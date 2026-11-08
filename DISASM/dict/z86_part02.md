# Z86.SYS part 02 dictionary (D800h-DBB1h)

New equates: none.

### JTAB_FETCH — JTAB: read the table entry and jump
- class: routine
- addresses: z86 DA10
- aliases: JTAB1 (source)
- status: verified (code + I86.ASM)
- notes: reached once DE has been advanced by A; loads the DW entry and jumps through PUSH DE / RET so HL survives.

### SETSEG_DS — SETSEG: the new segment is DS, refresh EADS
- class: routine
- addresses: z86 DA80
- aliases: SETSG1 (source)
- status: verified (code + I86.ASM)

### GETF_HIGH — GETF: build the FLAGS high byte
- class: routine
- addresses: z86 DA96
- aliases: GETF1 (source)
- status: verified (code + I86.ASM + cpu86.py flags)
- notes: FLAGHI (TF IF DF) | F0h, with OF from Z80 V.

### GETF_DONE — GETF: high byte complete, store it in H
- class: routine
- addresses: z86 DAA1
- aliases: GETF2 (source)
- status: verified (code + I86.ASM)

### SETF_PF — SETF: F' built, now choose A' for PF
- class: routine
- addresses: z86 DAAC
- aliases: SETF1 (source)
- status: verified (code + I86.ASM)

### SETF_LOAD — SETF: load D:E into AF'
- class: routine
- addresses: z86 DAB4
- aliases: SETF2 (source)
- status: verified (code + I86.ASM)
- notes: A' = 00h (PF = 1) or 01h (PF = 0).

### SETSTEP_STORE — SETSTEP: store STEP1/STEP2
- class: routine
- addresses: z86 DAD0
- aliases: SETST1 (source)
- status: verified (code + I86.ASM)

### SETCO_MERGE — SETCO: merge the new CF/OF bits into F'
- class: routine
- addresses: z86 DADE
- aliases: SETCO1 (source)
- status: verified (code + I86.ASM)

### SZP8_STORE — SZP8: load result:flags into AF' and end the instruction
- class: routine
- addresses: z86 DAFE
- aliases: SZP81 (source)
- status: verified (code + I86.ASM)
