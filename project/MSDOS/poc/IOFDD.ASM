; I/O system for MS-DOS 1.25 on the Timex FDD3000 (8086 interpreter).
;
; The FDD3000 has a Z80, so this 8086 code runs on an interpreter. Each
; device entry is a BIOS trap: opcode 0FH (POP CS, unused on a real 8086)
; followed by a function number. The interpreter does the function in
; native code (console over the 2FH link to the TT3000 / TC3256 / TC2068
; terminal, sectors through the WD177x) and the following RETF returns
; to MS-DOS.
;
; The boot loader (COLD in BIOS.ASM) puts this file at 0040:0000 and
; MSDOS.SYS at DOSSEG:0000, then jumps to 0040:0000. Both are hidden files
; on the disk, after Z86.SYS (the Z80 interpreter and BIOS).

BIOSSEG EQU     40H
DOSSEG  EQU     60H             ; this file must stay below 512 bytes

ENTRY   MACRO   N
        DB      0FH,N,0CBH      ; TRAP N / RETF
        ENDM

CODE    SEGMENT
        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE
        ORG     0

        JMP     INIT
        ENTRY   1               ; STATUS  ZF=1 nothing; else ZF=0, AL=char
        ENTRY   2               ; INP     AL=char (waits)
        ENTRY   3               ; OUTP    AL=char
        ENTRY   4               ; PRINT   AL=char
        ENTRY   5               ; AUXIN
        ENTRY   6               ; AUXOUT
        ENTRY   7               ; READ    AL=drive DS:BX=buffer CX=count DX=sector
        ENTRY   8               ; WRITE   same; CF=1 on error, AL=code, CX=left
        ENTRY   9               ; DSKCHG  AH=1 not changed, 0 don't know, -1 changed
        ENTRY   10              ; SETDATE AX=day count
        ENTRY   11              ; SETTIME CH=hour CL=min DH=sec DL=1/100
        ENTRY   12              ; GETTIME AX=days, CX, DX as SETTIME
        ENTRY   13              ; FLUSH   clear console input
        ENTRY   14              ; MAPDEV

INIT:
        CLI
        XOR     BP,BP           ; Stack just below the I/O system
        MOV     SS,BP
        MOV     SP,BIOSSEG*16
        PUSH    CS
        POP     DS
        STI
;
; Minimal IBM PC ROM BIOS for programs written for PC-DOS (DEBUG, CHKDSK...):
; INT 10H teletype, 11H equipment, 12H memory size, 14H serial, 16H
; keyboard, 17H printer, 1AH clock tick. Each vector points to TRAP n / RETF 2,
; which returns with the flags the trap set.
;
        MOV     ES,BP
        MOV     SI,OFFSET ROMTAB
        MOV     CX,7
SETROM: LODSB                   ; Interrupt number
        XOR     AH,AH
        SHL     AX,1
        SHL     AX,1
        MOV     DI,AX
        LODSW                   ; Handler offset
        STOSW
        MOV     AX,CS
        STOSW
        LOOP    SETROM
        MOV     SI,OFFSET INITTAB
        MOV     DX,[MEMTOP]     ; End of RAM in paragraphs (1 = scan)
        CALL    DWORD PTR [DOSENT]
;
; MS-DOS returns with DS = segment for the first program. Load COMMAND.COM
; there with function calls, as the SCP I/O system does.
;
        MOV     DX,100H
        MOV     AH,26           ; Set DMA address
        INT     33
        MOV     CX,DS:[6]       ; Size of segment
        MOV     BX,DS
        MOV     AX,CS
        MOV     DS,AX
        MOV     DX,OFFSET FCB
        MOV     AH,15           ; Open COMMAND.COM
        INT     33
        OR      AL,AL
        JNZ     COMERR
        XOR     AX,AX
        MOV     WORD PTR [FCB+33],AX
        MOV     WORD PTR [FCB+35],AX
        INC     AX
        MOV     WORD PTR [FCB+14],AX    ; Record length 1
        MOV     AH,39           ; Block read
        INT     33
        JCXZ    COMERR
        TEST    AL,1
        JZ      COMERR
        MOV     DS,BX
        MOV     ES,BX
        MOV     SS,BX
        MOV     SP,5CH
        XOR     AX,AX
        PUSH    AX
        MOV     DX,80H
        MOV     AH,26
        INT     33
        PUSH    BX
        MOV     AX,100H
        PUSH    AX
        DB      0CBH            ; RETF to COMMAND

COMERR:
        MOV     DX,OFFSET BADCOM
        MOV     AH,9
        INT     33
STALL:  JMP     STALL

INT10:  DB      0FH,10H,0CAH,2,0        ; TRAP n / RETF 2
INT11:  DB      0FH,11H,0CAH,2,0
INT12:  DB      0FH,12H,0CAH,2,0
INT14:  DB      0FH,14H,0CAH,2,0
INT16:  DB      0FH,16H,0CAH,2,0
INT17:  DB      0FH,17H,0CAH,2,0
INT1A:  DB      0FH,1AH,0CAH,2,0

ROMTAB  DB      10H
        DW      OFFSET INT10
        DB      11H
        DW      OFFSET INT11
        DB      12H
        DW      OFFSET INT12
        DB      14H
        DW      OFFSET INT14
        DB      16H
        DW      OFFSET INT16
        DB      17H
        DW      OFFSET INT17
        DB      1AH
        DW      OFFSET INT1A

MEMTOP  DW      0D00H           ; 52 KB of 8086 memory (patched by the loader)
DOSENT  DW      0,DOSSEG

; Disk parameters. FDD3000 40-track single-sided disk, 18 sectors of
; 256 bytes per track: 720 sectors. The boot sector, then 2 FATs (MS-DOS
; makes them 2 sectors each), 64 directory entries, 1 KB clusters. The
; system is in files: Z86.SYS, IO.SYS and MSDOS.SYS.
INITTAB DB      2               ; Two drives, A: and B:
        DB      0
        DW      OFFSET DPT40
        DB      1
        DW      OFFSET DPT40
DPT40   DW      256             ; Sector size
        DB      4               ; Sectors per cluster
        DW      1               ; Reserved sectors: the boot sector
        DB      2               ; FATs
        DW      64              ; Directory entries
        DW      720             ; Total sectors

BADCOM  DB      13,10,"Error in loading Command Interpreter",13,10,"$"
FCB     DB      1,"COMMAND COM"
        DB      25 DUP (0)

CODE    ENDS
        END
