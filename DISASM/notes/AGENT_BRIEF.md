# Brief: narrate one region of Z86.SYS (parallel pass, 2026-11-08)

Work directly (no sub-agents). N below = your part number, given in your prompt.

## Context
Workspace: /Users/hugopinto/Developer/LOADZX/FDD3000-MSDOS/DISASM. It holds
commented, byte-identical disassemblies of the FDD3000-MSDOS binaries: MS-DOS 1.25
running on a Timex FDD3000's Z80 through an 8086 interpreter written in Z80. The voice
and rules come from the TC3256 corpus ("The Complete TMX Portugal ROM Disassemblies").

Read first, in this order:
1. `DISASM/dict/CONVENTIONS.md`: the rules (binding).
2. `DISASM/asm/boot.asm`: the finished model volume. Match its voice, routine-header
   format, `; (src: X)` rename marks and density.
3. `../OVERVIEW.md` (sections 2.1-2.3) and `../DISASSEMBLY_GUIDE.md` (Z86.SYS section).

Evidence: `../project/MSDOS/poc/I86.ASM` and `BIOS.ASM` (the author's source),
`../symbols/z80/Z86.SYS.lst` (address/bytes/source), `../project/MSDOS/poc/cpu86.py`
(the Python 8086 model the interpreter must match), and `../project/MSDOS/poc/README.md`
(working notes). For link and FDC code, also
`/Users/hugopinto/Developer/LOADZX/TC3256/SIM/ROMS/FDD_Interface/bios_z80asm.asm`
(CP/M CBIOS A1.1, which BIOS.ASM borrows from) and
`/Users/hugopinto/Developer/LOADZX/TC3256/SIM/ROMDIS/asm/fdd3000b.asm` (hardware names).

Z86.SYS (loaded at D000h) is split into 8 parts in `DISASM/parts/`; 7 other agents are
editing the other parts at the same time.

## Your file
`DISASM/parts/z86_0N.asm`. Edit ONLY this file (Edit tool). Do not touch other parts,
`parts/base/`, `asm/` or `tools/`.

## Task
- **Routine headers:** a header block on every routine, table or handler group: purpose,
  entry, exit, corrupted registers, callers (search the listing; read other parts but
  don't edit them), and lineage where relevant (mirrors cpu86.py X; from CBIOS A1.1 Y).
- **Line comments:** intent-level (why, not what). About 85% of instruction lines should
  carry a comment that says something; a comment that restates the mnemonic is worse
  than none. The skeleton carries the author's source comments: keep the good ones,
  rewrite them in this voice, fix the wrong ones.
- **Data tables:** decode them inline (what each entry means).
- **Renames:** give cryptic numbered locals (`CB1`, `LD2`, `S8R7`) parent-derived names,
  each label line marked `; (src: OLD)`. ONLY rename a label that nothing outside your
  part refers to: search all of `../symbols/z80/Z86.SYS.lst` AND
  `../symbols/z80/CPMZ80.lst` (CPMZ80 calls into Z86.SYS by name). Author or global
  names (routines, variables, `O_xxx` handlers, tables) stay as they are.
- **Ports:** replace raw port numbers with the shared equates at the top of part 01:
  FDCSTS FDCMD FDCTRK FDCSEC FDCDAT COM MASK BYTEON SERVICO STANDBY CSTAT BSTAT STMSK
  HRD UART_BAUD_CHA/CHB UART_DATA_CHA/CHB UART_CMD_CHA/CHB. Never define duplicates
  of them. You may add equates in your own part for constants whose meaning you
  establish; check the name against every existing label in the .sym files.
- **Self-modifying code:** explain the patch at both the patching store and the
  patched JP.
- **Part 01 only:** do NOT write the file preface. The `[[FILE PREFACE ...]]` line
  stays; it is written at the join.

## Hard rules
- **NEVER change bytes.** Mnemonics come from the bytes (the project assembler relaxed
  some JRs to JP; keep what is there).
- **z80asm hazards** (CONVENTIONS rules 2-3): in an 8-bit operand, never START the
  operand with a symbol named `<reg8>_…` (`B_ES`, `H_X`, `R_AX`, `C_…`); write
  `0FFh&NAME` or `0+NAME>>8` instead. No jump-target name starts with
  `NZ_ Z_ NC_ C_ PO_ PE_ P_ M_`.
- **Gate:** `cd DISASM && python3 tools/z86parts.py check N`. It assembles your part
  with the frozen baseline of all the other parts and compares the result with
  `bin/Z86.SYS`. It must print PASS when you finish; run it often. An undefined-label
  failure means you renamed something another part uses: revert that rename.
- **Claims:** if code and source both confirm something, say so plainly. Anything about
  real-hardware behaviour that was never tested stays marked provisional. Never invent.

## Deliverables
1. `parts/z86_0N.asm`, narrated, check PASS.
2. `notes/z86_part0N_findings.md`: findings with evidence (wrong source comments, bugs or
   edge cases, divergences from cpu86.py, dead code, surprises, notable design), each
   marked verified or provisional.
3. `dict/z86_part0N.md`: one entry per renamed label (format in CONVENTIONS.md;
   `aliases:` = the source name) and one per new equate.
4. Final reply, under 250 words: check result, comment-coverage estimate, top findings,
   and any cross-part issue (for example a global name you think is misleading:
   propose it, do not rename it).
