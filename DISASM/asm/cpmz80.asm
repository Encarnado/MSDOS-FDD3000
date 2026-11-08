;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  3/10
;  CPMZ80.BIN - CPM.COM's Z80 part: a CP/M 2.2 BDOS and BIOS over MS-DOS
;  (Z80, 2506 bytes, runs at F12Ch over Z86.SYS's COLD)
;==============================================================================
;
;  ROLE.  `CPM program [arguments]` runs a CP/M 2.2 program natively on
;  the FDD3000's Z80 with its files on the DOS disk.  CPM.COM (8086) does
;  the loading; this image is what the CP/M program then talks to.  It
;  moves DOS out of the program's way, builds page zero and a page P
;  above the program holding a BDOS entry, an 8086 stub and a 17-entry
;  BIOS jump table, and serves the BDOS calls: console calls straight on
;  the Z80 BIOS's console code, file calls by swapping DOS back in and
;  running one INT 21h on the 8086 interpreter.  DOS 1.25's FCB calls
;  are CP/M's (same numbers, same first 32 bytes of FCB); the rest is
;  translation, plus a 1 KB buffer that batches 8 records per swap.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM  ->  CPM.COM (8086, volume 6): TRAP 1Ch with BP = its
;       copy of this image: Z86.SYS's T_CPML checks the 16-byte header
;       and copies the code to ENDBIOS (F12Ch, over COLD, volume 2)
;     CPM.COM reads the program over that copy (STAGE), builds the FCBs
;       and tail, and calls TRAP 1Ch with BP = 0  ->  THIS IMAGE, T_CPM
;       ->  the CP/M program at 0100h  ->  BDOSE / BIOSV  ->  (file
;       calls) DOSCALL: INT 21h on the interpreter, TRAP 1Dh back
;     warm boot  ->  CPEXIT: DOS back, RET out of TRAP 1Ch into CPM.COM,
;       which resets the disks and exits to COMMAND
;  Inside CPM.COM the image sits at file offset 32Ah behind a 16-byte
;  header at 31Ah (30Ch / 2FCh in the shipped CPM.COM, before its
;  2026-11-08 read check): the length (09CAh) and the Z86.SYS addresses it was
;  assembled against, NEXT D83Bh, JPHL EB4Dh, PEEKEY EBE3h, GETKEY
;  EC00h, CONOUT EC0Eh, DCSP F12Ah, ENDBIOS F12Ch (BIOS.ASM's CPMSYM).
;  Trap 1Ch refuses to copy an image whose header differs ("CPM.COM does
;  not match Z86.SYS").  At run time the 1 KB buffer BUF follows the
;  image at FAF6h-FEF5h; the Z80 stack keeps FF00h-FFFFh.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/cpmz80_findings.md)
;   - BDOSE switches to the Z80 stack above the 8086 memory (SHIMSP):
;     the program's own stack may lie anywhere in the TPA, even in the
;     bottom 9.3 KB that a DOS call swaps away.  But file calls do NOT
;     keep IX, IY or AF' (DOSCALL loads IX = NEXT and the 8086 flags
;     into AF'; the FCB helpers use IY), which an 8080-coded CP/M 2.2
;     BDOS never touches - and a read served from BUF keeps them, so a
;     program that relies on them fails only now and then.
;   - The program's FCB byte 13 (S1) is "the program's own" for DOS's
;     sake, yet FPOS and FBACK read bytes 12-13 as one block number:
;     with an odd S1 the record arithmetic gains 32768 (RC becomes 0,
;     positions jump).  PIP's 7Ch is even, so x128 mod 64K hides it.
;     SETPOS (random reads) writes 0 into the program's S1.
;   - The drive byte, kept at the program's 0, makes MS-DOS 1.25's CLOSE
;     compute unit FFh and skip writing back its dirty sector buffer
;     (MSDOS.LST CLOSE); the sector reaches the disk at the next buffer
;     reuse or CPM.COM's final disk reset (provisional: read from the DOS
;     listing, not run).
;   - F_FCB's own random read/write handling (DMADTA, PADZ, DTADMA, the
;     33/34/40 result codes) is reached only with R2 <> 0, where DOS
;     fails first: a vestige of the version before BUF.
;   - BDOS 6 with E = FEh returns status (a CP/M 3 code), so a CP/M 2.2
;     program cannot output FEh that way; BDOS 14 to a drive DOS lacks
;     is silently refused by DOS but recorded here (BDOS 25 then lies).
;   - Search results are one directory entry per file, RC at most 128,
;     no allocation: files over 16 KB look like one 16 KB extent.  The
;     DPB says 72 records a track; an FDD3000 DOS track holds 36.
;   - Trap 1Ch's header covers 7 Z86.SYS addresses; the REGS fields and
;     the serial routines (SPRN SAUXO SAUXI SLSTS) are also called by
;     address and are not checked.
;
;  HARDWARE.  Ran natively on a real FDD3000 on 2026-11-07: a CP/M
;  program under CPM.COM, files on the DOS disk (notes/hardware_run.md).
;  Which program, and which BDOS calls it made, is not recorded, so the
;  edge findings above stay code findings.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/CPMZ80.BIN with
;  Wijnen z80asm v1.8 (tools/roundtrip.sh).  The image equals CPM.COM
;  from file offset 32Ah to its end (2026-11-08 CPM.COM); the header was
;  checked against ../symbols/z80/Z86.SYS.sym.  Every instruction
;  matches the build listing ../symbols/z80/CPMZ80.lst.
;
;  FILE:    CPMZ80.BIN, 2506 bytes
;  MD5:     f4d8c6cec8c7962e19c87e522de87240
;  SHA256:  7d94cfd8e0c0298bfa9f3c84ec4d263311eb0e9bd8cd692cf964616660a80377
;  SOURCE:  ../project/MSDOS/poc/CPMZ80.ASM (z86.py cpmz80(), build.py
;           CPMZ80.INC)
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  CP/M 2.2
;  interfaces after Digital Research's (BDOS function numbers, FCB, page
;  zero, BIOS jump vector); LIST, PUNCH and READER as the FDD3000 CP/M
;  CBIOS A1.1 (Antonio Nobrega, TMX Portugal, 85/10/29) wires them.
;==============================================================================

; =====================================================================
;                    IMPORTED FROM Z86.SYS (volume 2)
; =====================================================================
; The author's names and values; CPMZ80.ASM is assembled after I86.ASM
; and BIOS.ASM and simply uses their symbols.  The first group, and
; ENDBIOS, are in the trap-1Ch header and checked at load; the rest are
; not (see the preface).

ENDBIOS:	equ	0F12Ch		; end of the resident BIOS: COLD, then this

; ---- REGS page: the 8086 register file the interpreter works on ----
REGS:		equ	0D000h		; start of the page
R_AL:		equ	0D000h		; AL (low byte of AX)
R_AH:		equ	0D001h		; AH: the INT 21h function
R_CX:		equ	0D002h		; T_CPM entry: program bytes (PLEN)
R_DX:		equ	0D004h		; T_CPM entry: P; DOSCALL: the P offset
R_BX:		equ	0D006h		; T_CPM entry: SWLEN
R_SP:		equ	0D008h		; 8086 SP
R_SI:		equ	0D00Ch		; T_CPM entry: linear PARMS (FCBs, tail)
R_DI:		equ	0D00Eh		; T_CPM entry: DOSLEN
R_ES:		equ	0D010h		; segment registers ...
R_CS:		equ	0D012h
R_SS:		equ	0D014h
R_DS:		equ	0D016h
B_ES:		equ	0D018h		; ... and their bases, seg << 4 (16-bit
B_CS:		equ	0D01Ah		;   uses only: an 8-bit operand starting
B_SS:		equ	0D01Ch		;   B_ would be read as register B)
B_DS:		equ	0D01Eh
EADS:		equ	0D020h		; base for DS-relative operands (no override)
EASS:		equ	0D022h		; base for SS-relative operands
					; REGS+0..41 (to STEP2: incl. FLAGHI's DF/IF
					;   and the string steps) is what T_CPM saves

; ---- serial routines in the free end of the REGS page (WD2123) ----
SPRN:		equ	0D03Eh		; A to channel A, the printer (CP/M LIST)
SAUXO:		equ	0D042h		; A to channel B (CP/M PUNCH)
SAUXI:		equ	0D062h		; A from channel B (CP/M READER)
SLSTS:		equ	0D085h		; A = FFh if channel A's CTS is on, else 0

; ---- interpreter and BIOS entries ----
NEXT:		equ	0D83Bh		; the 8086 dispatcher: runs from BC = CS:IP
JPHL:		equ	0EB4Dh		; JP (HL): CALL JPHL is an indirect call
PEEKEY:		equ	0EBE3h		; CF=1: a key waits (A, kept for GETKEY)
GETKEY:		equ	0EC00h		; A = next key, waiting for one
CONOUT:		equ	0EC0Eh		; A to the terminal (CBIOS's link send)
DCSP:		equ	0F12Ah		; Z80 SP saved by DOSCALL for trap 1Dh

; =====================================================================
;                    LAYOUT CONSTANTS (CPMZ80.ASM's header)
; =====================================================================
; The P area: a 512-byte page that CPM.COM chose just above the
; program's memory (P = (TOP - 200h - SWLEN) AND FF00h).  The 8086 sees
; it as segment SEGP = P >> 4, so every offset below is also an 8086
; offset for INT 21h.  It is never swapped, so it is where everything
; DOS must see during a call lives.
;
;   P+00h-05h  zero; the program's initial SP is P (pushes go below)
;   P+06h      JP BDOSE                    ((0006h) points here)
;   P+09h      CD 21 0F 1D: INT 21h, TRAP 1Dh   (the 8086 stub)
;   P+10h-34h  the scratch FCB, 37 bytes (DOS's FCB is one longer)
;   P+38h-5Ch  the FCB of search first / next
;   P+60h-DFh  DOS's DTA, one 128-byte record
;   P+100h     17 x JP: the CP/M BIOS vector ((0001h) = P+103h)
;   P+1FFh     downwards: the 8086 stack (SS:SP = SEGP:0200h)
;   P+200h     SAVE: where the bottom of memory waits

PBDOS:		equ	06h		; JP BDOSE: (0006h) points here
PSTUB:		equ	09h		; 8086: INT 21h, TRAP 1Dh
PFCB:		equ	10h		; the FCB of a call (37 bytes)
PSRCH:		equ	38h		; the FCB of search first / next
PDTA:		equ	60h		; DOS's DTA (128 bytes)
PBIOS:		equ	100h		; BIOS jump table, (0001h) = P+103h
PSTK:		equ	200h		; 8086 SP: DOS pushes about 26 bytes below
PSIZE:		equ	200h		; the whole P area
NBUF:		equ	8		; records in BUF (1 KB)

; ---- counts ----
REGS_SAVED:	equ	42		; REGS bytes kept in SAVREG (AX..STEP2)
NBDOS:		equ	41		; BDOS functions 0-40 in BDTAB
NBIOS:		equ	17		; CP/M 2.2 BIOS entries, BOOT..SECTRAN
RECLEN:		equ	128		; a CP/M record; DOS record size here

; ---- CP/M page zero ----
IOBYTE:		equ	0003h		; CP/M's I/O byte (kept, means nothing)
CDISK:		equ	0004h		; current drive (user number 0 above it)
TFCB:		equ	005Ch		; default FCB 1 (FCB 2 at 006Ch)
TBUFF:		equ	0080h		; command tail, then the default DMA
TPA:		equ	0100h		; where a CP/M program loads and starts

; ---- the FCB, CP/M's names (DOS 1.25's meaning of the byte after) ----
FCB_EX:		equ	12		; extent (DOS: current block, low byte)
FCB_S1:		equ	13		; reserved, PIP uses it (DOS: block, high)
FCB_S2:		equ	14		; extent high (DOS: record size, low)
FCB_RC:		equ	15		; records in this extent (DOS: rec size, hi)
FCB_D0:		equ	16		; allocation d0-d15 (DOS: file size 16-19,
					;   date 20-21, own state 22-31 - DEVID at
					;   24 holds the drive DOS really uses)
FCB_CR:		equ	32		; current record (DOS: the same)
FCB_R2:		equ	35		; random record r0 r1 r2 (DOS: 33-36)
FCB_LEN:	equ	36		; a CP/M FCB with random record
DFCB_LEN:	equ	37		; a DOS FCB: one byte more (r3)
DIR_SIZE:	equ	28		; directory entry: file size (as boot.asm)


	org	ENDBIOS

; =====================================================================
; T_CPM - run the staged CP/M program (trap 1Ch, BP = 0)
; ---------------------------------------------------------------------
; Entry:  from Z86.SYS's T_CPML (JP Z,ENDBIOS), inside TRAP: the Z80
;         stack holds TRAP's return to TRAPX, its saved IX and BC (the
;         8086 code pointer, just past CPM.COM's 0F 1C) and the
;         interpreter's return.  REGS = CPM.COM's registers:
;           BX = SWLEN: CPM.COM's end, linear; DOS and CPM.COM are below
;                it.  The program lies there.  (COMMAND 1.17 is built with
;                HIGHMEM: its resident part sits above the memory top that
;                PSP offset 2 reports, outside the swap - volume 6.)
;           DX = P (page-aligned)       CX = program bytes
;           SI = linear PARMS: FCB 1 (16), FCB 2 (16), tail (128)
;           DI = DOSLEN: CPM.COM's PSP + 256, linear
;           AL = current drive          AF' = CPM.COM's 8086 flags
; Exit:   never returns here: JP TPA.  The trap returns later, from
;         CPEXIT, on the stack frame saved in SHIMSP.
;
; The order matters: DOS is still in place for the one DOS call made
; here (set DTA), and only then is the bottom of memory swapped out.
; The staged program sits at SWLEN, exactly where the swap ends (STAGE
; follows CPM.COM's code), so the swap leaves it alone and it can be
; copied down to 0100h.  T_CPM trusts CPM.COM's arithmetic: P above
; the program, SAVE + SWLEN below the top of CPM.COM's memory.
; =====================================================================
T_CPM:
	ld	hl,REGS		; CPM.COM's 8086 state: the template for every
	ld	de,SAVREG	;   DOSCALL, and what CPEXIT puts back
	ld	bc,REGS_SAVED	; AX..STEP2, the flags' high half included
	ldir			; SAVREG = REGS
	ex	af,af'		; the 8086's arithmetic flags live in AF'
	push	af		;   (CPM.COM did CLD: DF = 0 is in FLAGHI,
	pop	hl		;   already saved above)
	ld	(SAVAF),hl	; kept for DOSCALL and CPEXIT
	ex	af,af'		; (the Z80's own AF back)
	ld	hl,(R_BX)	; the arguments of the call, out of REGS
	ld	(SWLEN),hl	;   before DOSCALL overwrites them:
	ld	hl,(R_DI)	;   swap lengths, program size, PARMS
	ld	(DOSLEN),hl	; 0000h-DOSLEN: what a DOS call needs
	ld	hl,(R_CX)	; bytes staged at SWLEN
	ld	(PLEN),hl	; (may be 0)
	ld	hl,(R_SI)	; where FCB 1, FCB 2 and the tail are
	ld	(PARAM),hl	; (linear, still below SWLEN)
	ld	a,(R_AL)	; DOS's current drive ...
	ld	(CPDSK),a	; ... is the program's
	ld	hl,(R_DX)	; P itself
	ld	(PAGE),hl	; the P area
	ld	de,PSIZE	; the save area follows the P area
	add	hl,de		; P + 200h
	ld	(SAVE),hl	; the bottom of memory waits here
	ld	hl,(PAGE)	; P's 8086 segment, P >> 4, for DOSCALL
	ld	b,4		; four 16-bit right shifts
T_CPM_SEG_SHIFT:			; (src: TC1)
	srl	h		; H:L >> 1, high bit in from 0 ...
	rr	l		; ... the bit out of H into L
	djnz	T_CPM_SEG_SHIFT	; four times
	ld	(SEGP),hl	; P / 16
	ld	hl,(PAGE)	; clear the whole P area (unused bytes are 0:
	ld	d,h		;   the scratch FCBs start clean) - the usual
	ld	e,l		;   overlapping LDIR fill, one byte ahead
	inc	de		; DE = HL + 1
	ld	(hl),0		; the seed byte
	ld	bc,PSIZE-1	; and 511 copies of it
	ldir			; P area all 0
	ld	ix,(PAGE)	; IX = P while the page is built
	ld	(ix+PBDOS),0C3h	; P+06h: JP BDOSE, the BDOS entry a CP/M
	ld	hl,BDOSE	;   program finds through (0006h)
	ld	(ix+PBDOS+1),l	; BDOSE, low byte
	ld	(ix+PBDOS+2),h	; BDOSE, high byte
	ld	(ix+PSTUB),0CDh	; P+09h: the 8086 stub DOSCALL runs at
	ld	(ix+PSTUB+1),21h	;   SEGP:0009h - CD 21 = INT 21h ...
	ld	(ix+PSTUB+2),0Fh	; ... 0F 1D = TRAP 1Dh: Z86.SYS's T_RET,
	ld	(ix+PSTUB+3),1Dh	;   which lands back in DOSCALL's caller
	ld	hl,(PAGE)	; P+100h: the CP/M BIOS vector, 17 JPs built
	ld	de,PBIOS	;   from the addresses in BIOSV
	add	hl,de		; HL = P+100h
	ex	de,hl		; DE = where the next JP goes
	ld	hl,BIOSV	; HL = the next address in BIOSV
	ld	b,NBIOS		; BOOT .. SECTRAN
T_CPM_BIOS_JP:				; (src: TC2)
	ld	a,0C3h		; JP opcode ...
	ld	(de),a		; P+100h+3i: C3
	inc	de		; (next byte of the JP)
	ld	a,(hl)		; ... low byte of the target ...
	ld	(de),a		; P+100h+3i+1
	inc	hl		; BIOSV entry, high byte next
	inc	de		; (next byte of the JP)
	ld	a,(hl)		; ... high byte
	ld	(de),a		; P+100h+3i+2
	inc	hl		; next entry
	inc	de		; next JP slot (3 bytes on)
	djnz	T_CPM_BIOS_JP	; 17 entries
	ld	a,1Ah		; DOS 1Ah, set DTA: SEGP:PDTA, for good - every
	ld	de,PDTA		;   record DOS moves goes through P+60h
	call	DOSCALL		; (DOS is still in: no swap needed)
	ld	(SHIMSP),sp	; the trap's frame: BDOSE runs on this stack and
					;   CPEXIT's RET from here goes back to TRAP
	call	XCHGA		; DOS and CPM.COM out to SAVE; the
					;   program, at SWLEN, is just past the swap
	ld	hl,(SWLEN)	; the program down to 0100h (downward copy:
	ld	de,TPA		;   LDIR is safe, destination below source)
	ld	bc,(PLEN)	; its length
	ld	a,b		; an empty program: LDIR with BC = 0 would
	or	c		;   move 64 KB
	jr	z,T_CPM_PAGE0	; nothing to move
	ldir			; the program in place at 0100h
T_CPM_PAGE0:				; (src: TC3)
	ld	hl,0		; page zero 0000h-00FFh to zeros: IOBYTE 0,
	ld	b,l		;   drive 0 / user 0, FCB tails clear (B = 0:
T_CPM_CLR_PAGE0:			;   256 turns) (src: TC4)
	ld	(hl),0		; (what XCHGA brought down was junk)
	inc	l		; L only: stays in page zero
	djnz	T_CPM_CLR_PAGE0	; page zero clear
	ld	a,0C3h		; 0000h: JP WBOOT, 0005h: JP BDOS, as CP/M
	ld	(0000h),a	; 0000h: JP (to WBOOT)
	ld	(0005h),a	; 0005h: JP (to BDOSE via P+06h)
	ld	hl,(PAGE)	; (0001h) = P+103h, the WBOOT entry: programs
	ld	de,PBIOS+3	;   find the BIOS vector as (0001h) - 3
	add	hl,de		; HL = P+103h
	ld	(0001h),hl	; 0000h's target
	ld	hl,(PAGE)	; (0006h) = P+06h: the BDOS entry, and the top
	ld	de,PBDOS	;   of the TPA for programs that size memory
	add	hl,de		;   from it
	ld	(0006h),hl	; 0005h's target
	ld	a,(CPDSK)	; current drive, user 0
	ld	(CDISK),a	; page zero's drive byte
	ld	hl,(SAVE)	; FCB 1, FCB 2 and the tail CPM.COM built: its
	ld	de,(PARAM)	;   PARMS moved up with it, to SAVE + PARAM
	add	hl,de		;   (PARAM < SWLEN: inside the swapped range)
	ld	de,TFCB		; 005Ch-007Bh: both FCBs, 16 bytes each, as the
	ld	bc,32		;   CCP leaves them (7Ch-7Fh stay 0: FCB 1's CR
	ldir			;   and random record)
	ld	de,TBUFF	; 0080h: length byte + upper-case tail (HL
	ld	bc,RECLEN	;   follows on from the FCBs)
	ldir			; (from SAVE + PARAM + 32)
	ld	hl,TBUFF	; the default DMA, as after the CCP
	ld	(DMAADR),hl	; (BDOS 26 changes it)
	xor	a		; the screen is taken to be at column 0 (the
	ld	(COL),a		;   command line ended with CR LF)
	ld	hl,(PAGE)	; the program's stack starts at P, just under
	ld	sp,hl		;   its BDOS entry
	ld	hl,0		; a RET from the program goes to 0000h: warm
	push	hl		;   boot, as the CCP's stack does
	jp	TPA		; run it

; =====================================================================
; CPEXIT - warm boot: DOS back, CPM.COM's registers, return from trap
; ---------------------------------------------------------------------
; Entry:  any stack - from BDOS 0 (BDTAB), BIOS BOOT and WBOOT (BIOSV,
;         so JP 0000h and a RET to the 0 that T_CPM pushed), or ^C on an
;         empty line in BDOS 10.
; Exit:   RET into Z86.SYS's TRAPX on the trap-1Ch frame: IX and BC are
;         popped there, so CPM.COM resumes after its 0F 1C with the
;         registers and flags it had when it called.
;
; Records still in BUF are written (no close: as under CP/M, a file the
; program did not close loses its directory update; a write error here
; goes unreported).  The swap is its own inverse: the second XCHGA
; brings DOS back and parks the program's image in the save area,
; where it is forgotten.
; =====================================================================
CPEXIT:
	ld	sp,(SHIMSP)	; the trap's frame, wherever the program was
	call	FLUSH		; pending buffered writes to the file
	call	XCHGA		; DOS and CPM.COM back at 0000h
	ld	hl,SAVREG	; CPM.COM's 8086 registers ...
	ld	de,REGS		;   (the last DOSCALL left DOS's in REGS)
	ld	bc,REGS_SAVED	; the whole saved block
	ldir			; REGS = CPM.COM's again
	ld	hl,(SAVAF)	; ... and its arithmetic flags, into AF'
	push	hl		; through the stack ...
	pop	af		; ... into AF ...
	ex	af,af'		; (trap 1Ch's CF is whatever CPM.COM had)
	ret			; to TRAPX: the 8086 goes on at MOV AH,13

; =====================================================================
; XCHGA / XCHGD - swap the bottom of memory with the save area
; ---------------------------------------------------------------------
; XCHGA:  exchanges 0000h..SWLEN-1 with SAVE..: DOS, CPM.COM's PSP and
;         code (DOS in <-> program in).  COMMAND's resident part is not in
;         it: HIGHMEM puts it at the top (volume 6, cpmcom_findings 1).
; XCHGD:  only 0000h..DOSLEN-1: DOS and CPM.COM's PSP, all a DOS call
;         needs.  A prefix of XCHGA's
;         range, so XCHGD in / XCHGD out may be nested inside it.
; Exit:   BC = 0; HL, DE past the ranges.  Corrupts A, F.
; Callers: T_CPM, CPEXIT (XCHGA); DOSX, RD_FILL, FLUSH (XCHGD).
;
; Both lengths are multiples of 16 (CPM.COM puts STAGE on a paragraph
; and BASE = CS * 16), which the loop needs: it swaps 8 bytes per
; turn and tests BC only after the 8th LDI (any other length would
; run on through 64 KB).  The LDI does the move one way and counts;
; A carries the other byte back.  About 0.2 s for DOSLEN = 9.3 KB.
; While DOS is in, the program's 0000h-DOSLEN waits at SAVE: nothing
; may touch the program's memory then - hence the copies through P.
; =====================================================================
XCHGA:
	ld	bc,(SWLEN)	; everything below the program's staging
	jr	XCHG_LEN	; (BC = SWLEN)
XCHGD:
	ld	bc,(DOSLEN)	; DOS and the PSP only
XCHG_LEN:				; (src: XC0)
	ld	hl,0		; the bottom of memory ...
	ld	de,(SAVE)	; ... against the save area above P
XCHG_8:					; 8 swaps per turn (src: XC1)
	ld	a,(de)		; 1: A = the save area's byte
	ldi			; (DE) <- (HL); both up; BC - 1
	dec	hl		; back to the low byte's place ...
	ld	(hl),a		; ... and the save area's byte into it
	inc	hl		; on
	ld	a,(de)		; 2
	ldi			; (the same four steps for bytes 2-8)
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 3
	ldi
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 4
	ldi
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 5
	ldi
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 6
	ldi
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 7
	ldi
	dec	hl
	ld	(hl),a
	inc	hl
	ld	a,(de)		; 8
	ldi			; P/V = (BC <> 0) after this one
	dec	hl		; (DEC / INC rr and LD leave P/V alone)
	ld	(hl),a
	inc	hl
	jp	pe,XCHG_8	; more to go
	ret			; BC = 0: both ranges swapped

; =====================================================================
; DOSCALL - run one INT 21h on the 8086 interpreter and come back
; ---------------------------------------------------------------------
; Entry:  A = AH (the DOS function), DE = DX (an offset in P).  DOS must
;         be swapped in.
; Exit:   REGS holds DOS's results (AL = R_AL); every Z80 register and
;         AF', IX are lost (IX ends as NEXT, AF' as the 8086 flags).
; Callers: T_CPM, DOSX, RD_FILL_NEXT, FLUSH_REC.
;
; The Z80 SP goes to DCSP; the 8086 is set up from CPM.COM's registers
; (SAVREG: so BP, SI, DI, AL, DF and IF are CPM.COM's) with CS = DS =
; ES = SS = SEGP, SP = 0200h, IP = 0009h, the stub.  JP (IX) = NEXT
; starts interpreting: INT 21h pushes FLAGS CS IP on P's 8086 stack and
; enters DOS through vector 21h (page zero is DOS's again); DOS's IRET
; comes back to SEGP:000Bh, 0F 1D, and Z86.SYS's T_RET reloads SP from
; DCSP (clearing it) and RETs - to DOSCALL's caller.  The interpreter's
; own frames below DCSP are just abandoned.  This INT 21h runs nested:
; CPM.COM's own trap 1Ch is still open in TRAP higher up the stack.
; An abort from DOS's critical-error handler would end CPM.COM without
; ever reaching T_RET (untested; README: ~30 bytes of Z80 stack lost).
; =====================================================================
DOSCALL:
	ld	(DCSP),sp	; trap 1Dh returns to our caller from here
	push	af		; keep the function and the offset over the
	push	de		;   copy
	ld	hl,SAVREG	; start from CPM.COM's 8086 state
	ld	de,REGS		; over REGS ...
	ld	bc,REGS_SAVED	; ... the saved part
	ldir			; REGS = CPM.COM's (AL = its drive, too)
	pop	de		; DE = the P offset again
	pop	af		; A = the function again
	ld	(R_AH),a	; AH = function (AL stays CPM.COM's: the drive)
	ld	(R_DX),de	; DS:DX = P:offset - the FCB, DTA or 0
	ld	hl,(SEGP)	; all four segments = P's paragraph
	ld	(R_ES),hl	; ES: so calls using ES see P
	ld	(R_CS),hl	; CS: the stub's segment
	ld	(R_SS),hl	; SS: P's 8086 stack
	ld	(R_DS),hl	; DS: the FCB / DTA's segment
	ld	hl,(PAGE)	; and their bases = P (linear = Z80 address)
	ld	(B_ES),hl	; the interpreter adds these bases to every
	ld	(B_CS),hl	;   offset: they must agree with the
	ld	(B_SS),hl	;   segment values above
	ld	(B_DS),hl
	ld	(EADS),hl	; no segment override in force
	ld	(EASS),hl	; (SS-relative operands: BP, the stack)
	ld	de,PSTUB	; BC = host address of the stub: CS base + IP
	add	hl,de		; P + 9
	ld	b,h		; BC = the 8086 code pointer
	ld	c,l		; (CS:IP = SEGP:0009h)
	ld	hl,PSTK		; 8086 SP = 0200h: the top of the P area
	ld	(R_SP),hl	; SS:SP = P:0200h
	ld	hl,(SAVAF)	; 8086 arithmetic flags = CPM.COM's
	push	hl		; through the stack ...
	pop	af		; ... into AF ...
	ex	af,af'		; (the interpreter's flag register)
	ld	ix,NEXT		; the dispatcher register, as the interpreter
	jp	(ix)		;   requires - and go: INT 21h, then TRAP 1Dh

; =====================================================================
; DOSX - DOSCALL with DOS swapped in around it
; ---------------------------------------------------------------------
; Entry:  A = AH, DE = DX (P offset); DOS out.   Exit: A = AL, DOS out.
; Corrupts everything else (as DOSCALL).  Callers: F_RST, F_SEL, F_FCB,
; F_SRCH.  The record loops (RD_FILL, FLUSH) swap once for several
; calls and use DOSCALL themselves.
; =====================================================================
DOSX:
	push	af		; XCHGD loses A and the registers
	push	de		; (the offset)
	call	XCHGD		; DOS in; the program's 0000h-DOSLEN to SAVE
	pop	de		; DE = the P offset
	pop	af		; A = the function
	call	DOSCALL		; the call itself
	call	XCHGD		; DOS out again, the program back
	ld	a,(R_AL)	; DOS's result
	ret			; A = AL; DOS out, the program's memory back

; =====================================================================
; BDOSE - the CP/M BDOS entry (CALL 0005h -> JP P+06h -> here)
; ---------------------------------------------------------------------
; Entry:  C = function, DE = parameter (E for byte parameters).
; Exit:   HL = result, A = L, B = H (CP/M 2.2's convention); SP back
;         to the program's.  Every other register may be lost - in
;         particular IX, IY and AF' after a file call (see the preface).
;
; The program's stack is used for nothing but CALL 5's return address:
; handlers run on the trap's Z80 stack (SHIMSP, above the 8086 memory),
; since a file call swaps 0000h-DOSLEN away, possibly with the program's
; stack in it.  Functions 41 and up return 0.
; =====================================================================
BDOSE:
	ld	(USRSP),sp	; the program's stack, for the way back
	ld	sp,(SHIMSP)	; work on the Z80's own stack
	ld	hl,0		; HL = 0: the answer to an unknown function
	ld	a,c		; the function number
	cp	NBDOS		; 0-40 only
	jr	nc,BDOSE_RET	; 41 and up: HL = 0
	ld	l,a		; HL = BDTAB + 2 * C
	add	hl,hl		; HL = 2 * C (H = 0)
	push	de		; keep the parameter
	ld	de,BDTAB	; the table ...
	add	hl,de		; HL -> BDTAB[C]
	pop	de		; DE = the parameter again
	ld	a,(hl)		; HL = the handler
	inc	hl		; high byte ...
	ld	h,(hl)		; ... into H ...
	ld	l,a		; ... and L: HL = the handler
	call	JPHL		; call it, C and DE as the program gave them
BDOSE_RET:				; (src: BD1)
	ld	a,l		; A = L, B = H, as CP/M 2.2's BDOS returns
	ld	b,h		; (the BDOS result convention)
	ld	sp,(USRSP)	; back on the program's stack
	ret			; to the program, after its CALL 5

; ---------------------------------------------------------------------
; BDTAB - the 41 BDOS functions, by CP/M 2.2 number (F325h)
; ---------------------------------------------------------------------
BDTAB:
	defw	CPEXIT, F_CIN, F_COUT, F_RDR	; 0 System Reset (warm boot),
					;   1 Console Input, 2 Console Output,
					;   3 Reader Input (serial channel B)
	defw	F_PUN, F_LST, F_DIO, F_GIOB	; 4 Punch Output (channel B),
					;   5 List Output (channel A), 6 Direct
					;   Console I/O, 7 Get IOBYTE
	defw	F_SIOB, F_PRT, F_RDL, F_CST	; 8 Set IOBYTE, 9 Print String,
					;   10 Read Console Buffer, 11 Get Console
					;   Status
	defw	F_VER, F_RST, F_SEL, F_FCB	; 12 Return Version Number,
					;   13 Reset Disk System, 14 Select Disk,
					;   15 Open File (DOS 0Fh)
	defw	F_FCB, F_SRCH, F_SRCH, F_FCB	; 16 Close File (DOS 10h),
					;   17 Search for First (11h), 18 Search for
					;   Next (12h), 19 Delete File (13h)
	defw	F_RSEQ, F_WSEQ, F_FCB, F_FCB	; 20 Read Sequential (via BUF,
					;   DOS 14h), 21 Write Sequential (BUF,
					;   15h), 22 Make File (16h), 23 Rename
					;   File (17h)
	defw	F_LOGV, F_CUR, F_DMA, F_ALV	; 24 Return Login Vector,
					;   25 Return Current Disk, 26 Set DMA
					;   Address, 27 Get Addr(Alloc)
	defw	F_ZERO, F_ZERO, F_ZERO, F_DPB	; 28 Write Protect Disk, 29 Get
					;   R/O Vector, 30 Set File Attributes:
					;   all "done" doing nothing; 31 Get
					;   Addr(Disk Parms)
	defw	F_ZERO, F_RRND, F_WRND, F_FCB	; 32 Set/Get User Code (always
					;   user 0), 33 Read Random (BUF), 34 Write
					;   Random (BUF), 35 Compute File Size (23h)
	defw	F_FCB, F_ZERO, F_ZERO, F_ZERO	; 36 Set Random Record (24h),
					;   37 Reset Drive (nothing), 38-39 not in
					;   CP/M 2.2 (CP/M 3 Access/Free Drive): 0
	defw	F_WRND				; 40 Write Random with Zero Fill
					;   (as 34: DOS has no zero fill)

; =====================================================================
; F_ZERO / RETA - common BDOS returns
; ---------------------------------------------------------------------
; F_ZERO: HL = 0 (success, or "nothing to report").  RETA: HL = A.
; Most handlers end with JR / JP to one of them.
; =====================================================================
F_ZERO:
	xor	a		; result 0
RETA:
	ld	l,a		; HL = A, H = 0: BDOSE copies them to A, B
	ld	h,0		; (the result's high byte)
	ret			; to BDOSE_RET

; =====================================================================
; F_CIN - BDOS 1, Console Input: a key, echoed
; ---------------------------------------------------------------------
; Waits for a key.  Printable keys (20h up, DEL included) and CR are
; echoed through OUTCH; CP/M 2.2 also echoes LF, TAB and BS, and checks
; ^S / ^P - neither is done here.
; =====================================================================
F_CIN:
	call	GETKEY		; A = the key (waits; a key PEEKEY took first
	push	af		;   comes out of KBUF)
	cp	20h		; printable: echo it
	call	nc,OUTCH	; (OUTCH keeps the column right)
	pop	af		; the key again (OUTCH keeps only BC DE HL)
	push	af		; keep it for the next test
	cp	13		; CR: echo it too (the terminal returns)
	call	z,OUTCH		; (column back to 0)
	pop	af		; A = the key
	jr	RETA		; the key to the program

; F_COUT - BDOS 2, Console Output: E to the screen, tabs expanded
F_COUT:
	ld	a,e		; the character
	call	OUTCH		; keeps COL for tabs and for BDOS 10's rubouts
	jr	F_ZERO		; A = 0

; ---------------------------------------------------------------------
; F_RDR / F_PUN / F_LST - BDOS 3, 4, 5 on the WD2123's serial channels
; READER and PUNCH are channel B (AUX), LIST channel A (PRN), as in CBIOS
; A1.1.  The routines in the REGS page wait for ever (HL = 0 polls).
; ---------------------------------------------------------------------
F_RDR:
	call	SAUXI		; A = a byte from channel B
	jr	RETA		; A = the byte
F_PUN:
	ld	a,e		; E to channel B
	call	SAUXO		; waits for the channel
	jr	F_ZERO		; A = 0
F_LST:
	ld	a,e		; E to channel A, the printer
	call	SPRN		; waits for the printer (CTS, TxRDY)
	jr	F_ZERO		; A = 0

; =====================================================================
; F_DIO - BDOS 6, Direct Console I/O
; ---------------------------------------------------------------------
; E = FFh: a key if one waits, else 0 (no wait, no echo).
; E = FEh: console status, as BDOS 11 - CP/M 3's code; under CP/M 2.2
;          FEh is just a character, which a program cannot send here.
; Else:    E to the terminal raw: no tab expansion, COL not kept (CP/M
;          2.2's direct output does not count columns either).
; =====================================================================
F_DIO:
	ld	a,e		; the parameter
	inc	a		; FFh?
	jr	z,F_DIO_IN	; FFh: a key or 0
	inc	a		; FEh?
	jr	z,F_CST		; FEh: status
	ld	a,e		; anything else: output it as it is
	call	CONOUT		; raw output: COL not kept
	jr	F_ZERO		; A = 0
F_DIO_IN:				; (src: DIO1)
	call	PEEKEY		; CF=1: a key is there (kept in KBUF)
	ld	a,0		; (LD keeps CF) none: 0
	jr	nc,RETA		; A = 0, no key
	call	GETKEY		; take the key PEEKEY saw
	jr	RETA		; A = the key

; F_GIOB / F_SIOB - BDOS 7 / 8: the IOBYTE at 0003h, read or set.  It
; is kept for programs that look at it but steers nothing.
F_GIOB:
	ld	a,(IOBYTE)	; as the program last set it (0 at start)
	jr	RETA		; A = IOBYTE

F_SIOB:
	ld	a,e		; stored, nothing else
	ld	(IOBYTE),a	; page zero's byte
	jr	F_ZERO		; A = 0

; F_PRT - BDOS 9, Print String: from DE to the first '$' (not printed)
F_PRT:
	ld	a,(de)		; next character
	cp	'$'		; the terminator
	jr	z,F_ZERO	; '$': done, A = 0
	call	OUTCH		; keeps DE
	inc	de		; next character
	jr	F_PRT		; until the '$'

; F_CST - BDOS 11, Get Console Status: FFh if a key waits, else 0.  The
; link cannot look at a key without taking it, so PEEKEY takes it and
; keeps it in KBUF for the next GETKEY.
F_CST:
	call	PEEKEY		; CF=1: a key
	ld	a,0		; no key: 0
	jr	nc,RETA		; A = 0
	dec	a		; a key: FFh
	jr	RETA		; A = FFh

; F_VER - BDOS 12: HL = 0022h - CP/M 2.2 (B = 0: 8080 CP/M, not MP/M)
F_VER:
	ld	hl,0022h	; version 2.2
	ret			; (A = 22h, B = 0 via BDOSE)

; =====================================================================
; F_RST - BDOS 13, Reset Disk System;  F_SEL - BDOS 14, Select Disk
; ---------------------------------------------------------------------
; Reset: pending writes out, DMA back to 0080h, DOS 0Dh (which writes
; DOS's dirty buffer and FATs), then select drive A, as CP/M 2.2 does.
; Select: E = drive (0 = A).  The drive goes to CPDSK and (0004h) and
; to DOS 0Eh - whose answer is not looked at: MS-DOS 1.25's SELDSK
; ignores a drive >= NUMDRV, yet CPDSK keeps it, so BDOS 25 then reports
; a drive DOS is not on (CP/M would stop with "Bdos Err On x: Select").
; =====================================================================
F_RST:
	call	FLUSH		; the buffered records first
	ld	hl,TBUFF	; DMA = 0080h
	ld	(DMAADR),hl	; (where CP/M's reset leaves it)
	ld	a,0Dh		; DOS 0Dh, disk reset
	call	DOSX		; (DOS in and out: DOSX)
	ld	e,0		; then drive A
F_SEL:
	push	de		; FLUSH loses DE
	call	FLUSH		; the file in BUF belongs to the old drive
	pop	de		; E = the drive
	ld	a,e		; the drive
	ld	(CPDSK),a	; what BDOS 25 reports
	ld	(CDISK),a	; and page zero's copy (user 0)
	ld	a,0Eh		; DOS 0Eh, select disk: DL = E
	call	DOSX		; (the drive count it returns is ignored)
	jp	F_ZERO		; A = 0

; F_LOGV - BDOS 24: login vector 0003h, drives A: and B: (whatever the
; machine has)
F_LOGV:
	ld	hl,3		; A: and B:
	ret			; (A = 3, B = 0 via BDOSE)

; F_CUR - BDOS 25: the drive last selected here
F_CUR:
	ld	a,(CPDSK)	; (not asked of DOS: see F_SEL)
	jp	RETA		; A = the drive

; F_DMA - BDOS 26: where records go to and come from in the program
F_DMA:
	ld	(DMAADR),de	; used by every record copy and by DIRENT
	jp	F_ZERO		; A = 0

; F_ALV / F_DPB - BDOS 27 / 31: the fake allocation vector and DPB that
; describe the DOS disk as a 1 KB-block CP/M disk (see DPB)
F_ALV:
	ld	hl,ALLOCV	; all zero: every block free
	ret			; (HL = its address)

F_DPB:
	ld	hl,DPB		; the DPB below
	ret			; (HL = its address)

; =====================================================================
; F_RDL - BDOS 10, Read Console Buffer
; ---------------------------------------------------------------------
; Entry:  DE -> buffer: max length, count (filled in), text.
; Exit:   count set; CR echoed (no LF, as CP/M 2.2's BDOS); A = 0.
;
; Editing: BS and DEL rub out one character (BS space BS - CP/M 2.2
; echoes the deleted character on DEL instead), ^U and ^X the whole
; line, ^C on an empty line is a warm boot (elsewhere it is dropped).
; Every other code, controls included, is stored and echoed raw;
; characters past the maximum are dropped.  A rubout always backs one
; column, so rubbing out a TAB or a control character leaves the screen
; out of step (CP/M 2.2 retypes the line for that).
; B = count so far, C = max; the count byte's address stays on the stack.
; =====================================================================
F_RDL:
	ex	de,hl		; HL -> max
	ld	c,(hl)		; C = max
	inc	hl		; HL -> count
	push	hl		; -> count, kept on the stack throughout
	ld	b,0		; nothing typed yet
F_RDL_KEY:				; (src: RL1)
	push	bc		; GETKEY loses BC
	call	GETKEY		; next key
	pop	bc		; B, C: count and max
	pop	hl		; HL -> count, and put back
	push	hl		; (the count pointer stays on the stack)
	cp	13		; CR or LF: the line is done
	jr	z,RLEND		; CR
	cp	10		; LF: CP/M accepts either
	jr	z,RLEND		; LF ends it too
	cp	8		; BS or DEL: rub one out
	jr	z,RLBS		; BS
	cp	7Fh		; DEL, the other rubout key
	jr	z,RLBS		; DEL: rubout
	cp	15h		; ^U, ^X: rub out the whole line
	jr	z,RLKILL	; ^U
	cp	18h		; ^X, the same
	jr	z,RLKILL	; ^X: kill
	cp	3		; ^C ...
	jr	nz,F_RDL_STORE	; anything else: store it
	inc	b		; ... on an empty line: warm boot
	dec	b		; (INC / DEC: Z if B = 0)
	jp	z,CPEXIT	; warm boot: the program ends here
	jr	F_RDL_KEY	; ... anywhere else: ignored
F_RDL_STORE:				; (src: RL2)
	ld	d,a		; D = the character
	ld	a,b		; count so far ...
	cp	c		; buffer full: drop it
	jr	nc,F_RDL_KEY	; (B >= C)
	inc	b		; one more
	ld	e,b		; DE = B, the offset from the count byte
	push	de		; keep the character in D
	ld	d,0		; DE = B
	add	hl,de		; HL = count + B: text[B-1]
	pop	de		; D = the character again
	ld	(hl),d		; store it
	ld	a,d		; for the echo
	push	bc		; (B, C: count and max)
	call	OUTCH		; and echo it (OUTCH keeps BC; pushed anyway)
	pop	bc		; count and max back
	jr	F_RDL_KEY	; next key
RLBS:
	inc	b		; nothing to rub out?
	dec	b		; (Z if B = 0)
	jr	z,F_RDL_KEY	; empty: ignore
	dec	b		; one character less ...
	push	bc		; (B, C: count and max)
	call	RUBOUT		; ... and off the screen
	pop	bc		; count and max back
	jr	F_RDL_KEY	; next key
RLKILL:
	inc	b		; until the line is empty ...
	dec	b		; (Z if B = 0)
	jr	z,F_RDL_KEY	; line empty: done
	dec	b		; ... one less ...
	push	bc		; (B, C over RUBOUT)
	call	RUBOUT		; ... rubbed out
	pop	bc		; count and max back
	jr	RLKILL		; again
RLEND:
	pop	hl		; HL -> count
	ld	(hl),b		; the length typed (the CR is not stored)
	ld	a,13		; the cursor back to column 0 - CR only, as
	call	OUTCH		;   CP/M 2.2's BDOS ends a line read
	jp	F_ZERO		; A = 0

; RUBOUT - BS, space, BS: erase the character left of the cursor.  The
; last BS falls through into OUTCH (a tail call).
RUBOUT:
	ld	a,8		; back ...
	call	OUTCH		; BS
	ld	a,' '		; ... blank it ...
	call	OUTCH		; space over the old character
	ld	a,8		; ... and back again (into OUTCH)

; =====================================================================
; OUTCH - A to the screen, keeping the column; TAB to the next 8
; ---------------------------------------------------------------------
; Entry:  A = character.   Keeps BC, DE, HL (CONOUT uses A, BC, DE).
; COL counts printable characters (20h up, DEL too), goes to 0 on CR and
; back one on BS; LF and other controls leave it.  It is the BDOS's
; column, as CP/M's: BIOS CONOUT and BDOS 6 output bypass it.
; Callers: F_CIN, F_COUT, F_PRT, F_RDL and RUBOUT.
; =====================================================================
OUTCH:
	push	bc		; the caller's registers survive CONOUT
	push	de		; (CONOUT uses DE)
	push	hl		; (and HL here)
	cp	9		; TAB?
	jr	nz,OUTCH_ONE	; one character
OUTCH_TAB:				; (src: OC1)
	ld	a,' '		; spaces, at least one ...
	call	OUTCH_COL	; one space ...
	ld	a,(COL)		; ... where are we now?
	and	7		; ... until the column is a multiple of 8
	jr	nz,OUTCH_TAB	; not yet at a tab stop
	jr	OUTCH_RET	; done
OUTCH_ONE:				; (src: OC2)
	call	OUTCH_COL	; any other character, once
OUTCH_RET:				; (src: OC4)
	pop	hl		; restore the caller's
	pop	de
	pop	bc
	ret			; to the caller
OUTCH_COL:				; keep COL, then send (src: OC3)
	push	af		; the character, for CONOUT
	ld	hl,COL		; HL -> the column
	cp	13		; CR: column 0
	jr	z,OUTCH_COL_CR	; CR
	cp	8		; BS: one back
	jr	z,OUTCH_COL_BS	; BS
	cp	20h		; other controls: no move
	jr	c,OUTCH_SEND	; control: column unchanged
	inc	(hl)		; printable: one on
	jr	OUTCH_SEND	; send it
OUTCH_COL_CR:				; (src: OC5)
	ld	(hl),0		; carriage return
	jr	OUTCH_SEND	; send it
OUTCH_COL_BS:				; (src: OC6)
	ld	a,(hl)		; not past column 0
	or	a		; (Z if column 0)
	jr	z,OUTCH_SEND	; already 0
	dec	(hl)		; one column back
OUTCH_SEND:				; (src: OC7)
	pop	af		; the character again
	jp	CONOUT		; to the terminal (CONOUT's RET is ours)

; =====================================================================
; F_FCB - the FCB calls passed to DOS one for one
; ---------------------------------------------------------------------
; Entry:  C = CP/M function = DOS function: 15 open, 16 close, 19
;         delete, 22 make, 23 rename, 35 file size, 36 set random
;         record; also 33 / 34 / 40 from F_RRND / F_WRND when R2 <> 0.
;         DE -> the program's FCB.
; Exit:   HL = A = CP/M's code: 0 / FFh as DOS says; FFh for a close
;         after buffered writes failed; 33: 1, 34/40: 2 or 1 for DOS's
;         other codes.
;
; Pending writes first (FLUSH), then TOSCR copies the FCB into P with
; S1 = 0, and except for open / delete / make / rename (DOS sets or
; ignores it) the record size 128 goes where CP/M keeps S2 and RC.
; After the call FBACK copies DOS's position, random record and its own
; state back, with S2 = 0 and the RC that CP/M would show.  An open also
; leaves a directory record at the DMA (DIRENT), as the source says
; CP/M's BDOS does (provisional for open: CP/M 2.2's BDOS copies the
; directory record to the DMA for a search; for an open it is not
; established here).
; The 33 / 34 / 40 branches below (DMADTA, PADZ, DTADMA, F_FCB_RDERR,
; F_FCB_WRERR) only see R2 <> 0, a record past 8 MB that DOS rejects
; before moving data: they are the pre-BUF random I/O, now vestigial.
; =====================================================================
F_FCB:
	push	bc		; FLUSH loses them
	push	de		; (the FCB)
	call	FLUSH		; anything buffered goes out first (and BMODE
	pop	de		;   = 0: no read-ahead survives a file call)
	pop	bc		; C = the function
	ld	(UFCB),de	; the program's FCB
	ld	a,c		; the function ...
	ld	(CPFN),a	; the function, for the cases below
	call	TOSCR		; FCB -> P+PFCB, S1 = 0, byte 36 = 0
	ld	a,(CPFN)	; record size 128 where CP/M has S2, RC -
	cp	15		;   but not for open, delete, make, rename:
	jr	z,F_FCB_DTA	;   open and make set it themselves
	cp	19		; (delete: wildcards, no record size needed)
	jr	z,F_FCB_DTA	; delete: as DOS has it
	cp	22		; (make: DOS sets 128)
	jr	z,F_FCB_DTA	; make: as DOS has it
	cp	23		; (rename: new name at 16, as CP/M)
	call	nz,SETRS	; close, size, set random (and 33/34/40)
F_FCB_DTA:				; (src: FF1)
	ld	a,(CPFN)	; a random write: the record to the DTA
	cp	34		; random write?
	jr	z,F_FCB_COPYREC	; yes: the record goes too
	cp	40		; (40 with R2 <> 0)
	jr	nz,F_FCB_FN	; no record to move
F_FCB_COPYREC:				; (src: FF2)
	call	DMADTA		; (before the swap: the DMA may be low)
F_FCB_FN:				; (src: FF3)
	ld	a,(CPFN)	; the DOS function = the CP/M one ...
	cp	40		; zero fill?
	jr	nz,F_FCB_CALL	; no: the same number
	ld	a,34		; ... but zero fill is plain 22h: DOS has none
F_FCB_CALL:				; (src: FF4)
	ld	de,PFCB		; DOS function A on the scratch FCB
	call	DOSX		; DOS in, the call, DOS out
	ld	(FRES),a	; DOS's code
	call	SCRFCB		; DOS's FCB back to the program's: position,
	call	FBACK		;   random record, DOS's state; S2, RC
	ld	a,(CPFN)	; an open that found the file: its directory
	cp	15		;   record at the DMA
	jr	nz,F_FCB_RRD	; not an open
	ld	a,(FRES)	; found?
	or	a		; (0: found)
	jr	nz,F_FCB_RRD	; no: no record
	ld	hl,(UFCB)	; A = the RC FBACK just set
	ld	de,FCB_RC	; -> RC
	add	hl,de
	ld	a,(hl)		; A = RC
	ld	hl,(UFCB)	; HL -> the program's name (wildcards and all:
	inc	hl		;   the name DOS matched is not copied back)
	call	DIRENT		; directory record at the DMA
F_FCB_RRD:				; (src: FF5)
	ld	a,(CPFN)	; a random read: the record to the DMA
	cp	33		;   (vestigial, see above)
	jr	nz,F_FCB_CLOSE	; not a random read
	ld	a,(FRES)	; DOS's code
	cp	3		; partial record: ^Z after the end, and it
	jr	nz,F_FCB_RRD_OK	;   counts as read
	call	PADZ		; pad the DTA
	xor	a		; treat as success
	ld	(FRES),a
F_FCB_RRD_OK:				; (src: FR4)
	ld	a,(FRES)	; read: the DTA to the DMA
	or	a		; (0: a record)
	call	z,DTADMA	; the record to the program
F_FCB_CLOSE:				; (src: FR5)
	ld	a,(CPFN)	; a close after buffered writes that failed:
	cp	16		;   FFh, though DOS did close the file.  FERR
	jr	nz,F_FCB_CODE	;   may come from any file's FLUSH - the one
	ld	a,(FERR)	;   closed or another
	or	a		; (any write error pending?)
	jr	z,F_FCB_CODE	; none: as DOS says
	xor	a		; reported once
	ld	(FERR),a
	ld	a,0FFh		; "close failed"
	jp	RETA		; A = FFh
F_FCB_CODE:				; DOS's codes -> CP/M's (src: FR8)
	ld	a,(FRES)	; DOS's code
	or	a		; 0: success
	jp	z,RETA		; 0: as it is
	cp	0FFh		; FFh: not found / no room, the same in both
	jp	z,RETA		; FFh: as it is
	ld	b,a		; anything else depends on the call
	ld	a,(CPFN)	; which call?
	cp	33		; random read?
	jr	z,F_FCB_RDERR
	cp	34		; random write?
	jr	z,F_FCB_WRERR
	cp	40		; ... with zero fill?
	jr	z,F_FCB_WRERR
	ld	a,b		; others: DOS's code as it is
	jp	RETA		; A = DOS's code
F_FCB_RDERR:				; (src: FR6)
	ld	a,1		; read: 1, reading unwritten data
	jp	RETA		; A = 1
F_FCB_WRERR:				; (src: FR7)
	dec	b		; write: DOS 1 (disk full) -> 2, no data
	ld	a,2		;   block ...
	jp	z,RETA		; A = 2
	dec	a		; ... DOS 2 (DTA wrap, impossible here) -> 1
	jp	RETA		; A = 1

; =====================================================================
; THE RECORD BUFFER - sequential and random reads and writes
; ---------------------------------------------------------------------
; BUF (FAF6h, after the image) holds NBUF = 8 records of one file, so
; one DOS swap moves up to 8 records (ASM TX went from 25 s to 9.7 s).
;
;   BMODE 0  empty.
;   BMODE 1  read-ahead: BUF holds BCNT records from record BPOS of the
;            FCB at address BFCB; BEOF = 1 if the file ends after them.
;            BSHAD = DOS's FCB after the first of them (what the
;            program got).  Reading record BPOS+k (k < BCNT) is a copy.
;   BMODE 2  write-behind: BCNT records to write from record BPOS for
;            the FCB at BFCB; WRND = 1 if they came by random writes.
;            BSHAD = DOS's FCB positioned at BPOS.
;
; The file is recognised by the FCB's ADDRESS (BFCB), not its name.
; Every other file call, select, reset, search and warm boot FLUSHes
; first (writes mode 2, drops mode 1).  Errors of the deferred writes
; surface at the next write (code 2) or close (FFh) - of whatever file.
; Hazards (by code reading): a program that abandons an unclosed FCB
; and reuses its memory gets FBACK written over it at the next FLUSH;
; a program that closes a copy of the FCB closes it with the size from
; before the pending records went out.
; =====================================================================

; ---------------------------------------------------------------------
; F_RSEQ - BDOS 20, Read Sequential: the record at the FCB's position
; F_RRND - BDOS 33, Read Random: the record R0 R1; the FCB is set to
;          that record, not past it (CP/M's rule)
; Exit:    A = 0 read, 1 end of file (for random: unwritten data).
; ---------------------------------------------------------------------
F_RSEQ:
	ld	(UFCB),de	; the program's FCB
	call	FPOS		; HL = EX * 128 + CR
	xor	a		; sequential
	jr	RD_ANY		; (A = 0)
F_RRND:
	ld	(UFCB),de	; the program's FCB
	ld	hl,FCB_R2	; R2 <> 0: record 65536 on, 8 MB out - let
	add	hl,de		;   DOS say so through F_FCB
	ld	a,(hl)		; R2
	or	a		; zero?
	jr	z,F_RRND_POS	; yes: a record DOS can address
	ld	c,33		; (C is 33 already)
	jp	F_FCB		; (DOS answers: past the end)
F_RRND_POS:				; HL = R1 R0 (src: RR1)
	dec	hl		; R1 ...
	ld	d,(hl)		; high byte
	dec	hl		; ... R0
	ld	e,(hl)		; low byte
	ex	de,hl		; HL = the record wanted
	ld	a,1		; random
RD_ANY:					; (src: RD0)
	ld	(RRND),a	; the kind of read
	ld	(RPOS),hl	; the record wanted
	ld	a,(BMODE)	; read-ahead of this very FCB?
	dec	a		; (BMODE 1 -> 0, and A = 0)
	jr	nz,RD_FILL	; no read-ahead in BUF
	ld	de,(BFCB)	; BUF's FCB ...
	ld	hl,(UFCB)	; ... against this call's
	or	a		; (A = 0: CF clear for SBC)
	sbc	hl,de		; same FCB address?
	jr	nz,RD_FILL	; another FCB: read afresh
	ld	hl,(RPOS)	; k = RPOS - BPOS, 0..255?
	ld	de,(BPOS)	; BUF's first record
	sbc	hl,de		; (CF still clear from the last SBC)
	jr	c,RD_FILL	; before the buffer
	ld	a,h		; k >= 256?
	or	a
	jr	nz,RD_FILL	; far after it
	ld	a,(BCNT)	; within BCNT?
	cp	l		; k against BCNT
	jr	z,RD_AT_END	; just after the records
	jr	c,RD_FILL	; further on: read afresh
	ld	a,l		; one of them: copy it to the DMA, no DOS
	call	BUFREC		; HL = BUF[k]
	ld	de,(DMAADR)	; to the program's DMA
	ld	bc,RECLEN	; one record
	ldir			; copied
	call	RDPOS		; the FCB past it (or at it, random)
	jp	F_ZERO		; read
RD_AT_END:				; (src: RS1)
	ld	a,(BEOF)	; the file ended there: say so without DOS
	or	a		; (1: no more)
	jr	z,RD_FILL	; it did not: fetch the next 8
	ld	a,1		; end of file
	jp	RETA		; A = 1
RD_FILL:				; read up to NBUF records (src: RS2)
	call	FLUSH		; pending writes out, BMODE = 0
	call	TOSCR		; the FCB to P, S1 = 0
	call	SETRS		; record size 128
	ld	a,(RRND)	; sequential: DOS reads from the FCB's place
	or	a		; random?
	jr	z,RD_FILL_GO	; no: DOS reads on from the FCB
	call	SCRFCB		; random: position DOS's FCB at RPOS
	ex	de,hl		; DE -> scratch FCB
	ld	hl,(RPOS)	; the record wanted
	call	POSTO		; block and CR of the scratch FCB
RD_FILL_GO:				; (src: RS2A)
	xor	a		; BUF empty, no end seen yet
	ld	(BCNT),a	; no records yet
	ld	(BEOF),a	; no end seen
	call	XCHGD		; DOS in, once for all the records
RD_FILL_NEXT:				; (src: RS3)
	ld	a,14h		; DOS 14h, sequential read, to the DTA
	ld	de,PFCB		; on the scratch FCB
	call	DOSCALL		; DOS is in: straight to DOSCALL
	ld	a,(R_AL)	; DOS's result
	or	a		; 0: a whole record
	jr	z,RD_FILL_TAKE	; a whole record
	cp	3		; 3: the last, partial one
	jr	nz,RD_FILL_EOF	; 1 / 2: nothing more
	call	PADZ		; ^Z after its end (DOS left zeros)
	ld	a,1		; and the file ends after it
	ld	(BEOF),a	; end after this one
RD_FILL_TAKE:				; (src: RS4)
	ld	a,(BCNT)	; DTA -> BUF[BCNT]
	call	BUFREC		; HL -> BUF[BCNT]
	ex	de,hl		; DE = destination in BUF
	ld	hl,(PAGE)	; HL = the DTA in P
	ld	bc,PDTA		; + the DTA offset
	add	hl,bc		; HL = the DTA
	ld	bc,RECLEN	; one record
	ldir			; into BUF
	ld	hl,BCNT		; one more
	inc	(hl)		; BCNT + 1
	ld	a,(hl)		; the new count
	dec	a		; was it the first?
	jr	nz,RD_FILL_MORE	; not the first
	call	SCRFCB		; after the first record: the FCB the program
	ld	de,BSHAD	;   gets (DOS's, one record on)
	ld	bc,DFCB_LEN	; 37 bytes
	ldir			; BSHAD = DOS's FCB after record 1
RD_FILL_MORE:				; (src: RS5)
	ld	a,(BEOF)	; until the end of the file ...
	or	a		; end of file seen?
	jr	nz,RD_FILL_DONE	; yes: stop
	ld	a,(BCNT)	; ... or a full buffer
	cp	NBUF		; buffer full?
	jr	c,RD_FILL_NEXT	; room: read on
	jr	RD_FILL_DONE	; full: stop
RD_FILL_EOF:				; (src: RS6)
	ld	a,1		; DOS says end of file
	ld	(BEOF),a	; no more records
RD_FILL_DONE:				; (src: RS7)
	call	XCHGD		; DOS out
	ld	a,(BCNT)	; anything read?
	or	a		; (0: nothing at all)
	jr	nz,RD_FILL_OK	; some: serve the first
	call	SCRFCB		; none at all: end of file; the program's FCB
	call	FBACK		;   as DOS left it
	ld	a,(RRND)	; random read?
	or	a
	call	nz,SETPOS	; (random: at the record asked for)
	ld	a,1		; end of file
	jp	RETA		; A = 1
RD_FILL_OK:				; (src: RS8)
	ld	a,1		; BUF is now this file's read-ahead
	ld	(BMODE),a	; read-ahead
	ld	hl,(UFCB)	; of this FCB ...
	ld	(BFCB),hl	; BUF's FCB
	ld	hl,(RPOS)	; ... from this record
	ld	(BPOS),hl	; BUF's first record
	ld	hl,BSHAD	; the program's FCB one record on, as if read
	call	FBACK		;   alone
	ld	a,(RRND)	; random read?
	or	a
	call	nz,SETPOS	; random: back at RPOS
	xor	a		; and the first record to the DMA
	call	BUFREC		; HL -> BUF[0]
	ld	de,(DMAADR)	; to the DMA
	ld	bc,RECLEN	; one record
	ldir			; copied
	jp	F_ZERO		; read

; ---------------------------------------------------------------------
; RDPOS - after a record from or to BUF: the program's FCB past it
;         (sequential, FNEXT) or at it (random, SETPOS).
; SETPOS - the program's FCB to record RPOS.
; POSTO - the FCB at DE to record HL: byte 12 = HL / 128 (low), byte 13
;         = its high bit, CR = HL MOD 128.  Corrupts A, BC, HL, DE.
; Byte 13 is DOS's block high byte - and the program's S1: SETPOS
; writes 0 there for any record below 32768 (the source's "the program's
; own byte stays" does not hold for random reads).  EX is not split
; into EX / S2 the CP/M way: harmless up to 512 KB, beyond any disk here.
; Nothing here updates RC: after a buffered read crosses into the next
; extent, RC stays the old extent's until the next DOS read.
; ---------------------------------------------------------------------
RDPOS:
	ld	a,(RRND)	; random?
	or	a
	jp	z,FNEXT		; sequential: one on
SETPOS:
	ld	de,(UFCB)	; random: the record itself
	ld	hl,(RPOS)	; the record
POSTO:
	ld	a,l		; CR = record MOD 128
	and	7Fh		; (7 bits)
	push	hl		; keep the record
	ld	hl,FCB_CR	; -> the FCB's CR
	add	hl,de		; HL -> CR
	ld	(hl),a		; CR set
	pop	hl		; HL = the record
	ex	de,hl		; HL -> FCB, DE = record
	ld	bc,FCB_EX	; -> byte 12
	add	hl,bc		; HL -> byte 12
	ld	a,e		; (DE >> 7) AND FFh: bit 7 of E into carry,
	rla			;   then D shifted left over it
	ld	a,d		; D, shifted ...
	rla			; ... with E's top bit
	ld	(hl),a		; byte 12: block, low
	inc	hl		; -> byte 13
	ld	a,d		; bit 15 of the record
	rlca			; bit 15 to bit 0
	and	1		; only it
	ld	(hl),a		; byte 13: block, high (S1 to CP/M)
	ret

; ---------------------------------------------------------------------
; F_WSEQ - BDOS 21, Write Sequential: the DMA record at the FCB's place
; F_WRND - BDOS 34 / 40, Write Random (with zero fill): at R0 R1, the
;          FCB set to that record.  DOS writes the run sequentially from
;          its first record (MBASIC's SAVE writes this way).
; Exit:    A = 0 accepted (the write itself may happen later), 2 if
;          the previous run could not be written (disk full).
; Zero fill (40) is not done: records skipped over keep whatever the
; newly allocated clusters held.
; ---------------------------------------------------------------------
F_WSEQ:
	ld	(UFCB),de	; the program's FCB
	call	FPOS		; HL = the FCB's record
	xor	a		; sequential
	jr	WR_ANY		; (A = 0)
F_WRND:
	ld	(UFCB),de	; the program's FCB
	ld	hl,FCB_R2	; R2 <> 0: DOS refuses it (through F_FCB,
	add	hl,de		;   C still 34 or 40)
	ld	a,(hl)		; R2
	or	a		; zero?
	jp	nz,F_FCB	; no: past the end, DOS answers
	dec	hl		; HL = R1 R0
	ld	d,(hl)		; high byte
	dec	hl		; -> R0
	ld	e,(hl)		; low byte
	ex	de,hl		; the record to write
	ld	a,1		; random
WR_ANY:					; (src: WR0)
	ld	(RRND),a	; the kind of write
	ld	(RPOS),hl	; and where
	ld	a,(BMODE)	; append to the run in BUF? only if: write mode,
	cp	2		;   the same FCB, the same kind (sequential or
	jr	nz,WR_FLUSH	;   random), room, and this record follows on
	ld	de,(BFCB)	; BUF's FCB ...
	ld	hl,(UFCB)	; ... against this call's
	or	a		; same FCB address?
	sbc	hl,de		; (CF clear)
	jr	nz,WR_FLUSH	; another FCB
	ld	a,(WRND)	; same kind?
	ld	hl,RRND		; this call's kind
	cp	(hl)		; same as the run's?
	jr	nz,WR_FLUSH	; sequential after random or back
	ld	a,(BCNT)	; room?
	cp	NBUF		; 8 already?
	jr	nc,WR_FLUSH	; full
	ld	e,a		; DE = BCNT
	ld	d,0
	ld	hl,(BPOS)	; BPOS + BCNT = RPOS?
	add	hl,de		; BPOS + BCNT: the next record
	ld	de,(RPOS)	; the record asked for
	or	a		; (CF clear)
	sbc	hl,de		; equal?
	jr	z,WR_APPEND	; the next record of the run
WR_FLUSH:				; (src: WS2)
	call	FLUSH		; write the old run, start a new one
	ld	a,(FERR)	; the records before could not be written:
	or	a		;   report it on this write, which is dropped
	jr	z,WR_START	; none: start a run
	xor	a		; reported once
	ld	(FERR),a	; reported once
	ld	a,2		; disk full
	jp	RETA		; A = 2
WR_START:				; (src: WS1)
	ld	a,2		; a new run of writes
	ld	(BMODE),a	; write-behind
	xor	a		; empty yet
	ld	(BCNT),a	; empty
	ld	hl,(UFCB)	; for this FCB ...
	ld	(BFCB),hl	; BUF's FCB
	ld	hl,(RPOS)	; ... from this record
	ld	(BPOS),hl	; BUF's first record
	ld	hl,(UFCB)	; BSHAD = the FCB as it is now, DOS's 37th byte
	ld	de,BSHAD	;   0 ...
	ld	bc,FCB_LEN	; 36 bytes
	ldir			; copied
	xor	a
	ld	(de),a		; byte 36 = 0
	ld	(BSHAD+FCB_S1),a	; ... and S1 0, not the program's (see TOSCR)
	ld	a,(RRND)	; random?
	ld	(WRND),a	; the run's kind
	or	a
	jr	z,WR_APPEND	; sequential: BSHAD is already at the place
	ld	de,BSHAD	; random: DOS writes from that record on
	ld	hl,(RPOS)	; the record
	call	POSTO		; block and CR of BSHAD
WR_APPEND:				; (src: WS3)
	ld	a,(BCNT)	; the DMA record into BUF[BCNT]
	call	BUFREC		; HL -> BUF[BCNT]
	ex	de,hl		; DE = BUF[BCNT]
	ld	hl,(DMAADR)	; from the program's DMA
	ld	bc,RECLEN	; one record
	ldir			; copied
	ld	hl,BCNT		; one more in the run
	inc	(hl)		; BCNT + 1
	call	RDPOS		; the program's FCB past it (or at it, random)
	jp	F_ZERO		; "written"

; =====================================================================
; FLUSH - write the run collected in BUF; BUF is empty after it
; ---------------------------------------------------------------------
; Exit:   BMODE = 0.  After a write run: FERR = DOS's code (0, or 1 disk
;         full: the records from the failing one on are lost); the
;         program's FCB at BFCB as DOS left it.  UFCB kept.  Corrupts
;         all registers.  Mode 1 (read-ahead) is simply dropped, FERR
;         untouched.
; Callers: CPEXIT, F_RST, F_SEL, F_FCB, RD_FILL, WR_FLUSH, F_SRCH.
;
; DOS writes the run with sequential writes (15h) from BSHAD's
; position.  The program's FCB then gets DOS's state through FBACK -
; but after random writes its position and R0-R2 are put back as the
; program set them (CP/M does not move a random writer's FCB, and
; MBASIC counts in R0 R1).
; =====================================================================
FLUSH:
	ld	a,(BMODE)	; what is in BUF?
	cp	2		; a write run?
	ld	a,0		; (LD keeps Z) BUF empty either way
	ld	(BMODE),a	; (Z still from the CP)
	ret	nz		; read-ahead or nothing: done
	ld	hl,(UFCB)	; the caller's FCB, put back at the end
	push	hl		; (UFCB is restored at the end)
	ld	hl,(PAGE)	; BSHAD -> P+PFCB, record size 128
	ld	de,PFCB		; + scratch FCB offset
	add	hl,de		; HL = scratch FCB
	ex	de,hl		; DE = scratch FCB
	ld	hl,BSHAD	; from BSHAD
	ld	bc,DFCB_LEN	; 37 bytes
	ldir			; copied
	call	SETRS		; record size 128
	call	XCHGD		; DOS in
	xor	a		; from the first record of the run
	ld	(BIDX),a	; BIDX = 0
FLUSH_REC:				; (src: FLU1)
	ld	a,(BIDX)	; BUF[BIDX] -> the DTA
	call	BUFREC		; HL -> BUF[BIDX]
	push	hl		; (kept over the DTA arithmetic)
	ld	hl,(PAGE)	; P
	ld	de,PDTA		; + DTA offset
	add	hl,de		; HL = the DTA
	ex	de,hl		; DE = the DTA
	pop	hl		; HL = the record in BUF
	ld	bc,RECLEN	; one record
	ldir			; BUF -> DTA
	ld	a,15h		; DOS 15h, sequential write
	ld	de,PFCB		; on the scratch FCB
	call	DOSCALL		; DOS is in: straight to DOSCALL
	ld	a,(R_AL)	; DOS's result
	or	a		; (0: written)
	jr	nz,FLUSH_END	; failed: stop, A = the code
	ld	hl,BIDX		; next record
	inc	(hl)		; BIDX + 1
	ld	a,(BCNT)	; all done?
	cp	(hl)
	jr	nz,FLUSH_REC	; until all BCNT
	xor	a		; all written
FLUSH_END:				; (src: FLU2)
	ld	(FERR),a	; 0, or the error for the next write / close
	call	XCHGD		; DOS out
	ld	hl,(BFCB)	; the run's FCB: keep its position (bytes
	ld	(UFCB),hl	;   12-13) and CR R0 R1 R2 (32-35), for a
	ld	de,FCB_EX	;   random run - MBASIC counts in R0 R1
	add	hl,de		; HL -> byte 12
	ld	de,PSAVE	; bytes 12-13 -> PSAVE+0..1
	ld	bc,2		; 2 bytes
	ldir			; PSAVE+0..1 = bytes 12-13
	ld	bc,FCB_CR-FCB_S2	; (HL at byte 14) -> byte 32
	add	hl,bc		; HL -> byte 32
	ld	c,4		; (B = 0 after the LDIR) 32-35 -> PSAVE+2..5
	ldir			; PSAVE+2..5 = CR R0 R1 R2
	call	SCRFCB		; DOS's FCB after the run -> the program's
	call	FBACK		; (UFCB = BFCB)
	ld	a,(WRND)	; a random run?
	or	a
	jr	z,FLUSH_RET	; sequential: DOS's position is the program's
	ld	hl,(UFCB)	; random: put the saved fields back
	ld	de,FCB_EX	; -> byte 12
	add	hl,de
	ex	de,hl		; DE -> the program's byte 12
	ld	hl,PSAVE	; the saved block
	ld	bc,2		; 2 bytes
	ldir			; bytes 12-13 back
	ld	hl,FCB_CR-FCB_S2	; (DE at byte 14) -> byte 32
	add	hl,de		; DE -> byte 32 (HL used as scratch)
	ex	de,hl		; DE -> the program's CR
	ld	hl,PSAVE+2	; the saved CR R0 R1 R2
	ld	bc,4		; CR R0 R1 R2
	ldir			; back
FLUSH_RET:				; (src: FLU3)
	pop	hl		; the caller's FCB again
	ld	(UFCB),hl	; UFCB as the caller left it
	ret

; =====================================================================
;                    THE FCB TRANSLATION HELPERS
; =====================================================================

; ---------------------------------------------------------------------
; TOSCR - the program's FCB (UFCB) to the scratch FCB in P
; Copies bytes 0-35, sets DOS's byte 36 (r3) to 0 and byte 13 to 0:
; CP/M's S1, which programs may use (PIP stores 7Ch there copying from a
; device), is to DOS the high byte of the block number - a nonzero one
; sent the write far past the end of the disk.  Corrupts A, BC, DE, HL,
; IY.  (DOS ignores r3 anyway at record size 128: SETUP's "ignore MSB".)
; The drive byte goes as the program has it: 0 means DOS's default
; drive at each call (read and write go by DOS's DEVID byte instead;
; close by byte 0 - see the preface).
; ---------------------------------------------------------------------
TOSCR:
	call	SCRFCB		; HL = scratch FCB ...
	ex	de,hl		; ... as destination
	ld	hl,(UFCB)	; from the program's FCB
	ld	bc,FCB_LEN	; the 36 bytes CP/M defines
	ldir			; copied
	xor	a		; byte 36: r3, DOS's only
	ld	(de),a		; byte 36 = 0
	ld	iy,(PAGE)	; byte 13 is CP/M's S1, which programs may
	ld	(iy+PFCB+FCB_S1),a	;   use (PIP does); to DOS it is the
	ret			;   high byte of the block number

; SCRFCB - HL = the scratch FCB, P+PFCB.  Corrupts DE.
SCRFCB:
	ld	hl,(PAGE)	; P
	ld	de,PFCB		; + scratch FCB offset
	add	hl,de		; HL = P+10h
	ret

; SETRS - the scratch FCB's record size (bytes 14-15) = 128.  Corrupts IY.
SETRS:
	ld	iy,(PAGE)	; IY = P
	ld	(iy+PFCB+FCB_S2),RECLEN	; where CP/M has S2 ...
	ld	(iy+PFCB+FCB_RC),0	; ... and RC
	ret

; DMADTA - the record at the program's DMA to DOS's DTA in P
DMADTA:
	ld	hl,(PAGE)	; DE = the DTA
	ld	de,PDTA		; + DTA offset
	add	hl,de
	ex	de,hl		; DE = the DTA
	ld	hl,(DMAADR)	; HL = the program's record
	ld	bc,RECLEN	; one record
	ldir			; copied
	ret

; DTADMA - DOS's DTA in P to the program's DMA
DTADMA:
	ld	hl,(PAGE)	; HL = the DTA
	ld	de,PDTA		; + DTA offset
	add	hl,de		; HL = the DTA
	ld	de,(DMAADR)	; DE = the program's buffer
	ld	bc,RECLEN	; one record
	ldir			; copied
	ret

; ---------------------------------------------------------------------
; PADZ - the DTA holds the file's last, partial record: ^Z after its end
; The valid bytes are the file size MOD 128 (scratch FCB bytes 16-19);
; DOS filled the rest with zeros, CP/M text ends at ^Z.  Corrupts A,
; B, DE, HL, IY.  (A DOS binary file of odd length gets ^Z, not 0, in
; its last record - CP/M files are whole records anyway.)
; ---------------------------------------------------------------------
PADZ:
	ld	iy,(PAGE)	; IY = P
	ld	a,(iy+PFCB+FCB_D0)	; size, low byte ...
	and	7Fh		; ... MOD 128 = bytes in the last record
	ret	z		; a whole record: nothing to pad
	ld	e,a		; DE = n
	ld	d,0
	ld	hl,(PAGE)	; HL -> the first byte past the data
	add	hl,de		; P + n
	ld	de,PDTA		; + DTA offset
	add	hl,de		; HL = DTA + n
	neg			; B = 128 - n bytes of ^Z
	add	a,RECLEN
	ld	b,a		; B = the count
PADZ_FILL:				; (src: PZ1)
	ld	(hl),1Ah	; ^Z, CP/M's end of text
	inc	hl		; next byte
	djnz	PADZ_FILL	; to the record's end
	ret

; ---------------------------------------------------------------------
; FBACK - an FCB after DOS (HL) back into the program's (UFCB)
; Copies byte 12 and bytes 14-35: position, DOS's file size, date and
; own state (in CP/M's allocation bytes d0-d15: the program's FCB is
; where DOS's state lives between calls), CR, R0-R2.  Not bytes 0-11:
; DOS writes the drive's number into byte 0 of an FCB it opens, CP/M
; leaves the program's 0 (MBASIC's NAME compares them).  Not byte 13,
; the program's S1.  Then S2 = 0 and RC = the records of this extent:
; (size + 127) / 128 - EX * 128, clamped to 0..128.
; Caution: EX * 128 is computed from the program's bytes 12-13, S1
; included: an odd S1 adds 32768 and RC comes out 0 (PIP's 7Ch is even:
; x128 wraps it to 0).  Corrupts all registers and IY.
; Callers: F_FCB, RD_FILL_DONE, RD_FILL_OK, FLUSH.
; ---------------------------------------------------------------------
FBACK:
	push	hl		; the DOS-side FCB, for the size below
	ld	de,(UFCB)	; the program's FCB
	ld	bc,FCB_EX	; offset 12 for both
	add	hl,bc		; HL -> its byte 12
	ex	de,hl		; (swap to offset DE)
	add	hl,bc
	ex	de,hl		; DE -> the program's byte 12
	ldi			; EX
	inc	hl		; not S1: the program's own (see TOSCR)
	inc	de		; skip it in both
	ld	bc,FCB_LEN-FCB_S2	; bytes 14-35
	ldir			; copied
	pop	iy		; IY -> the DOS-side FCB
	ld	l,(iy+FCB_D0)	; A:HL = file size, low 24 bits
	ld	h,(iy+FCB_D0+1)
	ld	a,(iy+FCB_D0+2)	; (bytes 16-18: the size up to 16 MB)
	call	RECS		; HL = records in the file
	push	hl
	ld	hl,(UFCB)	; DE = (bytes 12-13) * 128: the records before
	ld	de,FCB_EX	;   this extent (S1 in the high byte!)
	add	hl,de		; -> byte 12
	ld	e,(hl)		; EX
	inc	hl
	ld	d,(hl)		; byte 13 (S1)
	ex	de,hl		; HL = bytes 12-13
	add	hl,hl		; x 128, seven doublings
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ex	de,hl		; DE = records before this extent
	pop	hl		; HL = records in the file
	or	a		; (CF clear)
	sbc	hl,de		; records left from this extent on
	jr	nc,FBACK_RC	; not negative
	ld	hl,0		; the file ends before this extent
FBACK_RC:				; (src: FB1)
	call	MAX128		; A = at most 128: one extent's worth
	ld	hl,(UFCB)	; the program's FCB
	ld	de,FCB_S2	; -> S2
	add	hl,de
	ld	(hl),0		; S2 = 0
	inc	hl		; -> RC
	ld	(hl),a		; RC
	ret

; FPOS - HL = the record position of the program's FCB: (bytes 12-13) *
; 128 + CR.  Byte 13 is the program's S1 (see FBACK).  Corrupts A, BC, DE.
FPOS:
	ld	hl,(UFCB)	; the program's FCB
	ld	de,FCB_EX	; -> byte 12
	add	hl,de
	ld	e,(hl)		; DE = bytes 12-13
	inc	hl
	ld	d,(hl)		; byte 13 (S1)
	ld	bc,FCB_CR-FCB_S1	; HL -> CR
	add	hl,bc
	ld	a,(hl)		; A = CR
	ex	de,hl		; HL = bytes 12-13
	add	hl,hl		; x 128, seven doublings
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	e,a		; + CR
	ld	d,0		; DE = CR
	add	hl,de		; HL = record number
	ret

; FNEXT - the program's FCB one record on: CR + 1, at 128 CR = 0 and the
; block (EX, carrying into byte 13) + 1.  Corrupts A, DE, HL.
FNEXT:
	ld	hl,(UFCB)	; the program's FCB
	ld	de,FCB_CR	; -> CR
	add	hl,de
	inc	(hl)		; CR + 1
	ld	a,(hl)
	cp	RECLEN		; past the extent?
	ret	nz		; still in this extent
	ld	(hl),0		; next extent, record 0
	ld	hl,(UFCB)	; the program's FCB
	ld	de,FCB_EX	; -> EX
	add	hl,de
	inc	(hl)		; EX + 1
	ret	nz		; no carry
	inc	hl		; (carry into byte 13: past 4 MB)
	inc	(hl)
	ret

; BUFREC - HL = BUF + A * 128, record A of BUF.  Corrupts DE.
BUFREC:
	ld	h,a		; A * 256 ...
	ld	l,0		; (HL = A * 256)
	srl	h		; ... / 2
	rr	l		; HL = A * 128
	ld	de,BUF		; BUF
	add	hl,de		; + offset
	ret

; RECS - HL = (A:HL + 127) / 128: the records of a file of A:HL bytes.
; Corrupts A, DE.
RECS:
	ld	de,RECLEN-1	; round up
	add	hl,de
	adc	a,0		; (into the third byte)
	sla	l		; A:H:L << 1, then drop the low byte: / 128
	rl	h
	rl	a		; (A:H:L shifted)
	ld	l,h		; L = middle byte
	ld	h,a		; H = top byte
	ret

; MAX128 - A = HL, at most 128
MAX128:
	ld	a,h		; 256 or more: 128
	or	a
	ld	a,RECLEN	; (LD keeps Z)
	ret	nz		; 256 or more
	ld	a,l		; under 256
	cp	RECLEN+1	; 129-255: 128
	ret	c		; 128 or less: A = HL
	ld	a,RECLEN	; 129-255
	ret

; =====================================================================
; F_SRCH - BDOS 17 / 18, Search for First / Next
; ---------------------------------------------------------------------
; Entry:  C = 17 (DE -> FCB, '?' wildcards) or 18 (DE ignored, as CP/M).
; Exit:   A = 0 and a directory record at the DMA, or FFh: no more.
;
; The search FCB lives at P+PSRCH between calls (DOS 1.25 keeps its
; search state in it).  A drive byte '?' (CP/M: every entry, all user
; numbers, empty ones too) is taken as the default drive.  DOS leaves
; the drive byte and the 32-byte directory entry at the DTA; DIRENT
; makes a CP/M directory record of it, entry 0, RC from the size.  So
; a file over 16 KB shows as one 16 KB extent, never with more entries,
; and with no allocation.  CP/M would return the slot (0-3) of the entry
; in its record; this always says 0, and programs test only for FFh.
; =====================================================================
F_SRCH:
	push	bc		; (FLUSH loses them)
	push	de
	call	FLUSH		; pending writes first (the size must be right)
	pop	de
	pop	bc
	ld	a,c		; the function
	cp	18		; search next?
	ld	a,12h		; (LD keeps Z) next: DOS 12h, same FCB
	jr	z,F_SRCH_CALL	; next: same FCB in P
	ld	hl,(PAGE)	; first: the program's FCB -> P+PSRCH
	ld	bc,PSRCH	; + search FCB offset
	add	hl,bc		; HL = P+38h
	ex	de,hl		; DE = search FCB, HL = the program's
	push	de		; (kept: its drive byte)
	ld	bc,FCB_LEN	; 36 bytes
	ldir			; copied
	xor	a		; DOS's byte 36
	ld	(de),a		; byte 36 = 0
	pop	hl		; HL -> search FCB's drive byte
	ld	a,(hl)		; the drive byte
	cp	'?'		; all user numbers: the default drive
	jr	nz,F_SRCH_FIRST	; a drive: as given
	ld	(hl),0		; '?' -> the default drive
F_SRCH_FIRST:				; (src: FS0)
	ld	a,11h		; DOS 11h, search first
F_SRCH_CALL:				; (src: FS1)
	ld	de,PSRCH	; on the search FCB
	call	DOSX		; DOS in, the call, DOS out
	cp	0FFh		; no (more) match
	jp	z,RETA		; A = FFh
	ld	hl,(PAGE)	; RC from the entry's size (DTA = drive byte +
	ld	bc,PDTA+1+DIR_SIZE	;   directory entry)
	add	hl,bc		; HL -> the size
	ld	e,(hl)		; A:DE = size, low 24 bits
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)		; third byte
	ex	de,hl		; A:HL for RECS
	call	RECS		; HL = records
	call	MAX128		; one extent at most
	ld	hl,(PAGE)	; HL -> the name in the entry
	ld	bc,PDTA+1	; +1: past the drive byte
	add	hl,bc		; HL -> the name
	call	DIRENT		; the record at the DMA
	jp	F_ZERO		; directory code 0

; ---------------------------------------------------------------------
; DIRENT - a CP/M directory record at the DMA, as CP/M's BDOS leaves it
; after a search (and, per the source, an open): entry 0 = user 0, the
; 11-byte name at HL, EX S1 S2 0, RC = A, allocation all 0; entries 1-3
; empty (E5h).  Corrupts all registers.
; ---------------------------------------------------------------------
DIRENT:
	push	af		; RC
	push	hl		; name
	ld	hl,(DMAADR)	; the whole record to E5h, "unused"
	ld	d,h		; DE = HL + 1:
	ld	e,l		;   the overlapping LDIR fill
	inc	de
	ld	(hl),0E5h	; the seed byte
	ld	bc,RECLEN-1	; 127 copies
	ldir
	ld	de,(DMAADR)	; entry 0: user 0 ...
	xor	a		; user 0
	ld	(de),a		; entry 0, byte 0
	inc	de
	pop	hl		; ... the name and type ...
	ld	bc,11		; 8 + 3 characters
	ldir			; copied
	ld	b,32-FCB_EX	; ... EX S1 S2 RC and d0-d15: 0
DIRENT_ZERO:				; (src: FS2)
	ld	(de),a		; 0
	inc	de
	djnz	DIRENT_ZERO	; 20 bytes
	pop	af		; RC into byte 15
	ld	hl,(DMAADR)	; the record
	ld	de,FCB_RC	; + 15
	add	hl,de
	ld	(hl),a		; RC = A
	ret

; =====================================================================
; BIOSV - the CP/M BIOS entries (F9E6h); T_CPM makes P+100h a JP to
; each.  (0001h) = P+103h, so programs find the vector at (0001h) - 3.
; =====================================================================
BIOSV:
	defw	CPEXIT, CPEXIT, B_CONST, B_CONIN	; +00 BOOT, +03 WBOOT: warm
					;   boot; +06 CONST, +09 CONIN
	defw	B_CONOUT, B_LIST, B_PUN, B_RDR	; +0C CONOUT, +0F LIST (channel
					;   A), +12 PUNCH, +15 READER (channel B)
	defw	B_RET, B_SELD, B_RET, B_RET	; +18 HOME, +1B SELDSK (no
					;   disk), +1E SETTRK, +21 SETSEC: nothing
	defw	B_RET, B_RW, B_RW, B_LSTS	; +24 SETDMA: nothing; +27 READ,
					;   +2A WRITE: always error 1; +2D LISTST
	defw	B_STRN				; +30 SECTRAN: no translation

; ---------------------------------------------------------------------
; B_CONST / B_CONIN / B_CONOUT - the console entries.  MBASIC calls
; these directly.  BC, DE, HL kept (more than CP/M promises).
; CONST: A = FFh if a key waits, else 0.  CONIN: A = a key.  CONOUT: C
; to the terminal, raw (BDOS's COL not kept, as under CP/M).
; They run on the program's stack: nothing is swapped here.
; ---------------------------------------------------------------------
B_CONST:
	push	bc		; the BIOS routines use BC DE HL
	push	de
	push	hl
	call	PEEKEY		; CF=1: a key (kept for CONIN)
	ld	a,0		; none: 0
	jr	nc,BIOS_POPRET	; none: 0
	dec	a		; FFh
BIOS_POPRET:				; (src: BC1)
	pop	hl		; restore the program's
	pop	de
	pop	bc
B_RET:
	ret			; also HOME, SETTRK, SETSEC, SETDMA: no disks
B_CONIN:
	push	bc		; (kept for the program)
	push	de
	push	hl
	call	GETKEY		; A = the key, waiting for it
	jr	BIOS_POPRET	; A = the key
B_CONOUT:
	push	bc		; (kept for the program)
	push	de
	push	hl
	ld	a,c		; CP/M passes the character in C
	call	CONOUT		; (waits on the link)
	jr	BIOS_POPRET

; ---------------------------------------------------------------------
; B_LIST / B_PUN / B_RDR / B_LSTS - the serial entries (CBIOS A1.1's
; assignment: LIST and LISTST channel A, PUNCH and READER channel B).
; C = the byte to send; A = the byte read / the status; BC, DE, HL kept.
; ---------------------------------------------------------------------
B_LIST:
	push	hl		; HL = the routine in Z86.SYS's REGS page
	ld	hl,SPRN		; channel A out
	jr	BSER
B_PUN:
	push	hl		; (BSER pops it)
	ld	hl,SAUXO	; channel B out
	jr	BSER
B_RDR:
	push	hl		; (BSER pops it)
	ld	hl,SAUXI	; channel B in
	jr	BSER
B_LSTS:
	push	hl		; (BSER pops it)
	ld	hl,SLSTS	; A = FFh ready (CTS on), 0 not
BSER:
	push	de		; the routines use C, E, HL
	push	bc		; C, the byte, is kept
	ld	a,c		; they take the byte in A
	call	JPHL		; call the routine in HL
	pop	bc		; restore the program's
	pop	de
	pop	hl
	ret			; A = the result
B_SELD:
	ld	hl,0		; no CP/M disks: HL = 0, select error
	ret
B_RW:
	ld	a,1		; READ / WRITE: error (STAT's disk report,
	ret			;   SYSGEN, FORMAT cannot work here)
B_STRN:
	ld	h,b		; SECTRAN: logical = physical
	ld	l,c		; HL = BC
	ret

; ---------------------------------------------------------------------
; DPB - what BDOS 31 (STAT) sees: the DOS disk as a CP/M disk with 1 KB
; blocks.  DSM, DRM and CKS match the FDD3000 DOS format (176 clusters
; of 1 KB, 64 directory entries).  SPT does not: a track is 18 x 256 =
; 4608 bytes = 36 records, not 72 (cosmetic: nothing here uses it).
; ---------------------------------------------------------------------
DPB:
	defw	72		; SPT: 128-byte records per track (36 real)
	defb	3,7,0		; BSH 3, BLM 7: 1 KB blocks; EXM 0: 16 KB
					;   extents (DSM < 256)
	defw	175,63		; DSM: blocks 0-175; DRM: entries 0-63
	defb	0C0h,0		; AL0 AL1: blocks 0, 1 hold the directory
	defw	16,0		; CKS: (DRM+1)/4; OFF: no system tracks
ALLOCV:
	defs	23		; BDOS 27's allocation vector, never set: all
					;   blocks free, so STAT counts the whole
					;   disk as free (176 bits fit in 22 bytes)

; =====================================================================
;                              VARIABLES
; =====================================================================
PAGE:
	defw	0		; P, the page above the program
SEGP:
	defw	0		; P >> 4, its 8086 segment
SAVE:
	defw	0		; P + 200h: where DOS goes while the program runs
SWLEN:
	defw	0		; bytes swapped by XCHGA (CPM.COM's end)
PLEN:
	defw	0		; program bytes, staged at SWLEN
PARAM:
	defw	0		; linear PARMS in CPM.COM: FCB 1, FCB 2, tail
DMAADR:
	defw	0		; the program's DMA address (BDOS 26)
USRSP:
	defw	0		; the program's SP during a BDOS call
SHIMSP:
	defw	0		; the Z80 SP of the trap-1Ch frame
SAVAF:
	defw	0		; CPM.COM's 8086 flags (its AF')
UFCB:
	defw	0		; the program's FCB of the current call
CPDSK:
	defb	0		; the current drive (BDOS 14 / 25)
COL:
	defb	0		; the screen column (OUTCH)
CPFN:
	defb	0		; F_FCB: the function
FRES:
	defb	0		; F_FCB: DOS's result
DOSLEN:
	defw	0		; bytes swapped by XCHGD (DOS + PSP)
BMODE:
	defb	0		; BUF: 0 empty, 1 read ahead, 2 to write
BFCB:
	defw	0		; BUF: the FCB's address
BPOS:
	defw	0		; BUF: record number of BUF[0]
BCNT:
	defb	0		; BUF: records held
BEOF:
	defb	0		; BUF, reading: 1 the file ends after them
BIDX:
	defb	0		; FLUSH: record being written
RPOS:
	defw	0		; the record asked for
RRND:
	defb	0		; 1: a random read / write
WRND:
	defb	0		; BUF holds random writes
PSAVE:
	defs	6		; FLUSH: block, CR, R0-R2
FERR:
	defb	0		; DOS's code from the last failed FLUSH
SAVREG:
	defs	42		; CPM.COM's REGS (REGS_SAVED bytes)
BSHAD:
	defs	37		; DOS's FCB for BUF's run (DFCB_LEN bytes)
CPMEND:					; FAF6h: the end of the image
BUF:	equ	$		; NBUF records, not in CPM.COM
BUFEND:	equ	BUF+NBUF*128	; FEF6h: z86.py checks it is below FF00h
