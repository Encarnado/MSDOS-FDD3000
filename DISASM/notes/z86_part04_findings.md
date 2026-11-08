# Z86.SYS part 04 (DFF8h-E416h) - findings

Region: O_XCHGA up to just before O_MOVI_AL: XCHG AX,r16, CBW/CWD, CALL FAR,
PUSHF/POPF/SAHF/LAHF, MOV AL/AX <-> moffs, TEST AL/AX,imm, the string
instructions, the REP prefix (O_REP, REPTAB) and the REP handlers.
Check: `python3 tools/z86parts.py check 4` PASS. Lint: 550 instructions,
97.5 % commented, 0 errors, 0 warnings.

Evidence used: I86.ASM (source), Z86.SYS.lst, cpu86.py (op_string and
neighbours), README.md "The Z80 interpreter", OVERVIEW.md 2.2 / 3, and a
lockstep run of z86.Z86 against cpu86.CPU (a throwaway script built on
fuzz_z86.setup).

## 1. REP MOVSW with operands overlapping by one byte diverges from the 8086 - verified (test)

R_MOVSW copies 2*CX bytes with one LDIR (DF=0) or LDDR (DF=1). The 8086, and
cpu86.py (`ww(es, DI, rw(sseg, SI))` per iteration), read a whole word before
writing it. A byte copy and a word copy agree unless the destination runs into
the not-yet-read half of the source word, which happens exactly when
DI = SI + 1 with DF = 0, or DI = SI - 1 with DF = 1.

Run on both models (ES = DS, memory pattern b0 b1 b2 ... = 03 0A 11 18 ...,
CX = 4):

| case | cpu86.py | interpreter |
|---|---|---|
| F3 A5, DF=0, DI=SI+1 | 03 03 0A 0A 18 18 26 26 34 | 03 03 03 03 03 03 03 03 03 |
| F3 A5, DF=0, DI=SI+2 | match | match |
| F3 A5, DF=1, DI=SI-1 (SI=9) | 03 0A 18 26 26 34 34 42 42 49 | 03 0A 49 49 49 49 49 49 49 49 |
| F3 A4 (MOVSB), DF=0, DI=SI+1 | match | match |

Registers (SI, DI, CX) agree in every case; only memory differs. The random
fuzzer (fuzz_z86.py) draws SI and DI independently below 3000h, so a distance
of exactly one is too rare to have been hit. Real code that does this is
unlikely (it is an odd way to shift a buffer by one byte; REP MOVSB is the
normal idiom), so no DOS-session test caught it either. Not fixed here (no
byte changes); a fix would be a test of DI - SI = +-1 sending those cases to a
word loop. The header of R_MOVSW records it.

## 2. REPNE SCASB fast path: how it keeps flags, CX and DI exact - verified (code + source + README/OVERVIEW)

R_SCASB, REPNE only, CX >= 2: with n = CX - 1, CPIR (DF=0) or CPDR (DF=1)
passes over at most n bytes from ES:DI. CPIR sets only Z (found) and P/V, not
the 8086's SUB flags, so it is never allowed to make the final compare:

- Every byte passed over unmatched is an 8086 iteration whose only lasting
  effect is DI +-1 and CX - 1 (ZF = 0, CX stays >= 1, so the loop would have
  continued).
- New CX = BC left + 1 (the reserved last byte) + 1 more if CPIR stopped on a
  match (CPIR counted the matched byte; it is handed back uncompared).
  DE = old CX - new CX = bytes passed over; negated by RNEG_DE when DF = 1; DI
  += DE. CPIR's HL is discarded (a host address, one past a match).
- The ordinary loop (SCASB_STEP + REPGO) then runs at least once: its SUB makes
  every flag and REPGO the final CX. Checked by hand for: no match (CX -> 1,
  last byte compared), match in the middle, match on the very last passed-over
  byte (BC = 0 and Z: CX = 2, the match is recompared, CX -> 1).

Exclusions: REPE (F3h), CX = 1, and DI wrapping during the pass (forward
DI + n > FFFFh; backward DI < CX). The backward test is "one too strict" (the
author's comment): the carry left by the RLA that read DF is borrowed into
`SBC HL,BC`, so it computes DI - n - 1 and also rejects DI = n, which would not
wrap. Harmless: the slow loop is always right. Observation (verified by
reasoning): the wrap exclusion is caution, not need - Z80 HL wraps mod 64K
exactly as base + offset does, so CPIR across an offset wrap would give the
same bytes. Lockstep runs at DI = FFF0h/CX = 32 and DI = 5/CX = 5,6 (DF = 1)
match cpu86.py.

Speed: 21 T a byte against about 300 (README; OVERVIEW 3: EDIT loading 28 KB,
5.5 s -> 3.3 s). Validation: lockstep, `fuzz_z86.py --scan`, and a
deliberately broken fast path giving 159 mismatches (OVERVIEW 3, item 9).

## 3. RADVS is dead code - verified

E25Dh-E26Eh (18 bytes). No reference in Z86.SYS.lst, CPMZ80.lst or I86.ASM
other than its own label (notes/partition_findings.md). It advances SI only,
the shape a block REP LODS would need; R_LODSB/R_LODSW loop instead. The
intended use is inferred (provisional). Marked DEAD CODE in its header.

## 4. Source glosses lost from the skeleton - verified

I86.ASM has comments on label lines that carry code (`R_NOTSTR: ; A8 / A9
after REP: plain TEST`, `RNEG_DE: ; DE = -DE if DF`); the skeleton dropped
them. Restored in the headers. Cross-part: other parts may have lost
label-line comments the same way (a z80dis.py matter).

## 5. Small redundancies (harmless) - verified

- O_MOVSB: `PUSH AF / POP AF` around DSTPTR is not needed: DSTPTR changes only
  DE, HL and F.
- CMPSB_STEP: `LD (TMP),A ... LD A,(TMP)` around SRCPTR likewise (A survives
  SRCPTR); only DE needs freeing.
- O_LAHF: `AND 0D5h / OR 2` copies cpu86.py's `flags & 0xD5 | 2`, but GETF's L
  already has bits 3 and 5 clear and bit 1 set: a no-op.
- O_LODSW is SRCPTR + SI_STEP_W written in line (no CALLs); O_LODSB is not -
  presumably LODSW was hot in profiling (provisional: no note says so).

## 6. Edge cases with no consequence - verified (code)

- REP MOVSW / STOSW with CX >= 8000h: 2*CX wraps. CX = 8000h still copies
  64K (BC = 0 means 65536 to LDIR); above that fewer bytes move. Such a REP
  would sweep the whole 64K host (the interpreter included) on any reading, so
  it cannot occur in a working guest. SI/DI end correct regardless (mod 64K).
- Word accesses at offset FFFFh (moffs, string word ops): base + FFFFh + 1 =
  base + 0 mod 64K, so the 8086's offset wrap (cpu86.py rw/ww) comes free.
- REP before a non-string opcode: dispatched as if absent (REP_OTHER -> DISPA),
  REPT left set but read only by REP compares, which always rewrite it. Same
  as cpu86.py.
- XCHG AX,AX (90h) is O_NOP in the tables, not O_XCHGA.

## 7. Assembler relaxation - verified (listing)

Three `JR RADVSD/RADVDN` in the source were relaxed to `JP` by the project
assembler (E2C7h, E2F5h, E32Bh: 136 bytes and more back). Noted on the lines.

## 8. Design notes - verified

- STEP1/STEP2 (+-1, +-2) are maintained by SETSTEP on every DF change, so no
  handler tests DF to step a pointer; the block forms read DF as the sign byte
  STEP1+1 (RLA -> carry).
- REPT keeps the raw prefix; only bit 0 is tested (F2h = 0 REPNE, F3h = 1
  REPE), and only by REPGO and R_SCASB.
- Prefixes after REP (segment, another REP, LOCK) are handled inside O_REP in
  the order met, matching cpu86.py step(); SEGSET points IX at RESTORE, so the
  REP handler's final JP (IX) restores the bases.
- REP STOS fills with an overlapping LDIR/LDDR (period 1 for bytes, 2 for
  words) after one store by hand; REP MOVSB is a plain LDIR/LDDR and is exact,
  overlap included.

## Renames

Numbered locals, all referenced only inside this part (checked in Z86.SYS.lst
and CPMZ80.lst): NSI1 NDI1 NSI2 NDI2 CMPSB1 CMPSW1 SCASB1 SCASW1 REP1-3 RMB1-3
RMW1-3 RSB1-3 RSW1-3 RLB1 RLW1 REPGO1 RCB1 RCW1 RSC0 RSCF RSCF1 RSCD RSCE RSCE1
RSCX RSC1 RSCW1. See dict/z86_part04.md.

## Fixed 2026-11-08
- Finding 1 (REP MOVSW one-byte overlap): FIXED. MWCHK (EAHI page end) sends
  DI = SI + 1 / DF = 0 and DI = SI - 1 / DF = 1 to MWSLOW (EALO page end),
  which runs O_MOVSW CX times. fuzz_z86.py --overlap: 814 mismatches on the
  old build, 0 now. RADVS (dead code) left in place.
