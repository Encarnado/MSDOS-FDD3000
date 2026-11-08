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
- Shift groups D0h-D3h live in part 05 (brief misplaced them in 06); narrated there.
- Corrections for the package docs: OVERVIEW 2.2 AF sentence (INC/DEC -> AF = 0; AF also read by PUSHF/LAHF/INT); DISASSEMBLY_GUIDE seeds (G3BT/G3WT/G5T, LD IX targets); fdd86.py bad-opcode address off by one (part 02).
