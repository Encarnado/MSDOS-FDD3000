# CPMZ80.BIN dictionary (volume 3)

Renamed labels, each from a numbered source local, and new equates. Every other
label is the author's (CPMZ80.ASM). Addresses are CPMZ80 run addresses (the image
runs at F12Ch). The old local TC1 is unrelated to CPM.ASM's own TC1 (a separate
assembly).

## Renamed labels

### T_CPM_SEG_SHIFT — T_CPM: the loop that shifts P right 4 times to get SEGP
- class: routine (local entry or loop)
- addresses: cpmz80 F16E
- aliases: TC1 (source)
- status: verified (code + CPMZ80.ASM)

### T_CPM_BIOS_JP — T_CPM: builds one JP of the 17-entry BIOS vector at P+100h
- class: routine (local entry or loop)
- addresses: cpmz80 F1B2
- aliases: TC2 (source)
- status: verified (code + CPMZ80.ASM)

### T_CPM_PAGE0 — T_CPM: after the program is copied to 0100h, starts building page zero
- class: routine (local entry or loop)
- addresses: cpmz80 F1DF
- aliases: TC3 (source)
- status: verified (code + CPMZ80.ASM)

### T_CPM_CLR_PAGE0 — T_CPM: the loop that zeroes the 256 bytes of page zero
- class: routine (local entry or loop)
- addresses: cpmz80 F1E3
- aliases: TC4 (source)
- status: verified (code + CPMZ80.ASM)

### XCHG_LEN — XCHGA/XCHGD: shared tail, BC = the length to swap
- class: routine (local entry or loop)
- addresses: cpmz80 F25D
- aliases: XC0 (source)
- status: verified (code + CPMZ80.ASM)

### XCHG_8 — XCHGA/XCHGD: one unrolled turn that swaps 8 bytes
- class: routine (local entry or loop)
- addresses: cpmz80 F264
- aliases: XC1 (source)
- status: verified (code + CPMZ80.ASM)

### BDOSE_RET — BDOSE: the return path (A = L, B = H, program SP restored)
- class: routine (local entry or loop)
- addresses: cpmz80 F31E
- aliases: BD1 (source)
- status: verified (code + CPMZ80.ASM)

### F_DIO_IN — F_DIO: E = FFh, return a waiting key or 0
- class: routine (local entry or loop)
- addresses: cpmz80 F3B3
- aliases: DIO1 (source)
- status: verified (code + CPMZ80.ASM)

### F_RDL_KEY — F_RDL: the loop head that gets the next key
- class: routine (local entry or loop)
- addresses: cpmz80 F426
- aliases: RL1 (source)
- status: verified (code + CPMZ80.ASM)

### F_RDL_STORE — F_RDL: stores and echoes an ordinary character
- class: routine (local entry or loop)
- addresses: cpmz80 F450
- aliases: RL2 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_TAB — OUTCH: the loop that expands a TAB with spaces
- class: routine (local entry or loop)
- addresses: cpmz80 F49A
- aliases: OC1 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_ONE — OUTCH: sends a character that is not a TAB
- class: routine (local entry or loop)
- addresses: cpmz80 F4A8
- aliases: OC2 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_RET — OUTCH: restores BC DE HL and returns
- class: routine (local entry or loop)
- addresses: cpmz80 F4AB
- aliases: OC4 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_COL — OUTCH: updates COL, then sends the character
- class: routine (local entry or loop)
- addresses: cpmz80 F4AF
- aliases: OC3 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_COL_CR — OUTCH_COL: CR sets the column to 0
- class: routine (local entry or loop)
- addresses: cpmz80 F4C2
- aliases: OC5 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_COL_BS — OUTCH_COL: BS moves the column back one
- class: routine (local entry or loop)
- addresses: cpmz80 F4C6
- aliases: OC6 (source)
- status: verified (code + CPMZ80.ASM)

### OUTCH_SEND — OUTCH_COL: the tail jump to CONOUT
- class: routine (local entry or loop)
- addresses: cpmz80 F4CB
- aliases: OC7 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_DTA — F_FCB: decides whether the call writes a record (34/40)
- class: routine (local entry or loop)
- addresses: cpmz80 F4F5
- aliases: FF1 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_COPYREC — F_FCB: copies the DMA record to the DTA
- class: routine (local entry or loop)
- addresses: cpmz80 F500
- aliases: FF2 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_FN — F_FCB: maps 40 to DOS 22h
- class: routine (local entry or loop)
- addresses: cpmz80 F503
- aliases: FF3 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_CALL — F_FCB: the DOS call and FBACK
- class: routine (local entry or loop)
- addresses: cpmz80 F50C
- aliases: FF4 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_RRD — F_FCB: handling for a random read (vestigial)
- class: routine (local entry or loop)
- addresses: cpmz80 F537
- aliases: FF5 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_RRD_OK — F_FCB: copies the DTA to the DMA after a good random read (vestigial)
- class: routine (local entry or loop)
- addresses: cpmz80 F54C
- aliases: FR4 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_CLOSE — F_FCB: makes a close report FFh when FERR is set
- class: routine (local entry or loop)
- addresses: cpmz80 F553
- aliases: FR5 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_CODE — F_FCB: maps DOS result codes to CP/M codes
- class: routine (local entry or loop)
- addresses: cpmz80 F569
- aliases: FR8 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_RDERR — F_FCB_CODE: read error, returns 1
- class: routine (local entry or loop)
- addresses: cpmz80 F589
- aliases: FR6 (source)
- status: verified (code + CPMZ80.ASM)

### F_FCB_WRERR — F_FCB_CODE: write error, DOS 1 becomes 2 and others become 1
- class: routine (local entry or loop)
- addresses: cpmz80 F58E
- aliases: FR7 (source)
- status: verified (code + CPMZ80.ASM)

### F_RRND_POS — F_RRND: HL = R1:R0, the record to read
- class: routine (local entry or loop)
- addresses: cpmz80 F5B3
- aliases: RR1 (source)
- status: verified (code + CPMZ80.ASM)

### RD_ANY — common read path for BDOS 20/33: serve from BUF or refill
- class: routine (local entry or loop)
- addresses: cpmz80 F5BA
- aliases: RD0 (source)
- status: verified (code + CPMZ80.ASM)

### RD_AT_END — read: the record just after BUF, EOF if BEOF is set
- class: routine (local entry or loop)
- addresses: cpmz80 F5FC
- aliases: RS1 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL — read: FLUSH, then refill BUF from DOS
- class: routine (local entry or loop)
- addresses: cpmz80 F607
- aliases: RS2 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_GO — RD_FILL: clears the counts and swaps DOS in
- class: routine (local entry or loop)
- addresses: cpmz80 F620
- aliases: RS2A (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_NEXT — RD_FILL: one DOS 14h sequential read
- class: routine (local entry or loop)
- addresses: cpmz80 F62A
- aliases: RS3 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_TAKE — RD_FILL: copies the DTA into BUF[BCNT]
- class: routine (local entry or loop)
- addresses: cpmz80 F644
- aliases: RS4 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_MORE — RD_FILL: loop test (stop at end of file or with BUF full)
- class: routine (local entry or loop)
- addresses: cpmz80 F66A
- aliases: RS5 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_EOF — RD_FILL: DOS reported end of file
- class: routine (local entry or loop)
- addresses: cpmz80 F679
- aliases: RS6 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_DONE — RD_FILL: swaps DOS out; EOF if nothing was read
- class: routine (local entry or loop)
- addresses: cpmz80 F67E
- aliases: RS7 (source)
- status: verified (code + CPMZ80.ASM)

### RD_FILL_OK — RD_FILL: sets BMODE 1 and gives the first record to the program
- class: routine (local entry or loop)
- addresses: cpmz80 F699
- aliases: RS8 (source)
- status: verified (code + CPMZ80.ASM)

### WR_ANY — common write path for BDOS 21/34/40: append to the run or start a new one
- class: routine (local entry or loop)
- addresses: cpmz80 F70E
- aliases: WR0 (source)
- status: verified (code + CPMZ80.ASM)

### WR_FLUSH — write: FLUSH the old run, report FERR
- class: routine (local entry or loop)
- addresses: cpmz80 F747
- aliases: WS2 (source)
- status: verified (code + CPMZ80.ASM)

### WR_START — write: starts a new run (BMODE 2, BSHAD)
- class: routine (local entry or loop)
- addresses: cpmz80 F759
- aliases: WS1 (source)
- status: verified (code + CPMZ80.ASM)

### WR_APPEND — write: copies the DMA record into BUF[BCNT]
- class: routine (local entry or loop)
- addresses: cpmz80 F790
- aliases: WS3 (source)
- status: verified (code + CPMZ80.ASM)

### FLUSH_REC — FLUSH: writes one record with DOS 15h
- class: routine (local entry or loop)
- addresses: cpmz80 F7D2
- aliases: FLU1 (source)
- status: verified (code + CPMZ80.ASM)

### FLUSH_END — FLUSH: sets FERR, swaps DOS out, fixes up the program's FCB
- class: routine (local entry or loop)
- addresses: cpmz80 F800
- aliases: FLU2 (source)
- status: verified (code + CPMZ80.ASM)

### FLUSH_RET — FLUSH: restores UFCB and returns
- class: routine (local entry or loop)
- addresses: cpmz80 F849
- aliases: FLU3 (source)
- status: verified (code + CPMZ80.ASM)

### PADZ_FILL — PADZ: the loop that stores ^Z
- class: routine (local entry or loop)
- addresses: cpmz80 F8B5
- aliases: PZ1 (source)
- status: verified (code + CPMZ80.ASM)

### FBACK_RC — FBACK: limits RC to 128 and stores S2 and RC
- class: routine (local entry or loop)
- addresses: cpmz80 F8FB
- aliases: FB1 (source)
- status: verified (code + CPMZ80.ASM)

### F_SRCH_FIRST — F_SRCH: selects DOS 11h, search first
- class: routine (local entry or loop)
- addresses: cpmz80 F98D
- aliases: FS0 (source)
- status: verified (code + CPMZ80.ASM)

### F_SRCH_CALL — F_SRCH: the DOS search call and DIRENT
- class: routine (local entry or loop)
- addresses: cpmz80 F98F
- aliases: FS1 (source)
- status: verified (code + CPMZ80.ASM)

### DIRENT_ZERO — DIRENT: the loop that zeroes EX..d15 of entry 0
- class: routine (local entry or loop)
- addresses: cpmz80 F9D8
- aliases: FS2 (source)
- status: verified (code + CPMZ80.ASM)

### BIOS_POPRET — B_CONST/B_CONIN/B_CONOUT: shared exit that pops HL DE BC
- class: routine (local entry or loop)
- addresses: cpmz80 FA13
- aliases: BC1 (source)
- status: verified (code + CPMZ80.ASM)

## New equates

### ENDBIOS — Z86.SYS: the end of the resident BIOS, where this image is copied and ORGed (author name, imported)
- class: constant
- addresses: value F12Ch
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### REGS_SAVED — REGS bytes kept in SAVREG: R_AX..STEP2, which includes FLAGHI (DF/IF) and the string steps
- class: constant
- addresses: value 42
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### NBDOS — number of BDOS functions in BDTAB (0-40)
- class: constant
- addresses: value 41
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### NBIOS — number of CP/M 2.2 BIOS entries, BOOT..SECTRAN
- class: constant
- addresses: value 17
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### RECLEN — one CP/M record, which is also the DOS record size used here
- class: constant
- addresses: value 128
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### IOBYTE — CP/M page zero: the I/O byte (stored, has no effect)
- class: constant
- addresses: value 0003h
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### CDISK — CP/M page zero: the current drive (user number 0 in the high nibble)
- class: constant
- addresses: value 0004h
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### TFCB — CP/M page zero: default FCB 1 (FCB 2 at 006Ch)
- class: constant
- addresses: value 005Ch
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### TBUFF — CP/M page zero: the command tail and the default DMA
- class: constant
- addresses: value 0080h
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### TPA — CP/M program load and start address
- class: constant
- addresses: value 0100h
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_EX — FCB extent (DOS: current block, low byte)
- class: constant
- addresses: value 12
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_S1 — FCB S1, reserved and used by PIP (DOS: block, high byte); zeroed for DOS
- class: constant
- addresses: value 13
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_S2 — FCB S2 (DOS: record size, low byte)
- class: constant
- addresses: value 14
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_RC — FCB record count (DOS: record size, high byte); also the RC offset in a directory entry
- class: constant
- addresses: value 15
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_D0 — FCB d0 (DOS: file size, 4 bytes)
- class: constant
- addresses: value 16
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_CR — FCB current record (the same in DOS)
- class: constant
- addresses: value 32
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_R2 — FCB random record, high byte (r0 r1 r2 at 33-35)
- class: constant
- addresses: value 35
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### FCB_LEN — length of a CP/M FCB including the random record
- class: constant
- addresses: value 36
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### DFCB_LEN — length of a DOS 1.25 FCB (adds r3)
- class: constant
- addresses: value 37
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)

### DIR_SIZE — offset of the file size in a directory entry (same name and value as boot.asm)
- class: constant
- addresses: value 28
- aliases: none (numeric in source)
- status: verified (code + CPMZ80.ASM / CP/M 2.2 and DOS 1.25 FCB layouts)
