# Z86.SYS part 08 dictionary (EDDCh-F220h)

## Equates

### RSTCMD — WD177x Restore with verify, 12 ms (05h)
- class: constant
- addresses: z86 RESCMD default (F10Ah), T_FMT EEE1
- aliases: none (CBIOS RSTCMD, same value)
- status: verified (code + BIOS.ASM + CBIOS)

### RSTCMD_NOVFY — Restore without verify (01h)
- class: constant
- addresses: z86 T_FMT EED5
- aliases: none (boot.asm name, same value)
- status: verified

### SEKCMD — Seek with verify, 12 ms (15h)
- class: constant
- addresses: z86 SEEK EDFA
- aliases: none (CBIOS SEKCMD)
- status: verified

### SEKCMD_NOVFY — Seek without verify (11h)
- class: constant
- addresses: z86 T_FMT EEEF
- status: verified

### WTKCMD — Write Track, h=1 E=1 P=1 (FEh)
- class: constant
- addresses: z86 T_FMT EEFC
- status: verified (code); "as FORMAT 2.0" provisional (source comment only)

### FDC_STAT_MASK — status bits FDCINT returns (5Ch: 6, 4, 3, 2)
- class: constant
- addresses: z86 FDCINT EDE6
- status: verified; CBIOS uses 9Ch

### FDC_SKERR_MASK — Type I seek error + ID CRC (18h)
- class: constant
- addresses: z86 SEEK EDFF
- status: verified

### FDC_SEEKERR — Type I bit 4, seek error (10h)
- class: constant
- addresses: z86 FHOME EE22
- status: verified

### FDC_WPROT — write protect status bit 6 (40h)
- class: constant
- addresses: z86 T_FMT EF25
- status: verified

## Renamed labels

### SEEK_RETRY — SEEK's seek-verify / restore retry loop
- class: routine (local)
- addresses: z86 EDF7
- aliases: SK1 (source)
- status: verified (code + BIOS.ASM)

### FHOME_DELAY — pause for BUSY to rise after the Restore
- class: routine (local)
- addresses: z86 EE19
- aliases: FH0 (source)
- status: verified

### FHOME_WAIT — poll BUSY until the Restore ends
- class: routine (local)
- addresses: z86 EE1C
- aliases: FH1 (source)
- status: verified

### SELECT_CHANGE — another drive: save the old one's head position
- class: routine (local)
- addresses: z86 EE31
- aliases: SEL0 (source)
- status: verified

### SELECT_NEW — make the new drive current and load its position
- class: routine (local)
- addresses: z86 EE3B
- aliases: SEL1 (source)
- status: verified

### SELECT_RESTORE — position unknown: restore it
- class: routine (local)
- addresses: z86 EE4F
- aliases: SEL2 (source)
- status: verified

### LATCHC_SHIFT — rotate the select 0 to drive C's bit
- class: routine (local)
- addresses: z86 EE60
- aliases: LC1 (source)
- status: verified

### LATCHC_OUT — mask and write the latch
- class: routine (local)
- addresses: z86 EE66
- aliases: LC2 (source)
- status: verified

### T_FMT_IMAGE — feed the track image on DRQ
- class: routine (local)
- addresses: z86 EF00
- aliases: FT1 (source)
- status: verified

### T_FMT_GAP — feed 4Eh until the index pulse
- class: routine (local)
- addresses: z86 EF0C
- aliases: FT2 (source)
- status: verified

### T_FMT_IMAGE_IDLE — no DRQ during the image: BUSY check
- class: routine (local)
- addresses: z86 EF1E
- aliases: FT3 (source)
- status: verified

### T_FMT_GAP_IDLE — no DRQ during the gap: BUSY check
- class: routine (local)
- addresses: z86 EF17
- aliases: FT4 (source)
- status: verified

### T_FMT_STATUS — final status, write-protect test
- class: routine (local)
- addresses: z86 EF23
- aliases: FT5 (source)
- status: verified

### T_I10_MODE — INT 10h AH 0Fh get mode
- class: routine (local)
- addresses: z86 EF68
- aliases: I10A (source)
- status: verified

### T_I10_SETCUR — INT 10h AH 02h, VT52 ESC Y
- class: routine (local)
- addresses: z86 EF77
- aliases: I10B (source)
- status: verified

### T_I10_ROW — row byte (clamped) out
- class: routine (local)
- addresses: z86 EF8E
- aliases: I10B1 (source)
- status: verified

### T_I10_COL — column byte (clamped) out
- class: routine (local)
- addresses: z86 EF9C
- aliases: I10B2 (source)
- status: verified

### T_I10_GETCUR — INT 10h AH 03h, fixed answer
- class: routine (local)
- addresses: z86 EFA1
- aliases: I10C (source)
- status: verified

### T_I10_SCROLL — INT 10h AH 06h/07h test
- class: routine (local)
- addresses: z86 EFB2
- aliases: I10D (source)
- status: verified

### T_I10_CLEAR — AL = 0: ESC H ESC J
- class: routine (local)
- addresses: z86 EFBA
- aliases: I10D1 (source)
- status: verified

### T_I10_WRCHR — INT 10h AH 09h/0Ah test
- class: routine (local)
- addresses: z86 EFD3
- aliases: I10E (source)
- status: verified

### T_I10_REPEAT — load the CX count
- class: routine (local)
- addresses: z86 EFDA
- aliases: I10E1 (source)
- status: verified

### T_I10_REPEAT_LOOP — AL out CX times
- class: routine (local)
- addresses: z86 EFDD
- aliases: I10E2 (source)
- status: verified

### T_I16_PEEK — INT 16h AH 1, look for a key
- class: routine (local)
- addresses: z86 F009
- aliases: I16A (source)
- status: verified

### T_I16_OTHER — INT 16h AH 2+, AL = 0
- class: routine (local)
- addresses: z86 F01B
- aliases: I16B (source)
- status: verified

### T_I14_FUNC — INT 14h function dispatch (C = channel)
- class: routine (local)
- addresses: z86 F02F
- aliases: I14A (source)
- status: verified

### T_I14_STATUS — INT 14h AH 1/2 result: SSTAT + timeout bit
- class: routine (local)
- addresses: z86 F058
- aliases: I14T (source)
- status: verified

### T_I17_STATUS — INT 17h status from DSR
- class: routine (local)
- addresses: z86 F084
- aliases: I17A (source)
- status: verified

### T_I17_SET — INT 17h AH = status + timeout
- class: routine (local)
- addresses: z86 F08D
- aliases: I17B (source)
- status: verified

### T_CPML_CHECK — compare CPM.COM's 7 addresses with CPMSYM
- class: routine (local)
- addresses: z86 F0C7
- aliases: TL1 (source)
- status: verified

### T_CPML_BAD — header mismatch: CF=1
- class: routine (local)
- addresses: z86 F0D8
- aliases: TL2 (source)
- status: verified

### COLD_CLEAR_REGS — zero the 8086 registers D000h-D017h
- class: routine (local)
- addresses: z86 F176
- aliases: CB1 (source)
- status: verified

### CFILE_NAME — compare the 11-byte directory name
- class: routine (local)
- addresses: z86 F19C
- aliases: CFL1 (source)
- status: verified

### CFILE_LIMIT — size in sectors against the limit
- class: routine (local)
- addresses: z86 F1B4
- aliases: CFL2 (source)
- status: verified

### CBAD_PRINT — print "Disk boot failure"
- class: routine (local)
- addresses: z86 F1E7
- aliases: CB2 (source)
- status: verified

### CBAD_HALT — DI / HALT, final stop
- class: routine (local)
- addresses: z86 F1F3
- aliases: CB3 (source)
- status: verified
