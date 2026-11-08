# Brief: narrate one 8086 volume (parallel pass, 2026-11-08)

Work directly (no sub-agents). Your prompt names your volume (file, gate name,
volume number).

## Context
Workspace: /Users/hugopinto/Developer/LOADZX/FDD3000-MSDOS/DISASM. It holds
commented, byte-identical disassemblies of the FDD3000-MSDOS binaries: MS-DOS 1.25
running on a Timex FDD3000's Z80 through an 8086 interpreter written in Z80. The voice
and rules come from the TC3256 corpus ("The Complete TMX Portugal ROM Disassemblies").

Read first, in this order:
1. `DISASM/dict/CONVENTIONS.md`: the rules (binding).
2. `DISASM/asm/boot.asm`: the model volume. Match its file preface, routine-header
   format and voice.
3. `../OVERVIEW.md` (sections 2.3-2.7) and `../DISASSEMBLY_GUIDE.md` (8086 section).
4. The opening of `DISASM/asm/z86sys.asm` (its preface) and its TTAB / trap
   handlers, to see how the Z80 side serves your traps.

Evidence: the author's MASM source in `../project/MSDOS/poc/` (IOFDD.ASM, FORMAT.ASM,
CPM.ASM, EDIT.ASM), the MASM listings in `../symbols/x86/*.LST`, the working notes in
`../project/MSDOS/poc/README.md`, and the test scripts (`test_edit.py`,
`test_fdd86.py`) for behaviour that was checked. The DOS 1.25 kernel listing
`../symbols/x86/MSDOS.LST` tells you what each INT 21h call does in this exact DOS.

## Your file
`DISASM/asm/<volume>.asm`, currently a byte-identical skeleton made by
`tools/x86dis.py`. Edit ONLY that file (Edit tool), plus your two notes and dict
files.

## How the skeleton is spelled (keep this; it is what makes the bytes match)
- Assembler: **NASM, `nasm -O0 -f bin`**. `-O0` means NASM never re-sizes anything,
  so the explicit `short`, `byte`, `word` keywords decide the encoding. Never remove
  them, and never add an instruction form whose size NASM would choose differently.
- `TRAP nn` = `db 0Fh,nn`, the interpreter's BIOS trap (`POP CS` on a real 8086). The
  Z80 BIOS does function nn and execution continues at the next byte. Name each trap
  number with an equate (`TRAP_xxx`, after TTAB in z86sys.asm) and say what the Z80
  side does.
- `xor_d bp,bp`, `mov_d di,ax` and the other `_d` forms: a register-to-register
  instruction in MASM's encoding (direction bit set). Same operation as the plain
  mnemonic. The macros are defined at the top; explain them once in the preface.
- `$ST1`, `$DR0`: author labels that are NASM reserved words, escaped with `$`.
- Operands still written as numbers (`mov bx,0x40b`, `[0x162]`) can be made symbolic
  when you know the author's expression (see the MASM source). NASM accepts the
  author's expressions (`TRACK+BOOTOFF`) once the needed equates are defined. Keep
  the bytes identical.

## Task
- **File preface** in the model's form: banner
  "MS-DOS 1.25 ON THE TIMEX FDD3000 -- THE DISASSEMBLIES -- N/7", ROLE, place in the
  run chain, KEY FINDINGS, VERIFICATION, FILE / MD5 / SHA256 (from
  `notes/hashes.txt`), SOURCE, CREDITS. Replace the generator banner line.
- **Routine headers** on every routine and table: purpose, entry, exit, registers
  changed, callers, and the DOS calls it makes (INT 21h AH=nn by name: "AH=0Fh open
  FCB").
- **Line comments:** intent-level on about 85% of instruction lines. Keep the good
  author comments, rewrite them in this voice, fix the wrong ones. A comment that
  restates the mnemonic is worse than none.
- **Data:** decode tables and strings inline (key tables, message tables, FCBs, track
  image layouts).
- **Renames:** give cryptic numbered locals (`ST1`, `DR0`, `GS1`) parent-derived names,
  each label line marked `; (src: OLD)`; the `$` escape then disappears.
  Author/global names stay. One volume per file, so any label used only inside your
  file may be renamed.

## Hard rules
- **NEVER change bytes.**
- **Gate:** `cd DISASM && tools/roundtrip.sh <gatename>` must print PASS at the end;
  run it often.
- **Claims:** if code and source both confirm something, say so plainly. Behaviour on
  real hardware that was never tested stays marked provisional. Never invent.

## Deliverables
1. The narrated volume, gate PASS.
2. `notes/<volume>_findings.md`: findings with evidence (wrong source comments,
   bugs/edges, surprises, notable design), each marked verified or provisional.
3. `dict/<volume>.md`: one entry per rename and per new equate (format in
   CONVENTIONS.md).
4. Final reply, under 250 words: gate result, comment-coverage estimate, top
   findings, and any cross-volume issue.
