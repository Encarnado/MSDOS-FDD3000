;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  5/7
;  FORMAT.COM - the disk formatter (8086, 1 628 bytes, .COM at 0100h)
;==============================================================================
;
;  ROLE.  `FORMAT [d:] [/S]` lays down the FDD3000 DOS format of mkfat.py
;  on drive d: (default: the CURRENT drive): 40 tracks of 18 x 256-byte
;  sectors, IDs 0-17, then boot sector, two FATs (FAT12, media FEh) and an
;  empty 64-entry directory.  /S then copies the system - Z86.SYS, IO.SYS,
;  MSDOS.SYS (hidden + system, attribute 06h) and COMMAND.COM - from the
;  current drive.  Each track is built here as a WD177x Write Track image
;  (MKTRACK), written by the Z80 BIOS through trap 1Bh (z86sys.asm T_FMT),
;  and read back with INT 25h; a track that fails the read-back has its
;  clusters marked bad (FF7h).  Everything it needs from the source disk
;  (boot sector, the four system files) is read BEFORE the new disk is
;  asked for, so `FORMAT A:/S` works with one drive.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM loads it at CS:0100h (an ordinary .COM)
;       ->  INT 21h for console, FCB files and disk reset
;       ->  INT 25h / 26h  = IO.SYS READ / WRITE (TRAP 7 / TRAP 8, RETF)
;       ->  TRAP 1Bh       = Z86.SYS T_FMT, Write Track on the WD177x
;  The disks it makes are booted by boot.asm (volume 1), which loads
;  Z86.SYS from cluster 2 without the FAT, and by Z86.SYS COLD, which
;  loads directory entries 1 and 2 (IO.SYS, MSDOS.SYS) the same way.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/format_findings.md)
;   - Track budget, checked: the image is 32 + 18 x 332 = 6 008 bytes; each
;     of the 36 F7h bytes becomes 2 CRC bytes on the disk, so 6 044 bytes
;     go down of the 6 250 a 300 rpm MFM turn holds (OVERVIEW 2.5).  The
;     206-byte slack (3.3%) is filled with 4Eh by T_FMT until the index
;     pulse.  No index address mark (F6h F6h F6h FCh) is written: gap 1
;     is bare 4Eh.  Gap 3 is 16 bytes, far under IBM's 54 for 256-byte
;     MFM sectors.  The write-track path (image, trap 1Bh, /S) is
;     checked on the emulator against the Python BIOS; not yet run on a
;     real FDD3000 - notes/hardware_run.md (provisional).
;   - The 2:1 interleave is NOT in the image: IDs go 0..17 in physical
;     order.  It lives in Z86.SYS's SKEW (logical e -> ID 2e / 2e-17), so
;     logically adjacent sectors sit two slots apart.  The resulting
;     layout (IDs, skew, FAT/directory places) is the one mkfat.py wrote
;     on the disk that booted on a real FDD3000 on 2026-11-07
;     (notes/hardware_run.md): indirect support for the layout, not for
;     the write-track path that produces it here.
;   - /S does not check contiguity.  A bad track 1-3 lands in Z86.SYS's
;     clusters (2-10); DOS then allocates around the FF7h entries and the
;     disk will not boot (boot.asm and COLD read without the FAT), yet
;     "System transferred" is printed (verified by code; no test makes
;     a bad track inside the system area).
;   - SETFCB's record-length write is dead: FCB open / create reset it to
;     128 (MSDOS.LST 03E1h / 0405h), so GETSYS and PUTSYS set it again.
;   - `JMP DNUMM` at the end of REPORT is MASM's forward-reference jump:
;     3 bytes reserved, assembled short, padded with NOP.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/FORMAT.COM with
;  `nasm -O0 -f bin` (tools/roundtrip.sh format).  Every address agrees
;  with the MASM listing ../symbols/x86/FORMAT.LST (TRACK = 075Ch, the
;  file's end).  Behaviour checked by project/MSDOS/poc/test_fdd86.py:
;  FORMAT B:/S on both BIOSes (same screens, same disk, all 40 tracks with
;  IDs 0-17, the disk boots), FORMAT B: over a used disk, a bad track 10
;  (6 clusters, 6144 bytes bad, CHKDSK agrees), a write-protected disk,
;  and FORMAT A:/S with one drive and a swapped disk.  The drive in those
;  tests has no rotation, so gaps and timing are not covered by them.
;  FORMAT was checked on the emulator against the Python BIOS; not yet
;  run on a real FDD3000 - notes/hardware_run.md (the 2026-11-07 hardware
;  run covered boot, console tools, EDIT, CPM and serial, not FORMAT).
;
;  NOTATION.  This is NASM spelling of MASM-built bytes; with -O0 the
;  explicit `short` / `byte` / `word` keywords fix every encoding.
;  `TRAP nn` = db 0Fh,nn - the interpreter's BIOS trap (POP CS on a real
;  8086).  The `_d` macros (`xor_d ax,ax`, `mov_d dx,ax` ...) are reg,reg
;  instructions in MASM's encoding (direction bit set, opcode +2): same
;  operation as the plain mnemonic, different bytes.
;
;  FILE:    FORMAT.COM, 1 628 bytes
;  MD5:     5defa452c475a2482a9d8ef67af1957e
;  SHA256:  b8351e19d30c58d1ff5f6bbdea5e6016a26c5cfd60351202c11fb405cd552508
;  SOURCE:  project/MSDOS/poc/FORMAT.ASM (MASM, EXE2BIN)
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  The Write
;  Track loop on the Z80 side is CP/M FORMAT 2.0's.  Disassembly and
;  annotation in the style of "The Complete TMX Portugal ROM
;  Disassemblies", LoadZX Museum, 2026.
;==============================================================================
; assemble: nasm -O0 -f bin
%macro TRAP 1
	db	0Fh, %1	; BIOS trap: POP CS on an 8086, a Z80 call here
%endmacro
; _d forms: reg,reg with the direction bit set - MASM's encoding of the
; same operation (NASM would emit the r/m,reg form).  xor_d bp,bp = 33 ED.
%define R16_ax 0
%define R16_cx 1
%define R16_dx 2
%define R16_bx 3
%define R16_sp 4
%define R16_bp 5
%define R16_si 6
%define R16_di 7
%define R8_al 0
%define R8_cl 1
%define R8_dl 2
%define R8_bl 3
%define R8_ah 4
%define R8_ch 5
%define R8_dh 6
%define R8_bh 7
%macro _D 3
%ifdef R16_%2
	db	%1+3, 0C0h+(R16_%2<<3)+R16_%3
%else
	db	%1+2, 0C0h+(R8_%2<<3)+R8_%3
%endif
%endmacro
%macro add_d 2
	_D 00h, %1, %2
%endmacro
%macro or_d 2
	_D 08h, %1, %2
%endmacro
%macro adc_d 2
	_D 10h, %1, %2
%endmacro
%macro sbb_d 2
	_D 18h, %1, %2
%endmacro
%macro and_d 2
	_D 20h, %1, %2
%endmacro
%macro sub_d 2
	_D 28h, %1, %2
%endmacro
%macro xor_d 2
	_D 30h, %1, %2
%endmacro
%macro cmp_d 2
	_D 38h, %1, %2
%endmacro
%macro mov_d 2
	_D 88h, %1, %2
%endmacro
	org	0100h
bits 16

; =====================================================================
;                    DISK GEOMETRY (the author's equates)
; =====================================================================
;
;   logical 0       boot sector (copied from the current drive)
;   logical 1-2     FAT 1           logical 3-4   FAT 2
;   logical 5-12    directory, 64 entries of 32 bytes
;   logical 13-716  clusters 2-177, 4 sectors (1 KB) each
;   logical 717-719 three sectors no cluster covers
;
SPT equ 18		; sectors per track
NTRACK equ 40		; tracks, single-sided
TRKLEN equ 32+SPT*332	; 6008: the Write Track image (gap 1 + 18 sectors of
			;   332); T_FMT feeds 4Eh after it until the index
NDRIVE equ 2		; IO.SYS has A: and B: (T_FMT itself accepts 0-3)
FATSEC equ 1		; FAT 1 at 1-2, FAT 2 at 3-4
FATSECS equ 2		; sectors per FAT
DIRSEC equ 5		; first directory sector
DIRSECS equ 8		; directory sectors (8 x 8 entries)
FIRREC equ 13		; logical sector of cluster 2
MAXCLUS equ 177		; highest cluster: 2-177 = 176 clusters, 180 224 bytes
NSYS equ 4		; files copied by /S
SYSMAX equ 22528	; room for them, in bytes (22 KB)

; ---- buffers after the program, offsets from the label TRACK (075Ch) ----
;   TRACK+0000h  075Ch  the Write Track image          6008 bytes
;   TRACK+VEROFF 1ED4h  one track read back (4.5 KB); later the directory
;   TRACK+FATOFF 30D4h  the FAT                         512 bytes
;   TRACK+BOOTOFF 32D4h the boot sector                 256 bytes
;   TRACK+SYSOFF 33D4h  the /S files, back to back      up to SYSMAX
;   TRACK+BUFEND 8BD4h  end; +256 of stack = 8CD4h, the memory test
VEROFF equ TRKLEN	; one track read back (4.5 KB); the directory
FATOFF equ VEROFF+SPT*256	; the FAT (512 bytes)
BOOTOFF equ FATOFF+512	; the boot sector
SYSOFF equ BOOTOFF+256	; the /S files, one after the other
BUFEND equ SYSOFF+SYSMAX	; end of all buffers

; ---- program segment prefix (DOS 1.25) ----
PSP_MEMSIZE equ 06h	; word: bytes available in the program's segment
PSP_FCB1 equ 5Ch	; first FCB: drive byte, 0 = current, else drive + 1
PSP_TAIL equ 80h	; command tail: length byte, then the text at 81h

; ---- the Z80 BIOS trap this program issues (z86sys.asm TTAB) ----
TRAP_FMTTRK equ 1Bh	; T_FMT, FORMAT TRACK: AL = drive, DL = track,
			;   DS:BX = image; CF=1, AL = 0 WP / 2 not ready /
			;   8 track > 39 / 0Ch image past memory


; =====================================================================
; BEGIN - .COM entry; variables follow the jump
; =====================================================================
BEGIN:
	jmp START	; over the data (near: E9, as MASM built it)

DRIVE:
	db 0		; drive to format, 0 = A:
SRCDRV:
	db 0		; the current drive: boot sector and system come from it
SYSFLG:
	db 0		; 1: /S was given
TRK:
	db 0		; track being formatted, 0-39
SYSCL:
	dw 0		; clusters the /S files took, for REPORT

; ---------------------------------------------------------------------
; SYSTAB - the /S files, 16 bytes each (SYSENT):
;   +0  11-byte 8+3 directory name    +11  attribute for the extended FCB
;   +12 size in bytes (GETSYS)        +14  where it sits in memory (GETSYS)
; Order matters: on the empty disk DOS hands out directory entries and
; clusters in creation order, so Z86.SYS gets entry 0 / cluster 2
; (boot.asm's precondition), IO.SYS entry 1 and MSDOS.SYS entry 2 (COLD's).
; ---------------------------------------------------------------------
SYSTAB:
	db "Z86     SYS",6	; the interpreter + Z80 BIOS: hidden + system
	dw 0,0			;   size, address
	db "IO      SYS",6	; the 8086 BIOS: hidden + system
	dw 0,0
	db "MSDOS   SYS",6	; the DOS kernel: hidden + system
	dw 0,0
	db "COMMAND COM",0	; the shell: a normal file
	dw 0,0
SYSENT equ 16	; bytes per entry

; ---------------------------------------------------------------------
; XFCB / FCB - one extended FCB, reused for every file.  FFh flags it as
; extended, 5 reserved bytes, the attribute at XFCB+6 (DOS's MOVNAME takes
; it as the search / create attribute), then the normal 37-byte FCB:
;   FCB+0 drive  +1 name (11)  +12 extent  +14 record size  +16 file size
;   (dword)  +20 date ... +32 current record  +33 random record (dword).
; ---------------------------------------------------------------------
XFCB:
	db 0FFH,0,0,0,0,0,0	; extended-FCB flag, reserved, attribute
FCB:
	db 0,"           "	; drive, name: filled by SETFCB
	times 25 db 0		; extent .. random record

NUMBUF:
	db "         $"	; DNUMM's 9 right-aligned digit columns, $-ended

; ---- messages, all $-terminated for INT 21h AH=09h ----
INSMSG:
	db 13,10,"Insert new diskette for drive "
DRVLET:
	db "A:",13,10			; the letter is patched by START
	db "and strike any key when ready$"
FMTMSG:
	db 13,10,13,10,"Formatting...$"
DONMSG:
	db "Format complete",13,10,"$"	; follows "Formatting..." on its line
SYSMSG:
	db "System transferred",13,10,"$"
TOTMSG:
	db " bytes total disk space",13,10,"$"	; REPORT's four lines,
USEMSG:
	db " bytes used by system",13,10,"$"	;   each after a 9-column
BADMSG:
	db " bytes in bad sectors",13,10,"$"	;   number (DNUMM)
AVLMSG:
	db " bytes available on disk",13,10,"$"
AGNMSG:
	db 13,10,"Format another (Y/N)?$"
CRLF:
	db 13,10,"$"
WPMSG:
	db 13,10,"Write protect error",13,10,"$"	; error code 0
NRMSG:
	db 13,10,"Drive not ready",13,10,"$"		; error code 2
FFMSG:
	db 13,10,"Format failure",13,10,"$"		; anything else
DRVMSG:
	db "Invalid drive specification",13,10,"$"
MEMMSG:
	db "Insufficient memory",13,10,"$"
NOSMSG:
	db "No system on default drive",13,10,"$"
NOBMSG:
	db "Cannot read the boot sector of the default drive",13,10,"$"
SWEMSG:
	db 13,10,"Disk error writing system",13,10,"$"

; =====================================================================
; START - check the arguments and memory, collect the source material
; ---------------------------------------------------------------------
; Entry:  from COMMAND.COM; AL = FFh if the first argument's drive is
;         invalid, PSP at CS:0, DS = ES = CS.
; Exit:   to ASK, or INT 20h after a message.
; DOS:    AH=19h current drive, AH=09h print string, INT 25h absolute read.
;
; Order: drive -> /S switch -> the track image (built once, only C changes
; per track) -> the source boot sector -> with /S the four files.  All of
; it happens before the user is asked for the new disk.
; =====================================================================
START:
	cmp al,0xff	; DOS: invalid drive in the first argument
	jz short BADDRV	; invalid: "Invalid drive specification"
	cmp word [PSP_MEMSIZE],TRACK+BUFEND+256	; buffers + 256 of stack
	jc short NOMEM	;   must fit the segment (36 052 bytes)
	mov bl,[PSP_FCB1]	; 0 = current drive, else drive + 1
	mov ah,0x19	; AH=19h current drive -> AL
	int byte 0x21	; (AL = 0 for A:)
	mov [SRCDRV],al	; the system and boot sector come from it
	dec bl		; 0-based target; -1 if none was named ...
	jns short HAVDRV	; a drive was named: use it
	mov_d bl,al	; ... then format the current drive itself
HAVDRV:
	cmp bl,NDRIVE	; only A: and B: exist in IO.SYS
	jnc short BADDRV	; C: or beyond: refused
	mov [DRIVE],bl	; the target, 0-based
	add bl,'A'	; its letter into "...for drive A:"
	mov [DRVLET],bl	; patched into INSMSG
;
; /S anywhere in the command tail
;
	mov si,PSP_TAIL+1	; the tail text
	mov cl,[PSP_TAIL]	; its length
	xor_d ch,ch	; CX = characters left
SCAN:
	jcxz short SCANX	; tail exhausted
	lodsb	; next tail character
	dec cx	; one fewer left
	cmp al,'/'	; a switch?
	jnz short SCAN	; not a switch: keep scanning
	jcxz short SCANX	; "/" as the last character: nothing follows
	lodsb		; the switch letter (consumed even if not S,
	dec cx		;   so "//S" is missed - harmless)
	and al,0xdf	; fold to upper case
	cmp al,'S'	; /S?
	jnz short SCAN	; any other switch is ignored
	mov byte [SYSFLG],0x1	; /S
	jmp short SCAN	; keep scanning (a later /S is harmless)
SCANX:
	call MKTRACK	; the image, once for all tracks and all disks
	mov al,[SRCDRV]	; the boot sector of the current drive
	mov bx,TRACK+BOOTOFF	;   to its buffer: every new disk gets it
	mov cx,0x1	; one sector ...
	xor_d dx,dx	; ... logical 0
	int byte 0x25	; INT 25h: IO.SYS READ (TRAP 7, RETF)
	pop bp		; drop the flags INT 25h leaves on the stack
	mov dx,NOBMSG	; (message ready for the failure case)
	jc short QUITM	; unreadable: give up before touching anything
	cmp byte [SYSFLG],0x0	; /S asked for?
	jz short ASK	; no /S: nothing more to fetch
	call GETSYS	; the four files into memory
	jnc short ASK	; all four read: on to the prompt
	mov dx,NOSMSG	; missing, unreadable or too big
	jmp short QUITM	; print it and exit

BADDRV:
	mov dx,DRVMSG	; "Invalid drive specification"
	jmp short QUITM	; print it and exit
NOMEM:
	mov dx,MEMMSG	; "Insufficient memory"
QUITM:
	mov ah,0x9	; AH=09h print the message at DX
	int byte 0x21	; AH=09h print
	int byte 0x20	; and end the program

; =====================================================================
; ASK / ANOTHER - one disk per pass; "Format another (Y/N)?" loops here
; ---------------------------------------------------------------------
; DOS:    AH=09h print, AX=0C08h flush + read key (no echo), AX=0C01h
;         flush + read key (echo), AH=0Dh disk reset, INT 20h exit.
; The buffers survive the loop: the image (C is rewritten per track),
; the source boot sector and the /S files are not fetched again, so every
; disk of the session gets the same system.
; =====================================================================
ASK:
	mov dx,INSMSG	; "Insert new diskette for drive X:" ...
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (the prompt names the drive)
	mov ax,0xc08	; AH=0Ch: flush typed-ahead keys, then AL=08h:
	int byte 0x21	;   wait for a key, no echo
	mov ah,0xd	; AH=0Dh disk reset: DOS forgets the old disk
	int byte 0x21	; (the key itself is discarded)
	mov dx,FMTMSG	; "Formatting..."
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (no CR LF: DONMSG follows on the line)
	call FORMAT	; 40 tracks, boot sector, FATs, directory
	jc short ANOTHER	; failed: message already printed
	mov dx,DONMSG	; "Format complete"
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (ends with CR LF)
	call PUTSYS	; /S: write the system (else just CF=0)
	jc short ANOTHER	; failed: message already printed
	call REPORT	; the byte counts
ANOTHER:
	mov ah,0xd	; disk reset again before the prompt
	int byte 0x21	; flush buffers, forget this disk
	mov dx,AGNMSG	; "Format another (Y/N)?"
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (the cursor stays after "?")
	mov ax,0xc01	; flush, then a key with echo
	int byte 0x21	; AL = the key, echoed
	push ax		; the key, across the print
	mov dx,CRLF	; end the prompt line
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (CR LF)
	pop ax	; the key again
	and al,0xdf	; y or Y ...
	cmp al,'Y'	; yes?
	jz short ASK	; ... another disk
	int byte 0x20	; anything else: done

; =====================================================================
; FORMAT - format and verify the 40 tracks, then write the system area
; ---------------------------------------------------------------------
; Entry:  image built (MKTRACK), [DRIVE] set.
; Exit:   CF=0 done; CF=1 failed, message printed (via FMTERR / FFAIL).
; Corrupts: AX, BX, CX, DX, SI, DI, BP.  Caller: ASK.
; Traps:  TRAP_FMTTRK per track.  INT 25h read-back, INT 26h writes.
;
; The FAT is built in memory as the tracks go: entries 0-1 hold the media
; byte (FEh FFh FFh), every data cluster starts free (000h), and MARKBAD
; sets FF7h on the clusters of a track that does not read back.  Track 0
; holds the boot sector, FATs and directory: a bad track 0 fails the disk.
; =====================================================================
FORMAT:
	mov di,TRACK+FATOFF	; clear the FAT: 512 bytes of 00h
	xor_d ax,ax	; (AX = 0)
	mov cx,0x100	; 256 words
	rep stosw	; 256 words of zero
	mov word [TRACK+FATOFF],0xfffe	; media FEH, then FFFH: bytes
	mov byte [TRACK+FATOFF+2],0xff	;   FE FF FF (entries 0 and 1)
	mov byte [TRK],0x0	; from track 0
FLOOP:
	mov di,TRACK+48	; the C byte of each ID field: 32 gap + 12 + 3 + FE
	mov cx,SPT	; in every one of the 18 sectors ...
	mov al,[TRK]	; C for this track
SETC:
	mov [di],al	; ... C = this track
	add di,332	; next sector's ID field
	loop short SETC	; all 18 ID fields
	mov al,[DRIVE]	; AL = drive
	mov dl,[TRK]	; DL = track
	mov bx,TRACK	; DS:BX = the image
	TRAP TRAP_FMTTRK	; T_FMT: restore/seek without verify, Write Track
	jc short FMTERR	; AL = 0 write protect, 2 not ready, ...
	mov al,[TRK]	; read it back: first logical sector = track x 18
	mov cl,SPT	; x 18 sectors per track
	mul cl	; AX = track x 18
	mov_d dx,ax	; DX = first logical sector of the track
	mov al,[DRIVE]	; AL = drive
	mov bx,TRACK+VEROFF	; to the read-back buffer (data unused:
	mov cx,SPT	;   only "does it read" matters), 18 sectors
	int byte 0x25	; INT 25h: BIOS READ, with its 10 retries
	pop bp		; drop the flags INT 25h leaves
	jnc short TRKOK	; all 18 read: good track
	cmp byte [TRK],0x0	; which track failed?
	jz short FFAIL	; track 0 is the system area: fatal
	call MARKBAD	; else its clusters -> FF7h
TRKOK:
	inc byte [TRK]	; next track
	cmp byte [TRK],NTRACK	; past the last?
	jc short FLOOP	; until all 40
;
; boot sector, FAT twice, then the directory: zeros (00 ends a directory
; in 1.25)
;
	mov bx,TRACK+BOOTOFF	; the current drive's boot sector ...
	mov cx,0x1	; one sector
	xor_d dx,dx	; ... to logical 0
	call WRSECS	; INT 26h
	jc short FMTERR	; write error: report it
	mov bx,TRACK+FATOFF	; FAT 1 to logical 1-2
	mov cx,FATSECS	; 2 sectors
	mov dx,FATSEC	; from logical 1
	call WRSECS	; INT 26h
	jc short FMTERR	; write error: report it
	mov bx,TRACK+FATOFF	; the same FAT again, as FAT 2 at 3-4
	mov cx,FATSECS	; 2 sectors
	mov dx,FATSEC+FATSECS	; from logical 3
	call WRSECS	; INT 26h
	jc short FMTERR	; write error: report it
	mov di,TRACK+VEROFF	; the read-back buffer, now free, becomes
	xor_d ax,ax	;   the directory: 2048 bytes of 00h
	mov cx,DIRSECS*128	; (a first byte 00h ends the search in 1.25)
	rep stosw	; 1024 words of zero
	mov bx,TRACK+VEROFF	; to logical 5-12
	mov cx,DIRSECS	; 8 sectors
	mov dx,DIRSEC	; from logical 5
	call WRSECS	; INT 26h
	jc short FMTERR	; write error: report it
	ret		; CF=0 from the last WRSECS

; ---------------------------------------------------------------------
; WRSECS - CX sectors from DS:BX to logical sector DX of the new disk
; Exit: CF / AL as the BIOS WRITE left them.  Corrupts AX, BP (and what
; the BIOS changes).  Callers: FORMAT.
; ---------------------------------------------------------------------
WRSECS:
	mov al,[DRIVE]	; the disk being formatted
	int byte 0x26	; INT 26h: IO.SYS WRITE (TRAP 8, RETF)
	pop bp		; drop the flags it leaves on the stack
	ret		; CF intact for the caller

; ---------------------------------------------------------------------
; FMTERR / FFAIL - print the error for BIOS code AL, return CF=1
; Reached by JC from FORMAT (trap 1Bh or INT 26h: AL = code) and FFAIL
; from a bad track 0 (code not used).  Codes as ERRTAB in z86sys.asm.
; ---------------------------------------------------------------------
FMTERR:
	mov dx,WPMSG	; 0: write protect
	or_d al,al	; code 0?
	jz short FMSG	; yes: "Write protect error"
	mov dx,NRMSG	; 2: not ready (no such drive / no track 0)
	cmp al,0x2	; code 2?
	jz short FMSG	; yes: "Drive not ready"
FFAIL:
	mov dx,FFMSG	; anything else: "Format failure"
FMSG:
	mov ah,0x9	; print it
	int byte 0x21	; AH=09h print
	stc		; CF=1: ASK skips to "Format another"
	ret	; (CF=1)

; =====================================================================
; MARKBAD - mark every cluster with a sector on track TRK as bad (FF7h)
; ---------------------------------------------------------------------
; Entry:  [TRK] = 1-39.   Corrupts AX, BX, CX, DX, SI.  Caller: FORMAT.
; Track t covers data sectors 18t-13 .. 18t+4; cluster = 2 + sector / 4.
; A track touches 5 or 6 clusters (track 10: 43-48, as test_fdd86.py
; checks); a cluster shared with a good neighbour is lost with it.  On
; track 39 the last one would be 178: clipped at MAXCLUS.
; =====================================================================
MARKBAD:
	mov al,[TRK]	; first logical sector of the track
	mov cl,SPT	; x 18
	mul cl	; AX = first logical sector of the track
	sub ax,FIRREC	; first sector of the track, in the data area
	mov_d bx,ax	; BX = first data sector
	add ax,SPT-1	; its last
	shr bx,1	; / 4 sectors per cluster
	shr bx,1	; (second shift: / 4)
	add bx,byte 0x2	; first cluster
	shr ax,1	; last data sector / 4
	shr ax,1	; (second shift)
	add ax,0x2	; last cluster
MARKBAD_LOOP:				; (src: MB1)
	cmp bx,MAXCLUS	; beyond the last real cluster?
	ja short MARKBAD_DONE	; (track 39's 178)
	push ax		; SETFAT corrupts AX
	mov dx,0xff7	; the FAT12 "bad cluster" mark
	call SETFAT	; FAT[BX] = FF7h
	pop ax	; last cluster again
	inc bx		; next cluster
	cmp_d bx,ax	; up to the last cluster
	jna short MARKBAD_LOOP	; through the last one
MARKBAD_DONE:				; (src: MB2)
	ret	; (CF meaningless)

; =====================================================================
; SETFAT / GETFAT / FATPTR - FAT12 access to the in-memory FAT
; ---------------------------------------------------------------------
; SETFAT: entry BX = DX (12 bits).  Corrupts AX, CL, DX, SI.
; GETFAT: AX = entry BX.            Corrupts CL, SI.
; FATPTR: SI = TRACK+FATOFF + BX x 3/2, the word holding entry BX.
; Callers: MARKBAD (SETFAT), REPORT (GETFAT).
; Even entries are the word's low 12 bits, odd ones its high 12: the
; nibble they share belongs to the neighbour and is kept.
; =====================================================================
SETFAT:
	call FATPTR	; SI -> the word holding entry BX
	mov ax,[si]	; the 16 bits around the entry
	test bx,0x1	; odd entry?
	jnz short SETFAT_ODD	; odd: high 12 bits
	and ax,0xf000	; even: keep the neighbour's top nibble
	jmp short SETFAT_MERGE	; (skip the odd case)
SETFAT_ODD:				; (src: SF1)
	and ax,0xf	; odd: keep the neighbour's low nibble ...
	mov cl,0x4	; 4-bit shift
	shl dx,cl	; ... and move the value up 4 bits
SETFAT_MERGE:				; (src: SF2)
	or_d ax,dx	; insert the entry
	mov [si],ax	; back into the FAT
	ret	; (AX = merged word)

GETFAT:
	call FATPTR	; SI -> the word holding entry BX
	mov ax,[si]	; the 16 bits around the entry
	test bx,0x1	; odd entry: its 12 bits are the top ones
	jz short GETFAT_MASK	; even: low 12 bits already
	mov cl,0x4	; 4-bit shift
	shr ax,cl	; odd: drop the neighbour's nibble
GETFAT_MASK:				; (src: GF1)
	and ax,0xfff	; the entry alone
	ret	; AX = 12-bit entry

FATPTR:
	mov_d si,bx	; SI = BX + BX / 2
	shr si,1	; BX / 2
	add_d si,bx	; + BX = BX x 3/2
	add si,TRACK+FATOFF	; into the FAT buffer
	ret	; SI -> entry BX's word

; =====================================================================
; MKTRACK - build the WD177x Write Track image at TRACK
; ---------------------------------------------------------------------
; Entry: none.  Exit: 6008 bytes at TRACK, all C bytes 0 (FORMAT sets
; them per track).  Corrupts AX, BL, CX, DI; sets DF=0.  Caller: START.
;
; The WD177x in MFM writes most bytes as given but interprets three:
;   F5h  writes A1h with a missing clock (the sync mark) and presets
;        the CRC generator - three of them open each address mark;
;   F6h  writes C2h with a missing clock (index mark sync) - NOT used;
;   F7h  writes the 2 CRC bytes of everything since the last F5h.
;
; Layout, image bytes (disk bytes where they differ):
;   gap 1   32 x 4Eh                           (no index address mark)
;   18 x {  12 x 00h            PLL sync before the ID
;            3 x F5h            A1 A1 A1, CRC preset
;               FEh             ID address mark
;           C H R N             track, 0, sector ID, 1 (= 256 bytes)
;               F7h             ID CRC                         (2 bytes)
;           22 x 4Eh            gap 2
;           12 x 00h            PLL sync before the data
;            3 x F5h            A1 A1 A1
;               FBh             data address mark
;          256 x E5h            the data, the usual empty-disk fill
;               F7h             data CRC                       (2 bytes)
;           16 x 4Eh  }         gap 3
;   one sector = 332 image bytes, 334 on the disk.
;   32 + 18 x 332 = 6008 = TRKLEN; on the disk 32 + 18 x 334 = 6044 of
;   the 6250 bytes in a 300 rpm turn at 250 kbit/s; T_FMT pads the last
;   206 (gap 4) with 4Eh until the index pulse ends the command, so a
;   drive up to 3.3% fast still fits the whole track (provisional:
;   checked on the emulator against the Python BIOS; not yet run on a
;   real FDD3000 - notes/hardware_run.md).
; R runs 0..17 in physical order: the 2:1 interleave is applied by the
; BIOS's SKEW when it maps logical sectors to IDs, not here.
; =====================================================================
MKTRACK:
	cld		; STOS forward
	mov di,TRACK	; (the label at the file's end)
	mov al,0x4e	; gap 1: 32 x 4Eh
	mov cx,0x20	; 32 bytes
	rep stosb	; gap 1
	xor_d bl,bl	; BL = sector ID, 0..17
MKTRACK_SECTOR:				; (src: MK1)
	xor_d al,al	; 12 x 00h: sync field
	mov cx,0xc	; 12 bytes
	rep stosb	; (00h)
	mov al,0xf5	; 3 x F5h: A1h sync marks, CRC preset
	mov cx,0x3	; 3 bytes
	rep stosb	; A1 A1 A1 on the disk
	mov al,0xfe	; ID address mark
	stosb	; FEh
	xor_d ax,ax	; C, H (C patched per track by FORMAT)
	stosw	; C = 0, H = 0
	mov_d al,bl	; R: sector ID
	stosb	; R
	mov al,0x1	; N: 256 bytes
	stosb	; N
	mov al,0xf7	; ID CRC (2 bytes on the disk)
	stosb	; F7h
	mov al,0x4e	; gap 2: 22 x 4Eh
	mov cx,0x16	; 22 bytes
	rep stosb	; gap 2
	xor_d al,al	; 12 x 00h: sync field
	mov cx,0xc	; 12 bytes
	rep stosb	; (00h)
	mov al,0xf5	; 3 x F5h: A1h sync marks
	mov cx,0x3	; 3 bytes
	rep stosb	; A1 A1 A1 on the disk
	mov al,0xfb	; data address mark
	stosb	; FBh
	mov al,0xe5	; 256 x E5h: the sector's data
	mov cx,0x100	; 256 bytes
	rep stosb	; the data field
	mov al,0xf7	; data CRC (2 bytes on the disk)
	stosb	; F7h
	mov al,0x4e	; gap 3: 16 x 4Eh
	mov cx,0x10	; 16 bytes
	rep stosb	; gap 3
	inc bl		; next sector ID
	cmp bl,SPT	; past ID 17?
	jc short MKTRACK_SECTOR	; all 18
	ret	; DI = TRACK + TRKLEN

; =====================================================================
; SETFCB - fill XFCB for SYSTAB entry SI on drive AL
; ---------------------------------------------------------------------
; Entry:  SI -> SYSTAB entry (name, attribute); AL = drive (0 = current,
;         else drive + 1).
; Exit:   XFCB ready; SI -> the entry's size field.  Corrupts AL, CX, DI.
; Callers: GETSYS, PUTSYS.
; The record-length write at the end is undone by DOS: open and create
; set FCB+14 to 128, so both callers set it to 1 again afterwards.
; =====================================================================
SETFCB:
	mov di,FCB	; drive byte
	stosb	; FCB+0: drive
	mov cx,0xb	; the 11-byte name
	rep movsb	; FCB+1: name from SYSTAB
	lodsb		; the attribute, into the extended header
	mov [XFCB+6],al	; XFCB+6: attribute
	xor_d al,al	; extent .. random record: zero
	mov cx,0x19	; 25 bytes: FCB+12..FCB+36
	rep stosb	; (zero)
	mov word [FCB+14],0x1	; record length 1 (overwritten by open/create)
	ret	; (SI -> the size field)

; =====================================================================
; GETSYS - read the /S files of the current drive into memory
; ---------------------------------------------------------------------
; Entry:  none.  Exit: CF=0, each SYSTAB entry's size and address set;
;         CF=1 a file is missing, 64 KB or more, does not fit up to
;         TRACK+BUFEND, or reads short.
; Corrupts: AX, BX, CX, DX, SI, DI.  Caller: START.
; DOS:    AH=0Fh open FCB, AH=1Ah set DMA address, AH=27h random block
;         read.  The extended FCB's attribute 06h lets open find the
;         hidden system files.  The files are not closed (nothing to
;         write back in DOS 1.25).
; =====================================================================
GETSYS:
	mov bx,SYSTAB	; BX = this file's entry
	mov di,TRACK+SYSOFF	; DI = where it goes
GETSYS_NEXT:				; (src: GS1)
	push di	; the load address
	push bx	; the entry
	mov_d si,bx	; SI -> name
	xor_d al,al	; on the current drive
	call SETFCB	; XFCB for it
	mov dx,XFCB	; DS:DX = the extended FCB
	mov ah,0xf	; AH=0Fh open
	int byte 0x21	; AL = 0 found, FFh not
	pop bx	; the entry back
	pop di	; the load address back
	or_d al,al	; AL = FFh: not found
	jnz short GSNO	; not found
	cmp word [FCB+18],byte 0x0	; size's high word: 64 KB or more
	jnz short GSNO	; too big
	mov ax,[FCB+16]	; size
	mov [bx+12],ax	; into SYSTAB: size ...
	mov [bx+14],di	; ... and address
	add_d ax,di	; its end
	jc short GSNO	; past 64 KB
	cmp ax,TRACK+BUFEND	; past the buffers?
	ja short GSNO	; it would overrun
	push ax		; the next file's address
	push bx	; the entry
	mov word [FCB+14],0x1	; record length 1: CX counts bytes (open
	mov word [FCB+33],0x0	;   made it 128); random record 0
	mov word [FCB+35],0x0	; (random record high word)
	mov_d dx,di	; DX = load address
	mov ah,0x1a	; AH=1Ah DMA address = DI
	int byte 0x21	; (DS:DX = transfer address)
	mov cx,[bx+12]	; the whole file, as 1-byte records
	mov dx,XFCB	; DS:DX = the FCB
	mov ah,0x27	; AH=27h random block read -> CX records read
	int byte 0x21	; CX = bytes actually read
	pop bx	; the entry back
	pop di		; where the next file goes
	cmp cx,[bx+12]	; all of it?
	jnz short GSNO	; short read
	add bx,byte SYSENT	; next entry
	cmp bx,SYSTAB+NSYS*SYSENT	; past the last entry?
	jc short GETSYS_NEXT	; all four
	clc	; CF=0: all loaded
	ret	; (to START)
GSNO:
	stc		; NOSMSG in START
	ret	; (to START)

; =====================================================================
; PUTSYS - with /S, create the four files on the new disk, in order
; ---------------------------------------------------------------------
; Entry:  disk formatted; SYSTAB filled by GETSYS.
; Exit:   CF=0 (also without /S); CF=1 failed, SWEMSG printed.
;         [SYSCL] = clusters used, for REPORT.
; Corrupts: AX, BX, CX, DX, SI, DI.  Caller: ASK.
; DOS:    AH=0Dh disk reset, AH=16h create, AH=1Ah DMA, AH=28h random
;         block write, AH=10h close, AH=09h print.
; DOS gives the files directory entries 0-3 and the first free clusters.
; Z86.SYS ends up at cluster 2 only because the disk is empty; nothing
; checks that each file is contiguous, which boot.asm and COLD assume -
; a bad track among clusters 2-~23 yields an unbootable system disk.
; =====================================================================
PUTSYS:
	mov word [SYSCL],0x0	; nothing used yet (also for REPORT without /S)
	cmp byte [SYSFLG],0x0	; /S asked for?
	jz short PSX	; no /S: done
	mov ah,0xd	; disk reset: DOS reads the new FAT
	int byte 0x21	; (DOS re-reads the FAT on next access)
	mov bx,SYSTAB	; the first entry
PUTSYS_NEXT:				; (src: PS1)
	push bx	; the entry
	mov_d si,bx	; SI -> name
	mov al,[DRIVE]	; the new disk, as drive + 1
	inc al	; 0-based -> FCB drive byte
	call SETFCB	; attribute 06h makes it hidden + system
	mov dx,XFCB	; DS:DX = the extended FCB
	mov ah,0x16	; AH=16h create
	int byte 0x21	; AL = 0 created, FFh not
	pop bx	; the entry back
	or_d al,al	; FFh: directory full / no such disk
	jnz short PSERR	; cannot create
	push bx	; the entry, across the DOS calls
	mov word [FCB+14],0x1	; record length 1 (create made it 128)
	mov word [FCB+33],0x0	; random record 0
	mov word [FCB+35],0x0	; (random record high word)
	mov dx,[bx+14]	; AH=1Ah DMA = the file's copy in memory
	mov ah,0x1a	; AH=1Ah DMA address
	int byte 0x21	; (DS:DX = the copy)
	mov cx,[bx+12]	; its size in 1-byte records
	mov dx,XFCB	; DS:DX = the FCB
	mov ah,0x28	; AH=28h random block write
	int byte 0x21	; AL = 0 written
	or_d al,al	; 1: disk full
	jnz short PSERRP	; disk full: fail
	mov dx,XFCB	; DS:DX = the FCB
	mov ah,0x10	; AH=10h close: directory entry and FAT out
	int byte 0x21	; AL = 0 closed
	or_d al,al	; closed?
	jnz short PSERRP	; no: fail
	pop bx	; the entry back
	mov ax,[bx+12]	; its clusters: size rounded up to 1 KB
	add ax,0x3ff	; + 1023 ...
	mov cl,0xa	; ... / 1024
	shr ax,cl	; = clusters
	add [SYSCL],ax	; for "bytes used by system"
	add bx,byte SYSENT	; next entry
	cmp bx,SYSTAB+NSYS*SYSENT	; past the last entry?
	jc short PUTSYS_NEXT	; all four
	mov dx,SYSMSG	; "System transferred"
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (ends with CR LF)
PSX:
	clc	; CF=0: success
	ret	; (to ASK)
PSERRP:
	pop bx		; (the entry pushed before the write)
PSERR:
	mov dx,SWEMSG	; "Disk error writing system"
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (ends with CR LF)
	stc	; CF=1: failure
	ret	; (to ASK)

; =====================================================================
; REPORT - total, system, bad and available bytes, as CHKDSK prints them
; ---------------------------------------------------------------------
; Entry:  FAT in memory, [SYSCL].   Corrupts everything but SI-chained
;         messages.  Caller: ASK.   DOS: AH=09h print.
; The system and bad lines appear only when non-zero.  Available =
; 176 - SYSCL - bad clusters (test_fdd86.py: 180224 / 22528 / 157696).
; =====================================================================
REPORT:
	mov dx,CRLF	; a blank line first
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (CR LF)
	mov ax,MAXCLUS-1	; 176 clusters ...
	call KBYTES	; DX:AX = 180 224
	mov si,TOTMSG	; ... "bytes total disk space"
	call DNUMM	; print it
	mov ax,[SYSCL]	; system clusters, if any
	or_d ax,ax	; any?
	jz short REPORT_BAD	; no /S: no line
	call KBYTES	; DX:AX = bytes
	mov si,USEMSG	; "bytes used by system"
	call DNUMM	; print it
REPORT_BAD:				; (src: RP1)
	xor_d bp,bp	; bad clusters
	mov bx,0x2	; from cluster 2
REPORT_COUNT:				; (src: RP2)
	call GETFAT	; AX = FAT[BX]
	cmp ax,0xff7	; marked bad?
	jnz short REPORT_NEXT	; (not bad)
	inc bp	; one more bad cluster
REPORT_NEXT:				; (src: RP3)
	inc bx	; next cluster
	cmp bx,MAXCLUS	; last one is 177
	jna short REPORT_COUNT	; through cluster 177
	or_d bp,bp	; any bad?
	jz short REPORT_AVAIL	; no bad clusters: no line
	mov_d ax,bp	; bad clusters
	call KBYTES	; DX:AX = bytes
	mov si,BADMSG	; "bytes in bad sectors"
	call DNUMM	; print it
REPORT_AVAIL:				; (src: RP4)
	mov ax,MAXCLUS-1	; what is left
	sub ax,[SYSCL]	; less the system
	sub_d ax,bp	; less the bad clusters
	call KBYTES	; DX:AX = bytes
	mov si,AVLMSG	; "bytes available on disk"
	jmp short DNUMM	; tail call (DNUMM's RET returns to ASK)
	nop		; MASM's forward JMP: 3 bytes reserved, 2 used

; ---------------------------------------------------------------------
; KBYTES - DX:AX = AX clusters x 1024.  Callers: REPORT.
; ---------------------------------------------------------------------
KBYTES:
	mov dx,0x400	; 1 KB per cluster
	mul dx	; DX:AX = AX x 1024
	ret	; (DX:AX)

; ---------------------------------------------------------------------
; DNUMM - print DX:AX in decimal, right-aligned in 9 columns, then the
; message at SI.   Corrupts AX, BX, CX, DX, DI.  Callers: REPORT.
; Long division by 10 in two 16-bit steps (high word, then remainder:low
; word), digits stored backwards from NUMBUF+9.  Values here stay under
; 180 224, so 9 columns never overflow.
; ---------------------------------------------------------------------
DNUMM:
	push si		; the message, for the end
	mov di,NUMBUF	; blank the 9 columns
	push ax	; the low word, across the fill
	mov al,' '	; blank ...
	mov cx,0x9	; ... all 9 columns
	rep stosb	; DI = NUMBUF+9, at the "$"
	pop ax	; the low word back
	mov bx,0xa	; divisor
DNUMM_DIGIT:				; (src: DN1)
	mov_d cx,ax	; CX = low word
	mov_d ax,dx	; high word / 10 ...
	xor_d dx,dx	; DX:AX = 0:high word
	div bx		; high word / 10
	xchg ax,cx	; CX = high quotient, AX = low word
	div bx		; (remainder, low word) / 10
	add dl,'0'	; remainder = next digit, right to left
	dec di	; one column left
	mov [di],dl	; the digit
	mov_d dx,cx	; DX:AX = the quotient
	mov_d cx,ax	; CX = low quotient
	or_d cx,dx	; zero?
	jnz short DNUMM_DIGIT	; more digits
	mov dx,NUMBUF	; the padded number
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (9 columns, then "$")
	pop dx		; then the message
	mov ah,0x9	; AH=09h print
	int byte 0x21	; (the message at SI)
	ret	; (to REPORT)

; =====================================================================
; TRACK - end of the file (075Ch): the buffers start here (see VEROFF)
; =====================================================================
TRACK:
