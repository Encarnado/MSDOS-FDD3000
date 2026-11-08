# Z86.SYS part 06 dictionary (E806h-EB45h)

Renamed numbered locals only; every old name is referenced solely inside this part
(checked in Z86.SYS.lst and CPMZ80.lst). No new equates.

### G3B_IDIV_QNEG — byte IDIV: range check for a negative quotient
- class: routine (local label)
- addresses: Z86.SYS E900
- aliases: G3BID1 (source)
- status: verified (code + I86.ASM)
- notes: |q| <= 80h allowed, then NEG.

### G3B_IDIV_STQ — byte IDIV: store the quotient in AL
- class: routine (local label)
- addresses: Z86.SYS E907
- aliases: G3BID2 (source)
- status: verified (code + I86.ASM)

### G3B_IDIV_STR — byte IDIV: store the remainder in AH
- class: routine (local label)
- addresses: Z86.SYS E913
- aliases: G3BID3 (source)
- status: verified (code + I86.ASM)

### G3W_IMUL_FIXB — word IMUL: correct the high word for a negative operand
- class: routine (local label)
- addresses: Z86.SYS E999
- aliases: G3WIM1 (source)
- status: verified (code + I86.ASM)

### G3W_IMUL_STORE — word IMUL: store DX and set CF/OF
- class: routine (local label)
- addresses: Z86.SYS E9A6
- aliases: G3WIM2 (source)
- status: verified (code + I86.ASM)

### G3W_IDIV_QNEG — word IDIV: range check for a negative quotient
- class: routine (local label)
- addresses: Z86.SYS EA07
- aliases: G3WID1 (source)
- status: verified (code + I86.ASM)
- notes: |q| <= 8000h allowed.

### G3W_IDIV_NEGQ — word IDIV: negate the quotient magnitude
- class: routine (local label)
- addresses: Z86.SYS EA14
- aliases: G3WID0 (source)
- status: verified (code + I86.ASM)

### G3W_IDIV_STQ — word IDIV: store the quotient in AX
- class: routine (local label)
- addresses: Z86.SYS EA1A
- aliases: G3WID2 (source)
- status: verified (code + I86.ASM)

### G3W_IDIV_STR — word IDIV: store the remainder in DX
- class: routine (local label)
- addresses: Z86.SYS EA2A
- aliases: G3WID3 (source)
- status: verified (code + I86.ASM)

### MULU16_LOOP — MULU16: one multiplier bit per pass
- class: routine (local label)
- addresses: Z86.SYS EA37
- aliases: MULU1 (source)
- status: verified (code + I86.ASM)

### MULU16_NEXT — MULU16: loop count
- class: routine (local label)
- addresses: Z86.SYS EA42
- aliases: MULU2 (source)
- status: verified (code + I86.ASM)

### DIVU_LOOP — DIVU: one quotient bit per pass
- class: routine (local label)
- addresses: Z86.SYS EA4C
- aliases: DIVU1 (source)
- status: verified (code + I86.ASM)

### DIVU_BIG — DIVU: partial remainder overflowed 16 bits, subtract unconditionally
- class: routine (local label)
- addresses: Z86.SYS EA5B
- aliases: DIVU2 (source)
- status: verified (code + I86.ASM)

### DIVU_QBIT — DIVU: set quotient bit 1
- class: routine (local label)
- addresses: Z86.SYS EA5E
- aliases: DIVU3 (source)
- status: verified (code + I86.ASM)

### DIVU_NEXT — DIVU: loop count
- class: routine (local label)
- addresses: Z86.SYS EA5F
- aliases: DIVU4 (source)
- status: verified (code + I86.ASM)

### SDIV_DIVISOR — SDIV: quotient sign and |divisor|
- class: routine (local label)
- addresses: Z86.SYS EA7A
- aliases: SDIV1 (source)
- status: verified (code + I86.ASM)

### SDIV_CHECK — SDIV: overflow check, then DIVU
- class: routine (local label)
- addresses: Z86.SYS EA92
- aliases: SDIV2 (source)
- status: verified (code + I86.ASM)
