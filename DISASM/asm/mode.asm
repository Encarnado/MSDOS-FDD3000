;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  8/10
;  MODE.COM - set and show the WD2123 serial channels (8086, 1 119 bytes,
;  a .COM at PSP:0100h)
;==============================================================================
;
;  ROLE.  The FDD3000's MODE: one command line sets the speed and frame
;  of one of the two WD2123 channels, or shows them.
;
;       MODE port[:] [baud][,[parity][,[data bits][,stop bits]]]
;       MODE [port[:]]
;
;  port  PRN, LPT1, COM1 = channel A (DOS's PRN, INT 14h DX = 0);
;        AUX, COM2       = channel B (DOS's AUX, INT 14h DX = 1).
;  baud  any of the WD2123's 16 rates, 50 .. 19200 ("134.5" or "134"),
;        or the IBM PC MODE's short forms 11 15 30 60 12 24 48 96 19.
;  parity N / O / E; data bits 5-8; stop bits 1, 1.5 or 2.
;  A field left out KEEPS its current value (the PC's MODE puts in
;  defaults instead), so `MODE COM1:,E` changes the parity alone.  A
;  port alone shows that channel; no argument shows both.
;
;  It is not Microsoft's.  The MODE.COM in Microsoft's MS-DOS v1.25/bin
;  is IBM's PC MODE 1.10 (screen modes, PC printer / async ports), an
;  unrelated program that would not work here.  This one talks to the
;  FDD3000 BIOS only, through two FDD3000-only INT 14h calls.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM loads it at <PSP>:0100h (CS = DS = ES = SS = PSP)
;       ->  THIS PROGRAM: INT 14h AH = F0h / F1h, INT 21h AH = 02h / 09h
;       ->  INT 14h vector -> IO.SYS's stub 0040:INT14 (set by SETROM,
;           volume 4): TRAP TRAP_INT14 (0Fh 14h) / RETF 2
;       ->  Z86.SYS TTAB -> T_I14 -> I14X (z86_bios.asm):
;             F0h -> I14RD: AL = mode byte, AH = baud code, from SAVED
;             F1h -> SSET (reset, mode, command, baud register, copy to
;                    SAVED) -> SSTAT (AH / AL = status, ignored here)
;       ->  INT 20h back to COMMAND.COM
;  The setting lasts until the next boot: COLD sets both channels to mode
;  8Eh, baud code 8 (1200 baud, 8 data bits, no parity, 1.5 stop bits),
;  as the FDD3000's CP/M CBIOS A1.1 does.  It holds for DOS's PRN and AUX
;  and for CP/M programs under CPM.COM (they share the Z80 serial
;  routines).  MODE lines in AUTOEXEC.BAT make another setting stick.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/mode_findings.md)
;   - MODE never touches the chip: every read is INT 14h F0h, which
;     returns the Z80's copy SAVED (the WD2123's mode and baud registers
;     can't be read back), every write F1h.  What MODE shows after a
;     change is that copy re-read, not the chip.
;   - Read-modify-write: SETS fetches the current mode byte and baud
;     code FIRST, each field given replaces only its own bits (stop 7-6,
;     parity 5-4, data 3-2), and bits 1-0 (the x16 clock) are carried
;     through untouched - the Z80 forces them to 10b anyway.
;   - Nothing reaches the BIOS until the whole line has parsed: every
;     error path ends in BAD (usage, INT 20h) before SETX.  test_fdd86.py
;     group 9 checks that nine bad lines leave both channels as they were.
;   - Any successful set, even to the same values, is a full channel
;     reset in SSET (00h 00h 00h 40h, mode, command, baud).  MODE does not
;     wait for the transmitter to drain first (provisional: what a reset
;     does to a character still shifting out was never tested).
;   - A comma right after the port stands for an empty baud field:
;     `MODE COM1:,O` and `MODE COM1 ,O` change the parity; `MODE PRN,,E`
;     is refused (the 'E' lands in the data-bits field).
;   - The STOPS table has a "?" for stop-bit code 00 (not a valid async
;     mode); no path in MODE or the BIOS ever stores it (SSET's callers
;     give 40h / 80h / C0h only).
;   - SHOW names channel A "PRN:" and channel B "AUX:" whatever name was
;     typed (COM1, LPT1 ...).
;
;  HARDWARE.  NOT RUN ON A REAL FDD3000.  The merged 2026-11-08 build that
;  contains MODE.COM has never been booted on the machine; the one real
;  run (notes/hardware_run.md, 2026-11-07) was an earlier build without
;  MODE or the INT 14h F0h / F1h calls.  Whether João Encarnado ran MODE
;  on hardware is not recorded (the poc README's serial section ends
;  "nothing has been tried on the hardware").  The baud rates are the
;  WD2123 datasheet's for its standard 1.8432 MHz crystal (poc README);
;  provisional until measured.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/MODE.COM with
;  `nasm -O0 -f bin` (tools/roundtrip.sh mode).  Every byte agrees with
;  the MASM listing ../symbols/x86/MODE.LST (0100h-055Eh).  The Z80 side
;  is read from z86_bios.asm (T_I14, I14X) and z86_interp.asm (SSET,
;  SSTAT, I14RD, SAVED).  Under the emulator (fdd86.py, with its WD2123
;  model): test_fdd86.py group 9 runs MODE with no argument, every port
;  name, all four fields, fields left out, the PC's baud names, a port
;  alone, and nine bad lines, checking after each the mode byte and baud
;  code the model chip received and MODE's printed line; then COPY to PRN
;  after MODE.
;
;  FILE:    MODE.COM, 1 119 bytes
;  MD5:     d3bed820421d5a7fdc6aa9e1c9daf3c1
;  SHA256:  c60807affd8e3ad7bbe1446247ac77858123622939b53665ee44d27b861dff6a
;  SOURCE:  project/MSDOS/poc/MODE.ASM (MASM 1.10)
;
;  CREDITS.  Original code: João Encarnado, for the FDD3000-MSDOS project
;  (2026).  The INT 14h F0h / F1h calls it uses (I14X, I14RD, SAVED) are
;  his too.  Mode byte and baud codes as CBIOS A1.1 and TMX CONFIGUR
;  (TMX Portugal) use them.  Disassembly and annotation in the style of
;  "The Complete TMX Portugal ROM Disassemblies", LoadZX Museum, 2026.
;==============================================================================
;
; ASSEMBLER NOTES.  NASM, `-O0 -f bin`: -O0 stops NASM re-sizing
; anything, so the explicit `short`, `byte` and `word` keywords fix the
; encoding.  The `_d` macros spell a register-to-register instruction in
; MASM's encoding (direction bit set, e.g. mov_d di,si = 8B FEh where
; NASM would emit 89 F7h): same operation, MASM's bytes.  The TRAP macro
; (0Fh n, the interpreter's BIOS trap) is kept for the series but unused:
; MODE reaches the BIOS by INT 14h, and IO.SYS's stub does the trap.

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
;                    THE Z80 SIDE (for the comments)
; =====================================================================
TRAP_INT14	equ	14h	; IO.SYS's INT14 stub: TRAP TRAP_INT14 / RETF 2
				;   -> Z86.SYS T_I14 (TTAB entry 14h)

; ---- INT 14h: DX = channel, AH = function ------------------------------
CHAN_A		equ	0	; DX = 0: channel A, DOS's PRN (T_I14: C = 81h)
CHAN_B		equ	1	; DX = 1: channel B, DOS's AUX (T_I14: C = 41h)
I14_GETMODE	equ	0F0h	; FDD3000 call (I14X -> I14RD): AL = mode
				;   byte, AH = baud code, as SSET last set them
				;   (the copy in SAVED; the chip can't be read)
I14_SETMODE	equ	0F1h	; FDD3000 call (I14X -> SSET, SSTAT): AL =
				;   mode byte (bits 1-0 forced to 10b), CL =
				;   baud code 0-15 (16+ ignored); AH / AL return
				;   the line / modem status (MODE ignores them)

; ---- the 8251A asynchronous mode byte (WD2123 = two 8251A channels) ----
;   bits 7-6  stop bits   01 = 1, 10 = 1.5, 11 = 2   (00: sync mode)
;   bit  5    EP          1 = even, 0 = odd  (only with PEN)
;   bit  4    PEN         parity on
;   bits 3-2  data bits   00 = 5, 01 = 6, 10 = 7, 11 = 8
;   bits 1-0  clock       10 = x16 (01 x1, 11 x64); always 10 here
;   COLD's 8Eh = 10 00 11 10: 1.5 stop, no parity, 8 bits, x16.
MODE_DBITS	equ	0Ch	; data-bit field (bits 3-2: count - 5)
MODE_PEN	equ	10h	; parity enable
MODE_EP		equ	20h	; even parity (with PEN)
MODE_STOPS	equ	0C0h	; stop-bit field
MODE_STOP1	equ	40h	; 1 stop bit
MODE_STOP15	equ	80h	; 1.5 stop bits
MODE_STOP2	equ	0C0h	; 2 stop bits
PAR_NONE	equ	0	; PEN = 0
PAR_ODD		equ	MODE_PEN	; 10h: PEN, EP = 0
PAR_EVEN	equ	MODE_PEN|MODE_EP	; 30h: PEN + EP
STOP_SHIFT	equ	6	; stop field down to bits 1-0

; ---- the tables' shapes -------------------------------------------------
NAME_LEN	equ	4	; a port name, space-padded
PORT_W		equ	5	; PORTS entry: name + channel byte
NBAUDS		equ	16	; WD2123 baud codes 0-15
BAUD_W		equ	6	; BAUDS entry: rate, space-padded (= TOKEN)
ABAUD_W		equ	7	; ABAUDS entry: name (6) + baud code
STOP_W		equ	3	; STOPS entry

; ---- DOS 1.25 interface (MSDOS.LST) -------------------------------------
DOS_CONOUT	equ	02h	; INT 21h AH=02h display character DL (CONOUT)
DOS_PRTSTR	equ	09h	; INT 21h AH=09h print string to "$" (PRTBUF)
PSP_TAILLEN	equ	80h	; command tail: length byte (CR not counted)
PSP_TAIL	equ	81h	;   and its text, CR-ended
TAB		equ	9
CR		equ	13
LF		equ	10

	org	0100h
bits 16

; =====================================================================
; BEGIN - .COM entry: over the data to START
; =====================================================================
BEGIN:
	jmp START		; near JMP (MASM: forward reference)

; =====================================================================
; VARIABLES
; =====================================================================
CHAN:
	dw 0		; INT 14h DX: CHAN_A / CHAN_B (a word: only the
			;   low byte is ever written, the high stays 0)
MODEB:
	db 0		; the mode byte being built (from F0h, then fields)
BAUDC:
	db 0		; the baud code being built (0-15)
NAMBUF:
	db "    "	; the port name as typed, padded to NAME_LEN
TOKEN:
	db "      "	; the baud field as typed, padded to BAUD_W

; ---------------------------------------------------------------------
; PORTS - the port names: 4 characters (space-padded), then the INT 14h
; channel.  Searched by PORT with REPE CMPSB against NAMBUF.
; ---------------------------------------------------------------------
PORTS:
	db "PRN ",0	; channel A, DOS's printer device
	db "LPT1",0	; channel A
	db "COM1",0	; channel A, INT 14h port 0
	db "AUX ",1	; channel B, DOS's auxiliary device
	db "COM2",1	; channel B, INT 14h port 1
NPORTS equ 5

; ---------------------------------------------------------------------
; BAUDS - the 16 WD2123 rates, entry n = baud code n, 6 characters each,
; in the order TMX CONFIGUR lists them (and z86_interp.asm SSET).
; Rates for the 1.8432 MHz crystal at x16 (datasheet; provisional).
; Used both ways: BAUD matches TOKEN against it, SHOW prints entry n.
; ---------------------------------------------------------------------
BAUDS:
	db "50    "	; 0
	db "75    "	; 1
	db "110   "	; 2
	db "134.5 "	; 3
	db "150   "	; 4
	db "200   "	; 5
	db "300   "	; 6
	db "600   "	; 7
	db "1200  "	; 8  (the boot setting)
	db "1800  "	; 9
	db "2400  "	; 10
	db "3600  "	; 11
	db "4800  "	; 12
	db "7200  "	; 13
	db "9600  "	; 14
	db "19200 "	; 15

; ---------------------------------------------------------------------
; ABAUDS - other names for a rate: 6 characters, then the baud code.
; "134" for 134.5, then the IBM PC MODE's two-digit short forms.
; ---------------------------------------------------------------------
ABAUDS:
	db "134   ",3	; 134.5
	db "11    ",2	; 110
	db "15    ",4	; 150
	db "30    ",6	; 300
	db "60    ",7	; 600
	db "12    ",8	; 1200
	db "24    ",10	; 2400
	db "48    ",12	; 4800
	db "96    ",14	; 9600
	db "19    ",15	; 19200
NABAUDS equ 10

; ---------------------------------------------------------------------
; Messages ("$"-terminated, INT 21h AH=09h).  SHOW builds the line
; "PRN: 1200 baud, no parity, 8 data bits, 1.5 stop bits" from them.
; ---------------------------------------------------------------------
PRNMSG:
	db "PRN: $"	; channel A, whatever name was typed
AUXMSG:
	db "AUX: $"	; channel B
BAUMSG:
	db " baud, $"
NOPMSG:
	db "no$"	; PEN = 0
ODDMSG:
	db "odd$"	; PEN, EP = 0
EVNMSG:
	db "even$"	; PEN + EP
PARMSG:
	db " parity, $"
DATMSG:
	db " data bits, $"
STPMSG:
	db " stop bit$"	; SHOW adds the "s" unless the code is 1
CRLF:
	db CR,LF,"$"

; STOPS - mode bits 7-6 as text, 3 characters each (PUTN stops at a space)
STOPS:
	db "?  1  1.52  "	; 00 "?" (sync - never stored), 01 "1",
				;   10 "1.5", 11 "2"

; USEMSG - shown for every bad command line; nothing has been changed
USEMSG:
	db "Invalid parameter",CR,LF,CR,LF
	db "Usage: MODE port[:] [baud][,[N|O|E][,[5-8][,[1|1.5|2]]]]",CR,LF
	db "  port: PRN, LPT1 or COM1 (channel A), AUX or COM2 (channel B)",CR,LF
	db "  baud: 50 75 110 134.5 150 200 300 600 1200 1800 2400 3600",CR,LF
	db "        4800 7200 9600 19200",CR,LF,"$"

; =====================================================================
; START - upper-case the command tail, then dispatch on what it holds
; ---------------------------------------------------------------------
; Entry:  from BEGIN; DOS 1.25 PSP: [80h] = tail length, 81h.. = tail
;         (CR-ended).  DS = ES = PSP, so STOSB writes back into the tail.
; Exit:   no argument: both channels shown, INT 20h.  Otherwise on to
;         PORT with SI at the first non-blank.
; DOS calls: (through SHOW) AH=02h, AH=09h; INT 20h terminate.
; INT 14h:  (through SHOW) AH=F0h.
; =====================================================================
START:
	cld			; LODSB / STOSB / CMPSB all go up
	mov si,PSP_TAIL		; the command tail, upper-cased in place
	mov cl,[PSP_TAILLEN]	;   CX = its length (tail + CR fit in
	xor_d ch,ch		;   81h-FFh, so the 0 below lands <= 00FFh)
	mov_d di,si		; written back where it was read
UPPER:
	jcxz short UPPER_END	; every character done
	lodsb			; next character
	cmp al,'a'		; lower-case letter?
	jc short UPPER_STORE	; below 'a': as it is
	cmp al,'z'	; past 'z'?
	ja short UPPER_STORE	; above 'z': as it is
	sub al,'a'-'A'		; a-z -> A-Z
UPPER_STORE:			; (src: UP1)
	stosb			; back into the tail
	loop short UPPER	; next
UPPER_END:			; (src: UPX)
	mov byte [di],0x0	; a 0 over the CR: the end mark BLANKS tests
	mov si,PSP_TAIL		; parse from the start
	call BLANKS		; skip leading blanks; ZF=1 if nothing else
	jnz short PORT		; a port name follows
	call SHOW		; no argument: channel A (CHAN = 0) ...
	inc word [CHAN]		; ... then channel B
	call SHOW	; (CHAN = 1 now)
	int byte 20h		; terminate (CS = PSP, as INT 20h needs)

; =====================================================================
; PORT - the port: a name of up to 4 letters / digits, then maybe ':'
; ---------------------------------------------------------------------
; Entry:  SI at the first non-blank of the tail.
; Exit:   CHAN set; a port alone -> SHOW, INT 20h; settings follow ->
;         SETS with SI at the first non-blank after the port; an
;         unknown name -> BAD.
; =====================================================================
PORT:
	mov di,NAMBUF		; the name, padded to 4 with spaces
	mov cx,NAME_LEN	; (4)
	call GETW		; ZF=0: none, or 5+ characters
	jnz short BAD		; (e.g. "PRNTR", "COM19600")
	mov bx,PORTS		; BX walks the 5-byte entries
	mov dl,NPORTS		; DL = entries left
PORT_MATCH:			; (src: PORT1)
	push si			; keep the parse position
	mov si,NAMBUF		; the name typed ...
	mov_d di,bx		; ... against this entry's 4 characters
	mov cx,NAME_LEN	; 4 characters
	repe cmpsb		; ZF=1 when all 4 agree
	pop si			; (POP keeps the flags)
	jz short PORT_FOUND	; this one
	add bx,byte PORT_W	; next entry
	dec dl		; one entry fewer
	jnz short PORT_MATCH	; until all 5 tried
	jmp short BAD		; no such port ("COM3")
PORT_FOUND:			; (src: PORT2)
	mov al,[bx+NAME_LEN]	; the entry's channel byte
	mov [CHAN],al		; INT 14h DX low byte (high stays 0)
	cmp byte [si],':'	; the optional colon
	jnz short PORT_SETTINGS	; (a ',' here = no baud field)
	inc si			; past it
PORT_SETTINGS:			; (src: PORT3)
	call BLANKS		; anything after the port?
	jnz short SETS		; yes: settings (a ',' here = no baud field)
	call SHOW		; a port alone: show it
	int byte 20h		; terminate

; ---------------------------------------------------------------------
; BAD - the usage message, nothing changed, INT 20h.  Reached by JMP
; from anywhere in the parse, from inside COMMA too (its return address
; is simply abandoned: INT 20h does not care about the stack).
; DOS calls: AH=09h print string.
; ---------------------------------------------------------------------
BAD:
	mov dx,USEMSG		; "Invalid parameter" + usage
	mov ah,DOS_PRTSTR	; AH=09h print string to "$"
	int 21h		; (DS = CS = PSP: USEMSG is here)
	int byte 20h		; terminate (DOS 1.25 has no exit code)

; =====================================================================
; SETS - the settings: start from the channel's current ones, then
; replace each field that is given
; ---------------------------------------------------------------------
; Entry:  SI at the first non-blank after the port; CHAN set.
; Exit:   a good line -> SETX (INT 14h F1h, SHOW, INT 20h); else BAD.
; INT 14h: AH=F0h (I14_GETMODE): AL = mode byte, AH = baud code, from
;          the Z80's SAVED copy (I14X -> I14RD).
; Fields are positional and comma-separated; a field may be empty
; (",,") and the line may stop after any field.  Bits not named by a
; field - including bits 1-0, the x16 clock - are carried over.
; =====================================================================
SETS:
	mov ah,I14_GETMODE	; AH=F0h: the settings now
	mov dx,[CHAN]		; DX = channel
	int byte 14h		; -> TRAP TRAP_INT14 -> I14RD
	mov [MODEB],al		; mode byte to edit
	mov [BAUDC],ah		; baud code to edit
	cmp byte [si],','	; baud field empty (port then comma)?
	jz short PAR		; yes: keep the rate
; ---- baud: an exact entry of BAUDS, else of ABAUDS ----
	mov di,TOKEN		; the field, padded to 6
	mov cx,BAUD_W	; (6)
	call GETW		; ZF=0: none, or more than 6 ("1234567")
	jnz short BAD	; not a word: usage
	mov bx,BAUDS		; first the 16 rates, entry n = code n
	xor_d dl,dl		; DL = code
BAUD_CODES:			; (src: BAUD1)
	call SAME6		; TOKEN = this rate?
	jz short BAUD_STORE	; yes: DL is its code
	add bx,byte BAUD_W	; next rate
	inc dl		; and its code
	cmp dl,NBAUDS		; all 16 tried?
	jc short BAUD_CODES	; no: on
	mov bx,ABAUDS		; then "134" and the PC's short names
	mov dh,NABAUDS		; DH = entries left
BAUD_PCNAMES:			; (src: BAUD2)
	call SAME6		; TOKEN = this name?
	jz short BAUD_PCCODE	; yes: its code follows the name
	add bx,byte ABAUD_W	; next name
	dec dh		; one name fewer
	jnz short BAUD_PCNAMES	; until all 10 tried
	jmp short BAD		; no such rate ("9601")
BAUD_PCCODE:			; (src: BAUD4)
	mov dl,[bx+BAUD_W]	; the code after the 6-character name
BAUD_STORE:			; (src: BAUD3)
	mov [BAUDC],dl		; the new baud code
; ---- parity: N, O or E -> mode bits 5-4 ----
PAR:
	call COMMA		; CF=1 end of line; ZF=1 empty field
	jc short SETX		; line ends: set it
	jz short DBITS		; empty: keep the parity
	mov ah,PAR_NONE		; AH = the new PEN / EP bits
	cmp al,'N'		; none
	jz short PAR_STORE	; 'N': PEN = 0
	mov ah,PAR_ODD		; PEN, EP = 0
	cmp al,'O'		; odd
	jz short PAR_STORE	; 'O': PEN only
	mov ah,PAR_EVEN		; PEN + EP
	cmp al,'E'		; even
	jnz short BAD_JUMP	; anything else ("X")
PAR_STORE:			; (src: PAR1)
	inc si			; past the letter (one letter only: "NONE"
				;   fails at the next COMMA)
	and byte [MODEB],0FFh-(MODE_PEN|MODE_EP)	; clear bits 5-4 (CFh)
	or [MODEB],ah		; and put the new ones in
; ---- data bits: 5-8 -> mode bits 3-2 ----
DBITS:
	call COMMA		; next field
	jc short SETX		; line ends: set it
	jz short SBITS		; empty: keep the data bits
	sub al,'5'		; '5'-'8' -> 0-3; anything below '5'
	cmp al,4		;   wraps high, so one unsigned test
	jnc short BAD_JUMP	;   rejects all others ("9")
	inc si			; past the digit
	shl al,1		; to bits 3-2
	shl al,1	; (count - 5) << 2
	and byte [MODEB],0FFh-MODE_DBITS	; clear bits 3-2 (F3h)
	or [MODEB],al		; the new count
; ---- stop bits: 1, 1.5 or 2 -> mode bits 7-6 ----
SBITS:
	call COMMA		; last field
	jc short SETX		; line ends: set it
	jz short SBEND		; empty: keep the stop bits
	mov ah,MODE_STOP1	; assume 1
	cmp al,'2'		; "2"?
	jnz short SBITS_ONE	; no: 1 or 1.5
	mov ah,MODE_STOP2	; 2 stop bits
	jmp short SBITS_STORE	; store it
SBITS_ONE:			; (src: SBIT1)
	cmp al,'1'		; must be "1" or "1.5" now
	jnz short BAD_JUMP	; ("3")
	cmp byte [si+1],'.'	; "1." ...
	jnz short SBITS_STORE	; no: plain 1
	cmp byte [si+2],'5'	; ... must go on "5" ("1.4" fails)
	jnz short BAD_JUMP	; ("3")
	add si,byte 2		; past ".5"
	mov ah,MODE_STOP15	; 1.5 stop bits
SBITS_STORE:			; (src: SBIT2)
	inc si			; past the last digit
	and byte [MODEB],0FFh-MODE_STOPS	; clear bits 7-6 (3Fh)
	or [MODEB],ah		; the new stop bits
SBEND:
	call BLANKS		; nothing may follow the fourth field
	jz short SETX		; end: set it
BAD_JUMP:			; (src: BAD1)
	jmp BAD			; relay: BAD is out of short range here
				;   (",1" after the stop bits lands here too)

; ---------------------------------------------------------------------
; SETX - hand the new settings to the BIOS and show them
; INT 14h: AH=F1h (I14_SETMODE), AL = mode byte, CL = baud code, DX =
;          channel -> I14X: SSET resets and programs the channel and
;          updates SAVED; SSTAT's status in AH / AL is not looked at.
; Then SHOW (INT 14h F0h: the copy just stored) and INT 20h.
; ---------------------------------------------------------------------
SETX:
	mov ah,I14_SETMODE	; AH=F1h: set the channel up
	mov al,[MODEB]		; AL = mode byte (bits 1-0 as F0h gave them)
	mov cl,[BAUDC]		; CL = baud code 0-15
	mov dx,[CHAN]		; DX = channel
	int byte 14h		; -> TRAP TRAP_INT14 -> I14X -> SSET
	call SHOW		; the settings as the BIOS now holds them
	int byte 20h		; terminate

; =====================================================================
; COMMA - step from one field to the next
; ---------------------------------------------------------------------
; Entry:  SI just after a field (or at the baud field's comma).
; Exit:   CF=1: the line ends here (no more fields).
;         Otherwise SI is past the comma and any blanks, CF=0, and
;         ZF=1 if the next field is empty (another comma, or the end
;         after a trailing comma), else ZF=0 and AL = its first char.
;         Anything but a comma or the end -> BAD (via BAD_JUMP).
; Corrupts: AL, F.  Callers: PAR, DBITS, SBITS.
; =====================================================================
COMMA:
	call BLANKS		; past blanks; ZF=1 at the end of the line
	stc			; (STC keeps ZF)
	jz short COMMA_EXIT	; end: CF=1
	cmp al,','		; else it must be the separator
	jnz short BAD_JUMP	; (e.g. "9600 N" without the comma)
	inc si			; past it
	call BLANKS		; and past blanks after it
	cmp al,','		; another comma: empty field, ZF=1, CF=0
	jz short COMMA_EXIT	; (CF=1, ZF=1)
	or_d al,al		; CF=0; ZF=1 at the end (trailing comma)
COMMA_EXIT:			; (src: CMX)
	ret

; =====================================================================
; BLANKS - skip spaces and tabs
; ---------------------------------------------------------------------
; Entry:  SI in the upper-cased, 0-ended tail.
; Exit:   SI at the first other character, AL = it, ZF=1 if it is the
;         end mark 0, CF=0.  Corrupts: AL, F.
; Callers: START, PORT, SBITS, COMMA.
; =====================================================================
BLANKS:
	lodsb			; next character
	cmp al,' '		; space?
	jz short BLANKS	; skip it
	cmp al,TAB		; tab?
	jz short BLANKS	; skip it
	dec si			; back onto the character
	or_d al,al		; ZF=1 at the end, CF=0
	ret

; =====================================================================
; GETW - copy a word (letters A-Z, digits, '.') to a padded buffer
; ---------------------------------------------------------------------
; Entry:  SI = text, DI = buffer, CX = its size (4 or 6).
; Exit:   ZF=1: 1..CX characters copied, the rest of the buffer filled
;         with spaces, SI past the word.  ZF=0: no word at SI, or one
;         longer than CX (SI then mid-word: the caller gives up).
; Corrupts: AL, BX, CX, DI, F.  Callers: PORT (CX = 4), SETS (CX = 6).
; A '.' counts as part of a word so "134.5" is one; lower case can't
; occur (START upper-cased the tail).
; =====================================================================
GETW:
	mov_d bx,cx		; BX = size, to tell "none copied"
GETW_NEXT:			; (src: GETW1)
	mov al,[si]		; look, don't take yet
	cmp al,'.'		; '.'
	jz short GETW_TAKE	; part of a word
	cmp al,'0'		; below '0': end of word
	jc short GETW_PAD	; ends here
	cmp al,'9'		; '0'-'9'
	jna short GETW_TAKE	; a digit: take it
	cmp al,'A'		; ':' .. '@': end of word
	jc short GETW_PAD	; ends here
	cmp al,'Z'		; above 'Z': end of word
	ja short GETW_PAD	; ends here ('A'-'Z' fall through)
GETW_TAKE:			; (src: GETW2)
	jcxz short GETW_FAIL	; a word character with no room: too long
	stosb			; into the buffer
	inc si		; taken
	dec cx			; room left
	jmp short GETW_NEXT	; next character
GETW_PAD:			; (src: GETW3)
	cmp_d cx,bx		; nothing copied at all?
	jz short GETW_FAIL	; then no word
	mov al,' '		; pad the rest (CX may be 0: no-op)
	rep stosb	; spaces to the end of the buffer
	cmp_d al,al		; ZF=1: a word
	ret
GETW_FAIL:			; (src: GETWX)
	or_d sp,sp		; ZF=0 (SP is never 0 here)
	ret

; =====================================================================
; SAME6 - compare TOKEN with the 6 characters at BX
; ---------------------------------------------------------------------
; Entry:  BX = a BAUDS or ABAUDS entry.  Exit: ZF=1 if equal.
; Corrupts: CX, DI, F (SI kept).  Callers: SETS (BAUD_CODES,
; BAUD_PCNAMES).
; =====================================================================
SAME6:
	push si			; keep the parse position
	mov si,TOKEN		; the baud field ...
	mov_d di,bx		; ... against the entry
	mov cx,BAUD_W	; 6 characters
	repe cmpsb		; ZF=1 when all 6 agree
	pop si		; (POP keeps the flags)
	ret		; ZF = the answer

; =====================================================================
; SHOW - print one channel's settings as
;        "PRN: 1200 baud, no parity, 8 data bits, 1.5 stop bits"
; ---------------------------------------------------------------------
; Entry:  CHAN = channel.
; Exit:   line printed, CR LF.  Corrupts: AX, BX, CX, DX, SI, F.
; Callers: START (both), PORT (one), SETX (after a change).
; INT 14h:  AH=F0h (I14_GETMODE) - the BIOS's copy, not the chip.
; DOS calls: AH=09h print string, AH=02h display character.
; Ends by falling into PUTS: PUTS's RET is SHOW's.
; =====================================================================
SHOW:
	mov ah,I14_GETMODE	; AH=F0h: AL = mode byte, AH = baud code
	mov dx,[CHAN]		; DX = channel
	int byte 14h		; -> TRAP TRAP_INT14 -> I14RD
	push ax			; kept for each field below
	mov dx,PRNMSG		; "PRN: " for channel A ...
	cmp word [CHAN],byte CHAN_A	; channel A?
	jz short SHOW_NAME	; yes: keep PRNMSG
	mov dx,AUXMSG		; ... "AUX: " for channel B
SHOW_NAME:			; (src: SHOW1)
	mov ah,DOS_PRTSTR	; AH=09h print string to "$"
	int 21h		; the port's name
; ---- the rate: BAUDS entry (code & 15) ----
	pop bx			; BL mode byte, BH baud code
	push bx		; (keep it for the next field)
	mov al,BAUD_W		; AX = code x 6 ...
	and bh,0Fh		; (a code is 0-15; masked to stay in the table)
	mul bh		; AX = code x 6
	add ax,BAUDS		; ... + BAUDS = the entry
	mov_d si,ax	; SI = the rate's text
	mov cx,BAUD_W		; up to 6 characters, to the first space
	call PUTN	; "1200"
	mov dx,BAUMSG		; " baud, "
	call PUTS	; (PUTS, via CALL)
; ---- the parity: PEN, then EP ----
	pop bx			; BL = mode byte again
	push bx		; (and again for the next)
	mov dx,NOPMSG		; "no" if PEN = 0
	test bl,MODE_PEN	; parity on?
	jz short SHOW_PARITY	; no
	mov dx,ODDMSG		; "odd" if PEN and EP = 0
	test bl,MODE_EP	; even?
	jz short SHOW_PARITY	; no: odd
	mov dx,EVNMSG		; "even" if PEN and EP
SHOW_PARITY:			; (src: SHOW2)
	call PUTS		; the word
	mov dx,PARMSG		; " parity, "
	call PUTS	; "no" / "odd" / "even"
; ---- the data bits: bits 3-2 + 5, one digit ----
	pop bx		; BL = mode byte
	push bx		; (once more for the stop bits)
	mov_d dl,bl		; mode byte ...
	shr dl,1		; ... bits 3-2 down to 1-0
	shr dl,1	; (two single shifts: MASM's SHR r,1)
	and dl,3		; 0-3
	add dl,'5'		; '5'-'8'
	mov ah,DOS_CONOUT	; AH=02h display character
	int 21h		; the digit
	mov dx,DATMSG		; " data bits, "
	call PUTS	; (PUTS)
; ---- the stop bits: STOPS entry (bits 7-6), "s" unless 1 ----
	pop bx			; last use: the stack is level again
	mov_d al,bl		; mode byte ...
	mov cl,STOP_SHIFT	; ... bits 7-6 down to 1-0
	shr al,cl		; AL = 0-3 (AH is junk, MUL ignores it)
	push ax			; kept for the plural test
	mov ah,STOP_W		; AX = code x 3 ...
	mul ah		; AX = code x 3
	add ax,STOPS		; ... + STOPS = the entry
	mov_d si,ax	; SI = the stop text
	mov cx,STOP_W		; "1", "1.5", "2" (or "?")
	call PUTN	; "1.5"
	mov dx,STPMSG		; " stop bit"
	call PUTS	; (PUTS)
	pop ax			; AL = stop code
	cmp al,MODE_STOP1>>STOP_SHIFT	; code 1 = one stop bit: singular
	jz short SHOW_EOL	; yes: no "s"
	mov dl,'s'		; "bits"
	mov ah,DOS_CONOUT	; AH=02h display character
	int 21h		; the "s"
SHOW_EOL:			; (src: SHOW3)
	mov dx,CRLF		; end of line, printed by PUTS below

; ---------------------------------------------------------------------
; PUTS - print the "$" string at DX (INT 21h AH=09h).  Corrupts AH.
; Callers: SHOW (and SHOW falls into it).
; ---------------------------------------------------------------------
PUTS:
	mov ah,DOS_PRTSTR	; AH=09h print string to "$"
	int 21h		; (DS = PSP: every string is in this file)
	ret

; ---------------------------------------------------------------------
; PUTN - print up to CX characters at SI, stopping at the first space
; (the tables pad with spaces).  AH=02h display character, one by one.
; Corrupts: AX, CX, DL, SI, F.  Callers: SHOW (rate, stop bits).
; ---------------------------------------------------------------------
PUTN:
	lodsb			; next character
	cmp al,' '		; padding: done
	jz short PUTN_END
	mov_d dl,al		; DL = the character
	mov ah,DOS_CONOUT	; AH=02h display character
	int 21h		; one character
	loop short PUTN		; until CX characters
PUTN_END:			; (src: PUTN1)
	ret
