;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  7/10
;  EDIT.COM - the full-screen text editor (8086, 4 653 bytes, .COM at 0100h)
;==============================================================================
;
;  ROLE.  `EDIT name.ext [/80]`: a full-screen editor for DOS itself,
;  written in 8086 code, with the WordStar-style keys and the status line
;  of TMX CP/M's EDIT (cpm80ds/progs/edit.asm), so that the two work
;  alike.  The whole file lives in memory in a gap buffer; the screen is
;  a Terminal 3000 (VT52 dialect) reached through the PC ROM BIOS calls
;  INT 10h (teletype) and INT 16h (keyboard).  Files go through DOS 1.25
;  FCB calls only.
;
;  WHERE IT SITS IN THE RUN CHAIN
;     COMMAND.COM loads EDIT.COM at PSP:0100h (CS = DS = ES = SS = PSP)
;       ->  START: options, memory, file read, INT 24h hook, full redraw
;       ->  MAIN loop: FIXSCR / DRAW / STATUS / PLACE / FLUSH, GETKEY,
;           DOKEY (through CTAB) ... until ^KX, ^KD or ^KQ -> INT 20h.
;     EDIT contains NO trap (0Fh nn).  INT 10h -> IO.SYS stub TRAP 10h
;     (TRAP_INT10, iosys.asm) -> T_I10 in z86sys.asm; INT 16h -> IO.SYS
;     stub TRAP 16h (TRAP_INT16) -> T_I16 in z86sys.asm.  Each stub
;     ends in RETF 2, so the flags set in Z80 code reach EDIT.  AH=0Eh
;     sends AL to the terminal through CONOUT, AH=1 peeks the key queue
;     (ZF), AH=0 waits for a key.  Because keys come from INT 16h and not
;     from DOS, ^C, ^S and ^P reach the editor instead of DOS's console.
;
;  THE GAP BUFFER (state words at SIG+6, read by test_edit.py)
;       BUFS ........ GAPS ======== GAPE ........ TEND
;       text before    the gap       text after
;       the cursor     (free room)   the cursor
;   - BUFS <= GAPS <= GAPE <= TEND always; the cursor IS the gap.  The
;     document is BUFS..GAPS-1 followed by GAPE..TEND-1.  GAPS = GAPE
;     means memory full (INSCH / SPLIT say so).
;   - Lines end in LF inside (no CR); CR LF and a final ^Z only on disk.
;   - Addresses before the gap stay fixed while the cursor moves forward
;     and are the only ones LSOF may scan backward over (AX <= GAPS).
;     An address in the gap is meaningless.
;   - TOP (the top screen line) and CLS_ (the cursor's line) are line
;     starts before the gap; LINE / TOPLN are 1-based line numbers;
;     CROW = LINE - TOPLN is the cursor's text row (screen row - 1),
;     0 <= CROW < NR; LEFT <= CCOL < LEFT + W.  A command may break the
;     TOP / CROW / CCOL part (TOP can even end up in the gap after a move
;     backward); FIXSCR restores all of them before anything is drawn.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/edit_findings.md)
;   - The screen engine has no screen copy: a byte per text row in DIRTY
;     holds the first column to send again (FFh = clean, 0 = all of it).
;     DRAW finds the first and last marks with two REPE SCASB, walks the
;     lines only from the top (if a mark is above the cursor's row) or
;     from the cursor's own line down to the last mark, checks for a key
;     before every row and gives up (CF=1) when one is waiting; the
;     marks left behind finish the job on a later pass.
;   - One-line vertical moves scroll the terminal: LF on the bottom row
;     (SCRUP) or ESC I on the status row (SCRDN).  The whole screen
;     scrolls, status line included, so the marks are shifted with the
;     rows, the row brought in is marked whole and the status line is
;     sent again in full.  While FULL is set (a whole redraw is pending)
;     no scroll is sent.
;   - The status line is a set of shadow fields (SHMOD, SHLINE, SHCOL,
;     SHMSG): only a field that differs is sent.  The column of the `*`
;     is measured from the output buffer pointer (SF1), not counted.
;   - The INT 24h hook (CRIT) only sets ERRF and chains to DOS's own
;     handler; after a save AFTDOS redraws everything if DOS printed its
;     "Abort, Retry, Ignore?".  The old vector is read straight from
;     0000:0090h: DOS 1.25 has no AH=35h get-vector call.
;   - FIXED 2026-11-08 (this build): an arrow key at a ^K / ^Q prefix or
;     at "Find:" inserted its letter A-D into the text; ^Y answered Y at
;     "Abandon changes (Y/N)?" (losing the work); CLOSE and the last RENAME
;     of a save were not checked ("Saved" after a failure).  Tested:
;     test_edit.py group 7 (fails on the old EDIT, passes now).
;   - Still as designed / not fixed: every CR is dropped on reading, not
;     only those before LF (EDIT keeps lines as LF); Abort at DOS's
;     question during a save ends EDIT (DOS's ABORT) with name.$$$ left.
;   - Two NOPs (INVON / INVOFF) are MASM's padding of a forward JMP that
;     turned out short; the stack starts at an odd address (243Dh).
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/EDIT.COM with
;  `nasm -O0 -f bin` (tools/roundtrip.sh edit).  Every label address
;  agrees with the MASM listing ../symbols/x86/EDIT.LST.  Behaviour was
;  checked by project/MSDOS/poc/test_edit.py on the emulated FDD3000
;  (fdd86.py): after every step the terminal model's screen is compared
;  with the editor's own gap buffer (read through the EDIT86 signature)
;  and the text and cursor with a Python model of the keys; it covers
;  every key, scrolling (exactly one terminal scroll per one-line move),
;  400 random keys, find, help, abandon, saving (.BAK, a new file, a full
;  disk, a write-protected disk with Retry), memory full, usage, /80.
;  REAL HARDWARE (notes/hardware_run.md): on 2026-11-07 the emulator-
;  written disk booted on a real FDD3000 with TC2048 and TC2068
;  terminals and EDIT worked on it.  The VT52 codes,
;  the row marks, the terminal scrolls and the last-column rule are
;  thereby confirmed against a real Terminal-3000-family terminal (one
;  machine, no fault report, no step-by-step log).  The per-key timings
;  quoted below (0.03-0.07 s a key, ~1 s a page) are emulator figures
;  at an assumed 4 MHz; no timing was taken on the machine.
;
;  FILE:    EDIT.COM, 4 720 bytes (2026-11-08 build; the shipped one was 4 653)
;  MD5:     a3ca407746916d8b2891404f09a0a178
;  SHA256:  15afaccbe6c7e1e8d2b19fbd1ba0ae8e2fcd2dc78dbef244f183c3ef08e670f5
;  SOURCE:  project/MSDOS/poc/EDIT.ASM (MASM 1.10 + LINK 2.00 + EXE2BIN),
;           listing symbols/x86/EDIT.LST
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  Keys and
;  status line after TMX CP/M's EDIT; terminal codes read from the
;  Terminal 3000 ROM.
;==============================================================================
;
;  ASSEMBLER NOTES.  NASM, `-O0 -f bin`: nothing is ever re-sized, so the
;  explicit `short`, `byte` and `word` keywords fix every encoding.
;  The `_d` macros below (mov_d, add_d, xor_d ...) are register-to-
;  register instructions in MASM's encoding, with the direction bit set
;  (`xor_d bp,bp` = 33 ED); the operation is the plain mnemonic's.  NASM
;  would emit the other encoding (31 ED).  TRAP is defined for symmetry
;  with the other 8086 volumes but EDIT uses none.

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
	org	0100h
bits 16

; =====================================================================
;                    CHARACTERS AND SIZES (the author's)
; =====================================================================
TAB		equ	9
LF		equ	10
CR		equ	13
CTLZ		equ	26		; end of a text file on disk
KESC		equ	27		; ESC, as a key and as the VT52 lead-in
NRMAX		equ	24		; text rows at most (DIRTY's size)
LMAX		equ	1024		; columns of a line that can be shown
FMAX		equ	16		; longest search string
OBSZ		equ	1024		; output to the terminal, sent at once
WBSZ		equ	2048		; the file is written in blocks of this
LNUMC		equ	23		; status line: column of the line number,
CNUMC		equ	33		;   of the column number,
MSGC		equ	39		;   of the message

; ---- the buffers after the program, from BUFFERS (132Dh) on --------
;   BUFFERS+0000h  OBUF  1024  output to the terminal      (132Dh)
;   BUFFERS+0400h  EBUF  1040  one row, tabs expanded       (172Dh)
;   BUFFERS+0810h  WBUF  2048  the file being written       (1B3Dh)
;   BUFFERS+1010h  stack  256  SP starts at its top          (233Dh)
;   BUFFERS+1110h  text: BUFS = 243Dh up to TEND             (243Dh)
OBOFF		equ	0
EBOFF		equ	OBOFF+OBSZ	; a row with its tabs expanded
WBOFF		equ	EBOFF+LMAX+16	; (+16: a tab may run 7 past the limit)
STKOFF		equ	WBOFF+WBSZ+256	; the stack's top
TXOFF		equ	STKOFF		; then the text

; ---- names added by this disassembly (dict/edit.md) -----------------
; Program Segment Prefix fields (DOS 1.25, MSDOS.LST "[2] = first
; unavailable segment"; FCB 1 at 5Ch; command tail at 80h)
PSP_MEMTOP	equ	02h		; first segment past our memory
PSP_FCB1	equ	5Ch		; FCB parsed from the first argument
PSP_TAILLEN	equ	80h		; command tail: length byte
PSP_TAIL	equ	81h		;   and its text (ends in CR)
INT24_VEC	equ	24h*4		; 0000:0090h, the critical-error vector

; FCB fields (DOS 1.25 37-byte FCB; the rename form in RFCB)
FCB_NAME	equ	1		; 8 name bytes
FCB_EXT		equ	9		; 3 extension bytes
FCB_RECSZ	equ	14		; record size (word): EDIT sets 1
FCB_SIZE	equ	16		; file size, low word
FCB_SIZEHI	equ	18		;   high word
FCB_RANDOM	equ	33		; random record, low word
FCB_RANDOMHI	equ	35		;   high word
REN_NEW		equ	17		; rename FCB: the new name (16 = its drive)
REN_NEWEXT	equ	25		;   the new extension
NAMELEN		equ	11		; 8 + 3, blank-padded
FCBHEAD		equ	12		; drive byte + name + extension

; INT 21h functions (AH), named after MS-DOS 1.25's
DOS_PRTSTR	equ	09h		; print a $-terminated string at DX
DOS_OPEN	equ	0Fh		; open FCB
DOS_CLOSE	equ	10h		; close FCB
DOS_DELETE	equ	13h		; delete FCB (wildcards allowed)
DOS_MAKE	equ	16h		; create FCB
DOS_RENAME	equ	17h		; rename FCB (old name at 1, new at 17)
DOS_CURDSK	equ	19h		; AL = current drive, 0 = A
DOS_SETDTA	equ	1Ah		; disk transfer address = DX
DOS_SETVEC	equ	25h		; vector AL = DS:DX
DOS_BLKREAD	equ	27h		; random block read, CX records
DOS_BLKWRITE	equ	28h		; random block write, CX records

; PC ROM BIOS functions (served by Z86.SYS T_I10 / T_I16)
VID_TTY		equ	0Eh		; INT 10h: AL to the terminal
KBD_READ	equ	00h		; INT 16h: wait, AL = key
KBD_PEEK	equ	01h		; INT 16h: ZF=0 if a key is waiting

; Terminal 3000 (VT52) codes, each sent after KESC
VT_CUP		equ	'Y'		; ESC Y row+32 col+32: cursor address
VT_BIAS		equ	32		;   the bias on row and column
VT_HOME		equ	'H'		; ESC H: cursor home
VT_EOS		equ	'J'		; ESC J: clear to the end of the screen
VT_EOL		equ	'K'		; ESC K: clear to the end of the line
VT_INVON	equ	'L'		; ESC L: inverse on (Terminal 3000)
VT_INVOFF	equ	'M'		; ESC M: inverse off
VT_RLF		equ	'I'		; ESC I: cursor up; on row 0 scroll down

; keys that are not control codes of CTAB
KEY_DEL		equ	7Fh		; DEL: delete left (as ^H)
KEY_BS		equ	08h		; ^H, accepted by PROMPT
KEY_CTLU	equ	'U'-40h		; ^U: give up a prompt
ARROW_UP	equ	'A'		; ESC A .. ESC D: the terminal's arrows
ARROW_DOWN	equ	'B'
ARROW_RIGHT	equ	'C'
ARROW_LEFT	equ	'D'
STNAMEW		equ	17		; inverse name field " A:NAME.EXT*"

; =====================================================================
; BEGIN - .COM entry: over the signature and the state to START
; =====================================================================
BEGIN:
	jmp START		; near JMP (E9): the state follows at 0103h

; =====================================================================
; SIG and the editor's state (0103h)
; ---------------------------------------------------------------------
; test_edit.py finds "EDIT86" in the 8086 memory and unpacks the 13
; words and the byte after it (BUFS .. W, MODIF) to rebuild the text
; and check the screen against it; the order is therefore fixed.  The
; segment base is the signature's address - 103h.
; =====================================================================
SIG:
	db "EDIT86"		; the test's handle (the source names test_fdd86.py)
BUFS:
	dw 0			; start of the text (= BUFFERS+TXOFF)
GAPS:
	dw 0			; the cursor: start of the gap
GAPE:
	dw 0			; end of the gap: first byte after the cursor
TEND:
	dw 0			; end of the text = end of memory (fixed)
TOP:
	dw 0			; start of the top text line (before the gap)
TOPLN:
	dw 1			; its line number (1-based)
LINE:
	dw 1			; the cursor's line number
LEFT:
	dw 0			; first column shown (a multiple of 8)
CCOL:
	dw 0			; the cursor's column, tabs expanded (0-based)
CROW:
	dw 0			; its text row (screen row - 1)
COLS:
	dw 64			; terminal columns (/nn); stored, never read
NR:
	dw 23			; text rows (screen rows 1-23; row 0 = status)
W:
	dw 63			; columns used: COLS - 1, never the last one
MODIF:
	db 0			; 1: changed since read or saved

; ---- working state (not read by the test) ----
CLS_:
	dw 0			; start of the cursor's line (FIXSCR)
GOAL:
	dw 0			; column wanted by up and down
VERT:
	db 0			; 1: this key moved up or down (GOAL kept)
MARKF:
	db 0			; 1: FIXSCR marks the cursor's row from the cursor
FULL:
	db 0			; 1: every row is to be sent (no terminal scroll)
STFULL:
	db 0			; 1: the whole status line is to be sent
MSG:
	dw 0			; message for the status line, 0 = none
SHMSG:
	dw 0			; shadows - what the terminal shows: message,
SHLINE:
	dw 0			;   line number,
SHCOL:
	dw 0			;   column (1-based),
SHMOD:
	db 0			;   changed mark
MODC:
	db 0			; screen column of the changed mark
DRVL:
	db "A"			; drive letter for the status line
OPTR:
	dw BUFFERS+OBOFF	; next free byte of OBUF
DRROW:
	dw 0			; DRAW: the row being drawn,
DRLAST:
	dw 0			;   the last one marked,
DRP:
	dw 0			;   start of the next row's line,
DREOT:
	db 0			;   1: past the end of the text
P1:
	dw 0			; ROWOUT: the line in up to two pieces (the
N1:
	dw 0			;   cursor's line is split by the gap):
P2:
	dw 0			;   P1/N1 address/length, then P2/N2
N2:
	dw 0
TLEN:
	dw 0			; PROMPT: characters typed into TBUF
FLEN:
	dw 0			; length of the search string in FSTR
FC1:
	db 0			;   its first letter, upper case,
FC2:
	db 0			;   and lower case (= FC1 if not a letter)
FP1:
	dw 0			;   where each occurs next (FFFFh: nowhere)
FP2:
	dw 0
WCNT:
	dw 0			; bytes in the write buffer
DFULL:
	db 0			; 1: a block write failed (disk full)
ERRF:
	db 0			; 1: DOS asked about a disk error (INT 24h)
OLD24:
	dw 0,0			; DOS's INT 24h vector, offset:segment

; DIRTY - one mark per text row: FFh = the row is right on the
; terminal; otherwise the first screen column (0..W-1, relative to
; LEFT) from which it must be sent again; 0 = the whole row.
DIRTY:
	times NRMAX db 0FFH

TBUF:
	times FMAX db 0		; PROMPT: the characters typed
FSTR:
	times FMAX db 0		; the search string, upper case

; ---- FCBs (37 bytes: 0 drive, 1-8 name, 9-11 ext, 12 block,
;      14 record size, 16 size, 20 date, 32 record, 33 random) ----
FCB:
	times 37 db 0		; name.ext, from PSP_FCB1
TFCB:
	times 37 db 0		; name.$$$, the file being written
RFCB:
	times 37 db 0		; rename / delete: old name at 1, new at 17

; ---- messages: $-terminated for DOS_PRTSTR, 0-terminated for PUTS ----
USEMSG:
	db "EDIT 1.0 - full screen text editor",13,10
	db "Usage: EDIT name.ext [/80]",13,10,"$"
BIGMSG:
	db "File too big for memory",13,10,"$"
MKPRE:
	db "^K",0		; prefix prompts on the status line
MQPRE:
	db "^Q",0
MNEW:
	db "New file",0		; LOADF: the open failed
MSAVED:
	db "Saved",0
MNOTF:
	db "Not found",0
MMEM:
	db "Memory full",0	; the gap is empty
MDFULL:
	db "Disk full: not saved",0
MREN:
	db "Not renamed: text in .$$$",0	; SAVE's last rename failed (2026-11-08)
MDIR:
	db "Directory full",0	; DOS_MAKE failed
MABAN:
	db "Abandon changes (Y/N)? ",0	; 23 characters: ends at column 62
MFIND:
	db "Find: ",0		; 6 characters: input from MSGC+6
MLINE:
	db " Line ",0
MCOL:
	db " Col ",0
MHELP:				; ^J: the key list, sent as it stands
	db "EDIT 1.0   (^ = CTRL)",13,10,13,10
	db "Cursor  ^E up   ^X down   ^S left   ^D right   (or arrows)",13,10
	db "        ^A word left      ^F word right",13,10
	db "        ^R page up        ^C page down",13,10
	db "        ^QS line start    ^QD line end",13,10
	db "        ^QR file start    ^QC file end",13,10
	db "Delete  DEL left   ^G right   ^T word   ^Y line",13,10
	db "        ^QY to the end of the line",13,10
	db "Insert  RETURN new line   ^N split line   TAB",13,10
	db "Find    ^QF find          ^L find again",13,10
	db "File    ^KS save          ^KX save and exit",13,10
	db "        ^KQ quit",13,10,13,10
	db "Press a key",0

; =====================================================================
; CTAB - control code -> command (32 words, JMP [BX+CTAB] in DOKEY)
; ---------------------------------------------------------------------
; WordStar's cursor diamond (^E ^S ^D ^X), its ^A/^F word moves, ^R/^C
; pages, ^G/^T/^Y deletes, and the ^K (file) and ^Q (quick) prefixes,
; whose second key PREFIX folds to a capital letter.  DEL (7Fh) is
; caught before the table (DELB); 20h-FFh are inserted (INSCH).
;
;   00 ^@  -          08 ^H  DELB  del left  10 ^P  -          18 ^X  DOWN
;   01 ^A  WORDL      09 ^I  TABK  tab       11 ^Q  QPRE       19 ^Y  DELLN
;   02 ^B  -          0A ^J  HELP            12 ^R  PGUP       1A ^Z  -
;   03 ^C  PGDN       0B ^K  KPRE            13 ^S  LEFTK      1B ESC ESCK
;   04 ^D  RIGHT      0C ^L  FNEXT  again    14 ^T  DELWD      1C-1F  -
;   05 ^E  UP         0D ^M  NEWLN  RETURN   15 ^U  -
;   06 ^F  WORDR      0E ^N  SPLIT           16 ^V  -
;   07 ^G  DELF       0F ^O  -               17 ^W  -
;   ^K then S save, X or D save and exit, Q quit (asks if changed)
;   ^Q then S line start, D line end, R file start, C file end,
;          F find, Y delete to the end of the line
;   ESC then A up, B down, C right, D left (the terminal's arrow keys)
; =====================================================================
CTAB:
	dw NOKEY,WORDL,NOKEY,PGDN	; ^@ ^A ^B ^C
	dw RIGHT,UP,WORDR,DELF		; ^D ^E ^F ^G
	dw DELB,TABK,HELP,KPRE		; ^H ^I ^J ^K
	dw FNEXT,NEWLN,SPLIT,NOKEY	; ^L ^M ^N ^O
	dw NOKEY,QPRE,PGUP,LEFTK	; ^P ^Q ^R ^S
	dw DELWD,NOKEY,NOKEY,NOKEY	; ^T ^U ^V ^W
	dw DOWN,DELLN,NOKEY,ESCK	; ^X ^Y ^Z ESC
	dw NOKEY,NOKEY,NOKEY,NOKEY	; 1Ch-1Fh: nothing

; =====================================================================
; USAGE / DOSMSG - print a $-message through DOS and end
; ---------------------------------------------------------------------
; USAGE: no name, or a wildcard.  DOSMSG: DX = message (TOOBIG enters
; here).  Both run before the screen is touched.  INT 21h AH=09h print
; string, then INT 20h terminate.
; =====================================================================
USAGE:
	mov dx,USEMSG		; banner and the command line form
DOSMSG:
	mov ah,DOS_PRTSTR	; the $-terminated text at DX
	int byte 0x21		; DOS prints it
	int byte 0x20		; back to COMMAND

; =====================================================================
; START - set up, read the file, hook INT 24h, draw everything
; ---------------------------------------------------------------------
; Entry:  from BEGIN, as a .COM (CS = DS = ES = SS = PSP), FCB 1 at
;         5Ch already parsed by COMMAND.
; Exit:   falls into MAIN; never returns.
; DOS:    AH=19h current drive (only for a name without a drive),
;         AH=25h set the INT 24h vector to CRIT.
;
; The stack goes below the text, in the 256 bytes after the write
; buffer; BUFFERS falls at 132Dh, so SP starts odd (243Dh), which an
; 8086 tolerates (an extra bus cycle a word) and the interpreter
; ignores.  TEND is the end of the memory DOS gave us in this segment
; (at most FFF0h); the text may grow from BUFS up to it.  The INT 24h
; hook is set only after the file is read: a disk error while loading
; prints DOS's question before anything of ours is on the screen, and
; REDRAW clears it anyway.  The old vector is read from 0000:0090h
; directly because DOS 1.25 has no "get vector" call (AH=35h came with
; DOS 2.0); DOS itself puts it back from the PSP when we end
; (MSDOS.LST ABORT, which INT 20h reaches as function 0).
; =====================================================================
START:
	mov sp,BUFFERS+STKOFF	; stack below the text (243Dh)
	cld			; string ops go up unless said otherwise
	call OPTS		; /nn: terminal columns
	cmp byte [PSP_FCB1+FCB_NAME],' '	; no name given?
	jz short USAGE		; blank name: usage
	mov di,PSP_FCB1+FCB_NAME	; any '?' in the 8+3 name (COMMAND turns
	mov cx,NAMELEN		;   * into ?s) means a wildcard
	mov al,'?'		; the wildcard character
	repne scasb		; scan the 11 name bytes
	jz short USAGE		; one file only
	mov si,PSP_FCB1		; our FCB: drive, name, extension; the rest
	mov di,FCB		;   stays 0
	mov cx,FCBHEAD		; 12 bytes
	rep movsb		; the rest of FCB stays 0
	mov al,[FCB]		; drive: 0 = default, 1 = A ...
	or_d al,al		; a drive given?
	jnz short START_DRIVE_LETTER	; yes: use it
	mov ah,DOS_CURDSK	; the current drive, 0 = A
	int byte 0x21		; AL = 0 for A
	inc al			; as an FCB drive number
START_DRIVE_LETTER:			; (src: DRV1)
	add al,'A'-1		; 1 -> 'A' for the status line
	mov [DRVL],al		; shown on the status line
	mov ax,[PSP_MEMTOP]	; memory: up to the end of ours, in this segment
	mov bx,cs		; paragraphs from our segment to the top
	sub_d ax,bx		; AX = paragraphs we may use
	mov bx,0xfff0		; 64K or more: the segment's last paragraph
	cmp ax,0xfff		; under 64K?
	jnc short START_SET_TEND	; no: FFF0h stands
	mov cl,0x4		; less: paragraphs * 16 = the offset of the top
	shl ax,cl		; paragraphs -> bytes
	mov_d bx,ax		; BX = the top offset
START_SET_TEND:				; (src: MEM1)
	mov [TEND],bx		; the end of the text's room (never moves)
	mov word [BUFS],BUFFERS+TXOFF	; its start, above the stack
	call LOADF		; the file into the gap buffer, or a new file
	mov dx,CRIT		; INT 24H: note disk errors (DOS puts the
	mov ax,DOS_SETVEC*256+24h	;   old vector back when we end)
	push ds			; keep our DS
	xor_d bx,bx		; DS = 0: read the vector table itself
	mov ds,bx		; DS = 0000h
	mov bx,[INT24_VEC]	; offset ...
	mov cx,[INT24_VEC+2]	; ... and segment of DOS's handler
	pop ds			; our DS again
	mov [OLD24],bx		; kept for CRIT to chain to
	mov [OLD24+2],cx	; (the source: OLD24+2)
	int byte 0x21		; INT 24h -> CRIT
	call REDRAW		; clear the terminal, mark every row and the
				;   status line

; =====================================================================
; MAIN - the editor's loop: fix the view, draw it, take a key
; ---------------------------------------------------------------------
; FIXSCR first (it may queue a terminal scroll); then, unless a key is
; already waiting, the marked rows, the status fields and the cursor.
; DRAW gives up (CF=1) at a waiting key and STATUS / PLACE are skipped
; with it; what was queued is sent anyway.  A message lasts one key.
; =====================================================================
MAIN:
	call FIXSCR		; TOP, CROW, LEFT, CCOL right for the cursor
	call KEYRDY		; typed ahead?
	jnz short MAIN_KEY	; yes: the screen can wait
	call DRAW		; the marked rows
	jc short MAIN_KEY	; a key came in the middle
	call STATUS		; the status fields that changed
	call PLACE		; the terminal's cursor on the editor's
MAIN_KEY:				; (src: MAIN1)
	call FLUSH		; send what is queued
	call GETKEY		; wait for a key
	mov word [MSG],0x0	; a message lasts until the next key
	mov byte [VERT],0x0	; GOAL follows the cursor unless UP / DOWN
	call DOKEY		; do it
	jmp short MAIN		; and round again

; =====================================================================
; DOKEY - dispatch one key
; ---------------------------------------------------------------------
; Entry:  AL = key.   DEL -> DELB; 20h-7Eh and 80h-FFh -> INSCH (bytes
; above 7Eh go into the text and show as '?'); 00h-1Fh through CTAB.
; Each command ends in RET (to MAIN).  Callers: MAIN.
; =====================================================================
DOKEY:
	cmp al,KEY_DEL		; DEL: delete left, as ^H
	jnz short DOKEY_NOT_DEL	; not DEL
	jmp DELB		; DEL: as ^H
DOKEY_NOT_DEL:				; (src: DK1)
	cmp al,0x20		; printable (or above 7Fh): insert it
	jc short DOKEY_CONTROL	; below 20h: a command
	jmp INSCH		; a character to insert
DOKEY_CONTROL:				; (src: DK2)
	mov_d bl,al		; BX = code * 2: CTAB's word
	xor_d bh,bh		; (BH = 0)
	shl bx,1		; a word table
	jmp word near [bx+CTAB]	; the command returns to MAIN

NOKEY:
	ret			; an unused control key (and ESC + other)

; ---------------------------------------------------------------------
; ESCK - ESC: the terminal's arrow keys send ESC A/B/C/D.  Any other
; second key is swallowed.  Callers: CTAB (1Bh).
; ---------------------------------------------------------------------
ESCK:
	call GETKEY		; the arrow keys: ESC A, B, C, D
	cmp al,ARROW_UP		; ESC A: up
	jnz short ESCK_NOT_UP	; no
	jmp UP			; (the routine returns to MAIN)
ESCK_NOT_UP:				; (src: EK1)
	cmp al,ARROW_DOWN	; ESC B: down
	jnz short ESCK_NOT_DOWN	; no
	jmp DOWN		; (returns to MAIN)
ESCK_NOT_DOWN:				; (src: EK2)
	cmp al,ARROW_RIGHT	; ESC C: right
	jnz short ESCK_NOT_RIGHT	; no
	jmp RIGHT		; (returns to MAIN)
ESCK_NOT_RIGHT:				; (src: EK3)
	cmp al,ARROW_LEFT	; ESC D: left
	jnz short NOKEY		; nothing: the pair is dropped
	jmp LEFTK		; (returns to MAIN)

; ---------------------------------------------------------------------
; KPRE - ^K: S save, X or D save and exit, Q quit.  Callers: CTAB.
; ---------------------------------------------------------------------
KPRE:
	mov si,MKPRE		; "^K" on the status line, then the key
	call PREFIX		; shown; AL = the folded key
	cmp al,'S'		; ^KS: save and stay (the result is shown)
	jnz short KPRE_NOT_S	; no
	jmp SAVE		; SAVE returns to MAIN
KPRE_NOT_S:				; (src: KP1)
	cmp al,'X'		; ^KX ...
	jz short SAVEX		; save, then leave
	cmp al,'D'		; ... or ^KD (WordStar's "done")
	jz short SAVEX		; the same
	cmp al,'Q'		; ^KQ: quit
	jz short QUIT		; ask, maybe leave
	ret			; any other: the prefix is dropped

; SAVEX - save, and leave only if it worked
SAVEX:
	call SAVE		; CF=1: not saved
	jnc short EXIT		; saved: back to DOS
	ret			; not saved: stay, the message says why

; QUIT - leave; with changes, only after a Y.  PREFIX folds the answer,
; so y and ^Y count as Y too.
QUIT:
	cmp byte [MODIF],0x0	; nothing to lose?
	jz short EXIT		; unchanged: just go
	mov si,MABAN		; "Abandon changes (Y/N)? "
	call PREFIX		; shown; AL folded, AH the key as typed
	cmp ah,'Y'		; only a real Y or y abandons: AL would
	jz short EXIT		;   also say Y for ^Y (fixed 2026-11-08 -
	cmp ah,'y'		;   ^Y, delete line, used to abandon)
	jz short EXIT		; leave
	ret			; anything else: carry on editing

; EXIT - clear the terminal and end (DOS restores INT 24h)
EXIT:
	call CLS		; ESC H ESC J
	call FLUSH		; send them
	int byte 0x20		; terminate: COMMAND's prompt appears

; ---------------------------------------------------------------------
; QPRE - ^Q: S D line start / end, R C file start / end, F find,
; Y delete to the end of the line.  Callers: CTAB.
; ---------------------------------------------------------------------
QPRE:
	mov si,MQPRE		; "^Q" on the status line, then the key
	call PREFIX		; shown; AL = the folded key
	cmp al,'S'		; ^QS: line start
	jnz short QPRE_NOT_S	; no
	jmp LBEG		; (returns to MAIN)
QPRE_NOT_S:				; (src: QP1)
	cmp al,'D'		; ^QD: line end
	jnz short QPRE_NOT_D	; no
	jmp LEND		; (returns to MAIN)
QPRE_NOT_D:				; (src: QP2)
	cmp al,'R'		; ^QR: file start
	jnz short QPRE_NOT_R	; no
	jmp FTOP		; (returns to MAIN)
QPRE_NOT_R:				; (src: QP3)
	cmp al,'C'		; ^QC: file end
	jnz short QPRE_NOT_C	; no
	jmp FEND		; (returns to MAIN)
QPRE_NOT_C:				; (src: QP4)
	cmp al,'F'		; ^QF: find
	jnz short QPRE_NOT_F	; no
	jmp FIND		; (returns to MAIN)
QPRE_NOT_F:				; (src: QP5)
	cmp al,'Y'		; ^QY: delete to the end of the line
	jnz short QPRE_NONE	; no
	jmp DELEOL		; (returns to MAIN)
QPRE_NONE:				; (src: QP6)
	ret			; unknown: dropped

; =====================================================================
; PREFIX - show a prompt on the status line and read the answer
; ---------------------------------------------------------------------
; Entry:  SI = 0-terminated message.
; Exit:   AL = the next key as a capital letter: a control code is
;         raised by 40h (^S -> S), a-z lowered by 20h; AH = the key as
;         typed.  MSG = 0 again, so the next STATUS rubs the prompt out.
; Corrupts AX and what STATUS / FLUSH corrupt.  Callers: KPRE, QPRE,
; QUIT.  UPPER (a-z only, no control folding) is called by FIND and
; MATCH.
; An arrow key here sends ESC A..D.  Since 2026-11-08 ESC takes the next
; key too, as ESCK does, so the letter no longer reaches MAIN (it used
; to be inserted into the text: test_edit.py group 7).
; =====================================================================
PREFIX:
	mov [MSG],si		; the message field shows SI ...
	call STATUS		; ... sent now
	call FLUSH		; so the prompt is seen now
	call GETKEY		; the second key of the command
	cmp al,KESC		; ESC (an arrow key's first half)?
	jnz short PREFIX_KEY
	call GETKEY		; then its letter goes too
	mov al,KESC		; and ESC stands (folds to '[': no match)
PREFIX_KEY:				; (src: PFX1)
	mov_d ah,al		; AH = the key as typed (QUIT's Y test)
	mov word [MSG],0x0	; the prompt goes at the next STATUS
	cmp al,0x20		; a control code: its letter
	jnc short UPPER		; printable: as it is
	add al,0x40		; ^S -> S, ^[ -> [ ...
UPPER:
	cmp al,'a'		; a-z -> A-Z; nothing else changes
	jc short UPPER_X	; below 'a': as it is
	cmp al,'z'		; above 'z' ...
	ja short UPPER_X	; ... as it is
	sub al,0x20		; a-z -> A-Z
UPPER_X:				; (src: UPX)
	ret			; AL = the folded key

; =====================================================================
; OPTS - /nn in the command tail: a terminal of nn columns (64 to 80)
; ---------------------------------------------------------------------
; Exit:  COLS = nn, W = nn - 1 when nn is in range; else no change.
; The first '/' anywhere in the tail counts; digits are read until a
; non-digit (the tail ends in CR).  The running total is multiplied
; with an 8-bit MUL, so only its low byte survives each step - "/2624"
; reads as 64 (harmless).  NR stays 23: a 24-line terminal is assumed.
; Corrupts AX, BX, CX, DX, SI, DI.  Callers: START.
; =====================================================================
OPTS:
	mov si,PSP_TAIL		; the command tail and its length
	mov cl,[PSP_TAILLEN]	; CL = its length
	xor_d ch,ch		; CX = length
	jcxz short OPTS_X	; empty: 64 columns
	mov_d di,si		; find '/'
	mov al,'/'		; the option mark
	repne scasb		; scan the tail for it
	jnz short OPTS_X	; none
	xor_d dx,dx		; DX = the number so far
OPTS_DIGIT:				; (src: OP1)
	mov al,[di]		; next character, as a digit
	sub al,'0'		; ASCII -> value
	cmp al,0x9		; 0-9?
	ja short OPTS_RANGE	; not a digit: the number ends
	inc di			; take it
	xchg ax,dx		; AL = total (low byte), DX = digit
	mov bl,0xa		; times ten
	mul bl			; AX = total * 10
	xor_d dh,dh		; DX = the digit alone
	add_d ax,dx		; + the new digit
	xchg ax,dx		; DX = new total
	jmp short OPTS_DIGIT	; the next character
OPTS_RANGE:				; (src: OP2)
	cmp dx,byte 0x40	; 64 ...
	jc short OPTS_X		; under 64: ignored
	cmp dx,byte 0x50	; ... to 80 columns only
	ja short OPTS_X		; over 80: ignored
	mov [COLS],dx		; noted (nothing reads it again)
	dec dx			; W: every column but the last, where the
	mov [W],dx		;   terminal would wrap
OPTS_X:					; (src: OPX)
	ret			; (COLS / W changed or not)

; ---------------------------------------------------------------- the file
; =====================================================================
; LOADF - read the file into the text; a missing file is a new one
; ---------------------------------------------------------------------
; Entry:  FCB = name.ext; BUFS, TEND set.
; Exit:   the text in the gap buffer, cursor at its start (GAPS = BUFS,
;         the text at GAPE..TEND); TOP = BUFS.  A file that does not fit
;         ends EDIT through DOSMSG ("File too big for memory").
; DOS:    AH=0Fh open FCB, AH=1Ah set DTA (to BUFS: the file is read
;         straight into the text room), AH=27h random block read with
;         record size 1, so CX records = CX bytes in one call.
;
; Then the text is cleaned in place: it ends at the first ^Z in its
; last 128 bytes (CP/M pads its last record with them), and EVERY CR is
; dropped by copying the runs between CRs down (LOADF_CR_LOOP) - a lone
; CR not followed by LF is lost too.  Finally GAPMV(BUFS) moves the whole
; text to the top of memory, so the gap is in front of it.
; Corrupts AX, BX, CX, DX, SI, DI.  Callers: START.
; =====================================================================
LOADF:
	mov ax,[BUFS]		; empty text: gap = all of memory
	mov [GAPS],ax		; the cursor at the start ...
	mov [TOP],ax		; ... which is the top line
	mov ax,[TEND]		; the gap: all the room
	mov [GAPE],ax		; (nothing read yet)
	mov dx,FCB		; open name.ext
	mov ah,DOS_OPEN		; open name.ext
	int byte 0x21		; (fills in the size, sets record size 128)
	or_d al,al		; AL = 0 found, FFh not found
	jz short LOADF_OPENED	; found: read it
	mov word [MSG],MNEW	; not found: a new file, empty text
	ret			; (GAPS = BUFS, GAPE = TEND: empty)
LOADF_OPENED:				; (src: LD1)
	mov ax,[TEND]		; AX = room for text
	sub ax,[BUFS]		; = TEND - BUFS
	cmp word [FCB+FCB_SIZEHI],byte 0x0	; 64K or more: too big
	jnz short TOOBIG	; too big
	mov cx,[FCB+FCB_SIZE]	; CX = file size
	cmp_d cx,ax		; fits (exactly full is allowed)?
	jna short LOADF_READ	; it fits
TOOBIG:
	mov dx,BIGMSG		; "File too big for memory", back to DOS
	jmp DOSMSG		; the message, then INT 20h
LOADF_READ:				; (src: LD2)
	jcxz short LOADF_X	; an empty file: nothing to read
	mov dx,[BUFS]		; read straight into the text room
	mov ah,DOS_SETDTA	; DTA
	int byte 0x21		; the DTA is the text room
	mov word [FCB+FCB_RECSZ],0x1	; record size 1: CX records = bytes
	mov word [FCB+FCB_RANDOM],0x0	; from record 0
	mov word [FCB+FCB_RANDOMHI],0x0	; (32-bit random record = 0)
	mov dx,FCB		; read from our FCB
	mov ah,DOS_BLKREAD	; random block read
	int byte 0x21		; CX = records (bytes) actually read
	mov bx,[BUFS]		; the text ends at the first ^Z of the last
	add_d bx,cx		; 128 bytes (CP/M fills its last record
	mov_d di,bx		; with them); a scan costs 300 T a byte
	mov cx,0x80		;   (the source's figure before REPNE SCASB
	sub_d di,cx		;   became CPIR in the interpreter)
	cmp di,[BUFS]		; a file shorter than 128: scan all of it
	jnc short LOADF_SCAN_Z
	mov di,[BUFS]		; scan from BUFS instead ...
	mov_d cx,bx		; ... over the whole file
	sub_d cx,di		; CX = its length
LOADF_SCAN_Z:				; (src: LD2A)
	mov al,CTLZ		; the first ^Z there ends the text
	repne scasb		; look for ^Z
	jnz short LOADF_DROP_CR	; none: BX (the end read) stands
	mov_d bx,di		; BX = the ^Z itself
	dec bx			; (the text ends before it)
LOADF_DROP_CR:				; (src: LD3)
	mov si,[BUFS]		; drop the CRs: copy what is between them
	mov_d cx,bx		; CX = bytes still to scan
	sub_d cx,si		; CX = the text's length
	mov_d bx,si		; BX = where the next part goes
LOADF_CR_LOOP:				; (src: LD4)
	jcxz short LOADF_CR_DONE	; all scanned: done
	mov_d di,si		; scan for the next CR
	mov al,CR		; the byte to drop
	repne scasb		; scan the rest for CR
	mov_d dx,cx		; left after this part
	mov_d cx,di		; CX = end of the part (after its CR) ...
	jnz short LOADF_PART	; (no CR: the part runs to the end)
	dec cx			; not the CR
LOADF_PART:				; (src: LD5)
	sub_d cx,si		; ... minus its start = bytes to keep
	xchg di,bx		; DI = write point, BX = next read point
	rep movsb		; move the part down over the CRs dropped
	mov_d si,bx		; read on after the CR
	mov_d bx,di		; write on after the part
	mov_d cx,dx		; CX = what remains after it
	jmp short LOADF_CR_LOOP	; the next part
LOADF_CR_DONE:				; (src: LD6)
	mov [GAPS],bx		; the text is BUFS..BX-1, the gap after it
	mov ax,[BUFS]		; the cursor to the start: the whole text
	call GAPMV		;   moves up to end at TEND (LINE stays 1)
LOADF_X:				; (src: LDX)
	ret			; the text in place, or none

; =====================================================================
; SAVE - write the text as name.ext, keeping the old file as name.BAK
; ---------------------------------------------------------------------
; Exit:   CF=0 saved (MODIF = 0, "Saved"); CF=1 not saved, the old file
;         as it was, MSG says why ("Directory full", "Disk full: not
;         saved").  Either way AFTDOS redraws if DOS asked a question.
; DOS:    AH=13h delete, AH=16h make, AH=1Ah set DTA (the write buffer),
;         AH=28h random block write (through WFLUSH), AH=10h close,
;         AH=17h rename.
;
; Order: delete any old name.$$$, make it, write the text with CR LF and
; a ^Z, close; if a block write failed, delete name.$$$ and stop - the
; original is untouched.  Otherwise delete name.BAK, rename name.ext to
; name.BAK (fails harmlessly for a new file) and name.$$$ to name.ext.
; Only the block writes are checked: CLOSE's and the RENAMEs' AL are
; ignored.  If DOS asks Abort, Retry, Ignore? meanwhile, Abort ends
; EDIT altogether (DOS's ABORT) with name.$$$ left behind (findings).
; Corrupts AX, BX, CX, DX, SI, DI.  Callers: KPRE (^KS), SAVEX.
; =====================================================================
SAVE:
	mov si,FCB		; TFCB = drive + name of FCB ...
	mov di,TFCB		; (the file being written)
	mov cx,FCBHEAD		; drive + name + extension
	rep movsb		; copied
	xor_d al,al		; ... the other 25 bytes 0 (random record 0)
	mov cx,37-FCBHEAD	; 25 bytes
	rep stosb		; zeroed
	mov di,TFCB+FCB_EXT	; ... and the extension "$$$"
	mov al,'$'		; the extension "$$$"
	stosb			; '$'
	stosb			; '$'
	stosb			; '$'
	mov byte [ERRF],0x0	; no DOS question yet
	mov byte [DFULL],0x0	; no failed write yet
	mov word [WCNT],0x0	; write buffer empty
	mov dx,TFCB		; name.$$$
	mov ah,DOS_DELETE	; delete an old one
	int byte 0x21		; (no result needed: AL FFh if none)
	mov dx,TFCB		; name.$$$ again
	mov ah,DOS_MAKE		; make
	int byte 0x21		; AL = 0 made, FFh no room
	or_d al,al		; FFh: no directory entry free
	jz short SAVE_MADE	; made: write it
	mov word [MSG],MDIR	; "Directory full"
	jmp SVFAIL		; (the old file untouched)
SAVE_MADE:				; (src: SV1)
	mov word [TFCB+FCB_RECSZ],0x1	; record size 1: blocks of bytes
	mov dx,BUFFERS+WBOFF	; DTA = the write buffer
	mov ah,DOS_SETDTA	; (writes come from WBUF)
	int byte 0x21		; set
	mov si,[BUFS]		; the text before the gap ...
	mov cx,[GAPS]		; CX = GAPS - BUFS bytes
	sub_d cx,si		; (may be 0)
	call WTEXT		; written with CR LF
	mov si,[GAPE]		; ... and after it
	mov cx,[TEND]		; CX = TEND - GAPE bytes
	sub_d cx,si		; (may be 0)
	call WTEXT		; written with CR LF
	mov al,CTLZ		; the end mark
	call WBYTE		; the last byte of the file
	call WFLUSH		; the last part block
	mov dx,TFCB		; name.$$$
	mov ah,DOS_CLOSE	; close
	int byte 0x21		; the directory entry gets its size
	or_d al,al		; a failed close counts as not saved
	jz short SAVE_CLOSED	;   (it used to be ignored)
	mov byte [DFULL],0x1
SAVE_CLOSED:				; (src: SVCL)
	cmp byte [DFULL],0x0	; did a write (or the close) fail?
	jz short SAVE_RENAME	; all written: replace the old file
	mov dx,TFCB		; yes: drop name.$$$, keep the old file
	mov ah,DOS_DELETE	; delete
	int byte 0x21		; (the partial name.$$$ goes)
	mov word [MSG],MDFULL	; "Disk full: not saved"
	jmp short SVFAIL	; CF=1
SAVE_RENAME:				; (src: SV2)
	mov si,FCB		; name.BAK: delete, then name.ext -> name.BAK
	mov di,RFCB		; the rename / delete FCB
	mov cx,FCBHEAD		; drive + name + extension
	rep movsb		; copied
	mov di,RFCB+FCB_EXT	; RFCB = name.BAK
	call BAKEXT		; extension BAK
	mov dx,RFCB		; delete the previous backup
	mov ah,DOS_DELETE	; delete name.BAK
	int byte 0x21		; (no result needed: none is fine)
	mov si,FCB		; RFCB: old name = name.ext ...
	mov di,RFCB		; old name: name.ext
	mov cx,FCBHEAD		; drive + name + extension
	rep movsb		; copied
	mov si,FCB+FCB_NAME	; ... new name = name.BAK (the new name's
	mov di,RFCB+REN_NEW	;   drive byte at 16 is left 0: DOS 1.25
	mov cx,NAMELEN		;   ignores it)
	rep movsb		; copied
	mov di,RFCB+REN_NEWEXT	; new extension: BAK
	call BAKEXT		; "BAK"
	mov dx,RFCB		; rename name.ext -> name.BAK
	mov ah,DOS_RENAME	; rename (a new file has none)
	int byte 0x21		; (AL FFh for a new file: harmless)
	mov si,TFCB		; name.$$$ -> name.ext
	mov di,RFCB		; old name: name.$$$
	mov cx,FCBHEAD		; drive + name + extension
	rep movsb		; copied
	mov si,FCB+FCB_NAME	; the new name: the original's
	mov di,RFCB+REN_NEW	; new name at 17
	mov cx,NAMELEN		; 8 + 3
	rep movsb		; copied
	mov dx,RFCB		; rename name.$$$ -> name.ext
	mov ah,DOS_RENAME	; name.$$$ -> name.ext
	int byte 0x21
	or_d al,al		; refused: the text is safe in name.$$$, but
	jz short SAVE_OK	;   say so and keep MODIF (it used to say
	mov word [MSG],MREN	;   "Saved" whatever happened)
	jmp short SVFAIL
SAVE_OK:				; (src: SVOK)
	mov byte [MODIF],0x0	; the file now matches the text
	mov word [MSG],MSAVED	; "Saved" on the status line
	call AFTDOS		; DOS's question on the screen?
	clc			; saved
	ret			; CF=0 for SAVEX
SVFAIL:
	call AFTDOS		; redraw if DOS spoke
	stc			; not saved
	ret			; CF=1 for SAVEX

; BAKEXT - "BAK" at DI (DI += 3).  Corrupts AL.  Callers: SAVE (twice).
BAKEXT:
	mov al,'B'		; 'B'
	stosb			; stored
	mov al,'A'		; 'A'
	stosb			; stored
	mov al,'K'		; 'K'
	stosb			; stored
	ret			; DI past the extension

; ---------------------------------------------------------------------
; AFTDOS - if DOS asked about a disk error, its question is on the
; screen: draw everything again.  Callers: SAVE.
; ---------------------------------------------------------------------
AFTDOS:
	cmp byte [ERRF],0x0	; did CRIT run?
	jz short AFTDOS_X	; no: the screen is ours
	call REDRAW		; yes: the terminal holds DOS's text
AFTDOS_X:				; (src: AFX)
	ret			; ERRF stays 1 (cleared by the next SAVE)

; =====================================================================
; CRIT - INT 24h: note it, then DOS's own handler asks the question
; ---------------------------------------------------------------------
; Reached from DOS's HARDERR with DS = DOS's segment, so both accesses
; carry CS:.  The registers and the stack frame pass to DOS's handler
; untouched; its answer (Retry / Ignore / Abort) goes back to DOS
; directly.  The flag tells AFTDOS the screen was written over.
; =====================================================================
CRIT:
	mov byte [cs:ERRF],0x1	; DOS printed on our screen
	jmp word far [cs:OLD24]	; and it asks Abort, Retry, Ignore? itself

; =====================================================================
; WTEXT - CX bytes at SI to the file, each LF as CR LF
; ---------------------------------------------------------------------
; A line at a time: REPNE SCASB finds the LF, WCOPY moves the bytes
; before it, then CR LF go in by WBYTE.  Exit: SI past the bytes.
; Corrupts AX, CX, DX, DI.  Callers: SAVE (both halves of the text).
; =====================================================================
WTEXT:
	jcxz short WTEXT_X	; nothing (left): done
	mov_d di,si		; the next LF
	mov al,LF		; the line end
	repne scasb		; scan for LF
	mov_d dx,cx		; left after this line
	mov_d cx,di		; CX = end of the line (after its LF)
	mov ah,0x0		; AH = 0: no LF (the last piece)
	jnz short WTEXT_COPY	; no LF: the last piece, all of it
	dec cx			; not the LF
	mov ah,0x1		; AH = 1: a LF to write as CR LF
WTEXT_COPY:				; (src: WT1)
	sub_d cx,si		; bytes before the LF
	push dx			; keep the rest count
	push ax			; keep the LF flag
	call WCOPY		; them (SI advances)
	pop ax			; AH = the LF flag
	or_d ah,ah		; was there a LF?
	jz short WTEXT_NEXT	; no LF: nothing to add
	inc si			; over the LF ...
	mov al,CR		; ... written as CR LF
	call WBYTE		; CR
	mov al,LF		; then
	call WBYTE		; LF
WTEXT_NEXT:				; (src: WT2)
	pop cx			; the rest
	jmp short WTEXT		; next line
WTEXT_X:				; (src: WTX) - also WCOPY's, WBYTE's, WFLUSH's
	ret			; (the LF is not copied as such)

; ---------------------------------------------------------------------
; WCOPY - CX bytes at SI to the write buffer, flushing each time it is
; full.  Corrupts AX, CX, DX, DI.  Callers: WTEXT.
; ---------------------------------------------------------------------
WCOPY:
	jcxz short WTEXT_X	; nothing (left): done
	mov di,[WCNT]		; room left in the buffer
	mov ax,WBSZ		; AX = room left
	sub_d ax,di		; = WBSZ - WCNT
	add di,BUFFERS+WBOFF	; DI = its first free byte
	mov_d dx,cx		; DX = all still to copy
	cmp_d cx,ax		; at most what fits
	jna short WCOPY_FITS	; all fits
	mov_d cx,ax		; only what fits
WCOPY_FITS:				; (src: WC1)
	sub_d dx,cx		; DX = what will be left over
	add [WCNT],cx		; the buffer fills by CX
	rep movsb		; copy them
	cmp word [WCNT],WBSZ	; full?
	jc short WCOPY_MORE	; not full: no write
	call WFLUSH		; write the block
WCOPY_MORE:				; (src: WC2)
	mov_d cx,dx		; the rest, if any
	jmp short WCOPY		; loop while bytes are left

; ---------------------------------------------------------------------
; WBYTE - AL to the write buffer; falls into WFLUSH when it fills.
; Corrupts DI (CX, DX via WFLUSH).  Callers: WTEXT, SAVE.
; ---------------------------------------------------------------------
WBYTE:
	mov di,[WCNT]		; the next free byte
	mov [di+BUFFERS+WBOFF],al	; stored in WBUF
	inc di			; one more byte
	mov [WCNT],di		; counted
	cmp di,WBSZ		; not full yet: done
	jc short WTEXT_X	; not full yet: done

; ---------------------------------------------------------------------
; WFLUSH - the write buffer to the file (random block write); after a
; failed write, nothing more is written
; DOS: AH=28h random block write of WCNT records of 1 byte at TFCB
; (the DTA is the buffer); AL <> 0 = disk full -> DFULL.  The buffer is
; emptied either way.  Preserves SI, DX.  Callers: WCOPY, WBYTE, SAVE.
; ---------------------------------------------------------------------
WFLUSH:
	mov cx,[WCNT]		; CX = bytes = records
	jcxz short WTEXT_X	; empty: nothing
	mov word [WCNT],0x0	; the buffer is empty again ...
	cmp byte [DFULL],0x0	; already failed: drop the rest
	jnz short WTEXT_X	; ... and the bytes are dropped after a failure
	push si			; (WTEXT / WCOPY need them)
	push dx			; (WCOPY's remaining count)
	mov dx,TFCB		; name.$$$
	mov ah,DOS_BLKWRITE	; the random record advances by CX
	int byte 0x21		; writes CX bytes from the DTA (WBUF)
	pop dx
	pop si
	or_d al,al		; 0 = all written
	jz short WTEXT_X	; all written
	mov byte [DFULL],0x1	; 1 = disk full: SAVE will undo
	ret			; (SAVE checks DFULL after the close)

; ---------------------------------------------------------------- the text
; =====================================================================
; GAPMV - move the gap (the cursor) to address AX
; ---------------------------------------------------------------------
; Entry:  AX <= GAPS (the cursor goes back: AX is a text address before
;         the gap) or AX >= GAPE (forward: AX is an address after it).
; Exit:   GAPS / GAPE moved; the bytes between change sides.  LINE is
;         NOT kept (MOVETO does that).  Corrupts CX, SI, DI.
; Callers: MOVETO, LOADF.
; Backward: the bytes AX..GAPS-1 are copied, top down (STD), to just
; below GAPE.  Forward: GAPE..AX-1 copied up to GAPS.  Cost is the
; distance moved, not the size of the text.
; =====================================================================
GAPMV:
	cmp ax,[GAPS]		; forward or back?
	ja short GAPMV_FORWARD	; AX past the gap: forward
	mov cx,[GAPS]		; back: CX = bytes that cross over
	sub_d cx,ax		; (AX <= GAPS here)
	jz short GAPMV_X	; already there
	mov si,[GAPS]		; from the last byte before the gap ...
	dec si			; SI = GAPS - 1
	mov di,[GAPE]		; ... to the last byte of the gap
	dec di			; DI = GAPE - 1
	std			; downward, the regions may overlap
	rep movsb		; the bytes cross the gap
	cld			; back to upward strings
	inc di			; DI = the first byte moved: the new GAPE
	mov [GAPE],di		; the gap now ends where they begin
	mov [GAPS],ax		; and the cursor is AX
GAPMV_X:				; (src: GMX)
	ret			; (the gap keeps its size)
GAPMV_FORWARD:				; (src: GM2)
	mov_d cx,ax		; forward: CX = AX - GAPE bytes
	sub cx,[GAPE]		; (AX >= GAPE here)
	jz short GAPMV_X	; already there
	mov si,[GAPE]		; the first bytes after the gap ...
	mov di,[GAPS]		; ... to the gap's start, upward
	rep movsb		; the bytes cross the gap
	mov [GAPS],di		; the gap now starts after them
	mov [GAPE],ax		; and ends at AX
	ret			; (the gap keeps its size)

; =====================================================================
; MOVETO - put the cursor at AX (as GAPMV) and keep LINE right
; ---------------------------------------------------------------------
; LINE goes down by the LFs between AX and GAPS, or up by those between
; GAPE and AX.  AX reaches GAPMV intact.  Corrupts CX, DX, SI, DI.
; Callers: LEFTK, RIGHT, UP, DOWN, WORDR, WORDL, LBEG, LEND, FTOP,
; FEND, DELLN, FOUND - every cursor move goes through here.
; =====================================================================
MOVETO:
	push ax			; the target, for GAPMV
	cmp ax,[GAPS]		; forward or back?
	ja short MOVETO_FORWARD	; after the gap: forward
	mov_d di,ax		; back: the LFs in AX..GAPS-1
	mov cx,[GAPS]		; CX = GAPS - AX
	sub_d cx,ax		; (bytes passed going back)
	call CNTLF		; DX = LFs among them
	sub [LINE],dx		; are lines we go up
	jmp short MOVETO_GO	; then move
MOVETO_FORWARD:				; (src: MT1)
	mov di,[GAPE]		; forward: the LFs in GAPE..AX-1
	mov_d cx,ax		; CX = AX - GAPE
	sub_d cx,di		; (bytes passed going forward)
	call CNTLF		; DX = LFs among them
	add [LINE],dx		; are lines we go down
MOVETO_GO:				; (src: MT2)
	pop ax			; AX = the target again
	jmp short GAPMV		; then move the gap itself

; ---------------------------------------------------------------------
; CNTLF - DX = LFs in the CX bytes at DI (REPNE SCASB per line).
; Corrupts AL, CX, DI.  Callers: MOVETO.
; ---------------------------------------------------------------------
CNTLF:
	xor_d dx,dx		; none yet
	mov al,LF		; the byte to count
CNTLF_LOOP:				; (src: CN1)
	jcxz short CNTLF_X	; bytes left?
	repne scasb		; to the next LF
	jnz short CNTLF_X	; none left
	inc dx			; one more line end
	jmp short CNTLF_LOOP	; go on after it
CNTLF_X:				; (src: CNX)
	ret			; DX = the count

; =====================================================================
; LSOF - AX = start of the line that holds the byte before address AX
; ---------------------------------------------------------------------
; Entry:  AX <= GAPS (a scan backward never crosses the gap).
; Exit:   AX = the byte after the last LF below AX, or BUFS.  If the
;         byte before AX is itself a LF, AX comes back unchanged (an
;         empty line starts at its own LF).
; Corrupts CX, DI.  Callers: FIXSCR, UP (twice), KEEPRW, LBEG, SETTOP.
; =====================================================================
LSOF:
	mov_d cx,ax		; CX = bytes back to BUFS
	sub cx,[BUFS]		; (AX - BUFS)
	jz short LSOF_X		; at the start: AX is the start
	mov_d di,ax		; scan down from AX-1 for LF
	dec di			; the byte before AX
	mov al,LF		; look for the line end below
	std			; downward
	repne scasb		; scan back
	cld			; upward again
	jnz short LSOF_FIRST	; no LF: the first line
	lea ax,[di+0x2]		; DI stopped one below the LF: start = LF + 1
	ret			; AX = line start
LSOF_FIRST:				; (src: LS1)
	mov ax,[BUFS]		; no LF below: the text's first line
LSOF_X:					; (src: LSX)
	ret			; AX = line start

; ---------------------------------------------------------------------
; NEXTLF - DI = the next LF from DI on, below BX; CF=1 none, DI = BX.
; Corrupts AL, CX.  Callers: DOWN, LEND, DELEOL, DELLN, FIXSCR, DRAW.
; ---------------------------------------------------------------------
NEXTLF:
	mov_d cx,bx		; CX = bytes to search
	sub_d cx,di		; (BX - DI)
	jz short NEXTLF_NONE	; empty range: none
	mov al,LF		; the line end
	repne scasb		; scan forward
	jnz short NEXTLF_NONE	; not found
	dec di			; DI = the LF itself
	clc			; CF=0: found
	ret			; DI = the LF
NEXTLF_NONE:				; (src: NLN)
	mov_d di,bx		; the end of the range
	stc			; CF=1: none
	ret			; DI = BX

; =====================================================================
; WALK - SI = the place in the line SI..BX-1 at column DX, or the last
; one before it
; ---------------------------------------------------------------------
; Entry:  SI = line start, BX = its end (the LF or the text end),
;         DX = the column wanted (GOAL).
; Exit:   SI = the byte whose column is DX, or the last byte whose
;         column is below it (a tab spanning DX stops before the tab);
;         at most BX.  Columns as FIXSCR counts them: a tab goes to the
;         next multiple of 8, every other byte is one column.
; Fast path: no tab among the first DX bytes - SI + DX.
; Corrupts AX, CX, DI.  Callers: UP, DOWN.
; =====================================================================
WALK:
	mov_d cx,bx		; CX = min(line length, DX)
	sub_d cx,si		; (BX - SI)
	cmp_d cx,dx		; more bytes than columns?
	jna short WALK_TABS	; no: the whole line
	mov_d cx,dx		; only DX bytes can matter
WALK_TABS:				; (src: WK1)
	jcxz short WALK_X	; column 0 or an empty line: the start
	mov_d di,si		; a tab in the first CX bytes?
	mov al,TAB		; the tab character
	push cx			; (the count, kept)
	repne scasb		; scan the first CX bytes
	pop cx
	jz short WALK_SLOW	; a tab: count column by column
	add_d si,cx		; no tab: a column a byte
WALK_X:					; (src: WKX)
	ret			; SI = the byte at column DX
WALK_SLOW:				; (src: WK2)
	xor_d cx,cx		; CX = column of the byte at SI
WALK_LOOP:				; (src: WK3)
	cmp_d si,bx		; at the line end: stop
	jnc short WALK_X	; (the line end is the limit)
	mov_d di,cx		; DI = column after this byte:
	cmp byte [si],TAB	; a tab here?
	jnz short WALK_ONE	; no: one column
	or di,0x7		;   a tab: to the next multiple of 8
WALK_ONE:				; (src: WK4)
	inc di			; the column after this byte
	cmp_d di,dx		; would it pass DX?
	ja short WALK_X		; yes: stop on this byte
	mov_d cx,di		; this byte is passed
	inc si			; the next byte
	jmp short WALK_LOOP

; ---------------------------------------------------------------------
; ISWD - CF=1 if AL is a letter or a digit (ASCII 0-9 A-Z a-z only;
; bytes above 7Fh are not).  Callers: WORDR, WORDL, DELWD.
; ---------------------------------------------------------------------
ISWD:
	cmp al,'0'		; below '0': no
	jc short ISWD_NO	; (CF=1 from CMP means below)
	cmp al,'9'+1		; '0'-'9': CF=1 yes
	jc short ISWD_X		; a digit
	cmp al,'A'		; ':'-'@': no
	jc short ISWD_NO	; punctuation
	cmp al,'Z'+1		; 'A'-'Z': yes
	jc short ISWD_X		; a capital
	cmp al,'a'		; '['-'`': no
	jc short ISWD_NO	; punctuation
	cmp al,'z'+1		; 'a'-'z': CF=1; above: CF=0
ISWD_X:					; (src: IWX)
	ret			; CF=1 word, CF=0 not
ISWD_NO:				; (src: IWN)
	clc			; not a word byte
	ret			; CF=0

; ---------------------------------------------------------------- moving
; ---------------------------------------------------------------------
; LEFTK / RIGHT - one byte left (^S, ESC D) / right (^D, ESC C); a LF
; is one byte, so they cross line ends.  Callers: CTAB, ESCK.
; ---------------------------------------------------------------------
LEFTK:
	mov ax,[GAPS]		; at the start of the text: nothing
	cmp ax,[BUFS]		; at the start?
	jz short MOVE_X		; nothing to do
	dec ax			; the byte before the cursor
	jmp MOVETO		; (LINE drops if it was a LF)

RIGHT:
	mov ax,[GAPE]		; at the end: nothing
	cmp ax,[TEND]		; at the end?
	jz short MOVE_X		; nothing to do
	inc ax			; past the byte after the cursor
	jmp MOVETO		; (LINE rises if it was a LF)
MOVE_X:					; (src: MVX)
	ret			; (no change)

; =====================================================================
; UP, DOWN - to the column GOAL of the line above, below; CF=1 if none
; ---------------------------------------------------------------------
; VERT = 1 tells FIXSCR to keep GOAL, so a run of ups and downs through
; short lines comes back to the column it started at.  Callers: CTAB
; (^E, ^X), ESCK, PGUP, PGDN.  Corrupts AX, BX, CX, DX, SI, DI.
; =====================================================================
UP:
	mov byte [VERT],0x1	; GOAL stays for the next key
	mov ax,[GAPS]		; start of the cursor's line
	call LSOF		; AX = start of the cursor's line
	cmp ax,[BUFS]		; the first line: no line above
	jz short UP_NONE	; (CF=1 for PGUP)
	mov_d bx,ax		; BX = that start - 1 ...
	dec bx			; the LF that ends the line above
	mov_d ax,bx		; AX = the LF
	push bx			; (the end of the line above)
	call LSOF		; AX = start of the line above
	pop bx			; BX = end of the line above
	mov_d si,ax		; SI = its start
	mov dx,[GOAL]		; the column wanted, in SI..BX-1
	call WALK		; SI = the byte at column GOAL
	mov_d ax,si		; the new cursor
	call MOVETO		; LINE - 1
	clc			; CF=0: moved
	ret
UP_NONE:				; (src: UPN)
	stc			; CF=1: no line above
	ret			; (the cursor stays)

DOWN:
	mov byte [VERT],0x1	; GOAL stays for the next key
	mov di,[GAPE]		; the LF that ends the cursor's line
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF
	jc short DOWN_X		; none: the last line (CF=1)
	inc di			; the next line starts after it
	mov_d si,di		; SI = the next line's start
	push si			; (kept over NEXTLF)
	call NEXTLF		; and ends at its LF (or TEND)
	mov_d bx,di		; BX = its end
	pop si			; SI = its start
	mov dx,[GOAL]		; the column wanted
	call WALK		; SI = the byte at column GOAL
	mov_d ax,si		; the new cursor
	call MOVETO		; LINE + 1
	clc			; CF=0: moved
DOWN_X:					; (src: DNX)
	ret			; CF=1 with no line below

; =====================================================================
; PGDN / PGUP - page down (^C), up (^R): the cursor stays on its row,
; the text moves a page (NR - 1 lines, fewer at either end)
; ---------------------------------------------------------------------
; KEEPRW then puts the top line CROW lines above the cursor's line, so
; the cursor's screen row does not change; SETTOP marks everything if
; the top line moved.  Callers: CTAB.
; =====================================================================
PGDN:
	mov cx,[NR]		; NR - 1 downs: one line of overlap
	dec cx			; (NR - 1 = 22 lines)
PGDN_LOOP:				; (src: PD1)
	push cx			; (DOWN corrupts CX)
	call DOWN		; one line
	pop cx			; (count back)
	jc short KEEPRW		; the last line: stop early
	loop short PGDN_LOOP	; the next line
	jmp short KEEPRW	; then keep the row

PGUP:
	mov cx,[NR]		; NR - 1 ups
	dec cx			; (22 lines)
PGUP_LOOP:				; (src: PU1)
	push cx			; (UP corrupts CX)
	call UP			; one line
	pop cx			; (count back)
	jc short KEEPRW		; the first line: stop early
	loop short PGUP_LOOP	; the next line
KEEPRW:
	mov ax,[GAPS]		; the cursor's line, on the row it had
	call LSOF		; AX = its start
	mov cx,[CROW]		; the row the cursor had
	jmp SETTOP		; TOP from there; marks if moved

; ---------------------------------------------------------------------
; WORDR - ^F: over the rest of this word, then over what is not a word
; to the start of the next one.  Callers: CTAB.
; ---------------------------------------------------------------------
WORDR:
	mov si,[GAPE]		; over this word, then to the next one
WORDR_IN_WORD:				; (src: WR1)
	cmp si,[TEND]		; the end of the text stops it
	jnc short WORDR_GO	; (there)
	lodsb			; the next byte
	call ISWD		; still a word?
	jc short WORDR_IN_WORD	; yes: on
	dec si			; back onto the first non-word byte
WORDR_GAP:				; (src: WR2)
	cmp si,[TEND]		; the end stops it
	jnc short WORDR_GO	; (there)
	lodsb			; the next byte
	call ISWD		; a word byte?
	jnc short WORDR_GAP	; not yet: on
	dec si			; back onto the next word's first byte
WORDR_GO:				; (src: WR3)
	mov_d ax,si		; the new cursor
	jmp MOVETO		; (LINE counts the LFs passed)

; ---------------------------------------------------------------------
; WORDL - ^A: back over what is not a word, then over a word, to its
; first byte.  Callers: CTAB.
; ---------------------------------------------------------------------
WORDL:
	mov si,[GAPS]		; back over the gap, then over a word
WORDL_GAP:				; (src: WL1)
	cmp si,[BUFS]		; the start of the text stops it
	jz short WORDL_GO	; (there)
	mov al,[si-0x1]		; the byte before SI
	call ISWD		; a word byte before SI?
	jc short WORDL_IN_WORD	; yes: now back over the word
	dec si			; no: one more back
	jmp short WORDL_GAP
WORDL_IN_WORD:				; (src: WL2)
	cmp si,[BUFS]		; the start stops it
	jz short WORDL_GO	; (there)
	mov al,[si-0x1]		; the byte before SI
	call ISWD		; still a word?
	jnc short WORDL_GO	; the word's first byte reached
	dec si			; yes: back over it
	jmp short WORDL_IN_WORD
WORDL_GO:				; (src: WL3)
	mov_d ax,si		; the new cursor
	jmp MOVETO		; (LINE counts the LFs passed)

; LBEG - ^QS: to the start of the line
LBEG:
	mov ax,[GAPS]		; the cursor ...
	call LSOF		; AX = its line's start
	jmp MOVETO		; (no LF passed: LINE unchanged)

; LEND - ^QD: to the line's LF (or the end of the text)
LEND:
	mov di,[GAPE]		; from the cursor ...
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF, or TEND
	mov_d ax,di		; the new cursor
	jmp MOVETO		; (no LF passed)

; FTOP - ^QR: to the start of the text
FTOP:
	mov ax,[BUFS]		; the first byte of the text
	jmp MOVETO		; (LINE counts back to 1)

; FEND - ^QC: to the end of the text
FEND:
	mov ax,[TEND]		; past the last byte
	jmp MOVETO		; (LINE counts the LFs passed)

; ---------------------------------------------------------------- editing
; =====================================================================
; NEWLN / TABK / INSCH - insert a LF (RETURN), a TAB, or the key in AL
; ---------------------------------------------------------------------
; The byte goes at GAPS (the gap shrinks by one).  MARKC first, while
; CCOL / CROW are still those of the cursor before the insert: the row
; is sent again from there.  A LF also marks every row below (they all
; move down) and counts a line.  GAPS = GAPE: "Memory full".
; Callers: CTAB (^M, ^I), DOKEY (20h-FFh).
; =====================================================================
NEWLN:
	mov al,LF		; RETURN: a LF inside
	jmp short INSCH		; (AL = LF)
TABK:
	mov al,TAB		; TAB key (^I)
INSCH:
	mov di,[GAPS]		; room in the gap?
	cmp di,[GAPE]		; the gap is empty?
	jz short MFULL		; no room
	push ax			; (MARKC uses AX)
	call MARKC		; this row, from the cursor
	pop ax			; AL = the byte again
	mov di,[GAPS]		; the cursor's address
	stosb			; the byte before the cursor
	mov [GAPS],di		; the cursor is after it
	mov byte [MODIF],0x1	; changed
	cmp al,LF		; a new line?
	jnz short INSCH_X	; not a line end: done
	inc word [LINE]		; the cursor is on the next line
	call MARKB		; and every row below moves
INSCH_X:				; (src: INX)
	ret			; (the screen catches up in MAIN)
MFULL:
	mov word [MSG],MMEM	; "Memory full"
	ret			; (the byte is dropped)

; ---------------------------------------------------------------------
; SPLIT - ^N: a LF after the cursor (the cursor stays).  Callers: CTAB.
; ---------------------------------------------------------------------
SPLIT:
	mov di,[GAPE]		; a LF after the cursor
	cmp di,[GAPS]		; room?
	jz short MFULL		; no room
	call MARKC		; this row from the cursor
	call MARKB		; and all below
	dec word [GAPE]		; the gap's last byte becomes the LF
	mov di,[GAPE]		; the gap's new last byte
	mov byte [di],LF	; becomes LF
	mov byte [MODIF],0x1	; changed
	ret			; (LINE unchanged: the LF is after the cursor)

; =====================================================================
; DELB - DEL, ^H: delete the byte before the cursor
; ---------------------------------------------------------------------
; The cursor moves left, maybe onto the line above, so the row to mark
; is not known yet: MARKF asks FIXSCR to mark the cursor's row from
; its new column.  Deleting a LF joins two lines: every row from the
; old cursor row down is marked (MARKR CROW); the joined line is on the
; row above it and gets its mark through MARKF.  Callers: DOKEY, CTAB.
; =====================================================================
DELB:
	mov si,[GAPS]		; at the start: nothing
	cmp si,[BUFS]		; at the start of the text?
	jz short DELB_X		; nothing to delete
	dec si			; the gap grows down by one
	mov [GAPS],si		; the byte is now in the gap
	mov byte [MODIF],0x1	; changed
	mov byte [MARKF],0x1	; the row from the cursor (FIXSCR)
	cmp byte [si],LF	; was it a line end?
	jnz short DELB_X	; not a LF: done
	dec word [LINE]		; the cursor is on the line above
	mov ax,[CROW]		; the rows below move up
	call MARKR		; every row from CROW down
DELB_X:					; (src: DBX)
	ret			; (FIXSCR marks the joined row)

; ---------------------------------------------------------------------
; DELF - ^G: delete the byte after the cursor; a LF joins the next line
; (rows below marked).  Callers: CTAB, DELWD.
; ---------------------------------------------------------------------
DELF:
	mov si,[GAPE]		; at the end: nothing
	cmp si,[TEND]		; at the end?
	jz short DEL_X		; nothing to delete
	call MARKC		; this row from the cursor
	mov si,[GAPE]		; the byte after the cursor
	lodsb			; the gap grows up by one
	mov [GAPE],si		; now in the gap
	mov byte [MODIF],0x1	; changed
	cmp al,LF		; a line end?
	jnz short DEL_X		; no: done
	call MARKB		; lines below move up
DEL_X:					; (src: DFX) - DELEOL's, DELLN's, DELWD's too
	ret			; (shared exit)

; ---------------------------------------------------------------------
; DELEOL - ^QY: delete up to (not including) the LF.  Callers: QPRE.
; ---------------------------------------------------------------------
DELEOL:
	mov di,[GAPE]		; up to the LF
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF, or TEND
	cmp di,[GAPE]		; nothing before it: done
	jz short DEL_X		; (the cursor is on the LF)
	push di			; (MARKC corrupts AX, BX only; kept anyway)
	call MARKC		; the rest of the row
	pop di			; DI = the LF
	mov [GAPE],di		; the gap swallows them
	mov byte [MODIF],0x1	; changed
	ret			; (the LF stays)

; ---------------------------------------------------------------------
; DELLN - ^Y: delete the whole line with its LF; the cursor goes to the
; start of what follows.  CLS_ is still right (no move since FIXSCR).
; Callers: CTAB.
; ---------------------------------------------------------------------
DELLN:
	mov ax,[CLS_]		; from the start of the line, with its LF
	call MOVETO		; (LINE is unchanged: no LF crossed)
	mov di,[GAPE]		; to its LF ...
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF, or TEND
	jc short DELLN_CUT	; (the last line: to the end)
	inc di			; ... included
DELLN_CUT:				; (src: DL1)
	cmp di,[GAPE]		; an empty last line: nothing
	jz short DEL_X		; (nothing to delete)
	mov [GAPE],di		; the gap swallows the line
	mov byte [MODIF],0x1	; changed
	mov ax,[CROW]		; this row and all below
	jmp MARKR		; (rows below move up)

; ---------------------------------------------------------------------
; DELWD - ^T: delete a word and the blanks after it.  On a LF it joins
; lines (DELF); on another non-word byte, that byte and the blanks.
; Callers: CTAB.
; ---------------------------------------------------------------------
DELWD:
	mov si,[GAPE]		; a word and the blanks after it
	cmp si,[TEND]		; at the end?
	jz short DEL_X		; nothing to delete
	lodsb			; the first byte always goes
	cmp al,LF		; a line end?
	jnz short DELWD_WORD	; no
	jmp short DELF		; a line end: as ^G
DELWD_WORD:				; (src: DW0)
	call ISWD		; a word byte: the whole word
	jnc short DELWD_BLANKS	; not a word byte: just the blanks after it
DELWD_WORD_LOOP:			; (src: DW1)
	cmp si,[TEND]		; the end stops it
	jnc short DELWD_CUT	; (there)
	lodsb			; the next byte
	call ISWD		; still a word?
	jc short DELWD_WORD_LOOP	; yes: on
	dec si			; the first non-word byte stays (so far)
DELWD_BLANKS:				; (src: DW2)
	cmp si,[TEND]		; the end stops it
	jnc short DELWD_CUT	; (there)
	lodsb			; the next byte
	cmp al,0x20		; spaces and tabs go too
	jz short DELWD_BLANKS	; a space: on
	cmp al,TAB		; a tab?
	jz short DELWD_BLANKS	; also on
	dec si			; back onto the first kept byte
DELWD_CUT:				; (src: DW3)
	push si			; (MARKC corrupts AX, BX only)
	call MARKC		; the rest of the row
	pop si			; SI = the end of what goes
	mov [GAPE],si		; the gap swallows GAPE..SI-1
	mov byte [MODIF],0x1	; changed
	ret			; (the screen catches up in MAIN)

; ---------------------------------------------------------------- find
; =====================================================================
; FIND - ^QF: ask for a string, then FNEXT; ^L enters at FNEXT
; ---------------------------------------------------------------------
; The string is kept upper case in FSTR; capitals and small letters in
; the text match alike.  RETURN alone searches for the last string
; again.  The search runs forward from the byte after the cursor to
; the end of the text, with no wrap; only the text after the gap is
; searched, so a match never spans the gap.  To be fast on the
; interpreter, both cases of the first letter are looked for with
; REPNE SCASB (SCANF), the nearer of the two hits is tried with MATCH,
; and only the scan whose hit failed is run again.
; Exit:   the cursor on the match's first byte, or "Not found".
; Callers: QPRE (FIND), CTAB ^L (FNEXT).
; =====================================================================
FIND:
	call PROMPT		; "Find: " and the string typed
	jnc short FIND_TYPED	; a string (maybe empty)
	ret			; ESC or ^U: given up
FIND_TYPED:				; (src: FI0)
	mov cx,[TLEN]		; CX = characters typed
	jcxz short FNEXT	; nothing typed: the last string again
	mov [FLEN],cx		; the new string, upper case, to FSTR
	mov si,TBUF		; from the typed characters
	mov di,FSTR		; to the search string
FIND_COPY:				; (src: FI1)
	lodsb			; a typed character
	call UPPER		; upper case
	stosb			; into FSTR
	loop short FIND_COPY	; all of them
FNEXT:
	mov cx,[FLEN]		; from after the cursor on
	jcxz short FIND_X	; no string yet: nothing
	mov si,[GAPE]		; from the byte after the gap ...
	inc si			; (a match at the cursor is the last one found)
	mov bx,[TEND]		; ... to TEND - FLEN + 1
	sub_d bx,cx		; (no match can start later)
	inc bx			; BX: where a match can start, below
	mov al,[FSTR]		; the first letter (upper case)
	mov [FC1],al		; first letter, upper case
	mov_d ah,al		; AH = its small form, if a letter
	cmp al,'A'		; a letter: its small form too
	jc short FIND_CASE	; below 'A': not a letter
	cmp al,'Z'		; above 'Z' ...
	ja short FIND_CASE	; ... not a letter
	or ah,0x20		; the small letter
FIND_CASE:				; (src: FN0)
	mov [FC2],ah		; (= FC1 if not a letter: both scans agree)
	call SCANF		; the first letter, both cases: the nearer
	mov [FP1],ax		; one is where the string may be
	mov al,[FC2]		; the small-letter scan
	call SCANF		; from SI
	mov [FP2],ax		; FP2 = its next place
FIND_TRY:				; (src: FN1)
	mov ax,[FP1]		; AX = the nearer candidate
	cmp ax,[FP2]		; the nearer of the two
	jna short FIND_NEAR	; FP1 is
	mov ax,[FP2]		; FP2 is
FIND_NEAR:				; (src: FN2)
	cmp ax,0xffff		; neither case occurs again: not found
	jz short NOTF		; none left: not found
	push ax			; (the candidate, kept)
	call MATCH		; the rest of the string there?
	pop ax			; AX = the candidate
	jz short FOUND		; ZF=1: here
	mov_d si,ax		; no: look again after this candidate
	inc si			; SI = past the candidate
	cmp ax,[FP1]		; renew the scan that gave it ...
	jnz short FIND_RENEW_LOWER	; not the upper-case scan's hit
	push ax			; (the candidate, kept)
	mov al,[FC1]		; the upper-case letter
	call SCANF		; from past the candidate
	mov [FP1],ax		; its next place
	pop ax			; AX = the candidate
FIND_RENEW_LOWER:				; (src: FN3)
	cmp ax,[FP2]		; ... (both, for a non-letter)
	jnz short FIND_TRY	; not the lower-case scan's hit
	mov al,[FC2]		; the lower-case letter
	call SCANF		; from past the candidate
	mov [FP2],ax		; its next place
	jmp short FIND_TRY	; try again
FOUND:
	jmp MOVETO		; the cursor on the match
NOTF:
	mov word [MSG],MNOTF	; "Not found"; the cursor stays
FIND_X:					; (src: FX)
	ret			; (MSG shows on the next STATUS)

; ---------------------------------------------------------------------
; SCANF - AX = the first AL from SI on, below BX (FFFFH: none).
; Corrupts CX, DI.  Callers: FNEXT.
; ---------------------------------------------------------------------
SCANF:
	mov_d di,si		; (SCASB uses DI)
	mov_d cx,bx		; CX = bytes to look at; none (or SI past
	sub_d cx,si		;   BX, a borrow) -> FFFFh
	jna short SCANF_NONE	; (CF or ZF: nothing to scan)
	repne scasb		; look for AL
	jnz short SCANF_NONE	; not found
	lea ax,[di-0x1]		; the byte found
	ret			; AX = its address
SCANF_NONE:				; (src: SFN)
	mov ax,0xffff		; none
	ret			; AX = FFFFh

; ---------------------------------------------------------------------
; MATCH - ZF=1 if the rest of the string follows AX (the first letter
; already matched).  Text bytes are folded with UPPER.
; Corrupts AL, CX, SI, DI.  Callers: FNEXT.
; ---------------------------------------------------------------------
MATCH:
	mov_d si,ax		; text after the first letter
	inc si			; the byte after the first letter
	mov di,FSTR+1		; string after its first letter
	mov cx,[FLEN]		; the string's length
	dec cx			; one letter only: ZF=1 already
	jz short MATCH_X	; (ZF=1 from DEC: a match)
MATCH_LOOP:				; (src: MA1)
	lodsb			; the text's byte
	call UPPER		; upper case
	cmp al,[di]		; against the string's
	jnz short MATCH_X	; a difference: ZF=0
	inc di			; the next string byte
	loop short MATCH_LOOP	; the rest
	cmp_d al,al		; all equal: ZF=1
MATCH_X:				; (src: MAX)
	ret			; ZF=1 match, ZF=0 not

; =====================================================================
; PROMPT - "Find: " on the status line, then a line typed into TBUF
; (RETURN ends it, DEL takes back); CF=1 if ESC or ^U gave up
; ---------------------------------------------------------------------
; The typed characters are echoed straight after the prompt (the
; terminal's cursor follows the output).  At most FMAX characters;
; control keys other than these are ignored.  SHMSG = 1, a value no
; message has, so the next STATUS rewrites the message field.  An
; arrow key here sends ESC: the prompt is given up and the letter that
; follows is inserted by MAIN (findings).
; Corrupts AX, BX, CX, SI, DI.  Callers: FIND.
; =====================================================================
PROMPT:
	mov si,MFIND		; "Find: " ...
	mov [MSG],si		; shown by STATUS
	call STATUS		; ... at MSGC, the cursor after it
	mov word [MSG],0x0	; (STATUS has sent it)
	mov word [SHMSG],0x1	; the message area is sent again later
	mov word [TLEN],0x0	; nothing typed yet
PROMPT_KEY:				; (src: PR1)
	call FLUSH		; the echo so far
	call GETKEY		; a key
	cmp al,CR		; RETURN: done
	jz short PRX		; done
	cmp al,KESC		; ESC or ^U: give up
	jz short PROMPT_ESC	; (ESC: an arrow's letter follows)
	cmp al,KEY_CTLU		; ^U?
	jz short PRQ		; (^U)
	mov bx,[TLEN]		; BX = characters so far
	cmp al,KEY_DEL		; DEL or ^H: take one back
	jz short PRDEL		; (DEL)
	cmp al,KEY_BS		; ^H?
	jz short PRDEL		; (^H)
	cmp al,0x20		; other control keys: ignored
	jc short PROMPT_KEY	; (other control keys)
	cmp bx,byte FMAX	; full: ignored
	jnc short PROMPT_KEY	; (no room)
	mov [bx+TBUF],al	; keep it
	inc word [TLEN]		; one more
	call PUTC		; and echo it
	jmp short PROMPT_KEY	; (next key)
PRDEL:
	or_d bx,bx		; nothing to take back
	jz short PROMPT_KEY	; (nothing typed)
	dec bx			; one fewer
	mov [TLEN],bx		; TLEN = BX
	mov_d ax,bx		; column of the character taken back:
	add al,MSGC+6		; after "Find: "
	mov ah,0x0		; row 0
	call PUTPOS		; ESC Y 0 col
	call PUTEOL		; rub it (and the cursor stays there)
	jmp short PROMPT_KEY	; (next key)
PRX:
	clc			; a string (maybe empty) in TBUF / TLEN
	ret			; CF=0
PROMPT_ESC:				; (src: PRESC)
	call GETKEY		; take the arrow's letter too, as ESCK does
PRQ:
	stc			; given up
	ret			; CF=1

; ---------------------------------------------------------------- marks
; ---------------------------------------------------------------------
; MARKC - the cursor's row, from the cursor on: DIRTY[CROW] lowered to
; CCOL - LEFT (a mark only ever moves left).  Uses CCOL / LEFT / CROW
; as FIXSCR last left them, so it must run before the cursor moves.
; Corrupts AX, BX.  Callers: INSCH, SPLIT, DELF, DELEOL, DELWD, FIXSCR.
; ---------------------------------------------------------------------
MARKC:
	mov ax,[CCOL]		; the cursor's screen column
	sub ax,[LEFT]		; (relative to LEFT)
	mov bx,[CROW]		; the cursor's row
	cmp al,[bx+DIRTY]	; already marked further left (or 0)?
	jnc short MARK_X	; no: keep it
	mov [bx+DIRTY],al	; from here
MARK_X:					; (src: MCX)
	ret			; (DIRTY[CROW] = min(old, column))

; ---------------------------------------------------------------------
; MARKB - the rows below the cursor's; MARKR - the rows from AX on
; (AX < 0 counts as 0), each marked whole (0).
; Corrupts AX, CX, DI.  Callers: MARKB: INSCH, SPLIT, DELF; MARKR:
; DELB, DELLN, ALLD.
; ---------------------------------------------------------------------
MARKB:
	mov ax,[CROW]		; the rows after the cursor's
	inc ax			; CROW + 1
MARKR:
	or_d ax,ax		; negative: from row 0
	jns short MARKR_FROM	; (AX >= 0)
	xor_d ax,ax		; 0
MARKR_FROM:				; (src: MR1)
	mov cx,[NR]		; CX = rows from AX to the bottom
	sub_d cx,ax		; (NR - AX)
	jna short MARK_X	; none (AX = NR: below the last row)
	mov_d di,ax		; DI = DIRTY[AX]
	add di,DIRTY		; (the mark array)
	xor_d al,al		; 0 = from column 0
	rep stosb		; every row from AX: 0
	ret			; (marks only ever move left)

; ALLD - every row, all of it; FULL also stops terminal scrolls until
; DRAW has sent them all.  Callers: REDRAW, FIXSCR, SETTOP.
ALLD:
	xor_d ax,ax		; from row 0
	call MARKR		; every row whole
	mov byte [FULL],0x1	; no scrolling until DRAW is through
	ret			; (DRAW clears FULL)

; REDRAW - clear the terminal, then everything is to be sent.
; Callers: START, AFTDOS, HELP.
REDRAW:
	call CLS		; ESC H ESC J (queued)
	call ALLD		; every row whole
	mov byte [STFULL],0x1	; and the status line in full
	ret			; (sent on the next MAIN pass)

; ---------------------------------------------------------------- the screen
; =====================================================================
; FIXSCR - the cursor's line and column; the top line and the first
; column shown, so that the cursor is on the screen
; ---------------------------------------------------------------------
; Runs first in every MAIN pass and restores the view invariants:
;   CLS_  = start of the cursor's line;  CCOL = its column (tabs to the
;           next multiple of 8); GOAL = CCOL unless the key was UP/DOWN.
;   Rows: LINE - TOPLN in 0..NR-1: nothing to do.  Exactly one line
;   below / above the screen: TOP moves by one line and the terminal is
;   scrolled (SCRUP / SCRDN) - unless FULL says every row will be sent
;   anyway.  Further: the cursor's line goes to the middle (SETTOP).
;   Columns: CCOL outside LEFT..LEFT+W-1: LEFT = CCOL - W/2, down to a
;   multiple of 8, between 0 and LMAX - W, and every row is marked.  A
;   cursor past column LMAX-1 cannot be shown: PLACE parks it on the
;   last column used (findings).
;   Then the MARKF request of DELB.
; Corrupts AX, BX, CX, DX, SI, DI.  Callers: MAIN.
; =====================================================================
FIXSCR:
	mov ax,[GAPS]		; CLS_, CCOL
	call LSOF		; AX = start of the cursor's line
	mov [CLS_],ax		; kept for DRAW, DELLN
	mov_d si,ax		; CX = bytes from the line start to the cursor
	mov cx,[GAPS]		; (GAPS - line start)
	sub_d cx,si		; CX = bytes before the cursor
	jcxz short FIXSCR_SETCOL	; at the line start: column 0
	mov_d di,si		; any tab among them?
	mov al,TAB		; the tab character
	push cx			; (count kept)
	repne scasb		; scan for a tab
	pop cx
	jnz short FIXSCR_SETCOL	; no tab: a column a byte
	xor_d dx,dx		; with tabs: count column by column
FIXSCR_COUNT:				; (src: FS2)
	lodsb			; a byte
	cmp al,TAB		; a tab?
	jnz short FIXSCR_ONE	; no: one column
	or dx,0x7		; a tab: to the next multiple of 8
FIXSCR_ONE:				; (src: FS2A)
	inc dx			; one column (the tab's last)
	loop short FIXSCR_COUNT	; every byte
	mov_d cx,dx		; CX = the column
FIXSCR_SETCOL:				; (src: FS3)
	mov [CCOL],cx		; the cursor's column
	cmp byte [VERT],0x0	; after UP / DOWN the goal column stays
	jnz short FIXSCR_ROWS	; (VERT = 1)
	mov [GOAL],cx		; the column up / down aim for
FIXSCR_ROWS:				; (src: FS4)
	mov ax,[LINE]		; the row
	sub ax,[TOPLN]		; (LINE - TOPLN)
	jc short FIXSCR_ABOVE	; above the top line
	cmp ax,[NR]		; (rows 0..NR-1)
	jc short FIXSCR_SETROW	; on the screen
	ja short FIXSCR_CENTRE	; more than one below
	mov di,[TOP]		; one below: a line up
	mov bx,[GAPS]		; (before the gap)
	call NEXTLF		; the top line's LF (before the cursor)
	inc di			; DI = start of the second line
	mov [TOP],di		; the next line is the top one
	inc word [TOPLN]	; one line further down
	cmp byte [FULL],0x0	; all rows to be sent anyway?
	jnz short FIXSCR_BOTTOM	; (no terminal scroll)
	call SCRUP		; no: let the terminal scroll them
FIXSCR_BOTTOM:				; (src: FS5)
	mov ax,[NR]		; the cursor on the bottom row
	dec ax			; (NR - 1)
	jmp short FIXSCR_SETROW	; (store it)
FIXSCR_ABOVE:				; (src: FSUP)
	inc ax			; exactly one above?
	jnz short FIXSCR_CENTRE	; (more than one above)
	mov ax,[CLS_]		; one above: a line down
	mov [TOP],ax		; the cursor's line is the top one
	mov ax,[LINE]		; TOPLN = LINE
	mov [TOPLN],ax		; (the cursor is on row 0)
	cmp byte [FULL],0x0	; all rows to be sent anyway?
	jnz short FIXSCR_TOPROW	; yes: no scroll
	call SCRDN		; the terminal scrolls down
FIXSCR_TOPROW:				; (src: FS6)
	xor_d ax,ax		; the cursor on row 0
	jmp short FIXSCR_SETROW	; (store it)
FIXSCR_CENTRE:				; (src: FSCEN)
	mov ax,[CLS_]		; further: the cursor's line in the middle
	mov cx,[NR]		; (NR / 2)
	shr cx,1		; NR/2 lines above it (fewer near the start)
	call SETTOP		; sets TOP, TOPLN, CROW; marks everything
	mov ax,[CROW]		; (the row SETTOP found)
FIXSCR_SETROW:				; (src: FSROW)
	mov [CROW],ax		; the cursor's row
	mov ax,[CCOL]		; the columns
	cmp ax,[LEFT]		; left of the window?
	jc short FIXSCR_HSCROLL	; yes: move the window
	mov bx,[LEFT]		; right of it (past LEFT + W - 1)?
	add bx,[W]		; (LEFT + W - 1)
	dec bx			; the window's last column
	cmp_d ax,bx		; within it?
	jna short FIXSCR_MARKF	; yes: LEFT stays
FIXSCR_HSCROLL:				; (src: FSH)
	mov bx,[W]		; LEFT = CCOL - W/2 ...
	shr bx,1		; (W / 2)
	sub_d ax,bx		; AX = CCOL - W/2
	jnc short FIXSCR_ROUND	; (no borrow: >= 0)
	xor_d ax,ax		; ... not below 0,
FIXSCR_ROUND:				; (src: FSH1)
	and ax,0xfff8		; ... a multiple of 8 (tab stops line up),
	mov bx,LMAX		; ... and not past LMAX - W (EBUF's end)
	sub bx,[W]		; (LMAX - W)
	cmp_d ax,bx		; past it?
	jna short FIXSCR_SETLEFT	; no
	mov_d ax,bx		; the farthest LEFT can go
FIXSCR_SETLEFT:				; (src: FSH2)
	cmp ax,[LEFT]		; unchanged (cursor beyond LMAX): no redraw
	jz short FIXSCR_MARKF	; (no change)
	mov [LEFT],ax		; the new first column
	call ALLD		; every row shifts sideways
FIXSCR_MARKF:				; (src: FSM)
	cmp byte [MARKF],0x0	; DELB's request: now CCOL / CROW are known
	jz short FIXSCR_X	; (none)
	mov byte [MARKF],0x0	; (done once)
	call MARKC		; the row from the new cursor
FIXSCR_X:				; (src: FSX)
	ret			; (the view is right)

; =====================================================================
; SETTOP - the top line CX lines above the line at AX (fewer at the start)
; ---------------------------------------------------------------------
; Entry:  AX = start of the cursor's line (before the gap), CX = rows
;         wanted above it.
; Exit:   TOP, CROW (= lines actually walked), TOPLN = LINE - CROW;
;         every row marked (ALLD) if TOPLN changed.
; Corrupts AX, CX, DX, DI.  Callers: FIXSCR (centre), KEEPRW (pages).
; =====================================================================
SETTOP:
	xor_d dx,dx		; DX = lines walked
SETTOP_UP:				; (src: ST1)
	jcxz short SETTOP_SET	; enough
	cmp ax,[BUFS]		; the first line: no more above
	jz short SETTOP_SET	; (no more lines above)
	dec ax			; into the line above ...
	push cx			; (LSOF corrupts CX)
	push dx			; (and its CX/DI; DX kept)
	call LSOF		; ... to its start
	pop dx
	pop cx
	inc dx			; one row more above the cursor
	dec cx			; one fewer to go
	jmp short SETTOP_UP
SETTOP_SET:				; (src: ST2)
	mov [TOP],ax		; the top line
	mov [CROW],dx		; the cursor's row
	mov ax,[LINE]		; (LINE - rows above)
	sub_d ax,dx		; the top line's number
	cmp ax,[TOPLN]		; (MOV keeps the flags of this CMP)
	mov [TOPLN],ax		; (stored; ZF still from the CMP)
	jz short SETTOP_X	; the same top line: the screen stands
	call ALLD		; (changed: every row)
SETTOP_X:				; (src: ST3)
	ret			; (TOP, TOPLN, CROW set)

; =====================================================================
; SCRUP - LF on the bottom row moves every row up; SCRDN - ESC I on
; the top row moves them down.  The marks move with the rows; the
; status line is sent again.
; ---------------------------------------------------------------------
; The terminal scrolls its whole screen, the status line with it: after
; SCRUP the old text row 0 sits on screen row 0, after SCRDN the old
; status line sits on text row 0 (marked whole, so it is overwritten),
; and screen row 0 is in either case resent in full (STFULL).  DIRTY is
; shifted one place with the rows and the row brought in is marked
; whole.  Terminal behaviour after the Terminal 3000 ROM (OVERVIEW 2.7)
; and test_edit.py's terminal model, which demands exactly one scroll
; per one-line move; confirmed on a real FDD3000 + TC2048 / TC2068
; (notes/hardware_run.md).  Corrupts AX, CX, SI, DI.  Callers: FIXSCR.
; =====================================================================
SCRUP:
	mov ax,[NR]		; ESC Y to the bottom row (screen row NR),
	mov_d ah,al		;   column 0
	xor_d al,al		; (AL = 0: column 0)
	call PUTPOS		; (ESC Y NR+32 32)
	mov al,LF		; a LF there scrolls the screen up
	call PUTC		; (queued: sent with the next FLUSH)
	mov di,DIRTY		; marks: row r+1 -> row r
	mov si,DIRTY+1		; (the marks one row down)
	mov cx,[NR]		; NR - 1 of them
	dec cx			; (the bottom one is new)
	rep movsb		; shifted up
	mov byte [di],0x0	; the new bottom row: all of it
	mov byte [STFULL],0x1	; the status line scrolled away
	ret			; (the rows come with DRAW)

SCRDN:
	xor_d ax,ax		; ESC Y to row 0 (the status row)
	call PUTPOS		; (ESC Y 32 32)
	mov al,KESC		; ESC I on row 0 scrolls the screen down
	call PUTC
	mov al,VT_RLF		; I
	call PUTC
	mov cx,[NR]		; marks: row r -> row r+1, from the bottom
	mov_d di,cx		; (DI = NR)
	add di,DIRTY-1		; DI = DIRTY[NR-1]
	lea si,[di-0x1]		; SI = DIRTY[NR-2]
	dec cx			; NR - 1 marks
	std			; downward
	rep movsb		; shifted down
	cld			; upward again
	mov byte [di],0x0	; DIRTY[0]: the new top row, all of it
	mov byte [STFULL],0x1	; screen row 0 is blank now
	ret			; (the rows come with DRAW)

; =====================================================================
; DRAW - the marked rows, top to bottom; CF=1 if a key came first
; ---------------------------------------------------------------------
; 1. Two REPE SCASB find the first marked row (DRROW) and the last
;    (DRLAST); with none, done.
; 2. If the first is above the cursor's row, the rows from the top
;    line (TOP, before the gap: each line one piece P1/N1) down to
;    min(DRLAST, CROW-1) are walked - from row 0, since line starts are
;    only known by walking from TOP.
; 3. The cursor's row: its line in two pieces, CLS_..GAPS-1 and
;    GAPE..its LF.  Rows above the first mark are thus never walked
;    when the first mark is at or below the cursor.
; 4. The rows below, from the line after the cursor's, to DRLAST; past
;    the end of the text (DREOT) a row is sent empty (just ESC K).
; DRAWR sends a row only if it is marked, and checks for a key before
; each one: a waiting key stops DRAW with CF=1, the remaining marks
; (and FULL) left for the next pass.  CF=0: all sent, FULL = 0.
; Corrupts AX, BX, CX, DX, SI, DI.  Callers: MAIN.
; =====================================================================
DRAW:
	mov di,DIRTY		; the first and the last marked rows: the
	mov cx,[NR]		; lines of the others are not even looked at
	mov al,0xff		; clean mark
	repe scasb		; skip the clean rows
	jnz short DRAW_SOME	; one is marked
	jmp DRDONE		; every row is clean
DRAW_SOME:				; (src: DR0)
	sub di,DIRTY+1		; SCASB stepped one past the first mark
	mov [DRROW],di		; the first marked row
	mov di,DIRTY-1		; from DIRTY[NR-1] downward
	add di,[NR]		; (DIRTY + NR - 1)
	mov cx,[NR]		; NR marks
	std			; downward
	repe scasb		; skip the clean rows from the bottom
	cld			; upward again
	sub di,DIRTY-1		; again one past (below) the last mark
	mov [DRLAST],di		; the last marked row
	mov ax,[DRROW]		; the first marked row ...
	cmp ax,[CROW]		; ... above the cursor's?
	jnc short DRAW_CURSOR_ROW	; none above the cursor's row
	mov word [DRROW],0x0	; walk from the top line
	mov ax,[TOP]		; (TOP is before the gap)
	mov [DRP],ax		; the first row's line
	jmp short DRAW_ABOVE	; (above the cursor)
DRAW_DONE_EARLY:				; (src: DRDN0)
	mov byte [FULL],0x0	; everything sent
	clc			; CF=0
	ret			; (STATUS / PLACE follow)
DRAW_ABOVE:				; (src: DR1)
	mov bx,[DRROW]		; the rows above the cursor's
	cmp bx,[DRLAST]		; past the last mark: done
	ja short DRAW_DONE_EARLY	; (nothing more marked)
	cmp bx,[CROW]		; at the cursor's row: its own way
	jnc short DRAW_CURSOR_ROW	; (the cursor's own line)
	mov di,[DRP]		; this row's line: DRP .. its LF
	push bx			; (the row, kept)
	mov bx,[GAPS]		; (always found before the gap)
	call NEXTLF		; DI = the LF ending this row's line
	pop bx
	mov si,[DRP]		; SI = the line's start
	mov [P1],si		; one piece
	sub_d di,si		; (LF - start)
	mov [N1],di		; N1 = its length
	inc di			; DRP = start of the next line
	add [DRP],di		; DRP past the LF
	mov word [N2],0x0	; no second piece
	call DRAWR		; sent if marked, unless a key is waiting
	jnc short DRAW_ABOVE_NEXT	; (sent or clean)
	ret			; CF=1: a key
DRAW_ABOVE_NEXT:			; (src: DR1A)
	inc word [DRROW]	; the next row
	jmp short DRAW_ABOVE
DRAW_CURSOR_ROW:			; (src: DR2)
	mov ax,[CROW]		; the cursor's row: the line in two pieces
	cmp ax,[DRLAST]		; below the last mark: done
	ja short DRAW_DONE_EARLY	; (nothing more marked)
	mov [DRROW],ax		; the row to draw
	mov ax,[CLS_]		; piece 1: line start .. cursor
	mov [P1],ax		; P1 = the line's start
	mov cx,[GAPS]		; (to the cursor)
	sub_d cx,ax		; CX = bytes before the cursor
	mov [N1],cx		; N1
	mov di,[GAPE]		; piece 2: after the gap .. the LF
	mov [P2],di		; P2 = GAPE
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF, or TEND
	mov byte [DREOT],0x0	; (a LF: more lines follow)
	jnc short DRAW_CURSOR_LEN	; (found)
	mov byte [DREOT],0x1	; no LF: the last line of the text
DRAW_CURSOR_LEN:			; (src: DR3)
	mov_d ax,di		; (LF - GAPE)
	sub ax,[GAPE]		; bytes after the cursor
	mov [N2],ax		; N2
	inc di			; the next line
	mov [DRP],di		; the next line's start
	call DRAWR		; send it if marked
	jc short DRAW_X		; a key: stop
DRAW_BELOW:				; (src: DR4)
	inc word [DRROW]	; the rows below
	mov bx,[DRROW]		; the row
	cmp bx,[DRLAST]		; past the last mark: done
	ja short DRDONE		; (nothing more marked)
	mov word [N1],0x0	; an empty row by default
	mov word [N2],0x0	; (N1 = N2 = 0: ESC K only)
	cmp byte [DREOT],0x0	; past the end of the text?
	jnz short DRAW_SEND	; (an empty row)
	mov di,[DRP]		; this row's line: DRP .. its LF
	mov [P1],di		; P1 = the line's start
	mov bx,[TEND]		; (to the end of the text)
	call NEXTLF		; DI = the LF, or TEND
	jnc short DRAW_BELOW_LEN	; (found)
	mov byte [DREOT],0x1	; the last line
DRAW_BELOW_LEN:				; (src: DR6)
	mov_d ax,di		; (LF - start)
	sub ax,[DRP]		; bytes in the line
	mov [N1],ax		; N1
	inc di			; past the LF
	mov [DRP],di		; the next line's start
DRAW_SEND:				; (src: DR5)
	call DRAWR		; send it if marked
	jnc short DRAW_BELOW	; (next row)
DRAW_X:					; (src: DRX)
	ret			; CF=1: a key is waiting
DRDONE:
	mov byte [FULL],0x0	; every marked row sent
	clc			; CF=0
	ret			; (STATUS / PLACE follow)

; ---------------------------------------------------------------------
; DRAWR - row DRROW, if marked, unless a key is waiting (CF=1).
; Callers: DRAW.
; ---------------------------------------------------------------------
DRAWR:
	mov bx,[DRROW]		; the row
	cmp byte [bx+DIRTY],0xff	; clean: nothing to send
	jz short DRAWR_OK	; (nothing to do)
	call KEYRDY		; a key typed: stop drawing
	stc			; (CF=1 if so)
	jnz short DRAWR_X	; a key: CF=1 out
	call ROWOUT		; send the row
DRAWR_OK:				; (src: DWX)
	clc			; CF=0: go on
DRAWR_X:				; (src: DWR)
	ret			; (CF: 1 = stop)

; =====================================================================
; ROWOUT - send row DRROW from its mark on: the pieces P1/N1, P2/N2
; with their tabs expanded, the columns LEFT.. of them, and ESC K
; ---------------------------------------------------------------------
; The line is expanded into EBUF up to column LEFT + W only; the part
; from LEFT + mark to there is queued after ESC Y row col, then ESC K
; clears the rest.  The last screen column (W) is never written: the
; terminal would wrap there (test_edit.py checks it on every step).
; The mark becomes FFh.  PUTEOL (ESC K) is also entered from PROMPT
; and PUTMSG.  Corrupts AX, BX, CX, DX, SI, DI.  Callers: DRAWR.
; =====================================================================
ROWOUT:
	call FLUSHQ		; room in OBUF for a row
	mov di,BUFFERS+EBOFF	; expand into EBUF
	mov dx,[LEFT]		; DX = EBUF + LEFT + W:
	add dx,[W]		; (the first column not shown)
	add_d dx,di		; DX: no more is needed
	mov si,[P1]		; piece 1
	mov cx,[N1]		; (may be 0 bytes)
	call EXPAND		; tabs out, into EBUF
	mov si,[P2]		; the second piece goes on at the same
	mov cx,[N2]		;   column, so tab stops stay right
	call EXPAND		; (DI goes on)
	cmp_d di,dx		; a tab may have run past the limit
	jna short ROWOUT_SEND	; (no)
	mov_d di,dx		; (clamp)
ROWOUT_SEND:				; (src: RO1)
	mov bx,[DRROW]		; the row
	mov al,[bx+DIRTY]	; AL = the first column to send
	mov byte [bx+DIRTY],0xff	; the row will be right
	mov_d ah,bl		; AH = screen row = text row + 1
	inc ah			; (screen row)
	push ax			; (kept)
	call PUTPOS		; ESC Y row col
	pop ax			; AL = the first column again
	xor_d ah,ah		; AX = the column
	mov si,BUFFERS+EBOFF	; SI = EBUF + LEFT + mark
	add si,[LEFT]		; (+ LEFT)
	add_d si,ax		; (+ mark)
	mov_d cx,di		; CX = what is left of the line there
	sub_d cx,si		; (DI - SI)
	jna short PUTEOL	; nothing: just clear the row's end
	mov di,[OPTR]		; queue those characters
	rep movsb		; queued
	mov [OPTR],di		; (OBUF's new end)
PUTEOL:
	mov al,KESC		; ESC K: clear to the end of the line
	call PUTC
	mov al,VT_EOL		; K
	jmp PUTC		; (queued; PUTC returns for us)

; =====================================================================
; EXPAND - CX bytes at SI to DI, tabs as spaces to the next column
; that is a multiple of 8, other control bytes as "?"; up to DX at most
; (a tab can go 7 past it)
; ---------------------------------------------------------------------
; Columns count from EBUF's start (the line's column 0).  Bytes 7Fh-FFh
; also show as '?'.  Every shown byte is one column, as FIXSCR and WALK
; count, so the cursor lands on its character.  EBUF has 16 bytes of
; slack for the tab overrun.  Corrupts AX, CX, SI, DI.  Callers: ROWOUT.
; =====================================================================
EXPAND:
	jcxz short EXPAND_X	; nothing to expand
	mov_d ax,dx		; AX = columns still wanted
	sub_d ax,di		; (DX - DI)
	jna short EXPAND_X	; the limit is reached
	cmp_d cx,ax		; a byte is a column, but for tabs
	jna short EXPAND_BYTE	; all fit
	mov_d cx,ax		; only so many bytes
EXPAND_BYTE:				; (src: EX1)
	lodsb			; a byte of the line
	cmp al,0x20		; control byte?
	jc short EXPAND_CTL	; (below 20h)
	cmp al,0x7f		; DEL and above: '?'
	jnc short EXPAND_QUERY	; (7Fh-FFh)
EXPAND_PUT:				; (src: EX2)
	stosb			; shown as it is
	loop short EXPAND_BYTE	; (next byte)
EXPAND_X:				; (src: EXX)
	ret			; (DI = past the expanded bytes)
EXPAND_QUERY:				; (src: EXQ)
	mov al,'?'		; shown as '?'
	jmp short EXPAND_PUT	; (stored)
EXPAND_CTL:				; (src: EXC)
	cmp al,TAB		; a tab?
	jnz short EXPAND_QUERY	; not a tab: '?'
	push cx			; (byte count kept)
	mov_d cx,di		; CX = spaces to the next multiple of 8:
	sub cx,BUFFERS+EBOFF	;   ((col | 7) + 1) - col
	or cx,0x7		; (col | 7)
	inc cx			; (+ 1: the next tab stop)
	add cx,BUFFERS+EBOFF	; (as an address)
	sub_d cx,di		; CX = spaces to it
	mov al,0x20		; space
	rep stosb		; fill to the tab stop
	pop cx			; (byte count back)
	dec cx			; the tab byte is done
	jz short EXPAND_X	; (no bytes left)
	mov_d ax,dx		; re-clamp CX to the columns left
	sub_d ax,di		; (DX - DI)
	jna short EXPAND_X	; (the limit is reached)
	cmp_d cx,ax		; more bytes than columns?
	jna short EXPAND_BYTE	; no
	mov_d cx,ax		; (clamp)
	jmp short EXPAND_BYTE	; (next byte)

; =====================================================================
; STATUS - the status line, row 0: the whole of it, or the fields that
; changed
; ---------------------------------------------------------------------
;   col 0      " A:NAME.EXT" + '*' or ' ' (at MODC), padded to 17 columns,
;              in inverse (ESC L .. ESC M)
;   col 17     " Line " + LINE, 5 columns     (number at LNUMC = 23)
;   col 28     " Col "  + CCOL+1, 5 columns   (number at CNUMC = 33)
;   col 38     ' ', then the message          (at MSGC = 39), ESC K
; Each field has a shadow (SHMOD, SHLINE, SHCOL, SHMSG) holding what the
; terminal shows; only a field that differs is sent, after ESC Y to its
; column.  The longest message ("Abandon changes (Y/N)? ") ends at
; column 62, inside a 64-column terminal's W.
; Corrupts AX, BX, CX, DX, SI.  Callers: MAIN, PREFIX, PROMPT.
; =====================================================================
STATUS:
	call FLUSHQ		; room in OBUF; STCUT for SF1
	cmp byte [STFULL],0x0	; (set after a scroll, REDRAW)
	jnz short SFULL		; the whole line
	mov al,[MODIF]		; the changed mark
	cmp al,[SHMOD]		; (what the terminal shows)
	jz short STATUS_LINE	; the same
	mov al,[MODC]		; ESC Y 0 MODC, inverse, '*' or ' '
	xor_d ah,ah		; (row 0)
	call PUTPOS		; ESC Y 0 MODC
	call INVON		; ESC L
	call PUTMOD		; '*' or ' '
	call INVOFF		; ESC M
STATUS_LINE:				; (src: SS1)
	mov ax,[LINE]		; the line number
	cmp ax,[SHLINE]		; (what is shown)
	jz short STATUS_COL	; the same
	mov ax,LNUMC		; row 0 (AH = 0), column 23
	call PUTPOS		; ESC Y 0 23
	call PUTLN		; nnnnn
STATUS_COL:				; (src: SS2)
	mov ax,[CCOL]		; the column, 1-based
	inc ax			; (1-based)
	cmp ax,[SHCOL]		; (what is shown)
	jz short STATUS_MSG	; the same
	mov ax,CNUMC		; (row 0, column 33)
	call PUTPOS		; ESC Y 0 33
	call PUTCN		; nnnnn
STATUS_MSG:				; (src: SS3)
	mov ax,[MSG]		; the message (compared as a pointer)
	cmp ax,[SHMSG]		; (what is shown)
	jz short STATUS_X	; the same
	mov ax,MSGC		; (row 0, column 39)
	call PUTPOS		; ESC Y 0 39
	call PUTMSG		; the message, ESC K
STATUS_X:				; (src: SS4)
	ret			; (the status line is right)

SFULL:
	mov byte [STFULL],0x0	; (done once)
	xor_d ax,ax		; ESC Y 0 0
	call PUTPOS		; ESC Y 32 32
	call INVON		; ESC L
	mov al,0x20		; " A:NAME.EXT*" in inverse, 17 columns
	call PUTC		; (column 0 is blank)
	mov al,[DRVL]		; the drive letter
	call PUTC		; (A)
	mov al,':'		; the colon
	call PUTC		; (:)
	mov si,FCB+FCB_NAME	; the name, to its first blank
	mov cx,0x8		; up to 8 characters
	call PUTNM		; (NAME)
	mov si,FCB+FCB_EXT	; '.' and the extension, if there is one
	cmp byte [si],0x20	; no extension?
	jz short SFULL_MARK	; (then no dot)
	mov al,'.'		; the dot
	call PUTC		; (.)
	mov cx,0x3		; up to 3 characters
	call PUTNM		; (EXT)
SFULL_MARK:				; (src: SF1)
	mov ax,[OPTR]		; the column of the mark
	sub ax,BUFFERS+OBOFF+6	;   = bytes queued since this line began,
	sub ax,[STCUT]		;   less ESC Y r c and ESC L (6 bytes)
	mov [MODC],al		; (column of '*')
	call PUTMOD		; '*' or ' '
	mov cl,STNAMEW		; pad the inverse field to 17 columns
	sub cl,[MODC]		; (17 - MODC ...
	dec cl			; ... - 1 for the mark itself)
	xor_d ch,ch		; CX = blanks to add
	mov al,0x20
SFULL_PAD:				; (src: SF2)
	call PUTC
	loop short SFULL_PAD
	call INVOFF		; ESC M
	mov si,MLINE		; " Line nnnnn"
	call PUTS		; (" Line ")
	call PUTLN		; the line number
	mov si,MCOL		; " Col nnnnn"
	call PUTS		; (" Col ")
	mov ax,[CCOL]		; the column ...
	inc ax			; ... 1-based
	call PUTCN		; (5 columns)
	mov al,0x20		; then the message at column 39
	call PUTC		; (column 38)
	jmp short PUTMSG	; the message at 39, ESC K

STCUT:
	dw 0	; bytes in OBUF before this status line

; ---------------------------------------------------------------------
; PUTMOD - '*' if MODIF else ' ', and SHMOD = MODIF.  Callers: STATUS,
; SFULL.
; ---------------------------------------------------------------------
PUTMOD:
	mov al,[MODIF]		; changed?
	mov [SHMOD],al		; the terminal will show this
	or_d al,al		; (ZF from MODIF)
	mov al,0x20		; (MOV keeps OR's flags)
	jz short PUTMOD_PUT	; unchanged: blank
	mov al,'*'		; changed: star
PUTMOD_PUT:				; (src: PM1)
	jmp PUTC		; (PUTC returns for us)

; PUTLN / PUTCN - LINE, CCOL+1 as 5 columns, noting the shadow.
; Callers: STATUS, SFULL.
PUTLN:
	mov ax,[LINE]		; the line number
	mov [SHLINE],ax		; (now shown)
	jmp short PUTNUM	; 5 columns
PUTCN:
	mov ax,[CCOL]		; the column ...
	inc ax			; ... 1-based
	mov [SHCOL],ax		; (now shown)

; ---------------------------------------------------------------------
; PUTNUM - AX in decimal, 5 columns, left-aligned (blank-padded).
; Corrupts AX, BX, CX, DX.  Callers: PUTLN, PUTCN.
; ---------------------------------------------------------------------
PUTNUM:
	mov bx,0xa		; decimal
	xor_d cx,cx		; CX = digits
PUTNUM_DIV:				; (src: PN1)
	xor_d dx,dx		; (DX:AX / 10)
	div bx			; the lowest digit, kept on the stack
	push dx			; (kept for printing)
	inc cx			; one more digit
	or_d ax,ax		; more digits?
	jnz short PUTNUM_DIV	; yes
	mov dx,0x5		; DX = blanks after them
	sub_d dx,cx		; (5 - digits)
PUTNUM_DIGIT:				; (src: PN2)
	pop ax			; highest digit first
	add al,'0'		; ASCII
	call PUTC
	loop short PUTNUM_DIGIT	; every digit
	mov_d cx,dx		; CX = blanks
	mov al,0x20
PUTNUM_PAD:				; (src: PN3)
	jcxz short PUTNUM_X	; (none)
	call PUTC
	loop short PUTNUM_PAD
PUTNUM_X:				; (src: PNX) - also PUTNM's
	ret			; (5 columns written)

; ---------------------------------------------------------------------
; PUTMSG - the message (or nothing), then ESC K; SHMSG = MSG.
; Callers: STATUS, SFULL.
; ---------------------------------------------------------------------
PUTMSG:
	mov si,[MSG]		; the message pointer
	mov [SHMSG],si		; (now shown)
	or_d si,si		; none?
	jz short PUTMSG_EOL	; none: just clear the field
	call PUTS		; (0-terminated)
PUTMSG_EOL:				; (src: PMS1)
	jmp PUTEOL		; ESC K clears the rest of row 0

; PUTNM - up to CX characters of a name at SI, to the first space.
; Callers: SFULL.
PUTNM:
	lodsb			; a name byte
	cmp al,0x20		; the blank padding ends it
	jz short PUTNUM_X	; (end of the name)
	call PUTC
	loop short PUTNM	; (at most CX)
	ret			; (the full length)

; ---------------------------------------------------------------------
; INVON / INVOFF - ESC L / ESC M: inverse on / off.  Each JMP PUTC was
; a forward reference to MASM, which reserved 3 bytes for it, found
; the target near and emitted a short JMP plus NOP.  Callers: STATUS,
; SFULL.
; ---------------------------------------------------------------------
INVON:
	mov al,KESC
	call PUTC
	mov al,VT_INVON		; L
	jmp short PUTC		; (PUTC returns for us)
	nop			; MASM's forward-JMP padding (never run)
INVOFF:
	mov al,KESC
	call PUTC
	mov al,VT_INVOFF	; M
	jmp short PUTC		; (PUTC returns for us)
	nop			; MASM's forward-JMP padding (never run)

; ---------------------------------------------------------------------
; PLACE - the terminal's cursor on the editor's (column clamped to
; W - 1, which only matters past column LMAX); falls into PUTPOS.
; Callers: MAIN.
; ---------------------------------------------------------------------
PLACE:
	mov ax,[CCOL]		; the cursor's screen column
	sub ax,[LEFT]		; (relative to LEFT)
	mov bx,[W]		; (W - 1: the last column used)
	dec bx
	cmp_d ax,bx		; beyond it?
	jna short PLACE_ROW	; no
	mov_d ax,bx		; (clamp)
PLACE_ROW:				; (src: PL1)
	mov ah,[CROW]		; screen row = text row + 1
	inc ah			; (the status row is 0)
; ---------------------------------------------------------------------
; PUTPOS - ESC Y, row AH, column AL (each + 32: VT52 direct cursor
; address); falls into PUTC.  Callers: many.
; ---------------------------------------------------------------------
PUTPOS:
	push ax			; (the position, kept)
	mov al,KESC
	call PUTC
	mov al,VT_CUP		; Y
	call PUTC
	pop ax
	push ax
	mov_d al,ah		; row + 32
	add al,VT_BIAS		; (+ 32)
	call PUTC
	pop ax			; AL = the column
	add al,VT_BIAS		; column + 32
; ---------------------------------------------------------------------
; PUTC - AL to the output buffer (no check: FLUSHQ keeps 128 bytes
; free before each row or status line).  Preserves all but OPTR.
; ---------------------------------------------------------------------
PUTC:
	push di			; (callers keep DI)
	mov di,[OPTR]		; the next free byte
	stosb			; stored
	mov [OPTR],di		; (advanced)
	pop di
	ret			; (no overflow check)

; PUTS - the string at SI, to its 0.  Callers: STATUS, PUTMSG.
PUTS:
	lodsb			; a byte
	or_d al,al		; the end?
	jz short PUTS_X		; yes
	call PUTC
	jmp short PUTS
PUTS_X:					; (src: PSX)
	ret			; (SI past the 0)

; ---------------------------------------------------------------------
; FLUSHQ - send the output buffer if it is getting full (896 bytes,
; OBSZ - 128); STCUT = what is left in it.  Callers: ROWOUT, STATUS,
; HELP.
; ---------------------------------------------------------------------
FLUSHQ:
	mov ax,[OPTR]		; bytes queued
	sub ax,BUFFERS		; (OPTR - OBUF)
	cmp ax,OBSZ-128		; 896: room for one more row or status line?
	jc short FLUSHQ_KEEP	; yes: keep it
	call FLUSH		; send it all now
	xor_d ax,ax		; empty now
FLUSHQ_KEEP:				; (src: FQ1)
	mov [STCUT],ax		; (the column base for SFULL)
	ret			; (nothing sent if not needed)

; =====================================================================
; FLUSH - the output buffer to the terminal
; ---------------------------------------------------------------------
; One INT 10h AH=0Eh per byte (INT 10h -> IO.SYS stub TRAP 10h -> T_I10
; in z86sys.asm -> CONOUT): about 3 900 T-states a character against
; 1 900 for the BIOS alone (emulator figure, project README), so a
; full screen costs about a second.  AH is set once: T_I10 does not
; write AX back for function 0Eh.  BH (the page on a PC) is not set;
; T_I10 ignores BL / BH.  Corrupts AX, CX, SI.  Callers: MAIN, PREFIX,
; PROMPT, FLUSHQ, EXIT, HELP.
; =====================================================================
FLUSH:
	mov si,BUFFERS		; from the start of OBUF ...
	mov cx,[OPTR]		; ... to OPTR; and the buffer is empty again
	mov [OPTR],si		; OPTR back to OBUF's start
	sub_d cx,si		; CX = bytes queued
	jcxz short FLUSH_X	; nothing queued
	mov ah,VID_TTY		; teletype output
FLUSH_LOOP:				; (src: FL1)
	lodsb			; a byte
	int byte 0x10		; INT 10h AH=0Eh: to the terminal
	loop short FLUSH_LOOP	; (every byte)
FLUSH_X:				; (src: FLX)
	ret			; (OBUF empty)

; CLS - ESC H ESC J: home, clear the screen (queued).
; Callers: REDRAW, EXIT, HELP.
CLS:
	mov al,KESC
	call PUTC
	mov al,VT_HOME		; H
	call PUTC
	mov al,KESC
	call PUTC
	mov al,VT_EOS		; J
	jmp short PUTC		; (PUTC returns for us)

; ---------------------------------------------------------------------
; KEYRDY - ZF=0 if a key is waiting (INT 16h AH=1 -> IO.SYS stub TRAP
; 16h -> T_I16: PEEKEY; the key stays queued); GETKEY - AL = the next
; key (INT 16h AH=0, waits; AH = 0, no scan codes on a terminal).
; Corrupts AX.
; ---------------------------------------------------------------------
KEYRDY:
	mov ah,KBD_PEEK		; look, do not take
	int byte 0x16		; ZF=1 none, ZF=0 a key
	ret			; (the key stays queued)
GETKEY:
	mov ah,KBD_READ		; wait and take
	int byte 0x16		; AL = the key
	ret			; (AH = 0)

; ---------------------------------------------------------------------
; HELP - ^J: the keys (MHELP) on a clear screen, until a key is
; pressed; then everything again.  Callers: CTAB.
; ---------------------------------------------------------------------
HELP:
	call CLS		; ESC H ESC J
	mov si,MHELP		; the key list
HELP_CHAR:				; (src: HE1)
	call FLUSHQ		; ~600 bytes: sent in pieces
	lodsb			; a byte of it
	or_d al,al		; the end?
	jz short HELP_WAIT	; yes
	call PUTC
	jmp short HELP_CHAR
HELP_WAIT:				; (src: HE2)
	call FLUSH		; send the rest
	call GETKEY		; any key (it is not used)
	jmp REDRAW		; then the whole screen again

; BUFFERS (132Dh) - end of the file.  OBUF, EBUF, WBUF, the stack and
; the text follow in memory (see OBOFF..TXOFF at the top).
BUFFERS:
