# Z86.SYS part 03: renamed labels (2026-11-08)

All are local to part 03. Each name was checked against Z86.SYS.lst, CPMZ80.lst and both .sym files.

### DAA_LOW_ADJ — DAA: add 6 for the low digit, AF = 1
- class: routine (local label)
- addresses: z86 DBC7
- aliases: DAA1 (source)
- status: verified (code + I86.ASM + cpu86.py op_daa)

### DAA_HIGH_TEST — DAA: test the original AL > 99h or CF
- class: routine (local label)
- addresses: z86 DBCD
- aliases: DAA2 (source)
- status: verified (code + I86.ASM)

### DAA_HIGH_ADJ — DAA: add 60h for the high digit, CF = 1
- class: routine (local label)
- addresses: z86 DBD6
- aliases: DAA3 (source)
- status: verified (code + I86.ASM)

### DAA_FLAGS — shared DAA/DAS tail: store AL, build S Z AF OF CF and A' into AF'
- class: routine (local label)
- addresses: z86 DBDC
- aliases: DAAF (source)
- status: verified (code + I86.ASM)

### DAA_FLAGS_NZ — DAA_FLAGS: the new AL is not zero, so ZF is left clear
- class: routine (local label)
- addresses: z86 DBF0
- aliases: DAAF1 (source)
- status: verified (code + I86.ASM)

### DAS_LOW_ADJ — DAS: subtract 6, AF = 1
- class: routine (local label)
- addresses: z86 DC0B
- aliases: DAS1 (source)
- status: verified (code + I86.ASM + cpu86.py op_das)

### DAS_HIGH_TEST — DAS: test the original AL > 99h or CF
- class: routine (local label)
- addresses: z86 DC11
- aliases: DAS2 (source)
- status: verified (code + I86.ASM)

### DAS_HIGH_ADJ — DAS: subtract 60h, CF = 1
- class: routine (local label)
- addresses: z86 DC1A
- aliases: DAS3 (source)
- status: verified (code + I86.ASM)

### AAA_ADJ — AAA: AX += 106h
- class: routine (local label)
- addresses: z86 DC34
- aliases: AAA1 (source)
- status: verified (code + I86.ASM + cpu86.py op_aaa)

### AAA_SET_AFCF — AAA/AAS: an adjustment was made, so AF = CF = 1
- class: routine (local label)
- addresses: z86 DC3A
- aliases: AAAS1 (source)
- status: verified (code + I86.ASM)
- notes: AAS joins here from AAS_ADJ.

### AAA_CLR_AFCF — AAA/AAS: no adjustment, so AF = CF = 0
- class: routine (local label)
- addresses: z86 DC40
- aliases: AAA0 (source)
- status: verified (code + I86.ASM)

### AAA_STORE — AAA/AAS: mask AL to its low digit, store AX, flags into AF'
- class: routine (local label)
- addresses: z86 DC44
- aliases: AAA2 (source)
- status: verified (code + I86.ASM)

### AAS_ADJ — AAS: AL -= 6, AH -= 1 (separately)
- class: routine (local label)
- addresses: z86 DC62
- aliases: AAS1 (source)
- status: verified (code + I86.ASM + cpu86.py op_aas)

### JPAR_NOT — JP/JNP: the parity test failed, so restore F and go to J_NOT
- class: routine (local label)
- addresses: z86 DEAB
- aliases: JP1 (source)
- status: verified (code + I86.ASM)
- notes: not named JP_xxx, to keep a mnemonic-looking name out of operands.

### JL_OF_SET — JL/JLE with OF = 1: taken when SF = 0
- class: routine (local label)
- addresses: z86 DEB7
- aliases: JL1 (source)
- status: verified (code + I86.ASM + cpu86.py cond)

### JGE_OF_SET — JGE/JG with OF = 1: taken when SF = 1
- class: routine (local label)
- addresses: z86 DEC5
- aliases: JGE1 (source)
- status: verified (code + I86.ASM + cpu86.py cond)

### LEA_STORE — LEA: write the offset (0 for mod = 3) into reg16
- class: routine (local label)
- addresses: z86 DFBC
- aliases: LEA1 (source)
- status: verified (code + I86.ASM + cpu86.py op_lea)

No new equates.
