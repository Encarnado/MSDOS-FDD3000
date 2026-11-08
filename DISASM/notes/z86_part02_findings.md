# Z86.SYS part 02 (D800h-DBB1h): findings

Region: START to O_POP_DS: the dispatcher, the prefixes, ModR/M decoding,
the helpers (GETIP FARJ PUSHDE POPDE SETSEG GETF SETF SETSTEP SETCO SZP8),
and the 00h-3Fh ALU handlers. `python3 tools/z86parts.py check 2`: PASS.
lint: 0 errors, comment coverage 91.8 % (523 instructions).

## Design (verified: code + I86.ASM + README)

- **Dispatch cost 58 T-states.** NEXT is 7+6+4+7+7+4+7+4+4 = 50 T, and the
  handler's closing `JP (IX)` adds 8. That matches the README. The split
  table OPLO (D100h) / OPHI (D200h) is indexed by the opcode in L, so a single
  `INC H` moves from the low-byte table to the high-byte one. EALO/EAHI
  (D300h/D400h) work the same way for ModR/M. The whole ModR/M byte is the
  index, so each 8-entry row repeats 8 times (the reg field is ignored), and
  C0h-FFh are zeros.
- **Segment override = two stores plus an IX redirection.** Every memory
  operand base comes from EADS/EASS. O_SEG_* (72 T) points both at the
  override base and sets IX = RESTORE. RESTORE (86 T, including its JP (IX))
  reloads them from B_DS/B_SS, so it is also correct when the overridden
  instruction loaded DS or SS itself (SETSEG has already updated the base).
  An override therefore costs about 158 T. RESTORE is reachable only through IX.
- **NEXT2/DISPA duplicate NEXT** because while an override is pending, IX may
  hold RESTORE: a prefix must reach the next handler without going through IX.
- **LOCK = NEXT2** (an EQU): F0h is ignored, as in cpu86.py `step()`.
- **SEGSET** is the CALLable form of O_SEG_*, used by O_REP's prefix loop. Two
  RRCAs turn prefix bits 4-3 into 2*sreg (26h→0, 2Eh→2, 36h→4, 3Eh→6).
- **Self-modifying ALU dispatch.** `opcode & 38h` = 8k; one `ADD A,A` gives
  16k, a BCORE slot (D500h, 16-byte slots); two give 32k, a WCORE slot
  (D600h, 32-byte slots, maximum E0h). The handler writes that byte into the low
  byte of its own `JP` (ALUnJ+1). This only works because BCORE and WCORE
  start on page boundaries; the high byte D5h/D6h is fixed. Each entry
  rewrites the byte before the JP executes, so a stale value is harmless.
- **O_CMPAL (3Ch) fast path:** 46 T against 84 T through O_ALU4 + BCORE's CMP
  slot. Why only this opcode got one is not documented (provisional: probably
  hot in DOS loops).
- **SETF's PF trick:** PF is always the parity of A', so SETF picks A' = 00h
  (PF = 1) or 01h (PF = 0) and gives up the old result byte. Verified: it
  matches cpu86.py's flags setter. GETF forces bit 1 and bits 12-15 on, which
  equals cpu86.py's 0F002h base.
- **SETCO keeps the caller's A and F** (they wait in the alternate pair
  during the exchange). Only E and HL are corrupted. The I86.ASM comment
  does not say this.
- **PUSHDE/POPDE add the SS base byte-wise through A** so that DE, the data,
  stays intact. They use B_SS, not EASS, so the stack correctly ignores
  overrides. A word at segment offset FFFFh wraps to base+0, the same as
  cpu86.py's `(off+1) & 0FFFFh`, because host addresses are taken mod 64K. No
  divergence.
- **Register pointers rely on alignment:** REGS is page-aligned (D000h) and
  R8TAB is 8-aligned (REGS+30h), so `OR R8TAB&0FFh` and `INC L` (O_ALU1
  reading the reg operand) are safe. O_ALU3 correctly uses `INC HL` for
  the r/m value, which can be in memory and cross a page.

## Edge cases and divergences

- **O_BAD's `DEC BC` is wrong when entered from O_GRP4** (verified, code).
  It points BC back at the opcode only when O_BAD is reached from NEXT
  (opcode F1h). O_GRP4 (FEh /2../7) jumps there after fetching the ModR/M
  and any displacement, so BC ends up inside the instruction and the
  reported IP is off by 1-3 bytes. Diagnostic only.
- **fdd86.py reports the bad-opcode address one byte low** (verified, harness
  code; outside the binary). At BADSTOP, BC already points at the opcode,
  yet fdd86.py prints `BC - 1`. z86.py reads `m[BC]` correctly.
- **O_HLT hangs for good:** there are no interrupts and START did DI. The
  harnesses stop on PC = HALTED. cpu86.py sets `halted`. Equivalent in effect.
- **OUT DX,AL/AX (EEh/EFh) and WAIT (9Bh) map to O_NOP**, and so does NOP. cpu86.py
  routes EEh/EFh to `op_out`, which calls a `port_out` hook. This only matters
  if a DX-addressed guest port device is ever modelled (verified, OPLO table
  + cpu86.py `_build`).
- **SETSEG with CS** updates B_CS but not BC. Its only CS-capable caller,
  O_MOV8E, branches to MOVCS (GETIP/FARJ) for CS, so nothing is broken
  (verified).
- **Segment bases are 16-bit** (`SHL4`, FARJ, SETSEG drop bits 12-15 of
  the segment). This is a documented limitation (I86.ASM preamble).

## Source comments corrected or sharpened

- NEXT `; handler gets A = opcode`: true. Also, Z80 F is corrupted (INC H),
  which the source does not say.
- START header `IP in TMP`: it also needs AF' and FLAGHI prepared. COLD
  sets F' = 0, A' = 1 (PF = 0) and FLAGHI = 0.
- `SZP8 ... CF OF AF kept`: correct. It is a tail (JP SZP8 from O_AAM/O_AAD),
  ending in JP (IX), not a subroutine.

## Lint warnings left (deliberate)

The 34 CRYPTIC warnings are all for author or global names that are kept
under the conventions: SHL4, NEXT2, REG8, SZP8, EA00-EA27 (named by the
EALO/EAHI tables in part 01), and ALU0J-ALU5J (named by the brief and the
README). The patched-JP labels could get descriptive aliases at the join
if wanted.
