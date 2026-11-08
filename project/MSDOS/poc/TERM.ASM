; TERM.COM for MS-DOS 1.25 on the Timex FDD3000: a serial terminal on one
; of the WD2123's channels, with the Timex terminal as screen and keyboard.
;
;       TERM [port[:] [baud][,[parity][,[data bits][,stop bits]]]] [/opts]
;
; port and settings as for MODE (default: AUX, as it is set now). Options:
;       /80     an 80-column terminal (/64, the default: 64 columns)
;       /52     the host sends VT52 codes (default VT100 / ANSI)
;       /X      XON / XOFF flow control (the default), /R RTS / CTS, /N none
;       /E      local echo: what is typed shows on the screen too
;       /C      a CR received also goes to the next line (an implicit LF)
;
; Ctrl-A brings up the menu on the bottom line: Q quit, L log to a file
; (on / off), E local echo (on / off), C implicit LF (on / off), R
; receive a file by XMODEM, S send one, B send a break, Ctrl-A send a
; Ctrl-A; any other key goes back.
;
; The work is done by the Z80 part (TERMZ80.ASM, here as TERMZ80.INC),
; which BIOS trap 1CH copies over the BIOS's COLD and then calls: the
; session itself, the screen, and the channel's bytes for XMODEM. This
; part reads the command line, keeps the files and runs the menu and the
; XMODEM protocol. The buffers the Z80 part uses are here, over the copy
; of it, once it is loaded.

ROWS    EQU     24
RINGSZ  EQU     2048
LOGSZ   EQU     8192
MENUK   EQU     1               ; Ctrl-A

SOH     EQU     1
EOT     EQU     4
ACK     EQU     6
NAK     EQU     15H
CAN     EQU     18H

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

BEGIN:  JMP     START

BASE    DW      0               ; CS * 16: this program's linear address
CHAN    DW      1               ; INT 14H's port: 0 channel A, 1 channel B
MODEB   DB      0               ; the channel's settings
BAUDC   DB      0
NAMBUF  DB      "    "          ; the port's name, then a field
TOKEN   DB      "      "

; the parameter block for the Z80 part's INIT (TERMZ80.ASM)
PBLK    LABEL   BYTE
PCTL    DB      0
PCOLS   DB      64
PROWS   DB      ROWS
PFLAGS  DB      2               ; 1 VT52, 2 XON / XOFF, 4 RTS / CTS, 8 echo,
                                ;   10h CR as CR LF
PMENU   DB      MENUK
PSCR    DW      0
PRING   DW      0
PLOG    DW      0
PLOGSZ  DW      LOGSZ

LOGON   DB      0               ; 1: logging to LFCB
LOGN    DW      0               ; bytes in the log buffer
LOST    DW      0               ; bytes the Z80 part could not take

; XMODEM
BLK     DB      0               ; the block number expected / sent
CRCM    DB      0               ; 1: CRC-16, 0: checksum
TRIES   DB      0
GOT     DB      0               ; 1: a block has come
XREPLY  DB      0               ; what to send before the next byte
XLEN    DW      0
XCNT    DW      0               ; bytes in the block being sent
XMSG    DW      0               ; Receiving: / Sending:
NBYTES  DW      0,0             ; bytes moved
ANSB    DB      0
EOTB    DB      EOT
CANS    DB      CAN,CAN,CAN
MENUKB  DB      MENUK

LFCB    DB      0,"           "
        DB      25 DUP (0)
XFCB    DB      0,"           "
        DB      25 DUP (0)
LINE    DB      32 DUP (0)

PORTS   DB      "PRN ",0,"LPT1",0,"COM1",0,"AUX ",1,"COM2",1
NPORTS  EQU     5
BAUDS   DB      "50    75    110   134.5 150   200   300   600   "
        DB      "1200  1800  2400  3600  4800  7200  9600  19200 "
ABAUDS  DB      "134   ",3,"11    ",2,"15    ",4,"30    ",6
        DB      "60    ",7,"12    ",8,"24    ",10,"48    ",12
        DB      "96    ",14,"19    ",15
NABAUDS EQU     10

USEMSG  DB      "Invalid parameter",13,10,13,10
        DB      "Usage: TERM [port[:] [baud][,[N|O|E][,[5-8][,[1|1.5|2]]]]]",13,10
        DB      "            [/80|/64] [/52] [/X|/R|/N] [/E] [/C]",13,10
        DB      "  port: PRN, LPT1 or COM1 (channel A), AUX or COM2 (channel B)",13,10
        DB      "  /80 80 columns, /52 VT52 host, /X XON/XOFF, /R RTS/CTS, /N none",13,10
        DB      "  /E local echo, /C LF after each CR received, /64 64 columns",13,10
        DB      "  Ctrl-A: the menu$"
CRLF    DB      13,10,"$"
VERMSG  DB      "TERM.COM does not match Z86.SYS",13,10,"$"
HELLO   DB      "TERM: Ctrl-A for the menu"
HELLOE  LABEL   BYTE

BOTL    DB      27,"Y",32+ROWS-1,32,27,"L$"     ; the bottom line, inverse
; (what goes there stays under 63 characters: the last column of the
; bottom line would scroll the terminal)
BOTE    DB      27,"M",27,"K$"                  ; normal, the rest blank
MENU1   DB      "Q quit L log$"
MENUE   DB      " E echo$"
MENUC   DB      " C lf$"
MENUON  DB      "+$"                    ; on
MENUOF  DB      "-$"                    ; off
MENU2   DB      " R rcv S snd B brk ^A ^A$"
LOSTM   DB      " lost $"
LOGASK  DB      "Log to file: $"
RCVASK  DB      "Receive (XMODEM) as file: $"
SNDASK  DB      "Send (XMODEM) file: $"
CRMSG   DB      "Cannot create the file$"
NFMSG   DB      "File not found$"
FULLM   DB      "Disk full: log stopped$"
XRMSG   DB      "Receiving: $"
XSMSG   DB      "Sending: $"
BYTESM  DB      " bytes$"
DONEM   DB      " bytes: done$"
CANM    DB      "Cancelled$"
RCANM   DB      "Cancelled by the other side$"
FAILM   DB      "Transfer failed$"
KEYM    DB      " - a key$"
BSSTR   DB      8," ",8,"$"

START:  MOV     SP,OFFSET STKTOP
        CLD
        MOV     AX,CS
        MOV     CL,4
        SHL     AX,CL
        MOV     [BASE],AX
;
; the command line, in upper case, ending with a 0; the options first
;
        MOV     SI,81H
        MOV     CL,DS:[80H]
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
OPT:    LODSB
        OR      AL,AL
        JZ      OPTX
        CMP     AL,"/"
        JNZ     OPT
        MOV     BYTE PTR [SI-1]," "
        MOV     AX,[SI]
        MOV     BL,2            ; BL: the option's length
        CMP     AX,"0"*256+"8"  ; "80"
        JZ      OPT80
        CMP     AX,"4"*256+"6"  ; "64"
        JZ      OPT64
        CMP     AX,"2"*256+"5"  ; "52"
        JZ      OPT52
        MOV     BL,1
        MOV     AH,2
        CMP     AL,"X"
        JZ      OPTF
        MOV     AH,4
        CMP     AL,"R"
        JZ      OPTF
        MOV     AH,0
        CMP     AL,"N"
        JZ      OPTF
        MOV     AH,8
        CMP     AL,"E"
        JZ      OPTM
        MOV     AH,10H
        CMP     AL,"C"
        JNZ     BADO
OPTM:   OR      [PFLAGS],AH
        JMP     SHORT OPTB
BADO:   JMP     BAD
OPT80:  MOV     [PCOLS],80
        JMP     SHORT OPTB
OPT64:  MOV     [PCOLS],64
        JMP     SHORT OPTB
OPT52:  OR      [PFLAGS],1
        JMP     SHORT OPTB
OPTF:   AND     [PFLAGS],19H    ; VT52, echo and LF stay
        OR      [PFLAGS],AH
OPTB:   MOV     BYTE PTR [SI]," "       ; the option blanked out
        INC     SI
        DEC     BL
        JNZ     OPTB
        JMP     OPT
OPTX:   MOV     SI,81H
        CALL    BLANKS
        JNZ     PORT0
        JMP     LOAD
PORT0:
;
; the port, then the settings (as MODE)
;
        MOV     DI,OFFSET NAMBUF
        MOV     CX,4
        CALL    GETW
        JNZ     BAD0
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
BAD0:   JMP     BAD
PORT2:  MOV     AL,[BX+4]
        MOV     BYTE PTR [CHAN],AL
        CMP     BYTE PTR [SI],":"
        JNZ     PORT3
        INC     SI
PORT3:  CALL    BLANKS
        JNZ     PORT4
        JMP     LOAD
PORT4:
        MOV     AH,0F0H         ; the settings of now
        MOV     DX,[CHAN]
        INT     20
        MOV     [MODEB],AL
        MOV     [BAUDC],AH
        CMP     BYTE PTR [SI],","       ; baud
        JZ      PAR
        MOV     DI,OFFSET TOKEN
        MOV     CX,6
        CALL    GETW
        JNZ     BAD0
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
        MOV     AH,0
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
;
; the Z80 part to its place (BIOS trap 1CH), the buffers over its copy
;
LOAD:   MOV     BP,[BASE]
        ADD     BP,OFFSET Z80IMG
        DB      0FH,1CH
        JNB     LOAD1
        MOV     DX,OFFSET VERMSG
        MOV     AH,9
        INT     33
        INT     32
LOAD1:  MOV     AL,81H
        CMP     [CHAN],0
        JZ      LOAD2
        MOV     AL,41H
LOAD2:  MOV     [PCTL],AL
        MOV     AX,[BASE]
        ADD     AX,OFFSET SCRBUF
        MOV     [PSCR],AX
        MOV     AX,[BASE]
        ADD     AX,OFFSET RINGBUF
        MOV     [PRING],AX
        MOV     AX,[BASE]
        ADD     AX,OFFSET LOGBUF
        MOV     [PLOG],AX
        MOV     SI,OFFSET PBLK
        ADD     SI,[BASE]
        MOV     AH,0            ; INIT: the screen cleared
        CALL    Z80
        MOV     SI,OFFSET HELLO ; a line on the host's screen till it
        MOV     DI,OFFSET SCRBUF        ;   writes there
        MOV     CX,OFFSET HELLOE-OFFSET HELLO
        REP     MOVSB
        MOV     CL,0
        MOV     AH,2            ; DRAW
        CALL    Z80
;
; the session; back here for the menu and a full log buffer
;
SESS:   MOV     AH,1
        CALL    Z80
        MOV     [LOGN],CX
        MOV     [LOST],DX
        CMP     AL,2
        JNZ     SESS1
        CALL    LOGWR           ; the log buffer to the file
        JMP     SESS
SESS1:  CALL    MENU
        MOV     CL,ROWS-1       ; the bottom line again
        MOV     AH,2
        CALL    Z80
        JMP     SESS

; Z80: the Z80 part's function AH (BIOS trap 1CH, BP = 0)
Z80:    XOR     BP,BP
        DB      0FH,1CH
        RET

BAD:    MOV     DX,OFFSET USEMSG
        MOV     AH,9
        INT     33
        MOV     DX,OFFSET CRLF
        MOV     AH,9
        INT     33
        INT     32

; ---------------------------------------------------------------- the menu
MENU:   CALL    BOTTOM
        MOV     DX,OFFSET MENU1
        CALL    PUTS
        MOV     AL,[LOGON]
        CALL    ONOFF
        MOV     DX,OFFSET MENUE
        CALL    PUTS
        MOV     AL,[PFLAGS]
        AND     AL,8
        CALL    ONOFF
        MOV     DX,OFFSET MENUC
        CALL    PUTS
        MOV     AL,[PFLAGS]
        AND     AL,10H
        CALL    ONOFF
        MOV     DX,OFFSET MENU2
        CALL    PUTS
        MOV     AX,[LOST]
        OR      AX,AX
        JZ      MENU1A
        MOV     DX,OFFSET LOSTM
        CALL    PUTS
        CALL    PUTNUM
MENU1A: CALL    BOTEND
        MOV     AH,7
        INT     33
        CMP     AL,"a"
        JB      MENU2A
        SUB     AL,20H
MENU2A: CMP     AL,"Q"
        JZ      QUIT
        CMP     AL,"L"
        JNZ     MENU3
        JMP     LOGSW
MENU3:  CMP     AL,"R"
        JNZ     MENU4
        JMP     XRECV
MENU4:  CMP     AL,"S"
        JNZ     MENU5
        JMP     XSEND
MENU5:  CMP     AL,"B"
        JNZ     MENU8
        MOV     AH,5
        JMP     Z80
MENU8:  MOV     AH,8            ; E local echo, C implicit LF: on / off
        CMP     AL,"E"
        JZ      MENU9
        MOV     AH,10H
        CMP     AL,"C"
        JNZ     MENU6
MENU9:  XOR     [PFLAGS],AH
        MOV     DL,[PFLAGS]
        MOV     AH,9            ; MODE: flags 8 and 10h
        JMP     Z80
MENU6:  CMP     AL,MENUK
        JNZ     MENU7
        MOV     SI,OFFSET MENUKB
        MOV     CX,1
        JMP     SEND
MENU7:  RET

; ONOFF: + if AL <> 0, else -
ONOFF:  MOV     DX,OFFSET MENUON
        OR      AL,AL
        JNZ     ONOFF1
        MOV     DX,OFFSET MENUOF
ONOFF1: JMP     PUTS

QUIT:   CMP     [LOGON],0
        JZ      QUIT1
        CALL    LOGOFF
QUIT1:  XOR     CX,CX           ; the host let go (SEND of nothing:
        CALL    SEND            ;   the Z80 part's ENSURE)
        CALL    BOTTOM          ; DOS goes on from the bottom line
        CALL    BOTEND
        MOV     DL,13
        MOV     AH,2
        INT     33
        INT     32

; ---------------------------------------------------------------- the log
LOGSW:  CMP     [LOGON],0
        JNZ     LOGOFF
        MOV     DX,OFFSET LOGASK
        MOV     DI,OFFSET LFCB
        CALL    ASKF
        JB      LOGX
        MOV     DX,OFFSET LFCB
        MOV     AH,22           ; create
        INT     33
        OR      AL,AL
        JZ      LOGON1
        MOV     DX,OFFSET CRMSG
        JMP     SHOW
LOGON1: MOV     BX,OFFSET LFCB
        CALL    RECSZ1
        MOV     [LOGON],1
        MOV     DX,1
LOGSET: XOR     CX,CX
        MOV     [LOGN],CX
        MOV     AH,6
        JMP     Z80
LOGOFF: CALL    LOGWR
        MOV     DX,OFFSET LFCB
        MOV     AH,16           ; close
        INT     33
        MOV     [LOGON],0
        XOR     DX,DX
        JMP     LOGSET
LOGX:   RET

; LOGWR: the log buffer to the file (random block write, records of 1)
LOGWR:  MOV     CX,[LOGN]
        JCXZ    LOGW1
        MOV     DX,OFFSET LOGBUF
        MOV     AH,26           ; DTA
        INT     33
        MOV     DX,OFFSET LFCB
        MOV     AH,40
        INT     33
        OR      AL,AL
        JZ      LOGW1
        MOV     DX,OFFSET LFCB  ; disk full: the log stops
        MOV     AH,16
        INT     33
        MOV     [LOGON],0
        XOR     DX,DX
        CALL    LOGSET
        MOV     DX,OFFSET FULLM
        CALL    SHOW
        MOV     CL,ROWS-1
        MOV     AH,2
        JMP     Z80
LOGW1:  MOV     DX,1
        JMP     LOGSET

; ---------------------------------------------------------------- XMODEM
; XRECV: a file from the host: CRC-16 if the sender takes 'C', else
; checksums. The answer to each block goes out with the wait for the next.
XRECV:  MOV     DX,OFFSET RCVASK
        MOV     DI,OFFSET XFCB
        CALL    ASKF
        JB      XRX
        MOV     DX,OFFSET XFCB
        MOV     AH,22
        INT     33
        OR      AL,AL
        JZ      XR0
        MOV     DX,OFFSET CRMSG
        JMP     SHOW
XRX:    RET
XR0:    MOV     BX,OFFSET XFCB
        CALL    RECSZ1
        MOV     DX,OFFSET XRMSG
        CALL    XSTART
        MOV     [BLK],1
        MOV     [CRCM],1
        MOV     [GOT],0
        MOV     [XREPLY],"C"
XR1:    MOV     BL,[XREPLY]     ; the answer, then a block, its first
        MOV     BH,BL           ;   byte within 3 s, the others 1 s apart
        MOV     CX,132
        ADD     CL,[CRCM]
        MOV     [XLEN],CX
        MOV     DX,300
        CALL    XGET
        JB      XRUSR
        JCXZ    XRTO
        MOV     AL,[XBUF]
        CMP     AL,SOH
        JZ      XRSOH
        CMP     AL,EOT
        JNZ     XR2
        CMP     CX,1            ; an EOT alone, not a block's first byte
        JNZ     XR4             ;   hit by noise
        JMP     XREOT
XR2:    CMP     AL,CAN
        JNZ     XR3
        CMP     CX,1            ; two CANs, as YMODEM's graceful abort
        JNA     XR3
        CMP     BYTE PTR [XBUF+1],CAN
        JNZ     XR4
        JMP     XRCAN
XR3:    MOV     [XREPLY],0      ; noise: wait on
        JMP     XR1
XR4:    JMP     XRBAD
XRUSR:  JMP     XUSER
XRTO:   INC     [TRIES]
        CMP     [TRIES],10
        JA      XRFL
        CMP     [GOT],0         ; nothing yet: 'C' three times, then
        JNZ     XRNAK           ;   checksums (NAK)
        CMP     [TRIES],3
        JB      XRC
        MOV     [CRCM],0
XRNAK:  MOV     [XREPLY],NAK
        JMP     XR1
XRC:    MOV     [XREPLY],"C"
        JMP     XR1
XRFL:   JMP     XFAIL
XRSOH:  CMP     CX,[XLEN]
        JNZ     XRBAD
        MOV     AX,WORD PTR [XBUF+1]
        NOT     AH
        CMP     AL,AH
        JNZ     XRBAD
        CALL    XCHECK
        CMP     [CRCM],0
        JZ      XRS1
        CMP     DH,[XBUF+131]
        JNZ     XRBAD
        CMP     DL,[XBUF+132]
        JNZ     XRBAD
        JMP     SHORT XRS2
XRS1:   CMP     AL,[XBUF+131]
        JNZ     XRBAD
XRS2:   MOV     [GOT],1
        MOV     [TRIES],0
        MOV     AL,[XBUF+1]
        CMP     AL,[BLK]
        JZ      XRS3
        INC     AL              ; the last block again: its ACK was lost
        CMP     AL,[BLK]
        JZ      XRACK
        JMP     XFAIL
XRS3:   MOV     DX,OFFSET XBUF+3
        MOV     AH,26
        INT     33
        MOV     CX,128
        MOV     DX,OFFSET XFCB
        MOV     AH,40
        INT     33
        OR      AL,AL
        JZ      XRS4
        JMP     XFAIL
XRS4:   INC     [BLK]
        MOV     AX,128
        CALL    XPROG
XRACK:  MOV     [XREPLY],ACK
        JMP     XR1
XRBAD:  CALL    PURGE           ; when the line is quiet: NAK
        INC     [TRIES]
        CMP     [TRIES],10
        JNA     XRBAD1
        JMP     XFAIL
XRBAD1:
        JMP     XRNAK
XREOT:  MOV     BX,ACK*256+ACK
        XOR     CX,CX
        CALL    XGET
        JMP     XDONE
XRCAN:  MOV     DX,OFFSET RCANM
        JMP     XEND

; XSEND: a file to the host
XSEND:  MOV     DX,OFFSET SNDASK
        MOV     DI,OFFSET XFCB
        CALL    ASKF
        JB      XSX
        MOV     DX,OFFSET XFCB
        MOV     AH,15           ; open
        INT     33
        OR      AL,AL
        JZ      XS0
        MOV     DX,OFFSET NFMSG
        JMP     SHOW
XSX:    RET
XS0:    MOV     BX,OFFSET XFCB
        CALL    RECSZ1
        MOV     DX,OFFSET XSMSG
        CALL    XSTART
XS1:    XOR     BX,BX           ; the receiver's 'C' or NAK, a minute
        MOV     CX,1
        MOV     DX,6000
        CALL    XGET
        JB      XSUSR
        JCXZ    XSFL
        MOV     AL,[XBUF]
        MOV     [CRCM],1
        CMP     AL,"C"
        JZ      XS2
        MOV     [CRCM],0
        CMP     AL,NAK
        JZ      XS2
        CMP     AL,CAN
        JNZ     XS1
        JMP     XRCAN
XSUSR:  JMP     XUSER
XSFL:   JMP     XFAIL
XS2:    MOV     [BLK],1
XS3:    MOV     DX,OFFSET XBUF+3        ; the next 128 bytes
        MOV     AH,26
        INT     33
        MOV     CX,128
        MOV     DX,OFFSET XFCB
        MOV     AH,39           ; random block read
        INT     33
        OR      CX,CX
        JNZ     XS31
        JMP     XSEOT
XS31:   MOV     [XCNT],CX
        MOV     DI,OFFSET XBUF+3
        ADD     DI,CX
        NEG     CX
        ADD     CX,128
        MOV     AL,1AH          ; the last block filled with ^Z
        REP     STOSB
        MOV     [XBUF],SOH
        MOV     AL,[BLK]
        MOV     [XBUF+1],AL
        NOT     AL
        MOV     [XBUF+2],AL
        CALL    XCHECK
        MOV     [XBUF+131],AL
        MOV     [XLEN],132
        CMP     [CRCM],0
        JZ      XS4
        MOV     [XBUF+131],DH
        MOV     [XBUF+132],DL
        MOV     [XLEN],133
XS4:    MOV     [TRIES],0
XS5:    MOV     SI,OFFSET XBUF
        MOV     CX,[XLEN]
        CALL    SEND
        OR      AL,AL
        JNZ     XSFL1
        CALL    XANS
        JB      XSUSR
        CMP     AL,ACK
        JZ      XS6
        CMP     AL,CAN
        JNZ     XS51
        JMP     XRCAN
XS51:   CALL    PURGE           ; not ACK: the line quiet first, so no
        INC     [TRIES]         ;   late answer is taken for the next
        CMP     [TRIES],10
        JB      XS5
XSFL1:  JMP     XFAIL
XS6:    INC     [BLK]
        MOV     AX,[XCNT]
        CALL    XPROG
        JMP     XS3
XSEOT:  MOV     [TRIES],0
XSE1:   MOV     SI,OFFSET EOTB
        MOV     CX,1
        CALL    SEND
        CALL    XANS
        JNB     XSE11
        JMP     XUSER
XSE11:  CMP     AL,ACK
        JZ      XSE2
        INC     [TRIES]
        CMP     [TRIES],10
        JB      XSE1
        JMP     XFAIL
XSE2:   JMP     XDONE

; XSTART: the bottom line for a transfer, DX = what it is
XSTART: MOV     [XMSG],DX
        PUSH    DX
        CALL    BOTTOM
        POP     DX
        CALL    PUTS
        CALL    BOTEND
        MOV     WORD PTR [NBYTES],0
        MOV     WORD PTR [NBYTES+2],0
        MOV     [TRIES],0
        MOV     AH,8            ; FLUSH what came before
        JMP     Z80

; XPROG: AX more bytes moved; their count on the bottom line
XPROG:  ADD     WORD PTR [NBYTES],AX
        ADC     WORD PTR [NBYTES+2],0
        CALL    BOTTOM
        MOV     DX,[XMSG]
        CALL    PUTNB
        MOV     DX,OFFSET BYTESM
        CALL    PUTS
        JMP     BOTEND

; XANS: AL = the answer to what was sent (0 if none in 10 s); CF=1 a key
XANS:   XOR     BX,BX
        MOV     CX,1
        MOV     DX,1000
        MOV     DI,OFFSET ANSB
        CALL    XGETDI
        JB      XANS1
        MOV     AL,0
        JCXZ    XANS1
        MOV     AL,[ANSB]
XANS1:  RET

; XGET / XGETDI: send BL if BH <> 0, then up to CX bytes to XBUF / DI,
; DX x 10 ms each; CX = bytes received, CF=1 if a key was pressed
XGET:   MOV     DI,OFFSET XBUF
XGETDI: ADD     DI,[BASE]
        MOV     AH,3
        CALL    Z80
        CMP     AL,1
        CMC
        RET

; XCHECK: the block's data: DX = CRC-16, AL = checksum
XCHECK: MOV     SI,OFFSET XBUF+3
        MOV     CX,128
        ADD     SI,[BASE]
        MOV     AH,7
        JMP     Z80

; PURGE: wait till nothing comes for 0.3 s (not into XBUF: XSEND sends
; it again)
PURGE:  MOV     CX,1
        MOV     DX,30
        XOR     BX,BX
        MOV     DI,OFFSET ANSB
        CALL    XGETDI
        JCXZ    PURGE1
        JMP     PURGE
PURGE1: RET

; SEND: CX bytes at SI to the channel; AL = 1 if CTS stayed off
SEND:   ADD     SI,[BASE]
        MOV     AH,4
        JMP     Z80

XDONE:  MOV     AH,10           ; HOLD: the host stopped till SESS
        CALL    Z80
        MOV     DX,OFFSET XFCB
        MOV     AH,16
        INT     33
        CALL    BOTTOM
        MOV     DX,[XMSG]
        CALL    PUTNB
        MOV     DX,OFFSET DONEM
        JMP     SHOW1
XUSER:  MOV     DX,OFFSET CANM
        JMP     SHORT XCAN
XFAIL:  MOV     DX,OFFSET FAILM
XCAN:   PUSH    DX
        MOV     SI,OFFSET CANS
        MOV     CX,3
        CALL    SEND
        POP     DX
XEND:   PUSH    DX
        MOV     AH,10           ; HOLD
        CALL    Z80
        MOV     DX,OFFSET XFCB
        MOV     AH,16
        INT     33
        POP     DX
;
; SHOW: the message DX on the bottom line until a key is pressed
;
SHOW:   PUSH    DX
        CALL    BOTTOM
        POP     DX
SHOW1:  CALL    PUTS
        MOV     DX,OFFSET KEYM
        CALL    PUTS
        CALL    BOTEND
        MOV     AH,7
        INT     33
        RET

; ---------------------------------------------------------------- helpers
; ASKF: DX = the question; a file name from the keyboard into the FCB at
; DI. CF=1: none given (or ESC)
ASKF:   PUSH    DI
        PUSH    DX
        CALL    BOTTOM
        POP     DX
        CALL    PUTS
        CALL    BOTEND
        XOR     BX,BX
ASK1:   MOV     AH,7
        INT     33
        CMP     AL,13
        JZ      ASK4
        CMP     AL,27
        JZ      ASKNO
        CMP     AL,8
        JZ      ASK3
        CMP     AL,7FH
        JZ      ASK3
        CMP     AL," "
        JB      ASK1
        CMP     BX,28
        JNB     ASK1
        MOV     LINE[BX],AL
        INC     BX
        MOV     DL,AL
        MOV     AH,2
        INT     33
        JMP     ASK1
ASK3:   OR      BX,BX
        JZ      ASK1
        DEC     BX
        MOV     DX,OFFSET BSSTR
        CALL    PUTS
        JMP     ASK1
ASK4:   MOV     LINE[BX],13
        POP     DI
        MOV     SI,OFFSET LINE
        MOV     AX,2900H        ; parse the name
        INT     33
        CMP     AL,0FFH
        JZ      ASKNO1
        CMP     BYTE PTR [DI+1]," "
        JZ      ASKNO1
        CLC
        RET
ASKNO:  POP     DI
ASKNO1: STC
        RET

; RECSZ1: the FCB at BX for random block I/O, records of 1 byte, from 0
RECSZ1: MOV     WORD PTR [BX+14],1
        MOV     WORD PTR [BX+33],0
        MOV     WORD PTR [BX+35],0
        RET

; BOTTOM / BOTEND: to the bottom line, inverse / back to normal
BOTTOM: MOV     DX,OFFSET BOTL
        JMP     SHORT PUTS
BOTEND: MOV     DX,OFFSET BOTE
PUTS:   MOV     AH,9
        INT     33
        RET

; PUTNB: DX, then NBYTES in decimal (up to 655359)
PUTNB:  CALL    PUTS
        MOV     AX,WORD PTR [NBYTES]
        MOV     DX,WORD PTR [NBYTES+2]
        MOV     BX,10
        DIV     BX              ; DX:AX / 10 (NBYTES < 655360)
        PUSH    DX
        OR      AX,AX
        JZ      PUTNB1
        CALL    PUTNUM
PUTNB1: POP     AX
        JMP     SHORT PUTN2
; PUTNUM: AX in decimal
PUTNUM: XOR     DX,DX
        MOV     BX,10
        DIV     BX
        PUSH    DX
        OR      AX,AX
        JZ      PUTN1
        CALL    PUTNUM
PUTN1:  POP     AX
PUTN2:  MOV     DL,AL
        ADD     DL,"0"
        MOV     AH,2
        INT     33
        RET

; COMMA: after a field: CF=1 if the line ends there; otherwise past the
; comma, ZF=1 if the next field is empty too, AL = its first character
COMMA:  CALL    BLANKS
        STC
        JZ      CMX
        CMP     AL,","
        JNZ     CMBAD
        INC     SI
        CALL    BLANKS
        CMP     AL,","
        JZ      CMX
        OR      AL,AL
CMX:    RET
CMBAD:  JMP     BAD

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

        DW      64 DUP (0)
STKTOP  LABEL   WORD

; the Z80 part: length, the BIOS addresses it was made for, the code.
; Once it is in the Z80's memory the buffers go over it.
Z80IMG  LABEL   BYTE
SCRBUF  EQU     Z80IMG          ; the host's screen, 24 x 80 at most
RINGBUF EQU     SCRBUF+ROWS*80
LOGBUF  EQU     RINGBUF+RINGSZ
XBUF    EQU     LOGBUF+LOGSZ    ; an XMODEM block (133 bytes)
        INCLUDE TERMZ80.INC

CODE    ENDS
        END     BEGIN
