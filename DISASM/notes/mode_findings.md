# MODE.COM — findings (2026-11-08)

Gate: PASS (byte-identical, `nasm -O0 -f bin`, `tools/roundtrip.sh mode`).
Every byte agrees with `symbols/x86/MODE.LST` (0100h-055Eh, 1 119 bytes).
Partition: data 0103h-030Ah (variables, PORTS, BAUDS, ABAUDS, messages,
STOPS, USEMSG), code 030Bh-055Eh. Author: João Encarnado, for the
FDD3000-MSDOS project (2026). Not Microsoft code: the MODE.COM in
Microsoft's v1.25/bin is IBM's PC MODE 1.10, an unrelated program.

Hardware: **not run on a real FDD3000.** The merged 2026-11-08 build that
contains MODE.COM (and INT 14h F0h / F1h) has never been booted on the
machine; `notes/hardware_run.md` covers the 2026-11-07 build, without MODE.
Whether João ran MODE on hardware is not recorded (the poc README's serial
section ends "nothing has been tried on the hardware"). Everything below is
verified against code + source + emulator tests only.

1. **MODE reads the BIOS's copy, never the chip.** Both reads (SETS, SHOW)
   are INT 14h AH=F0h -> IO.SYS INT14 stub (TRAP TRAP_INT14 / RETF 2) ->
   T_I14 -> I14X -> I14RD, which returns SAVED (z86_interp.asm), the copy
   SSET keeps because the WD2123's mode and baud registers are write-only.
   The line printed after a change is that copy re-read, not a readback of
   the hardware. *verified (code + MODE.ASM + z86_bios/z86_interp).*
2. **Read-modify-write of the 8251A mode byte.** SETS starts from F0h's
   AL / AH; each field replaces only its bits: parity 5-4 (AND CFh, N 00 /
   O 10h / E 30h), data 3-2 (AND F3h, digit - '5' << 2), stop 7-6 (AND 3Fh,
   1 40h / 1.5 80h / 2 C0h). Bits 1-0 (clock) are passed through; I14X
   forces them to 10b (x16) anyway. Encodings agree with the 8251A table in
   SSET's header and with test_fdd86.py group 9's expected bytes (4Eh, FAh,
   5Eh, 92h, 46h). *verified (code + source + test).*
3. **No change before the whole line has parsed.** All error exits go to
   BAD (usage + INT 20h) before SETX's F1h. test_fdd86.py checks nine bad
   lines (`COM3`, `9601`, `,X`, `,9`, `,3`, a fifth field, `1.4`, `PRNTR`,
   `1234567`) leave both channels unchanged. *verified (code + test).*
4. **Every successful set is a full channel reset.** F1h -> SSET: 00h 00h
   00h 40h, mode, command ACOM, baud register — even when the values are
   unchanged (`MODE PRN 1200` on a 1200 channel). MODE does not wait for
   the transmitter to empty first. *code verified; the effect on a
   character still shifting out is provisional (never tested, on the model
   or hardware).*
5. **Comma after the port = empty baud field.** SETS tests `[SI] = ','`
   before reading a rate, so `MODE COM1:,O` / `MODE COM1 ,O` set parity
   only (tested: `MODE COM1:,O`). Consequence: `MODE PRN,,E` is refused —
   first comma ends the empty baud field, second the empty parity field,
   and `E` lands in data bits. Consistent with the documented syntax, but
   unlike a reading where the first comma separates port and baud.
   *verified (code trace; the `,,E` case not in the tests).*
6. **A trailing comma is accepted.** `MODE PRN 9600,` -> COMMA sees ',' then
   the end, returns ZF=1 (empty field), DBITS' COMMA then CF=1 -> SETX.
   Harmless. *verified (code trace).*
7. **Parity and stop fields are one token.** Only the first letter is
   consumed (`NONE` fails at the next COMMA on `O`); `1.5` is matched by
   peeking `[SI+1]='.'`, `[SI+2]='5'`. *verified (code; `1.4` in test).*
8. **STOPS has a "?" entry for stop code 00** (sync mode). Unreachable: MODE
   stores 40h/80h/C0h only, COLD 8Eh, I14INI 40h or C0h. *verified (code).*
9. **SHOW names channels by number, not by what was typed**: COM1/LPT1 show
   as "PRN:", COM2 as "AUX:" (test expects `MODE COM1:,O` -> "PRN: ...").
   *verified (code + test).*
10. **Idioms worth knowing.** GETW returns ZF=0 with `OR SP,SP` (SP never 0)
    and ZF=1 with `CMP AL,AL`; SHOW falls into PUTS so PUTS's RET ends
    SHOW; COMMA jumps to BAD from inside a CALL, abandoning the return
    address (fine: INT 20h follows). `BAD1` is a near-JMP relay because BAD
    is out of short range from the stop-bits parser. *verified (code).*
11. **The upper-casing writes a 0 over the tail's CR** at 81h+len. The tail
    plus CR fits in 81h-FFh, so the store never reaches 0100h. *verified
    (PSP layout).*
12. **FDD3000-only.** INT 14h AH=F0h / F1h are this BIOS's extensions; on an
    IBM PC they are undefined, and MODE makes no check. Not a bug for its
    purpose; noted. *verified (code); PC behaviour not examined.*
13. **Baud rates are the datasheet's** for the 1.8432 MHz crystal at x16
    (poc README); the BAUDS text is what the user sees, not a measurement.
    *provisional (never measured on hardware).*

## Source comments

MODE.ASM's comments were found accurate; none wrong. Its header's
"BIOS.ASM, I86.ASM's I14X" now lives in z86_bios.asm (I14X follows T_I14)
and z86_interp.asm (I14RD, SAVED, SSET) — the poc README notes the merge
moved these into `;@SLACK` slot ends; a location note, not an error.

## Cross-volume

- z86_bios.asm I14X: F1h with CL >= 16 returns with nothing done and AX
  unchanged (AH still F1h). MODE never sends it (BAUDC is 0-15 from F0h or
  the tables). Worth a line in any INT 14h documentation.
- DOS function-name equates differ across 8086 volumes: iosys uses
  `DOS_PRTSTR` (09h), edit uses `DOS_PRINT`. MODE follows iosys
  (`DOS_PRTSTR`) and adds `DOS_CONOUT` (02h, MSDOS.LST's CONOUT).
- Volume numbering: earlier volumes' banners say "N/7"; this one is "8/10"
  as instructed. The older banners may need updating to "/10".
