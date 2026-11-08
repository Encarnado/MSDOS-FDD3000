; EDIT.COM for MS-DOS 1.25 on the Timex FDD3000: a full-screen text
; editor, with the keys and the status line of TMX CP/M's EDIT
; (cpm80ds/progs/edit.asm).
;
;       EDIT name.ext [/80]
;
; The whole file is held in memory in a gap buffer: the text before the
; cursor at BUFS..GAPS-1, the text after it at GAPE..TEND-1. Lines end in
; LF inside; the file is read and written with CR LF and a ^Z at the end.
;
; The 8086 runs here on an interpreter, at about 17 000 instructions a
; second, so the screen is not kept as a copy and compared, as EDIT does
; on the Z80. Each text row has a mark instead: the first column to send
; again, or FFH. A command marks what it changed, and only marked rows are
; sent, a row at a time, until a key is waiting. A line moved past the top
; or bottom row scrolls the terminal (ESC I on the top row, LF on the
; bottom one), and the fields of the status line are sent only when they
; change.
;
; The terminal is the Terminal 3000's VT52: ESC Y row col, ESC H ESC J,
; ESC K, ESC L / ESC M (inverse), ESC I. The editor never writes in the
; last column (the terminal wraps there). Output goes through INT 10H
; (teletype) and keys come from INT 16H, so ^C, ^S and the rest reach the
; editor, not DOS.

TAB     EQU     9
LF      EQU     10
CR      EQU     13
CTLZ    EQU     26
KESC    EQU     27
NRMAX   EQU     24              ; text rows at most
LMAX    EQU     1024            ; columns of a line that can be shown
FMAX    EQU     16              ; longest search string
OBSZ    EQU     1024            ; output to the terminal, sent at once
WBSZ    EQU     2048            ; the file, written in blocks of this
LNUMC   EQU     23              ; status line: line number,
CNUMC   EQU     33              ;   column,
MSGC    EQU     39              ;   messages

; buffers after the program, at BUFFERS
OBOFF   EQU     0
EBOFF   EQU     OBOFF+OBSZ      ; a row with its tabs expanded
WBOFF   EQU     EBOFF+LMAX+16
STKOFF  EQU     WBOFF+WBSZ+256  ; the stack's top
TXOFF   EQU     STKOFF          ; then the text

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

BEGIN:  JMP     START

; the test (test_fdd86.py) finds these by the signature
SIG     DB      "EDIT86"
BUFS    DW      0               ; start of the text
GAPS    DW      0               ; the cursor: start of the gap
GAPE    DW      0               ; end of the gap
TEND    DW      0               ; end of the text
TOP     DW      0               ; start of the top line (before the gap)
TOPLN   DW      1               ; its line number
LINE    DW      1               ; the cursor's line number
LEFT    DW      0               ; first column shown
CCOL    DW      0               ; the cursor's column
CROW    DW      0               ; its text row (screen row - 1)
COLS    DW      64              ; terminal columns (/nn)
NR      DW      23              ; text rows
W       DW      63              ; columns used: never the last one
MODIF   DB      0               ; 1: changed since read or saved

CLS_    DW      0               ; start of the cursor's line (FIXSCR)
GOAL    DW      0               ; column wanted by up and down
VERT    DB      0               ; 1: the last command moved up or down
MARKF   DB      0               ; 1: mark the cursor's row from the cursor
FULL    DB      0               ; 1: every row is to be sent
STFULL  DB      0               ; 1: the whole status line is to be sent
MSG     DW      0               ; message on the status line, 0 = none
SHMSG   DW      0               ; the message the terminal shows,
SHLINE  DW      0               ;   line number,
SHCOL   DW      0               ;   column,
SHMOD   DB      0               ;   changed mark
MODC    DB      0               ; column of the changed mark
DRVL    DB      "A"
OPTR    DW      OFFSET BUFFERS+OBOFF
DRROW   DW      0               ; DRAW: row,
DRLAST  DW      0               ;   the last one marked,
DRP     DW      0               ;   start of its line,
DREOT   DB      0               ;   1: past the end of the text
P1      DW      0               ; ROWOUT: the line in up to two pieces
N1      DW      0
P2      DW      0
N2      DW      0
TLEN    DW      0               ; PROMPT: what was typed
FLEN    DW      0               ; the search string
FC1     DB      0               ;   its first letter, upper case,
FC2     DB      0               ;   lower case
FP1     DW      0               ;   where they are next
FP2     DW      0
WCNT    DW      0               ; bytes in the write buffer
DFULL   DB      0               ; 1: a write failed
ERRF    DB      0               ; 1: DOS asked about a disk error (INT 24H)
OLD24   DW      0,0

DIRTY   DB      NRMAX DUP (0FFH)        ; per text row: first column to send
TBUF    DB      FMAX DUP (0)
FSTR    DB      FMAX DUP (0)
FCB     DB      37 DUP (0)
TFCB    DB      37 DUP (0)      ; name.$$$
RFCB    DB      37 DUP (0)      ; for rename: old name, new name at 16

USEMSG  DB      "EDIT 1.0 - full screen text editor",13,10
        DB      "Usage: EDIT name.ext [/80]",13,10,"$"
BIGMSG  DB      "File too big for memory",13,10,"$"
MKPRE   DB      "^K",0
MQPRE   DB      "^Q",0
MNEW    DB      "New file",0
MSAVED  DB      "Saved",0
MNOTF   DB      "Not found",0
MMEM    DB      "Memory full",0
MDFULL  DB      "Disk full: not saved",0
MDIR    DB      "Directory full",0
MABAN   DB      "Abandon changes (Y/N)? ",0
MFIND   DB      "Find: ",0
MLINE   DB      " Line ",0
MCOL    DB      " Col ",0
MHELP   DB      "EDIT 1.0   (^ = CTRL)",13,10,13,10
        DB      "Cursor  ^E up   ^X down   ^S left   ^D right   (or arrows)",13,10
        DB      "        ^A word left      ^F word right",13,10
        DB      "        ^R page up        ^C page down",13,10
        DB      "        ^QS line start    ^QD line end",13,10
        DB      "        ^QR file start    ^QC file end",13,10
        DB      "Delete  DEL left   ^G right   ^T word   ^Y line",13,10
        DB      "        ^QY to the end of the line",13,10
        DB      "Insert  RETURN new line   ^N split line   TAB",13,10
        DB      "Find    ^QF find          ^L find again",13,10
        DB      "File    ^KS save          ^KX save and exit",13,10
        DB      "        ^KQ quit",13,10,13,10
        DB      "Press a key",0

CTAB    DW      NOKEY,WORDL,NOKEY,PGDN          ; ^@ ^A ^B ^C
        DW      RIGHT,UP,WORDR,DELF             ; ^D ^E ^F ^G
        DW      DELB,TABK,HELP,KPRE             ; ^H ^I ^J ^K
        DW      FNEXT,NEWLN,SPLIT,NOKEY         ; ^L ^M ^N ^O
        DW      NOKEY,QPRE,PGUP,LEFTK           ; ^P ^Q ^R ^S
        DW      DELWD,NOKEY,NOKEY,NOKEY         ; ^T ^U ^V ^W
        DW      DOWN,DELLN,NOKEY,ESCK           ; ^X ^Y ^Z ESC
        DW      NOKEY,NOKEY,NOKEY,NOKEY

USAGE:  MOV     DX,OFFSET USEMSG
DOSMSG: MOV     AH,9
        INT     33
        INT     32

START:  MOV     SP,OFFSET BUFFERS+STKOFF
        CLD
        CALL    OPTS
        CMP     BYTE PTR DS:[5DH]," "
        JZ      USAGE
        MOV     DI,5DH
        MOV     CX,11
        MOV     AL,"?"
        REPNE   SCASB
        JZ      USAGE
        MOV     SI,5CH
        MOV     DI,OFFSET FCB
        MOV     CX,12
        REP     MOVSB
        MOV     AL,[FCB]
        OR      AL,AL
        JNZ     DRV1
        MOV     AH,25           ; the current drive
        INT     33
        INC     AL
DRV1:   ADD     AL,"A"-1
        MOV     [DRVL],AL
        MOV     AX,DS:[2]       ; memory: up to the end of ours, in this segment
        MOV     BX,CS
        SUB     AX,BX
        MOV     BX,0FFF0H
        CMP     AX,0FFFH
        JAE     MEM1
        MOV     CL,4
        SHL     AX,CL
        MOV     BX,AX
MEM1:   MOV     [TEND],BX
        MOV     WORD PTR [BUFS],OFFSET BUFFERS+TXOFF
        CALL    LOADF
        MOV     DX,OFFSET CRIT  ; INT 24H: note disk errors (DOS puts the
        MOV     AX,2524H        ;   old vector back when we end)
        PUSH    DS
        XOR     BX,BX
        MOV     DS,BX
        MOV     BX,DS:[90H]
        MOV     CX,DS:[92H]
        POP     DS
        MOV     [OLD24],BX
        MOV     [OLD24+2],CX
        INT     33
        CALL    REDRAW
;
; the main loop: the screen for the cursor, then draw it unless a key is
; waiting, then the key
;
MAIN:   CALL    FIXSCR
        CALL    KEYRDY
        JNZ     MAIN1
        CALL    DRAW
        JB      MAIN1
        CALL    STATUS
        CALL    PLACE
MAIN1:  CALL    FLUSH
        CALL    GETKEY
        MOV     WORD PTR [MSG],0        ; a message lasts until the next key
        MOV     [VERT],0
        CALL    DOKEY
        JMP     MAIN

DOKEY:  CMP     AL,7FH
        JNZ     DK1
        JMP     DELB
DK1:    CMP     AL," "
        JB      DK2
        JMP     INSCH
DK2:    MOV     BL,AL
        XOR     BH,BH
        SHL     BX,1
        JMP     CTAB[BX]

NOKEY:  RET

ESCK:   CALL    GETKEY          ; the arrow keys: ESC A, B, C, D
        CMP     AL,"A"
        JNZ     EK1
        JMP     UP
EK1:    CMP     AL,"B"
        JNZ     EK2
        JMP     DOWN
EK2:    CMP     AL,"C"
        JNZ     EK3
        JMP     RIGHT
EK3:    CMP     AL,"D"
        JNZ     NOKEY
        JMP     LEFTK

KPRE:   MOV     SI,OFFSET MKPRE
        CALL    PREFIX
        CMP     AL,"S"
        JNZ     KP1
        JMP     SAVE
KP1:    CMP     AL,"X"
        JZ      SAVEX
        CMP     AL,"D"
        JZ      SAVEX
        CMP     AL,"Q"
        JZ      QUIT
        RET

SAVEX:  CALL    SAVE
        JNB     EXIT
        RET

QUIT:   CMP     [MODIF],0
        JZ      EXIT
        MOV     SI,OFFSET MABAN
        CALL    PREFIX
        CMP     AL,"Y"
        JZ      EXIT
        RET

EXIT:   CALL    CLS
        CALL    FLUSH
        INT     32

QPRE:   MOV     SI,OFFSET MQPRE
        CALL    PREFIX
        CMP     AL,"S"
        JNZ     QP1
        JMP     LBEG
QP1:    CMP     AL,"D"
        JNZ     QP2
        JMP     LEND
QP2:    CMP     AL,"R"
        JNZ     QP3
        JMP     FTOP
QP3:    CMP     AL,"C"
        JNZ     QP4
        JMP     FEND
QP4:    CMP     AL,"F"
        JNZ     QP5
        JMP     FIND
QP5:    CMP     AL,"Y"
        JNZ     QP6
        JMP     DELEOL
QP6:    RET

; PREFIX: SI (a message) on the status line, then the next key as a
; capital letter (^S, s and S are all S)
PREFIX: MOV     [MSG],SI
        CALL    STATUS
        CALL    FLUSH
        CALL    GETKEY
        MOV     WORD PTR [MSG],0
        CMP     AL," "
        JNB     UPPER
        ADD     AL,40H
UPPER:  CMP     AL,"a"
        JB      UPX
        CMP     AL,"z"
        JA      UPX
        SUB     AL,20H
UPX:    RET

; OPTS: /nn in the command tail: nn columns (64 to 80)
OPTS:   MOV     SI,81H
        MOV     CL,DS:[80H]
        XOR     CH,CH
        JCXZ    OPX
        MOV     DI,SI
        MOV     AL,"/"
        REPNE   SCASB
        JNZ     OPX
        XOR     DX,DX
OP1:    MOV     AL,[DI]
        SUB     AL,"0"
        CMP     AL,9
        JA      OP2
        INC     DI
        XCHG    AX,DX
        MOV     BL,10
        MUL     BL
        XOR     DH,DH
        ADD     AX,DX
        XCHG    AX,DX
        JMP     OP1
OP2:    CMP     DX,64
        JB      OPX
        CMP     DX,80
        JA      OPX
        MOV     [COLS],DX
        DEC     DX
        MOV     [W],DX
OPX:    RET

; ---------------------------------------------------------------- the file
;
; LOADF: read the file into the text; a missing file is a new one
;
LOADF:  MOV     AX,[BUFS]
        MOV     [GAPS],AX
        MOV     [TOP],AX
        MOV     AX,[TEND]
        MOV     [GAPE],AX
        MOV     DX,OFFSET FCB
        MOV     AH,15
        INT     33
        OR      AL,AL
        JZ      LD1
        MOV     WORD PTR [MSG],OFFSET MNEW
        RET
LD1:    MOV     AX,[TEND]
        SUB     AX,[BUFS]
        CMP     WORD PTR [FCB+18],0
        JNZ     TOOBIG
        MOV     CX,WORD PTR [FCB+16]
        CMP     CX,AX
        JBE     LD2
TOOBIG: MOV     DX,OFFSET BIGMSG
        JMP     DOSMSG
LD2:    JCXZ    LDX
        MOV     DX,[BUFS]
        MOV     AH,26           ; DTA
        INT     33
        MOV     WORD PTR [FCB+14],1     ; record size 1: CX records = bytes
        MOV     WORD PTR [FCB+33],0
        MOV     WORD PTR [FCB+35],0
        MOV     DX,OFFSET FCB
        MOV     AH,39           ; random block read
        INT     33
        MOV     BX,[BUFS]       ; the text ends at the first ^Z of the last
        ADD     BX,CX           ;   128 bytes (CP/M fills its last record
        MOV     DI,BX           ;   with them)
        MOV     CX,128
        SUB     DI,CX
        CMP     DI,[BUFS]
        JAE     LD2A
        MOV     DI,[BUFS]
        MOV     CX,BX
        SUB     CX,DI
LD2A:   MOV     AL,CTLZ
        REPNE   SCASB
        JNZ     LD3
        MOV     BX,DI
        DEC     BX
LD3:    MOV     SI,[BUFS]       ; drop the CRs: copy what is between them
        MOV     CX,BX
        SUB     CX,SI
        MOV     BX,SI           ; BX = where the next part goes
LD4:    JCXZ    LD6
        MOV     DI,SI
        MOV     AL,CR
        REPNE   SCASB
        MOV     DX,CX           ; left after this part
        MOV     CX,DI
        JNZ     LD5
        DEC     CX              ; not the CR
LD5:    SUB     CX,SI
        XCHG    DI,BX
        REP     MOVSB
        MOV     SI,BX
        MOV     BX,DI
        MOV     CX,DX
        JMP     LD4
LD6:    MOV     [GAPS],BX
        MOV     AX,[BUFS]       ; the cursor to the start
        CALL    GAPMV
LDX:    RET

;
; SAVE: write name.$$$, then name.ext becomes name.BAK and name.$$$
; becomes name.ext. CF=1 if it was not saved (the old file is as it was).
;
SAVE:   MOV     SI,OFFSET FCB
        MOV     DI,OFFSET TFCB
        MOV     CX,12
        REP     MOVSB
        XOR     AL,AL
        MOV     CX,25
        REP     STOSB
        MOV     DI,OFFSET TFCB+9
        MOV     AL,"$"
        STOSB
        STOSB
        STOSB
        MOV     [ERRF],0
        MOV     [DFULL],0
        MOV     WORD PTR [WCNT],0
        MOV     DX,OFFSET TFCB
        MOV     AH,19           ; delete an old one
        INT     33
        MOV     DX,OFFSET TFCB
        MOV     AH,22           ; make
        INT     33
        OR      AL,AL
        JZ      SV1
        MOV     WORD PTR [MSG],OFFSET MDIR
        JMP     SVFAIL
SV1:    MOV     WORD PTR [TFCB+14],1
        MOV     DX,OFFSET BUFFERS+WBOFF
        MOV     AH,26
        INT     33
        MOV     SI,[BUFS]
        MOV     CX,[GAPS]
        SUB     CX,SI
        CALL    WTEXT
        MOV     SI,[GAPE]
        MOV     CX,[TEND]
        SUB     CX,SI
        CALL    WTEXT
        MOV     AL,CTLZ
        CALL    WBYTE
        CALL    WFLUSH
        MOV     DX,OFFSET TFCB
        MOV     AH,16           ; close
        INT     33
        CMP     [DFULL],0
        JZ      SV2
        MOV     DX,OFFSET TFCB
        MOV     AH,19
        INT     33
        MOV     WORD PTR [MSG],OFFSET MDFULL
        JMP     SHORT SVFAIL
SV2:    MOV     SI,OFFSET FCB   ; name.BAK: delete, then name.ext -> name.BAK
        MOV     DI,OFFSET RFCB
        MOV     CX,12
        REP     MOVSB
        MOV     DI,OFFSET RFCB+9
        CALL    BAKEXT
        MOV     DX,OFFSET RFCB
        MOV     AH,19
        INT     33
        MOV     SI,OFFSET FCB
        MOV     DI,OFFSET RFCB
        MOV     CX,12
        REP     MOVSB
        MOV     SI,OFFSET FCB+1
        MOV     DI,OFFSET RFCB+17
        MOV     CX,11
        REP     MOVSB
        MOV     DI,OFFSET RFCB+25
        CALL    BAKEXT
        MOV     DX,OFFSET RFCB
        MOV     AH,23           ; rename (a new file has none)
        INT     33
        MOV     SI,OFFSET TFCB  ; name.$$$ -> name.ext
        MOV     DI,OFFSET RFCB
        MOV     CX,12
        REP     MOVSB
        MOV     SI,OFFSET FCB+1
        MOV     DI,OFFSET RFCB+17
        MOV     CX,11
        REP     MOVSB
        MOV     DX,OFFSET RFCB
        MOV     AH,23
        INT     33
        MOV     [MODIF],0
        MOV     WORD PTR [MSG],OFFSET MSAVED
        CALL    AFTDOS
        CLC
        RET
SVFAIL: CALL    AFTDOS
        STC
        RET

BAKEXT: MOV     AL,"B"
        STOSB
        MOV     AL,"A"
        STOSB
        MOV     AL,"K"
        STOSB
        RET

; AFTDOS: if DOS asked about a disk error, its question is on the screen
AFTDOS: CMP     [ERRF],0
        JZ      AFX
        CALL    REDRAW
AFX:    RET

; CRIT: INT 24H. Note it, then DOS's own handler asks the question.
CRIT:   MOV     CS:[ERRF],1
        JMP     DWORD PTR CS:[OLD24]

; WTEXT: CX bytes at SI to the file, each LF as CR LF
WTEXT:  JCXZ    WTX
        MOV     DI,SI
        MOV     AL,LF
        REPNE   SCASB
        MOV     DX,CX           ; left after this line
        MOV     CX,DI
        MOV     AH,0
        JNZ     WT1
        DEC     CX              ; not the LF
        MOV     AH,1
WT1:    SUB     CX,SI
        PUSH    DX
        PUSH    AX
        CALL    WCOPY
        POP     AX
        OR      AH,AH
        JZ      WT2
        INC     SI
        MOV     AL,CR
        CALL    WBYTE
        MOV     AL,LF
        CALL    WBYTE
WT2:    POP     CX
        JMP     WTEXT
WTX:    RET

; WCOPY: CX bytes at SI to the write buffer
WCOPY:  JCXZ    WTX
        MOV     DI,[WCNT]
        MOV     AX,WBSZ
        SUB     AX,DI
        ADD     DI,OFFSET BUFFERS+WBOFF
        MOV     DX,CX
        CMP     CX,AX
        JBE     WC1
        MOV     CX,AX
WC1:    SUB     DX,CX
        ADD     [WCNT],CX
        REP     MOVSB
        CMP     WORD PTR [WCNT],WBSZ
        JB      WC2
        CALL    WFLUSH
WC2:    MOV     CX,DX
        JMP     WCOPY

; WBYTE: AL to the write buffer
WBYTE:  MOV     DI,[WCNT]
        MOV     BYTE PTR BUFFERS+WBOFF[DI],AL
        INC     DI
        MOV     [WCNT],DI
        CMP     DI,WBSZ
        JB      WTX

; WFLUSH: the write buffer to the file (random block write); after a
; failed write, nothing more is written
WFLUSH: MOV     CX,[WCNT]
        JCXZ    WTX
        MOV     WORD PTR [WCNT],0
        CMP     [DFULL],0
        JNZ     WTX
        PUSH    SI
        PUSH    DX
        MOV     DX,OFFSET TFCB
        MOV     AH,40
        INT     33
        POP     DX
        POP     SI
        OR      AL,AL
        JZ      WTX
        MOV     [DFULL],1
        RET

; ---------------------------------------------------------------- the text
;
; GAPMV: the gap to address AX, AX <= GAPS (the cursor goes back) or
; AX >= GAPE (forward)
;
GAPMV:  CMP     AX,[GAPS]
        JA      GM2
        MOV     CX,[GAPS]
        SUB     CX,AX
        JZ      GMX
        MOV     SI,[GAPS]
        DEC     SI
        MOV     DI,[GAPE]
        DEC     DI
        STD
        REP     MOVSB
        CLD
        INC     DI
        MOV     [GAPE],DI
        MOV     [GAPS],AX
GMX:    RET
GM2:    MOV     CX,AX
        SUB     CX,[GAPE]
        JZ      GMX
        MOV     SI,[GAPE]
        MOV     DI,[GAPS]
        REP     MOVSB
        MOV     [GAPS],DI
        MOV     [GAPE],AX
        RET

; MOVETO: GAPMV, and LINE counts the LFs passed
MOVETO: PUSH    AX
        CMP     AX,[GAPS]
        JA      MT1
        MOV     DI,AX
        MOV     CX,[GAPS]
        SUB     CX,AX
        CALL    CNTLF
        SUB     [LINE],DX
        JMP     SHORT MT2
MT1:    MOV     DI,[GAPE]
        MOV     CX,AX
        SUB     CX,DI
        CALL    CNTLF
        ADD     [LINE],DX
MT2:    POP     AX
        JMP     GAPMV

; CNTLF: DX = LFs in the CX bytes at DI
CNTLF:  XOR     DX,DX
        MOV     AL,LF
CN1:    JCXZ    CNX
        REPNE   SCASB
        JNZ     CNX
        INC     DX
        JMP     CN1
CNX:    RET

; LSOF: AX = start of the line that holds the byte before address AX
; (AX at most GAPS)
LSOF:   MOV     CX,AX
        SUB     CX,[BUFS]
        JZ      LSX
        MOV     DI,AX
        DEC     DI
        MOV     AL,LF
        STD
        REPNE   SCASB
        CLD
        JNZ     LS1
        LEA     AX,[DI+2]
        RET
LS1:    MOV     AX,[BUFS]
LSX:    RET

; NEXTLF: DI = the next LF from DI on, below BX; CF=1 none, DI = BX
NEXTLF: MOV     CX,BX
        SUB     CX,DI
        JZ      NLN
        MOV     AL,LF
        REPNE   SCASB
        JNZ     NLN
        DEC     DI
        CLC
        RET
NLN:    MOV     DI,BX
        STC
        RET

; WALK: SI = the place in the line SI..BX-1 at column DX, or the last
; one before it
WALK:   MOV     CX,BX
        SUB     CX,SI
        CMP     CX,DX
        JBE     WK1
        MOV     CX,DX
WK1:    JCXZ    WKX
        MOV     DI,SI
        MOV     AL,TAB
        PUSH    CX
        REPNE   SCASB
        POP     CX
        JZ      WK2
        ADD     SI,CX           ; no tab: a column a byte
WKX:    RET
WK2:    XOR     CX,CX
WK3:    CMP     SI,BX
        JAE     WKX
        MOV     DI,CX
        CMP     BYTE PTR [SI],TAB
        JNZ     WK4
        OR      DI,7
WK4:    INC     DI              ; the column after this byte
        CMP     DI,DX
        JA      WKX
        MOV     CX,DI
        INC     SI
        JMP     WK3

; ISWD: CF=1 if AL is a letter or a digit
ISWD:   CMP     AL,"0"
        JB      IWN
        CMP     AL,"9"+1
        JB      IWX
        CMP     AL,"A"
        JB      IWN
        CMP     AL,"Z"+1
        JB      IWX
        CMP     AL,"a"
        JB      IWN
        CMP     AL,"z"+1
IWX:    RET
IWN:    CLC
        RET

; ---------------------------------------------------------------- moving
LEFTK:  MOV     AX,[GAPS]
        CMP     AX,[BUFS]
        JZ      MVX
        DEC     AX
        JMP     MOVETO

RIGHT:  MOV     AX,[GAPE]
        CMP     AX,[TEND]
        JZ      MVX
        INC     AX
        JMP     MOVETO
MVX:    RET

; UP, DOWN: to the column GOAL of the line above, below; CF=1 if none
UP:     MOV     [VERT],1
        MOV     AX,[GAPS]
        CALL    LSOF
        CMP     AX,[BUFS]
        JZ      UPN
        MOV     BX,AX
        DEC     BX              ; the LF that ends the line above
        MOV     AX,BX
        PUSH    BX
        CALL    LSOF
        POP     BX
        MOV     SI,AX
        MOV     DX,[GOAL]
        CALL    WALK
        MOV     AX,SI
        CALL    MOVETO
        CLC
        RET
UPN:    STC
        RET

DOWN:   MOV     [VERT],1
        MOV     DI,[GAPE]
        MOV     BX,[TEND]
        CALL    NEXTLF
        JB      DNX
        INC     DI
        MOV     SI,DI
        PUSH    SI
        CALL    NEXTLF
        MOV     BX,DI
        POP     SI
        MOV     DX,[GOAL]
        CALL    WALK
        MOV     AX,SI
        CALL    MOVETO
        CLC
DNX:    RET

; page down, up: the cursor stays on its row, the text moves a page
PGDN:   MOV     CX,[NR]
        DEC     CX
PD1:    PUSH    CX
        CALL    DOWN
        POP     CX
        JB      KEEPRW
        LOOP    PD1
        JMP     SHORT KEEPRW

PGUP:   MOV     CX,[NR]
        DEC     CX
PU1:    PUSH    CX
        CALL    UP
        POP     CX
        JB      KEEPRW
        LOOP    PU1
KEEPRW: MOV     AX,[GAPS]
        CALL    LSOF
        MOV     CX,[CROW]
        JMP     SETTOP

WORDR:  MOV     SI,[GAPE]       ; over this word, then to the next one
WR1:    CMP     SI,[TEND]
        JAE     WR3
        LODSB
        CALL    ISWD
        JB      WR1
        DEC     SI
WR2:    CMP     SI,[TEND]
        JAE     WR3
        LODSB
        CALL    ISWD
        JNB     WR2
        DEC     SI
WR3:    MOV     AX,SI
        JMP     MOVETO

WORDL:  MOV     SI,[GAPS]       ; back over the gap, then over a word
WL1:    CMP     SI,[BUFS]
        JZ      WL3
        MOV     AL,[SI-1]
        CALL    ISWD
        JB      WL2
        DEC     SI
        JMP     WL1
WL2:    CMP     SI,[BUFS]
        JZ      WL3
        MOV     AL,[SI-1]
        CALL    ISWD
        JNB     WL3
        DEC     SI
        JMP     WL2
WL3:    MOV     AX,SI
        JMP     MOVETO

LBEG:   MOV     AX,[GAPS]
        CALL    LSOF
        JMP     MOVETO

LEND:   MOV     DI,[GAPE]
        MOV     BX,[TEND]
        CALL    NEXTLF
        MOV     AX,DI
        JMP     MOVETO

FTOP:   MOV     AX,[BUFS]
        JMP     MOVETO

FEND:   MOV     AX,[TEND]
        JMP     MOVETO

; ---------------------------------------------------------------- editing
NEWLN:  MOV     AL,LF
        JMP     SHORT INSCH
TABK:   MOV     AL,TAB
INSCH:  MOV     DI,[GAPS]
        CMP     DI,[GAPE]
        JZ      MFULL
        PUSH    AX
        CALL    MARKC
        POP     AX
        MOV     DI,[GAPS]
        STOSB
        MOV     [GAPS],DI
        MOV     [MODIF],1
        CMP     AL,LF
        JNZ     INX
        INC     WORD PTR [LINE]
        CALL    MARKB
INX:    RET
MFULL:  MOV     WORD PTR [MSG],OFFSET MMEM
        RET

SPLIT:  MOV     DI,[GAPE]       ; a LF after the cursor
        CMP     DI,[GAPS]
        JZ      MFULL
        CALL    MARKC
        CALL    MARKB
        DEC     WORD PTR [GAPE]
        MOV     DI,[GAPE]
        MOV     BYTE PTR [DI],LF
        MOV     [MODIF],1
        RET

DELB:   MOV     SI,[GAPS]
        CMP     SI,[BUFS]
        JZ      DBX
        DEC     SI
        MOV     [GAPS],SI
        MOV     [MODIF],1
        MOV     [MARKF],1       ; the row from the cursor (FIXSCR)
        CMP     BYTE PTR [SI],LF
        JNZ     DBX
        DEC     WORD PTR [LINE]
        MOV     AX,[CROW]       ; the rows below move up
        CALL    MARKR
DBX:    RET

DELF:   MOV     SI,[GAPE]
        CMP     SI,[TEND]
        JZ      DFX
        CALL    MARKC
        MOV     SI,[GAPE]
        LODSB
        MOV     [GAPE],SI
        MOV     [MODIF],1
        CMP     AL,LF
        JNZ     DFX
        CALL    MARKB
DFX:    RET

DELEOL: MOV     DI,[GAPE]       ; up to the LF
        MOV     BX,[TEND]
        CALL    NEXTLF
        CMP     DI,[GAPE]
        JZ      DFX
        PUSH    DI
        CALL    MARKC
        POP     DI
        MOV     [GAPE],DI
        MOV     [MODIF],1
        RET

DELLN:  MOV     AX,[CLS_]       ; from the start of the line, with its LF
        CALL    MOVETO
        MOV     DI,[GAPE]
        MOV     BX,[TEND]
        CALL    NEXTLF
        JB      DL1
        INC     DI
DL1:    CMP     DI,[GAPE]
        JZ      DFX
        MOV     [GAPE],DI
        MOV     [MODIF],1
        MOV     AX,[CROW]
        JMP     MARKR

DELWD:  MOV     SI,[GAPE]       ; a word and the blanks after it
        CMP     SI,[TEND]
        JZ      DFX
        LODSB
        CMP     AL,LF
        JNZ     DW0
        JMP     DELF
DW0:    CALL    ISWD
        JNB     DW2
DW1:    CMP     SI,[TEND]
        JAE     DW3
        LODSB
        CALL    ISWD
        JB      DW1
        DEC     SI
DW2:    CMP     SI,[TEND]
        JAE     DW3
        LODSB
        CMP     AL," "
        JZ      DW2
        CMP     AL,TAB
        JZ      DW2
        DEC     SI
DW3:    PUSH    SI
        CALL    MARKC
        POP     SI
        MOV     [GAPE],SI
        MOV     [MODIF],1
        RET

; ---------------------------------------------------------------- find
FIND:   CALL    PROMPT
        JNB     FI0
        RET
FI0:    MOV     CX,[TLEN]
        JCXZ    FNEXT           ; nothing typed: the last string again
        MOV     [FLEN],CX
        MOV     SI,OFFSET TBUF
        MOV     DI,OFFSET FSTR
FI1:    LODSB
        CALL    UPPER
        STOSB
        LOOP    FI1
FNEXT:  MOV     CX,[FLEN]       ; from after the cursor on
        JCXZ    FX
        MOV     SI,[GAPE]
        INC     SI
        MOV     BX,[TEND]
        SUB     BX,CX
        INC     BX              ; BX: where a match can start, below
        MOV     AL,[FSTR]
        MOV     [FC1],AL
        MOV     AH,AL
        CMP     AL,"A"
        JB      FN0
        CMP     AL,"Z"
        JA      FN0
        OR      AH,20H
FN0:    MOV     [FC2],AH
        CALL    SCANF           ; the first letter, both cases: the nearer
        MOV     [FP1],AX        ;   one is where the string may be
        MOV     AL,[FC2]
        CALL    SCANF
        MOV     [FP2],AX
FN1:    MOV     AX,[FP1]
        CMP     AX,[FP2]
        JBE     FN2
        MOV     AX,[FP2]
FN2:    CMP     AX,0FFFFH
        JZ      NOTF
        PUSH    AX
        CALL    MATCH
        POP     AX
        JZ      FOUND
        MOV     SI,AX
        INC     SI
        CMP     AX,[FP1]
        JNZ     FN3
        PUSH    AX
        MOV     AL,[FC1]
        CALL    SCANF
        MOV     [FP1],AX
        POP     AX
FN3:    CMP     AX,[FP2]
        JNZ     FN1
        MOV     AL,[FC2]
        CALL    SCANF
        MOV     [FP2],AX
        JMP     FN1
FOUND:  JMP     MOVETO
NOTF:   MOV     WORD PTR [MSG],OFFSET MNOTF
FX:     RET

; SCANF: AX = the first AL from SI on, below BX (FFFFH: none)
SCANF:  MOV     DI,SI
        MOV     CX,BX
        SUB     CX,SI
        JBE     SFN
        REPNE   SCASB
        JNZ     SFN
        LEA     AX,[DI-1]
        RET
SFN:    MOV     AX,0FFFFH
        RET

; MATCH: ZF=1 if the rest of the string follows AX
MATCH:  MOV     SI,AX
        INC     SI
        MOV     DI,OFFSET FSTR+1
        MOV     CX,[FLEN]
        DEC     CX
        JZ      MAX
MA1:    LODSB
        CALL    UPPER
        CMP     AL,[DI]
        JNZ     MAX
        INC     DI
        LOOP    MA1
        CMP     AL,AL
MAX:    RET

; PROMPT: "Find: " on the status line, then a line typed into TBUF (RETURN
; ends it, DEL takes back); CF=1 if ESC or ^U gave up
PROMPT: MOV     SI,OFFSET MFIND
        MOV     [MSG],SI
        CALL    STATUS
        MOV     WORD PTR [MSG],0
        MOV     WORD PTR [SHMSG],1      ; the message area is sent again later
        MOV     WORD PTR [TLEN],0
PR1:    CALL    FLUSH
        CALL    GETKEY
        CMP     AL,CR
        JZ      PRX
        CMP     AL,KESC
        JZ      PRQ
        CMP     AL,"U"-40H
        JZ      PRQ
        MOV     BX,[TLEN]
        CMP     AL,7FH
        JZ      PRDEL
        CMP     AL,8
        JZ      PRDEL
        CMP     AL," "
        JB      PR1
        CMP     BX,FMAX
        JAE     PR1
        MOV     TBUF[BX],AL
        INC     WORD PTR [TLEN]
        CALL    PUTC
        JMP     PR1
PRDEL:  OR      BX,BX
        JZ      PR1
        DEC     BX
        MOV     [TLEN],BX
        MOV     AX,BX
        ADD     AL,MSGC+6       ; after "Find: "
        MOV     AH,0
        CALL    PUTPOS
        CALL    PUTEOL
        JMP     PR1
PRX:    CLC
        RET
PRQ:    STC
        RET

; ---------------------------------------------------------------- marks
; MARKC: the cursor's row, from the cursor on
MARKC:  MOV     AX,[CCOL]
        SUB     AX,[LEFT]
        MOV     BX,[CROW]
        CMP     AL,DIRTY[BX]
        JNB     MCX
        MOV     DIRTY[BX],AL
MCX:    RET

; MARKB: the rows below the cursor's; MARKR: the rows from AX on
MARKB:  MOV     AX,[CROW]
        INC     AX
MARKR:  OR      AX,AX
        JNS     MR1
        XOR     AX,AX
MR1:    MOV     CX,[NR]
        SUB     CX,AX
        JBE     MCX
        MOV     DI,AX
        ADD     DI,OFFSET DIRTY
        XOR     AL,AL
        REP     STOSB
        RET

; ALLD: every row, all of it
ALLD:   XOR     AX,AX
        CALL    MARKR
        MOV     [FULL],1
        RET

; REDRAW: clear the terminal, then everything is to be sent
REDRAW: CALL    CLS
        CALL    ALLD
        MOV     [STFULL],1
        RET

; ---------------------------------------------------------------- the screen
;
; FIXSCR: the cursor's line and column; the top line and the first column
; shown, so that the cursor is on the screen
;
FIXSCR: MOV     AX,[GAPS]       ; CLS_, CCOL
        CALL    LSOF
        MOV     [CLS_],AX
        MOV     SI,AX
        MOV     CX,[GAPS]
        SUB     CX,SI
        JCXZ    FS3
        MOV     DI,SI
        MOV     AL,TAB
        PUSH    CX
        REPNE   SCASB
        POP     CX
        JNZ     FS3             ; no tab: a column a byte
        XOR     DX,DX
FS2:    LODSB
        CMP     AL,TAB
        JNZ     FS2A
        OR      DX,7
FS2A:   INC     DX
        LOOP    FS2
        MOV     CX,DX
FS3:    MOV     [CCOL],CX
        CMP     [VERT],0
        JNZ     FS4
        MOV     [GOAL],CX
FS4:    MOV     AX,[LINE]       ; the row
        SUB     AX,[TOPLN]
        JB      FSUP
        CMP     AX,[NR]
        JB      FSROW
        JA      FSCEN
        MOV     DI,[TOP]        ; one below: a line up
        MOV     BX,[GAPS]
        CALL    NEXTLF
        INC     DI
        MOV     [TOP],DI
        INC     WORD PTR [TOPLN]
        CMP     [FULL],0
        JNZ     FS5
        CALL    SCRUP
FS5:    MOV     AX,[NR]
        DEC     AX
        JMP     SHORT FSROW
FSUP:   INC     AX
        JNZ     FSCEN
        MOV     AX,[CLS_]       ; one above: a line down
        MOV     [TOP],AX
        MOV     AX,[LINE]
        MOV     [TOPLN],AX
        CMP     [FULL],0
        JNZ     FS6
        CALL    SCRDN
FS6:    XOR     AX,AX
        JMP     SHORT FSROW
FSCEN:  MOV     AX,[CLS_]       ; further: the cursor's line in the middle
        MOV     CX,[NR]
        SHR     CX,1
        CALL    SETTOP
        MOV     AX,[CROW]
FSROW:  MOV     [CROW],AX
        MOV     AX,[CCOL]       ; the columns
        CMP     AX,[LEFT]
        JB      FSH
        MOV     BX,[LEFT]
        ADD     BX,[W]
        DEC     BX
        CMP     AX,BX
        JBE     FSM
FSH:    MOV     BX,[W]
        SHR     BX,1
        SUB     AX,BX
        JNB     FSH1
        XOR     AX,AX
FSH1:   AND     AX,0FFF8H
        MOV     BX,LMAX
        SUB     BX,[W]
        CMP     AX,BX
        JBE     FSH2
        MOV     AX,BX
FSH2:   CMP     AX,[LEFT]
        JZ      FSM
        MOV     [LEFT],AX
        CALL    ALLD
FSM:    CMP     [MARKF],0
        JZ      FSX
        MOV     [MARKF],0
        CALL    MARKC
FSX:    RET

; SETTOP: the top line CX lines above the line at AX (fewer at the start)
SETTOP: XOR     DX,DX
ST1:    JCXZ    ST2
        CMP     AX,[BUFS]
        JZ      ST2
        DEC     AX
        PUSH    CX
        PUSH    DX
        CALL    LSOF
        POP     DX
        POP     CX
        INC     DX
        DEC     CX
        JMP     ST1
ST2:    MOV     [TOP],AX
        MOV     [CROW],DX
        MOV     AX,[LINE]
        SUB     AX,DX
        CMP     AX,[TOPLN]
        MOV     [TOPLN],AX
        JZ      ST3
        CALL    ALLD
ST3:    RET

; SCRUP: LF on the bottom row moves every row up; SCRDN: ESC I on the
; top row moves them down. The marks move with the rows; the status line
; is sent again.
SCRUP:  MOV     AX,[NR]
        MOV     AH,AL
        XOR     AL,AL
        CALL    PUTPOS
        MOV     AL,LF
        CALL    PUTC
        MOV     DI,OFFSET DIRTY
        MOV     SI,OFFSET DIRTY+1
        MOV     CX,[NR]
        DEC     CX
        REP     MOVSB
        MOV     BYTE PTR [DI],0
        MOV     [STFULL],1
        RET

SCRDN:  XOR     AX,AX
        CALL    PUTPOS
        MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"I"
        CALL    PUTC
        MOV     CX,[NR]
        MOV     DI,CX
        ADD     DI,OFFSET DIRTY-1
        LEA     SI,[DI-1]
        DEC     CX
        STD
        REP     MOVSB
        CLD
        MOV     BYTE PTR [DI],0
        MOV     [STFULL],1
        RET

;
; DRAW: the marked rows, top to bottom; CF=1 if a key came first
;
DRAW:   MOV     DI,OFFSET DIRTY ; the first and the last marked rows: the
        MOV     CX,[NR]         ;   lines of the others are not even looked at
        MOV     AL,0FFH
        REPE    SCASB
        JNZ     DR0
        JMP     DRDONE
DR0:    SUB     DI,OFFSET DIRTY+1
        MOV     [DRROW],DI
        MOV     DI,OFFSET DIRTY-1
        ADD     DI,[NR]
        MOV     CX,[NR]
        STD
        REPE    SCASB
        CLD
        SUB     DI,OFFSET DIRTY-1
        MOV     [DRLAST],DI
        MOV     AX,[DRROW]
        CMP     AX,[CROW]
        JAE     DR2             ; none above the cursor's row
        MOV     WORD PTR [DRROW],0
        MOV     AX,[TOP]
        MOV     [DRP],AX
        JMP     SHORT DR1
DRDN0:  MOV     [FULL],0
        CLC
        RET
DR1:    MOV     BX,[DRROW]      ; the rows above the cursor's
        CMP     BX,[DRLAST]
        JA      DRDN0
        CMP     BX,[CROW]
        JAE     DR2
        MOV     DI,[DRP]
        PUSH    BX
        MOV     BX,[GAPS]
        CALL    NEXTLF
        POP     BX
        MOV     SI,[DRP]
        MOV     [P1],SI
        SUB     DI,SI
        MOV     [N1],DI
        INC     DI
        ADD     [DRP],DI
        MOV     WORD PTR [N2],0
        CALL    DRAWR
        JNB     DR1A
        RET
DR1A:   INC     WORD PTR [DRROW]
        JMP     DR1
DR2:    MOV     AX,[CROW]       ; the cursor's row: the line in two pieces
        CMP     AX,[DRLAST]
        JA      DRDN0
        MOV     [DRROW],AX
        MOV     AX,[CLS_]
        MOV     [P1],AX
        MOV     CX,[GAPS]
        SUB     CX,AX
        MOV     [N1],CX
        MOV     DI,[GAPE]
        MOV     [P2],DI
        MOV     BX,[TEND]
        CALL    NEXTLF
        MOV     [DREOT],0
        JNB     DR3
        MOV     [DREOT],1
DR3:    MOV     AX,DI
        SUB     AX,[GAPE]
        MOV     [N2],AX
        INC     DI
        MOV     [DRP],DI
        CALL    DRAWR
        JB      DRX
DR4:    INC     WORD PTR [DRROW]        ; the rows below
        MOV     BX,[DRROW]
        CMP     BX,[DRLAST]
        JA      DRDONE
        MOV     WORD PTR [N1],0
        MOV     WORD PTR [N2],0
        CMP     [DREOT],0
        JNZ     DR5
        MOV     DI,[DRP]
        MOV     [P1],DI
        MOV     BX,[TEND]
        CALL    NEXTLF
        JNB     DR6
        MOV     [DREOT],1
DR6:    MOV     AX,DI
        SUB     AX,[DRP]
        MOV     [N1],AX
        INC     DI
        MOV     [DRP],DI
DR5:    CALL    DRAWR
        JNB     DR4
DRX:    RET
DRDONE: MOV     [FULL],0
        CLC
        RET

; DRAWR: row DRROW, if marked, unless a key is waiting (CF=1)
DRAWR:  MOV     BX,[DRROW]
        CMP     DIRTY[BX],0FFH
        JZ      DWX
        CALL    KEYRDY
        STC
        JNZ     DWR
        CALL    ROWOUT
DWX:    CLC
DWR:    RET

; ROWOUT: send row DRROW from its mark on: the pieces P1/N1, P2/N2 with
; their tabs expanded, the columns LEFT.. of them, and ESC K
ROWOUT: CALL    FLUSHQ
        MOV     DI,OFFSET BUFFERS+EBOFF
        MOV     DX,[LEFT]
        ADD     DX,[W]
        ADD     DX,DI           ; DX: no more is needed
        MOV     SI,[P1]
        MOV     CX,[N1]
        CALL    EXPAND
        MOV     SI,[P2]
        MOV     CX,[N2]
        CALL    EXPAND
        CMP     DI,DX
        JBE     RO1
        MOV     DI,DX
RO1:    MOV     BX,[DRROW]
        MOV     AL,DIRTY[BX]
        MOV     DIRTY[BX],0FFH
        MOV     AH,BL
        INC     AH
        PUSH    AX
        CALL    PUTPOS
        POP     AX
        XOR     AH,AH
        MOV     SI,OFFSET BUFFERS+EBOFF
        ADD     SI,[LEFT]
        ADD     SI,AX
        MOV     CX,DI
        SUB     CX,SI
        JBE     PUTEOL
        MOV     DI,[OPTR]
        REP     MOVSB
        MOV     [OPTR],DI
PUTEOL: MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"K"
        JMP     PUTC

; EXPAND: CX bytes at SI to DI, tabs as spaces to the next column that is
; a multiple of 8, other control bytes as "?"; up to DX at most (a tab
; can go 7 past it)
EXPAND: JCXZ    EXX
        MOV     AX,DX
        SUB     AX,DI
        JBE     EXX
        CMP     CX,AX           ; a byte is a column, but for tabs
        JBE     EX1
        MOV     CX,AX
EX1:    LODSB
        CMP     AL," "
        JB      EXC
        CMP     AL,7FH
        JAE     EXQ
EX2:    STOSB
        LOOP    EX1
EXX:    RET
EXQ:    MOV     AL,"?"
        JMP     EX2
EXC:    CMP     AL,TAB
        JNZ     EXQ
        PUSH    CX
        MOV     CX,DI
        SUB     CX,OFFSET BUFFERS+EBOFF
        OR      CX,7
        INC     CX
        ADD     CX,OFFSET BUFFERS+EBOFF
        SUB     CX,DI
        MOV     AL," "
        REP     STOSB
        POP     CX
        DEC     CX
        JZ      EXX
        MOV     AX,DX
        SUB     AX,DI
        JBE     EXX
        CMP     CX,AX
        JBE     EX1
        MOV     CX,AX
        JMP     EX1

;
; STATUS: the status line, row 0: the whole of it, or the fields that
; changed
;
STATUS: CALL    FLUSHQ
        CMP     [STFULL],0
        JNZ     SFULL
        MOV     AL,[MODIF]
        CMP     AL,[SHMOD]
        JZ      SS1
        MOV     AL,[MODC]
        XOR     AH,AH
        CALL    PUTPOS
        CALL    INVON
        CALL    PUTMOD
        CALL    INVOFF
SS1:    MOV     AX,[LINE]
        CMP     AX,[SHLINE]
        JZ      SS2
        MOV     AX,LNUMC
        CALL    PUTPOS
        CALL    PUTLN
SS2:    MOV     AX,[CCOL]
        INC     AX
        CMP     AX,[SHCOL]
        JZ      SS3
        MOV     AX,CNUMC
        CALL    PUTPOS
        CALL    PUTCN
SS3:    MOV     AX,[MSG]
        CMP     AX,[SHMSG]
        JZ      SS4
        MOV     AX,MSGC
        CALL    PUTPOS
        CALL    PUTMSG
SS4:    RET

SFULL:  MOV     [STFULL],0
        XOR     AX,AX
        CALL    PUTPOS
        CALL    INVON
        MOV     AL," "          ; " A:NAME.EXT*" in inverse, 17 columns
        CALL    PUTC
        MOV     AL,[DRVL]
        CALL    PUTC
        MOV     AL,":"
        CALL    PUTC
        MOV     SI,OFFSET FCB+1
        MOV     CX,8
        CALL    PUTNM
        MOV     SI,OFFSET FCB+9
        CMP     BYTE PTR [SI]," "
        JZ      SF1
        MOV     AL,"."
        CALL    PUTC
        MOV     CX,3
        CALL    PUTNM
SF1:    MOV     AX,[OPTR]       ; the column of the mark
        SUB     AX,OFFSET BUFFERS+OBOFF+6
        SUB     AX,[STCUT]
        MOV     [MODC],AL
        CALL    PUTMOD
        MOV     CL,17
        SUB     CL,[MODC]
        DEC     CL
        XOR     CH,CH
        MOV     AL," "
SF2:    CALL    PUTC
        LOOP    SF2
        CALL    INVOFF
        MOV     SI,OFFSET MLINE
        CALL    PUTS
        CALL    PUTLN
        MOV     SI,OFFSET MCOL
        CALL    PUTS
        MOV     AX,[CCOL]
        INC     AX
        CALL    PUTCN
        MOV     AL," "
        CALL    PUTC
        JMP     SHORT PUTMSG

STCUT   DW      0               ; bytes in OBUF before this status line

PUTMOD: MOV     AL,[MODIF]
        MOV     [SHMOD],AL
        OR      AL,AL
        MOV     AL," "
        JZ      PM1
        MOV     AL,"*"
PM1:    JMP     PUTC

PUTLN:  MOV     AX,[LINE]
        MOV     [SHLINE],AX
        JMP     SHORT PUTNUM
PUTCN:  MOV     AX,[CCOL]
        INC     AX
        MOV     [SHCOL],AX

; PUTNUM: AX in decimal, 5 columns
PUTNUM: MOV     BX,10
        XOR     CX,CX
PN1:    XOR     DX,DX
        DIV     BX
        PUSH    DX
        INC     CX
        OR      AX,AX
        JNZ     PN1
        MOV     DX,5
        SUB     DX,CX
PN2:    POP     AX
        ADD     AL,"0"
        CALL    PUTC
        LOOP    PN2
        MOV     CX,DX
        MOV     AL," "
PN3:    JCXZ    PNX
        CALL    PUTC
        LOOP    PN3
PNX:    RET

; PUTMSG: the message (or nothing), then ESC K
PUTMSG: MOV     SI,[MSG]
        MOV     [SHMSG],SI
        OR      SI,SI
        JZ      PMS1
        CALL    PUTS
PMS1:   JMP     PUTEOL

; PUTNM: up to CX characters of a name at SI, to the first space
PUTNM:  LODSB
        CMP     AL," "
        JZ      PNX
        CALL    PUTC
        LOOP    PUTNM
        RET

INVON:  MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"L"
        JMP     PUTC
INVOFF: MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"M"
        JMP     PUTC

; PLACE: the terminal's cursor on the editor's
PLACE:  MOV     AX,[CCOL]
        SUB     AX,[LEFT]
        MOV     BX,[W]
        DEC     BX
        CMP     AX,BX
        JBE     PL1
        MOV     AX,BX
PL1:    MOV     AH,BYTE PTR [CROW]
        INC     AH
; PUTPOS: ESC Y, row AH, column AL
PUTPOS: PUSH    AX
        MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"Y"
        CALL    PUTC
        POP     AX
        PUSH    AX
        MOV     AL,AH
        ADD     AL,32
        CALL    PUTC
        POP     AX
        ADD     AL,32
; PUTC: AL to the output buffer
PUTC:   PUSH    DI
        MOV     DI,[OPTR]
        STOSB
        MOV     [OPTR],DI
        POP     DI
        RET

; PUTS: the string at SI, to its 0
PUTS:   LODSB
        OR      AL,AL
        JZ      PSX
        CALL    PUTC
        JMP     PUTS
PSX:    RET

; FLUSHQ: send the output buffer if it is getting full; STCUT = what is
; left in it
FLUSHQ: MOV     AX,[OPTR]
        SUB     AX,OFFSET BUFFERS+OBOFF
        CMP     AX,OBSZ-128
        JB      FQ1
        CALL    FLUSH
        XOR     AX,AX
FQ1:    MOV     [STCUT],AX
        RET

; FLUSH: the output buffer to the terminal
FLUSH:  MOV     SI,OFFSET BUFFERS+OBOFF
        MOV     CX,[OPTR]
        MOV     [OPTR],SI
        SUB     CX,SI
        JCXZ    FLX
        MOV     AH,14
FL1:    LODSB
        INT     16
        LOOP    FL1
FLX:    RET

CLS:    MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"H"
        CALL    PUTC
        MOV     AL,KESC
        CALL    PUTC
        MOV     AL,"J"
        JMP     PUTC

; KEYRDY: ZF=0 if a key is waiting; GETKEY: AL = the next key
KEYRDY: MOV     AH,1
        INT     22
        RET
GETKEY: MOV     AH,0
        INT     22
        RET

; HELP: the keys, until a key is pressed
HELP:   CALL    CLS
        MOV     SI,OFFSET MHELP
HE1:    CALL    FLUSHQ
        LODSB
        OR      AL,AL
        JZ      HE2
        CALL    PUTC
        JMP     HE1
HE2:    CALL    FLUSH
        CALL    GETKEY
        JMP     REDRAW

BUFFERS LABEL   BYTE

CODE    ENDS
        END     BEGIN
