# CPM.COM — findings (2026-11-08)

Gate: PASS (`tools/roundtrip.sh cpmcom`, NASM -O0, byte-identical to bin/CPM.COM).
The 8086 part (0100h-03FBh) matches `../symbols/x86/CPM.LST` instruction for instruction;
the labels sit at the addresses CPM.COM.sym gives. The 16-byte header at 03FCh is
written as named DW fields (length = `Z80_CODE_END-Z80_CODE`, then NEXT JPHL PEEKEY
GETKEY CONOUT DCSP ENDBIOS as equates checked against `../symbols/z80/Z86.SYS.sym`:
D83B EB60 EBF6 EC13 EC21 F12A F12C). The 2506 bytes from file offset 030Ch to the end are
bin/CPMZ80.BIN, byte for byte (checked with cmp), and are now `incbin "bin/CPMZ80.BIN"`.
No bytes follow the image. Comment coverage about 93% of instruction lines (119/128). Three
numbered locals were renamed (SKIP1, TAIL0, TC1).

Hardware: notes/hardware_run.md (2026-11-07, real FDD3000, TT3000 terminal) reports
"CPM (a CP/M program under CPM.COM) worked". So CPM.COM and its Z80 part running natively
are **verified on real hardware** (one machine; which program is not recorded). The error
paths (usage, not found, too big, mismatch) were exercised only in the emulator
(test_fdd86.py group 6). No item in this volume remains HW-PENDING.

## Cross-volume: where COMMAND's resident part sits (resolved)

1. **COMMAND 1.17 here is the HIGHMEM build. Its resident part is above TOP (PSP offset 2),
   outside the swap.** COMMAND.LST line 24: `HIGHMEM EQU TRUE ;Run resident part above
   transient (high memory)`. At CONPROC (lines 792-810) COMMAND takes DS:[2], subtracts the
   resident size, stores the result back in [2], moves the resident part there, and sets
   MEMSIZ to it and TRNSEG = MEMSIZ - TRNLEN. HAVCOM (line 612-613) gives every program
   PSP:[2] = MEMSIZ. The banner "Command v. 1.17H" (README line 53) is this build's mark.
   - Right: CPM.ASM's CHKSZ comment ("COMMAND's resident part is above it"), the
     README ("COMMAND's resident part, above that, is left alone"; "Abort, Retry, Ignore
     comes from COMMAND's resident part, which is in place"), and OVERVIEW "Problems found"
     (TOP must come from the PSP).
   - Wrong: CPMZ80.ASM's header / T_CPM register comment ("BX = SWLEN ... DOS, COMMAND and
     CPM.COM are below"), OVERVIEW 2.6 ("the bottom of memory (where DOS, COMMAND and
     CPM.COM live)"), and the conclusion of notes/cpmz80_findings.md's side note, which
     assumed the non-HIGHMEM layout ("the resident part follows DOS").
   - What the swap does overwrite is COMMAND's **transient** part, at TRNSEG just below TOP,
     inside SAVE. COMMAND checksums it and reloads it after the exit (README: "exits to
     COMMAND, which reloads its transient part").
   *verified (COMMAND.LST + CPM.ASM + code; consistent with the README's measured layout).*
   Action for volume 3: the side note and the "DOS, COMMAND and CPM.COM" wording in
   cpmz80.asm should say "DOS and CPM.COM".

## Design points confirmed (code + source)

2. **Memory layout (CHKSZ).** SWLEN = BASE + STGOFF (STGOFF = 03FCh+15 AND FFF0h = 0400h);
   TOP = [PSP:2]×16; P = (TOP − 200h − SWLEN) AND FF00h, so the P area and SAVE (a
   copy of 0000h-SWLEN) fit under TOP. All the arithmetic is 16-bit and linear, which
   works only because the 8086 memory ends below 64 KB (D000h). With the README's figures
   (BASE 2400h, DOSLEN 2500h = 9.25 KB, TOP CBA0h) this gives SWLEN 2800h and P = A100h,
   the documented TPA 0100h-A0FFh. *verified (arithmetic).*
3. **Paragraph rounding exists for CPMZ80's swap.** XCHGA/XCHGD swap 8 bytes per turn and
   test the count only every 8th byte (volume 3, finding 4). STGOFF and BASE are multiples
   of 16, so SWLEN is too. *verified.*
4. **The order: load the Z80 part first, then look for the program.** Trap 1Ch (BP ≠ 0) runs
   before the program is opened. The copy lands over COLD, which is dead after the boot, so
   stopping afterwards on "not found" / "too big" costs nothing. The program is then read
   over CPM.COM's own copy of the image (STGOFF 0400h). The first 4 header bytes
   (03FCh-03FFh) survive, unused. *verified.*
5. **CCP emulation.** The tail is everything after the program name, including the
   separating blank, upper-cased (a-z only). It is ≤126 bytes, so TAIL always keeps a 0
   terminator. FCB1/FCB2 come from DOS function 29h with AL=01h. In DOS 1.25, MAKEFCB
   writes exactly 16 bytes (drive, 11 name bytes, two zero words), which matches the
   16-byte slots in PARMS. '*' becomes '?' as in the CCP. A drive letter beyond NUMDRV
   gives AL=FFh and that result is ignored. DOS's separator set is not identical to the
   CCP's. *verified (code + MSDOS.LST); separator differences not enumerated.*
6. **.CPM before .COM.** An extension the user types is used as given. With none, .CPM is
   tried, then .COM (only the middle letter is patched: CPM → COM). *verified.*
7. **End of run.** T_CPM returns at warm boot with registers restored. CPM.COM then does
   AH=0Dh disk reset, which writes back DOS's dirty sector buffer, the safety net for
   volume 3 finding 7 (a CP/M close with drive byte 0 skips that write), and then INT 20h.
   *verified (code); the flush effect is from the DOS listing.*

## Edges and oddities

8. **The loadable maximum is smaller than the TPA.** The program is staged at SWLEN and
   must end at or below P, so bytes ≤ P − SWLEN. In the typical layout that is 7900h =
   30 976 bytes, while the program then runs in 0100h-P = 40 960 bytes. A CP/M program of
   31-40 KB would fit the TPA but is refused "Program too big". test_fdd86.py's BIG.CPM
   (40 000 bytes) is refused for this reason, although it is under 40 960. Staging just
   above SWLEN is what forces this. Staging in the would-be SAVE region is not possible
   because T_CPM fills SAVE before it moves the program down. *verified (arithmetic +
   emulator test).*
9. **The random block read's result is not checked.** After AH=27h, AL (1 = EOF with no
   data, 2 = DTA wrap, 3 = partial) is ignored. Reading exactly the size DOS reported should
   always give 0, but a disk error that the user answers with Ignore would run a partly
   loaded program. The staging DTA cannot wrap: 0400h + 7900h < 10000h. *verified (code).*
10. **`JMP MSG` is EB 3E 90.** At 025Dh MASM 1.10 met a forward reference without SHORT,
    reserved 3 bytes and emitted a short jump plus NOP (CPM.LST line 86). The other
    forward jumps to MSG say `JMP SHORT` and are 2 bytes. One byte wasted. *verified.*
11. **The program FCB is never closed.** That is harmless for a read in DOS 1.25, which has
    no handles to leak. *verified.*
12. **A zero-length program is not refused.** CX = 0 passes every check. T_CPM skips the
    move when PLEN = 0 (volume 3 guards its LDIR) and clears only page zero, so the jump to
    0100h runs whatever XCHGA brought down from SAVE: junk, most likely the old transient
    COMMAND. (CP/M's CCP is not known to refuse an empty .COM either; not checked.) *verified (code reading);
    not run. DOS 1.25's AH=27h with CX = 0 not traced: provisional.*
13. **Trap 1Ch's check is incomplete (from volume 3, finding 17).** The header covers 7
    addresses. This program's own arguments reach T_CPM through the REGS page (R_BX, R_CX,
    R_DX, R_SI, R_DI, R_AL at D000h-D00Fh), and CPMZ80 also calls SPRN, SAUXO, SAUXI and
    SLSTS (D03Eh-D085h). None of these is in the header. A Z86.SYS that moved only those
    would pass the check and fail at run time. The REGS layout is fixed by I86.ASM and has
    no reason to move. *verified (code); the risk is theoretical.*

## Fixed 2026-11-08
- 9 (the random block read's result not checked): FIXED - "Program read
  error". CPM.COM grew by 30 bytes: its CPMZ80 header is now at 041Ah (file
  offset 31Ah); the image is unchanged. test_cpm_smoke.py runs CPM HI.
