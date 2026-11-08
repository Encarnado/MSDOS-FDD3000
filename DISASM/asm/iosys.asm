;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  4/10
;  IO.SYS - the I/O system (8086, 332 bytes, runs at 0040:0000 = 0400h)
;==============================================================================
;
;  ROLE.  The machine-dependent half of MS-DOS 1.25: the "I/O system"
;  that Microsoft's kernel (MSDOS.SYS) calls far at 0040:0003..0040:002A,
;  one 3-byte entry per device function, in the order of MSDOS.LST's
;  SEGBIOS (BIOSSTAT .. BIOSMAPDEV).  On the FDD3000 there is no 8086:
;  this code runs on Z86.SYS's 8086 interpreter (volume 2), and every
;  entry is just `TRAP n / RETF` - the 0Fh nn opcode hands function nn to
;  the Z80 BIOS (TTAB, z86sys.asm), which works on the 8086 registers in
;  REGS and reports through ZF / CF.  INIT, which runs once, is the only
;  real 8086 program here: it sets seven IBM PC ROM BIOS vectors to
;  `TRAP n / RETF 2` stubs, gives DOS its drive table, and loads
;  COMMAND.COM with ordinary INT 21h FCB calls, as Seattle Computer
;  Products' I/O system for 86-DOS / MS-DOS does.
;
;  WHERE IT SITS IN THE BOOT CHAIN (OVERVIEW 2.4, step 4)
;     boot ROM -> BOOT.BIN (3F00h) -> Z86.SYS COLD (F12Ch: loads this
;       file to 0400h and MSDOS.SYS to 0600h, CS = DS = 0040h, IP = 0)
;       ->  THIS FILE, INIT  ->  MSDOS.SYS DOSINIT (far call, 0060:0000)
;       ->  back here  ->  COMMAND.COM at <first free segment>:0100h
;  After INIT has run, only 0400h-042Ch (the entries) and 04AFh-04D1h
;  (the PC ROM stubs) are ever executed again.  Nothing reclaims the
;  rest; it is under 512 bytes and DOS starts at 0600h regardless.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/iosys_findings.md)
;   - The 14 entries are exactly DOS 1.25's SEGBIOS in order: trap n is
;     the n-th entry, at offset 3n.  MAPDEV (trap 0Eh) and the trap
;     handlers for SETDATE / SETTIME / GETTIME / AUX / PRINT set no
;     flags; STATUS answers in ZF (plus AL), READ / WRITE / DSKCHG in CF.
;     Because a far CALL pushes no FLAGS, a plain RETF hands the trap's
;     flags straight to MSDOS.SYS.
;   - The ROM BIOS stubs end in RETF 2, not IRET: an INT pushed FLAGS,
;     and IRET would restore the caller's flags over the ZF / CF the trap
;     just set.  RETF 2 pops CS:IP and throws the FLAGS word away - the
;     IBM PC BIOS's own convention for INT 16h and friends.  Side effect:
;     IF and TF stay as INT cleared them (bookkeeping only here).
;   - INITTAB / DPT40 match DOSINIT (MSDOS.LST 3805-3907) field for
;     field.  From DPT40 DOS itself computes 8 directory sectors, 2 FAT
;     sectors (the iteration converges at 2), FIRDIR = 5, FIRREC = 13,
;     MAXCLUS = 177 - the very constants Z86.SYS hard-codes (FIRDIR,
;     FIRREC) and mkfat.py writes.  Worked through below at DPT40.
;   - The source's "MEMTOP ... (patched by the loader)" is stale: COLD
;     loads IO.SYS byte for byte and patches nothing, and no build script
;     touches offset 00E7h.  DOS always gets 0D00h (52 KB, = GTOP).
;   - INIT has no CLD: its STOSW loop relies on COLD having left DF = 0.
;   - The COMMAND.COM loader is SCP's, line for line as the source says
;     (not checkable here: no SCP source in the workspace).  It asks
;     Block Read for [6] bytes - the program segment's size counted from
;     offset 0 - into DS:0100h, so the read may run 256 bytes past
;     ENDMEM; harmless, COMMAND.COM 1.17 is far smaller.  It insists on
;     AL bit 0 (EOF reached): a COMMAND.COM that fills the whole segment
;     is refused rather than run truncated.
;   - OVERVIEW 2.3 and the poc README say "six" PC ROM BIOS interrupts;
;     there are seven (10h 11h 12h 14h 16h 17h 1Ah), as their own tables
;     and ROMTAB show.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/IO.SYS with
;  `nasm -O0 -f bin` (tools/roundtrip.sh iosys).  Every instruction and
;  data byte agrees with the MASM listing ../symbols/x86/IOFDD.LST
;  (addresses 0000h-014Bh).  The DOS side of each contract is read from
;  ../symbols/x86/MSDOS.LST (DOS 1.25 as built for this disk); the Z80
;  side from z86sys.asm (TRAP, TTAB and the T_* handlers).  Boots to
;  COMMAND.COM under the emulator (test_dos.py, test_fdd86.py).  On
;  REAL HARDWARE (notes/hardware_run.md, run of 2026-11-07): the
;  emulator-written disk booted a real FDD3000 with a TT3000 terminal
;  through this file's INIT (vectors set, DOSINIT, COMMAND.COM loaded)
;  to the prompt, and DOS console tools, EDIT, CPM and PRN / AUX ran -
;  so the device entries for console, disk, printer and AUX are
;  verified on one machine.  COMERR (no / bad COMMAND.COM) is not
;  exercised by any test or by that run.
;
;  FILE:    IO.SYS, 332 bytes
;  MD5:     0a9d3cf0eaee0a0a6610b5d79d5b2bc0
;  SHA256:  185ad55ec5944918ef8a80e6837deb848b567faf4524ce8d5b72f15633c2d46f
;  SOURCE:  project/MSDOS/poc/IOFDD.ASM (MASM 1.10, built as IOFDD.SYS)
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  The
;  COMMAND.COM loader after Seattle Computer Products' I/O system
;  (Tim Paterson); the entry layout and DOSINIT contract are MS-DOS
;  1.25's (Microsoft, MIT licence).  Disassembly and annotation in the
;  style of "The Complete TMX Portugal ROM Disassemblies", LoadZX
;  Museum, 2026.
;==============================================================================
;
; ASSEMBLER NOTES.  NASM, `-O0 -f bin`: -O0 stops NASM re-sizing
; anything, so the explicit `short`, `byte` and `word` keywords fix the
; encoding.  TRAP n emits 0Fh n, the interpreter's BIOS trap (POP CS on
; a real 8086).  The `_d` macros spell a register-to-register
; instruction in MASM's encoding (direction bit set, e.g. xor_d bp,bp =
; 33 EDh where NASM would emit 31 EDh): same operation, MASM's bytes.

%macro TRAP 1
	db	0Fh, %1	; BIOS trap: POP CS on an 8086, a Z80 call here
%endmacro
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

; =====================================================================
;                    SEGMENTS (the author's equates)
; =====================================================================
BIOSSEG		equ	40H	; this file: 0040:0000 = linear 0400h,
				;   the address DOS 1.25 assumes (MSDOS.LST 190)
DOSSEG		equ	60H	; MSDOS.SYS: 0060:0000 = 0600h, so this
				;   file must stay below 512 bytes

; =====================================================================
;                    BIOS TRAP NUMBERS (served by TTAB, z86sys.asm)
; =====================================================================
; 01h-0Eh: the DOS 1.25 I/O-system entries, n-th entry = trap n.
TRAP_STATUS	equ	01h	; T_STAT:  ZF=1 no key; ZF=0, AL = key (kept)
TRAP_INP	equ	02h	; T_INP:   AL = key, waits; no flags
TRAP_OUTP	equ	03h	; T_OUTP:  AL to the terminal; no flags
TRAP_PRINT	equ	04h	; T_PRINT: AL to WD2123 channel A; no flags
TRAP_AUXIN	equ	05h	; T_AUXIN: AL from channel B; no flags
TRAP_AUXOUT	equ	06h	; T_AUXOUT: AL to channel B; no flags
TRAP_READ	equ	07h	; T_READ:  CF=0 done / CF=1, AL = error, CX left
TRAP_WRITE	equ	08h	; T_WRITE: the same
TRAP_DSKCHG	equ	09h	; T_DSKCHG: AH = 0 "don't know", CF=0
TRAP_SETDATE	equ	0Ah	; T_SDATE: stores AX; no flags
TRAP_SETTIME	equ	0Bh	; T_STIME: stores CX, DX; no flags
TRAP_GETTIME	equ	0Ch	; T_GTIME: AX, CX, DX as last set; no flags
TRAP_FLUSH	equ	0Dh	; T_FLUSH: drops type-ahead; no flags
TRAP_MAPDEV	equ	0Eh	; TNONE:   nothing done, AL (device) unchanged
; 10h-1Ah: IBM PC ROM BIOS interrupts, trap number = vector number.
TRAP_INT10	equ	10h	; T_I10: video (teletype, VT52 cursor, clear)
TRAP_INT11	equ	11h	; T_I11: AX = 0071h equipment word
TRAP_INT12	equ	12h	; T_I12: AX = 52 (KB)
TRAP_INT14	equ	14h	; T_I14: serial, channels A / B
TRAP_INT16	equ	16h	; T_I16: keyboard; AH=1 answers in ZF
TRAP_INT17	equ	17h	; T_I17: printer, channel A
TRAP_INT1A	equ	1Ah	; T_I1A: tick count, +1 per call

; =====================================================================
;                    DOS 1.25 INTERFACE (MSDOS.LST)
; =====================================================================
DOS_PRTSTR	equ	09h	; INT 21h AH=09h print string to "$"
DOS_OPEN	equ	0Fh	; INT 21h AH=0Fh open FCB
DOS_SETDTA	equ	1Ah	; INT 21h AH=1Ah set disk transfer address
DOS_BLKREAD	equ	27h	; INT 21h AH=27h random block read
FCB_RECSIZ	equ	14	; FCB: record size (FCBLOCK RECSIZ, 0Eh)
FCB_RR		equ	33	; FCB: random record, 4 bytes (RR, 21h)
PSP_SEGSIZE	equ	6	; program segment: bytes in the segment, set
				;   by SETMEM (CP/M's BDOS-address word)
PSP_FCBSTK	equ	5Ch	; program's initial SP: just under the FCB
PSP_DTA		equ	80h	; program's default DTA (command tail)
COM_ORG		equ	100h	; where a .COM is loaded and entered

	org	0
bits 16

; =====================================================================
; THE I/O SYSTEM ENTRY TABLE - 0040:0000-002C, the part DOS calls
; ---------------------------------------------------------------------
; Entry:  a far CALL from MSDOS.SYS (CALL FAR PTR BIOSxxx), registers as
;         each function's contract below.
; Exit:   RETF, with what the Z80 handler left in the 8086 registers and
;         in ZF / CF.  A far CALL pushes no FLAGS, so plain RETF already
;         delivers the trap's flags to DOS.
; Corrupts: per handler (z86sys.asm); none touches SP, segments or BX.
;
; Offset 0 holds DOS's "jump to init code" slot (SEGBIOS's first 3
; bytes); the 14 entries follow at 3n.  The author's macro was
; `ENTRY n` = DB 0FH,n,0CBH.  DOS's use of each, from MSDOS.LST:
;   STATUS  STATCHK (^S ^P ^C check while printing) and AH=0Bh/06h:
;           JZ = nothing typed; else AL is the key, still unread
;   INP     every console read; AL = key
;   READ /  DSKREAD / DSKWRITE and INT 25h / 26h (DOSINIT points those
;   WRITE   vectors straight at 0040:0015 / 0040:0018): AL = physical
;           unit (DRVNUM from INITTAB), DS:BX buffer, CX count, DX first
;           sector; CF=1 -> AL = 0 WP, 2 not ready, 4 data, 6 seek,
;           8 not found, 0Ch general; CX = sectors not done
;   DSKCHG  FATREAD: DOS presets AH = 0 and CF = 0; CF=1 is "bad drive",
;           AH < 0 changed, > 0 unchanged, 0 unknown.  The FDD3000 has
;           no change line, so 0: the FAT is re-read unless DOS holds
;           a dirty buffer for that drive
;   MAPDEV  FATREAD after a FAT read: AL = device number, AH = first
;           FAT byte OR F8h (the media byte); returns the device to use
;           in AL.  Identity here (one format, nothing to remap)
; =====================================================================
	jmp short INIT		; +00 DOS's init slot (2-byte JMP ...
	nop			;   ... padded to SEGBIOS's 3)
	TRAP	TRAP_STATUS	; +03 BIOSSTAT    console input status
	retf			;     ZF / AL straight to DOS
	TRAP	TRAP_INP	; +06 BIOSIN      console input (waits)
	retf			; AL = the key
	TRAP	TRAP_OUTP	; +09 BIOSOUT     console output
	retf			; (a far CALL stacks no FLAGS)
	TRAP	TRAP_PRINT	; +0C BIOSPRINT   printer output (waits for ever)
	retf			; back to DOS
	TRAP	TRAP_AUXIN	; +0F BIOSAUXIN   auxiliary input
	retf			; AL = the byte
	TRAP	TRAP_AUXOUT	; +12 BIOSAUXOUT  auxiliary output
	retf			; back to DOS
	TRAP	TRAP_READ	; +15 BIOSREAD    disk read (also INT 25h)
	retf			;     CF / AL / CX to DOS
	TRAP	TRAP_WRITE	; +18 BIOSWRITE   disk write (also INT 26h)
	retf			; CF / AL / CX to DOS
	TRAP	TRAP_DSKCHG	; +1B BIOSDSKCHG  disk changed? AH = 0, CF = 0
	retf			; AH, CF to FATREAD
	TRAP	TRAP_SETDATE	; +1E BIOSSETDATE AX = days since 1-1-80
	retf			; back to DOS
	TRAP	TRAP_SETTIME	; +21 BIOSSETTIME CH:CL h:m, DH:DL s.1/100
	retf			; back to DOS
	TRAP	TRAP_GETTIME	; +24 BIOSGETTIME AX days, CX, DX (frozen clock)
	retf			; AX, CX, DX to READTIME
	TRAP	TRAP_FLUSH	; +27 BIOSFLUSH   drop keys typed ahead
	retf			; back to DOS
	TRAP	TRAP_MAPDEV	; +2A BIOSMAPDEV  TNONE: AL comes back unchanged
	retf			; AL = device to use, as given

; =====================================================================
; INIT - one-time start: ROM vectors, DOS init, load COMMAND.COM
; ---------------------------------------------------------------------
; Entry:  from COLD (z86sys.asm): CS = DS = 0040h, IP = 0 (through the
;         JMP above), every other register 0, so SS:SP = 0000:0000;
;         DF = IF = 0.
; Exit:   never returns - RETF into COMMAND.COM at <seg>:0100h, or the
;         STALL loop after "Error in loading Command Interpreter".
; DOS calls: AH=1Ah set DTA, AH=0Fh open FCB, AH=27h random block read,
;         AH=1Ah again, and on failure AH=09h print string.
; Callers: COLD only (by starting the 8086 here).
;
; The stack goes at 0000:0400h, just under this file, growing down into
; the top of the interrupt vector table (vectors F8h-FFh, unused).
; CLI / STI are bookkeeping on the interpreter (nothing interrupts the
; guest) but keep the SS:SP pair safe on a real 8086.
; =====================================================================
INIT:
	cli			; no interrupt between the SS and SP loads
	xor_d bp,bp		; BP = 0: the stack segment, and ES below
	mov ss,bp		; stack at 0000:0400h, just under this file
	mov sp,BIOSSEG*16	; = 0400h
	push cs			; DS = CS = 0040h (COLD set it already;
	pop ds			;   INIT does not rely on that)
	sti			; interrupts may run again

; ---- seven PC ROM BIOS vectors -> TRAP n / RETF 2 stubs --------------
; Minimal IBM PC ROM BIOS for programs written for PC-DOS (DEBUG,
; CHKDSK...).  COLD zeroed all 256 vectors; DOSINIT will set 20h-27h.
; No CLD: STOSW counts up only because COLD left DF = 0.
	mov es,bp		; ES = 0000h: the vector table
	mov si,ROMTAB		; (vector, handler offset) triples
	mov cx,(ROMEND-ROMTAB)/3	; 7 of them
SETROM:
	lodsb			; vector number n
	xor_d ah,ah		; widened to a word
	shl ax,1		; x 4: the vector's address
	shl ax,1		;   (0000:4n)
	mov_d di,ax		; STOSW target
	lodsw			; the stub's offset in this file ...
	stosw			; ... is the vector's IP
	mov ax,cs		; and 0040h ...
	stosw			; ... its CS
	loop short SETROM	; all seven

; ---- hand DOS the drive table and the memory size --------------------
; DOSINIT (MSDOS.LST 3805): CS:SI = INITTAB, DX = paragraphs of memory
; (1 = scan for the end).  It builds a DPB per drive, places FATs and
; buffers after itself, sets vectors 20h-27h, prints the DOS banner and
; returns far with DS = ES = the first free segment, already prepared
; as a program segment by SETMEM ([2] = ENDMEM, [6] = bytes in the
; segment, [0] = INT 20h).  A bad table never returns: "INIT TABLE BAD"
; and HLT.
	mov si,INITTAB		; drive count, then (unit, DPT) per drive
	mov dx,[MEMTOP]		; 0D00h paragraphs: memory ends at D000h
	call word far [DOSENT]	; DOSINIT at 0060:0000 (DOS's JMP DOSINIT)

; ---- load COMMAND.COM (Seattle Computer's I/O-system method) ---------
; MS-DOS 1.25 has no EXEC: the I/O system loads the shell itself, with
; FCB calls, into the segment DOSINIT just prepared.
	mov dx,COM_ORG		; DTA = DS:0100h, where a .COM belongs
	mov ah,DOS_SETDTA	; AH=1Ah set disk transfer address
	int 21h	; DTA = BX:0100h (DS is still the new segment)
	mov cx,[PSP_SEGSIZE]	; CX = bytes in the program segment: the
				;   record count for the read (records of 1)
	mov bx,ds		; BX = the program segment, kept to the end
	mov ax,cs		; DS back to this file, where the FCB is
	mov ds,ax	;   (no FCB in the program segment yet)
	mov dx,FCB		; DS:DX -> "A:COMMAND.COM"
	mov ah,DOS_OPEN		; AH=0Fh open FCB
	int 21h	; AL = 0 found, FFh not
	or_d al,al		; AL = 0 found, FFh not found
	jnz short COMERR	; no COMMAND.COM on drive A:
	xor_d ax,ax		; random record = 0: from the first byte
	mov [FCB+FCB_RR],ax	; (low word ...
	mov [FCB+FCB_RR+2],ax	;   ... and high word)
	inc ax			; record size 1, so CX counts bytes
	mov [FCB+FCB_RECSIZ],ax	; (open set it to 128)
	mov ah,DOS_BLKREAD	; AH=27h random block read, CX records
	int 21h			;   to the DTA; CX = records read
	jcxz short COMERR	; nothing read: empty or unreadable
	test al,1		; AL = 1 (or 3): end of file reached
	jz short COMERR		; 0: the file fills the segment (too big
				;   to trust); 2: the DTA would wrap
; ---- start COMMAND.COM as a .COM program -----------------------------
	mov ds,bx		; DS = ES = SS = the program segment
	mov es,bx	;   (a .COM sees one segment for all)
	mov ss,bx	;   (SS:SP set back to back, as an 8086 needs)
	mov sp,PSP_FCBSTK	; SP = 5Ch, the standard start of a 1.x
				;   program (the stack sits under the FCB)
	xor_d ax,ax		; a 0 on top of the stack: a near RET from
	push ax			;   the program lands on [0] = INT 20h
	mov dx,PSP_DTA		; DTA = DS:0080h, the default buffer
	mov ah,DOS_SETDTA	; AH=1Ah set disk transfer address
	int 21h	; (the read is done; 80h is the 1.x default)
	push bx			; far return address = segment:0100h ...
	mov ax,COM_ORG	; IP = 0100h, the .COM entry
	push ax	;   on top, for the RETF
	retf			; ... "returned" to: COMMAND.COM runs, with
				;   SP back at 5Ah over the 0

; ---------------------------------------------------------------------
; COMERR - COMMAND.COM missing, empty or too big: say so and hang.
; DS = CS here on every path (all three jumps come before DS changes).
; DOS calls: AH=09h print string.  Never returns.
; ---------------------------------------------------------------------
COMERR:
	mov dx,BADCOM		; "Error in loading Command Interpreter"
	mov ah,DOS_PRTSTR	; AH=09h print string to "$"
	int 21h	; (DS = CS: BADCOM is in this file)
STALL:
	jmp short STALL		; nothing to fall back on: reset the machine

; =====================================================================
; INT10 .. INT1A - the PC ROM BIOS stubs (vectors set by SETROM)
; ---------------------------------------------------------------------
; Entry:  INT n from a program: FLAGS, CS, IP pushed; IF = TF = 0.
; Exit:   RETF 2 - CS:IP popped, then SP += 2 drops the saved FLAGS, so
;         the ZF / CF the Z80 handler set (INT 16h AH=1's ZF, INT 14h /
;         17h status is in AH) reach the caller.  IRET would put the
;         caller's old flags back over them.  IF / TF stay cleared
;         (only visible to a later PUSHF).
; Corrupts: per handler (z86sys.asm T_I10..T_I1A).
; Not served: 13h (disk - DOS uses traps 7/8), 15h, 18h, 19h: those
; vectors stay 0000:0000 from COLD's clear, and a program calling them
; jumps to address 0.
; =====================================================================
INT10:
	TRAP	TRAP_INT10	; video: teletype, cursor, clear
	retf 2			; drop FLAGS, keep the trap's
INT11:
	TRAP	TRAP_INT11	; equipment word
	retf 2			; (same: the trap's flags survive)
INT12:
	TRAP	TRAP_INT12	; memory size in KB
	retf 2			; (same: the trap's flags survive)
INT14:
	TRAP	TRAP_INT14	; serial port
	retf 2			; (same: the trap's flags survive)
INT16:
	TRAP	TRAP_INT16	; keyboard (AH=1 answers in ZF)
	retf 2			; (same: the trap's flags survive)
INT17:
	TRAP	TRAP_INT17	; printer
	retf 2			; (same: the trap's flags survive)
INT1A:
	TRAP	TRAP_INT1A	; tick count
	retf 2			; (same: the trap's flags survive)

; ---------------------------------------------------------------------
; ROMTAB - vector number, stub offset (3 bytes each), read by SETROM
; ---------------------------------------------------------------------
ROMTAB:
	db 10H			; INT 10h video
	dw INT10		; 0040:INT10
	db 11H			; INT 11h equipment
	dw INT11		; 0040:INT11
	db 12H			; INT 12h memory size
	dw INT12		; 0040:INT12
	db 14H			; INT 14h serial
	dw INT14		; 0040:INT14
	db 16H			; INT 16h keyboard
	dw INT16		; 0040:INT16
	db 17H			; INT 17h printer
	dw INT17		; 0040:INT17
	db 1AH			; INT 1Ah time of day
	dw INT1A		; 0040:INT1A
ROMEND:				; (no source label: marks the count for SETROM)

; ---------------------------------------------------------------------
; MEMTOP - DOSINIT's DX: paragraphs of 8086 memory.  0D00h = D000h =
; 52 KB = Z86.SYS's GTOP (and fddos.py's MEMTOP).  1 would make DOSINIT
; scan for the end itself (MSDOS.LST 3951).  The source says "patched by
; the loader": nothing patches it (COLD copies the file as it is).
; DOSENT - far pointer to DOSINIT: 0060:0000, MSDOS.SYS's JMP DOSINIT.
; ---------------------------------------------------------------------
MEMTOP:
	dw 0D00H		; 52 KB of 8086 memory, fixed
DOSENT:
	dw 0,DOSSEG		; IP = 0000h, CS = 0060h

; =====================================================================
; INITTAB / DPT40 - the drive table DOSINIT reads (MSDOS.LST 3811-3907)
; ---------------------------------------------------------------------
; INITTAB: byte count of drives (NUMIO), then per drive a byte physical
; unit (DRVNUM: what READ / WRITE get in AL; must be 0-15, it also
; picks the drive's FAT buffer in FATSIZTAB, so units 0 and 1 get
; separate FATs) and a word offset of its drive parameter table.
; Both drives share DPT40.
;
; DPT40, the 9 bytes DOSINIT copies or derives per DPB:
;   SECSIZ 256, sectors/cluster 4 (-> CLUSMSK 3, CLUSSHFT 2),
;   reserved 1 (-> FIRFAT 1), FATCNT 2, MAXENT 64, total 720 sectors.
; What DOS works out from it (FIGFATSIZ / FIGMAX):
;   directory sectors (64 + 8 - 1) / 8 = 8 (8 entries of 32 a sector)
;   FAT size: trial 1 -> FIRREC 11, clusters (720-11)/4+1 = 178, FAT
;     (179 x 1.5) = 269 bytes = 2 sectors; trial 2 -> FIRREC 13,
;     177 -> 267 bytes = 2 sectors: converged, FATSIZ = 2
;   FIRDIR = 1 + 2 x 2 = 5, FIRREC = 5 + 8 = 13, MAXCLUS = 177
;     (clusters 2-177; sectors 717-719 left over)
; - the layout of OVERVIEW 2.5, of mkfat.py, and of Z86.SYS's FIRDIR /
; FIRREC, which COLD uses before DOS exists.
; =====================================================================
INITTAB:
	db 2			; NUMIO: two drives, A: and B:
	db 0			; A: physical unit 0 ...
	dw DPT40		;   ... 40 x 18 x 256 geometry
	db 1			; B: physical unit 1 ...
	dw DPT40		;   ... the same geometry
DPT40:
	dw 256			; SECSIZ: bytes per sector
	db 4			; sectors per cluster: 1 KB clusters
	dw 1			; reserved sectors: the boot sector
	db 2			; FATCNT: two copies of the FAT
	dw 64			; MAXENT: directory entries
	dw 720			; total sectors: 40 tracks x 18

; ---------------------------------------------------------------------
; BADCOM - COMERR's message (AH=09h string, "$"-terminated), SCP's
; wording.
; ---------------------------------------------------------------------
BADCOM:
	db 13,10,"Error in loading Command Interpreter",13,10,"$"	; CR LF, the text, CR LF, "$"

; =====================================================================
; FCB - the File Control Block for COMMAND.COM (37 bytes)
; ---------------------------------------------------------------------
;   +0   drive 1 = A: (explicit, not 0 = default: the shell always comes
;        from the boot drive)     +1-11  "COMMAND COM" (8+3, padded)
;   +12  extent, +14 record size, +16 file size... filled in by OPEN;
;        INIT then sets +14 = 1 and +33..36 (random record) = 0.
; =====================================================================
FCB:
	db 1,"COMMAND COM"	; drive A:, name and extension
	times 25 db 0		; +12..+36: OPEN and INIT fill these
