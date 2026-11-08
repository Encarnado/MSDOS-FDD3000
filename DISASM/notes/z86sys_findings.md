# Z86.SYS — findings index (joined 2026-11-08)

Volume preface: asm/z86sys.asm. Per-region notes (each written by the region's pass, evidence inline):

- [part 01](z86_part01_findings.md) — Z86.SYS part 01 (D000h-D7FFh) — findings (2026-11-08)
- [part 02](z86_part02_findings.md) — Z86.SYS part 02 (D800h-DBB1h): findings
- [part 03](z86_part03_findings.md) — Z86.SYS part 03 (DBB2h-DFF7h, O_DAA .. O_POP8F): findings (2026-11-08)
- [part 04](z86_part04_findings.md) — Z86.SYS part 04 (DFF8h-E416h) - findings
- [part 05](z86_part05_findings.md) — Z86.SYS part 05 findings (E417h-E805h: O_MOVI_AL .. O_JMPF)
- [part 06](z86_part06_findings.md) — Z86.SYS part 06 (E806h-EB45h, O_CMC .. ENDCODE): findings
- [part 07](z86_part07_findings.md) — Z86.SYS part 07 (EB46h-EDDBh: TRAP .. WRSEC) — findings (2026-11-08)
- [part 08](z86_part08_findings.md) — Z86.SYS part 08 (EDDCh-F220h: FDCCMD to BIOSEND) - findings (2026-11-08)

Cross-region items settled at the join:
- Duplicate-equate risk (parts 07/08): none at join; RDSCMD/WRSCMD/WSTA/KEYRDY/LINKERR defined once (part 07).
- Serial equates (part 01) used by 07/08 throughout; no raw port operands remain (lint).
- 19 source comments on label-only lines were dropped by the skeleton generator (fixed in z80dis.py); all 19 sites carry equivalent commentary after the pass (checked).
- LED polarity: boot_findings item 7 (bit 7 active low), agreeing with part 08.
- Shift groups D0h-D3h live in part 05 (the plan had them in 06); narrated there.
- Corrections for the package docs: OVERVIEW 2.2 AF sentence (INC/DEC -> AF = 0; AF also read by PUSHF/LAHF/INT); DISASSEMBLY_GUIDE seeds (G3BT/G3WT/G5T, LD IX targets); fdd86.py bad-opcode address off by one (part 02).

## Fixed 2026-11-08 (floppy robustness; git: "BIOS: floppy timeouts")
- No timeout on FDC waits (part 08: FDCCMD; part 07: transfer loops) - fixed:
  FDCCMD, FHOME and XFER's first-byte wait time out after ~3 s -> FDTOUT
  (Force Interrupt, A = 20h -> DOS "Not ready").  test_fdtimeout.py with the
  new realistic `machine.FDC.no_index` model: before, DOS hung on DIR B:; now
  "Not ready error reading drive B" after ~9.7 s of Z80 time (DOS 1.25 tries
  FAT 1, FAT 2, FAT 1).
- Retries never moved the head (part 07) - fixed: SECTIO restores half-way.
- Residual (documented): FORMAT TRACK's write-track loop is not timed; a disk
  pulled while the motor runs still hangs it.  The seek before it is timed.

## Merge with João Encarnado's serial / terminal work (2026-11-08)
- His package (MODE.COM, TERM.COM + TERMZ80, INT 14h F0h/F1h, CTS) merged
  onto this branch (git: incoming/joao). Space: his ;@FILL page-end code met
  this branch's ;@SLACK page-end code; resolved by moving I14X into the BIOS,
  I14RD / SAVED / FDTOUT into free ALU slot ends, and removing the dead RADVS.
- All his tests pass on the merged build (test_term.py: flow control, log,
  XMODEM both ways, /52, /80), as do all of ours.
- Not yet disassembled: MODE.COM, TERM.COM, TERMZ80.BIN (new binaries).
