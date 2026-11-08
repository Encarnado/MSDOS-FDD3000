# Naming & narration conventions — FDD3000-MSDOS disassemblies

Adopted 2026-11-08 from the TC3256 corpus (`TC3256/SIM/ROMDIS/dict/CONVENTIONS.md`,
whose rules apply here unless changed below). Change only by recorded decision.

## Toolchain

- **Z80: Wijnen `z80asm` v1.8**, the corpus assembler of record. Gate: `tools/roundtrip.sh`.
- **8086: NASM 3.02, `nasm -O0 -f bin`** (installed 2026-11-08). `-O0`: NASM never
  re-sizes, so explicit `short` / `byte` / `word` keywords fix each encoding.
  Skeletons by `tools/x86dis.py`: MASM listing for line offsets and code/data,
  `ndisasm` for the decode, NASM listing for a per-line reconcile.
  Spelling devices (all reassemble to MASM's exact bytes):
  - `TRAP nn` = `db 0Fh,nn`: the interpreter's BIOS trap (`POP CS` on an 8086).
  - `xor_d bp,bp`, `mov_d di,ax` … (`_d` family): register-to-register with the
    direction bit set. MASM always encodes reg,reg this way and NASM never does;
    same operation as the plain mnemonic.
  - `add bx,byte 2`: opcode 83h, an imm8 sign-extended (MASM's short form).
  - `$ST1`, `$DR0`: author labels that are NASM reserved words (x87 / debug
    registers), escaped with `$` until renamed.
  Result: all four 8086 images with **zero** raw-byte fallback lines.
- `tools/z80dis.py` makes the first-cut skeleton only. After `--install`,
  the `.asm` in `asm/` is the master, edited by hand; the generator never
  overwrites it.

## Hard constraints

1. **Byte identity.** Edits change comments, labels and the symbolic spelling of
   operands, never the bytes. `tools/roundtrip.sh` is green at the end of every session.
2. **z80asm condition-lexing rule** (inherited): no jump/call target named
   `NZ_ Z_ NC_ C_ PO_ PE_ P_ M_`….
3. **z80asm register-lexing rule** (NEW, found 2026-11-08 on Z86.SYS): in an
   **8-bit operand slot**, a symbol whose name starts with an 8-bit register
   letter plus `_` (`B_ES`, `H_X`, `R_AX`, `I_…`) is read as **that register**,
   silently: `add a,B_ES&0FFh` → `add a,b` (80h), `cp B_ES&0FFh` → `cp b`,
   `ld l,B_ES&0FFh` → `ld l,b`. 16-bit and memory forms are safe
   (`ld hl,R_AX`, `ld (B_ES),hl`). Write such operands as `0FFh&B_ES` or
   `0+NAME>>8`. Z86.SYS's own names (`B_ES`, `R_AX`…) are the author's and are
   kept; the operand is guarded instead. `tools/lint.py` flags violations.
4. **Bytes outrank source.** The project assembler (tmxcobol `z80asm.py`)
   silently relaxes an out-of-range `JR` into `JP`. Mnemonics are taken from the
   bytes; a relaxed site carries a short note.

## Naming

- **Global names are the author's** (from `symbols/*.sym`): routines, variables,
  tables, entry points (`IPL`, `LOAD`, `NEXT`, `TRAP`, `COLD`, `BDOSE`…). They are
  the vocabulary of the sources, the overview and the guide; renaming them would cut
  the disassembly off from all three.
- **Cryptic numbered locals are renamed** to names derived from their parent
  (`LD2` → `LOAD_POLL`, `CK1` → `IPL_CHECK_NAME`). The label line carries
  `; (src: LD2)`, and the dictionary keeps the alias.
- **Hardware uses corpus names**, shared with `fdd3000b.asm`, TOSDIS and the CP/M
  CBIOS: `FDCSTS/FDCMD/FDCTRK/FDCSEC/FDCDAT`, `HRD` (E0h latch), `COM` (2Fh link, bit 7 =
  DRQ), CBIOS link codes `MASK BYTEON SERVICO CSTAT BSTAT STMSK` (STMSK, CBIOS's alias of its DSTAT, because Z86.SYS has its own DSTAT variable), WD2123 `UART_*`.
  FDC command constants are named after CBIOS's (`RDSCMD`); a value that differs
  from CBIOS's gets a suffix (`RSTCMD_NOVFY` = 01h vs CBIOS `RSTCMD` 05h). One name,
  one value, across both corpora.
- 8086 volumes: the author's MASM names; `TRAP_*` constants for trap numbers.

## Narration

As in the corpus: comments state **intent, not mechanics**. Routine headers give
purpose, entry, exit, what is corrupted, callers, and lineage (what came from CBIOS
A1.1, what mirrors cpu86.py). Tables are decoded inline. File preface: role, place
in the boot/run chain, key findings, verification, hashes, source, credits.

Evidence: the source exists, so an interpretation is `verified` when it agrees with
the code **and** the source (or the Python reference model `cpu86.py`). Hardware
behaviour that was never run on a real FDD3000 stays `provisional` and says so.

Findings (source comments that are wrong, dead code, guide omissions, assembler
hazards) go in `notes/<file>_findings.md` and the file preface.

## Dictionary entry format

```markdown
### CANONICAL_NAME — one-line meaning
- class: routine | variable | constant | port | table | entry-point
- addresses: boot 3F5C
- aliases: LD2 (source)
- status: verified (code + BOOT.ASM) | provisional (why)
- notes: …
```

## DOS call equates (8086 volumes), harmonised 2026-11-08
One name per INT 21h function across iosys / format / cpmcom / edit / mode / term:
`DOS_PRTSTR` (09h, was DOS_PRINT in edit), `DOS_SETDTA` (1Ah, was DOS_SETDMA),
`DOS_BLKREAD` (27h, was DOS_BLKRD).
