; FORMAT.COM for MS-DOS 1.25 on the Timex FDD3000.
;
;       FORMAT [d:] [/S]
;
; Formats the disk in drive d: (default: the current drive) in the FDD3000
; DOS format of mkfat.py: 40 tracks of 18 x 256-byte sectors, IDs 0-17,
; the boot sector, 2 FATs of 2 sectors, 64 directory entries, 1 KB
; clusters.
;
; Each track is written by the BIOS trap 1BH (FORMAT TRACK in BIOS.ASM:
; the WD177x write track) from a track image made here, then read back
; with INT 25H. The clusters of a track that does not read back are
; marked bad (FF7H); a bad track 0 (boot sector, FATs, directory) fails
; the format. Every disk gets the boot sector of the current drive: it
; boots the system or says "Non-System disk".
;
; /S copies the system from the current drive: the hidden files Z86.SYS
; (the Z80 interpreter and BIOS), IO.SYS and MSDOS.SYS, then COMMAND.COM.
; On the empty disk DOS gives them the first directory entries and the
; first clusters, contiguous, where the boot sector and COLD look for
; them. Everything is read before the new disk is asked for, so
; FORMAT A:/S works with one drive.
;
; INT 25H / 26H in MS-DOS 1.25 call the BIOS READ / WRITE directly: CF=1
; and AL = error code, the flags are left on the stack.

SPT     EQU     18
NTRACK  EQU     40
TRKLEN  EQU     32+SPT*332      ; track image bytes (the FDC pads with 4EH)
NDRIVE  EQU     2               ; IO.SYS has A: and B:
FATSEC  EQU     1               ; FAT 1 at 1-2, FAT 2 at 3-4
FATSECS EQU     2
DIRSEC  EQU     5
DIRSECS EQU     8
FIRREC  EQU     13
MAXCLUS EQU     177             ; clusters 2-177
NSYS    EQU     4               ; files copied by /S
SYSMAX  EQU     22528           ; their bytes

; buffers after the program, at TRACK
VEROFF  EQU     TRKLEN          ; one track read back (4.5 KB); the directory
FATOFF  EQU     VEROFF+SPT*256  ; the FAT (512 bytes)
BOOTOFF EQU     FATOFF+512      ; the boot sector
SYSOFF  EQU     BOOTOFF+256     ; the /S files, one after the other
BUFEND  EQU     SYSOFF+SYSMAX

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     100H

BEGIN:  JMP     START

DRIVE   DB      0               ; 0 = A:
SRCDRV  DB      0               ; the current drive: the system comes from it
SYSFLG  DB      0               ; 1: /S
TRK     DB      0
SYSCL   DW      0               ; clusters of the /S files

; /S files: name, attribute, then size and address in memory (GETSYS)
SYSTAB  DB      "Z86     SYS",6
        DW      0,0
        DB      "IO      SYS",6
        DW      0,0
        DB      "MSDOS   SYS",6
        DW      0,0
        DB      "COMMAND COM",0
        DW      0,0
SYSENT  EQU     16              ; bytes per entry

; extended FCB: FFH, 5 x 0, attribute, then the FCB (drive, name, ...)
XFCB    DB      0FFH,0,0,0,0,0,0
FCB     DB      0,"           "
        DB      25 DUP (0)

NUMBUF  DB      "         $"

INSMSG  DB      13,10,"Insert new diskette for drive "
DRVLET  DB      "A:",13,10
        DB      "and strike any key when ready$"
FMTMSG  DB      13,10,13,10,"Formatting...$"
DONMSG  DB      "Format complete",13,10,"$"
SYSMSG  DB      "System transferred",13,10,"$"
TOTMSG  DB      " bytes total disk space",13,10,"$"
USEMSG  DB      " bytes used by system",13,10,"$"
BADMSG  DB      " bytes in bad sectors",13,10,"$"
AVLMSG  DB      " bytes available on disk",13,10,"$"
AGNMSG  DB      13,10,"Format another (Y/N)?$"
CRLF    DB      13,10,"$"
WPMSG   DB      13,10,"Write protect error",13,10,"$"
NRMSG   DB      13,10,"Drive not ready",13,10,"$"
FFMSG   DB      13,10,"Format failure",13,10,"$"
DRVMSG  DB      "Invalid drive specification",13,10,"$"
MEMMSG  DB      "Insufficient memory",13,10,"$"
NOSMSG  DB      "No system on default drive",13,10,"$"
NOBMSG  DB      "Cannot read the boot sector of the default drive",13,10,"$"
SWEMSG  DB      13,10,"Disk error writing system",13,10,"$"

START:
        CMP     AL,0FFH         ; DOS: invalid drive in the first argument
        JZ      BADDRV
        CMP     WORD PTR DS:[6],OFFSET TRACK+BUFEND+256
        JB      NOMEM
        MOV     BL,DS:[5CH]     ; 0 = current drive, else drive + 1
        MOV     AH,25           ; current drive
        INT     33
        MOV     [SRCDRV],AL
        DEC     BL
        JNS     HAVDRV
        MOV     BL,AL
HAVDRV: CMP     BL,NDRIVE
        JAE     BADDRV
        MOV     [DRIVE],BL
        ADD     BL,"A"
        MOV     [DRVLET],BL
;
; /S anywhere in the command tail
;
        MOV     SI,81H
        MOV     CL,DS:[80H]
        XOR     CH,CH
SCAN:   JCXZ    SCANX
        LODSB
        DEC     CX
        CMP     AL,"/"
        JNZ     SCAN
        JCXZ    SCANX
        LODSB
        DEC     CX
        AND     AL,0DFH
        CMP     AL,"S"
        JNZ     SCAN
        MOV     [SYSFLG],1
        JMP     SCAN
SCANX:
        CALL    MKTRACK
        MOV     AL,[SRCDRV]     ; the boot sector of the current drive
        MOV     BX,OFFSET TRACK+BOOTOFF
        MOV     CX,1
        XOR     DX,DX
        INT     37
        POP     BP              ; the flags INT 25H left
        MOV     DX,OFFSET NOBMSG
        JC      QUITM
        CMP     [SYSFLG],0
        JZ      ASK
        CALL    GETSYS
        JNC     ASK
        MOV     DX,OFFSET NOSMSG
        JMP     SHORT QUITM

BADDRV: MOV     DX,OFFSET DRVMSG
        JMP     SHORT QUITM
NOMEM:  MOV     DX,OFFSET MEMMSG
QUITM:  MOV     AH,9
        INT     33
        INT     32

;
; One disk
;
ASK:    MOV     DX,OFFSET INSMSG
        MOV     AH,9
        INT     33
        MOV     AX,0C08H        ; flush the keyboard, then a key, no echo
        INT     33
        MOV     AH,13           ; disk reset
        INT     33
        MOV     DX,OFFSET FMTMSG
        MOV     AH,9
        INT     33
        CALL    FORMAT
        JC      ANOTHER
        MOV     DX,OFFSET DONMSG
        MOV     AH,9
        INT     33
        CALL    PUTSYS
        JC      ANOTHER
        CALL    REPORT
ANOTHER:
        MOV     AH,13
        INT     33
        MOV     DX,OFFSET AGNMSG
        MOV     AH,9
        INT     33
        MOV     AX,0C01H        ; flush, then a key with echo
        INT     33
        PUSH    AX
        MOV     DX,OFFSET CRLF
        MOV     AH,9
        INT     33
        POP     AX
        AND     AL,0DFH
        CMP     AL,"Y"
        JZ      ASK
        INT     32

;
; FORMAT: format and verify the 40 tracks, write the boot sector, the
; FATs and the directory. CF=1: failed, message printed.
;
FORMAT: MOV     DI,OFFSET TRACK+FATOFF
        XOR     AX,AX
        MOV     CX,256
        REP     STOSW
        MOV     WORD PTR [TRACK+FATOFF],0FFFEH  ; media FEH, then FFFH
        MOV     BYTE PTR [TRACK+FATOFF+2],0FFH
        MOV     [TRK],0
FLOOP:  MOV     DI,OFFSET TRACK+48      ; the C byte of each ID field
        MOV     CX,SPT
        MOV     AL,[TRK]
SETC:   MOV     [DI],AL
        ADD     DI,332
        LOOP    SETC
        MOV     AL,[DRIVE]
        MOV     DL,[TRK]
        MOV     BX,OFFSET TRACK
        DB      0FH,1BH         ; BIOS trap: FORMAT TRACK
        JC      FMTERR
        MOV     AL,[TRK]        ; read it back
        MOV     CL,SPT
        MUL     CL
        MOV     DX,AX
        MOV     AL,[DRIVE]
        MOV     BX,OFFSET TRACK+VEROFF
        MOV     CX,SPT
        INT     37
        POP     BP
        JNC     TRKOK
        CMP     [TRK],0
        JZ      FFAIL
        CALL    MARKBAD
TRKOK:  INC     [TRK]
        CMP     [TRK],NTRACK
        JB      FLOOP
;
; boot sector, FAT twice, then the directory: zeros (00 ends a directory
; in 1.25)
;
        MOV     BX,OFFSET TRACK+BOOTOFF
        MOV     CX,1
        XOR     DX,DX
        CALL    WRSECS
        JC      FMTERR
        MOV     BX,OFFSET TRACK+FATOFF
        MOV     CX,FATSECS
        MOV     DX,FATSEC
        CALL    WRSECS
        JC      FMTERR
        MOV     BX,OFFSET TRACK+FATOFF
        MOV     CX,FATSECS
        MOV     DX,FATSEC+FATSECS
        CALL    WRSECS
        JC      FMTERR
        MOV     DI,OFFSET TRACK+VEROFF
        XOR     AX,AX
        MOV     CX,DIRSECS*128
        REP     STOSW
        MOV     BX,OFFSET TRACK+VEROFF
        MOV     CX,DIRSECS
        MOV     DX,DIRSEC
        CALL    WRSECS
        JC      FMTERR
        RET

; WRSECS: CX sectors from BX to sector DX of the new disk
WRSECS: MOV     AL,[DRIVE]
        INT     38
        POP     BP
        RET

FMTERR: MOV     DX,OFFSET WPMSG
        OR      AL,AL
        JZ      FMSG
        MOV     DX,OFFSET NRMSG
        CMP     AL,2
        JZ      FMSG
FFAIL:  MOV     DX,OFFSET FFMSG
FMSG:   MOV     AH,9
        INT     33
        STC
        RET

;
; MARKBAD: clusters with a sector on track TRK (1 or more) -> FF7H
;
MARKBAD:
        MOV     AL,[TRK]
        MOV     CL,SPT
        MUL     CL
        SUB     AX,FIRREC       ; first sector of the track, in the data area
        MOV     BX,AX
        ADD     AX,SPT-1        ; its last
        SHR     BX,1
        SHR     BX,1
        ADD     BX,2            ; first cluster
        SHR     AX,1
        SHR     AX,1
        ADD     AX,2            ; last cluster
MB1:    CMP     BX,MAXCLUS
        JA      MB2
        PUSH    AX
        MOV     DX,0FF7H
        CALL    SETFAT
        POP     AX
        INC     BX
        CMP     BX,AX
        JBE     MB1
MB2:    RET

; SETFAT: FAT entry BX = DX.  GETFAT: AX = FAT entry BX.
SETFAT: CALL    FATPTR
        MOV     AX,[SI]
        TEST    BX,1
        JNZ     SF1
        AND     AX,0F000H
        JMP     SHORT SF2
SF1:    AND     AX,000FH
        MOV     CL,4
        SHL     DX,CL
SF2:    OR      AX,DX
        MOV     [SI],AX
        RET

GETFAT: CALL    FATPTR
        MOV     AX,[SI]
        TEST    BX,1
        JZ      GF1
        MOV     CL,4
        SHR     AX,CL
GF1:    AND     AX,0FFFH
        RET

FATPTR: MOV     SI,BX
        SHR     SI,1
        ADD     SI,BX
        ADD     SI,OFFSET TRACK+FATOFF
        RET

;
; MKTRACK: the track image: 32 x 4EH, then 18 x (12 x 00, 3 x F5 (sync),
; FE C H R N F7 (ID, CRC), 22 x 4EH, 12 x 00, 3 x F5, FB, 256 x E5
; (data), F7, 16 x 4EH). Each F7 is 2 CRC bytes on the disk: 6044 bytes of
; a turn's 6250, so a drive 3% fast still fits it. C is set per track.
;
MKTRACK:
        CLD
        MOV     DI,OFFSET TRACK
        MOV     AL,4EH
        MOV     CX,32
        REP     STOSB
        XOR     BL,BL
MK1:    XOR     AL,AL
        MOV     CX,12
        REP     STOSB
        MOV     AL,0F5H
        MOV     CX,3
        REP     STOSB
        MOV     AL,0FEH
        STOSB
        XOR     AX,AX           ; C, H
        STOSW
        MOV     AL,BL           ; R: sector ID
        STOSB
        MOV     AL,1            ; N: 256 bytes
        STOSB
        MOV     AL,0F7H
        STOSB
        MOV     AL,4EH
        MOV     CX,22
        REP     STOSB
        XOR     AL,AL
        MOV     CX,12
        REP     STOSB
        MOV     AL,0F5H
        MOV     CX,3
        REP     STOSB
        MOV     AL,0FBH
        STOSB
        MOV     AL,0E5H
        MOV     CX,256
        REP     STOSB
        MOV     AL,0F7H
        STOSB
        MOV     AL,4EH
        MOV     CX,16
        REP     STOSB
        INC     BL
        CMP     BL,SPT
        JB      MK1
        RET

;
; SETFCB: XFCB for SYSTAB entry SI (name, attribute) on drive AL (0 =
; current, else drive + 1)
;
SETFCB: MOV     DI,OFFSET FCB
        STOSB
        MOV     CX,11
        REP     MOVSB
        LODSB
        MOV     [XFCB+6],AL
        XOR     AL,AL
        MOV     CX,25
        REP     STOSB
        MOV     WORD PTR [FCB+14],1     ; record length 1
        RET

;
; GETSYS: the /S files of the current drive into memory, one after the
; other from SYSOFF. CF=1: one is missing or they are too big.
;
GETSYS: MOV     BX,OFFSET SYSTAB
        MOV     DI,OFFSET TRACK+SYSOFF
GS1:    PUSH    DI
        PUSH    BX
        MOV     SI,BX
        XOR     AL,AL
        CALL    SETFCB
        MOV     DX,OFFSET XFCB
        MOV     AH,15           ; open
        INT     33
        POP     BX
        POP     DI
        OR      AL,AL
        JNZ     GSNO
        CMP     WORD PTR [FCB+18],0
        JNZ     GSNO
        MOV     AX,WORD PTR [FCB+16]    ; size
        MOV     [BX+12],AX
        MOV     [BX+14],DI
        ADD     AX,DI
        JC      GSNO
        CMP     AX,OFFSET TRACK+BUFEND
        JA      GSNO
        PUSH    AX
        PUSH    BX
        MOV     WORD PTR [FCB+14],1     ; record length 1
        MOV     WORD PTR [FCB+33],0
        MOV     WORD PTR [FCB+35],0
        MOV     DX,DI
        MOV     AH,26           ; DMA address
        INT     33
        MOV     CX,[BX+12]
        MOV     DX,OFFSET XFCB
        MOV     AH,39           ; random block read
        INT     33
        POP     BX
        POP     DI              ; where the next file goes
        CMP     CX,[BX+12]
        JNZ     GSNO
        ADD     BX,SYSENT
        CMP     BX,OFFSET SYSTAB+NSYS*SYSENT
        JB      GS1
        CLC
        RET
GSNO:   STC
        RET

;
; PUTSYS: with /S, create the files on the new disk, in SYSTAB's order.
; CF=1: failed, message printed.
;
PUTSYS: MOV     [SYSCL],0
        CMP     [SYSFLG],0
        JZ      PSX
        MOV     AH,13           ; disk reset: DOS reads the new FAT
        INT     33
        MOV     BX,OFFSET SYSTAB
PS1:    PUSH    BX
        MOV     SI,BX
        MOV     AL,[DRIVE]
        INC     AL
        CALL    SETFCB
        MOV     DX,OFFSET XFCB
        MOV     AH,22           ; create
        INT     33
        POP     BX
        OR      AL,AL
        JNZ     PSERR
        PUSH    BX
        MOV     WORD PTR [FCB+14],1
        MOV     WORD PTR [FCB+33],0
        MOV     WORD PTR [FCB+35],0
        MOV     DX,[BX+14]
        MOV     AH,26
        INT     33
        MOV     CX,[BX+12]
        MOV     DX,OFFSET XFCB
        MOV     AH,40           ; random block write
        INT     33
        OR      AL,AL
        JNZ     PSERRP
        MOV     DX,OFFSET XFCB
        MOV     AH,16           ; close
        INT     33
        OR      AL,AL
        JNZ     PSERRP
        POP     BX
        MOV     AX,[BX+12]      ; its clusters
        ADD     AX,1023
        MOV     CL,10
        SHR     AX,CL
        ADD     [SYSCL],AX
        ADD     BX,SYSENT
        CMP     BX,OFFSET SYSTAB+NSYS*SYSENT
        JB      PS1
        MOV     DX,OFFSET SYSMSG
        MOV     AH,9
        INT     33
PSX:    CLC
        RET
PSERRP: POP     BX
PSERR:  MOV     DX,OFFSET SWEMSG
        MOV     AH,9
        INT     33
        STC
        RET

;
; REPORT: total, system, bad and available bytes, as CHKDSK prints them
;
REPORT: MOV     DX,OFFSET CRLF
        MOV     AH,9
        INT     33
        MOV     AX,MAXCLUS-1
        CALL    KBYTES
        MOV     SI,OFFSET TOTMSG
        CALL    DNUMM
        MOV     AX,[SYSCL]
        OR      AX,AX
        JZ      RP1
        CALL    KBYTES
        MOV     SI,OFFSET USEMSG
        CALL    DNUMM
RP1:    XOR     BP,BP           ; bad clusters
        MOV     BX,2
RP2:    CALL    GETFAT
        CMP     AX,0FF7H
        JNZ     RP3
        INC     BP
RP3:    INC     BX
        CMP     BX,MAXCLUS
        JBE     RP2
        OR      BP,BP
        JZ      RP4
        MOV     AX,BP
        CALL    KBYTES
        MOV     SI,OFFSET BADMSG
        CALL    DNUMM
RP4:    MOV     AX,MAXCLUS-1
        SUB     AX,[SYSCL]
        SUB     AX,BP
        CALL    KBYTES
        MOV     SI,OFFSET AVLMSG
        JMP     DNUMM

; KBYTES: DX:AX = AX clusters x 1024
KBYTES: MOV     DX,1024
        MUL     DX
        RET

; DNUMM: DX:AX in decimal right-aligned in 9 columns, then message SI
DNUMM:  PUSH    SI
        MOV     DI,OFFSET NUMBUF
        PUSH    AX
        MOV     AL," "
        MOV     CX,9
        REP     STOSB
        POP     AX
        MOV     BX,10
DN1:    MOV     CX,AX
        MOV     AX,DX
        XOR     DX,DX
        DIV     BX              ; high word / 10
        XCHG    AX,CX
        DIV     BX              ; (remainder, low word) / 10
        ADD     DL,"0"
        DEC     DI
        MOV     [DI],DL
        MOV     DX,CX
        MOV     CX,AX
        OR      CX,DX
        JNZ     DN1
        MOV     DX,OFFSET NUMBUF
        MOV     AH,9
        INT     33
        POP     DX
        MOV     AH,9
        INT     33
        RET

TRACK   LABEL   BYTE

CODE    ENDS
        END     BEGIN           ; at 100H: EXE2BIN makes a .COM
