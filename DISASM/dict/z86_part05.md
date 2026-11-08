# Z86.SYS part 05 dictionary (E417h-E805h)

### INTO_TAKE — O_INTO's taken path: OF = 1, raise INT 4
- class: routine
- addresses: z86 E575
- aliases: INTO1 (source)
- status: verified (code + I86.ASM)
- notes: swaps AF' back before falling into DOINT.

### SHB_RUN — byte shift with a non-zero count: build the SHPG frame, patch SHB2
- class: routine
- addresses: z86 E5A8
- aliases: SHB1 (source)
- status: verified (code + I86.ASM)

### SHD1_SHR — O_SHD1 fast path for SHR r/m16,1
- class: routine
- addresses: z86 E5E6
- aliases: SHR1W (source)
- status: verified (code + I86.ASM + cpu86.py op_shift)

### SHD1_SHR_ZF — SHD1_SHR: CF set, now test for zero
- class: routine
- addresses: z86 E5F6
- aliases: SHR1W1 (source)
- status: verified (code + I86.ASM)

### SHD1_SHR_DONE — SHD1_SHR: flags built, set A' for PF
- class: routine
- addresses: z86 E5FC
- aliases: SHR1W2 (source)
- status: verified (code + I86.ASM)

### SHW_RUN — word shift with a non-zero count: build the SHPG frame, patch SHW2
- class: routine
- addresses: z86 E61A
- aliases: SHW1 (source)
- status: verified (code + I86.ASM)

### ROT16_DONE — common tail of the word rotates: merge OF/CF, store
- class: routine
- addresses: z86 E651
- aliases: ROTE16 (source)
- status: verified (code + I86.ASM)

### SH16_FLAGS — common tail of the word shifts: add SF, ZF
- class: routine
- addresses: z86 E69D
- aliases: SHE16 (source)
- status: verified (code + I86.ASM)

### SH16_STORE — word shifts: set AF', store the result
- class: routine
- addresses: z86 E6A9
- aliases: SHE161 (source)
- status: verified (code + I86.ASM)

### ROT8_DONE — common tail of the byte rotates
- class: routine
- addresses: z86 E6D4
- aliases: ROTE8 (source)
- status: verified (code + I86.ASM)

### SH8_FLAGS — common tail of the byte shifts: add SF, ZF
- class: routine
- addresses: z86 E70A
- aliases: SHE8 (source)
- status: verified (code + I86.ASM)

### SH8_STORE — byte shifts: set AF', store the result
- class: routine
- addresses: z86 E713
- aliases: SHE81 (source)
- status: verified (code + I86.ASM)

### XLAT_ADD — O_XLAT: offset formed, add the DS/override base
- class: routine
- addresses: z86 E777
- aliases: XLAT1 (source)
- status: verified (code + I86.ASM)

### SHPG_8BIT — offset of the 8-bit half of the SHPG slot block (80h)
- class: constant
- addresses: (equate) value 80h
- aliases: — (source writes `OR 80h`)
- status: verified (code + I86.ASM SHPG layout: 8-bit slots at SHPG+128+k*16)
