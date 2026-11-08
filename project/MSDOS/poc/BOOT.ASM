; BOOT.ASM - sector 0 of an MS-DOS disk for the FDD3000 (the IPL).
;
; The FDD3000 boot ROM restores drive A, reads sector 0 of track 0 to 3F00h
; and jumps here with interrupts off, SP = 3EFFh and the ROM still paged in
; at 0000h-07FFh.
;
; This reads the first directory sector (logical 5) to D000h. If its first
; entry is Z86.SYS starting at cluster 2 (FORMAT /S and mkfat put it there,
; contiguous), it reads that file - the 8086 interpreter and the BIOS - to
; D000h and jumps to D0FDh, where the interpreter's page holds JP COLD.
; COLD loads IO.SYS and MSDOS.SYS. A disk without the system gets
; "Non-System disk" on the terminal (the CBIOS link protocol, without
; timeouts) and stops.
;
; Logical sector s is track s / 18; in the track, logical sector e is
; sector ID 2e, or 2e - 17 from e = 9 on (2:1 interleave: 0 2 4 .. 16
; 1 3 .. 17), as for the rest of the disk (mkfat.chs, BIOS.ASM's SKEW). Polled throughout: no interrupts, 0038h is
; not used. A read error restores the drive and starts again, 8 times at
; most, then it stops (HALT).

SPT     EQU 18
FIRDIR  EQU 5                   ; first directory sector
FIRREC  EQU 13                  ; first data sector: cluster 2
IMAGE   EQU 0D000h
ENTRY   EQU 0D0FDh              ; JP COLD

        ORG 3F00h
IPL:    LD A,5Eh                ; drive A, side 0, ROM off, head loaded
        OUT (0E0h),A
IPL0:   LD A,01h                ; restore
        CALL CMD
        LD HL,IMAGE
        LD DE,FIRDIR            ; D = track, E = sector in it
        LD B,1
        CALL LOAD
        LD HL,IMAGE             ; entry 0: Z86.SYS, cluster 2?
        LD DE,SYSNAM
        LD B,11
CK1:    LD A,(DE)
        CP (HL)
        JR NZ,NOSYS
        INC HL
        INC DE
        DJNZ CK1
        LD HL,(IMAGE+26)
        DEC HL
        DEC HL
        LD A,H
        OR L
        JR NZ,NOSYS
        LD HL,(IMAGE+28)        ; size -> sectors
        LD A,L
        OR A
        LD A,H
        JR Z,CK2
        INC A
CK2:    LD B,A                  ; z86.bootcode: it fits below FF00h
        LD HL,IMAGE
        LD DE,FIRREC
        CALL LOAD
        JP ENTRY

; LOAD: B sectors from track D, sector E (logical, in the track) to HL
LOAD:   PUSH BC
        PUSH DE
        LD A,E                  ; sector ID: 2e, or 2e - 17
        ADD A,A
        CP SPT
        JR C,LD0
        SUB SPT-1
LD0:    OUT (0C2h),A
        LD BC,00C3h
        LD A,80h                ; read sector
        OUT (0C0h),A
        LD A,6                  ; let the FDC raise BUSY
LD1:    DEC A
        JR NZ,LD1
LD2:    IN A,(2Fh)              ; bit 7 = DRQ
        RLA
        JR C,LD3
        IN A,(0C0h)
        RRA
        JR C,LD2
        JR ERR                  ; ended without data
LD3:    INI
        JR NZ,LD2
LD4:    IN A,(0C0h)
        RRA
        JR C,LD4
        IN A,(0C0h)
        AND 1Ch                 ; not found, CRC, lost data
        JR NZ,ERR
        POP DE
        POP BC
        INC E
        LD A,E
        CP SPT
        JR NZ,LD5
        LD E,0
        INC D
        LD A,51h                ; step in
        CALL CMD
LD5:    DJNZ LOAD
        RET

ERR:    LD SP,3EFFh
        LD HL,TRIES
        DEC (HL)
        JR NZ,IPL0
        HALT                    ; interrupts are off: stop here

; CMD: type I command A, polled until not BUSY
CMD:    OUT (0C0h),A
        PUSH BC
        LD B,12h
CMD1:   DJNZ CMD1
        POP BC
CMD2:   IN A,(0C0h)
        RRA
        JR C,CMD2
        RET

; "Non-System disk": each character as CBIOS A1.1 sends it (0Ah, then
; the low and the high nibble, each echoed by the terminal, then 50h)
NOSYS:  LD HL,NSMSG
NS1:    LD E,(HL)
        INC E
        DEC E
        JR Z,NS4
NS2:    LD A,0Ah                ; ask to send
        OUT (2Fh),A
        IN A,(2Fh)
        AND 5Fh
        CP 0Fh
        JR NZ,NS2
        LD A,E
        AND 0Fh
        OR 10h
        CALL NSPUT
        LD A,E
        RRCA
        RRCA
        RRCA
        RRCA
        AND 0Fh
        OR 40h
        CALL NSPUT
        LD A,50h
        OUT (2Fh),A
        INC HL
        JR NS1
NSPUT:  OUT (2Fh),A
        LD D,A
NSP1:   IN A,(2Fh)
        AND 5Fh
        CP D
        JR NZ,NSP1
        RET
NS4:    HALT

SYSNAM: DB 'Z86     SYS'
NSMSG:  DB 13,10,'Non-System disk',13,10,0
TRIES:  DB 8
ENDIPL:
        END
