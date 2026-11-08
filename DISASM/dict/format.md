# FORMAT.COM dictionary (0100h-075Bh, buffers from TRACK = 075Ch)

The author's MASM names (FORMAT.ASM) are kept; equates SPT .. BUFEND, the
variables, messages and routines are the author's.  Only the numbered locals
were renamed, and four equates were added.

## New equates

### TRAP_FMTTRK — trap 1Bh, FORMAT TRACK: Write Track of one image
- class: constant
- value: 1Bh; Z80 handler T_FMT (z86sys TTAB entry 1Bh)
- addresses: format FLOOP (0460h, `TRAP TRAP_FMTTRK`)
- aliases: none (source writes `DB 0FH,1BH`; name per the 8086-volume TRAP_* set shared with iosys.md)
- status: verified (code + FORMAT.ASM + z86sys T_FMT)
- notes: AL = drive, DL = track, DS:BX = 6008-byte image; CF=1 with AL =
  0 write protect, 2 not ready, 8 track > 39, 0Ch image past memory.

### PSP_MEMSIZE — PSP word 06h: bytes available in the program's segment
- class: constant
- value: 06h
- addresses: format START (035Fh)
- aliases: none (source `DS:[6]`)
- status: verified (code + FORMAT.ASM; DOS 1.x PSP layout)

### PSP_FCB1 — PSP 5Ch: first parsed FCB (drive byte 0 = current)
- class: constant
- value: 5Ch
- addresses: format START
- aliases: none (source `DS:[5CH]`)
- status: verified

### PSP_TAIL — PSP 80h: command-tail length, text from 81h
- class: constant
- value: 80h
- addresses: format START (SCAN set-up, `PSP_TAIL+1` for 81h)
- aliases: none (source `81H`, `DS:[80H]`)
- status: verified

## Renamed locals

### MARKBAD_LOOP — MARKBAD: mark one cluster FF7h, next
- class: routine (local label)
- addresses: format 050D
- aliases: MB1 (source)
- status: verified (code + FORMAT.ASM)

### MARKBAD_DONE — MARKBAD: return
- class: routine (local label)
- addresses: format 0520
- aliases: MB2 (source)
- status: verified

### SETFAT_ODD — SETFAT: odd entry, value into the high 12 bits
- class: routine (local label)
- addresses: format 0531
- aliases: SF1 (source)
- status: verified

### SETFAT_MERGE — SETFAT: OR the entry into the word, store
- class: routine (local label)
- addresses: format 0538
- aliases: SF2 (source)
- status: verified

### GETFAT_MASK — GETFAT: keep the low 12 bits
- class: routine (local label)
- addresses: format 054C
- aliases: GF1 (source)
- status: verified

### MKTRACK_SECTOR — MKTRACK: build one 332-byte sector
- class: routine (local label)
- addresses: format 0568
- aliases: MK1 (source)
- status: verified

### GETSYS_NEXT — GETSYS: open and read the next SYSTAB file
- class: routine (local label)
- addresses: format 05D7
- aliases: GS1 (source)
- status: verified

### PUTSYS_NEXT — PUTSYS: create, write and close the next file
- class: routine (local label)
- addresses: format 0652
- aliases: PS1 (source)
- status: verified

### REPORT_BAD — REPORT: start counting bad clusters
- class: routine (local label)
- addresses: format 06EA
- aliases: RP1 (source)
- status: verified

### REPORT_COUNT — REPORT: test one FAT entry for FF7h
- class: routine (local label)
- addresses: format 06EF
- aliases: RP2 (source)
- status: verified

### REPORT_NEXT — REPORT: next cluster
- class: routine (local label)
- addresses: format 06F8
- aliases: RP3 (source)
- status: verified

### REPORT_AVAIL — REPORT: the "bytes available" line
- class: routine (local label)
- addresses: format 070E
- aliases: RP4 (source)
- status: verified

### DNUMM_DIGIT — DNUMM: one decimal digit by 32/16 long division
- class: routine (local label)
- addresses: format 0736
- aliases: DN1 (source)
- status: verified
