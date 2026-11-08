; CPM.COM for MS-DOS 1.25 on the Timex FDD3000: CP/M 2.2 programs, run
; natively on the FDD3000's Z80, with their files on the DOS disk.
;
;       CPM program [arguments]
;
; The program is program.CPM, or program.COM if there is no .CPM (a CP/M
; .COM is Z80 code: keep CP/M programs as .CPM, so that DOS does not run
; one as 8086 code). The arguments become the CP/M command tail and the
; FCBs at 5CH and 6CH, as the CCP makes them.
;
; This part, in 8086 code, has BIOS trap 1CH copy the Z80 part
; (CPMZ80.ASM, here as CPMZ80.INC) to the Z80's memory above the BIOS,
; reads the program over it (STAGE) and works out the memory: the
; program gets 0100H up to P, a page that holds its BDOS and BIOS
; entries; above it DOS, COMMAND and CPM.COM wait while it runs. Trap
; 1CH again runs the Z80 part, which returns when the program ends.

PSIZE   EQU     200H            ; the P area (CPMZ80.ASM)

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

BEGIN:  JMP     START

BASE    DW      0               ; CS * 16: this program's linear address
DRIVE   DB      0               ; the current drive
STGOFF  DW      0               ; STAGE, rounded up to a paragraph

PFCB    DB      0,"           "
        DB      25 DUP (0)

; FCB 1, FCB 2 and the command tail, as the CP/M program gets them
PARMS   LABEL   BYTE
FCB1    DB      0,"           ",0,0,0,0
FCB2    DB      0,"           ",0,0,0,0
TAIL    DB      128 DUP (0)

USEMSG  DB      "Usage: CPM program [arguments]",13,10,"$"
NFMSG   DB      "Program not found",13,10,"$"
BIGMSG  DB      "Program too big",13,10,"$"
VERMSG  DB      "CPM.COM does not match Z86.SYS",13,10,"$"

START:  MOV     SP,OFFSET STKTOP
        CLD
        CMP     BYTE PTR DS:[5DH]," "
        JZ      USAGE
        MOV     AH,25           ; the current drive
        INT     33
        MOV     [DRIVE],AL
        MOV     AX,CS
        MOV     CL,4
        SHL     AX,CL
        MOV     [BASE],AX
        MOV     BP,AX           ; the Z80 part to its place (BIOS trap 1CH)
        ADD     BP,OFFSET Z80
        DB      0FH,1CH
        JNB     PROG
        MOV     DX,OFFSET VERMSG
        JMP     MSG
;
; the program: drive and name from DOS's FCB 1, .CPM or .COM
;
PROG:   MOV     SI,5CH
        MOV     DI,OFFSET PFCB
        MOV     CX,12
        REP     MOVSB
        CMP     BYTE PTR [PFCB+9]," "
        JNZ     OPEN
        MOV     BYTE PTR [PFCB+9],"C"
        MOV     BYTE PTR [PFCB+10],"P"
        MOV     BYTE PTR [PFCB+11],"M"
        CALL    OPENP
        JZ      CHKSZ
        MOV     BYTE PTR [PFCB+10],"O"
OPEN:   CALL    OPENP
        JZ      CHKSZ
NOTFND: MOV     DX,OFFSET NFMSG
        JMP     SHORT MSG
USAGE:  MOV     DX,OFFSET USEMSG
        JMP     SHORT MSG
TOOBIG: MOV     DX,OFFSET BIGMSG
MSG:    MOV     AH,9
        INT     33
        INT     32
;
; P = (TOP - PSIZE - SWLEN) AND 0FF00H, with SWLEN = BASE + STAGE and TOP
; the end of our memory (PSP offset 2; COMMAND's resident part is above
; it): the P area and the copy of 0000H-SWLEN fit below TOP. The program
; is read to STAGE, so it must end below P.
;
CHKSZ:  CMP     WORD PTR [PFCB+18],0
        JNZ     TOOBIG
        MOV     BX,OFFSET STAGE+15      ; STAGE on a paragraph: CPMZ80
        AND     BX,0FFF0H               ; exchanges in multiples of 8
        MOV     [STGOFF],BX
        ADD     BX,[BASE]
        MOV     DX,DS:[2]       ; the end of our memory: COMMAND is above
        MOV     CL,4
        SHL     DX,CL
        SUB     DX,PSIZE
        JB      TOOBIG
        SUB     DX,BX
        JB      TOOBIG
        AND     DX,0FF00H
        MOV     AX,DX
        SUB     AX,BX
        JB      TOOBIG
        MOV     CX,WORD PTR [PFCB+16]
        CMP     CX,AX
        JA      TOOBIG
        PUSH    BX
        PUSH    CX
        PUSH    DX
        MOV     DX,[STGOFF]
        MOV     AH,26           ; DTA
        INT     33
        MOV     WORD PTR [PFCB+14],1    ; record size 1: CX records = bytes
        MOV     WORD PTR [PFCB+33],0
        MOV     WORD PTR [PFCB+35],0
        MOV     DX,OFFSET PFCB
        MOV     AH,39           ; random block read
        INT     33
;
; the command tail: what follows the program's name, in upper case
;
        MOV     SI,81H
        MOV     CL,DS:[80H]
        XOR     CH,CH
SKIP:   JCXZ    TAILX
        MOV     AL,[SI]
        CMP     AL," "
        JZ      SKIP1
        CMP     AL,9
        JNZ     SKIPNM
SKIP1:  INC     SI
        DEC     CX
        JMP     SKIP
SKIPNM: JCXZ    TAILX
        MOV     AL,[SI]
        CMP     AL," "
        JZ      TAIL0
        CMP     AL,9
        JZ      TAIL0
        INC     SI
        DEC     CX
        JMP     SKIPNM
TAIL0:  MOV     [TAIL],CL
        MOV     DI,OFFSET TAIL+1
TCOPY:  LODSB
        CMP     AL,"a"
        JB      TC1
        CMP     AL,"z"
        JA      TC1
        SUB     AL,20H
TC1:    STOSB
        LOOP    TCOPY
TAILX:  MOV     SI,OFFSET TAIL+1        ; FCB 1 and 2 from it
        MOV     DI,OFFSET FCB1
        MOV     AX,2901H
        INT     33
        MOV     DI,OFFSET FCB2
        MOV     AX,2901H
        INT     33
;
; run it
;
        POP     DX              ; P
        POP     CX              ; bytes
        POP     BX              ; SWLEN
        MOV     SI,[BASE]
        ADD     SI,OFFSET PARMS
        XOR     BP,BP           ; trap 1CH, BP = 0: run it
        MOV     DI,[BASE]       ; DOS and our PSP
        ADD     DI,100H
        MOV     AL,[DRIVE]
        DB      0FH,1CH
        MOV     AH,13           ; disk reset
        INT     33
        INT     32

; OPENP: open PFCB, ZF=1 if found
OPENP:  MOV     DX,OFFSET PFCB
        MOV     AH,15
        INT     33
        OR      AL,AL
        RET

        DW      64 DUP (0)
STKTOP  LABEL   WORD

; the Z80 part: length, the BIOS addresses it was made for, the code.
; Once copied to the Z80's memory, the CP/M program is read over it.
Z80     LABEL   BYTE
STAGE   LABEL   BYTE
        INCLUDE CPMZ80.INC

CODE    ENDS
        END     BEGIN
