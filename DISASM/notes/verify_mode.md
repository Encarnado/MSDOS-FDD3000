# MODE.COM: verification of `mode_findings.md` (2026-11-08)

Read-only pass. Sources: `project/MSDOS/poc/MODE.ASM` (350 lines),
`symbols/x86/MODE.LST`, `BIOS.ASM` (T_I14 / I14X, lines 795-840), `I86.ASM`
(SSET 154-189, I14RD / SAVED 219-242, I14EXT / I14INI 333-389),
`test_fdd86.py` group 9, `fdd86.WD2123`, the poc README (serial and MODE
sections), `DISASM/asm/mode.asm`, `z86_bios.asm`, and IBM's PC MODE 1.10
(`v1.25/bin/MODE.COM`, disassembled with ndisasm to compare finding 5).
All four MODE.COM copies (`binaries/x86`, `binaries/disk/files`,
`DISASM/bin`, `poc/build`) have the same MD5 (d3bed820...).

Experiments (run on the emulator; the scripts are not kept in the repository):
- `exp.py`: 24 command lines on `fdd86` with `test_fdd86.booted` / `step`,
  showing the channel A model state (mode / baud / command) before and after,
  plus a .COM that calls INT 14h F1h with CL = 16 and CL = 255.
- `exp2.py`: logs every write to ports 81h / 41h / 10h / 11h per command.
- `exp3.py`: a .COM that calls F1h with AL = 0Eh (stop-bit code 00), then MODE.

## 1. Summary

| # | Title | Class | Sev. | Fix |
|---|---|---|---|---|
| 1 | Reads the BIOS's copy (SAVED), never the chip | NOTE | - | no |
| 2 | Read-modify-write of the mode byte | NOTE | - | no |
| 3 | Nothing changes until the whole line has parsed | NOTE | - | no |
| 4 | Every set is a full channel reset, with no wait for the transmitter | DESIGN (effect: HW) | low | no (leave) |
| 5 | Comma after the port = empty baud; `MODE PRN,,E` refused | NOTE (correct) | - | no (an optional test) |
| 6 | Trailing comma accepted | NOTE | - | no |
| 7 | Parity / stop fields are one character (`NONE` refused) | DESIGN | low | no (leave) |
| 8 | STOPS "?" for code 00 is "unreachable" ("sync mode") | **INVALID** | low | comment fix in `DISASM/asm/mode.asm` |
| 9 | SHOW names by channel (COM1 shows as "PRN:") | DESIGN | low | no (leave) |
| 10 | Idioms (OR SP,SP, fall into PUTS, BAD1 relay) | NOTE | - | no |
| 11 | The upper-casing writes 0 over the CR, never reaches 0100h | NOTE | - | no |
| 12 | FDD3000-only INT 14h calls, no check | NOTE | - | no |
| 13 | Baud rates come from the datasheet, not a measurement | HW | low | no |
| SC | "MODE.ASM's comments accurate; none wrong" | DOC (claim overstated) | low | yes (comments) |
| CV1 | I14X: F1h with CL >= 16 does nothing, AX unchanged | DOC | low | yes (README, optional) |
| CV2 | edit uses `DOS_PRINT`, iosys `DOS_PRTSTR` | **INVALID** | - | no (stale note) |
| CV3 | Older banners say "N/7" | **INVALID** | - | no (stale note) |
| N1 | BIOS.ASM's T_I14 header says I14X is "in I86.ASM" | DOC | low | yes (comment) |
| N2 | INT 14h F1h passes stop-bit code 00 (8251A "invalid") to the chip | DESIGN (BIOS; effect HW) | low | leave for author |
| N3 | Stricter than PC MODE: `NONE`, the `,P` field, 2-letter baud prefixes | NOTE | - | no |

No BUG was found in MODE.COM. Neither the findings nor this pass need a code change.

## 2. Per finding

### 1. MODE reads the BIOS's copy, never the chip: NOTE
SETS (MODE.ASM 123-127, LST 0384h) and SHOW (271-273, LST 04B7h) both use
INT 14h AH=F0h. BIOS.ASM 826-828 sends F0h to I14RD (I86.ASM 226-237), which
returns `SAVED` (channel A at +0, B at +1, baud codes at +2/+3). SSET writes
SAVED (I86.ASM 176-183) because the WD2123 can't be read back. Exp3 confirms
this: after the model chip took mode 0Eh, MODE showed exactly what SAVED held.
Correct.

### 2. Read-modify-write of the mode byte: NOTE
MODE.ASM 155-196: AND CFh / F3h / 3Fh, then OR the field. Data = (digit-'5')<<2,
stop 40h / 80h / C0h, parity 00 / 10h / 30h. I14X (BIOS.ASM 834-836) does
`AND 0FCh / OR 2`. test_fdd86.py 614-620 expects 4Eh, FAh, 5Eh, 92h, 46h.
In exp.py every partial set kept the other fields (`MODE COM1:,,7`: 9Eh ->
9Ah). Correct.

### 3. No change before the whole line has parsed: NOTE
Every error path goes to BAD (MODE.ASM 116-119) / BAD1 (199), and all of them
come before SETX (200). test_fdd86.py 627-631 has the nine lines the finding
names. Exp.py added 9 more refused lines (`PRN,,E`, `COM1:,,E`, `PRN,9600`,
`PRN 960`, `PRN ,NONE`, `PRN 9600 E`, `PRN ,,,1.`, `PRN 9600,N,8,1,`,
`LPT2`). None changed the model. Correct.

### 4. Every successful set is a full reset: DESIGN, low (the effect is HW)
Exp2: `MODE PRN 1200` on a 1200 channel writes `81:00 81:00 81:00 81:40
81:8E 81:07 10:08`. `MODE AUX ,` (no field at all) does the same on
41h/11h. `MODE PRN` (show) writes nothing. Correct as stated. Two more
details: the reset also leaves command 07h (RTS off, error flags cleared),
and the 8251A drops a received byte that was waiting. What an internal reset
does to a character still shifting out can only be measured on the chip. In
practice MODE runs after COMMAND has loaded it from disk, which takes far
longer than one character even at 50 baud. **Recommendation: leave.** If the
author ever wants a fix, it belongs in SSET (wait for TxEMPTY before the
40h), not in MODE.

### 5. Comma after the port = empty baud field: NOTE (the behaviour is correct)
Code: SETS tests `[SI]=','` (MODE.ASM 128-129) before reading a baud. Exp.py:

```
'MODE PRN,,E'    8E -> 8E  Invalid parameter
'MODE PRN,E'     8E -> BE  PRN: 1200 baud, even parity, 8 data bits, 1.5 stop bits
'MODE PRN ,O'    BE -> 9E  (odd parity)
'MODE COM1:,,E'  Invalid parameter
'MODE COM1:,,7'  9E -> 9A   (7 data bits)
'MODE PRN,9600'  Invalid parameter   ('9' lands in the parity field)
```

**Decision: correct, not a bug.** The documented syntax (MODE.ASM 3, the
usage at 60, README 660, the volume header) is
`port[:] [baud][,[parity][,[data bits][,stop bits]]]`. The port ends at the
colon or blank, so the first comma closes the (empty) baud field, the second
the (empty) parity field, and `E` sits in data bits. A data-bits `E` is
invalid, and saying so is right. PC MODE uses the same positional reading.
In IBM PC MODE 1.10 (disassembly 0A27h-0AB7h, field reader 0918h), the text
after `COMn:` is split at commas: field 1 = baud (up to 4 chars into 0909h),
then parity 090Eh, data 0910h, stop 0912h. So on the PC, `MODE COM1:,,E`
also puts E in data bits. The PC actually rejects it earlier, for the empty
baud: 0909h starts as four blanks, matches nothing in the `1115306012244896`
table, and gets "Invalid baud rate specified". (PC MODE 1.10 needs a baud.
It also quietly turns a bad data field into 7 bits, so `MODE COM1:96,,E`
gives 9600,e,7 there.) Reading "the first comma separates port and baud"
would break the documented `MODE COM1:,E` = parity-only form and contradict
the README's example. Optional test (no fix needed): add `'MODE PRN,,E'` to
the bad list in test_fdd86.py 627 and `('MODE PRN,E', A, ...)` to the good
list, so the documented reading stays locked down.

### 6. Trailing comma accepted: NOTE
Exp.py: `MODE PRN 9600,` -> baud 0Eh, accepted. In COMMA, `CMP AL,","` with
AL=0 sets CF, but the `OR AL,AL` right after clears it, so PAR sees ZF=1 CF=0
and DBITS' COMMA returns CF=1 -> SETX. Correct. `MODE PRN ,` is accepted too:
a reset with nothing changed (finding 4).

### 7. Parity / stop fields are one character: DESIGN, low
Exp.py: `MODE PRN ,NONE` is refused, `MODE PRN ,,,1.` is refused, `1.5` is
accepted. PC MODE 1.10 differs: its field reader keeps the first character
and skips the rest up to the comma, so `NONE` works there. The usage text
(`[N|O|E]`, `[1|1.5|2]`) documents the strict form. **Leave.**

### 8. STOPS "?" for code 00 is unreachable: INVALID
Two parts are wrong:
- **"sync mode"**: on the 8251A, bits 1-0 = 00 selects sync. Bits 7-6 = 00
  in async mode is the datasheet's "invalid" stop-bit setting. I14X forces
  bits 1-0 to 10 (BIOS.ASM 834-836), so the chip is always async (exp3:
  model state `cmd`, not `sync`).
- **"Unreachable"**: MODE never makes code 00, but INT 14h F1h passes the
  caller's AL bits 7-6 through unchanged. Exp3 (a .COM doing F1h with
  AL=0Eh, CL=8):

```
'SYNC'          -> chip mode 0Eh, SAVED mode 0Eh
'MODE PRN'      PRN: 1200 baud, no parity, 8 data bits, ? stop bits
'MODE PRN 9600' PRN: 9600 baud, no parity, 8 data bits, ? stop bits   (00 kept)
'MODE PRN ,,,1' PRN: 9600 baud, no parity, 8 data bits, 1 stop bit
```

So the "?" entry is a useful guard, not dead data. MODE.ASM itself is fine.
The wrong text is in the volume: `DISASM/asm/mode.asm` 62-64, 180 and 319,
plus the findings file. Fix (comments only; the roundtrip is unaffected):

```diff
-;   - The STOPS table has a "?" for stop-bit code 00 (not a valid async
-;     mode); no path in MODE or the BIOS ever stores it (SSET's callers
-;     give 40h / 80h / C0h only).
+;   - The STOPS table has a "?" for stop-bit code 00 (the 8251A's
+;     "invalid" async setting).  MODE never makes it, but INT 14h F1h
+;     passes AL's bits 7-6 through, so another program can store it;
+;     MODE then shows "? stop bits" and keeps it on a partial set.
@@ 180
-;   bits 7-6  stop bits   01 = 1, 10 = 1.5, 11 = 2   (00: sync mode)
+;   bits 7-6  stop bits   01 = 1, 10 = 1.5, 11 = 2   (00: invalid)
@@ 319
-	db "?  1  1.52  "	; 00 "?" (sync - never stored), 01 "1",
+	db "?  1  1.52  "	; 00 "?" (invalid; only via F1h), 01 "1",
```

### 9. SHOW names channels by number: DESIGN, low
SHOW (MODE.ASM 275-278) picks PRNMSG / AUXMSG from CHAN alone. The test
expects `MODE COM1:,O` -> "PRN: ...". Since COM1 and PRN are the same
channel, naming DOS's device is defensible. **Leave.**

### 10. Idioms: NOTE
GETWX `OR SP,SP` (LST 04A7h) and `CMP AL,AL` (255) are correct. SHOW falls
into PUTS (334-337). COMMA's `JNZ BAD1` leaves a CALL frame behind, which
does no harm because INT 20h follows. BAD1 relay: the stop parser's `JNZ`
at about 0422h-0424h would need to reach BAD at 037Bh, about -169 bytes, out
of short range. So 199 is a near `JMP BAD`. Correct.

### 11. The 0 over the CR stays below 0100h: NOTE
COMMAND.COM 1.25 (build/COMMAND.ASM 205, 214) reads lines into a 128-byte
COMBUF. COMTAIL (772-781) copies only what follows the command name, so the
tail count is at most about 123 and the store lands at 81h+len <= FCh.
Correct for every line COMMAND survives. A batch line longer than 128 bytes
overruns COMBUF in COMMAND itself (READBAT, 732-744, has no limit). A
190-character `MODE` line in a .BAT crashed the machine before MODE ever ran
(exp.py: Z80Error in the interpreter). That is Microsoft's COMMAND, not MODE.

### 12. FDD3000-only: NOTE
On a PC BIOS, INT 14h AH>3 returns AX unchanged. SHOW would then print
nonsense (baud code F0h AND 15 = "50") and F1h would do nothing. Harmless.
MODE is part of this system only.

### 13. Baud rates from the datasheet: HW, low
BAUDS matches SSET's table (I86.ASM 154-156) and README 618-621. Whether the
FDD3000's crystal really is 1.8432 MHz, so that the rates are true, can only
be checked by measuring on the machine.

### SC. "MODE.ASM's comments accurate; none wrong": DOC, low (claim overstated)
- MODE.ASM 13-14, "(BIOS.ASM, I86.ASM's I14X)", reads as if I14X were in
  I86.ASM. It is in BIOS.ASM (826). I86.ASM holds I14RD, SAVED and SSET.
  The finding's point about "z86_bios.asm / z86_interp.asm" mixes up the
  disassembly volumes with the sources. In the source tree nothing moved
  files.
- MODE.ASM 8-9 leaves out the `134` alias (ABAUDS 43). README 666 and the
  volume header do list it.

Fix (comments only: MODE.COM unchanged, same line count, TERMZ80 unaffected):

```diff
-; baud: 50 75 110 134.5 150 200 300 600 1200 1800 2400 3600 4800 7200 9600
-; 19200, or the PC's 11 15 30 60 12 24 48 96 19. parity: N, O or E. data
-; bits: 5 to 8. stop bits: 1, 1.5 or 2. A setting left out stays as it
-; is. MODE with a port alone shows its settings, with no port both.
+; baud: 50 75 110 134.5 (or 134) 150 200 300 600 1200 1800 2400 3600 4800
+; 7200 9600 19200, or the PC's 11 15 30 60 12 24 48 96 19. parity: N, O or
+; E. data bits: 5 to 8. stop bits: 1, 1.5 or 2. A setting left out stays
+; as it is. MODE with a port alone shows its settings, with no port both.
@@
-; The settings go to the chip through INT 14H's FDD3000 calls (BIOS.ASM,
-; I86.ASM's I14X): F0H reads the mode byte and baud code the BIOS last
+; The settings go to the chip through INT 14H's FDD3000 calls (BIOS.ASM's
+; I14X, I86.ASM's I14RD and SSET): F0H reads the mode byte and baud code the BIOS last
```

(Rewrap the second hunk if the author keeps lines under 76 columns: it only
changes comments.)

### CV1. F1h with CL >= 16: AX unchanged: DOC, low
BIOS.ASM 830-832: `LD A,(R_CL) / CP 16 / RET NC`, before any write to R_AX.
Exp.py: AX=F177h, CL=16 -> F177h; CL=255 -> F177h; the model saw no write.
A valid F1h (AL=4Eh, CL=15) returned 6030h (status). Every other AH (5-EFh,
F2h+) and DX > 1 (T_I14 801-808) also return AX unchanged. That matches how
the PC BIOS treats undefined calls. MODE can't hit it (BAUDC is 0-15). An
optional README line (README 641-642, no binary change):

```diff
   the channel up from AL (mode byte; bits 1-0 are forced to the ×16 clock)
-  and CL (baud code 0-15) and returns the status.
+  and CL (baud code 0-15) and returns the status; with CL 16 or more (or
+  any other AH) nothing is done and AX comes back unchanged.
```

### CV2. "edit uses DOS_PRINT": INVALID
`DISASM/asm/edit.asm` 224 defines `DOS_PRTSTR equ 09h`, and nothing in
DISASM uses `DOS_PRINT` except this findings file.
`DISASM/dict/CONVENTIONS.md` 88 records the rename ("was DOS_PRINT in
edit"). Stale. Drop it from the findings file.

### CV3. "Older banners say N/7": INVALID
All banners already read "/10": boot 1/10, z86* 2/10, cpmz80 3/10, iosys
4/10, format 5/10, cpmcom 6/10, edit 7/10, mode 8/10, term 9/10, termz80
10/10. Stale.

## 3. New findings

### N1. BIOS.ASM's T_I14 header misplaces I14X: DOC, low
BIOS.ASM 798-799: "F0h and F1h read and set ... (I14X, in I86.ASM)". I14X is
eight lines further down in BIOS.ASM itself (826). Fix (comment only: Z86.SYS
bytes unchanged, TERMZ80 image unchanged):

```diff
-; byte and baud code (I14X, in I86.ASM). Returns AH = line status (bit 7:
+; byte and baud code (I14X, below). Returns AH = line status (bit 7:
```

### N2. INT 14h F1h accepts stop-bit code 00: DESIGN (BIOS), low; effect HW
I14X forces only bits 1-0. Bits 7-6 = 00 goes to the chip as the 8251A's
"invalid" async stop setting, and SAVED keeps it (exp3). What the WD2123
then sends can only be found out on the hardware. MODE copes: it shows "?",
and `,,,1` repairs it. A guard in I14X (`AND 0FCh / OR 2`, then force 40h
when bits 7-6 = 00) would grow BIOS code next to T_I14. That changes Z86.SYS
and might shift addresses other parts rely on. **Leave for the author.** At
most, say in README's F1h line that AL bits 7-6 must be 01, 10 or 11.

### N3. Stricter than PC MODE: NOTE
Compared with PC MODE 1.10: `NONE` / `EVEN` are refused (the PC keeps the
first letter); a 5th field (PC's retry `,P`) is refused; baud must be an
exact name (`9600` or `96`, not `960` or `9601`), while the PC compares only
the first two characters. On the other hand, the baud may be left out here
(the PC demands it), and unspecified fields keep their value (the PC
defaults them to e,7,1). Each difference is consistent with MODE's own
usage text. Nothing to do.

No MODE.COM code bug was found. Also checked and correct: GETW's length
limit (exactly 4 / 6 characters accepted, 5 / 7 refused); `1.5` peeking
can't read past the 0 terminator; CHAN's high byte stays 0 (`MOV BYTE PTR`
into a DW initialised to 0); `INC [CHAN]` is a word INC; SHOW's
MUL-indexed tables (BAUDS x6 with `AND BH,15`, STOPS x3); tabs between
fields (`MODE PRN\t9600`) accepted; lower case accepted.

## 4. Recommended fixes, in priority order

None is a behaviour fix. All are text:

1. `DISASM/asm/mode.asm` 62-64, 180, 319 and `mode_findings.md` item 8:
   stop code 00 is "invalid", not "sync", and F1h can store it (finding 8).
2. `mode_findings.md`: delete the stale cross-volume notes CV2 (DOS_PRINT)
   and CV3 (banners), and correct "Source comments".
3. BIOS.ASM 799: "(I14X, below)" (N1). Comment only.
4. MODE.ASM 8-14: the `134` alias and I14X's real home (SC). Comment
   only, MODE.COM unchanged.
5. README 641-642: F1h with CL >= 16 does nothing (CV1). Optionally also
   the bits 7-6 rule (N2).
6. Optional test lock-in: add `MODE PRN,,E` (bad) and `MODE PRN,E`
   (parity only) to test_fdd86.py group 9 (finding 5).

None of these changes MODE.COM, Z86.SYS or the TERMZ80 image, so TERM.COM
needs no rebuild.
