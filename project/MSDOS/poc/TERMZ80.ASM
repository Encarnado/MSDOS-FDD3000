; TERMZ80.ASM - the Z80 part of TERM.COM: a serial terminal on one of the
; FDD3000's WD2123 channels, with the Timex terminal as screen and keyboard.
;
; Assembled by z86.py like CPMZ80.ASM: after I86.ASM and BIOS.ASM, with
; their symbols, for ENDBIOS (over COLD). build.py puts it in TERM.COM
; (TERMZ80.INC). BIOS trap 1Ch copies it to ENDBIOS; TERM.COM then calls
; it with trap 1Ch, BP = 0 and AH = the function:
;   0 INIT  SI = the parameter block (below): set up, clear the screen
;   1 SESS  the session: received bytes to the screen, keys to the
;           channel, until the menu key (AL = 1) or a full log buffer
;           (AL = 2). CX = bytes in the log buffer, DX = bytes lost
;   2 DRAW  draw the screen again from row CL (TERM.COM wrote on it)
;   3 RECV  BH <> 0: first send BL. Then up to CX bytes to DI, waiting
;           up to DX x 10 ms for the first, 1 s for each of the others;
;           CX = bytes received, AL = 1 if a key was pressed (it is taken)
;   4 SEND  CX bytes from SI; AL = 1 if CTS stayed off (not all sent)
;   5 BRK   a break of about 250 ms
;   6 LOG   DX = 0 log off, 1 on; CX = bytes now in the log buffer
;   7 CRC   CX bytes at SI: DX = their CRC-16 (XMODEM), AL = their sum
;   8 FLUSH forget what has been received
;   9 MODE  DL = the flags 8 (local echo) and 10h (LF after each CR)
;  10 HOLD  stop the host (XOFF / RTS off) till the next SESS, RECV,
;           SEND or BRK
; Addresses are the 8086's linear ones, which are the Z80's.
;
; Received bytes go to a 2 KB ring as soon as they are seen: the loops
; that wait for the terminal or the channel call RXPOLL, so the one byte
; the WD2123 holds is taken in time. With the ring half full the host is
; asked to stop (XOFF, or RTS off), below an eighth (256) it is let go.
;
; The screen: the host sees a VT100 (or, with flag 1, a VT52) of ROWS x
; COLS; a shadow copy of it is kept in the 8086's memory. The Timex
; terminal knows only ESC H I J K L M Y (Terminal 3000 ROM) and wraps at
; once after the last column, so the cursor is placed with ESC Y, lines
; scrolled in a region are drawn again from the shadow, and the bottom
; right cell is never written (that would scroll the terminal).

; parameter block (copied to PB)
P_CTL   EQU 0                   ; control port: 81h channel A, 41h B
P_COLS  EQU 1                   ; 64 or 80
P_ROWS  EQU 2                   ; 24
P_FLAGS EQU 3                   ; 1 VT52 host, 2 XON/XOFF, 4 RTS/CTS, 8 echo,
                                ;   10h a CR received is CR LF
P_MENU  EQU 4                   ; the menu key
P_SCR   EQU 5                   ; the shadow screen, ROWS x COLS bytes
P_RING  EQU 7                   ; the ring, 2048 bytes
P_LOG   EQU 9                   ; the log buffer
P_LOGSZ EQU 11                  ;   and its size
PBLEN   EQU 13

RINGM   EQU 07h                 ; ring index mask, high byte (2048)
HIWAT   EQU 4                   ; stop the host at 4 x 256 bytes
LOWAT   EQU 1                   ; let it go below 256

        ORG ENDBIOS
T_TERM: LD A,(R_AH)
        CP 11
        RET NC
        ADD A,A
        LD L,A
        LD H,0
        LD DE,FTAB
        ADD HL,DE
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        JP (HL)
FTAB:   DW F_INIT, F_SESS, F_DRAW, F_RECV, F_SEND, F_BRK, F_LOG, F_CRC
        DW F_FLSH, F_MODE, HOLD

; ---------------------------------------------------------------- 0 INIT
F_INIT: LD HL,(R_SI)
        LD DE,PB
        LD BC,PBLEN
        LDIR
        LD A,(ROWS)
        CALL ROWP
        LD (SCREND),HL
        XOR A
        LD (LOGON),A
        LD (STOPF),A
        LD (HOLDF),A
        LD (TXQ),A
        LD H,A
        LD L,A
        LD (LOGN),HL
        LD (LOST),HL
        CALL F_FLSH
        LD A,27h                ; transmitter, CS, receiver, RTS on
        LD (CMDV),A
        CALL CMDOUT
; RESET: the terminal's state as at power-on, the screen cleared
RESET:  XOR A
        LD (PST),A
        LD (CROW),A
        LD (CCOL),A
        LD (WRAPF),A
        LD (ATTR),A
        LD (TOP),A
        LD (IRM),A
        LD (CKM),A
        LD (GL),A
        LD (G0),A
        LD (G1),A
        LD (SAVR),A
        LD (SAVC),A
        LD (SAVA),A
        INC A
        LD (AWM),A
        LD A,(ROWS)
        DEC A
        LD (BOT),A
        LD A,0FFh               ; the terminal's attribute: not known
        LD (TATTR),A
; CLRALL: the whole screen blank, the terminal's cursor home
CLRALL: LD HL,(SCREND)
        LD DE,(SCR)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        EX DE,HL
        CALL FILL
        XOR A
        CALL TSETA
        LD A,'H'
        CALL TESC
        LD A,'J'
        CALL TESC
        XOR A
        LD (TROW),A
        LD (TCOL),A
        RET

; ---------------------------------------------------------------- 1 SESS
F_SESS: XOR A
        LD (HOLDF),A
SL1:    CALL RXPOLL
        CALL PEEKEY
        JR NC,SL2
        CALL GETKEY
        LD HL,MENUK
        CP (HL)
        JR Z,SMENU
        CALL KEYOUT
SL2:    CALL RGET
        JR C,SL3
        CALL TSYNC              ; nothing to show: the cursor to its place
        LD A,(STOPF)
        OR A
        CALL NZ,RESUME
        JR SL1
SL3:    LD C,A
        LD A,(LOGON)
        OR A
        JR Z,SL4
        LD HL,(LOGN)
        PUSH HL
        LD DE,(LOGB)
        ADD HL,DE
        LD (HL),C
        POP HL
        INC HL
        LD (LOGN),HL
        LD DE,(LOGSZ)
        OR A
        SBC HL,DE
        JR C,SL4
        LD A,C
        CALL EMUL
        CALL HOLD
        LD A,2
        JR SRET
SL4:    LD A,C
        CALL EMUL
        LD A,(STOPF)
        OR A
        JR Z,SL1
        CALL LEVEL
        LD A,H
        CP LOWAT
        CALL C,RESUME
        JR SL1
SMENU:  CALL HOLD
        LD A,1
SRET:   LD (R_AL),A
        LD HL,(LOGN)
        LD (R_CX),HL
        LD HL,(LOST)
        LD (R_DX),HL
        JP TSYNC

; HOLD: stop the host and take in what it still sends for 120 ms
HOLD:   LD A,1
        LD (STOPF),A
        LD (HOLDF),A
        CALL FLOWOFF
        LD HL,3000
HO1:    CALL RXPOLL
        DEC HL
        LD A,H
        OR L
        JR NZ,HO1
        RET

; ---------------------------------------------------------------- 2 DRAW
F_DRAW: LD A,0FFh               ; the terminal's cursor and attribute:
        LD (TROW),A             ;   not known
        LD (TATTR),A
        LD A,(ROWS)
        DEC A
        LD C,A
        LD A,(R_CL)
        CP C
        JR C,FD1
        LD A,C
FD1:    LD B,A
        CALL REDR
        JP TSYNC

; ---------------------------------------------------------------- 3 RECV
F_RECV: CALL ENSURE
        LD A,(R_BH)
        OR A
        LD A,(R_BL)
        CALL NZ,SERPUT
        LD HL,0
        LD (RCNT),HL
        LD HL,(R_DX)
        LD (TMO),HL
FR1:    LD HL,(R_CX)
        LD DE,(RCNT)
        OR A
        SBC HL,DE
        JR Z,FR8
        CALL RGET               ; first what is in the ring
        JR C,FR6
        LD A,(CTL)
        LD C,A
        LD DE,(TMO)
FR2:    LD HL,292               ; about 10 ms
FR3:    IN A,(C)
        BIT 1,A
        JR NZ,FR5
        CALL PEEKEY             ; a key (DOS may have taken it to KBUF)
        JR C,FR7
        DEC HL
        LD A,H
        OR L
        JR NZ,FR3
        DEC DE
        LD A,D
        OR E
        JR NZ,FR2
        JR FR8                  ; timed out
FR5:    AND 38h
        JR Z,FR51
        LD A,(CMDV)
        OR 10h
        OUT (C),A
FR51:   DEC C
        IN A,(C)
FR6:    LD HL,100
        LD (TMO),HL
        LD HL,(RCNT)
        PUSH HL
        LD DE,(R_DI)
        ADD HL,DE
        LD (HL),A
        POP HL
        INC HL
        LD (RCNT),HL
        JR FR1
FR7:    CALL GETKEY
        LD A,1
        JR FR9
FR8:    XOR A
FR9:    LD (R_AL),A
        LD HL,(RCNT)
        LD (R_CX),HL
        RET

; ---------------------------------------------------------------- 4 SEND
F_SEND: CALL ENSURE
        LD HL,(R_SI)
        LD BC,(R_CX)
FS1:    LD A,B
        OR C
        JR Z,FS2
        LD A,(HL)
        PUSH HL
        PUSH BC
        CALL SERPUT
        POP BC
        POP HL
        LD A,1
        JR C,FS3
        INC HL
        DEC BC
        JR FS1
FS2:    XOR A
FS3:    LD (R_AL),A
        RET

; ---------------------------------------------------------------- 5 BRK
F_BRK:  CALL ENSURE
        LD A,(CMDV)
        OR 08h                  ; send break
        CALL CMDA
        LD HL,6250              ; 250 ms, taking received bytes
        CALL HO1
        JP CMDOUT

; ---------------------------------------------------------------- 6 LOG
F_LOG:  LD A,(R_DL)
        LD (LOGON),A
        LD HL,(R_CX)
        LD (LOGN),HL
        RET

; ---------------------------------------------------------------- 9 MODE
F_MODE: LD A,(FLAGS)
        AND 0E7h
        LD B,A
        LD A,(R_DL)
        AND 18h
        OR B
        LD (FLAGS),A
        RET

; ---------------------------------------------------------------- 7 CRC
F_CRC:  LD HL,(R_SI)
        LD BC,(R_CX)
        LD DE,0
        XOR A
        LD (SUM),A
CR1:    LD A,B
        OR C
        JR Z,CR4
        PUSH BC
        LD A,(SUM)
        ADD A,(HL)
        LD (SUM),A
        LD A,(HL)
        XOR D
        LD D,A
        LD B,8
CR2:    SLA E
        RL D
        JR NC,CR3
        LD A,D
        XOR 10h
        LD D,A
        LD A,E
        XOR 21h
        LD E,A
CR3:    DJNZ CR2
        POP BC
        INC HL
        DEC BC
        JR CR1
CR4:    LD (R_DX),DE
        LD A,(SUM)
        LD (R_AL),A
        RET

; ---------------------------------------------------------------- 8 FLUSH
F_FLSH: LD HL,0
        LD (RHEAD),HL
        LD (RTAIL),HL
        RET

; ENSURE: the host let go and the RTS line on, for a transfer
ENSURE: XOR A
        LD (HOLDF),A
        LD A,(STOPF)
        OR A
        RET Z
        CALL RESUME
        LD HL,0
EN1:    CALL RXPOLL             ; until the XON has gone
        LD A,(TXQ)
        OR A
        RET Z
        DEC HL
        LD A,H
        OR L
        JR NZ,EN1
        RET

; ---------------------------------------------------------------- the channel
; RXPOLL: a received byte, if there is one, to the ring; a queued XON /
; XOFF out when the transmitter is free. Changes nothing but the flags.
RXPOLL: PUSH AF
        EXX
        LD A,(CTL)
        LD C,A
        IN B,(C)
        LD A,(TXQ)
        OR A
        JR Z,RXP1
        LD E,A
        LD A,B
        AND 81h                 ; TxRDY, CTS
        CP 81h
        JR NZ,RXP1
        DEC C
        OUT (C),E
        INC C
        XOR A
        LD (TXQ),A
RXP1:   BIT 1,B                 ; RxRDY
        JR Z,RXP9
        LD A,B
        AND 38h                 ; framing, overrun, parity
        JR Z,RXP3
        AND 10h
        JR Z,RXP2
        LD HL,(LOST)            ; overrun: at least one byte lost
        INC HL
        LD (LOST),HL
RXP2:   LD A,(CMDV)
        OR 10h                  ; error reset
        OUT (C),A
RXP3:   DEC C
        IN E,(C)
        LD HL,(RHEAD)
        PUSH HL
        LD BC,(RING)
        ADD HL,BC
        LD (HL),E
        POP HL
        INC HL
        LD A,H
        AND RINGM
        LD H,A
        LD BC,(RTAIL)
        OR A
        SBC HL,BC
        JR Z,RXP4               ; full: the byte is lost
        LD A,H                  ; the level with this byte, x 256
        ADD HL,BC
        LD (RHEAD),HL
        AND RINGM
        CP HIWAT
        CALL NC,STOP
        JR RXP9
RXP4:   LD HL,(LOST)
        INC HL
        LD (LOST),HL
RXP9:   EXX
        POP AF
        RET

; RGET: CF=1 and A = the next byte in the ring; CF=0: none. Uses DE, HL.
RGET:   LD HL,(RTAIL)
        LD DE,(RHEAD)
        OR A
        SBC HL,DE
        RET Z
        ADD HL,DE
        EX DE,HL
        LD HL,(RING)
        ADD HL,DE
        LD A,(HL)
        INC DE
        PUSH AF
        LD A,D
        AND RINGM
        LD D,A
        LD (RTAIL),DE
        POP AF
        SCF
        RET

; LEVEL: HL = bytes in the ring. Uses DE.
LEVEL:  LD HL,(RHEAD)
        LD DE,(RTAIL)
        OR A
        SBC HL,DE
        LD A,H
        AND RINGM
        LD H,A
        RET

; STOP / RESUME: ask the host to stop / go on (XOFF / XON, RTS)
STOP:   LD A,(STOPF)
        OR A
        RET NZ
        INC A
        LD (STOPF),A
FLOWOFF:
        LD A,(FLAGS)
        BIT 1,A
        JR Z,ST1
        LD A,13h                ; XOFF
        LD (TXQ),A
ST1:    LD A,(FLAGS)
        BIT 2,A
        RET Z
        LD A,07h                ; RTS off
        JR CMDSET
RESUME: LD A,(HOLDF)
        OR A
        RET NZ
        LD (STOPF),A
        LD A,(FLAGS)
        BIT 1,A
        JR Z,RS1
        LD A,11h                ; XON
        LD (TXQ),A
RS1:    LD A,27h
CMDSET: LD (CMDV),A
CMDOUT: LD A,(CMDV)
CMDA:   PUSH BC
        LD B,A
        LD A,(CTL)
        LD C,A
        OUT (C),B
        POP BC
        RET

; SERPUT: A to the channel, when it is free and CTS on (status bit 7: the
; WD2123 has no DSR), taking received bytes meanwhile. CF=1: CTS stayed
; off for about 3.4 s and the byte was dropped.
SERPUT: PUSH BC
        PUSH DE
        PUSH HL
        LD E,A
        LD HL,0
QSP1:   CALL RXPOLL
        LD A,(CTL)
        LD C,A
        IN A,(C)
        AND 81h
        CP 81h
        JR Z,QSP2
        DEC HL
        LD A,H
        OR L
        JR NZ,QSP1
        SCF
        JR SP3
QSP2:   DEC C
        OUT (C),E
        OR A
SP3:    POP HL
        POP DE
        POP BC
        RET

; SENDS: the 0-terminated string at HL to the channel
SENDS:  LD A,(HL)
        OR A
        RET Z
        CALL SERPUT
        INC HL
        JR SENDS

; SENDN: A (0-255) in decimal to the channel
SENDN:  LD C,0
        LD B,100
        CALL SN1
        LD B,10
        CALL SN1
        ADD A,'0'
        JR SERPUT
SN1:    LD D,'0'-1
SN2:    INC D
        SUB B
        JR NC,SN2
        ADD A,B
        LD E,A
        LD A,D
        CP '0'
        JR NZ,SN3
        LD A,C                  ; no leading zeros
        OR A
        LD A,E
        RET Z
SN3:    LD A,D
        CALL SERPUT
        LD C,1
        LD A,E
        RET

; ---------------------------------------------------------------- keys
; KEYOUT: a key to the channel. For a VT100 host the arrow keys (the
; terminal sends ESC A-D) become ESC [ A-D (ESC O A-D in cursor key mode);
; an ESC not followed at once by A-D goes alone. With local echo (flag 8)
; a key also goes to the screen, CR as CR LF; not ESC, the arrows, nor
; (VT52 host) the key after an ESC.
KEYOUT: LD (KCH),A
        LD A,(FLAGS)
        RRCA
        JR C,KO2
        LD A,(KCH)
        CP 1Bh
        JR NZ,KO2
        LD HL,800               ; about 53 ms
KO1:    CALL RXPOLL
        PUSH HL
        CALL PEEKEY
        POP HL
        JR C,KO3
        DEC HL
        LD A,H
        OR L
        JR NZ,KO1
KO2:    LD A,(KCH)
        CALL SERPUT
        LD HL,KLAST
        LD B,(HL)               ; the key before
        LD A,(KCH)
        LD (HL),A
        LD A,(FLAGS)
        BIT 3,A
        RET Z
        RRCA
        JR NC,KO5
        LD A,B
        CP 1Bh
        RET Z
KO5:    LD A,(KCH)
        CP 1Bh
        RET Z
        CP 0Dh
        JR NZ,KO6
        CALL EMUL               ; (with flag 10h it has added the LF)
        LD A,(FLAGS)
        AND 10h
        RET NZ
        LD A,0Ah
KO6:    JP EMUL
KO3:    SUB 'A'
        CP 4
        JR NC,KO2               ; not an arrow: it stays for SESS
        CALL GETKEY
        LD (KCH),A
        LD A,1Bh
        CALL SERPUT
        LD A,(CKM)
        OR A
        LD A,'['
        JR Z,KO4
        LD A,'O'
KO4:    CALL SERPUT
        LD A,(KCH)
        JP SERPUT

; ---------------------------------------------------------------- the terminal
; TOUT: A to the terminal, as the BIOS's CONOUT, but taking received
; bytes while the terminal is busy. Keeps BC, DE, HL.
TOUT:   PUSH BC
        PUSH DE
        LD (TOCH),A
TO1:    LD A,(TOCH)
        LD B,A
        CALL TSEND
        JR Z,TO3
TO2:    CALL RXPOLL             ; timed out: wait for the terminal's abort
        IN A,(2Fh)
        AND 5Fh
        CP 07h
        JR NZ,TO2
        JR TO1
TO3:    POP DE
        POP BC
        RET

; TSEND: B in two nibbles, each echoed back (BIOS COSEND, but taking
; received bytes while the echo is awaited). Z = sent.
TSEND:  LD A,B
        AND 0Fh
        LD E,A
        LD A,B
        RRCA
        RRCA
        RRCA
        RRCA
        AND 0Fh
        LD D,A
TS1:    CALL RXPOLL
        LD A,0Ah                ; ask to send
        OUT (2Fh),A
        IN A,(2Fh)
        AND 5Fh
        CP 0Fh                  ; terminal ready
        JR NZ,TS1
        LD A,E
        OR 10h
        OUT (2Fh),A
        LD B,A
        LD C,0
TS2:    CALL RXPOLL
        IN A,(2Fh)
        DEC C
        JR Z,TS4
        AND 5Fh
        CP B
        JR NZ,TS2
        LD A,D
        OR 40h
        OUT (2Fh),A
        LD B,A
        LD C,0
TS3:    CALL RXPOLL
        IN A,(2Fh)
        DEC C
        JR Z,TS4
        AND 5Fh
        CP B
        JR NZ,TS3
        LD A,50h                ; done
        OUT (2Fh),A
        XOR A
        RET
TS4:    LD A,07h                ; abort
        OUT (2Fh),A
        AND A
        RET

; TESC: ESC, then A
TESC:   PUSH AF
        LD A,1Bh
        CALL TOUT
        POP AF
        JR TOUT

; TGOTO: the terminal's cursor to row D, column E. Uses A.
TGOTO:  LD A,(TROW)
        CP D
        JR NZ,TG1
        LD A,(TCOL)
        CP E
        RET Z
TG1:    LD A,'Y'
        CALL TESC
        LD A,D
        ADD A,32
        CALL TOUT
        LD A,E
        ADD A,32
        CALL TOUT
        LD A,D
        LD (TROW),A
        LD A,E
        LD (TCOL),A
        RET

; TSYNC: the terminal's cursor to the screen's
TSYNC:  LD A,(CROW)
        LD D,A
        LD A,(CCOL)
        LD E,A
        JR TGOTO

; TSETA: the terminal's attribute to A (0 normal, 80h inverse). Uses A.
TSETA:  PUSH HL
        LD HL,TATTR
        CP (HL)
        JR Z,TSA2
        LD (HL),A
        OR A
        LD A,'M'
        JR Z,TSA1
        LD A,'L'
TSA1:   CALL TESC
TSA2:   POP HL
        RET

; TPUT: cell A (character, bit 7 inverse) at row D, column E on the
; terminal; not the bottom right one. Uses A.
TPUT:   PUSH AF
        LD A,(ROWS)
        DEC A
        CP D
        JR NZ,TP1
        LD A,(COLS)
        DEC A
        CP E
        JR NZ,TP1
        POP AF
        RET
TP1:    CALL TGOTO
        POP AF
        PUSH AF
        AND 80h
        CALL TSETA
        POP AF
        AND 7Fh
        CALL TOUT
        LD A,(TCOL)
        INC A
        LD (TCOL),A
        PUSH HL
        LD HL,COLS
        CP (HL)
        POP HL
        RET NZ
        XOR A                   ; the terminal wrapped
        LD (TCOL),A
        LD A,(TROW)
        INC A
        LD (TROW),A
        RET

; CLRK: from row D, column E to the end of the line on the terminal
CLRK:   CALL TGOTO
        XOR A
        CALL TSETA
        LD A,'K'
        JR TESC

; DRAWR: row D from column E on the terminal, from the shadow. Uses all.
DRAWR:  CALL RXPOLL             ; (a row may follow a row, or a scroll)
        LD A,(COLS)
        DEC A
        LD C,A                  ; C = the last column to draw
        LD A,(ROWS)
        DEC A
        CP D
        JR NZ,DR1
        DEC C
DR1:    LD A,C
        CP E
        JR C,CLRK
        PUSH DE
        LD E,C
        CALL CELLP
        POP DE
        LD B,C
DR2:    LD A,(HL)               ; the last cell that is not blank
        CP ' '
        JR NZ,DR3
        LD A,B
        CP E
        JR Z,CLRK               ; all blank
        AND 7                   ; every 8 cells (a blank cell: 75 T)
        CALL Z,RXPOLL
        DEC HL
        DEC B
        JR DR2
DR3:    PUSH BC
        CALL CELLP
        POP BC
DR4:    LD A,(HL)
        CALL TPUT
        INC HL
        LD A,E
        INC E
        CP B
        JR NZ,DR4
        LD A,C
        CP E
        RET C
        JR CLRK

; REDR: rows B to C on the terminal, from the shadow. Uses all.
REDR:   LD D,B
QRD1:   PUSH BC
        PUSH DE
        LD E,0
        CALL DRAWR
        POP DE
        POP BC
        LD A,D
        CP C
        RET Z
        INC D
        JR QRD1

; ---------------------------------------------------------------- the shadow
; ROWP: HL = row A. CELLP: HL = row D, column E. Use A.
ROWP:   PUSH DE                 ; COLS is 64 or 80: A x 64 (+ A x 16)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        LD A,(COLS)
        CP 64
        JR Z,RP1
        ADD HL,DE
RP1:    LD DE,(SCR)
        ADD HL,DE
        POP DE
        RET
CELLP:  LD A,D
        CALL ROWP
        LD A,E
ADDHLA: ADD A,L
        LD L,A
        RET NC
        INC H
        RET
SUBHLA: PUSH DE
        LD E,A
        LD D,0
        OR A
        SBC HL,DE
        POP DE
        RET

; NROWS: BC = A rows' bytes. Uses A, HL.
NROWS:  CALL ROWP
        LD BC,(SCR)
        OR A
        SBC HL,BC
        LD B,H
        LD C,L
        RET

; MVF / MVB: LDIR / LDDR (BC > 0) in pieces of 32 bytes, with RXPOLL
; between them: at 19200 baud a byte comes every 2100 T-states.
MVF:    LD A,B
        OR A
        JR NZ,MVF1
        LD A,C
        CP 33
        JR C,MVF2
MVF1:   PUSH BC
        LD BC,32
        LDIR
        POP BC
        CALL MVSUB
        JR MVF
MVF2:   LDIR
        RET
MVB:    LD A,B
        OR A
        JR NZ,MVB1
        LD A,C
        CP 33
        JR C,MVB2
MVB1:   PUSH BC
        LD BC,32
        LDDR
        POP BC
        CALL MVSUB
        JR MVB
MVB2:   LDDR
        RET
MVSUB:  LD A,C
        SUB 32
        LD C,A
        JR NC,MVS1
        DEC B
MVS1:   JP RXPOLL

; FILL: BC cells at HL blank. Uses A, BC, DE, HL.
FILL:   LD A,B
        OR C
        RET Z
        LD (HL),' '
        DEC BC
        LD A,B
        OR C
        RET Z
        LD D,H
        LD E,L
        INC DE
        CALL MVF
        RET

; SHUP / SHDN: rows RT to RB of the shadow one up / down; the row that
; comes in is blank. Use all.
SHUP:   CALL RXPOLL             ; a byte may have come since the last
        LD A,(RT)
        CALL ROWP
        EX DE,HL
        CALL RCOUNT
        LD A,(COLS)
        LD L,A
        LD H,0
        ADD HL,DE
        LD A,B
        OR C
        JR Z,SHU1
        CALL MVF
SHU1:   EX DE,HL
        JR FILLRW
SHDN:   CALL RXPOLL
        CALL RCOUNT
        LD A,(RB)
        CALL ROWP
        LD A,(COLS)
        DEC A
        CALL ADDHLA
        LD D,H
        LD E,L
        LD A,(COLS)
        CALL SUBHLA
        LD A,B
        OR C
        JR Z,SHD1
        CALL MVB
SHD1:   LD A,(RT)
        CALL ROWP
FILLRW: LD A,(COLS)
        LD C,A
        LD B,0
        JR FILL
RCOUNT: LD A,(RB)
        LD HL,RT
        SUB (HL)
        JR NROWS

; SETRG: RT, RB = the scrolling region
SETRG:  LD A,(TOP)
        LD (RT),A
        LD A,(BOT)
        LD (RB),A
        RET

; FULLSC: Z if the region is the whole screen. Uses A, HL.
FULLSC: LD A,(TOP)
        OR A
        RET NZ
        LD A,(ROWS)
        DEC A
        LD HL,BOT
        CP (HL)
        RET

; SCRUP: the region up one line. On the whole screen the terminal
; scrolls itself (LF on its bottom row); otherwise it is drawn again.
SCRUP:  CALL SETRG
        CALL SHUP
        CALL FULLSC
        JR NZ,SCRR
        LD A,(ROWS)
        DEC A
        LD D,A
        LD A,(TROW)
        CP D
        JR Z,SU1
        LD E,0
        CALL TGOTO
SU1:    XOR A
        CALL TSETA
        LD A,0Ah
        CALL TOUT
        LD A,(ROWS)             ; the bottom right cell, which could not
        SUB 2                   ;   be drawn, is now a row up
        LD D,A
        LD A,(COLS)
        DEC A
        LD E,A
        CALL CELLP
        LD A,(HL)
        CP ' '
        RET Z
        JP TPUT
SCRR:   LD A,(TOP)
        LD B,A
        LD A,(BOT)
        LD C,A
        JR REDR

; SCRDN: the region down one line (ESC I on the terminal's top row)
SCRDN:  CALL SETRG
        CALL SHDN
        CALL FULLSC
        JR NZ,SCRR
        LD A,(TROW)
        OR A
        JR Z,SD1
        LD DE,0
        CALL TGOTO
SD1:    XOR A
        CALL TSETA
        LD A,'I'
        JP TESC

; ---------------------------------------------------------------- the screen
; INDEX: down a line, scrolling at the region's bottom. RINDEX: up.
INDEX:  XOR A
        LD (WRAPF),A
        LD A,(BOT)
        LD HL,CROW
        CP (HL)
        JR Z,SCRUP
        LD A,(ROWS)
        DEC A
        CP (HL)
        RET Z
        INC (HL)
        RET
RINDEX: XOR A
        LD (WRAPF),A
        LD A,(TOP)
        LD HL,CROW
        CP (HL)
        JR Z,SCRDN
        LD A,(HL)
        OR A
        RET Z
        DEC (HL)
        RET

; PUTCH: the character A at the cursor
PUTCH:  CALL RXPOLL             ; (halfway from the last one to TOUT's)
        LD C,A
        LD A,(WRAPF)            ; the last column was written: wrap now
        OR A
        JR Z,PC1
        XOR A
        LD (CCOL),A
        PUSH BC
        CALL INDEX
        POP BC
PC1:    LD A,(CROW)
        LD D,A
        LD A,(CCOL)
        LD E,A
        LD A,(IRM)
        OR A
        JR Z,PC2
        PUSH BC                 ; insert mode
        LD A,1
        CALL ICHS
        POP BC
        CALL CURP
        LD A,(ATTR)
        OR C
        LD (HL),A
        CALL DRAWR
        JR PC3
PC2:    CALL CELLP
        LD A,(ATTR)
        OR C
        LD (HL),A
        CALL TPUT
PC3:    LD A,(CCOL)
        LD E,A
        LD A,(COLS)
        DEC A
        CP E
        JR Z,PC4
        INC E
        LD A,E
        LD (CCOL),A
        RET
PC4:    LD A,(AWM)
        LD (WRAPF),A
        RET

; ICHS / DCHS / ECHS: insert / delete / blank A cells at the cursor, in
; the shadow. Use all.
CHCNT:  LD B,A                  ; B = n, at most the cells left;
        OR A                    ;   A = cells left - n
        JR NZ,CHC1
        INC B
CHC1:   LD A,(CCOL)
        LD C,A
        LD A,(COLS)
        SUB C
        CP B
        JR NC,CHC2
        LD B,A
CHC2:   SUB B
        RET
ICHS:   CALL CHCNT
        PUSH BC
        PUSH AF
        LD A,(CROW)
        LD D,A
        LD A,(COLS)
        DEC A
        LD E,A
        CALL CELLP              ; the row's last cell
        LD D,H
        LD E,L
        POP AF
        POP BC
        PUSH BC
        PUSH AF
        LD A,B
        CALL SUBHLA
        POP AF
        LD C,A
        LD B,0
        OR A
        JR Z,IC1
        CALL MVB
IC1:    POP BC
        JR ECHS1
DCHS:   CALL CHCNT
        PUSH BC
        PUSH AF
        CALL CURP
        LD D,H
        LD E,L
        POP AF
        POP BC
        PUSH BC
        PUSH AF
        LD A,B
        CALL ADDHLA
        POP AF
        LD C,A
        LD B,0
        OR A
        JR Z,DC1
        CALL MVF
DC1:    POP BC
        EX DE,HL
        LD C,B
        LD B,0
        JP FILL
ECHS:   CALL CHCNT
ECHS1:  PUSH BC
        CALL CURP
        POP BC
        LD C,B
        LD B,0
        JP FILL
CURP:   LD A,(CROW)
        LD D,A
        LD A,(CCOL)
        LD E,A
        JP CELLP

; SETCUR: the cursor to row D, column E, kept on the screen
SETCUR: LD A,(ROWS)
        DEC A
        CP D
        JR NC,SC1
        LD D,A
SC1:    LD A,(COLS)
        DEC A
        CP E
        JR NC,SC2
        LD E,A
SC2:    LD A,D
        LD (CROW),A
        LD A,E
        LD (CCOL),A
CLRW:   XOR A
        LD (WRAPF),A
        RET

; EDN: erase in display, A = 0 cursor to end, 1 start to cursor, 2 all
EDN:    CP 1
        JR Z,ED1
        JP NC,CLRALL
        CALL CURP
        PUSH DE
        EX DE,HL
        LD HL,(SCREND)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        EX DE,HL
        CALL FILL
        POP DE
        CALL TGOTO
        XOR A
        CALL TSETA
        LD A,'J'
        JP TESC
ED1:    CALL CURP
        PUSH DE
        INC HL
        LD DE,(SCR)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        EX DE,HL
        CALL FILL
        POP DE
        LD B,0
        LD C,D
        JP REDR

; ELN: erase in line, A = 0 cursor to end, 1 start to cursor, 2 all
ELN:    LD B,A
        LD A,(CROW)
        LD D,A
        LD A,B
        CP 1
        JR Z,EL1
        JR NC,EL2
        LD A,(CCOL)
        LD E,A
        CALL CELLP
        LD A,(COLS)
        SUB E
EL0:    LD C,A
        LD B,0
        PUSH DE
        CALL FILL
        POP DE
        JP CLRK
EL1:    LD E,0
        CALL CELLP
        LD A,(CCOL)
        INC A
        LD C,A
        LD B,0
        PUSH DE
        CALL FILL
        POP DE
        JP DRAWR
EL2:    LD E,0
        CALL CELLP
        LD A,(COLS)
        JR EL0

; ---------------------------------------------------------------- the host's codes
; EMUL: a byte from the host
EMUL:   LD C,A
        CP 80h
        JR NC,EM8
        CP 20h
        JR C,ECTRL
        CP 7Fh
        RET Z
        LD A,(PST)
        OR A
        JR NZ,ESTATE
GPUT:   LD HL,G0                ; the character set in use
        LD A,(GL)
        CALL ADDHLA
        LD A,(HL)
        OR A
        LD A,C
        JP Z,PUTCH
        CP 5Fh                  ; DEC special graphics: 5Fh-7Eh
        JP C,PUTCH
        SUB 5Fh
        LD HL,GRTAB
        CALL ADDHLA
        LD A,(HL)
        JP PUTCH
EM8:    LD A,(PST)              ; 8-bit and UTF-8: one ? per character
        OR A
        RET NZ
        LD A,C
        CP 0C0h
        RET C
        LD A,'?'
        JP PUTCH
ECTRL:  CP 1Bh
        JR Z,EESC
        CP 18h
        JR Z,ECAN
        CP 1Ah
        JR Z,ECAN
        CP 0Dh
        JR Z,ECR
        CP 0Ah
        JP Z,INDEX
        CP 0Bh
        JP Z,INDEX
        CP 0Ch
        JP Z,INDEX
        CP 08h
        JR Z,EBS
        CP 09h
        JR Z,ETAB
        CP 0Eh
        JR Z,ESO
        CP 0Fh
        RET NZ
        XOR A                   ; SI: G0
        JR ESO1
ESO:    LD A,1                  ; SO: G1
ESO1:   LD (GL),A
        RET
EESC:   LD A,1
        JR ECAN1
ECAN:   XOR A
ECAN1:  LD (PST),A
        RET
ECR:    XOR A
        LD (CCOL),A
        LD (WRAPF),A
        LD A,(FLAGS)            ; flag 10h: a LF after each CR
        AND 10h
        RET Z
        JP INDEX
EBS:    XOR A
        LD (WRAPF),A
        LD A,(CCOL)
        OR A
        RET Z
        DEC A
        LD (CCOL),A
        RET
ETAB:   LD A,(CCOL)
        OR 7
        INC A
        LD HL,COLS
        CP (HL)
        JR C,ET1
        LD A,(HL)
        DEC A
ET1:    LD (CCOL),A
        JP CLRW

ESTATE: DEC A
        JR Z,SESC
        DEC A
        JP Z,SCSI
        DEC A
        JR Z,SSCS
        DEC A
        JR Z,ECAN               ; ESC # x: x ignored
        DEC A
        JR Z,SY1
        XOR A                   ; VT52 ESC Y row col: the column
        LD (PST),A
        LD A,C
        SUB 32
        LD E,A
        LD A,(YROW)
        LD D,A
        JP SETCUR
SY1:    LD A,C
        SUB 32
        LD (YROW),A
        LD A,6
        LD (PST),A
        RET
SSCS:   XOR A                   ; ESC ( x / ESC ) x: '0' graphics
        LD (PST),A
        LD HL,G0
        LD A,(PG)
        CALL ADDHLA
        LD A,C
        SUB '0'
        JR Z,QSS1
        LD A,0FFh
QSS1:   INC A
        LD (HL),A
        RET

SESC:   LD (PST),A              ; (A = 0)
        LD A,(FLAGS)
        RRCA
        JR C,V52ESC
        LD A,C
        CP '['
        JR Z,ECSI
        CP '7'
        JP Z,SAVEC
        CP '8'
        JP Z,RESTC
        CP 'D'
        JP Z,INDEX
        CP 'E'
        JR Z,ENEL
        CP 'M'
        JP Z,RINDEX
        CP 'c'
        JP Z,RESET
        CP 'Z'
        JP Z,DAREP
        CP '#'
        LD B,4
        JR Z,ESTS
        CP '('
        LD B,0
        JR Z,EG
        CP ')'
        RET NZ
        INC B
EG:     LD A,B
        LD (PG),A
        LD B,3
ESTS:   LD A,B
        LD (PST),A
        RET
ENEL:   XOR A
        LD (CCOL),A
        JP INDEX
ECSI:   LD A,2
        LD (PST),A
        XOR A
        LD (NPAR),A
        LD (PRIV),A
        LD HL,PARS
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        RET

; VT52: ESC A B C D cursor, H home, I up (scrolling), J K erase, Y r c
V52ESC: LD A,1
        LD (PARS),A
        LD A,C
        CP 'A'
        JP Z,CUU
        CP 'B'
        JP Z,CUD
        CP 'C'
        JP Z,CUF
        CP 'D'
        JP Z,CUB
        CP 'I'
        JP Z,RINDEX
        CP 'H'
        LD DE,0
        JP Z,SETCUR
        CP 'J'
        LD A,0
        JP Z,EDN
        LD A,C
        CP 'K'
        LD A,0
        JP Z,ELN
        LD A,C
        CP 'Z'
        JP Z,DAREP
        CP 'Y'
        RET NZ
        LD A,5
        LD (PST),A
        RET

; CSI: parameters, then the final byte
SCSI:   LD A,C
        CP '<'
        JR NC,CS2
        CP '0'
        RET C                   ; intermediate bytes: ignored
        CP ';'
        JR Z,CSEMI
        CP ':'
        RET NC
        LD A,(NPAR)             ; a digit
        CP 4
        RET NC
        LD HL,PARS
        CALL ADDHLA
        LD A,(HL)
        CP 26
        JR NC,CS1
        LD B,A
        ADD A,A
        ADD A,A
        ADD A,B
        ADD A,A
        LD B,A
        LD A,C
        SUB '0'
        ADD A,B
        JR NC,CS0
CS1:    LD A,255
CS0:    LD (HL),A
        RET
CSEMI:  LD HL,NPAR
        LD A,(HL)
        CP 4
        RET NC
        INC (HL)
        RET
CS2:    CP 40h
        JR NC,CFIN
        LD A,1                  ; < = > ?: private
        LD (PRIV),A
        RET
CFIN:   XOR A
        LD (PST),A
        LD HL,CTAB
        LD A,(PRIV)
        OR A
        JR Z,QCF1
        LD HL,PTAB
QCF1:   LD A,(HL)
        OR A
        RET Z
        INC HL
        CP C
        JR Z,CF2
        INC HL
        INC HL
        JR QCF1
CF2:    LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        JP (HL)

CTAB:   DB 'A'
        DW CUU
        DB 'B'
        DW CUD
        DB 'e'
        DW CUD
        DB 'C'
        DW CUF
        DB 'a'
        DW CUF
        DB 'D'
        DW CUB
        DB 'H'
        DW CUP
        DB 'f'
        DW CUP
        DB 'G'
        DW CHA
        DB 60h
        DW CHA
        DB 'd'
        DW VPA
        DB 'J'
        DW CED
        DB 'K'
        DW CEL
        DB 'm'
        DW SGR
        DB 'r'
        DW STBM
        DB 'n'
        DW DSR
        DB 'c'
        DW CDA
        DB 'h'
        DW SM
        DB 'l'
        DW RM
        DB 'L'
        DW IL
        DB 'M'
        DW DL
        DB '@'
        DW ICH
        DB 'P'
        DW DCH
        DB 'X'
        DW ECH
        DB 's'
        DW SAVEC
        DB 'u'
        DW RESTC
        DB 0
PTAB:   DB 'h'
        DW PSM
        DB 'l'
        DW PRM
        DB 0

; PAR1 / PAR2: A = the first / second parameter, 1 if 0 or none
PAR2:   LD A,(PARS+1)
        JR PAR0
PAR1:   LD A,(PARS)
PAR0:   OR A
        RET NZ
        INC A
        RET

CUU:    CALL PAR1
        LD B,A
        LD A,(TOP)              ; the region's top, if the cursor is in it
        LD C,A
        LD A,(CROW)
        CP C
        JR NC,CU1
        LD C,0
CU1:    SUB B
        JR C,CU2
        CP C
        JR NC,CU3
CU2:    LD A,C
CU3:    LD (CROW),A
        JP CLRW
CUD:    CALL PAR1
        LD B,A
        LD A,(BOT)
        LD C,A
        LD A,(CROW)
        CP C
        JR C,CD1
        JR Z,CD1
        LD A,(ROWS)
        DEC A
        LD C,A
        LD A,(CROW)
CD1:    ADD A,B
        JR C,CD2
        CP C
        JR C,CD3
CD2:    LD A,C
CD3:    LD (CROW),A
        JP CLRW
CUF:    CALL PAR1
        LD B,A
        LD A,(COLS)
        DEC A
        LD C,A
        LD A,(CCOL)
        ADD A,B
        JR C,CF3
        CP C
        JR C,CF4
CF3:    LD A,C
CF4:    LD (CCOL),A
        JP CLRW
CUB:    CALL PAR1
        LD B,A
        LD A,(CCOL)
        SUB B
        JR NC,QCB1
        XOR A
QCB1:   LD (CCOL),A
        JP CLRW
CUP:    CALL PAR1
        DEC A
        LD D,A
        CALL PAR2
        DEC A
        LD E,A
        JP SETCUR
CHA:    CALL PAR1
        DEC A
        LD E,A
        LD A,(CROW)
        LD D,A
        JP SETCUR
VPA:    CALL PAR1
        DEC A
        LD D,A
        LD A,(CCOL)
        LD E,A
        JP SETCUR
CED:    LD A,(PARS)
        JP EDN
CEL:    LD A,(PARS)
        JP ELN

SGR:    LD HL,PARS
        CALL NPARS
QSG1:   LD A,(HL)
        INC HL
        OR A
        JR Z,QSG2
        CP 27
        JR NZ,SG4
        XOR A
        JR QSG2
SG4:    CP 7
        JR NZ,SG3
        LD A,80h
QSG2:   LD (ATTR),A
SG3:    DJNZ QSG1
        RET
; NPARS: B = parameters given (1-4). Uses A.
NPARS:  LD A,(NPAR)
        CP 4
        JR C,NPS1
        LD A,3
NPS1:   INC A
        LD B,A
        RET

STBM:   CALL PAR1
        DEC A
        LD D,A
        LD A,(PARS+1)
        LD HL,ROWS
        OR A
        JR Z,ST2
        CP (HL)
        JR C,ST3
ST2:    LD A,(HL)
ST3:    DEC A
        CP D
        RET C
        RET Z
        LD (BOT),A
        LD A,D
        LD (TOP),A
        LD DE,0
        JP SETCUR

DSR:    LD A,(PARS)
        CP 5
        JR Z,DSR5
        CP 6
        RET NZ
        LD A,1Bh
        CALL SERPUT
        LD A,'['
        CALL SERPUT
        LD A,(CROW)
        INC A
        CALL SENDN
        LD A,';'
        CALL SERPUT
        LD A,(CCOL)
        INC A
        CALL SENDN
        LD A,'R'
        JP SERPUT
DSR5:   LD HL,DSROK
        JP SENDS
CDA:    LD A,(PARS)
        OR A
        RET NZ
DAREP:  LD HL,DA100
        LD A,(FLAGS)
        RRCA
        JR NC,DA1
        LD HL,DA52
DA1:    JP SENDS
DA100:  DB 1Bh,'[?1;0c',0       ; a VT100 without options
DA52:   DB 1Bh,'/Z',0
DSROK:  DB 1Bh,'[0n',0

; SM / RM: 4 insert mode. Private: ?1 cursor keys, ?7 autowrap.
SM:     LD C,1
        JR SM0
RM:     LD C,0
SM0:    LD HL,PARS
        CALL NPARS
SM1:    LD A,(HL)
        INC HL
        CP 4
        JR NZ,SM2
        LD A,C
        LD (IRM),A
SM2:    DJNZ SM1
        RET
PSM:    LD C,1
        JR PSM0
PRM:    LD C,0
PSM0:   LD HL,PARS
        CALL NPARS
PS1:    LD A,(HL)
        INC HL
        CP 1
        JR NZ,PS2
        LD A,C
        LD (CKM),A
PS2:    CP 7
        JR NZ,PS3
        LD A,C
        LD (AWM),A
        XOR A
        LD (WRAPF),A
PS3:    DJNZ PS1
        RET

; IL / DL: insert / delete lines at the cursor, in the region
IL:     LD HL,SHDN
        JR IL0
DL:     LD HL,SHUP
IL0:    LD (ILOP),HL
        LD A,(TOP)
        LD B,A
        LD A,(CROW)
        CP B
        RET C
        LD (RT),A
        LD B,A
        LD A,(BOT)
        LD (RB),A
        CP B
        RET C
        SUB B
        INC A
        LD C,A                  ; lines from the cursor to the bottom
        CALL PAR1
        CP C
        JR C,IL1
        LD A,C
IL1:    LD B,A
IL2:    PUSH BC
        LD HL,(ILOP)
        CALL JPHL
        POP BC
        DJNZ IL2
        XOR A
        LD (CCOL),A
        LD (WRAPF),A
        LD A,(CROW)
        LD B,A
        LD A,(BOT)
        LD C,A
        JP REDR

; ICH / DCH / ECH: insert / delete / erase characters at the cursor
ICH:    LD HL,ICHS
        JR CH0
DCH:    LD HL,DCHS
        JR CH0
ECH:    LD HL,ECHS
CH0:    LD DE,CH1
        PUSH DE
        PUSH HL
        LD A,(PARS)
        RET                     ; to ICHS / DCHS / ECHS, then CH1
CH1:    XOR A
        LD (WRAPF),A
        LD A,(CROW)
        LD D,A
        LD A,(CCOL)
        LD E,A
        JP DRAWR

SAVEC:  LD A,(CROW)
        LD (SAVR),A
        LD A,(CCOL)
        LD (SAVC),A
        LD A,(ATTR)
        LD (SAVA),A
        RET
RESTC:  LD A,(SAVA)
        LD (ATTR),A
        LD A,(SAVR)
        LD D,A
        LD A,(SAVC)
        LD E,A
        JP SETCUR

; DEC special graphics 5Fh-7Eh, as near as ASCII gets
GRTAB:  DB ' *#HFCLo#NV+++++~--__++++|<>p#f.'

; ---------------------------------------------------------------- variables
PB:
CTL:    DB 0
COLS:   DB 0
ROWS:   DB 0
FLAGS:  DB 0
MENUK:  DB 0
SCR:    DW 0
RING:   DW 0
LOGB:   DW 0
LOGSZ:  DW 0
SCREND: DW 0
CROW:   DB 0                    ; the host's cursor
CCOL:   DB 0
WRAPF:  DB 0                    ; 1: the last column was written
ATTR:   DB 0                    ; 80h: inverse
TOP:    DB 0                    ; the scrolling region
BOT:    DB 0
AWM:    DB 0                    ; modes: autowrap, insert, cursor keys
IRM:    DB 0
CKM:    DB 0
GL:     DB 0                    ; character sets: G0 or G1 in use;
G0:     DB 0                    ;   1 = DEC special graphics
G1:     DB 0
PG:     DB 0
SAVR:   DB 0                    ; ESC 7
SAVC:   DB 0
SAVA:   DB 0
PST:    DB 0                    ; parser: 0 text, 1 ESC, 2 CSI, 3 ESC ( ),
NPAR:   DB 0                    ;   4 ESC #, 5 6 VT52 ESC Y
PRIV:   DB 0
PARS:   DB 0,0,0,0
YROW:   DB 0
TROW:   DB 0                    ; the terminal's cursor and attribute
TCOL:   DB 0
TATTR:  DB 0
TOCH:   DB 0
KCH:    DB 0
KLAST:  DB 0                    ; the key sent before
RT:     DB 0
RB:     DB 0
ILOP:   DW 0
CMDV:   DB 0                    ; the WD2123 command in force
TXQ:    DB 0                    ; XON / XOFF to send, 0 none
STOPF:  DB 0                    ; 1: the host was asked to stop
HOLDF:  DB 0                    ; 1: and must stay stopped
LOGON:  DB 0
LOGN:   DW 0
RHEAD:  DW 0
RTAIL:  DW 0
LOST:   DW 0
RCNT:   DW 0
TMO:    DW 0                    ; RECV: the wait for the next byte
SUM:    DB 0
TERMEND:
        END
