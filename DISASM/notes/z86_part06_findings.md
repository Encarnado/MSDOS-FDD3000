# Z86.SYS part 06 (E806h-EB45h, O_CMC .. ENDCODE): findings

Narrated 2026-11-08. File `parts/z86_06.asm`; gate `python3 tools/z86parts.py check 6`
= PASS; `tools/lint.py`: 0 errors, 84.4% of instruction lines commented.
Evidence: `symbols/z80/Z86.SYS.lst`, `project/MSDOS/poc/I86.ASM` (lines 2865-3376),
`project/MSDOS/poc/cpu86.py` (op_cmc, op_flagop, op_grp3, op_grp45, interrupt).

## Scope note (cross-part)

- **The shift/rotate groups D0h-D3h, SHB2 / SHW2 and their SHPG patching are not in
  this part.** They sit at E591h-E6xxh, in `parts/z86_05.asm` (O_SHD0 .. SHW2), and SHPG
  (D700h) is in part 01. The brief listed them for part 06; part 06 actually begins
  at O_CMC (E806h). Not narrated here, to keep to "edit only your file". The part-05
  agent should carry the store/JP explanation (`ld (SHB2+1),a` / `SHB2: jp SHPG`,
  low byte = ((reg AND 38h) * 2) OR 80h, i.e. a 16-byte slot in the upper half of the
  SHPG page; verified from the bytes only, the slot contents not checked here).
- The BIOS.ASM preface and its equates (NDRIVE, SPT, NTRACK, NSECT, FIRDIR, FIRREC,
  GTOP, RETRIES) follow ENDCODE inside this file because the split cut above the
  comment block heading TRAP only. Left untouched; they belong to part 07's narrative.
  At the join they should probably move to part 07's head.

## Design notes (verified: code + I86.ASM + cpu86.py)

- **Flag model in this row.** CMC/CLC/STC edit bit 0 of F' through `PUSH AF / POP HL`,
  keeping A' (the PF byte) in H. TEST r/m8 uses `AND (HL) / ADD A,0`: Z80 AND sets H = 1
  and P/V = parity, which would read as AF = 1 and OF = parity; `ADD A,0` recomputes S Z
  with H = V = C = 0, matching cpu86.py alu(4,...) (AF = OF = CF = 0).
- **IF is never acted on.** FLAGHI bit 1 is only set/cleared (CLI/STI, DOINT, SETF) and
  reported (GETF); nothing tests it - the guest gets no hardware interrupts. TF likewise.
  DF is turned into STEP1/STEP2 by SETSTEP at CLD/STD time.
- **MUL / IMUL** use one unsigned MULU16 (also used by O_AAD). Byte IMUL sign-extends both
  factors to 16 bits (low 16 bits of the unsigned product = signed product). Word IMUL
  corrects the high word: `hi -= (a<0 ? b : 0) + (b<0 ? a : 0)`. CF = OF tests match
  cpu86.py exactly; the other flags are kept (SETCO), as in cpu86.py.
- **DIV** pre-checks overflow (AH >= divisor / DX >= divisor), which is exactly
  "quotient too big" and also DIVU's precondition HL < divisor. DIVU is a restoring
  divider whose 17th-bit case (`ADC HL,HL` carry) is handled by DIVU_BIG.
- **SDIV** works on unsigned magnitudes, so -8000h and -80000000h come out right. Its
  overflow test is `SBC HL,DE / ADD HL,DE`: the ADD's carry reproduces the SBC's borrow
  while restoring HL (a neat idiom). It overwrites (DIVISOR) with |divisor|.
- **Divide error = INT 0 via DIVERR (E57Ah, part 05) -> DOINT**: pushes FLAGS, CS and
  GETIP (= the address AFTER the whole instruction, BC having passed ModR/M and
  displacement). cpu86.py pushes self.ip at the same point. This matches the 8086/8088
  (the 286 and later push the faulting instruction's address). Flags are untouched on
  DIV/IDIV in both models (undefined on the 8086).
- Group tables G3BT, G3WT, G5T map /1 (F6/F7) to TEST and /7 (FF) to PUSH, as cpu86.py.

## Divergences and edge cases

1. **IDIV quotient -128 / -32768 accepted (both models) - provisional vs silicon.**
   G3B_IDIV allows |q| = 80h when negative, G3W_IDIV allows 8000h; cpu86.py the same
   (`q < -0x80` / `q < -0x8000`). Intel's 80286/80386 manuals list, among differences
   from the 8086, that the 8086 raises a divide error for these quotients. So the
   interpreter behaves like a 286 here. Consistent with the reference model; not tested
   on an 8086, and no DOS 1.25 code is known to depend on it.
2. **FE /2-/7: Z80 stops, cpu86.py executes (verified divergence).** O_GRP4 sends reg
   2-7 to O_BAD (BADSTOP, an endless loop); cpu86.py op_grp45 treats FE like FF for
   k >= 2 (word CALL/JMP/PUSH). Real 8086 behaviour for these encodings is not claimed.
   Also: O_BAD's `DEC BC` assumes BC is just past the opcode; from O_GRP4 it is past
   ModR/M and displacement, so the "stop address" is off by 1+disp bytes.
3. **FF /6 with SP (FF F4) pushes the old SP (verified, both models).** G5_PUSH reads
   the operand before PUSHDE; cpu86.py `push(get_rm(...))` likewise. Yet cpu86.py's 54h
   PUSH SP deliberately pushes the NEW value ("PUSH SP pushes the new value on the
   8086"), and Z86.SYS's 54h handler is meant to match. The ModR/M form is thus
   inconsistent with the model's own 54h choice. Whether a real 8086 pushes the new SP
   for FF F4 too is provisional (likely, same microcode path; untested). Harmless in
   practice: assemblers emit 54h.
4. **FF /3 or /5 with mod = 11 (register "far pointer").** Undefined on the 8086. Z80
   reads 4 bytes from REGS at the register's slot (e.g. FF DB reads BX and SP as
   offset:segment); cpu86.py reads memory 0000:0000 (modrm returns seg = off = 0 for mod
   3). Divergent, only for invalid code.
5. **No segment wrap** for near CALL/JMP (B_CS + offset as a 16-bit host address) and
   the 4-byte far-pointer read: the documented "segment wrap not modelled" limitation.
6. **Word NEG / INC / DEC AF** is the Z80's bit-11 half-carry (I86.ASM header's known
   difference); byte forms are exact.
7. `JP C,DIVERR` after SDIV in G3B_IDIV is unreachable in effect (|AX| sign-extended to
   32 bits never has a high word >= a non-zero divisor), kept as defensive code.

## Source comments

- I86.ASM's comments in this region are correct. The DIVU header "HL < divisor" is a
  precondition the callers guarantee (G3B_DIV, G3W_DIV and SDIV check it; O_AAM passes
  HL = 0). No wrong comments found.

## Dead code

- None in this part. ENDCODE carries no code; it is read only by z86.py (size report).

## Lint false positives

- `tools/lint.py` flags `MULU16` and `G5T` as CRYPTIC. Both are author globals (MULU16 is
  called from O_AAD in part 05; G5T is the table name the partition notes use), so they
  stay. The regex `[A-Z]{1,5}\d{1,2}...` could exempt names referenced outside the part.
