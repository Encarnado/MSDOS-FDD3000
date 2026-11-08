;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  2/7 (interpreter)
;  Included by asm/z86sys.asm, which holds the volume preface, the ORG and
;  the shared hardware equates.  Not assembled on its own.  Range: D000h-EB45h
;==============================================================================

; =====================================================================
; I86.ASM - the 8086 interpreter (author's header, kept and glossed)
; ---------------------------------------------------------------------
; Assembled by z86.py (tmxcobol's z80asm plus ;@FOR / ;@TABLE expansion).
; cpu86.py is the reference: this must do exactly what it does.
;
; Guest memory: 8086 linear address n is Z80 address n, 0000h-CFFFh (52 KB).
; A segment's base (seg << 4) is kept with it, so an operand's host address
; is base + offset, both 16 bits.
;
; Z80 registers while 8086 code runs:
;   BC   host address of the next 8086 code byte (CS base + IP)
;   IX   NEXT, the dispatcher: every handler ends with JP (IX)
;   AF'  the 8086 arithmetic flags. F' holds S Z AF(H) OF(V) CF(C) in the
;        Z80 positions; A' is the low byte of the last result, PF is its
;        parity. Only flag code does EX AF,AF'.
;   A, DE, HL, IY, SP  scratch (SP is the Z80 stack)
;
; The 8086 registers live in memory (REGS), so a ModR/M operand is always a
; host pointer: into guest memory, or into REGS for a register.
;
; Known differences from an 8086: AF after 16-bit add/subtract/inc/dec is
; the Z80's (carry from bit 11, not bit 3); segment wrap above 64 KB is not
; modelled (the guest has 52 KB).
;   [Correction, notes/z86_part01_findings.md: that holds for the WCORE
;   ADD/ADC/SUB/SBB/CMP slots only.  INC16 / DEC16 end with RRA, which
;   resets H, so 16-bit INC and DEC (40h-4Fh, FF /0 /1) always leave
;   AF = 0.]
; =====================================================================


; =====================================================================
; REGS - the register page (D000h-D0FFh)
; ---------------------------------------------------------------------
; Page-aligned so that any register is H = REGS>>8 plus a byte offset:
; the ModR/M decoders (MRW / MRB / EAW / EAB, part 2) build L from the
; reg or r/m field and never carry into H.  Word registers sit at
; 2 * (8086 register number), so a 16-bit reg field doubled is its
; offset; byte registers go through R8TAB.  Segment registers sit at
; 16 + 2 * sreg and their bases (seg << 4, recomputed on every load)
; 8 bytes higher, so SEGSET reaches a base as 24 + 2 * sreg.
;
;   D000-D00F  AX CX DX BX SP BP SI DI (little-endian, AL at D000h)
;   D010-D017  ES CS SS DS
;   D018-D01F  their bases
;   D020-D023  EADS / EASS: the bases ModR/M actually adds - normally
;              B_DS / B_SS, a segment prefix points both at its segment
;              for one instruction (RESTORE puts them back)
;   D024-D02F  interpreter state (below)
;   D030-D037  R8TAB
;   D038-D03D  shift / divide scratch
;   D03E-D0F0  serial routines and their tables (code in a data page)
;   D0F1-D0FC  padding
;   D0FD-D0FF  BOOTJP
;
; At load time D000h-D02Fh are zero: COLD fills in what START needs.
; =====================================================================
REGS:
R_AX:	equ	REGS+0		; AX (reg 0)
R_AL:	equ	REGS+0
R_AH:	equ	REGS+1
R_CX:	equ	REGS+2		; CX (reg 1)
R_CL:	equ	REGS+2
R_CH:	equ	REGS+3
R_DX:	equ	REGS+4		; DX (reg 2)
R_DL:	equ	REGS+4
R_DH:	equ	REGS+5
R_BX:	equ	REGS+6		; BX (reg 3)
R_BL:	equ	REGS+6
R_BH:	equ	REGS+7
R_SP:	equ	REGS+8		; SP (reg 4)
R_BP:	equ	REGS+10		; BP (reg 5)
R_SI:	equ	REGS+12		; SI (reg 6)
R_DI:	equ	REGS+14		; DI (reg 7)
R_ES:	equ	REGS+16	; segment registers, 2 * sreg + 16
R_CS:	equ	REGS+18
R_SS:	equ	REGS+20
R_DS:	equ	REGS+22
B_ES:	equ	REGS+24	; their bases (seg << 4), 2 * sreg + 24
B_CS:	equ	REGS+26		;   B_CS + IP is where BC points
B_SS:	equ	REGS+28
B_DS:	equ	REGS+30
EADS:	equ	REGS+32	; base for DS-relative operands (override aware)
EASS:	equ	REGS+34	; base for SS-relative operands (override aware)
FLAGHI:	equ	REGS+36	; FLAGS bits 8-10 as bits 0-2: TF IF DF (GETF/SETF)
REPT:	equ	REGS+37	; F2h / F3h: the REP prefix of a string op
STEP1:	equ	REGS+38	; +1 / -1 by DF (SETSTEP keeps it in step with DF)
STEP2:	equ	REGS+40	; +2 / -2 by DF
TMP:	equ	REGS+42		; scratch word (START takes the 8086 IP from it)
TMP2:	equ	REGS+44		; second scratch word (word IMUL)
DIVISOR:	equ	REGS+46	; DIV / IDIV divisor
R8TAB:	equ	REGS+48	; reg8 number -> offset: AL CL DL BL AH CH DH BH
SHCNT:	equ	REGS+56	; shift count (SHR finishers: OF only for count 1)
QNEG:	equ	REGS+57	; bit 7: quotient negative
RNEG:	equ	REGS+58	; bit 7: remainder (dividend) negative
					;   (REGS+59 is unused)
SHORIG:	equ	REGS+60	; operand before a shift (SHR's OF = its old MSB)
	defs	48		; D000-D02F: registers, bases, state - zero at load
; R8TAB: the 8086 numbers byte registers AL CL DL BL AH CH DH BH (0-7);
; each lives at offset 2*(n & 3) + (n >> 2) in the word block.  The
; decoders index it as `OR R8TAB&0FFh` - the table's low byte is 30h, so
; ORing in 0-7 is the same as adding.
	defb	0,2,4,6,1,3,5,7	; AL=0 CL=2 DL=4 BL=6 AH=1 CH=3 DH=5 BH=7
	defs	REGS+62-$	; D038-D03D: SHCNT QNEG RNEG (spare) SHORIG

; =====================================================================
; THE SERIAL ROUTINES - WD2123 channels, in the register page's free end
;   >>> BIOS CODE IN AN INTERPRETER PAGE (BIOS.ASM's, placed here for
;   >>> the page slack - logically part of asm/z86_bios.asm)
; ---------------------------------------------------------------------
; Shared by BIOS.ASM (traps 4/5/6 PRINT AUXIN AUXOUT, INT 14h, INT 17h,
; COLD) and by CPMZ80 (BDOS LIST/PUNCH/READER, the CP/M BIOS vector).
; They live at D03Eh-D0F0h so that they take no room above the BIOS,
; where CPM.COM's Z80 part is copied (F12Ch on).
;
; The FDD3000's WD2123 holds two 8251A-compatible channels with their
; own baud-rate generators (ports in the hardware block).  As in CBIOS
; A1.1, the printer is channel A (CP/M's LIST) and AUX channel B (PUNCH,
; READER).  Throughout, C = the channel's control port; the data port is
; C - 1.
;
; Lineage: CBIOS A1.1's PUN / RDR / LISTST / ERROA / INITRS, generalised
; to either channel by C, given an optional poll limit (HL) for INT 14h
; and INT 17h, and given a full 8251A reset in SSET that CBIOS lacks.
; On real hardware PRN and AUX worked (the 2026-11-07 run,
; notes/hardware_run.md).  Not checked there: the baud rates each code
; really gives (crystal unknown) and how DSR is wired - provisional.
; =====================================================================

; ---------------------------------------------------------------------
; SPRN / SAUXO - send A to channel A (printer) / channel B (AUX)
; Entry: A = byte.  Exit: CF = 0 (they wait for ever).
; Corrupts: A, C, E, HL, F.  RTS is left on (SIOWORD).
; Callers: T_PRINT, T_AUXOUT (JP); CPMZ80 F_LST, F_PUN, B_LIST, B_PUN.
; ---------------------------------------------------------------------
SPRN:
	ld	c,UART_CMD_CHA	; printer: channel A
	jr	SPUT_FOREVER		; join SAUXO's path with C = printer port
SAUXO:
	ld	c,UART_CMD_CHB	; AUX: channel B, falling into the common part
SPUT_FOREVER:				; (src: SPF)
	ld	e,a		; SPUT wants the byte in E
	ld	hl,0		; poll limit 0: wait as long as it takes
; ---------------------------------------------------------------------
; SPUT - send E on the channel at C once DSR and TxRDY are both on
; Entry: C = control port, E = byte, HL = poll limit (0 = for ever).
; Exit:  CF = 0 sent; CF = 1 gave up after HL polls (nothing sent).
; Corrupts: A, HL, F.  C kept.
; Callers: SPRN/SAUXO above; I14PUT (INT 14h AH=1) and T_I17 with
; HL = FFFFh.  Mirrors CBIOS A1.1 PUN (same 27h command, same 81h test).
; ---------------------------------------------------------------------
SPUT:
	ld	a,SIOWORD	; transmitter, receiver, DTR and RTS on - the
	out	(c),a		;   far end may need RTS/DTR to send DSR back
	call	SERR		; drop any stale PE/OE/FE first (once only)
SPUT_POLL:				; (src: SP1)
	in	a,(c)		; status: DSR (7) and TxRDY (0) both needed
	and	IOMASK		;   - DSR is the printer's "on line"
	cp	IOMASK		; Z only if both bits are set
	jr	z,SPUT_SEND	; both on: send (Z, and CF = 0 from the CP)
	call	SWAIT		; count one poll against the limit
	jr	nc,SPUT_POLL	; limit not reached (or none): poll again
	ret			; CF = 1: timed out
SPUT_SEND:				; (src: SP2)
	dec	c		; control port - 1 = data port
	out	(c),e		; the byte goes
	inc	c		; C back to the control port for the caller
	ret			; CF = 0 still (DEC/INC leave carry alone)

; ---------------------------------------------------------------------
; SAUXI - read a byte from channel B (AUX), waiting for ever
; Exit: A = byte, CF = 0.  Corrupts: C, E, HL, F.
; Callers: T_AUXIN; CPMZ80 F_RDR, B_RDR.
; ---------------------------------------------------------------------
SAUXI:
	ld	c,UART_CMD_CHB	; AUX: channel B
	ld	hl,0		; no poll limit
; ---------------------------------------------------------------------
; SGET - read a byte from the channel at C
; Entry: C = control port, HL = poll limit (0 = for ever).
; Exit:  CF = 0: A = byte (Z set if it is 00h), RTS dropped again;
;        CF = 1: timed out, A = 0, and RTS is LEFT ON (SIOWORD).
; Corrupts: A, E, HL, F.  C kept.
; RTS is raised only while waiting, as CBIOS A1.1's RDR does - but see
; the timeout case above, and SPUT, which also leaves RTS on.
; Callers: SAUXI above; I14GET (INT 14h AH=2) with HL = FFFFh.
; ---------------------------------------------------------------------
SGET:
	ld	a,SIOWORD	; RTS on: "you may send" (CBIOS: "forca CTS low")
	out	(c),a		; (SGET's own wait has its own poll limit)
SGET_POLL:				; (src: SG1)
	call	SERR		; clear PE/OE/FE on every poll, as RDRERR does,
	in	a,(c)		;   so an error never wedges RxRDY
	bit	RXRDY,a		; a character waiting?
	jr	nz,SGET_TAKE		; yes: go and take it
	call	SWAIT		; count the poll
	jr	nc,SGET_POLL	; keep waiting
	ret			; CF = 1: timed out (RTS still on)
SGET_TAKE:				; (src: SG2)
	dec	c		; data port
	in	e,(c)		; the character
	inc	c		; back to the control port
	ld	a,ACOM		; RTS off again: hold the sender until the
	out	(c),a		;   next read (CBIOS: "forca CTS a high")
	ld	a,e		; A = character
	or	a		; CF = 0 (success); Z if it was 00h
	ret		; CF = 0, Z = byte was 00h

; ---------------------------------------------------------------------
; SLSTS - printer status: A = FFh if channel A's DSR is on, else 00h
; Exit: A, CF = DSR.  Corrupts: C, F.
; Callers: CPMZ80 B_LSTS (CP/M LISTST).  Mirrors CBIOS A1.1 LISTST.
; ---------------------------------------------------------------------
SLSTS:
	ld	c,UART_CMD_CHA	; channel A
	call	SERR		; clear errors first, as CBIOS (ERROA)
	in	a,(c)		; DSR is status bit 7 ...
	rla			; ... into carry
	sbc	a,a		; FFh if on, 00h if off
	ret		; A = DSR as a flag byte, CF = DSR

; ---------------------------------------------------------------------
; SWAIT - charge one poll to the limit in HL
; Entry: HL = polls left (0 = no limit).
; Exit:  CF = 1 when HL has just reached 0, else CF = 0; HL = 0 never
;        times out (it is never decremented).  A corrupted (A = 0 on
;        timeout).  HL = n allows exactly n polls.
; Callers: SPUT, SGET.
; ---------------------------------------------------------------------
SWAIT:
	ld	a,h		; unlimited?
	or	l		;   (OR also clears carry)
	ret	z		; yes: CF = 0, keep polling for ever
	dec	hl		; one poll spent
	ld	a,h		; limit 0 means unlimited
	or	l		; CF = 0 again
	ret	nz		; some left
	scf			; just ran out: CF = 1
	ret		; CF = 1: the caller gives up

; ---------------------------------------------------------------------
; SERR - clear the channel's error flags, if any are set
; Entry: C = control port.  Corrupts: A, F.
; Issues IOERR (37h: ER plus the running SIOWORD bits) only when one
; of status bits 3-6 is on.  ER resets PE, OE and FE; BRKDET (bit 6)
; follows the line and stays up while a break lasts, so during a break
; SERR fires on every call (harmless).  Side effect: IOERR has RTS set,
; so SERR also raises RTS (e.g. from SLSTS after an SGET dropped it).
; Callers: SPUT, SGET (every poll), SLSTS.  CBIOS A1.1 ERROA / ERROB.
; ---------------------------------------------------------------------
SERR:
	in	a,(c)		; status
	and	SIOERRS		; parity, overrun, framing, break?
	ret	z		; none: leave the command register alone
	ld	a,IOERR		; error reset, with TxEN DTR RxE RTS on
	out	(c),a		; (ER bit self-clears; TxEN DTR RxE RTS stay on)
	ret		; nothing returned: callers re-read status

; ---------------------------------------------------------------------
; SSET - set a channel up from scratch
; Entry: C = control port; D = 8251A mode byte; E = WD2123 baud code
;        0-15: 50 75 110 134.5 150 200 300 600 1200 1800 2400 3600 4800
;        7200 9600 19200 (the order TMX CONFIGUR lists them; provisional:
;        the real rates depend on the WD2123's clock, never checked).
; Exit:  channel reset, mode D, command ACOM (TxEN DTR RxE, RTS off),
;        baud register loaded.  Corrupts: A, F.  BC, DE, HL kept.
; Callers: COLD (both channels, D = 8Eh = 1.5 stop, no parity, 8 bits,
;        x16 - CBIOS SIOTAB's 02h+0Ch+00h+00h+80h; E = 8, 1200 baud);
;        I14SET (INT 14h AH = 0 / 4).
;
; Mode byte (async): bits 1-0 clock factor (01 x1, 10 x16, 11 x64),
; 3-2 data bits (00 5 .. 11 8), 4 PEN, 5 EP (1 even), 7-6 stop bits
; (01 1, 10 1.5, 11 2).
; The 00h 00h 00h 40h prologue is the 8251A's reset from any state: if
; the chip is half-way through a mode/sync-character sequence, three
; zeros satisfy it whatever it was expecting, and 40h (IR) then returns
; it to "next byte is a mode byte".  CBIOS A1.1 INITRS skips this and
; assumes a chip fresh from power-up.
; ---------------------------------------------------------------------
SSET:
	xor	a		; three dummy bytes: complete any pending
	out	(c),a		;   mode / sync-character sequence
	out	(c),a		; dummy 1
	out	(c),a		; dummy 2
	ld	a,SIORESET	; internal reset: next write is a mode byte
	out	(c),a		; dummy 3: whatever it wanted, it has it
	out	(c),d		; the mode
	ld	a,ACOM		; command: transmitter, receiver, DTR on
	out	(c),a		; (IR does not touch the baud register)
	ld	a,c		; which baud register? Bit 7 of the control
	rla			;   port: 81h (A) -> CF = 1, 41h (B) -> CF = 0
	ld	a,UART_BAUD_CHB	; 11h - CF: 10h for channel A, 11h for B
	sbc	a,0		; 10h for channel A, 11h for B
	push	bc		; borrow C for the port, keep the caller's
	ld	c,a		; C = baud register for the OUT
	out	(c),e		; baud code to the channel's own generator
	pop	bc		; C = the control port again
	ret		; A corrupted; channel ready

; ---------------------------------------------------------------------
; SSTAT - INT 14h status of the channel at C, in the PC's format
; Entry: C = control port.
; Exit:  R_AH = line status, R_AL = modem status.
;        AH: 0 data ready, 1 overrun, 2 parity, 3 framing, 4 break,
;            5 holding register empty (TxRDY), 6 transmitter empty
;            (TxEMPTY), 7 = 0 (timeout is OR-ed in by I14T).
;        AL: 5 DSR; 4 CTS, always reported on - the 8251A gates its
;            transmitter on CTS itself and does not show it in status.
; Corrupts: A, B (0), DE, HL, F.  C kept.
; Callers: T_I14 (AH = 3, JP), I14T (after AH = 1 / 2), I14SET (JP,
; after AH = 0 / 4).
; ---------------------------------------------------------------------
SSTAT:
	in	a,(c)		; the 8251A status byte
	ld	d,a		; kept in D for both halves
	ld	hl,LSMAP	; one mask per AH bit, bit 6 first
	ld	b,7		; seven AH bits (bit 7 is the timeout)
SSTAT_MAP:				; (src: SS1)
	ld	a,d		; status again for each mask
	and	(hl)		; is the 8251A bit for this AH bit on?
	add	a,0FFh		; CF = 1 iff it was (any non-zero + FFh carries)
	rl	e		; shift it into E; after 7 rounds the first
	inc	hl		;   mask's bit is bit 6
	djnz	SSTAT_MAP		; next AH bit
	ld	a,e		; bit 7 still holds a stale bit of E: clear it
	and	7Fh		;   (no timeout here)
	ld	(R_AH),a		; AH = line status
	ld	a,d		; DSR (status bit 7) ...
	and	80h		; DSR alone
	rrca			; ... to bit 5, the PC's MSR DSR position
	rrca		; 80h -> 40h -> 20h
	or	10h		; CTS (bit 4) always on
	ld	(R_AL),a		; AL = modem status
	ret		; (B = 0, D = raw status, E = AH)

; LSMAP - the 8251A status mask for each PC line-status bit, AH bit 6
; first (SSTAT shifts them in from the right).
LSMAP:
	defb	04h,01h,40h,20h,08h,10h,02h	; AH6 TxEMPTY, AH5 TxRDY, AH4 BRKDET,
					;   AH3 FE, AH2 PE, AH1 OE, AH0 RxRDY
; BAUDT - INT 14h baud index (0-7 from AH=0's AL bits 7-5, 0-8 from
; AH=4's CL) -> WD2123 baud code (see SSET).
BAUDT:
	defb	2,4,6,7,8,10,12,14,15	; 110 150 300 600 1200 2400 4800 9600 19200
	defs	REGS+253-$	; D0F1-D0FC: free (zero)

; =====================================================================
; BOOTJP - the boot sector's entry into Z86.SYS
; ---------------------------------------------------------------------
; BOOT.BIN loads the file to D000h and jumps to D0FDh (its ENTRY), the
; last three bytes of the register page.  Fixed address: the boot
; sector hard-codes it, so the page above must never grow past D0FCh.
; =====================================================================
BOOTJP:
	jp	COLD	; D0FDh: to the cold-boot loader (part 8, F12Ch)

; =====================================================================
; OPLO / OPHI - the 8086 opcode dispatch table, split by byte
; ---------------------------------------------------------------------
; 256 handler addresses, low bytes at D100h + opcode, high bytes at
; D200h + opcode.  NEXT (part 2) fetches the opcode into L, sets
; H = OPLO>>8, reads the low byte, INC H, reads the high byte and jumps:
; a split table costs no doubling of the index and no carry handling.
; Handlers are entered with A = opcode and BC past it, so one handler
; can serve a family (O_ALU0-5, O_XCHGA, O_ESC) by decoding A.
;
; Each line covers 8 opcodes.  Where the table maps several opcodes to
; one handler, the 8086 behaves the same way (undocumented aliases
; 60h-6Fh, 82h, C0h/C1h, C8h/C9h, D6h SALC), as cpu86.py does.
; =====================================================================
OPLO:
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_PUSH_ES&0FFh, O_POP_ES&0FFh	; 00-07 ADD Eb,Gb Ev,Gv Gb,Eb Gv,Ev AL,Ib AX,Iv; 06 PUSH ES; 07 POP ES
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_PUSH_CS&0FFh, O_TRAP&0FFh	; 08-0F OR (same six forms); 0E PUSH CS; 0F BIOS trap (POP CS on an 8086)
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_PUSH_SS&0FFh, O_POP_SS&0FFh	; 10-17 ADC (six forms); 16 PUSH SS; 17 POP SS
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_PUSH_DS&0FFh, O_POP_DS&0FFh	; 18-1F SBB (six forms); 1E PUSH DS; 1F POP DS
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_SEG_ES&0FFh, O_DAA&0FFh	; 20-27 AND (six forms); 26 ES: prefix; 27 DAA
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_SEG_CS&0FFh, O_DAS&0FFh	; 28-2F SUB (six forms); 2E CS: prefix; 2F DAS
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_ALU4&0FFh, O_ALU5&0FFh, O_SEG_SS&0FFh, O_AAA&0FFh	; 30-37 XOR (six forms); 36 SS: prefix; 37 AAA
	defb	O_ALU0&0FFh, O_ALU1&0FFh, O_ALU2&0FFh, O_ALU3&0FFh, O_CMPAL&0FFh, O_ALU5&0FFh, O_SEG_DS&0FFh, O_AAS&0FFh	; 38-3F CMP (3C CMP AL,Ib has its own fast path); 3E DS:; 3F AAS
	defb	O_INC_AX&0FFh, O_INC_CX&0FFh, O_INC_DX&0FFh, O_INC_BX&0FFh, O_INC_SP&0FFh, O_INC_BP&0FFh, O_INC_SI&0FFh, O_INC_DI&0FFh	; 40-47 INC AX CX DX BX SP BP SI DI
	defb	O_DEC_AX&0FFh, O_DEC_CX&0FFh, O_DEC_DX&0FFh, O_DEC_BX&0FFh, O_DEC_SP&0FFh, O_DEC_BP&0FFh, O_DEC_SI&0FFh, O_DEC_DI&0FFh	; 48-4F DEC AX CX DX BX SP BP SI DI
	defb	O_PUSH_AX&0FFh, O_PUSH_CX&0FFh, O_PUSH_DX&0FFh, O_PUSH_BX&0FFh, O_PUSH_SP&0FFh, O_PUSH_BP&0FFh, O_PUSH_SI&0FFh, O_PUSH_DI&0FFh	; 50-57 PUSH AX CX DX BX SP BP SI DI
	defb	O_POP_AX&0FFh, O_POP_CX&0FFh, O_POP_DX&0FFh, O_POP_BX&0FFh, O_POP_SP&0FFh, O_POP_BP&0FFh, O_POP_SI&0FFh, O_POP_DI&0FFh	; 58-5F POP AX CX DX BX SP BP SI DI
	defb	O_JO&0FFh, O_JNO&0FFh, O_JB&0FFh, O_JNB&0FFh, O_JZ&0FFh, O_JNZ&0FFh, O_JBE&0FFh, O_JA&0FFh	; 60-67 8086 aliases of 70-77 (JO JNO JB JNB JZ JNZ JBE JA)
	defb	O_JS&0FFh, O_JNS&0FFh, O_JP&0FFh, O_JNP&0FFh, O_JL&0FFh, O_JGE&0FFh, O_JLE&0FFh, O_JG&0FFh	; 68-6F 8086 aliases of 78-7F (JS JNS JP JNP JL JGE JLE JG)
	defb	O_JO&0FFh, O_JNO&0FFh, O_JB&0FFh, O_JNB&0FFh, O_JZ&0FFh, O_JNZ&0FFh, O_JBE&0FFh, O_JA&0FFh	; 70-77 JO JNO JB/JC JNB/JNC JZ JNZ JBE JA (short)
	defb	O_JS&0FFh, O_JNS&0FFh, O_JP&0FFh, O_JNP&0FFh, O_JL&0FFh, O_JGE&0FFh, O_JLE&0FFh, O_JG&0FFh	; 78-7F JS JNS JP JNP JL JGE JLE JG (short)
	defb	O_GRP80&0FFh, O_GRP81&0FFh, O_GRP80&0FFh, O_GRP83&0FFh, O_TEST84&0FFh, O_TEST85&0FFh, O_XCHG86&0FFh, O_XCHG87&0FFh	; 80 grp1 Eb,Ib; 81 grp1 Ev,Iv; 82 = 80; 83 grp1 Ev,Ib(sx); 84/85 TEST; 86/87 XCHG
	defb	O_MOV88&0FFh, O_MOV89&0FFh, O_MOV8A&0FFh, O_MOV8B&0FFh, O_MOV8C&0FFh, O_LEA&0FFh, O_MOV8E&0FFh, O_POP8F&0FFh	; 88-8B MOV Eb,Gb Ev,Gv Gb,Eb Gv,Ev; 8C MOV Ew,Sw; 8D LEA; 8E MOV Sw,Ew; 8F POP Ev
	defb	O_NOP&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh, O_XCHGA&0FFh	; 90 NOP (XCHG AX,AX); 91-97 XCHG AX,CX..DI
	defb	O_CBW&0FFh, O_CWD&0FFh, O_CALLF&0FFh, O_NOP&0FFh, O_PUSHF&0FFh, O_POPF&0FFh, O_SAHF&0FFh, O_LAHF&0FFh	; 98 CBW; 99 CWD; 9A CALL far; 9B WAIT (no 8087: NOP); 9C PUSHF; 9D POPF; 9E SAHF; 9F LAHF
	defb	O_MOVA0&0FFh, O_MOVA1&0FFh, O_MOVA2&0FFh, O_MOVA3&0FFh, O_MOVSB&0FFh, O_MOVSW&0FFh, O_CMPSB&0FFh, O_CMPSW&0FFh	; A0-A3 MOV AL/AX,[m] / [m],AL/AX; A4/A5 MOVSB/W; A6/A7 CMPSB/W
	defb	O_TESTA8&0FFh, O_TESTA9&0FFh, O_STOSB&0FFh, O_STOSW&0FFh, O_LODSB&0FFh, O_LODSW&0FFh, O_SCASB&0FFh, O_SCASW&0FFh	; A8/A9 TEST AL,Ib / AX,Iv; AA/AB STOSB/W; AC/AD LODSB/W; AE/AF SCASB/W
	defb	O_MOVI_AL&0FFh, O_MOVI_CL&0FFh, O_MOVI_DL&0FFh, O_MOVI_BL&0FFh, O_MOVI_AH&0FFh, O_MOVI_CH&0FFh, O_MOVI_DH&0FFh, O_MOVI_BH&0FFh	; B0-B7 MOV AL CL DL BL AH CH DH BH,Ib
	defb	O_MOVI_AX&0FFh, O_MOVI_CX&0FFh, O_MOVI_DX&0FFh, O_MOVI_BX&0FFh, O_MOVI_SP&0FFh, O_MOVI_BP&0FFh, O_MOVI_SI&0FFh, O_MOVI_DI&0FFh	; B8-BF MOV AX CX DX BX SP BP SI DI,Iv
	defb	O_RETN&0FFh, O_RET&0FFh, O_RETN&0FFh, O_RET&0FFh, O_LES&0FFh, O_LDS&0FFh, O_MOVC6&0FFh, O_MOVC7&0FFh	; C0/C2 RET Iw, C1/C3 RET (C0/C1: 8086 aliases); C4 LES; C5 LDS; C6/C7 MOV E,I
	defb	O_RETFN&0FFh, O_RETF&0FFh, O_RETFN&0FFh, O_RETF&0FFh, O_INT3&0FFh, O_INTN&0FFh, O_INTO&0FFh, O_IRET&0FFh	; C8/CA RETF Iw, C9/CB RETF (C8/C9: aliases); CC INT 3; CD INT Ib; CE INTO; CF IRET
	defb	O_SHD0&0FFh, O_SHD1&0FFh, O_SHD2&0FFh, O_SHD3&0FFh, O_AAM&0FFh, O_AAD&0FFh, O_SALC&0FFh, O_XLAT&0FFh	; D0-D3 grp2 shift/rotate Eb,1 Ev,1 Eb,CL Ev,CL; D4 AAM; D5 AAD; D6 SALC; D7 XLAT
	defb	O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh, O_ESC&0FFh	; D8-DF ESC (8087 escape: ModR/M and displacement skipped)
	defb	O_LOOPNZ&0FFh, O_LOOPZ&0FFh, O_LOOP&0FFh, O_JCXZ&0FFh, O_INB&0FFh, O_INW&0FFh, O_OUTI&0FFh, O_OUTI&0FFh	; E0 LOOPNZ; E1 LOOPZ; E2 LOOP; E3 JCXZ; E4/E5 IN AL/AX,Ib (FFh); E6/E7 OUT Ib (ignored)
	defb	O_CALLN&0FFh, O_JMPN&0FFh, O_JMPF&0FFh, O_JREL8&0FFh, O_INDXB&0FFh, O_INDXW&0FFh, O_NOP&0FFh, O_NOP&0FFh	; E8 CALL near; E9 JMP near; EA JMP far; EB JMP short; EC/ED IN AL/AX,DX (FFh); EE/EF OUT DX (NOP)
	defb	O_LOCK&0FFh, O_BAD&0FFh, O_REP&0FFh, O_REP&0FFh, O_HLT&0FFh, O_CMC&0FFh, O_GRP3B&0FFh, O_GRP3W&0FFh	; F0 LOCK (ignored); F1 undefined (an 8086 takes it as LOCK); F2/F3 REPNE/REP; F4 HLT; F5 CMC; F6/F7 grp3
	defb	O_CLC&0FFh, O_STC&0FFh, O_CLI&0FFh, O_STI&0FFh, O_CLD&0FFh, O_STD&0FFh, O_GRP4&0FFh, O_GRP5&0FFh	; F8 CLC; F9 STC; FA CLI; FB STI; FC CLD; FD STD; FE grp4 Eb (INC/DEC); FF grp5 Ev
OPHI:
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_PUSH_ES>>8, O_POP_ES>>8	; 00-07 (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_PUSH_CS>>8, O_TRAP>>8	; 08-0F (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_PUSH_SS>>8, O_POP_SS>>8	; 10-17 (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_PUSH_DS>>8, O_POP_DS>>8	; 18-1F (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_SEG_ES>>8, O_DAA>>8	; 20-27 (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_SEG_CS>>8, O_DAS>>8	; 28-2F (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_ALU4>>8, O_ALU5>>8, O_SEG_SS>>8, O_AAA>>8	; 30-37 (high bytes, as OPLO)
	defb	O_ALU0>>8, O_ALU1>>8, O_ALU2>>8, O_ALU3>>8, O_CMPAL>>8, O_ALU5>>8, O_SEG_DS>>8, O_AAS>>8	; 38-3F (high bytes, as OPLO)
	defb	O_INC_AX>>8, O_INC_CX>>8, O_INC_DX>>8, O_INC_BX>>8, O_INC_SP>>8, O_INC_BP>>8, O_INC_SI>>8, O_INC_DI>>8	; 40-47 (high bytes, as OPLO)
	defb	O_DEC_AX>>8, O_DEC_CX>>8, O_DEC_DX>>8, O_DEC_BX>>8, O_DEC_SP>>8, O_DEC_BP>>8, O_DEC_SI>>8, O_DEC_DI>>8	; 48-4F (high bytes, as OPLO)
	defb	O_PUSH_AX>>8, O_PUSH_CX>>8, O_PUSH_DX>>8, O_PUSH_BX>>8, O_PUSH_SP>>8, O_PUSH_BP>>8, O_PUSH_SI>>8, O_PUSH_DI>>8	; 50-57 (high bytes, as OPLO)
	defb	O_POP_AX>>8, O_POP_CX>>8, O_POP_DX>>8, O_POP_BX>>8, O_POP_SP>>8, O_POP_BP>>8, O_POP_SI>>8, O_POP_DI>>8	; 58-5F (high bytes, as OPLO)
	defb	O_JO>>8, O_JNO>>8, O_JB>>8, O_JNB>>8, O_JZ>>8, O_JNZ>>8, O_JBE>>8, O_JA>>8	; 60-67 (high bytes, as OPLO)
	defb	O_JS>>8, O_JNS>>8, O_JP>>8, O_JNP>>8, O_JL>>8, O_JGE>>8, O_JLE>>8, O_JG>>8	; 68-6F (high bytes, as OPLO)
	defb	O_JO>>8, O_JNO>>8, O_JB>>8, O_JNB>>8, O_JZ>>8, O_JNZ>>8, O_JBE>>8, O_JA>>8	; 70-77 (high bytes, as OPLO)
	defb	O_JS>>8, O_JNS>>8, O_JP>>8, O_JNP>>8, O_JL>>8, O_JGE>>8, O_JLE>>8, O_JG>>8	; 78-7F (high bytes, as OPLO)
	defb	O_GRP80>>8, O_GRP81>>8, O_GRP80>>8, O_GRP83>>8, O_TEST84>>8, O_TEST85>>8, O_XCHG86>>8, O_XCHG87>>8	; 80 (high bytes, as OPLO)
	defb	O_MOV88>>8, O_MOV89>>8, O_MOV8A>>8, O_MOV8B>>8, O_MOV8C>>8, O_LEA>>8, O_MOV8E>>8, O_POP8F>>8	; 88-8B (high bytes, as OPLO)
	defb	O_NOP>>8, O_XCHGA>>8, O_XCHGA>>8, O_XCHGA>>8, O_XCHGA>>8, O_XCHGA>>8, O_XCHGA>>8, O_XCHGA>>8	; 90 (high bytes, as OPLO)
	defb	O_CBW>>8, O_CWD>>8, O_CALLF>>8, O_NOP>>8, O_PUSHF>>8, O_POPF>>8, O_SAHF>>8, O_LAHF>>8	; 98 (high bytes, as OPLO)
	defb	O_MOVA0>>8, O_MOVA1>>8, O_MOVA2>>8, O_MOVA3>>8, O_MOVSB>>8, O_MOVSW>>8, O_CMPSB>>8, O_CMPSW>>8	; A0-A3 (high bytes, as OPLO)
	defb	O_TESTA8>>8, O_TESTA9>>8, O_STOSB>>8, O_STOSW>>8, O_LODSB>>8, O_LODSW>>8, O_SCASB>>8, O_SCASW>>8	; A8/A9 (high bytes, as OPLO)
	defb	O_MOVI_AL>>8, O_MOVI_CL>>8, O_MOVI_DL>>8, O_MOVI_BL>>8, O_MOVI_AH>>8, O_MOVI_CH>>8, O_MOVI_DH>>8, O_MOVI_BH>>8	; B0-B7 (high bytes, as OPLO)
	defb	O_MOVI_AX>>8, O_MOVI_CX>>8, O_MOVI_DX>>8, O_MOVI_BX>>8, O_MOVI_SP>>8, O_MOVI_BP>>8, O_MOVI_SI>>8, O_MOVI_DI>>8	; B8-BF (high bytes, as OPLO)
	defb	O_RETN>>8, O_RET>>8, O_RETN>>8, O_RET>>8, O_LES>>8, O_LDS>>8, O_MOVC6>>8, O_MOVC7>>8	; C0/C2 (high bytes, as OPLO)
	defb	O_RETFN>>8, O_RETF>>8, O_RETFN>>8, O_RETF>>8, O_INT3>>8, O_INTN>>8, O_INTO>>8, O_IRET>>8	; C8/CA (high bytes, as OPLO)
	defb	O_SHD0>>8, O_SHD1>>8, O_SHD2>>8, O_SHD3>>8, O_AAM>>8, O_AAD>>8, O_SALC>>8, O_XLAT>>8	; D0-D3 (high bytes, as OPLO)
	defb	O_ESC>>8, O_ESC>>8, O_ESC>>8, O_ESC>>8, O_ESC>>8, O_ESC>>8, O_ESC>>8, O_ESC>>8	; D8-DF (high bytes, as OPLO)
	defb	O_LOOPNZ>>8, O_LOOPZ>>8, O_LOOP>>8, O_JCXZ>>8, O_INB>>8, O_INW>>8, O_OUTI>>8, O_OUTI>>8	; E0 (high bytes, as OPLO)
	defb	O_CALLN>>8, O_JMPN>>8, O_JMPF>>8, O_JREL8>>8, O_INDXB>>8, O_INDXW>>8, O_NOP>>8, O_NOP>>8	; E8 (high bytes, as OPLO)
	defb	O_LOCK>>8, O_BAD>>8, O_REP>>8, O_REP>>8, O_HLT>>8, O_CMC>>8, O_GRP3B>>8, O_GRP3W>>8	; F0 (high bytes, as OPLO)
	defb	O_CLC>>8, O_STC>>8, O_CLI>>8, O_STI>>8, O_CLD>>8, O_STD>>8, O_GRP4>>8, O_GRP5>>8	; F8 (high bytes, as OPLO)

; =====================================================================
; EALO / EAHI - memory-operand address routines, split by byte
; ---------------------------------------------------------------------
; Indexed by the whole ModR/M byte, 00h-BFh (mod = 00, 01, 10); EAMEM
; (part 2) does L = ModR/M, H = EALO>>8, low byte, INC H, high byte,
; JP (HL).  The reg field (bits 5-3) does not matter here, so each row
; of 8 repeats for the 8 reg values: rows 00h-3Fh are EA00-EA07,
; 40h-7Fh EA10-EA17, 80h-BFh EA20-EA27 (EA<mod><rm>).
;   rm  0 [BX+SI]  1 [BX+DI]  2 [BP+SI]  3 [BP+DI]
;       4 [SI]     5 [DI]     6 [BP] (mod 00: disp16 alone)  7 [BX]
;   mod 01 adds a sign-extended disp8, mod 10 a disp16.
; BP-based forms add EASS, the rest EADS.  Each routine returns
; HL = host address = segment base + effective address (16-bit sum).
; C0h-FFh (mod 11, a register) never reach this table - every decoder
; tests CP 0C0h first and indexes REGS instead - so the rest of each
; page is free: since 2026-11-08 it holds BIOS floppy code (XFER in
; EALO's end, FHOME and FDTOUT in EAHI's), zero fill after it.  O_LEA reuses the table for the bare offset: it
; zeroes EADS / EASS around its CALL EAMEM, then restores them.
; =====================================================================
EALO:
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 00-07  EA00-EA07, reg 0  [mod 00, no displacement (rm 6: disp16 alone)]
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 08-0F  EA00-EA07, reg 1
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 10-17  EA00-EA07, reg 2
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 18-1F  EA00-EA07, reg 3
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 20-27  EA00-EA07, reg 4
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 28-2F  EA00-EA07, reg 5
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 30-37  EA00-EA07, reg 6
	defb	EA00&0FFh, EA01&0FFh, EA02&0FFh, EA03&0FFh, EA04&0FFh, EA05&0FFh, EA06&0FFh, EA07&0FFh	; 38-3F  EA00-EA07, reg 7
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 40-47  EA10-EA17, reg 0  [mod 01, + disp8 (sign-extended)]
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 48-4F  EA10-EA17, reg 1
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 50-57  EA10-EA17, reg 2
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 58-5F  EA10-EA17, reg 3
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 60-67  EA10-EA17, reg 4
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 68-6F  EA10-EA17, reg 5
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 70-77  EA10-EA17, reg 6
	defb	EA10&0FFh, EA11&0FFh, EA12&0FFh, EA13&0FFh, EA14&0FFh, EA15&0FFh, EA16&0FFh, EA17&0FFh	; 78-7F  EA10-EA17, reg 7
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; 80-87  EA20-EA27, reg 0  [mod 10, + disp16]
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; 88-8F  EA20-EA27, reg 1
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; 90-97  EA20-EA27, reg 2
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; 98-9F  EA20-EA27, reg 3
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; A0-A7  EA20-EA27, reg 4
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; A8-AF  EA20-EA27, reg 5
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; B0-B7  EA20-EA27, reg 6
	defb	EA20&0FFh, EA21&0FFh, EA22&0FFh, EA23&0FFh, EA24&0FFh, EA25&0FFh, EA26&0FFh, EA27&0FFh	; B8-BF  EA20-EA27, reg 7
; ---------------------------------------------------------------------
; XFER - one sector through the WD177x  (C0h-FFh of this page: BIOS code)
;   >>> BIOS CODE IN AN INTERPRETER PAGE: the free end of EALO, placed by
;   >>> z86.py's ;@SLACK block in BIOS.ASM (added 2026-11-08)
; ---------------------------------------------------------------------
; Entry:  A = command (RDSCMD 80h read / WRSCMD A0h write), HL = buffer,
;         XFI's second byte patched by SECTIO: A2h INI (read) / A3h OUTI
;         (write); HOOK38 active (0038h -> FDCINT).
; Exit:   through FDCINT when INTRQ ends the command: A = status AND 5Ch
;         (Z = sector done); or through FDTOUT, A = 20h (NZ), if no first
;         byte came in ~3.1 s (no disk / no drive: the WD1770 sees no
;         index pulses, and its sector search would never end).
; Corrupts: A, B, C, DE, HL, F.
;
; The byte loop XF1/XFI is CBIOS A1.1's (F8ECh read, F934h write) and
; the old RDSEC / WRSEC, unchanged: the timing that ran on a real
; FDD3000.  Only the wait for the FIRST byte is timed, 4 x 65536 turns
; of XFW at 48 T (~3.1 s at 4 MHz); once data flows the sector ends on
; its own.  The wait cannot be a subroutine: FDCINT discards exactly one
; return address (the interrupted loop's) and returns to XFER's caller.
; =====================================================================
XFER:
	ld	c,FDCDAT	; INI / OUTI work through the data register
	im	1		; INTRQ ends the command through 0038h
	ei
	out	(FDCMD),a	; start the read or write
	ld	b,4		; first-byte timeout: 4 x 65536 polls
	ld	de,0
XFER_WAIT:				; (src: XFW)
	in	a,(COM)		; DRQ (bit 7) -> carry: first byte ready?
	rla
	jr	c,XFI		; yes: straight into the transfer
	dec	de		; no: count down
	ld	a,d
	or	e
	jr	nz,XFER_WAIT
	djnz	XFER_WAIT
	jp	FDTOUT		; ~3.1 s and nothing: stop the FDC, "not ready"
XFER_LOOP:				; (src: XF1) CBIOS's byte loop
	in	a,(COM)		; wait for DRQ - INTRQ at the end leaves via FDCINT
	rla
	jr	nc,XFER_LOOP
XFI:
	ini			; PATCHED by SECTIO: ED A2 INI / ED A3 OUTI
	jr	XFER_LOOP
EALOEND:
	defs	EALO+256-$	; the rest of the page: zero fill
EAHI:
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 00-07  EA00-EA07, reg 0  [mod 00, no displacement (rm 6: disp16 alone)]
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 08-0F  EA00-EA07, reg 1
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 10-17  EA00-EA07, reg 2
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 18-1F  EA00-EA07, reg 3
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 20-27  EA00-EA07, reg 4
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 28-2F  EA00-EA07, reg 5
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 30-37  EA00-EA07, reg 6
	defb	EA00>>8, EA01>>8, EA02>>8, EA03>>8, EA04>>8, EA05>>8, EA06>>8, EA07>>8	; 38-3F  EA00-EA07, reg 7
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 40-47  EA10-EA17, reg 0  [mod 01, + disp8 (sign-extended)]
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 48-4F  EA10-EA17, reg 1
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 50-57  EA10-EA17, reg 2
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 58-5F  EA10-EA17, reg 3
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 60-67  EA10-EA17, reg 4
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 68-6F  EA10-EA17, reg 5
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 70-77  EA10-EA17, reg 6
	defb	EA10>>8, EA11>>8, EA12>>8, EA13>>8, EA14>>8, EA15>>8, EA16>>8, EA17>>8	; 78-7F  EA10-EA17, reg 7
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; 80-87  EA20-EA27, reg 0  [mod 10, + disp16]
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; 88-8F  EA20-EA27, reg 1
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; 90-97  EA20-EA27, reg 2
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; 98-9F  EA20-EA27, reg 3
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; A0-A7  EA20-EA27, reg 4
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; A8-AF  EA20-EA27, reg 5
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; B0-B7  EA20-EA27, reg 6
	defb	EA20>>8, EA21>>8, EA22>>8, EA23>>8, EA24>>8, EA25>>8, EA26>>8, EA27>>8	; B8-BF  EA20-EA27, reg 7
; ---------------------------------------------------------------------
; FHOME / FDTOUT  (C0h-FFh of this page: BIOS code)
;   >>> BIOS CODE IN AN INTERPRETER PAGE: the free end of EAHI (;@SLACK)
; ---------------------------------------------------------------------
; FHOME - restore the selected drive to track 0, polled (CBIOS F7B5h).
; Entry:  RESCMD = the restore command (05h: with verify; T_FMT sets 01h).
; Exit:   Z, A = 0: at track 0.  NZ, A = 10h: seek error (no track 0
;         seen).  NZ, A = 20h: timed out (~3.1 s: no index pulses, so the
;         spin-up or the verify never ends) - FDTOUT.
; Keeps BC; corrupts A, DE, F.  Callers: SELECT (a drive not used
; yet), SEEK (after a failed seek), SECTIO (re-seek half-way through
; the retries).  Before 2026-11-08 it sat in the BIOS and waited for
; ever (z86 part 08 findings).
FHOME:
	ld	a,(RESCMD)	; restore, verify unless FORMAT asked otherwise
	out	(FDCMD),a
	push	bc		; SEEK keeps its counters in B
	ld	b,12h		; ~57 us: let the FDC raise BUSY before polling
FHOME_SETTLE:				; (src: FH0)
	djnz	FHOME_SETTLE
	ld	b,4		; timeout: 4 x 65536 polls of 48 T, ~3.1 s
	ld	de,0
FHOME_WAIT:				; (src: FH1)
	in	a,(FDCSTS)	; BUSY (bit 0) -> carry
	rra
	jr	nc,FHOME_DONE	; finished
	dec	de
	ld	a,d
	or	e
	jr	nz,FHOME_WAIT
	djnz	FHOME_WAIT
	pop	bc		; timed out: balance the stack, then
	jp	FDTOUT		;   leave as "not ready" (A = 20h)
FHOME_DONE:				; (src: FH2)
	pop	bc
	rla			; status back as it was read
	and	10h		; seek error bit: NZ = no track 0
	ret

; FDTOUT - a floppy wait timed out (FDCCMD, FHOME, XFER, FMT's seek).
; Force Interrupt with no condition (D0h) stops the command and raises no
; INTRQ; DI because the hook at 0038h must not fire any more.  Returns
; NZ, A = 20h: never a WD177x status here (those leave ANDed with 5Ch),
; and DFAIL's ERRTAB maps it to DOS error 2, "Not ready".  Reached by JP
; from the waits, so the RET goes straight to their caller.
FDTOUT:
	di
	ld	a,0D0h		; Force Interrupt, no condition
	out	(FDCMD),a
	ld	a,20h		; "not ready"
	or	a		; NZ
	ret
EAHIEND:
	defs	EAHI+256-$	; the rest of the page: zero fill

; =====================================================================
; BCORE - 8-bit ALU cores in 16-byte slots (D500h)
; ---------------------------------------------------------------------
; THE SLOT SCHEME (BCORE, WCORE and SHPG alike).  Each block is a
; page-aligned run of fixed-size routines, one per 8086 operation, in
; the order of the operation's 3-bit field.  The caller does not
; index a table: it patches the LOW byte of its own `JP block` and then
; executes that JP.  Because the block starts at xx00h, the low byte
; alone selects the slot:
;     BCORE  low byte = op * 16      (op from opcode bits 5-3)
;     WCORE  low byte = op * 32
;     SHPG   low byte = k * 16 (16-bit) or 128 + k * 16 (8-bit)
; The patching store and the patched JP (guide item 5):
;     O_ALU0 / O_ALU2 / O_ALU4  AND 38h, ADD A,A      -> (ALUnJ+1)  JP BCORE
;     O_ALU1 / O_ALU3 / O_ALU5  AND 38h, ADD A,A x2   -> (ALUnJ+1)  JP WCORE
;     O_GRP80 (80h, 82h)  (ModR/M AND 38h) x2      -> (G80J+1)   JP BCORE
;     O_GRP81 / O_GRP83   (ModR/M AND 38h) x4      -> (G8xJ+1)   JP WCORE
;     SHB  (byte)         (ModR/M AND 38h) x2 OR 80h -> (SHB2+1)  JP SHPG
;     SHW  (word)         (ModR/M AND 38h) x2      -> (SHW2+1)   JP SHPG
; (op & 38h) is already op * 8, so one doubling gives the 16-byte slot
; and two the 32-byte slot.  The high byte of each JP is never touched.
; Slack in a slot is zero fill (DEFS), never executed.
;
; 8-bit slots.  Entry: HL = destination operand (guest memory or REGS),
; E = source value, IX = NEXT, AF' = 8086 flags.  Exit: JP (IX) with
; the result stored (not for CMP) and AF' = new flags, A' = result's
; low byte (for PF).  The Z80's own flags are the 8086's here: ADD/SUB
; give S Z H(=AF) V(=OF) C; logic ops are followed by ADD A,0 to force
; H = V = C = 0 (Z80 AND sets H, OR/XOR put parity in V).
; Op order = the 8086's: 0 ADD 1 OR 2 ADC 3 SBB 4 AND 5 SUB 6 XOR 7 CMP.
; Mirrors cpu86.py alu() (w = 0).  CMP AL,Ib (3Ch) skips all this:
; O_CMPAL inlines the CMP slot.
; =====================================================================
BCORE:
	ld	a,(hl)	; 0 ADD  (D500h)
	add	a,e		; S Z AF OF CF exactly as the 8086's
	ld	(hl),a		; store; the Z80 flags are already the 8086's
	ex	af,af'		; flags and result byte become AF'
	jp	(ix)		; next instruction
	defs	BCORE+16-$
	ld	a,(hl)	; 1 OR   (D510h)
	or	e		; (Z80 OR: H = 0, V = parity)
	add	a,0	; OF = CF = AF = 0
	ld	(hl),a		;   (V held parity after OR; ADD clears it)
	ex	af,af'		; flags + result to AF'
	jp	(ix)		; next instruction
	defs	BCORE+32-$
	ex	af,af'	; 2 ADC  (D520h) - 8086 CF into the Z80 carry
	ld	a,(hl)		;   (A' is about to be replaced anyway)
	adc	a,e		; dest + src + CF
	ld	(hl),a		; store
	ex	af,af'		; new flags back to AF'
	jp	(ix)		; next instruction
	defs	BCORE+48-$
	ex	af,af'	; 3 SBB  (D530h) - borrow in from CF
	ld	a,(hl)		; dest
	sbc	a,e		; Z80 H on SBC = borrow from bit 4 = 8086 AF
	ld	(hl),a		; store
	ex	af,af'		; flags out
	jp	(ix)		; next instruction
	defs	BCORE+64-$
	ld	a,(hl)	; 4 AND  (D540h)
	and	e		; (Z80 AND: H = 1, V = parity)
	add	a,0		; Z80 AND sets H: clear H, V and C
	ld	(hl),a		; store
	ex	af,af'		; flags out
	jp	(ix)		; next instruction
	defs	BCORE+80-$
	ld	a,(hl)	; 5 SUB  (D550h)
	sub	e		; S Z AF OF CF as the 8086's (H = borrow from bit 4)
	ld	(hl),a		; store
	ex	af,af'		; flags out
	jp	(ix)		; next instruction
	defs	BCORE+96-$
	ld	a,(hl)	; 6 XOR  (D560h)
	xor	e		; (Z80 XOR: H = 0, V = parity)
	add	a,0		; drop parity from V: OF = CF = AF = 0
	ld	(hl),a		; store
	ex	af,af'		; flags out
	jp	(ix)		; next instruction
	defs	BCORE+112-$
	ld	a,(hl)	; 7 CMP  (D570h) - SUB without the store
	sub	e		; flags only: the destination is not written
	ex	af,af'		; A' = difference, for PF
	jp	(ix)		; next instruction
	defs	BCORE+128-$

; ---------------------------------------------------------------------
; INC16 / DEC16 - 16-bit INC / DEC with the 8086's flags (CF kept)
; Entry: HL = value (not a pointer), AF' = 8086 flags.
; Exit:  HL = value +/- 1; AF' = S Z OF from the result, CF unchanged,
;        A' = low byte (PF).  AF (Z80 H) is ALWAYS 0: the closing RRA
;        resets H - cpu86.py sets AF on a nibble carry/borrow (finding).
; Corrupts: A, DE, F.  Returns with RET (not JP (IX)): callers store.
; Callers: O_INC_xx / O_DEC_xx (40h-4Fh), G5_INC / G5_DEC (FF /0 /1).
; Lineage: the BCORE page's spare room after the eight 16-byte slots.
; ---------------------------------------------------------------------
INC16:
	ex	af,af'		; 8086 flags into F
	sbc	a,a	; A = CF ? FFh : 0
	ld	de,0		; adding 0 + carry: the carry is the +1
	scf			; +1 comes in as the carry: ADC HL sets S Z V,
	adc	hl,de		;   which ADD HL,DE would not
	rra	; CF back, S Z V untouched
	ld	a,l		; result's low byte for PF
	ex	af,af'		; flags back
	ret		; to the INC/DEC handler, which stores HL

DEC16:
	ex	af,af'		; as INC16, borrowing instead
	sbc	a,a		; park the 8086 CF in A
	ld	de,0		; subtracting 0 + carry: the carry is the -1
	scf			; HL - 0 - 1 with S Z V set
	sbc	hl,de		; HL - 1: S Z V (OF) as the 8086's
	rra			; CF restored; H (AF) and N cleared
	ld	a,l		; low byte for PF
	ex	af,af'		; flags back to AF'
	ret		; caller stores HL

; ---------------------------------------------------------------------
; LOGF16 - flags of a 16-bit AND / OR / XOR / TEST, then next
; Entry: DE = result (already stored if it is to be).
; Exit:  JP (IX) with S Z from the word, PF from its low byte,
;        OF = CF = AF = 0.  Corrupts: A, DE (0), HL (= result), F.
; Callers: WCORE OR/AND/XOR slots, O_TEST85, O_TESTA9, G3W_TEST.
; ADC HL,DE with DE = 0 and CF = 0 is the cheapest way to make the Z80
; set S and Z for a 16-bit value (no carries: H = V = C = 0).
; ---------------------------------------------------------------------
LOGF16:
	ex	de,hl		; HL = result
	xor	a		; CF = 0, A = 0
	ld	d,a		; DE = 0
	ld	e,a		; (DE is zeroed next; its value now lives in HL)
	adc	hl,de		; HL + 0 + 0: S Z set, H V C clear
	ld	a,l		; low byte for PF
	ex	af,af'		; to the 8086 flags
	jp	(ix)		; next instruction

; ---------------------------------------------------------------------
; I14EXT / I14INI - INT 14h channel set-up, AH = 4 and AH = 0
;   >>> BIOS CODE IN AN INTERPRETER PAGE (the BCORE page's free end)
; ---------------------------------------------------------------------
; BIOS.ASM's T_I14 picks the channel (DX = 0: C = 81h, DX = 1: 41h)
; and jumps here for the two set-up calls; the code sits in the free
; end of the BCORE page, as the serial routines sit in REGS's.  Both
; build an 8251A mode byte in D and a BAUDT index in B, then share
; I14SET, which calls SSET and leaves through SSTAT (AH/AL = status).
; Entry: C = control port, the 8086 registers in REGS.
; Exit:  via SSTAT (RET to T_I14's caller).  Corrupts: A, B, DE, HL, F.
;
; I14EXT (AH = 4, the PS/2 "extended initialize"): CL baud 0-8 (110 ..
; 9600, 19200), CH data bits 0-3 (5-8), BL stop bits (bit 0: 0 one,
; 1 two), BH parity (0 none, 1 odd, 2 even; 3 and 4 - stick parity on
; the PS/2 - and anything else fall to none).  AL (break) is ignored.
; CL >= 9 returns at once: nothing set, AH/AL not touched.
; =====================================================================
I14EXT:
	ld	a,(R_CL)	; 4: CL baud 0-8 (110 ... 9600, 19200),
	cp	9	; CH data bits 0-3 (5-8), BL stop bits
	ret	nc	; (0: 1, 1: 2), BH parity (0 none, 1 odd,
	ld	b,a	; 2 even)
	ld	a,(R_BH)	; parity
	ld	d,10h		; BH = 1: PEN, odd
	dec	a		; BH = 1?
	jr	z,I14EXT_STOP		; odd parity
	ld	d,30h		; BH = 2: PEN + EP, even
	dec	a		; BH = 2?
	jr	z,I14EXT_STOP		; even parity
	ld	d,0		; anything else: no parity
I14EXT_STOP:				; (src: I14E1)
	ld	a,(R_BL)	; stop bits: BL bit 0 ...
	and	1		; BL bit 0 only
	rrca			; ... to mode bit 7: 0 -> 01 (one stop bit),
	or	40h		;   1 -> 11 (two)
	or	d		; with the parity bits
	ld	d,a		; D = stop + parity bits
	ld	a,(R_CH)	; data bits code 0-3 (5-8 bits)
	and	3		; (higher bits of CH ignored)
	jr	I14SET		; build the mode, look up the baud, program it
; I14INI (AH = 0, the PC's form): AL bits 7-5 baud (110 150 300 600
; 1200 2400 4800 9600), 4-3 parity (x0 none, 01 odd, 11 even), 2 stop
; bits (0 one, 1 two), 1-0 data bits (00 5 .. 11 8).
I14INI:
	ld	a,(R_AL)	; 0: AL = baud (bits 7-5: 110 ... 9600),
	ld	e,a	; parity (4-3: x0 none, 01 odd, 11 even),
	and	18h	; stop bits (2: 1 or 2), data bits (1-0)
	add	a,a		; AL bit 3 -> mode bit 4 (PEN), bit 4 -> 5 (EP):
	ld	d,a		;   "10" gives EP without PEN, i.e. none
	bit	2,e		; stop bits
	ld	a,40h		; 0: mode 01xxxxxx, one stop bit
	jr	z,I14INI_MERGE		; one stop bit
	ld	a,0C0h		; 1: mode 11xxxxxx, two
I14INI_MERGE:				; (src: I14I1)
	or	d		; stop + parity
	ld	d,a		; D = stop + parity bits
	ld	a,e		; baud: AL bits 7-5 ...
	rlca		; bits 7-5 ...
	rlca		; ... rotated round ...
	rlca		; ... to bits 2-0
	and	7		; ... as 0-7
	ld	b,a		; BAUDT index
	ld	a,e		; AL again for the data bits
	and	3		; data bits code
; I14SET - common tail.  A = data bits code, D = stop + parity bits,
; B = BAUDT index; C = control port.
I14SET:
	add	a,a	; A = data bits 0-3, D = parity and stop
	add	a,a	; bits, B = index in BAUDT
	or	d		; data bits in mode bits 3-2
	or	SIO_X16		; x16 clock, as COLD and CBIOS use
	ld	d,a		; D = the mode byte
	ld	hl,BAUDT	; E = BAUDT[B]
	ld	a,l		; HL = BAUDT + B, done by hand
	add	a,b		; (an 8-bit add on L ...)
	ld	l,a		; (... with the carry into H below)
	jr	nc,I14SET_FETCH	; page-carry guard (never taken: BAUDT ends
	inc	h		;   at D0F0h)
I14SET_FETCH:				; (src: I14S1)
	ld	e,(hl)		; the WD2123 baud code
	call	SSET		; program the channel
	jp	SSTAT		; and return its status, as the PC BIOS does

	defs	(($+255)&0FF00h)-$	; D5FB-D5FF: pad to the WCORE page
; =====================================================================
; WCORE - 16-bit ALU cores in 32-byte slots (D600h)
; ---------------------------------------------------------------------
; Selected by the patched JP low byte = op * 32 (see BCORE's header).
; Entry: HL = destination operand pointer, DE = source value,
;        IX = NEXT, AF' = 8086 flags.
; Exit:  JP (IX) (or via LOGF16) with the word stored (not for CMP) and
;        AF' = flags, A' = low byte of the result.
; Arithmetic slots use ADC HL,DE / SBC HL,DE (ADD HL,DE would not set
; S Z V): S Z OF CF are the 8086's, but the Z80's H is the carry out of
; bit 11, so AF differs from cpu86.py (author's known difference).
; Logic slots work byte by byte and leave the flags to LOGF16.
; Op order: 0 ADD 1 OR 2 ADC 3 SBB 4 AND 5 SUB 6 XOR 7 CMP.
; Mirrors cpu86.py alu() (w = 1).
; =====================================================================
WCORE:
	push	hl	; 0 ADD  (D600h) - keep the pointer for the store
	ld	a,(hl)		; HL = the destination word
	inc	hl		; read the destination word ...
	ld	h,(hl)		; ... high byte ...
	ld	l,a		; ... into HL
	or	a		; CF = 0: ADC becomes ADD with S Z V set
	adc	hl,de		; dest + src: S Z OF CF, H = carry out of bit 11
	ld	a,l		; low byte for PF
	ex	af,af'		; flags out
	ex	de,hl		; DE = result
	pop	hl		; back to the destination
	ld	(hl),e		; store it, low byte first
	inc	hl		; high byte
	ld	(hl),d		; of the result
	jp	(ix)		; next instruction
	defs	WCORE+32-$
	ld	a,(hl)	; 1 OR   (D620h) - low byte
	or	e		; low result byte
	ld	e,a		; DE collects the result for LOGF16
	ld	(hl),a		; stored in place
	inc	hl		; high byte
	ld	a,(hl)		; high byte of the destination
	or	d		; OR in the source's high byte
	ld	d,a		; DE = whole result
	ld	(hl),a		; stored
	jp	LOGF16		; S Z PF from DE, OF CF AF cleared
	defs	WCORE+64-$
	push	hl	; 2 ADC  (D640h)
	ld	a,(hl)		; HL = destination word
	inc	hl		; read the destination word
	ld	h,(hl)
	ld	l,a
	ex	af,af'		; 8086 CF in
	adc	hl,de		; dest + src + CF
	ld	a,l		; low byte for PF
	ex	af,af'		; flags out
	ex	de,hl		; store as in ADD
	pop	hl		; destination pointer back
	ld	(hl),e		; store the result
	inc	hl
	ld	(hl),d
	jp	(ix)		; next instruction
	defs	WCORE+96-$
	push	hl	; 3 SBB  (D660h)
	ld	a,(hl)		; read the destination word
	inc	hl
	ld	h,(hl)
	ld	l,a
	ex	af,af'		; borrow in from the 8086 CF
	sbc	hl,de		; dest - src - CF
	ld	a,l		; low byte for PF
	ex	af,af'		; flags out
	ex	de,hl		; DE = result
	pop	hl		; destination pointer back
	ld	(hl),e		; store it
	inc	hl
	ld	(hl),d
	jp	(ix)		; next instruction
	defs	WCORE+128-$
	ld	a,(hl)	; 4 AND  (D680h)
	and	e		; low byte
	ld	e,a		; DE collects the result
	ld	(hl),a		; stored in place
	inc	hl		; high byte
	ld	a,(hl)
	and	d		; AND in the source's high byte
	ld	d,a
	ld	(hl),a		; stored
	jp	LOGF16		; S Z PF from DE, OF CF AF cleared
	defs	WCORE+160-$
	push	hl	; 5 SUB  (D6A0h)
	ld	a,(hl)		; read the destination word
	inc	hl
	ld	h,(hl)
	ld	l,a
	or	a		; no borrow in
	sbc	hl,de		; dest - src: S Z OF CF; H = borrow from bit 11
	ld	a,l		; low byte for PF
	ex	af,af'		; flags out
	ex	de,hl		; DE = result
	pop	hl		; destination pointer back
	ld	(hl),e		; store it
	inc	hl
	ld	(hl),d
	jp	(ix)		; next instruction
	defs	WCORE+192-$
	ld	a,(hl)	; 6 XOR  (D6C0h)
	xor	e		; low byte
	ld	e,a		; DE collects the result
	ld	(hl),a		; stored in place
	inc	hl		; high byte
	ld	a,(hl)
	xor	d		; XOR in the source's high byte
	ld	d,a
	ld	(hl),a		; stored
	jp	LOGF16		; S Z PF from DE, OF CF AF cleared
	defs	WCORE+224-$
	ld	a,(hl)	; 7 CMP  (D6E0h) - SUB without the store,
	inc	hl		;   so no PUSH HL either
	ld	h,(hl)		; ... HL = destination word
	ld	l,a
	or	a		; no borrow in
	sbc	hl,de		; dest - src, result discarded
	ld	a,l		; difference's low byte for PF
	ex	af,af'		; flags out
	jp	(ix)		; next instruction
	defs	WCORE+256-$

; =====================================================================
; SHPG - shift / rotate loops in 16-byte slots (D700h)
; ---------------------------------------------------------------------
; Selected by the patched JP low byte (see BCORE's header): SHW puts
; k * 16 into SHW2+1 for a word operand, SHB puts 128 + k * 16 into
; SHB2+1 for a byte operand; k = the ModR/M reg field:
;     k  0 ROL  1 ROR  2 RCL  3 RCR  4 SHL  5 SHR  6 SAL (= SHL)  7 SAR
;     D700-D770 16-bit, D780-D7F0 8-bit
; Entry: HL (16-bit) or L (8-bit) = value, D = count 1-255 (count 0 is
;        filtered out by the caller; CL is not masked, as on an 8086),
;        stack: [SP] = the 8086 flags (old AF'), [SP+2] = operand
;        address.
; Exit:  JP to a finisher (part 5: ROT16A/B, SHL16F, SHR16F, SAR16F,
;        ROT8A/B, SHL8F, SHR8F, SAR8F) with the result in HL / L and
;        Z80 C = the last bit shifted out (the 8086's CF).  The
;        finishers compute OF etc., pop the flags, store, JP (IX).
; RCL / RCR slots peek at the stacked flags (POP AF / PUSH AF) to seed
; the carry.  DEC D leaves the carry alone, so it survives the loop.
; k = 6 is treated as SHL, as cpu86.py does (op_shift: k == 4 or 6).
; =====================================================================
SHPG:
SH16_ROL:				; (src: S16R0)
	add	hl,hl	; 0 ROL  (D700h) - bit 15 out to carry ...
	jr	nc,SH16_ROL_NEXT		; bit 15 was 0: nothing to wrap
	inc	l		; ... and back in at bit 0 (INC keeps carry)
SH16_ROL_NEXT:				; (src: S16R0A)
	dec	d		; one bit position done
	jr	nz,SH16_ROL		; until the count runs out
	jp	ROT16A		; CF = last bit out; OF = MSB ^ CF
	defs	SHPG+16-$
SH16_ROR:				; (src: S16R1)
	srl	h	; 1 ROR  (D710h) - bit 0 out to carry ...
	rr	l		; (low byte: bit 0 now in carry)
	jr	nc,SH16_ROR_NEXT		; bit 0 was 0: nothing to wrap
	set	7,h		; ... and back in at bit 15 (SET keeps carry)
SH16_ROR_NEXT:				; (src: S16R1A)
	dec	d		; one bit position done
	jr	nz,SH16_ROR
	jp	ROT16B		; OF = bit 15 ^ bit 14
	defs	SHPG+32-$
	pop	af	; 2 RCL: CF in
	push	af		; (D720h) the flags stay on the stack
SH16_RCL:				; (src: S16R2)
	rl	l		; 17-bit rotate through carry
	rl	h		; (high byte: bit 15 to carry)
	dec	d		; one bit position done
	jr	nz,SH16_RCL
	jp	ROT16A		; OF = MSB ^ CF
	defs	SHPG+48-$
	pop	af	; 3 RCR
	push	af		; (D730h) 8086 CF into the Z80 carry
SH16_RCR:				; (src: S16R3)
	rr	h		; carry -> bit 15, bit 0 -> carry
	rr	l		; (bit 0 to carry)
	dec	d		; one bit position done
	jr	nz,SH16_RCR
	jp	ROT16B		; OF = bit 15 ^ bit 14
	defs	SHPG+64-$
SH16_SHL:				; (src: S16R4)
	add	hl,hl	; 4 SHL  (D740h) - bit 15 to carry, 0 in
	dec	d		; one bit position done
	jr	nz,SH16_SHL
	jp	SHL16F		; S Z PF, OF = MSB ^ CF, AF = 0
	defs	SHPG+80-$
SH16_SHR:				; (src: S16R5)
	srl	h	; 5 SHR  (D750h) - 0 in at bit 15
	rr	l		; bit 0 to carry
	dec	d		; one bit position done
	jr	nz,SH16_SHR
	jp	SHR16F		; OF = old MSB when the count was 1
	defs	SHPG+96-$
SH16_SAL:				; (src: S16R6)
	add	hl,hl	; 6 SAL (= SHL)  (D760h)
	dec	d		; one bit position done
	jr	nz,SH16_SAL
	jp	SHL16F		; same finisher as SHL
	defs	SHPG+112-$
SH16_SAR:				; (src: S16R7)
	sra	h	; 7 SAR  (D770h) - sign bit copied down
	rr	l		; (bit 0 to carry)
	dec	d		; one bit position done
	jr	nz,SH16_SAR
	jp	SAR16F		; OF = 0
	defs	SHPG+128-$
SH8_ROL:				; (src: S8R0)
	rlc	l	; 0 ROL  (D780h) - bit 7 to carry and bit 0
	dec	d		; one bit position done
	jr	nz,SH8_ROL
	jp	ROT8A		; OF = bit 7 ^ CF
	defs	SHPG+144-$
SH8_ROR:				; (src: S8R1)
	rrc	l	; 1 ROR  (D790h) - bit 0 to carry and bit 7
	dec	d		; one bit position done
	jr	nz,SH8_ROR
	jp	ROT8B		; OF = bit 7 ^ bit 6
	defs	SHPG+160-$
	pop	af	; 2 RCL
	push	af		; (D7A0h) seed the carry with the 8086 CF
SH8_RCL:				; (src: S8R2)
	rl	l		; 9-bit rotate through carry
	dec	d		; one bit position done
	jr	nz,SH8_RCL
	jp	ROT8A		; as ROL
	defs	SHPG+176-$
	pop	af	; 3 RCR
	push	af		; (D7B0h) seed the carry
SH8_RCR:				; (src: S8R3)
	rr	l		; carry -> bit 7, bit 0 -> carry
	dec	d		; one bit position done
	jr	nz,SH8_RCR
	jp	ROT8B		; as ROR
	defs	SHPG+192-$
SH8_SHL:				; (src: S8R4)
	sla	l	; 4 SHL  (D7C0h)
	dec	d		; one bit position done
	jr	nz,SH8_SHL
	jp	SHL8F		; S Z PF, OF = bit 7 ^ CF, AF = 0
	defs	SHPG+208-$
SH8_SHR:				; (src: S8R5)
	srl	l	; 5 SHR  (D7D0h)
	dec	d		; one bit position done
	jr	nz,SH8_SHR
	jp	SHR8F		; OF = old bit 7 when the count was 1
	defs	SHPG+224-$
SH8_SAL:				; (src: S8R6)
	sla	l	; 6 SAL  (D7E0h) - as SHL
	dec	d		; one bit position done
	jr	nz,SH8_SAL
	jp	SHL8F		; same finisher as SHL
	defs	SHPG+240-$
SH8_SAR:				; (src: S8R7)
	sra	l	; 7 SAR  (D7F0h)
	dec	d		; one bit position done
	jr	nz,SH8_SAR
	jp	SAR8F		; OF = 0
	defs	SHPG+256-$	; D7F8-D7FF: slot slack; START follows at D800h
; =====================================================================
;                    THE DISPATCHER AND ITS HELPERS
; =====================================================================
;
; THE Z80 REGISTER CONTRACT while 8086 code runs (I86.ASM preamble;
; README "The Z80 interpreter"):
;
;   BC   host address of the next 8086 code byte = CS base + IP.  Guest
;        linear address n is Z80 address n, so fetching is LD A,(BC) /
;        INC BC and IP itself is never kept (GETIP rebuilds it).
;   IX   the dispatcher.  Every handler ends with JP (IX), normally to
;        NEXT; a segment override points it at RESTORE for exactly one
;        instruction (O_SEG_*, SEGSET).  Only the code in this part ever
;        loads IX (LD IX at START, O_SEG_*, SEGSET, RESTORE).
;   AF'  the 8086 arithmetic flags.  F' holds S Z AF OF CF in the Z80's
;        S Z H V C bits; A' is the low byte of the last result and PF is
;        its parity, worked out only when FLAGS is read (GETF).  Only
;        flag code does EX AF,AF'.
;   A DE HL IY, Z80 SP   scratch (SP is the Z80's own stack, FFFFh down).
;
; The 8086 registers live in the REGS page (D000h, page-aligned), so a
; ModR/M operand always decodes to a host pointer: into guest memory or
; into REGS.  One handler then serves register and memory operands.
;
; Lineage: the whole part must behave as cpu86.py's CPU class
; (project/MSDOS/poc/cpu86.py); the matching Python routine is named in
; each header.

; =====================================================================
; START - enter 8086 execution
; ---------------------------------------------------------------------
; Entry:  REGS holds AX..DI and the four segment registers, TMP = IP,
;         FLAGHI = TF IF DF, AF' = the arithmetic flags (COLD sets F' = 0,
;         A' = 1: all clear, PF = 0, FLAGHI = 0, IP = 0).
; Exit:   never returns - FARJ loads BC and jumps into NEXT.
; Called: COLD (JP START at F194h, part 07/08).
;
; Discards any Z80 stack, so START is also a clean restart point.
; Builds the three segment bases that FARJ does not (CS is FARJ's job),
; primes the override-aware operand bases EADS/EASS with the plain DS/SS
; bases, and sets STEP1/STEP2 from DF.
; =====================================================================
START:
	di			; no Z80 interrupts while the 8086 runs
	ld	sp,0		; fresh Z80 stack from FFFFh down
	ld	ix,NEXT		; the dispatcher every handler returns through
	ld	hl,(R_ES)	; ES base = ES << 4 (16 bits: the guest is 52 KB)
	call	SHL4		; ES << 4
	ld	(B_ES),hl	; B_ES: string destinations (ES:DI)
	ld	hl,(R_SS)	; SS base, and the SS-relative operand base
	call	SHL4		; SS << 4
	ld	(B_SS),hl	; B_SS: the stack (PUSHDE/POPDE)
	ld	(EASS),hl	; EASS: BP-based operands, no override yet
	ld	hl,(R_DS)	; DS base, and the DS-relative operand base
	call	SHL4		; DS << 4
	ld	(B_DS),hl	; B_DS: the value RESTORE returns to
	ld	(EADS),hl	; EADS: DS-relative operands, no override yet
	call	SETSTEP		; string step +-1/+-2 from DF in FLAGHI
	ld	hl,(R_CS)	; CS:IP = R_CS:TMP; FARJ makes B_CS and BC
	ld	de,(TMP)	; the IP COLD left in TMP
	jp	FARJ		; ... and falls into the first JP (IX)

; =====================================================================
; SHL4 - HL = HL << 4 (segment value -> base)
; ---------------------------------------------------------------------
; Entry: HL = segment.  Exit: HL = segment * 16, mod 64K.  Corrupts F.
; Called: START only (FARJ and SETSEG inline the same four ADDs).
; =====================================================================
SHL4:
	add	hl,hl		; x2
	add	hl,hl		; x4
	add	hl,hl		; x8
	add	hl,hl		; x16: bits 12-15 of the segment fall off
	ret			; HL = base

; =====================================================================
; NEXT - the dispatcher: fetch an opcode, jump to its handler
; ---------------------------------------------------------------------
; Entry:  BC -> the opcode.  IX = NEXT (every handler ends JP (IX)).
; Exit:   jumps to the handler with A = opcode, BC -> the byte after it,
;         HL = the handler's address, DE = the old HL (junk), Z80 F
;         corrupted (INC H).  AF' and IX are never touched.
;
; The split table: OPLO (D100h) holds the 256 handler low bytes, OPHI
; (D200h, the very next page) the high bytes.  The opcode is the low
; byte of both addresses, so moving from one to the other is a single
; INC H - no doubling, no carry.  Cost: 7+6+4+7+7+4+7+4+4 = 50 T-states
; here, plus the handler's closing JP (IX) at 8: 58 T-states of overhead
; per 8086 instruction, the figure the README quotes (verified).
; mirrors cpu86.py step() / self.ops[op](op).
; =====================================================================
NEXT:
	ld	a,(bc)		; the opcode ...
	inc	bc		; ... consumed: BC = CS base + IP + 1
	ld	l,a		; index both halves of the table by it
	ld	h,OPLO>>8	; D1h: the low-byte page
	ld	e,(hl)		; handler low byte
	inc	h		; D2h: OPHI, same offset
	ld	d,(hl)		; handler high byte
	ex	de,hl		; HL = handler
	jp	(hl)		; handler gets A = opcode

; =====================================================================
; NEXT2 / DISPA - dispatch the byte after a prefix
; ---------------------------------------------------------------------
; NEXT2: entry BC -> the byte after a prefix.  DISPA: entry A = an
; opcode already fetched.  Exit: as NEXT.
; Called: NEXT2 by O_SEG_* (JP), O_LOCK (it IS NEXT2: F0h re-dispatches
; the next byte, so LOCK is ignored) and R_NOTSTR (REP on a non-string
; opcode, part 05); DISPA by O_REP's REP3 (part 05), which has already
; fetched the byte while scanning for string opcodes.
;
; The same code as NEXT, duplicated because NEXT's address is in IX and
; may at this moment be RESTORE: a prefix must reach the next handler
; without passing through IX.
; =====================================================================
NEXT2:
	ld	a,(bc)		; the prefixed opcode
	inc	bc		; BC past it
DISPA:
	ld	l,a		; same split-table lookup as NEXT
	ld	h,OPLO>>8	; D1h: OPLO, the low bytes
	ld	e,(hl)		; handler low byte
	inc	h		; OPLO -> OPHI
	ld	d,(hl)		; handler high byte
	ex	de,hl		; HL = handler
	jp	(hl)		; handler gets A = opcode

; =====================================================================
; O_SEG_ES / O_SEG_CS / O_SEG_SS / O_SEG_DS - opcodes 26h 2Eh 36h 3Eh
; ---------------------------------------------------------------------
; Entry:  from NEXT, BC -> the byte after the prefix.
; Exit:   EADS = EASS = the named segment's base, IX = RESTORE, and the
;         next instruction dispatched straight away (JP NEXT2).
; Corrupts HL (A = the next opcode, from NEXT2).
;
; Every memory operand base comes from EADS (DS-relative ModR/M forms,
; string sources, moffs) or EASS (BP-based forms), never from B_DS /
; B_SS directly.  So an override is two stores; undoing it is RESTORE's
; job, which runs at the end of the prefixed instruction because that
; instruction ends with JP (IX) and IX now points there.  The stack
; (PUSHDE/POPDE) uses B_SS, so it is rightly immune to overrides.
; Stacked prefixes simply overwrite each other: the last one wins, as in
; cpu86.py step() (self.seg = (op >> 3) & 3).  Cost: 72 T-states, plus
; RESTORE's 86 - an override costs about 158 T-states (verified by count).
; =====================================================================
O_SEG_ES:
	ld	hl,(B_ES)	; both operand bases become ES's
	ld	(EADS),hl	; DS-side operands now use ES
	ld	(EASS),hl	; and BP-based ones
	ld	ix,RESTORE	; one instruction from now, put them back
	jp	NEXT2		; run the prefixed instruction (not via IX)
O_SEG_CS:
	ld	hl,(B_CS)	; both operand bases become CS's
	ld	(EADS),hl	; DS-side operands now use CS
	ld	(EASS),hl	; and BP-based ones
	ld	ix,RESTORE	; undo after the next instruction
	jp	NEXT2		; run the prefixed instruction
O_SEG_SS:
	ld	hl,(B_SS)	; both operand bases become SS's
	ld	(EADS),hl	; DS-side operands now use SS
	ld	(EASS),hl	; BP-based ones (SS anyway, unless overridden)
	ld	ix,RESTORE	; undo after the next instruction
	jp	NEXT2		; run the prefixed instruction
O_SEG_DS:
	ld	hl,(B_DS)	; both operand bases become DS's
	ld	(EADS),hl	; DS-side operands (DS anyway, unless overridden)
	ld	(EASS),hl	; BP-based ones now use DS
	ld	ix,RESTORE	; undo after the next instruction
	jp	NEXT2		; run the prefixed instruction

; =====================================================================
; SEGSET - a segment override met inside a REP prefix sequence
; ---------------------------------------------------------------------
; Entry:  A = the override prefix (26h 2Eh 36h 3Eh).
; Exit:   EADS = EASS = that segment's base, IX = RESTORE; RETurns.
; Corrupts A, F, DE, HL.
; Called: O_REP's REP2 (part 05), which loops over the prefix bytes
; itself and so needs a CALLable form of O_SEG_*.
;
; The prefix's bits 4-3 are the segment number (ES 0, CS 1, SS 2,
; DS 3).  Two RRCAs bring them to bits 2-1, i.e. 2*sreg, which indexes
; the word table of bases B_ES/B_CS/B_SS/B_DS in the REGS page:
;   26h -> 0 (B_ES)   2Eh -> 2 (B_CS)   36h -> 4 (B_SS)   3Eh -> 6 (B_DS)
; =====================================================================
SEGSET:
	rrca			; bits 4-3 (the sreg number) ...
	rrca			; ... to bits 2-1
	and	06h		; A = 2 * sreg
	add	a,0FFh&B_ES	; + offset of B_ES in REGS: L of that base
	ld	l,a		;   (the 0FFh& guard: CONVENTIONS rule 3)
	ld	h,REGS>>8	; the REGS page (D0h)
	ld	e,(hl)		; DE = the segment's base
	inc	l		; word-aligned within REGS: no carry into H
	ld	d,(hl)		; high byte of the base
	ld	(EADS),de	; both operand bases become it, as O_SEG_*
	ld	(EASS),de	; (EADS above): both bases overridden
	ld	ix,RESTORE	; undo after the string instruction
	ret			; back to O_REP's prefix loop

; =====================================================================
; RESTORE - end of a segment-overridden instruction
; ---------------------------------------------------------------------
; Entry:  reached ONLY through JP (IX) after O_SEG_* or SEGSET set
;         IX = RESTORE (nothing CALLs or JPs here; the partition descent
;         finds it only via LD IX,RESTORE - notes/partition_findings.md).
; Exit:   EADS = B_DS, EASS = B_SS, IX = NEXT, and on into NEXT.
; Corrupts HL.
;
; Reloading from B_DS/B_SS (not from saved copies) also covers an
; overridden instruction that loaded DS or SS itself (POP DS, MOV DS,..,
; LDS): SETSEG has already updated the base, and RESTORE copies the
; new one.  86 T-states including the JP (IX).
; =====================================================================
RESTORE:
	ld	hl,(B_DS)	; DS-relative operands back to DS ...
	ld	(EADS),hl	; (EADS above)
	ld	hl,(B_SS)	; ... BP-relative back to SS
	ld	(EASS),hl	; (EASS above)
	ld	ix,NEXT		; the override is spent
	jp	(ix)		; dispatch the following instruction

; F0h LOCK: no bus to lock - just dispatch the next byte (cpu86.py step()
; skips F0h the same way).
O_LOCK:	equ	NEXT2

; =====================================================================
; O_BAD / BADSTOP - an opcode the interpreter does not implement
; ---------------------------------------------------------------------
; Entry:  from NEXT (opcode F1h, the only OPLO hole) or JP NZ,O_BAD from
;         O_GRP4 (FEh with ModR/M reg field 2-7, part 08).
; Exit:   none - a tight loop with interrupts off.
;
; BC is stepped back one byte so that, at BADSTOP, BC - CS base names
; the opcode for a debugger: z86.py hooks BADSTOP and prints the byte at
; BC.  True from NEXT only: from O_GRP4 the ModR/M (and any displacement)
; has been fetched too, so BC lands inside the instruction.
; mirrors cpu86.py op_bad (raises Halt).
; =====================================================================
O_BAD:
	dec	bc		; back onto the offending opcode
BADSTOP:
	jr	BADSTOP		; stop for good (harnesses trap this address)

; =====================================================================
; O_HLT - F4h HLT
; ---------------------------------------------------------------------
; There are no 8086 interrupts to wake it (START left the Z80 at DI), so
; HLT hangs the machine; z86.py and fdd86.py treat a PC of HALTED as the
; end of the run.  cpu86.py op_hlt sets halted the same way.
; =====================================================================
O_HLT:
HALTED:
	jr	HALTED		; for ever

; =====================================================================
; O_NOP - 90h NOP, 9Bh WAIT, EEh/EFh OUT DX,AL/AX
; ---------------------------------------------------------------------
; Back to the dispatcher at once (8 T-states).  WAIT has no coprocessor
; to wait for; OUT DX goes nowhere (OPLO maps EEh/EFh here, while
; cpu86.py op_out calls its port_out hook: a divergence only if a guest
; port device ever listens on DX ports).
; =====================================================================
O_NOP:
	jp	(ix)		; nothing to do

; =====================================================================
; O_TRAP - 0Fh nn, the BIOS trap (POP CS on a real 8086)
; ---------------------------------------------------------------------
; Entry:  from NEXT, BC -> nn.  Exit: through IX after TRAP returns.
; IO.SYS's entries and the PC ROM interrupts are each TRAP n.  TRAP
; (BIOS.ASM, part 06) takes A = n and works on the registers in REGS,
; returning ZF/CF in AF'.  Under z86.py, TRAP is a RET the Python BIOS
; hooks.  mirrors cpu86.py op_trap.
; =====================================================================
O_TRAP:
	ld	a,(bc)		; A = BIOS function number nn
	inc	bc		; IP past the 2-byte trap
	call	TRAP		; into the Z80 BIOS
	jp	(ix)		; next instruction (BIOS set ZF/CF in AF')

; =====================================================================
;                    ModR/M DECODING
; =====================================================================
;
; ModR/M = mod(7-6) reg(5-3) r/m(2-0).  mod = 11 (byte >= C0h) names a
; register; anything below C0h is a memory operand, decoded by one of 24
; routines EA<mod><rm> through the split table EALO (D300h) / EAHI
; (D400h), indexed by the WHOLE ModR/M byte.  The reg field does not
; matter to the address, so each 8-entry row is repeated 8 times:
;   00h-3Fh  EA00..EA07  mod 0: no displacement (r/m 6 = [disp16])
;   40h-7Fh  EA10..EA17  mod 1: + sign-extended disp8
;   80h-BFh  EA20..EA27  mod 2: + disp16
;   C0h-FFh  zeros (never used: mod 3 is a register)
;
; Register operands point into REGS (page-aligned at D000h):
;   word reg n  -> REGS + 2n                 (AX CX DX BX SP BP SI DI)
;   byte reg n  -> REGS + R8TAB[n], R8TAB = 0 2 4 6 1 3 5 7
;                  (AL CL DL BL = low bytes, AH CH DH BH = high bytes)
; R8TAB sits at REGS+48 (30h), 8-aligned, so "OR R8TAB&0FFh" indexes it.

; =====================================================================
; MRW - fetch the ModR/M of a word instruction, decode both operands
; ---------------------------------------------------------------------
; Entry:  BC -> ModR/M.
; Exit:   HL -> the r/m operand (guest memory or REGS), DE -> the reg
;         operand (always REGS + 2*reg), BC past ModR/M and displacement.
; Corrupts A, F.
; Called: O_ALU1, O_ALU3, O_TEST85, O_XCHG87, O_MOV89, O_MOV8B, LXS.
; mirrors cpu86.py modrm() + the get_rm/set_rm addressing.
; =====================================================================
MRW:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; BC past ModR/M (displacements follow)
	cp	0C0h		; mod < 3: a memory operand
	jr	c,MRWM		; memory forms go through EALO/EAHI
	ld	e,a		; keep ModR/M for the reg field
	and	7		; r/m = a word register:
	add	a,a		;   its offset in REGS is 2 * r/m
	ld	l,a		; L = 2 * r/m
	ld	a,e		; ModR/M back
	rrca			; reg field (bits 5-3) to bits 3-1 ...
	rrca
	and	0Eh		; ... = 2 * reg, the reg operand's offset
	ld	e,a		; E = 2 * reg
	ld	h,REGS>>8	; both pointers in the REGS page
	ld	d,h		; D = D0h too
	ret
MRWM:
	push	af		; the EA routines eat A: save the ModR/M
	call	EAMEM		; HL = host address of the memory operand
	pop	af		; ModR/M back
	rrca			; DE = REGS + 2 * reg, as above
	rrca
	and	0Eh		; A = 2 * reg
	ld	e,a
	ld	d,REGS>>8	; DE -> the reg16 in REGS
	ret			; HL -> memory, DE -> register

; =====================================================================
; MRB - the same for a byte instruction
; ---------------------------------------------------------------------
; Entry:  BC -> ModR/M.
; Exit:   HL -> the r/m byte operand, DE -> the reg byte operand (REGS +
;         R8TAB[reg]), BC past ModR/M and displacement.
; Corrupts A, F.
; Called: O_ALU0, O_ALU2, O_TEST84, O_XCHG86, O_MOV88, O_MOV8A.
; mirrors cpu86.py modrm() with getr8/setr8.
; =====================================================================
MRB:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; BC past ModR/M
	cp	0C0h		; memory operand?
	jr	c,MRBM		; memory forms go through EALO/EAHI
	ld	e,a		; keep ModR/M
	and	7		; r/m = byte register number ...
	or	R8TAB&0FFh	; ... index into R8TAB
	ld	l,a		; L -> R8TAB entry
	ld	h,REGS>>8	; R8TAB is in the REGS page
	ld	l,(hl)		; HL = REGS + that register's byte offset
	ld	a,e		; ModR/M back for the reg field
	jr	REG8		; decode reg the same way as the memory path
MRBM:
	push	af		; save ModR/M across the EA routine
	call	EAMEM		; HL = host address of the memory operand
	pop	af		; ModR/M back for the reg field
REG8:
	rrca			; A = ModR/M -> DE = reg8 operand:
	rrca			;   reg field (bits 5-3) down to bits 2-0
	rrca
	and	7		; A = reg (0-7)
	or	R8TAB&0FFh	; look the register up in R8TAB
	ld	e,a		; E -> R8TAB entry
	ld	d,REGS>>8	; DE -> R8TAB entry
	ld	a,(de)		; its byte offset in REGS ...
	ld	e,a		; ... DE = REGS + offset
	ret			; HL -> r/m, DE -> reg8

; =====================================================================
; EAW / EAB - decode the r/m half only, ModR/M already fetched
; ---------------------------------------------------------------------
; Entry:  A = ModR/M, BC -> any displacement.
; Exit:   HL -> the r/m operand (word / byte), BC past the displacement.
; Corrupts A, F, DE (memory forms).
; Callers of EAW: O_GRP81, O_GRP83, O_MOV8C, O_MOV8E, O_POP8F, O_MOVC7,
; O_SHD1, SHWA, O_ESC, O_GRP3W, O_GRP5.  Of EAB: O_GRP80, O_MOVC6, SHB,
; O_GRP3B, O_GRP4.  These handlers want the reg field as an opcode
; extension, not a register, so they keep ModR/M themselves.
; =====================================================================
EAW:
	cp	0C0h		; memory operand?
	jr	c,EAMEM		; mod < 3: memory
	and	7		; word register r/m: REGS + 2 * r/m
	add	a,a		; 2 * r/m
	ld	l,a		; L = offset in REGS
	ld	h,REGS>>8	; HL -> the word register
	ret
EAB:
	cp	0C0h		; memory operand?
	jr	c,EAMEM		; mod < 3: memory
	and	7		; byte register r/m: REGS + R8TAB[r/m]
	or	R8TAB&0FFh	; index R8TAB
	ld	l,a		; L -> R8TAB entry
	ld	h,REGS>>8	; in the REGS page
	ld	l,(hl)		; HL -> the byte register
	ret

; =====================================================================
; EAMEM - dispatch a memory ModR/M (00h-BFh) to its EA routine
; ---------------------------------------------------------------------
; Entry:  A = ModR/M < C0h, BC -> any displacement.
; Exit:   via the EA routine: HL = operand host address.  Corrupts A,
;         F, DE.
; Called: MRWM, MRBM, EAW, EAB (falling or jumping in), O_LEA.
; The same split-table trick as NEXT: EALO page, INC H, EAHI page.
; =====================================================================
EAMEM:
	ld	l,a		; ModR/M indexes both halves
	ld	h,EALO>>8	; D3h: the low bytes
	ld	e,(hl)		; low byte of EA<mod><rm>
	inc	h		; D4h: EAHI
	ld	d,(hl)		; high byte
	ex	de,hl		; HL = EA<mod><rm>
	jp	(hl)		; it RETs to our caller

; =====================================================================
; EA<mod><rm> - the 24 memory-operand routines
; ---------------------------------------------------------------------
; Entry:  from EAMEM; BC -> the displacement, if any.
; Exit:   HL = segment base + effective address (16-bit host address),
;         BC past the displacement.  Corrupts A, F, DE.
;
;   r/m:  0 BX+SI  1 BX+DI  2 BP+SI  3 BP+DI  4 SI  5 DI  6 BP  7 BX
;   r/m 2, 3, 6 (BP-based) take EASS; the rest take EADS.  mod 0 r/m 6
;   is [disp16], DS-relative (EA06).
;
; The offset wraps at 16 bits and the base is added mod 64K too: the
; 8086's 20-bit sum is not modelled (I86.ASM preamble: the guest has
; only 52 KB).  EADS/EASS are the override-aware bases (O_SEG_*).
; mirrors cpu86.py modrm() (rm/mod branches, dseg = SS for BP forms).
; =====================================================================

; ---- mod 00: no displacement ----------------------------------------
EA00:
	ld	hl,(R_BX)	; [BX+SI]
	ld	de,(R_SI)	; + SI
	add	hl,de		; offset BX+SI (wraps at 16 bits)
ADDDS:
	ld	de,(EADS)	; common tail: + DS-side base (override aware)
	add	hl,de		; host address = base + offset
	ret
EA01:
	ld	hl,(R_BX)	; [BX+DI]
	ld	de,(R_DI)	; + DI
	add	hl,de		; BX+DI
	jr	ADDDS		; DS side
EA02:
	ld	hl,(R_BP)	; [BP+SI], SS-relative
	ld	de,(R_SI)	; + SI
	add	hl,de		; BP+SI
ADDSS:
	ld	de,(EASS)	; common tail: + SS-side base (override aware)
	add	hl,de		; host address = SS-side base + offset
	ret
EA03:
	ld	hl,(R_BP)	; [BP+DI], SS-relative
	ld	de,(R_DI)	; + DI
	add	hl,de		; BP+DI
	jr	ADDSS		; SS side
EA04:
	ld	hl,(R_SI)	; [SI]
	jr	ADDDS		; DS side
EA05:
	ld	hl,(R_DI)	; [DI]
	jr	ADDDS		; DS side
EA06:
	ld	a,(bc)		; [disp16]: mod 0 r/m 6 is a direct
	ld	l,a		;   address, not [BP]
	inc	bc		; BC past disp16 low byte
	ld	a,(bc)		; disp16 high byte
	ld	h,a		; HL = disp16
	inc	bc		; BC past it
	jr	ADDDS		; DS-relative
EA07:
	ld	hl,(R_BX)	; [BX]
	jr	ADDDS

; ---- mod 01: + disp8, sign-extended ---------------------------------
EA10:
	ld	hl,(R_BX)	; [BX+SI+d8]
	ld	de,(R_SI)	; + SI
	add	hl,de		; BX+SI
D8DS:
	ld	a,(bc)		; common tail: fetch d8 ...
	inc	bc		; BC past d8
	ld	e,a		; low byte of the displacement
	add	a,a		; ... CF = its sign bit ...
	sbc	a,a		; ... A = 00h or FFh
	ld	d,a		; DE = d8 sign-extended
	add	hl,de		; offset + d8
	jr	ADDDS		; then the DS-side base
EA11:
	ld	hl,(R_BX)	; [BX+DI+d8]
	ld	de,(R_DI)	; + DI
	add	hl,de		; BX+DI
	jr	D8DS		; + d8, DS side
EA12:
	ld	hl,(R_BP)	; [BP+SI+d8], SS-relative
	ld	de,(R_SI)	; + SI
	add	hl,de		; BP+SI
D8SS:
	ld	a,(bc)		; d8, sign-extended, as D8DS
	inc	bc		; BC past d8
	ld	e,a
	add	a,a		; sign bit into CF
	sbc	a,a		; A = 00h / FFh
	ld	d,a		; DE = d8 sign-extended
	add	hl,de		; offset + d8
	jr	ADDSS		; then the SS-side base
EA13:
	ld	hl,(R_BP)	; [BP+DI+d8], SS-relative
	ld	de,(R_DI)	; + DI
	add	hl,de		; BP+DI
	jr	D8SS		; + d8, SS side
EA14:
	ld	hl,(R_SI)	; [SI+d8]
	jr	D8DS		; + d8, DS side
EA15:
	ld	hl,(R_DI)	; [DI+d8]
	jr	D8DS		; + d8, DS side
EA16:
	ld	hl,(R_BP)	; [BP+d8]: with a displacement r/m 6 is BP
	jr	D8SS		; + d8, SS side
EA17:
	ld	hl,(R_BX)	; [BX+d8]
	jr	D8DS		; + d8, DS side

; ---- mod 10: + disp16 -----------------------------------------------
EA20:
	ld	hl,(R_BX)	; [BX+SI+d16]
	ld	de,(R_SI)	; + SI
	add	hl,de		; BX+SI
D16DS:
	ld	a,(bc)		; common tail: DE = d16 (little-endian)
	ld	e,a		; disp16 low byte
	inc	bc
	ld	a,(bc)		; disp16 high byte
	ld	d,a		; DE = disp16
	inc	bc		; BC past d16
	add	hl,de		; offset + d16
	jp	ADDDS		; out of JR range from here
EA21:
	ld	hl,(R_BX)	; [BX+DI+d16]
	ld	de,(R_DI)	; + DI
	add	hl,de		; BX+DI
	jr	D16DS		; + d16, DS side
EA22:
	ld	hl,(R_BP)	; [BP+SI+d16], SS-relative
	ld	de,(R_SI)	; + SI
	add	hl,de		; BP+SI
D16SS:
	ld	a,(bc)		; DE = d16, as D16DS
	ld	e,a		; disp16 low byte
	inc	bc
	ld	a,(bc)		; high byte
	ld	d,a		; DE = disp16
	inc	bc		; BC past d16
	add	hl,de		; offset + d16
	jp	ADDSS		; out of JR range
EA23:
	ld	hl,(R_BP)	; [BP+DI+d16], SS-relative
	ld	de,(R_DI)	; + DI
	add	hl,de		; BP+DI
	jr	D16SS		; + d16, SS side
EA24:
	ld	hl,(R_SI)	; [SI+d16]
	jr	D16DS		; + d16, DS side
EA25:
	ld	hl,(R_DI)	; [DI+d16]
	jr	D16DS		; + d16, DS side
EA26:
	ld	hl,(R_BP)	; [BP+d16]
	jr	D16SS		; + d16, SS side
EA27:
	ld	hl,(R_BX)	; [BX+d16]
	jr	D16DS		; + d16, DS side

; =====================================================================
; JTAB - jump to entry A/2 of a DW table, keeping HL
; ---------------------------------------------------------------------
; Entry:  A = 2 * index (the groups pass ModR/M & 38h shifted down),
;         DE = table.  HL = the decoded operand, passed through.
; Exit:   jumps to the entry.  Corrupts A, F, DE (DE = the target).
; Called: O_GRP3B (G3BT), O_GRP3W (G3WT), O_GRP5 (G5T), all part 08.
; PUSH DE / RET is the jump: JP (HL) would cost the operand pointer.
; =====================================================================
JTAB:
	add	a,e		; DE += A, 8-bit add with carry into D
	ld	e,a
	jr	nc,JTAB_FETCH	; no carry out of E
	inc	d		; carry into the high byte
JTAB_FETCH:				; (src: JTAB1)
	ex	de,hl		; HL -> entry, DE keeps the operand
	ld	a,(hl)		; entry low byte
	inc	hl		; entry high byte
	ld	h,(hl)		; entry high byte
	ld	l,a		; HL = target
	ex	de,hl		; DE = target, HL = operand again
	push	de		; jump there via RET
	ret

; =====================================================================
;                    HELPERS
; =====================================================================

; =====================================================================
; GETIP - DE = the 8086 IP
; ---------------------------------------------------------------------
; Entry:  BC = host code pointer.  Exit: DE = BC - B_CS (the IP of the
; next byte).  Corrupts A, F, HL.
; Called: MOVCS, O_CALLF, DOINT, G5_CALL, G5_CALLF (to push a return IP
; or keep IP across a CS change).
; =====================================================================
GETIP:
	ld	hl,(B_CS)	; IP = host pointer - CS base, 16-bit
	ld	a,c		;   (byte-wise, so BC is not disturbed)
	sub	l		; IP low = C - base low
	ld	e,a
	ld	a,b		; B - base high
	sbc	a,h		; IP high, with the borrow
	ld	d,a		; DE = IP
	ret

; =====================================================================
; FARJ - continue at CS:IP = HL:DE
; ---------------------------------------------------------------------
; Entry:  HL = new CS, DE = new IP.
; Exit:   R_CS, B_CS and BC set; jumps through IX (never returns).
; Called (JP): START, MOVCS, O_CALLF, O_RETFN, O_RETF, DOINT, O_IRET,
; O_JMPF, G5_CALLF, G5_JMPF.
; =====================================================================
FARJ:
	ld	(R_CS),hl	; the visible CS
	add	hl,hl		; its base = CS << 4
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	(B_CS),hl	; CS base
	add	hl,de		; + IP = host address of the next byte
	ld	b,h		; ... the new code pointer
	ld	c,l		; BC = CS base + IP
	jp	(ix)		; dispatch there (via RESTORE if overridden)

; =====================================================================
; PUSHDE / POPDE - the 8086 stack
; ---------------------------------------------------------------------
; PUSHDE: entry DE = word.  SP -= 2, then the word goes to SS base + SP,
;         low byte first.
; POPDE:  exit DE = the word at SS base + SP, then SP += 2.
; Both corrupt A, F, HL.  B_SS, not EASS: the stack ignores segment
; overrides, as on the 8086.  The base is added byte-wise through A
; because ADD HL,DE would need DE, which holds the data.
; PUSHDE called by O_PUSH_ES/CS/SS/DS, O_CALLF, O_PUSHF, DOINT, G5_CALL,
; G5_CALLF, G5_PUSH; POPDE by O_POP_ES/SS/DS, O_POP8F, O_POPF, O_RETN,
; O_RETFN, O_RETF, O_IRET.
; mirrors cpu86.py push() / pop().  A word at offset FFFFh needs no
; care: host addresses are mod 64K, so base + FFFFh + 1 = base + 0000h,
; the same wrap cpu86.py's (off + 1) & 0FFFFh makes.
; =====================================================================
PUSHDE:
	ld	hl,(R_SP)	; pre-decrement SP
	dec	hl		; (two bytes per push)
	dec	hl		; SP - 2
	ld	(R_SP),hl	; the new SP
	ld	a,(B_SS)	; HL = SS base + SP, without touching DE
	add	a,l
	ld	l,a
	ld	a,(B_SS+1)	; base high byte
	adc	a,h		; high byte with carry
	ld	h,a		; HL = host address of the new top
	ld	(hl),e		; low byte at the lower address
	inc	hl
	ld	(hl),d		; high byte above it
	ret

POPDE:
	ld	hl,(R_SP)	; DE = SS base + SP (the address) ...
	ld	a,(B_SS)	; base low byte + SP low
	add	a,l
	ld	e,a
	ld	a,(B_SS+1)	; base high byte + SP high
	adc	a,h
	ld	d,a		; DE = host address of the top
	inc	hl		; ... then post-increment SP
	inc	hl
	ld	(R_SP),hl	; SP + 2
	ex	de,hl		; HL -> the word
	ld	e,(hl)		; DE = it
	inc	hl
	ld	d,(hl)		; DE = the popped word
	ret

; =====================================================================
; SETSEG - load segment register A/2 with DE, and its base
; ---------------------------------------------------------------------
; Entry:  A = 2 * sreg (0 ES, 2 CS, 4 SS, 6 DS), DE = the new value.
; Exit:   R_xx = DE, B_xx = DE << 4, and EADS / EASS kept in step for
;         DS / SS.  DE = the new base.  Corrupts A, F, HL.
; Called: O_POP_ES, O_POP_SS, O_POP_DS, O_MOV8E, LXS.
;
; R_ES..R_DS sit at REGS+16.., their bases B_ES..B_DS 8 bytes further
; on, so one pointer walks from the register to its base.  CS gets no
; special care: B_CS changes but BC does not move, so a caller loading
; CS must rebuild BC itself (O_MOV8E sends CS elsewhere - MOVCS).
; mirrors cpu86.py s[] assignment + z86.py _seg_set.
; =====================================================================
SETSEG:
	add	a,0FFh&R_ES	; L = offset of R_xx in REGS
	ld	l,a		; L -> R_xx
	ld	h,REGS>>8	; in the REGS page
	ld	(hl),e		; the visible segment register
	inc	l		; word-aligned: no carry into H
	ld	(hl),d		; high byte of the new value
	ld	a,l		; R_xx+1 + 8 = B_xx+1: its base's high byte
	add	a,8		; skip to the matching base
	ld	l,a		; L -> B_xx + 1
	ex	de,hl		; DE = value << 4, HL kept as the pointer
	add	hl,hl		; x16: the new base
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ex	de,hl		; DE = base, HL = pointer
	ld	(hl),d		; store the base, high byte first
	dec	l
	ld	(hl),e		; low byte of the base
	ld	a,l		; which base was it?
	cp	0FFh&B_DS	; DS?
	jr	z,SETSEG_DS	; DS: update EADS
	cp	0FFh&B_SS	; SS?
	ret	nz		; ES, CS: no operand base depends on them
	ld	(EASS),de	; SS: BP-relative operands follow at once
	ret
SETSEG_DS:				; (src: SETSG1)
	ld	(EADS),de	; DS: DS-relative operands follow at once
	ret

; =====================================================================
; GETF - HL = the 8086 FLAGS word
; ---------------------------------------------------------------------
; Entry:  AF' = arithmetic flags, FLAGHI = TF IF DF in bits 0-2.
; Exit:   HL = FLAGS.  AF' unchanged.  Corrupts A, F, DE.
; Called: O_PUSHF, O_SAHF, O_LAHF, DOINT.
;
;   Z80 F':  S7 Z6 -5 H4 -3 V2 N1 C0      A' = last result low byte
;   FLAGS:   -15..12=1 OF11 DF10 IF9 TF8 | S7 Z6 0 AF4 0 PF2 1 CF0
; S Z AF CF copy across (mask D1h); bit 1 is forced on; PF is the
; parity of A' (OR A sets the Z80's P/V to even parity); OF comes from
; V; bits 12-15 read as 1, as cpu86.py's 0F002h base.
; mirrors cpu86.py CPU.flags (getter) - verified.
; =====================================================================
GETF:
	ex	af,af'		; copy the 8086 flags out ...
	push	af		; (PUSH AF of the alternate pair)
	ex	af,af'		; ... leaving AF' as it was
	pop	de		; D = A' (PF byte), E = F'
	ld	a,e		; F'
	and	0D1h		; S Z AF CF in place; V/N/undoc bits out
	or	02h		; FLAGS bit 1 is always 1
	ld	l,a		; low byte of FLAGS so far
	ld	a,d		; A'
	or	a		; P/V = parity of the last result
	jp	po,GETF_HIGH	; odd parity: PF stays 0
	set	2,l		; even parity: PF
GETF_HIGH:				; (src: GETF1)
	ld	a,(FLAGHI)	; TF IF DF in bits 0-2 (= FLAGS 8-10)
	or	0F0h		; FLAGS 12-15 read as 1
	bit	2,e		; Z80 V = 8086 OF
	jr	z,GETF_DONE	; V clear: OF = 0
	or	08h		; OF
GETF_DONE:				; (src: GETF2)
	ld	h,a		; high byte of FLAGS
	ret			; HL = FLAGS

; =====================================================================
; SETF - FLAGS = HL; falls into SETSTEP
; ---------------------------------------------------------------------
; Entry:  HL = a FLAGS word.
; Exit:   AF' and FLAGHI rebuilt, STEP1/STEP2 from DF.  Corrupts A, F,
;         DE, HL.
; Called: O_POPF, O_SAHF, O_IRET.
;
; PF cannot be stored as a bit - it is always the parity of A' - so A'
; is chosen to have the right parity: 00h (even, PF = 1) or 01h (odd,
; PF = 0).  This loses the old result byte, which nothing else reads.
; mirrors cpu86.py CPU.flags (setter) - verified.
; =====================================================================
SETF:
	ld	a,l		; FLAGS low byte
	and	0D1h		; S Z AF CF into F' positions
	bit	3,h		; FLAGS bit 11, OF ...
	jr	z,SETF_PF	; V stays clear
	or	04h		; OF -> V
SETF_PF:				; (src: SETF1)
	ld	e,a		; E = new F'
	ld	d,0		; A' = 0: even parity, PF = 1
	bit	2,l		; PF?
	jr	nz,SETF_LOAD	; PF set: A' = 0 is right
	inc	d		; A' = 1: PF = 0
SETF_LOAD:				; (src: SETF2)
	push	de		; AF = D:E ...
	pop	af		; F = E, A = D
	ex	af,af'		; ... becomes the 8086 flags
	ld	a,h		; FLAGS high byte
	and	07h		; keep TF IF DF (bits 8-10)
	ld	(FLAGHI),a	; the high flags
				; fall into SETSTEP: DF may have changed

; =====================================================================
; SETSTEP - STEP1 / STEP2 = +1/+2 (DF = 0) or -1/-2 (DF = 1)
; ---------------------------------------------------------------------
; Entry:  FLAGHI bit 2 = DF.  Exit: STEP1, STEP2 set.  Corrupts A, F,
; DE, HL.  Called: START, O_CLD, O_STD, and SETF falling in.
; The string handlers add these instead of testing DF each time.
; =====================================================================
SETSTEP:
	ld	a,(FLAGHI)	; TF IF DF
	and	4		; DF
	ld	hl,1		; DF = 0: SI/DI go up
	ld	de,2		; STEP2 = +2
	jr	z,SETSTEP_STORE	; DF clear
	ld	hl,-1		; DF = 1: down
	ld	de,-2		; STEP2 = -2
SETSTEP_STORE:				; (src: SETST1)
	ld	(STEP1),hl	; byte step
	ld	(STEP2),de	; word step
	ret

; =====================================================================
; SETCO - CF = OF = (Z80 NZ), the other 8086 flags kept
; ---------------------------------------------------------------------
; Entry:  Z80 Z = 1 when the high half of a product is insignificant.
; Exit:   F' bits C and V both set (NZ) or both clear (Z); A', S, Z, AF
;         untouched.  The caller's A and F survive (they ride in the
;         alternate pair meanwhile).  Corrupts E, HL.
; Called: G3B_MUL, G3B_IMUL, G3W_MUL, G3WIM2 (part 08).
; mirrors cpu86.py MUL/IMUL's cf = of = (high part significant).
; =====================================================================
SETCO:
	ld	e,0		; Z: CF = OF = 0
	jr	z,SETCO_MERGE	; Z: store with both clear
	ld	e,05h		; NZ: Z80 V (OF) and C (CF)
SETCO_MERGE:				; (src: SETCO1)
	ex	af,af'		; the 8086 flags to the main pair
	push	af		; F' via the stack
	pop	hl		; L = F', H = A'
	ld	a,l		; F'
	and	0FAh		; drop the old V and C
	or	e		; put the new ones in
	ld	l,a
	push	hl		; HL = A' : new F'
	pop	af		; A' back unchanged, new F'
	ex	af,af'		; flags home; caller's AF back
	ret

; =====================================================================
; SZP8 - set S Z PF from an 8-bit result, keep CF OF AF; ends the
;        instruction
; ---------------------------------------------------------------------
; Entry:  A = the result (AL).  Exit: JP (IX) - tail-jumped to, never
; called.  Corrupts DE, HL.
; Called (JP): O_AAM, O_AAD (part 03).
; A' becomes the result, so PF follows it; S and Z are built by hand
; because no Z80 arithmetic has run on it.
; =====================================================================
SZP8:
	ld	d,a		; D = result -> the new A'
	ex	af,af'		; copy F' out
	push	af		; F' via the stack
	ex	af,af'		; (AF' left unchanged)
	pop	hl		; L = F'
	ld	a,l		; F'
	and	15h		; AF OF CF (Z80 H V C) are kept
	ld	e,a		; E = the kept bits
	ld	a,d
	and	80h		; S = the result's bit 7
	or	e		; S from the result
	ld	e,a
	ld	a,d		; result again
	or	a		; Z when the result is 0
	jr	nz,SZP8_STORE	; non-zero: ZF stays 0
	set	6,e		; ZF
SZP8_STORE:				; (src: SZP81)
	push	de		; AF' = result : new flags
	pop	af		; main AF = result : flags
	ex	af,af'		; swap them into AF'
	jp	(ix)		; end of the instruction

; =====================================================================
;                    00h-3Fh: THE ALU OPCODES
; =====================================================================
;
; Opcode 00ooo0dw: ooo = ADD OR ADC SBB AND SUB XOR CMP, low 3 bits:
;   0 r/m8,r8   1 r/m16,r16   2 r8,r/m8   3 r16,r/m16   4 AL,imm8
;   5 AX,imm16                 (6, 7: PUSH/POP seg, prefixes, BCD ops)
;
; SELF-MODIFYING DISPATCH.  The arithmetic itself lives in two cores:
;   BCORE (D500h, page-aligned): 8 slots of 16 bytes, slot k at D500h+16k
;   WCORE (D600h, page-aligned): 8 slots of 32 bytes, slot k at D600h+32k
; in operation order ADD OR ADC SBB AND SUB XOR CMP (part 01).  Each core
; takes HL -> destination and E (BCORE) / DE (WCORE) = source, writes
; the result (CMP does not) and the flags, and ends with JP (IX).
; Opcode & 38h is 8k, so one ADD A,A gives 16k (a BCORE slot offset)
; and two give 32k (a WCORE slot offset, at most E0h).  Each handler
; stores that byte into the LOW byte of its own JP's operand (ALUnJ+1);
; the high byte, D5h or D6h, never changes, which is why the cores must
; start on a page boundary.  The patched JP runs a few instructions
; later, so no flag, register or table lookup is spent on choosing the
; operation.  The stored byte stays until the next opcode of that form,
; harmless since every entry rewrites it first.
; mirrors cpu86.py op_alu + alu().

; ---- 00 08 10 .. 38: r/m8 op= r8 -------------------------------------
O_ALU0:
	and	38h		; r/m8 op= r8: ooo field = 8k
	add	a,a		; 16k = the BCORE slot offset
	ld	(ALU0J+1),a	; PATCH: low byte of the JP below -> slot k
	call	MRB		; HL -> r/m8 (destination), DE -> reg8
	ld	a,(de)		; the reg8's value
	ld	e,a		; E = the source value
ALU0J:
	jp	BCORE		; PATCHED: JP D500h+16k (low byte set above)

; ---- 01 09 11 .. 39: r/m16 op= r16 -----------------------------------
O_ALU1:
	and	38h		; r/m16 op= r16: 8k
	add	a,a		; 32k = the WCORE slot offset
	add	a,a		; 32k = the WCORE slot offset
	ld	(ALU1J+1),a	; PATCH: low byte of the JP below -> slot k
	call	MRW		; HL -> r/m16 (destination), DE -> reg16
	ex	de,hl		; DE = the reg's value:
	ld	a,(hl)		; the reg16's value, low byte
	inc	l		; INC L is safe: the reg is word-aligned in REGS
	ld	h,(hl)		; high byte
	ld	l,a		; DE = reg value after the swap
	ex	de,hl		; HL -> destination again
ALU1J:
	jp	WCORE		; PATCHED: JP D600h+32k (low byte set above)

; ---- 02 0A 12 .. 3A: r8 op= r/m8 -------------------------------------
O_ALU2:
	and	38h		; r8 op= r/m8: 8k
	add	a,a		; 16k: BCORE slot
	ld	(ALU2J+1),a	; PATCH: low byte of the JP below -> slot k
	call	MRB		; HL -> r/m8, DE -> reg8 (destination)
	ld	a,(hl)		; the r/m value is the source
	ex	de,hl		; HL -> reg8
	ld	e,a		; E = source
ALU2J:
	jp	BCORE		; PATCHED: JP D500h+16k (low byte set above)

; ---- 03 0B 13 .. 3B: r16 op= r/m16 -----------------------------------
O_ALU3:
	and	38h		; r16 op= r/m16: 8k
	add	a,a		; 32k: WCORE slot
	add	a,a		; 32k: WCORE slot
	ld	(ALU3J+1),a	; PATCH: low byte of the JP below -> slot k
	call	MRW		; HL -> r/m16, DE -> reg16 (destination)
	ld	a,(hl)		; HL = the r/m value; INC HL, not INC L:
	inc	hl		;   a memory operand may straddle a page
	ld	h,(hl)		; high byte of the r/m value
	ld	l,a
	ex	de,hl		; HL -> reg16, DE = source
ALU3J:
	jp	WCORE		; PATCHED: JP D600h+32k (low byte set above)

; ---- 04 0C 14 .. 34: AL op= imm8 (3Ch has its own handler) -----------
O_ALU4:
	and	38h		; AL op= imm8: 8k
	add	a,a		; 16k: BCORE slot
	ld	(ALU4J+1),a	; PATCH: low byte of the JP below -> slot k
	ld	a,(bc)		; E = the immediate byte
	inc	bc		; BC past imm8
	ld	e,a		; E = imm8
	ld	hl,R_AL		; destination AL
ALU4J:
	jp	BCORE		; PATCHED: JP D500h+16k (low byte set above)

; =====================================================================
; O_CMPAL - 3Ch CMP AL,imm8, a fast path
; ---------------------------------------------------------------------
; OPLO sends 3Ch here instead of O_ALU4, skipping the patch and the
; BCORE hop (46 T-states against 84).  Why only CMP AL,imm8 got a fast path is
; not recorded; presumably it was hot in DOS's character loops
; (provisional - the profile is not in the notes).  Same
; result as BCORE's CMP slot: SUB sets S Z AF OF CF, A = AL - imm is
; the low byte PF is taken from.
; =====================================================================
O_CMPAL:
	ld	a,(bc)		; the immediate
	inc	bc		; BC past imm8
	ld	e,a		; E = imm8
	ld	a,(R_AL)	; AL
	sub	e		; AL - imm: flags only, AL untouched
	ex	af,af'		; they are the 8086 flags now
	jp	(ix)		; next instruction

; ---- 05 0D 15 .. 3D: AX op= imm16 ------------------------------------
O_ALU5:
	and	38h		; AX op= imm16: 8k
	add	a,a		; 32k: WCORE slot
	add	a,a		; 32k: WCORE slot
	ld	(ALU5J+1),a	; PATCH: low byte of the JP below -> slot k
	ld	a,(bc)		; DE = the immediate word
	ld	e,a		; imm16 low byte
	inc	bc
	ld	a,(bc)		; imm16 high byte
	ld	d,a		; DE = imm16
	inc	bc		; BC past imm16
	ld	hl,R_AX		; destination AX
ALU5J:
	jp	WCORE		; PATCHED: JP D600h+32k (low byte set above)

; =====================================================================
; O_PUSH_ES/CS/SS/DS - 06h 0Eh 16h 1Eh;  O_POP_ES/SS/DS - 07h 17h 1Fh
; ---------------------------------------------------------------------
; There is no O_POP_CS: 0Fh is the BIOS trap (O_TRAP).  The POPs go
; through SETSEG so the base (and EADS/EASS) follow the new value.
; mirrors cpu86.py op_push_seg / op_pop_seg.
; =====================================================================
O_PUSH_ES:
	ld	de,(R_ES)	; PUSH ES
	call	PUSHDE		; SP -= 2, store
	jp	(ix)		; next
O_PUSH_CS:
	ld	de,(R_CS)	; PUSH CS
	call	PUSHDE		; SP -= 2, store
	jp	(ix)		; next
O_PUSH_SS:
	ld	de,(R_SS)	; PUSH SS
	call	PUSHDE		; SP -= 2, store
	jp	(ix)		; next
O_PUSH_DS:
	ld	de,(R_DS)	; PUSH DS
	call	PUSHDE		; SP -= 2, store
	jp	(ix)		; next
O_POP_ES:
	call	POPDE		; POP ES: DE = the word
	xor	a		; sreg 0 (ES) -> A = 0
	call	SETSEG		; value and base
	jp	(ix)		; next
O_POP_SS:
	call	POPDE		; POP SS
	ld	a,4		; sreg 2 (SS) -> A = 4
	call	SETSEG		; also moves EASS
	jp	(ix)		; next
O_POP_DS:
	call	POPDE		; POP DS
	ld	a,6		; sreg 3 (DS) -> A = 6
	call	SETSEG		; also moves EADS
	jp	(ix)		; next
; =====================================================================
;            DECIMAL ADJUST: DAA DAS AAA AAS (27h 2Fh 37h 3Fh)
; =====================================================================
;
; HOW THE 8086 FLAGS LIVE IN AF' (the convention every handler in this
; part relies on).  F' holds S Z AF OF CF in the Z80's S Z H V C bits
; (7 6 4 2 0); A' holds the low byte of the last result, and PF is its
; parity, worked out only when something asks (O_JP / O_JNP below,
; GETF for PUSHF / LAHF / INT).  So the four handlers here read the old
; flags by copying AF' into DE (D = A', E = F') and write the new ones
; by building a DE and POPping it into AF'.
;
; AF AFTER 16-BIT ARITHMETIC.  These four are the only instructions
; that READ AF in a computation.  The overview says AF comes from bit
; 11 after 16-bit add / subtract / increment / decrement; the code is
; more mixed (notes/z86_part03_findings.md, F1):
;   - 16-bit ADD ADC SUB SBB CMP (WCORE, its ADC HL / SBC HL): AF is
;     the carry out of bit 11, the Z80 H flag.
;   - INC / DEC reg16 and r/m16 (INC16 / DEC16): AF is ALWAYS 0.  The
;     ADC HL / SBC HL that does the work sets H from bit 11, but the
;     RRA that then puts CF back clears H.  Run on the Z80 build: INC
;     AX with AX = 000Fh gives FLAGS F002h, cpu86.py F012h; INC AX with
;     AX = 0FFFh (a bit-11 carry) also gives AF = 0.
; Where it matters: DAA / DAS / AAA / AAS straight after a 16-bit op,
; which real code does not do (it adjusts AL after 8-bit arithmetic),
; and any copy of FLAGS taken by PUSHF, LAHF or INT, where AF can
; differ from an 8086's.  Where it does not: no Jcc, ALU, shift or
; string op tests AF.  test_z86.py masks AF in FLAGS and in pushed
; FLAGS words, and fuzz_z86.py's af_loose covers INC / DEC, so neither
; test can see the difference.
; =====================================================================

; =====================================================================
; O_DAA - 27h DAA: decimal adjust AL after an addition
; ---------------------------------------------------------------------
; Entry:  AF' = 8086 flags, AL in REGS.
; Exit:   AL adjusted; CF and AF as the 8086 sets them, S Z from the new
;         AL, A' = new AL (so PF), OF kept.  Ends JP (IX).
; Corrupts: A DE HL.
; Callers: OPLO/OPHI slot 27h.
;
; Mirrors cpu86.py op_daa test for test: low digit > 9 or AF -> +6 and
; AF = 1; ORIGINAL AL > 99h or CF -> +60h and CF = 1.  The second test
; reads the AL from before the +6 (H keeps it), as the 8086 does.  OF
; is undefined on an 8086 after DAA; cpu86 leaves it alone, so the
; tail keeps the old V bit.  The Z80's own DAA cannot be used: it
; works from N and H of the last Z80 operation, not of the last 8086
; one.
; =====================================================================
O_DAA:
	ex	af,af'		; old 8086 flags into DE:
	push	af		;   E = F' (S Z AF OF CF), D = A' (dropped
	ex	af,af'		;   below - the new A' is the new AL)
	pop	de	; E = old flags
	ld	a,(R_AL)	; the AL being adjusted ...
	ld	h,a	; ... H keeps it as it came, for the high test
	ld	d,a	; ... D is the copy that gets adjusted
	ld	l,0	; L collects the new AF (bit 4) and CF (bit 0)
	and	0Fh		; low digit above 9 ...
	cp	10		;   (10-15: NC)
	jr	nc,DAA_LOW_ADJ	;   ... adjust
	bit	4,e		; ... or AF set by the addition?
	jr	z,DAA_HIGH_TEST	; neither: low digit is fine
DAA_LOW_ADJ:				; (src: DAA1)
	ld	a,d		; +6 carries the low digit into the high one
	add	a,6
	ld	d,a
	ld	l,10h		; AF = 1
DAA_HIGH_TEST:				; (src: DAA2)
	ld	a,h		; original AL above 99h ...
	cp	9Ah		;   (9Ah-FFh: NC)
	jr	nc,DAA_HIGH_ADJ	;   ... adjust
	bit	0,e		; ... or CF set by the addition?
	jr	z,DAA_FLAGS	; neither: CF stays 0
DAA_HIGH_ADJ:				; (src: DAA3)
	ld	a,d		; +60h fixes the high digit
	add	a,60h
	ld	d,a
	set	0,l		; CF = 1 (a decimal carry out)

; ---- DAA_FLAGS: shared tail of DAA and DAS ---------------------------
; D = new AL, L = AF | CF, E = old flags.  Builds F from scratch: S and
; Z from the new AL, H and C from L, V (OF) from the old flags; N and
; the undocumented bits 3 and 5 stay 0.  A' = new AL carries PF.
DAA_FLAGS:				; (src: DAAF)
	ld	a,d		; the adjusted AL ...
	ld	(R_AL),a	; ... to the register file
	ld	a,e		; OF (Z80 V, bit 2) survives unchanged
	and	04h
	or	l		; with AF and CF
	ld	l,a
	ld	a,d		; SF = bit 7 of the new AL
	and	80h
	or	l
	ld	l,a
	ld	a,d		; ZF if the new AL is 0
	or	a
	jr	nz,DAA_FLAGS_NZ
	set	6,l		; Z80 Z, bit 6
DAA_FLAGS_NZ:				; (src: DAAF1)
	ld	e,l		; DE = new AL : new F ...
	push	de		; ... through the stack ...
	pop	af
	ex	af,af'		; ... into AF', the 8086 flags
	jp	(ix)		; next instruction

; =====================================================================
; O_DAS - 2Fh DAS: decimal adjust AL after a subtraction
; ---------------------------------------------------------------------
; Entry, exit, corrupts: as O_DAA.  Callers: OPLO/OPHI slot 2Fh.
;
; DAA with SUB for ADD (cpu86.py op_das): the same two tests on the
; same AL, -6 and -60h, then DAA's flag tail.
; =====================================================================
O_DAS:
	ex	af,af'		; E = old 8086 flags (D overwritten below)
	push	af		; AF' copied through the stack ...
	ex	af,af'		; ... and left in place
	pop	de		; E = F'
	ld	a,(R_AL)	; the AL being adjusted:
	ld	h,a		;   H as it came, for the high test
	ld	d,a		;   D the adjusted copy
	ld	l,0		; L = new AF | CF
	and	0Fh		; low digit above 9 ...
	cp	10
	jr	nc,DAS_LOW_ADJ	;   ... adjust
	bit	4,e		; ... or a borrow out of it (AF)?
	jr	z,DAS_HIGH_TEST	; neither
DAS_LOW_ADJ:				; (src: DAS1)
	ld	a,d		; -6 undoes the low digit's wrap
	sub	6
	ld	d,a
	ld	l,10h		; AF = 1
DAS_HIGH_TEST:				; (src: DAS2)
	ld	a,h		; original AL above 99h ...
	cp	9Ah
	jr	nc,DAS_HIGH_ADJ	;   ... adjust
	bit	0,e		; ... or a borrow out of AL (CF)?
	jr	z,DAA_FLAGS	; neither: CF = 0
DAS_HIGH_ADJ:				; (src: DAS3)
	ld	a,d		; -60h for the high digit
	sub	60h
	ld	d,a
	set	0,l		; CF = 1 (a decimal borrow)
	jr	DAA_FLAGS	; S Z PF OF as DAA

; =====================================================================
; O_AAA - 37h AAA: ASCII adjust after an addition
; ---------------------------------------------------------------------
; Entry:  AF' = 8086 flags, AX in REGS.
; Exit:   AX adjusted, AL's high nibble cleared; AF = CF = 1 if an
;         adjustment was made, else both 0; S Z OF and A' (so PF) kept.
;         Ends JP (IX).
; Corrupts: A DE HL.
; Callers: OPLO/OPHI slot 37h.
;
; Mirrors cpu86.py op_aaa, which also adds 106h to the whole of AX, so
; a carry out of AL+6 reaches AH (AL = FAh with an adjust: AH+2; run on
; both, both give AX = 0200h).  That is the 80286-and-later behaviour;
; the original 8086 is documented as adding 6 to AL and 1 to AH
; separately (provisional: never compared with a real 8086; finding
; F4).  The 8086 leaves S Z PF OF undefined; here they keep their old
; values, as in cpu86.
; =====================================================================
O_AAA:
	ex	af,af'		; DE = old A' : F' - both kept unless AF / CF
	push	af		;   change, so PF (from A') carries through
	ex	af,af'
	pop	de
	ld	hl,(R_AX)	; HL = AX
	ld	a,l		; low digit of AL above 9 ...
	and	0Fh
	cp	10
	jr	nc,AAA_ADJ	;   ... adjust
	bit	4,e		; ... or AF?
	jr	z,AAA_CLR_AFCF	; neither: no adjustment
AAA_ADJ:				; (src: AAA1)
	push	de		; keep the flags while DE is the addend
	ld	de,106h		; AX += 106h: AL+6, AH+1 (plus AL's carry,
	add	hl,de		;   as cpu86 - see the header)
	pop	de		; flags back
AAA_SET_AFCF:				; (src: AAAS1) - AAS joins here
	ld	a,e		; adjusted: AF (H, bit 4) = CF (bit 0) = 1
	or	11h
	ld	e,a
	jr	AAA_STORE	; then mask and store
AAA_CLR_AFCF:				; (src: AAA0) - AAS joins here
	ld	a,e		; not adjusted: AF = CF = 0
	and	0EEh
	ld	e,a
AAA_STORE:				; (src: AAA2)
	ld	a,l		; AL keeps only its low digit either way
	and	0Fh
	ld	l,a
	ld	(R_AX),hl	; AX back to REGS
	push	de		; old A' with the new F ...
	pop	af
	ex	af,af'		; ... back into AF'
	jp	(ix)		; next instruction

; =====================================================================
; O_AAS - 3Fh AAS: ASCII adjust after a subtraction
; ---------------------------------------------------------------------
; Entry, exit, corrupts: as O_AAA.  Callers: OPLO/OPHI slot 3Fh.
;
; Mirrors cpu86.py op_aas: AL-6 and AH-1 as two separate bytes (no
; borrow from AL into AH, unlike AAA's 106h add), then AAA's tails.
; =====================================================================
O_AAS:
	ex	af,af'		; DE = old A' : F'
	push	af		; through the stack, AF' unchanged
	ex	af,af'
	pop	de
	ld	hl,(R_AX)	; HL = AX
	ld	a,l		; low digit of AL above 9 ...
	and	0Fh
	cp	10
	jr	nc,AAS_ADJ	;   ... adjust
	bit	4,e		; ... or AF?
	jr	z,AAA_CLR_AFCF	; no: AF = CF = 0, AL masked
AAS_ADJ:				; (src: AAS1)
	ld	a,l		; AL - 6, borrow dropped
	sub	6
	ld	l,a		; (8-bit: AH not touched by it)
	dec	h		; AH - 1
	jr	AAA_SET_AFCF	; AF = CF = 1, AL masked

; =====================================================================
;      40h-5Fh: INC / DEC / POP / PUSH reg16 (one handler per opcode)
; =====================================================================
;
; Expanded by the source's `;@FOR R AX CX DX BX SP BP SI DI` loop: per
; register an INC (40h+r), a DEC (48h+r) and a POP (58h+r), then the
; PUSHes (50h+r) with PUSH SP apart.  Reached from OPLO/OPHI only.
;
; INC / DEC: HL = the register, INC16 / DEC16 (BCORE page, D580h /
; D58Ch) do the arithmetic and the flags: CF kept, S Z OF from the
; 16-bit result, A' = low byte (PF), AF always 0 (see the note at the
; top; cpu86.py sets AF from bit 4 - finding F1).  Corrupts A DE HL.
;
; POP: the source's POPDE pasted inline, which saves the CALL and RET
; (27 T-states) on one of the commonest instructions.  The stack
; address is SS base + SP, a 16-bit add, so it wraps in the 64K guest
; exactly as SS:SP wraps in the segment.  Corrupts A DE HL.  POP SP
; stores SP+2 first and then the popped word over it, so SP ends as
; the popped value, as on an 8086 and in cpu86.py.
; =====================================================================
O_INC_AX:				; 40h INC AX
	ld	hl,(R_AX)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_AX),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_AX:				; 48h DEC AX
	ld	hl,(R_AX)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_AX),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_AX:				; 58h POP AX: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_AX),de	; into AX
	jp	(ix)		; next instruction
O_INC_CX:				; 41h INC CX
	ld	hl,(R_CX)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_CX),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_CX:				; 49h DEC CX
	ld	hl,(R_CX)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_CX),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_CX:				; 59h POP CX: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_CX),de	; into CX
	jp	(ix)		; next instruction
O_INC_DX:				; 42h INC DX
	ld	hl,(R_DX)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_DX),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_DX:				; 4Ah DEC DX
	ld	hl,(R_DX)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_DX),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_DX:				; 5Ah POP DX: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_DX),de	; into DX
	jp	(ix)		; next instruction
O_INC_BX:				; 43h INC BX
	ld	hl,(R_BX)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_BX),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_BX:				; 4Bh DEC BX
	ld	hl,(R_BX)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_BX),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_BX:				; 5Bh POP BX: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_BX),de	; into BX
	jp	(ix)		; next instruction
O_INC_SP:				; 44h INC SP
	ld	hl,(R_SP)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_SP),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_SP:				; 4Ch DEC SP
	ld	hl,(R_SP)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_SP),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_SP:				; 5Ch POP SP: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; SP+2 here, overwritten below
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_SP),de	; SP = the popped word, as on an 8086
	jp	(ix)		; next instruction
O_INC_BP:				; 45h INC BP
	ld	hl,(R_BP)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_BP),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_BP:				; 4Dh DEC BP
	ld	hl,(R_BP)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_BP),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_BP:				; 5Dh POP BP: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_BP),de	; into BP
	jp	(ix)		; next instruction
O_INC_SI:				; 46h INC SI
	ld	hl,(R_SI)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_SI),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_SI:				; 4Eh DEC SI
	ld	hl,(R_SI)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_SI),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_SI:				; 5Eh POP SI: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_SI),de	; into SI
	jp	(ix)		; next instruction
O_INC_DI:				; 47h INC DI
	ld	hl,(R_DI)	; the register into HL
	call	INC16		; HL+1; CF kept, S Z OF A' set, AF = 0
	ld	(R_DI),hl	; back to REGS
	jp	(ix)		; next instruction
O_DEC_DI:				; 4Fh DEC DI
	ld	hl,(R_DI)	; the register into HL
	call	DEC16		; HL-1; CF kept, S Z OF A' set, AF = 0
	ld	(R_DI),hl	; back to REGS
	jp	(ix)		; next instruction
O_POP_DI:				; 5Fh POP DI: POPDE inline
	ld	hl,(R_SP)	; DE = SS base + SP, byte by byte so that
	ld	a,(B_SS)	;   HL keeps SP for the increment
	add	a,l		; base low + SP low
	ld	e,a		; low byte of the stack address
	ld	a,(B_SS+1)	; high byte of the SS base
	adc	a,h		; base high + SP high + carry
	ld	d,a		; high byte (wraps in 64K, as SS:SP does)
	inc	hl		; SP += 2 now; nothing reads SP before
	inc	hl		;   the word is fetched
	ld	(R_SP),hl	; back to REGS
	ex	de,hl		; HL -> the top of stack
	ld	e,(hl)		; DE = the word, low byte first
	inc	hl		; the high byte follows
	ld	d,(hl)		; DE complete
	ld	(R_DI),de	; into DI
	jp	(ix)		; next instruction

; ---------------------------------------------------------------------
; O_PUSH_r (50h-57h, not 54h): DE = the register, then PUSHX.  Flags
; untouched.
; ---------------------------------------------------------------------
O_PUSH_AX:				; 50h PUSH AX
	ld	de,(R_AX)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_CX:				; 51h PUSH CX
	ld	de,(R_CX)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_DX:				; 52h PUSH DX
	ld	de,(R_DX)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_BX:				; 53h PUSH BX
	ld	de,(R_BX)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_BP:				; 55h PUSH BP
	ld	de,(R_BP)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_SI:				; 56h PUSH SI
	ld	de,(R_SI)	; the word to push
	jp	PUSHX		; push it and go on
O_PUSH_DI:				; 57h PUSH DI
	ld	de,(R_DI)	; the word to push
	jp	PUSHX		; push it and go on

; O_PUSH_SP (54h): the 8086 (unlike the 80286) stores SP as it is AFTER
; the decrement, so the word pushed is SP-2 (cpu86.py does the same).
O_PUSH_SP:
	ld	hl,(R_SP)	; DE = SP - 2, the value an 8086 stores
	dec	hl
	dec	hl
	ex	de,hl		; then falls into PUSHX

; =====================================================================
; PUSHX - push DE on the 8086 stack, then on to the next instruction
; ---------------------------------------------------------------------
; Entry:  DE = word.   Exit: SP -= 2, word at SS:SP; JP (IX).
; Corrupts: A HL.
; Callers: O_PUSH_r, O_PUSH_SP (falls in), O_CALLN (E7E8h, part 05:
;          pushes the return IP).
;
; PUSHDE with its RET replaced by JP (IX): a handler whose last act is
; a push jumps here instead of CALL PUSHDE / JP (IX).
; =====================================================================
PUSHX:
	ld	hl,(R_SP)	; PUSHDE, then the next instruction
	dec	hl		; SP -= 2 first, as the 8086 does
	dec	hl
	ld	(R_SP),hl
	ld	a,(B_SS)	; HL = SS base + SP, wrapping in 64K as
	add	a,l		;   SS:SP wraps in the segment
	ld	l,a
	ld	a,(B_SS+1)	; high byte, with the carry
	adc	a,h
	ld	h,a
	ld	(hl),e		; little-endian, low byte at the lower address
	inc	hl
	ld	(hl),d		; high byte
	jp	(ix)		; next instruction

; =====================================================================
;            70h-7Fh: CONDITIONAL JUMPS (and EBh JMP short)
; =====================================================================
;
; Every Jcc handler swaps AF' in (EX AF,AF'), so the 8086 flags are in
; the live F and the Z80's own condition codes test them directly:
;    8086     Z80 test           8086     Z80 test
;    OF=1     PE (V set)         SF=1     M
;    CF=1     C                  ZF=1     Z
; PF is not in F: O_JP / O_JNP compute it from A' (OR A sets P/V to the
; parity of A).  The signed jumps test S against OF by branching on V
; first.  cpu86.py cond() is the model: k = c >> 1 selects OF, CF, ZF,
; CF|ZF, SF, PF, SF^OF, (SF^OF)|ZF, and bit 0 of the opcode inverts.
; Checked against cond() case by case: all sixteen agree.
;
; OPLO/OPHI send 60h-6Fh here too (D160h-D16Fh, D260h-D26Fh): on an
; 8086 those opcodes are undocumented aliases of 70h-7Fh, and cpu86.py
; maps range(60h, 80h) to op_jcc the same way.
;
; J_TAKE / J_NOT swap AF back before they finish, so every path leaves
; the 8086 flags in AF' untouched.  The four commonest (JB JNB JZ JNZ)
; carry their own copy of J_NOT's three instructions, saving the JR on
; the not-taken path.  BC is the host address of the displacement byte
; on entry.
; =====================================================================

; J_TAKE: the jump is taken.  Swap the 8086 flags back to AF', then
; JREL8.  Callers: the Jcc handlers, O_LOOPNZ / O_LOOPZ (part 05).
J_TAKE:
	ex	af,af'		; 8086 flags back into AF'

; =====================================================================
; O_JREL8 / JREL8 - EBh JMP short, and the taken-jump tail
; ---------------------------------------------------------------------
; Entry:  BC -> the 8-bit displacement.  Exit: BC += 1 + disp; JP (IX).
; Corrupts: A HL.
; Callers: OPLO/OPHI slot EBh, J_TAKE (falls in), O_LOOP / O_JCXZ
;          (part 05).
;
; The displacement is added to BC, the host address (CS base + IP), not
; to IP.  That is still right at a segment edge: IP wraps mod 64K, and
; so does CS base + IP in the 64K guest, so BC lands where CS:IP does.
; =====================================================================
O_JREL8:
JREL8:
	ld	a,(bc)		; the signed displacement ...
	inc	bc		; ... counted from the next instruction
	ld	l,a		; L = disp
	add	a,a		; sign into CF ...
	sbc	a,a		; ... A = FFh or 00h
	ld	h,a		; HL = disp sign-extended
	add	hl,bc		; next instruction + disp
	ld	b,h		; BC = the target
	ld	c,l
	jp	(ix)		; fetch from there

; J_NOT: not taken.  Flags back to AF', step over the displacement.
; Callers: the Jcc handlers, O_LOOPNZ / O_LOOPZ (part 05).
J_NOT:
	ex	af,af'		; 8086 flags back into AF'
	inc	bc		; skip the displacement byte
	jp	(ix)		; next instruction

O_JO:					; 70h: OF = 1
	ex	af,af'		; 8086 flags live
	jp	pe,J_TAKE	; V is OF
	jr	J_NOT		; otherwise not taken
O_JNO:					; 71h: OF = 0
	ex	af,af'		; 8086 flags live
	jp	po,J_TAKE	; V clear
	jr	J_NOT		; otherwise not taken
O_JB:					; 72h JB / JC / JNAE: CF = 1
	ex	af,af'		; 8086 flags live
	jr	c,J_TAKE	; CF is the Z80 carry
	ex	af,af'		; J_NOT inline: no JR on the fall-through
	inc	bc		; skip the displacement
	jp	(ix)		; next instruction
O_JNB:					; 73h JNB / JNC / JAE: CF = 0
	ex	af,af'		; 8086 flags live
	jr	nc,J_TAKE	; taken
	ex	af,af'		; J_NOT inline
	inc	bc		; skip the displacement
	jp	(ix)		; next instruction
O_JZ:					; 74h JZ / JE: ZF = 1
	ex	af,af'		; 8086 flags live
	jr	z,J_TAKE	; taken
	ex	af,af'		; J_NOT inline
	inc	bc		; skip the displacement
	jp	(ix)		; next instruction
O_JNZ:					; 75h JNZ / JNE: ZF = 0
	ex	af,af'		; 8086 flags live
	jr	nz,J_TAKE	; taken
	ex	af,af'		; J_NOT inline
	inc	bc		; skip the displacement
	jp	(ix)		; next instruction
O_JBE:					; 76h JBE / JNA: CF = 1 or ZF = 1
	ex	af,af'		; 8086 flags live
	jr	c,J_TAKE	; either one takes it
	jr	z,J_TAKE	; taken
	jr	J_NOT		; otherwise not taken
O_JA:					; 77h JA / JNBE: CF = 0 and ZF = 0
	ex	af,af'		; 8086 flags live
	jr	c,J_NOT		; either one refuses it
	jr	z,J_NOT	; not taken
	jr	J_TAKE		; otherwise taken
O_JS:					; 78h: SF = 1
	ex	af,af'		; 8086 flags live
	jp	m,J_TAKE	; S is SF
	jr	J_NOT		; otherwise not taken
O_JNS:					; 79h: SF = 0
	ex	af,af'		; 8086 flags live
	jp	p,J_TAKE	; taken
	jr	J_NOT		; otherwise not taken

; 7Ah JP / JPE and 7Bh JNP / JPO: the lazy PF.  OR A on A' (the low
; byte of the last result, or the 0 / 1 that SETF leaves after POPF /
; SAHF) puts its parity in P/V; PUSH / POP keeps the real F intact.
O_JP:					; 7Ah: PF = 1, even parity
	ex	af,af'		; A = A', F = the 8086 flags
	push	af		; keep the 8086 flags ...
	or	a		; ... while P/V becomes the parity of A'
	jp	po,JPAR_NOT	; odd: PF = 0, not taken
	pop	af		; F = 8086 flags again
	jr	J_TAKE		; otherwise taken
O_JNP:					; 7Bh: PF = 0, odd parity
	ex	af,af'		; A = A', F = the 8086 flags
	push	af		; keep them
	or	a		; P/V = parity of A'
	jp	pe,JPAR_NOT	; even: PF = 1, not taken
	pop	af		; F = 8086 flags again
	jr	J_TAKE		; otherwise taken
JPAR_NOT:				; (src: JP1)
	pop	af		; the 8086 flags back in F for J_NOT
	jr	J_NOT		; otherwise not taken

; Signed jumps: V (OF) decides which way S is read.
O_JL:					; 7Ch JL / JNGE: SF != OF
	ex	af,af'	; S != OF
	jp	pe,JL_OF_SET	; OF = 1: take when SF = 0
	jp	m,J_TAKE	; OF = 0: take when SF = 1
	jr	J_NOT		; otherwise not taken
JL_OF_SET:				; (src: JL1) - O_JLE joins here
	jp	p,J_TAKE	; OF = 1 and SF = 0: less
	jr	J_NOT		; otherwise not taken
O_JGE:					; 7Dh JGE / JNL: SF = OF
	ex	af,af'		; 8086 flags live
	jp	pe,JGE_OF_SET	; OF = 1: take when SF = 1
	jp	p,J_TAKE	; OF = 0: take when SF = 0
	jr	J_NOT		; otherwise not taken
JGE_OF_SET:				; (src: JGE1) - O_JG joins here
	jp	m,J_TAKE	; OF = 1 and SF = 1: not less
	jr	J_NOT		; otherwise not taken
O_JLE:					; 7Eh JLE / JNG: ZF = 1 or SF != OF
	ex	af,af'		; 8086 flags live
	jp	z,J_TAKE	; equal: taken (the source's JR Z, relaxed
					;   to JP: J_TAKE is out of JR range)
	jp	pe,JL_OF_SET	; otherwise as JL
	jp	m,J_TAKE	; taken
	jp	J_NOT		; the source's JR, relaxed to JP
O_JG:					; 7Fh JG / JNLE: ZF = 0 and SF = OF
	ex	af,af'		; 8086 flags live
	jp	z,J_NOT		; equal: not taken (JR Z relaxed to JP)
	jp	pe,JGE_OF_SET	; otherwise as JGE
	jp	p,J_TAKE	; taken
	jp	J_NOT		; the source's JR, relaxed to JP

; =====================================================================
;            80h-83h: IMMEDIATE GROUP (ADD OR ADC SBB AND SUB XOR CMP)
; =====================================================================
;
; SELF-MODIFYING.  The reg field of the ModR/M byte (bits 5-3, op
; 0-7) picks the ALU routine: each handler masks it (AND 38h = op*8),
; scales it to the slot size and stores it as the LOW byte of its own
; JP below (G80J / G81J / G83J); the high byte stays the page of the
; core.  BCORE (D500h) has 16-byte slots: op*16 = (op*8)*2.  WCORE
; (D600h) has 32-byte slots: op*32 = (op*8)*4.  The slot code finds
; HL = operand pointer, E (or DE) = the immediate, does the operation,
; writes the result back (not CMP), sets AF' and ends JP (IX).
; The EA is decoded before the immediate is fetched because the
; displacement bytes come first in the instruction (and EAMEM uses DE).
; Mirrors cpu86.py op_grp1 / alu().
; =====================================================================

; O_GRP80 - 80h and 82h (OPLO/OPHI send both here): r/m8, imm8.
; Corrupts A DE HL (and whatever the BCORE slot uses).
O_GRP80:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; past it
	push	af		; kept across the EA decode
	call	EAB		; HL -> the r/m8 operand (REGS or guest)
	pop	af		; ModR/M again
	and	38h		; op * 8 ...
	add	a,a		; ... * 16: BCORE slot offset
	ld	(G80J+1),a	; PATCH: low byte of the JP below
	ld	a,(bc)		; E = imm8 (after any displacement)
	inc	bc		; past it
	ld	e,a
G80J:
	jp	BCORE		; PATCHED: BCORE + op*16 (ADD at D500h ...
					;   CMP at D570h)

; O_GRP81 - 81h: r/m16, imm16.  Corrupts A DE HL.
O_GRP81:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across the EA decode
	call	EAW		; HL -> the r/m16 operand
	pop	af		; ModR/M back
	and	38h		; op * 8 ...
	add	a,a
	add	a,a		; ... * 32: WCORE slot offset
	ld	(G81J+1),a	; PATCH: low byte of the JP below
	ld	a,(bc)		; DE = imm16, low byte first
	ld	e,a
	inc	bc		; past it
	ld	a,(bc)		; high byte
	ld	d,a
	inc	bc		; BC -> next instruction
G81J:
	jp	WCORE		; PATCHED: WCORE + op*32 (ADD at D600h ...
					;   CMP at D6E0h)

; O_GRP83 - 83h: r/m16, imm8 sign-extended to 16 bits.  Corrupts A DE HL.
O_GRP83:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across the EA decode
	call	EAW		; HL -> the r/m16 operand
	pop	af		; ModR/M back
	and	38h		; op * 32, as O_GRP81
	add	a,a
	add	a,a
	ld	(G83J+1),a	; PATCH: low byte of the JP below
	ld	a,(bc)		; E = imm8 ...
	inc	bc		; past it
	ld	e,a
	add	a,a		; ... D = its sign (FFh / 00h)
	sbc	a,a
	ld	d,a
G83J:
	jp	WCORE		; PATCHED: WCORE + op*32

; =====================================================================
;            84h-8Fh: TEST, XCHG, MOV, LEA, MOV sreg, POP r/m16
; =====================================================================
;
; MRB / MRW (ModR/M decode, part 02) return HL -> the r/m operand
; (guest memory or REGS) and DE -> the reg operand (always in the REGS
; page).  So a word's second byte is INC HL on the r/m side (it may
; cross a page in guest memory) but INC E on the reg side (REGS offsets
; never cross D0FFh).  A word at offset FFFFh: HL+1 wraps to the
; segment base in the 64K guest exactly as the 8086 offset wraps in
; the segment, so no special case is needed.
; =====================================================================

; O_TEST84 - 84h TEST r/m8, reg8: AND for the flags only.
; ADD A,0 after the AND rebuilds F the 8086 way: the Z80's AND sets
; P/V to the parity and H to 1, but the 8086 wants OF = 0 and AF = 0
; (cpu86 alu() op 4); ADD A,0 keeps S Z, clears V H C.  A' = result.
O_TEST84:
	call	MRB		; HL -> r/m8, DE -> reg8
	ld	a,(de)
	and	(hl)		; the AND, result not stored
	add	a,0		; F: S Z from it, OF = AF = CF = 0
	ex	af,af'		; A' = result (PF), F' = flags
	jp	(ix)		; next instruction

; O_TEST85 - 85h TEST r/m16, reg16: AND both bytes into DE, then LOGF16
; (BCORE page: S Z from DE, OF = CF = AF = 0, A' = low byte).
O_TEST85:
	call	MRW		; HL -> r/m16, DE -> reg16
	ld	a,(de)		; low bytes
	and	(hl)
	inc	hl		; r/m side may cross a page
	inc	e		; reg side never does
	push	af		; hold the low result
	ld	a,(de)		; high bytes
	and	(hl)
	ld	d,a
	pop	af
	ld	e,a		; DE = the 16-bit AND
	jp	LOGF16		; flags, then JP (IX)

; O_XCHG86 - 86h XCHG r/m8, reg8 (flags untouched).
O_XCHG86:
	call	MRB		; HL -> r/m8, DE -> reg8
	ld	a,(de)		; swap through A and the stack
	push	af
	ld	a,(hl)
	ld	(de),a		; r/m -> reg
	pop	af
	ld	(hl),a		; old reg -> r/m
	jp	(ix)		; next instruction

; O_XCHG87 - 87h XCHG r/m16, reg16: two byte swaps.
O_XCHG87:
	call	MRW		; HL -> r/m16, DE -> reg16
	ld	a,(de)		; low bytes
	push	af
	ld	a,(hl)
	ld	(de),a
	pop	af
	ld	(hl),a
	inc	hl		; r/m: may cross a page
	inc	e		; reg: never
	ld	a,(de)		; high bytes
	push	af
	ld	a,(hl)
	ld	(de),a
	pop	af
	ld	(hl),a
	jp	(ix)		; next instruction

; O_MOV88 - 88h MOV r/m8, reg8.
O_MOV88:
	call	MRB		; HL -> r/m8, DE -> reg8
	ld	a,(de)		; reg -> r/m
	ld	(hl),a
	jp	(ix)		; next instruction

; O_MOV89 - 89h MOV r/m16, reg16.
O_MOV89:
	call	MRW		; HL -> r/m16, DE -> reg16
	ld	a,(de)		; reg -> r/m, low byte
	ld	(hl),a
	inc	hl		; r/m: may cross a page
	inc	e		; reg: never
	ld	a,(de)		; high byte
	ld	(hl),a
	jp	(ix)		; next instruction

; O_MOV8A - 8Ah MOV reg8, r/m8.
O_MOV8A:
	call	MRB		; HL -> r/m8, DE -> reg8
	ld	a,(hl)		; r/m -> reg
	ld	(de),a
	jp	(ix)		; next instruction

; O_MOV8B - 8Bh MOV reg16, r/m16.
O_MOV8B:
	call	MRW		; HL -> r/m16, DE -> reg16
	ld	a,(hl)		; r/m -> reg, low byte
	ld	(de),a
	inc	hl		; r/m: may cross a page
	inc	e		; reg: never
	ld	a,(hl)		; high byte
	ld	(de),a
	jp	(ix)		; next instruction

; O_MOV8C - 8Ch MOV r/m16, sreg.  The reg field's low two bits pick ES
; CS SS DS (reg 4-7 alias 0-3, as cpu86.py's m[0] & 3); the segment
; registers sit at R_ES + 2*sreg in REGS.  Corrupts A DE HL.
O_MOV8C:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across the EA decode
	call	EAW		; HL -> the r/m16 destination
	pop	af		; ModR/M back
	rrca			; reg field -> bits 2-1: 2 * (sreg & 3)
	rrca
	and	06h
	add	a,0FFh&R_ES	; DE -> R_ES + 2*sreg (operand guarded:
	ld	e,a		;   rule 3, R_ES would lex as register R)
	ld	d,REGS>>8
	ld	a,(de)		; copy the segment value, low byte first
	ld	(hl),a
	inc	hl		; r/m: may cross a page
	inc	e		; REGS: never
	ld	a,(de)		; high byte
	ld	(hl),a
	jp	(ix)		; next instruction

; =====================================================================
; O_LEA - 8Dh LEA reg16, mem: the offset of the operand, not its value
; ---------------------------------------------------------------------
; Entry:  BC -> ModR/M.  Exit: reg16 = offset; JP (IX).
; Corrupts: A DE HL.
; Callers: OPLO/OPHI slot 8Dh.
;
; EAMEM returns a HOST address: the offset plus EADS or EASS.  Zeroing
; both bases first leaves the bare 16-bit offset, which is the answer;
; then they are put back from B_DS / B_SS.  That drops a segment
; override early, harmlessly: LEA ignores segments, and the override's
; restore routine (IX) puts the same bases back after the instruction.
; mod = 3 (LEA reg,reg, undefined on an 8086) stores 0, as cpu86.py,
; whose modrm() returns offset 0 for a register operand.
; =====================================================================
O_LEA:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept for the reg field
	ld	hl,0		; the result for mod = 3, and the zero bases
	cp	0C0h		; register operand?
	jr	nc,LEA_STORE	; LEA r,reg: 0, as cpu86
	ld	(EADS),hl	; no base: EAMEM yields the bare offset
	ld	(EASS),hl
	call	EAMEM		; HL = offset (ModR/M still in A)
	ld	de,(B_DS)	; the normal bases back
	ld	(EADS),de
	ld	de,(B_SS)
	ld	(EASS),de
LEA_STORE:				; (src: LEA1)
	pop	af		; ModR/M
	rrca			; reg field -> 2*reg = the low byte of R_reg
	rrca
	and	0Eh
	ld	e,a
	ld	d,REGS>>8	; DE -> the destination register
	ex	de,hl		; HL -> register, DE = offset
	ld	(hl),e		; reg16 = the offset
	inc	l		; REGS: never crosses
	ld	(hl),d
	jp	(ix)		; next instruction

; =====================================================================
; O_MOV8E - 8Eh MOV sreg, r/m16
; ---------------------------------------------------------------------
; Entry:  BC -> ModR/M.  Exit: the segment register and its base set;
;         JP (IX) (through FARJ for CS).
; Corrupts: A DE HL.
; Callers: OPLO/OPHI slot 8Eh.
;
; SETSEG (part 02) stores the value, its base (value * 16) and, for DS
; or SS, the operand base EADS / EASS.  MOV CS works on an 8086 (no
; real code uses it); here it must move BC, the host address of the
; next code byte, to the new CS base with IP unchanged: GETIP turns BC
; back into IP, FARJ jumps to CS:IP.  reg 4-7 alias 0-3, as cpu86.py.
; =====================================================================
O_MOV8E:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across the EA decode
	call	EAW		; HL -> the r/m16 source
	pop	af		; ModR/M back
	ld	e,(hl)		; DE = the new segment value
	inc	hl
	ld	d,(hl)
	rrca			; A = 2 * (sreg & 3), SETSEG's argument
	rrca
	and	06h
	cp	2		; CS?
	jr	z,MOVCS
	call	SETSEG		; ES / SS / DS with base
	jp	(ix)		; next instruction
MOVCS:
	push	de	; CS changes, IP stays: hold the new CS
	call	GETIP		; DE = IP (BC - CS base)
	pop	hl		; HL = new CS
	jp	FARJ		; CS:IP = HL:DE, BC rebuilt, JP (IX)

; =====================================================================
; O_POP8F - 8Fh POP r/m16
; ---------------------------------------------------------------------
; Entry:  BC -> ModR/M.  Exit: word popped into r/m16; JP (IX).
; Corrupts: A DE HL.
; Callers: OPLO/OPHI slot 8Fh.
;
; The pop comes BEFORE the EA is decoded, the order of cpu86.py
; op_pop_rm ("the address uses SP after the pop").  No 8086 addressing
; mode reads SP, so the order is visible only for 8F C4h (POP SP in
; the r/m form): SP ends as the popped word, as with 5Ch.  The reg
; field is not checked: 8F /1-/7 (undefined on an 8086) act as POP,
; as in cpu86.
; =====================================================================
O_POP8F:
	call	POPDE		; DE = the word, SP += 2 first
	push	de		; kept across the EA decode
	ld	a,(bc)		; then the ModR/M and its EA
	inc	bc		; past it
	call	EAW		; HL -> the r/m16 destination
	pop	de
	ld	(hl),e		; store the popped word
	inc	hl
	ld	(hl),d
	jp	(ix)		; next instruction
; =====================================================================
;            OPCODES 90h-AFh: XCHG / CBW / CWD / CALL FAR / FLAGS /
;            MOV ACC<->MOFFS / TEST ACC / THE STRING INSTRUCTIONS / REP
; =====================================================================
;
; Every handler here is entered from NEXT (or NEXT2 / DISPA after a
; prefix) through the split opcode tables OPLO/OPHI, with A = the opcode
; and BC = the host address of the byte after it.  Every one ends with
; JP (IX): normally NEXT, or RESTORE for the one instruction after a
; segment override.  The 8086 flags live in AF' (S Z AF OF CF in the
; Z80's S Z H V C, A' = low byte of the last result for PF), so a
; handler that sets flags builds them in AF and ends with EX AF,AF'.
; All of it mirrors cpu86.py's op_xchg_ax ... op_string one for one; the
; one divergence found is REP MOVSW with overlapping operands one byte
; apart (R_MOVSW, notes/z86_part04_findings.md).

; =====================================================================
; O_XCHGA - 91h-97h  XCHG AX,r16
; ---------------------------------------------------------------------
; Entry:  A = opcode (low 3 bits = the register: CX DX BX SP BP SI DI).
; Exit:   AX and r16 swapped; flags untouched.   Corrupts A, DE, HL.
; 90h (XCHG AX,AX) is routed to O_NOP by the tables, not here - though
; this code would do it correctly too.  Mirrors cpu86.py op_xchg_ax.
; =====================================================================
O_XCHGA:
	and	7		; register number 0-7 ...
	add	a,a		; ... times 2 = its offset in REGS (AX CX DX BX
	ld	l,a		;   SP BP SI DI are words 0-7 of a page-aligned
	ld	h,REGS>>8	;   block), so HL points straight at it
	ld	e,(hl)		; DE = the other register's old value
	inc	l		;   (INC L: never crosses the page)
	ld	d,(hl)		; (the register's high byte)
	ld	a,(R_AH)	; old AX into it, high byte first since HL is
	ld	(hl),a		;   already on it
	dec	l		; back to its low byte
	ld	a,(R_AL)	; then the low byte
	ld	(hl),a		; low byte of old AX stored
	ld	(R_AX),de	; and its old value into AX
	jp	(ix)		; next instruction

; =====================================================================
; O_CBW - 98h  CBW: AH = sign of AL.   O_CWD - 99h  CWD: DX = sign of AX
; ---------------------------------------------------------------------
; The ADD A,A / SBC A,A pair turns bit 7 into 00h or FFh in two bytes.
; Flags are untouched (only the Z80's main F is used).  Corrupt A.
; Mirror cpu86.py op_cbw / op_cwd.
; =====================================================================
O_CBW:
	ld	a,(R_AL)	; sign source: AL's bit 7
	add	a,a		; AL's sign -> carry
	sbc	a,a		; 00h or FFh
	ld	(R_AH),a	; AH = AL's sign extension
	jp	(ix)		; (main F only: the 8086 flags stay in AF')

O_CWD:
	ld	a,(R_AH)	; AX's sign is AH's bit 7
	add	a,a		; -> carry
	sbc	a,a		; 0000h or FFFFh, a byte at a time
	ld	(R_DL),a	; DX = 0000h / FFFFh
	ld	(R_DH),a	; (AX itself unchanged)
	jp	(ix)		; next instruction

; =====================================================================
; O_CALLF - 9Ah  CALL FAR ptr16:16
; ---------------------------------------------------------------------
; Entry:  BC -> the 4 immediate bytes (offset, then segment).
; Exit:   old CS and the return IP pushed on the 8086 stack (CS first,
;         as an 8086 does), then FARJ: CS:IP = the target, BC rebuilt.
; Corrupts A, DE, HL; two words pass through the Z80 stack.
; The new IP and CS are parked on the Z80 stack because PUSHDE and
; GETIP both use DE/HL.  GETIP runs after the immediates are consumed,
; so it yields the address of the next instruction - the return IP.
; Mirrors cpu86.py op_call_far.
; =====================================================================
O_CALLF:
	ld	a,(bc)		; DE = target offset, from the code stream
	ld	e,a		; low byte
	inc	bc		; next immediate byte
	ld	a,(bc)		; high byte
	ld	d,a		; (DE = offset)
	inc	bc		; on to the segment word
	push	de		; new IP, kept for FARJ
	ld	a,(bc)		; DE = target segment
	ld	e,a		; low byte
	inc	bc		; next immediate byte
	ld	a,(bc)		; high byte
	ld	d,a		; (DE = segment)
	inc	bc		; BC now past the instruction
	push	de		; new CS, kept for FARJ
	ld	de,(R_CS)	; push the caller's CS ...
	call	PUSHDE		; [SS:SP-2] = old CS
	call	GETIP		; ... then its return IP (BC - CS base)
	call	PUSHDE		; [SS:SP-2] = return IP
	pop	hl		; FARJ takes HL = CS, DE = IP
	pop	de		; DE = new IP
	jp	FARJ		; sets CS and its base, BC = new CS:IP

; =====================================================================
; O_PUSHF - 9Ch  PUSHF.   O_POPF - 9Dh  POPF
; ---------------------------------------------------------------------
; GETF assembles the 16-bit FLAGS from AF' and FLAGHI (bits 12-15 set
; and bit 1 set, as an 8086 pushes them); SETF splits a word back into
; AF', FLAGHI and STEP1/STEP2 (the direction flag's strides, used by
; every string handler below).  Corrupt A, DE, HL.
; Mirror cpu86.py's 9Ch lambda and op_popf.
; =====================================================================
O_PUSHF:
	call	GETF		; HL = FLAGS
	ex	de,hl		; PUSHDE pushes DE
	call	PUSHDE		; [SS:SP-2] = FLAGS
	jp	(ix)		; next instruction

O_POPF:
	call	POPDE		; DE = the popped word
	ex	de,hl		; SETF takes HL
	call	SETF		; flags, TF IF DF, and the string strides
	jp	(ix)		; next instruction

; =====================================================================
; O_SAHF - 9Eh  SAHF.   O_LAHF - 9Fh  LAHF
; ---------------------------------------------------------------------
; Both go through the full 16-bit FLAGS word so that GETF/SETF stay the
; only code that knows how AF' packs PF and OF.  SAHF keeps H (OF, DF,
; IF, TF) as it was, so SETF rewrites FLAGHI and the strides with their
; own values.  Corrupt A, DE, HL.  Mirror cpu86.py op_sahf / op_lahf.
; =====================================================================
O_SAHF:
	call	GETF		; HL = FLAGS
	ld	a,(R_AH)	; low byte (SF ZF AF PF CF) replaced by AH
	ld	l,a		; (H = OF DF IF TF kept)
	call	SETF		; high byte (OF DF IF TF) written back as found
	jp	(ix)		; next instruction

O_LAHF:
	call	GETF		; L = SF ZF - AF - PF 1 CF
	ld	a,l		; low byte of FLAGS
	and	0D5h		; keep SF ZF AF PF CF, force bit 1: copied from
	or	2		;   cpu86.py's `flags & 0xD5 | 2`; GETF's L
					;   already has that form, so a no-op here
	ld	(R_AH),a	; AH = low byte of FLAGS
	jp	(ix)		; next instruction

; =====================================================================
; O_MOVA0..O_MOVA3 - A0h-A3h  MOV AL/AX <-> [moffs16]
; ---------------------------------------------------------------------
; Entry:  BC -> the 16-bit offset.   Corrupt A, DE, HL.
;   A0h  MOV AL,[moffs]      A1h  MOV AX,[moffs]
;   A2h  MOV [moffs],AL      A3h  MOV [moffs],AX
; The segment is DS unless overridden: EADS holds whichever base is in
; force.  The word forms read/write base+off and base+off+1 with plain
; 16-bit Z80 arithmetic; in a 64K host that wraps exactly as the 8086's
; offset does at FFFFh (cpu86.py rw/ww), so offset FFFFh needs no case.
; Mirror cpu86.py op_mov_moffs.
; =====================================================================
O_MOVA0:
	ld	a,(bc)		; HL = the offset from the code stream
	ld	l,a		; offset, low byte
	inc	bc		; next byte
	ld	a,(bc)		; offset, high byte
	ld	h,a		; (HL = moffs16)
	inc	bc		; BC past the instruction
	ld	de,(EADS)	; + DS base (or the override's)
	add	hl,de		; = host address of the operand
	ld	a,(hl)		; AL = the byte there
	ld	(R_AL),a	; (AH untouched)
	jp	(ix)		; next instruction
O_MOVA1:
	ld	a,(bc)		; HL = the offset from the code stream
	ld	l,a		; offset, low byte
	inc	bc		; next byte
	ld	a,(bc)		; offset, high byte
	ld	h,a		; (HL = moffs16)
	inc	bc		; BC past the instruction
	ld	de,(EADS)	; + DS base (or the override's)
	add	hl,de		; = host address of the operand
	ld	e,(hl)		; AX = the word there
	inc	hl		; (byte at offset+1: wraps with HL)
	ld	d,(hl)		; high byte
	ld	(R_AX),de	; AX = [moffs]
	jp	(ix)		; next instruction
O_MOVA2:
	ld	a,(bc)		; HL = the offset from the code stream
	ld	l,a		; offset, low byte
	inc	bc		; next byte
	ld	a,(bc)		; offset, high byte
	ld	h,a		; (HL = moffs16)
	inc	bc		; BC past the instruction
	ld	de,(EADS)	; + DS base (or the override's)
	add	hl,de		; = host address of the operand
	ld	a,(R_AL)	; the byte there = AL
	ld	(hl),a		; [moffs] = AL
	jp	(ix)		; next instruction
O_MOVA3:
	ld	a,(bc)		; HL = the offset from the code stream
	ld	l,a		; offset, low byte
	inc	bc		; next byte
	ld	a,(bc)		; offset, high byte
	ld	h,a		; (HL = moffs16)
	inc	bc		; BC past the instruction
	ld	de,(EADS)	; + DS base (or the override's)
	add	hl,de		; = host address of the operand
	ld	de,(R_AX)	; the word there = AX, low byte first
	ld	(hl),e		; [moffs] = AL
	inc	hl		; (offset+1, wrapping as on the 8086)
	ld	(hl),d		; [moffs+1] = AH
	jp	(ix)		; next instruction

; =====================================================================
; O_TESTA8 - A8h  TEST AL,imm8.   O_TESTA9 - A9h  TEST AX,imm16
; ---------------------------------------------------------------------
; Flags only: SF ZF PF from AL/AX AND imm, OF = CF = AF = 0 (cpu86.py
; alu op 4, via op_test_acc).  The Z80's AND sets H, which here means
; AF = 1, so the 8-bit form follows it with ADD A,0: same S Z and
; result, H = V = C = 0.  The 16-bit form leaves that to LOGF16
; (ADC HL,0 on the result for S Z, A' = low byte for PF).
; Corrupt A, DE, HL.  REP before A8h/A9h comes here via R_NOTSTR.
; =====================================================================
O_TESTA8:
	ld	a,(bc)		; imm8
	inc	bc		; BC past the instruction
	ld	e,a		; E = the mask
	ld	a,(R_AL)	; AL is only read: TEST stores nothing
	and	e		; the result: S Z right, but H = 1 ...
	add	a,0		; ... so recompute with AF = OF = CF = 0
	ex	af,af'		; result and flags become the 8086's
	jp	(ix)		; next instruction
O_TESTA9:
	ld	a,(bc)		; low byte of imm16 ...
	inc	bc		; next immediate byte
	ld	hl,R_AL		; HL -> AL in REGS
	and	(hl)		; ... AND AL
	ld	e,a		; E = low byte of the result
	ld	a,(bc)		; high byte ...
	inc	bc		;   (BC past the instruction)
	inc	l		; (R_AH is R_AL+1, same page)
	and	(hl)		; ... AND AH
	ld	d,a		; DE = AX AND imm16
	jp	LOGF16		; flags of a 16-bit logic result, then JP (IX)

; =====================================================================
; STRING OPERAND HELPERS
; ---------------------------------------------------------------------
; SRCPTR: HL = host address of DS:SI.  The source segment follows a
;         segment override (EADS), as on the 8086.
; DSTPTR: HL = host address of ES:DI.  ES is never overridden (B_ES).
;         Both corrupt DE and the main F; A and BC survive.
; SI_STEP_B / DI_STEP_B: SI / DI += STEP1 (+1, or -1 when DF = 1).
; SI_STEP_W / DI_STEP_W: SI / DI += STEP2 (+2 / -2), word forms.
;         All four corrupt DE, HL and the main F; AF' is untouched, so
;         they may follow a compare that has just set the 8086 flags.
; STEP1/STEP2 are written by SETSTEP whenever DF changes (SETF, CLD,
; STD, START), so no handler tests DF just to step a pointer.
; Callers: every handler from O_MOVSB to R_SCASW (internal to this part).
; =====================================================================
SRCPTR:
	ld	hl,(R_SI)	; offset
	ld	de,(EADS)	; + DS base, or the override's
	add	hl,de		; (mod 64K: the host has no more)
	ret			; HL = host DS:SI
DSTPTR:
	ld	hl,(R_DI)	; offset
	ld	de,(B_ES)	; + ES base: no override applies to DI
	add	hl,de		; HL = host ES:DI
	ret			; (DE = ES base on return)
SI_STEP_B:				; (src: NSI1)
	ld	hl,(R_SI)	; SI ...
	ld	de,(STEP1)	; +1 / -1 by DF
	add	hl,de		; ... stepped
	ld	(R_SI),hl	; offsets wrap at 64K, as the 8086's do
	ret			; (main F changed, AF' not)
DI_STEP_B:				; (src: NDI1)
	ld	hl,(R_DI)	; DI ...
	ld	de,(STEP1)	; +1 / -1 by DF
	add	hl,de		; ... stepped
	ld	(R_DI),hl	; offsets wrap at 64K
	ret			; (main F changed, AF' not)
SI_STEP_W:				; (src: NSI2)
	ld	hl,(R_SI)	; SI ...
	ld	de,(STEP2)	; +2 / -2 by DF
	add	hl,de		; ... stepped by two
	ld	(R_SI),hl	; offsets wrap at 64K
	ret			; (main F changed, AF' not)
DI_STEP_W:				; (src: NDI2)
	ld	hl,(R_DI)	; DI ...
	ld	de,(STEP2)	; +2 / -2 by DF
	add	hl,de		; ... stepped by two
	ld	(R_DI),hl	; offsets wrap at 64K
	ret			; (main F changed, AF' not)

; =====================================================================
; THE STRING INSTRUCTIONS, ONE ITERATION (no REP prefix)
; ---------------------------------------------------------------------
;   A4h MOVSB  A5h MOVSW   [ES:DI] = [DS:SI], SI and DI stepped
;   A6h CMPSB  A7h CMPSW   flags of [DS:SI] - [ES:DI], both stepped
;   AAh STOSB  ABh STOSW   [ES:DI] = AL/AX, DI stepped
;   ACh LODSB  ADh LODSW   AL/AX = [DS:SI], SI stepped
;   AEh SCASB  AFh SCASW   flags of AL/AX - [ES:DI], DI stepped
; The compares are split into a body (CMPSB_STEP, CMPSW_STEP,
; SCASB_STEP, SCASW_STEP: one iteration, returns) and an O_ wrapper, so
; the REP loops below can call the same body.  Word compares take AF
; from bit 11 (SBC HL,DE), the interpreter's one known difference
; (OVERVIEW 2.2; fuzz_z86.py af_loose allows it for A7h/AFh).
; Corrupt A, DE, HL (and TMP for CMPSB_STEP).  Mirror cpu86.py
; op_string with rep = 0.
; =====================================================================
O_MOVSB:
	call	SRCPTR		; HL -> DS:SI
	ld	a,(hl)		; the byte at DS:SI
	push	af		; (needless: DSTPTR keeps A)
	call	DSTPTR		; HL -> ES:DI
	pop	af		; A = the byte again
	ld	(hl),a		; to ES:DI
	call	SI_STEP_B	; both pointers by +-1
	call	DI_STEP_B	; (SI first, then DI: order immaterial)
	jp	(ix)		; next instruction
O_MOVSW:
	call	SRCPTR		; HL -> DS:SI
	ld	a,(hl)		; HL = the word at DS:SI
	inc	hl		; high byte
	ld	h,(hl)		; H = [SI+1]
	ld	l,a		; L = [SI]
	push	hl		; kept over DSTPTR, which uses DE and HL
	call	DSTPTR		; HL -> ES:DI
	pop	de		; DE = the word
	ld	(hl),e		; to ES:DI, low byte first
	inc	hl		; (DI+1)
	ld	(hl),d		; high byte
	call	SI_STEP_W	; both pointers by +-2
	call	DI_STEP_W	; (MOVS sets no flags)
	jp	(ix)		; next instruction

; CMPSB_STEP - one CMPSB: flags of [DS:SI] - [ES:DI], SI and DI stepped.
; Callers: O_CMPSB, R_CMPSB.
CMPSB_STEP:				; (src: CMPSB1)
	call	DSTPTR		; the subtrahend, [ES:DI], first
	ld	a,(hl)		; A = [ES:DI]
	ld	(TMP),a		; parked in TMP (A would in fact survive
	call	SRCPTR		;   SRCPTR; only DE is lost)
	ld	a,(TMP)		; A = [ES:DI] again
	ld	e,a		; E = [ES:DI]
	ld	a,(hl)		; [DS:SI] - [ES:DI]: Z80 S Z H V C are the
	sub	e		;   8086's SF ZF AF OF CF for a byte SUB
	ex	af,af'		; result and flags are now the 8086's
	call	SI_STEP_B	; the steps leave AF' alone
	jp	DI_STEP_B	; tail call: its RET returns for us
O_CMPSB:
	call	CMPSB_STEP	; one compare
	jp	(ix)		; next instruction

; CMPSW_STEP - one CMPSW.  Callers: O_CMPSW, R_CMPSW.
CMPSW_STEP:				; (src: CMPSW1)
	call	DSTPTR		; DE = the word at ES:DI ...
	ld	e,(hl)		; low byte
	inc	hl		; (DI+1)
	ld	d,(hl)		; high byte
	push	de		; ... kept over SRCPTR
	call	SRCPTR		; HL = the word at DS:SI
	ld	a,(hl)		; low byte
	inc	hl		; (SI+1)
	ld	h,(hl)		; high byte
	ld	l,a		; HL = [DS:SI]
	pop	de		; DE = [ES:DI]
	or	a		; no borrow in
	sbc	hl,de		; [DS:SI] - [ES:DI] (AF from bit 11)
	ld	a,l		; A' = low byte of the result, for PF
	ex	af,af'		; into the 8086 flags
	call	SI_STEP_W	; the steps leave AF' alone
	jp	DI_STEP_W	; tail call
O_CMPSW:
	call	CMPSW_STEP	; one compare
	jp	(ix)		; next instruction
O_STOSB:
	call	DSTPTR		; HL -> ES:DI
	ld	a,(R_AL)	; [ES:DI] = AL
	ld	(hl),a		; (STOS sets no flags)
	call	DI_STEP_B	; DI by +-1
	jp	(ix)		; next instruction
O_STOSW:
	call	DSTPTR		; HL -> ES:DI
	ld	de,(R_AX)	; [ES:DI] = AX, low byte first
	ld	(hl),e		; low byte
	inc	hl		; (DI+1)
	ld	(hl),d		; high byte
	call	DI_STEP_W	; DI by +-2
	jp	(ix)		; next instruction
O_LODSB:
	call	SRCPTR		; HL -> DS:SI
	ld	a,(hl)		; AL = [DS:SI]
	ld	(R_AL),a	; (AH untouched)
	call	SI_STEP_B	; SI by +-1
	jp	(ix)		; next instruction

; O_LODSW is SRCPTR + SI_STEP_W written out in line (SI read once, kept
; on the stack): the same result without two CALL/RET pairs.
O_LODSW:
	ld	hl,(R_SI)	; SI, the offset
	push	hl		; SI, for the step below
	ld	de,(EADS)	; host address of DS:SI (override aware)
	add	hl,de		; HL -> DS:SI
	ld	e,(hl)		; AX = the word there
	inc	hl		; (SI+1)
	ld	d,(hl)		; high byte
	ld	(R_AX),de	; AX = [DS:SI]
	pop	hl		; SI again
	ld	de,(STEP2)	; SI += 2 / -2 by DF
	add	hl,de		; stepped
	ld	(R_SI),hl	; SI = SI +-2
	jp	(ix)		; next instruction

; SCASB_STEP - one SCASB: flags of AL - [ES:DI], DI stepped.
; Callers: O_SCASB, R_SCASB (its ordinary loop, which also makes the
; CPIR path's final compare).
SCASB_STEP:				; (src: SCASB1)
	call	DSTPTR		; HL -> ES:DI
	ld	a,(R_AL)	; the byte sought
	sub	(hl)		; AL - [ES:DI], 8086 byte-SUB flags
	ex	af,af'		; into AF'
	jp	DI_STEP_B	; tail call
O_SCASB:
	call	SCASB_STEP	; one compare
	jp	(ix)		; next instruction

; SCASW_STEP - one SCASW.  Callers: O_SCASW, R_SCASW.
SCASW_STEP:				; (src: SCASW1)
	call	DSTPTR		; HL -> ES:DI
	ld	e,(hl)		; DE = the word there
	inc	hl		; (DI+1)
	ld	d,(hl)		; high byte
	ld	hl,(R_AX)	; minuend: AX
	or	a		; no borrow in
	sbc	hl,de		; AX - [ES:DI] (AF from bit 11)
	ld	a,l		; A' = low byte, for PF
	ex	af,af'		; into the 8086 flags
	jp	DI_STEP_W	; tail call
O_SCASW:
	call	SCASW_STEP	; one compare
	jp	(ix)		; next instruction

; =====================================================================
; O_REP - F2h REPNE / F3h REP(E): read on to the string instruction
; ---------------------------------------------------------------------
; Entry:  A = F2h or F3h (from the opcode table), BC -> the next byte.
; Exit:   to a REPTAB handler (A4h-AFh), or the opcode dispatched as if
;         no REP had been seen (DISPA), REPT left set but read by nobody.
; REPT keeps the prefix byte: bit 0 is the only part ever tested
; (0 = F2h REPNE, 1 = F3h REPE), and only by the compares; MOVS / STOS /
; LODS repeat on CX alone whichever of the two it was, as on an 8086.
; Prefixes that follow REP are taken here, in the order met, as
; cpu86.py step() takes them:
;   26h 2Eh 36h 3Eh  segment override -> SEGSET (bases + IX = RESTORE)
;   F2h F3h          another REP: the last one wins (back to O_REP)
;   F0h LOCK         ignored
; A segment override BEFORE the REP went through O_SEG_xx, which points
; IX at RESTORE and enters here via NEXT2; either way the REP handler's
; final JP (IX) puts the DS/SS bases back.
; =====================================================================
O_REP:
	ld	(REPT),a	; F2h / F3h: bit 0 = REPE
REP_FETCH:				; (src: REP1)
	ld	a,(bc)		; the next byte of the instruction
	inc	bc		; BC past it
	cp	0A4h		; below A4h: maybe a segment override
	jr	c,REP_TRY_SEG	; (26h 2Eh 36h 3Eh live there)
	cp	0B0h		; B0h and up: a prefix or not a string op
	jr	nc,REP_OTHER	; (F0h F2h F3h live there)
	sub	0A4h		; A4h-AFh: REPTAB[op - A4h]
	add	a,a		; word index
	ld	l,a		; HL = (op - A4h) * 2
	ld	h,0
	ld	de,REPTAB	; REPTAB base
	add	hl,de		; HL -> the entry
	ld	e,(hl)		; DE = the handler
	inc	hl		; high byte
	ld	d,(hl)
	ex	de,hl		; HL = the handler
	jp	(hl)		; to R_xxx (A not needed there)
REP_TRY_SEG:				; (src: REP2)
	ld	e,a		; keep the byte
	and	0E7h		; 26h 2Eh 36h 3Eh all reduce to 26h
	cp	26h		; the reduced form of an override
	ld	a,e		; (LD keeps the flags)
	jr	nz,REP_OTHER	; not an override
	call	SEGSET		; operand bases := that segment's, IX = RESTORE
	jr	REP_FETCH	; and read on
REP_OTHER:				; (src: REP3)
	cp	0F2h		; REPNE again: it replaces the first
	jr	z,O_REP		; (REPT rewritten)
	cp	0F3h		; REPE again: likewise
	jr	z,O_REP		; (REPT rewritten)
	cp	0F0h		; LOCK: skipped, as everywhere
	jr	z,REP_FETCH	; read on past it
	jp	DISPA		; anything else: REP has no effect, run it

; ---------------------------------------------------------------------
; REPTAB - REP handler per string opcode, indexed by (opcode - A4h) * 2
; ---------------------------------------------------------------------
REPTAB:
	defw	R_MOVSB, R_MOVSW, R_CMPSB, R_CMPSW, R_NOTSTR, R_NOTSTR
					; A4h MOVSB  A5h MOVSW  A6h CMPSB  A7h CMPSW
					; A8h TEST AL,imm8  A9h TEST AX,imm16: not
					;   string ops, REP ignored (R_NOTSTR)
	defw	R_STOSB, R_STOSW, R_LODSB, R_LODSW, R_SCASB, R_SCASW
					; AAh STOSB  ABh STOSW  ACh LODSB  ADh LODSW
					; AEh SCASB  AFh SCASW

; R_NOTSTR - A8h / A9h after REP: plain TEST (the source's gloss).  BC
; is stepped back onto the opcode and NEXT2 dispatches it afresh (to
; O_TESTA8 / O_TESTA9).
R_NOTSTR:
	dec	bc		; back onto the opcode REP_FETCH consumed
	jp	NEXT2		; and run it normally

; ---------------------------------------------------------------------
; CXNZ - HL = CX, Z80 Z set when CX = 0.   Corrupts A.
; Every R_xxx starts with it: REP with CX = 0 does nothing at all - no
; access, no step, flags untouched (cpu86.py: `if r[CX] == 0: return`).
; ---------------------------------------------------------------------
CXNZ:
	ld	hl,(R_CX)	; HL = the count, for the caller too
	ld	a,h		; Z if 0
	or	l		; Z: CX = 0
	ret			; (HL = CX for the caller)

; =====================================================================
; RADVSD / RADVD / RADVDN - finish a block REP run: advance the
; pointers in one go, CX = 0, back to the dispatcher
; ---------------------------------------------------------------------
; Entry:  DE = bytes moved (CX for byte ops, 2 * CX for word ops),
;         unsigned; DF read from STEP1's high byte.
;   RADVSD  SI and DI += DE (negated first when DF = 1)  - REP MOVS
;   RADVDN  DI += DE (negated first when DF = 1)         - REP STOS
;   RADVD   DI += DE as given, CX = 0 (RADVSD's and RADVDN's tail)
; Exit:   JP (IX).   Corrupts A, DE, HL.
; The block transfer (LDIR / LDDR) has moved Z80 HL/DE already, but
; those are host addresses; SI/DI are recomputed from the count, mod
; 64K, which is where an 8086 leaves them after CX iterations.
; Callers: R_MOVSB, R_MOVSW (RADVSD); R_STOSB, R_STOSW (RADVDN).
; =====================================================================
RADVSD:
	call	RNEG_DE		; DE = -DE if DF
	ld	hl,(R_SI)	; SI moves by the same amount ...
	add	hl,de		; SI +-= bytes moved
	ld	(R_SI),hl	; (mod 64K)
RADVD:
	ld	hl,(R_DI)	; ... and so does DI
	add	hl,de		; DI +-= bytes moved
	ld	(R_DI),hl	; (mod 64K)
	ld	hl,0		; the REP ran to the end: CX = 0
	ld	(R_CX),hl	; as an 8086 ends a full REP
	jp	(ix)		; next instruction
RADVDN:
	call	RNEG_DE		; DE = -DE if DF, then DI only
	jr	RADVD		; DI += DE, CX = 0, done

; ---------------------------------------------------------------------
; RADVS - DEAD CODE (E25Dh-E26Eh, 18 bytes).  Nothing refers to it: not
; the binary, not I86.ASM, where its only occurrence is its own label
; (notes/partition_findings.md: the one piece of listing code the
; recursive descent never reaches).  It is the SI-only sibling of
; RADVDN, the shape a block REP LODS would have needed (load the last
; element, then move SI by the count); R_LODSB/R_LODSW loop instead.
; That purpose is inferred, not documented (provisional).  Kept for
; byte identity.
; ---------------------------------------------------------------------
RADVS:
	call	RNEG_DE		; DE = -DE if DF
	ld	hl,(R_SI)	; SI += DE
	add	hl,de		; SI +-= the count
	ld	(R_SI),hl	; (mod 64K)
	ld	hl,0		; CX = 0
	ld	(R_CX),hl	; (all as RADVSD, DI excepted)
	jp	(ix)		; (never reached)

; ---------------------------------------------------------------------
; RNEG_DE - DE = -DE if DF = 1 (the source's own gloss, lost from the
; listing skeleton), else unchanged.
; DF is taken from STEP1's high byte (FFh when STEP1 = -1, 00h when +1)
; so the flag never has to be fetched from FLAGHI.  Corrupts A, F.
; Callers: RADVSD, RADVDN, RADVS (dead), the R_SCASB CPIR path.
; ---------------------------------------------------------------------
RNEG_DE:
	ld	a,(STEP1+1)	; 00h or FFh: bit 7 = DF
	rla			; -> carry
	ret	nc		; DF = 0: forward, DE stays
	xor	a		; DE = 0 - DE: low byte ...
	sub	e		; E = -E, carry = borrow
	ld	e,a		; low byte of -DE
	sbc	a,a		; ... then 0 - D - borrow (SBC A,A = -borrow)
	sub	d		; A = -D - borrow
	ld	d,a		; high byte of -DE
	ret			; (Z80 flags meaningless)

; =====================================================================
; R_MOVSB - REP MOVSB as one LDIR (DF = 0) or LDDR (DF = 1)
; ---------------------------------------------------------------------
; Entry:  from REP_FETCH; BC = 8086 IP (host).   Exit: via RADVSD.
; Byte-at-a-time copying in the direction of DF is exactly what the
; 8086 does, overlap included (DI = SI + 1 forward replicates the first
; byte, as on the 8086), so the result is identical.  The guest's
; offsets wrap at 64K just as the host's HL/DE do, since a linear
; address is base + offset mod 64K (I86.ASM preface).
; =====================================================================
R_MOVSB:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RMOVSB_GO	; CX >= 1: copy
	jp	(ix)		; next instruction
RMOVSB_GO:				; (src: RMB1)
	push	bc		; save IP: BC becomes the count
	push	hl		; count = CX bytes
	call	DSTPTR		; HL = host ES:DI
	push	hl		; host ES:DI
	call	SRCPTR		; HL = host DS:SI
	pop	de		; DE = host ES:DI
	pop	bc		; BC = CX
	ld	a,(STEP1+1)	; DF -> carry
	rla			; (STEP1+1 = FFh when DF = 1)
	jr	c,RMOVSB_DOWN	; DF = 1: downwards
	ldir			; DF = 0: upwards
	jr	RMOVSB_DONE	; (skip LDDR)
RMOVSB_DOWN:				; (src: RMB2)
	lddr			; DF = 1: downwards from SI / DI
RMOVSB_DONE:				; (src: RMB3)
	pop	bc		; IP back
	ld	de,(R_CX)	; CX bytes moved: SI, DI += +-CX, CX = 0
	jr	RADVSD		; SI, DI += +-CX; CX = 0

; =====================================================================
; R_MOVSW - REP MOVSW as one LDIR / LDDR of 2 * CX bytes
; ---------------------------------------------------------------------
; Entry/exit as R_MOVSB.  Downwards, the copy starts at the HIGH byte
; of the first word (SI+1 -> DI+1) and runs down byte by byte.
; DIVERGENCE (verified, notes/z86_part04_findings.md): a byte copy is
; not a word copy when the operands overlap by ONE byte - DI = SI + 1
; with DF = 0, or DI = SI - 1 with DF = 1.  The 8086 (and cpu86.py)
; reads each whole word before writing it; LDIR/LDDR smear the first
; byte instead.  Overlap by 2 or more, or no overlap, is identical.
; CX >= 8000h makes 2 * CX wrap (8000h -> BC = 0 = 64K, still right;
; above that, fewer bytes): beyond any 52K guest, so of no consequence.
; =====================================================================
R_MOVSW:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RMOVSW_GO	; CX >= 1: copy
	jp	(ix)		; next instruction
RMOVSW_GO:				; (src: RMW1)
	push	bc		; save IP
	add	hl,hl		; bytes = 2 * CX
	push	hl		; (2 * CX bytes)
	call	DSTPTR		; HL = host ES:DI
	push	hl		; host ES:DI
	call	SRCPTR		; HL = host DS:SI
	pop	de		; DE = host ES:DI
	pop	bc		; BC = 2 * CX
	ld	a,(STEP1+1)	; DF -> carry
	rla			; (STEP1+1 = FFh when DF = 1)
	jr	c,RMOVSW_DOWN	; DF = 1: downwards
	ldir			; DF = 0: upwards
	jr	RMOVSW_DONE	; (skip LDDR)
RMOVSW_DOWN:				; (src: RMW2)
	inc	hl		; from the high byte of the first word down
	inc	de		; (DI+1: the high byte too)
	lddr			; DF = 1: 2 * CX bytes downwards
RMOVSW_DONE:				; (src: RMW3)
	pop	bc		; IP back
	ld	hl,(R_CX)	; DE = 2 * CX bytes moved
	add	hl,hl		; (2 * CX, mod 64K)
	ex	de,hl		; into DE for RADVSD
	jp	RADVSD		; (JR in the source, relaxed to JP: 136 back)

; =====================================================================
; R_STOSB - REP STOSB: one store, then LDIR / LDDR copies it along
; ---------------------------------------------------------------------
; The first byte is written by hand; then a copy from DI to DI+1 (or
; DI-1 when DF = 1) of CX-1 bytes, each reading the byte just written:
; the classic overlapping-LDIR fill.  CX = 1 skips the copy (BC would
; be 0, which LDIR takes as 64K).  Exit via RADVDN (DI only).
; =====================================================================
R_STOSB:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RSTOSB_GO	; CX >= 1: store
	jp	(ix)		; next instruction
RSTOSB_GO:				; (src: RSB1)
	push	bc		; save IP
	push	hl		; CX
	call	DSTPTR		; HL = host ES:DI
	pop	bc		; BC = CX
	ld	a,(R_AL)	; the first byte, by hand
	ld	(hl),a		; [ES:DI] = AL
	dec	bc		; CX - 1 still to fill
	ld	a,b		; BC = 0?
	or	c
	jr	z,RSTOSB_DONE	; CX was 1: done
	ld	d,h		; DE = HL = DI ...
	ld	e,l		; (DE = HL)
	ld	a,(STEP1+1)	; DF -> carry
	rla			; (STEP1+1 = FFh when DF = 1)
	jr	c,RSTOSB_DOWN	; DF = 1: fill downwards
	inc	de		; ... DE = DI+1: each byte copies its left
	ldir			;   neighbour, so AL runs to the right
	jr	RSTOSB_DONE	; (skip LDDR)
RSTOSB_DOWN:				; (src: RSB2)
	dec	de		; DE = DI-1: AL runs to the left
	lddr			; each byte copies its right neighbour
RSTOSB_DONE:				; (src: RSB3)
	pop	bc		; IP back
	ld	de,(R_CX)	; CX bytes stored: DI += +-CX, CX = 0
	jp	RADVDN		; (JR in the source, relaxed to JP)

; =====================================================================
; R_STOSW - REP STOSW: one word by hand, LDIR / LDDR repeat it
; ---------------------------------------------------------------------
; As R_STOSB with a period of 2: the copy runs 2 bytes behind the
; destination, so it repeats the low/high pair.  Forward: HL = DI,
; DE = DI+2.  Backward: HL = DI+1, DE = DI-1, so DI+1 -> DI-1 and DI ->
; DI-2: the word at DI-2 gets low, high in the right order.  2 * CX - 2
; bytes are copied; CX = 1 skips the copy.  Exit via RADVDN.
; (CX > 8000h: 2 * CX wraps and fewer words are stored - unreachable in
; a 52K guest, as for R_MOVSW.)
; =====================================================================
R_STOSW:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RSTOSW_GO	; CX >= 1: store
	jp	(ix)		; next instruction
RSTOSW_GO:				; (src: RSW1)
	push	bc		; save IP
	add	hl,hl		; bytes = 2 * CX
	push	hl		; (2 * CX bytes)
	call	DSTPTR		; HL = host ES:DI
	pop	bc		; BC = 2 * CX
	ld	de,(R_AX)	; the first word, by hand
	ld	(hl),e		; [ES:DI] = AL
	inc	hl		; (DI+1)
	ld	(hl),d		; HL = DI + 1
	dec	bc		; 2 * CX - 2 bytes still to fill
	dec	bc		; (BC >= 2 here, as CX >= 1)
	ld	a,b		; BC = 0?
	or	c
	jr	z,RSTOSW_DONE	; CX was 1: done
	ld	d,h		; DE = DI + 1
	ld	e,l		; (DE = HL)
	ld	a,(STEP1+1)	; DF -> carry
	rla			; (STEP1+1 = FFh when DF = 1)
	jr	c,RSTOSW_DOWN	; DF = 1: fill downwards
	inc	de		; DI+1 -> DI+2 ... from DI
	dec	hl		;   (copy DI.. to DI+2..: period 2)
	ldir			; each byte copies the one 2 below it
	jr	RSTOSW_DONE	; (skip LDDR)
RSTOSW_DOWN:				; (src: RSW2)
	dec	de		; DI+1 -> DI-1 ... downwards
	dec	de		; (DE = DI-1)
	lddr			; (HL = DI+1 already)
RSTOSW_DONE:				; (src: RSW3)
	pop	bc		; IP back
	ld	hl,(R_CX)	; DE = 2 * CX bytes stored
	add	hl,hl		; (2 * CX, mod 64K)
	ex	de,hl		; into DE for RADVDN
	jp	RADVDN		; (JR in the source, relaxed to JP)

; =====================================================================
; R_LODSB / R_LODSW - REP LODS: an honest loop
; ---------------------------------------------------------------------
; Every element is loaded in turn; only the last survives in AL / AX.
; Pointless in real code and so not worth a block form (see RADVS).
; The loop tests CX after the decrement: entry guarantees CX >= 1.
; Exit: CX = 0, SI advanced by CX elements.  Corrupt A, DE, HL.
; =====================================================================
R_LODSB:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RLODSB_LOOP	; CX >= 1: load
	jp	(ix)		; next instruction
RLODSB_LOOP:				; (src: RLB1)
	call	SRCPTR		; HL -> DS:SI
	ld	a,(hl)		; AL = [DS:SI]
	ld	(R_AL),a	; (AH untouched)
	call	SI_STEP_B	; SI by +-1
	ld	hl,(R_CX)	; CX - 1, until 0
	dec	hl
	ld	(R_CX),hl	; (CX kept in REGS each turn)
	ld	a,h		; CX = 0?
	or	l
	jr	nz,RLODSB_LOOP
	jp	(ix)		; next instruction

R_LODSW:
	call	CXNZ		; CX = 0: nothing at all
	jr	nz,RLODSW_LOOP	; CX >= 1: load
	jp	(ix)		; next instruction
RLODSW_LOOP:				; (src: RLW1)
	call	SRCPTR		; HL -> DS:SI
	ld	e,(hl)		; AX = [DS:SI]
	inc	hl		; (SI+1)
	ld	d,(hl)		; high byte
	ld	(R_AX),de	; AX = [DS:SI]
	call	SI_STEP_W	; SI by +-2
	ld	hl,(R_CX)	; CX - 1, until 0
	dec	hl
	ld	(R_CX),hl	; (CX kept in REGS each turn)
	ld	a,h		; CX = 0?
	or	l
	jr	nz,RLODSW_LOOP
	jp	(ix)		; next instruction

; =====================================================================
; REPGO - after one CMPS / SCAS iteration: CX -= 1, and go on?
; ---------------------------------------------------------------------
; Exit:   Z80 NZ = repeat, Z = stop.   Corrupts A, HL.  AF' preserved.
; Stops when CX reaches 0, or on the compare's ZF: REPE (F3h, REPT
; bit 0 = 1) stops on ZF = 0, REPNE (F2h, bit 0 = 0) on ZF = 1.  The
; order (CX first, then ZF) is cpu86.py op_string's, and the 8086's.
; The 8086 ZF is tested by swapping AF' in, then swapped back before
; the Z80 flags are rebuilt for the return value.
; Callers: R_CMPSB, R_CMPSW, R_SCASB, R_SCASW.
; =====================================================================
REPGO:
	ld	hl,(R_CX)	; CX - 1
	dec	hl
	ld	(R_CX),hl	; (stored back at once)
	ld	a,h		; CX = 0?
	or	l
	ret	z		; CX = 0: stop, whatever ZF says
	ld	a,(REPT)	; L = F2h / F3h (survives the swaps)
	ld	l,a		; (LD L,A: no flag change)
	ex	af,af'		; the 8086 flags into F, to read ZF
	jr	z,REPGO_ZF1	; 8086 ZF = 1
	ex	af,af'		; (8086 flags put back)
	ld	a,l		; ZF = 0: stop if REPE
	cpl			; F3h -> bit 0 = 0 -> Z: stop
	and	1		; F2h -> bit 0 = 1 -> NZ: go on
	ret			; Z = stop, NZ = go on
REPGO_ZF1:				; (src: REPGO1)
	ex	af,af'		; (8086 flags put back)
	ld	a,l		; ZF = 1: stop if REPNE
	and	1		; F2h -> Z: stop; F3h -> NZ: go on
	ret			; Z = stop, NZ = go on

; =====================================================================
; R_CMPSB / R_CMPSW - REPE / REPNE CMPS: one iteration at a time
; ---------------------------------------------------------------------
; The body sets the 8086 flags, REPGO decides.  Exit: JP (IX) with CX,
; SI, DI and the flags of the last compare, as on the 8086.
; =====================================================================
R_CMPSB:
	call	CXNZ		; CX = 0: nothing, flags untouched
	jr	nz,RCMPSB_LOOP	; CX >= 1: start
	jp	(ix)		; next instruction
RCMPSB_LOOP:				; (src: RCB1)
	call	CMPSB_STEP	; one compare, SI and DI stepped
	call	REPGO		; CX - 1, and the REPE/REPNE test
	jr	nz,RCMPSB_LOOP	; until CX = 0 or ZF ends it
	jp	(ix)		; next instruction
R_CMPSW:
	call	CXNZ		; CX = 0: nothing, flags untouched
	jr	nz,RCMPSW_LOOP	; CX >= 1: start
	jp	(ix)		; next instruction
RCMPSW_LOOP:				; (src: RCW1)
	call	CMPSW_STEP	; one compare, SI and DI stepped
	call	REPGO		; CX - 1, and the REPE/REPNE test
	jr	nz,RCMPSW_LOOP	; until CX = 0 or ZF ends it
	jp	(ix)		; next instruction

; =====================================================================
; R_SCASB - REPE / REPNE SCASB, with a CPIR / CPDR fast path for REPNE
; ---------------------------------------------------------------------
; Entry:  from REP_FETCH; BC = 8086 IP.   Exit: JP (IX).
; Corrupts A, DE, HL.
;
; REPNE SCASB ("find AL") is what DOS and EDIT use to scan text for CR,
; LF or a terminator; at about 300 T-states a byte through SCASB_STEP +
; REPGO it made big files slow.  CPIR / CPDR does the same search at
; 21 T a byte (README "The Z80 interpreter"; OVERVIEW 2.2 and 3: loading
; a 28 KB file in EDIT, 5.5 s -> 3.3 s).
;
; But CPIR is not SCASB: it sets only Z (found) and P/V (BC <> 0), not
; the SUB flags (CF SF OF AF PF) the 8086 leaves from its last compare.
; So CPIR never makes the last compare.  With n = CX - 1:
;   1. CPIR / CPDR passes over at most n bytes from ES:DI, stopping on a
;      match.  Every byte it passes over without a match is an 8086
;      iteration that would have compared unequal (ZF = 0), stepped DI,
;      decremented CX to a value still >= 1, and gone on: no lasting
;      effect but CX and DI.
;   2. CX and DI are set as if those iterations had run: CX = what is
;      left + 1 (the reserved last byte), + 1 more if CPIR stopped on a
;      match - the matched byte is handed back, uncompared (CPIR had
;      counted it).  DE = old CX - new CX = bytes passed over, negated
;      when DF = 1, is added to DI.
;   3. RSCASB_LOOP, the ordinary loop, then compares at least once (new
;      CX >= 1): the match, or the last byte.  That compare makes every
;      flag, and REPGO the final CX - so flags, CX and DI end exactly as
;      on an 8086, with no flag code of its own.
; Not taken (ordinary loop from the start) for:
;   - REPE (F3h): a "skip while equal" scan has no single-instruction
;     Z80 equivalent;
;   - CX = 1: nothing to pass over;
;   - DI wrapping during the pass: forward when DI + n > FFFFh, backward
;     when DI < CX - one case too strict (DI = n would not wrap; the
;     author's own note): the carry left by the RLA that tested DF
;     is borrowed into the SBC, so it computes DI - n - 1.  A wrap would
;     still be right in the host (offsets and linear addresses wrap
;     alike mod 64K), so this is caution, not need; the slow loop is
;     always correct, so being too strict only costs time.
; Checked: lockstep against cpu86.py over a DOS session, fuzz_z86.py
; --scan (REP SCASB/SCASW, CX up to 2000), and a deliberately broken
; fast path made the fuzzer report 159 mismatches (OVERVIEW 3, item 9).
; =====================================================================
R_SCASB:
	call	CXNZ		; CX = 0: nothing, flags untouched
	jr	nz,RSCASB_GO	; CX >= 1: start
	jp	(ix)		; next instruction
RSCASB_GO:				; (src: RSC0)
	ld	a,(REPT)	; F2h: REPNE
	rra			; bit 0 -> carry: F3h REPE ...
	jr	c,RSCASB_LOOP	; ... takes the ordinary loop
	dec	hl		; CX-1 bytes to pass over
	ld	a,h		; n = 0?
	or	l
	jr	z,RSCASB_LOOP	; CX = 1: only the final compare
	push	bc		; save IP: BC = n for CPIR
	ld	b,h		; BC = n
	ld	c,l
	ld	hl,(R_DI)	; C: DI would wrap
	ld	a,(STEP1+1)	; DF -> carry
	rla			; (STEP1+1 = FFh when DF = 1)
	jr	nc,RSCASB_FWD	; DF = 0: test DI + n
	sbc	hl,bc		; (CF=1: DI < CX, one too strict)
	jr	RSCASB_WRAP_CHK	; carry decides
RSCASB_FWD:				; (src: RSCF)
	add	hl,bc		; DI + n > FFFFh: carry
RSCASB_WRAP_CHK:			; (src: RSCF1)
	jr	c,RSCASB_SLOW	; would wrap: leave it to the ordinary loop
	call	DSTPTR		; HL = host ES:DI (BC = n kept)
	ld	a,(STEP1+1)	; DF -> carry again (DSTPTR's ADD lost it)
	rla			; (STEP1+1 = FFh when DF = 1)
	ld	a,(R_AL)	; A = the byte sought (LD keeps carry)
	jr	c,RSCASB_CPDR	; DF = 1: downwards
	cpir			; DF = 0: up to n bytes, upwards
	jr	RSCASB_PASSED	; (skip CPDR)
RSCASB_CPDR:				; (src: RSCD)
	cpdr			; DF = 1: downwards
RSCASB_PASSED:				; (src: RSCE)
	jr	nz,RSCASB_SET_CX	; Z = CPIR stopped on a match
	inc	bc		; found: RSCASB_LOOP compares it again
RSCASB_SET_CX:				; (src: RSCE1)
	inc	bc		; + the reserved final byte: CX for the loop
	ld	hl,(R_CX)	; DE = old CX - new CX = bytes passed over
	ld	(R_CX),bc	; CX = remaining + 1 or + 2
	or	a		; no borrow in
	sbc	hl,bc		; HL = bytes passed over
	ex	de,hl		; DE = that count
	call	RNEG_DE		; negative when DF = 1
	ld	hl,(R_DI)	; DI moves past them (CPIR's HL is not used:
	add	hl,de		;   it is a host address, and one too far
	ld	(R_DI),hl	;   after a match)
RSCASB_SLOW:				; (src: RSCX)
	pop	bc		; IP back
RSCASB_LOOP:				; (src: RSC1)
	call	SCASB_STEP	; one SCASB: flags, DI stepped
	call	REPGO		; CX - 1, stop on ZF per REPT
	jr	nz,RSCASB_LOOP	; until CX = 0 or a match
	jp	(ix)		; next instruction

; R_SCASW - REPE / REPNE SCASW: the ordinary loop only (no word CPIR).
R_SCASW:
	call	CXNZ		; CX = 0: nothing, flags untouched
	jr	nz,RSCASW_LOOP	; CX >= 1: start
	jp	(ix)		; next instruction
RSCASW_LOOP:				; (src: RSCW1)
	call	SCASW_STEP	; one compare, DI stepped
	call	REPGO		; CX - 1, and the REPE/REPNE test
	jr	nz,RSCASW_LOOP	; until CX = 0 or ZF ends it
	jp	(ix)		; next instruction
; =====================================================================
;            OPCODES B0h-EAh - MOV IMMEDIATE, RETURNS, INTERRUPTS,
;            SHIFTS, ASCII ADJUST, LOOPS, PORT I/O, NEAR/FAR JUMPS
; =====================================================================
;
; Handlers for opcodes B0h-EAh, in opcode order (E417h-E805h).  Every
; one is reached only through the split dispatch table OPLO/OPHI
; (D1B0h-D1EAh / D2B0h-D2EAh) from NEXT, with BC = host address of the
; byte after the opcode and A = the opcode; every one leaves through
; JP (IX) (NEXT, or RESTORE after a segment prefix) or through a
; helper that ends that way (FARJ, PUSHX, JREL8, J_TAKE, J_NOT, SZP8).
;
; Opcodes this part does NOT hold, though they sit in the same range of
; the table: EBh JMP short is O_JREL8 (the Jcc code, DE48h); EEh/EFh
; OUT DX go straight to O_NOP.  The BIOS trap 0Fh nn (O_TRAP), HLT
; (O_HLT, F4h) and CALL far (O_CALLF, 9Ah) live in earlier parts;
; DOINT and O_RETF / O_RETFN below are the trap mechanism's other half
; (the INT that reaches a trap stub, the RETF that leaves it).
;
; Segment bases: every place that loads CS goes through FARJ (RET far,
; RETF n, IRET, INT, JMP far), which stores R_CS AND B_CS = CS << 4 and
; rebuilds BC from them; LES / LDS go through SETSEG, which stores the
; register, its base and (for DS) EADS.  No handler here writes a
; segment register any other way.
;
; Mirrors cpu86.py, opcode for opcode (op_mov_imm_r .. op_jmp_far);
; differences are listed per handler and in notes/z86_part05_findings.md.

SHPG_8BIT:	equ	80h		; offset of the 8-bit half of SHPG: slot
					;   k of an 8-bit shift is SHPG+80h+16k

; =====================================================================
; O_MOVI_AL .. O_MOVI_BH (B0h-B7h) - MOV reg8,imm8
; O_MOVI_AX .. O_MOVI_DI (B8h-BFh) - MOV reg16,imm16
; ---------------------------------------------------------------------
; Entry:  BC -> the immediate.
; Exit:   the register's REGS slot holds it, BC past it, to NEXT.
;         Flags untouched (MOV sets none).
; Corrupts: A.
;
; One handler per register (an ;@FOR expansion in I86.ASM), so the
; register number in the opcode's low 3 bits is never decoded at run
; time: the dispatch table has already chosen the slot.  The word forms
; copy low byte then high byte, the 8086's little-endian order and the
; REGS layout.  Mirrors cpu86.py op_mov_imm_r.
; =====================================================================
O_MOVI_AL:
	ld	a,(bc)		; the immediate byte
	inc	bc		; IP past it
	ld	(R_AL),a	; straight into AL's REGS slot (REGS+0)
	jp	(ix)		; flags untouched: MOV sets none
O_MOVI_CL:
	ld	a,(bc)		; as O_MOVI_AL, into CL
	inc	bc		; IP past the immediate
	ld	(R_CL),a	; CL = REGS+2
	jp	(ix)		; next instruction
O_MOVI_DL:
	ld	a,(bc)		; ... into DL
	inc	bc		; IP past the immediate
	ld	(R_DL),a	; DL = REGS+4
	jp	(ix)		; next instruction
O_MOVI_BL:
	ld	a,(bc)		; ... into BL
	inc	bc		; IP past the immediate
	ld	(R_BL),a	; BL = REGS+6
	jp	(ix)		; next instruction
O_MOVI_AH:
	ld	a,(bc)		; ... into AH
	inc	bc		; IP past the immediate
	ld	(R_AH),a	; AH = REGS+1, the high byte of AX
	jp	(ix)		; next instruction
O_MOVI_CH:
	ld	a,(bc)		; ... into CH
	inc	bc		; IP past the immediate
	ld	(R_CH),a	; CH = REGS+3
	jp	(ix)		; next instruction
O_MOVI_DH:
	ld	a,(bc)		; ... into DH
	inc	bc		; IP past the immediate
	ld	(R_DH),a	; DH = REGS+5
	jp	(ix)		; next instruction
O_MOVI_BH:
	ld	a,(bc)		; ... into BH
	inc	bc		; IP past the immediate
	ld	(R_BH),a	; BH = REGS+7
	jp	(ix)		; next instruction
O_MOVI_AX:
	ld	a,(bc)		; low byte of the immediate word ...
	ld	(R_AX),a	; ... to the register's low byte
	inc	bc		; next byte
	ld	a,(bc)		; high byte ...
	ld	(R_AX+1),a	; ... to its high byte
	inc	bc		; IP past the word
	jp	(ix)		; flags untouched
O_MOVI_CX:
	ld	a,(bc)		; as O_MOVI_AX, into CX: low byte
	ld	(R_CX),a	; CX low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_CX+1),a	; CX high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_DX:
	ld	a,(bc)		; ... into DX: low byte
	ld	(R_DX),a	; DX low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_DX+1),a	; DX high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_BX:
	ld	a,(bc)		; ... into BX: low byte
	ld	(R_BX),a	; BX low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_BX+1),a	; BX high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_SP:
	ld	a,(bc)		; ... into SP (no alignment check: the 8086
	ld	(R_SP),a	;   allows an odd SP, and so does this)
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_SP+1),a	; SP high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_BP:
	ld	a,(bc)		; ... into BP: low byte
	ld	(R_BP),a	; BP low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_BP+1),a	; BP high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_SI:
	ld	a,(bc)		; ... into SI: low byte
	ld	(R_SI),a	; SI low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_SI+1),a	; SI high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction
O_MOVI_DI:
	ld	a,(bc)		; ... into DI: low byte
	ld	(R_DI),a	; DI low
	inc	bc		; next byte
	ld	a,(bc)		; high byte
	ld	(R_DI+1),a	; DI high
	inc	bc		; IP past the word
	jp	(ix)		; next instruction

; =====================================================================
; OPCODES C0h-CFh - the table row decoded
; ---------------------------------------------------------------------
;   C0 RETN  C1 RET   C2 RETN  C3 RET    C4 LES   C5 LDS   C6 MOVC6 C7 MOVC7
;   C8 RETFN C9 RETF  CA RETFN CB RETF   CC INT3  CD INTN  CE INTO  CF IRET
; C0h/C1h and C8h/C9h are the 8086's undocumented aliases of C2h/C3h and
; CAh/CBh (shift-immediate and ENTER/LEAVE only from the 80186 on), and
; are taken as such, as cpu86.py's _build does.
; =====================================================================

; =====================================================================
; O_RETN - RET imm16 (C2h, alias C0h): near return, then SP += imm16
; ---------------------------------------------------------------------
; Entry:  BC -> the imm16.
; Exit:   BC = CS base + popped IP; SP advanced past the return address
;         and imm16 bytes of arguments.  CS unchanged, so B_CS stands.
; Corrupts: A, DE, HL.
;
; The new host PC is parked on the Z80 stack because BC is still needed
; to read the imm16; the order (pop first, read imm16 second) differs
; from cpu86.py op_ret_imm's but touches disjoint state, so the result
; is the same.
; =====================================================================
O_RETN:
	call	POPDE		; DE = return IP, SP += 2
	ld	hl,(B_CS)	; host address of CS:IP = CS base + IP
	add	hl,de		; HL = new host PC
	push	hl		; park it: BC still points at the imm16
	ld	a,(bc)		; DE = imm16, the argument bytes to drop
	ld	e,a		; imm16 low
	inc	bc		; to its high byte
	ld	a,(bc)		; imm16 high
	ld	d,a		; (BC is not advanced past it: it is replaced)
	ld	hl,(R_SP)	; SP += imm16, wrapping in 16 bits as on the
	add	hl,de		;   8086
	ld	(R_SP),hl	; SP updated
	pop	bc		; resume at the return address
	jp	(ix)		; flags untouched

; =====================================================================
; O_RET - RET (C3h, alias C1h): near return
; ---------------------------------------------------------------------
; Entry:  -
; Exit:   BC = CS base + popped IP.
; Corrupts: A, DE, HL.
;
; POPDE written out in line: RET is one of the commonest instructions,
; and the CALL/RET pair would cost 27 T-states on every one.
; =====================================================================
O_RET:
	ld	hl,(R_SP)	; DE = SS base + SP: host address of the top
	ld	a,(B_SS)	;   of the 8086 stack (16-bit add, done byte
	add	a,l		;   by byte so that HL keeps SP)
	ld	e,a		; DE low = (SS base + SP) low
	ld	a,(B_SS+1)	; high byte with the carry
	adc	a,h		; + SP high
	ld	d,a		; DE = host address of [SS:SP]
	inc	hl		; SP += 2
	inc	hl
	ld	(R_SP),hl	; SP stored back
	ex	de,hl		; DE = the word popped (the return IP)
	ld	e,(hl)		; return IP, low
	inc	hl		; HL, not L: the word may cross a page
	ld	d,(hl)		; return IP, high
	ld	hl,(B_CS)	; back into the same code segment
	add	hl,de		; CS base + IP
	ld	b,h		; BC = new host PC
	ld	c,l
	jp	(ix)		; flags untouched

; =====================================================================
; O_LES / O_LDS (C4h / C5h) - load a far pointer: reg16 = [m], ES or DS
; = [m+2]
; ---------------------------------------------------------------------
; Entry:  BC -> the ModR/M byte.
; Exit:   reg16 and the segment register loaded; the segment's base
;         (B_ES / B_DS) recomputed by SETSEG, and EADS too for LDS, so
;         the very next DS-relative operand uses the new base.
; Corrupts: A, DE, HL.
;
; A = 2 * sreg (0 = ES, 6 = DS), the index SETSEG takes, kept on the
; Z80 stack across MRW.  The register is written before the segment
; word is read; no aliasing is possible because the registers live in
; REGS (D000h) and the operand in guest memory (below D000h).
;
; Under a segment prefix, SETSEG's EADS store is overwritten one
; instruction later by RESTORE, which reloads EADS from B_DS - already
; the new base after an LDS - so the result is right either way.
;
; Divergence (undefined input): a register operand (mod = 11) makes MRW
; return a pointer into REGS, so the "far pointer" is read from two
; adjacent registers (rm, rm+1; rm = DI reads R_ES as the segment).
; cpu86.py reads 0000:0000 instead.  The 8086 leaves the case undefined
; and fuzz_z86.py masks it out, so the two models were never compared
; there (verified by code reading).
; =====================================================================
O_LES:
	xor	a		; segment index 0: ES
	jr	LXS		; shared body
O_LDS:
	ld	a,6		; segment index 6 (= 2 * 3): DS
LXS:
	push	af		; MRW needs A for the ModR/M byte
	call	MRW		; HL -> m16:16 (offset, segment), DE -> reg16
	ld	a,(hl)		; offset word into the register: low byte
	ld	(de),a		; register low byte
	inc	hl		; to the offset's high byte
	inc	e		; REGS is page-aligned: a register never
	ld	a,(hl)		;   straddles a page, so INC E suffices
	ld	(de),a		; register high byte
	inc	hl		; to [m+2]
	ld	e,(hl)		; DE = the segment word at [m+2]
	inc	hl
	ld	d,(hl)
	pop	af		; A = which segment register
	call	SETSEG		; store it with its base (and EADS for DS)
	jp	(ix)		; flags untouched

; =====================================================================
; O_MOVC6 / O_MOVC7 (C6h / C7h) - MOV r/m8,imm8 / MOV r/m16,imm16
; ---------------------------------------------------------------------
; Entry:  BC -> the ModR/M byte.
; Exit:   operand written, BC past the immediate.  Flags untouched.
; Corrupts: A, DE, HL.
;
; The encoding order is ModR/M, displacement, immediate.  EAB / EAW
; (through the EAMEM routines) consume the displacement from BC, so
; the immediate is simply the next code byte afterwards.  The reg field
; of the ModR/M is ignored, as on the 8086 and in cpu86.py
; op_mov_rm_imm.
; =====================================================================
O_MOVC6:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; IP past the ModR/M
	call	EAB		; HL -> the r/m8 operand, displacement eaten
	ld	a,(bc)		; the immediate byte follows it
	inc	bc		; IP past the instruction
	ld	(hl),a		; store, register or memory alike
	jp	(ix)		; flags untouched
O_MOVC7:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; IP past the ModR/M
	call	EAW		; HL -> the r/m16 operand
	ld	a,(bc)		; immediate low byte
	inc	bc
	ld	(hl),a		; low byte stored
	inc	hl		; HL, not L: a memory word may cross a page
	ld	a,(bc)		; immediate high byte
	inc	bc		; IP past the instruction
	ld	(hl),a		; high byte stored
	jp	(ix)		; flags untouched

; =====================================================================
; O_RETFN - RETF imm16 (CAh, alias C8h): far return, then SP += imm16
; ---------------------------------------------------------------------
; Entry:  BC -> the imm16.
; Exit:   CS:IP popped, SP += imm16; FARJ sets R_CS, B_CS = CS << 4 and
;         BC = B_CS + IP.
; Corrupts: A, DE, HL.
;
; The interrupt half of the BIOS trap mechanism: IO.SYS points each PC
; ROM BIOS vector (INT 10h-12h, 14h, 16h, 17h, 1Ah) at a 5-byte stub
; `0Fh n, CAh 02h 00h` - TRAP n / RETF 2 (IOFDD.ASM INT10..INT1A).  The
; INT (DOINT) pushed FLAGS, CS, IP; TRAP n ran the Z80 BIOS function,
; which reports through ZF / CF in AF'; this RETF 2 then drops the
; pushed FLAGS instead of restoring them, so the trap's flags reach
; the caller (the IBM BIOS's own convention).  Mirrors cpu86.py
; op_retf_imm.
; =====================================================================
O_RETFN:
	call	POPDE		; IP ...
	push	de		; ... parked
	call	POPDE		; CS ...
	push	de
	ld	a,(bc)		; DE = imm16 (BC is about to be replaced, so
	ld	e,a		;   it is not advanced past the word)
	inc	bc
	ld	a,(bc)		; imm16 high
	ld	d,a		; DE = imm16
	ld	hl,(R_SP)	; drop imm16 bytes of arguments (2 at the
	add	hl,de		;   end of a trap stub: the saved FLAGS)
	ld	(R_SP),hl	; SP stored back
	pop	hl		; HL = CS
	pop	de		; DE = IP
	jp	FARJ		; CS, its base and BC, then NEXT

; =====================================================================
; O_RETF - RETF (CBh, alias C9h): far return
; ---------------------------------------------------------------------
; Entry:  -
; Exit:   CS:IP popped; FARJ reloads R_CS, B_CS and BC.
; Corrupts: A, DE, HL.
;
; The device half of the trap mechanism: each of IO.SYS's DOS device
; entries is `0Fh n, CBh` - TRAP n / RETF (IOFDD.ASM line 18), entered
; by a far CALL from MSDOS.SYS.  Mirrors cpu86.py op_retf.
; =====================================================================
O_RETF:
	call	POPDE		; IP, parked over the second pop
	push	de
	call	POPDE		; CS ...
	ex	de,hl		; ... into HL, where FARJ wants it
	pop	de		; DE = IP
	jp	FARJ		; CS, its base and BC, then NEXT

; =====================================================================
; O_INT3 / O_INTN / DOINT - INT 3 (CCh), INT n (CDh nn), and the common
; interrupt entry
; ---------------------------------------------------------------------
; Entry:  DOINT: A = vector number, BC = host address of the instruction
;         after the one that interrupts (the return address).
; Exit:   FLAGS, CS, IP pushed (in that order, as the 8086); IF = TF = 0;
;         CS:IP = the far pointer at linear 4n, entered through FARJ
;         (R_CS, B_CS = CS << 4, BC).  DF and the arithmetic flags kept.
; Corrupts: A, DE, HL.
; Callers: O_INT3, O_INTN (falls in), INTO_TAKE, DIVERR (from O_AAM here
;          and from DIV / IDIV in O_GRP3B / O_GRP3W).
;
; The vector table needs no segment arithmetic: guest linear address n
; is Z80 address n, so vector n sits at Z80 address 4n, inside
; 0000h-03FFh.  There is no counterpart of cpu86.py's int_hook (used
; only by the dosshim test harness): every INT, 21h included, goes
; through guest memory as on a real 8086.  The BIOS-type vectors lead
; to IO.SYS's `TRAP n / RETF 2` stubs (see O_RETFN), and the 0Fh there
; is where interpretation hands over to the Z80 BIOS - the guide's
; item 1 seen from the interpreter's side.
;
; Vector 0Eh (0038h-003Bh) doubles as the Z80's RST 38h; the BIOS lends
; it to FDCINT during a disk transfer and puts it back.  Transfers run
; inside a trap, never while 8086 code runs, so a guest INT 0Eh cannot
; meet the borrowed bytes.
;
; IF and TF are bookkeeping only (FLAGHI bits 1, 0): nothing interrupts
; the guest and nothing single-steps.  After a `TRAP n / RETF 2`
; vector they stay cleared, because RETF 2 discards the saved FLAGS
; (harmless; visible only to a later PUSHF).  Mirrors cpu86.py
; interrupt().
; =====================================================================
O_INT3:
	ld	a,3		; the one-byte breakpoint interrupt
	jr	DOINT		; common entry
O_INTN:
	ld	a,(bc)		; vector number from the code stream; BC past
	inc	bc		;   it is the return address
DOINT:
	push	af		; keep the vector number over the pushes
	call	GETF		; HL = FLAGS, assembled from AF' and FLAGHI
	ex	de,hl		; PUSHDE pushes DE
	call	PUSHDE		; push FLAGS (before IF/TF are cleared)
	ld	a,(FLAGHI)	; FLAGHI = TF IF DF (FLAGS bits 8-10)
	and	0FCh		; IF = TF = 0 (FLAGHI bits 1, 0; DF bit 2 kept)
	ld	(FLAGHI),a
	ld	de,(R_CS)	; push CS
	call	PUSHDE
	call	GETIP		; DE = IP = BC - CS base
	call	PUSHDE		; push IP
	pop	af		; A = vector number again
	ld	l,a		; HL = 4n: the vector's Z80 (= linear) address
	ld	h,0		; n < 256, so 4n < 0400h
	add	hl,hl		; x2
	add	hl,hl		; x4
	ld	e,(hl)		; DE = new IP (vector word 0)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)		; HL = new CS (vector word 1)
	inc	hl
	ld	h,(hl)
	ld	l,a
	jp	FARJ		; CS, its base and BC, then NEXT

; =====================================================================
; O_INTO (CEh) - INT 4 if OF; DIVERR - INT 0 (divide error)
; ---------------------------------------------------------------------
; Entry:  O_INTO: -.  DIVERR: BC already past the whole faulting
;         instruction (the ModR/M, displacement or AAM's imm8 eaten).
; Exit:   through DOINT, or (INTO with OF = 0) straight to NEXT.
; Corrupts: as DOINT.
;
; OF lives in the V position of F', so INTO swaps AF' in just to test
; it.  DIVERR pushes the address of the NEXT instruction, which is the
; 8086/8088's behaviour (from the 80286 on the fault returns to the
; divide itself) and cpu86.py's (interrupt(0) after the fetch).
; DIVERR's callers: O_AAM (E716h) and the DIV / IDIV paths of
; O_GRP3B / O_GRP3W (E8A9h-E902h, E9BEh-EA11h, part 06).
; =====================================================================
O_INTO:
	ex	af,af'		; the 8086 flags in: OF is the V bit
	jp	pe,INTO_TAKE	; OF = 1: interrupt
	ex	af,af'		; OF = 0: a no-op, flags back where they live
	jp	(ix)		; next instruction
INTO_TAKE:				; (src: INTO1)
	ex	af,af'		; flags back first: DOINT reads them via GETF
	ld	a,4		; the overflow vector
	jr	DOINT		; common entry
DIVERR:
	xor	a		; vector 0: divide error
	jr	DOINT		; common entry

; =====================================================================
; O_IRET (CFh) - pop IP, CS, FLAGS
; ---------------------------------------------------------------------
; Entry:  -
; Exit:   FLAGS restored by SETF (AF', FLAGHI and, through SETSTEP, the
;         DF-dependent string steps STEP1 / STEP2); CS:IP via FARJ.
; Corrupts: A, DE, HL.
;
; Unused by IO.SYS's own stubs (they return with RETF / RETF 2), but
; DOS (INT 21h, 20h...) and programs' own handlers end with it.
; Mirrors cpu86.py op_iret.
; =====================================================================
O_IRET:
	call	POPDE		; IP, parked
	push	de
	call	POPDE		; CS, parked
	push	de
	call	POPDE		; FLAGS
	ex	de,hl		; SETF takes them in HL
	call	SETF		; into AF' / FLAGHI / STEP1 / STEP2
	pop	hl		; HL = CS
	pop	de		; DE = IP
	jp	FARJ		; CS, its base and BC, then NEXT

; =====================================================================
; OPCODES D0h-DFh - the table row decoded
; ---------------------------------------------------------------------
;   D0 SHD0 r/m8,1     D1 SHD1 r/m16,1    D2 SHD2 r/m8,CL   D3 SHD3 r/m16,CL
;   D4 AAM imm8        D5 AAD imm8        D6 SALC           D7 XLAT
;   D8-DF ESC (coprocessor escapes, operand decoded and ignored)
; D6h SALC is the 8086's undocumented "AL = CF ? FFh : 00h".
; =====================================================================

; =====================================================================
; O_SHD0 / O_SHD2 / SHB - byte shifts and rotates (D0h r/m8,1; D2h
; r/m8,CL)
; ---------------------------------------------------------------------
; Entry:  BC -> the ModR/M byte.  SHB: D = count (1 or CL).
; Exit:   jumps into SHPG slot 80h + 16k (k = ModR/M reg field: ROL ROR
;         RCL RCR SHL SHR SAL SAR) with L = the value, D = count > 0 and
;         the Z80 stack holding [old AF'] [operand address]; the slot
;         loops D times and its finisher (ROT8A .. SAR8F) sets the flags,
;         stores the result and goes to NEXT.  Count 0: nothing changes,
;         flags included.
; Corrupts: A, DE, HL; SHCNT, SHORIG.
;
; The count is CL in full, 0-255, not masked to 5 bits: the 8086 does
; not mask (the 80186 on do), and neither does cpu86.py op_shift.
;
; SELF-MODIFYING: the slot is chosen by patching the low byte of
; SHB2's JP SHPG.  SHPG is page-aligned (D700h), so the low byte alone
; selects the slot; the assembled JP SHPG (slot 0) is never executed
; unpatched.
; =====================================================================
O_SHD0:
	ld	d,1		; count 1
	jr	SHB		; common byte path
O_SHD2:
	ld	a,(R_CL)	; count = CL, unmasked
	ld	d,a		; D = count
SHB:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; IP past the ModR/M
	push	de		; the count and ModR/M survive EAB, whose
	push	af		;   EAMEM routines use A, DE
	call	EAB		; HL -> the r/m8 operand
	pop	af		; A = ModR/M again
	pop	de		; D = count again
	inc	d		; Z if the count is 0, A kept
	dec	d
	jr	nz,SHB_RUN	; count > 0: shift
	jp	(ix)		; count 0: no change at all, flags included
SHB_RUN:				; (src: SHB1)
	ld	e,a		; E = ModR/M
	ld	a,d
	ld	(SHCNT),a	; SHR8F needs the count (OF is defined for 1)
	push	hl		; frame: operand address ...
	ld	a,(hl)		; the byte operand
	ld	l,a		; L = the value
	ld	(SHORIG),a	; ... SHR8F needs the original MSB too
	ex	af,af'		; ... then the old 8086 flags on top: RCL/RCR
	push	af		;   take CF from there, rotates keep S Z AF PF
	ex	af,af'
	ld	a,e		; slot = 80h + reg field * 16: (modrm & 38h)
	and	38h		;   * 2 is reg * 16
	add	a,a
	or	SHPG_8BIT	; the 8-bit half of SHPG
	ld	(SHB2+1),a	; PATCH the low byte of the JP below
SHB2:
	jp	SHPG		; PATCHED by the store above: SHPG+80h+16k

; =====================================================================
; O_SHD1 (D1h) - word shift / rotate by 1, with a fast path for SHL / SHR
; ---------------------------------------------------------------------
; Entry:  BC -> the ModR/M byte.
; Exit:   SHL r/m16,1 (reg 4) and SHR r/m16,1 (reg 5) are done here in
;         line; every other reg field goes to SHWA with D = 1.
; Corrupts: A, DE, HL.
;
; The mask 30h with 20h picks reg 4 and 5 only; SAL (reg 6, the same
; operation as SHL) takes the general path.
;
; SHL: ADC HL,HL with CF cleared is a one-bit shift that, unlike
; ADD HL,HL, sets S, Z and V - and V (signed overflow of v + v) is
; exactly the 8086's OF for a 1-bit SHL (new MSB XOR CF).  H (carry from
; bit 11) is cleared: AF = 0, as cpu86.py.
; SHR: the flags are built in E from nothing: CF from the bit shifted
; out, OF = the old MSB, S = 0 (the new MSB is always 0), Z if zero.
; In both, D = the low byte, which becomes A' and so yields PF.
; =====================================================================
O_SHD1:
	ld	a,(bc)		; r/m16, 1: the ModR/M byte
	inc	bc		; IP past the ModR/M
	ld	e,a		; keep the ModR/M
	and	30h		; reg field 4 or 5 (SHL / SHR)?
	cp	20h
	ld	a,e		; A = ModR/M again (LD keeps the flags)
	ld	d,1		; count 1 for the general path
	jr	nz,SHWA		; not SHL / SHR: the general path
	push	af		; the ModR/M over EAW
	call	EAW		; HL -> the r/m16 operand
	pop	af		; A = ModR/M
	push	hl		; the operand address, for the store
	ld	e,(hl)		; DE = the value
	inc	hl
	ld	d,(hl)
	ex	de,hl		; HL = value
	and	08h		; reg bit 0: 4 = SHL, 5 = SHR
	jr	nz,SHD1_SHR	; 5: SHR
	or	a		; SHL: A = 0, so this only clears CF; then
	adc	hl,hl		;   S Z OF(V) CF come from ADC
	ld	a,l		; A = low byte, the new A' (for PF)
	push	af		; DE = A:F
	pop	de		; E = F (S Z V C), D = low byte
	res	4,e		; H (the Z80's half carry from bit 11): AF = 0
	jr	SH1WE		; common store
SHD1_SHR:				; (src: SHR1W)
	ld	a,h		; SHR: OF = old MSB, S = 0
	and	80h		; isolate it
	rrca			; bit 7 -> bit 2, the V position (OF)
	rrca
	rrca
	rrca
	rrca
	ld	e,a		; E = the new flags, built up
	srl	h		; the shift; bit 0 out to the Z80 carry
	rr	l		; the low byte; carry = old bit 0
	jr	nc,SHD1_SHR_ZF	; no bit out: CF stays 0
	inc	e		; CF
SHD1_SHR_ZF:				; (src: SHR1W1)
	ld	a,h		; result zero?
	or	l
	jr	nz,SHD1_SHR_DONE
	set	6,e		; ZF
SHD1_SHR_DONE:				; (src: SHR1W2)
	ld	d,l		; A' = low byte of the result: PF from it
SH1WE:
	push	de		; the new 8086 flags into AF'
	pop	af
	ex	af,af'		; AF' = the 8086 flags
	ex	de,hl		; DE = result
	pop	hl		; HL = operand address
	ld	(hl),e		; store the word
	inc	hl
	ld	(hl),d		; high byte
	jp	(ix)		; next instruction

; =====================================================================
; O_SHD3 / SHW / SHWA - word shifts and rotates (D3h r/m16,CL, and
; D1h's non-SHL/SHR cases)
; ---------------------------------------------------------------------
; Entry:  O_SHD3 / SHW: BC -> the ModR/M byte.  SHWA: A = ModR/M
;         (fetched), D = count (from O_SHD1: 1).
; Exit:   into SHPG slot 16k with HL = value, D = count > 0, stack
;         [old AF'] [operand address]; the finisher (ROT16A .. SAR16F)
;         ends at NEXT.  Count 0: no change.
; Corrupts: A, DE, HL; SHCNT, SHORIG.
;
; The word twin of SHB.  SHW itself is entered only by falling in from
; O_SHD3 (nothing jumps to it).
;
; SELF-MODIFYING: as SHB2, the low byte of SHW2's JP SHPG is patched to
; slot 16k of the 16-bit half (no 80h added).
; =====================================================================
O_SHD3:
	ld	a,(R_CL)	; count = CL, unmasked
	ld	d,a		; D = count
SHW:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; IP past the ModR/M
SHWA:
	push	de		; count and ModR/M over EAW
	push	af
	call	EAW		; HL -> the r/m16 operand
	pop	af		; A = ModR/M
	pop	de		; D = count
	inc	d		; count 0?
	dec	d
	jr	nz,SHW_RUN	; count > 0: shift
	jp	(ix)		; count 0: no change, flags included
SHW_RUN:				; (src: SHW1)
	ld	e,a		; E = ModR/M
	ld	a,d		; A = count
	ld	(SHCNT),a	; for SHR16F's OF
	push	hl		; frame: operand address ...
	ld	a,(hl)		; HL = the value
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	(SHORIG),hl	; ... for SHR16F's OF (the original bit 15)
	ex	af,af'		; ... old 8086 flags on top
	push	af
	ex	af,af'
	ld	a,e		; slot = reg field * 16
	and	38h		; reg field
	add	a,a		; x2: (reg*8)*2 = reg*16
	ld	(SHW2+1),a	; PATCH the low byte of the JP below
SHW2:
	jp	SHPG		; PATCHED by the store above: SHPG+16k

; =====================================================================
; Shift / rotate finishers - flags, store, NEXT
; ---------------------------------------------------------------------
; Entry:  from the end of an SHPG slot: HL (word) or L (byte) = result,
;         Z80 carry = the last bit shifted out (the 8086 CF); Z80 stack
;         [old AF'] [operand address].
; Exit:   result stored, AF' = the new 8086 flags, to NEXT.
; Corrupts: A, DE, HL (TMP for the word rotates).
;
;   finisher        slots         OF                       other flags
;   ROT16A/ROT8A    ROL, RCL      MSB XOR CF               S Z AF PF kept
;   ROT16B/ROT8B    ROR, RCR      MSB XOR next bit         S Z AF PF kept
;   SHL16F/SHL8F    SHL, SAL      MSB XOR CF               S Z PF set, AF=0
;   SHR16F/SHR8F    SHR           old MSB if count 1, else 0  S Z PF, AF=0
;   SAR16F/SAR8F    SAR           0                        S Z PF, AF=0
;
; The OF rules for counts above 1 (undefined on the 8086) are
; cpu86.py's, which the interpreter matches flag for flag.  Every
; finisher starts with SBC A,A / AND 1, turning the Z80 carry into bit 0
; (the C position) of the flag byte E it builds; OF goes in bit 2 (V).
; The names ROT16A .. SAR8F are referenced from the SHPG slots (part
; 01) and stay as the author's.
; =====================================================================

; ---- 16-bit rotates: CF and OF only --------------------------------
ROT16A:
	sbc	a,a		; OF = MSB ^ CF
	and	1		; E = CF in bit 0
	ld	e,a		; E = CF
	ld	a,h		; bit 15 to bit 0 ...
	rlca			; bit 15 -> bit 0
	xor	e		; ... XOR CF ...
	and	1		; OF alone
	rlca			; ... moved to bit 2 (V): OF
	rlca
	or	e		; E = OF | CF
	ld	e,a
	jr	ROT16_DONE
ROT16B:
	sbc	a,a		; OF = bit 15 ^ bit 14
	and	1		; E = CF in bit 0
	ld	e,a		; E = CF
	ld	a,h		; bit 14 up to bit 7 ...
	add	a,a		; bit 14 -> bit 7
	xor	h		; ... XOR bit 15 ...
	and	80h		; OF alone, in bit 7
	rlca			; ... bit 7 round to bit 2 (V)
	rlca
	rlca
	or	e		; E = OF | CF
	ld	e,a
ROT16_DONE:				; (src: ROTE16)
	ld	(TMP),hl	; park the result: HL is needed for the flags
	pop	hl		; L = the old 8086 F' (H = old A', the PF byte)
	ld	a,l		; old F'
	and	0FAh		; drop the old OF (V) and CF ...
	or	e		; ... put in the new ones, keep S Z AF PF
	ld	l,a
	push	hl		; back into AF'
	pop	af
	ex	af,af'		; the 8086 flags back in AF'
	ld	de,(TMP)	; DE = result
	pop	hl		; HL = operand address
	ld	(hl),e		; store the word
	inc	hl
	ld	(hl),d		; high byte
	jp	(ix)		; next instruction

; ---- 16-bit shifts: S Z PF from the result, AF = 0 -----------------
SHL16F:
	sbc	a,a		; OF = MSB ^ CF, as ROT16A
	and	1		; E = CF
	ld	e,a
	ld	a,h		; bit 15 to bit 0
	rlca
	xor	e		; XOR CF
	and	1		; OF alone
	rlca			; to bit 2 (V)
	rlca
	or	e		; E = OF | CF
	ld	e,a
	jr	SH16_FLAGS	; common shift tail
SHR16F:
	sbc	a,a		; OF = original MSB if count 1, else 0
	and	1		; E = CF
	ld	e,a
	ld	a,(SHCNT)	; count 1?
	dec	a
	jr	nz,SH16_FLAGS	; count above 1: OF = 0
	ld	a,(SHORIG+1)	; count 1: the operand's bit 15 before the shift
	and	80h		; bit 15 alone
	rrca			; bit 7 -> bit 2 (V)
	rrca
	rrca
	rrca
	rrca
	or	e		; E = OF | CF
	ld	e,a
	jr	SH16_FLAGS	; common shift tail
SAR16F:
	sbc	a,a		; OF = 0
	and	1
	ld	e,a		; E = CF only
SH16_FLAGS:				; (src: SHE16)
	ld	a,h		; SF = bit 15 of the result (bit 7 of F)
	and	80h		; bit 15 = SF
	or	e		; E |= SF
	ld	e,a
	ld	a,h		; ZF if the whole word is 0
	or	l
	jr	nz,SH16_STORE	; nonzero: ZF stays 0
	set	6,e		; ZF
SH16_STORE:				; (src: SHE161)
	ld	d,l		; A' = low byte: PF from it
	pop	af		; the old flags are not wanted: shifts set all
	push	de		; the new flags in AF' (H = AF = 0)
	pop	af
	ex	af,af'		; AF' = the 8086 flags
	ex	de,hl		; DE = result
	pop	hl		; HL = operand address
	ld	(hl),e		; store the word
	inc	hl
	ld	(hl),d		; high byte
	jp	(ix)		; next instruction

; ---- 8-bit rotates -------------------------------------------------
ROT8A:
	sbc	a,a		; OF = bit 7 ^ CF (ROL, RCL)
	and	1		; E = CF
	ld	e,a
	ld	a,l		; bit 7 to bit 0
	rlca
	xor	e		; XOR CF
	and	1		; OF alone
	rlca			; to bit 2 (V)
	rlca
	or	e		; E = OF | CF
	ld	e,a
	jr	ROT8_DONE	; common rotate tail
ROT8B:
	sbc	a,a		; OF = bit 7 ^ bit 6 (ROR, RCR)
	and	1		; E = CF
	ld	e,a
	ld	a,l		; bit 6 up to bit 7
	add	a,a		; bit 6 -> bit 7
	xor	l		; XOR bit 7
	and	80h		; OF alone, in bit 7
	rlca			; bit 7 round to bit 2 (V)
	rlca
	rlca
	or	e		; E = OF | CF
	ld	e,a
ROT8_DONE:				; (src: ROTE8)
	ld	d,l		; D = result (no need for TMP: one byte)
	pop	hl		; L = old F'
	ld	a,l		; old flags
	and	0FAh		; new OF and CF, the rest kept
	or	e
	ld	l,a
	push	hl		; back into AF'
	pop	af
	ex	af,af'		; AF' = the 8086 flags
	pop	hl		; operand address
	ld	(hl),d		; store the byte
	jp	(ix)		; next instruction

; ---- 8-bit shifts --------------------------------------------------
SHL8F:
	sbc	a,a		; OF = bit 7 ^ CF
	and	1		; E = CF
	ld	e,a
	ld	a,l		; bit 7 to bit 0
	rlca
	xor	e		; XOR CF
	and	1		; OF alone
	rlca			; to bit 2 (V)
	rlca
	or	e		; E = OF | CF
	ld	e,a
	jr	SH8_FLAGS	; common shift tail
SHR8F:
	sbc	a,a		; OF = original bit 7 if count 1, else 0
	and	1
	ld	e,a		; E = CF
	ld	a,(SHCNT)	; count 1?
	dec	a
	jr	nz,SH8_FLAGS	; count above 1: OF = 0
	ld	a,(SHORIG)	; the byte operand before the shift
	and	80h		; bit 7 alone
	rrca			; bit 7 -> bit 2 (V)
	rrca
	rrca
	rrca
	rrca
	or	e		; E = OF | CF
	ld	e,a
	jr	SH8_FLAGS	; common shift tail
SAR8F:
	sbc	a,a		; OF = 0
	and	1
	ld	e,a		; E = CF only
SH8_FLAGS:				; (src: SHE8)
	ld	a,l		; SF from bit 7
	and	80h		; bit 7 = SF
	or	e		; E |= SF
	ld	e,a
	ld	a,l		; ZF if the byte is 0
	or	a
	jr	nz,SH8_STORE	; nonzero: ZF stays 0
	set	6,e		; ZF
SH8_STORE:				; (src: SHE81)
	ld	d,l		; A' = the result: PF from it
	pop	af		; discard the old flags
	push	de		; the new flags in AF'
	pop	af
	ex	af,af'		; AF' = the 8086 flags
	pop	hl		; operand address
	ld	(hl),d		; store the byte
	jp	(ix)		; next instruction

; =====================================================================
; O_AAM (D4h ib) - ASCII adjust after multiply: AH = AL / ib, AL = AL mod ib
; ---------------------------------------------------------------------
; Entry:  BC -> the imm8 base (0Ah in the documented form).
; Exit:   AX set; S Z PF from AL (SZP8), CF OF AF kept.  Base 0: INT 0
;         with IP past the instruction.
; Corrupts: A, DE, HL; DIVISOR.
;
; DIVU in its 8-bit mode (A = 8) divides HL:D by DIVISOR: HL = 0, D =
; AL.  HL < divisor holds, so the quotient fits E and the remainder L.
; Mirrors cpu86.py op_aam (which also keeps CF OF AF, undefined on the
; 8086).
; =====================================================================
O_AAM:
	ld	a,(bc)		; the base
	inc	bc		; past it first: INT 0 returns after AAM
	or	a		; base 0?
	jp	z,DIVERR	; base 0: divide error
	ld	e,a		; DIVISOR = base, as a word
	ld	d,0
	ld	(DIVISOR),de
	ld	a,(R_AL)	; dividend HL:D = 0:AL (E is shifted in as
	ld	d,a		;   quotient bits)
	ld	e,0
	ld	hl,0		; high half of the dividend: 0
	ld	a,8		; 8 quotient bits
	call	DIVU		; E = quotient, L = remainder
	ld	a,e		; quotient
	ld	(R_AH),a	; AH = AL / base
	ld	a,l		; remainder
	ld	(R_AL),a	; AL = AL mod base
	jp	SZP8		; S Z PF from AL, then NEXT

; =====================================================================
; O_AAD (D5h ib) - ASCII adjust before divide: AL = AH * ib + AL, AH = 0
; ---------------------------------------------------------------------
; Entry:  BC -> the imm8 base.
; Exit:   AX set; S Z PF from AL, CF OF AF kept.
; Corrupts: A, DE, HL.
;
; Only the low byte of MULU16's product matters: the sum is taken
; modulo 256, as on the 8086.  MULU16 preserves BC.  Mirrors cpu86.py
; op_aad.
; =====================================================================
O_AAD:
	ld	a,(bc)		; DE = base
	inc	bc		; IP past the base
	ld	e,a
	ld	d,0
	ld	a,(R_AH)	; HL = AH
	ld	l,a
	ld	h,0
	call	MULU16		; DE:HL = AH * base; L is all that counts
	ld	a,(R_AL)	; AL += low byte of the product
	add	a,l
	ld	(R_AL),a	; AL = AH * base + AL, mod 256
	ld	l,a		; keep AL over the clearing of AH
	xor	a
	ld	(R_AH),a	; AH = 0
	ld	a,l		; SZP8 takes the value in A
	jp	SZP8		; S Z PF from AL

; =====================================================================
; O_SALC (D6h) - AL = FFh if CF, else 00h (undocumented 8086 opcode)
; ---------------------------------------------------------------------
; Entry/exit: -.  Flags unchanged.  Corrupts: A.
; Mirrors cpu86.py op_salc.
; =====================================================================
O_SALC:
	ex	af,af'		; the 8086 flags in, CF = Z80 carry ...
	push	af		; ... but A' (the PF byte) must survive
	sbc	a,a		; A = 00h or FFh from CF
	ld	(R_AL),a	; AL = 00h / FFh
	pop	af		; A' back, flags untouched
	ex	af,af'
	jp	(ix)		; next instruction

; =====================================================================
; O_XLAT (D7h) - AL = [DS:BX + AL] (segment prefix honoured)
; ---------------------------------------------------------------------
; Entry/exit: -.  Flags unchanged.  Corrupts: A, DE, HL.
;
; BX + AL is formed in 16 bits first, so the offset wraps inside the
; segment exactly as on the 8086; EADS is DS's base, or the prefix's.
; Mirrors cpu86.py op_xlat.
; =====================================================================
O_XLAT:
	ld	hl,(R_BX)	; HL = BX + AL, the 16-bit offset
	ld	a,(R_AL)
	add	a,l
	ld	l,a
	jr	nc,XLAT_ADD	; no carry out of the low byte
	inc	h		; carry into the high byte
XLAT_ADD:				; (src: XLAT1)
	ld	de,(EADS)	; + the DS (or override) base
	add	hl,de		; host address of the table byte
	ld	a,(hl)		; the table byte
	ld	(R_AL),a	; AL = it
	jp	(ix)		; next instruction (or RESTORE after a prefix)

; =====================================================================
; O_ESC (D8h-DFh) - coprocessor escape: decode the operand, do nothing
; ---------------------------------------------------------------------
; Entry:  BC -> the ModR/M byte.
; Exit:   BC past the ModR/M and any displacement.  Corrupts: A, DE, HL.
;
; There is no 8087 and no emulation of one: EAW is called only to eat
; the displacement bytes (the EAMEM routines read them from BC), so the
; next instruction is found.  Mirrors cpu86.py op_esc (modrm() only).
; =====================================================================
O_ESC:
	ld	a,(bc)		; the ModR/M byte
	inc	bc		; IP past the ModR/M
	call	EAW		; consumes the displacement; HL unused
	jp	(ix)		; nothing else happens

; =====================================================================
; OPCODES E0h-EFh - the table row decoded
; ---------------------------------------------------------------------
;   E0 LOOPNZ  E1 LOOPZ   E2 LOOP    E3 JCXZ    E4 INB    E5 INW   E6 OUTI E7 OUTI
;   E8 CALLN   E9 JMPN    EA JMPF    EB O_JREL8 EC INDXB  ED INDXW EE NOP  EF NOP
; =====================================================================

; =====================================================================
; O_LOOPNZ / O_LOOPZ / O_LOOP / O_JCXZ (E0h-E3h) - CX-counted short jumps
; ---------------------------------------------------------------------
; Entry:  BC -> the rel8.
; Exit:   CX decremented (not by JCXZ); taken: BC += rel8 via JREL8 (or
;         J_TAKE, which first swaps AF' back); not taken: BC past the
;         rel8.  Flags never changed.
; Corrupts: A, HL (DE untouched).
;
; LOOPZ / LOOPNZ test the 8086 ZF by swapping AF' in, then leave by the
; Jcc exits J_TAKE / J_NOT (part 03), which swap it out again; the
; zero test on CX uses only the main F, which is scratch.  Mirrors
; cpu86.py op_loop.
; =====================================================================
O_LOOPNZ:
	ld	hl,(R_CX)	; CX -= 1 (no flags: LOOP changes none)
	dec	hl
	ld	(R_CX),hl	; CX stored
	ld	a,h		; CX = 0: fall through whatever ZF says
	or	l		; CX = 0?
	jr	z,LOOPX		; CX = 0: done
	ex	af,af'		; the 8086 ZF in
	jp	nz,J_TAKE	; ZF = 0: jump (J_TAKE swaps AF' back)
	jp	J_NOT		; ZF = 1: fall through (J_NOT swaps back)
O_LOOPZ:
	ld	hl,(R_CX)	; CX -= 1
	dec	hl
	ld	(R_CX),hl	; CX stored
	ld	a,h		; CX = 0?
	or	l
	jr	z,LOOPX		; CX = 0: fall through
	ex	af,af'		; the 8086 ZF in
	jp	z,J_TAKE	; ZF = 1: jump
	jp	J_NOT		; ZF = 0: fall through
LOOPX:
	inc	bc		; not taken: skip the rel8
	jp	(ix)		; flags untouched
O_LOOP:
	ld	hl,(R_CX)	; CX -= 1
	dec	hl
	ld	(R_CX),hl	; CX stored
	ld	a,h		; jump while CX <> 0 (AF' never touched, so
	or	l		;   JREL8 rather than J_TAKE)
	jp	nz,JREL8	; taken: BC += rel8
	inc	bc		; CX = 0: skip the rel8
	jp	(ix)		; flags untouched
O_JCXZ:
	ld	hl,(R_CX)	; jump if CX = 0, CX unchanged
	ld	a,h
	or	l		; CX = 0?
	jp	z,JREL8		; taken: BC += rel8
	inc	bc		; CX <> 0: skip the rel8
	jp	(ix)		; flags untouched

; =====================================================================
; O_INB / O_INDXB / O_INW / O_INDXW / O_OUTI - port I/O (E4h-E7h, ECh,
; EDh; EEh / EFh OUT DX are O_NOP in the table)
; ---------------------------------------------------------------------
; Entry:  BC -> the port byte (E4h-E7h) or the next instruction (DX
;         forms).
; Exit:   IN: AL = FFh / AX = FFFFh.  OUT: nothing.  BC past the port
;         byte if there is one.  Corrupts: A, HL.
;
; Guest port I/O never reaches a Z80 port.  IN reads an empty bus
; (all ones), OUT goes nowhere; the port number is not even looked at.
; This is cpu86.py's default (port_in returns FFh / FFFFh, port_out
; does nothing), and is safe because IO.SYS does all its hardware work
; through traps: the FDC, the link on 2Fh, the latch E0h and the WD2123
; are touched only by the Z80 BIOS.  Provisional (never tried): a PC
; program that polls PC hardware would read every status bit as 1 -
; ready at once if it waits for a bit to set, hung if it waits for one
; to clear.
; =====================================================================
O_INB:
	inc	bc		; IN AL,imm8: skip the port; nothing there
O_INDXB:
	ld	a,0FFh		; IN AL,DX (and IN AL,imm8): the empty bus
	ld	(R_AL),a	; AL = FFh
	jp	(ix)		; flags untouched
O_INW:
	inc	bc		; IN AX,imm8: skip the port
O_INDXW:
	ld	hl,0FFFFh	; IN AX,DX: all ones
	ld	(R_AX),hl	; AX = FFFFh
	jp	(ix)		; flags untouched
O_OUTI:
	inc	bc		; OUT imm8,AL/AX: skip the port, write nothing
	jp	(ix)		; flags untouched

; =====================================================================
; O_CALLN (E8h rel16) - near relative call
; ---------------------------------------------------------------------
; Entry:  BC -> the rel16.
; Exit:   return IP pushed; BC = return address + rel16; to NEXT via
;         PUSHX.  Corrupts: A, DE, HL.
;
; The return IP is BC - B_CS (GETIP written out).  The target is formed
; as a host address, BC + rel16 modulo 64K; that equals CS base +
; ((IP + rel16) mod 64K) whenever the result lies in guest memory - the
; segment-wrap limit stated in I86.ASM's header.  Mirrors cpu86.py
; op_call.
; =====================================================================
O_CALLN:
	ld	a,(bc)		; DE = rel16
	ld	e,a		; rel16 low
	inc	bc
	ld	a,(bc)		; rel16 high
	ld	d,a
	inc	bc		; BC = host address of the return point
	ld	hl,(B_CS)	; HL = return IP = BC - CS base
	ld	a,c
	sub	l		; IP low = C - base low
	ld	l,a
	ld	a,b
	sbc	a,h		; IP high, with the borrow
	ld	h,a		; HL = return IP
	push	hl		; parked while BC moves
	ex	de,hl		; BC += rel16: the target
	add	hl,bc		; target = return point + rel16
	ld	b,h
	ld	c,l		; BC = target
	pop	de		; DE = return IP
	jp	PUSHX		; push it, then NEXT

; =====================================================================
; O_JMPN (E9h rel16) - near relative jump
; ---------------------------------------------------------------------
; Entry:  BC -> the rel16.  Exit: BC += 2 + rel16.  Corrupts: A, DE, HL.
; Same host-address arithmetic as O_CALLN.  Mirrors cpu86.py op_jmp.
; =====================================================================
O_JMPN:
	ld	a,(bc)		; DE = rel16
	ld	e,a		; rel16 low
	inc	bc
	ld	a,(bc)		; rel16 high
	ld	d,a
	inc	bc		; relative to the next instruction
	ld	h,b		; HL = BC + rel16
	ld	l,c
	add	hl,de		; HL = target host address
	ld	b,h		; BC = target
	ld	c,l
	jp	(ix)		; flags untouched

; =====================================================================
; O_JMPF (EAh ptr16:16) - direct far jump
; ---------------------------------------------------------------------
; Entry:  BC -> the new IP, then the new CS.
; Exit:   via FARJ: R_CS, B_CS = CS << 4, BC = B_CS + IP.
; Corrupts: A, DE, HL.
; Mirrors cpu86.py op_jmp_far.
; =====================================================================
O_JMPF:
	ld	a,(bc)		; DE = new IP
	ld	e,a		; IP low
	inc	bc
	ld	a,(bc)		; IP high
	ld	d,a		; DE = IP
	inc	bc
	ld	a,(bc)		; HL = new CS
	ld	l,a		; CS low byte
	inc	bc
	ld	a,(bc)		; CS high byte
	ld	h,a		; (BC not advanced: FARJ replaces it)
	jp	FARJ		; CS, its base and BC, then NEXT
; ============================================================ F0-FF
;
; The last opcode row: the flag instructions F5h and F8h-FDh, the two
; "group 3" opcodes F6h / F7h (TEST NOT NEG MUL IMUL DIV IDIV), the
; arithmetic helpers they share (MULU16, DIVU, SDIV), and the groups FEh
; / FFh (INC DEC CALL CALLF JMP JMPF PUSH).  F0h LOCK, F2h/F3h REP and F4h
; HLT live elsewhere (O_LOCK = NEXT2, O_REP, O_HLT).
;
; The flag model, which every handler here touches (I86.ASM header):
; AF' holds the 8086 arithmetic flags in the Z80 positions - S, Z, H as
; AF, P/V as OF, C as CF - and A' is the low byte of the last result,
; whose parity is PF (GETF computes it on demand).  So a handler sets
; flags by finishing a Z80 operation on the result in A and doing
; EX AF,AF'; it leaves them alone by never touching AF'.
; TF IF DF live apart, in FLAGHI bits 0-2 (FLAGS bits 8-10).
;
; Operand pointers: EAB / EAW return in HL a HOST address - into guest
; memory or into REGS for a register operand - so every handler below
; works on (HL) without caring which.

; =====================================================================
; O_CMC / O_CLC / O_STC - F5h CMC, F8h CLC, F9h STC
; ---------------------------------------------------------------------
; Entry:  from NEXT (A = opcode, unused).
; Exit:   JP (IX); CF in F' complemented / cleared / set, everything
;         else in AF' (A' = the PF byte included) unchanged.
; Corrupts: HL.
; The 8086 flags are fetched from AF' into L through the stack, bit 0
; (Z80 C = 8086 CF) is edited, and FLSET puts them back.  Mirrors
; cpu86.py op_cmc / op_flagop (verified).
; =====================================================================
O_CMC:
	ex	af,af'		; the 8086 flags into AF ...
	push	af		; ... and through the stack ...
	pop	hl		; ... into HL: H = PF byte, L = flags
	ld	a,l		; (A is free: the PF byte is safe in H)
	xor	1		; CF = NOT CF
	ld	l,a		; edited flags
	jr	FLSET		; put them back
O_CLC:
	ex	af,af'		; 8086 flags -> HL, as above
	push	af	; flags -> HL
	pop	hl		; L = flags
	res	0,l		; CF = 0
	jr	FLSET		; put them back
O_STC:
	ex	af,af'		; 8086 flags -> HL, as above
	push	af	; flags -> HL
	pop	hl		; L = flags
	set	0,l		; CF = 1
FLSET:
	push	hl		; edited flags (and the untouched PF byte) ...
	pop	af		; ... into AF ...
	ex	af,af'		; ... and back where the 8086 flags live
	jp	(ix)		; next instruction

; =====================================================================
; O_CLI / O_STI / O_CLD / O_STD - FAh, FBh, FCh, FDh
; ---------------------------------------------------------------------
; Entry:  from NEXT.
; Exit:   JP (IX); FLAGHI bit 1 (IF) or bit 2 (DF) changed.
; Corrupts: HL; CLD / STD also A, DE (SETSTEP).
; IF is bookkeeping only: nothing in Z86.SYS tests FLAGHI bit 1 - the
; guest never receives a hardware interrupt - so CLI / STI only change
; what PUSHF, INT and the BIOS traps see.  DF matters at once: SETSTEP
; turns it into the string-op strides STEP1 / STEP2 (+-1 / +-2), so the
; string handlers never test DF themselves.  Mirrors cpu86.py op_flagop.
; =====================================================================
O_CLI:
	ld	hl,FLAGHI	; the TF IF DF byte
	res	1,(hl)		; IF = 0 (recorded, never acted on)
	jp	(ix)		; next instruction
O_STI:
	ld	hl,FLAGHI	; the TF IF DF byte
	set	1,(hl)		; IF = 1 (recorded, never acted on)
	jp	(ix)		; next instruction
O_CLD:
	ld	hl,FLAGHI	; the TF IF DF byte
	res	2,(hl)		; DF = 0: strings go up ...
	call	SETSTEP		; ... STEP1 = +1, STEP2 = +2
	jp	(ix)		; next instruction
O_STD:
	ld	hl,FLAGHI	; the TF IF DF byte
	set	2,(hl)		; DF = 1: strings go down ...
	call	SETSTEP		; ... STEP1 = -1, STEP2 = -2
	jp	(ix)		; next instruction

; =====================================================================
; O_GRP3B - F6h: TEST/NOT/NEG/MUL/IMUL/DIV/IDIV r/m8
; ---------------------------------------------------------------------
; Entry:  from NEXT; BC at the ModR/M byte.
; Exit:   to G3BT entry reg (bits 5-3 of ModR/M) with HL = host pointer
;         to the r/m8 operand and BC past ModR/M and any displacement
;         (a TEST immediate is still to come).
; Corrupts: A, DE, HL.
; EAB computes the operand address (and may fetch a displacement); the
; ModR/M byte rides the stack across it.  (op AND 38h) RRCA RRCA =
; reg * 2, the byte offset of a DW entry, and JTAB jumps there keeping
; HL.  Mirrors cpu86.py op_grp3 with w = 0.
; =====================================================================
O_GRP3B:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; keep it: EAB uses A and DE
	call	EAB		; HL -> the r/m8 operand (register or memory)
	pop	af		; ModR/M back
	and	38h		; reg field ...
	rrca
	rrca			; ... * 2 = offset into the table
	ld	de,G3BT		; the byte-group table
	jp	JTAB		; jump to entry reg, HL kept

; G3BT - group F6h by the ModR/M reg field (reached only via JTAB):
;   /0 TEST r/m8,imm8   /1 TEST (undocumented alias, as on the 8086 and
;   in cpu86.py)        /2 NOT   /3 NEG   /4 MUL (AX = AL * r/m8)
;   /5 IMUL   /6 DIV (AL = AX / r/m8, AH = remainder)   /7 IDIV
G3BT:
	defw	G3B_TEST, G3B_TEST, G3B_NOT, G3B_NEG, G3B_MUL, G3B_IMUL, G3B_DIV, G3B_IDIV

; ---- /0 /1 TEST r/m8,imm8: flags of r/m8 AND imm8, nothing stored ----
; Z80 AND leaves H = 1 and P/V = parity, which here would read as AF = 1
; and OF = parity.  ADD A,0 recomputes S and Z from the same value with
; H = V = C = 0: exactly the 8086's AF = OF = CF = 0.
G3B_TEST:
	ld	a,(bc)		; the immediate follows ModR/M + displacement
	inc	bc		; past it: BC = next instruction
	and	(hl)		; the test itself, operand untouched
	add	a,0		; clear H, V, C; S and Z from the result
	ex	af,af'		; flags out, A' = result for PF
	jp	(ix)		; next instruction

; ---- /2 NOT r/m8: flags untouched (AF' never visited) ----
G3B_NOT:
	ld	a,(hl)		; operand ...
	cpl			; ... complemented ...
	ld	(hl),a		; ... in place
	jp	(ix)		; next instruction

; ---- /3 NEG r/m8: 0 - operand, all flags as SUB ----
; The Z80 SUB gives CF = (operand <> 0), OF on 80h, AF from the bit-3
; borrow: the 8086's NEG flags exactly (cpu86.py: alu(5,0,v), CF = v<>0).
G3B_NEG:
	xor	a		; 0 ...
	sub	(hl)		; ... - operand, flags as the 8086's
	ld	(hl),a		; result in place (LD keeps the flags)
	ex	af,af'		; flags out, A' = result for PF
	jp	(ix)		; next instruction

; ---- /4 MUL r/m8: AX = AL * r/m8 (unsigned) ----
G3B_MUL:
	ld	e,(hl)		; DE = operand, zero-extended
	ld	d,0
	ld	a,(R_AL)	; HL = AL, zero-extended
	ld	l,a	; (MULU16's first factor)
	ld	h,0
	call	MULU16		; product fits HL (DE = 0)
	ld	(R_AX),hl	; the whole of AX
	ld	a,h		; CF = OF = (AH <> 0) ...
	or	a		; ... as Z80 NZ
	call	SETCO		; S Z AF PF left as they were (cpu86.py too)
	jp	(ix)		; next instruction

; ---- /5 IMUL r/m8: AX = AL * r/m8 (signed) ----
; Both factors are sign-extended to 16 bits; the low 16 bits of the
; unsigned product of two's-complement words are the signed product.
G3B_IMUL:
	ld	a,(hl)		; operand
	ld	e,a
	add	a,a		; its sign into carry ...
	sbc	a,a		; ... 00h / FFh
	ld	d,a		; DE = operand, sign-extended
	ld	a,(R_AL)	; AL ...
	ld	l,a	; (MULU16's first factor)
	add	a,a
	sbc	a,a
	ld	h,a		; ... HL = AL, sign-extended
	call	MULU16		; HL = the 16-bit signed product
	ld	(R_AX),hl	; the whole of AX
	ld	a,l		; A = sign extension of AL (00h / FFh) ...
	add	a,a
	sbc	a,a	; (00h / FFh)
	xor	h		; ... NZ when AH is not it: the product needs
	call	SETCO		;   16 bits, CF = OF = 1
	jp	(ix)		; next instruction

; ---- /6 DIV r/m8: AL = AX / r/m8, AH = AX mod r/m8 (unsigned) ----
; Divisor 0 or quotient over 8 bits -> INT 0 (DIVERR).  The quotient
; exceeds FFh exactly when AH >= divisor, so the check is made before
; dividing; it also guarantees DIVU's entry condition HL < divisor.
G3B_DIV:
	ld	a,(hl)		; divisor
	or	a		; zero?
	jp	z,DIVERR	; divide by zero: INT 0
	ld	e,a		; divisor, zero-extended ...
	ld	d,0
	ld	(DIVISOR),de	; ... where DIVU reads it
	ld	a,(R_AH)	; dividend high byte
	cp	e	; compare with the divisor
	jp	nc,DIVERR	; AH >= divisor: quotient > FFh, INT 0
	ld	l,a		; DIVU's 8-bit form: high part HL = AH ...
	ld	h,0	; (< divisor, checked)
	ld	a,(R_AL)	; ... low part D = AL, E = 0
	ld	d,a
	ld	e,0	; (E's zeros feed D, unused)
	ld	a,8		; 8 quotient bits
	call	DIVU		; E = quotient, L = remainder
	ld	a,e		; AL = quotient
	ld	(R_AL),a
	ld	a,l		; AH = remainder
	ld	(R_AH),a
	jp	(ix)		; flags unchanged (undefined on the 8086)

; ---- /7 IDIV r/m8: AL = AX / r/m8, AH = remainder (signed) ----
; Widened to SDIV's 32 / 16 form: divisor sign-extended to 16 bits,
; AX to 32.  SDIV returns magnitudes; the quotient must then fit
; -80h..7Fh, and the signs are put back (quotient: QNEG, remainder:
; RNEG, the sign of the dividend - truncating division, as cpu86.py).
G3B_IDIV:
	ld	a,(hl)		; divisor
	or	a		; zero?
	jp	z,DIVERR	; divide by zero: INT 0
	ld	l,a		; HL = divisor, sign-extended ...
	add	a,a
	sbc	a,a	; (00h / FFh)
	ld	h,a
	ld	(DIVISOR),hl	; ... for SDIV
	ld	de,(R_AX)	; dividend low word = AX ...
	ld	a,d	; AX high byte's sign ...
	add	a,a
	sbc	a,a		; ... high word = AX's sign, 0000h / FFFFh
	ld	h,a
	ld	l,a	; (HL:DE = AX, 32 bits)
	call	SDIV		; DE = |q|, HL = |r|
	jp	c,DIVERR	; cannot happen here (|AX| < 10000h), kept
	ld	a,d		; |q| must fit 8 bits ...
	or	a	; (D <> 0: |q| >= 100h)
	jp	nz,DIVERR	; ... or INT 0
	ld	a,(QNEG)	; quotient sign
	rla			; quotient sign into carry
	ld	a,e		; A = |q| (LD keeps the carry)
	jr	c,G3B_IDIV_QNEG	; negative quotient: other limit
	cp	80h		; positive: at most 7Fh
	jp	nc,DIVERR	; 80h and up: INT 0
	jr	G3B_IDIV_STQ	; store it
G3B_IDIV_QNEG:				; (src: G3BID1)
	cp	81h		; negative: at most 80h (-128; see findings:
	jp	nc,DIVERR	;   a real 8086 traps that one too)
	neg			; back to two's complement
G3B_IDIV_STQ:				; (src: G3BID2)
	ld	(R_AL),a	; AL = quotient
	ld	a,(RNEG)	; remainder sign = dividend sign
	rla			; dividend sign into carry
	ld	a,l		; A = |r|
	jr	nc,G3B_IDIV_STR	; positive: store as is
	neg			; remainder takes the dividend's sign
G3B_IDIV_STR:				; (src: G3BID3)
	ld	(R_AH),a	; AH = remainder
	jp	(ix)		; flags unchanged

; =====================================================================
; O_GRP3W - F7h: TEST/NOT/NEG/MUL/IMUL/DIV/IDIV r/m16
; ---------------------------------------------------------------------
; Entry:  from NEXT; BC at the ModR/M byte.
; Exit:   to G3WT entry reg, HL = host pointer to the r/m16 operand
;         (low byte), BC past ModR/M and displacement.
; Corrupts: A, DE, HL.
; As O_GRP3B with EAW.  Mirrors cpu86.py op_grp3 with w = 1.
; =====================================================================
O_GRP3W:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across EAW
	call	EAW		; HL -> the r/m16 operand
	pop	af		; ModR/M back
	and	38h		; reg field * 2 ...
	rrca
	rrca
	ld	de,G3WT		; ... into the word table
	jp	JTAB		; jump to entry reg, HL kept

; G3WT - group F7h by reg (reached only via JTAB): the same eight as
; G3BT, word sized: MUL / IMUL give DX:AX = AX * r/m16, DIV / IDIV
; AX = DX:AX / r/m16 with DX = remainder.
G3WT:
	defw	G3W_TEST, G3W_TEST, G3W_NOT, G3W_NEG, G3W_MUL, G3W_IMUL, G3W_DIV, G3W_IDIV

; ---- /0 /1 TEST r/m16,imm16 ----
G3W_TEST:
	ld	a,(bc)		; immediate low byte ...
	inc	bc	; BC = next instruction
	and	(hl)		; ... AND operand low byte
	ld	e,a
	inc	hl		; operand high byte
	ld	a,(bc)		; immediate high byte ...
	inc	bc		; BC = next instruction
	and	(hl)		; ... AND operand high byte
	ld	d,a		; DE = result, not stored
	jp	LOGF16		; S Z PF from DE, OF = CF = AF = 0, JP (IX)

; ---- /2 NOT r/m16: flags untouched ----
G3W_NOT:
	ld	a,(hl)		; low byte complemented in place
	cpl	; high byte complemented
	ld	(hl),a	; (flags untouched)
	inc	hl		; high byte, the same
	ld	a,(hl)
	cpl	; high byte complemented
	ld	(hl),a
	jp	(ix)		; next instruction

; ---- /3 NEG r/m16: 0 - operand ----
; SBC HL gives S Z OF and CF = (operand <> 0) as the 8086; AF is the
; Z80's bit-11 half-borrow (the documented 16-bit AF difference).
G3W_NEG:
	push	hl		; operand address, for the store
	ld	e,(hl)		; DE = operand
	inc	hl	; (high byte)
	ld	d,(hl)
	ld	hl,0		; 0 ...
	or	a		; (no borrow in)
	sbc	hl,de		; ... - operand, flags as the 8086's
	ld	a,l		; A' must be the low byte, for PF
	ex	af,af'		; flags out
	ex	de,hl		; DE = result
	pop	hl		; operand address
	ld	(hl),e		; store the result
	inc	hl
	ld	(hl),d	; (high byte)
	jp	(ix)		; next instruction

; ---- /4 MUL r/m16: DX:AX = AX * r/m16 (unsigned) ----
G3W_MUL:
	ld	e,(hl)		; DE = operand
	inc	hl
	ld	d,(hl)	; (high byte)
	ld	hl,(R_AX)	; times AX
	call	MULU16		; DE:HL = product
	ld	(R_AX),hl	; low word
	ld	(R_DX),de	; high word
	ld	a,d		; CF = OF = (DX <> 0)
	or	e	; product's high word zero?
	call	SETCO		; other flags kept
	jp	(ix)		; next instruction

; ---- /5 IMUL r/m16: DX:AX = AX * r/m16 (signed) ----
; The unsigned 32-bit product, then the high word corrected:
;   signed high = unsigned high - (a < 0 ? b : 0) - (b < 0 ? a : 0)
; (mod 10000h), a = AX, b = operand, kept in TMP2 / TMP.
G3W_IMUL:
	ld	e,(hl)		; DE = operand
	inc	hl
	ld	d,(hl)	; (high byte)
	ld	(TMP),de	; b, the operand
	ld	hl,(R_AX)	; multiplicand AX
	ld	(TMP2),hl	; a, AX
	call	MULU16		; DE:HL = a * b, unsigned
	ld	(R_AX),hl	; the low word needs no correction
	ex	de,hl		; HL = high word, unsigned
	ld	a,(TMP2+1)	; sign of a
	rla			; a negative?
	jr	nc,G3W_IMUL_FIXB
	ld	de,(TMP)	; then subtract b
	or	a
	sbc	hl,de	; high -= b
G3W_IMUL_FIXB:				; (src: G3WIM1)
	ld	a,(TMP+1)	; sign of b
	rla			; b negative?
	jr	nc,G3W_IMUL_STORE
	ld	de,(TMP2)	; then subtract a
	or	a
	sbc	hl,de	; high -= a
G3W_IMUL_STORE:				; (src: G3WIM2)
	ld	(R_DX),hl	; signed high word
	ld	a,(R_AH)	; E = sign extension of AX (00h / FFh)
	add	a,a	; (00h or FFh)
	sbc	a,a
	ld	e,a
	xor	h		; NZ unless DX = that extension:
	ld	d,a		;   (ext XOR DH) OR (ext XOR DL)
	ld	a,e
	xor	l	; ext XOR DL
	or	d	; OR'ed: NZ = mismatch
	call	SETCO		; CF = OF = product needs 32 bits
	jp	(ix)		; next instruction

; ---- /6 DIV r/m16: AX = DX:AX / r/m16, DX = remainder (unsigned) ----
G3W_DIV:
	ld	e,(hl)		; DE = divisor
	inc	hl
	ld	d,(hl)	; (high byte)
	ld	a,d		; zero?
	or	e	; divisor zero?
	jp	z,DIVERR	; divide by zero: INT 0
	ld	(DIVISOR),de	; where DIVU reads it
	ld	hl,(R_DX)	; dividend high word
	or	a		; (A <> 0 here, but OR A is for the carry)
	sbc	hl,de	; C = DX < divisor
	jp	nc,DIVERR	; DX >= divisor: quotient over 16 bits, INT 0
	add	hl,de		; HL = DX again (and < divisor, as DIVU wants)
	ld	de,(R_AX)	; dividend HL:DE = DX:AX
	ld	a,16		; 16 quotient bits
	call	DIVU		; DE = quotient, HL = remainder
	ld	(R_AX),de	; AX = quotient
	ld	(R_DX),hl	; DX = remainder
	jp	(ix)		; flags unchanged

; ---- /7 IDIV r/m16: AX = DX:AX / r/m16, DX = remainder (signed) ----
; SDIV gives magnitudes, already checked to fit 16 bits; the quotient
; must then be <= 7FFFh if positive, <= 8000h if negative.
G3W_IDIV:
	ld	e,(hl)		; DE = divisor
	inc	hl
	ld	d,(hl)	; (high byte)
	ld	a,d		; zero?
	or	e	; divisor zero?
	jp	z,DIVERR	; divide by zero: INT 0
	ld	(DIVISOR),de	; for SDIV
	ld	hl,(R_DX)	; dividend HL:DE = DX:AX
	ld	de,(R_AX)	; (dividend low word)
	call	SDIV		; DE = |q|, HL = |r|
	jp	c,DIVERR	; |q| over 16 bits: INT 0
	ld	a,(QNEG)
	rla			; quotient sign into carry
	jr	c,G3W_IDIV_QNEG	; negative: other limit
	bit	7,d		; positive: |q| <= 7FFFh
	jp	nz,DIVERR	; > 7FFFh: INT 0
	jr	G3W_IDIV_STQ	; store it
G3W_IDIV_QNEG:				; (src: G3WID1)
	ld	a,d		; negative: |q| <= 8000h
	cp	80h	; high byte vs 80h
	jr	c,G3W_IDIV_NEGQ	; high byte below 80h: fits
	jp	nz,DIVERR	; above 80h: too big
	ld	a,e		; exactly 80xxh: only 8000h fits (-32768;
	or	a		;   a real 8086 traps it - see findings)
	jp	nz,DIVERR	; 81h-FFh high byte: INT 0
G3W_IDIV_NEGQ:				; (src: G3WID0)
	xor	a		; DE = -DE: low byte 0 - E ...
	sub	e	; (low byte)
	ld	e,a
	sbc	a,a		; ... high byte -borrow - D
	sub	d	; (high byte)
	ld	d,a
G3W_IDIV_STQ:				; (src: G3WID2)
	ld	(R_AX),de	; AX = quotient
	ld	a,(RNEG)	; remainder sign = dividend sign
	rla			; dividend negative?
	jr	nc,G3W_IDIV_STR	; positive: store as is
	xor	a		; then HL = -HL, the same way
	sub	l	; (low byte)
	ld	l,a
	sbc	a,a
	sub	h	; (high byte)
	ld	h,a
G3W_IDIV_STR:				; (src: G3WID3)
	ld	(R_DX),hl	; DX = remainder, with the dividend's sign
	jp	(ix)		; flags unchanged

; =====================================================================
; MULU16 - unsigned 16 x 16 -> 32 multiply
; ---------------------------------------------------------------------
; Entry:  HL, DE = the factors.
; Exit:   DE:HL = HL * DE (DE high).  BC preserved.
; Corrupts: A, F.  AF' untouched.
; Callers: G3B_MUL, G3B_IMUL, G3W_MUL, G3W_IMUL, O_AAD (E744h).
; Shift-and-add over the 32-bit DE:HL: DE starts as the multiplier and
; is shifted out at the top one bit per pass while the partial product
; grows in from below; each 1 bit adds the multiplicand (BC) to HL,
; carrying into DE.
; =====================================================================
MULU16:
	push	bc		; BC is the 8086 code pointer: keep it
	ld	b,h		; BC = multiplicand
	ld	c,l
	ld	hl,0		; partial product
	ld	a,16		; one pass per multiplier bit
MULU16_LOOP:				; (src: MULU1)
	add	hl,hl		; DE:HL <<= 1 ...
	rl	e	; (HL's top bit into DE)
	rl	d		; ... the multiplier's next bit into carry
	jr	nc,MULU16_NEXT	; bit clear: nothing to add
	add	hl,bc		; bit set: add the multiplicand ...
	jr	nc,MULU16_NEXT	; bit clear: no add
	inc	de		; ... and its carry into the high word
MULU16_NEXT:				; (src: MULU2)
	dec	a		; 16 passes
	jr	nz,MULU16_LOOP	; next bit
	pop	bc		; 8086 code pointer back
	ret	; DE:HL = product

; =====================================================================
; DIVU - unsigned restoring division
; ---------------------------------------------------------------------
; Entry:  HL:DE = dividend (A = 16), or HL:D (A = 8, E = 0);
;         (DIVISOR) = divisor, non-zero; HL < divisor (the caller's
;         overflow check), so the quotient fits A bits.
; Exit:   E (A = 8) or DE (A = 16) = quotient, HL = remainder.  BC kept.
; Corrupts: A, F.  AF' untouched.
; Callers: G3B_DIV (8), G3W_DIV (16), SDIV (16), O_AAM (8, E72Bh).
; One quotient bit per pass: the dividend shifts left out of DE into
; the partial remainder HL, the divisor is subtracted when it fits, and
; the quotient bit enters at E bit 0 (freed by the shift).
; =====================================================================
DIVU:
	push	bc		; keep the 8086 code pointer
	ld	bc,(DIVISOR)	; BC = divisor for the whole loop
DIVU_LOOP:				; (src: DIVU1)
	sla	e		; next dividend bit out of DE ...
	rl	d	; (D's top bit into HL)
	adc	hl,hl		; ... into the partial remainder
	jr	c,DIVU_BIG	; 17 bits: certainly >= divisor
	sbc	hl,bc		; (carry is 0 here) does the divisor fit?
	jr	nc,DIVU_QBIT	; yes: keep the difference, quotient bit 1
	add	hl,bc		; no: restore, quotient bit 0
	jr	DIVU_NEXT	; (skip the quotient bit)
DIVU_BIG:				; (src: DIVU2)
	or	a		; clear carry (A, the count, is unchanged)
	sbc	hl,bc		; wraps to the true remainder, < divisor
DIVU_QBIT:				; (src: DIVU3)
	inc	e		; quotient bit 1
DIVU_NEXT:				; (src: DIVU4)
	dec	a		; A passes
	jr	nz,DIVU_LOOP	; next bit
	pop	bc		; 8086 code pointer back
	ret	; DE/E = quotient, HL = remainder

; =====================================================================
; SDIV - signed 32 / 16 division, by magnitudes
; ---------------------------------------------------------------------
; Entry:  HL:DE = signed dividend, (DIVISOR) = signed divisor, non-zero.
; Exit:   Z80 C = 1: |quotient| needs more than 16 bits (caller: INT 0).
;         C = 0: DE = |quotient|, HL = |remainder|.
;         Either way RNEG bit 7 = dividend sign (= the remainder's),
;         QNEG bit 7 = quotient sign, (DIVISOR) = |divisor|.
; Corrupts: A, F.  BC kept (DIVU).  AF' untouched.
; Callers: G3B_IDIV, G3W_IDIV.
; Magnitudes are taken as unsigned values, so the extremes come out
; right: |-8000h| = 8000h and |-80000000h| = 80000000h.
; =====================================================================
SDIV:
	ld	a,h		; dividend sign ...
	ld	(RNEG),a	; ... is the remainder's sign
	rla			; negative?
	jr	nc,SDIV_DIVISOR	; positive: as it is
	xor	a		; |dividend|: 32-bit 0 - HL:DE, byte by byte
	sub	e	; (lowest byte)
	ld	e,a
	ld	a,0		; (LD keeps the borrow)
	sbc	a,d
	ld	d,a
	ld	a,0	; (LD keeps the borrow)
	sbc	a,l
	ld	l,a
	ld	a,0	; (LD keeps the borrow)
	sbc	a,h	; (highest byte)
	ld	h,a
SDIV_DIVISOR:				; (src: SDIV1)
	push	hl		; park |dividend| high
	ld	hl,(DIVISOR)	; signed divisor
	ld	a,(RNEG)	; dividend sign
	xor	h		; quotient negative = signs differ
	ld	(QNEG),a	; bit 7 = quotient sign
	bit	7,h		; divisor negative?
	jr	z,SDIV_CHECK	; positive: as it is
	xor	a		; |divisor| = -divisor ...
	sub	l	; low byte 0 - L
	ld	l,a
	sbc	a,a
	sub	h	; high byte -borrow - H
	ld	h,a
	ld	(DIVISOR),hl	; ... where DIVU will read it
SDIV_CHECK:				; (src: SDIV2)
	ex	(sp),hl		; HL = |dividend| high, (SP) = |divisor|
	ex	de,hl		; HL = low, DE = high
	ex	(sp),hl		; HL = |divisor|, (SP) = low
	ex	de,hl		; DE = |divisor|, HL = high
	or	a		; no borrow in
	sbc	hl,de		; C = high < |divisor| ...
	add	hl,de		; ... and ADD's carry repeats it, HL restored
	pop	de		; DE = |dividend| low
	ccf			; C = high >= |divisor|: quotient > FFFFh
	ret	c		; overflow: let the caller raise INT 0
	ld	a,16		; 16 quotient bits
	call	DIVU		; DE = |q|, HL = |r|
	or	a		; C = 0: success
	ret	; C = 0, DE = |q|, HL = |r|

; =====================================================================
; O_GRP4 - FEh: INC / DEC r/m8
; ---------------------------------------------------------------------
; Entry:  from NEXT; BC at the ModR/M byte.
; Exit:   JP (IX), r/m8 +-1, flags as the 8086: Z80 INC/DEC (HL) set S
;         Z AF(H) OF(V) and leave CF alone, as the 8086's do; A' =
;         result for PF.  reg /2-/7 -> O_BAD (the interpreter stops).
; Corrupts: A, DE, HL.
; Divergence: cpu86.py op_grp45 runs FE /2-/7 as the FFh word forms;
; here they stop at BADSTOP (see findings).
; =====================================================================
O_GRP4:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across EAB
	call	EAB		; HL -> the r/m8 operand
	pop	af		; ModR/M back
	and	38h		; reg field
	jr	z,G4INC		; /0 INC
	cp	08h		; /1 DEC?
	jp	nz,O_BAD	; /2-/7: not defined for bytes
	ex	af,af'		; /1 DEC: on the 8086 flags ...
	dec	(hl)		; ... (CF kept)
	ld	a,(hl)		; A' = result, for PF
	ex	af,af'		; flags back to AF'
	jp	(ix)		; next instruction
G4INC:
	ex	af,af'		; on the 8086 flags ...
	inc	(hl)		; ... (CF kept)
	ld	a,(hl)		; A' = result, for PF
	ex	af,af'		; flags back to AF'
	jp	(ix)		; next instruction

; =====================================================================
; O_GRP5 - FFh: INC DEC CALL CALLF JMP JMPF PUSH r/m16
; ---------------------------------------------------------------------
; Entry:  from NEXT; BC at the ModR/M byte.
; Exit:   to G5T entry reg, HL = host pointer to the r/m16 operand,
;         BC past ModR/M and displacement - which is the return IP that
;         CALL / CALLF push.
; Corrupts: A, DE, HL.
; Mirrors cpu86.py op_grp45 with w = 1.
; =====================================================================
O_GRP5:
	ld	a,(bc)		; ModR/M
	inc	bc		; past it
	push	af		; kept across EAW
	call	EAW		; HL -> the r/m16 operand
	pop	af		; ModR/M back
	and	38h		; reg field * 2
	rrca
	rrca
	ld	de,G5T		; the FFh table
	jp	JTAB		; jump to entry reg, HL kept

; G5T - group FFh by reg (reached only via JTAB):
;   /0 INC r/m16   /1 DEC r/m16   /2 CALL r/m16 (near, indirect)
;   /3 CALL m16:16 (far, indirect)   /4 JMP r/m16   /5 JMP m16:16
;   /6 PUSH r/m16  /7 PUSH (undocumented alias; cpu86.py does the same)
G5T:
	defw	G5_INC, G5_DEC, G5_CALL, G5_CALLF, G5_JMP, G5_JMPF, G5_PUSH, G5_PUSH

; ---- /0 INC r/m16 (INC16: flags as INC, CF kept, A' = low byte) ----
G5_INC:
	push	hl		; operand address, for G5ST
	ld	a,(hl)		; HL = operand
	inc	hl
	ld	h,(hl)	; (high byte)
	ld	l,a
	call	INC16		; HL + 1, 8086 flags set
G5ST:
	ex	de,hl		; DE = result
	pop	hl		; operand address
	ld	(hl),e		; back into r/m16
	inc	hl
	ld	(hl),d	; (high byte)
	jp	(ix)		; next instruction

; ---- /1 DEC r/m16 ----
G5_DEC:
	push	hl		; operand address, for G5ST
	ld	a,(hl)		; HL = operand
	inc	hl
	ld	h,(hl)	; (high byte)
	ld	l,a
	call	DEC16		; HL - 1, 8086 flags set
	jr	G5ST		; store it

; ---- /2 CALL r/m16: push IP, IP = operand (read before the push) ----
G5_CALL:
	ld	e,(hl)		; DE = target offset
	inc	hl
	ld	d,(hl)
	push	de		; (GETIP / PUSHDE use DE, HL)
	call	GETIP		; DE = IP of the next instruction
	call	PUSHDE		; the return address
	pop	de		; target offset
	ld	hl,(B_CS)	; host code pointer = CS base + target
	add	hl,de	; (no segment wrap: 52K guest)
	ld	b,h	; BC = new 8086 code pointer
	ld	c,l
	jp	(ix)		; continue at the target

; ---- /3 CALL m16:16: push CS, push IP, CS:IP = the far pointer ----
G5_CALLF:
	ld	e,(hl)		; offset word
	inc	hl
	ld	d,(hl)
	inc	hl
	push	de		; kept for FARJ
	ld	e,(hl)		; segment word
	inc	hl
	ld	d,(hl)
	push	de		; kept for FARJ
	ld	de,(R_CS)	; return CS ...
	call	PUSHDE	; (SS:SP -= 2)
	call	GETIP		; ... then return IP
	call	PUSHDE	; (SS:SP -= 2)
	pop	hl		; HL = new CS
	pop	de		; DE = new IP
	jp	FARJ		; reload CS, its base and BC, JP (IX)

; ---- /4 JMP r/m16: IP = operand ----
G5_JMP:
	ld	e,(hl)		; DE = target offset
	inc	hl
	ld	d,(hl)
	ld	hl,(B_CS)	; host code pointer = CS base + target
	add	hl,de	; (no segment wrap: 52K guest)
	ld	b,h	; BC = new 8086 code pointer
	ld	c,l
	jp	(ix)		; continue at the target

; ---- /5 JMP m16:16: CS:IP = the far pointer ----
G5_JMPF:
	ld	e,(hl)		; DE = offset
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)		; HL = segment
	inc	hl
	ld	h,(hl)	; (high byte)
	ld	l,a
	jp	FARJ		; reload CS, its base and BC, JP (IX)

; ---- /6 /7 PUSH r/m16 ----
; The operand is read before PUSHDE moves SP, so FF F4 (PUSH SP in its
; ModR/M form) pushes the OLD SP, unlike the 54h handler (see findings).
G5_PUSH:
	ld	e,(hl)		; DE = operand
	inc	hl
	ld	d,(hl)	; (high byte)
	call	PUSHDE		; onto SS:SP
	jp	(ix)		; next instruction

; =====================================================================
; ENDCODE - end of the interpreter proper (I86.ASM), EB46h
; ---------------------------------------------------------------------
; No code refers to it: z86.py reads it from the symbol table to report
; the interpreter's size and the room left below FF00h.  BIOS.ASM is
; assembled straight after, so TRAP shares this address.
; =====================================================================
ENDCODE:
