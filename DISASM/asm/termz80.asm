;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  10/10
;  TERMZ80.BIN - TERM.COM's Z80 part: a VT100 / VT52 serial terminal on
;  the WD2123, with the Timex terminal as screen and keyboard
;  (Z80, 3468 bytes, runs at F12Ch over Z86.SYS's COLD)
;==============================================================================
;
;  ROLE.  `TERM [port] [settings] [/80] [/52] [/X|/R|/N] [/E] [/C]` makes
;  the FDD3000 a serial terminal: the host on one WD2123 channel (another
;  computer, a modem, a serial console) sees a VT100 - or with /52 a
;  VT52 - of 24 rows by 64 (or 80) columns, which the Timex terminal
;  shows and types into.  TERM.COM (8086, volume 9) parses the command
;  line, runs the Ctrl-A menu, the log file and the XMODEM protocol; this
;  image does everything that has to be quick: it takes every received
;  byte in time, keeps a shadow of the host's screen, turns VT100 codes
;  into the Timex terminal's few, sends keys, moves XMODEM blocks and
;  computes their CRC.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM  ->  TERM.COM (8086, volume 9): INT 14h F1h sets the
;       channel up, then TRAP 1Ch with BP = its copy of this image:
;       Z86.SYS's T_CPML checks the 16-byte header and copies the code to
;       ENDBIOS (F12Ch, over COLD, volume 2) - the same trap and header
;       as CPM.COM (volume 3)
;     TERM.COM then calls TRAP 1Ch with BP = 0 and AH = a function  ->
;       T_CPML's JP ENDBIOS  ->  THIS IMAGE, T_TERM  ->  FTAB[AH]  ->
;       RET to TRAPX: the 8086 goes on after its 0F 1C with AL / CX / DX
;       as the function left them in REGS
;     TERM.COM's buffers (shadow screen, 2 KB ring, 8 KB log, XMODEM
;       block) lie in its own memory over its copy of this image; the
;       addresses reach INIT in a 13-byte parameter block (PB below).
;  Inside TERM.COM the image sits at file offset C8Bh, behind a 16-byte
;  header at C7Bh: the length (0D8Ch) and the Z86.SYS addresses it was
;  assembled against, NEXT D83Bh, JPHL EB4Dh, PEEKEY EBE3h, GETKEY
;  EC00h, CONOUT EC0Eh, DCSP F12Ah, ENDBIOS F12Ch (z86.py termz80()).
;  This image uses JPHL, PEEKEY and GETKEY of those, and the REGS page;
;  it brings its own copy of the link's send routine (TSEND) instead of
;  CONOUT.  Code and variables end at FEB7h, 72 bytes under the Z80
;  stack (z86.py asserts TERMEND <= FF00h - 64).
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/termz80_findings.md)
;   - Every wait polls the channel (RXPOLL): the WD2123 holds ONE
;     received byte, and the next, 2 083 T-states later at 19 200 baud,
;     overwrites it.  The terminal link's nibble exchange, the block
;     moves (32-byte pieces), scrolling and drawing all call RXPOLL on
;     the way.  The exceptions: BRK's 250 ms break, and the key reads,
;     which go through Z86.SYS's PEEKEY / GETKEY -> CONIN, a whole link
;     exchange with no poll (a slow real terminal there could cost a
;     byte; provisional).
;   - The source header says the host is let go "at a quarter"; the
;     code lets it go below 256 bytes (LOWAT = 1 page), an eighth of the
;     ring.  It is stopped at 1 KB, half (HIWAT = 4 pages).  The README
;     has it right.
;   - LOGLIM keeps "256 bytes for the host's overrun", but the log never
;     passes LOGLIM: what the host sends after the stop goes to the ring,
;     and TERM.COM empties the log (LOGN = 0) before SESS runs again.
;     The reserve is never used.
;   - DROPS (bytes SERPUT gave up on) is counted and never read, by this
;     image, TERM.COM or the tests.  SERPUT's give-up takes about 3.4 s
;     at 4 MHz (210 T x 65 536 polls), not the source's "about 2 s".
;   - Error reset is CMDV OR ER: the RTS state in force is kept, unlike
;     Z86.SYS's SERR, whose fixed IOERR (37h) raises RTS.
;   - RXPOLL uses EXX: safe, because the interpreter never touches the
;     alternate BC' DE' HL' (only AF', the 8086 flags).
;   - Edges: Latin-1 80h-BFh are dropped, C0h-FFh and UTF-8 lead bytes
;     show as '?'; BEL is ignored; SGR parameters are taken one by one,
;     so ESC [ 38;5;7 m turns inverse on; ESC 7 does not save the
;     character sets; tab stops are fixed at every 8 columns.
;
;  HARDWARE.  João's README records an interactive TERM session
;  against PuTTY tried on a real FDD3000 (his build, before the merge;
;  serial, XON / XOFF or RTS / CTS).  XMODEM, logging and the timing
;  figures are emulator results.  This merged build has not been run on
;  real hardware.  Timings below assume the schematic's 4 MHz Z80 and
;  are T-state counts, not measurements.  Status bit 7 of the WD2123 is
;  CTS (it has no DSR pin; datasheet and schematic).
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/TERMZ80.BIN with
;  Wijnen z80asm v1.8 (tools/roundtrip.sh).  The image equals TERM.COM
;  from file offset C8Bh to its end; the header at C7Bh was checked
;  against ../symbols/z80/Z86.SYS.sym.  Every instruction matches the
;  build listing ../symbols/z80/TERMZ80.lst.  Code partition
;  (notes/partition_findings.md style): descent seeds T_TERM, the 10 DWs
;  of FTAB, every DW of CTAB and PTAB (character + handler pairs), and
;  ICHS / DCHS / ECHS and CH_REDRAW (src: CH1), which CH_DISPATCH (src:
;  CH0) reaches by LD HL,handler / LD DE,CH_REDRAW / PUSH / PUSH / RET.
;  Everything is reached: no dead code.  Behaviour is exercised by
;  ../project/MSDOS/poc/test_term.py on the fdd86.py model (21 code
;  cases and 60 random batches against a Python VT100 / VT52 model, keys,
;  local echo, /C, load with and without flow control, the log, XMODEM
;  both ways, /52 and /80) - an emulator, with a terminal model that
;  answers the link at once.
;
;  FILE:    TERMZ80.BIN, 3468 bytes
;  MD5:     abb0d2751f017c72a716eabe318c0a07
;  SHA256:  5823888f4d5aafe18f03f89271ecdc0c67a1e9a7bad36ff139f668c1cac1fe96
;  SOURCE:  ../project/MSDOS/poc/TERMZ80.ASM (z86.py termz80(), build.py
;           TERMZ80.INC)
;
;  CREDITS.  Original code: João Encarnado, for the FDD3000-MSDOS project
;  (2026).  The link protocol is CBIOS A1.1's (Antonio Nobrega, TMX
;  Portugal, 85/10/29); the host side follows DEC's VT100 and VT52.
;  Disassembly and annotation in the style of "The Complete TMX Portugal
;  ROM Disassemblies", LoadZX Museum, 2026.
;==============================================================================

; =====================================================================
;                    IMPORTED FROM Z86.SYS (volume 2)
; =====================================================================
; The author's names and values; TERMZ80.ASM is assembled after I86.ASM
; and BIOS.ASM, like CPMZ80.ASM, and simply uses their symbols.  JPHL,
; PEEKEY, GETKEY and ENDBIOS are in the trap-1Ch header and checked at
; load (with NEXT, CONOUT and DCSP, which this image does not use); the
; REGS fields are fixed at D000h and not checked.

ENDBIOS:	equ	0F12Ch		; end of the resident BIOS: COLD, then this

; ---- REGS page: TERM.COM's 8086 registers at the trap ----
R_AL:		equ	0D000h		; AL: the result of SESS, RECV, SEND, CRC
R_AH:		equ	0D001h		; AH: the function, 0-9
R_CL:		equ	0D002h		; CL: DRAW's first row
R_CX:		equ	0D002h		; CX: counts in and out
R_DX:		equ	0D004h		; DX: RECV's first wait; SESS's LOST; CRC
R_DL:		equ	0D004h		; DL: LOG's on / off, MODE's flags
R_BL:		equ	0D006h		; BL: RECV's byte to send first ...
R_BH:		equ	0D007h		; BH: ... if BH <> 0
R_SI:		equ	0D00Ch		; SI: INIT's PB, SEND's and CRC's data
R_DI:		equ	0D00Eh		; DI: where RECV puts the bytes

; ---- BIOS entries ----
JPHL:		equ	0EB4Dh		; JP (HL): CALL JPHL is an indirect call
PEEKEY:		equ	0EBE3h		; CF=1: a key waits (A, kept for GETKEY)
GETKEY:		equ	0EC00h		; A = next key, waiting for one

; =====================================================================
;                    HARDWARE (values as z86sys.asm's block)
; =====================================================================
; A separate image, so the shared names are defined once here, with
; the values Z86.SYS and CBIOS A1.1 give them (dict/CONVENTIONS.md).

; ---- communication port: terminal link, bit 7 = WD177x DRQ ----
COM:		equ	2Fh
MASK:		equ	5Fh		; link bits 6, 4-0 (CBIOS MASK)
KEYRDY:		equ	04h		; terminal idle with a key waiting (CBIOS)
LINKERR:	equ	07h		; abort, from either side (CBIOS TXERR)
BYTEON:		equ	0Ah		; FDD: "I have a byte"       (CBIOS)
SERVICO:	equ	0Fh		; terminal: "send it"        (CBIOS)
CSTAT:		equ	10h		; low-nibble tag             (CBIOS)
BSTAT:		equ	40h		; high-nibble tag            (CBIOS)
STMSK:		equ	50h		; end of character (CBIOS STMSK = its DSTAT)

; ---- WD2123 dual UART (8251A-compatible channels) ----
; Data port, then the control port = data + 1 (status on read, command
; on write).  TERM.COM puts the control port of its channel in PB's CTL
; (UART_CMD_CHA or UART_CMD_CHB); this image reaches the data port
; with DEC C, as Z86.SYS's serial routines do.  The baud registers are
; TERM.COM's business (INT 14h F1h), listed for completeness.
UART_BAUD_CHA:	equ	10h		; baud-rate register, channel A (printer)
UART_BAUD_CHB:	equ	11h		; baud-rate register, channel B (AUX)
UART_DATA_CHB:	equ	40h		; channel B data (CBIOS CANALB)
UART_CMD_CHB:	equ	41h		; status (read) / mode+command (write)
UART_DATA_CHA:	equ	80h		; channel A data (CBIOS CANALA)
UART_CMD_CHA:	equ	81h		; status (read) / mode+command (write)

; ---- 8251A command and status values ----
; Command: bit 0 TxEN, 1 DTR, 2 RxE, 3 send break, 4 ER, 5 RTS.
; Status:  bit 0 TxRDY, 1 RxRDY, 2 TxEMPTY, 3 PE, 4 OE, 5 FE,
;          6 BRKDET, 7 CTS (the WD2123 has no DSR pin).
ACOM:		equ	07h		; TxEN + DTR + RxE, RTS off   (CBIOS ACOM)
SIOWORD:	equ	27h		; ACOM + RTS                  (CBIOS SIOWORD)
SIO_SBRK:	equ	08h		; command bit 3: hold TxD at space (break)
SIO_ER:		equ	10h		; command bit 4: error reset (PE OE FE)
IOMASK:		equ	81h		; status CTS + TxRDY: both needed to send
SIO_PEOEFE:	equ	38h		; status bits 3-5: parity, overrun, framing
SIO_OE:		equ	10h		; status bit 4: overrun - a byte was lost

; ---- ASCII ----
ESC:		equ	1Bh
XON:		equ	11h		; DC1: host, go on
XOFF:		equ	13h		; DC3: host, stop

; ---- Terminal 3000 codes, each after ESC (names as edit.asm's) ----
VT_CUP:		equ	'Y'		; ESC Y row+32 col+32: cursor address
VT_BIAS:	equ	32		;   the bias on row and column
VT_HOME:	equ	'H'		; ESC H: cursor home
VT_EOS:		equ	'J'		; ESC J: clear to the end of the screen
VT_EOL:		equ	'K'		; ESC K: clear to the end of the line
VT_INVON:	equ	'L'		; ESC L: inverse on
VT_INVOFF:	equ	'M'		; ESC M: inverse off
VT_RLF:		equ	'I'		; ESC I: cursor up; on row 0 scroll down

; =====================================================================
;                    LAYOUT CONSTANTS (TERMZ80.ASM's header)
; =====================================================================
; The parameter block INIT copies from SI into PB (TERM.ASM's PBLK).
P_CTL:		equ	0		; control port: 81h channel A, 41h B
P_COLS:		equ	1		; 64 or 80 (anything but 64 is taken as 80)
P_ROWS:		equ	2		; 24
P_FLAGS:	equ	3		; the flags below
P_MENU:		equ	4		; the menu key (Ctrl-A)
P_SCR:		equ	5		; the shadow screen, ROWS x COLS bytes
P_RING:		equ	7		; the ring, 2048 bytes
P_LOG:		equ	9		; the log buffer
P_LOGSZ:	equ	11		;   and its size (8192)
PBLEN:		equ	13

; ---- FLAGS (TERM.COM's switches) ----
FL_VT52:	equ	01h		; bit 0: /52, the host sends VT52 codes
FL_XON:		equ	02h		; bit 1: /X, XON / XOFF (the default)
FL_RTS:		equ	04h		; bit 2: /R, RTS / CTS
FL_ECHO:	equ	08h		; bit 3: /E, local echo
FL_CRLF:	equ	10h		; bit 4: /C, a CR received is CR LF

; ---- the ring ----
RINGM:		equ	07h		; ring index mask, high byte (2048)
HIWAT:		equ	4		; stop the host at 4 x 256 bytes (half)
LOWAT:		equ	1		; let it go below 256 (an eighth)

; ---- the parser's states (PST) ----
PS_ESC:		equ	1		; after ESC
PS_CSI:		equ	2		; after ESC [: parameters, then a final
PS_SCS:		equ	3		; after ESC ( or ESC ): the set's letter
PS_HASH:	equ	4		; after ESC #: one byte, ignored
PS_YROW:	equ	5		; VT52 ESC Y: the row comes next
PS_YCOL:	equ	6		;   then the column
NPARMAX:	equ	4		; CSI parameters kept (PARS)

NFUNC:		equ	10		; functions in FTAB


	org	ENDBIOS

; =====================================================================
; T_TERM - trap 1Ch, BP = 0: run function AH
; ---------------------------------------------------------------------
; Entry:  from Z86.SYS's T_CPML (JP Z,ENDBIOS), inside TRAP: the stack
;         holds TRAP's return to TRAPX (which pops IX and BC, the 8086
;         code pointer).  REGS = TERM.COM's registers, AH = function.
; Exit:   the function's RET goes to TRAPX; results are in REGS.  An AH
;         of 10 or more returns at once, nothing done.
;
; Functions, with the register interface of TERMZ80.ASM's header:
;   0 INIT  SI = PB's linear address: set up, clear the screen
;   1 SESS  the session, until the menu key (AL = 1) or a full log
;           (AL = 2); CX = bytes in the log, DX = bytes lost
;   2 DRAW  draw the screen again from row CL
;   3 RECV  BH <> 0: send BL first.  Up to CX bytes to DI, waiting DX x
;           10 ms for the first, 1 s for each other; CX = received,
;           AL = 1 if a key was pressed (it is taken)
;   4 SEND  CX bytes from SI; AL = 1 if CTS stayed off (not all sent)
;   5 BRK   a break of about 250 ms
;   6 LOG   DL = 0 log off, else on; CX = bytes now in the log buffer
;   7 CRC   CX bytes at SI: DX = CRC-16 (XMODEM), AL = 8-bit sum
;   8 FLUSH forget what has been received
;   9 MODE  DL: the flags 8 (local echo) and 10h (LF after CR)
; Addresses are 8086 linear ones, which are the Z80's (0000h-CFFFh).
; =====================================================================
T_TERM:
	ld	a,(R_AH)	; the function
	cp	NFUNC		; 0-9 only: anything else is a no-op
	ret	nc		; (back to TRAPX, REGS untouched)
	add	a,a		; word index
	ld	l,a		; HL = 2 x AH ...
	ld	h,0		; (AH < 10: no overflow)
	ld	de,FTAB		; ... + the table
	add	hl,de		; HL -> the entry
	ld	a,(hl)		; the handler, low byte ...
	inc	hl		; (little-endian word)
	ld	h,(hl)		; ... and high
	ld	l,a		; HL = handler
	jp	(hl)		; its RET returns from the trap

; FTAB - function number -> handler (AH = 0..9)
FTAB:
	defw	F_INIT, F_SESS, F_DRAW, F_RECV, F_SEND, F_BRK, F_LOG, F_CRC
					; 0 INIT  1 SESS  2 DRAW  3 RECV
					; 4 SEND  5 BRK   6 LOG   7 CRC
	defw	F_FLSH, F_MODE	; 8 FLUSH 9 MODE

; =====================================================================
; F_INIT - function 0: take the parameter block, set the channel's
; command, reset the terminal and clear the screen
; ---------------------------------------------------------------------
; Entry:  SI = linear address of TERM.COM's PBLK (13 bytes, PB layout).
; Exit:   PB filled; SCREND, LOGLIM computed; log off, host not stopped,
;         ring empty, counts 0; WD2123 command SIOWORD (RTS on); then
;         RESET (screen blank, terminal home).
; The channel's mode and baud rate were set by TERM.COM (INT 14h F1h)
; before; only the command byte is this image's.
; =====================================================================
F_INIT:
	ld	hl,(R_SI)	; TERM.COM's parameter block ...
	ld	de,PB		; ... copied in: CTL COLS ROWS FLAGS MENUK
	ld	bc,PBLEN	;   SCR RING LOGB LOGSZ
	ldir		; 13 bytes, as TERM.ASM lays them out
	ld	a,(ROWS)	; the end of the shadow: row ROWS's start,
	call	ROWP		;   SCR + ROWS x COLS
	ld	(SCREND),hl	; (CLRALL and EDN fill up to it)
	ld	hl,(LOGSZ)	; the log's limit: its size less 256 (DEC H)
	dec	h		; (LOGSZ is a multiple of 256)
	ld	(LOGLIM),hl	; 256 bytes kept for the host's overrun - never
					;   used: see SESS_BYTE (src: SL3)
	xor	a		; all off:
	ld	(LOGON),a	; no log
	ld	(STOPF),a	; the host not stopped
	ld	(HOLDF),a	; nor held
	ld	(TXQ),a		; no XON / XOFF queued
	ld	(DROPS),a	; no bytes given up on
	ld	h,a		; HL = 0
	ld	l,a		; (L too)
	ld	(LOGN),hl	; the log buffer empty
	ld	(LOST),hl	; nothing lost yet
	call	F_FLSH		; the ring empty
	ld	a,SIOWORD	; transmitter, DTR, receiver, RTS on
	ld	(CMDV),a	; the command in force, kept for later ORs
	call	CMDOUT		; to the chip
; ---------------------------------------------------------------------
; RESET - the VT100's state as at power-on, the screen cleared
; Entry:  falls in from F_INIT; ESC c (SESC) jumps here.
; Exit:   through CLRALL.  FLAGS and the channel are left alone.
; ---------------------------------------------------------------------
RESET:
	xor	a		; zero:
	ld	(PST),a		; parser: text
	ld	(CROW),a	; cursor home
	ld	(CCOL),a		; column 0
	ld	(WRAPF),a	; no wrap pending
	ld	(ATTR),a	; normal video
	ld	(TOP),a		; scrolling region from row 0 ...
	ld	(IRM),a		; replace mode
	ld	(CKM),a		; cursor keys normal (ESC [ A)
	ld	(GL),a		; G0 in use ...
	ld	(G0),a		; ... both sets ASCII
	ld	(G1),a		; (G1 too)
	ld	(SAVR),a	; ESC 8 without ESC 7: home, normal
	ld	(SAVC),a
	ld	(SAVA),a		; (attribute)
	inc	a		; A = 1:
	ld	(AWM),a		; autowrap on (the VT100's default)
	ld	a,(ROWS)	; ... to the last row
	dec	a		; BOT = ROWS - 1: the region is the whole screen
	ld	(BOT),a		; (the region's bottom)
	ld	a,0FFh		; the terminal's attribute: not known, so the
	ld	(TATTR),a	;   next TSETA always sends
; ---------------------------------------------------------------------
; CLRALL - the whole shadow blank, the terminal cleared and homed
; Entry:  falls in from RESET; EDN with A >= 2.
; Exit:   TROW = TCOL = 0 (the terminal's cursor); CROW / CCOL kept.
; ---------------------------------------------------------------------
CLRALL:
	ld	hl,(SCREND)	; BC = the shadow's size
	ld	de,(SCR)		; (the shadow's start)
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; SCREND - SCR
	ld	b,h		; BC = the count
	ld	c,l
	ex	de,hl		; HL = SCR
	call	FILL		; all blanks
	xor	a		; normal video first: the terminal clears
	call	TSETA		;   with the attribute in force
	ld	a,VT_HOME	; ESC H: its cursor home ...
	call	TESC
	ld	a,VT_EOS	; ... ESC J: and everything from there
	call	TESC		; (clear to the end)
	xor	a		; where the terminal's cursor now is
	ld	(TROW),a		; the terminal's cursor is at 0,0 now
	ld	(TCOL),a		; (column 0)
	ret		; (CROW / CCOL untouched: TSYNC moves it later)

; =====================================================================
; F_SESS - function 1: the session
; ---------------------------------------------------------------------
; Entry:  none (REGS unused).
; Exit:   AL = 1 the menu key was pressed, 2 the log buffer is full;
;         CX = LOGN, DX = LOST (SRET).  The host is held stopped (HOLD)
;         either way; ENSURE or the next SESS lets it go.
;
; The loop: poll the channel, pass a key on (KEYOUT) unless it is the
; menu key, then show one byte from the ring (EMUL), logging it first.
; With the ring empty the terminal's cursor is put where the host's is
; (TSYNC: only sent when it differs), and a stopped host is let go.
; While stopped, the host is let go once the ring is below LOWAT pages.
; =====================================================================
F_SESS:
	xor	a		; a new session: the hold from the menu or the
	ld	(HOLDF),a	;   log is over (STOPF stays until RESUME)
SESS_LOOP:				; (src: SL1)
	call	RXPOLL		; a received byte to the ring
	call	PEEKEY		; a key?  (Z86.SYS: takes it from the link
	jr	nc,SESS_RING	;   and holds it - no RXPOLL in there)
	call	GETKEY		; the held key
	ld	hl,MENUK	; the menu key ends the session
	cp	(hl)		; the menu key?
	jr	z,SMENU		; yes: back to TERM.COM
	call	KEYOUT		; any other: to the host
SESS_RING:				; (src: SL2)
	call	RGET		; the next received byte?
	jr	c,SESS_BYTE		; a byte: log it and show it
	call	TSYNC		; nothing to show: the cursor to its place
	ld	a,(STOPF)	; the ring is empty: a stopped host may go on
	or	a		;   (RESUME does nothing while HOLDF)
	call	nz,RESUME		; (A = STOPF here, NZ)
	jr	SESS_LOOP		; round again
SESS_BYTE:				; (src: SL3)
	ld	c,a		; C = the byte
	ld	a,(LOGON)	; logging?
	or	a		; (Z: not logging)
	jr	z,SESS_SHOW	; no
	ld	hl,(LOGN)	; LOGB[LOGN] = the byte, raw
	push	hl		; (LOGN kept)
	ld	de,(LOGB)		; + the buffer's start
	add	hl,de		; HL -> the slot
	ld	(hl),c		; the raw byte, before the parser sees it
	pop	hl		; HL = LOGN
	inc	hl		; one more
	ld	(LOGN),hl		; (the new count)
	ld	de,(LOGLIM)	; at the limit?  The test follows the store,
	or	a		;   so LOGN never passes LOGLIM; what comes
	sbc	hl,de		;   meanwhile goes to the ring and is logged
	jr	c,SESS_SHOW	;   after TERM.COM has emptied the buffer
	ld	a,c		; full: this byte still shown,
	call	EMUL		; (shown before the stop, so nothing is skipped)
	call	HOLD		; the host stopped,
	ld	a,2		; AL = 2: write the log
	jr	SRET		; return to TERM.COM
SESS_SHOW:				; (src: SL4)
	ld	a,c		; the byte to the screen
	call	EMUL		; VT100 / VT52 parser
	ld	a,(STOPF)	; host stopped?
	or	a		; (Z: running freely)
	jr	z,SESS_LOOP	; no
	call	LEVEL		; yes: let it go when the ring is below
	ld	a,h		;   LOWAT pages (256 bytes: an eighth, not
	cp	LOWAT		;   the source header's "a quarter")
	call	c,RESUME		; below LOWAT pages: XON / RTS on
	jr	SESS_LOOP		; round again
SMENU:
	call	HOLD		; stop the host for the menu
	ld	a,1		; AL = 1: the menu
SRET:
	ld	(R_AL),a	; the reason
	ld	hl,(LOGN)	; CX = bytes in the log buffer
	ld	(R_CX),hl		; (TERM.ASM keeps it in its LOGN)
	ld	hl,(LOST)	; DX = bytes lost so far (overruns, ring full)
	ld	(R_DX),hl		; (TERM.ASM's LOST: shown in the menu)
	jp	TSYNC		; the cursor in place for TERM.COM's output

; ---------------------------------------------------------------------
; HOLD - stop the host and keep taking what it still sends, ~120 ms
; Exit:   STOPF = HOLDF = 1: RESUME refuses until HOLDF is cleared
;         (F_SESS, ENSURE).  Corrupts A, HL.
; Callers: F_SESS (menu key, full log).
; FLOWOFF is called directly, not STOP: the XOFF is queued again even
; if the host was already stopped.  3000 polls of 160 T are about
; 120 ms at 4 MHz (the source says 100 ms): long enough for the XOFF to
; go and a host's in-flight bytes to land in the ring.
; ---------------------------------------------------------------------
HOLD:
	ld	a,1		; stopped, and held so
	ld	(STOPF),a		; (the STOP flag RXPOLL's STOP tests)
	ld	(HOLDF),a		; (RESUME refuses while it is set)
	call	FLOWOFF		; XOFF queued and / or RTS off
	ld	hl,3000		; ~120 ms of polling
HOLD_DRAIN:				; (src: HO1)
	call	RXPOLL		; sends the XOFF, takes the stragglers
	dec	hl		; one poll fewer
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,HOLD_DRAIN		; until 3000 polls are done
	ret		; (back to SESS, still held)

; =====================================================================
; F_DRAW - function 2: draw the terminal again from the shadow
; ---------------------------------------------------------------------
; Entry:  CL = the first row (TERM.COM wrote over rows CL..bottom: the
;         menu on the last row, its hello line into the shadow itself).
; Exit:   rows CL..ROWS-1 drawn, the cursor at the host's.
; TERM.COM's own output went through DOS, so the terminal's cursor and
; attribute are forgotten first (FFh: no row or attribute has it).
; =====================================================================
F_DRAW:
	ld	a,0FFh		; the terminal's cursor and attribute:
	ld	(TROW),a	; not known
	ld	(TATTR),a		; (FFh: TSETA always sends next time)
	ld	a,(ROWS)	; C = the last row
	dec	a		; ROWS - 1
	ld	c,a		; (C = the last row)
	ld	a,(R_CL)	; B = CL, at most the last row
	cp	c		; (CL at most the last row)
	jr	c,DRAW_FROM		; within the screen: as given
	ld	a,c		; past it: the last row only
DRAW_FROM:				; (src: FD1)
	ld	b,a		; B = the first row
	call	REDR		; rows B..C
	jp	TSYNC		; and the cursor back

; =====================================================================
; F_RECV - function 3: receive a block for XMODEM
; ---------------------------------------------------------------------
; Entry:  BH <> 0: send BL first (the answer to the last block, ACK /
;         NAK / C); CX = bytes wanted; DI = where; DX = the wait for the
;         first byte in 10 ms units.
; Exit:   CX = bytes received; AL = 1 if a key was pressed (taken and
;         dropped: TERM.COM's "cancel"), else 0 (all in, or timed out).
;
; The ring is emptied first (it may hold the start of the block, taken
; by SERPUT's RXPOLL while BL went out); then the channel is read
; directly, without the ring and without flow control: XMODEM's
; lock-step is the flow control.  An overrun here is reset but not
; counted in LOST.  The inner loop is 85 T: 470 turns = 10 ms at 4 MHz.
; =====================================================================
F_RECV:
	call	ENSURE		; host let go, RTS on, the XON gone
	ld	a,(R_BH)	; an answer to send first?
	or	a		; (BH = 0: nothing to send)
	ld	a,(R_BL)	; (LD keeps the flags)
	call	nz,SERPUT	; yes: BL to the host
	ld	hl,0		; none received yet
	ld	(RCNT),hl		; (counter of bytes stored at DI)
	ld	hl,(R_DX)	; the first byte's wait, x 10 ms
	ld	(TMO),hl		; (in 10 ms units)
RECV_NEXT:				; (src: FR1)
	ld	hl,(R_CX)	; all CX in?
	ld	de,(RCNT)		; (the bytes stored so far)
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; CX - RCNT
	jr	z,RECV_END	; yes
	call	RGET		; first what is in the ring
	jr	c,RECV_STORE		; the ring had one: store it
	ld	a,(CTL)		; C = the control port
	ld	c,a		; (C: IN A,(C) below)
	ld	de,(TMO)	; DE = 10 ms units left
RECV_10MS:				; (src: FR2)
	ld	hl,470		; about 10 ms
RECV_POLL:				; (src: FR3)
	in	a,(c)		; the channel's status: RxRDY?
	bit	1,a		; (status bit 1)
	jr	nz,RECV_GOT		; a byte: take it
	in	a,(COM)		; the terminal's idle code:
	and	MASK		; (link bits only)
	cp	KEYRDY		; a key
	jr	z,RECV_KEY		; a key: the transfer is cancelled
	dec	hl		; one poll of 10 ms fewer
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,RECV_POLL		; not yet 10 ms
	dec	de		; another 10 ms gone
	ld	a,d		; (16-bit zero test)
	or	e		; (DE = 0?)
	jr	nz,RECV_10MS		; more 10 ms units to wait
	jr	RECV_END	; timed out
RECV_GOT:				; (src: FR5)
	and	SIO_PEOEFE	; parity, overrun or framing error?
	jr	z,RECV_TAKE		; a clean byte
	ld	a,(CMDV)	; reset it, keeping the RTS state in force
	or	SIO_ER		;   (the byte is taken all the same: XMODEM's
	out	(c),a		;   CRC judges it)
RECV_TAKE:				; (src: FR51)
	dec	c		; the data port
	in	a,(c)		; the byte
RECV_STORE:				; (src: FR6)
	ld	hl,100		; from now on 1 s for each byte
	ld	(TMO),hl		; (the next byte's wait)
	ld	hl,(RCNT)	; DI[RCNT] = the byte
	push	hl		; (RCNT kept)
	ld	de,(R_DI)		; + DI
	add	hl,de		; HL -> the slot
	ld	(hl),a		; the byte in TERM.COM's buffer (XBUF)
	pop	hl		; HL = RCNT
	inc	hl		; one more
	ld	(RCNT),hl		; (the new count)
	jr	RECV_NEXT		; the next byte
RECV_KEY:				; (src: FR7)
	call	GETKEY		; the key, taken (and dropped)
	ld	a,1		; AL = 1
	jr	RECV_RET		; (CX = what came before the key)
RECV_END:				; (src: FR8)
	xor	a		; AL = 0: all in or timed out (CX says which)
RECV_RET:				; (src: FR9)
	ld	(R_AL),a		; AL = the result
	ld	hl,(RCNT)	; CX = bytes received
	ld	(R_CX),hl		; (TERM.ASM checks it against 133)
	ret		; back to TRAPX

; =====================================================================
; F_SEND - function 4: send CX bytes from SI
; ---------------------------------------------------------------------
; Exit:   AL = 0 all sent; AL = 1 CTS stayed off ~3.4 s for one byte
;         (SERPUT gave up) and the rest was not sent.
; =====================================================================
F_SEND:
	call	ENSURE		; host let go, RTS on
	ld	hl,(R_SI)	; HL = the data
	ld	bc,(R_CX)	; BC = the count
SEND_NEXT:				; (src: FS1)
	ld	a,b		; all sent?
	or	c		; (BC = 0?)
	jr	z,SEND_DONE		; all sent
	ld	a,(hl)		; the next byte
	push	hl		; (the pointer ...
	push	bc		; ... and count survive SERPUT)
	call	SERPUT		; CF = 1: CTS never came
	pop	bc		; (count)
	pop	hl		; (pointer)
	ld	a,1		; (AL = 1 if it failed; LD keeps CF)
	jr	c,SEND_RET		; CTS stayed off: stop here
	inc	hl		; the next byte
	dec	bc		; one fewer
	jr	SEND_NEXT		; round again
SEND_DONE:				; (src: FS2)
	xor	a		; AL = 0
SEND_RET:				; (src: FS3)
	ld	(R_AL),a		; AL = 0 / 1
	ret		; back to TRAPX

; =====================================================================
; F_BRK - function 5: a break of about 250 ms
; ---------------------------------------------------------------------
; The command's break bit holds TxD at space; it is written without
; going into CMDV, so CMDOUT ends it.  25 x 10 ms: 1538 turns of a
; 26 T loop are 39 988 T, 10 ms at 4 MHz.  No RXPOLL meanwhile: a host
; that sends during the break loses all but its last byte.
; =====================================================================
F_BRK:
	call	ENSURE		; host let go, RTS on
	ld	a,(CMDV)	; the command in force ...
	or	SIO_SBRK	; ... with send break
	call	CMDA		; TxD held at space (CMDV unchanged)
	ld	b,25		; 25 x 10 ms
BRK_10MS:				; (src: FB1)
	ld	hl,1538		; 10 ms
BRK_SPIN:				; (src: FB2)
	dec	hl		; one 26 T turn
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,BRK_SPIN		; until 10 ms
	djnz	BRK_10MS		; 25 times
	jp	CMDOUT		; CMDV again: the break ends

; =====================================================================
; F_LOG - function 6: log on / off
; ---------------------------------------------------------------------
; Entry:  DL = 0 off, anything else on; CX = bytes now in the buffer
;         (TERM.COM passes 0 after writing it out: LOGSET).
; =====================================================================
F_LOG:
	ld	a,(R_DL)	; on / off
	ld	(LOGON),a		; (any nonzero: on)
	ld	hl,(R_CX)	; the buffer's count
	ld	(LOGN),hl		; (TERM.ASM passes 0 or its LOGN)
	ret		; back to TRAPX

; =====================================================================
; F_MODE - function 9: local echo and implicit LF
; ---------------------------------------------------------------------
; Entry:  DL: FL_ECHO (8) and FL_CRLF (10h); its other bits are ignored,
;         and FLAGS' other bits (VT52, flow control) are kept.
; =====================================================================
F_MODE:
	ld	a,(FLAGS)	; FLAGS without echo and LF ...
	and	0FFh-FL_ECHO-FL_CRLF		; FL_ECHO and FL_CRLF cleared (E7h)
	ld	b,a		; (B = the bits kept)
	ld	a,(R_DL)	; ... with DL's
	and	FL_ECHO+FL_CRLF		; only those two bits of DL (18h)
	or	b		; merged
	ld	(FLAGS),a		; (KEYOUT and ECR read them)
	ret		; back to TRAPX

; =====================================================================
; F_CRC - function 7: CRC-16 (XMODEM) and 8-bit sum of CX bytes at SI
; ---------------------------------------------------------------------
; Exit:   DX = CRC, AL = sum (XMODEM's checksum), whichever the
;         protocol uses.  Corrupts all.
; CRC-16/XMODEM: polynomial 1021h, initial 0, no reflection, no final
; XOR.  Each byte goes into the CRC's high byte, then 8 shifts left;
; a bit shifted out XORs in the polynomial.  ~8 x 50 T a byte.
; =====================================================================
F_CRC:
	ld	hl,(R_SI)	; HL = the data
	ld	bc,(R_CX)	; BC = the count
	ld	de,0		; DE = the CRC
	xor	a		; the sum
	ld	(SUM),a		; (SUM = 0)
CRC_NEXT:				; (src: CR1)
	ld	a,b		; all done?
	or	c		; (BC = 0?)
	jr	z,CRC_DONE		; all bytes done
	push	bc		; (B is the bit count below)
	ld	a,(SUM)		; sum += byte
	add	a,(hl)		; (8-bit, carries dropped)
	ld	(SUM),a		; (the checksum so far)
	ld	a,(hl)		; CRC high byte ^= byte
	xor	d		; into the CRC's high byte
	ld	d,a		; (D = the new high byte)
	ld	b,8		; eight bits
CRC_BIT:				; (src: CR2)
	sla	e		; DE << 1, the top bit to CF
	rl	d		; (high byte, the top bit to CF)
	jr	nc,CRC_NOXOR		; 0 out: no XOR
	ld	a,d		; it was 1: DE ^= 1021h
	xor	10h		; (high byte of 1021h)
	ld	d,a		; (D done)
	ld	a,e
	xor	21h		; (low byte of 1021h)
	ld	e,a		; (E done)
CRC_NOXOR:				; (src: CR3)
	djnz	CRC_BIT		; eight bits per byte
	pop	bc		; (the count back)
	inc	hl		; next byte
	dec	bc		; one fewer
	jr	CRC_NEXT		; round again
CRC_DONE:				; (src: CR4)
	ld	(R_DX),de	; DX = CRC
	ld	a,(SUM)		; AL = sum
	ld	(R_AL),a		; (the checksum)
	ret		; back to TRAPX

; =====================================================================
; F_FLSH - function 8: forget what has been received (ring empty)
; Also called by F_INIT.  Corrupts HL.
; =====================================================================
F_FLSH:
	ld	hl,0		; head = tail = 0: empty
	ld	(RHEAD),hl		; (head = 0 ...
	ld	(RTAIL),hl		; ... = tail: the ring is empty)
	ret		; (the bytes are forgotten, not cleared)

; ---------------------------------------------------------------------
; ENSURE - for a transfer: the host let go, and the XON gone out
; Exit:   HOLDF = 0; if the host was stopped, RESUME and up to 65 536
;         polls (~3 s) for TXQ to empty.  Corrupts A, HL (and RESUME's).
; Callers: F_RECV, F_SEND, F_BRK.
; ---------------------------------------------------------------------
ENSURE:
	xor	a		; no longer held
	ld	(HOLDF),a		; (RESUME may now act)
	ld	a,(STOPF)	; stopped?
	or	a		; (Z: running freely)
	ret	z		; no: nothing to do
	call	RESUME		; XON queued, RTS on
	ld	hl,0		; 65 536 tries
ENSURE_WAIT:				; (src: EN1)
	call	RXPOLL		; until the XON has gone
	ld	a,(TXQ)		; the queued XON gone?
	or	a		; (0 = sent)
	ret	z		; yes: ready for the transfer
	dec	hl		; one try fewer
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,ENSURE_WAIT		; not yet given up
	ret			; (CTS never came: given up)

; =====================================================================
;                    THE CHANNEL
; =====================================================================
; RXPOLL - a received byte, if any, to the ring; a queued XON / XOFF out
; when the transmitter is free
; ---------------------------------------------------------------------
; Entry:  none.
; Exit:   nothing changed but the flags: AF is pushed, the work is done
;         in the alternate BC' DE' HL' (EXX), which Z86.SYS's interpreter
;         never uses (it keeps only the 8086 flags in AF').
; Callers: everywhere a loop waits or a long job runs: SESS, HOLD,
;         ENSURE, SERPUT, KEYOUT, TOUT, TSEND, DRAWR, MVSUB, SHUP, SHDN,
;         PUTCH.  About 117 T when there is nothing to do.
;
; Why everywhere: the WD2123 holds one received byte; the next one
; overwrites it a character time later - 10 bits / 19 200 baud = 521 us
; = 2 083 T at 4 MHz.  The README's emulator measurement puts the
; longest gap between two RXPOLLs under 1 800 T (with a terminal model
; that answers the link at once).
;
; The ring: RING + 0..2047, head RHEAD (next free), tail RTAIL (next
; to read), indices masked to 11 bits (RINGM on the high byte).  One
; slot always stays empty, so head = tail is "empty" and it holds 2047.
; At HIWAT pages (1024 bytes, half) the host is asked to stop (STOP);
; SESS lets it go below LOWAT (256).  A byte that finds the ring full,
; and an overrun the chip reports, each count one in LOST.
; =====================================================================
RXPOLL:
	push	af		; A and F are the caller's too
	exx			; work in BC' DE' HL'
	ld	a,(CTL)		; C' = the control port
	ld	c,a		; (C' = CTL)
	in	b,(c)		; B' = the status, read once
	ld	a,(TXQ)		; an XON / XOFF to send?
	or	a		; (0 = none)
	jr	z,RXPOLL_RX	; no
	ld	e,a		; E' = it
	ld	a,b		; free to send: TxRDY and CTS both on?
	and	IOMASK		; (status bits 7 and 0)
	cp	IOMASK		; (both set?)
	jr	nz,RXPOLL_RX	; not yet: a later poll sends it
	dec	c		; the data port
	out	(c),e		; XON / XOFF goes
	inc	c		; (the control port again)
	xor	a		; nothing queued now
	ld	(TXQ),a
RXPOLL_RX:				; (src: RXP1)
	bit	1,b		; RxRDY: a byte waits?
	jr	z,RXPOLL_RET		; none: done
	ld	a,b		; framing, overrun, parity?
	and	SIO_PEOEFE		; (status bits 3-5)
	jr	z,RXPOLL_TAKE	; none
	and	SIO_OE		; an overrun: at least one byte lost
	jr	z,RXPOLL_ERRRST		; not an overrun: just reset the error
	ld	hl,(LOST)	;   (count one; how many is not known)
	inc	hl		; (LOST + 1)
	ld	(LOST),hl		; (TERM.COM shows it in the menu)
RXPOLL_ERRRST:				; (src: RXP2)
	ld	a,(CMDV)	; error reset, with the RTS state in force
	or	SIO_ER		;   (Z86.SYS's SERR would raise RTS here)
	out	(c),a		; (ER self-clears)
RXPOLL_TAKE:				; (src: RXP3)
	dec	c		; the data port
	in	e,(c)		; E' = the byte (kept even after an error)
	ld	hl,(RHEAD)	; RING[head] = the byte (written before the
	push	hl		;   full test: a full ring's head slot is the
	ld	bc,(RING)	;   empty one, so nothing is harmed)
	add	hl,bc		; HL' -> RING[head]
	ld	(hl),e		; the byte stored
	pop	hl		; HL' = head
	inc	hl		; head + 1, wrapped at 2048
	ld	a,h		; (wrapped:)
	and	RINGM		; (the high byte to 0-7)
	ld	h,a		; HL' = the new head
	ld	bc,(RTAIL)	; would it meet the tail?
	or	a		; (CF = 0 for the SBC)
	sbc	hl,bc		; new head - tail
	jr	z,RXPOLL_FULL	; full: the byte is lost
	ld	a,h		; A = the level's high byte, this byte
	add	hl,bc		;   included (the source: "less one")
	ld	(RHEAD),hl	; the byte is in
	and	RINGM		; (wrapped: head - tail mod 2048)
	cp	HIWAT		; half full?
	call	nc,STOP		; ask the host to stop (once)
	jr	RXPOLL_RET		; done
RXPOLL_FULL:				; (src: RXP4)
	ld	hl,(LOST)	; one more lost
	inc	hl		; (LOST + 1)
	ld	(LOST),hl		; (counted)
RXPOLL_RET:				; (src: RXP9)
	exx			; the caller's BC DE HL
	pop	af		; (the caller's A and F)
	ret		; RXPOLL is invisible to its caller

; ---------------------------------------------------------------------
; RGET - the next byte from the ring
; Exit:   CF = 1, A = the byte; CF = 0: the ring is empty.  Uses DE, HL.
; Callers: F_SESS, F_RECV.
; ---------------------------------------------------------------------
RGET:
	ld	hl,(RTAIL)	; tail = head: empty
	ld	de,(RHEAD)		; (the head)
	or	a		; (CF = 0 for the empty return)
	sbc	hl,de		; tail - head
	ret	z		; empty: CF = 0 from the OR
	add	hl,de		; HL = tail again
	ex	de,hl		; DE = tail
	ld	hl,(RING)	; A = RING[tail]
	add	hl,de		; HL -> RING[tail]
	ld	a,(hl)		; the byte
	inc	de		; tail + 1, wrapped at 2048
	push	af		; (the byte kept over the wrap)
	ld	a,d		; (wrap the high byte)
	and	RINGM		; (to 0-7)
	ld	d,a		; (DE = the new tail)
	ld	(RTAIL),de		; the byte is out of the ring
	pop	af		; A = the byte
	scf			; CF = 1: a byte
	ret		; (CF = 1)

; ---------------------------------------------------------------------
; LEVEL - HL = bytes in the ring (head - tail, mod 2048).  Uses A, DE.
; Callers: F_SESS (H against LOWAT).
; ---------------------------------------------------------------------
LEVEL:
	ld	hl,(RHEAD)		; head ...
	ld	de,(RTAIL)		; ... - tail
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; (may be negative after a wrap)
	ld	a,h		; mod 2048
	and	RINGM		; the high byte mod 8
	ld	h,a		; HL = 0-2047
	ret		; (callers look at H: pages of 256)

; ---------------------------------------------------------------------
; STOP / FLOWOFF / RESUME - ask the host to stop / go on
; ---------------------------------------------------------------------
; STOP:    once (STOPF): then FLOWOFF.  Called by RXPOLL, inside its EXX.
; FLOWOFF: FL_XON: XOFF queued for RXPOLL to send; FL_RTS: RTS off
;          (command ACOM).  Callers: STOP, HOLD.
; RESUME:  unless HOLDF: STOPF = 0, XON queued (FL_XON), RTS on
;          (SIOWORD, whatever the flow control).  Callers: SESS, ENSURE.
; CMDSET:  A = the new command, kept in CMDV and sent.
; CMDOUT:  CMDV sent again.  CMDA: A sent, CMDV kept (BRK's break).
; All use A and F only (CMDA keeps BC).
; TXQ is one byte: an XON queued over an XOFF not yet sent replaces it,
; which is right - only the latest wish matters.
; ---------------------------------------------------------------------
STOP:
	ld	a,(STOPF)	; already stopped?
	or	a		; (Z: not yet)
	ret	nz		; yes: once is enough
	inc	a		; STOPF = 1
	ld	(STOPF),a		; (STOPF = 1)
FLOWOFF:
	ld	a,(FLAGS)	; XON / XOFF?
	bit	1,a		; (FL_XON)
	jr	z,FLOWOFF_RTS		; no: only RTS (maybe)
	ld	a,XOFF		; XOFF, for RXPOLL to send
	ld	(TXQ),a		; (RXPOLL sends it when TxRDY and CTS)
FLOWOFF_RTS:				; (src: ST1)
	ld	a,(FLAGS)	; RTS / CTS?
	bit	2,a		; (FL_RTS)
	ret	z		; no RTS / CTS: done
	ld	a,ACOM		; RTS off
	jr	CMDSET		; (RTS off, remembered in CMDV)
RESUME:
	ld	a,(HOLDF)	; held (menu, log being written)?
	or	a		; (Z: not held)
	ret	nz		; yes: the host stays stopped
	ld	(STOPF),a	; STOPF = 0 (A = 0)
	ld	a,(FLAGS)	; XON / XOFF?
	bit	1,a		; (FL_XON)
	jr	z,RESUME_RTS		; no: only RTS
	ld	a,XON		; XON, for RXPOLL to send
	ld	(TXQ),a		; (RXPOLL sends it when TxRDY and CTS)
RESUME_RTS:				; (src: RS1)
	ld	a,SIOWORD	; RTS on (harmless without /R)
CMDSET:
	ld	(CMDV),a	; the command in force
CMDOUT:
	ld	a,(CMDV)	; CMDV to the chip
CMDA:
	push	bc		; (C is borrowed)
	ld	b,a		; B = the command
	ld	a,(CTL)		; C = the control port
	ld	c,a		; (C = the control port)
	out	(c),b		; the command to the WD2123
	pop	bc		; (the caller's BC)
	ret		; (A = CTL, corrupted)

; ---------------------------------------------------------------------
; SERPUT - A to the channel, when it is free and CTS on
; ---------------------------------------------------------------------
; Entry:  A = the byte.
; Exit:   CF = 0 sent; CF = 1 CTS (status bit 7: the WD2123 has no DSR)
;         or TxRDY stayed off for 65 536 polls and the byte was dropped
;         (DROPS + 1, saturating at 255 - a count nothing reads).
;         Keeps BC, DE, HL; corrupts A.
; Callers: F_RECV, F_SEND, SENDS, SENDN, KEYOUT, DSR.
; Received bytes are taken meanwhile (RXPOLL).  A poll is 210 T, so
; the give-up comes after ~13.8 M T = 3.4 s at 4 MHz (source: "about
; 2 s").  The CTS test is Z86.SYS SPUT's (IOMASK), so an unwired CTS
; input stops TERM's sending as it stops PRN / AUX.
; ---------------------------------------------------------------------
SERPUT:
	push	bc		; (all three
	push	de		; kept for
	push	hl		; the caller)
	ld	e,a		; E = the byte
	ld	hl,0		; 65 536 polls
SERPUT_WAIT:				; (src: QSP1)
	call	RXPOLL		; take a received byte meanwhile
	ld	a,(CTL)		; TxRDY and CTS both on?
	ld	c,a		; (C = the control port)
	in	a,(c)		; the status
	and	IOMASK		; (CTS and TxRDY)
	cp	IOMASK		; (both set?)
	jr	z,SERPUT_SEND	; yes (CF = 0 from the CP)
	dec	hl		; one poll fewer
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,SERPUT_WAIT		; keep trying
	ld	a,(DROPS)	; given up: one more dropped, at most 255
	inc	a		; DROPS + 1 ...
	jr	z,SERPUT_FAIL		; ... unless it would wrap to 0
	ld	(DROPS),a		; (DROPS kept at 255 at most)
SERPUT_FAIL:				; (src: SP0)
	scf			; CF = 1: not sent
	jr	SERPUT_RET		; (common exit)
SERPUT_SEND:				; (src: QSP2)
	dec	c		; the data port
	out	(c),e		; the byte goes
	or	a		; CF = 0
SERPUT_RET:				; (src: SP3)
	pop	hl		; (the caller's HL
	pop	de		; DE
	pop	bc		; and BC)
	ret		; CF = the result

; ---------------------------------------------------------------------
; SENDS - the 0-terminated string at HL to the channel
; Exit:   HL at the 0.  Callers: DSR (DSROK), DAREP (DA100 / DA52).
; ---------------------------------------------------------------------
SENDS:
	ld	a,(hl)		; the next character
	or	a		; the end?
	ret	z		; the 0: done
	call	SERPUT		; (SERPUT keeps HL)
	inc	hl		; the next character
	jr	SENDS		; round again

; ---------------------------------------------------------------------
; SENDN - A in decimal to the channel, no leading zeros
; Entry:  A = 0-255 (the source says 1-255; 0 sends "0": the units
;         digit is always sent).  Corrupts A, BC, DE.
; Callers: DSR (the cursor position report).
; SENDN_DIGIT: one digit of weight B; C = 1 once a digit has gone.
; ---------------------------------------------------------------------
SENDN:
	ld	c,0		; no digit sent yet
	ld	b,100		; hundreds
	call	SENDN_DIGIT		; (B = 100)
	ld	b,10		; tens
	call	SENDN_DIGIT		; (B = 10)
	add	a,'0'		; units: always
	jr	SERPUT		; the units digit, as a tail call
SENDN_DIGIT:				; (src: SN1)
	ld	d,'0'-1		; D = the digit, by repeated subtraction
SENDN_SUB:				; (src: SN2)
	inc	d		; one more in this place
	sub	b		; subtract the weight
	jr	nc,SENDN_SUB		; until it goes below zero
	add	a,b		; one too many: E = the remainder
	ld	e,a		; (E = A mod B)
	ld	a,d		; a zero digit ...
	cp	'0'		; a zero digit?
	jr	nz,SENDN_OUT		; no: send it
	ld	a,c		; ... before any other is not sent
	or	a		; (C = 0: nothing sent yet)
	ld	a,e		; (A = the remainder for the next weight)
	ret	z		; leading zero: skipped
SENDN_OUT:				; (src: SN3)
	ld	a,d		; the digit
	call	SERPUT		; the digit to the host
	ld	c,1		; digits from now on
	ld	a,e		; A = the remainder
	ret		; (A = the remainder)

; =====================================================================
;                    KEYS
; =====================================================================
; KEYOUT - a key to the host
; ---------------------------------------------------------------------
; Entry:  A = the key (from GETKEY).
; Exit:   corrupts all.  Callers: F_SESS.
;
; The Timex terminal's arrow keys send ESC A..D.  For a VT100 host they
; become ESC [ A..D, or ESC O A..D in cursor key mode (CKM, set by
; ESC [ ? 1 h).  An ESC not followed within ~53 ms (800 polls of
; ~265 T; the source says 40 ms) by A..D goes alone, and the key that
; came after it stays held in PEEKEY's buffer for SESS.  A VT52 host
; gets the keys as they are.
; Local echo (FL_ECHO): the key also goes to the screen (EMUL), CR as
; CR LF (with FL_CRLF EMUL's CR adds the LF itself); never ESC or the
; arrows, nor, for a VT52 host, the key right after an ESC (KLAST).
; =====================================================================
KEYOUT:
	ld	(KCH),a		; the key
	ld	a,(FLAGS)	; VT52 host?
	rrca			; (FL_VT52 to CF)
	jr	c,KEYOUT_SEND	; yes: as it is
	ld	a,(KCH)		; ESC?
	cp	ESC		; (the arrows start with ESC)
	jr	nz,KEYOUT_SEND	; no: as it is
	ld	hl,800		; about 50 ms for an arrow's letter
KEYOUT_WAIT:				; (src: KO1)
	call	RXPOLL		; the channel is not forgotten while waiting
	push	hl		; (PEEKEY corrupts A BC DE; HL kept to be safe)
	call	PEEKEY		; a key?  (held, not taken)
	pop	hl		; (the count back)
	jr	c,KEYOUT_ARROW		; a key came: an arrow's letter?
	dec	hl		; one poll fewer
	ld	a,h		; (16-bit zero test)
	or	l		; (HL = 0?)
	jr	nz,KEYOUT_WAIT		; keep waiting
KEYOUT_SEND:				; (src: KO2)
	ld	a,(KCH)		; the key to the host
	call	SERPUT		; (CF ignored: a dropped key is not reported)
	ld	hl,KLAST	; B = the key before, KLAST = this one
	ld	b,(hl)		; (the previous key)
	ld	a,(KCH)		; (this key ...
	ld	(hl),a		; ... remembered for next time)
	ld	a,(FLAGS)	; local echo?
	bit	3,a		; (FL_ECHO)
	ret	z		; no
	rrca			; VT52 host ...
	jr	nc,KEYOUT_ECHO		; VT100 host: no ESC test needed
	ld	a,b		; ... and the key before was ESC: this one is
	cp	ESC		;   a VT52 code's letter, not shown
	ret	z		; (ESC + letter: no echo)
KEYOUT_ECHO:				; (src: KO5)
	ld	a,(KCH)		; ESC is not shown
	cp	ESC		; ESC is never echoed
	ret	z		; (nothing shown)
	cp	0Dh		; CR: CR, then LF
	jr	nz,KEYOUT_SHOW		; any other key: shown as it is
	call	EMUL		; (with flag 10h it has added the LF)
	ld	a,(FLAGS)		; implicit LF on?
	and	FL_CRLF		; (FL_CRLF)
	ret	nz		; yes: ECR has already moved down
	ld	a,0Ah		; the LF
KEYOUT_SHOW:				; (src: KO6)
	jp	EMUL		; as if the host had sent it
KEYOUT_ARROW:				; (src: KO3)
	sub	'A'		; A..D?
	cp	4		; (A..D give 0-3)
	jr	nc,KEYOUT_SEND	; not an arrow: ESC alone; the key stays
					;   held for SESS
	call	GETKEY		; the letter, taken
	ld	(KCH),a		; (the arrow's letter)
	ld	a,ESC		; ESC ...
	call	SERPUT		; (to the host)
	ld	a,(CKM)		; ... [ or, in cursor key mode, O ...
	or	a		; (cursor key mode?)
	ld	a,'['		; normal: ESC [
	jr	z,KEYOUT_FINAL		; (LD keeps the flags)
	ld	a,'O'		; cursor key mode: ESC O
KEYOUT_FINAL:				; (src: KO4)
	call	SERPUT		; the second byte
	ld	a,(KCH)		; ... and the letter (no echo, KLAST kept)
	jp	SERPUT		; the letter, as a tail call

; =====================================================================
;                    THE TERMINAL (the Timex side)
; =====================================================================
; The Terminal 3000 knows ESC H I J K L M Y and plain text, and wraps
; (scrolling at the bottom) as soon as the last column is written.  So:
; the cursor is placed with ESC Y; TROW / TCOL track where the terminal's
; cursor is, so that nothing is sent when it is already right; TATTR
; tracks its attribute (ESC L / ESC M); and the bottom right cell is
; never written (TPUT), as it would scroll the screen.
; ---------------------------------------------------------------------
; TOUT - A to the terminal, as the BIOS's CONOUT, but taking received
; bytes while the terminal is busy
; Exit:   A = 0.  Keeps BC, DE, HL.  Callers: TESC, TGOTO, TPUT, SCRUP.
; CONOUT's retry (Z86.SYS): on an echo time-out TSEND has sent LINKERR;
; wait for the terminal to show LINKERR back, then the whole character
; again.  The wait polls the channel, CONOUT's does not.
; ---------------------------------------------------------------------
TOUT:
	push	bc		; (BC and DE are the caller's:
	push	de		; TSEND corrupts both)
	ld	(TOCH),a	; kept: TSEND destroys B
TOUT_TRY:				; (src: TO1)
	ld	a,(TOCH)	; the character, for every attempt
	ld	b,a		; (B = the byte for TSEND)
	call	TSEND		; Z: through
	jr	z,TOUT_RET		; sent: done
TOUT_ABORT:				; (src: TO2)
	call	RXPOLL		; timed out: wait for the terminal's abort
	in	a,(COM)		; the terminal's link code
	and	MASK		; (link bits only)
	cp	LINKERR		; the terminal's LINKERR: it has given up too
	jr	nz,TOUT_ABORT	; (no time-out, as CONOUT)
	jr	TOUT_TRY	; then from BYTEON again
TOUT_RET:				; (src: TO3)
	pop	de		; (the caller's DE
	pop	bc		; and BC)
	ret		; A = 0

; ---------------------------------------------------------------------
; TSEND - B across the link in two nibbles, each echoed back
; Exit:   Z, A = 0: sent.  NZ, A = LINKERR: an echo did not come in 255
;         polls and LINKERR was sent.  Corrupts A, BC, DE.
; Callers: TOUT.
; Z86.SYS's COSEND (CBIOS A1.1 TXBY) code for code - BYTEON until
; SERVICO, low nibble + CSTAT and high nibble + BSTAT each until echoed,
; STMSK - with RXPOLL in the endless BYTEON wait, the one that waits for
; the terminal.  The echo waits stay short (255 x ~45 T, ~2.9 ms) and
; unpolled, as COSEND's.  Same codes, so the terminal cannot tell.
; ---------------------------------------------------------------------
TSEND:
	ld	a,b		; low nibble in E
	and	0Fh		; (bits 3-0)
	ld	e,a		; E = the low nibble
	ld	a,b		; high nibble in D (COSEND masks before the
	rrca			;   shifts, this after: the same)
	rrca		; (bits 7-4
	rrca		; down to
	rrca		; bits 3-0)
	and	0Fh		; (masked after the shifts)
	ld	d,a		; D = the high nibble
TSEND_OFFER:				; (src: TS1)
	call	RXPOLL		; the wait for the terminal: poll
	ld	a,BYTEON	; ask to send
	out	(COM),a		; BYTEON on the link
	in	a,(COM)		; the terminal's answer
	and	MASK		; (link bits only)
	cp	SERVICO		; terminal ready
	jr	nz,TSEND_OFFER		; not yet: poll again (endless, as COSEND)
	ld	a,e		; low nibble, tagged CSTAT
	or	CSTAT		; (CSTAT tag)
	out	(COM),a		; on the wires
	ld	b,a		; the echo to wait for
	ld	c,0		; 255 polls
TSEND_ECHO_LO:				; (src: TS2)
	in	a,(COM)		; the terminal's side
	dec	c		; one poll fewer
	jr	z,TSEND_FAIL	; no echo in time
	and	MASK		; (drop DRQ and the unwired bit 5)
	cp	b		; echoed?
	jr	nz,TSEND_ECHO_LO		; not yet
	ld	a,d		; high nibble, tagged BSTAT
	or	BSTAT		; (BSTAT tag)
	out	(COM),a		; on the wires
	ld	b,a		; the echo to wait for
	ld	c,0		; 255 polls
TSEND_ECHO_HI:				; (src: TS3)
	in	a,(COM)		; the terminal's side
	dec	c		; one poll fewer
	jr	z,TSEND_FAIL	; no echo in time
	and	MASK		; (link bits only)
	cp	b		; echoed?
	jr	nz,TSEND_ECHO_HI		; not yet
	ld	a,STMSK		; done
	out	(COM),a		; STMSK: end of character, no answer awaited
	xor	a		; Z: sent
	ret
TSEND_FAIL:				; (src: TS4)
	ld	a,LINKERR	; abort
	out	(COM),a		; the terminal sees 07h
	and	a		; NZ (A = 07h)
	ret		; (NZ, A = LINKERR)

; ---------------------------------------------------------------------
; TESC - ESC, then A, to the terminal.  Exit: A = 0; keeps BC, DE, HL.
; Callers: CLRALL, TGOTO, TSETA, CLRK, SCRDN, EDN.
; ---------------------------------------------------------------------
TESC:
	push	af		; the letter, kept
	ld	a,ESC		; ESC first ...
	call	TOUT		; (keeps BC DE HL)
	pop	af		; ... then the letter
	jr	TOUT		; the letter

; ---------------------------------------------------------------------
; TGOTO - the terminal's cursor to row D, column E
; Exit:   TROW = D, TCOL = E.  Uses A.
; Callers: TSYNC, TPUT, CLRK, SCRUP, SCRDN, EDN.
; Nothing is sent if the terminal's cursor is there already (TROW =
; FFh, set by DRAW, never matches).  ESC Y row+32 col+32.
; ---------------------------------------------------------------------
TGOTO:
	ld	a,(TROW)	; there already?
	cp	d		; the same row?
	jr	nz,TGOTO_SEND		; no: move
	ld	a,(TCOL)		; the same column?
	cp	e		; (Z: nothing to do)
	ret	z		; yes: nothing to send
TGOTO_SEND:				; (src: TG1)
	ld	a,VT_CUP	; ESC Y
	call	TESC		; (ESC Y)
	ld	a,d		; row + 32
	add	a,VT_BIAS
	call	TOUT		; the row byte
	ld	a,e		; column + 32
	add	a,VT_BIAS
	call	TOUT		; the column byte
	ld	a,d		; where the terminal's cursor is now
	ld	(TROW),a		; (TROW = D)
	ld	a,e
	ld	(TCOL),a		; (TCOL = E)
	ret		; (A = E)

; ---------------------------------------------------------------------
; TSYNC - the terminal's cursor to the host's (CROW, CCOL).  Uses A, DE.
; Callers: F_SESS (ring empty), SRET, F_DRAW.
; ---------------------------------------------------------------------
TSYNC:
	ld	a,(CROW)		; D = the host's row ...
	ld	d,a
	ld	a,(CCOL)		; ... E = its column
	ld	e,a
	jr	TGOTO		; as a tail jump

; ---------------------------------------------------------------------
; TSETA - the terminal's attribute to A (0 normal, 80h inverse)
; Exit:   TATTR = A.  Uses A; keeps HL.
; Callers: CLRALL, TPUT, CLRK, SCRUP, SCRDN, EDN.
; ESC M (inverse off) or ESC L (inverse on), only on a change.  It is
; set to normal before every erase and scroll: the terminal clears
; with the attribute in force (as test_edit.py's model does - the real
; terminal's behaviour is not documented here; provisional).
; ---------------------------------------------------------------------
TSETA:
	push	hl		; (HL is the caller's)
	ld	hl,TATTR	; the same as now?
	cp	(hl)		; (TATTR = A?)
	jr	z,TSETA_RET	; yes: nothing to send
	ld	(hl),a		; the new one
	or	a		; normal: ESC M
	ld	a,VT_INVOFF		; (LD keeps the flags)
	jr	z,TSETA_SEND		; normal: ESC M
	ld	a,VT_INVON	; inverse: ESC L
TSETA_SEND:				; (src: TSA1)
	call	TESC		; ESC L or ESC M
TSETA_RET:				; (src: TSA2)
	pop	hl		; (the caller's HL)
	ret		; (A corrupted)

; ---------------------------------------------------------------------
; TPUT - cell A (character, bit 7 inverse) at row D, column E on the
; terminal; never the bottom right one
; Exit:   TCOL advanced; at the end of a row TROW + 1, TCOL = 0 (the
;         terminal has wrapped).  Uses A.
; Callers: PUTCH, DRAWR, SCRUP.
; ---------------------------------------------------------------------
TPUT:
	push	af		; the cell
	ld	a,(ROWS)	; the bottom right cell?
	dec	a		; ROWS - 1
	cp	d		; the bottom row?
	jr	nz,TPUT_DRAW		; no: draw
	ld	a,(COLS)		; (COLS - 1)
	dec	a		; the last column?
	cp	e
	jr	nz,TPUT_DRAW		; no: draw
	pop	af		; yes: writing it would scroll the terminal;
	ret			;   it stays in the shadow (SCRUP draws it)
TPUT_DRAW:				; (src: TP1)
	call	TGOTO		; the terminal's cursor there
	pop	af		; inverse or not
	push	af		; (and kept once more)
	and	80h		; bit 7: inverse
	call	TSETA		; the attribute first
	pop	af		; the character
	and	7Fh		; the character, 7 bits
	call	TOUT		; to the terminal
	ld	a,(TCOL)	; the terminal's cursor moved on
	inc	a		; one column on
	ld	(TCOL),a		; (where the terminal's cursor is)
	push	hl		; (HL kept)
	ld	hl,COLS		; past the last column?
	cp	(hl)		; = COLS?
	pop	hl		; (HL back)
	ret	nz		; no: done
	xor	a		; the terminal wrapped
	ld	(TCOL),a		; column 0 ...
	ld	a,(TROW)		; (the row ...
	inc	a		; ... one down)
	ld	(TROW),a		; (TROW + 1)
	ret		; (A corrupted)

; ---------------------------------------------------------------------
; CLRK - from row D, column E to the end of the line on the terminal
; (ESC K, attribute normal first).  Callers: DRAWR, ELN.
; ---------------------------------------------------------------------
CLRK:
	call	TGOTO		; the terminal's cursor to D, E
	xor	a		; erase in normal video
	call	TSETA		; (ESC M if needed)
	ld	a,VT_EOL	; ESC K
	jp	TESC		; ESC K, as a tail call

; ---------------------------------------------------------------------
; DRAWR - row D from column E on the terminal, from the shadow
; Entry:  D = row, E = first column.  Corrupts all.
; Callers: REDR, PUTCH (insert mode), ELN_START, CH_REDRAW.
; Only up to the last non-blank cell is drawn; the rest of the line,
; if any, is cleared with one ESC K.  C = the last column drawable:
; COLS-1, or COLS-2 on the bottom row (TPUT would skip it anyway).
; The trailing-blank scan polls the channel every 16 cells.
; ---------------------------------------------------------------------
DRAWR:
	ld	a,(COLS)	; C = the last column to draw ...
	dec	a		; COLS - 1
	ld	c,a
	ld	a,(ROWS)	; ... one less on the bottom row
	dec	a		; ROWS - 1
	cp	d		; the bottom row?
	jr	nz,DRAWR_RANGE		; no: C stays
	dec	c		; yes: the bottom right cell is not drawn
DRAWR_RANGE:				; (src: DR1)
	ld	a,c		; starting past it: only the clear
	cp	e		; (C < E?)
	jr	c,CLRK		; nothing to draw: clear from E
	push	de		; HL = the cell (D, C)
	ld	e,c		; (column C)
	call	CELLP		; HL -> the row's last drawable cell
	pop	de		; (D, E back)
	ld	b,c		; B = the last cell that is not blank
DRAWR_TRIM:				; (src: DR2)
	ld	a,(hl)		; blank?  (an inverse blank, A0h, is not)
	cp	' '		; a blank?
	jr	nz,DRAWR_FROM		; no: the last non-blank is B
	ld	a,b		; back at the first column: all blank
	cp	e
	jr	z,CLRK		; all blank
	and	15		; a poll every 16 cells
	call	z,RXPOLL		; (every 16 columns, a poll)
	dec	hl		; one cell left ...
	dec	b		; ... one column left
	jr	DRAWR_TRIM		; round again
DRAWR_FROM:				; (src: DR3)
	push	bc		; HL = the first cell (D, E)
	call	CELLP		; HL -> (D, E)
	pop	bc		; (B, C back)
DRAWR_CELL:				; (src: DR4)
	ld	a,(hl)		; columns E..B
	call	TPUT		; the cell to the terminal (A, D, E)
	inc	hl		; the next cell
	ld	a,e		; (the column just drawn)
	inc	e		; one column on
	cp	b		; was it B?
	jr	nz,DRAWR_CELL		; no: the next
	ld	a,c		; drawn to the last column: done
	cp	e		; (C < E: drawn to C)
	ret	c		; yes: nothing to clear
	jr	CLRK		; else the rest of the line cleared

; ---------------------------------------------------------------------
; REDR - rows B to C on the terminal, from the shadow.  Corrupts all.
; Callers: F_DRAW, SCRR, EDN (ED 1), IL / DL.
; ---------------------------------------------------------------------
REDR:
	ld	d,b		; D = the row
REDR_ROW:				; (src: QRD1)
	push	bc		; (the range
	push	de		; and the row survive DRAWR)
	ld	e,0		; the whole row
	call	DRAWR		; one row, from column 0
	pop	de
	pop	bc
	ld	a,d		; the last?
	cp	c		; the last row?
	ret	z		; yes: done
	inc	d		; the next row
	jr	REDR_ROW		; round again

; =====================================================================
;                    THE SHADOW (the host's screen, in 8086 memory)
; =====================================================================
; SCR: ROWS x COLS bytes in TERM.COM's memory, one per cell: the
; character in bits 6-0, bit 7 = inverse.  A blank is ' ' (20h).
; TERM.COM writes into it too (its hello line, then DRAW).
; ---------------------------------------------------------------------
; ROWP - HL = SCR + A x COLS (the start of row A).  Uses A.
; CELLP - HL = the cell at row D, column E.  Uses A.
; ADDHLA - HL += A.  SUBHLA - HL -= A (keeps DE).
; COLS is 64 or 80: A x 64, plus A x 16 unless COLS = 64.
; ---------------------------------------------------------------------
ROWP:
	push	de		; (DE is the caller's)
	ld	l,a		; HL = A x 16
	ld	h,0		; (HL = A)
	add	hl,hl		; x 2
	add	hl,hl		; x 4
	add	hl,hl		; x 8
	add	hl,hl		; x 16
	ld	d,h		; DE = A x 16
	ld	e,l		; (DE = A x 16)
	add	hl,hl		; HL = A x 64
	add	hl,hl		; x 64
	ld	a,(COLS)	; 64 columns: that is all
	cp	64		; (COLS = 64?)
	jr	z,ROWP_BASE		; yes: A x 64
	add	hl,de		; else 80: A x 64 + A x 16
ROWP_BASE:				; (src: RP1)
	ld	de,(SCR)	; + the shadow's start
	add	hl,de		; A x 80
	pop	de		; (the caller's DE)
	ret		; HL = the row's first cell
CELLP:
	ld	a,d		; the row ...
	call	ROWP		; HL = row D's start
	ld	a,e		; ... + the column
ADDHLA:
	add	a,l		; HL + A
	ld	l,a
	ret	nc		; no carry: done
	inc	h		; carry into H
	ret		; (HL = the cell)
SUBHLA:
	push	de		; (DE kept)
	ld	e,a		; DE = A
	ld	d,0		; (DE = A)
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; HL - A
	pop	de		; (the caller's DE)
	ret		; (A kept)

; ---------------------------------------------------------------------
; NROWS - BC = A rows' bytes (A x COLS).  Uses A, HL.
; Callers: RCOUNT.
; ---------------------------------------------------------------------
NROWS:
	call	ROWP		; SCR + A x COLS ...
	ld	bc,(SCR)	; ... less SCR
	or	a		; (CF = 0 for the SBC)
	sbc	hl,bc		; HL = A x COLS
	ld	b,h		; BC = it
	ld	c,l
	ret		; (HL corrupted)

; ---------------------------------------------------------------------
; MVF / MVB - LDIR / LDDR of BC (> 0) bytes, in pieces of 32 with
; RXPOLL between them
; ---------------------------------------------------------------------
; A 32-byte LDIR is 672 T, well inside the 2 083 T a byte takes at
; 19 200 baud.  The last piece is 1-32 bytes.  MVSUB: BC -= 32, then
; RXPOLL (as a tail jump).  Uses A, BC, DE, HL.
; Callers: FILL, SHUP, ICHS, DCHS (MVF); SHDN, ICHS (MVB).
; ---------------------------------------------------------------------
MVF:
	ld	a,b		; more than 32 left?
	or	a		; (BC >= 256?)
	jr	nz,MVF_PIECE		; yes: a whole piece
	ld	a,c
	cp	33		; (33 or more?)
	jr	c,MVF_LAST	; no: the last piece
MVF_PIECE:				; (src: MVF1)
	push	bc		; (the count kept)
	ld	bc,32		; 32 bytes
	ldir		; 32 bytes on
	pop	bc		; (the count back)
	call	MVSUB		; BC -= 32, and a poll
	jr	MVF		; round again
MVF_LAST:				; (src: MVF2)
	ldir			; the rest
	ret		; (DE, HL past the move)
MVB:
	ld	a,b		; more than 32 left?
	or	a		; (BC >= 256?)
	jr	nz,MVB_PIECE		; yes: a whole piece
	ld	a,c
	cp	33		; (33 or more?)
	jr	c,MVB_LAST	; no: the last piece
MVB_PIECE:				; (src: MVB1)
	push	bc		; (the count kept)
	ld	bc,32		; 32 bytes, downwards
	lddr		; 32 bytes back
	pop	bc		; (the count back)
	call	MVSUB		; BC -= 32, and a poll
	jr	MVB		; round again
MVB_LAST:				; (src: MVB2)
	lddr			; the rest
	ret		; (DE, HL below the move)
MVSUB:
	ld	a,c		; BC -= 32
	sub	32		; (C - 32)
	ld	c,a
	jr	nc,MVSUB_POLL		; no borrow
	dec	b		; borrow from B
MVSUB_POLL:				; (src: MVS1)
	jp	RXPOLL		; and a received byte taken

; ---------------------------------------------------------------------
; FILL - BC cells from HL blank.  Uses A, BC, DE, HL.
; One blank, then the usual overlapping copy one byte ahead (MVF).
; Callers: CLRALL, FILLRW, DCHS, ECHS, EDN, ELN.
; ---------------------------------------------------------------------
FILL:
	ld	a,b		; nothing to do?
	or	c		; (BC = 0?)
	ret	z		; nothing
	ld	(hl),' '	; the seed blank
	dec	bc		; one cell done
	ld	a,b		; just the one?
	or	c		; (BC = 0?)
	ret	z		; it was the only one
	ld	d,h		; DE = HL + 1
	ld	e,l		; (DE = HL ...
	inc	de		; ... + 1)
	call	MVF		; and BC - 1 copies of it
	ret		; (DE, HL past the blanks)

; ---------------------------------------------------------------------
; SHUP / SHDN - rows RT to RB of the shadow one up / down; the row that
; comes in is blank.  Corrupts all.
; Callers: SCRUP, SCRDN; IL / DL through ILOP (n times).
; RCOUNT: BC = (RB - RT) rows' bytes, the part that moves.
; ---------------------------------------------------------------------
SHUP:
	call	RXPOLL		; a byte may have come since the last
	ld	a,(RT)		; DE = row RT (the destination)
	call	ROWP		; HL = row RT
	ex	de,hl		; DE = row RT
	call	RCOUNT		; BC = rows RT+1..RB
	ld	a,(COLS)	; HL = row RT + 1 (the source)
	ld	l,a		; (HL = COLS)
	ld	h,0		; (H = 0)
	add	hl,de		; HL = row RT + 1
	ld	a,b		; a one-row region: nothing moves
	or	c		; (BC = 0?)
	jr	z,SHUP_BLANK		; only the blank row
	call	MVF		; up a row
SHUP_BLANK:				; (src: SHU1)
	ex	de,hl		; HL = past the last moved: row RB
	jr	FILLRW		; blank
SHDN:
	call	RXPOLL		; (as SHUP)
	call	RCOUNT		; BC = rows RT..RB-1
	ld	a,(RB)		; DE = row RB's last cell (the destination)
	call	ROWP		; HL = row RB
	ld	a,(COLS)		; (COLS - 1)
	dec	a		; (A = COLS - 1)
	call	ADDHLA		; HL = row RB's last cell
	ld	d,h		; DE = it
	ld	e,l
	ld	a,(COLS)	; HL = a row before (the source)
	call	SUBHLA		; HL = row RB - 1's last cell
	ld	a,b		; a one-row region: nothing moves
	or	c		; (BC = 0?)
	jr	z,SHDN_BLANK		; only the blank row
	call	MVB		; down a row, from the end
SHDN_BLANK:				; (src: SHD1)
	ld	a,(RT)		; row RT blank
	call	ROWP		; HL = row RT
FILLRW:
	ld	a,(COLS)	; one row of blanks at HL
	ld	c,a		; (C = COLS)
	ld	b,0		; (BC = COLS)
	jr	FILL		; COLS blanks, as a tail call
RCOUNT:
	ld	a,(RB)		; RB - RT rows
	ld	hl,RT
	sub	(hl)		; A = RB - RT
	jp	NROWS		; BC = that many rows' bytes

; ---------------------------------------------------------------------
; SETRG - RT, RB = the scrolling region (TOP, BOT).  Uses A.
; FULLSC - Z if the region is the whole screen.  Uses A, HL.
; Callers: SCRUP, SCRDN.
; ---------------------------------------------------------------------
SETRG:
	ld	a,(TOP)		; (the region's top ...
	ld	(RT),a		; ... for SHUP / SHDN)
	ld	a,(BOT)		; (its bottom ...
	ld	(RB),a		; ... likewise)
	ret		; (A = BOT)
FULLSC:
	ld	a,(TOP)		; top must be row 0 ...
	or	a		; (TOP = 0?)
	ret	nz		; no: a region
	ld	a,(ROWS)	; ... and bottom the last row
	dec	a		; (ROWS - 1)
	ld	hl,BOT
	cp	(hl)		; = ROWS - 1?
	ret		; Z: the whole screen

; ---------------------------------------------------------------------
; SCRUP - the region up one line.  Corrupts all.
; Callers: INDEX (at the region's bottom).
; On the whole screen the terminal scrolls itself: LF on its bottom row
; (in normal video, so the new row comes in blank).  The cell that sat
; at the bottom right, never drawn, is now at the end of the row above:
; drawn if it is not blank.  A smaller region is drawn again (SCRR).
; ---------------------------------------------------------------------
SCRUP:
	call	SETRG		; the shadow first
	call	SHUP		; rows RT..RB up one
	call	FULLSC		; (Z: whole screen)
	jr	nz,SCRR		; a region: draw it again
	ld	a,(ROWS)	; the terminal's cursor to its bottom row
	dec	a		;   (any column: LF only goes down)
	ld	d,a		; (D = the last row)
	ld	a,(TROW)		; the terminal's cursor already there?
	cp	d		; (row only)
	jr	z,SCRUP_LF		; yes: no ESC Y
	ld	e,0		; (column 0)
	call	TGOTO		; ESC Y to the bottom row
SCRUP_LF:				; (src: SU1)
	xor	a		; normal video
	call	TSETA		; (ESC M if needed)
	ld	a,0Ah		; LF: the terminal scrolls
	call	TOUT		; (to the terminal)
	ld	a,(ROWS)	; the bottom right cell, which could not
	sub	2		; be drawn, is now a row up
	ld	d,a		; (D = ROWS - 2)
	ld	a,(COLS)		; (the last column)
	dec	a		; (COLS - 1)
	ld	e,a
	call	CELLP		; HL -> the cell
	ld	a,(hl)		; blank: nothing to draw
	cp	' '		; (blank?)
	ret	z		; nothing to show
	jp	TPUT		; draw it (TPUT allows: not the bottom row)
SCRR:
	ld	a,(TOP)		; rows TOP..BOT from the shadow
	ld	b,a		; (B = TOP)
	ld	a,(BOT)		; (the region's bottom)
	ld	c,a		; (C = BOT)
	jp	REDR		; rows TOP..BOT drawn again

; ---------------------------------------------------------------------
; SCRDN - the region down one line (ESC I on the terminal's top row on
; the whole screen, else drawn again).  Corrupts all.
; Callers: RINDEX (at the region's top).
; ---------------------------------------------------------------------
SCRDN:
	call	SETRG		; the shadow first
	call	SHDN		; rows RT..RB down one
	call	FULLSC		; (Z: whole screen)
	jr	nz,SCRR		; a region: draw it again
	ld	a,(TROW)	; the terminal's cursor to its top row
	or	a		;   (ESC I scrolls only from row 0)
	jr	z,SCRDN_RLF		; already on row 0
	ld	de,0		; (row 0, column 0)
	call	TGOTO		; ESC Y 0 0
SCRDN_RLF:				; (src: SD1)
	xor	a		; normal video
	call	TSETA		; (ESC M if needed)
	ld	a,VT_RLF	; ESC I: the terminal scrolls down
	jp	TESC		; (ESC I as a tail call)

; =====================================================================
;                    THE SCREEN (the host's VT100)
; =====================================================================
; CROW / CCOL are the host's cursor; WRAPF is the VT100's pending wrap:
; writing the last column leaves the cursor there with WRAPF = AWM, and
; the next character first goes to column 0 of the next line.  Every
; cursor move clears it.
; ---------------------------------------------------------------------
; INDEX - down a line, scrolling at the region's bottom (LF VT FF, ESC D,
; ESC E, wrap).  RINDEX - up a line, scrolling at the region's top
; (ESC M, VT52 ESC I).  Below / above the region the cursor stops at
; the screen's edge without scrolling, as on a VT100.  Corrupt all.
; ---------------------------------------------------------------------
INDEX:
	xor	a		; no wrap pending
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(BOT)		; at the region's bottom: scroll it
	ld	hl,CROW		; (the cursor's row)
	cp	(hl)		; CROW = BOT?
	jr	z,SCRUP		; yes: the region scrolls
	ld	a,(ROWS)	; at the screen's bottom (below the region):
	dec	a		;   stay
	cp	(hl)		; CROW = ROWS - 1?
	ret	z		; yes: no further
	inc	(hl)		; else one down
	ret		; (one row down)
RINDEX:
	xor	a		; no wrap pending
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(TOP)		; at the region's top: scroll it down
	ld	hl,CROW		; (the cursor's row)
	cp	(hl)		; CROW = TOP?
	jr	z,SCRDN		; yes: the region scrolls down
	ld	a,(hl)		; at row 0 (above the region): stay
	or	a		; (row 0?)
	ret	z		; yes: no further
	dec	(hl)		; else one up
	ret		; (one row up)

; ---------------------------------------------------------------------
; PUTCH - the character A at the cursor, in ATTR
; Exit:   corrupts all.  Callers: GPUT, EM8 ('?').
; Insert mode (IRM) shifts the rest of the line right first and draws
; it all again; otherwise the one cell is drawn.
; ---------------------------------------------------------------------
PUTCH:
	call	RXPOLL		; (halfway from the last one to TOUT's)
	ld	c,a		; C = the character
	ld	a,(WRAPF)	; the last column was written: wrap now
	or	a		; (WRAPF = 0?)
	jr	z,PUTCH_CELL		; no wrap pending
	xor	a		; column 0 of the next line
	ld	(CCOL),a		; (CCOL = 0)
	push	bc		; (the character kept)
	call	INDEX		; (may scroll)
	pop	bc		; (the character back)
PUTCH_CELL:				; (src: PC1)
	ld	a,(CROW)	; D, E = the cursor
	ld	d,a		; (D = CROW)
	ld	a,(CCOL)		; (the column)
	ld	e,a		; (E = CCOL)
	ld	a,(IRM)		; insert mode?
	or	a		; (IRM = 0?)
	jr	z,PUTCH_OVER		; replace mode
	push	bc		; insert mode
	ld	a,1		; one cell opened at the cursor
	call	ICHS		; (the cells right of the cursor move on)
	pop	bc		; (the character back)
	call	CURP		; HL = the cell (D, E again)
	ld	a,(ATTR)	; character + attribute
	or	c		; (bit 7 = inverse)
	ld	(hl),a		; into the shadow
	call	DRAWR		; the rest of the line drawn
	jr	PUTCH_ADVANCE		; (on to the column advance)
PUTCH_OVER:				; (src: PC2)
	call	CELLP		; HL = the cell
	ld	a,(ATTR)	; character + attribute into the shadow ...
	or	c		; (bit 7 = inverse)
	ld	(hl),a
	call	TPUT		; ... and onto the terminal
PUTCH_ADVANCE:				; (src: PC3)
	ld	a,(CCOL)	; the last column?
	ld	e,a		; (E = CCOL)
	ld	a,(COLS)		; (the last column ...
	dec	a		; ... COLS - 1)
	cp	e		; (CCOL = it?)
	jr	z,PUTCH_LASTCOL		; yes: pending wrap
	inc	e		; no: one right
	ld	a,e		; (the new column)
	ld	(CCOL),a
	ret		; (WRAPF stays 0)
PUTCH_LASTCOL:				; (src: PC4)
	ld	a,(AWM)		; yes: a wrap pending, if autowrap is on
	ld	(WRAPF),a	;   (off: later characters overwrite it)
	ret		; (CCOL stays on the last column)

; ---------------------------------------------------------------------
; ICHS / DCHS / ECHS - insert / delete / blank A cells at the cursor, in
; the shadow only (the caller draws).  Corrupt all.
; CHCNT: B = n (0 taken as 1), at most the cells left in the row;
;        A = cells left - n, the cells that move.
; Callers: PUTCH (ICHS, insert mode); ICH / DCH / ECH through
; CH_DISPATCH, which returns to CH_REDRAW.
; ---------------------------------------------------------------------
CHCNT:
	ld	b,a		; B = n, at most the cells left;
	or	a		; A = cells left - n
	jr	nz,CHCNT_LEFT		; (n <> 0)
	inc	b		; (0 means 1)
CHCNT_LEFT:				; (src: CHC1)
	ld	a,(CCOL)	; A = COLS - CCOL, the cells left
	ld	c,a		; (C = CCOL)
	ld	a,(COLS)		; (the width)
	sub	c		; cells from the cursor to the end
	cp	b		; n more than that: all of them
	jr	nc,CHCNT_RET		; n fits
	ld	b,a		; B = the cells left
CHCNT_RET:				; (src: CHC2)
	sub	b		; A = the cells that move
	ret		; (B = n, A = cells to move)
ICHS:
	call	CHCNT		; B = n, A = cells that move
	push	bc		; (n
	push	af		; and the count kept)
	ld	a,(CROW)	; DE = the row's last cell (the destination)
	ld	d,a		; (D = the cursor's row)
	ld	a,(COLS)		; (the last column ...
	dec	a		; ... COLS - 1)
	ld	e,a
	call	CELLP	; the row's last cell
	ld	d,h		; DE = the last cell
	ld	e,l
	pop	af		; (A = cells that move)
	pop	bc
	push	bc		; (kept again
	push	af		; for after the move)
	ld	a,b		; HL = n cells before it (the source)
	call	SUBHLA		; HL = the last cell - n
	pop	af		; BC = the cells that move
	ld	c,a		; (C = cells that move)
	ld	b,0
	or	a		; (none?)
	jr	z,ICHS_BLANK	; none
	call	MVB		; right by n, from the end
ICHS_BLANK:				; (src: IC1)
	pop	bc		; B = n: blanked at the cursor
	jr	ECHS_FILL		; the n cells at the cursor blank
DCHS:
	call	CHCNT		; B = n, A = cells that move
	push	bc		; (n
	push	af		; and the count kept)
	call	CURP		; DE = the cursor's cell (the destination)
	ld	d,h		; DE = the cursor's cell
	ld	e,l
	pop	af
	pop	bc
	push	bc		; (kept again
	push	af		; for after the move)
	ld	a,b		; HL = n cells on (the source)
	call	ADDHLA		; HL = n cells on
	pop	af		; BC = the cells that move
	ld	c,a		; (C = cells that move)
	ld	b,0
	or	a		; (none?)
	jr	z,DCHS_BLANK	; none
	call	MVF		; left by n
DCHS_BLANK:				; (src: DC1)
	pop	bc		; B = n
	ex	de,hl		; HL = past the moved cells
	ld	c,b		; n blanks at the end of the row
	ld	b,0		; (BC = n)
	jp	FILL		; as a tail call
ECHS:
	call	CHCNT		; B = n
ECHS_FILL:				; (src: ECHS1)
	push	bc		; HL = the cursor's cell
	call	CURP		; HL = the cursor's cell
	pop	bc
	ld	c,b		; n blanks there
	ld	b,0		; (BC = n)
	jp	FILL		; as a tail call
; CURP - HL = the cursor's cell; D, E = CROW, CCOL.  Uses A.
CURP:
	ld	a,(CROW)
	ld	d,a
	ld	a,(CCOL)
	ld	e,a
	jp	CELLP		; HL = the cell

; ---------------------------------------------------------------------
; SETCUR - the cursor to row D, column E, kept on the screen (values
; past the edge stop there).  CLRW - no wrap pending.  Use A.
; Absolute: there is no origin mode (DECOM).
; ---------------------------------------------------------------------
SETCUR:
	ld	a,(ROWS)	; row at most the last
	dec	a		; (ROWS - 1)
	cp	d		; (D within?)
	jr	nc,SETCUR_COL		; yes
	ld	d,a		; no: the last row
SETCUR_COL:				; (src: SC1)
	ld	a,(COLS)	; column at most the last
	dec	a		; (COLS - 1)
	cp	e		; (E within?)
	jr	nc,SETCUR_SET		; yes
	ld	e,a		; no: the last column
SETCUR_SET:				; (src: SC2)
	ld	a,d
	ld	(CROW),a		; the host's cursor
	ld	a,e
	ld	(CCOL),a
CLRW:
	xor	a		; (any move ends a pending wrap)
	ld	(WRAPF),a		; (WRAPF = 0)
	ret		; (A = 0)

; ---------------------------------------------------------------------
; EDN - erase in display: A = 0 cursor to end, 1 start to cursor, 2 (or
; more: ESC [ 3 J too) all.  Corrupts all.
; Callers: CED (ESC [ n J), V52ESC (ESC J).
; 0: ESC J on the terminal from the cursor.  1: the terminal has no
; "erase above", so rows 0..CROW are drawn again.  2: CLRALL (the
; cursor stays where it was, as on a VT100).
; ---------------------------------------------------------------------
EDN:
	cp	1		; (0, 1 or 2+)
	jr	z,EDN_START		; 1: start to cursor
	jp	nc,CLRALL	; 2 and up: all
	call	CURP		; 0: from the cursor's cell ...
	push	de		; (D, E kept for TGOTO)
	ex	de,hl		; (DE = the cell)
	ld	hl,(SCREND)	; ... to the end of the shadow
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; SCREND - the cell
	ld	b,h		; BC = the count
	ld	c,l
	ex	de,hl		; (HL = the cell)
	call	FILL		; blanks
	pop	de		; and ESC J at the cursor
	call	TGOTO		; the terminal's cursor there
	xor	a		; (normal video ...
	call	TSETA		; ... for the erase)
	ld	a,VT_EOS		; (ESC J)
	jp	TESC		; as a tail call
EDN_START:				; (src: ED1)
	call	CURP		; 1: SCR to the cursor's cell, inclusive
	push	de		; (D, E kept)
	inc	hl		; one past the cursor
	ld	de,(SCR)		; (the shadow's start)
	or	a		; (CF = 0 for the SBC)
	sbc	hl,de		; cells up to and with the cursor
	ld	b,h		; BC = the count
	ld	c,l
	ex	de,hl		; HL = SCR
	call	FILL		; blanks
	pop	de		; rows 0..CROW drawn again
	ld	b,0		; (B = row 0)
	ld	c,d		; (C = CROW)
	jp	REDR		; rows 0..CROW drawn

; ---------------------------------------------------------------------
; ELN - erase in line: A = 0 cursor to end, 1 start to cursor, 2 all
; (more than 2: as 2).  Corrupts all.  Callers: CEL, V52ESC (ESC K).
; 0 and 2: ESC K from the cursor / column 0; 1: the row drawn again.
; ---------------------------------------------------------------------
ELN:
	ld	b,a		; (the parameter)
	ld	a,(CROW)	; D = the row
	ld	d,a		; (D = CROW)
	ld	a,b		; (the parameter)
	cp	1		; (0, 1 or 2+)
	jr	z,ELN_START		; 1: start to cursor
	jr	nc,ELN_ALL		; 2 or more: the whole line
	ld	a,(CCOL)	; 0: from the cursor's cell
	ld	e,a		; (E = CCOL)
	call	CELLP		; HL -> the cursor's cell
	ld	a,(COLS)	; COLS - CCOL cells
	sub	e		; cells to the end
ELN_FILL:				; (src: EL0)
	ld	c,a		; BC = A cells blank
	ld	b,0		; (BC = A)
	push	de		; (D, E kept for CLRK)
	call	FILL		; blanks
	pop	de		; (D, E back)
	jp	CLRK		; ESC K from D, E
ELN_START:				; (src: EL1)
	ld	e,0		; 1: from column 0 ...
	call	CELLP		; HL -> column 0
	ld	a,(CCOL)	; ... to the cursor, inclusive
	inc	a		; (CCOL + 1 cells)
	ld	c,a
	ld	b,0
	push	de		; (D, E kept)
	call	FILL		; blanks
	pop	de		; (D, E = row, 0)
	jp	DRAWR		; the row drawn again from column 0
ELN_ALL:				; (src: EL2)
	ld	e,0		; 2: the whole row
	call	CELLP		; HL -> column 0
	ld	a,(COLS)		; (COLS cells)
	jr	ELN_FILL		; (and ESC K from column 0)

; =====================================================================
;                    THE HOST'S CODES (VT100 / VT52 parser)
; =====================================================================
; EMUL - a byte from the host
; ---------------------------------------------------------------------
; Entry:  A = the byte.  Exit: corrupts all.
; Callers: F_SESS, KEYOUT (local echo).
;
; 00h-1Fh: controls (ECTRL), acted on even inside a sequence, as on a
; VT100; 7Fh: ignored; 20h-7Eh: text, or the next byte of a sequence
; (PST <> 0: ESTATE); 80h-FFh: outside a sequence one '?' for each
; C0h-FFh (a UTF-8 character's lead byte, or Latin-1's upper quarter),
; 80h-BFh dropped (UTF-8's continuation bytes - but also Latin-1's
; A0h-BFh, and the 8-bit controls such as CSI 9Bh).
;
; PST, the parser's state: 0 text, 1 ESC, 2 CSI, 3 ESC ( ), 4 ESC #,
; 5 / 6 VT52 ESC Y's row / column.
; =====================================================================
EMUL:
	ld	c,a		; C = the byte
	cp	80h		; 8-bit?
	jr	nc,EM8		; 80h-FFh
	cp	20h		; a control?
	jr	c,ECTRL		; 00h-1Fh
	cp	7Fh		; DEL: ignored
	ret	z
	ld	a,(PST)		; inside a sequence?
	or	a		; (PST = 0?)
	jp	nz,ESTATE		; no: part of a sequence
; GPUT - text: through the character set in use (G0 or G1, by GL)
GPUT:
	ld	hl,G0	; the character set in use
	ld	a,(GL)		; (GL = 0 / 1)
	call	ADDHLA		; HL -> G0 or G1
	ld	a,(hl)		; 0 ASCII, 1 DEC special graphics
	or	a		; (Z: ASCII)
	ld	a,c		; (the character; LD keeps the flags)
	jp	z,PUTCH		; ASCII: as it is
	cp	5Fh	; DEC special graphics: 5Fh-7Eh
	jp	c,PUTCH		; below: as it is
	sub	5Fh		; the nearest ASCII (GRTAB)
	ld	hl,GRTAB		; (the table)
	call	ADDHLA		; HL -> the replacement
	ld	a,(hl)		; (an ASCII look-alike)
	jp	PUTCH		; shown
EM8:
	ld	a,(PST)	; 8-bit and UTF-8: one ? per character
	or	a		; inside a sequence: ignored (it goes on)
	ret	nz		; (in a sequence: dropped)
	ld	a,c		; (the byte)
	cp	0C0h		; 80h-BFh: dropped
	ret	c		; (continuation byte: nothing)
	ld	a,'?'		; C0h-FFh: '?'
	jp	PUTCH		; one per character

; ---------------------------------------------------------------------
; ECTRL - a control code (C = A = 00h-1Fh)
; ESC starts a sequence; CAN, SUB end one; CR; LF VT FF go down (no
; new-line mode); BS; TAB; SO / SI choose G1 / G0.  The rest (BEL,
; ENQ, ...) is ignored.
; ---------------------------------------------------------------------
ECTRL:
	cp	ESC		; ESC: a sequence starts
	jr	z,EESC
	cp	18h		; CAN
	jr	z,ECAN
	cp	1Ah		; SUB
	jr	z,ECAN
	cp	0Dh		; CR
	jr	z,ECR
	cp	0Ah		; LF
	jp	z,INDEX
	cp	0Bh		; VT
	jp	z,INDEX
	cp	0Ch		; FF
	jp	z,INDEX
	cp	08h		; BS
	jr	z,EBS
	cp	09h		; TAB
	jr	z,ETAB
	cp	0Eh		; SO
	jr	z,ESO
	cp	0Fh		; SI (anything else: ignored)
	ret	nz		; (BEL and the rest)
	xor	a	; SI: G0
	jr	ESO_SET		; (GL = 0)
ESO:
	ld	a,1	; SO: G1
ESO_SET:				; (src: ESO1)
	ld	(GL),a		; (GL = 0 / 1)
	ret		; (no redraw: only later text)
EESC:
	ld	a,PS_ESC	; after ESC (an unfinished sequence is dropped)
	jr	ECAN_SET		; (PST = 1)
ECAN:
	xor	a		; back to text
ECAN_SET:				; (src: ECAN1)
	ld	(PST),a
	ret		; (the bytes so far are dropped)
ECR:
	xor	a		; column 0
	ld	(CCOL),a		; (CCOL = 0)
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(FLAGS)	; flag 10h: a LF after each CR
	and	FL_CRLF		; (FL_CRLF)
	ret	z		; no: CR alone
	jp	INDEX		; yes: LF too
EBS:
	xor	a		; one left, stopping at column 0
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(CCOL)		; (the column)
	or	a		; (column 0?)
	ret	z		; yes: stays
	dec	a		; (one left)
	ld	(CCOL),a
	ret		; (no wrap back to the line above)
ETAB:
	ld	a,(CCOL)	; the next multiple of 8 (fixed stops) ...
	or	7		; (to the stop below the next ...
	inc	a		; ... multiple of 8)
	ld	hl,COLS		; ... at most the last column
	cp	(hl)		; past the last column?
	jr	c,ETAB_SET		; no
	ld	a,(hl)
	dec	a		; (COLS - 1)
ETAB_SET:				; (src: ET1)
	ld	(CCOL),a
	jp	CLRW		; (WRAPF = 0)

; ---------------------------------------------------------------------
; ESTATE - C = a printable byte inside a sequence; A = PST (1-6)
; ---------------------------------------------------------------------
ESTATE:
	dec	a		; 1: after ESC
	jr	z,SESC
	dec	a		; 2: in a CSI
	jp	z,SCSI
	dec	a		; 3: ESC ( / ESC ): the set
	jr	z,SSCS
	dec	a		; 4: ESC # x: x ignored
	jr	z,ECAN	; ESC # x: x ignored
	dec	a		; 5: VT52 ESC Y's row
	jr	z,ESTATE_YROW
	xor	a	; VT52 ESC Y row col: the column
	ld	(PST),a		; (back to text)
	ld	a,c		; column - 32
	sub	VT_BIAS
	ld	e,a		; (E = the column)
	ld	a,(YROW)	; the row kept
	ld	d,a		; (D = the row)
	jp	SETCUR		; (off-screen values stop at the edge)
ESTATE_YROW:				; (src: SY1)
	ld	a,c		; row - 32, kept
	sub	VT_BIAS
	ld	(YROW),a
	ld	a,PS_YCOL	; the column next
	ld	(PST),a		; (PST = 6)
	ret		; (the column next)
SSCS:
	xor	a	; ESC ( x / ESC ) x: '0' graphics
	ld	(PST),a		; (back to text)
	ld	hl,G0		; the set ESC ( or ESC ) named (PG)
	ld	a,(PG)		; (0 for ESC (, 1 for ESC ))
	call	ADDHLA		; HL -> G0 or G1
	ld	a,c		; '0': DEC special graphics (1) ...
	sub	'0'		; (Z for '0')
	jr	z,SSCS_SET		; '0': A = 0 -> 1
	ld	a,0FFh		; ... any other ('B', 'A', ...): ASCII (0)
SSCS_SET:				; (src: QSS1)
	inc	a		; 1 / 0
	ld	(hl),a		; G0 / G1 set
	ret		; (applies to later text)

; ---------------------------------------------------------------------
; SESC - the byte after ESC (A = 0)
; VT100: [ CSI, 7 8 save / restore the cursor, D index, E next line,
; M reverse index, c reset, Z identify, # ( ) a further byte.  Others
; (= > H ...) are ignored.  A VT52 host's go to V52ESC.
; ---------------------------------------------------------------------
SESC:
	ld	(PST),a	; (A = 0)
	ld	a,(FLAGS)	; VT52 host?
	rrca		; (FL_VT52 to CF)
	jr	c,V52ESC		; yes: VT52 codes
	ld	a,c		; (the byte)
	cp	'['		; ESC [: CSI
	jr	z,ECSI
	cp	'7'		; ESC 7: save the cursor (DECSC)
	jp	z,SAVEC		; (DECSC)
	cp	'8'		; ESC 8: restore it (DECRC)
	jp	z,RESTC		; (DECRC)
	cp	'D'		; ESC D: index
	jp	z,INDEX
	cp	'E'		; ESC E: next line
	jr	z,ENEL
	cp	'M'		; ESC M: reverse index
	jp	z,RINDEX
	cp	'c'		; ESC c: reset (RIS)
	jp	z,RESET
	cp	'Z'		; ESC Z: identify (DECID)
	jp	z,DAREP		; (DECID)
	cp	'#'		; ESC #: one more byte, ignored
	ld	b,PS_HASH	; (LD keeps the flags)
	jr	z,ESTS		; (ESC #)
	cp	'('		; ESC (: G0's set next
	ld	b,0		; (B = 0: G0)
	jr	z,EG		; (ESC ()
	cp	')'		; ESC ): G1's
	ret	nz		; anything else: ignored
	inc	b		; (B = 1: G1)
EG:
	ld	a,b		; PG = which set
	ld	(PG),a		; (the set named)
	ld	b,PS_SCS	; the set's letter next
ESTS:
	ld	a,b		; the new state
	ld	(PST),a
	ret		; (the next byte decides)
ENEL:
	xor	a		; column 0, then down
	ld	(CCOL),a		; (CCOL = 0)
	jp	INDEX		; then IND
ECSI:
	ld	a,PS_CSI	; in a CSI: no parameters, not private
	ld	(PST),a		; (PST = 2)
	xor	a		; (A = 0)
	ld	(NPAR),a		; (no ';' yet)
	ld	(PRIV),a		; (not private)
	ld	hl,PARS		; all four parameters 0 (omitted)
	ld	(hl),a		; PARS[0] = 0
	inc	hl
	ld	(hl),a		; PARS[1] = 0
	inc	hl
	ld	(hl),a		; PARS[2] = 0
	inc	hl
	ld	(hl),a		; PARS[3] = 0
	ret		; (digits follow)

; ---------------------------------------------------------------------
; V52ESC - a VT52 host's ESC x: A B C D cursor, H home, I up (scrolling),
; J K erase to the end, Y r c, Z identify.  Others ignored.
; The cursor moves borrow the VT100 handlers with PARS[0] = 1.
; ---------------------------------------------------------------------
V52ESC:
	ld	a,1		; a move of one
	ld	(PARS),a		; (PARS[0] = 1)
	ld	a,c		; (the byte)
	cp	'A'		; up
	jp	z,CUU		; (CUU, region-bounded)
	cp	'B'		; down
	jp	z,CUD
	cp	'C'		; right
	jp	z,CUF
	cp	'D'		; left
	jp	z,CUB
	cp	'I'		; reverse line feed
	jp	z,RINDEX
	cp	'H'		; home
	ld	de,0		; (row 0, column 0; LD keeps the flags)
	jp	z,SETCUR
	cp	'J'		; erase to the end of the screen
	ld	a,0		; (A = 0: to the end; LD keeps the flags)
	jp	z,EDN
	ld	a,c		; (the byte again)
	cp	'K'		; erase to the end of the line
	ld	a,0		; (A = 0; LD keeps the flags)
	jp	z,ELN
	ld	a,c		; (the byte again)
	cp	'Z'		; identify: ESC / Z
	jp	z,DAREP		; (ESC / Z)
	cp	'Y'		; cursor address: row and column follow
	ret	nz		; (others: ignored)
	ld	a,PS_YROW		; (PST = 5)
	ld	(PST),a		; (the row next)
	ret		; (then the column)

; ---------------------------------------------------------------------
; SCSI - a byte in a CSI: parameters, then the final byte
; ---------------------------------------------------------------------
; 20h-2Fh intermediates: ignored.  0-9: a digit of the current
; parameter, saturating at 255.  ';': the next parameter (4 kept; more
; are ignored).  ':': ignored.  < = > ?: private (PRIV), wherever they
; come.  40h-7Eh: the final byte, looked up in CTAB (or PTAB if
; private); not found: ignored.
; ---------------------------------------------------------------------
SCSI:
	ld	a,c		; (the byte)
	cp	'<'		; < = > ? or a final byte
	jr	nc,CSI_PRIV		; 3Ch-7Eh
	cp	'0'		; (below '0': an intermediate)
	ret	c	; intermediate bytes: ignored
	cp	';'		; the next parameter
	jr	z,CSEMI
	cp	':'		; ':' ignored
	ret	nc
	ld	a,(NPAR)	; a digit
	cp	NPARMAX		; past the fourth parameter: ignored
	ret	nc		; (NPAR = 4)
	ld	hl,PARS		; HL -> the parameter
	call	ADDHLA		; HL -> PARS[NPAR]
	ld	a,(hl)		; 26 or more: x 10 would pass 255
	cp	26		; (p >= 26: p x 10 > 255)
	jr	nc,CSI_SAT		; saturate
	ld	b,a		; x 10: (4p + p) x 2
	add	a,a
	add	a,a
	add	a,b
	add	a,a
	ld	b,a		; (B = 10p)
	ld	a,c		; + the digit
	sub	'0'		; (the digit's value)
	add	a,b		; 10p + digit
	jr	nc,CSI_STORE		; (250-255 + digit may carry)
CSI_SAT:				; (src: CS1)
	ld	a,255		; saturated
CSI_STORE:				; (src: CS0)
	ld	(hl),a
	ret		; (more digits may follow)
CSEMI:
	ld	hl,NPAR		; one parameter more, up to 4
	ld	a,(hl)
	cp	NPARMAX		; (4 already?)
	ret	nc		; yes: no more
	inc	(hl)		; (NPAR + 1)
	ret		; (the next parameter starts at 0)
CSI_PRIV:				; (src: CS2)
	cp	40h		; 40h-7Eh: the final byte
	jr	nc,CFIN		; (40h-7Eh)
	ld	a,1	; < = > ?: private
	ld	(PRIV),a		; (PRIV = 1)
	ret		; (parameters go on)
CFIN:
	xor	a		; the sequence is over
	ld	(PST),a		; (PST = 0)
	ld	hl,CTAB		; ANSI finals ...
	ld	a,(PRIV)		; (private?)
	or	a		; (Z: no)
	jr	z,CFIN_SCAN		; ANSI: CTAB
	ld	hl,PTAB		; ... or private ones
CFIN_SCAN:				; (src: QCF1)
	ld	a,(hl)		; the end of the table: not known, ignored
	or	a
	ret	z		; not found: ignored
	inc	hl		; (past the character)
	cp	c		; this final?
	jr	z,CFIN_JUMP		; found
	inc	hl		; no: past its handler
	inc	hl		; (past the DW ...
	jr	CFIN_SCAN		; ... to the next entry)
CFIN_JUMP:				; (src: CF2)
	ld	a,(hl)		; the handler
	inc	hl
	ld	h,(hl)
	ld	l,a		; HL = the handler
	jp	(hl)		; its RET is EMUL's return

; CTAB - the final byte of an ANSI CSI -> handler (char, DW), 0 ends
CTAB:
	defb	'A'		; CUU   cursor up
	defw	CUU
	defb	'B'		; CUD   cursor down
	defw	CUD
	defb	'e'		; VPR   line position relative: as CUD
	defw	CUD
	defb	'C'		; CUF   cursor forward
	defw	CUF
	defb	'a'		; HPR   character position relative: as CUF
	defw	CUF
	defb	'D'		; CUB   cursor back
	defw	CUB
	defb	'H'		; CUP   cursor position
	defw	CUP
	defb	'f'		; HVP   the same
	defw	CUP
	defb	'G'		; CHA   cursor to a column
	defw	CHA
	defb	60h		; HPA   (`) the same
	defw	CHA
	defb	'd'		; VPA   cursor to a row
	defw	VPA
	defb	'J'		; ED    erase in display
	defw	CED
	defb	'K'		; EL    erase in line
	defw	CEL
	defb	'm'		; SGR   attributes: only inverse
	defw	SGR
	defb	'r'		; DECSTBM  the scrolling region
	defw	STBM
	defb	'n'		; DSR   status / cursor position report
	defw	DSR
	defb	'c'		; DA    device attributes
	defw	CDA
	defb	'h'		; SM    set mode (4: insert)
	defw	SM
	defb	'l'		; RM    reset mode
	defw	RM
	defb	'L'		; IL    insert lines
	defw	IL
	defb	'M'		; DL    delete lines
	defw	DL
	defb	'@'		; ICH   insert characters
	defw	ICH
	defb	'P'		; DCH   delete characters
	defw	DCH
	defb	'X'		; ECH   erase characters
	defw	ECH
	defb	's'		; save the cursor (SCO; as ESC 7)
	defw	SAVEC
	defb	'u'		; restore it (as ESC 8)
	defw	RESTC
	defb	0		; end
; PTAB - the final byte of a private CSI (ESC [ ? ...)
PTAB:
	defb	'h'		; DECSET  ?1 cursor keys, ?7 autowrap
	defw	PSM
	defb	'l'		; DECRST
	defw	PRM
	defb	0		; end

; ---------------------------------------------------------------------
; PAR1 / PAR2 - A = the first / second parameter, 1 if 0 or omitted
; ---------------------------------------------------------------------
PAR2:
	ld	a,(PARS+1)		; (the second)
	jr	PAR0		; (the default test)
PAR1:
	ld	a,(PARS)		; (the first)
PAR0:
	or	a		; 0: the default, 1
	ret	nz		; (given: as it is)
	inc	a		; (omitted: 1)
	ret		; (A = 1-255)

; ---------------------------------------------------------------------
; The cursor moves (VT100: CUU and CUD stop at the region's edge when
; the cursor is inside it, else at the screen's).  All clear WRAPF.
; ---------------------------------------------------------------------
CUU:
	call	PAR1		; B = n
	ld	b,a
	ld	a,(TOP)	; the region's top, if the cursor is in it
	ld	c,a
	ld	a,(CROW)		; (the cursor's row)
	cp	c		; (inside the region?)
	jr	nc,CUU_LIMIT		; yes: TOP is the limit
	ld	c,0		; above it: row 0
CUU_LIMIT:				; (src: CU1)
	sub	b		; CROW - n, not past the limit C
	jr	c,CUU_STOP		; (below row 0)
	cp	c		; (past the limit?)
	jr	nc,CUU_SET		; no: as computed
CUU_STOP:				; (src: CU2)
	ld	a,c		; (the limit)
CUU_SET:				; (src: CU3)
	ld	(CROW),a		; (the new row)
	jp	CLRW		; (WRAPF = 0)
CUD:
	call	PAR1		; B = n
	ld	b,a
	ld	a,(BOT)		; C = the region's bottom, if the cursor is
	ld	c,a		;   in it (or above it)
	ld	a,(CROW)		; (the cursor's row)
	cp	c		; (inside or above the region?)
	jr	c,CUD_LIMIT		; yes: BOT is the limit
	jr	z,CUD_LIMIT		; (on BOT too)
	ld	a,(ROWS)	; below it: the last row
	dec	a		; (ROWS - 1)
	ld	c,a		; (C = the last row)
	ld	a,(CROW)		; (the row again)
CUD_LIMIT:				; (src: CD1)
	add	a,b		; CROW + n, not past C
	jr	c,CUD_STOP		; (past 255)
	cp	c		; (past the limit?)
	jr	c,CUD_SET		; no: as computed
CUD_STOP:				; (src: CD2)
	ld	a,c		; (the limit)
CUD_SET:				; (src: CD3)
	ld	(CROW),a		; (the new row)
	jp	CLRW		; (WRAPF = 0)
CUF:
	call	PAR1		; B = n
	ld	b,a
	ld	a,(COLS)	; C = the last column
	dec	a		; (COLS - 1)
	ld	c,a
	ld	a,(CCOL)	; CCOL + n, not past it
	add	a,b		; (CCOL + n)
	jr	c,CUF_STOP		; (past 255)
	cp	c		; (past the last column?)
	jr	c,CUF_SET		; no: as computed
CUF_STOP:				; (src: CF3)
	ld	a,c		; (the last column)
CUF_SET:				; (src: CF4)
	ld	(CCOL),a		; (the new column)
	jp	CLRW		; (WRAPF = 0)
CUB:
	call	PAR1		; B = n
	ld	b,a
	ld	a,(CCOL)	; CCOL - n, not past column 0
	sub	b		; (CCOL - n)
	jr	nc,CUB_SET		; not past 0
	xor	a		; (column 0)
CUB_SET:				; (src: QCB1)
	ld	(CCOL),a		; (the new column)
	jp	CLRW		; (WRAPF = 0)
CUP:
	call	PAR1		; row (1-based) ...
	dec	a		; (0-based)
	ld	d,a		; (D = row)
	call	PAR2		; ... and column
	dec	a		; (0-based)
	ld	e,a		; (E = column)
	jp	SETCUR		; (clamped to the screen)
CHA:
	call	PAR1		; the column; the row kept
	dec	a		; (0-based)
	ld	e,a
	ld	a,(CROW)		; (the row kept)
	ld	d,a
	jp	SETCUR		; (clamped)
VPA:
	call	PAR1		; the row; the column kept
	dec	a		; (0-based)
	ld	d,a
	ld	a,(CCOL)		; (the column kept)
	ld	e,a
	jp	SETCUR		; (clamped)
CED:
	ld	a,(PARS)	; ED: the parameter as it is (0 default)
	jp	EDN		; (0 / 1 / 2)
CEL:
	ld	a,(PARS)	; EL: likewise
	jp	ELN		; (0 / 1 / 2)

; ---------------------------------------------------------------------
; SGR - attributes: 7 inverse, 0 and 27 normal; the rest (bold,
; underline, colours) ignored.  Each parameter on its own, so a colour
; sequence carrying a 7 or a 0 (ESC [ 38;5;7 m) changes the inverse.
; ---------------------------------------------------------------------
SGR:
	ld	hl,PARS		; B = parameters given
	call	NPARS		; (B = 1-4)
SGR_NEXT:				; (src: QSG1)
	ld	a,(hl)		; (the parameter)
	inc	hl
	or	a		; 0: normal
	jr	z,SGR_SET		; (0: normal)
	cp	27		; 27: inverse off
	jr	nz,SGR_INV		; (not 27)
	xor	a		; (27: normal)
	jr	SGR_SET
SGR_INV:				; (src: SG4)
	cp	7		; 7: inverse on
	jr	nz,SGR_SKIP		; (others ignored)
	ld	a,80h		; (inverse)
SGR_SET:				; (src: QSG2)
	ld	(ATTR),a		; (the attribute for later text)
SGR_SKIP:				; (src: SG3)
	djnz	SGR_NEXT		; every parameter
	ret		; (the last one wins)
; NPARS - B = parameters given (1-4: NPAR + 1, at most 4).  Uses A.
NPARS:
	ld	a,(NPAR)		; (NPAR = 0-4)
	cp	NPARMAX
	jr	c,NPARS_SET		; no: NPAR + 1
	ld	a,NPARMAX-1		; (4 parameters at most)
NPARS_SET:				; (src: NPS1)
	inc	a
	ld	b,a		; (B = 1-4)
	ret		; (A = B)

; ---------------------------------------------------------------------
; STBM - ESC [ top ; bottom r: the scrolling region (DECSTBM)
; Bottom omitted, 0 or past the screen: the last row.  A region of
; fewer than two rows is ignored.  Set: the cursor home (0, 0).
; ---------------------------------------------------------------------
STBM:
	call	PAR1		; D = top, 0-based
	dec	a		; (0-based)
	ld	d,a		; (D = top)
	ld	a,(PARS+1)	; the bottom, 1-based
	ld	hl,ROWS		; (the screen's rows)
	or	a		; omitted: the last row
	jr	z,STBM_FULL		; (0: the last row)
	cp	(hl)		; within the screen: as given
	jr	c,STBM_BOT		; (below ROWS: as given)
STBM_FULL:				; (src: ST2)
	ld	a,(hl)
STBM_BOT:				; (src: ST3)
	dec	a		; 0-based
	cp	d		; bottom at or above top: ignored
	ret	c		; (bottom above top)
	ret	z		; (one row)
	ld	(BOT),a		; (the region's bottom)
	ld	a,d
	ld	(TOP),a		; (the region's top)
	ld	de,0		; home
	jp	SETCUR		; (home, as on a VT100 without DECOM)

; ---------------------------------------------------------------------
; DSR - ESC [ 5 n: "OK" (ESC [ 0 n); ESC [ 6 n: the cursor position,
; ESC [ row ; col R (1-based, absolute).  Others ignored.
; CDA - ESC [ c / ESC [ 0 c: device attributes.  DAREP (also ESC Z):
; ESC [ ? 1 ; 0 c, "a VT100 without options"; to a VT52 host ESC / Z.
; ---------------------------------------------------------------------
DSR:
	ld	a,(PARS)		; (the parameter)
	cp	5		; status
	jr	z,DSR_STATUS		; (5: status)
	cp	6		; cursor position
	ret	nz		; (others ignored)
	ld	a,ESC		; ESC [
	call	SERPUT
	ld	a,'['
	call	SERPUT
	ld	a,(CROW)	; row
	inc	a		; (1-based)
	call	SENDN		; (decimal)
	ld	a,';'
	call	SERPUT
	ld	a,(CCOL)	; column
	inc	a		; (1-based)
	call	SENDN		; (decimal)
	ld	a,'R'
	jp	SERPUT		; (the report's end)
DSR_STATUS:				; (src: DSR5)
	ld	hl,DSROK	; "no malfunction"
	jp	SENDS		; (ESC [ 0 n)
CDA:
	ld	a,(PARS)	; only parameter 0
	or	a		; (0 only)
	ret	nz		; (ESC [ > c etc.: ignored)
DAREP:
	ld	hl,DA100	; a VT100 ...
	ld	a,(FLAGS)		; (VT52 host?)
	rrca		; (FL_VT52 to CF)
	jr	nc,DAREP_SEND		; (no: the VT100 answer)
	ld	hl,DA52		; ... or, to a VT52 host, a VT52
DAREP_SEND:				; (src: DA1)
	jp	SENDS		; (as a tail call)
DA100:
	defb	1Bh,'[?1;0c',0	; a VT100 without options
DA52:
	defb	1Bh,'/Z',0	; VT52 identify answer
DSROK:
	defb	1Bh,'[0n',0	; DSR 5: terminal OK

; ---------------------------------------------------------------------
; SM / RM - ESC [ 4 h / l: insert / replace mode.
; PSM / PRM - ESC [ ? n h / l: ?1 cursor keys (KEYOUT's ESC O), ?7
; autowrap.  Every parameter given is looked at; others are ignored.
; ---------------------------------------------------------------------
SM:
	ld	c,1		; set
	jr	SM_SCAN		; (C = 1)
RM:
	ld	c,0		; reset
SM_SCAN:				; (src: SM0)
	ld	hl,PARS		; (the parameters ...
	call	NPARS		; ... B of them)
SM_NEXT:				; (src: SM1)
	ld	a,(hl)		; (the parameter)
	inc	hl
	cp	4		; IRM
	jr	nz,SM_SKIP		; (not 4: ignored)
	ld	a,c		; (1 / 0)
	ld	(IRM),a
SM_SKIP:				; (src: SM2)
	djnz	SM_NEXT		; every parameter
	ret		; (redraw not needed)
PSM:
	ld	c,1		; set
	jr	PSM_SCAN		; (C = 1)
PRM:
	ld	c,0		; reset
PSM_SCAN:				; (src: PSM0)
	ld	hl,PARS		; (the parameters ...
	call	NPARS		; ... B of them)
PSM_NEXT:				; (src: PS1)
	ld	a,(hl)		; (the parameter)
	inc	hl
	cp	1		; ?1: DECCKM
	jr	nz,PSM_AWM		; (not ?1)
	ld	a,c		; (A = 0 / 1 now: the ?7 test fails)
	ld	(CKM),a		; (CKM: KEYOUT's ESC O)
PSM_AWM:				; (src: PS2)
	cp	7		; ?7: DECAWM
	jr	nz,PSM_SKIP		; (not ?7)
	ld	a,c		; (1 / 0)
	ld	(AWM),a		; (AWM: PUTCH_LASTCOL)
	xor	a		; and no wrap pending
	ld	(WRAPF),a		; (WRAPF = 0)
PSM_SKIP:				; (src: PS3)
	djnz	PSM_NEXT		; every parameter
	ret		; (nothing to draw)

; ---------------------------------------------------------------------
; IL / DL - insert / delete n lines at the cursor, in the region
; ---------------------------------------------------------------------
; Outside the region: ignored.  The part from the cursor's row to the
; region's bottom (RT..RB) is shifted n times by one row with SHDN /
; SHUP (called through ILOP and Z86.SYS's JPHL, its only use here),
; then drawn again: the terminal cannot scroll part of its screen.
; The cursor goes to column 0, as on a VT100.
; ---------------------------------------------------------------------
IL:
	ld	hl,SHDN		; insert: rows down
	jr	IL_SET		; (insert)
DL:
	ld	hl,SHUP		; delete: rows up
IL_SET:				; (src: IL0)
	ld	(ILOP),hl		; (the operation, for JPHL)
	ld	a,(TOP)		; the cursor above the region: ignored
	ld	b,a		; (B = TOP)
	ld	a,(CROW)		; (the cursor's row)
	cp	b		; (above TOP?)
	ret	c		; yes: ignored
	ld	(RT),a		; RT = the cursor's row
	ld	b,a		; (B = CROW)
	ld	a,(BOT)		; RB = the region's bottom
	ld	(RB),a		; (RB = BOT)
	cp	b		; the cursor below the region: ignored
	ret	c		; (below BOT: ignored)
	sub	b		; (BOT - CROW)
	inc	a
	ld	c,a	; lines from the cursor to the bottom
	call	PAR1		; n, at most that
	cp	c		; (n against that)
	jr	c,IL_COUNT		; fewer: n
	ld	a,c		; (all of them)
IL_COUNT:				; (src: IL1)
	ld	b,a		; (B = the count)
IL_SHIFT:				; (src: IL2)
	push	bc		; (the count kept)
	ld	hl,(ILOP)	; SHDN or SHUP
	call	JPHL		; SHDN or SHUP, rows RT..RB
	pop	bc		; (the count back)
	djnz	IL_SHIFT		; n times
	xor	a		; column 0, no wrap pending
	ld	(CCOL),a		; (CCOL = 0)
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(CROW)	; rows CROW..BOT drawn again
	ld	b,a		; (B = CROW)
	ld	a,(BOT)		; (to the region's bottom)
	ld	c,a		; (C = BOT)
	jp	REDR		; rows CROW..BOT drawn again

; ---------------------------------------------------------------------
; ICH / DCH / ECH - ESC [ n @ / P / X: insert / delete / erase n
; characters at the cursor
; CH_DISPATCH pushes CH_REDRAW, then the handler, and RETs into the
; handler with A = PARS[0] (0 taken as 1 by CHCNT): the handler's own
; RET then lands in CH_REDRAW, which draws the row from the cursor on.
; ---------------------------------------------------------------------
ICH:
	ld	hl,ICHS		; (insert)
	jr	CH_DISPATCH		; (common tail)
DCH:
	ld	hl,DCHS		; (delete)
	jr	CH_DISPATCH		; (common tail)
ECH:
	ld	hl,ECHS		; (erase)
CH_DISPATCH:				; (src: CH0)
	ld	de,CH_REDRAW	; the return address for the handler ...
	push	de		; (CH_REDRAW under it)
	push	hl		; ... and the handler, for the RET below
	ld	a,(PARS)	; n
	ret	; to ICHS / DCHS / ECHS, then CH_REDRAW
CH_REDRAW:				; (src: CH1)
	xor	a		; no wrap pending
	ld	(WRAPF),a		; (WRAPF = 0)
	ld	a,(CROW)	; the row from the cursor drawn again
	ld	d,a		; (D = CROW)
	ld	a,(CCOL)		; (from the cursor)
	ld	e,a		; (E = CCOL)
	jp	DRAWR		; the rest of the row

; ---------------------------------------------------------------------
; SAVEC / RESTC - ESC 7 / ESC 8, ESC [ s / ESC [ u: the cursor and the
; attribute (not the character sets, unlike a VT100's DECSC).
; ---------------------------------------------------------------------
SAVEC:
	ld	a,(CROW)		; (the row ...
	ld	(SAVR),a		; ... saved)
	ld	a,(CCOL)		; (the column ...
	ld	(SAVC),a		; ... saved)
	ld	a,(ATTR)		; (the attribute ...
	ld	(SAVA),a		; ... saved)
	ret		; (no G0 / G1 / GL)
RESTC:
	ld	a,(SAVA)		; (the attribute ...
	ld	(ATTR),a		; ... back)
	ld	a,(SAVR)	; (SETCUR clears WRAPF)
	ld	d,a		; (D = the row)
	ld	a,(SAVC)		; (the column)
	ld	e,a
	jp	SETCUR		; (clamped; WRAPF = 0)

; GRTAB - DEC special graphics 5Fh-7Eh, as near as ASCII gets:
;   5F blank ' '    60 diamond '*'    61 checkerboard '#'
;   62-65 HT FF CR LF symbols 'H' 'F' 'C' 'L'   66 degree 'o'
;   67 plus-minus '#'   68 NL 'N'   69 VT 'V'
;   6A-6E corners and crossing '+' (lower right, upper right, upper
;   left, lower left, cross)   6F-73 scan lines 1 3 5 7 9: '~' '-' '-'
;   '_' '_'   74-77 tees '+'   78 vertical bar '|'
;   79 '<=' '<'   7A '>=' '>'   7B pi 'p'   7C not-equal '#'
;   7D pound 'f'   7E centred dot '.'
GRTAB:
	defb	' *#HFCLo#NV+++++~--__++++|<>p#f.'

; =====================================================================
;                    VARIABLES
; =====================================================================
; PB - the parameter block, as TERM.COM's PBLK (copied by F_INIT)
PB:
CTL:
	defb	0		; the channel's control port (81h A, 41h B)
COLS:
	defb	0		; 64 or 80
ROWS:
	defb	0		; 24
FLAGS:
	defb	0		; FL_VT52 FL_XON FL_RTS FL_ECHO FL_CRLF
MENUK:
	defb	0		; the menu key (Ctrl-A)
SCR:
	defw	0		; the shadow screen (8086 memory)
RING:
	defw	0		; the 2 KB ring
LOGB:
	defw	0		; the log buffer
LOGSZ:
	defw	0		;   and its size
; ---- derived by F_INIT ----
LOGLIM:
	defw	0		; LOGSZ - 256: SESS stops at it
SCREND:
	defw	0		; SCR + ROWS x COLS
; ---- the host's screen ----
CROW:
	defb	0	; the host's cursor
CCOL:
	defb	0
WRAPF:
	defb	0	; 1: the last column was written
ATTR:
	defb	0	; 80h: inverse
TOP:
	defb	0	; the scrolling region
BOT:
	defb	0
AWM:
	defb	0	; modes: autowrap, insert, cursor keys
IRM:
	defb	0
CKM:
	defb	0
GL:
	defb	0	; character sets: G0 or G1 in use;
G0:
	defb	0	; 1 = DEC special graphics
G1:
	defb	0
PG:
	defb	0		; the set ESC ( / ESC ) is naming (0 / 1)
SAVR:
	defb	0	; ESC 7
SAVC:
	defb	0
SAVA:
	defb	0
; ---- the parser ----
PST:
	defb	0	; parser: 0 text, 1 ESC, 2 CSI, 3 ESC ( ),
NPAR:
	defb	0	; 4 ESC #, 5 6 VT52 ESC Y; NPAR: params - 1
PRIV:
	defb	0		; 1: a private CSI (< = > ?)
PARS:
	defb	0,0,0,0		; the CSI's parameters, 0 = omitted
YROW:
	defb	0		; VT52 ESC Y: the row, until the column comes
; ---- the terminal ----
TROW:
	defb	0	; the terminal's cursor and attribute
TCOL:
	defb	0
TATTR:
	defb	0		; (FFh: not known)
TOCH:
	defb	0		; TOUT's character, across retries
KCH:
	defb	0		; KEYOUT's key
KLAST:
	defb	0	; the key sent before
RT:
	defb	0		; SHUP / SHDN's rows: top ...
RB:
	defb	0		; ... and bottom
ILOP:
	defw	0		; IL / DL: SHDN or SHUP
; ---- the channel ----
CMDV:
	defb	0	; the WD2123 command in force
TXQ:
	defb	0	; XON / XOFF to send, 0 none
STOPF:
	defb	0	; 1: the host was asked to stop
HOLDF:
	defb	0	; 1: and must stay stopped
LOGON:
	defb	0		; log on (TERM.COM's LOG function)
LOGN:
	defw	0		; bytes in the log buffer
RHEAD:
	defw	0		; the ring's head (next free) ...
RTAIL:
	defw	0		; ... and tail (next to read), 0-2047
LOST:
	defw	0		; bytes lost: overruns, ring full (SESS's DX)
DROPS:
	defb	0		; bytes SERPUT gave up on (never read)
RCNT:
	defw	0		; RECV: bytes received
TMO:
	defw	0	; RECV: the wait for the next byte
SUM:
	defb	0		; CRC: the 8-bit sum
TERMEND:				; FEB8h: 72 bytes below the Z80 stack's FF00h
