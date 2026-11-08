;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  6/10
;  CPM.COM - CP/M 2.2 programs under MS-DOS, run natively on the Z80
;  (8086 .COM, 3286 bytes, runs at CS:0100h; carries volume 3 inside)
;==============================================================================
;
;  ROLE.  `CPM program [arguments]` runs program.CPM (or program.COM
;  when there is no .CPM) as a CP/M 2.2 program.  The FDD3000's CPU is
;  a Z80, so the program runs natively; only its file calls go through
;  DOS.  This file is two programs in one: 764 bytes of 8086 code and
;  data (0100h-0419h), run by Z86.SYS's interpreter like any .COM, and
;  from 041Ah the Z80 part, CPMZ80 (volume 3), behind a 16-byte header.
;  The 8086 part does what CP/M's CCP would do (find the program, load
;  it, build the two FCBs and the command tail) and works out where the
;  program, its BDOS/BIOS page P and the save area will go; the Z80
;  part then does the rest.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM 1.17H  ->  THIS PROGRAM (8086, START)
;       ->  TRAP 1Ch, BP = linear address of the header at 041Ah:
;           Z86.SYS's T_CPML (volume 2) checks the header's 7 addresses
;           and copies the 2506-byte image to ENDBIOS (F12Ch, over COLD)
;       ->  open the program, read it over the image (STAGE, 0400h on),
;           build FCB1 / FCB2 / TAIL (PARMS)
;       ->  TRAP 1Ch, BP = 0: JP ENDBIOS = CPMZ80's T_CPM (volume 3):
;           DOS and this program swapped out, the CP/M program at 0100h
;       ->  warm boot: CPEXIT swaps everything back and RETs out of the
;           trap  ->  AH=0Dh disk reset, INT 20h  ->  COMMAND reloads its
;           transient part (which the save area overwrote)
;
;  MEMORY, AS CHKSZ LAYS IT OUT (linear = Z80 addresses; typical values
;  from the README's measured layout: BASE 2400h, TOP CBA0h)
;     0000h        vectors, IO.SYS, MSDOS.SYS and its data
;     BASE         this program's PSP (BASE = CS x 16)
;     BASE+100h    DOSLEN: what a DOS call needs swapped back in
;     BASE+400h    SWLEN = BASE + STGOFF: the program as read (staged)
;     P            (TOP - 200h - SWLEN) AND FF00h: BDOS entry, 8086 stub,
;                  BIOS vector, scratch FCBs (PSIZE = 200h)
;     P+200h       SAVE: 0000h-SWLEN while the program runs
;     TOP          PSP offset 2 (the transient COMMAND sits just below)
;     TOP..        COMMAND's resident part (HIGHMEM build: see findings)
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/cpmcom_findings.md)
;   - COMMAND's resident part sits ABOVE TOP, not in the swap: COMMAND
;     1.17 here is assembled with HIGHMEM = TRUE (COMMAND.LST line 24;
;     its banner "Command v. 1.17H"), which moves the resident part to
;     the top of memory and lowers PSP offset 2 below it.  CHKSZ's
;     comment and the README are right; CPMZ80.ASM's header ("DOS,
;     COMMAND and CPM.COM are below" SWLEN), OVERVIEW 2.6 and volume 3's
;     side note are wrong.  The part that IS overwritten (by SAVE) is the
;     transient one, which COMMAND checksums and reloads.
;   - A program must fit between SWLEN and P while it is staged, so the
;     largest loadable program is P - SWLEN (7900h = 30 976 bytes in the
;     typical layout), about 9.7 KB less than the TPA it then gets
;     (0100h-P, 40 960 bytes).  test_fdd86.py's BIG.CPM (40 000 bytes)
;     is refused "Program too big" although it would fit the TPA.
;   - FIXED 2026-11-08 (this build): the random block read's result was
;     not checked, so a short or failed read would run a partly loaded
;     program.  Now "Program read error" (test_cpm_smoke.py runs CPM.COM).
;   - `JMP MSG` after the trap is EB 3E 90: MASM 1.10 reserved a near
;     jump for the forward reference and padded the short form with NOP.
;   - Trap 1Ch's header holds 7 Z86.SYS addresses; the REGS page that
;     carries this program's arguments into T_CPM, and the serial
;     routines CPMZ80 calls, are not in it (volume 3, finding 17).
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/CPM.COM with NASM
;  (nasm -O0 -f bin, tools/roundtrip.sh).  Every instruction matches
;  the MASM listing ../symbols/x86/CPM.LST; every label is at the
;  address CPM.COM.sym gives.  The header at 041Ah was checked against
;  ../symbols/z80/Z86.SYS.sym, and the 2506 bytes after it are
;  bin/CPMZ80.BIN, byte for byte (volume 3), included here with incbin.
;  The four error messages and the CP/M runs are exercised by
;  test_fdd86.py groups 6 and 7 on the emulated FDD3000.  On real
;  hardware (notes/hardware_run.md, 2026-11-07: a real FDD3000 with a
;  TT3000 terminal, the emulator-written disk) CPM.COM ran a CP/M
;  program, its Z80 part running natively with the files on the DOS
;  disk: verified on one machine.  Which program, and the error paths,
;  are not recorded.
;
;  FILE:    CPM.COM, 3316 bytes (2026-11-08 build; the shipped one was 3286)
;  MD5:     1c52ad31ae2edb8d70a39e77a857a9ed
;  SHA256:  4e45e24109f3ae8147b3b08e3faa8bf87bc4e7ef6f665ed3e0d6d28bd133db3c
;  SOURCE:  ../project/MSDOS/poc/CPM.ASM (MASM 1.10), with CPMZ80.INC
;           (z86.py cpmz80(): header + CPMZ80.ASM's code) by build.py
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  CP/M 2.2
;  conventions (page zero, FCBs at 5Ch/6Ch, the tail at 80h) after
;  Digital Research's CCP; MS-DOS 1.25 and COMMAND.COM by Microsoft.
;  Disassembly and annotation in the style of "The Complete TMX Portugal
;  ROM Disassemblies", LoadZX Museum, 2026.
;==============================================================================

; =====================================================================
;                    ASSEMBLER SPELLING (NASM -O0)
; =====================================================================
; TRAP n emits 0Fh n: POP CS on a real 8086, which Z86.SYS's
; interpreter takes as "call BIOS function n" (TTAB, volume 2) and then
; continues at the next byte.
;
; The _d forms (mov_d bp,ax, xor_d ch,ch ...) are register-to-register
; instructions in MASM's encoding, with the direction bit set (8B E8 for
; MOV BP,AX); NASM would pick the other, equally valid, form.  Same
; operation as the plain mnemonic, other bytes.  With -O0 NASM never
; re-sizes, so the explicit `short`, `byte` and `word` keep the bytes.

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
;                    CONSTANTS
; =====================================================================

PSIZE		equ	200H	; the P area (CPMZ80.ASM's PSIZE): BDOS entry,
				;   stub, BIOS vector and scratch at P..P+1FFh

TRAP_CPM	equ	1Ch	; Z86.SYS T_CPML: BP <> 0 load the Z80 part at
				;   linear BP, CF=1 if built for another Z86.SYS;
				;   BP = 0 run it (T_CPM), back when it ends
TRAP_DOSRET	equ	1Dh	; Z86.SYS T_RET: end of a DOS call started by
				;   CPMZ80 (its stub at P+09h, CD 21 0F 1D).  Not
				;   issued by this 8086 code; named for the record
				;   (trap names as in iosys.asm: TRAP_STATUS ..)

; ---- this program's PSP, as COMMAND.COM leaves it ----
PSP_TOP		equ	02h	; first segment past our memory (DOS SETMEM's
				;   [2]; COMMAND 1.17H stores MEMSIZ, the start
				;   of its resident part)
PSP_FCB1	equ	5Ch	; FCB 1: COMMAND parsed the first argument
				;   (here: the CP/M program's name) into it
PSP_TAILLEN	equ	80h	; length of the command tail
PSP_TAIL	equ	81h	; the tail: what followed "CPM", CR-ended

; ---- MS-DOS 1.25 FCB offsets used on PFCB ----
FCB_EXT		equ	9	; extension, 3 bytes (after drive + 8 name)
FCB_RECSIZ	equ	14	; record size (word; OPEN sets 128)
FCB_SIZE	equ	16	; file size in bytes (dword: low word ...
FCB_SIZEHI	equ	18	;   ... high word)
FCB_RR		equ	33	; random record (3-4 bytes, two words here)

; ---- Z86.SYS addresses CPMZ80 was assembled against (Z86.SYS.sym) ----
; The author's names; the header at 041Ah carries them in BIOS.ASM's
; CPMSYM order and T_CPML compares them with its own CPMSYM.
NEXT		equ	0D83Bh	; the 8086 dispatcher (interpreter main loop)
JPHL		equ	0EB4Dh	; JP (HL): CPMZ80's indirect CALL
PEEKEY		equ	0EBE3h	; console: CF=1 when a key waits
GETKEY		equ	0EC00h	; console: A = next key, waiting
CONOUT		equ	0EC0Eh	; console: A to the terminal
DCSP		equ	0F12Ah	; Z80 SP that DOSCALL leaves for trap 1Dh
ENDBIOS		equ	0F12Ch	; end of the resident BIOS: CPMZ80 goes here

	org	0100h
bits 16

; =====================================================================
; BEGIN - .COM entry: over the variables to START
; =====================================================================
BEGIN:
	jmp START	; (E9: MASM's near JMP for the forward reference)

; =====================================================================
; VARIABLES
; ---------------------------------------------------------------------
; BASE and DRIVE are set at START; STGOFF at CHKSZ.  PFCB is the
; program's own FCB (37 bytes: drive, name, extension, then the fields
; DOS fills at OPEN and the random record at +33).
; =====================================================================
BASE:
	dw 0	; CS x 16: this program's linear (= Z80) address
DRIVE:
	db 0	; DOS's current drive (0 = A), becomes the CP/M one
STGOFF:
	dw 0	; offset of STAGE rounded up to a paragraph (0400h)

PFCB:
	db 0,"           "	; drive + 8.3 name: filled from PSP_FCB1

	times 25 db 0	; DOS's FCB fields (+12 .. +36)

; =====================================================================
; PARMS - FCB 1, FCB 2 and the command tail, as the CP/M program gets
; them.  T_CPM receives PARMS's linear address in SI and copies these
; 160 bytes - by then swapped up to SAVE + PARMS - to 005Ch (32 bytes:
; both FCBs) and 0080h (128 bytes: length + tail), as the CCP leaves
; page zero.  The FCBs are 16 bytes each, exactly what DOS function 29h
; writes (MSDOS.LST MAKEFCB: drive, 11 name bytes, then two zero words
; - CP/M's EX, S1, S2, RC all 0, as the CCP leaves them).
; =====================================================================
PARMS:
FCB1:
	db 0,"           ",0,0,0,0	; -> 005Ch: first argument


FCB2:
	db 0,"           ",0,0,0,0	; -> 006Ch: second argument


TAIL:
	times 128 db 0	; -> 0080h: length, upper-case text, then 0s
			;   (the 0 after the text is CP/M's terminator)

; =====================================================================
; MESSAGES - INT 21h AH=09h strings, "$"-terminated
; =====================================================================
USEMSG:
	db "Usage: CPM program [arguments]",13,10,"$"	; no name given
NFMSG:
	db "Program not found",13,10,"$"	; neither .CPM nor .COM opens
BIGMSG:
	db "Program too big",13,10,"$"	; does not fit between SWLEN and P
RDMSG:
	db "Program read error",13,10,"$"	; the read came back short (2026-11-08)
VERMSG:
	db "CPM.COM does not match Z86.SYS",13,10,"$"	; trap 1Ch: CF=1

; =====================================================================
; START - set up, load the Z80 part
; ---------------------------------------------------------------------
; Entry:  from COMMAND.COM: CS=DS=ES=SS = our PSP, FCB 1 (5Ch) holds the
;         first argument parsed by COMMAND, the tail at 80h.
; Exit:   to PROG with the Z80 part at ENDBIOS, or out through MSG.
; DOS calls: AH=19h current disk.  Traps: 1Ch (load).
;
; The stack moves to STKTOP, inside this file and below the image: the
; image is about to be overwritten by the program, and the 128-byte
; stack must survive that.  The Z80 part is copied before the program
; is even looked for: the copy lands over COLD, which only the boot
; needed, so loading it and then stopping on an error is harmless.
; =====================================================================
START:
	mov sp,STKTOP	; our own 128-byte stack, under the image
	cld		; string moves go up (and T_CPM saves DF = 0)
	cmp byte [PSP_FCB1+1],' '	; no program name at all?
	jz short USAGE	; "CPM" alone: the usage line
	mov ah,19h	; AH=19h current disk ...
	int 21h	; AL = 0 for A:, 1 for B: ...
	mov [DRIVE],al	; ... kept for the CP/M program (0 = A)
	mov ax,cs	; BASE = CS x 16: the 8086 memory is the Z80's
	mov cl,4	;   0000h-CFFFh, so a linear address is a Z80
	shl ax,cl	;   address (16 bits: all of it is below 64K)
	mov [BASE],ax	; kept for SWLEN, PARMS and DOSLEN
	mov_d bp,ax	; BP = linear address of the header at Z80 (041Ah)
	add bp,Z80	;   = BASE + 041Ah
	TRAP TRAP_CPM	; T_CPML: check the 7 addresses, copy to ENDBIOS
	jnc short PROG	; CF=0: in place
	mov dx,VERMSG	; CF=1: this CPM.COM was built against another
	jmp short MSG	;   Z86.SYS ("does not match")
	nop		; MASM's padding: the forward JMP was given 3 bytes
			;   (CPM.LST 025D: EB 3E 90)

; =====================================================================
; PROG - open the program: drive and name from DOS's FCB 1, .CPM or .COM
; ---------------------------------------------------------------------
; Entry:  from START.  Exit: to CHKSZ with PFCB open, or out through MSG.
; DOS calls (through OPENP): AH=0Fh open FCB.
;
; An extension typed by the user is used as given.  With none, .CPM is
; tried first, then .COM: a CP/M .COM is Z80 code, and if DOS ran it at
; its prompt it would run it as 8086 code - hence the .CPM convention.
; =====================================================================
PROG:
	mov si,PSP_FCB1	; drive byte + 8.3 name, 12 bytes, as COMMAND
	mov di,PFCB	;   parsed them
	mov cx,12	;   (the rest of PFCB stays 0)
	rep movsb	; PFCB = the program's name
	cmp byte [PFCB+FCB_EXT],' '	; an extension given?
	jnz short OPEN	; yes: that file and no other
	mov byte [PFCB+FCB_EXT],'C'	; none: try name.CPM ...
	mov byte [PFCB+FCB_EXT+1],'P'	; (third letter next)
	mov byte [PFCB+FCB_EXT+2],'M'
	call OPENP	; AH=0Fh open FCB
	jz short CHKSZ	; found
	mov byte [PFCB+FCB_EXT+1],'O'	; ... then name.COM ("CPM" -> "COM")
OPEN:
	call OPENP	; AH=0Fh open FCB
	jz short CHKSZ	; found: size it
NOTFND:
	mov dx,NFMSG	; "Program not found"
	jmp short MSG	; print it and end
USAGE:
	mov dx,USEMSG	; "Usage: CPM program [arguments]"
	jmp short MSG	; print it and end
TOOBIG:
	mov dx,BIGMSG	; "Program too big" (every size check lands here)
; ---------------------------------------------------------------------
; MSG - print DX's "$" string and end: AH=09h print string, INT 20h.
; The common error exit.  Nothing needs undoing: a Z80 part already
; copied over COLD is harmless, and no DOS state was changed but the
; DTA (only when CHKSZ got that far, and it never fails after that).
; ---------------------------------------------------------------------
MSG:
	mov ah,9	; AH=09h print string
	int 21h	; the message
	int 20h		; terminate: back to COMMAND

; =====================================================================
; CHKSZ - size check, memory layout, read the program
; ---------------------------------------------------------------------
; Entry:  PFCB open (DOS filled in the size, record size 128).
; Exit:   falls into the tail builder with, stacked, SWLEN (BX), the
;         program's byte count (CX) and P (DX); the program read to
;         DS:STGOFF = linear SWLEN.  Or TOOBIG.
; DOS calls: AH=1Ah set DTA, AH=27h random block read.
;
;   SWLEN = BASE + STGOFF   (STGOFF = STAGE rounded up to 16: CPMZ80's
;                            XCHGA/XCHGD swap 8 bytes a turn and test
;                            the count only every 8th byte)
;   TOP   = [PSP_TOP] x 16  (the end of the memory DOS gave us)
;   P     = (TOP - PSIZE - SWLEN) AND FF00h
;   so P + PSIZE + SWLEN <= TOP: the P area and SAVE (a copy of
;   0000h-SWLEN) both fit under TOP.  The program is staged at SWLEN
;   and must end below P (T_CPM clears P and fills SAVE before moving
;   it down), hence bytes <= P - SWLEN.  That is the loadable maximum,
;   smaller than the TPA 0100h-P the program then runs in.
;
; The source comment "COMMAND's resident part is above it" is right for
; this COMMAND (1.17H, HIGHMEM): see the preface.  The read's AL result
; is checked since 2026-11-08 (READ_OK).
; =====================================================================
CHKSZ:
	cmp word [PFCB+FCB_SIZEHI],byte 0x0	; 64 KB or more?
	jnz short TOOBIG	; no CP/M program is that big
	mov bx,STAGE+15	; STAGE on a paragraph: CPMZ80
	and bx,0xfff0	;   exchanges in multiples of 8 (041Ah -> 0400h)
	mov [STGOFF],bx	; where the program will be read
	add bx,[BASE]	; BX = SWLEN, linear
	mov dx,[PSP_TOP]	; the end of our memory, a segment: COMMAND's
	mov cl,4	;   resident part starts there
	shl dx,cl	; DX = TOP, linear
	sub dx,PSIZE	; room for the P area ...
	jc short TOOBIG	; TOP below 200h: impossible, but checked
	sub_d dx,bx	; ... and for SAVE (SWLEN bytes) above it
	jc short TOOBIG	; SWLEN does not even fit: too big
	and dx,0xff00	; DX = P, on a page
	mov_d ax,dx	; AX = P - SWLEN: room to stage the program
	sub_d ax,bx	; (P >= SWLEN unless the AND dropped below it)
	jc short TOOBIG	; none at all
	mov cx,[PFCB+FCB_SIZE]	; CX = the program's bytes
	cmp_d cx,ax	; staged copy must end at or below P
	ja short TOOBIG	; more than the room: refuse
	push bx		; SWLEN  } for T_CPM, past the tail builder
	push cx		; bytes  }   (which needs CX, SI, DI)
	push dx		; P      }
	mov dx,[STGOFF]	; AH=1Ah set DTA: DS:STGOFF, over the Z80 image
	mov ah,1ah	;   (already copied to ENDBIOS: no longer needed)
	int 21h	; DOS reads into DS:STGOFF from now on
	mov word [PFCB+FCB_RECSIZ],0x1	; record size 1: CX records = bytes
	mov word [PFCB+FCB_RR],0x0	; from record 0 (bytes 33-34 ...
	mov word [PFCB+FCB_RR+2],0x0	;   ... and 35-36)
	mov dx,PFCB	; AH=27h random block read: CX bytes from the
	mov ah,27h	;   start of the file; AL (0 ok, 1/3 short,
	int 21h		;   2 DTA wrap)
	or_d al,al	; not all of it: a disk error answered with Ignore
	jz short READ_OK	;   must not run half a program (it used to)
	mov dx,RDMSG	; "Program read error"
	jmp short MSG	; print, end
READ_OK:				; (src: RDOK)

; =====================================================================
; The command tail: what follows the program's name, in upper case
; ---------------------------------------------------------------------
; DOS's tail at 81h is "  name args" (the text after "CPM").  Skip the
; blanks and the name; what is left - including the blank that
; separates it from the name, as CP/M's CCP keeps it - becomes TAIL,
; upper-cased (the CCP upper-cases the whole line).  With no arguments
; TAIL stays length 0.  127 bytes at most from DOS: TAIL's 128 always
; keep a 0 after the text.
; =====================================================================
	mov si,PSP_TAIL	; SI = the tail, CX = its length
	mov cl,[PSP_TAILLEN]	; CX = length (0-127)
	xor_d ch,ch
SKIP:
	jcxz short TAILX	; ran out: no arguments
	mov al,[si]
	cmp al,0x20	; blank ...
	jz short SKIP_NEXT	; blank: skip
	cmp al,0x9	; ... or TAB: skip it
	jnz short SKIPNM	; the program's name starts here
SKIP_NEXT:				; (src: SKIP1)
	inc si		; next character
	dec cx	; one character fewer
	jmp short SKIP
SKIPNM:
	jcxz short TAILX	; the name ended the line: no arguments
	mov al,[si]	; next name character
	cmp al,0x20	; a blank or TAB ends the name
	jz short TAIL_START	; blank: the arguments start here
	cmp al,0x9
	jz short TAIL_START
	inc si		; still the name
	dec cx	; one character fewer
	jmp short SKIPNM
TAIL_START:				; (src: TAIL0)
	mov [TAIL],cl	; the CP/M tail length: all that is left
	mov di,TAIL+1	; copy it, from the separating blank on
TCOPY:
	lodsb	; next tail character
	cmp al,'a'	; lower-case letter?
	jc short TCOPY_STORE	; below 'a': as is
	cmp al,'z'
	ja short TCOPY_STORE	; above 'z': as is
	sub al,0x20	; to upper case
TCOPY_STORE:				; (src: TC1)
	stosb	; into TAIL
	loop short TCOPY	; CL characters
TAILX:
	mov si,TAIL+1	; FCB 1 and 2 parsed from TAIL, as the CCP
	mov di,FCB1	;   makes them: AX=2901h parse filename, skip
	mov ax,0x2901	;   leading separators; '*' becomes '?'s
	int 21h	; FCB1 = first argument (blank if none)
	mov di,FCB2	; SI was left after the first name: the second
	mov ax,0x2901	;   AX=2901h parse filename
	int 21h	; FCB2 = second argument

; =====================================================================
; Run it - TRAP 1Ch with BP = 0, then back to COMMAND
; ---------------------------------------------------------------------
; T_CPM's register contract (CPMZ80.ASM header, read from REGS):
;   BX = SWLEN, CX = program bytes, DX = P, SI = linear PARMS,
;   DI = DOSLEN = BASE + 100h (DOS and our PSP: what every DOS call
;   swaps back in), AL = current drive, BP = 0 (run, not load).
; The trap returns only at the CP/M program's warm boot, with DOS and
; this program back in place and our registers restored (CPEXIT).
; DOS calls: AH=0Dh disk reset (writes back DOS's dirty sector buffer:
; volume 3, finding 7 - a CP/M close can leave one), then INT 20h.
; =====================================================================
	pop dx		; P
	pop cx		; bytes
	pop bx		; SWLEN
	mov si,[BASE]	; SI = PARMS, linear: T_CPM finds it in SAVE
	add si,PARMS	;   (BASE + 012Dh)
	xor_d bp,bp	; trap 1CH, BP = 0: run it
	mov di,[BASE]	; DOSLEN: DOS and our PSP
	add di,0x100	;   = BASE + 100h, the end of our PSP
	mov al,[DRIVE]	; the CP/M program's current drive
	TRAP TRAP_CPM	; T_CPM: runs the program; back at its warm boot
	mov ah,0dh	; AH=0Dh disk reset: flush what DOS still holds
	int 21h	; (dirty buffer written, directory current)
	int 20h		; terminate: COMMAND reloads its transient part

; =====================================================================
; OPENP - open PFCB.  Exit: ZF=1 found (AL=0), ZF=0 not found (AL=FFh).
; Corrupts AX, DX.  Callers: PROG (twice).  DOS calls: AH=0Fh open FCB.
; =====================================================================
OPENP:
	mov dx,PFCB	; DS:DX = the FCB to open
	mov ah,0xf	; AH=0Fh open FCB
	int 21h	; AL = 00h found, FFh not
	or_d al,al	; AL = 0: found
	ret	; ZF tells the caller

; ---- the stack: 64 words, 039Ah-0419h ----
	times 64 dw 0
STKTOP:

; =====================================================================
; Z80 / STAGE - the Z80 part (CPMZ80.INC), and where the program lands
; ---------------------------------------------------------------------
; z86.py cpmz80() builds this as a 16-byte header and the code.  Trap
; 1Ch (BP = linear Z80) reads the length, compares the 7 words with
; Z86.SYS's own CPMSYM (14 bytes) and copies the code to ENDBIOS.  Once
; copied, this region is dead: CHKSZ reads the CP/M program over it,
; from STGOFF = 0400h (its first 4 bytes, the length and NEXT, are left
; alone).  The header names the addresses in BIOS.ASM CPMSYM's order;
; the values below are this build's (Z86.SYS.sym).  A mismatch in any
; byte gives "CPM.COM does not match Z86.SYS" (test_fdd86.py group 6
; flips NEXT's low byte to check it).
; =====================================================================
Z80:
STAGE:
Z80_LEN:
	dw Z80_CODE_END-Z80_CODE	; 09CAh = 2506 bytes of code to copy
Z80_SYMS:
	dw NEXT		; D83Bh  must equal Z86.SYS NEXT
	dw JPHL		; EB4Dh  must equal Z86.SYS JPHL
	dw PEEKEY	; EBE3h  must equal Z86.SYS PEEKEY
	dw GETKEY	; EC00h  must equal Z86.SYS GETKEY
	dw CONOUT	; EC0Eh  must equal Z86.SYS CONOUT
	dw DCSP		; F12Ah  must equal Z86.SYS DCSP
	dw ENDBIOS	; F12Ch  must equal Z86.SYS ENDBIOS (the copy target)

; The code, assembled to run at ENDBIOS (F12Ch): CPMZ80.BIN, narrated
; in asm/cpmz80.asm (volume 3).  File offset 032Ah to the end of
; CPM.COM; nothing follows it.  (Path relative to DISASM/, where
; tools/roundtrip.sh assembles.)
Z80_CODE:
	incbin "bin/CPMZ80.BIN"
Z80_CODE_END:
