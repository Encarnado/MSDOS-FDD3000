;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  9/10
;  TERM.COM - a serial terminal on the WD2123, with XMODEM and a log
;  (8086 .COM, 6679 bytes, runs at CS:0100h; carries volume 10 inside)
;==============================================================================
;
;  ROLE.  `TERM [port[:] [settings]] [/opts]` turns the Timex terminal
;  into a VT100 (or VT52) of 24 x 64 (or 80) on one of the WD2123's two
;  serial channels: what the host sends is drawn, what is typed goes to
;  the host.  Ctrl-A brings a menu on the bottom line: quit, log to a
;  file, local echo, implicit LF, XMODEM receive / send, break.  Like
;  CPM.COM (volume 6) it is two programs in one: 3195 bytes of 8086 code
;  and data (0100h-0D7Ah), run by Z86.SYS's interpreter like any .COM,
;  and from 0D7Bh the Z80 part, TERMZ80 (volume 10), behind a 16-byte
;  header.  The division of labour follows speed: everything that must
;  keep up with the line (the WD2123 holds one received byte; at 19 200
;  baud the next one overwrites it about 2 100 T-states later) is Z80
;  code - the session, the VT100 emulation and its shadow screen, the
;  2 KB receive ring, flow control, the raw bytes of a transfer, the
;  CRC.  This 8086 part does what is slow or needs DOS: the command
;  line, the menu, the files (log and XMODEM, DOS FCB calls) and the
;  XMODEM protocol's decisions.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM 1.17H  ->  THIS PROGRAM (8086, START)
;       ->  options, port and settings parsed; INT 14h AH=F1h sets the
;           channel (only when settings were given)
;       ->  TRAP 1Ch, BP = linear address of the header at Z80IMG
;           (0D7Bh): Z86.SYS's T_CPML (volume 2) checks the header's 7
;           addresses and copies the 3468-byte image to ENDBIOS (F12Ch,
;           over COLD); the image's place here becomes the buffers
;       ->  TRAP 1Ch, BP = 0, AH = function: JP ENDBIOS = TERMZ80's
;           T_TERM, which dispatches AH 0-9 (TZ_INIT .. TZ_MODE below)
;           and RETs out of the trap.  SESS (AH = 1) is the session; it
;           comes back only for the menu key or a full log buffer
;       ->  menu Q: log closed, cursor to the bottom line, INT 20h
;
;  THE TERMZ80 FUNCTIONS (TERMZ80.ASM header; trap 1Ch with BP = 0)
;     AH 0 INIT   SI = linear PBLK (13 bytes, below): set up, clear screen
;     AH 1 SESS   the session; AL = 1 menu key, 2 log buffer full;
;                 CX = bytes in the log buffer, DX = bytes lost
;     AH 2 DRAW   draw the screen again from row CL (DOS wrote over it)
;     AH 3 RECV   BH <> 0: send BL first; then up to CX bytes to linear
;                 DI, DX x 10 ms for the first, 1 s for each other;
;                 CX = bytes received, AL = 1 a key was pressed (taken)
;     AH 4 SEND   CX bytes from linear SI; AL = 1 if CTS stayed off
;     AH 5 BRK    a break of about 250 ms
;     AH 6 LOG    DX = 0 off / 1 on; CX = bytes now in the log buffer
;     AH 7 CRC    CX bytes at linear SI: DX = CRC-16 (XMODEM), AL = sum
;     AH 8 FLUSH  forget what has been received (empty the ring)
;     AH 9 MODE   DL = PFLAGS: bits 8 (echo) and 10h (LF after CR) taken
;  Addresses passed are linear (BASE + offset): the 8086's memory is the
;  Z80's 0000h-CFFFh, so a linear address is a Z80 address.
;
;  MEMORY OF THIS PROGRAM ONCE TERMZ80 IS LOADED (offsets in our segment)
;     0100h-0D7Ah  8086 code, variables, tables, messages, 128-byte stack
;     0D7Bh        SCRBUF   shadow of the host's screen, 24 x 80 at most
;     14FBh        RINGBUF  the receive ring, RINGSZ = 2048
;     1CFBh        LOGBUF   the log buffer, LOGSZ = 8192
;     3CFBh-3D7Fh  XBUF     one XMODEM block, 133 bytes
;  The file ends at 1B16h; the buffers cover the dead image and run on
;  past it (the .COM owns the whole segment; nothing checks the size).
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/term_findings.md)
;   - QUIT leaves the host stopped.  The menu is entered through
;     TERMZ80's HOLD (XOFF queued and sent, or RTS dropped with /R), and
;     only a later SESS / RECV / SEND lets the host go again.  Q goes
;     straight to INT 20h, so after TERM ends the host sits XOFFed (or
;     with RTS off) until something else sends XON.  By reading both
;     sources; test_term.py never presses Q.
;   - XMODEM: one CAN as a block's first byte ends a transfer ("Cancelled
;     by the other side"; most programs want two); the sender's wait for
;     'C' / NAK restarts its 60 s on every other byte (only a key or
;     silence ends it); a block numbered BLK-1 is ACKed and dropped,
;     which also quietly skips a YMODEM block 0; a failed or cancelled
;     receive keeps the partial file; retries: 10 on receive (JA), 9
;     re-sends on send (JB).  The received file is whole blocks: ^Z
;     padding included (test_term.py compares against `padded`).
;   - /64 is accepted (64 columns, the default) but not in the usage.
;   - Three MASM 1.10 forward-reference NOPs: `JMP LOGSW` (EB 64 90),
;     `JMP SHOW1` (EB 22 90), and `MOV [XBUF],SOH` (C6 06 FB 3C 01 90):
;     XBUF is an EQU defined after the code, so pass 1 sized the move
;     before knowing it was a BYTE location.
;   - The header carries the same 7 Z86.SYS addresses as CPM.COM's
;     (z86.py termz80() reuses cpmz80()'s names); TERMZ80 uses JPHL,
;     PEEKEY, GETKEY, CONOUT and ENDBIOS but not NEXT or DCSP, and it
;     also uses REGS-page names (R_AH, R_SI ...) the header does not
;     check.  TERMZ80 ends at FEB8h, 8 bytes under z86.py's FEC0h limit.
;   - A logging session that fills the disk while being closed closes
;     LFCB twice (LOGWR's disk-full path, then LOGOFF's own close).
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/TERM.COM with NASM
;  (nasm -O0 -f bin, tools/roundtrip.sh term).  Every instruction
;  matches the MASM listing ../symbols/x86/TERM.LST; every label is at
;  the address TERM.COM.sym gives.  The header at 0D7Bh was checked
;  against ../symbols/z80/Z86.SYS.sym, and the 3468 bytes after it are
;  bin/TERMZ80.BIN byte for byte (volume 10), included with incbin.
;  On the emulated FDD3000 (fdd86.py, a host on channel B sending in
;  real time) test_term.py checks: start-up (AUX:9600 gives mode 8Eh,
;  baud code 14, the hello line); 21 code cases and 60 random batches
;  against a Python VT100; keys and the menu's Ctrl-A and B; /E, /C and
;  the menu's E and C; 6 KB at 9600 and 19200 with XON/XOFF and with
;  RTS/CTS (nothing lost) and /N (bytes lost, as expected); the log
;  (12 KB at 19200 through the 8 KB buffer: the file is every byte);
;  XMODEM receive with CRC (block 6 corrupted once, 9600; and 19200)
;  and with checksums after three 'C's, and send with CRC and with
;  checksums (the files are the same bytes); /52 and /80.  Not tested:
;  Q, the usage / port / baud error paths, disk full, cancel by key or
;  by CAN, the retry limits, a duplicated block.
;  HARDWARE: the merged build containing TERM has NOT been run on a real
;  FDD3000 (notes/hardware_run.md has no TERM run).  João's own build:
;  his poc README records an interactive TERM session against PuTTY
;  "Tried on a real FDD3000" (undated), while its serial section says
;  "nothing has been tried on the hardware" and the TERM section's "Not
;  known" covers the real terminal's speed.  So: one interactive session
;  on hardware, probably; XMODEM, logging, flow-control rates and every
;  timing figure are emulator results (test_term.py).  To be confirmed
;  with João.
;
;  FILE:    TERM.COM, 6679 bytes
;  MD5:     e28710898db1d2cb34972e30b1201089
;  SHA256:  a50bf0384031f6e1e67d3b011464030fb82e17d3ca15c338b7a48cb62403c875
;  SOURCE:  ../project/MSDOS/poc/TERM.ASM (MASM 1.10), with TERMZ80.INC
;           (z86.py termz80(): header + TERMZ80.ASM's code) by build.py
;
;  CREDITS.  Original code: João Encarnado, for the FDD3000-MSDOS
;  project (2026).  Not Microsoft code: MS-DOS 1.25 has no terminal
;  program.  XMODEM after Ward Christensen (1977), CRC-16 variant after
;  John Byrns; the command line's port and settings as MODE.COM
;  (volume 8).  Disassembly and annotation in the style of "The Complete
;  TMX Portugal ROM Disassemblies", LoadZX Museum, 2026.
;==============================================================================

; =====================================================================
;                    ASSEMBLER SPELLING (NASM -O0)
; =====================================================================
; TRAP n emits 0Fh n: POP CS on a real 8086, which Z86.SYS's
; interpreter takes as "call BIOS function n" (TTAB, volume 2) and then
; continues at the next byte.  (The source writes it DB 0FH,1CH.)
;
; The _d forms (mov_d di,si, xor_d ch,ch ...) are register-to-register
; instructions in MASM's encoding, with the direction bit set (8B FE for
; MOV DI,SI); NASM would pick the other, equally valid, form.  Same
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

ROWS		equ	24	; the host's screen: 24 lines (PROWS)
RINGSZ		equ	2048	; TERMZ80's receive ring (RINGBUF)
LOGSZ		equ	8192	; the log buffer (LOGBUF, PLOGSZ)
MENUK		equ	1	; Ctrl-A: the menu key (PMENU)

; ---- XMODEM control bytes ----
SOH		equ	1	; start of a 128-byte block
EOT		equ	4	; end of the file
ACK		equ	6	; block good
NAK		equ	15H	; block bad / start with checksums
CAN		equ	18H	; cancel
				; ('C' = 43h: start with CRC-16, written 'C')

; ---- BIOS trap (served by TTAB, z86sys.asm; names as in iosys.asm) ----
TRAP_CPM	equ	1Ch	; Z86.SYS T_CPML: BP <> 0 load the Z80 part at
				;   linear BP (CF=1: built for another Z86.SYS);
				;   BP = 0 JP ENDBIOS - here TERMZ80's T_TERM,
				;   function AH (the name is from CPM.COM, the
				;   trap's first user)

; ---- TERMZ80's functions (AH for TRAP_CPM with BP = 0) ----
TZ_INIT		equ	0	; SI = PBLK: set up, screen cleared
TZ_SESS		equ	1	; the session -> AL 1 menu / 2 log full
TZ_DRAW		equ	2	; redraw from row CL
TZ_RECV		equ	3	; [send BL], receive CX bytes to DI
TZ_SEND		equ	4	; send CX bytes from SI
TZ_BRK		equ	5	; a break, ~250 ms
TZ_LOG		equ	6	; DX = log on / off, CX = LOGN
TZ_CRC		equ	7	; DX = CRC-16, AL = sum of CX bytes at SI
TZ_FLUSH	equ	8	; empty the receive ring
TZ_MODE		equ	9	; DL = flags (echo, LF after CR)

; ---- PFLAGS bits (TERMZ80's P_FLAGS) ----
PF_VT52		equ	01h	; /52: the host sends VT52 codes
PF_XONXOFF	equ	02h	; /X: XON / XOFF flow control (the default)
PF_RTSCTS	equ	04h	; /R: RTS / CTS flow control
PF_ECHO		equ	08h	; /E, menu E: local echo
PF_CRLF		equ	10h	; /C, menu C: a CR received is CR LF

; ---- the WD2123's control / status ports (PCTL; z86sys.asm names) ----
UART_CMD_CHA	equ	81h	; channel A (PRN, COM1): INT 14h port 0
UART_CMD_CHB	equ	41h	; channel B (AUX, COM2): INT 14h port 1

; ---- this program's PSP, as COMMAND.COM leaves it ----
PSP_TAILLEN	equ	80h	; length of the command tail
PSP_TAIL	equ	81h	; the tail: what followed "TERM", CR-ended

; ---- MS-DOS 1.25 FCB offsets (RECSZ1) ----
FCB_RECSIZ	equ	14	; record size (word; CREATE / OPEN set 128)
FCB_RR		equ	33	; random record, 4 bytes (two words here)

; ---- Z86.SYS addresses TERMZ80 was assembled against (Z86.SYS.sym) ----
; The author's names, in z86.py termz80()'s order (= CPMSYM's); trap
; 1Ch compares the header's copy with its own CPMSYM.
NEXT		equ	0D83Bh	; the 8086 dispatcher (interpreter main loop)
JPHL		equ	0EB4Dh	; JP (HL): an indirect CALL
PEEKEY		equ	0EBE3h	; console: CF=1 when a key waits
GETKEY		equ	0EC00h	; console: A = next key, waiting
CONOUT		equ	0EC0Eh	; console: A to the terminal
DCSP		equ	0F12Ah	; Z80 SP that DOSCALL leaves for trap 1Dh
ENDBIOS		equ	0F12Ch	; end of the resident BIOS: TERMZ80 goes here

	org	0100h
bits 16

; =====================================================================
; BEGIN - .COM entry: over the variables to START
; =====================================================================
BEGIN:
	jmp START	; (E9: MASM's near JMP for the forward reference)

; =====================================================================
; VARIABLES - the channel and the command line's fields
; ---------------------------------------------------------------------
; CHAN is a word because INT 14h takes the port in DX; PORT2 stores
; only its low byte.  MODEB / BAUDC are filled from INT 14h AH=F0h
; (the settings of now) before the command line changes them.
; =====================================================================
BASE:
	dw 0	; CS x 16: this program's linear (= Z80) address
CHAN:
	dw 1	; INT 14h port: 0 channel A, 1 channel B (default AUX)
MODEB:
	db 0	; the channel's 8251A-style mode byte (see PAR..SBITS)
BAUDC:
	db 0	; the channel's baud code, 0-15 (BAUDS's index)
NAMBUF:
	db "    "	; the port's name, 4 characters, blank-padded
TOKEN:
	db "      "	; the baud field, 6 characters, blank-padded

; =====================================================================
; PBLK - the parameter block INIT copies (TERMZ80's PB, PBLEN = 13)
; ---------------------------------------------------------------------
; Offsets as TERMZ80.ASM's P_xxx equates.  PCTL and the three buffer
; addresses are filled at LOAD_OK; the rest by the options.
; =====================================================================
PBLK:
PCTL:
	db 0	; +0  P_CTL: control port, UART_CMD_CHA / _CHB
PCOLS:
	db 64	; +1  P_COLS: 64, or 80 with /80
PROWS:
	db ROWS	; +2  P_ROWS: 24
PFLAGS:
	db 2	; +3  P_FLAGS: PF_xxx, PF_XONXOFF by default
PMENU:
	db MENUK	; +4  P_MENU: the menu key, Ctrl-A
PSCR:
	dw 0	; +5  P_SCR: linear SCRBUF, the shadow screen
PRING:
	dw 0	; +7  P_RING: linear RINGBUF
PLOG:
	dw 0	; +9  P_LOG: linear LOGBUF
PLOGSZ:
	dw LOGSZ	; +11 P_LOGSZ: 8192 (TERMZ80 keeps 256 for overrun)

; ---- the log ----
LOGON:
	db 0	; 1: logging to LFCB
LOGN:
	dw 0	; bytes in LOGBUF, as SESS last reported
LOST:
	dw 0	; received bytes TERMZ80 could not keep (menu shows)

; ---- XMODEM state ----
BLK:
	db 0	; block number expected (receive) / being sent
CRCM:
	db 0	; 1: CRC-16 (133-byte blocks), 0: checksum (132)
TRIES:
	db 0	; timeouts / bad blocks / re-sends so far
GOT:
	db 0	; receive: 1 once a good block has come
XREPLY:
	db 0	; receive: the byte to send before the next wait
			;   ('C', NAK, ACK; 0 none)
XLEN:
	dw 0	; the block's length on the line, 132 or 133
XCNT:
	dw 0	; send: file bytes in the block (before ^Z padding)
XMSG:
	dw 0	; XRMSG / XSMSG: the bottom line's caption
NBYTES:
	dw 0,0	; bytes moved, 32 bits (low, high)
ANSB:
	db 0	; send: the receiver's answer byte
EOTB:
	db EOT	; send: the EOT, as a 1-byte buffer for SEND
CANS:
	db CAN,CAN,CAN	; three CANs: what XCAN sends to give up
MENUKB:
	db MENUK	; the menu key, as a 1-byte buffer (menu ^A)

; ---- FCBs: drive, 8.3 name (filled by ASKF's AH=29h), DOS's fields ----
LFCB:
	db 0,"           "	; the log file

	times 25 db 0	; +12..+36: DOS's fields, the random record
XFCB:
	db 0,"           "	; the XMODEM file (received or sent)

	times 25 db 0	; +12..+36

LINE:
	times 32 db 0	; ASKF's typed name: 28 characters + CR at most

; =====================================================================
; PORTS - the port names: 4 characters, blank-padded, then the channel
; =====================================================================
PORTS:
	db "PRN ",0,"LPT1",0,"COM1",0,"AUX ",1,"COM2",1	; A A A B B
NPORTS equ 5

; =====================================================================
; BAUDS - the baud rates by code 0-15, 6 characters each (as MODE's,
; after TMX CONFIGUR); a code is the entry's index
; =====================================================================
BAUDS:
	db "50    75    110   134.5 150   200   300   600   "	; 0-7
	db "1200  1800  2400  3600  4800  7200  9600  19200 "	; 8-15

; ---------------------------------------------------------------------
; ABAUDS - the PC's MODE abbreviations: 6 characters, then the code
; ---------------------------------------------------------------------
ABAUDS:
	db "134   ",3,"11    ",2,"15    ",4,"30    ",6	; 134.5 110 150 300
	db "60    ",7,"12    ",8,"24    ",10,"48    ",12	; 600 1200 2400 4800
	db "96    ",14,"19    ",15	; 9600 19200
NABAUDS equ 10

; =====================================================================
; MESSAGES - INT 21h AH=09h strings, "$"-terminated
; ---------------------------------------------------------------------
; USEMSG..CRLF go to DOS's console before the session.  From BOTL on
; they are for the bottom line (row 23) in the Timex terminal's own
; codes: ESC Y row col, ESC L inverse, ESC M normal, ESC K erase to the
; end of the line.  A bottom-line text stays under 63 characters: the
; terminal wraps at once after the last column, and on the bottom line
; that would scroll it.
; =====================================================================
USEMSG:
	db "Invalid parameter",13,10,13,10	; any command-line error
	db "Usage: TERM [port[:] [baud][,[N|O|E][,[5-8][,[1|1.5|2]]]]]",13,10
	db "            [/80] [/52] [/X|/R|/N] [/E] [/C]",13,10
	db "  port: PRN, LPT1 or COM1 (channel A), AUX or COM2 (channel B)",13,10
	db "  /80 80 columns, /52 VT52 host, /X XON/XOFF, /R RTS/CTS, /N none",13,10
	db "  /E local echo, /C LF after each CR received",13,10
	db "  Ctrl-A: the menu$"	; (/64 is accepted too, not listed)
CRLF:
	db 13,10,"$"	; ends the usage
VERMSG:
	db "TERM.COM does not match Z86.SYS",13,10,"$"	; trap 1Ch: CF=1

HELLO:
	db "TERM: Ctrl-A for the menu"	; copied into the shadow screen
HELLOE:			;   (no "$": 25 bytes by HELLOE-HELLO)

BOTL:
	db 27,"Y",32+ROWS-1,32,27,"L$"	; ESC Y row 23 col 0, ESC L inverse
BOTE:
	db 27,"M",27,"K$"	; ESC M normal, ESC K: the rest blank
MENU1:
	db "Q quit L log$"	; the menu: 13 + 8 + 6 + 24 + 6 + 5 = 62
MENUE:
	db " E echo$"	;   characters at most, with " lost 65535"
MENUC:
	db " C lf$"
MENUON:
	db "+$"	; after L, E, C: on
MENUOF:
	db "-$"	; off
MENU2:
	db " R rcv S snd B brk ^A ^A$"	; Ctrl-A in the menu sends a Ctrl-A
LOSTM:
	db " lost $"	; then LOST in decimal
LOGASK:
	db "Log to file: $"
RCVASK:
	db "Receive (XMODEM) as file: $"
SNDASK:
	db "Send (XMODEM) file: $"
CRMSG:
	db "Cannot create the file$"	; AH=16h failed (directory full)
NFMSG:
	db "File not found$"	; AH=0Fh failed
FULLM:
	db "Disk full: log stopped$"	; AH=28h short
XRMSG:
	db "Receiving: $"	; XMSG captions, then NBYTES
XSMSG:
	db "Sending: $"
BYTESM:
	db " bytes$"	; progress
DONEM:
	db " bytes: done$"	; the end
CANM:
	db "Cancelled$"	; a key during a transfer
RCANM:
	db "Cancelled by the other side$"	; a CAN came
FAILM:
	db "Transfer failed$"	; retries out, sequence, disk, CTS
KEYM:
	db " - a key$"	; SHOW's "press a key"
BSSTR:
	db 8," ",8,"$"	; ASKF's rub-out: back, blank, back

; =====================================================================
; START - set up; upper-case the command line; take the options out
; ---------------------------------------------------------------------
; Entry:  from COMMAND.COM: CS=DS=ES=SS = our PSP, the tail at 80h.
; Exit:   to OPTX with every /option blanked out of the tail, or BAD.
;
; The tail is upper-cased in place and its CR replaced by a 0, so the
; rest of the parse ends on 0.  Options are found anywhere ("AUX/X" is
; as good as "AUX /X") and blanked, leaving only port and settings.
; Two-character options are tried first (80, 64, 52), then the letters;
; the flow options replace each other (the last one wins), E and C add.
; =====================================================================
START:
	mov sp,STKTOP	; our own 128-byte stack, under the image
	cld		; string operations go up
	mov ax,cs	; BASE = CS x 16: linear = Z80 address
	mov cl,0x4	; (4 shifts: x 16)
	shl ax,cl	; AX = linear address of our PSP
	mov [BASE],ax	; for every address handed to TERMZ80
;
; the command line, in upper case, ending with a 0; the options first
;
	mov si,PSP_TAIL	; SI = DI = the tail, CX = its length
	mov cl,[PSP_TAILLEN]	; CL = tail length (0-127)
	xor_d ch,ch	; CX = it
	mov_d di,si	; upper-cased in place
UPPER:
	jcxz short UPX	; all done
	lodsb		; next character
	cmp al,'a'	; a lower-case letter?
	jc short UPPER_STORE	; below 'a': as is
	cmp al,'z'	; ... up to 'z'
	ja short UPPER_STORE	; above 'z': as is
	sub al,0x20	; to upper case
UPPER_STORE:				; (src: UP1)
	stosb		; back where it was
	loop short UPPER	; every character
UPX:
	mov byte [di],0x0	; a 0 over the CR: the end of the line
	mov si,PSP_TAIL	; from the start, for the options
OPT:
	lodsb		; next character
	or_d al,al	; the end?
	jz short OPTX	; yes: on to the port
	cmp al,'/'	; an option?
	jnz short OPT	; no: pass
	mov byte [si-1],' '	; the "/" blanked out
	mov ax,[si]	; AL, AH = the two characters after it
	mov bl,0x2	; BL: the option's length
	cmp ax,'0'*256+'8'	; "80": 80 columns
	jz short OPT80	; /80
	cmp ax,'4'*256+'6'	; "64": 64 columns (the default; not in USEMSG)
	jz short OPT64	; /64
	cmp ax,'2'*256+'5'	; "52": a VT52 host
	jz short OPT52	; /52
	mov bl,0x1	; one letter from here on
	mov ah,PF_XONXOFF	; X: XON / XOFF
	cmp al,'X'	; /X
	jz short OPTF	; flow: XON / XOFF
	mov ah,PF_RTSCTS	; R: RTS / CTS
	cmp al,'R'	; /R
	jz short OPTF	; flow: RTS / CTS
	mov ah,0x0	; N: no flow control
	cmp al,'N'	; /N
	jz short OPTF	; flow: none
	mov ah,PF_ECHO	; E: local echo
	cmp al,'E'	; /E
	jz short OPTM	; echo on
	mov ah,PF_CRLF	; C: LF after each CR received
	cmp al,'C'	; /C
	jnz short BADO	; anything else: the usage
OPTM:
	or [PFLAGS],ah	; E, C: added to the others
	jmp short OPTB	; blank it
BADO:
	jmp BAD		; an unknown option
OPT80:
	mov byte [PCOLS],80	; /80
	jmp short OPTB	; blank it
OPT64:
	mov byte [PCOLS],64	; /64
	jmp short OPTB	; blank it
OPT52:
	or byte [PFLAGS],PF_VT52	; /52
	jmp short OPTB	; blank it
OPTF:
	and byte [PFLAGS],PF_VT52+PF_ECHO+PF_CRLF	; VT52, echo and LF stay,
	or [PFLAGS],ah	;   the flow control is replaced
OPTB:
	mov byte [si],' '	; the option blanked out
	inc si		;   BL characters of it
	dec bl	; all of it?
	jnz short OPTB	; no: next character
	jmp short OPT	; look for the next
OPTX:
	mov si,PSP_TAIL	; what is left: port and settings
	call BLANKS	; anything?
	jnz short PORT_PARSE	; yes: a port
	jmp LOAD	; nothing: AUX as it is set now

; =====================================================================
; PORT_PARSE - the port, then the settings (as MODE.COM)
; ---------------------------------------------------------------------
; Entry:  SI at the first non-blank after the options were taken out.
; Exit:   to LOAD (port alone: CHAN set, the channel left as it is) or
;         through SETX (settings: INT 14h AH=F1h), or BAD.
;
; Settings start from the channel's present ones (INT 14h AH=F0h: the
; mode byte and baud code the BIOS last set, the WD2123 cannot be read)
; and each field given replaces its part; an empty field ("9600,,7")
; keeps it.  A port is needed to give settings: "TERM 9600" fails, as
; "9600" is no port name.
; =====================================================================
PORT_PARSE:				; (src: PORT0)
;
; the port, then the settings (as MODE)
;
	mov di,NAMBUF	; the name, up to 4 characters, blank-padded
	mov cx,0x4	; (4: 'COM1', 'PRN ')
	call GETW	; ZF=0: none, or more than 4
	jnz short BAD_PORT	; none, or too long: the usage
	mov bx,PORTS	; BX = the table, DL = entries left
	mov dl,NPORTS	; 5 names
PORT_CMP:				; (src: PORT1)
	push si		; SI: the command line, kept
	mov si,NAMBUF	; NAMBUF against this entry
	mov_d di,bx	; DI = this entry
	mov cx,0x4	; 4 characters
	repe cmpsb	; compare
	pop si	; SI back
	jz short PORT_FOUND	; the same 4 characters
	add bx,byte 0x5	; next entry
	dec dl	; entries left?
	jnz short PORT_CMP	; try the next
BAD_PORT:				; (src: BAD0)
	jmp BAD		; no such port (also: the baud field unreadable)
PORT_FOUND:				; (src: PORT2)
	mov al,[bx+0x4]	; the entry's channel
	mov [CHAN],al	; (low byte: CHAN's high byte stays 0)
	cmp byte [si],':'	; "COM1:" - the colon is optional
	jnz short PORT_AFTER	; no colon
	inc si		; past it
PORT_AFTER:				; (src: PORT3)
	call BLANKS	; settings follow?
	jnz short PORT_SETTINGS	; yes
	jmp LOAD	; no: the channel as it is set now
PORT_SETTINGS:				; (src: PORT4)
	mov ah,0xf0	; INT 14h AH=F0h: the settings of now
	mov dx,[CHAN]	;   (DX = port)
	int 14h		; AL = mode byte, AH = baud code
	mov [MODEB],al	; the base the fields change
	mov [BAUDC],ah	; (both kept if not given)
	cmp byte [si],','	; baud left out?
	jz short PAR	; yes: straight to parity
	mov di,TOKEN	; the baud, up to 6 characters
	mov cx,0x6	; (6: '134.5 ', '19200 ')
	call GETW	; ZF=0: none, or too long
	jnz short BAD_PORT	; none, or too long
	mov bx,BAUDS	; first the full numbers: DL = code
	xor_d dl,dl	; DL = code 0
BAUD_CMP:				; (src: BAUD1)
	call SAME6	; TOKEN = this entry?
	jz short BAUD_SET	; yes: DL is the code
	add bx,byte 0x6	; next
	inc dl	; code + 1
	cmp dl,0x10	; all 16?
	jc short BAUD_CMP	; no: next
	mov bx,ABAUDS	; then the PC's abbreviations
	mov dh,NABAUDS	; 10 of them
BAUD_ABBR_CMP:				; (src: BAUD2)
	call SAME6	; TOKEN = this one?
	jz short BAUD_ABBR_CODE	; found: the code follows the text
	add bx,byte 0x7	; next (6 characters + code)
	dec dh	; entries left?
	jnz short BAUD_ABBR_CMP	; try the next
	jmp BAD		; no such baud rate
BAUD_ABBR_CODE:				; (src: BAUD4)
	mov dl,[bx+0x6]	; DL = its code
BAUD_SET:				; (src: BAUD3)
	mov [BAUDC],dl	; the new baud code
PAR:
	call COMMA	; parity
	jc short SETX	; the line ended: set what we have
	jz short DBITS	; empty field: parity unchanged
	mov ah,0x0	; N: bits 5-4 = 00, no parity
	cmp al,'N'	; N?
	jz short PAR_SET	; yes
	mov ah,0x10	; O: 01, parity on, odd
	cmp al,'O'	; O?
	jz short PAR_SET	; yes
	mov ah,0x30	; E: 11, parity on, even
	cmp al,'E'	; E?
	jnz short BAD_SETTING	; none of them: the usage
PAR_SET:				; (src: PAR1)
	inc si		; past the letter
	and byte [MODEB],0xcf	; bits 5-4 replaced
	or [MODEB],ah	; the new parity
DBITS:
	call COMMA	; data bits
	jc short SETX	; end of the line
	jz short SBITS	; empty: unchanged
	sub al,'5'	; '5'-'8' -> 0-3
	cmp al,0x4	; 0-3 only
	jnc short BAD_SETTING	; not 5 to 8
	inc si		; past the digit
	shl al,1	; to bits 3-2
	shl al,1	; (x 4)
	and byte [MODEB],0xf3	; bits 3-2 replaced
	or [MODEB],al	; the new data bits
SBITS:
	call COMMA	; stop bits
	jc short SETX	; end of the line
	jz short SBEND	; empty: unchanged
	mov ah,0x40	; bits 7-6: 01 = 1 stop bit
	cmp al,'2'	; '2'?
	jnz short SBITS_ONE	; no: '1' or '1.5'
	mov ah,0xc0	; 11 = 2
	jmp short SBITS_SET	; to store
SBITS_ONE:				; (src: SBIT1)
	cmp al,'1'	; "1" or "1.5"
	jnz short BAD_SETTING	; neither: the usage
	cmp byte [si+0x1],'.'	; "1.5"
	jnz short SBITS_SET	; "1": 01
	cmp byte [si+0x2],'5'	; (the '5' of 1.5)
	jnz short BAD_SETTING	; "1." and not 5
	add si,byte 0x2	; past ".5"
	mov ah,0x80	; 10 = 1.5
SBITS_SET:				; (src: SBIT2)
	inc si		; past the last digit
	and byte [MODEB],0x3f	; bits 7-6 replaced
	or [MODEB],ah	; the new stop bits
SBEND:
	call BLANKS	; nothing may follow
	jz short SETX	; the end: set it
BAD_SETTING:				; (src: BAD1)
	jmp BAD		; a bad field, or something after the last
SETX:
	mov ah,0xf1	; INT 14h AH=F1h: set the channel up
	mov al,[MODEB]	; AL = mode byte (the BIOS forces x16 clock)
	mov cl,[BAUDC]	; CL = baud code
	mov dx,[CHAN]	; DX = port
	int 14h		; the WD2123 programmed (status ignored)

; =====================================================================
; LOAD - the Z80 part to its place (TRAP_CPM), INIT, the hello line
; ---------------------------------------------------------------------
; Entry:  CHAN, PFLAGS, PCOLS as the command line left them.
; Exit:   falls into SESS; or VERMSG and INT 20h.
; DOS calls: AH=09h print string (VERMSG only).  Traps: 1Ch.
;
; Once trap 1Ch has copied the image to ENDBIOS, its bytes here are
; free: SCRBUF, RINGBUF, LOGBUF and XBUF go over them.  HELLO is put in
; the shadow screen's top row and drawn: it stays until the host writes
; over it.  On VERMSG the channel keeps any settings SETX gave it.
; =====================================================================
LOAD:
	mov bp,[BASE]	; BP = linear address of the header
	add bp,Z80IMG	;   = BASE + 0D7Bh
	TRAP TRAP_CPM	; T_CPML: check the 7 addresses, copy to ENDBIOS
	jnc short LOAD_OK	; CF=0: in place
	mov dx,VERMSG	; CF=1: built against another Z86.SYS
	mov ah,0x9	; AH=09h print string
	int 21h	; "TERM.COM does not match Z86.SYS"
	int 20h		; terminate
LOAD_OK:				; (src: LOAD1)
	mov al,UART_CMD_CHA	; PCTL: channel A's control port ...
	cmp word [CHAN],byte 0x0	; channel A (port 0)?
	jz short LOAD_CTL	; yes: 81h
	mov al,UART_CMD_CHB	; ... or channel B's
LOAD_CTL:				; (src: LOAD2)
	mov [PCTL],al	; PCTL = the port
	mov ax,[BASE]	; the three buffers, as linear addresses
	add ax,SCRBUF	;   (TERMZ80 works in Z80 addresses)
	mov [PSCR],ax	; P_SCR
	mov ax,[BASE]
	add ax,RINGBUF	; RINGBUF, linear
	mov [PRING],ax	; P_RING
	mov ax,[BASE]
	add ax,LOGBUF	; LOGBUF, linear
	mov [PLOG],ax	; P_LOG
	mov si,PBLK	; SI = linear PBLK
	add si,[BASE]	; (TERMZ80 copies the 13 bytes)
	mov ah,TZ_INIT	; INIT: the screen cleared
	call Z80	; TERMZ80 INIT
	mov si,HELLO	; a line on the host's screen till it
	mov di,SCRBUF	;   writes there (top row of the shadow)
	mov cx,HELLOE-HELLO	; 25 bytes
	rep movsb	; into row 0
	mov cl,0x0	; DRAW from row 0: the whole screen
	mov ah,TZ_DRAW	; DRAW
	call Z80	; the hello line shows

; =====================================================================
; SESS - the session; back here for the menu and a full log buffer
; ---------------------------------------------------------------------
; TERMZ80's SESS runs until the menu key (AL = 1) or until the log
; buffer reaches LOGSZ - 256 (AL = 2); either way it has stopped the
; host first (HOLD: XOFF or RTS off, then 100 ms of polling).  The
; next SESS lets the host go again once the ring has emptied.  After
; the menu, DOS's bottom-line output is wiped by drawing row 23 again.
; =====================================================================
SESS:
	mov ah,TZ_SESS	; the session
	call Z80	; returns AL, CX = log bytes, DX = lost
	mov [LOGN],cx	; for LOGWR
	mov [LOST],dx	; for the menu
	cmp al,0x2	; the log buffer full?
	jnz short SESS_MENU	; no: the menu key
	call LOGWR	; the log buffer to the file
	jmp short SESS	; the session goes on
SESS_MENU:				; (src: SESS1)
	call MENU	; one menu command
	mov cl,ROWS-1	; the bottom line again
	mov ah,TZ_DRAW	; (TERMZ80 knows nothing of DOS's writes)
	call Z80	; DRAW row 23
	jmp short SESS	; the session again

; ---------------------------------------------------------------------
; Z80 - TERMZ80's function AH (TRAP_CPM with BP = 0)
; Entry: AH = TZ_xxx, other registers as the function wants.  Exit: as
; the function leaves them; BP = 0.  Callers: everywhere (also as a
; tail JMP).
; ---------------------------------------------------------------------
Z80:
	xor_d bp,bp	; BP = 0: run, not load
	TRAP TRAP_CPM	; JP ENDBIOS -> T_TERM -> FTAB[AH]
	ret	; to the caller

; ---------------------------------------------------------------------
; BAD - the usage, then terminate.  DOS calls: AH=09h twice, INT 20h.
; ---------------------------------------------------------------------
BAD:
	mov dx,USEMSG	; "Invalid parameter" and the usage
	mov ah,0x9	; AH=09h print string
	int 21h
	mov dx,CRLF	; the last line ended
	mov ah,0x9	; AH=09h print string
	int 21h	; CR LF
	int 20h		; terminate

; =====================================================================
; MENU - one command from the bottom-line menu
; ---------------------------------------------------------------------
; Entry:  from SESS_MENU, the host held.  Exit: RET to SESS_MENU, often
;         by a tail JMP into the command (Z80, SEND, LOGSW, XRECV ...).
; DOS calls: AH=09h (through PUTS), AH=07h direct console input.
;
; The line: "Q quit L log+ E echo- C lf- R rcv S snd B brk ^A ^A" with
; " lost n" when bytes were lost.  The key is read with AH=07h (no
; echo, no ^C check) and folded to upper case (anything from 'a' up
; loses 20h: harmless for the keys that matter).  Any key that is no
; command just goes back.
; =====================================================================
MENU:
	call BOTTOM	; the bottom line, inverse
	mov dx,MENU1	; "Q quit L log"
	call PUTS
	mov al,[LOGON]	; + / -
	call ONOFF	; log + / -
	mov dx,MENUE	; " E echo"
	call PUTS
	mov al,[PFLAGS]	; PFLAGS: echo?
	and al,PF_ECHO	; + / -
	call ONOFF	; echo + / -
	mov dx,MENUC	; " C lf"
	call PUTS
	mov al,[PFLAGS]	; PFLAGS: LF after CR?
	and al,PF_CRLF	; + / -
	call ONOFF	; lf + / -
	mov dx,MENU2	; " R rcv S snd B brk ^A ^A"
	call PUTS
	mov ax,[LOST]	; bytes lost?
	or_d ax,ax	; 0: none lost
	jz short MENU_KEY	; none: say nothing
	mov dx,LOSTM	; " lost " and the count
	call PUTS
	call PUTNUM	; LOST in decimal
MENU_KEY:				; (src: MENU1A)
	call BOTEND	; normal, the rest of the line blank
	mov ah,0x7	; AH=07h direct console input, no echo
	int 21h	; AL = the key
	cmp al,'a'	; to upper case
	jc short MENU_CMD	; below 'a': as is
	sub al,0x20	; (no upper bound)
MENU_CMD:				; (src: MENU2A)
	cmp al,'Q'	; Q: quit
	jz short QUIT
	cmp al,'L'	; L: log on / off
	jnz short MENU_R	; no
	jmp short LOGSW	; yes
	nop		; MASM's padding: the forward JMP was given 3 bytes
			;   (TERM.LST 07BA: EB 64 90)
MENU_R:					; (src: MENU3)
	cmp al,'R'	; R: XMODEM receive
	jnz short MENU_S	; no
	jmp XRECV	; yes
MENU_S:					; (src: MENU4)
	cmp al,'S'	; S: XMODEM send
	jnz short MENU_B	; no
	jmp XSEND	; yes
MENU_B:					; (src: MENU5)
	cmp al,'B'	; B: a break
	jnz short MENU_E_C	; no
	mov ah,TZ_BRK	; ~250 ms of break, then back
	jmp Z80	; BRK, then back to SESS_MENU
MENU_E_C:				; (src: MENU8)
	mov ah,PF_ECHO	; E local echo, C implicit LF: on / off
	cmp al,'E'	; E?
	jz short MENU_TOGGLE	; flip the echo
	mov ah,PF_CRLF	; C: implicit LF
	cmp al,'C'	; C?
	jnz short MENU_CTRLA	; neither
MENU_TOGGLE:				; (src: MENU9)
	xor [PFLAGS],ah	; the flag flipped
	mov dl,[PFLAGS]	; MODE: TERMZ80 takes bits 8 and 10h
	mov ah,TZ_MODE	; MODE
	jmp Z80	; TERMZ80 takes the new flags
MENU_CTRLA:				; (src: MENU6)
	cmp al,MENUK	; Ctrl-A again: one Ctrl-A to the host
	jnz short MENU_BACK	; no: back
	mov si,MENUKB	; the 1-byte buffer holding it
	mov cx,0x1	; one byte
	jmp SEND	; to the host
MENU_BACK:				; (src: MENU7)
	ret		; any other key: back to the session

; ---------------------------------------------------------------------
; ONOFF - "+" if AL <> 0, else "-".  Corrupts AH, DX.  Callers: MENU.
; ---------------------------------------------------------------------
ONOFF:
	mov dx,MENUON	; "+"
	or_d al,al	; on?
	jnz short ONOFF_PUT	; yes: '+'
	mov dx,MENUOF	; "-"
ONOFF_PUT:				; (src: ONOFF1)
	jmp PUTS	; print it

; ---------------------------------------------------------------------
; QUIT - menu Q: the log closed, DOS's cursor to the bottom line, end.
; DOS calls: AH=02h display (CR), INT 20h.  The Z80 part stays at
; ENDBIOS (nothing to undo).  NOTE: the host is still held as the menu
; left it (XOFF sent, or RTS off): nothing lets it go before INT 20h.
; ---------------------------------------------------------------------
QUIT:
	cmp byte [LOGON],0x0	; logging?
	jz short QUIT_EXIT	; no: just go
	call LOGOFF	; the rest written, the file closed
QUIT_EXIT:				; (src: QUIT1)
	call BOTTOM	; DOS goes on from the bottom line
	call BOTEND	;   (blank, normal video)
	mov dl,0xd	; AH=02h display: CR, column 0
	mov ah,0x2
	int 21h	; (the cursor at row 23, col 0)
	int 20h		; terminate: back to COMMAND

; =====================================================================
; LOGSW - menu L: start a log (ask the name, create), or stop it
; ---------------------------------------------------------------------
; Exit: RET (through LOGSET / SHOW).  DOS calls: AH=16h create FCB,
; AH=10h close FCB (LOGOFF), and LOGWR's.  Callers: MENU (JMP), QUIT.
;
; The file is created afresh (an existing one of that name is
; truncated) and written with random block writes, records of 1 byte
; (RECSZ1): DOS advances the random record by what each write took,
; so the file is exactly the bytes received.  TERMZ80 collects them
; (LOG on) and SESS hands over when LOGBUF is nearly full.
; =====================================================================
LOGSW:
	cmp byte [LOGON],0x0	; on already?
	jnz short LOGOFF	; yes: off
	mov dx,LOGASK	; "Log to file: "
	mov di,LFCB	; into LFCB
	call ASKF	; CF=1: no name, or ESC
	jc short LOGX	; no name: nothing
	mov dx,LFCB	; AH=16h create FCB
	mov ah,0x16
	int 21h	; AL = 0 made, FFh directory full
	or_d al,al	; AL = 0: made
	jz short LOG_OPENED	; made
	mov dx,CRMSG	; "Cannot create the file"
	jmp SHOW	; say so, wait for a key
LOG_OPENED:				; (src: LOGON1)
	mov bx,LFCB	; byte records, from record 0
	call RECSZ1
	mov byte [LOGON],0x1	; logging
	mov dx,0x1	; LOG on ...
; ---------------------------------------------------------------------
; LOGSET - TERMZ80's LOG: DX = 0 off / 1 on, the buffer emptied (CX =
; LOGN = 0).  Callers: LOGSW, LOGOFF, LOGWR (also by falling in).
; ---------------------------------------------------------------------
LOGSET:
	xor_d cx,cx	; ... with an empty buffer
	mov [LOGN],cx	; LOGN = 0
	mov ah,TZ_LOG	; LOG: DX on / off, CX = 0
	jmp Z80	; TERMZ80 starts (or stops) collecting
; ---------------------------------------------------------------------
; LOGOFF - the rest of the log written, the file closed, LOG off.
; DOS calls: AH=10h close FCB.  Callers: LOGSW, QUIT.  (If LOGWR found
; the disk full it has closed LFCB already: closed twice, likely
; harmless - not checked.)
; ---------------------------------------------------------------------
LOGOFF:
	call LOGWR	; what is in LOGBUF
	mov dx,LFCB	; AH=10h close FCB: the directory entry written
	mov ah,0x10
	int 21h
	mov byte [LOGON],0x0	; off
	xor_d dx,dx	; LOG off
	jmp short LOGSET	; tell TERMZ80
LOGX:
	ret		; no name given: nothing done

; ---------------------------------------------------------------------
; LOGWR - the log buffer to the file (random block write, records of 1)
; Entry: LOGN = bytes in LOGBUF.  Exit: LOG on again with an empty
; buffer; or, disk full, the log stopped and said so.
; DOS calls: AH=1Ah set DTA, AH=28h random block write, AH=10h close.
; Callers: SESS (buffer full), LOGOFF.
; ---------------------------------------------------------------------
LOGWR:
	mov cx,[LOGN]	; CX = bytes = records of 1
	jcxz short LOGWR_DONE	; nothing to write
	mov dx,LOGBUF	; AH=1Ah set DTA: DS:LOGBUF
	mov ah,0x1a
	int 21h	; DOS writes from LOGBUF
	mov dx,LFCB	; AH=28h random block write: CX records
	mov ah,0x28
	int 21h	; AL = 0 ok, 1 disk full
	or_d al,al	; AL = 0: all written
	jz short LOGWR_DONE	; all of it
	mov dx,LFCB	; disk full: the log stops
	mov ah,0x10	; AH=10h close FCB: keep what fitted
	int 21h
	mov byte [LOGON],0x0	; off
	xor_d dx,dx	; LOG off in TERMZ80 too
	call LOGSET	; TERMZ80: log off
	mov dx,FULLM	; "Disk full: log stopped - a key"
	call SHOW	; wait for a key
	mov cl,ROWS-1	; the bottom line back as the host had it
	mov ah,TZ_DRAW	; DRAW
	jmp Z80	; repaint row 23
LOGWR_DONE:				; (src: LOGW1)
	mov dx,0x1	; LOG on, the buffer empty
	jmp short LOGSET	; tell TERMZ80

; =====================================================================
; XRECV - menu R: a file from the host by XMODEM
; ---------------------------------------------------------------------
; CRC-16 if the sender takes 'C', else checksums.  The answer to each
; block goes out with the wait for the next (RECV sends BL first), so
; there is no gap in which the next block's first bytes could be lost.
; DOS calls: AH=16h create, AH=1Ah set DTA, AH=28h random block write,
; AH=10h close (XDONE / XEND).  Exit: through XDONE, XEND or SHOW.
;
; The state machine, one RECV per pass of XR_WAIT:
;   send XREPLY (if not 0), wait 3 s for the first byte and then up to
;   XLEN = 132 + CRCM bytes, 1 s apart.
;     key           -> XUSER: CAN CAN CAN, "Cancelled"
;     nothing       -> XRTO: TRIES + 1; past 10 -> XFAIL.  No block yet:
;                      'C' while TRIES < 3 (so 'C' goes out three times
;                      in all), then CRCM = 0 and NAK; after a block: NAK
;     SOH           -> XRSOH: length, block number / complement, CRC or
;                      sum.  Bad -> XRBAD: PURGE, TRIES + 1, NAK.  Good,
;                      number = BLK: written, BLK + 1, ACK; number =
;                      BLK - 1 (our ACK was lost): ACK only; else XFAIL
;     EOT           -> ACK, XDONE (one EOT is enough)
;     CAN           -> "Cancelled by the other side" (one CAN is enough)
;     other         -> noise: XREPLY = 0, wait on
; =====================================================================
XRECV:
	mov dx,RCVASK	; "Receive (XMODEM) as file: "
	mov di,XFCB	; into XFCB
	call ASKF	; CF=1: no name
	jc short XRX	; no name: nothing
	mov dx,XFCB	; AH=16h create FCB
	mov ah,0x16
	int 21h	; AL = 0 made
	or_d al,al	; AL = 0: made
	jz short XR_CREATED	; made
	mov dx,CRMSG	; "Cannot create the file"
	jmp SHOW	; wait for a key
XRX:
	ret	; back to the menu's caller
XR_CREATED:				; (src: XR0)
	mov bx,XFCB	; byte records, from 0
	call RECSZ1
	mov dx,XRMSG	; "Receiving: ", ring flushed
	call XSTART
	mov byte [BLK],0x1	; XMODEM starts at block 1
	mov byte [CRCM],0x1	; try CRC first
	mov byte [GOT],0x0	; no block yet
	mov byte [XREPLY],'C'	; 'C': "CRC please"
XR_WAIT:				; (src: XR1)
	mov bl,[XREPLY]	; the answer, then a block, its first
	mov_d bh,bl	; byte within 3 s, the others 1 s apart
	mov cx,132	;   (BH <> 0: send BL)
	add cl,[CRCM]	; 133 with the CRC's second byte
	mov [XLEN],cx	; what a whole block is
	mov dx,300	; 300 x 10 ms for the first byte
	call XGET	; CX = bytes, CF=1 a key
	jc short XRUSR	; the user gave up
	jcxz short XRTO	; nothing came
	mov al,[XBUF]	; what starts it?
	cmp al,SOH	; a block
	jz short XRSOH
	cmp al,EOT	; the end
	jnz short XR_NOT_EOT	; no
	jmp XREOT
XR_NOT_EOT:				; (src: XR2)
	cmp al,CAN	; cancelled
	jnz short XR_NOISE	; no
	jmp XRCAN
XR_NOISE:				; (src: XR3)
	mov byte [XREPLY],0x0	; noise: wait on (the reply went already)
	jmp short XR_WAIT
XRUSR:
	jmp XUSER	; a key: cancel
XRTO:
	inc byte [TRIES]	; a timeout
	cmp byte [TRIES],10	; more than 10: give up
	ja short XRFL	; (11th timeout)
	cmp byte [GOT],0x0	; nothing yet: 'C' three times, then
	jnz short XRNAK	; checksums (NAK)
	cmp byte [TRIES],0x3	; three 'C's so far?
	jc short XRC	; tries 1, 2: 'C' again
	mov byte [CRCM],0x0	; the sender knows no CRC: checksums
XRNAK:
	mov byte [XREPLY],NAK	; "again" / "checksums please"
	jmp short XR_WAIT
XRC:
	mov byte [XREPLY],'C'	; CRC please, once more
	jmp short XR_WAIT
XRFL:
	jmp XFAIL	; out of retries
XRSOH:
	cmp cx,[XLEN]	; a whole block?
	jnz short XRBAD	; short: bad
	mov ax,[XBUF+1]	; AL = number, AH = its complement
	not ah	; (complement back)
	cmp_d al,ah	; do they agree?
	jnz short XRBAD	; no: bad
	call XCHECK	; DX = CRC, AL = sum of the 128 data bytes
	cmp byte [CRCM],0x0	; which check?
	jz short XRS_SUM	; checksum mode
	cmp dh,[XBUF+131]	; CRC: high byte first
	jnz short XRBAD	; no: bad
	cmp dl,[XBUF+132]	; then low
	jnz short XRBAD	; no: bad
	jmp short XRS_GOOD	; CRC agrees
XRS_SUM:				; (src: XRS1)
	cmp al,[XBUF+131]	; checksum: one byte
	jnz short XRBAD	; no: bad
XRS_GOOD:				; (src: XRS2)
	mov byte [GOT],0x1	; a good block: no more 'C'
	mov byte [TRIES],0x0	; retries start again
	mov al,[XBUF+1]	; its number
	cmp al,[BLK]	; the one expected?
	jz short XRS_WRITE	; yes: keep it
	inc al		; the last block again: its ACK was lost
	cmp al,[BLK]	;   (BLK - 1; with BLK = 1 a block 0 too)
	jz short XRACK	; ACK it again, keep nothing
	jmp XFAIL	; out of sequence: give up
XRS_WRITE:				; (src: XRS3)
	mov dx,XBUF+3	; AH=1Ah set DTA: the 128 data bytes
	mov ah,0x1a
	int 21h	; DOS writes from XBUF+3
	mov cx,128	; AH=28h random block write: 128 byte records
	mov dx,XFCB
	mov ah,0x28	; AH=28h
	int 21h	; AL = 0: written
	or_d al,al	; all written?
	jz short XRS_NEXT	; yes
	jmp XFAIL	; disk full: give up
XRS_NEXT:				; (src: XRS4)
	inc byte [BLK]	; the next one (wraps 255 -> 0)
	mov ax,128	; 128 more bytes on the bottom line
	call XPROG	; "Receiving: n bytes"
XRACK:
	mov byte [XREPLY],ACK	; sent with the next wait
	jmp XR_WAIT	; ACK goes out with the next wait
XRBAD:
	call PURGE	; when the line is quiet: NAK
	inc byte [TRIES]	; one more failure
	cmp byte [TRIES],10	; more than 10?
	jna short XRBAD_NAK	; no: NAK it
	jmp XFAIL	; more than 10: give up
XRBAD_NAK:				; (src: XRBAD1)
	jmp XRNAK	; NAK goes out with the next wait
XREOT:
	mov bx,ACK*256+ACK	; send ACK (BH <> 0) ...
	xor_d cx,cx	; ... and receive nothing
	call XGET	; (RECV with CX = 0: send only)
	jmp XDONE	; "n bytes: done"
XRCAN:
	mov dx,RCANM	; "Cancelled by the other side": no CANs back
	jmp XEND	; close, say so

; =====================================================================
; XSEND - menu S: a file to the host by XMODEM
; ---------------------------------------------------------------------
; DOS calls: AH=0Fh open FCB, AH=1Ah set DTA, AH=27h random block
; read, AH=10h close (XDONE / XEND).  Exit: through XDONE, XEND, SHOW.
;
;   wait up to 60 s for the receiver's first byte: 'C' -> CRC, NAK ->
;   checksums, CAN -> cancelled; any other byte: wait again (60 s anew)
;   then per block: read 128 bytes (CX = what came; 0 -> EOT), pad
;   with ^Z, SOH n ~n data check; send; wait 10 s for the answer: ACK ->
;   next, CAN -> cancelled, anything else or nothing -> again, up to 10
;   sends in all; CTS off for ~2 s during a block -> XFAIL
;   EOT, until ACKed (10 tries)
; =====================================================================
XSEND:
	mov dx,SNDASK	; "Send (XMODEM) file: "
	mov di,XFCB	; into XFCB
	call ASKF	; CF=1: no name
	jc short XSX	; no name: nothing
	mov dx,XFCB	; AH=0Fh open FCB
	mov ah,0xf
	int 21h	; AL = 0 found
	or_d al,al	; AL = 0: found
	jz short XS_OPENED	; found
	mov dx,NFMSG	; "File not found"
	jmp SHOW	; wait for a key
XSX:
	ret	; back to the menu's caller
XS_OPENED:				; (src: XS0)
	mov bx,XFCB	; byte records, from 0
	call RECSZ1
	mov dx,XSMSG	; "Sending: ", ring flushed
	call XSTART
XS_WAITC:				; (src: XS1)
	xor_d bx,bx	; the receiver's 'C' or NAK, a minute
	mov cx,0x1	;   (send nothing first, take 1 byte)
	mov dx,6000	; 6000 x 10 ms
	call XGET	; one byte, up to 60 s
	jc short XSUSR	; a key: cancel
	jcxz short XSFL	; a minute of nothing: failed
	mov al,[XBUF]	; the byte
	mov byte [CRCM],0x1	; 'C': CRC-16
	cmp al,'C'	; 'C'?
	jz short XS_START	; yes: CRC
	mov byte [CRCM],0x0	; NAK: checksums
	cmp al,NAK	; NAK?
	jz short XS_START	; yes: checksums
	cmp al,CAN	; CAN: the receiver gave up
	jnz short XS_WAITC	; else wait again (no retry count)
	jmp short XRCAN	; ("Cancelled by the other side")
XSUSR:
	jmp XUSER	; a key: cancel
XSFL:
	jmp XFAIL	; no receiver: "Transfer failed"
XS_START:				; (src: XS2)
	mov byte [BLK],0x1	; the first block
XS_BLOCK:				; (src: XS3)
	mov dx,XBUF+3	; the next 128 bytes
	mov ah,0x1a	; AH=1Ah set DTA: the block's data
	int 21h	; DOS reads into XBUF+3
	mov cx,128	; 128 records of 1 byte
	mov dx,XFCB
	mov ah,0x27	; random block read
	int 21h	; CX = bytes read
	or_d cx,cx	; CX = bytes read (AL not looked at)
	jnz short XS_FILL	; some: a block
	jmp XSEOT	; none: the file is all sent
XS_FILL:				; (src: XS31)
	mov [XCNT],cx	; file bytes in this block
	mov di,XBUF+3	; DI = past them
	add_d di,cx
	neg cx		; CX = 128 - bytes
	add cx,128
	mov al,0x1a	; the last block filled with ^Z
	rep stosb	; pad
	mov byte [XBUF],SOH	; the header: SOH, number, complement
	nop		; MASM's padding (TERM.LST 0A74: C6 06 3CFB 01 90):
			;   XBUF is a forward EQU, sized before its type was known
	mov al,[BLK]	; block number
	mov [XBUF+1],al
	not al	; its complement
	mov [XBUF+2],al
	call XCHECK	; DX = CRC, AL = sum
	mov [XBUF+131],al	; checksum block: the sum ...
	mov word [XLEN],132	;   ... 132 bytes
	cmp byte [CRCM],0x0	; CRC wanted?
	jz short XS_TRY0	; no: as is
	mov [XBUF+131],dh	; CRC block: high, low ...
	mov [XBUF+132],dl
	mov word [XLEN],133	;   ... 133 bytes
XS_TRY0:				; (src: XS4)
	mov byte [TRIES],0x0	; this block's sends
XS_SENDBLK:				; (src: XS5)
	mov si,XBUF	; the block to the host
	mov cx,[XLEN]	; 132 / 133 bytes
	call SEND	; AL = 1: CTS stayed off
	or_d al,al
	jnz short XSFL1	; the line is dead: give up
	call XANS	; the answer, 10 s
	jc short XSUSR	; a key
	cmp al,ACK	; taken
	jz short XS_ACKED	; yes: next block
	cmp al,CAN	; the receiver gave up
	jnz short XS_RETRY	; no
	jmp XRCAN
XS_RETRY:				; (src: XS51)
	inc byte [TRIES]	; NAK, 'C', noise or nothing: again
	cmp byte [TRIES],10	; 10 sends in all
	jc short XS_SENDBLK	; again
XSFL1:
	jmp XFAIL
XS_ACKED:				; (src: XS6)
	inc byte [BLK]	; next block
	mov ax,[XCNT]	; file bytes (not the padding) on the line
	call XPROG	; "Sending: n bytes"
	jmp XS_BLOCK	; the next 128
XSEOT:
	mov byte [TRIES],0x0	; EOT until ACKed
XSE_SEND:				; (src: XSE1)
	mov si,EOTB	; one EOT (SEND's AL not looked at)
	mov cx,0x1
	call SEND	; to the host
	call XANS	; the answer, 10 s
	jnc short XSE_ANSWER	; no key
	jmp XUSER	; a key
XSE_ANSWER:				; (src: XSE11)
	cmp al,ACK	; done
	jz short XSE_DONE
	inc byte [TRIES]	; again, 10 in all
	cmp byte [TRIES],10
	jc short XSE_SEND	; again
	jmp XFAIL	; no ACK for the EOT
XSE_DONE:				; (src: XSE2)
	jmp XDONE	; "n bytes: done"

; ---------------------------------------------------------------------
; XSTART - the bottom line for a transfer.  Entry: DX = XRMSG / XSMSG.
; NBYTES and TRIES zeroed, the ring flushed (what came before the
; transfer is not a block).  Callers: XRECV, XSEND.
; ---------------------------------------------------------------------
XSTART:
	mov [XMSG],dx	; kept for XPROG / XDONE
	push dx
	call BOTTOM	; the bottom line, inverse
	pop dx
	call PUTS	; "Receiving: " / "Sending: "
	call BOTEND	; normal, rest blank
	mov word [NBYTES],0x0	; nothing moved yet
	mov word [NBYTES+2],0x0	; (high word)
	mov byte [TRIES],0x0	; no retries yet
	mov ah,TZ_FLUSH	; FLUSH what came before
	jmp Z80	; empty the ring

; ---------------------------------------------------------------------
; XPROG - AX more bytes moved; their count on the bottom line
; ("Receiving: 1408 bytes").  Callers: XRECV, XSEND.
; ---------------------------------------------------------------------
XPROG:
	add [NBYTES],ax	; 32-bit total
	adc word [NBYTES+2],byte 0x0
	call BOTTOM	; redraw the line
	mov dx,[XMSG]	; caption, then the count
	call PUTNB	; "Receiving: n"
	mov dx,BYTESM	; " bytes"
	call PUTS
	jmp BOTEND	; normal, rest blank

; ---------------------------------------------------------------------
; XANS - AL = the answer to what was sent (0 if none in 10 s); CF=1 a
; key.  Corrupts BX, CX, DX, DI.  Callers: XSEND.
; ---------------------------------------------------------------------
XANS:
	xor_d bx,bx	; send nothing
	mov cx,0x1	; one byte
	mov dx,1000	; within 10 s
	mov di,ANSB	; into ANSB
	call XGETDI	; RECV
	jc short XANS_RET	; a key: CF=1
	mov al,0x0	; nothing: AL = 0
	jcxz short XANS_RET	; none came
	mov al,[ANSB]	; the byte
XANS_RET:				; (src: XANS1)
	ret

; ---------------------------------------------------------------------
; XGET / XGETDI - TERMZ80's RECV.  Entry: BH <> 0: send BL first; CX =
; bytes wanted, to XBUF (XGET) or DI (XGETDI); DX x 10 ms for the first
; byte (1 s for each other).  Exit: CX = bytes received; CF=1 if a key
; was pressed (it is taken).  Corrupts AX, DI.
; ---------------------------------------------------------------------
XGET:
	mov di,XBUF	; the block buffer
XGETDI:
	add di,[BASE]	; linear
	mov ah,TZ_RECV	; RECV
	call Z80	; AL = 1: a key
	cmp al,0x1	; CF=1 when AL = 0 ...
	cmc		; ... so CF=1 now when AL = 1
	ret

; ---------------------------------------------------------------------
; XCHECK - the block's data: DX = CRC-16, AL = checksum (TERMZ80 CRC
; on XBUF+3, 128 bytes).  Callers: XRSOH, XS_FILL.
; ---------------------------------------------------------------------
XCHECK:
	mov si,XBUF+3	; the 128 data bytes
	mov cx,128	; 128 bytes
	add si,[BASE]	; linear
	mov ah,TZ_CRC	; CRC
	jmp Z80	; DX, AL back to the caller

; ---------------------------------------------------------------------
; PURGE - wait till nothing comes for 0.3 s (the rest of a bad block),
; so the NAK is not lost in it.  A key pressed meanwhile is taken and
; ignored.  Callers: XRBAD.
; ---------------------------------------------------------------------
PURGE:
	mov cx,133	; take anything, up to a block
	mov dx,30	; 0.3 s for the first byte
	xor_d bx,bx	; send nothing
	call XGET	; RECV
	jcxz short PURGE_RET	; quiet: done
	jmp short PURGE	; something came: again
PURGE_RET:				; (src: PURGE1)
	ret

; ---------------------------------------------------------------------
; SEND - CX bytes at SI to the channel; AL = 1 if CTS stayed off.
; TERMZ80's SEND (it lets a held host go first).  Callers: XSEND,
; XCAN, MENU (Ctrl-A).
; ---------------------------------------------------------------------
SEND:
	add si,[BASE]	; linear
	mov ah,TZ_SEND	; SEND
	jmp Z80	; AL back to the caller

; ---------------------------------------------------------------------
; XDONE - the transfer ended well: the file closed, "n bytes: done".
; XUSER / XFAIL - give up: three CANs to the other side, then XEND.
; XEND - the file closed (a partial file is kept), the message DX.
; DOS calls: AH=10h close FCB.
; ---------------------------------------------------------------------
XDONE:
	mov dx,XFCB	; AH=10h close FCB
	mov ah,0x10
	int 21h	; directory entry written
	call BOTTOM
	mov dx,[XMSG]	; caption, count ...
	call PUTNB	; "Receiving: n" / "Sending: n"
	mov dx,DONEM	; ... " bytes: done - a key"
	jmp short SHOW1	; then wait for a key
	nop		; MASM's padding (TERM.LST 0BB4: EB 22 90)
XUSER:
	mov dx,CANM	; "Cancelled"
	jmp short XCAN
XFAIL:
	mov dx,FAILM	; "Transfer failed"
XCAN:
	push dx	; keep the message
	mov si,CANS	; CAN CAN CAN: tell the other side
	mov cx,0x3	; three of them
	call SEND	; (AL ignored)
	pop dx
XEND:
	push dx
	mov dx,XFCB	; AH=10h close FCB: what came is kept
	mov ah,0x10
	int 21h
	pop dx	; the message
;
; SHOW: the message DX on the bottom line until a key is pressed
;
; ---------------------------------------------------------------------
; SHOW / SHOW1 - message DX (SHOW1: the bottom line already begun), " -
; a key", wait for a key (AH=07h, taken).  Callers: LOGSW, LOGWR,
; XRECV, XSEND, XDONE, XEND.
; ---------------------------------------------------------------------
SHOW:
	push dx
	call BOTTOM	; the bottom line, inverse
	pop dx
SHOW1:
	call PUTS	; the message
	mov dx,KEYM	; " - a key"
	call PUTS
	call BOTEND	; normal, rest blank
	mov ah,0x7	; AH=07h direct console input
	int 21h	; wait (the key is dropped)
	ret

; =====================================================================
;                    HELPERS
; =====================================================================

; ---------------------------------------------------------------------
; ASKF - a file name from the keyboard into an FCB
; Entry: DX = the question, DI = the FCB.  Exit: CF=0 the FCB holds a
; name; CF=1 none given (ESC, an empty name, or a bad drive).
; Corrupts AX, BX, DX, SI, DI.  DOS calls: AH=07h input, AH=02h display,
; AH=09h, AH=29h parse filename (AL = 0: leading blanks skipped but no
; other separator - MSDOS.LST MAKEFCB; drive / name / extension all from
; the text, upper-cased).
; Up to 28 printable characters; BS and DEL rub out; others ignored.
; ---------------------------------------------------------------------
ASKF:
	push di		; the FCB, for the parse
	push dx
	call BOTTOM	; the question on the bottom line
	pop dx
	call PUTS	; the question
	call BOTEND	; normal, rest blank
	xor_d bx,bx	; BX = characters typed
ASK_KEY:				; (src: ASK1)
	mov ah,0x7	; AH=07h direct console input
	int 21h	; AL = key
	cmp al,0xd	; CR: done
	jz short ASK_ENTER
	cmp al,0x1b	; ESC: never mind
	jz short ASKNO
	cmp al,0x8	; BS or DEL: rub out
	jz short ASK_RUBOUT
	cmp al,0x7f	; (DEL)
	jz short ASK_RUBOUT
	cmp al,' '	; other controls: ignored
	jc short ASK_KEY
	cmp bx,byte 28	; full: ignored
	jnc short ASK_KEY
	mov [bx+LINE],al	; kept ...
	inc bx
	mov_d dl,al	; ... and shown (AH=02h display)
	mov ah,0x2
	int 21h	; echo it
	jmp short ASK_KEY	; next key
ASK_RUBOUT:				; (src: ASK3)
	or_d bx,bx	; nothing to rub out?
	jz short ASK_KEY	; none typed
	dec bx		; one fewer
	mov dx,BSSTR	; back, blank, back
	call PUTS	; on the screen
	jmp short ASK_KEY	; next key
ASK_ENTER:				; (src: ASK4)
	mov byte [bx+LINE],0xd	; CR-ended for the parse
	pop di		; ES:DI = the FCB
	mov si,LINE	; DS:SI = the text
	mov ax,0x2900	; parse the name
	int 21h	; AL = 0 ok, 1 wild cards, FFh bad drive
	cmp al,0xff	; a bad drive letter
	jz short ASKNO_CF
	cmp byte [di+0x1],' '	; no name at all
	jz short ASKNO_CF
	clc		; CF=0: a name
	ret
ASKNO:
	pop di		; (the FCB pointer, unused)
ASKNO_CF:				; (src: ASKNO1)
	stc		; CF=1: none
	ret

; ---------------------------------------------------------------------
; RECSZ1 - the FCB at BX for random block I/O, records of 1 byte, from
; record 0.  Then AH=27h / 28h with CX = a byte count, and DOS moves
; the random record on by what was moved.  Callers: LOGSW, XRECV, XSEND.
; ---------------------------------------------------------------------
RECSZ1:
	mov word [bx+FCB_RECSIZ],0x1	; record size 1 (CREATE/OPEN set 128)
	mov word [bx+FCB_RR],0x0	; random record 0 (bytes 33-34 ...
	mov word [bx+FCB_RR+2],0x0	;   ... and 35-36)
	ret

; ---------------------------------------------------------------------
; BOTTOM / BOTEND / PUTS - to the bottom line, inverse / back to normal
; and the rest blanked / any "$" string.  DX = string (PUTS); AH=09h.
; Corrupt AH, DX.  These go straight to the terminal through DOS, so
; TERMZ80's shadow knows nothing of them: DRAW repairs row 23 after.
; ---------------------------------------------------------------------
BOTTOM:
	mov dx,BOTL	; ESC Y 23,0  ESC L
	jmp short PUTS	; print it
BOTEND:
	mov dx,BOTE	; ESC M  ESC K
PUTS:
	mov ah,0x9	; AH=09h print string
	int 21h
	ret

; ---------------------------------------------------------------------
; PUTNB - DX (a string), then NBYTES in decimal (up to 655359: above
; that the DIV overflows - unreachable, a disk holds 176 KB of files).
; Corrupts AX, BX, DX.  Callers: XPROG, XDONE.
; ---------------------------------------------------------------------
PUTNB:
	call PUTS	; the caption
	mov ax,[NBYTES]	; DX:AX = the 32-bit count
	mov dx,[NBYTES+2]	; (high word)
	mov bx,10
	div bx		; DX:AX / 10 (NBYTES < 655360)
	push dx		; the last digit
	or_d ax,ax	; more digits?
	jz short PUTNB_LAST	; no: just the one
	call PUTNUM	; the quotient (now 16 bits)
PUTNB_LAST:				; (src: PUTNB1)
	pop ax		; the last digit
	jmp short PUTNUM_OUT	; print it
; ---------------------------------------------------------------------
; PUTNUM - AX in decimal (recursive: highest digit first).  AH=02h.
; Corrupts AX, BX, DX.  Callers: MENU (LOST), PUTNB.
; ---------------------------------------------------------------------
PUTNUM:
	xor_d dx,dx	; DX:AX / 10
	mov bx,10
	div bx	; AX = quotient, DX = this digit
	push dx		; this digit, after the higher ones
	or_d ax,ax	; more?
	jz short PUTNUM_DIGIT	; no
	call PUTNUM	; the higher ones first
PUTNUM_DIGIT:				; (src: PUTN1)
	pop ax		; this digit
PUTNUM_OUT:				; (src: PUTN2)
	mov_d dl,al	; AH=02h display: '0' + digit
	add dl,'0'
	mov ah,0x2	; AH=02h display
	int 21h
	ret

; ---------------------------------------------------------------------
; COMMA - after a field: CF=1 if the line ends there; otherwise past the
; comma, ZF=1 if the next field is empty too (another comma, or the
; end), AL = its first character.  Anything but a comma: BAD.
; Callers: PAR, DBITS, SBITS.
; ---------------------------------------------------------------------
COMMA:
	call BLANKS	; the end?
	stc		; (STC leaves ZF alone)
	jz short CMX	; yes: CF=1
	cmp al,','	; must be a comma
	jnz short CMBAD	; not a comma: the usage
	inc si		; past it
	call BLANKS	; the field's first character
	cmp al,','	; ",,": empty field, ZF=1
	jz short CMX
	or_d al,al	; ",<end>": empty too; CF=0 either way
CMX:
	ret
CMBAD:
	jmp BAD		; junk between the fields

; ---------------------------------------------------------------------
; BLANKS - past spaces and tabs; AL = the next character (SI on it),
; ZF=1 at the end (the 0 UPX put).  Callers: the whole parse.
; ---------------------------------------------------------------------
BLANKS:
	lodsb	; next character
	cmp al,' '	; space
	jz short BLANKS	; skip
	cmp al,0x9	; tab
	jz short BLANKS	; skip
	dec si		; back on the character
	or_d al,al	; ZF=1: the 0
	ret

; ---------------------------------------------------------------------
; GETW - the letters, digits and points at SI to DI, padded with spaces
; to CX characters; ZF=0 if there are none or more than CX.  Corrupts
; AL, BX, CX; SI past the word.  Callers: PORT_PARSE, PORT_SETTINGS.
; ---------------------------------------------------------------------
GETW:
	mov_d bx,cx	; BX = the room, to tell "none"
GETW_NEXT:				; (src: GETW1)
	mov al,[si]	; a word character?
	cmp al,'.'	; '.' (134.5)
	jz short GETW_TAKE
	cmp al,'0'	; '0'-'9'
	jc short GETW_END
	cmp al,'9'
	jna short GETW_TAKE	; a digit
	cmp al,'A'	; 'A'-'Z'
	jc short GETW_END
	cmp al,'Z'
	ja short GETW_END	; not a letter: the word ends
GETW_TAKE:				; (src: GETW2)
	jcxz short GETWX	; no room left: too long
	stosb		; kept
	inc si
	dec cx	; room - 1
	jmp short GETW_NEXT
GETW_END:				; (src: GETW3)
	cmp_d cx,bx	; nothing taken?
	jz short GETWX	; ZF=0 via GETWX
	mov al,' '	; pad the rest
	rep stosb
	cmp_d al,al	; ZF=1: a word
	ret
GETWX:
	or_d sp,sp	; ZF=0 (SP is never 0)
	ret

; ---------------------------------------------------------------------
; SAME6 - ZF=1 if TOKEN is the 6 characters at BX.  Corrupts CX, DI.
; Callers: BAUD_CMP, BAUD_ABBR_CMP.
; ---------------------------------------------------------------------
SAME6:
	push si
	mov si,TOKEN	; TOKEN against
	mov_d di,bx	;   the entry at BX
	mov cx,0x6	; 6 characters
	repe cmpsb
	pop si
	ret	; ZF = equal

; ---- the stack: 64 words, 0CFBh-0D7Ah ----
	times 64 dw 0
STKTOP:

; =====================================================================
; Z80IMG - the Z80 part (TERMZ80.INC), and the buffers that replace it
; ---------------------------------------------------------------------
; z86.py termz80() builds this as a 16-byte header and the code.  Trap
; 1Ch (BP = linear Z80IMG) reads the length, compares the 7 words with
; Z86.SYS's own CPMSYM (14 bytes) and copies the code to ENDBIOS.  Once
; copied, this region is dead and the buffers below go over it (and on
; past the end of the file).  A mismatch in any byte of the 7 words
; gives "TERM.COM does not match Z86.SYS".  The values are this build's
; (Z86.SYS.sym) - the same as CPM.COM's header (volume 6).
; =====================================================================
Z80IMG:
SCRBUF equ Z80IMG	; 0D7Bh the host's screen, 24 x 80 at most
RINGBUF equ SCRBUF+ROWS*80	; 14FBh the receive ring, 2048
LOGBUF equ RINGBUF+RINGSZ	; 1CFBh the log buffer, 8192
XBUF equ LOGBUF+LOGSZ	; 3CFBh an XMODEM block (133 bytes)
Z80_LEN:
	dw Z80_CODE_END-Z80_CODE	; 0D8Ch = 3468 bytes of code to copy
Z80_SYMS:
	dw NEXT		; D83Bh  must equal Z86.SYS NEXT
	dw JPHL		; EB4Dh  must equal Z86.SYS JPHL
	dw PEEKEY	; EBE3h  must equal Z86.SYS PEEKEY
	dw GETKEY	; EC00h  must equal Z86.SYS GETKEY
	dw CONOUT	; EC0Eh  must equal Z86.SYS CONOUT
	dw DCSP		; F12Ah  must equal Z86.SYS DCSP
	dw ENDBIOS	; F12Ch  must equal Z86.SYS ENDBIOS (the copy target)

; The code, assembled to run at ENDBIOS (F12Ch-FEB7h): TERMZ80.BIN,
; narrated in asm/termz80.asm (volume 10).  File offset 0C8Bh to the
; end of TERM.COM; nothing follows it.  (Path relative to DISASM/,
; where tools/roundtrip.sh assembles.)
Z80_CODE:
	incbin "bin/TERMZ80.BIN"
Z80_CODE_END:
