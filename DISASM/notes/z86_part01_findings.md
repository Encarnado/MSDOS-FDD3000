# Z86.SYS part 01 (D000h-D7FFh) — findings (2026-11-08)

Gate: `python3 tools/z86parts.py check 1` PASS. lint: 0 errors, 91.5% of
instruction lines commented. The 3 CRYPTIC warnings are INC16 / DEC16 / LOGF16:
these are global author names, kept on purpose.
Renames: 27 local labels (SPF SP1 SP2 SG1 SG2 SS1 I14E1 I14I1 I14S1 S16R0-7
S16R0A S16R1A S8R0-7). None of them appears outside part 01 in Z86.SYS.lst or CPMZ80.lst.
New equates (part 01): ACOM SIOWORD IOERR SIORESET IOMASK RXRDY SIOERRS SIO_X16.

1. **16-bit INC/DEC always clear AF.** INC16/DEC16 (D580h/D58Ch) put the 8086
   CF back with `RRA`, and RRA resets the Z80's H and N flags. So after 40h-4Fh and
   FF /0 /1, AF is always 0. cpu86.py sets AF on a nibble carry or borrow
   (`af = ((v ^ 1 ^ res) >> 4) & 1`). The I86.ASM header says "AF after 16-bit
   add/subtract/inc/dec is the Z80's (carry from bit 11)". That is right for the
   WCORE ADD/ADC/SUB/SBB/CMP slots and wrong for INC/DEC. The header is now
   annotated. *verified (code + Z80 RRA flag rules + cpu86.py).* Effect: only
   on a DAA/DAS/AAA/AAS or a PUSHF/LAHF that follows a 16-bit INC/DEC of xxxFh
   (or a DEC of xxx0h). Not likely to matter to DOS.
2. **RTS is not "on only while a byte is awaited".** poc/README.md and the SGET
   source comment both say it is. But SPUT writes SIOWORD (27h, with RTS) and
   never drops it. SGET's timeout exit (INT 14h AH=2) also leaves RTS on. SERR's
   IOERR (37h) raises RTS too, so SLSTS can turn RTS back on after an SGET
   dropped it. Only a successful SGET ends with ACOM (RTS off). *verified (code).*
3. **CBIOS calls status bit 7 "CTS"; the 8251A's bit 7 is DSR.** In CBIOS
   A1.1 PUN: "espera cts low e thr empty" on `and 81h`. I86.ASM reads the same bit
   as DSR (the 8251A datasheet assignment). How the FDD3000 wires it to
   its connectors is unknown. *provisional (no WD2123 pinout/hardware check).*
4. **SSET's 00 00 00 40h reset is stronger than CBIOS.** CBIOS INITRS writes the
   mode and command straight away and assumes a chip fresh from power-up. SSET
   first completes any pending mode or sync-character sequence (three dummy bytes), then
   resets the chip internally (40h). COLD's mode 8Eh = x16, 8 bits, no parity, 1.5 stop is
   CBIOS SIOTAB's 02h+0Ch+00h+00h+80h. Baud code 8 = 1200 is also SIOTAB's.
   *verified (code + CBIOS source).*
5. **SERR and BRKDET.** SIOERRS (78h) includes bit 6 (SYNDET/BRKDET). ER does not
   clear BRKDET, which follows the line, so during a break SERR writes IOERR on every
   call (on every poll in SGET). This is harmless. *verified (code); 8251A behaviour
   from the datasheet, provisional on the WD2123.*
6. **SWAIT semantics.** HL = 0 means unlimited (never decremented). HL = n allows
   exactly n polls. BIOS passes FFFFh, which is 65535 polls. On timeout A = 0 and CF = 1, so
   I14GET reports AL = 0. *verified (code).*
7. **I14EXT with CL >= 9 returns without a status.** AH/AL are left
   as the caller set them. A PC BIOS returns the port status. Stick parity (BH = 3, 4)
   gives no parity. *verified (code).*
8. **I14INI parity "10" = none.** AL bits 4-3 are doubled into the mode's PEN/EP.
   With 10, EP is set without PEN, which an 8251A ignores. This matches the PC
   (x0 = none). *verified.*
9. **I14SET's page-carry guard is dead.** BAUDT is at D0E8h-D0F0h, so
   `JR NC / INC H` never takes the INC. *verified (addresses).*
10. **OPLO/OPHI aliases follow the 8086.** 60h-6Fh go to the 70h-7Fh Jcc
    handlers, 82h to O_GRP80, C0h/C1h to RET Iw/RET and C8h/C9h to RETF Iw/RETF,
    and D6h to SALC. 9Bh WAIT is a NOP. D8h-DFh ESC skip their ModR/M. IN returns FFh and OUT is ignored
    (O_INB/O_INDXB, O_OUTI, and EEh/EFh go straight to O_NOP). This all matches cpu86.py
    `_build()` and its default port hooks. **F1h → O_BAD**: a real 8086 treats F1h as a
    LOCK alias. cpu86.py also leaves F1h as op_bad, so the two models agree and
    differ from silicon. *verified (code + cpu86.py).*
11. **3Ch has its own handler.** O_CMPAL inlines the CMP slot (the most
    common ALU opcode in DOS code), and so skips the self-modifying path. *verified.*
12. **EALO/EAHI C0h-FFh are never indexed.** Every caller of EAMEM
    (MRW, MRB, EAW, EAB, O_LEA) tests `CP 0C0h` first. O_LEA zeroes EADS and EASS
    around its CALL EAMEM to get the bare offset. *verified (listing).*
13. **Slot scheme.** BCORE takes (op AND 38h) x2 = op x 16, WCORE x4 = op x 32, and SHPG
    (ModR/M AND 38h) x2, with OR 80h for byte operands. Each value is stored into the low byte of a `JP xx00h`.
    This works only because each block is page-aligned. The DEFS between
    slots and the page pads (D5FBh-D5FFh, D7F8h-D7FFh) are zero and never executed.
    *verified.*
14. **SHPG k = 6 is SHL.** This is the same as cpu86.py (`k == 4 or k == 6`). CL is not masked
    (counts up to 255 loop), as on an 8086. Count 0 is filtered out by SHB/SHW. *verified.*
15. **Code in a data page.** The serial routines (D03Eh-D0E0h) and INT 14h set-up
    (D5A2h-D5FAh) only use free page ends. BOOTJP's fixed D0FDh caps the
    REGS page: the serial code cannot grow past D0FCh. *verified.*
