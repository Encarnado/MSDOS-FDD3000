; I86.ASM - 8086 interpreter for the Timex FDD3000 (Z80), runs MS-DOS 1.25.
;
; Assembled by z86.py (tmxcobol's z80asm plus ;@FOR / ;@TABLE expansion).
; cpu86.py is the reference: this must do exactly what it does.
;
; Guest memory: 8086 linear address n is Z80 address n, 0000h-CFFFh (52 KB).
; A segment's base (seg << 4) is kept with it, so an operand's host address
; is base + offset, both 16 bits.
;
; Z80 registers while 8086 code runs:
;   BC   host address of the next 8086 code byte (CS base + IP)
;   IX   NEXT, the dispatcher: every handler ends with JP (IX)
;   AF'  the 8086 arithmetic flags. F' holds S Z AF(H) OF(V) CF(C) in the
;        Z80 positions; A' is the low byte of the last result, PF is its
;        parity. Only flag code does EX AF,AF'.
;   A, DE, HL, IY, SP  scratch (SP is the Z80 stack)
;
; The 8086 registers live in memory (REGS), so a ModR/M operand is always a
; host pointer: into guest memory, or into REGS for a register.
;
; Known differences from an 8086: AF after 16-bit add/subtract/inc/dec is
; the Z80's (carry from bit 11, not bit 3); segment wrap above 64 KB is not
; modelled (the guest has 52 KB).

        ORG 0D000h

; ---------------------------------------------------------------- REGS page
REGS:
R_AX    EQU REGS+0
R_AL    EQU REGS+0
R_AH    EQU REGS+1
R_CX    EQU REGS+2
R_CL    EQU REGS+2
R_CH    EQU REGS+3
R_DX    EQU REGS+4
R_DL    EQU REGS+4
R_DH    EQU REGS+5
R_BX    EQU REGS+6
R_BL    EQU REGS+6
R_BH    EQU REGS+7
R_SP    EQU REGS+8
R_BP    EQU REGS+10
R_SI    EQU REGS+12
R_DI    EQU REGS+14
R_ES    EQU REGS+16             ; segment registers, 2 * sreg + 16
R_CS    EQU REGS+18
R_SS    EQU REGS+20
R_DS    EQU REGS+22
B_ES    EQU REGS+24             ; their bases (seg << 4), 2 * sreg + 24
B_CS    EQU REGS+26
B_SS    EQU REGS+28
B_DS    EQU REGS+30
EADS    EQU REGS+32             ; base for DS-relative operands (override aware)
EASS    EQU REGS+34             ; base for SS-relative operands (override aware)
FLAGHI  EQU REGS+36             ; FLAGS bits 8-10: TF IF DF
REPT    EQU REGS+37             ; F2h / F3h: the REP prefix of a string op
STEP1   EQU REGS+38             ; +1 / -1 by DF
STEP2   EQU REGS+40             ; +2 / -2 by DF
TMP     EQU REGS+42
TMP2    EQU REGS+44
DIVISOR EQU REGS+46
R8TAB   EQU REGS+48             ; reg8 number -> offset: AL CL DL BL AH CH DH BH
SHCNT   EQU REGS+56             ; shift count
QNEG    EQU REGS+57             ; bit 7: quotient negative
RNEG    EQU REGS+58             ; bit 7: remainder (dividend) negative
SHORIG  EQU REGS+60             ; operand before a shift
        DS 48
        DB 0,2,4,6,1,3,5,7
        DS REGS+62-$

; ---- serial channels, for BIOS.ASM and CPMZ80.ASM. They are here, in the
; free end of the register page, so that they take no room above the BIOS
; (where CPM.COM's Z80 part goes).
;
; The FDD3000's WD2123 holds two 8251A-compatible channels with their own
; baud-rate generators: channel A data 80h, control and status 81h, baud
; 10h; channel B 40h, 41h, 11h. Status bits: 0 TxRDY, 1 RxRDY, 2 TxEMPTY,
; 3 parity, 4 overrun, 5 framing error, 6 break, 7 CTS (the WD2123 has no
; DSR; on the FDD3000's DE-9s CTS is pin 5, RTS pin 4). Commands: bit 0
; transmit, 1 CS, 2 receive, 3 break, 4 error reset, 5 RTS, 6 internal
; reset. CS (an 8251A's DTR) must be 1: both clocks then come from the
; baud-rate generator (SELCLK is tied high), with 0 the receiver's comes
; from SELCLK and nothing is received (WD2123 datasheet). As in CBIOS A1.1,
; the printer is channel A (CP/M's LIST) and AUX channel B (PUNCH, READER).
; C = the channel's control port throughout.

; SPRN, SAUXO: A to channel A, B; SAUXI: A from channel B; SLSTS: A = FFh
; if channel A's CTS is on, else 0. They wait for ever, as CBIOS A1.1.
SPRN:   LD C,81h
        JR SPF
SAUXO:  LD C,41h
SPF:    LD E,A
        LD HL,0
; SPUT: E to the channel when CTS and TxRDY are on. HL: polls before
; giving up with CF=1 (0: for ever).
SPUT:   LD A,27h                ; transmit, CS, receive, RTS on
        OUT (C),A
        CALL SERR
SP1:    IN A,(C)
        AND 81h
        CP 81h
        JR Z,SP2
        CALL SWAIT
        JR NC,SP1
        RET
SP2:    DEC C
        OUT (C),E
        INC C
        RET
SAUXI:  LD C,41h
        LD HL,0
; SGET: A = a byte from the channel; HL as SPUT. RTS is on only while
; waiting, as CBIOS A1.1's READER does.
SGET:   LD A,27h
        OUT (C),A
SG1:    CALL SERR
        IN A,(C)
        BIT 1,A
        JR NZ,SG2
        CALL SWAIT
        JR NC,SG1
        RET
SG2:    DEC C
        IN E,(C)
        INC C
        LD A,07h
        OUT (C),A
        LD A,E
        OR A
        RET
SLSTS:  LD C,81h
        CALL SERR
        IN A,(C)
        RLA
        SBC A,A
        RET
; SWAIT: one poll more; CF=1 when HL runs out (HL = 0: never)
SWAIT:  LD A,H
        OR L
        RET Z
        DEC HL
        LD A,H
        OR L
        RET NZ
        SCF
        RET
; SERR: clear the error flags, if any (command 37h)
SERR:   IN A,(C)
        AND 78h
        RET Z
        LD A,37h
        OUT (C),A
        RET
; SSET: set the channel up: mode byte D, baud code E (0-15: 50 75 110
; 134.5 150 200 300 600 1200 1800 2400 3600 4800 7200 9600 19200, as TMX
; CONFIGUR lists them; the WD2123's table for 1.8432 MHz, x16). The
; three 0s, as CBIOS A1.1 writes them, do no harm; 40h (internal reset)
; makes the next control write the mode, as the datasheet has it.
; Uses A, HL.
SSET:   XOR A
        OUT (C),A
        OUT (C),A
        OUT (C),A
        LD A,40h
        OUT (C),A
        OUT (C),D
        LD A,07h
        OUT (C),A
        LD A,C                  ; baud register: 10h for A (81h), 11h for B
        RLA
        LD A,11h
        SBC A,0
        PUSH BC
        LD C,A
        OUT (C),E
        LD HL,SAVED-10h         ; kept for INT 14h F0h: the chip can't
        ADD A,L                 ;   be read back
        LD L,A
        LD (HL),D
        INC L
        INC L
        LD (HL),E
        POP BC
        RET
; SSTAT: INT 14h's status: AH = line status (0 data ready, 1 overrun,
; 2 parity, 3 framing, 4 break, 5 and 6 transmitter empty), AL = modem
; status (4 CTS, from status bit 7; 5 DSR, always on: there is none)
SSTAT:  IN A,(C)
        LD D,A
        LD HL,LSMAP
        LD B,7
SS1:    LD A,D
        AND (HL)
        ADD A,0FFh
        RL E
        INC HL
        DJNZ SS1
        LD A,E
        AND 7Fh
        LD (R_AH),A
        LD A,D
        AND 80h
        RRCA
        RRCA
        RRCA
        OR 20h
        LD (R_AL),A
        RET
LSMAP:  DB 04h,01h,40h,20h,08h,10h,02h  ; the 8251A's bits for AH bits 6-0
; INT 14h's baud rates (0-8) as WD2123 codes
BAUDT:  DB 2,4,6,7,8,10,12,14,15        ; 110 150 300 600 1200 2400 4800 9600 19200
;@SLACKAT REGS                  ; ;@SLACK REGS blocks land here (z86.py)
        DS REGS+253-$
BOOTJP: JP COLD                 ; D0FDh: the boot sector jumps here

; ----------------------------------------------- opcode and ModR/M tables
;@TABLE OPLO OPHI ops           ; 256 handlers, low bytes then high bytes
;@TABLE EALO EAHI ea            ; ModR/M 00-BF: memory operand routines
;; ---- INT 14h's FDD3000 calls, AH = F0h / F1h (BIOS.ASM's T_I14 falls into
; I14X).  Their reader I14RD and the copy of the settings, SAVED, sit in
; free slot ends of the ALU blocks: the EALO / EAHI page ends are taken by
; the floppy and REP MOVSW code (;@SLACK, z86.py).
;@SLACK WGAP7
; I14RD: AH = F0h - AL = the channel's mode byte, AH = its baud code, as
; last set by SSET (the WD2123 can't be read back).  C = control port.
I14RD:  LD HL,SAVED+1
        BIT 7,C                 ; channel A: SAVED, B: SAVED+1
        JR Z,I14R1
        DEC L
I14R1:  LD A,(HL)
        LD (R_AL),A
        INC L
        INC L
        LD A,(HL)
        LD (R_AH),A
        RET
;@END
;@SLACK BGAP1
SAVED:  DS 4                    ; mode bytes for A, B, then baud codes (SSET);
                                ; SSET indexes it from SAVED-10h: its low
                                ; byte must be 10h-FCh (asserted in z86.py)
;@END

; ------------------------------------------------- ALU cores, 16-byte slots
; In: HL = destination operand, E = source. Index: (op >> 3) & 7.
BCORE:
        LD A,(HL)               ; 0 ADD
        ADD A,E
        LD (HL),A
        EX AF,AF'
        JP (IX)
;@SLACKAT BGAP0                 ; free end of slot 0 (z86.py ;@SLACK)
        DS BCORE+16-$
        LD A,(HL)               ; 1 OR
        OR E
        ADD A,0                 ; OF = CF = AF = 0
        LD (HL),A
        EX AF,AF'
        JP (IX)
;@SLACKAT BGAP1                 ; free end of slot 1
        DS BCORE+32-$
        EX AF,AF'               ; 2 ADC
        LD A,(HL)
        ADC A,E
        LD (HL),A
        EX AF,AF'
        JP (IX)
        DS BCORE+48-$
        EX AF,AF'               ; 3 SBB
        LD A,(HL)
        SBC A,E
        LD (HL),A
        EX AF,AF'
        JP (IX)
        DS BCORE+64-$
        LD A,(HL)               ; 4 AND
        AND E
        ADD A,0
        LD (HL),A
        EX AF,AF'
        JP (IX)
        DS BCORE+80-$
        LD A,(HL)               ; 5 SUB
        SUB E
        LD (HL),A
        EX AF,AF'
        JP (IX)
        DS BCORE+96-$
        LD A,(HL)               ; 6 XOR
        XOR E
        ADD A,0
        LD (HL),A
        EX AF,AF'
        JP (IX)
        DS BCORE+112-$
        LD A,(HL)               ; 7 CMP
        SUB E
        EX AF,AF'
        JP (IX)
        DS BCORE+128-$

; In: HL = 16-bit operand -> HL + 1, flags as INC (CF kept).
INC16:  EX AF,AF'
        SBC A,A                 ; A = CF ? FFh : 0
        LD DE,0
        SCF
        ADC HL,DE
        RRA                     ; CF back, S Z V untouched
        LD A,L
        EX AF,AF'
        RET

DEC16:  EX AF,AF'
        SBC A,A
        LD DE,0
        SCF
        SBC HL,DE
        RRA
        LD A,L
        EX AF,AF'
        RET

; DE = result of a 16-bit AND/OR/XOR/TEST: S Z PF from it, OF = CF = AF = 0.
LOGF16: EX DE,HL
        XOR A
        LD D,A
        LD E,A
        ADC HL,DE
        LD A,L
        EX AF,AF'
        JP (IX)

; ---- INT 14h's set-up (BIOS.ASM's T_I14, AH = 0 and 4), in the free end
; of this page, as the serial routines are in the register page's
I14EXT: LD A,(R_CL)             ; 4: CL baud 0-8 (110 ... 9600, 19200),
        CP 9                    ;   CH data bits 0-3 (5-8), BL stop bits
        RET NC                  ;   (0: 1, 1: 2), BH parity (0 none, 1 odd,
        LD B,A                  ;   2 even)
        LD A,(R_BH)
        LD D,10h
        DEC A
        JR Z,I14E1
        LD D,30h
        DEC A
        JR Z,I14E1
        LD D,0
I14E1:  LD A,(R_BL)
        AND 1
        RRCA
        OR 40h
        OR D
        LD D,A
        LD A,(R_CH)
        AND 3
        JR I14SET
I14INI: LD A,(R_AL)             ; 0: AL = baud (bits 7-5: 110 ... 9600),
        LD E,A                  ;   parity (4-3: x0 none, 01 odd, 11 even),
        AND 18h                 ;   stop bits (2: 1 or 2), data bits (1-0)
        ADD A,A
        LD D,A
        BIT 2,E
        LD A,40h
        JR Z,I14I1
        LD A,0C0h
I14I1:  OR D
        LD D,A
        LD A,E
        RLCA
        RLCA
        RLCA
        AND 7
        LD B,A
        LD A,E
        AND 3
I14SET: ADD A,A                 ; A = data bits 0-3, D = parity and stop
        ADD A,A                 ;   bits, B = index in BAUDT
        OR D
        OR 2                    ; x16 clock
        LD D,A
        LD HL,BAUDT
        LD A,L
        ADD A,B
        LD L,A
        JR NC,I14S1
        INC H
I14S1:  LD E,(HL)
        CALL SSET
        JP SSTAT

        DS (($+255)&0FF00h)-$
; ------------------------------------------------- ALU cores, 32-byte slots
; In: HL = destination operand, DE = source value.
WCORE:
        PUSH HL                 ; 0 ADD
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        OR A
        ADC HL,DE
        LD A,L
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
        DS WCORE+32-$
        LD A,(HL)               ; 1 OR
        OR E
        LD E,A
        LD (HL),A
        INC HL
        LD A,(HL)
        OR D
        LD D,A
        LD (HL),A
        JP LOGF16
        DS WCORE+64-$
        PUSH HL                 ; 2 ADC
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        EX AF,AF'
        ADC HL,DE
        LD A,L
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
        DS WCORE+96-$
        PUSH HL                 ; 3 SBB
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        EX AF,AF'
        SBC HL,DE
        LD A,L
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
        DS WCORE+128-$
        LD A,(HL)               ; 4 AND
        AND E
        LD E,A
        LD (HL),A
        INC HL
        LD A,(HL)
        AND D
        LD D,A
        LD (HL),A
        JP LOGF16
        DS WCORE+160-$
        PUSH HL                 ; 5 SUB
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        OR A
        SBC HL,DE
        LD A,L
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
        DS WCORE+192-$
        LD A,(HL)               ; 6 XOR
        XOR E
        LD E,A
        LD (HL),A
        INC HL
        LD A,(HL)
        XOR D
        LD D,A
        LD (HL),A
        JP LOGF16
        DS WCORE+224-$
        LD A,(HL)               ; 7 CMP
        INC HL
        LD H,(HL)
        LD L,A
        OR A
        SBC HL,DE
        LD A,L
        EX AF,AF'
        JP (IX)
;@SLACKAT WGAP7                 ; free end of slot 7
        DS WCORE+256-$

; ---------------------------------------------- shift / rotate loops
; 16-bit at k*16, 8-bit at 128 + k*16 (k = ModR/M reg field).
; In: HL (L) = value, D = count > 0; stack: old AF', operand address.
; Out: Z80 C = last bit out, then a finisher sets the flags and stores.
SHPG:
S16R0:  ADD HL,HL               ; 0 ROL
        JR NC,S16R0A
        INC L
S16R0A: DEC D
        JR NZ,S16R0
        JP ROT16A
        DS SHPG+16-$
S16R1:  SRL H                   ; 1 ROR
        RR L
        JR NC,S16R1A
        SET 7,H
S16R1A: DEC D
        JR NZ,S16R1
        JP ROT16B
        DS SHPG+32-$
        POP AF                  ; 2 RCL: CF in
        PUSH AF
S16R2:  RL L
        RL H
        DEC D
        JR NZ,S16R2
        JP ROT16A
        DS SHPG+48-$
        POP AF                  ; 3 RCR
        PUSH AF
S16R3:  RR H
        RR L
        DEC D
        JR NZ,S16R3
        JP ROT16B
        DS SHPG+64-$
S16R4:  ADD HL,HL               ; 4 SHL
        DEC D
        JR NZ,S16R4
        JP SHL16F
        DS SHPG+80-$
S16R5:  SRL H                   ; 5 SHR
        RR L
        DEC D
        JR NZ,S16R5
        JP SHR16F
        DS SHPG+96-$
S16R6:  ADD HL,HL               ; 6 SAL (= SHL)
        DEC D
        JR NZ,S16R6
        JP SHL16F
        DS SHPG+112-$
S16R7:  SRA H                   ; 7 SAR
        RR L
        DEC D
        JR NZ,S16R7
        JP SAR16F
        DS SHPG+128-$
S8R0:   RLC L                   ; 0 ROL
        DEC D
        JR NZ,S8R0
        JP ROT8A
        DS SHPG+144-$
S8R1:   RRC L                   ; 1 ROR
        DEC D
        JR NZ,S8R1
        JP ROT8B
        DS SHPG+160-$
        POP AF                  ; 2 RCL
        PUSH AF
S8R2:   RL L
        DEC D
        JR NZ,S8R2
        JP ROT8A
        DS SHPG+176-$
        POP AF                  ; 3 RCR
        PUSH AF
S8R3:   RR L
        DEC D
        JR NZ,S8R3
        JP ROT8B
        DS SHPG+192-$
S8R4:   SLA L                   ; 4 SHL
        DEC D
        JR NZ,S8R4
        JP SHL8F
        DS SHPG+208-$
S8R5:   SRL L                   ; 5 SHR
        DEC D
        JR NZ,S8R5
        JP SHR8F
        DS SHPG+224-$
S8R6:   SLA L                   ; 6 SAL
        DEC D
        JR NZ,S8R6
        JP SHL8F
        DS SHPG+240-$
S8R7:   SRA L                   ; 7 SAR
        DEC D
        JR NZ,S8R7
        JP SAR8F
        DS SHPG+256-$

; ================================================================ dispatch
; Start: the registers, segments and flags are in REGS / AF', IP in TMP.
START:  DI
        LD SP,0
        LD IX,NEXT
        LD HL,(R_ES)
        CALL SHL4
        LD (B_ES),HL
        LD HL,(R_SS)
        CALL SHL4
        LD (B_SS),HL
        LD (EASS),HL
        LD HL,(R_DS)
        CALL SHL4
        LD (B_DS),HL
        LD (EADS),HL
        CALL SETSTEP
        LD HL,(R_CS)
        LD DE,(TMP)
        JP FARJ

SHL4:   ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        RET

NEXT:   LD A,(BC)
        INC BC
        LD L,A
        LD H,OPLO>>8
        LD E,(HL)
        INC H
        LD D,(HL)
        EX DE,HL
        JP (HL)                 ; handler gets A = opcode

; After a prefix: the next byte.
NEXT2:  LD A,(BC)
        INC BC
DISPA:  LD L,A
        LD H,OPLO>>8
        LD E,(HL)
        INC H
        LD D,(HL)
        EX DE,HL
        JP (HL)

; 26 2E 36 3E: segment override. The operand bases become the segment's
; and IX points at RESTORE for one instruction, which puts them back.
;@FOR S ES CS SS DS
O_SEG_{S}:
        LD HL,(B_{S})
        LD (EADS),HL
        LD (EASS),HL
        LD IX,RESTORE
        JP NEXT2
;@END

SEGSET: RRCA                    ; the same, A = prefix (after REP)
        RRCA
        AND 06h
        ADD A,B_ES&0FFh
        LD L,A
        LD H,REGS>>8
        LD E,(HL)
        INC L
        LD D,(HL)
        LD (EADS),DE
        LD (EASS),DE
        LD IX,RESTORE
        RET

RESTORE:
        LD HL,(B_DS)
        LD (EADS),HL
        LD HL,(B_SS)
        LD (EASS),HL
        LD IX,NEXT
        JP (IX)

O_LOCK  EQU NEXT2

O_BAD:  DEC BC
BADSTOP:
        JR BADSTOP              ; unknown opcode (the harness stops here)

O_HLT:
HALTED: JR HALTED

O_NOP:  JP (IX)

; 0F nn: BIOS trap (POP CS on a real 8086)
O_TRAP: LD A,(BC)
        INC BC
        CALL TRAP
        JP (IX)

; TRAP (A = function) is the BIOS: BIOS.ASM, or a RET that z86.py hooks.

; ============================================================ ModR/M decode
; MRW: fetch ModR/M of a word op -> HL = r/m operand, DE = reg operand.
MRW:    LD A,(BC)
        INC BC
        CP 0C0h
        JR C,MRWM
        LD E,A
        AND 7
        ADD A,A
        LD L,A
        LD A,E
        RRCA
        RRCA
        AND 0Eh
        LD E,A
        LD H,REGS>>8
        LD D,H
        RET
MRWM:   PUSH AF
        CALL EAMEM
        POP AF
        RRCA
        RRCA
        AND 0Eh
        LD E,A
        LD D,REGS>>8
        RET

; MRB: the same for a byte op.
MRB:    LD A,(BC)
        INC BC
        CP 0C0h
        JR C,MRBM
        LD E,A
        AND 7
        OR R8TAB&0FFh
        LD L,A
        LD H,REGS>>8
        LD L,(HL)
        LD A,E
        JR REG8
MRBM:   PUSH AF
        CALL EAMEM
        POP AF
REG8:   RRCA                    ; A = ModR/M -> DE = reg8 operand
        RRCA
        RRCA
        AND 7
        OR R8TAB&0FFh
        LD E,A
        LD D,REGS>>8
        LD A,(DE)
        LD E,A
        RET

; EAW / EAB: A = ModR/M (fetched) -> HL = r/m operand
EAW:    CP 0C0h
        JR C,EAMEM
        AND 7
        ADD A,A
        LD L,A
        LD H,REGS>>8
        RET
EAB:    CP 0C0h
        JR C,EAMEM
        AND 7
        OR R8TAB&0FFh
        LD L,A
        LD H,REGS>>8
        LD L,(HL)
        RET
EAMEM:  LD L,A
        LD H,EALO>>8
        LD E,(HL)
        INC H
        LD D,(HL)
        EX DE,HL
        JP (HL)

; memory operands: EA<mod><rm>
EA00:   LD HL,(R_BX)
        LD DE,(R_SI)
        ADD HL,DE
ADDDS:  LD DE,(EADS)
        ADD HL,DE
        RET
EA01:   LD HL,(R_BX)
        LD DE,(R_DI)
        ADD HL,DE
        JR ADDDS
EA02:   LD HL,(R_BP)
        LD DE,(R_SI)
        ADD HL,DE
ADDSS:  LD DE,(EASS)
        ADD HL,DE
        RET
EA03:   LD HL,(R_BP)
        LD DE,(R_DI)
        ADD HL,DE
        JR ADDSS
EA04:   LD HL,(R_SI)
        JR ADDDS
EA05:   LD HL,(R_DI)
        JR ADDDS
EA06:   LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        INC BC
        JR ADDDS
EA07:   LD HL,(R_BX)
        JR ADDDS

EA10:   LD HL,(R_BX)
        LD DE,(R_SI)
        ADD HL,DE
D8DS:   LD A,(BC)
        INC BC
        LD E,A
        ADD A,A
        SBC A,A
        LD D,A
        ADD HL,DE
        JR ADDDS
EA11:   LD HL,(R_BX)
        LD DE,(R_DI)
        ADD HL,DE
        JR D8DS
EA12:   LD HL,(R_BP)
        LD DE,(R_SI)
        ADD HL,DE
D8SS:   LD A,(BC)
        INC BC
        LD E,A
        ADD A,A
        SBC A,A
        LD D,A
        ADD HL,DE
        JR ADDSS
EA13:   LD HL,(R_BP)
        LD DE,(R_DI)
        ADD HL,DE
        JR D8SS
EA14:   LD HL,(R_SI)
        JR D8DS
EA15:   LD HL,(R_DI)
        JR D8DS
EA16:   LD HL,(R_BP)
        JR D8SS
EA17:   LD HL,(R_BX)
        JR D8DS

EA20:   LD HL,(R_BX)
        LD DE,(R_SI)
        ADD HL,DE
D16DS:  LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        ADD HL,DE
        JR ADDDS
EA21:   LD HL,(R_BX)
        LD DE,(R_DI)
        ADD HL,DE
        JR D16DS
EA22:   LD HL,(R_BP)
        LD DE,(R_SI)
        ADD HL,DE
D16SS:  LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        ADD HL,DE
        JR ADDSS
EA23:   LD HL,(R_BP)
        LD DE,(R_DI)
        ADD HL,DE
        JR D16SS
EA24:   LD HL,(R_SI)
        JR D16DS
EA25:   LD HL,(R_DI)
        JR D16DS
EA26:   LD HL,(R_BP)
        JR D16SS
EA27:   LD HL,(R_BX)
        JR D16DS

; Jump to entry A/2 of the table at DE, keeping HL.
JTAB:   ADD A,E
        LD E,A
        JR NC,JTAB1
        INC D
JTAB1:  EX DE,HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        EX DE,HL
        PUSH DE
        RET

; ================================================================ helpers
; GETIP: DE = IP
GETIP:  LD HL,(B_CS)
        LD A,C
        SUB L
        LD E,A
        LD A,B
        SBC A,H
        LD D,A
        RET

; FARJ: jump to HL:DE (CS:IP)
FARJ:   LD (R_CS),HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD (B_CS),HL
        ADD HL,DE
        LD B,H
        LD C,L
        JP (IX)

; PUSHDE / POPDE: the 8086 stack. Use A, HL.
PUSHDE: LD HL,(R_SP)
        DEC HL
        DEC HL
        LD (R_SP),HL
        LD A,(B_SS)
        ADD A,L
        LD L,A
        LD A,(B_SS+1)
        ADC A,H
        LD H,A
        LD (HL),E
        INC HL
        LD (HL),D
        RET

POPDE:  LD HL,(R_SP)
        LD A,(B_SS)
        ADD A,L
        LD E,A
        LD A,(B_SS+1)
        ADC A,H
        LD D,A
        INC HL
        INC HL
        LD (R_SP),HL
        EX DE,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        RET

; SETSEG: segment register A/2 (0 ES, 1 CS, 2 SS, 3 DS) = DE, with its base
SETSEG: ADD A,R_ES&0FFh
        LD L,A
        LD H,REGS>>8
        LD (HL),E
        INC L
        LD (HL),D
        LD A,L
        ADD A,8
        LD L,A
        EX DE,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        EX DE,HL
        LD (HL),D
        DEC L
        LD (HL),E
        LD A,L
        CP B_DS&0FFh
        JR Z,SETSG1
        CP B_SS&0FFh
        RET NZ
        LD (EASS),DE
        RET
SETSG1: LD (EADS),DE
        RET

; GETF: HL = FLAGS. AF' unchanged. Uses A, DE.
GETF:   EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP DE                  ; D = A' (PF byte), E = F'
        LD A,E
        AND 0D1h                ; S Z AF CF
        OR 02h
        LD L,A
        LD A,D
        OR A
        JP PO,GETF1
        SET 2,L                 ; even parity: PF
GETF1:  LD A,(FLAGHI)
        OR 0F0h
        BIT 2,E
        JR Z,GETF2
        OR 08h                  ; OF
GETF2:  LD H,A
        RET

; SETF: FLAGS = HL
SETF:   LD A,L
        AND 0D1h
        BIT 3,H
        JR Z,SETF1
        OR 04h                  ; OF -> V
SETF1:  LD E,A
        LD D,0                  ; A' = 0: even parity, PF = 1
        BIT 2,L
        JR NZ,SETF2
        INC D                   ; A' = 1: PF = 0
SETF2:  PUSH DE
        POP AF
        EX AF,AF'
        LD A,H
        AND 07h
        LD (FLAGHI),A
SETSTEP:
        LD A,(FLAGHI)
        AND 4
        LD HL,1
        LD DE,2
        JR Z,SETST1
        LD HL,-1
        LD DE,-2
SETST1: LD (STEP1),HL
        LD (STEP2),DE
        RET

; SETCO: CF = OF = Z80 NZ, the other flags kept
SETCO:  LD E,0
        JR Z,SETCO1
        LD E,05h
SETCO1: EX AF,AF'
        PUSH AF
        POP HL
        LD A,L
        AND 0FAh
        OR E
        LD L,A
        PUSH HL
        POP AF
        EX AF,AF'
        RET

; SZP8: AL-type result in A: S Z PF from it, CF OF AF kept
SZP8:   LD D,A
        EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP HL
        LD A,L
        AND 15h                 ; AF OF CF
        LD E,A
        LD A,D
        AND 80h
        OR E
        LD E,A
        LD A,D
        OR A
        JR NZ,SZP81
        SET 6,E
SZP81:  PUSH DE
        POP AF
        EX AF,AF'
        JP (IX)

; ============================================================ 00-3F ALU
O_ALU0: AND 38h                 ; r/m8 op= r8
        ADD A,A
        LD (ALU0J+1),A
        CALL MRB
        LD A,(DE)
        LD E,A
ALU0J:  JP BCORE

O_ALU1: AND 38h                 ; r/m16 op= r16
        ADD A,A
        ADD A,A
        LD (ALU1J+1),A
        CALL MRW
        EX DE,HL
        LD A,(HL)
        INC L
        LD H,(HL)
        LD L,A
        EX DE,HL
ALU1J:  JP WCORE

O_ALU2: AND 38h                 ; r8 op= r/m8
        ADD A,A
        LD (ALU2J+1),A
        CALL MRB
        LD A,(HL)
        EX DE,HL
        LD E,A
ALU2J:  JP BCORE

O_ALU3: AND 38h                 ; r16 op= r/m16
        ADD A,A
        ADD A,A
        LD (ALU3J+1),A
        CALL MRW
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        EX DE,HL
ALU3J:  JP WCORE

O_ALU4: AND 38h                 ; AL op= imm8
        ADD A,A
        LD (ALU4J+1),A
        LD A,(BC)
        INC BC
        LD E,A
        LD HL,R_AL
ALU4J:  JP BCORE

O_CMPAL:                        ; 3C CMP AL,imm8 (the most common one)
        LD A,(BC)
        INC BC
        LD E,A
        LD A,(R_AL)
        SUB E
        EX AF,AF'
        JP (IX)

O_ALU5: AND 38h                 ; AX op= imm16
        ADD A,A
        ADD A,A
        LD (ALU5J+1),A
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        LD HL,R_AX
ALU5J:  JP WCORE

; 06 0E 16 1E / 07 17 1F: PUSH / POP segment
;@FOR S ES CS SS DS
O_PUSH_{S}:
        LD DE,(R_{S})
        CALL PUSHDE
        JP (IX)
;@END
O_POP_ES:
        CALL POPDE
        XOR A
        CALL SETSEG
        JP (IX)
O_POP_SS:
        CALL POPDE
        LD A,4
        CALL SETSEG
        JP (IX)
O_POP_DS:
        CALL POPDE
        LD A,6
        CALL SETSEG
        JP (IX)

; 27 DAA, 2F DAS
O_DAA:  EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP DE                  ; E = old flags
        LD A,(R_AL)
        LD H,A                  ; old AL
        LD D,A                  ; AL
        LD L,0                  ; new AF | CF
        AND 0Fh
        CP 10
        JR NC,DAA1
        BIT 4,E
        JR Z,DAA2
DAA1:   LD A,D
        ADD A,6
        LD D,A
        LD L,10h
DAA2:   LD A,H
        CP 9Ah
        JR NC,DAA3
        BIT 0,E
        JR Z,DAAF
DAA3:   LD A,D
        ADD A,60h
        LD D,A
        SET 0,L
; D = new AL, L = AF | CF, E = old flags (OF kept)
DAAF:   LD A,D
        LD (R_AL),A
        LD A,E
        AND 04h
        OR L
        LD L,A
        LD A,D
        AND 80h
        OR L
        LD L,A
        LD A,D
        OR A
        JR NZ,DAAF1
        SET 6,L
DAAF1:  LD E,L
        PUSH DE
        POP AF
        EX AF,AF'
        JP (IX)

O_DAS:  EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP DE
        LD A,(R_AL)
        LD H,A
        LD D,A
        LD L,0
        AND 0Fh
        CP 10
        JR NC,DAS1
        BIT 4,E
        JR Z,DAS2
DAS1:   LD A,D
        SUB 6
        LD D,A
        LD L,10h
DAS2:   LD A,H
        CP 9Ah
        JR NC,DAS3
        BIT 0,E
        JR Z,DAAF
DAS3:   LD A,D
        SUB 60h
        LD D,A
        SET 0,L
        JR DAAF

; 37 AAA, 3F AAS: AF CF set, the rest kept
O_AAA:  EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP DE
        LD HL,(R_AX)
        LD A,L
        AND 0Fh
        CP 10
        JR NC,AAA1
        BIT 4,E
        JR Z,AAA0
AAA1:   PUSH DE
        LD DE,106h
        ADD HL,DE
        POP DE
AAAS1:  LD A,E
        OR 11h
        LD E,A
        JR AAA2
AAA0:   LD A,E
        AND 0EEh
        LD E,A
AAA2:   LD A,L
        AND 0Fh
        LD L,A
        LD (R_AX),HL
        PUSH DE
        POP AF
        EX AF,AF'
        JP (IX)

O_AAS:  EX AF,AF'
        PUSH AF
        EX AF,AF'
        POP DE
        LD HL,(R_AX)
        LD A,L
        AND 0Fh
        CP 10
        JR NC,AAS1
        BIT 4,E
        JR Z,AAA0
AAS1:   LD A,L
        SUB 6
        LD L,A
        DEC H
        JR AAAS1

; ============================================================ 40-5F
;@FOR R AX CX DX BX SP BP SI DI
O_INC_{R}:
        LD HL,(R_{R})
        CALL INC16
        LD (R_{R}),HL
        JP (IX)
O_DEC_{R}:
        LD HL,(R_{R})
        CALL DEC16
        LD (R_{R}),HL
        JP (IX)
O_POP_{R}:                      ; POPDE, inline
        LD HL,(R_SP)
        LD A,(B_SS)
        ADD A,L
        LD E,A
        LD A,(B_SS+1)
        ADC A,H
        LD D,A
        INC HL
        INC HL
        LD (R_SP),HL
        EX DE,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (R_{R}),DE
        JP (IX)
;@END
;@FOR R AX CX DX BX BP SI DI
O_PUSH_{R}:
        LD DE,(R_{R})
        JP PUSHX
;@END
O_PUSH_SP:                      ; the 8086 pushes SP after the decrement
        LD HL,(R_SP)
        DEC HL
        DEC HL
        EX DE,HL
PUSHX:  LD HL,(R_SP)            ; PUSHDE, then the next instruction
        DEC HL
        DEC HL
        LD (R_SP),HL
        LD A,(B_SS)
        ADD A,L
        LD L,A
        LD A,(B_SS+1)
        ADC A,H
        LD H,A
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)

; ============================================================ 70-7F Jcc
J_TAKE: EX AF,AF'
O_JREL8:
JREL8:  LD A,(BC)
        INC BC
        LD L,A
        ADD A,A
        SBC A,A
        LD H,A
        ADD HL,BC
        LD B,H
        LD C,L
        JP (IX)
J_NOT:  EX AF,AF'
        INC BC
        JP (IX)

O_JO:   EX AF,AF'
        JP PE,J_TAKE
        JR J_NOT
O_JNO:  EX AF,AF'
        JP PO,J_TAKE
        JR J_NOT
O_JB:   EX AF,AF'
        JR C,J_TAKE
        EX AF,AF'
        INC BC
        JP (IX)
O_JNB:  EX AF,AF'
        JR NC,J_TAKE
        EX AF,AF'
        INC BC
        JP (IX)
O_JZ:   EX AF,AF'
        JR Z,J_TAKE
        EX AF,AF'
        INC BC
        JP (IX)
O_JNZ:  EX AF,AF'
        JR NZ,J_TAKE
        EX AF,AF'
        INC BC
        JP (IX)
O_JBE:  EX AF,AF'
        JR C,J_TAKE
        JR Z,J_TAKE
        JR J_NOT
O_JA:   EX AF,AF'
        JR C,J_NOT
        JR Z,J_NOT
        JR J_TAKE
O_JS:   EX AF,AF'
        JP M,J_TAKE
        JR J_NOT
O_JNS:  EX AF,AF'
        JP P,J_TAKE
        JR J_NOT
O_JP:   EX AF,AF'
        PUSH AF
        OR A
        JP PO,JP1
        POP AF
        JR J_TAKE
O_JNP:  EX AF,AF'
        PUSH AF
        OR A
        JP PE,JP1
        POP AF
        JR J_TAKE
JP1:    POP AF
        JR J_NOT
O_JL:   EX AF,AF'               ; S != OF
        JP PE,JL1
        JP M,J_TAKE
        JR J_NOT
JL1:    JP P,J_TAKE
        JR J_NOT
O_JGE:  EX AF,AF'
        JP PE,JGE1
        JP P,J_TAKE
        JR J_NOT
JGE1:   JP M,J_TAKE
        JR J_NOT
O_JLE:  EX AF,AF'
        JR Z,J_TAKE
        JP PE,JL1
        JP M,J_TAKE
        JR J_NOT
O_JG:   EX AF,AF'
        JR Z,J_NOT
        JP PE,JGE1
        JP P,J_TAKE
        JR J_NOT

; ============================================================ 80-8F
O_GRP80:                        ; 80 / 82: r/m8, imm8
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAB
        POP AF
        AND 38h
        ADD A,A
        LD (G80J+1),A
        LD A,(BC)
        INC BC
        LD E,A
G80J:   JP BCORE

O_GRP81:                        ; r/m16, imm16
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        AND 38h
        ADD A,A
        ADD A,A
        LD (G81J+1),A
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
G81J:   JP WCORE

O_GRP83:                        ; r/m16, imm8 sign-extended
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        AND 38h
        ADD A,A
        ADD A,A
        LD (G83J+1),A
        LD A,(BC)
        INC BC
        LD E,A
        ADD A,A
        SBC A,A
        LD D,A
G83J:   JP WCORE

O_TEST84:
        CALL MRB
        LD A,(DE)
        AND (HL)
        ADD A,0
        EX AF,AF'
        JP (IX)

O_TEST85:
        CALL MRW
        LD A,(DE)
        AND (HL)
        INC HL
        INC E
        PUSH AF
        LD A,(DE)
        AND (HL)
        LD D,A
        POP AF
        LD E,A
        JP LOGF16

O_XCHG86:
        CALL MRB
        LD A,(DE)
        PUSH AF
        LD A,(HL)
        LD (DE),A
        POP AF
        LD (HL),A
        JP (IX)

O_XCHG87:
        CALL MRW
        LD A,(DE)
        PUSH AF
        LD A,(HL)
        LD (DE),A
        POP AF
        LD (HL),A
        INC HL
        INC E
        LD A,(DE)
        PUSH AF
        LD A,(HL)
        LD (DE),A
        POP AF
        LD (HL),A
        JP (IX)

O_MOV88:
        CALL MRB
        LD A,(DE)
        LD (HL),A
        JP (IX)

O_MOV89:
        CALL MRW
        LD A,(DE)
        LD (HL),A
        INC HL
        INC E
        LD A,(DE)
        LD (HL),A
        JP (IX)

O_MOV8A:
        CALL MRB
        LD A,(HL)
        LD (DE),A
        JP (IX)

O_MOV8B:
        CALL MRW
        LD A,(HL)
        LD (DE),A
        INC HL
        INC E
        LD A,(HL)
        LD (DE),A
        JP (IX)

O_MOV8C:                        ; MOV r/m16, sreg
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        RRCA
        RRCA
        AND 06h
        ADD A,R_ES&0FFh
        LD E,A
        LD D,REGS>>8
        LD A,(DE)
        LD (HL),A
        INC HL
        INC E
        LD A,(DE)
        LD (HL),A
        JP (IX)

O_LEA:  LD A,(BC)
        INC BC
        PUSH AF
        LD HL,0
        CP 0C0h
        JR NC,LEA1              ; LEA r,reg: 0, as cpu86
        LD (EADS),HL
        LD (EASS),HL
        CALL EAMEM
        LD DE,(B_DS)
        LD (EADS),DE
        LD DE,(B_SS)
        LD (EASS),DE
LEA1:   POP AF
        RRCA
        RRCA
        AND 0Eh
        LD E,A
        LD D,REGS>>8
        EX DE,HL
        LD (HL),E
        INC L
        LD (HL),D
        JP (IX)

O_MOV8E:                        ; MOV sreg, r/m16
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        LD E,(HL)
        INC HL
        LD D,(HL)
        RRCA
        RRCA
        AND 06h
        CP 2
        JR Z,MOVCS
        CALL SETSEG
        JP (IX)
MOVCS:  PUSH DE                 ; CS changes, IP stays
        CALL GETIP
        POP HL
        JP FARJ

O_POP8F:
        CALL POPDE
        PUSH DE
        LD A,(BC)
        INC BC
        CALL EAW
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)

; ============================================================ 90-9F
O_XCHGA:
        AND 7
        ADD A,A
        LD L,A
        LD H,REGS>>8
        LD E,(HL)
        INC L
        LD D,(HL)
        LD A,(R_AH)
        LD (HL),A
        DEC L
        LD A,(R_AL)
        LD (HL),A
        LD (R_AX),DE
        JP (IX)

O_CBW:  LD A,(R_AL)
        ADD A,A
        SBC A,A
        LD (R_AH),A
        JP (IX)

O_CWD:  LD A,(R_AH)
        ADD A,A
        SBC A,A
        LD (R_DL),A
        LD (R_DH),A
        JP (IX)

O_CALLF:
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        PUSH DE                 ; new IP
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        PUSH DE                 ; new CS
        LD DE,(R_CS)
        CALL PUSHDE
        CALL GETIP
        CALL PUSHDE
        POP HL
        POP DE
        JP FARJ

O_PUSHF:
        CALL GETF
        EX DE,HL
        CALL PUSHDE
        JP (IX)

O_POPF: CALL POPDE
        EX DE,HL
        CALL SETF
        JP (IX)

O_SAHF: CALL GETF
        LD A,(R_AH)
        LD L,A
        CALL SETF
        JP (IX)

O_LAHF: CALL GETF
        LD A,L
        AND 0D5h
        OR 2
        LD (R_AH),A
        JP (IX)

; ============================================================ A0-AF
O_MOVA0:
        LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        INC BC
        LD DE,(EADS)
        ADD HL,DE
        LD A,(HL)
        LD (R_AL),A
        JP (IX)
O_MOVA1:
        LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        INC BC
        LD DE,(EADS)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (R_AX),DE
        JP (IX)
O_MOVA2:
        LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        INC BC
        LD DE,(EADS)
        ADD HL,DE
        LD A,(R_AL)
        LD (HL),A
        JP (IX)
O_MOVA3:
        LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        INC BC
        LD DE,(EADS)
        ADD HL,DE
        LD DE,(R_AX)
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)

O_TESTA8:
        LD A,(BC)
        INC BC
        LD E,A
        LD A,(R_AL)
        AND E
        ADD A,0
        EX AF,AF'
        JP (IX)
O_TESTA9:
        LD A,(BC)
        INC BC
        LD HL,R_AL
        AND (HL)
        LD E,A
        LD A,(BC)
        INC BC
        INC L
        AND (HL)
        LD D,A
        JP LOGF16

; string operands: HL = DS:SI (override aware) / ES:DI
SRCPTR: LD HL,(R_SI)
        LD DE,(EADS)
        ADD HL,DE
        RET
DSTPTR: LD HL,(R_DI)
        LD DE,(B_ES)
        ADD HL,DE
        RET
NSI1:   LD HL,(R_SI)
        LD DE,(STEP1)
        ADD HL,DE
        LD (R_SI),HL
        RET
NDI1:   LD HL,(R_DI)
        LD DE,(STEP1)
        ADD HL,DE
        LD (R_DI),HL
        RET
NSI2:   LD HL,(R_SI)
        LD DE,(STEP2)
        ADD HL,DE
        LD (R_SI),HL
        RET
NDI2:   LD HL,(R_DI)
        LD DE,(STEP2)
        ADD HL,DE
        LD (R_DI),HL
        RET

O_MOVSB:
        CALL SRCPTR
        LD A,(HL)
        PUSH AF
        CALL DSTPTR
        POP AF
        LD (HL),A
        CALL NSI1
        CALL NDI1
        JP (IX)
O_MOVSW:
        CALL SRCPTR
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        PUSH HL
        CALL DSTPTR
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        CALL NSI2
        CALL NDI2
        JP (IX)
CMPSB1: CALL DSTPTR             ; flags of [SI] - [ES:DI]
        LD A,(HL)
        LD (TMP),A
        CALL SRCPTR
        LD A,(TMP)
        LD E,A
        LD A,(HL)
        SUB E
        EX AF,AF'
        CALL NSI1
        JP NDI1
O_CMPSB:
        CALL CMPSB1
        JP (IX)
CMPSW1: CALL DSTPTR
        LD E,(HL)
        INC HL
        LD D,(HL)
        PUSH DE
        CALL SRCPTR
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        POP DE
        OR A
        SBC HL,DE
        LD A,L
        EX AF,AF'
        CALL NSI2
        JP NDI2
O_CMPSW:
        CALL CMPSW1
        JP (IX)
O_STOSB:
        CALL DSTPTR
        LD A,(R_AL)
        LD (HL),A
        CALL NDI1
        JP (IX)
O_STOSW:
        CALL DSTPTR
        LD DE,(R_AX)
        LD (HL),E
        INC HL
        LD (HL),D
        CALL NDI2
        JP (IX)
O_LODSB:
        CALL SRCPTR
        LD A,(HL)
        LD (R_AL),A
        CALL NSI1
        JP (IX)
O_LODSW:
        LD HL,(R_SI)
        PUSH HL
        LD DE,(EADS)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (R_AX),DE
        POP HL
        LD DE,(STEP2)
        ADD HL,DE
        LD (R_SI),HL
        JP (IX)
SCASB1: CALL DSTPTR             ; flags of AL - [ES:DI]
        LD A,(R_AL)
        SUB (HL)
        EX AF,AF'
        JP NDI1
O_SCASB:
        CALL SCASB1
        JP (IX)
SCASW1: CALL DSTPTR
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(R_AX)
        OR A
        SBC HL,DE
        LD A,L
        EX AF,AF'
        JP NDI2
O_SCASW:
        CALL SCASW1
        JP (IX)

; ------------------------------------------------------ REP prefix
O_REP:  LD (REPT),A
REP1:   LD A,(BC)
        INC BC
        CP 0A4h
        JR C,REP2
        CP 0B0h
        JR NC,REP3
        SUB 0A4h
        ADD A,A
        LD L,A
        LD H,0
        LD DE,REPTAB
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP (HL)
REP2:   LD E,A
        AND 0E7h
        CP 26h
        LD A,E
        JR NZ,REP3
        CALL SEGSET
        JR REP1
REP3:   CP 0F2h
        JR Z,O_REP
        CP 0F3h
        JR Z,O_REP
        CP 0F0h
        JR Z,REP1
        JP DISPA

REPTAB: DW R_MOVSB, R_MOVSW, R_CMPSB, R_CMPSW, R_NOTSTR, R_NOTSTR
        DW R_STOSB, R_STOSW, R_LODSB, R_LODSW, R_SCASB, R_SCASW

R_NOTSTR:                       ; A8 / A9 after REP: plain TEST
        DEC BC
        JP NEXT2

; CXNZ: HL = CX, Z80 Z if zero
CXNZ:   LD HL,(R_CX)
        LD A,H
        OR L
        RET

; RADV: SI and/or DI += DE * STEP1 (DE = bytes moved), CX = 0
RADVSD: CALL RNEG_DE
        LD HL,(R_SI)
        ADD HL,DE
        LD (R_SI),HL
RADVD:  LD HL,(R_DI)
        ADD HL,DE
        LD (R_DI),HL
        LD HL,0
        LD (R_CX),HL
        JP (IX)
RADVDN: CALL RNEG_DE
        JR RADVD
RNEG_DE:                        ; DE = -DE if DF
        LD A,(STEP1+1)
        RLA
        RET NC
        XOR A
        SUB E
        LD E,A
        SBC A,A
        SUB D
        LD D,A
        RET

R_MOVSB:
        CALL CXNZ
        JR NZ,RMB1
        JP (IX)
RMB1:   PUSH BC
        PUSH HL                 ; count
        CALL DSTPTR
        PUSH HL
        CALL SRCPTR
        POP DE
        POP BC
        LD A,(STEP1+1)
        RLA
        JR C,RMB2
        LDIR
        JR RMB3
RMB2:   LDDR
RMB3:   POP BC
        LD DE,(R_CX)
        JR RADVSD

R_MOVSW:
        CALL CXNZ
        JR NZ,RMW1
        JP (IX)
RMW1:   PUSH BC
        ADD HL,HL
        PUSH HL                 ; bytes
        CALL DSTPTR
        PUSH HL
        CALL SRCPTR
        POP DE
        POP BC
        CALL MWCHK              ; A = (STEP1+1); one-byte overlap: word loop
        RLA
        JR C,RMW2
        LDIR
        JR RMW3
RMW2:   INC HL                  ; from the high byte of the first word down
        INC DE
        LDDR
RMW3:   POP BC
        LD HL,(R_CX)
        ADD HL,HL
        EX DE,HL
        JR RADVSD

; A word copy is not a byte copy when the destination starts one byte
; into the source word not yet read: DI = SI + 1 going up (DF = 0), or
; DI = SI - 1 going down.  Then each MOVSW must read its word before it
; writes, as the 8086 does: MWCHK sends those cases to MWSLOW, which runs
; O_MOVSW CX times (IX pointed back at its loop).  Both live in free page
; ends (;@SLACK), so nothing else moves.
;@SLACK EAHI
; MWCHK: HL = source, DE = destination (host), BC = bytes. Returns A =
; (STEP1+1) as R_MOVSW expects, or goes to MWSLOW instead.
MWCHK:  PUSH HL
        OR A
        SBC HL,DE               ; source - destination
        LD A,(STEP1+1)          ; 00h: DF = 0, FFh: DF = 1
        OR A
        JR Z,MWC1
        DEC HL                  ; DF = 1: overlap if source - dest = +1
        DEC HL
MWC1:   INC HL                  ; DF = 0: overlap if source - dest = -1
        LD A,H
        OR L
        POP HL
        LD A,(STEP1+1)
        RET NZ                  ; no overlap: R_MOVSW's LDIR / LDDR
        POP DE                  ; overlap: drop the return address
        JP MWSLOW
;@END
;@SLACK EALO
; MWSLOW: REP MOVSW one word at a time.  Stack: R_MOVSW's saved BC.
MWSLOW: PUSH IX                 ; NEXT, or RESTORE after a segment override
        LD IX,MWS1
MWS0:   JP O_MOVSW              ; one exact MOVSW; its JP (IX) comes back
MWS1:   LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JR NZ,MWS0
        POP IX
        POP BC                  ; the 8086 code pointer
        JP (IX)
;@END

R_STOSB:
        CALL CXNZ
        JR NZ,RSB1
        JP (IX)
RSB1:   PUSH BC
        PUSH HL
        CALL DSTPTR
        POP BC
        LD A,(R_AL)
        LD (HL),A
        DEC BC
        LD A,B
        OR C
        JR Z,RSB3
        LD D,H
        LD E,L
        LD A,(STEP1+1)
        RLA
        JR C,RSB2
        INC DE
        LDIR
        JR RSB3
RSB2:   DEC DE
        LDDR
RSB3:   POP BC
        LD DE,(R_CX)
        JR RADVDN

R_STOSW:
        CALL CXNZ
        JR NZ,RSW1
        JP (IX)
RSW1:   PUSH BC
        ADD HL,HL
        PUSH HL
        CALL DSTPTR
        POP BC
        LD DE,(R_AX)
        LD (HL),E
        INC HL
        LD (HL),D               ; HL = DI + 1
        DEC BC
        DEC BC
        LD A,B
        OR C
        JR Z,RSW3
        LD D,H
        LD E,L
        LD A,(STEP1+1)
        RLA
        JR C,RSW2
        INC DE                  ; DI+1 -> DI+2 ... from DI
        DEC HL
        LDIR
        JR RSW3
RSW2:   DEC DE                  ; DI+1 -> DI-1 ... downwards
        DEC DE
        LDDR
RSW3:   POP BC
        LD HL,(R_CX)
        ADD HL,HL
        EX DE,HL
        JR RADVDN

R_LODSB:
        CALL CXNZ
        JR NZ,RLB1
        JP (IX)
RLB1:   CALL SRCPTR
        LD A,(HL)
        LD (R_AL),A
        CALL NSI1
        LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JR NZ,RLB1
        JP (IX)

R_LODSW:
        CALL CXNZ
        JR NZ,RLW1
        JP (IX)
RLW1:   CALL SRCPTR
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (R_AX),DE
        CALL NSI2
        LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JR NZ,RLW1
        JP (IX)

; REPGO: after one CMPS / SCAS: CX -= 1; NZ = go on
REPGO:  LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        RET Z
        LD A,(REPT)
        LD L,A
        EX AF,AF'
        JR Z,REPGO1
        EX AF,AF'
        LD A,L                  ; ZF = 0: stop if REPE
        CPL
        AND 1
        RET
REPGO1: EX AF,AF'
        LD A,L                  ; ZF = 1: stop if REPNE
        AND 1
        RET

R_CMPSB:
        CALL CXNZ
        JR NZ,RCB1
        JP (IX)
RCB1:   CALL CMPSB1
        CALL REPGO
        JR NZ,RCB1
        JP (IX)
R_CMPSW:
        CALL CXNZ
        JR NZ,RCW1
        JP (IX)
RCW1:   CALL CMPSW1
        CALL REPGO
        JR NZ,RCW1
        JP (IX)
; REPNE SCASB: CPIR (CPDR if DF) passes over all but the last compare, 21 T
; a byte instead of about 300; RSC1 then does that compare, which leaves the
; flags, CX and DI as the 8086 does. Not if DI would wrap round the segment.
R_SCASB:
        CALL CXNZ
        JR NZ,RSC0
        JP (IX)
RSC0:   LD A,(REPT)             ; F2h: REPNE
        RRA
        JR C,RSC1
        DEC HL                  ; CX-1 bytes to pass over
        LD A,H
        OR L
        JR Z,RSC1
        PUSH BC
        LD B,H
        LD C,L
        LD HL,(R_DI)            ; C: DI would wrap
        LD A,(STEP1+1)
        RLA
        JR NC,RSCF
        SBC HL,BC               ; (CF=1: DI < CX, one too strict)
        JR RSCF1
RSCF:   ADD HL,BC
RSCF1:  JR C,RSCX
        CALL DSTPTR
        LD A,(STEP1+1)
        RLA
        LD A,(R_AL)
        JR C,RSCD
        CPIR
        JR RSCE
RSCD:   CPDR
RSCE:   JR NZ,RSCE1
        INC BC                  ; found: RSC1 compares it again
RSCE1:  INC BC                  ; CX for RSC1, DE = bytes passed over
        LD HL,(R_CX)
        LD (R_CX),BC
        OR A
        SBC HL,BC
        EX DE,HL
        CALL RNEG_DE
        LD HL,(R_DI)
        ADD HL,DE
        LD (R_DI),HL
RSCX:   POP BC
RSC1:   CALL SCASB1
        CALL REPGO
        JR NZ,RSC1
        JP (IX)
R_SCASW:
        CALL CXNZ
        JR NZ,RSCW1
        JP (IX)
RSCW1:  CALL SCASW1
        CALL REPGO
        JR NZ,RSCW1
        JP (IX)

; ============================================================ B0-BF
;@FOR R AL CL DL BL AH CH DH BH
O_MOVI_{R}:
        LD A,(BC)
        INC BC
        LD (R_{R}),A
        JP (IX)
;@END
;@FOR R AX CX DX BX SP BP SI DI
O_MOVI_{R}:
        LD A,(BC)
        LD (R_{R}),A
        INC BC
        LD A,(BC)
        LD (R_{R}+1),A
        INC BC
        JP (IX)
;@END

; ============================================================ C0-CF
O_RETN: CALL POPDE              ; RET imm16
        LD HL,(B_CS)
        ADD HL,DE
        PUSH HL
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        LD HL,(R_SP)
        ADD HL,DE
        LD (R_SP),HL
        POP BC
        JP (IX)

O_RET:  LD HL,(R_SP)            ; POPDE, inline
        LD A,(B_SS)
        ADD A,L
        LD E,A
        LD A,(B_SS+1)
        ADC A,H
        LD D,A
        INC HL
        INC HL
        LD (R_SP),HL
        EX DE,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(B_CS)
        ADD HL,DE
        LD B,H
        LD C,L
        JP (IX)

O_LES:  XOR A
        JR LXS
O_LDS:  LD A,6
LXS:    PUSH AF
        CALL MRW
        LD A,(HL)
        LD (DE),A
        INC HL
        INC E
        LD A,(HL)
        LD (DE),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        POP AF
        CALL SETSEG
        JP (IX)

O_MOVC6:
        LD A,(BC)
        INC BC
        CALL EAB
        LD A,(BC)
        INC BC
        LD (HL),A
        JP (IX)
O_MOVC7:
        LD A,(BC)
        INC BC
        CALL EAW
        LD A,(BC)
        INC BC
        LD (HL),A
        INC HL
        LD A,(BC)
        INC BC
        LD (HL),A
        JP (IX)

O_RETFN:                        ; RETF imm16
        CALL POPDE
        PUSH DE
        CALL POPDE
        PUSH DE
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        LD HL,(R_SP)
        ADD HL,DE
        LD (R_SP),HL
        POP HL
        POP DE
        JP FARJ

O_RETF: CALL POPDE
        PUSH DE
        CALL POPDE
        EX DE,HL
        POP DE
        JP FARJ

O_INT3: LD A,3
        JR DOINT
O_INTN: LD A,(BC)
        INC BC
; DOINT: interrupt A through the vector table
DOINT:  PUSH AF
        CALL GETF
        EX DE,HL
        CALL PUSHDE
        LD A,(FLAGHI)
        AND 0FCh                ; IF = TF = 0
        LD (FLAGHI),A
        LD DE,(R_CS)
        CALL PUSHDE
        CALL GETIP
        CALL PUSHDE
        POP AF
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        JP FARJ
O_INTO: EX AF,AF'
        JP PE,INTO1
        EX AF,AF'
        JP (IX)
INTO1:  EX AF,AF'
        LD A,4
        JR DOINT
DIVERR: XOR A
        JR DOINT

O_IRET: CALL POPDE
        PUSH DE
        CALL POPDE
        PUSH DE
        CALL POPDE
        EX DE,HL
        CALL SETF
        POP HL
        POP DE
        JP FARJ

; ============================================================ D0-DF
O_SHD0: LD D,1                  ; r/m8, 1
        JR SHB
O_SHD2: LD A,(R_CL)             ; r/m8, CL
        LD D,A
SHB:    LD A,(BC)
        INC BC
        PUSH DE
        PUSH AF
        CALL EAB
        POP AF
        POP DE
        INC D
        DEC D
        JR NZ,SHB1
        JP (IX)                 ; count 0: nothing changes
SHB1:   LD E,A
        LD A,D
        LD (SHCNT),A
        PUSH HL
        LD A,(HL)
        LD L,A
        LD (SHORIG),A
        EX AF,AF'
        PUSH AF
        EX AF,AF'
        LD A,E
        AND 38h
        ADD A,A
        OR 80h
        LD (SHB2+1),A
SHB2:   JP SHPG

O_SHD1: LD A,(BC)               ; r/m16, 1
        INC BC
        LD E,A
        AND 30h
        CP 20h
        LD A,E
        LD D,1
        JR NZ,SHWA              ; not SHL / SHR: the general path
        PUSH AF
        CALL EAW
        POP AF
        PUSH HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL                ; HL = value
        AND 08h
        JR NZ,SHR1W
        OR A                    ; SHL: S Z OF CF from ADC; AF = 0
        ADC HL,HL
        LD A,L
        PUSH AF
        POP DE
        RES 4,E
        JR SH1WE
SHR1W:  LD A,H                  ; SHR: OF = old MSB, S = 0
        AND 80h
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        LD E,A
        SRL H
        RR L
        JR NC,SHR1W1
        INC E                   ; CF
SHR1W1: LD A,H
        OR L
        JR NZ,SHR1W2
        SET 6,E
SHR1W2: LD D,L
SH1WE:  PUSH DE
        POP AF
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
O_SHD3: LD A,(R_CL)
        LD D,A
SHW:    LD A,(BC)
        INC BC
SHWA:   PUSH DE
        PUSH AF
        CALL EAW
        POP AF
        POP DE
        INC D
        DEC D
        JR NZ,SHW1
        JP (IX)
SHW1:   LD E,A
        LD A,D
        LD (SHCNT),A
        PUSH HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        LD (SHORIG),HL
        EX AF,AF'
        PUSH AF
        EX AF,AF'
        LD A,E
        AND 38h
        ADD A,A
        LD (SHW2+1),A
SHW2:   JP SHPG

; finishers. In: HL (L) = result, Z80 C = CF; stack: old AF', operand.
; rotates: CF and OF only
ROT16A: SBC A,A                 ; OF = MSB ^ CF
        AND 1
        LD E,A
        LD A,H
        RLCA
        XOR E
        AND 1
        RLCA
        RLCA
        OR E
        LD E,A
        JR ROTE16
ROT16B: SBC A,A                 ; OF = bit 15 ^ bit 14
        AND 1
        LD E,A
        LD A,H
        ADD A,A
        XOR H
        AND 80h
        RLCA
        RLCA
        RLCA
        OR E
        LD E,A
ROTE16: LD (TMP),HL
        POP HL
        LD A,L
        AND 0FAh
        OR E
        LD L,A
        PUSH HL
        POP AF
        EX AF,AF'
        LD DE,(TMP)
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)

; shifts: S Z PF from the result, AF = 0
SHL16F: SBC A,A
        AND 1
        LD E,A
        LD A,H
        RLCA
        XOR E
        AND 1
        RLCA
        RLCA
        OR E
        LD E,A
        JR SHE16
SHR16F: SBC A,A                 ; OF = original MSB if count 1, else 0
        AND 1
        LD E,A
        LD A,(SHCNT)
        DEC A
        JR NZ,SHE16
        LD A,(SHORIG+1)
        AND 80h
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        OR E
        LD E,A
        JR SHE16
SAR16F: SBC A,A                 ; OF = 0
        AND 1
        LD E,A
SHE16:  LD A,H
        AND 80h
        OR E
        LD E,A
        LD A,H
        OR L
        JR NZ,SHE161
        SET 6,E
SHE161: LD D,L
        POP AF
        PUSH DE
        POP AF
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)

ROT8A:  SBC A,A
        AND 1
        LD E,A
        LD A,L
        RLCA
        XOR E
        AND 1
        RLCA
        RLCA
        OR E
        LD E,A
        JR ROTE8
ROT8B:  SBC A,A
        AND 1
        LD E,A
        LD A,L
        ADD A,A
        XOR L
        AND 80h
        RLCA
        RLCA
        RLCA
        OR E
        LD E,A
ROTE8:  LD D,L
        POP HL
        LD A,L
        AND 0FAh
        OR E
        LD L,A
        PUSH HL
        POP AF
        EX AF,AF'
        POP HL
        LD (HL),D
        JP (IX)

SHL8F:  SBC A,A
        AND 1
        LD E,A
        LD A,L
        RLCA
        XOR E
        AND 1
        RLCA
        RLCA
        OR E
        LD E,A
        JR SHE8
SHR8F:  SBC A,A
        AND 1
        LD E,A
        LD A,(SHCNT)
        DEC A
        JR NZ,SHE8
        LD A,(SHORIG)
        AND 80h
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        OR E
        LD E,A
        JR SHE8
SAR8F:  SBC A,A
        AND 1
        LD E,A
SHE8:   LD A,L
        AND 80h
        OR E
        LD E,A
        LD A,L
        OR A
        JR NZ,SHE81
        SET 6,E
SHE81:  LD D,L
        POP AF
        PUSH DE
        POP AF
        EX AF,AF'
        POP HL
        LD (HL),D
        JP (IX)

O_AAM:  LD A,(BC)
        INC BC
        OR A
        JP Z,DIVERR
        LD E,A
        LD D,0
        LD (DIVISOR),DE
        LD A,(R_AL)
        LD D,A
        LD E,0
        LD HL,0
        LD A,8
        CALL DIVU
        LD A,E
        LD (R_AH),A
        LD A,L
        LD (R_AL),A
        JP SZP8

O_AAD:  LD A,(BC)
        INC BC
        LD E,A
        LD D,0
        LD A,(R_AH)
        LD L,A
        LD H,0
        CALL MULU16
        LD A,(R_AL)
        ADD A,L
        LD (R_AL),A
        LD L,A
        XOR A
        LD (R_AH),A
        LD A,L
        JP SZP8

O_SALC: EX AF,AF'
        PUSH AF
        SBC A,A
        LD (R_AL),A
        POP AF
        EX AF,AF'
        JP (IX)

O_XLAT: LD HL,(R_BX)
        LD A,(R_AL)
        ADD A,L
        LD L,A
        JR NC,XLAT1
        INC H
XLAT1:  LD DE,(EADS)
        ADD HL,DE
        LD A,(HL)
        LD (R_AL),A
        JP (IX)

O_ESC:  LD A,(BC)
        INC BC
        CALL EAW
        JP (IX)

; ============================================================ E0-EF
O_LOOPNZ:
        LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JR Z,LOOPX
        EX AF,AF'
        JP NZ,J_TAKE
        JP J_NOT
O_LOOPZ:
        LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JR Z,LOOPX
        EX AF,AF'
        JP Z,J_TAKE
        JP J_NOT
LOOPX:  INC BC
        JP (IX)
O_LOOP: LD HL,(R_CX)
        DEC HL
        LD (R_CX),HL
        LD A,H
        OR L
        JP NZ,JREL8
        INC BC
        JP (IX)
O_JCXZ: LD HL,(R_CX)
        LD A,H
        OR L
        JP Z,JREL8
        INC BC
        JP (IX)

O_INB:  INC BC                  ; IN AL,imm8: nothing there
O_INDXB:
        LD A,0FFh
        LD (R_AL),A
        JP (IX)
O_INW:  INC BC
O_INDXW:
        LD HL,0FFFFh
        LD (R_AX),HL
        JP (IX)
O_OUTI: INC BC                  ; OUT imm8,AL/AX: ignored
        JP (IX)

O_CALLN:
        LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        LD HL,(B_CS)            ; HL = return IP
        LD A,C
        SUB L
        LD L,A
        LD A,B
        SBC A,H
        LD H,A
        PUSH HL
        EX DE,HL
        ADD HL,BC
        LD B,H
        LD C,L
        POP DE
        JP PUSHX

O_JMPN: LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        LD H,B
        LD L,C
        ADD HL,DE
        LD B,H
        LD C,L
        JP (IX)

O_JMPF: LD A,(BC)
        LD E,A
        INC BC
        LD A,(BC)
        LD D,A
        INC BC
        LD A,(BC)
        LD L,A
        INC BC
        LD A,(BC)
        LD H,A
        JP FARJ

; ============================================================ F0-FF
O_CMC:  EX AF,AF'
        PUSH AF
        POP HL
        LD A,L
        XOR 1
        LD L,A
        JR FLSET
O_CLC:  EX AF,AF'
        PUSH AF
        POP HL
        RES 0,L
        JR FLSET
O_STC:  EX AF,AF'
        PUSH AF
        POP HL
        SET 0,L
FLSET:  PUSH HL
        POP AF
        EX AF,AF'
        JP (IX)
O_CLI:  LD HL,FLAGHI
        RES 1,(HL)
        JP (IX)
O_STI:  LD HL,FLAGHI
        SET 1,(HL)
        JP (IX)
O_CLD:  LD HL,FLAGHI
        RES 2,(HL)
        CALL SETSTEP
        JP (IX)
O_STD:  LD HL,FLAGHI
        SET 2,(HL)
        CALL SETSTEP
        JP (IX)

; F6: TEST NOT NEG MUL IMUL DIV IDIV, byte
O_GRP3B:
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAB
        POP AF
        AND 38h
        RRCA
        RRCA
        LD DE,G3BT
        JP JTAB
G3BT:   DW G3B_TEST, G3B_TEST, G3B_NOT, G3B_NEG, G3B_MUL, G3B_IMUL, G3B_DIV, G3B_IDIV

G3B_TEST:
        LD A,(BC)
        INC BC
        AND (HL)
        ADD A,0
        EX AF,AF'
        JP (IX)
G3B_NOT:
        LD A,(HL)
        CPL
        LD (HL),A
        JP (IX)
G3B_NEG:
        XOR A
        SUB (HL)
        LD (HL),A
        EX AF,AF'
        JP (IX)
G3B_MUL:
        LD E,(HL)
        LD D,0
        LD A,(R_AL)
        LD L,A
        LD H,0
        CALL MULU16
        LD (R_AX),HL
        LD A,H
        OR A
        CALL SETCO
        JP (IX)
G3B_IMUL:
        LD A,(HL)
        LD E,A
        ADD A,A
        SBC A,A
        LD D,A
        LD A,(R_AL)
        LD L,A
        ADD A,A
        SBC A,A
        LD H,A
        CALL MULU16
        LD (R_AX),HL
        LD A,L
        ADD A,A
        SBC A,A
        XOR H
        CALL SETCO
        JP (IX)
G3B_DIV:
        LD A,(HL)
        OR A
        JP Z,DIVERR
        LD E,A
        LD D,0
        LD (DIVISOR),DE
        LD A,(R_AH)
        CP E
        JP NC,DIVERR
        LD L,A
        LD H,0
        LD A,(R_AL)
        LD D,A
        LD E,0
        LD A,8
        CALL DIVU
        LD A,E
        LD (R_AL),A
        LD A,L
        LD (R_AH),A
        JP (IX)
G3B_IDIV:
        LD A,(HL)
        OR A
        JP Z,DIVERR
        LD L,A
        ADD A,A
        SBC A,A
        LD H,A
        LD (DIVISOR),HL
        LD DE,(R_AX)
        LD A,D
        ADD A,A
        SBC A,A
        LD H,A
        LD L,A
        CALL SDIV
        JP C,DIVERR
        LD A,D                  ; |q| must fit 7 bits (or be 80h if negative)
        OR A
        JP NZ,DIVERR
        LD A,(QNEG)
        RLA
        LD A,E
        JR C,G3BID1
        CP 80h
        JP NC,DIVERR
        JR G3BID2
G3BID1: CP 81h
        JP NC,DIVERR
        NEG
G3BID2: LD (R_AL),A
        LD A,(RNEG)
        RLA
        LD A,L
        JR NC,G3BID3
        NEG
G3BID3: LD (R_AH),A
        JP (IX)

; F7: word
O_GRP3W:
        LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        AND 38h
        RRCA
        RRCA
        LD DE,G3WT
        JP JTAB
G3WT:   DW G3W_TEST, G3W_TEST, G3W_NOT, G3W_NEG, G3W_MUL, G3W_IMUL, G3W_DIV, G3W_IDIV

G3W_TEST:
        LD A,(BC)
        INC BC
        AND (HL)
        LD E,A
        INC HL
        LD A,(BC)
        INC BC
        AND (HL)
        LD D,A
        JP LOGF16
G3W_NOT:
        LD A,(HL)
        CPL
        LD (HL),A
        INC HL
        LD A,(HL)
        CPL
        LD (HL),A
        JP (IX)
G3W_NEG:
        PUSH HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,0
        OR A
        SBC HL,DE
        LD A,L
        EX AF,AF'
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
G3W_MUL:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(R_AX)
        CALL MULU16
        LD (R_AX),HL
        LD (R_DX),DE
        LD A,D
        OR E
        CALL SETCO
        JP (IX)
G3W_IMUL:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (TMP),DE             ; b
        LD HL,(R_AX)
        LD (TMP2),HL            ; a
        CALL MULU16
        LD (R_AX),HL
        EX DE,HL                ; HL = high word, unsigned
        LD A,(TMP2+1)
        RLA
        JR NC,G3WIM1
        LD DE,(TMP)
        OR A
        SBC HL,DE
G3WIM1: LD A,(TMP+1)
        RLA
        JR NC,G3WIM2
        LD DE,(TMP2)
        OR A
        SBC HL,DE
G3WIM2: LD (R_DX),HL
        LD A,(R_AH)
        ADD A,A
        SBC A,A
        LD E,A
        XOR H
        LD D,A
        LD A,E
        XOR L
        OR D
        CALL SETCO
        JP (IX)
G3W_DIV:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,DIVERR
        LD (DIVISOR),DE
        LD HL,(R_DX)
        OR A
        SBC HL,DE
        JP NC,DIVERR            ; DX >= divisor: quotient too big
        ADD HL,DE
        LD DE,(R_AX)
        LD A,16
        CALL DIVU
        LD (R_AX),DE
        LD (R_DX),HL
        JP (IX)
G3W_IDIV:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,DIVERR
        LD (DIVISOR),DE
        LD HL,(R_DX)
        LD DE,(R_AX)
        CALL SDIV
        JP C,DIVERR
        LD A,(QNEG)
        RLA
        JR C,G3WID1
        BIT 7,D                 ; positive: |q| <= 7FFFh
        JP NZ,DIVERR
        JR G3WID2
G3WID1: LD A,D                  ; negative: |q| <= 8000h
        CP 80h
        JR C,G3WID0
        JP NZ,DIVERR
        LD A,E
        OR A
        JP NZ,DIVERR
G3WID0: XOR A
        SUB E
        LD E,A
        SBC A,A
        SUB D
        LD D,A
G3WID2: LD (R_AX),DE
        LD A,(RNEG)
        RLA
        JR NC,G3WID3
        XOR A
        SUB L
        LD L,A
        SBC A,A
        SUB H
        LD H,A
G3WID3: LD (R_DX),HL
        JP (IX)

; MULU16: HL x DE -> DE:HL (DE high)
MULU16: PUSH BC
        LD B,H
        LD C,L
        LD HL,0
        LD A,16
MULU1:  ADD HL,HL
        RL E
        RL D
        JR NC,MULU2
        ADD HL,BC
        JR NC,MULU2
        INC DE
MULU2:  DEC A
        JR NZ,MULU1
        POP BC
        RET

; DIVU: HL:DE / (DIVISOR), A = bits (16, or 8 with the dividend in HL:D)
; HL < divisor. Out: DE = quotient, HL = remainder.
DIVU:   PUSH BC
        LD BC,(DIVISOR)
DIVU1:  SLA E
        RL D
        ADC HL,HL
        JR C,DIVU2              ; 17 bits: certainly >= divisor
        SBC HL,BC
        JR NC,DIVU3
        ADD HL,BC
        JR DIVU4
DIVU2:  OR A
        SBC HL,BC
DIVU3:  INC E
DIVU4:  DEC A
        JR NZ,DIVU1
        POP BC
        RET

; SDIV: signed HL:DE / (DIVISOR) -> DE = |q|, HL = |r|, QNEG / RNEG bit 7
; = their signs; Z80 C = quotient over 16 bits.
SDIV:   LD A,H
        LD (RNEG),A
        RLA
        JR NC,SDIV1
        XOR A                   ; |dividend|
        SUB E
        LD E,A
        LD A,0
        SBC A,D
        LD D,A
        LD A,0
        SBC A,L
        LD L,A
        LD A,0
        SBC A,H
        LD H,A
SDIV1:  PUSH HL
        LD HL,(DIVISOR)
        LD A,(RNEG)
        XOR H
        LD (QNEG),A
        BIT 7,H
        JR Z,SDIV2
        XOR A
        SUB L
        LD L,A
        SBC A,A
        SUB H
        LD H,A
        LD (DIVISOR),HL
SDIV2:  EX (SP),HL              ; HL = |dividend| high, (SP) = |divisor|
        EX DE,HL
        EX (SP),HL              ; HL = |divisor|, (SP) = low
        EX DE,HL                ; DE = |divisor|, HL = high
        OR A
        SBC HL,DE
        ADD HL,DE
        POP DE
        CCF
        RET C
        LD A,16
        CALL DIVU
        OR A
        RET

; FE: INC / DEC r/m8
O_GRP4: LD A,(BC)
        INC BC
        PUSH AF
        CALL EAB
        POP AF
        AND 38h
        JR Z,G4INC
        CP 08h
        JP NZ,O_BAD
        EX AF,AF'
        DEC (HL)
        LD A,(HL)
        EX AF,AF'
        JP (IX)
G4INC:  EX AF,AF'
        INC (HL)
        LD A,(HL)
        EX AF,AF'
        JP (IX)

; FF: INC DEC CALL CALLF JMP JMPF PUSH
O_GRP5: LD A,(BC)
        INC BC
        PUSH AF
        CALL EAW
        POP AF
        AND 38h
        RRCA
        RRCA
        LD DE,G5T
        JP JTAB
G5T:    DW G5_INC, G5_DEC, G5_CALL, G5_CALLF, G5_JMP, G5_JMPF, G5_PUSH, G5_PUSH

G5_INC: PUSH HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        CALL INC16
G5ST:   EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP (IX)
G5_DEC: PUSH HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        CALL DEC16
        JR G5ST
G5_CALL:
        LD E,(HL)
        INC HL
        LD D,(HL)
        PUSH DE
        CALL GETIP
        CALL PUSHDE
        POP DE
        LD HL,(B_CS)
        ADD HL,DE
        LD B,H
        LD C,L
        JP (IX)
G5_CALLF:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        PUSH DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        PUSH DE
        LD DE,(R_CS)
        CALL PUSHDE
        CALL GETIP
        CALL PUSHDE
        POP HL
        POP DE
        JP FARJ
G5_JMP: LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(B_CS)
        ADD HL,DE
        LD B,H
        LD C,L
        JP (IX)
G5_JMPF:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        LD H,(HL)
        LD L,A
        JP FARJ
G5_PUSH:
        LD E,(HL)
        INC HL
        LD D,(HL)
        CALL PUSHDE
        JP (IX)

ENDCODE:
