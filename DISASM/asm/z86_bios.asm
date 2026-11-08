;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  2/7 (BIOS)
;  Included by asm/z86sys.asm, which holds the volume preface, the ORG and
;  the shared hardware equates.  Not assembled on its own.  Range: EB46h-F220h
;==============================================================================

; BIOS.ASM - the BIOS traps of IOFDD.SYS in Z80 code, for the FDD3000.
;
; Assembled after I86.ASM (z86.build(bios=True)). The 8086 opcode 0F nn
; calls TRAP with A = nn. A handler reads and writes the 8086 registers in
; REGS and sets ZF / CF in AF' (the 8086 flags); TRAP keeps BC (the 8086
; code pointer) and IX (the dispatcher).
;
; The hardware code is CBIOS A1.1's, which runs on real FDD3000s:
;   console  the nibble protocol to the terminal on port 2Fh (CBIOS FAA8h
;            send, FB0Dh receive, F719h status)
;   disk     WD177x on C0h-C3h, drive latch E0h, DRQ in bit 7 of port 2Fh.
;            A command ends with INTRQ on the Z80 INT line (IM 1, RST 38h):
;            0038h is pointed at FDCINT for the duration of a disk call,
;            which leaves the transfer loop and returns the status (CBIOS
;            FBE2h / FC0Ch).
;
; The FDD3000 has no clock: the date and time are what DOS last set
; (1-1-80 0:00 at boot), and INT 1Ah's tick count goes up by one per call.

NDRIVE:	equ	4	; drives on the latch
SPT:	equ	18	; sectors per track, IDs 0-17
NTRACK:	equ	40
NSECT:	equ	NTRACK*SPT	; 720
FIRDIR:	equ	5	; the disk layout (mkfat.py): boot sector,
FIRREC:	equ	13	; 2 FATs of 2 sectors, 8 directory sectors
GTOP:	equ	0D000h	; end of the 8086's memory
RETRIES:	equ	10
; =====================================================================
;   LINK AND FDC CONSTANTS OF THE BIOS TRAPS (this part's own equates;
;   the shared port and link-code block is at the top of the volume)
; =====================================================================
WSTA:		equ	06h		; FDD: "I am waiting for a key" - CBIOS's
					;   name (its RXBY sends it the same way)
KEYRDY:		equ	04h		; terminal idle with a key waiting (CBIOS
					;   CONST tests the bare 04; no CBIOS name)
LINKERR:	equ	07h		; abort, from either side (CBIOS TXERR /
					;   RXERR send it; no CBIOS name)
RDSCMD:		equ	80h		; WD177x Read Sector: single, h=0, E=0
					;   (same name and value as CBIOS)
WRSCMD:		equ	0A0h		; WD177x Write Sector: single, precomp
					;   on, E=0 (same name and value as CBIOS)

; =====================================================================
; TRAP - the BIOS dispatcher: run the Z80 function for 8086 `0F nn`
; ---------------------------------------------------------------------
; Entry:  A = trap number nn (from O_TRAP, which has already stepped BC
;         past it); the 8086 registers in REGS, the 8086 flags in AF'.
; Exit:   whatever the handler left in REGS and AF' (ZF / CF through
;         ZF0/ZF1/CF0/CF1); BC and IX as on entry.
; Corrupts: A, DE, HL, IY, and anything else the handler uses.
; Callers: O_TRAP (D8C1h) only.
;
; BC is the 8086 code pointer and IX the dispatcher NEXT; every handler
; is free to use both, so TRAP alone saves them.  A number past the table
; (1Eh and up) is a silent no-op, where cpu86.py and fddos.py halt with
; "trap nn" - harmless, since no shipped 8086 code issues one.  The bound
; 1Eh is tied to the table by an assert in z86.py (TTEND - TTAB = 2*1Eh).
; =====================================================================
TRAP:
	push	bc		; the 8086 code pointer ...
	push	ix		; ... and NEXT survive any handler
	cp	1Eh		; 30 entries in TTAB; anything above does nothing
	jr	nc,TRAP_EXIT	; out of range: straight back
	add	a,a		; word index (A < 1Eh: no overflow)
	ld	l,a		; HL = 2 * nn ...
	ld	h,0
	ld	de,TTAB		; ... + the table
	add	hl,de		; HL -> the entry
	ld	e,(hl)		; DE = handler address
	inc	hl		; (little-endian word)
	ld	d,(hl)
	ex	de,hl		; HL = handler
	call	JPHL		; CALL (HL): the handler's RET comes back here
TRAP_EXIT:				; (src: TRAPX)
	pop	ix		; NEXT again for O_TRAP's JP (IX)
	pop	bc		; and the 8086 code pointer
TNONE:					; the table's "no function" entries land
	ret				;   on TRAP's own RET: nothing done
; ---------------------------------------------------------------------
; JPHL - the Z80 has no CALL (HL); `CALL JPHL` is one.  Exported: CPM.COM's
; Z80 part calls it by address (CPMZ80 F31Bh, FA41h), and its address is
; one of the seven CPMSYM words trap 1Ch checks before loading that part.
; ---------------------------------------------------------------------
JPHL:
	jp	(hl)		; the CALLer's return address is still stacked

; =====================================================================
; TTAB - trap number -> handler (30 words; IO.SYS / FORMAT / CPM.COM)
; ---------------------------------------------------------------------
; 01h-0Eh are IO.SYS's 14 DOS device entries, in MS-DOS 1.25's BIOS
; order (each `TRAP n / RETF`).  10h-1Ah are IBM PC ROM BIOS interrupts:
; IO.SYS points vectors 10h 11h 12h 14h 16h 17h 1Ah at `TRAP n / RETF 2`
; stubs (RETF 2 drops the flags INT pushed, so the ZF / CF set here reach
; the caller); the other numbers in that range get no stub and stay
; TNONE.  1Bh-1Dh are issued only by FORMAT.COM and CPM.COM.
; =====================================================================
TTAB:
	defw	TNONE		; 00h  -          (no function 0)
	defw	T_STAT		; 01h  STATUS     ZF=1 no key; ZF=0, AL = key
	defw	T_INP		; 02h  INP        AL = key (waits)
	defw	T_OUTP		; 03h  OUTP       AL to the terminal
	defw	T_PRINT		; 04h  PRINT      AL to the printer (WD2123 ch. A)
	defw	T_AUXIN		; 05h  AUXIN      AL from AUX (WD2123 ch. B)
	defw	T_AUXOUT	; 06h  AUXOUT     AL to AUX (WD2123 ch. B)
	defw	T_READ		; 07h  READ       AL drive, DS:BX, CX sectors, DX first
	defw	T_WRITE		; 08h  WRITE      the same; CF=1, AL = DOS error code
	defw	T_DSKCHG	; 09h  DSKCHG     disk changed?
	defw	T_SDATE		; 0Ah  SETDATE    AX = days since 1-1-80
	defw	T_STIME		; 0Bh  SETTIME    CX, DX = h:m, s.1/100
	defw	T_GTIME		; 0Ch  GETTIME    AX days, CX, DX
	defw	T_FLUSH		; 0Dh  FLUSH      drop the keys typed ahead
	defw	TNONE		; 0Eh  MAPDEV     IO.SYS's 14th entry: nothing to map
	defw	TNONE		; 0Fh  -
	defw	T_I10		; 10h  INT 10h    video: teletype, VT52 cursor, clear
	defw	T_I11		; 11h  INT 11h    equipment word
	defw	T_I12		; 12h  INT 12h    memory size
	defw	TNONE		; 13h  INT 13h    (disk: no stub, DOS uses traps 7/8)
	defw	T_I14		; 14h  INT 14h    serial (AUX, channel B)
	defw	TNONE		; 15h  INT 15h    (no stub)
	defw	T_I16		; 16h  INT 16h    keyboard (through PEEKEY / GETKEY)
	defw	T_I17		; 17h  INT 17h    printer (channel A)
	defw	TNONE		; 18h  INT 18h    (ROM BASIC: no stub)
	defw	TNONE		; 19h  INT 19h    (bootstrap: no stub)
	defw	T_I1A		; 1Ah  INT 1Ah    tick count, +1 per call
	defw	T_FMT		; 1Bh  FORMAT.COM: write one track image (Write Track)
	defw	T_CPML		; 1Ch  CPM.COM: load its Z80 part, or (BP = 0) run it
	defw	T_RET		; 1Dh  CPM.COM: end of a DOS call its Z80 part made
TTEND:				; z86.py asserts TTEND - TTAB = 2 * 1Eh

; =====================================================================
; ZF1 / ZF0 / CF1 / CF0 - set or clear one 8086 flag, then RET
; ---------------------------------------------------------------------
; Entry:  none (jumped to as a handler's tail).
; Exit:   F' = F' AND D OR E: ZF1 sets F' bit 6, ZF0 clears it, CF1 sets
;         bit 0, CF0 clears it; A' and the other flags in F' untouched.
; Corrupts: A, DE, HL (main set only).
; Callers: T_STAT, I16A (INT 16h), T_DSKCHG, DDONE / DERR (disk, also
;         for T_FMT), the CPM.COM traps.
;
; The interpreter keeps the 8086's ZF and CF in the Z80's own Z (bit 6)
; and C (bit 0) of F' - the same bit numbers as in the 8086 FLAGS word -
; so setting an 8086 flag is one AND/OR on F'.  F' cannot be reached
; directly: EX AF,AF' brings it to F, and PUSH AF / POP HL to L.  A'
; (the parity source) rides along in H and is put back unchanged.
; =====================================================================
ZF1:
	ld	de,0BF40h	; keep all but Z, then set Z
	jr	FSET		; (8086 ZF=1: "no key", "equal")
ZF0:
	ld	de,0BF00h	; keep all but Z, set nothing
	jr	FSET		; (ZF=0)
CF1:
	ld	de,0FE01h	; keep all but C, then set C
	jr	FSET		; (CF=1: error)
CF0:
	ld	de,0FE00h	; keep all but C, set nothing
FSET:
	ex	af,af'		; the 8086 flags into reach
	push	af		; F has no direct path to a register:
	pop	hl		;   L = F' (H = A', left alone)
	ld	a,l		; the flags
	and	d		; clear the one bit ...
	or	e		; ... and set it if asked
	ld	l,a		; back beside A'
	push	hl		; and the same detour home
	pop	af		; back into F
	ex	af,af'		; and away again; the main AF is junk
	ret			; to the trap's caller (TRAP_EXIT)

; =====================================================================
;                   CONSOLE TRAPS (1-3, 13) AND KEY BUFFER
; =====================================================================
; The console is the terminal at the far end of the 2Fh link, spoken to
; with CBIOS A1.1's nibble protocol (CONOUT / CONIN below).  When idle
; the terminal shows KEYRDY (04h) if a key is waiting.  It cannot say
; WHICH key without sending it, but DOS's STATUS must return the key in
; AL without consuming it - so STATUS receives it and parks it in KBUF
; (KFLAG = 1), where the next INP collects it.  CBIOS A1.1's CONST only
; had to answer FFh / 00h, so it just tested for 04h.
; ---------------------------------------------------------------------

; ---------------------------------------------------------------------
; T_STAT - trap 1, STATUS.  Exit: ZF=1, AL unchanged: no key; ZF=0, AL =
; the key, which stays for INP.  Corrupts A, BC, DE, HL.
; ---------------------------------------------------------------------
T_STAT:
	call	PEEKEY		; CF=1 and A = key if one is there (or held)
	jp	nc,ZF1		; none: ZF=1, AL as it was
	ld	(R_AL),a	; the key, not consumed
	jp	ZF0		; ZF=0: "a key is ready"

; ---------------------------------------------------------------------
; T_INP - trap 2, INP: AL = the next key, 7 bits; waits for one.
; ---------------------------------------------------------------------
T_INP:
	call	GETKEY		; the held key first, else from the terminal
	ld	(R_AL),a	; to the 8086's AL
	ret			; no flags for INP

; ---------------------------------------------------------------------
; T_OUTP - trap 3, OUTP: AL to the terminal (waits until it is taken).
; ---------------------------------------------------------------------
T_OUTP:
	ld	a,(R_AL)	; the character
	jp	CONOUT		; CONOUT's RET returns to TRAP

; ---------------------------------------------------------------------
; T_PRINT / T_AUXOUT / T_AUXIN - traps 4, 6, 5: front-ends to the serial
; routines in the register page's free end (SPRN, SAUXO, SAUXI, part 1).
; PRINT goes to WD2123 channel A, AUX to channel B, as CBIOS A1.1 wires
; CP/M's LIST and PUNCH / READER.  They wait for ever (HL = 0 polls,
; i.e. no time-out), as those CP/M functions do: a printer that is off
; hangs DOS, there being no error path in DOS 1.25's PRINT / AUX entries.
; No flags are set.
; ---------------------------------------------------------------------
T_PRINT:
	ld	a,(R_AL)	; the character
	jp	SPRN		; channel A, once DSR and TxRDY are both on
T_AUXOUT:
	ld	a,(R_AL)	; the character
	jp	SAUXO		; channel B, the same handshake
T_AUXIN:
	call	SAUXI		; channel B, RTS raised only while waiting
	ld	(R_AL),a	; to the 8086's AL
	ret			; no flags for AUXIN

; ---------------------------------------------------------------------
; T_FLUSH - trap 13, FLUSH: forget the keys typed ahead.  The held key
; is dropped, then keys are received and thrown away for as long as the
; terminal keeps showing KEYRDY.  Corrupts A, BC, DE.
; ---------------------------------------------------------------------
T_FLUSH:
	xor	a		; KFLAG = 0:
	ld	(KFLAG),a	;   KBUF no longer counts
FLUSH_DRAIN:				; (src: FL1)
	in	a,(COM)		; idle code from the terminal
	and	MASK		; (bit 7 is the FDC's DRQ, bit 5 unwired)
	cp	KEYRDY		; still a key waiting?
	ret	nz		; no: the type-ahead is empty
	call	CONIN		; take it ...
	jr	FLUSH_DRAIN	; ... and discard it

; =====================================================================
; PEEKEY - is a key ready?  (non-destructive, as DOS STATUS needs)
; ---------------------------------------------------------------------
; Exit:   CF=1, A = the key (now held in KBUF for GETKEY); CF=0: none.
; Corrupts: A, BC, DE (through CONIN).
; Callers: T_STAT, I16A (INT 16h AH=1); CPMZ80's DIO1, F_CST and B_CONST
;         by absolute address (EBF6h - in the CPMSYM header).
;
; FIXED 2026-11-08: the "no key" exit was `cp KEYRDY / ret nz`, and CP
; sets carry when A < 04h: a link value of 00h-03h returned CF=1 - a
; phantom key, the stale KBUF - with KFLAG still 0, so the next GETKEY
; waited for a real key.  Now `xor KEYRDY` (same 2 bytes): XOR always
; clears carry, so the exit is NC for every value but 04h
; (test_peekey.py: phantom keys on the old build, none now).
; =====================================================================
PEEKEY:
	ld	a,(KFLAG)	; already holding one from an earlier peek?
	or	a
	jr	nz,PEEKEY_HELD	; yes: report it again
	in	a,(COM)		; the terminal's idle code
	and	MASK		; link bits only
	xor	KEYRDY		; the terminal has a key?  (XOR: carry always
	ret	nz		;   clear - no: NC, whatever the link reads)
	call	CONIN		; it can only be seen by taking it ...
	ld	(KBUF),a	; ... so keep it
	ld	a,1		; KFLAG = 1:
	ld	(KFLAG),a	;   KBUF valid
PEEKEY_HELD:				; (src: PK1)
	ld	a,(KBUF)	; the key, left where it is
	scf			; CF=1: a key
	ret

; =====================================================================
; GETKEY - A = the next key (7 bits); waits for one
; ---------------------------------------------------------------------
; Exit:   A = key; KFLAG = 0.   Corrupts: A, HL, and BC, DE if the
;         terminal is asked (CONIN).
; Callers: T_INP, T_I16 (INT 16h AH=0); CPMZ80's F_CIN, DIO1, RL1 (read
;         line) and B_CONIN (EC13h, in CPMSYM).
; =====================================================================
GETKEY:
	ld	hl,KFLAG	; HL kept for the clear below
	ld	a,(hl)		; a key held by PEEKEY?
	or	a
	jp	z,CONIN		; no: wait for the terminal's next one
	ld	(hl),0		; yes: hand it over, the buffer is free again
	ld	a,(KBUF)	; the held key
	ret

; =====================================================================
; CONOUT - A to the terminal; retried until it gets through
; ---------------------------------------------------------------------
; Entry:  A = character (all 8 bits are sent).
; Exit:   A = 0, Z.   Corrupts: A, BC, DE.
; Callers: T_OUTP, T_I10 (the VT52 sequences), COLD's message printer
;         (CB2), CPMZ80 (CONOUT EC21h is in CPMSYM).
;
; CBIOS A1.1's TXBYTE (FAA8h per BIOS.ASM).  Kept: the whole retry -
; COSEND, and on its failure wait for the terminal to show LINKERR (07h)
; and start the character again from BYTEON.  Changed: TXBYTE's PUSH DE /
; PUSH BC ... POP DE / POP BC are gone (CBIOS pops them crossed, so its
; caller got B<->D and C<->E swapped); CHATMP becomes COCHR; the final
; XOR A is COSEND's own (RET Z returns with A = 0).
; =====================================================================
CONOUT:
	ld	(COCHR),a	; kept in memory: COSEND destroys B
CONOUT_RETRY:				; (src: CO1)
	ld	a,(COCHR)	; the character, for every attempt
	ld	b,a		; COSEND takes B
	call	COSEND		; Z: through; NZ: aborted with LINKERR
	ret	z		; delivered
CONOUT_WAIT_ABORT:			; (src: CO2)
	in	a,(COM)		; we sent LINKERR: wait for the terminal to
	and	MASK		;   show LINKERR back (its acknowledgement),
	cp	LINKERR		;   then send the whole character again
	jr	nz,CONOUT_WAIT_ABORT	; (no time-out on this wait)
	jr	CONOUT_RETRY	; from BYTEON again

; =====================================================================
; COSEND - one byte across the link, sender side (CBIOS A1.1 TXBY)
; ---------------------------------------------------------------------
; Entry:  B = byte.
; Exit:   Z, A = 0: sent.  NZ, A = LINKERR: an echo timed out and LINKERR
;         was sent to the terminal (LKFAIL).
; Corrupts: A, BC, DE.
;
; The exchange, FDD -> terminal:
;    BYTEON (0Ah), repeated until the terminal shows SERVICO (0Fh);
;    low nibble | CSTAT (10h), until the terminal echoes it;
;    high nibble | BSTAT (40h), until echoed;
;    STMSK (50h): end of character.
; Byte for byte TXBY: the same codes, the same endless BYTEON wait, and
; the same echo time-out - C = 0 then DEC C before the test, so 255
; compared polls (about 45 T each: ~2.9 ms at 4 MHz, provisional clock).
; The boot sector's NOSYS sends the same way with the time-outs removed.
; =====================================================================
COSEND:
	ld	a,b		; split the byte:
	and	0Fh		;   low nibble ...
	ld	e,a		;   ... in E
	ld	a,b
	and	0F0h		;   high nibble ...
	rrca			;   ... moved down to bits 3-0
	rrca
	rrca
	rrca
	ld	d,a		;   ... in D
COSEND_OFFER:				; (src: COS1)
	ld	a,BYTEON	; "I have a byte for you" ...
	out	(COM),a
	in	a,(COM)		; the terminal's answer
	and	MASK		; link bits only
	cp	SERVICO		; ... until the terminal says "send it"
	jr	nz,COSEND_OFFER	; (no time-out here, as in CBIOS)
	ld	a,e		; low nibble ...
	or	CSTAT		; ... tagged CSTAT
	out	(COM),a		; on the wires
	ld	b,a		; B = what the echo must look like
	ld	c,0		; 255 polls for it
COSEND_ECHO_LO:				; (src: COS2)
	in	a,(COM)		; the terminal's side
	dec	c		; one poll fewer
	jr	z,LKFAIL	; no echo in time: abort
	and	MASK		; drop DRQ and the unwired bit 5
	cp	b		; echoed?
	jr	nz,COSEND_ECHO_LO	; not yet
	ld	a,d		; high nibble ...
	or	BSTAT		; ... tagged BSTAT
	out	(COM),a		; on the wires
	ld	b,a		; the echo to wait for
	ld	c,0		; 255 polls again
COSEND_ECHO_HI:				; (src: COS3)
	in	a,(COM)		; the terminal's side
	dec	c		; one poll fewer
	jr	z,LKFAIL	; no echo in time: abort
	and	MASK		; link bits only
	cp	b		; echoed?
	jr	nz,COSEND_ECHO_HI	; not yet
	ld	a,STMSK		; end of character
	out	(COM),a		; (no answer awaited)
	xor	a		; Z: sent
	ret
; ---------------------------------------------------------------------
; LKFAIL - an echo or a nibble never came: tell the terminal (LINKERR)
; and return NZ.  CBIOS A1.1 has two identical copies of this, TXERR and
; RXERR; here COSEND and CIRECV share one.  Exit: A = 07h, NZ, NC.
; ---------------------------------------------------------------------
LKFAIL:
	ld	a,LINKERR	; abort the exchange
	out	(COM),a		; the terminal sees 07h
	and	a		; NZ (A = 07h), CF clear
	ret			; to CONOUT / CONIN's retry loop

; =====================================================================
; CONIN - A = a key from the terminal (7 bits); retried until one comes
; ---------------------------------------------------------------------
; Exit:   A = key.   Corrupts: A, BC, DE.
; Callers: T_FLUSH, PEEKEY, GETKEY.
;
; CBIOS A1.1's RXBYTE (FB0Dh per BIOS.ASM) without its PUSH BC / PUSH DE
; (popped in the right order there, unlike TXBYTE).  The two retry loops
; are mirror images, in CBIOS too: CONOUT waits FOR the terminal to show
; LINKERR, CONIN waits for it to STOP showing LINKERR, then asks again.
; A key lost or doubled by an abort in the closing STMSK exchange is
; possible in principle, as in CBIOS (untested, provisional).
; =====================================================================
CONIN:
	call	CIRECV		; Z: B = key; NZ: aborted
	jr	z,CONIN_GOT	; a whole key
CONIN_WAIT_ABORT:			; (src: CI1)
	in	a,(COM)		; aborted: let the terminal leave its
	and	MASK		;   LINKERR state ...
	cp	LINKERR		; still showing it?
	jr	z,CONIN_WAIT_ABORT	; yes: wait
	jr	CONIN		; ... and ask again
CONIN_GOT:				; (src: CI2)
	ld	a,b		; CIRECV left the key in B
	ret

; =====================================================================
; CIRECV - one key across the link, receiver side (CBIOS A1.1 RXBY)
; ---------------------------------------------------------------------
; Exit:   Z, A = 0, B = key AND 7Fh.   NZ (A = LINKERR): failed, LINKERR
;         sent.
; Corrupts: A, BC, DE.
;
; The exchange, terminal -> FDD:
;    WSTA (06h), repeated until the terminal shows STANDBY (05h): a key
;      is coming;
;    SERVICO (0Fh) - "go ahead" (CBIOS writes the bare 0Fh here: the same
;      code as the terminal's SERVICO, roles swapped);
;    the terminal shows low nibble | CSTAT; the FDD echoes it;
;    it shows high nibble | BSTAT; the FDD echoes it;
;    it shows STMSK (50h); the FDD answers STMSK.
; Byte for byte RXBY, time-outs included: 255 polls for each nibble
; (~3.3 ms and ~2.7 ms at 4 MHz, provisional), none for the WSTA wait or
; the final STMSK, where only LINKERR from the terminal ends the wait.
; The nibble tests are loose, as in CBIOS: bits 6 and 4 decide (AND
; STMSK = CSTAT), and the high nibble needs only bit 6; both echoes go
; out unmasked, DRQ bit included (the FDC is idle between transfers).
; =====================================================================
CIRECV:
	ld	a,WSTA		; "I am waiting for a key" ...
	out	(COM),a
	in	a,(COM)		; the terminal's answer
	and	MASK		; link bits only
	cp	STANDBY		; ... until the terminal says one is coming
	jr	nz,CIRECV	; (no time-out: this is where INP waits)
	ld	a,SERVICO	; go ahead
	out	(COM),a		; the terminal now puts up the low nibble
	ld	c,0		; 255 polls per nibble
CIRECV_LO:				; (src: CIR1)
	in	a,(COM)		; low nibble, tagged CSTAT
	dec	c		; one poll fewer
	jr	z,LKFAIL	; nothing in time: abort
	ld	e,a		; keep the raw value for the echo
	and	STMSK		; bits 6 and 4 only: must read CSTAT
	cp	CSTAT		; low-nibble tag?
	jr	nz,CIRECV_LO	; not yet
	ld	a,e		; the raw value ...
	out	(COM),a		; echo it back as the acknowledgement
	and	0Fh		; the nibble ...
	ld	e,a		; E = low nibble
	ld	c,0		; 255 polls for the next
CIRECV_HI:				; (src: CIR2)
	in	a,(COM)		; high nibble, tagged BSTAT
	dec	c		; one poll fewer
	jr	z,LKFAIL	; nothing in time: abort
	bit	6,a		; BSTAT's bit is all that is checked
	jr	z,CIRECV_HI	; not yet
	out	(COM),a		; echo
	and	0Fh		; the nibble ...
	rlca			; ... to the top half
	rlca
	rlca
	rlca
	or	e		; whole byte
	and	7Fh		; 7-bit keys only
	ld	b,a		; result in B (CONIN's convention)
CIRECV_END:				; (src: CIR3)
	in	a,(COM)		; the closing code
	and	MASK		; link bits only
	cp	LINKERR		; the terminal gave up?
	jr	z,LKFAIL	; abort too (sends our own 07h)
	cp	STMSK		; end of character?
	jr	nz,CIRECV_END	; (no time-out on this wait)
	ld	a,STMSK		; confirm it
	out	(COM),a		; the terminal drops the key
	xor	a		; Z: got a key
	ret

; =====================================================================
; T_READ / T_WRITE - traps 7 and 8: DOS sector read / write
; ---------------------------------------------------------------------
; Entry (8086): AL = drive (0-3), DS:BX = buffer, CX = sector count,
;         DX = first logical sector (0-719).
; Exit:   CF=0: all done, CX = 0, DX = the sector after the last.
;         CF=1: AL = DOS error code (ERRTAB), CX = sectors NOT done, DX =
;         the sector that failed.  BX is never changed (DOS 1.25 BIOS
;         contract: it uses CX only).
; Corrupts: A, BC, DE, HL (Z80).
; Callers: TTAB; COLD's CLOAD (F1DBh) calls T_READ directly to load
;         IO.SYS and MSDOS.SYS.  T_FMT shares DNRDY, DFAIL and DDONE.
;
; Per sector: logical n -> track n / 18 and sector ID SKEW[n MOD 18]
; (the 2:1 interleave 0 2 4 .. 16 1 3 .. 17, as boot.asm and mkfat.py),
; then SECTIO does select, seek and up to RETRIES (10) transfers.  The
; buffer goes straight to the guest's memory (8086 linear = Z80 address),
; one sector at a time with CX / DX updated in REGS, so a failure leaves
; DOS exactly the "sectors left" count it expects.  The transfer is
; refused before it starts if the 256 bytes would reach D000h, the
; interpreter.  0038h (the 8086's INT 0Eh vector) holds `JP FDCINT` from
; HOOK38 to UNHOOK; every exit after HOOK38 goes through UNHOOK.
; Lineage: the division / skew / retry layer is BIOS.ASM's own (CBIOS
; A1.1 deblocks 128-byte CP/M records); the transfer loops are CBIOS's.
; =====================================================================
T_READ:
	xor	a		; DWRITE = 0: read
	jr	DISKIO
T_WRITE:
	ld	a,1		; DWRITE = 1: write
DISKIO:
	ld	(DWRITE),a	; direction, for SECTIO
	ld	a,(R_AL)	; the drive
	cp	NDRIVE		; drives 0-3 are on the latch
	jp	nc,DNRDY	; others: not ready (the source's JR, relaxed to
					;   JP by the project assembler: 142 bytes on)
	ld	(DDRIVE),a	; for SELECT
	ld	hl,(B_DS)	; host address = DS base + BX (16-bit wrap,
	ld	de,(R_BX)	;   like all segment arithmetic here)
	add	hl,de
	ld	(DADDR),hl	; the running buffer pointer
	call	HOOK38		; INTRQ -> FDCINT for the duration
DLOOP:
	ld	hl,(R_CX)	; sectors still to do
	ld	a,h
	or	l
	jr	z,DDONE		; count exhausted (or CX = 0 to begin with)
	ld	hl,(R_DX)	; this sector
	ld	de,NSECT	; 720 on a 40 x 18 disk
	or	a		; (clear carry for SBC)
	sbc	hl,de		; DX >= 720?
	ld	a,10h		; as FDC "record not found" -> DOS 8
	jr	nc,DFAIL	; past the end of the disk
	ld	hl,(DADDR)	; this sector's buffer
	ld	de,GTOP-255	; CF01h
	or	a		; (clear carry for SBC)
	sbc	hl,de		; buffer at CF01h or above would spill into
					;   D000h, the interpreter itself
	ld	a,01h		; no ERRTAB bit -> DOS 0Ch, general failure
	jr	nc,DFAIL	; refuse it
	ld	hl,(R_DX)	; DX / 18 by repeated subtraction:
	ld	de,-SPT		;   B = quotient (the track, 0-39) ...
	ld	b,0FFh		;   (the first INC makes it 0)
DLOOP_DIV18:				; (src: DV1)
	inc	b		; one more whole track
	add	hl,de		; carry while HL was still >= 18
	jr	c,DLOOP_DIV18
	ld	a,b		; the track
	ld	(DTRK),a	; for SEEK
	ld	a,l		; ... and L = remainder - 18
	add	a,SPT		; remainder: logical sector in the track
	ld	e,a		; -> sector ID through SKEW (2:1 interleave)
	ld	d,0		; DE = index 0-17
	ld	hl,SKEW
	add	hl,de		; HL -> SKEW[remainder]
	ld	a,(hl)		; the sector ID on the disk
	ld	(DSEC),a	; for SECTIO
	call	SECTIO		; select, seek, transfer, retries
	jr	nz,DFAIL	; A = status bits
	ld	hl,(DADDR)
	inc	h		; next 256 bytes of the buffer
	ld	(DADDR),hl
	ld	hl,(R_DX)
	inc	hl		; next logical sector, in the 8086's DX
	ld	(R_DX),hl
	ld	hl,(R_CX)
	dec	hl		; one fewer to go, in the 8086's CX
	ld	(R_CX),hl
	jr	DLOOP		; the next sector
DDONE:					; also T_FMT's success exit
	call	UNHOOK		; 0038h back to the 8086's vector
	jp	CF0		; CF=0: done
; ---------------------------------------------------------------------
; DFAIL - A = status bits (ERRTAB's order): restore 0038h, translate the
; highest set bit 7..3 to a DOS code, AL = code, CF=1.  Also T_FMT's
; error exit.
; ---------------------------------------------------------------------
DFAIL:
	push	af		; UNHOOK uses A
	call	UNHOOK		; 0038h back to the 8086's vector
	pop	af		; the status again
	ld	hl,ERRTAB	; the status's top bit -> DOS error code
	ld	b,5		; bits 7..3 have entries; none set -> the 6th
DFAIL_SCAN:				; (src: DF1)
	rla			; next bit into carry, from bit 7 down
	jr	c,DFAIL_CODE	; the highest set bit decides
	inc	hl		; next entry
	djnz	DFAIL_SCAN	; five bits tried: HL ends on the 0Ch entry
DFAIL_CODE:				; (src: DF2)
	ld	a,(hl)		; the DOS code
DERR:
	ld	(R_AL),a	; AL = code (AH left alone)
	jp	CF1		; CF=1: error
DNRDY:					; also T_FMT's bad-drive exit
	ld	a,2		; no such drive: DOS 2, not ready (CX untouched;
	jr	DERR		;   HOOK38 not yet done, so no UNHOOK)

; ---------------------------------------------------------------------
; ERRTAB - status bit -> DOS 1.25 BIOS error code (0 write protect, 2 not
; ready, 4 data, 6 seek, 8 sector not found, 0Ch general failure).  The
; status bits are FDC Type II bits 6, 4, 3 (WP, RNF, CRC) as FDCINT
; returns them (AND 5Ch), plus two of the BIOS's own: 80h from SEEK,
; 20h from SELECT.  Bit 2 (lost data) has no entry and falls to 0Ch,
; as does DISKIO's 01h "buffer too high".
; ---------------------------------------------------------------------
ERRTAB:
	defb	6		; 80h SEEK gave up (10 tries): seek error
	defb	0		; 40h FDC write protect
	defb	2		; 20h SELECT's restore found no track 0 (no
				;     drive), or a floppy wait timed out
				;     (FDTOUT: no disk / no drive): not ready
	defb	8		; 10h FDC record not found (or DX past 719)
	defb	4		; 08h FDC CRC error: data error
	defb	0Ch		; none of the above (04h lost data, 01h bad
				;     buffer): general failure

; =====================================================================
; SECTIO - transfer one sector: DSEC of track DTRK on DDRIVE, at DADDR
; ---------------------------------------------------------------------
; Entry:  DDRIVE, DTRK, DSEC, DADDR, DWRITE set; 0038h hooked (HOOK38).
; Exit:   Z: done.  NZ: A = status bits as ERRTAB reads them (20h = timed
;         out, no disk or no drive).
; Corrupts: A, BC, DE, HL; DTRY, DSTAT; patches XFI.
; Callers: DISKIO only.
;
; RETRIES (10) attempts per sector, as CBIOS A1.1's RD256 / WR256 (its
; NTENT).  Write protect and a timeout return at once: DOS asks Abort /
; Retry / Ignore itself, and ten timeouts would mean 30 s of silence.
; Half-way through the retries FHOME restores to track 0: SEEK skips a
; seek to the track the FDC already reads, so without this a sector
; missed with head and track register out of step was never recovered
; (the 2026-11-08 change; before it, retries never moved the head).
; One routine, XFER (EALO page), now serves both directions: SECTIO
; patches its transfer instruction (INI / OUTI) and passes the command.
; =====================================================================
SECTIO:
	ld	a,(DDRIVE)	; the drive
	call	SELECT		; drive on, FDC track register for that drive
	ret	nz		; A = 20h: the drive is not there (or timed out)
	ld	a,RETRIES	; 10 transfer attempts
	ld	(DTRY),a
SECTIO_TRY:				; (src: SIO1)
	call	SEEK		; to DTRK, verified (no-op when already there)
	ret	nz		; A = 80h seek failed, or 20h timed out
	ld	a,(DSEC)	; the sector ID ...
	out	(FDCSEC),a	; ... for the FDC to look for
	ld	hl,(DADDR)	; buffer, for INI / OUTI
	ld	a,(DWRITE)	; 0 read / 1 write ...
	add	a,0A2h		; ... -> A2h (INI) / A3h (OUTI), the second byte
	ld	(XFI+1),a	;   of XFER's transfer instruction
	ld	a,(DWRITE)	; and the command: 0 -> 80h RDSCMD, 1 -> A0h WRSCMD
	rrca			; bit 0 -> bit 5
	rrca
	rrca
	add	a,RDSCMD
	call	XFER		; returns via FDCINT (status) or FDTOUT (20h)
	or	a		; any error bit?
	ret	z		; clean status: done
	bit	6,a		; write protected: no point retrying
	ret	nz		; (A = 40h+ -> DOS 0)
	bit	5,a		; timed out (only FDTOUT sets 20h): give up now
	ret	nz		;   (-> DOS 2, not ready)
	ld	(DSTAT),a	; keep the error for the last try
	ld	hl,DTRY		; one attempt used
	dec	(hl)
	jr	z,SECTIO_FAIL	; none left
	ld	a,(hl)		; half the tries gone?
	cp	RETRIES/2
	call	z,FHOME		; then restore, so the next SEEK really moves
	jr	SECTIO_TRY	; again
SECTIO_FAIL:
	ld	a,(DSTAT)	; out of tries (A held it anyway)
	or	a		; NZ: failed
	ret

; =====================================================================
;                    WD177x COMMAND BYTES AND STATUS MASKS
; =====================================================================
;
; Named after CBIOS A1.1's constants (bios_z80asm.asm, "Comandos de
; programacao"); a value CBIOS does not have, or has differently, gets a
; suffix (dict/CONVENTIONS.md: one name, one value, across both corpora).
; Bit fields as the WD1770/1772 datasheet gives them:
;   Type I   (Restore 0000, Seek 0001, Step-In 010u):  bit 3 h (1 = no
;            spin-up wait), bit 2 V (verify the ID on arrival), bits 1-0
;            r1r0 step rate (01 = 12 ms; boot.asm reads it the same way).
;   Type III (Write Track 1111): bit 3 h, bit 2 E (30 ms settle before
;            writing), bit 1 P (1 = write precompensation off), bit 0 = 0.
; The Read / Write Sector bytes (80h, A0h) are part 07's RDSCMD / WRSCMD (XFER).
RSTCMD:		equ	05h		; Restore, h=0 V=1 r=01: FHOME's normal
					;   byte (RESCMD).  Same value as CBIOS.
RSTCMD_NOVFY:	equ	01h		; Restore, V=0: for FORMAT TRACK, whose disk
					;   has no ID fields to verify against yet.
					;   Same name and value as boot.asm.
SEKCMD:		equ	15h		; Seek, h=0 V=1 r=01.  Same value as CBIOS.
SEKCMD_NOVFY:	equ	11h		; Seek, V=0: FORMAT TRACK's.  No CBIOS twin.
WTKCMD:		equ	0FEh		; Write Track, h=1 (motor already on) E=1
					;   P=1 (no precompensation).  Not in CBIOS
					;   (it has no formatter); the source says
					;   "as FORMAT 2.0", the CP/M formatter.
FDC_STAT_MASK:	equ	5Ch		; status bits FDCINT keeps: 6 write protect,
					;   4 seek error / record not found, 3 CRC,
					;   2 lost data (Type II) / track 0 (Type I).
					;   Drops 7 (motor on), 5, 1 (DRQ), 0 (BUSY).
FDC_SKERR_MASK:	equ	18h		; Type I after a verify: 4 seek error (no ID
					;   with this track number), 3 CRC in an ID
FDC_SEEKERR:	equ	10h		; Type I bit 4: Restore never saw track 0
FDC_WPROT:	equ	40h		; Type II/III bit 6: write protect

; =====================================================================
; FDCCMD - issue a WD177x command and wait for its INTRQ, ~3.4 s at most
; ---------------------------------------------------------------------
; Entry:  A = command; for a Seek, the target track already in FDCDAT;
;         0038h hooked to FDCINT (HOOK38).
; Exit:   A = status AND FDC_STAT_MASK, interrupts OFF (the RST 38h that
;         ended the wait left them off).  Or, if no INTRQ came: A = 20h,
;         NZ, through FDTOUT (no disk / no drive: a spin-up or a verify
;         needs index pulses, and the WD1770 would wait for ever).
; Corrupts A, B, DE.  Callers: SEEK, T_FMT.
;
; Lineage: CBIOS A1.1 SEKINT (`ld a,SEKCMD / im 1 / ei / out (FDCMD),a /
; jr $`), made generic and, since 2026-11-08, timed: the `jr $` became
; 8 x 65536 turns of FDCW at 26 T (~3.4 s at 4 MHz; a seek across all
; 40 tracks with spin-up and verify takes under 2 s).  The order EI,
; OUT matters: EI holds interrupts off for one more instruction, so the
; command is written - clearing any stale INTRQ - before an interrupt can
; be taken.  INTRQ arrives as RST 38h: FDCINT throws the loop's address
; away and RETs to our caller, wherever in the loop it struck.
; =====================================================================
FDCCMD:
	im	1		; INTRQ is a plain RST 38h: no vector byte needed
	ei			; takes effect after the OUT below
	out	(FDCMD),a	; go (also clears a stale INTRQ)
	ld	b,8		; timeout: 8 x 65536 turns
	ld	de,0
FDCW:
	dec	de		; FDCINT unwinds this loop when INTRQ comes
	ld	a,d
	or	e
	jr	nz,FDCW
	djnz	FDCW
	jp	FDTOUT		; ~3.4 s and no INTRQ: "not ready"

; =====================================================================
; FDCINT - the RST 38h handler for the WD177x INTRQ        (EDE3h)
; ---------------------------------------------------------------------
; Reached only through the JP FDCINT that HOOK38 writes at 0038h, while
; a disk call runs (FDCCMD, or XFER's wait and transfer loops).
; Entry:  top of stack = the address in the waiting loop (FDCW, XFER_WAIT,
;         XFER_LOOP) the interrupt pushed; under it, the caller's return.
; Exit:   RET to the caller of FDCCMD / XFER with A = status
;         AND FDC_STAT_MASK, interrupts left OFF (accepting the interrupt
;         reset IFF1/IFF2, and no EI follows): the rest of the BIOS and
;         the 8086 interpreter always run with interrupts disabled.
;
; Lineage: CBIOS A1.1 INTRPT byte for byte, except the mask: CBIOS keeps
; 9Ch (bits 7, 4, 3, 2).  On a WD1770 bit 7 is Motor On, not Not Ready,
; so this BIOS keeps write protect (bit 6) in its place - which
; SECTIO's "write protected: don't retry" test needs (provisional as to
; what CBIOS's bit 7 did on a real drive).
; The interrupt is how the transfer loop ends at all: XFER_LOOP only
; polls DRQ, and the last byte of a sector is followed by INTRQ, not by
; anything the loop could test.
; =====================================================================
FDCINT:
	pop	af		; drop the interrupted loop's address (AF itself is
				;   about to be overwritten)
	in	a,(FDCSTS)	; final status; reading it also clears INTRQ
	and	FDC_STAT_MASK	; keep only the error bits
	ret			; to whoever called the waiting loop (DI stays)

; =====================================================================
; SEEK - put the head on track DTRK, verified           (CBIOS FB7Ch)
; ---------------------------------------------------------------------
; Entry:  DTRK = wanted track; the drive selected and the FDC track
;         register valid for it (SELECT); 0038h hooked.
; Exit:   Z, A = 0: on the track.  NZ, A = 80h: RETRIES seeks failed
;         (ERRTAB's first entry: DOS error 6, seek error).  NZ, A = 20h:
;         the seek or its recovery restore timed out (DOS 2, not ready).
; Corrupts A, B, DE, HL.  Caller: SECTIO (part 07).
;
; No command at all when the FDC already thinks it is there: the track
; register is trusted, and the Read / Write Sector that follows checks
; the ID field's track number anyway (SECTIO's half-way FHOME is what
; breaks that trust when sectors keep failing).  Otherwise Seek with
; verify; a verify failure (seek error or ID CRC) restores to track 0
; and tries again from there, RETRIES (10) times - the CBIOS SEEKLP
; pattern.  A timeout ends it at once.  The target is re-read from DTRK
; each time: FDCCMD's timer uses B, where it used to be kept.
; FHOME lives in the EAHI page's free end, FDTOUT in the REGS page's
; (z86_interp.asm).
; =====================================================================
SEEK:
	ld	a,(DTRK)	; the track this call wants
	ld	b,a
	in	a,(FDCTRK)	; where the FDC believes the head is
	cp	b		; FDC already there?
	jr	z,SKOK		; already there: no seek, no verify
	ld	a,RETRIES	; a fresh seek budget
	ld	(STRY),a
SEEK_RETRY:				; (src: SK1)
	ld	a,(DTRK)	; the Seek target goes in the data register
	out	(FDCDAT),a
	ld	a,SEKCMD	; Seek with verify (15h, as CBIOS)
	call	FDCCMD		; wait for INTRQ (or the timeout)
	bit	5,a		; timed out: no disk / no drive -
	ret	nz		;   give up now (A = 20h, NZ)
	and	FDC_SKERR_MASK	; seek error or ID CRC?
	ret	z		; no: Z, A = 0
	call	FHOME		; lost: back to track 0 (track register = 0)
	bit	5,a		; that timed out too: give up
	ret	nz
	ld	hl,STRY		; one try fewer
	dec	(hl)
	jr	nz,SEEK_RETRY
	ld	a,80h		; out of tries: "seek failed" (ERRTAB 80h -> 6)
	or	a		; NZ
	ret
SKOK:
	xor	a		; Z: on the track
	ret

; =====================================================================
; SELECT - select drive A and give the FDC its head position  (CBIOS FA1Eh)
; ---------------------------------------------------------------------
; Entry:  A = drive 0-3 (callers have checked < NDRIVE).
; Exit:   Z, A = 0: drive selected, latch bit 7 low (busy light, see
;         LATCHC), FDC track register = that drive's head position.
;         NZ, A = 20h: a first restore failed (ERRTAB 20h -> DOS 2, not
;         ready).
; Corrupts A, B, C, HL.  Callers: SECTIO (part 07), T_FMT.
;
; One WD177x serves four drives, and its track register holds only one
; head position: TRKTAB keeps the others.  On a change of drive the old
; drive's position is saved from the FDC and the new one's loaded into
; it; a drive never used (FFh) is restored first.  CBIOS LIGHT does the
; same with its POINT table.  The track position is saved only on a
; change of drive, so TRKTAB's entry for the current drive is stale
; while it is current - harmless, the FDC holds the true value.
; =====================================================================
SELECT:
	ld	c,a		; C = new drive
	ld	a,(CURDRV)	; the drive the FDC was last set up for
	cp	c	; same as asked?
	jr	nz,SELECT_CHANGE
	call	LATCHC		; same drive: just light it again (UNHOOK
	xor	a		;   raised bit 7 after the last call)
	ret
SELECT_CHANGE:				; (src: SEL0)
	cp	NDRIVE		; CURDRV = FFh (none yet, or a failed restore):
	jr	nc,SELECT_NEW	;   nothing to save
	call	TRKPTR		; keep the old drive's head position
	in	a,(FDCTRK)	; the FDC's word for the old drive
	ld	(hl),a	;   into its TRKTAB slot
SELECT_NEW:				; (src: SEL1)
	ld	a,c	; the new drive becomes current
	ld	(CURDRV),a
	call	LATCHC		; select it on the latch
	ld	a,c	; its TRKTAB slot
	call	TRKPTR
	ld	a,(hl)		; its head position, if known
	cp	0FFh	; FFh: never found
	jr	z,SELECT_RESTORE	;   -> restore it first
	out	(FDCTRK),a	; the FDC now speaks for this drive
	xor	a	; Z: selected
	ret
SELECT_RESTORE:				; (src: SEL2)
	call	FHOME		; unknown: find track 0 (track register = 0)
	ret	z	; track 0 found: Z, FDC track register = 0
	ld	a,0FFh		; failed: forget the drive, so the next call
	ld	(CURDRV),a	;   tries the restore again
	ld	a,20h		; "no track 0": not ready
	or	a		; NZ
	ret

; =====================================================================
; LATCHC - write the drive latch for drive C
; ---------------------------------------------------------------------
; Entry:  C = drive 0-3.   Exit: latch and LATCH = the new value.
; Corrupts A, B.  Caller: SELECT.
;
; FEh rotated left C times leaves one 0 at bit C (drive selects are
; active low); AND 5Fh then clears bit 7 and bit 5 and keeps bit 6:
;   drive 0 5Eh, 1 5Dh, 2 5Bh, 3 57h =
;   bit 7 = 0   busy light (see below), bit 6 = 1  boot ROM out (RAM only),
;   bit 5 = 0   DDEN# = MFM,             bit 4 = 1  SIDE1# high: side 0,
;   bits 3-0    one select low.
; The source glosses bit 7 low as "head loaded".  No latch bit loads a
; head (boot_findings #1; the WD1770 has no HLD pin).  CBIOS calls bit 7
; LUZ, lit by `res LUZ` in LIGHT and put out by `set LUZ` in LIGHTOF,
; and this BIOS follows it (UNHOOK sets the bit).  fdd3000b.asm's HRD_LED
; gives the opposite polarity (1 = on): the two corpora disagree, and
; nothing here settles which is right (provisional).
; =====================================================================
LATCHC:
	ld	b,c		; B = drive + 1 turns of the loop below
	inc	b	; (LATCHC_SHIFT counts down to 0)
	ld	a,0FEh		; drive 0's select bit low
LATCHC_SHIFT:				; (src: LC1)
	dec	b	; one rotation per drive number
	jr	z,LATCHC_OUT
	rlca			; move the 0 up one drive
	jr	LATCHC_SHIFT
LATCHC_OUT:				; (src: LC2)
	and	5Fh		; bit 7 low (light), bit 5 low (MFM)
	out	(HRD),a	; to the latch
	ld	(LATCH),a	; the latch is write-only: keep a copy for UNHOOK
	ret

; ---------------------------------------------------------------------
; TRKPTR - HL = TRKTAB + A (drive A's head-position byte).  Corrupts A.
; Callers: SELECT.  (TRKTAB is 4 bytes; the carry test covers a page
; crossing that never happens at F10Fh.)
; ---------------------------------------------------------------------
TRKPTR:
	ld	hl,TRKTAB	; base of the 4 head positions
	add	a,l	; + drive
	ld	l,a
	ret	nc
	inc	h	; (page carry; never at F10Fh)
	ret

; =====================================================================
; HOOK38 / UNHOOK - borrow 0038h for the disk interrupt, then give it back
; ---------------------------------------------------------------------
; HOOK38: saves the three bytes at 0038h-003Ah in SAV38 and writes
;         JP FDCINT there.  Corrupts A, BC, DE, HL.
; UNHOOK: DI, puts the three bytes back, then raises latch bit 7 (the
;         busy light out, as CBIOS LIGHTOF; the drive stays selected and
;         the WD177x turns its motor off by itself after 10 idle turns).
;         Corrupts A, BC, DE, HL.
; Callers: HOOK38 - DISKIO (part 07), T_FMT; UNHOOK - DDONE, DFAIL
;         (part 07), which every exit of DISKIO and T_FMT after the hook
;         goes through.
;
; WHY BORROW AND RETURN.  The Z80's RST 38h vector is Z80 address 0038h,
; and Z80 0000h-CFFFh IS the 8086's memory (I86.ASM: linear n = Z80 n).
; 0038h = 0Eh x 4: the bytes are the offset and the low segment byte of
; the 8086's INT 0Eh vector (IRQ 6, the PC's diskette interrupt).  The
; 8086 world owns that vector - COLD zeroes it, and any program may read
; or set it through INT 21h - so the BIOS may use 0038h only while the
; 8086 is stopped inside a trap, and must leave it exactly as it was.
; Outside a disk call nothing needs it: interrupts stay disabled (START
; does DI) and nothing else on the FDD3000 raises INT.  CBIOS A1.1 does
; the same per READ / WRITE call (SAVJMP / PUTJMP, buffer BUFINT), there
; because CP/M programs own page zero too.  The DI in UNHOOK guards the
; restore: after it no INTRQ can reach the 8086's vector bytes.
; Edge (verified by reading, never seen): a disk buffer covering
; 0038h-003Ah would clash with the hook - a read would overwrite the JP
; with data (the end-of-command INTRQ then jumps into it), and UNHOOK
; would put the old vector bytes back over the data read; a write would
; send C3h E3h EDh.  DISKIO checks only the top of memory.  No DOS 1.25
; path reads a sector to linear 0000h-00FFh.
; =====================================================================
HOOK38:
	ld	hl,0038h	; save the 8086's INT 0Eh vector bytes ...
	ld	de,SAV38	; (the 3 bytes the JP will cover)
	ld	bc,3
	ldir	; the 8086's bytes into SAV38
	ld	a,0C3h		; ... and put JP FDCINT in their place
	ld	(0038h),a	; opcode at 0038h ...
	ld	hl,FDCINT	; ... and its operand, FDCINT
	ld	(0039h),hl	; INTRQ now ends in FDCINT
	ret

UNHOOK:
	di			; no INTRQ may reach 0038h from now on
	ld	hl,SAV38	; the 8086's vector bytes back
	ld	de,0038h	; (back where they came from)
	ld	bc,3
	ldir	; the hook gone
	ld	a,(LATCH)	; the latch as LATCHC left it
	or	80h		; latch bit 7 high: the busy light off (CBIOS
	out	(HRD),a		;   LIGHTOF's `set LUZ`)
	ld	(LATCH),a	; (the copy follows the latch)
	ret

; =====================================================================
; T_FMT - trap 1Bh, FORMAT TRACK (for FORMAT.COM)
; ---------------------------------------------------------------------
; Entry (8086):  AL = drive, DL = track, DS:BX = the track image,
;         FMTLEN bytes as the WD177x Write Track takes them.
; Exit (8086):   CF=0 done; CF=1 with AL = DOS error code: 0 write
;         protect, 2 not ready (no drive / no track 0), 8 track beyond
;         NTRACK, 0Ch image past the 8086's memory.
; Reached from TRAP through TTAB entry 1Bh.  FORMAT.ASM issues it as
; `DB 0FH,1BH` per track, then reads the track back with INT 25h.
;
; The image (FORMAT.ASM MKTRACK): 32 x 4Eh, then per sector 12 x 00h,
; 3 x F5h (the FDC writes A1h sync marks), FEh C H R N, F7h (the FDC
; writes the 2 CRC bytes), 22 x 4Eh, 12 x 00h, 3 x F5h, FBh, 256 x E5h,
; F7h, 16 x 4Eh = 332 bytes; 32 + 18 x 332 = FMTLEN (6008).  After the
; image the FDC is fed 4Eh until the index pulse ends the command.
;
; Error codes come out of part 07's DFAIL/ERRTAB from a status-like byte:
; 10h -> 8, 01h (no bit of 80h-08h set) -> 0Ch, 20h -> 2, 40h -> 0.
; Only write protect is tested at the end: lost data (a missed DRQ) is
; not, as FORMAT.COM's read-back catches a bad track anyway (verified,
; FORMAT.ASM).  The source's JR NC,DNRDY is a JP in the bytes (relaxed).
; =====================================================================
FMTLEN:	equ	32+SPT*332	; FORMAT.ASM's image (TRKLEN there)
T_FMT:
	ld	a,(R_AL)	; AL = drive
	cp	NDRIVE	; one of the four latch drives?
	jp	nc,DNRDY	; no such drive: AL = 2, before anything is hooked
	ld	(DDRIVE),a	; for SELECT
	call	HOOK38		; FDCCMD below needs the interrupt
	ld	a,(R_DL)	; DL = track
	ld	(DTRK),a	; (the seek target below)
	cp	NTRACK	; 0-39 only
	ld	a,10h		; past track 39: "record not found" -> 8
	jp	nc,DFAIL	;   -> AL = 8
	ld	hl,(B_DS)	; image's Z80 address = DS base + BX
	ld	de,(R_BX)	; + BX
	add	hl,de
	ld	(DADDR),hl	; where OUTI will read from
	ld	de,GTOP-FMTLEN+1	; the whole image must lie below GTOP
	or	a	; (clear carry for SBC)
	sbc	hl,de	; image end > GTOP?
	ld	a,01h		; -> ERRTAB's last entry, 0Ch general failure
	jp	nc,DFAIL	;   -> AL = 0Ch
	ld	a,RSTCMD_NOVFY	; restore without verify: a blank disk has no
	ld	(RESCMD),a	;   IDs for the verify to find
	ld	a,(DDRIVE)	; select it (restores a first-time drive)
	call	SELECT		; (restores only a drive not used yet)
	ld	b,a		; keep SELECT's result; LD leaves its flags
	ld	a,RSTCMD	; the normal Restore back at once
	ld	(RESCMD),a	; (for every later Restore)
	ld	a,b	; SELECT's A back, for DFAIL
	jp	nz,DFAIL	; SELECT's NZ: no track 0, AL = 2
	ld	a,(DTRK)	; seek without verify too: nothing to verify
	out	(FDCDAT),a	; (the Seek target)
	ld	a,SEKCMD_NOVFY	; Seek, V=0
	call	FDCCMD		; no verify, so no seek error - but it can time
				;   out: an empty drive with its motor off never
				;   finishes the spin-up (no index pulses)
	bit	5,a		; timed out (A = 20h): "not ready"
	jp	nz,DFAIL	;   (the write track below is not timed: a disk
				;   pulled with the motor running still hangs it)
	ld	hl,(DADDR)	; HL = the image
	ld	de,FMTLEN	; DE counts the image (OUTI's B is ignored)
	ld	c,FDCDAT	; C = data port for OUTI
	ld	a,WTKCMD	; Write Track
	out	(FDCMD),a	; from here on every DRQ wants a byte
T_FMT_IMAGE:				; (src: FT1)
	in	a,(COM)		; DRQ (bit 7) -> carry
	add	a,a	; DRQ -> carry
	jr	nc,T_FMT_IMAGE_IDLE	; no DRQ: is the command still running?
	outi			; next image byte to the FDC
	dec	de	; one image byte fewer
	ld	a,d
	or	e
	jr	nz,T_FMT_IMAGE	; until the whole image is out
T_FMT_GAP:				; (src: FT2)
	in	a,(COM)		; image done: gap 4Eh for every further DRQ,
	add	a,a		;   until the index pulse ends the command
	jr	nc,T_FMT_GAP_IDLE	; no DRQ: is the command still running?
	ld	a,4Eh	; gap filler
	out	(FDCDAT),a
	jr	T_FMT_GAP	; for as long as the FDC asks
T_FMT_GAP_IDLE:				; (src: FT4)
	in	a,(FDCSTS)	; no DRQ: still busy?
	rra	; BUSY -> carry
	jr	c,T_FMT_GAP	; still writing: keep feeding 4Eh
	jr	T_FMT_STATUS	; track written
T_FMT_IMAGE_IDLE:			; (src: FT3)
	in	a,(FDCSTS)	; no DRQ during the image: still busy?
	rra	; BUSY -> carry
	jr	c,T_FMT_IMAGE	; still writing: wait for the DRQ
				; ended early: write protect stops the command
				;   before the first byte
T_FMT_STATUS:				; (src: FT5)
	in	a,(FDCSTS)	; (this read also clears INTRQ)
	and	FDC_WPROT	; write protect: 40h -> AL = 0
	jp	nz,DFAIL	; protected: AL = 0 (DFAIL unhooks)
	jp	DDONE		; unhook, CF=0

; =====================================================================
; T_DSKCHG - trap 9, DISK CHANGE: AH = 0, "don't know"
; ---------------------------------------------------------------------
; The FDD3000 has no disk-change line, so DOS must check the FAT itself.
; CF=0.  Reached through TTAB.
; =====================================================================
T_DSKCHG:
	xor	a		; AH = 0: don't know
	ld	(R_AH),a	; (DOS 1.25 then reads the FAT again)
	jp	CF0	; CF=0: no error

; =====================================================================
;                    CLOCK - traps 10-12 (0Ah-0Ch)
; ---------------------------------------------------------------------
; The FDD3000 has no clock (BIOS.ASM header).  The date and time are
; simply what DOS last set, held unchanged: at boot 0 days = 1-1-80,
; 0:00:00.00, and they never advance.  IO.SYS's clock device calls these.
; =====================================================================

; T_SDATE - trap 10, SET DATE: AX = days since 1-1-80.  Corrupts HL.
T_SDATE:
	ld	hl,(R_AX)	; AX = days since 1-1-80
	ld	(DAYS),hl	; kept as is: nothing counts it on
	ret

; T_STIME - trap 11, SET TIME: CH hour, CL minute, DH second, DL
; hundredths; stored as given.  Corrupts HL.
T_STIME:
	ld	hl,(R_CX)	; CH:CL = hour:minute
	ld	(CLKCX),hl
	ld	hl,(R_DX)	; DH:DL = second:hundredths
	ld	(CLKDX),hl
	ret

; T_GTIME - trap 12, GET DATE AND TIME: AX = days, CX and DX as T_STIME
; left them.  Corrupts HL.
T_GTIME:
	ld	hl,(DAYS)	; the date as last set
	ld	(R_AX),hl
	ld	hl,(CLKCX)	; the time as last set: it never moves
	ld	(R_CX),hl
	ld	hl,(CLKDX)
	ld	(R_DX),hl
	ret

; =====================================================================
;                    PC ROM BIOS - traps 10h-12h, 14h, 16h, 17h, 1Ah
; ---------------------------------------------------------------------
; The parts of the IBM PC ROM BIOS that PC-DOS programs (IBM's DEBUG,
; CHKDSK...) call directly, mapped onto the VT52 terminal (80 x 24) and
; the WD2123 serial channels.  IO.SYS points each vector at a stub
; `TRAP n / RETF 2` (IOFDD.ASM INT10...), so ZF / CF set here survive
; the return to the caller.  Same choices as fddos.py rom_bios, except
; INT 17h and INT 1Ah (noted there).  Functions not listed return with
; the registers untouched.
; =====================================================================

; =====================================================================
; T_I10 - INT 10h video
; ---------------------------------------------------------------------
;   AH 0Eh  teletype: AL to the console (BL, BH ignored)
;   AH 0Fh  get mode: AH = 80 columns, AL = 7 (mono), BH = page 0
;   AH 02h  set cursor DH, DL: VT52 ESC Y row+32 col+32, clamped to 23/79
;   AH 03h  get cursor: not tracked - DX = 0 (top left), CX = 0607h
;           (start/end scan lines: the CGA shape, though mode 7 was
;           reported - harmless, nothing here draws a cursor)
;   AH 06h/07h with AL = 0  clear window: the whole screen, ESC H ESC J
;           (the window CX..DX is ignored; AL <> 0, a real scroll, is
;           ignored altogether)
;   AH 09h/0Ah  write AL CX times - through CONOUT, so unlike a PC the
;           cursor moves past them
; Corrupts A, HL (and what CONOUT corrupts).  Reached through TTAB.
; =====================================================================
T_I10:
	ld	a,(R_AH)	; AH = function
	cp	0Eh		; teletype
	jr	nz,T_I10_MODE	; not teletype
	ld	a,(R_AL)	; AL = character
	jp	CONOUT	; (CONOUT returns for us)
T_I10_MODE:				; (src: I10A)
	cp	0Fh		; get video mode
	jr	nz,T_I10_SETCUR	; not get-mode
	ld	hl,5007h	; AH = 50h = 80 columns, AL = 7 = mono text
	ld	(R_AX),hl	; (AX = 5007h)
	xor	a	; (BH = 0)
	ld	(R_BH),a	; active page 0
	ret
T_I10_SETCUR:				; (src: I10B)
	cp	02h		; set cursor position
	jr	nz,T_I10_GETCUR	; not set-cursor
	ld	a,1Bh		; VT52 direct cursor address: ESC Y row col,
	call	CONOUT		;   each biased by 32
	ld	a,'Y'	; the cursor-address command letter
	call	CONOUT	; (ESC Y)
	ld	a,(R_DH)	; row, at most 23 (24 lines)
	cp	23	; VT52 rows 0-23
	jr	c,T_I10_ROW	; in range
	ld	a,23	; lower rows: the last line
T_I10_ROW:				; (src: I10B1)
	add	a,32	; row + 32
	call	CONOUT	; row byte
	ld	a,(R_DL)	; column, at most 79
	cp	79	; VT52 columns 0-79
	jr	c,T_I10_COL	; in range
	ld	a,79	; beyond: the last column
T_I10_COL:				; (src: I10B2)
	add	a,32	; column + 32
	jp	CONOUT	; column byte (CONOUT returns for us)
T_I10_GETCUR:				; (src: I10C)
	cp	03h		; read cursor: the terminal is not asked
	jr	nz,T_I10_SCROLL	; not get-cursor
	ld	hl,0		; DH = row 0, DL = column 0
	ld	(R_DX),hl	; (DX = 0000h)
	ld	hl,0607h	; cursor scan lines 6-7
	ld	(R_CX),hl	; (CX = 0607h)
	ret
T_I10_SCROLL:				; (src: I10D)
	cp	06h		; scroll up / down ...
	jr	z,T_I10_CLEAR	; scroll up
	cp	07h	; scroll down
	jr	nz,T_I10_WRCHR	; neither
T_I10_CLEAR:				; (src: I10D1)
	ld	a,(R_AL)	; ... only AL = 0, "blank the window", is done
	or	a	; AL = 0?
	ret	nz	; a real scroll: not done
	ld	a,1Bh	; ESC
	call	CONOUT	; (ESC ...)
	ld	a,'H'		; ESC H: cursor home
	call	CONOUT	; (ESC H)
	ld	a,1Bh	; ESC
	call	CONOUT	; (ESC ...)
	ld	a,'J'		; ESC J: erase to the end of the screen
	jp	CONOUT	; (ESC J; CONOUT returns for us)
T_I10_WRCHR:				; (src: I10E)
	cp	09h		; write character (with or without attribute)
	jr	z,T_I10_REPEAT	; 09h: character and attribute
	cp	0Ah	; 0Ah: character only
	ret	nz		; anything else: ignored
T_I10_REPEAT:				; (src: I10E1)
	ld	hl,(R_CX)	; count
T_I10_REPEAT_LOOP:			; (src: I10E2)
	ld	a,h	; count left?
	or	l
	ret	z		; CX = 0: nothing (a PC would not do 65536 either)
	push	hl		; CONOUT corrupts HL
	ld	a,(R_AL)	; the character, again
	call	CONOUT	; (the attribute in BL is ignored)
	pop	hl
	dec	hl	; one fewer
	jr	T_I10_REPEAT_LOOP

; T_I11 - INT 11h equipment word: AX = 0071h = bit 0 floppies present,
; bits 5-4 = 11 (80x25 mono), bits 7-6 = 01 (two drives, as IO.SYS has
; A: and B:).  Corrupts HL.
T_I11:
	ld	hl,0071h	; floppies, mono 80x25, two drives
	ld	(R_AX),hl	; AX = equipment word
	ret

; T_I12 - INT 12h memory size: AX = GTOP / 1024 = 52 KB.  Corrupts HL.
T_I12:
	ld	hl,GTOP/1024	; 52
	ld	(R_AX),hl	; AX = KB of 8086 memory
	ret

; =====================================================================
; T_I16 - INT 16h keyboard (the terminal's keys via GETKEY / PEEKEY)
; ---------------------------------------------------------------------
;   AH 0  wait for a key: AL = key, AH = 0 (no scan codes on a terminal)
;   AH 1  look: ZF=1 none; ZF=0 and AX = the key, left for AH 0
;   other (AH 2 shift flags): AL = 0
; Corrupts A, HL.  Reached through TTAB.
; =====================================================================
T_I16:
	ld	a,(R_AH)	; AH = function
	or	a
	jr	nz,T_I16_PEEK	; not 0: look or other
	call	GETKEY		; waits
	ld	l,a	; L = key
	ld	h,0		; AH = 0: scan code unknown
	ld	(R_AX),hl	; AX = key, AH = 0
	ret
T_I16_PEEK:				; (src: I16A)
	dec	a	; AH = 1?
	jr	nz,T_I16_OTHER	; no: 2 and up
	call	PEEKEY		; CF=1: a key, in A, kept in KBUF
	jp	nc,ZF1		; none: ZF=1
	ld	l,a	; L = key
	ld	h,0	; no scan code
	ld	(R_AX),hl	; AX = the key, which stays queued
	jp	ZF0		; ZF=0: key available
T_I16_OTHER:				; (src: I16B)
	xor	a		; shift state: nothing held
	ld	(R_AL),a	; AL = 0: no shift / lock keys down
	ret

; =====================================================================
; T_I14 - INT 14h serial port, on the WD2123's two channels
; ---------------------------------------------------------------------
; Entry (8086):  DX = 0 channel A (the printer port, as CBIOS's LIST),
;         1 channel B (AUX); any other DX: return untouched.
;   AH 0  set up from AL (PC format)        -> I14INI (part 02, BCORE page)
;   AH 1  send AL                           -> SPUT
;   AH 2  receive into AL                   -> SGET
;   AH 3  status                            -> SSTAT
;   AH 4  set up from BX, CX (PS/2 format)  -> I14EXT (part 02)
; Exit:   AH = line status (bit 7: timed out), AL = modem status for AH 3;
;         for AH 1 AL is the byte sent (unchanged), for AH 2 the byte
;         received.  (The source's header says "AL = modem status" for
;         every AH; for AH 1 and 2 SSTAT's AL is overwritten, as here.)
; Corrupts A, BC, DE, HL.  Reached through TTAB.
;
; C = the channel's control/status port (UART_CMD_CHA / _CHB), the
; convention of the serial routines in the REGS page (part 01).  The
; timeout HL = FFFFh polls: about 1.6 s for SPUT, 2.3 s for SGET at
; 4 MHz (SWAIT loop counts; the FDD3000 clock is not documented).
; =====================================================================
T_I14:
	ld	hl,(R_DX)	; DX = port number
	ld	c,UART_CMD_CHA	; DX = 0: channel A
	ld	a,h	; high byte
	or	a
	ret	nz		; DX >= 256: no such port
	or	l	; low byte: 0?
	jr	z,T_I14_FUNC	; COM1 = channel A
	dec	a	; 1?
	ret	nz		; DX = 2 or more: no such port
	ld	c,UART_CMD_CHB	; DX = 1: channel B
T_I14_FUNC:				; (src: I14A)
	ld	a,(R_AH)	; AH = function
	or	a	; 0?
	jp	z,I14INI	; 0: set up (I86.ASM, BCORE page)
	dec	a	; 1?
	jr	z,I14PUT	;   send
	dec	a	; 2?
	jr	z,I14GET	;   receive
	dec	a	; 3?
	jp	z,SSTAT		; 3: status only, straight into AH / AL
	dec	a	; 4?
	ret	nz		; 5 and up: nothing
	jp	I14EXT		; 4: extended set-up (I86.ASM, with 0)
I14PUT:
	ld	a,(R_AL)	; the byte to send
	ld	e,a		; SPUT sends E
	ld	hl,0FFFFh	; timeout, about 1.6 s
	call	SPUT		; CF=1: DSR / TxRDY never came
	jr	T_I14_STATUS	; status + timeout bit
I14GET:
	ld	hl,0FFFFh	; timeout, about 2.3 s
	call	SGET		; A = byte, CF=1 on timeout
	ld	e,a	; E = the byte (garbage on a timeout)
T_I14_STATUS:				; (src: I14T)
	sbc	a,a		; CF -> A = FFh / 00h
	and	80h		; bit 7: timed out
	ld	d,a	; D = 80h if timed out
	push	de		; SSTAT uses B, D, E, HL
	call	SSTAT		; AH = line status, AL = modem status
	pop	de	; D, E back
	ld	a,e		; AL = the byte sent / received
	ld	(R_AL),a	; (PC: AL kept for 1, byte for 2)
	ld	hl,R_AH	; AH as SSTAT left it ...
	ld	a,d		; AH |= timeout flag
	or	(hl)	; ... plus the timeout bit
	ld	(hl),a
	ret

; =====================================================================
; T_I17 - INT 17h printer: channel A whatever DX is (every LPTn)
; ---------------------------------------------------------------------
;   AH 0  print AL (SPUT, ~1.6 s timeout); then the status
;   other (1 initialise, 2 status): the status only - set-up is
;         COLD's / INT 14h's business
; Exit:   AH = 90h ready (not busy + selected) when DSR is on, 10h busy
;         (selected, DSR off); +1 timed out (AH 0 only).
; Corrupts A, C, E, HL.  Reached through TTAB.  fddos.py always answers
; 90h; here DSR, the printer's busy line in CBIOS's wiring, is read.
; =====================================================================
T_I17:
	ld	c,UART_CMD_CHA	; the printer is channel A
	ld	e,0		; no timeout so far
	ld	a,(R_AH)	; AH = function
	or	a
	jr	nz,T_I17_STATUS	; not 0: status only
	ld	a,(R_AL)	; the character to print
	ld	e,a	; (SPUT sends E)
	ld	hl,0FFFFh	; timeout, about 1.6 s
	call	SPUT	; CF=1: not ready in time
	sbc	a,a		; CF -> bit 0: timed out
	and	1	; (AH bit 0)
	ld	e,a	; E = timeout bit
T_I17_STATUS:				; (src: I17A)
	in	a,(c)		; 8251A status: bit 7 = DSR
	rla	; DSR -> carry
	ld	a,10h		; DSR off: busy, selected
	jr	nc,T_I17_SET	; DSR off: busy
	ld	a,90h		; DSR on: not busy, selected
T_I17_SET:				; (src: I17B)
	or	e	; + timeout
	ld	(R_AH),a	; AH = printer status
	ret

; =====================================================================
; T_I1A - INT 1Ah AH = 0: read the tick count
; ---------------------------------------------------------------------
; Exit:  CX:DX = TICKS, then TICKS + 1 (32 bits); AL = 0 (no midnight).
; No clock: the count goes up by one per call, so programs that time
; themselves by it see time pass only as they ask (0 on the first call).
; AH = 1 (set the count) and others are ignored.  fddos.py returns the
; host's real time instead.  Corrupts A, HL.  Reached through TTAB.
; =====================================================================
T_I1A:
	ld	a,(R_AH)	; AH = function
	or	a
	ret	nz		; only "read" is served
	ld	(R_AL),a	; AL = 0: midnight not passed
	ld	hl,(TICKS+2)	; CX = high word
	ld	(R_CX),hl	; CX = high word of the count
	ld	hl,(TICKS)	; DX = low word
	ld	(R_DX),hl	; DX = low word
	inc	hl		; the count goes up per call
	ld	(TICKS),hl	; low word + 1
	ld	a,h
	or	l
	ret	nz	; no wrap
	ld	hl,(TICKS+2)	; low word wrapped: carry into the high word
	inc	hl	; high word + 1
	ld	(TICKS+2),hl
	ret

; =====================================================================
; T_CPML - trap 1Ch: load (BP <> 0) or run (BP = 0) CPM.COM's Z80 part
; ---------------------------------------------------------------------
; Entry (8086):  BP = linear address of CPMZ80's image inside CPM.COM
;         (CPM.ASM: CS x 16 + OFFSET Z80), laid out by z86.py cpmz80():
;           +0   length of the code (word)
;           +2   the addresses NEXT, JPHL, PEEKEY, GETKEY, CONOUT, DCSP,
;                ENDBIOS it was assembled against (7 words = CPMSYM)
;           +16  the code, assembled to run at ENDBIOS
; Exit:   load - CF=0: copied to ENDBIOS, over COLD; CF=1: the header
;         does not match this Z86.SYS (CPM.COM prints "CPM.COM does not
;         match Z86.SYS").  BP = 0 - JP ENDBIOS = T_CPM (CPMZ80.ASM), with
;         TRAP's frame still on the stack: T_CPM ends with a RET from
;         this trap back to CPM.COM.  Its register contract (CPMZ80.ASM
;         header): BX = SWLEN, DX = P, CX = program bytes, SI = FCBs and
;         tail, DI = DOSLEN, AL = drive.
; Reached through TTAB.
;
; CPMZ80 calls into Z86.SYS by absolute address, so it is only valid
; against the exact build it was assembled with: comparing these seven
; addresses is the build check.  ENDBIOS is among them, so the copy
; target moved by a different BIOS is caught too.  The length is not
; checked here; z86.py asserts at build time that CPMZ80's buffer ends
; below FF00h (the Z80 stack).
; Edge (verified by reading): BP = 0 before any copy jumps to COLD
; itself, still intact at ENDBIOS - a full reboot of DOS.  CPM.COM
; never does that (it loads first, and stops on CF=1).
; =====================================================================
T_CPML:
	ld	hl,(R_BP)	; linear = Z80 address
	ld	a,h	; BP = 0?
	or	l
	jp	z,ENDBIOS	; BP = 0: run what is there (T_CPM)
	ld	c,(hl)		; BC = code length
	inc	hl	; (the length word, high byte next)
	ld	b,(hl)	; BC = code length
	inc	hl	; HL -> the 7 addresses
	push	bc	; length, for the LDIR
	ld	de,CPMSYM	; the image's 7 addresses against ours
	ld	b,CPMSYE-CPMSYM	; 14 bytes
T_CPML_CHECK:				; (src: TL1)
	ld	a,(de)	; our address byte
	cp	(hl)	; the image's
	jr	nz,T_CPML_BAD	; any difference: wrong build
	inc	de
	inc	hl
	djnz	T_CPML_CHECK	; all 14 bytes
	pop	bc		; HL = the code now
	ld	de,ENDBIOS	; over COLD: the boot is long done
	ldir	; CPMZ80 into place, over COLD
	jp	CF0	; CF=0: loaded
T_CPML_BAD:				; (src: TL2)
	pop	bc		; built for another Z86.SYS: refuse
	jp	CF1	; CF=1: 'CPM.COM does not match Z86.SYS'

; =====================================================================
; T_RET - trap 1Dh: the end of an INT 21h that CPMZ80's DOSCALL started
; ---------------------------------------------------------------------
; DOSCALL saves the Z80 SP in DCSP (its caller's return address on top),
; then runs the 8086 interpreter on the stub at P+PSTUB: `INT 21h /
; TRAP 1Dh`.  When DOS returns, the trap lands here: SP back to DCSP
; discards TRAP's frame and everything the interpreter stacked, and the
; RET returns from DOSCALL to its caller, still in Z80 code.  DCSP = 0
; (no DOSCALL in progress): a stray TRAP 1Dh is a plain no-op RET.
; Corrupts HL (A, F when DCSP = 0).  Reached through TTAB.
; =====================================================================
T_RET:
	ld	hl,(DCSP)	; DOSCALL's SP, if one is waiting
	ld	a,h
	or	l	; 0: none
	ret	z		; not inside DOSCALL: ignore
	ld	sp,hl		; DOSCALL's stack, its caller's address on top
	ld	hl,0		; done: disarm
	ld	(DCSP),hl	; (a second TRAP 1Dh is now harmless)
	ret			; out of DOSCALL

; ---------------------------------------------------------------------
; CPMSYM - the Z86.SYS addresses CPMZ80 depends on, in z86.py
; cpmz80()'s order; T_CPML compares CPM.COM's copy with this.
;   NEXT D83Bh, JPHL EB60h, PEEKEY EBF6h, GETKEY EC13h, CONOUT EC21h,
;   DCSP F12Ah, ENDBIOS F12Ch (this build).
; ---------------------------------------------------------------------
CPMSYM:
	defw	NEXT, JPHL, PEEKEY, GETKEY, CONOUT, DCSP, ENDBIOS	; D83B EB60 EBF6 EC13 EC21 F12A F12C
CPMSYE:

; Free bytes (14 in the 2026-11-08 build).  The floppy timeouts made the
; BIOS shorter - RDSEC / WRSEC / FHOME moved to the EA table pages - and
; this padding keeps SKEW, the variables and ENDBIOS where the version
; that ran on a real FDD3000 had them (SKEW at F0F8h): CPMZ80, assembled
; for those addresses and checked by trap 1Ch, is then byte-identical
; and CPM.COM needs no rebuild.  z86.py asserts SKEW == SKEWAT.
SKEWAT:	equ	0F0F8h
	defs	SKEWAT-$

; =====================================================================
;                    BIOS DATA (F0F8h-F12Bh)
; =====================================================================

; SKEW - logical sector within a track (0-17) -> sector ID: a 2:1
; interleave.  e = 0-8 -> 2e (0, 2 .. 16), e = 9-17 -> 2e - 17 (1, 3
; .. 17): one turn reads the even IDs, the next the odd ones, giving the
; Z80 a sector's time between two reads.  The same table as boot.asm's
; LOAD arithmetic and mkfat.py.  Used by DISKIO (part 07).
SKEW:
	defb	0,2,4,6,8,10,12,14,16,1,3,5,7,9,11,13,15,17	; IDs for logical 0-8, then 9-17
RESCMD:
	defb	05h	; FHOME's Restore byte: RSTCMD (verify); T_FMT puts
			;   RSTCMD_NOVFY here round its SELECT, then 05h back
KFLAG:
	defb	0	; console: 1 = KBUF holds a key PEEKEY has taken
KBUF:
	defb	0	; console: that key
COCHR:
	defb	0	; console: CONOUT's character, kept across a retry
CURDRV:
	defb	0FFh	; drive selected last (FFh: none, or its restore failed)
TRKTAB:
	defb	0FFh,0FFh,0FFh,0FFh	; head position per drive 0-3, saved by
					;   SELECT on a change (FFh unknown:
					;   restore first)
LATCH:
	defb	0FFh	; copy of the write-only drive latch (HRD)
DWRITE:
	defb	0	; DISKIO: 0 read, 1 write
DDRIVE:
	defb	0	; drive of the current disk call
DTRK:
	defb	0	; its track ...
DSEC:
	defb	0	; ... and sector ID (through SKEW)
DTRY:
	defb	0	; SECTIO's retry count (RETRIES)
STRY:
	defb	0	; SEEK's retry count (RETRIES)
DSTAT:
	defb	0	; SECTIO: last failing status (for ERRTAB)
DADDR:
	defw	0	; Z80 address of the current sector buffer / format image
SAV38:
	defb	0,0,0	; the 8086's INT 0Eh vector bytes at 0038h-003Ah while
			;   HOOK38 holds them
DAYS:
	defw	0	; date: days since 1-1-80 (T_SDATE)
CLKCX:
	defw	0	; time: CH hour, CL minute (T_STIME)
CLKDX:
	defw	0	; time: DH second, DL hundredths
TICKS:
	defw	0,0	; INT 1Ah count, low word first (+1 per call)
DCSP:
	defw	0	; CPMZ80: Z80 SP inside DOSCALL (0: none) - see T_RET

; =====================================================================
; ENDBIOS - F12Ch: the end of the resident BIOS
; ---------------------------------------------------------------------
; Everything from here to BIOSEND (COLD and its strings, F12Ch-F220h) is
; needed once, at boot.  Trap 1Ch copies CPM.COM's Z80 part here, over
; it (DISASSEMBLY_GUIDE item 6: CPMZ80 runs at F12Ch-FAF5h, its buffer
; to FEF5h, below the Z80 stack at FFxxh); so after the first CPM.COM
; run these bytes are no longer COLD.
; =====================================================================
ENDBIOS:

; =====================================================================
; COLD - boot: from the boot sector to the 8086 at 0040:0000
; ---------------------------------------------------------------------
; Entry:  from BOOTJP (D0FDh: JP COLD), which BOOT.ASM jumps to with
;         this image at D000h, interrupts off and the boot ROM paged out.
; Exit:   never returns: JP START with the 8086 at 0040:0000, or HALT
;         after "Disk boot failure".
;
;  1. Both serial channels as CBIOS A1.1 sets them (its SIOTAB: 02h 16x
;     clock + 0Ch 8 bits + no parity + 80h 1.5 stop bits = mode 8Eh,
;     baud code 08 = 1200).
;  2. 0000h-03FFh, the 256 8086 interrupt vectors, zeroed: IO.SYS sets
;     the ones it serves.
;  3. The first directory sector (entries 0-7) to linear C000h, through
;     the BIOS's own READ trap code (T_READ, drive 0).
;  4. Entry 1 must be IO.SYS: loaded to 0000:0400h = 0040:0000, under 3
;     sectors so it ends below 0600h.  Entry 2 must be MSDOS.SYS: to
;     0060:0000, under 41 sectors (10 KB).  Each is read contiguously
;     from its first cluster without the FAT - FORMAT /S and mkfat.py
;     put Z86.SYS, IO.SYS, MSDOS.SYS first and contiguous - and its size
;     is the low word of the directory size (rounded up to sectors).
;  5. The 8086 registers: all general and segment registers 0, then
;     CS = DS = 0040h, IP = 0, flags clear (DF = 0, IF = 0) - as fddos.py
;     boot does.  SS:SP = 0:0 is not a usable stack, but IO.SYS's INIT
;     sets SS and SP first thing (IOFDD.ASM).  START computes the
;     segment bases from these.
; Corrupts everything.  Overwritten by CPMZ80 at run time (above).
; =====================================================================
DIRBUF:	equ	0C000h	; in the 8086's memory, free at boot
COLD:
	di	; (already off from BOOT.ASM; COLD makes sure)
	ld	sp,0		; Z80 stack from the top of RAM down
	ld	c,UART_CMD_CHA	; both serial channels as CBIOS A1.1 sets them:
	ld	de,8E08h	;   D = mode 8Eh (8 bits, no parity, 1.5 stop,
	call	SSET		;   16x), E = baud code 8 (1200)
	ld	c,UART_CMD_CHB	; channel B (AUX): the same D, E
	call	SSET	; (SSET keeps D, E)
	ld	hl,0		; clear the 8086 vector table, 0000h-03FFh
	ld	de,1	; (LDIR copies each zero one byte up)
	ld	bc,3FFh	; 1023 more bytes
	ld	(hl),l		;   (L = 0)
	ldir	; vectors 00h-FFh = 0000:0000
	ld	hl,DIRBUF	; directory sector 1 (entries 0-7) to C000h
	ld	de,1	; one sector
	ld	bc,FIRDIR	; logical 5: the first directory sector
	call	CLOAD	; read it (stops on error)
	ld	hl,DIRBUF+32	; entry 1: IO.SYS to 0040:0000 ...
	ld	de,IONAM	; must be named IO.SYS
	ld	bc,0400h	; linear 0400h = 0040:0000
	ld	a,3		; ... at most 2 sectors: MSDOS.SYS is at 0600h
	call	CFILE	; name, size, load (stops on error)
	ld	hl,DIRBUF+64	; entry 2: MSDOS.SYS to 0060:0000 ...
	ld	de,DOSNAM	; must be named MSDOS.SYS
	ld	bc,0600h	; linear 0600h = 0060:0000
	ld	a,41		; ... at most 40 sectors, 10 KB
	call	CFILE	; name, size, load (stops on error)
	ld	hl,R_AX		; AX-DI and ES CS SS DS (D000h-D017h): 0
	ld	b,24	; 8 + 4 registers, 2 bytes each
COLD_CLEAR_REGS:			; (src: CB1)
	ld	(hl),0
	inc	hl
	djnz	COLD_CLEAR_REGS	; (D000h-D017h)
	ld	hl,40h		; CS = DS = 0040h: IO.SYS's segment
	ld	(R_CS),hl	; CS = 0040h
	ld	(R_DS),hl	; DS = 0040h
	ld	hl,0	; IP = 0: IO.SYS's first byte
	ld	(TMP),hl	; IP = 0 (START takes it from TMP)
	xor	a	; (A = 0)
	ld	(FLAGHI),a	; DF, IF, TF = 0
	ld	hl,0100h	; F' = 0 (S Z AF OF CF clear), A' = 1 (odd
	push	hl		;   parity: PF = 0)
	pop	af	; AF = 0100h
	ex	af,af'		; the 8086 flags live in AF'
	jp	START		; bases from the segments, then FARJ to CS:IP

; =====================================================================
; CFILE - check a directory entry's name and load the file
; ---------------------------------------------------------------------
; Entry:  HL = directory entry, DE = the 11-byte 8+3 name it must have,
;         BC = linear load address (segment 0), A = sector limit (the
;         file must be SHORTER than A sectors).
; Exit:   falls into CLOAD with HL = BC, BC = logical sector =
;         FIRREC + 4 x (first cluster - 2), DE = sectors; returns from
;         CLOAD on success.  Wrong name, too big, or a read error:
;         CBAD (never returns; the pushed words do not matter then).
; Corrupts everything.  Caller: COLD.
; A size of 0 loads nothing and is not refused (edge, never met: FORMAT
; /S copies real files).
; =====================================================================
CFILE:
	push	bc		; load address  (popped last, into HL)
	push	af		; limit         (popped into BC: B = limit)
	push	hl		; entry
	ld	b,11	; 8 + 3 name bytes
CFILE_NAME:				; (src: CFL1)
	ld	a,(de)		; the name, all 11 bytes
	cp	(hl)	; same as the entry's?
	jr	nz,CBAD		; not the system file: boot failure
	inc	de
	inc	hl
	djnz	CFILE_NAME	; all 11
	pop	hl	; HL = the entry again
	ld	de,26		; +26 first cluster, +28 size (low word)
	add	hl,de	; HL -> first cluster
	ld	e,(hl)		; DE = first cluster
	inc	hl	; (cluster word, high byte next)
	ld	d,(hl)
	inc	hl	; HL -> size, low byte
	ld	a,(hl)		; size low byte: any bytes past a whole sector?
	inc	hl	; HL -> size, second byte
	or	a	; low byte 0: whole sectors
	ld	a,(hl)		; sectors = size / 256 ...
	jr	z,CFILE_LIMIT	; no partial last sector
	inc	a		; ... rounded up
CFILE_LIMIT:				; (src: CFL2)
	pop	bc		; B = the limit (the pushed AF)
	cp	b	; under the limit?
	jr	nc,CBAD		; too big for its place
	ex	de,hl	; HL = first cluster
	dec	hl		; logical sector = FIRREC + 4 (cluster - 2):
	dec	hl		;   4 sectors (1 KB) per cluster
	add	hl,hl	; x 2
	add	hl,hl	; x 4
	ld	bc,FIRREC	; + 13: cluster 2's logical sector
	add	hl,bc
	ld	b,h		; BC = first logical sector
	ld	c,l	; (C = low byte)
	ld	e,a		; DE = sector count
	ld	d,0	; (D = 0)
	pop	hl		; HL = load address
; ---------------------------------------------------------------------
; CLOAD - read DE sectors from logical sector BC of drive 0 to 0000:HL,
; by filling the 8086 registers and calling T_READ (part 07), the same
; code DOS's READ uses.  Returns if all were read (CX = 0 left); else
; falls into CBAD.  Corrupts everything.  Callers: COLD, CFILE.
; Only B_DS, the base, is set: T_READ adds BX to it and never reads R_DS.
; ---------------------------------------------------------------------
CLOAD:
	ld	(R_BX),hl	; BX = offset
	ld	(R_CX),de	; CX = count
	ld	(R_DX),bc	; DX = first logical sector
	xor	a	; (A = 0)
	ld	(R_AL),a	; AL = drive 0
	ld	h,a	; HL = 0 ...
	ld	l,a
	ld	(B_DS),hl	; DS base 0: BX is the linear address
	call	T_READ		; CF in AF', CX = sectors left
	ld	hl,(R_CX)	; sectors T_READ could not read
	ld	a,h
	or	l	; 0: all read
	ret	z		; all read
; ---------------------------------------------------------------------
; CBAD - print "Disk boot failure" and stop for good (interrupts off).
; Reached by JR from CFILE (wrong name, too big) and by falling out of
; CLOAD (read error).
; ---------------------------------------------------------------------
CBAD:
	ld	hl,BOOTMSG	; the message
CBAD_PRINT:				; (src: CB2)
	ld	a,(hl)		; 00h ends the text
	or	a	; end of text?
	jr	z,CBAD_HALT
	push	hl		; CONOUT corrupts HL
	call	CONOUT	; one character to the terminal
	pop	hl
	inc	hl	; next character
	jr	CBAD_PRINT
CBAD_HALT:				; (src: CB3)
	di	; interrupts off, so the HALT below is final
	halt			; reset is the only way on

BOOTMSG:
	defb	13,10,'Disk boot failure',13,10,0	; CR LF text CR LF, 00h-terminated
IONAM:
	defb	'IO      SYS'	; directory form of IO.SYS (8+3, space-padded)
DOSNAM:
	defb	'MSDOS   SYS'	; directory form of MSDOS.SYS
BIOSEND:			; F221h: Z86.SYS ends here (8737 bytes); z86.py
				;   cuts the output at this label
; =====================================================================
; The CPMZ80.ASM header, carried into this listing because z86.py
; assembles I86.ASM, BIOS.ASM and CPMZ80.ASM as one text (its code, past
; BIOSEND, is cut from Z86.SYS and goes into CPM.COM).  Only the equates
; below remain: they emit no bytes.  The author's header, kept:
; =====================================================================
; CPMZ80.ASM - the Z80 part of CPM.COM: CP/M 2.2 programs on the FDD3000's
; Z80, under MS-DOS 1.25.
;
; Assembled by z86.py after I86.ASM and BIOS.ASM, with their symbols, at
; ENDBIOS: over the BIOS's COLD, which only the boot needs (the ORG below
; moves the address, not the output). build.py puts it in CPM.COM
; (CPMZ80.INC). BIOS trap 1Ch copies it to ENDBIOS; trap 1Ch with BP = 0 then jumps to T_CPM, with
; CPM.COM's registers:
;   BX = SWLEN: CPM.COM's end, linear; DOS, COMMAND and CPM.COM are below
;   DX = P: the page above the program's memory (TPA = 0100h to P)
;   CX = program bytes, staged at linear SWLEN
;   SI = linear address of FCB1 (16), FCB2 (16), command tail (128)
;   DI = DOSLEN: CPM.COM's PSP + 256, linear
;   AL = current drive
; The 8086's memory is 0000h-CFFFh, DOS at the bottom where a CP/M
; program must run. So 0000h-SWLEN is exchanged with SAVE (P+200h, up
; to the top that DOS gave CPM.COM, below COMMAND), the program moved to
; 0100h, and it runs. Console calls go to the BIOS's console code. For a
; file call the BDOS copies the FCB (and a record being written) to the
; P area, exchanges DOS (0000h-DOSLEN) back in, runs the 8086
; interpreter on INT 21h there (DOSCALL; trap 1Dh returns), and
; exchanges it out again: DOS 1.25's FCB calls are CP/M's, record size
; 128. Sequential reads and writes go through BUF, so one exchange moves
; up to NBUF records. The program ends (warm boot) with DOS exchanged
; back and a return from the trap to CPM.COM.
;
; P area (in the 8086's memory, above the program's):
PBDOS:	equ	06h	; JP BDOSE: (0006h) points here
PSTUB:	equ	09h	; 8086: INT 21h, TRAP 1Dh
PFCB:	equ	10h	; the FCB of a call (37 bytes)
PSRCH:	equ	38h	; the FCB of search first / next
PDTA:	equ	60h	; DOS's DTA (128 bytes)
PBIOS:	equ	100h	; BIOS jump table, (0001h) = P+103h
PSTK:	equ	200h	; 8086 stack (DOS uses about 26 bytes)
PSIZE:	equ	200h
NBUF:	equ	8	; records in BUF
