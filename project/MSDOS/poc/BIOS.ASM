; BIOS.ASM - the BIOS traps of IOFDD.SYS in Z80 code, for the FDD3000.
;
; Assembled after I86.ASM (z86.build(bios=True)). The 8086 opcode 0F nn
; calls TRAP with A = nn. A handler reads and writes the 8086 registers in
; REGS and sets ZF / CF in AF' (the 8086 flags); TRAP keeps BC (the 8086
; code pointer) and IX (the dispatcher).
;
; The hardware code is CBIOS A1.1's, which runs on real FDD3000s:
;   console  the nibble protocol to the terminal on port 2Fh (CBIOS FAA8h
;            send, FB0Dh receive, F719h status)
;   disk     WD177x on C0h-C3h, drive latch E0h, DRQ in bit 7 of port 2Fh.
;            A command ends with INTRQ on the Z80 INT line (IM 1, RST 38h):
;            0038h is pointed at FDCINT for the duration of a disk call,
;            which leaves the transfer loop and returns the status (CBIOS
;            FBE2h / FC0Ch).
;
; The FDD3000 has no clock: the date and time are what DOS last set
; (1-1-80 0:00 at boot), and INT 1Ah's tick count goes up by one per call.

NDRIVE  EQU 4                   ; drives on the latch
SPT     EQU 18                  ; sectors per track, IDs 0-17
NTRACK  EQU 40
NSECT   EQU NTRACK*SPT          ; 720
FIRDIR  EQU 5                   ; the disk layout (mkfat.py): boot sector,
FIRREC  EQU 13                  ; 2 FATs of 2 sectors, 8 directory sectors
GTOP    EQU 0D000h              ; end of the 8086's memory
RETRIES EQU 10

; ---------------------------------------------------------------- dispatch
TRAP:   PUSH BC
        PUSH IX
        CP 1Eh                  ; entries in TTAB
        JR NC,TRAPX
        ADD A,A
        LD L,A
        LD H,0
        LD DE,TTAB
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL JPHL
TRAPX:  POP IX
        POP BC
TNONE:  RET
JPHL:   JP (HL)

TTAB:   DW TNONE, T_STAT, T_INP, T_OUTP         ; 0-3
        DW T_PRINT, T_AUXIN, T_AUXOUT, T_READ   ; 4-7
        DW T_WRITE, T_DSKCHG, T_SDATE, T_STIME  ; 8-11
        DW T_GTIME, T_FLUSH, TNONE, TNONE       ; 12, 13, 14 MAPDEV, 15
        DW T_I10, T_I11, T_I12, TNONE           ; 10h-13h: IBM PC ROM BIOS
        DW T_I14, TNONE, T_I16, T_I17           ; 14h-17h
        DW TNONE, TNONE, T_I1A                  ; 18h-1Ah
        DW T_FMT, T_CPML, T_RET                 ; 1Bh: FORMAT.COM, 1Ch-1Dh: CPM.COM
TTEND:

; 8086 flags in F': F' = F' AND D OR E
ZF1:    LD DE,0BF40h
        JR FSET
ZF0:    LD DE,0BF00h
        JR FSET
CF1:    LD DE,0FE01h
        JR FSET
CF0:    LD DE,0FE00h
FSET:   EX AF,AF'
        PUSH AF
        POP HL
        LD A,L
        AND D
        OR E
        LD L,A
        PUSH HL
        POP AF
        EX AF,AF'
        RET

; ---------------------------------------------------------------- console
; 1 STATUS: ZF=1 no key; else ZF=0, AL = the key (left for INP)
T_STAT: CALL PEEKEY
        JP NC,ZF1
        LD (R_AL),A
        JP ZF0

; 2 INP: AL = key (waits)
T_INP:  CALL GETKEY
        LD (R_AL),A
        RET

; 3 OUTP: AL to the screen
T_OUTP: LD A,(R_AL)
        JP CONOUT

; 4 PRINT: AL to the printer (WD2123 channel A); 6 AUXOUT: AL to AUX
; (channel B); 5 AUXIN: AL from AUX. They wait as long as it takes, as
; CP/M's LIST, PUNCH and READER do (the serial routines are in I86.ASM's
; register page).
T_PRINT:
        LD A,(R_AL)
        JP SPRN
T_AUXOUT:
        LD A,(R_AL)
        JP SAUXO
T_AUXIN:
        CALL SAUXI
        LD (R_AL),A
        RET

; 13 FLUSH: drop the keys typed ahead
T_FLUSH:
        XOR A
        LD (KFLAG),A
FL1:    IN A,(2Fh)
        AND 5Fh
        CP 04h
        RET NZ
        CALL CONIN
        JR FL1

; PEEKEY: CF=1 and A = the next key, which stays for GETKEY; CF=0 none.
; The link can't look at a key without taking it, so it is kept here.
PEEKEY: LD A,(KFLAG)
        OR A
        JR NZ,PK1
        IN A,(2Fh)
        AND 5Fh
        CP 04h                  ; the terminal has a key
        RET NZ                  ; (NC)
        CALL CONIN
        LD (KBUF),A
        LD A,1
        LD (KFLAG),A
PK1:    LD A,(KBUF)
        SCF
        RET

; GETKEY: A = next key (waits)
GETKEY: LD HL,KFLAG
        LD A,(HL)
        OR A
        JP Z,CONIN
        LD (HL),0
        LD A,(KBUF)
        RET

; CONOUT: A to the terminal (CBIOS FAA8h). Uses A, BC, DE.
CONOUT: LD (COCHR),A
CO1:    LD A,(COCHR)
        LD B,A
        CALL COSEND
        RET Z
CO2:    IN A,(2Fh)              ; timed out: wait for the terminal's abort
        AND 5Fh
        CP 07h
        JR NZ,CO2
        JR CO1

; COSEND: B in two nibbles, each echoed back. Z = sent.
COSEND: LD A,B
        AND 0Fh
        LD E,A
        LD A,B
        AND 0F0h
        RRCA
        RRCA
        RRCA
        RRCA
        LD D,A
COS1:   LD A,0Ah                ; ask to send
        OUT (2Fh),A
        IN A,(2Fh)
        AND 5Fh
        CP 0Fh                  ; terminal ready
        JR NZ,COS1
        LD A,E
        OR 10h                  ; low nibble
        OUT (2Fh),A
        LD B,A
        LD C,0
COS2:   IN A,(2Fh)
        DEC C
        JR Z,LKFAIL
        AND 5Fh
        CP B
        JR NZ,COS2
        LD A,D
        OR 40h                  ; high nibble
        OUT (2Fh),A
        LD B,A
        LD C,0
COS3:   IN A,(2Fh)
        DEC C
        JR Z,LKFAIL
        AND 5Fh
        CP B
        JR NZ,COS3
        LD A,50h                ; done
        OUT (2Fh),A
        XOR A
        RET
LKFAIL: LD A,07h                ; abort
        OUT (2Fh),A
        AND A
        RET

; CONIN: A = key from the terminal, 7 bits (CBIOS FB0Dh). Uses A, BC, DE.
CONIN:  CALL CIRECV
        JR Z,CI2
CI1:    IN A,(2Fh)
        AND 5Fh
        CP 07h
        JR Z,CI1
        JR CONIN
CI2:    LD A,B
        RET

CIRECV: LD A,06h                ; ask for a key
        OUT (2Fh),A
        IN A,(2Fh)
        AND 5Fh
        CP 05h                  ; one is coming
        JR NZ,CIRECV
        LD A,0Fh
        OUT (2Fh),A
        LD C,0
CIR1:   IN A,(2Fh)              ; low nibble: 1x
        DEC C
        JR Z,LKFAIL
        LD E,A
        AND 50h
        CP 10h
        JR NZ,CIR1
        LD A,E
        OUT (2Fh),A             ; echo
        AND 0Fh
        LD E,A
        LD C,0
CIR2:   IN A,(2Fh)              ; high nibble: 4x
        DEC C
        JR Z,LKFAIL
        BIT 6,A
        JR Z,CIR2
        OUT (2Fh),A
        AND 0Fh
        RLCA
        RLCA
        RLCA
        RLCA
        OR E
        AND 7Fh
        LD B,A
CIR3:   IN A,(2Fh)
        AND 5Fh
        CP 07h
        JR Z,LKFAIL
        CP 50h
        JR NZ,CIR3
        LD A,50h
        OUT (2Fh),A
        XOR A
        RET

; ---------------------------------------------------------------- disk
; 7 READ / 8 WRITE: AL = drive, DS:BX = buffer, CX = sectors, DX = first
; logical sector. CF=1 on error with AL = DOS error code, CX = sectors left.
T_READ: XOR A
        JR DISKIO
T_WRITE:
        LD A,1
DISKIO: LD (DWRITE),A
        LD A,(R_AL)
        CP NDRIVE
        JR NC,DNRDY
        LD (DDRIVE),A
        LD HL,(B_DS)
        LD DE,(R_BX)
        ADD HL,DE
        LD (DADDR),HL
        CALL HOOK38
DLOOP:  LD HL,(R_CX)
        LD A,H
        OR L
        JR Z,DDONE
        LD HL,(R_DX)
        LD DE,NSECT
        OR A
        SBC HL,DE
        LD A,10h                ; past the last sector: not found
        JR NC,DFAIL
        LD HL,(DADDR)
        LD DE,GTOP-255
        OR A
        SBC HL,DE
        LD A,01h                ; buffer beyond the 8086's memory
        JR NC,DFAIL
        LD HL,(R_DX)            ; track = DX / 18, B; sector = DX MOD 18
        LD DE,-SPT
        LD B,0FFh
DV1:    INC B
        ADD HL,DE
        JR C,DV1
        LD A,B
        LD (DTRK),A
        LD A,L
        ADD A,SPT
        LD E,A                  ; sector ID: 2:1 interleave in the track
        LD D,0
        LD HL,SKEW
        ADD HL,DE
        LD A,(HL)
        LD (DSEC),A
        CALL SECTIO
        JR NZ,DFAIL
        LD HL,(DADDR)
        INC H
        LD (DADDR),HL
        LD HL,(R_DX)
        INC HL
        LD (R_DX),HL
        LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        JR DLOOP
DDONE:  CALL UNHOOK
        JP CF0
DFAIL:  PUSH AF
        CALL UNHOOK
        POP AF
        LD HL,ERRTAB            ; the status's top bit -> DOS error code
        LD B,5
DF1:    RLA
        JR C,DF2
        INC HL
        DJNZ DF1
DF2:    LD A,(HL)
DERR:   LD (R_AL),A
        JP CF1
DNRDY:  LD A,2                  ; no such drive: not ready
        JR DERR

ERRTAB: DB 6                    ; 80h seek failed: seek error
        DB 0                    ; 40h write protect
        DB 2                    ; 20h no track 0 (no drive): not ready
        DB 8                    ; 10h record not found
        DB 4                    ; 08h CRC: data error
        DB 0Ch                  ; lost data, bad buffer: general failure

; SECTIO: one sector, DSEC of track DTRK, at DADDR. Z = done; else
; A = status (as ERRTAB).
SECTIO: LD A,(DDRIVE)
        CALL SELECT
        RET NZ
        LD A,RETRIES
        LD (DTRY),A
SIO1:   CALL SEEK
        RET NZ
        LD A,(DSEC)
        OUT (0C2h),A
        LD HL,(DADDR)
        LD A,(DWRITE)
        OR A
        JR NZ,SIO2
        CALL RDSEC
        JR SIO3
SIO2:   CALL WRSEC
SIO3:   OR A
        RET Z
        BIT 6,A                 ; write protected: no point retrying
        RET NZ
        LD (DSTAT),A
        LD HL,DTRY
        DEC (HL)
        JR NZ,SIO1
        LD A,(DSTAT)
        OR A
        RET

; RDSEC / WRSEC: 256 bytes at HL (CBIOS F8ECh / F934h). They end when
; INTRQ goes through 0038h to FDCINT: A = status AND 5Ch.
RDSEC:  LD C,0C3h
        IM 1
        EI
        LD A,80h                ; read sector
        OUT (0C0h),A
RD1:    IN A,(2Fh)              ; bit 7 = DRQ
        RLA
        JR NC,RD1
        INI
        JR RD1

WRSEC:  LD C,0C3h
        IM 1
        EI
        LD A,0A0h               ; write sector
        OUT (0C0h),A
WR1:    IN A,(2Fh)
        RLA
        JR NC,WR1
        OUTI
        JR WR1

; FDCCMD: command A, wait for INTRQ: A = status AND 5Ch.
FDCCMD: IM 1
        EI
        OUT (0C0h),A
FDCW:   JR FDCW

FDCINT: POP AF                  ; drop the waiting loop's address
        IN A,(0C0h)             ; status; clears INTRQ
        AND 5Ch
        RET                     ; to whoever called the loop (DI stays)

; SEEK: to DTRK with verify (CBIOS FB7Ch). Z = there; NZ, A = 80h failed.
SEEK:   LD A,(DTRK)
        LD B,A
        IN A,(0C1h)
        CP B
        JR Z,SKOK
        LD A,RETRIES
        LD (STRY),A
SK1:    LD A,B
        OUT (0C3h),A
        LD A,15h                ; seek, verify
        CALL FDCCMD
        AND 18h                 ; seek error, CRC
        RET Z
        CALL FHOME
        LD HL,STRY
        DEC (HL)
        JR NZ,SK1
        LD A,80h
        OR A
        RET
SKOK:   XOR A
        RET

; FHOME: restore to track 0, polled (CBIOS F7B5h). NZ: seek error, the
; drive never showed track 0.
FHOME:  LD A,(RESCMD)
        OUT (0C0h),A
        PUSH BC
        LD B,12h                ; let the FDC raise BUSY
FH0:    DJNZ FH0
        POP BC
FH1:    IN A,(0C0h)
        RRA
        JR C,FH1
        RLA
        AND 10h
        RET

; SELECT: drive A on, head loaded; the FDC track register is set to
; where that drive's head is (CBIOS FA1Eh). A drive not used yet is
; restored first. Z = done; NZ, A = 20h: the restore failed (no drive).
SELECT: LD C,A
        LD A,(CURDRV)
        CP C
        JR NZ,SEL0
        CALL LATCHC
        XOR A
        RET
SEL0:   CP NDRIVE
        JR NC,SEL1
        CALL TRKPTR             ; keep the old drive's track
        IN A,(0C1h)
        LD (HL),A
SEL1:   LD A,C
        LD (CURDRV),A
        CALL LATCHC
        LD A,C
        CALL TRKPTR
        LD A,(HL)
        CP 0FFh
        JR Z,SEL2
        OUT (0C1h),A
        XOR A
        RET
SEL2:   CALL FHOME
        RET Z
        LD A,0FFh               ; restore it again next time
        LD (CURDRV),A
        LD A,20h
        OR A
        RET

; LATCHC: latch = drive C selected (bits 0-3 low active), side 0 (bit 4
; high), boot ROM off (bit 6 high), head loaded (bit 7 low)
LATCHC: LD B,C
        INC B
        LD A,0FEh
LC1:    DEC B
        JR Z,LC2
        RLCA
        JR LC1
LC2:    AND 5Fh
        OUT (0E0h),A
        LD (LATCH),A
        RET

TRKPTR: LD HL,TRKTAB
        ADD A,L
        LD L,A
        RET NC
        INC H
        RET

; HOOK38 / UNHOOK: point 0038h (the 8086's INT 0Eh vector) at FDCINT for a
; disk call, then put the vector back and unload the head.
HOOK38: LD HL,0038h
        LD DE,SAV38
        LD BC,3
        LDIR
        LD A,0C3h               ; JP FDCINT
        LD (0038h),A
        LD HL,FDCINT
        LD (0039h),HL
        RET

UNHOOK: DI
        LD HL,SAV38
        LD DE,0038h
        LD BC,3
        LDIR
        LD A,(LATCH)
        OR 80h
        OUT (0E0h),A
        LD (LATCH),A
        RET

; 1Bh FORMAT TRACK, for FORMAT.COM: AL = drive, DL = track, DS:BX = the
; track image, FMTLEN bytes as the WD177x write track takes them (F5h =
; sync, F7h = CRC; FORMAT.COM makes it as the CP/M FORMAT 2.0 does). The
; FDC then writes 4Eh until the index pulse. CF=1 on error, AL = DOS error
; code (0 write protect, 2 not ready, 8 no such track, 0Ch buffer).
FMTLEN  EQU 32+SPT*332          ; FORMAT.ASM's image
T_FMT:  LD A,(R_AL)
        CP NDRIVE
        JR NC,DNRDY
        LD (DDRIVE),A
        CALL HOOK38
        LD A,(R_DL)
        LD (DTRK),A
        CP NTRACK
        LD A,10h
        JP NC,DFAIL
        LD HL,(B_DS)
        LD DE,(R_BX)
        ADD HL,DE
        LD (DADDR),HL
        LD DE,GTOP-FMTLEN+1
        OR A
        SBC HL,DE
        LD A,01h
        JP NC,DFAIL
        LD A,01h                ; restore without verify: no IDs there yet
        LD (RESCMD),A
        LD A,(DDRIVE)
        CALL SELECT
        LD B,A
        LD A,05h
        LD (RESCMD),A
        LD A,B
        JP NZ,DFAIL
        LD A,(DTRK)             ; seek without verify too
        OUT (0C3h),A
        LD A,11h
        CALL FDCCMD
        LD HL,(DADDR)
        LD DE,FMTLEN
        LD C,0C3h
        LD A,0FEh               ; write track, as FORMAT 2.0
        OUT (0C0h),A
FT1:    IN A,(2Fh)              ; bit 7 = DRQ
        ADD A,A
        JR NC,FT3
        OUTI
        DEC DE
        LD A,D
        OR E
        JR NZ,FT1
FT2:    IN A,(2Fh)              ; gap 4Eh until the index pulse ends it
        ADD A,A
        JR NC,FT4
        LD A,4Eh
        OUT (0C3h),A
        JR FT2
FT4:    IN A,(0C0h)
        RRA
        JR C,FT2
        JR FT5
FT3:    IN A,(0C0h)
        RRA
        JR C,FT1
FT5:    IN A,(0C0h)
        AND 40h                 ; write protect
        JP NZ,DFAIL
        JP DDONE

; 9 DSKCHG: AH=0, don't know
T_DSKCHG:
        XOR A
        LD (R_AH),A
        JP CF0

; ---------------------------------------------------------------- clock
; 10 SETDATE: AX = days since 1-1-80
T_SDATE:
        LD HL,(R_AX)
        LD (DAYS),HL
        RET

; 11 SETTIME: CH hour, CL minute, DH second, DL 1/100
T_STIME:
        LD HL,(R_CX)
        LD (CLKCX),HL
        LD HL,(R_DX)
        LD (CLKDX),HL
        RET

; 12 GETTIME: AX = days, CX and DX as SETTIME
T_GTIME:
        LD HL,(DAYS)
        LD (R_AX),HL
        LD HL,(CLKCX)
        LD (R_CX),HL
        LD HL,(CLKDX)
        LD (R_DX),HL
        RET

; ---------------------------------------------------------------- PC ROM BIOS
; The parts PC-DOS programs (IBM's DEBUG, CHKDSK...) use, on the VT52
; terminal: as fddos.rom_bios.

; INT 10h video
T_I10:  LD A,(R_AH)
        CP 0Eh                  ; teletype
        JR NZ,I10A
        LD A,(R_AL)
        JP CONOUT
I10A:   CP 0Fh                  ; mode: 80 columns, mono
        JR NZ,I10B
        LD HL,5007h
        LD (R_AX),HL
        XOR A
        LD (R_BH),A
        RET
I10B:   CP 02h                  ; cursor to DH, DL: ESC Y row col
        JR NZ,I10C
        LD A,1Bh
        CALL CONOUT
        LD A,59h
        CALL CONOUT
        LD A,(R_DH)
        CP 23
        JR C,I10B1
        LD A,23
I10B1:  ADD A,32
        CALL CONOUT
        LD A,(R_DL)
        CP 79
        JR C,I10B2
        LD A,79
I10B2:  ADD A,32
        JP CONOUT
I10C:   CP 03h                  ; read cursor: not tracked
        JR NZ,I10D
        LD HL,0
        LD (R_DX),HL
        LD HL,0607h
        LD (R_CX),HL
        RET
I10D:   CP 06h                  ; scroll with AL=0: clear the screen
        JR Z,I10D1
        CP 07h
        JR NZ,I10E
I10D1:  LD A,(R_AL)
        OR A
        RET NZ
        LD A,1Bh
        CALL CONOUT
        LD A,48h                ; ESC H
        CALL CONOUT
        LD A,1Bh
        CALL CONOUT
        LD A,4Ah                ; ESC J
        JP CONOUT
I10E:   CP 09h                  ; AL, CX times
        JR Z,I10E1
        CP 0Ah
        RET NZ
I10E1:  LD HL,(R_CX)
I10E2:  LD A,H
        OR L
        RET Z
        PUSH HL
        LD A,(R_AL)
        CALL CONOUT
        POP HL
        DEC HL
        JR I10E2

; INT 11h equipment: 2 floppies, 80x25 mono
T_I11:  LD HL,0071h
        LD (R_AX),HL
        RET

; INT 12h memory in KB
T_I12:  LD HL,GTOP/1024
        LD (R_AX),HL
        RET

; INT 16h keyboard: AH=0 wait, AH=1 look (ZF=1 none)
T_I16:  LD A,(R_AH)
        OR A
        JR NZ,I16A
        CALL GETKEY
        LD L,A
        LD H,0
        LD (R_AX),HL
        RET
I16A:   DEC A
        JR NZ,I16B
        CALL PEEKEY
        JP NC,ZF1
        LD L,A
        LD H,0
        LD (R_AX),HL
        JP ZF0
I16B:   XOR A
        LD (R_AL),A
        RET

; INT 14h serial: DX = 0 channel A, 1 channel B. AH = 0 set up from AL
; (PC format), 1 send AL, 2 receive into AL, 3 status, 4 set up from BX
; and CX (PS/2 format), F0h and F1h read and set the WD2123's own mode
; byte and baud code (I14X, in I86.ASM). Returns AH = line status (bit 7:
; timed out) and AL = modem status (but the byte received, for AH = 2).
T_I14:  LD HL,(R_DX)
        LD C,81h
        LD A,H
        OR A
        RET NZ
        OR L
        JR Z,I14A
        DEC A
        RET NZ
        LD C,41h
I14A:   LD A,(R_AH)
        OR A
        JP Z,I14INI             ; (in I86.ASM)
        DEC A
        JR Z,I14PUT
        DEC A
        JR Z,I14GET
        DEC A
        JP Z,SSTAT
        DEC A
        JP I14X                 ; 4, F0h, F1h (in I86.ASM, with 0)
I14PUT: LD A,(R_AL)
        LD E,A
        LD HL,0FFFFh            ; about 1.5 s
        CALL SPUT
        JR I14T
I14GET: LD HL,0FFFFh
        CALL SGET
        LD E,A
I14T:   SBC A,A                 ; CF: timed out
        AND 80h
        LD D,A
        PUSH DE
        CALL SSTAT
        POP DE
        LD A,E
        LD (R_AL),A
        LD HL,R_AH
        LD A,D
        OR (HL)
        LD (HL),A
        RET

; INT 17h printer (channel A, whatever DX is): AH = 0 print AL, 1 set up
; (nothing to do), 2 status. AH = 90h ready, 10h busy (no CTS), +1 timed out.
T_I17:  LD C,81h
        LD E,0
        LD A,(R_AH)
        OR A
        JR NZ,I17A
        LD A,(R_AL)
        LD E,A
        LD HL,0FFFFh
        CALL SPUT
        SBC A,A
        AND 1
        LD E,A
I17A:   IN A,(C)
        RLA
        LD A,10h
        JR NC,I17B
        LD A,90h
I17B:   OR E
        LD (R_AH),A
        RET

; INT 1Ah AH=0: CX:DX = ticks (one more each call), AL = 0
T_I1A:  LD A,(R_AH)
        OR A
        RET NZ
        LD (R_AL),A
        LD HL,(TICKS+2)
        LD (R_CX),HL
        LD HL,(TICKS)
        LD (R_DX),HL
        INC HL
        LD (TICKS),HL
        LD A,H
        OR L
        RET NZ
        LD HL,(TICKS+2)
        INC HL
        LD (TICKS+2),HL
        RET

; ---------------------------------------------------------------- CP/M
; 1Ch: CPM.COM's Z80 part (CPMZ80.ASM), which runs CP/M programs. BP =
; its linear address: a length word, the BIOS addresses it was assembled
; with (CPMSYM), then the code, for ENDBIOS. It is copied there; a
; CPM.COM made for another build of Z86.SYS gets CF=1 instead. BP = 0:
; run it (T_CPM, at ENDBIOS).
T_CPML: LD HL,(R_BP)
        LD A,H
        OR L
        JP Z,ENDBIOS
        LD C,(HL)
        INC HL
        LD B,(HL)
        INC HL
        PUSH BC
        LD DE,CPMSYM
        LD B,CPMSYE-CPMSYM
TL1:    LD A,(DE)
        CP (HL)
        JR NZ,TL2
        INC DE
        INC HL
        DJNZ TL1
        POP BC
        LD DE,ENDBIOS
        LDIR
        JP CF0
TL2:    POP BC
        JP CF1

; 1Dh: the end of an INT 21h that CPMZ80's DOSCALL started: back to
; DOSCALL's caller, on the Z80 stack it had
T_RET:  LD HL,(DCSP)
        LD A,H
        OR L
        RET Z
        LD SP,HL
        LD HL,0
        LD (DCSP),HL
        RET

CPMSYM: DW NEXT, JPHL, PEEKEY, GETKEY, CONOUT, DCSP, ENDBIOS
CPMSYE:

; ---------------------------------------------------------------- data
SKEW:   DB 0,2,4,6,8,10,12,14,16,1,3,5,7,9,11,13,15,17
RESCMD: DB 05h                  ; FHOME's restore: verify (FORMAT: 01h)
KFLAG:  DB 0                    ; 1: KBUF holds a key
KBUF:   DB 0
COCHR:  DB 0
CURDRV: DB 0FFh                 ; drive selected last (FFh none yet)
TRKTAB: DB 0FFh,0FFh,0FFh,0FFh  ; head position per drive (FFh unknown)
LATCH:  DB 0FFh
DWRITE: DB 0
DDRIVE: DB 0
DTRK:   DB 0
DSEC:   DB 0
DTRY:   DB 0
STRY:   DB 0
DSTAT:  DB 0
DADDR:  DW 0
SAV38:  DB 0,0,0
DAYS:   DW 0
CLKCX:  DW 0
CLKDX:  DW 0
TICKS:  DW 0,0
DCSP:   DW 0                    ; CPMZ80: Z80 SP in DOSCALL (0: none)

; ENDBIOS: CPM.COM's Z80 part (CPMZ80.ASM) is copied here, over COLD, which
; is needed only at boot.
ENDBIOS:
; ---------------------------------------------------------------- cold boot
; COLD: from the boot sector (BOOT.ASM) through D0FDh, with this image
; (Z86.SYS) at D000h and the boot ROM paged out. Clears the 8086 vectors,
; reads the first directory sector, then IO.SYS (entry 1) to 0040:0000
; and MSDOS.SYS (entry 2) to 0060:0000 through READ - each contiguous
; from its first cluster, as FORMAT /S and mkfat write them - and starts
; the 8086 at 0040:0000 with CS = DS = 0040h, as fddos.boot does. A read
; error or a missing file prints a message and stops.
DIRBUF  EQU 0C000h              ; in the 8086's memory, free at boot
COLD:   DI
        LD SP,0
        LD C,81h                ; both serial channels as CBIOS A1.1 sets
        LD DE,8E08h             ;   them: 8 bits, no parity, 1.5 stop bits,
        CALL SSET               ;   1200 baud (code 8)
        LD C,41h
        CALL SSET
        LD HL,0
        LD DE,1
        LD BC,3FFh
        LD (HL),L
        LDIR
        LD HL,DIRBUF
        LD DE,1
        LD BC,FIRDIR
        CALL CLOAD
        LD HL,DIRBUF+32
        LD DE,IONAM
        LD BC,0400h
        LD A,3                  ; under 3 sectors: MSDOS.SYS is at 0600h
        CALL CFILE
        LD HL,DIRBUF+64
        LD DE,DOSNAM
        LD BC,0600h
        LD A,41                 ; 10 KB at most
        CALL CFILE
        LD HL,R_AX              ; AX-DI and the segment registers: 0
        LD B,24
CB1:    LD (HL),0
        INC HL
        DJNZ CB1
        LD HL,40h
        LD (R_CS),HL
        LD (R_DS),HL
        LD HL,0
        LD (TMP),HL             ; IP
        XOR A
        LD (FLAGHI),A
        LD HL,0100h             ; F' = 0, A' = 1 (odd: PF = 0)
        PUSH HL
        POP AF
        EX AF,AF'
        JP START

; CFILE: directory entry HL, which must be named as at DE, to 0000:BC;
; fewer than A sectors
CFILE:  PUSH BC
        PUSH AF
        PUSH HL
        LD B,11
CFL1:   LD A,(DE)
        CP (HL)
        JR NZ,CBAD
        INC DE
        INC HL
        DJNZ CFL1
        POP HL
        LD DE,26
        ADD HL,DE
        LD E,(HL)               ; DE = first cluster
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)               ; size -> sectors
        INC HL
        OR A
        LD A,(HL)
        JR Z,CFL2
        INC A
CFL2:   POP BC                  ; B = the limit
        CP B
        JR NC,CBAD
        EX DE,HL
        DEC HL                  ; logical sector = FIRREC + 4 (cluster - 2)
        DEC HL
        ADD HL,HL
        ADD HL,HL
        LD BC,FIRREC
        ADD HL,BC
        LD B,H
        LD C,L
        LD E,A
        LD D,0
        POP HL
; CLOAD: DE sectors from logical sector BC of drive A to 0000:HL
CLOAD:  LD (R_BX),HL
        LD (R_CX),DE
        LD (R_DX),BC
        XOR A
        LD (R_AL),A
        LD H,A
        LD L,A
        LD (B_DS),HL
        CALL T_READ
        LD HL,(R_CX)
        LD A,H
        OR L
        RET Z
CBAD:   LD HL,BOOTMSG
CB2:    LD A,(HL)
        OR A
        JR Z,CB3
        PUSH HL
        CALL CONOUT
        POP HL
        INC HL
        JR CB2
CB3:    DI
        HALT

BOOTMSG:
        DB 13,10,'Disk boot failure',13,10,0
IONAM:  DB 'IO      SYS'
DOSNAM: DB 'MSDOS   SYS'
BIOSEND:                        ; the end of Z86.SYS
        END
