# Z86.SYS part 05 findings (E417h-E805h: O_MOVI_AL .. O_JMPF)

Narrated 2026-11-08. Gate `python3 tools/z86parts.py check 5`: PASS. Lint: 0 errors;
comment coverage 81% (the uncommented lines are mid-sequence bytes of multi-byte
moves and bit shuffles, covered by the line above or the block header).

## Scope note
- The brief listed the BIOS trap opcode 0Fh, HLT, CALL far and JMP short as part of this
  region. They are not here: O_TRAP (D8C1h) and O_HLT (D8BDh) are in part 02, O_CALLF
  (E027h) in part 04, EBh JMP short is O_JREL8 (DE48h, part 03), and EEh/EFh OUT DX
  dispatch straight to O_NOP. This part holds the other half of the trap mechanism:
  DOINT (the INT that reaches a trap stub) and O_RETF / O_RETFN (the RETF that leaves
  it). **verified** (Z86.SYS.lst, OPLO/OPHI).
- The D0h-D3h shift/rotate groups, including the self-modifying `JP SHPG` at SHB2 /
  SHW2, are in this part and are narrated at both the patching store and the patched JP.

## Findings
1. **INT goes through guest memory always; trap stubs close the loop.** DOINT reads the
   vector at Z80 address 4n (guest linear = Z80 address, so the IVT is 0000h-03FFh, no
   segment arithmetic). Unlike cpu86.py there is no `int_hook` (only dosshim uses it).
   IO.SYS's PC BIOS vectors point at `0Fh n, CAh 02 00` = TRAP n / RETF 2
   (IOFDD.ASM lines 117-123); RETF 2 (O_RETFN) discards the FLAGS DOINT pushed, so the
   ZF/CF set by the Z80 BIOS reach the caller. Device entries are `0Fh n, CBh`
   (TRAP n / RETF, IOFDD.ASM line 18). **verified** (code + I86.ASM + IOFDD.ASM).
2. **IF/TF stay cleared after a BIOS-interrupt call.** Because RETF 2 drops the saved
   FLAGS, IF=TF=0 persist after INT 10h etc. Harmless: nothing interrupts the guest and
   nothing reads IF/TF except PUSHF. **verified** (code); visible effect on real
   programs: none expected, **provisional**.
3. **Divide error pushes the next instruction's IP** (BC already past the instruction
   when DIVERR is reached from O_AAM or GRP3 DIV/IDIV). That is 8086/8088 behaviour and
   cpu86.py's. **verified**.
4. **LES/LDS with a register operand (mod=11) diverge from cpu86.py.** MRW returns a REGS
   pointer, so the pointer is read from registers rm and rm+1 (rm=DI reads R_ES as the
   segment); cpu86.py reads 0000:0000. Undefined on the 8086 and masked out by
   fuzz_z86.py, so never compared. **verified** by code reading; harmless for real code.
5. **Guest port I/O is a floating bus.** IN returns FFh/FFFFh, OUT is discarded, the
   port number is never read (E4h-E7h just skip the byte; EEh/EFh are O_NOP). Matches
   cpu86.py's default port_in/port_out. All hardware access is the Z80 BIOS's, via traps.
   **verified**. A PC program polling PC hardware would see all status bits set
   (instant "ready", or a hang waiting for a bit to clear): **provisional**, untested.
6. **Shift count is CL unmasked (0-255)**, as the 8086 and cpu86.py; count 0 leaves
   operand and flags alone. OF for counts above 1 (undefined on the 8086) follows
   cpu86.py's rules (ROL/RCL/SHL: MSB^CF; ROR/RCR: top two bits; SHR: 0; SAR: 0).
   AF = 0 after shifts. **verified** (code + cpu86.py op_shift).
7. **O_SHD1 fast path covers SHL and SHR r/m16,1 only** (mask 30h = 20h picks reg 4, 5);
   SAL (reg 6, identical to SHL) takes the general path. The SHL path uses `OR A /
   ADC HL,HL` because ADC, unlike ADD HL,HL, sets S, Z and V - and V is exactly the
   8086 OF of a 1-bit SHL. **verified**.
8. **Self-modifying JPs SHB2 / SHW2**: low byte patched to (modrm & 38h)*2 (+80h for
   bytes), selecting the 16-byte slot k in page-aligned SHPG (D700h). The Z80 stack frame
   at slot entry is [old AF'] [operand address]; RCL/RCR slots POP/PUSH it to get CF,
   rotate finishers keep S Z AF PF from it, shift finishers discard it. **verified**.
9. **O_RET inlines POPDE** to save the 27 T-state CALL/RET on the commonest return.
   O_RETN/O_RETFN do not advance BC past the imm16 (it is replaced). **verified**.
10. **Far-pointer and CS loads all update the base**: FARJ for CS (RETF, RETF n, IRET,
    INT, JMP far), SETSEG for ES/DS (LES/LDS, which also refreshes EADS; RESTORE after a
    segment prefix reloads EADS from the already-updated B_DS). **verified**.
11. **Near CALL/JMP target is a host-address add** (BC + rel16 mod 64K), equal to the
    8086 result while it lies in guest memory - the segment-wrap limit stated in
    I86.ASM's header. **verified** (known limitation, not new).
12. **Source comment fix**: `ld hl,(B_CS) ; HL = return IP` in O_CALLN - HL is the CS
    base at that line; it becomes the return IP after the subtraction. Comment moved.
    **verified**.

## Cross-part notes
- `ROT16A .. SAR8F` are flagged CRYPTIC by lint but are referenced from SHPG (part 01);
  kept. `SHB2` / `SHW2` are only referenced here but are named in DISASSEMBLY_GUIDE item
  5; kept.
- Lint warnings remaining: 12, all these kept names.
