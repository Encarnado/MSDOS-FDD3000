# MODE.COM dictionary (volume 8)

Addresses are 8086 offsets in the .COM segment (file offset + 100h).
Global names (BEGIN, START, CHAN, MODEB, BAUDC, NAMBUF, TOKEN, PORTS,
BAUDS, ABAUDS, the *MSG strings, CRLF, STOPS, USEMSG, UPPER, PORT, BAD,
SETS, PAR, DBITS, SBITS, SBEND, SETX, COMMA, BLANKS, GETW, SAME6, SHOW,
PUTS, PUTN, NPORTS, NABAUDS) are João Encarnado's and are kept.

## Renames

### UPPER_STORE — store the (upper-cased) tail character
- class: routine (local label)
- addresses: mode 0324
- aliases: UP1 (source)
- status: verified (code + MODE.ASM)

### UPPER_END — tail done: write the 0 end mark
- class: routine (local label)
- addresses: mode 0327
- aliases: UPX (source)
- status: verified (code + MODE.ASM)

### PORT_MATCH — compare NAMBUF with one PORTS entry
- class: routine (local label)
- addresses: mode 034E
- aliases: PORT1 (source)
- status: verified (code + MODE.ASM)

### PORT_FOUND — entry matched: take its channel, skip ':'
- class: routine (local label)
- addresses: mode 0365
- aliases: PORT2 (source)
- status: verified (code + MODE.ASM)

### PORT_SETTINGS — after the port: settings follow, or show
- class: routine (local label)
- addresses: mode 0371
- aliases: PORT3 (source)
- status: verified (code + MODE.ASM)

### BAUD_CODES — match TOKEN against the 16 BAUDS entries
- class: routine (local label)
- addresses: mode 03A8
- aliases: BAUD1 (source)
- status: verified (code + MODE.ASM)

### BAUD_PCNAMES — match TOKEN against ABAUDS ("134", PC short forms)
- class: routine (local label)
- addresses: mode 03BC
- aliases: BAUD2 (source)
- status: verified (code + MODE.ASM)

### BAUD_PCCODE — take the code stored after an ABAUDS name
- class: routine (local label)
- addresses: mode 03CA
- aliases: BAUD4 (source)
- status: verified (code + MODE.ASM)

### BAUD_STORE — the new baud code into BAUDC
- class: routine (local label)
- addresses: mode 03CD
- aliases: BAUD3 (source)
- status: verified (code + MODE.ASM)

### PAR_STORE — new parity bits into MODEB
- class: routine (local label)
- addresses: mode 03EA
- aliases: PAR1 (source)
- status: verified (code + MODE.ASM)

### SBITS_ONE — stop field: "1" or "1.5"
- class: routine (local label)
- addresses: mode 0420
- aliases: SBIT1 (source)
- status: verified (code + MODE.ASM)

### SBITS_STORE — new stop bits into MODEB
- class: routine (local label)
- addresses: mode 0435
- aliases: SBIT2 (source)
- status: verified (code + MODE.ASM)

### BAD_JUMP — near-JMP relay to BAD (out of short range)
- class: routine (local label)
- addresses: mode 0444
- aliases: BAD1 (source)
- status: verified (code + MODE.ASM)

### COMMA_EXIT — COMMA's common RET
- class: routine (local label)
- addresses: mode 046F
- aliases: CMX (source)
- status: verified (code + MODE.ASM)

### GETW_NEXT — GETW: look at the next character
- class: routine (local label)
- addresses: mode 047F
- aliases: GETW1 (source)
- status: verified (code + MODE.ASM)

### GETW_TAKE — GETW: a word character: copy it if there is room
- class: routine (local label)
- addresses: mode 0495
- aliases: GETW2 (source)
- status: verified (code + MODE.ASM)

### GETW_PAD — GETW: word ended: pad with spaces, ZF=1
- class: routine (local label)
- addresses: mode 049C
- aliases: GETW3 (source)
- status: verified (code + MODE.ASM)

### GETW_FAIL — GETW: no word / too long, ZF=0
- class: routine (local label)
- addresses: mode 04A7
- aliases: GETWX (source)
- status: verified (code + MODE.ASM)

### SHOW_NAME — print "PRN: " / "AUX: "
- class: routine (local label)
- addresses: mode 04CD
- aliases: SHOW1 (source)
- status: verified (code + MODE.ASM)

### SHOW_PARITY — print the parity word
- class: routine (local label)
- addresses: mode 0500
- aliases: SHOW2 (source)
- status: verified (code + MODE.ASM)

### SHOW_EOL — end the line (falls into PUTS)
- class: routine (local label)
- addresses: mode 0549
- aliases: SHOW3 (source)
- status: verified (code + MODE.ASM)

### PUTN_END — PUTN's RET
- class: routine (local label)
- addresses: mode 055E
- aliases: PUTN1 (source)
- status: verified (code + MODE.ASM)

## New equates

### TRAP_INT14 — trap 14h, IO.SYS's INT14 stub -> T_I14
- class: constant
- value: 14h (same name and value as iosys.asm); unused in MODE's bytes, named for the comments
- status: verified (iosys.asm + z86_bios TTAB)

### CHAN_A / CHAN_B — INT 14h DX: 0 channel A (PRN), 1 channel B (AUX)
- class: constant
- value: 0 / 1 (T_I14: C = 81h / 41h); used in PORTS and SHOW
- status: verified (code + z86_bios T_I14)

### I14_GETMODE — INT 14h AH=F0h: AL = mode byte, AH = baud code (SAVED)
- class: constant
- value: F0h (I14X -> I14RD)
- aliases: source writes 0F0H
- status: verified (code + MODE.ASM + z86_bios/z86_interp)

### I14_SETMODE — INT 14h AH=F1h: set up from AL (mode), CL (baud code)
- class: constant
- value: F1h (I14X -> SSET, SSTAT; bits 1-0 forced to 10b; CL >= 16 ignored)
- aliases: source writes 0F1H
- status: verified (code + MODE.ASM + z86_bios)

### MODE_DBITS, MODE_PEN, MODE_EP, MODE_STOPS — 8251A mode-byte fields
- class: constant
- value: 0Ch (data bits - 5), 10h (parity on), 20h (even), C0h (stop field)
- status: verified (code + MODE.ASM header + SSET header)

### MODE_STOP1 / MODE_STOP15 / MODE_STOP2 — stop-bit codes
- class: constant
- value: 40h / 80h / C0h
- status: verified (code + test_fdd86 group 9)

### PAR_NONE / PAR_ODD / PAR_EVEN — parity bits as MODE writes them
- class: constant
- value: 00h / 10h / 30h
- status: verified (code + test_fdd86 group 9)

### STOP_SHIFT — stop field to bits 1-0
- class: constant
- value: 6

### NAME_LEN, PORT_W, NBAUDS, BAUD_W, ABAUD_W, STOP_W — table shapes
- class: constant
- value: 4, 5, 16, 6, 7, 3 (source writes the literals)
- status: verified (code + MODE.ASM)

### DOS_CONOUT — INT 21h AH=02h display character (MSDOS.LST CONOUT)
- class: constant
- value: 02h
- status: verified (MSDOS.LST DISPATCH)

### DOS_PRTSTR — INT 21h AH=09h print string to "$" (PRTBUF)
- class: constant
- value: 09h (same name as iosys.asm)
- status: verified (MSDOS.LST DISPATCH)

### PSP_TAILLEN / PSP_TAIL — command tail length byte / text
- class: constant
- value: 80h / 81h (same names as format/cpmcom)
- status: verified

### TAB, CR, LF — 9, 13, 10
- class: constant
