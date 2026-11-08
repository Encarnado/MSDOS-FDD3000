# IO.SYS dictionary (volume 4)

No numbered source locals exist in IOFDD.ASM, so there are no renames; every
label (INIT, SETROM, COMERR, STALL, INT10..INT1A, ROMTAB, MEMTOP, DOSENT,
INITTAB, DPT40, BADCOM, FCB) and BIOSSEG / DOSSEG are the author's. Below:
the new equates. Offsets are IO.SYS offsets (linear = 0400h + offset).

## Trap numbers

Values are TTAB indices in z86sys.asm. Other 8086 volumes (FORMAT, CPM, EDIT)
should reuse these names for the same numbers.

### TRAP_STATUS — trap 01h, STATUS: ZF=1 no key; ZF=0, AL = key (kept for INP)
- class: constant
- value: 01h; Z80 handler T_STAT (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INP — trap 02h, INP: AL = key, waits; no flags
- class: constant
- value: 02h; Z80 handler T_INP (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_OUTP — trap 03h, OUTP: AL to the terminal
- class: constant
- value: 03h; Z80 handler T_OUTP (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_PRINT — trap 04h, PRINT: AL to WD2123 channel A
- class: constant
- value: 04h; Z80 handler T_PRINT (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_AUXIN — trap 05h, AUXIN: AL from channel B
- class: constant
- value: 05h; Z80 handler T_AUXIN (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_AUXOUT — trap 06h, AUXOUT: AL to channel B
- class: constant
- value: 06h; Z80 handler T_AUXOUT (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_READ — trap 07h, READ: AL unit, DS:BX, CX count, DX sector; CF=1 AL = error, CX left
- class: constant
- value: 07h; Z80 handler T_READ (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_WRITE — trap 08h, WRITE: as READ
- class: constant
- value: 08h; Z80 handler T_WRITE (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_DSKCHG — trap 09h, DSKCHG: AH = 0 (don't know), CF = 0
- class: constant
- value: 09h; Z80 handler T_DSKCHG (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_SETDATE — trap 0Ah, SETDATE: AX = days since 1-1-80
- class: constant
- value: 0Ah; Z80 handler T_SDATE (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_SETTIME — trap 0Bh, SETTIME: CH:CL h:m, DH:DL s.1/100
- class: constant
- value: 0Bh; Z80 handler T_STIME (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_GETTIME — trap 0Ch, GETTIME: AX, CX, DX as last set
- class: constant
- value: 0Ch; Z80 handler T_GTIME (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_FLUSH — trap 0Dh, FLUSH: drop type-ahead
- class: constant
- value: 0Dh; Z80 handler T_FLUSH (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_MAPDEV — trap 0Eh, MAPDEV: nothing done, AL unchanged
- class: constant
- value: 0Eh; Z80 handler TNONE (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT10 — trap 10h, INT 10h video
- class: constant
- value: 10h; Z80 handler T_I10 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT11 — trap 11h, INT 11h equipment word
- class: constant
- value: 11h; Z80 handler T_I11 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT12 — trap 12h, INT 12h memory size
- class: constant
- value: 12h; Z80 handler T_I12 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT14 — trap 14h, INT 14h serial
- class: constant
- value: 14h; Z80 handler T_I14 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT16 — trap 16h, INT 16h keyboard
- class: constant
- value: 16h; Z80 handler T_I16 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT17 — trap 17h, INT 17h printer
- class: constant
- value: 17h; Z80 handler T_I17 (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

### TRAP_INT1A — trap 1Ah, INT 1Ah tick count
- class: constant
- value: 1Ah; Z80 handler T_I1A (z86sys TTAB)
- aliases: none (source writes the bare number in ENTRY n / DB 0FH,n)
- status: verified (code + IOFDD.ASM + z86sys TTAB)

## DOS interface equates

### DOS_PRTSTR — INT 21h AH=09h print string to "$"
- class: constant
- value: 09h
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### DOS_OPEN — INT 21h AH=0Fh open FCB
- class: constant
- value: 0Fh
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### DOS_SETDTA — INT 21h AH=1Ah set disk transfer address
- class: constant
- value: 1Ah
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### DOS_BLKREAD — INT 21h AH=27h random block read
- class: constant
- value: 27h
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### FCB_RECSIZ — FCB record-size field (MSDOS.LST FCBLOCK RECSIZ = 0Eh)
- class: constant
- value: 14
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### FCB_RR — FCB random-record field, 4 bytes (FCBLOCK RR = 21h)
- class: constant
- value: 33
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### PSP_SEGSIZE — program segment word [6]: bytes in the segment (SETMEM)
- class: constant
- value: 6
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### PSP_FCBSTK — initial SP of a 1.x program, under the default FCB
- class: constant
- value: 5Ch
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### PSP_DTA — default DTA of a program
- class: constant
- value: 80h
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

### COM_ORG — load and entry offset of a .COM
- class: constant
- value: 100h
- aliases: none (source writes the number: MOV AH,26 / FCB+14 / DS:[6] ...)
- status: verified (code + IOFDD.ASM + MSDOS.LST)

## Label added

### ROMEND — end of ROMTAB (offset 00E7h, = MEMTOP)
- class: constant (label)
- addresses: iosys 00E7
- aliases: none; source writes MOV CX,7
- status: verified (code)
- notes: SETROM's count is spelled (ROMEND-ROMTAB)/3 = 7; same bytes.
