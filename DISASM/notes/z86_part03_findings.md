# Z86.SYS part 03 (DBB2h-DFF7h, O_DAA .. O_POP8F): findings (2026-11-08)

Gate: `python3 tools/z86parts.py check 3` PASS. lint: 613 instructions, 84% commented,
0 errors; 4 warnings, all CRYPTIC for `JREL8 G80J G81J G83J`. These names are global
(`JREL8` is called from part 05; the `G8xJ` names are in DISASSEMBLY_GUIDE's SMC table),
so they are kept.

Region contents: DAA DAS AAA AAS (27h 2Fh 37h 3Fh); INC / DEC / POP / PUSH reg16 (40h-5Fh)
and PUSHX; Jcc (60h-7Fh) with J_TAKE / JREL8 / J_NOT (EBh); the 80h-83h immediate group;
TEST / XCHG / MOV 84h-8Bh; MOV r/m,sreg; LEA; MOV sreg,r/m; POP r/m16.
**Not in this part,** although the plan lists them: PUSH / POP of segment registers
(06h 07h 0Eh 16h 17h 1Eh 1Fh, part 02), PUSHF / POPF / SAHF / LAHF (9Ch-9Fh, part 04),
GETF / SETF / SETCO (part 02). The flag findings below still cover them where they matter.

Experiments: a scratch script ran single instructions on `cpu86.CPU` and on `z86.Z86`
(the Z80 build on tmxcobol's Z80 emulator), set up the way fuzz_z86.py does.

## F1. INC / DEC r16 always give AF = 0, not "AF from bit 11". *verified (code + run)*
INC16 / DEC16 (D580h / D58Ch, part 02's BCORE page) do `SBC A,A / LD DE,0 / SCF /
ADC HL,DE (SBC HL,DE) / RRA`. ADC/SBC HL sets H from bit 11, but RRA then **resets H**
(and N) while it puts CF back. So AF after INC/DEC reg16 and INC/DEC r/m16 (FF /0 /1)
is always 0. The overview (2.2), README and fuzz_z86.py's af_loose docstring all say
"AF comes from bit 11". That holds only for the WCORE 16-bit ADD/ADC/SUB/SBB/CMP
(`OR A / ADC HL,DE`, `SBC HL,DE`).
Run: INC AX, AX=000Fh: cpu86 FLAGS F012h, Z80 F002h. DEC AX, AX=0010h: F016h / F006h.
INC AX, AX=0FFFh (a bit-11 carry): F016h / F006h, so it is not bit 11 either.
ADD AX,1 with AX=0FFFh gives F016h on both (bit 11 = bit 3 carry, a coincidence);
with AX=000Fh, F012h / F002h (bit 11 really is used there).
Proposed wording for the overview: "after 16-bit add/subtract AF is the carry from
bit 11; after 16-bit INC/DEC it is 0".

## F2. Where the AF difference can show. *verified (code + test source)*
The overview says "Only DAA, DAS, AAA and AAS read AF". In computation that is true:
no Jcc, ALU, shift or string handler tests H. But PUSHF, LAHF and every INT (the
interpreter's or a guest's) copy FLAGS through GETF, which keeps bit 4 (`AND 0D1h`),
so a different AF reaches memory and AH. test_z86.py masks exactly this
(`(rm[i] ^ zm[i]) != AF` on memory, "AF in a pushed FLAGS word"), so the testers knew.
In practice it is harmless. Only code that compares whole FLAGS words would notice
(CPU-detection idioms test bits 12-15, not AF).

## F3. Lazy PF and the Jcc conditions match cpu86.py cond(). *verified*
F' = S Z H(AF) V(OF) C, A' = low byte of the last result. O_JP / O_JNP do `PUSH AF /
OR A` on A' to get its parity, then POP. After POPF/SAHF, SETF stores A' = 0 (PF=1)
or 1 (PF=0), and OR A gives the right parity for both. I checked all 16 conditions
against cond(): JL/JGE branch on V first and then test S, and JLE/JG add the Z test.
DAA/DAS leave A' = the new AL, and AAA/AAS keep the old A' (PF unchanged, as cpu86).

## F4. AAA adds 106h to AX as a whole (80286 behaviour). *provisional (vs real 8086)*
Both Z86 and cpu86 do AX += 106h, so with AL >= FAh the carry out of AL reaches AH
(AL=FAh gives AX=0200h on both; run). The original 8086/8088 is generally documented
as adding 6 to AL and 1 to AH separately (result 0100h). This is no divergence from
cpu86. A divergence from real 8086 silicon is possible but never tested. AAS does AL-6
and AH-1 separately, in both models.

## F5. Undefined-flag choices follow cpu86. *verified*
DAA/DAS keep the old OF (undefined on an 8086), and AAA/AAS keep S, Z, OF and PF.
LEA reg,reg (mod=3, undefined) stores 0, because cpu86's modrm() returns offset 0.
8F /1-/7 act as POP. 8C/8E with reg 4-7 alias ES..DS (`& 3`).

## F6. TEST r/m8 uses `AND (HL) / ADD A,0`. *verified*
The Z80 AND sets P/V to parity and H=1, but the 8086 needs OF=0 and AF=0. ADD A,0 keeps
S and Z and clears V, H and C, which matches cpu86 alu() op 4. TEST r/m16 goes through LOGF16.

## F7. Relaxed jumps in O_JLE / O_JG. *verified (listing bytes)*
The source has `JR Z,J_TAKE` (DECBh), `JR J_NOT` (DED4h), `JR Z,J_NOT` (DED8h) and the
final `JR J_NOT` of O_JG (DEE1h). The bytes hold JP (C3/CA). The targets are over 128
bytes back, and the project assembler relaxed them silently.

## F8. Segment-edge wrap needs no special code. *verified (reasoning)*
JREL8 adds the displacement to BC (host address = CS base + IP). Word accesses use
INC HL on guest addresses, and stack addresses are SS base + SP. The guest is the
whole 64K and Z80 addresses wrap mod 10000h, so base + (off mod 10000h) and
(base + off) mod 10000h are the same address. IP and offset wrap therefore come out
right for free, which the overview's "segment arithmetic wraps within 64 KB" implies.

## F9. Opcodes 60h-6Fh are Jcc aliases. *verified (OPLO D160h-D16Fh + cpu86)*
They behave as on a real 8086 (undocumented aliases of 70h-7Fh). DISASSEMBLY_GUIDE
does not mention it. Any 8086 disassembler should decode 6xh as Jcc for this platform.

## F10. Design notes. *verified*
- POP reg16 has POPDE pasted inline (no CALL/RET, 27 T saved). PUSH reg16 jumps to
  PUSHX, which is PUSHDE with RET replaced by JP (IX). PUSHX is shared with O_CALLN
  (E7E8h, part 05).
- JB/JNB/JZ/JNZ duplicate J_NOT's three instructions to save a JR on the fall-through.
- PUSH SP pushes SP-2 (8086 behaviour, not 80286), as cpu86 does.
- POP SP and 8F C4h: SP+2 is stored first, then overwritten by the popped word.
- LEA clears EADS/EASS so that EAMEM returns the bare offset, then reloads them from
  B_DS/B_SS. Under a segment override this drops the override base early. That is
  harmless, because LEA ignores segments and the override's IX restore routine reloads
  the same values after the instruction.
- MOV CS,r/m (8E /1) is implemented: GETIP + FARJ rebase BC with IP unchanged.

## Source comments
None in this region is wrong. "AF CF set, the rest kept" (AAA) and "LEA r,reg: 0, as
cpu86" are accurate. The overview/README statement corrected by F1 is the only error
found.
