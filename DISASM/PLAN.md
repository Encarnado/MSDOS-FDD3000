# DISASM — plan and status

Commented, byte-identical disassemblies of the FDD3000-MSDOS binaries in the voice
of the TC3256 corpus (ROMDIS / TOSDIS). Rules: `dict/CONVENTIONS.md`.
Gate: `tools/roundtrip.sh`.

```
asm/    the volumes (masters once installed)    bin/   reference binaries (copies)
dict/   conventions + dictionary                 notes/ findings, hashes
tools/  z80decode.py z80dis.py images.py roundtrip.sh   build/ disposable
```

| # | Volume | Binary | State |
|---|---|---|---|
| 1 | `boot.asm` | BOOT.BIN (254 B, Z80 @3F00h) | ✅ narrated, gate PASS |
| 2 | `z86sys.asm` (+ `z86_interp.asm`, `z86_bios.asm`) | Z86.SYS (8 737 B, Z80 @D000h) | ✅ narrated (8 regions in parallel, joined), gate PASS, lint 0 errors, 87.8% commented |
| 3 | `cpmz80.asm` | CPMZ80.BIN (2 506 B, Z80 @F12Ch) | ✅ narrated, gate PASS, 89.5% commented |
| 4 | `iosys.asm` | IO.SYS (332 B, 8086) | ✅ narrated, gate PASS, 92% commented |
| 5 | `format.asm` | FORMAT.COM (1 628 B) | ✅ narrated, gate PASS, 98% commented |
| 6 | `cpmcom.asm` | CPM.COM (3 286 B; Z80 image from 03FCh) | ✅ narrated, gate PASS, 88% commented |
| 7 | `edit.asm` | EDIT.COM (4 653 B) | ✅ narrated, gate PASS, 96% commented |
| 8 | `mode.asm` | MODE.COM (1 119 B, 8086; João Encarnado) | ✅ narrated, gate PASS, 94% commented |
| 9 | `term.asm` | TERM.COM (6 679 B, 8086 + TERMZ80 image; João Encarnado) | ✅ narrated, gate PASS, 86% commented |
| 10 | `termz80.asm` | TERMZ80.BIN (3 468 B, Z80 @F12Ch; João Encarnado) | ✅ narrated, gate PASS, 93% commented |
| — | MSDOS.SYS / COMMAND.COM | Microsoft | short note only (public listings) |

## Done 2026-11-08
- Workspace, disassembler (independent decode + listing reconcile), gate.
- All three Z80 images round-trip byte-identical from skeletons.
- Partition proven; guide seed omissions and dead code found
  (`notes/partition_findings.md`).
- New z80asm hazard found and fenced (register-lexing, CONVENTIONS rule 3).
- Volume 1 complete (`notes/boot_findings.md`).

## Status 2026-11-08
Ten volumes (João Encarnado's MODE / TERM / TERMZ80 added after the merge); gate 10/10.
All 7 volumes narrated; gate 7/7 byte-identical; lint 0 errors. Real-hardware run folded in
(notes/hardware_run.md). Package doc corrections: notes/doc_corrections.md.

## Next (was)
1. ~~Z86.SYS narration~~ done; findings in notes/z86sys_findings.md. Was: Z86.SYS narration, by region: REGS page + serial; split tables; BCORE/WCORE/SHPG;
   START/NEXT/prefixes; handlers D83B-EB45 (in groups); TRAP + TTAB; BIOS
   console/disk/serial/clock/PC-BIOS; COLD. Symbolic split tables
   (`defb EA20&0FFh` style already in skeleton), SMC targets written as slot
   expressions, RADVS marked dead.
2. CPMZ80 narration (BDTAB / BIOSV decoded inline; overlay contract with trap 1Ch).
3. `tools/lint.py` (rule 3 guard, raw literals, auto/numbered labels, coverage).
4. 8086 volumes once NASM is installed.
