# term — dictionary (volume 9, TERM.COM)

Renames (cryptic numbered locals) and new equates/labels in asm/term.asm. Every other
label is the author's (TERM.COM.sym), unchanged; the author's equates ROWS RINGSZ LOGSZ
MENUK SOH EOT ACK NAK CAN NPORTS NABAUDS SCRBUF RINGBUF LOGBUF XBUF are kept. Addresses
are CS offsets in TERM.COM. All renames: status verified (code + TERM.ASM + TERM.LST;
each label sits at its TERM.COM.sym address).

## Renames

### UPPER_STORE — store one (upper-cased) tail character back in place
- class: routine (label)
- addresses: term 053D
- aliases: UP1 (source)
- status: verified (code + TERM.ASM)

### PORT_PARSE — start of the port/settings parse after the options are taken out
- class: routine (label)
- addresses: term 05C2
- aliases: PORT0 (source)
- status: verified (code + TERM.ASM)

### PORT_CMP — compare NAMBUF with one PORTS entry
- class: routine (label)
- addresses: term 05D2
- aliases: PORT1 (source)
- status: verified (code + TERM.ASM)

### BAD_PORT — short-range hop to BAD (no port name, or the baud field unreadable)
- class: routine (label)
- addresses: term 05E7
- aliases: BAD0 (source)
- status: verified (code + TERM.ASM)

### PORT_FOUND — port matched: CHAN from the entry, optional colon
- class: routine (label)
- addresses: term 05EA
- aliases: PORT2 (source)
- status: verified (code + TERM.ASM)

### PORT_AFTER — after the port (and colon): settings or not
- class: routine (label)
- addresses: term 05F6
- aliases: PORT3 (source)
- status: verified (code + TERM.ASM)

### PORT_SETTINGS — settings given: read the present ones (INT 14h AH=F0h), parse baud
- class: routine (label)
- addresses: term 05FE
- aliases: PORT4 (source)
- status: verified (code + TERM.ASM)

### BAUD_CMP — compare TOKEN with one BAUDS entry (code = index)
- class: routine (label)
- addresses: term 0622
- aliases: BAUD1 (source)
- status: verified (code + TERM.ASM)

### BAUD_ABBR_CMP — compare TOKEN with one ABAUDS abbreviation
- class: routine (label)
- addresses: term 0636
- aliases: BAUD2 (source)
- status: verified (code + TERM.ASM)

### BAUD_ABBR_CODE — abbreviation matched: DL = the code stored after it
- class: routine (label)
- addresses: term 0645
- aliases: BAUD4 (source)
- status: verified (code + TERM.ASM)

### BAUD_SET — store the baud code in BAUDC
- class: routine (label)
- addresses: term 0648
- aliases: BAUD3 (source)
- status: verified (code + TERM.ASM)

### PAR_SET — store the parity bits (5-4) in MODEB
- class: routine (label)
- addresses: term 0665
- aliases: PAR1 (source)
- status: verified (code + TERM.ASM)

### SBITS_ONE — stop bits: "1" or "1.5"
- class: routine (label)
- addresses: term 069B
- aliases: SBIT1 (source)
- status: verified (code + TERM.ASM)

### SBITS_SET — store the stop bits (7-6) in MODEB
- class: routine (label)
- addresses: term 06B0
- aliases: SBIT2 (source)
- status: verified (code + TERM.ASM)

### BAD_SETTING — short-range hop to BAD (a bad settings field)
- class: routine (label)
- addresses: term 06BF
- aliases: BAD1 (source)
- status: verified (code + TERM.ASM)

### LOAD_OK — Z80 part copied: fill PBLK (PCTL, buffers), INIT, hello line
- class: routine (label)
- addresses: term 06E6
- aliases: LOAD1 (source)
- status: verified (code + TERM.ASM)

### LOAD_CTL — store PCTL (81h channel A / 41h channel B)
- class: routine (label)
- addresses: term 06F1
- aliases: LOAD2 (source)
- status: verified (code + TERM.ASM)

### SESS_MENU — SESS returned for the menu key: menu, then redraw row 23
- class: routine (label)
- addresses: term 0743
- aliases: SESS1 (source)
- status: verified (code + TERM.ASM)

### MENU_KEY — menu line written: read the command key
- class: routine (label)
- addresses: term 07A5
- aliases: MENU1A (source)
- status: verified (code + TERM.ASM)

### MENU_CMD — dispatch the (upper-cased) menu key
- class: routine (label)
- addresses: term 07B2
- aliases: MENU2A (source)
- status: verified (code + TERM.ASM)

### MENU_R — menu: test R (XMODEM receive)
- class: routine (label)
- addresses: term 07BD
- aliases: MENU3 (source)
- status: verified (code + TERM.ASM)

### MENU_S — menu: test S (XMODEM send)
- class: routine (label)
- addresses: term 07C4
- aliases: MENU4 (source)
- status: verified (code + TERM.ASM)

### MENU_B — menu: test B (break)
- class: routine (label)
- addresses: term 07CB
- aliases: MENU5 (source)
- status: verified (code + TERM.ASM)

### MENU_E_C — menu: test E / C (echo, implicit LF)
- class: routine (label)
- addresses: term 07D4
- aliases: MENU8 (source)
- status: verified (code + TERM.ASM)

### MENU_TOGGLE — flip PFLAGS bit AH and pass the flags to TERMZ80 MODE
- class: routine (label)
- addresses: term 07E0
- aliases: MENU9 (source)
- status: verified (code + TERM.ASM)

### MENU_CTRLA — menu: Ctrl-A sends one Ctrl-A
- class: routine (label)
- addresses: term 07ED
- aliases: MENU6 (source)
- status: verified (code + TERM.ASM)

### MENU_BACK — menu: any other key, back to the session
- class: routine (label)
- addresses: term 07FA
- aliases: MENU7 (source)
- status: verified (code + TERM.ASM)

### ONOFF_PUT — print the chosen "+" / "-"
- class: routine (label)
- addresses: term 0805
- aliases: ONOFF1 (source)
- status: verified (code + TERM.ASM)

### QUIT_EXIT — quit: bottom line, CR, INT 20h
- class: routine (label)
- addresses: term 0812
- aliases: QUIT1 (source)
- status: verified (code + TERM.ASM)

### LOG_OPENED — log file created: byte records, LOG on
- class: routine (label)
- addresses: term 0843
- aliases: LOGON1 (source)
- status: verified (code + TERM.ASM)

### LOGWR_DONE — log buffer written (or empty): LOG on with an empty buffer
- class: routine (label)
- addresses: term 08A6
- aliases: LOGW1 (source)
- status: verified (code + TERM.ASM)

### XR_CREATED — receive file created: XMODEM receive set-up
- class: routine (label)
- addresses: term 08C8
- aliases: XR0 (source)
- status: verified (code + TERM.ASM)

### XR_WAIT — receive loop: send XREPLY, wait for a block
- class: routine (label)
- addresses: term 08E8
- aliases: XR1 (source)
- status: verified (code + TERM.ASM)

### XR_NOT_EOT — receive: first byte not SOH / EOT, test CAN
- class: routine (label)
- addresses: term 0911
- aliases: XR2 (source)
- status: verified (code + TERM.ASM)

### XR_NOISE — receive: noise byte, wait again without a reply
- class: routine (label)
- addresses: term 0918
- aliases: XR3 (source)
- status: verified (code + TERM.ASM)

### XRS_SUM — receive: checksum mode, compare the sum
- class: routine (label)
- addresses: term 0978
- aliases: XRS1 (source)
- status: verified (code + TERM.ASM)

### XRS_GOOD — receive: block passed the checks, test its number
- class: routine (label)
- addresses: term 097E
- aliases: XRS2 (source)
- status: verified (code + TERM.ASM)

### XRS_WRITE — receive: the expected block, write its 128 bytes
- class: routine (label)
- addresses: term 099C
- aliases: XRS3 (source)
- status: verified (code + TERM.ASM)

### XRS_NEXT — receive: block written, BLK + 1, progress
- class: routine (label)
- addresses: term 09B4
- aliases: XRS4 (source)
- status: verified (code + TERM.ASM)

### XRBAD_NAK — receive: bad block within the retry limit, NAK
- class: routine (label)
- addresses: term 09D7
- aliases: XRBAD1 (source)
- status: verified (code + TERM.ASM)

### XS_OPENED — send file opened: XMODEM send set-up
- class: routine (label)
- addresses: term 0A08
- aliases: XS0 (source)
- status: verified (code + TERM.ASM)

### XS_WAITC — send: wait up to 60 s for the receiver's 'C' / NAK
- class: routine (label)
- addresses: term 0A14
- aliases: XS1 (source)
- status: verified (code + TERM.ASM)

### XS_START — send: mode known, BLK = 1
- class: routine (label)
- addresses: term 0A44
- aliases: XS2 (source)
- status: verified (code + TERM.ASM)

### XS_BLOCK — send: read the next 128 bytes
- class: routine (label)
- addresses: term 0A49
- aliases: XS3 (source)
- status: verified (code + TERM.ASM)

### XS_FILL — send: pad with ^Z, build header and check
- class: routine (label)
- addresses: term 0A61
- aliases: XS31 (source)
- status: verified (code + TERM.ASM)

### XS_TRY0 — send: TRIES = 0 for this block
- class: routine (label)
- addresses: term 0AA6
- aliases: XS4 (source)
- status: verified (code + TERM.ASM)

### XS_SENDBLK — send: send the block, wait for the answer
- class: routine (label)
- addresses: term 0AAB
- aliases: XS5 (source)
- status: verified (code + TERM.ASM)

### XS_RETRY — send: no ACK, count and re-send
- class: routine (label)
- addresses: term 0AC9
- aliases: XS51 (source)
- status: verified (code + TERM.ASM)

### XS_ACKED — send: ACKed, BLK + 1, progress, next block
- class: routine (label)
- addresses: term 0AD7
- aliases: XS6 (source)
- status: verified (code + TERM.ASM)

### XSE_SEND — send: one EOT and wait for the answer
- class: routine (label)
- addresses: term 0AE9
- aliases: XSE1 (source)
- status: verified (code + TERM.ASM)

### XSE_ANSWER — send: the EOT answered, ACK?
- class: routine (label)
- addresses: term 0AFA
- aliases: XSE11 (source)
- status: verified (code + TERM.ASM)

### XSE_DONE — send: EOT ACKed, to XDONE
- class: routine (label)
- addresses: term 0B0C
- aliases: XSE2 (source)
- status: verified (code + TERM.ASM)

### XANS_RET — XANS return
- class: routine (label)
- addresses: term 0B67
- aliases: XANS1 (source)
- status: verified (code + TERM.ASM)

### PURGE_RET — PURGE return: the line was quiet
- class: routine (label)
- addresses: term 0B96
- aliases: PURGE1 (source)
- status: verified (code + TERM.ASM)

### ASK_KEY — ASKF: read one key
- class: routine (label)
- addresses: term 0BF7
- aliases: ASK1 (source)
- status: verified (code + TERM.ASM)

### ASK_RUBOUT — ASKF: BS / DEL rubs one character out
- class: routine (label)
- addresses: term 0C21
- aliases: ASK3 (source)
- status: verified (code + TERM.ASM)

### ASK_ENTER — ASKF: CR, parse LINE into the FCB (AH=29h)
- class: routine (label)
- addresses: term 0C2E
- aliases: ASK4 (source)
- status: verified (code + TERM.ASM)

### ASKNO_CF — ASKF: CF=1, no name
- class: routine (label)
- addresses: term 0C49
- aliases: ASKNO1 (source)
- status: verified (code + TERM.ASM)

### PUTNB_LAST — PUTNB: print the last digit
- class: routine (label)
- addresses: term 0C7F
- aliases: PUTNB1 (source)
- status: verified (code + TERM.ASM)

### PUTNUM_DIGIT — PUTNUM: pop this digit
- class: routine (label)
- addresses: term 0C91
- aliases: PUTN1 (source)
- status: verified (code + TERM.ASM)

### PUTNUM_OUT — print digit AL (shared by PUTNB)
- class: routine (label)
- addresses: term 0C92
- aliases: PUTN2 (source)
- status: verified (code + TERM.ASM)

### GETW_NEXT — GETW: test the next character
- class: routine (label)
- addresses: term 0CC3
- aliases: GETW1 (source)
- status: verified (code + TERM.ASM)

### GETW_TAKE — GETW: store a word character
- class: routine (label)
- addresses: term 0CD9
- aliases: GETW2 (source)
- status: verified (code + TERM.ASM)

### GETW_END — GETW: word ended, pad or fail
- class: routine (label)
- addresses: term 0CE0
- aliases: GETW3 (source)
- status: verified (code + TERM.ASM)
## New equates

### TRAP_CPM — BIOS trap 1Ch (Z86.SYS T_CPML): load (BP <> 0) / run (BP = 0) a Z80 part
- class: constant
- addresses: term 06D9 (LOAD), 0751 (in Z80, every function call)
- aliases: `DB 0FH,1CH` (source); same name and value as cpmcom.asm
- status: verified (code + TERM.ASM + z86_bios.asm T_CPML)
- notes: with BP = 0 the trap jumps to ENDBIOS, which for TERM is TERMZ80's T_TERM
  (dispatch on AH), not CPMZ80's T_CPM. The name comes from the trap's first user.

### TZ_INIT TZ_SESS TZ_DRAW TZ_RECV TZ_SEND TZ_BRK TZ_LOG TZ_CRC TZ_FLUSH TZ_MODE — TERMZ80 function numbers 0-9
- class: constant
- aliases: F_INIT F_SESS F_DRAW F_RECV F_SEND F_BRK F_LOG F_CRC F_FLSH F_MODE (TERMZ80.ASM FTAB entries); the source writes the bare numbers in `MOV AH,n`
- status: verified (code + TERM.ASM + TERMZ80.ASM header and FTAB)
- notes: passed in AH to TRAP_CPM with BP = 0; T_TERM ignores AH >= 10.

### PF_VT52 PF_XONXOFF PF_RTSCTS PF_ECHO PF_CRLF — PFLAGS bits 01h 02h 04h 08h 10h
- class: constant
- aliases: the source's numbers (PFLAGS comment; TERMZ80.ASM P_FLAGS comment)
- status: verified (code + TERM.ASM + TERMZ80.ASM)
- notes: /X /R /N replace bits 02h/04h (AND 19h = PF_VT52+PF_ECHO+PF_CRLF); TERMZ80 MODE
  takes only 08h and 10h.

### UART_CMD_CHA / UART_CMD_CHB — WD2123 control/status ports 81h / 41h (PCTL)
- class: port
- aliases: corpus names, as z86sys.asm; source writes 81H / 41H
- status: verified (code + TERM.ASM + z86sys.asm)

### PSP_TAILLEN / PSP_TAIL — PSP 80h (tail length) / 81h (tail)
- class: constant
- status: verified (code + TERM.ASM); same names as cpmcom.asm

### FCB_RECSIZ / FCB_RR — FCB offsets 14 (record size) / 33 (random record)
- class: constant
- status: verified (code + TERM.ASM RECSZ1 + MSDOS.LST); same names as cpmcom.asm

### NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS — the Z86.SYS addresses in the header
- class: constant
- addresses: values D83B EB4D EBE3 EC00 EC0E F12A F12C (../symbols/z80/Z86.SYS.sym)
- aliases: Z86.SYS's own names (author's)
- status: verified (header bytes + Z86.SYS.sym + z86.py termz80())

## New labels (header at 0D7Bh)

### Z80_LEN — header word 0: length of the Z80 code (0D8Ch = 3468)
- class: variable (data)
- addresses: term 0D7B (= Z80IMG = SCRBUF)
- status: verified (bytes + z86.py termz80())

### Z80_SYMS — header words 1-7: the 7 Z86.SYS addresses trap 1Ch compares with CPMSYM
- class: table
- addresses: term 0D7D
- status: verified (bytes + Z86.SYS.sym + z86_bios.asm T_CPML)

### Z80_CODE / Z80_CODE_END — TERMZ80.BIN, assembled for ENDBIOS (F12Ch-FEB7h)
- class: table (incbin)
- addresses: term 0D8B-1B16 (file offset 0C8Bh to the end)
- status: verified (cmp with bin/TERMZ80.BIN; gate PASS)
