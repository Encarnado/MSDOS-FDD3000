; MODE.COM for MS-DOS 1.25 on the Timex FDD3000: the WD2123's serial ports.
;
;       MODE port[:] [baud][,[parity][,[data bits][,stop bits]]]
;       MODE [port[:]]
;
; port: PRN, LPT1 or COM1 for channel A (DOS's PRN), AUX or COM2 for
; channel B (DOS's AUX); COM1 and COM2 are INT 14H's ports 0 and 1.
; baud: 50 75 110 134.5 (or 134) 150 200 300 600 1200 1800 2400 3600 4800
; 7200 9600 19200, or the PC's 11 15 30 60 12 24 48 96 19. parity: N, O or
; E. data bits: 5 to 8. stop bits: 1, 1.5 or 2. A setting left out stays
; as it is. MODE with a port alone shows its settings, with no port both.
;
; The settings go to the chip through INT 14H's FDD3000 calls (BIOS.ASM's
; I14X, with I86.ASM's I14RD and SSET): F0H reads the mode byte and baud
; code the BIOS last set, F1H sets them. CP/M programs run by CPM.COM use the same settings.
; Every boot sets both channels to 1200 baud, no parity, 8 bits, 1.5 stop
; bits, as the FDD3000's CP/M does: put MODE lines in AUTOEXEC.BAT to
; have others.
;
; The mode byte is the 8251A's: bits 7-6 stop bits (01 1, 10 1.5, 11 2),
; 5 even parity, 4 parity on, 3-2 data bits - 5, 1-0 10 (x16 clock).

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

BEGIN:  JMP     START

CHAN    DW      0               ; INT 14H's port: 0 channel A, 1 channel B
MODEB   DB      0               ; the new settings
BAUDC   DB      0
NAMBUF  DB      "    "          ; the port's name, then a field
TOKEN   DB      "      "

; port names: 4 characters, then the channel
PORTS   DB      "PRN ",0,"LPT1",0,"COM1",0,"AUX ",1,"COM2",1
NPORTS  EQU     5

; the baud codes 0-15, as TMX CONFIGUR lists them
BAUDS   DB      "50    75    110   134.5 150   200   300   600   "
        DB      "1200  1800  2400  3600  4800  7200  9600  19200 "
; other names: 6 characters, then the code
ABAUDS  DB      "134   ",3,"11    ",2,"15    ",4,"30    ",6
        DB      "60    ",7,"12    ",8,"24    ",10,"48    ",12
        DB      "96    ",14,"19    ",15
NABAUDS EQU     10

PRNMSG  DB      "PRN: $"
AUXMSG  DB      "AUX: $"
BAUMSG  DB      " baud, $"
NOPMSG  DB      "no$"
ODDMSG  DB      "odd$"
EVNMSG  DB      "even$"
PARMSG  DB      " parity, $"
DATMSG  DB      " data bits, $"
STPMSG  DB      " stop bit$"
CRLF    DB      13,10,"$"
STOPS   DB      "?  1  1.52  "  ; mode bits 7-6, 3 characters each
USEMSG  DB      "Invalid parameter",13,10,13,10
        DB      "Usage: MODE port[:] [baud][,[N|O|E][,[5-8][,[1|1.5|2]]]]",13,10
        DB      "  port: PRN, LPT1 or COM1 (channel A), AUX or COM2 (channel B)",13,10
        DB      "  baud: 50 75 110 134.5 150 200 300 600 1200 1800 2400 3600",13,10
        DB      "        4800 7200 9600 19200",13,10,"$"

START:  CLD
        MOV     SI,81H          ; the command tail, in upper case, ending
        MOV     CL,DS:[80H]     ;   with a 0
        XOR     CH,CH
        MOV     DI,SI
UPPER:  JCXZ    UPX
        LODSB
        CMP     AL,"a"
        JB      UP1
        CMP     AL,"z"
        JA      UP1
        SUB     AL,20H
UP1:    STOSB
        LOOP    UPPER
UPX:    MOV     BYTE PTR [DI],0
        MOV     SI,81H
        CALL    BLANKS
        JNZ     PORT
        CALL    SHOW            ; no port: both
        INC     [CHAN]
        CALL    SHOW
        INT     32
;
; the port: a name of up to 4 letters and digits, then maybe a colon
;
PORT:   MOV     DI,OFFSET NAMBUF
        MOV     CX,4
        CALL    GETW
        JNZ     BAD
        MOV     BX,OFFSET PORTS
        MOV     DL,NPORTS
PORT1:  PUSH    SI
        MOV     SI,OFFSET NAMBUF
        MOV     DI,BX
        MOV     CX,4
        REPE    CMPSB
        POP     SI
        JZ      PORT2
        ADD     BX,5
        DEC     DL
        JNZ     PORT1
        JMP     SHORT BAD
PORT2:  MOV     AL,[BX+4]
        MOV     BYTE PTR [CHAN],AL
        CMP     BYTE PTR [SI],":"
        JNZ     PORT3
        INC     SI
PORT3:  CALL    BLANKS
        JNZ     SETS
        CALL    SHOW            ; a port alone: its settings
        INT     32
BAD:    MOV     DX,OFFSET USEMSG
        MOV     AH,9
        INT     33
        INT     32
;
; the settings: those of now, then each field given
;
SETS:   MOV     AH,0F0H
        MOV     DX,[CHAN]
        INT     20
        MOV     [MODEB],AL
        MOV     [BAUDC],AH
        CMP     BYTE PTR [SI],","       ; baud
        JZ      PAR
        MOV     DI,OFFSET TOKEN
        MOV     CX,6
        CALL    GETW
        JNZ     BAD
        MOV     BX,OFFSET BAUDS
        XOR     DL,DL
BAUD1:  CALL    SAME6
        JZ      BAUD3
        ADD     BX,6
        INC     DL
        CMP     DL,16
        JB      BAUD1
        MOV     BX,OFFSET ABAUDS
        MOV     DH,NABAUDS
BAUD2:  CALL    SAME6
        JZ      BAUD4
        ADD     BX,7
        DEC     DH
        JNZ     BAUD2
        JMP     BAD
BAUD4:  MOV     DL,[BX+6]
BAUD3:  MOV     [BAUDC],DL
PAR:    CALL    COMMA           ; parity
        JB      SETX
        JZ      DBITS
        MOV     AH,0            ; AH: the parity bits
        CMP     AL,"N"
        JZ      PAR1
        MOV     AH,10H
        CMP     AL,"O"
        JZ      PAR1
        MOV     AH,30H
        CMP     AL,"E"
        JNZ     BAD1
PAR1:   INC     SI
        AND     [MODEB],0CFH
        OR      [MODEB],AH
DBITS:  CALL    COMMA           ; data bits
        JB      SETX
        JZ      SBITS
        SUB     AL,"5"
        CMP     AL,4
        JNB     BAD1
        INC     SI
        SHL     AL,1
        SHL     AL,1
        AND     [MODEB],0F3H
        OR      [MODEB],AL
SBITS:  CALL    COMMA           ; stop bits
        JB      SETX
        JZ      SBEND
        MOV     AH,40H
        CMP     AL,"2"
        JNZ     SBIT1
        MOV     AH,0C0H
        JMP     SHORT SBIT2
SBIT1:  CMP     AL,"1"
        JNZ     BAD1
        CMP     BYTE PTR [SI+1],"."     ; "1.5"
        JNZ     SBIT2
        CMP     BYTE PTR [SI+2],"5"
        JNZ     BAD1
        ADD     SI,2
        MOV     AH,80H
SBIT2:  INC     SI
        AND     [MODEB],3FH
        OR      [MODEB],AH
SBEND:  CALL    BLANKS
        JZ      SETX
BAD1:   JMP     BAD
SETX:   MOV     AH,0F1H
        MOV     AL,[MODEB]
        MOV     CL,[BAUDC]
        MOV     DX,[CHAN]
        INT     20
        CALL    SHOW
        INT     32

; COMMA: after a field: CF=1 if the line ends there; otherwise past the
; comma, ZF=1 if the next field is empty too, AL = its first character
COMMA:  CALL    BLANKS
        STC
        JZ      CMX
        CMP     AL,","
        JNZ     BAD1
        INC     SI
        CALL    BLANKS
        CMP     AL,","
        JZ      CMX
        OR      AL,AL
CMX:   RET

; BLANKS: past spaces and tabs; AL = the next character, ZF=1 at the end
BLANKS: LODSB
        CMP     AL," "
        JZ      BLANKS
        CMP     AL,9
        JZ      BLANKS
        DEC     SI
        OR      AL,AL
        RET

; GETW: the letters, digits and points at SI to DI, padded with spaces to
; CX characters; ZF=0 if there are none or more than CX
GETW:   MOV     BX,CX
GETW1:  MOV     AL,[SI]
        CMP     AL,"."
        JZ      GETW2
        CMP     AL,"0"
        JB      GETW3
        CMP     AL,"9"
        JBE     GETW2
        CMP     AL,"A"
        JB      GETW3
        CMP     AL,"Z"
        JA      GETW3
GETW2:  JCXZ    GETWX
        STOSB
        INC     SI
        DEC     CX
        JMP     GETW1
GETW3:  CMP     CX,BX
        JZ      GETWX
        MOV     AL," "
        REP     STOSB
        CMP     AL,AL
        RET
GETWX:  OR      SP,SP           ; ZF=0
        RET

; SAME6: ZF=1 if TOKEN is the 6 characters at BX
SAME6:  PUSH    SI
        MOV     SI,OFFSET TOKEN
        MOV     DI,BX
        MOV     CX,6
        REPE    CMPSB
        POP     SI
        RET

; SHOW: CHAN's settings, as "PRN: 1200 baud, no parity, 8 data bits,
; 1.5 stop bits"
SHOW:   MOV     AH,0F0H
        MOV     DX,[CHAN]
        INT     20
        PUSH    AX
        MOV     DX,OFFSET PRNMSG
        CMP     [CHAN],0
        JZ      SHOW1
        MOV     DX,OFFSET AUXMSG
SHOW1:  MOV     AH,9
        INT     33
        POP     BX              ; BL mode byte, BH baud code
        PUSH    BX
        MOV     AL,6
        AND     BH,15
        MUL     BH
        ADD     AX,OFFSET BAUDS
        MOV     SI,AX
        MOV     CX,6
        CALL    PUTN
        MOV     DX,OFFSET BAUMSG
        CALL    PUTS
        POP     BX
        PUSH    BX
        MOV     DX,OFFSET NOPMSG
        TEST    BL,10H
        JZ      SHOW2
        MOV     DX,OFFSET ODDMSG
        TEST    BL,20H
        JZ      SHOW2
        MOV     DX,OFFSET EVNMSG
SHOW2:  CALL    PUTS
        MOV     DX,OFFSET PARMSG
        CALL    PUTS
        POP     BX
        PUSH    BX
        MOV     DL,BL
        SHR     DL,1
        SHR     DL,1
        AND     DL,3
        ADD     DL,"5"
        MOV     AH,2
        INT     33
        MOV     DX,OFFSET DATMSG
        CALL    PUTS
        POP     BX
        MOV     AL,BL
        MOV     CL,6
        SHR     AL,CL
        PUSH    AX
        MOV     AH,3
        MUL     AH
        ADD     AX,OFFSET STOPS
        MOV     SI,AX
        MOV     CX,3
        CALL    PUTN
        MOV     DX,OFFSET STPMSG
        CALL    PUTS
        POP     AX
        CMP     AL,1
        JZ      SHOW3
        MOV     DL,"s"
        MOV     AH,2
        INT     33
SHOW3:  MOV     DX,OFFSET CRLF
PUTS:   MOV     AH,9
        INT     33
        RET

; PUTN: up to CX characters at SI, to the first space
PUTN:   LODSB
        CMP     AL," "
        JZ      PUTN1
        MOV     DL,AL
        MOV     AH,2
        INT     33
        LOOP    PUTN
PUTN1:  RET

CODE    ENDS
        END     BEGIN
