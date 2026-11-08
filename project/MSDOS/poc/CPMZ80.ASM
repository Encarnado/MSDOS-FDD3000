; CPMZ80.ASM - the Z80 part of CPM.COM: CP/M 2.2 programs on the FDD3000's
; Z80, under MS-DOS 1.25.
;
; Assembled by z86.py after I86.ASM and BIOS.ASM, with their symbols, at
; ENDBIOS: over the BIOS's COLD, which only the boot needs (the ORG below
; moves the address, not the output). build.py puts it in CPM.COM
; (CPMZ80.INC). BIOS trap 1Ch copies it to ENDBIOS; trap 1Ch with BP = 0 then jumps to T_CPM, with
; CPM.COM's registers:
;   BX = SWLEN: CPM.COM's end, linear; DOS, COMMAND and CPM.COM are below
;   DX = P: the page above the program's memory (TPA = 0100h to P)
;   CX = program bytes, staged at linear SWLEN
;   SI = linear address of FCB1 (16), FCB2 (16), command tail (128)
;   DI = DOSLEN: CPM.COM's PSP + 256, linear
;   AL = current drive
; The 8086's memory is 0000h-CFFFh, DOS at the bottom where a CP/M
; program must run. So 0000h-SWLEN is exchanged with SAVE (P+200h, up
; to the top that DOS gave CPM.COM, below COMMAND), the program moved to
; 0100h, and it runs. Console calls go to the BIOS's console code. For a
; file call the BDOS copies the FCB (and a record being written) to the
; P area, exchanges DOS (0000h-DOSLEN) back in, runs the 8086
; interpreter on INT 21h there (DOSCALL; trap 1Dh returns), and
; exchanges it out again: DOS 1.25's FCB calls are CP/M's, record size
; 128. Sequential reads and writes go through BUF, so one exchange moves
; up to NBUF records. The program ends (warm boot) with DOS exchanged
; back and a return from the trap to CPM.COM.
;
; P area (in the 8086's memory, above the program's):
PBDOS   EQU 06h                 ; JP BDOSE: (0006h) points here
PSTUB   EQU 09h                 ; 8086: INT 21h, TRAP 1Dh
PFCB    EQU 10h                 ; the FCB of a call (37 bytes)
PSRCH   EQU 38h                 ; the FCB of search first / next
PDTA    EQU 60h                 ; DOS's DTA (128 bytes)
PBIOS   EQU 100h                ; BIOS jump table, (0001h) = P+103h
PSTK    EQU 200h                ; 8086 stack (DOS uses about 26 bytes)
PSIZE   EQU 200h
NBUF    EQU 8                   ; records in BUF

        ORG ENDBIOS
T_CPM:  LD HL,REGS              ; CPM.COM's 8086 state, for DOSCALL and
        LD DE,SAVREG            ; the return
        LD BC,42
        LDIR
        EX AF,AF'
        PUSH AF
        POP HL
        LD (SAVAF),HL
        EX AF,AF'
        LD HL,(R_BX)
        LD (SWLEN),HL
        LD HL,(R_DI)
        LD (DOSLEN),HL
        LD HL,(R_CX)
        LD (PLEN),HL
        LD HL,(R_SI)
        LD (PARAM),HL
        LD A,(R_AL)
        LD (CPDSK),A
        LD HL,(R_DX)
        LD (PAGE),HL
        LD DE,PSIZE
        ADD HL,DE
        LD (SAVE),HL
        LD HL,(PAGE)            ; its segment
        LD B,4
TC1:    SRL H
        RR L
        DJNZ TC1
        LD (SEGP),HL
        LD HL,(PAGE)            ; the P area
        LD D,H
        LD E,L
        INC DE
        LD (HL),0
        LD BC,PSIZE-1
        LDIR
        LD IX,(PAGE)
        LD (IX+PBDOS),0C3h
        LD HL,BDOSE
        LD (IX+PBDOS+1),L
        LD (IX+PBDOS+2),H
        LD (IX+PSTUB),0CDh
        LD (IX+PSTUB+1),21h
        LD (IX+PSTUB+2),0Fh
        LD (IX+PSTUB+3),1Dh
        LD HL,(PAGE)
        LD DE,PBIOS
        ADD HL,DE
        EX DE,HL
        LD HL,BIOSV
        LD B,17
TC2:    LD A,0C3h
        LD (DE),A
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ TC2
        LD A,1Ah                ; DOS's DTA: P+PDTA
        LD DE,PDTA
        CALL DOSCALL
        LD (SHIMSP),SP          ; the BDOS's stack; RET from here: to TRAP
        CALL XCHGA              ; DOS out
        LD HL,(SWLEN)           ; the program to 0100h
        LD DE,0100h
        LD BC,(PLEN)
        LD A,B
        OR C
        JR Z,TC3
        LDIR
TC3:    LD HL,0                 ; page zero
        LD B,L
TC4:    LD (HL),0
        INC L
        DJNZ TC4
        LD A,0C3h
        LD (0000h),A
        LD (0005h),A
        LD HL,(PAGE)
        LD DE,PBIOS+3
        ADD HL,DE
        LD (0001h),HL
        LD HL,(PAGE)
        LD DE,PBDOS
        ADD HL,DE
        LD (0006h),HL
        LD A,(CPDSK)
        LD (0004h),A
        LD HL,(SAVE)            ; FCBs and tail: exchanged out with CPM.COM
        LD DE,(PARAM)
        ADD HL,DE
        LD DE,005Ch
        LD BC,32
        LDIR
        LD DE,0080h
        LD BC,128
        LDIR
        LD HL,0080h
        LD (DMAADR),HL
        XOR A
        LD (COL),A
        LD HL,(PAGE)
        LD SP,HL
        LD HL,0
        PUSH HL                 ; RET from the program: warm boot
        JP 0100h

; warm boot: DOS back, CPM.COM's registers, return from the trap
CPEXIT: LD SP,(SHIMSP)
        CALL FLUSH
        CALL XCHGA
        LD HL,SAVREG
        LD DE,REGS
        LD BC,42
        LDIR
        LD HL,(SAVAF)
        PUSH HL
        POP AF
        EX AF,AF'
        RET

; XCHGA: exchange 0000h-SWLEN with SAVE; XCHGD: only 0000h-DOSLEN, DOS
; and CPM.COM's PSP, for a DOS call. Both are multiples of 8.
XCHGA:  LD BC,(SWLEN)
        JR XC0
XCHGD:  LD BC,(DOSLEN)
XC0:    LD HL,0
        LD DE,(SAVE)
XC1:
;@FOR I 1 2 3 4 5 6 7 8
        LD A,(DE)
        LDI
        DEC HL
        LD (HL),A
        INC HL
;@END
        JP PE,XC1
        RET

; DOSCALL: INT 21h with AH = A, DS:DX = P:DE, ES = SS = P, SP = PSTK.
; Out: the registers in REGS (AL). DOS must be in.
DOSCALL:
        LD (DCSP),SP
        PUSH AF
        PUSH DE
        LD HL,SAVREG
        LD DE,REGS
        LD BC,42
        LDIR
        POP DE
        POP AF
        LD (R_AH),A
        LD (R_DX),DE
        LD HL,(SEGP)
        LD (R_ES),HL
        LD (R_CS),HL
        LD (R_SS),HL
        LD (R_DS),HL
        LD HL,(PAGE)
        LD (B_ES),HL
        LD (B_CS),HL
        LD (B_SS),HL
        LD (B_DS),HL
        LD (EADS),HL
        LD (EASS),HL
        LD DE,PSTUB
        ADD HL,DE
        LD B,H
        LD C,L
        LD HL,PSTK
        LD (R_SP),HL
        LD HL,(SAVAF)
        PUSH HL
        POP AF
        EX AF,AF'
        LD IX,NEXT
        JP (IX)

; DOSX: DOSCALL with DOS exchanged in. A = AL.
DOSX:   PUSH AF
        PUSH DE
        CALL XCHGD
        POP DE
        POP AF
        CALL DOSCALL
        CALL XCHGD
        LD A,(R_AL)
        RET

; ---- BDOS: C = function, DE = parameter; A = L, B = H = result
BDOSE:  LD (USRSP),SP
        LD SP,(SHIMSP)
        LD HL,0
        LD A,C
        CP 41
        JR NC,BD1
        LD L,A
        ADD HL,HL
        PUSH DE
        LD DE,BDTAB
        ADD HL,DE
        POP DE
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        CALL JPHL
BD1:    LD A,L
        LD B,H
        LD SP,(USRSP)
        RET

BDTAB:  DW CPEXIT, F_CIN, F_COUT, F_RDR         ; 0-3
        DW F_PUN, F_LST, F_DIO, F_GIOB          ; 4 PUNCH, 5 LIST, 6, 7
        DW F_SIOB, F_PRT, F_RDL, F_CST          ; 8-11
        DW F_VER, F_RST, F_SEL, F_FCB           ; 12-15 OPEN
        DW F_FCB, F_SRCH, F_SRCH, F_FCB         ; 16 CLOSE, 17, 18, 19 DELETE
        DW F_RSEQ, F_WSEQ, F_FCB, F_FCB         ; 20 READ, 21 WRITE, 22 MAKE, 23 RENAME
        DW F_LOGV, F_CUR, F_DMA, F_ALV          ; 24-27
        DW F_ZERO, F_ZERO, F_ZERO, F_DPB        ; 28 W/P, 29 R/O, 30 ATTR, 31
        DW F_ZERO, F_RRND, F_WRND, F_FCB        ; 32 USER, 33 READ R, 34 WRITE R, 35 SIZE
        DW F_FCB, F_ZERO, F_ZERO, F_ZERO        ; 36 SET R, 37 RESET DRIVE, 38, 39
        DW F_WRND                               ; 40 WRITE R ZERO FILL

F_ZERO: XOR A
RETA:   LD L,A
        LD H,0
        RET

F_CIN:  CALL GETKEY
        PUSH AF
        CP 20h
        CALL NC,OUTCH
        POP AF
        PUSH AF
        CP 13
        CALL Z,OUTCH
        POP AF
        JR RETA

F_COUT: LD A,E
        CALL OUTCH
        JR F_ZERO

F_RDR:  CALL SAUXI              ; READER, PUNCH, LIST: the WD2123's
        JR RETA                 ;   channels, as CBIOS A1.1 (I86.ASM)
F_PUN:  LD A,E
        CALL SAUXO
        JR F_ZERO
F_LST:  LD A,E
        CALL SPRN
        JR F_ZERO

F_DIO:  LD A,E
        INC A
        JR Z,DIO1               ; FFh: a key or 0
        INC A
        JR Z,F_CST              ; FEh: status
        LD A,E
        CALL CONOUT
        JR F_ZERO
DIO1:   CALL PEEKEY
        LD A,0
        JR NC,RETA
        CALL GETKEY
        JR RETA

F_GIOB: LD A,(0003h)
        JR RETA

F_SIOB: LD A,E
        LD (0003h),A
        JR F_ZERO

F_PRT:  LD A,(DE)
        CP '$'
        JR Z,F_ZERO
        CALL OUTCH
        INC DE
        JR F_PRT

F_CST:  CALL PEEKEY
        LD A,0
        JR NC,RETA
        DEC A
        JR RETA

F_VER:  LD HL,0022h
        RET

F_RST:  CALL FLUSH
        LD HL,0080h
        LD (DMAADR),HL
        LD A,0Dh
        CALL DOSX
        LD E,0
F_SEL:  PUSH DE
        CALL FLUSH
        POP DE
        LD A,E
        LD (CPDSK),A
        LD (0004h),A
        LD A,0Eh
        CALL DOSX
        JR F_ZERO

F_LOGV: LD HL,3                 ; A: and B:
        RET

F_CUR:  LD A,(CPDSK)
        JR RETA

F_DMA:  LD (DMAADR),DE
        JR F_ZERO

F_ALV:  LD HL,ALLOCV
        RET

F_DPB:  LD HL,DPB
        RET

; 10: read a line to DE: max, count, text
F_RDL:  EX DE,HL
        LD C,(HL)
        INC HL
        PUSH HL                 ; -> count
        LD B,0
RL1:    PUSH BC
        CALL GETKEY
        POP BC
        POP HL
        PUSH HL
        CP 13
        JR Z,RLEND
        CP 10
        JR Z,RLEND
        CP 8
        JR Z,RLBS
        CP 7Fh
        JR Z,RLBS
        CP 15h                  ; ^U, ^X: the whole line
        JR Z,RLKILL
        CP 18h
        JR Z,RLKILL
        CP 3                    ; ^C on an empty line: warm boot
        JR NZ,RL2
        INC B
        DEC B
        JP Z,CPEXIT
        JR RL1
RL2:    LD D,A
        LD A,B
        CP C
        JR NC,RL1               ; full
        INC B
        LD E,B
        PUSH DE
        LD D,0
        ADD HL,DE
        POP DE
        LD (HL),D
        LD A,D
        PUSH BC
        CALL OUTCH
        POP BC
        JR RL1
RLBS:   INC B
        DEC B
        JR Z,RL1
        DEC B
        PUSH BC
        CALL RUBOUT
        POP BC
        JR RL1
RLKILL: INC B
        DEC B
        JR Z,RL1
        DEC B
        PUSH BC
        CALL RUBOUT
        POP BC
        JR RLKILL
RLEND:  POP HL
        LD (HL),B
        LD A,13
        CALL OUTCH
        JP F_ZERO
RUBOUT: LD A,8
        CALL OUTCH
        LD A,' '
        CALL OUTCH
        LD A,8

; OUTCH: A to the screen, tabs to the next column of 8. Keeps BC DE HL.
OUTCH:  PUSH BC
        PUSH DE
        PUSH HL
        CP 9
        JR NZ,OC2
OC1:    LD A,' '
        CALL OC3
        LD A,(COL)
        AND 7
        JR NZ,OC1
        JR OC4
OC2:    CALL OC3
OC4:    POP HL
        POP DE
        POP BC
        RET
OC3:    PUSH AF
        LD HL,COL
        CP 13
        JR Z,OC5
        CP 8
        JR Z,OC6
        CP 20h
        JR C,OC7
        INC (HL)
        JR OC7
OC5:    LD (HL),0
        JR OC7
OC6:    LD A,(HL)
        OR A
        JR Z,OC7
        DEC (HL)
OC7:    POP AF
        JP CONOUT

; FCB calls other than sequential read / write: open, close, delete,
; make, rename, random read / write, file size, set random record
F_FCB:  PUSH BC
        PUSH DE
        CALL FLUSH
        POP DE
        POP BC
        LD (UFCB),DE
        LD A,C
        LD (CPFN),A
        CALL TOSCR
        LD A,(CPFN)             ; record size 128, where CP/M has S2, RC
        CP 15
        JR Z,FF1
        CP 19
        JR Z,FF1
        CP 22
        JR Z,FF1
        CP 23
        CALL NZ,SETRS
FF1:    LD A,(CPFN)             ; a write: the record to the DTA
        CP 34
        JR Z,FF2
        CP 40
        JR NZ,FF3
FF2:    CALL DMADTA
FF3:    LD A,(CPFN)
        CP 40
        JR NZ,FF4
        LD A,34                 ; zero fill: DOS has no such thing
FF4:    LD DE,PFCB
        CALL DOSX
        LD (FRES),A
        CALL SCRFCB
        CALL FBACK
        LD A,(CPFN)             ; an open: its directory entry at the DMA
        CP 15
        JR NZ,FF5
        LD A,(FRES)
        OR A
        JR NZ,FF5
        LD HL,(UFCB)
        LD DE,15
        ADD HL,DE
        LD A,(HL)
        LD HL,(UFCB)
        INC HL
        CALL DIRENT
FF5:    LD A,(CPFN)             ; a random read: the record to the DMA
        CP 33
        JR NZ,FR5
        LD A,(FRES)
        CP 3                    ; partial record: ^Z after the end
        JR NZ,FR4
        CALL PADZ
        XOR A
        LD (FRES),A
FR4:    LD A,(FRES)
        OR A
        CALL Z,DTADMA
FR5:    LD A,(CPFN)             ; a close after writes that failed: FFh
        CP 16
        JR NZ,FR8
        LD A,(FERR)
        OR A
        JR Z,FR8
        XOR A
        LD (FERR),A
        LD A,0FFh
        JP RETA
FR8:    LD A,(FRES)             ; DOS's codes -> CP/M's
        OR A
        JP Z,RETA
        CP 0FFh
        JP Z,RETA
        LD B,A
        LD A,(CPFN)
        CP 33
        JR Z,FR6
        CP 34
        JR Z,FR7
        CP 40
        JR Z,FR7
        LD A,B
        JP RETA
FR6:    LD A,1                  ; read: unwritten data
        JP RETA
FR7:    DEC B                   ; write: 1 disk full -> 2
        LD A,2
        JP Z,RETA
        DEC A
        JP RETA

; Sequential read and write, and random read, go through BUF, NBUF
; records of one file (one FCB): a read fills it with the records from
; the one asked for on (MBASIC LOADs with random reads), a write
; collects records there; DOS is exchanged in once for all of them.
; BMODE 1: BUF holds records BPOS.. of the file at BFCB (BCNT of them,
; BEOF: the end of the file after them); BSHAD is the FCB after the
; first, which the program got. 2: records to write at BPOS.. (WRND:
; by random writes), BSHAD the FCB before them, at BPOS. Any other file
; call writes them first (FLUSH).
F_RSEQ: LD (UFCB),DE
        CALL FPOS
        XOR A
        JR RD0
; random read: the same, from record R0 R1, and the FCB's position is
; set to that record instead of the next
F_RRND: LD (UFCB),DE
        LD HL,35
        ADD HL,DE
        LD A,(HL)
        OR A
        JR Z,RR1
        LD C,33                 ; R2 not 0: past 8 MB, DOS says so
        JP F_FCB
RR1:    DEC HL
        LD D,(HL)
        DEC HL
        LD E,(HL)
        EX DE,HL
        LD A,1
RD0:    LD (RRND),A
        LD (RPOS),HL
        LD A,(BMODE)
        DEC A
        JR NZ,RS2
        LD DE,(BFCB)
        LD HL,(UFCB)
        OR A
        SBC HL,DE
        JR NZ,RS2
        LD HL,(RPOS)
        LD DE,(BPOS)
        SBC HL,DE
        JR C,RS2
        LD A,H
        OR A
        JR NZ,RS2
        LD A,(BCNT)
        CP L
        JR Z,RS1                ; just after the records
        JR C,RS2
        LD A,L                  ; one of them
        CALL BUFREC
        LD DE,(DMAADR)
        LD BC,128
        LDIR
        CALL RDPOS
        JP F_ZERO
RS1:    LD A,(BEOF)
        OR A
        JR Z,RS2
        LD A,1                  ; end of file
        JP RETA
RS2:    CALL FLUSH              ; read up to NBUF records
        CALL TOSCR
        CALL SETRS
        LD A,(RRND)
        OR A
        JR Z,RS2A
        CALL SCRFCB             ; random: from that record on
        EX DE,HL
        LD HL,(RPOS)
        CALL POSTO
RS2A:   XOR A
        LD (BCNT),A
        LD (BEOF),A
        CALL XCHGD
RS3:    LD A,14h
        LD DE,PFCB
        CALL DOSCALL
        LD A,(R_AL)
        OR A
        JR Z,RS4
        CP 3
        JR NZ,RS6
        CALL PADZ               ; the last, partial record
        LD A,1
        LD (BEOF),A
RS4:    LD A,(BCNT)
        CALL BUFREC
        EX DE,HL
        LD HL,(PAGE)
        LD BC,PDTA
        ADD HL,BC
        LD BC,128
        LDIR
        LD HL,BCNT
        INC (HL)
        LD A,(HL)
        DEC A
        JR NZ,RS5
        CALL SCRFCB             ; after the first record: the FCB the
        LD DE,BSHAD             ; program gets
        LD BC,37
        LDIR
RS5:    LD A,(BEOF)
        OR A
        JR NZ,RS7
        LD A,(BCNT)
        CP NBUF
        JR C,RS3
        JR RS7
RS6:    LD A,1
        LD (BEOF),A
RS7:    CALL XCHGD
        LD A,(BCNT)
        OR A
        JR NZ,RS8
        CALL SCRFCB             ; none: end of file
        CALL FBACK
        LD A,(RRND)
        OR A
        CALL NZ,SETPOS
        LD A,1
        JP RETA
RS8:    LD A,1
        LD (BMODE),A
        LD HL,(UFCB)
        LD (BFCB),HL
        LD HL,(RPOS)
        LD (BPOS),HL
        LD HL,BSHAD
        CALL FBACK
        LD A,(RRND)
        OR A
        CALL NZ,SETPOS
        XOR A
        CALL BUFREC
        LD DE,(DMAADR)
        LD BC,128
        LDIR
        JP F_ZERO

; RDPOS: after a record from BUF, the program's FCB to the next record,
; or (random read) to that record
RDPOS:  LD A,(RRND)
        OR A
        JP Z,FNEXT
; SETPOS: the program's FCB to record RPOS
SETPOS: LD DE,(UFCB)
        LD HL,(RPOS)
; POSTO: the FCB at DE to record HL: block HL / 128, CR HL MOD 128
POSTO:  LD A,L
        AND 7Fh
        PUSH HL
        LD HL,32
        ADD HL,DE
        LD (HL),A
        POP HL
        EX DE,HL
        LD BC,12
        ADD HL,BC
        LD A,E
        RLA
        LD A,D
        RLA
        LD (HL),A
        INC HL
        LD A,D
        RLCA
        AND 1
        LD (HL),A
        RET

F_WSEQ: LD (UFCB),DE
        CALL FPOS
        XOR A
        JR WR0
; random write (and with zero fill): the same, at record R0 R1, and the
; FCB's position is set to that record instead of the next. DOS writes
; them sequentially from the first (SAVE in MBASIC writes this way).
F_WRND: LD (UFCB),DE
        LD HL,35
        ADD HL,DE
        LD A,(HL)
        OR A
        JP NZ,F_FCB             ; R2 not 0: DOS says it is too far
        DEC HL
        LD D,(HL)
        DEC HL
        LD E,(HL)
        EX DE,HL
        LD A,1
WR0:    LD (RRND),A
        LD (RPOS),HL
        LD A,(BMODE)
        CP 2
        JR NZ,WS2
        LD DE,(BFCB)
        LD HL,(UFCB)
        OR A
        SBC HL,DE
        JR NZ,WS2
        LD A,(WRND)
        LD HL,RRND
        CP (HL)
        JR NZ,WS2
        LD A,(BCNT)
        CP NBUF
        JR NC,WS2
        LD E,A
        LD D,0
        LD HL,(BPOS)
        ADD HL,DE
        LD DE,(RPOS)
        OR A
        SBC HL,DE
        JR Z,WS3                ; the next record of the file
WS2:    CALL FLUSH
        LD A,(FERR)             ; the records before could not be written
        OR A
        JR Z,WS1
        XOR A
        LD (FERR),A
        LD A,2                  ; disk full
        JP RETA
WS1:    LD A,2
        LD (BMODE),A
        XOR A
        LD (BCNT),A
        LD HL,(UFCB)
        LD (BFCB),HL
        LD HL,(RPOS)
        LD (BPOS),HL
        LD HL,(UFCB)
        LD DE,BSHAD
        LD BC,36
        LDIR
        XOR A
        LD (DE),A
        LD (BSHAD+13),A         ; not the program's S1 (see TOSCR)
        LD A,(RRND)
        LD (WRND),A
        OR A
        JR Z,WS3
        LD DE,BSHAD             ; random: DOS writes from that record on
        LD HL,(RPOS)
        CALL POSTO
WS3:    LD A,(BCNT)
        CALL BUFREC
        EX DE,HL
        LD HL,(DMAADR)
        LD BC,128
        LDIR
        LD HL,BCNT
        INC (HL)
        CALL RDPOS
        JP F_ZERO

; FLUSH: write the records collected in BUF; BUF is empty after it.
; FERR = DOS's code if a write failed. Keeps UFCB.
FLUSH:  LD A,(BMODE)
        CP 2
        LD A,0
        LD (BMODE),A
        RET NZ
        LD HL,(UFCB)
        PUSH HL
        LD HL,(PAGE)
        LD DE,PFCB
        ADD HL,DE
        EX DE,HL
        LD HL,BSHAD
        LD BC,37
        LDIR
        CALL SETRS
        CALL XCHGD
        XOR A
        LD (BIDX),A
FLU1:   LD A,(BIDX)
        CALL BUFREC
        PUSH HL
        LD HL,(PAGE)
        LD DE,PDTA
        ADD HL,DE
        EX DE,HL
        POP HL
        LD BC,128
        LDIR
        LD A,15h
        LD DE,PFCB
        CALL DOSCALL
        LD A,(R_AL)
        OR A
        JR NZ,FLU2
        LD HL,BIDX
        INC (HL)
        LD A,(BCNT)
        CP (HL)
        JR NZ,FLU1
        XOR A
FLU2:   LD (FERR),A
        CALL XCHGD
        LD HL,(BFCB)
        LD (UFCB),HL
        LD DE,12                ; random writes: the program's position
        ADD HL,DE               ; and R0-R2 stay (MBASIC counts in R0 R1)
        LD DE,PSAVE
        LD BC,2
        LDIR
        LD BC,32-14
        ADD HL,BC
        LD C,4
        LDIR
        CALL SCRFCB
        CALL FBACK
        LD A,(WRND)
        OR A
        JR Z,FLU3
        LD HL,(UFCB)
        LD DE,12
        ADD HL,DE
        EX DE,HL
        LD HL,PSAVE
        LD BC,2
        LDIR
        LD HL,32-14
        ADD HL,DE
        EX DE,HL
        LD HL,PSAVE+2
        LD BC,4
        LDIR
FLU3:   POP HL
        LD (UFCB),HL
        RET

; TOSCR: the program's FCB (UFCB) to the scratch one
TOSCR:  CALL SCRFCB
        EX DE,HL
        LD HL,(UFCB)
        LD BC,36
        LDIR
        XOR A
        LD (DE),A
        LD IY,(PAGE)            ; byte 13 is CP/M's S1, which programs may
        LD (IY+PFCB+13),A       ;   use (PIP does); to DOS it is the high
        RET                     ;   byte of the block number

; SCRFCB: HL = the scratch FCB
SCRFCB: LD HL,(PAGE)
        LD DE,PFCB
        ADD HL,DE
        RET

SETRS:  LD IY,(PAGE)
        LD (IY+PFCB+14),80h
        LD (IY+PFCB+15),0
        RET

DMADTA: LD HL,(PAGE)
        LD DE,PDTA
        ADD HL,DE
        EX DE,HL
        LD HL,(DMAADR)
        LD BC,128
        LDIR
        RET

DTADMA: LD HL,(PAGE)
        LD DE,PDTA
        ADD HL,DE
        LD DE,(DMAADR)
        LD BC,128
        LDIR
        RET

; PADZ: the DTA holds the file's last, partial record: ^Z after its end
PADZ:   LD IY,(PAGE)
        LD A,(IY+PFCB+16)
        AND 7Fh
        RET Z
        LD E,A
        LD D,0
        LD HL,(PAGE)
        ADD HL,DE
        LD DE,PDTA
        ADD HL,DE
        NEG
        ADD A,128
        LD B,A
PZ1:    LD (HL),1Ah
        INC HL
        DJNZ PZ1
        RET

; FBACK: HL = an FCB after DOS; its bytes 12 and 14-35 to the program's (UFCB),
; with S2 = 0 and RC = the file's records in this extent: (size + 127) /
; 128 - block * 128, at most 128. Not the drive: DOS puts the drive's
; number there, CP/M leaves the program's 0 (MBASIC's NAME compares them).
FBACK:  PUSH HL
        LD DE,(UFCB)
        LD BC,12
        ADD HL,BC
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        LDI                     ; EX
        INC HL                  ; not S1: the program's own (see TOSCR)
        INC DE
        LD BC,22
        LDIR
        POP IY
        LD L,(IY+16)
        LD H,(IY+17)
        LD A,(IY+18)
        CALL RECS
        PUSH HL
        LD HL,(UFCB)
        LD DE,12
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        EX DE,HL
        POP HL
        OR A
        SBC HL,DE
        JR NC,FB1
        LD HL,0
FB1:    CALL MAX128
        LD HL,(UFCB)
        LD DE,14
        ADD HL,DE
        LD (HL),0
        INC HL
        LD (HL),A
        RET

; FPOS: HL = the record position of the program's FCB: block * 128 + CR
FPOS:   LD HL,(UFCB)
        LD DE,12
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD BC,32-13
        ADD HL,BC
        LD A,(HL)
        EX DE,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD E,A
        LD D,0
        ADD HL,DE
        RET

; FNEXT: the program's FCB to the next record
FNEXT:  LD HL,(UFCB)
        LD DE,32
        ADD HL,DE
        INC (HL)
        LD A,(HL)
        CP 128
        RET NZ
        LD (HL),0
        LD HL,(UFCB)
        LD DE,12
        ADD HL,DE
        INC (HL)
        RET NZ
        INC HL
        INC (HL)
        RET

; BUFREC: HL = record A of BUF
BUFREC: LD H,A
        LD L,0
        SRL H
        RR L
        LD DE,BUF
        ADD HL,DE
        RET

; RECS: HL = (A:HL + 127) / 128, records of a file of A:HL bytes
RECS:   LD DE,127
        ADD HL,DE
        ADC A,0
        SLA L
        RL H
        RL A
        LD L,H
        LD H,A
        RET

; MAX128: A = HL, at most 128
MAX128: LD A,H
        OR A
        LD A,128
        RET NZ
        LD A,L
        CP 129
        RET C
        LD A,128
        RET

; 17 / 18: search first / next. DOS puts the drive and the directory
; entry at the DTA; CP/M wants a directory record at the DMA, entry 0.
F_SRCH: PUSH BC
        PUSH DE
        CALL FLUSH
        POP DE
        POP BC
        LD A,C
        CP 18
        LD A,12h
        JR Z,FS1
        LD HL,(PAGE)
        LD BC,PSRCH
        ADD HL,BC
        EX DE,HL
        PUSH DE
        LD BC,36
        LDIR
        XOR A
        LD (DE),A
        POP HL
        LD A,(HL)
        CP '?'                  ; all user numbers: the default drive
        JR NZ,FS0
        LD (HL),0
FS0:    LD A,11h
FS1:    LD DE,PSRCH
        CALL DOSX
        CP 0FFh
        JP Z,RETA
        LD HL,(PAGE)            ; RC from the size
        LD BC,PDTA+29
        ADD HL,BC
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        CALL RECS
        CALL MAX128
        LD HL,(PAGE)
        LD BC,PDTA+1
        ADD HL,BC
        CALL DIRENT
        JP F_ZERO

; DIRENT: a CP/M directory record at the DMA, as CP/M's BDOS leaves it
; after a search or an open: entry 0 is user 0, the name at HL, RC = A,
; no allocation; entries 1-3 unused (E5h)
DIRENT: PUSH AF
        PUSH HL
        LD HL,(DMAADR)
        LD D,H
        LD E,L
        INC DE
        LD (HL),0E5h
        LD BC,127
        LDIR
        LD DE,(DMAADR)
        XOR A
        LD (DE),A
        INC DE
        POP HL
        LD BC,11
        LDIR
        LD B,20                 ; EX S1 S2 RC, allocation: 0
FS2:    LD (DE),A
        INC DE
        DJNZ FS2
        POP AF
        LD HL,(DMAADR)
        LD DE,15
        ADD HL,DE
        LD (HL),A
        RET

; ---- BIOS entries, (0001h) - 3
BIOSV:  DW CPEXIT, CPEXIT, B_CONST, B_CONIN     ; BOOT WBOOT CONST CONIN
        DW B_CONOUT, B_LIST, B_PUN, B_RDR       ; CONOUT LIST PUNCH READER
        DW B_RET, B_SELD, B_RET, B_RET          ; HOME SELDSK SETTRK SETSEC
        DW B_RET, B_RW, B_RW, B_LSTS            ; SETDMA READ WRITE LISTST
        DW B_STRN                               ; SECTRAN

B_CONST:
        PUSH BC
        PUSH DE
        PUSH HL
        CALL PEEKEY
        LD A,0
        JR NC,BC1
        DEC A
BC1:    POP HL
        POP DE
        POP BC
B_RET:  RET
B_CONIN:
        PUSH BC
        PUSH DE
        PUSH HL
        CALL GETKEY
        JR BC1
B_CONOUT:
        PUSH BC
        PUSH DE
        PUSH HL
        LD A,C
        CALL CONOUT
        JR BC1
B_LIST: PUSH HL                 ; LIST, PUNCH, READER, LISTST: the serial
        LD HL,SPRN              ;   routines (I86.ASM), with C the byte;
        JR BSER                 ;   BC, DE and HL kept
B_PUN:  PUSH HL
        LD HL,SAUXO
        JR BSER
B_RDR:  PUSH HL
        LD HL,SAUXI
        JR BSER
B_LSTS: PUSH HL
        LD HL,SLSTS
BSER:   PUSH DE
        PUSH BC
        LD A,C
        CALL JPHL
        POP BC
        POP DE
        POP HL
        RET
B_SELD: LD HL,0                 ; no CP/M disks
        RET
B_RW:   LD A,1
        RET
B_STRN: LD H,B
        LD L,C
        RET

; what STAT sees: the disk as CP/M would have it (1 KB blocks)
DPB:    DW 72                   ; SPT: 128-byte records per track
        DB 3,7,0                ; BSH BLM EXM
        DW 175,63               ; DSM DRM
        DB 0C0h,0               ; AL0 AL1
        DW 16,0                 ; CKS OFF
ALLOCV: DS 23

; ---- variables
PAGE:   DW 0                    ; the P area
SEGP:   DW 0                    ; its segment
SAVE:   DW 0                    ; where DOS goes while the program runs
SWLEN:  DW 0                    ; bytes exchanged
PLEN:   DW 0
PARAM:  DW 0
DMAADR: DW 0
USRSP:  DW 0
SHIMSP: DW 0
SAVAF:  DW 0
UFCB:   DW 0
CPDSK:  DB 0
COL:    DB 0
CPFN:   DB 0
FRES:   DB 0
DOSLEN: DW 0                    ; bytes exchanged for a DOS call
BMODE:  DB 0                    ; BUF: 0 empty, 1 read ahead, 2 to write
BFCB:   DW 0
BPOS:   DW 0
BCNT:   DB 0
BEOF:   DB 0
BIDX:   DB 0
RPOS:   DW 0
RRND:   DB 0                    ; 1: a random read / write
WRND:   DB 0                    ; BUF holds random writes
PSAVE:  DS 6                    ; FLUSH: block, CR, R0-R2
FERR:   DB 0
SAVREG: DS 42                   ; CPM.COM's REGS
BSHAD:  DS 37
CPMEND:
BUF     EQU $                   ; NBUF records, not in CPM.COM
BUFEND  EQU BUF+NBUF*128
        END
