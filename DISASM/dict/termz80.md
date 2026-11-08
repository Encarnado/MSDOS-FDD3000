# TERMZ80.BIN dictionary (volume 10)

Renamed labels, each from a numbered source local, and new equates. Every other
label is the author's (TERMZ80.ASM). Addresses are TERMZ80 run addresses (the image
runs at F12Ch). Kept despite lint's CRYPTIC warning, as meaningful author names:
EM8 (8-bit byte), PAR0/PAR1/PAR2 (CSI parameter 1/2), DA100/DA52 (DA answers),
G0/G1 (the VT100's own names for its character sets). The Q prefix of QSP1, QRD1,
QSS1, QCF1, QCB1, QSG1/2 is the author's, avoiding clashes with Z86.SYS globals
(TERMZ80.ASM is assembled after I86.ASM and BIOS.ASM).

## Renamed labels

### SESS_LOOP — F_SESS: the session loop head (poll, key, byte)
- class: routine (local entry or loop)
- addresses: termz80 F1F6
- aliases: SL1 (source)
- status: verified (code + TERMZ80.ASM)

### SESS_RING — F_SESS: take the next byte from the ring
- class: routine (local entry or loop)
- addresses: termz80 F20A
- aliases: SL2 (source)
- status: verified (code + TERMZ80.ASM)

### SESS_BYTE — F_SESS: a received byte: log it (stop at LOGLIM)
- class: routine (local entry or loop)
- addresses: termz80 F21B
- aliases: SL3 (source)
- status: verified (code + TERMZ80.ASM)

### SESS_SHOW — F_SESS: show the byte, let the host go below LOWAT
- class: routine (local entry or loop)
- addresses: termz80 F245
- aliases: SL4 (source)
- status: verified (code + TERMZ80.ASM)

### HOLD_DRAIN — HOLD: the ~120 ms polling loop after the stop
- class: routine (local entry or loop)
- addresses: termz80 F27F
- aliases: HO1 (source)
- status: verified (code + TERMZ80.ASM)

### DRAW_FROM — F_DRAW: B = the first row, clamped
- class: routine (local entry or loop)
- addresses: termz80 F29C
- aliases: FD1 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_NEXT — F_RECV: loop head: all in? ring first
- class: routine (local entry or loop)
- addresses: termz80 F2BC
- aliases: FR1 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_10MS — F_RECV: one 10 ms unit of the wait
- class: routine (local entry or loop)
- addresses: termz80 F2D5
- aliases: FR2 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_POLL — F_RECV: polls RxRDY and the terminal's KEYRDY (85 T)
- class: routine (local entry or loop)
- addresses: termz80 F2D8
- aliases: FR3 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_GOT — F_RECV: RxRDY: reset an error if any
- class: routine (local entry or loop)
- addresses: termz80 F2F2
- aliases: FR5 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_TAKE — F_RECV: read the byte from the data port
- class: routine (local entry or loop)
- addresses: termz80 F2FD
- aliases: FR51 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_STORE — F_RECV: store at DI + RCNT, wait now 1 s
- class: routine (local entry or loop)
- addresses: termz80 F300
- aliases: FR6 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_KEY — F_RECV: a key cancels: AL = 1
- class: routine (local entry or loop)
- addresses: termz80 F317
- aliases: FR7 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_END — F_RECV: all in or timed out: AL = 0
- class: routine (local entry or loop)
- addresses: termz80 F31E
- aliases: FR8 (source)
- status: verified (code + TERMZ80.ASM)

### RECV_RET — F_RECV: AL and CX to REGS
- class: routine (local entry or loop)
- addresses: termz80 F31F
- aliases: FR9 (source)
- status: verified (code + TERMZ80.ASM)

### SEND_NEXT — F_SEND: loop over CX bytes
- class: routine (local entry or loop)
- addresses: termz80 F333
- aliases: FS1 (source)
- status: verified (code + TERMZ80.ASM)

### SEND_DONE — F_SEND: all sent, AL = 0
- class: routine (local entry or loop)
- addresses: termz80 F347
- aliases: FS2 (source)
- status: verified (code + TERMZ80.ASM)

### SEND_RET — F_SEND: AL to REGS
- class: routine (local entry or loop)
- addresses: termz80 F348
- aliases: FS3 (source)
- status: verified (code + TERMZ80.ASM)

### BRK_10MS — F_BRK: one of 25 10-ms units
- class: routine (local entry or loop)
- addresses: termz80 F359
- aliases: FB1 (source)
- status: verified (code + TERMZ80.ASM)

### BRK_SPIN — F_BRK: the 26 T delay loop
- class: routine (local entry or loop)
- addresses: termz80 F35C
- aliases: FB2 (source)
- status: verified (code + TERMZ80.ASM)

### CRC_NEXT — F_CRC: next byte (sum, CRC high byte)
- class: routine (local entry or loop)
- addresses: termz80 F391
- aliases: CR1 (source)
- status: verified (code + TERMZ80.ASM)

### CRC_BIT — F_CRC: one bit: shift, XOR 1021h on carry
- class: routine (local entry or loop)
- addresses: termz80 F3A2
- aliases: CR2 (source)
- status: verified (code + TERMZ80.ASM)

### CRC_NOXOR — F_CRC: bit loop tail
- class: routine (local entry or loop)
- addresses: termz80 F3B0
- aliases: CR3 (source)
- status: verified (code + TERMZ80.ASM)

### CRC_DONE — F_CRC: DX = CRC, AL = sum
- class: routine (local entry or loop)
- addresses: termz80 F3B7
- aliases: CR4 (source)
- status: verified (code + TERMZ80.ASM)

### ENSURE_WAIT — ENSURE: poll until the XON has gone
- class: routine (local entry or loop)
- addresses: termz80 F3DB
- aliases: EN1 (source)
- status: verified (code + TERMZ80.ASM)

### RXPOLL_RX — RXPOLL: the receive half (RxRDY?)
- class: routine (local entry or loop)
- addresses: termz80 F407
- aliases: RXP1 (source)
- status: verified (code + TERMZ80.ASM)

### RXPOLL_ERRRST — RXPOLL: error reset, CMDV OR ER (RTS kept)
- class: routine (local entry or loop)
- addresses: termz80 F41B
- aliases: RXP2 (source)
- status: verified (code + TERMZ80.ASM)

### RXPOLL_TAKE — RXPOLL: read the byte into the ring
- class: routine (local entry or loop)
- addresses: termz80 F422
- aliases: RXP3 (source)
- status: verified (code + TERMZ80.ASM)

### RXPOLL_FULL — RXPOLL: ring full, LOST + 1
- class: routine (local entry or loop)
- addresses: termz80 F44C
- aliases: RXP4 (source)
- status: verified (code + TERMZ80.ASM)

### RXPOLL_RET — RXPOLL: EXX back, AF restored
- class: routine (local entry or loop)
- addresses: termz80 F453
- aliases: RXP9 (source)
- status: verified (code + TERMZ80.ASM)

### FLOWOFF_RTS — FLOWOFF: RTS off if /R
- class: routine (local entry or loop)
- addresses: termz80 F499
- aliases: ST1 (source)
- status: verified (code + TERMZ80.ASM)

### RESUME_RTS — RESUME: RTS on (SIOWORD)
- class: routine (local entry or loop)
- addresses: termz80 F4B7
- aliases: RS1 (source)
- status: verified (code + TERMZ80.ASM)

### SERPUT_WAIT — SERPUT: wait for TxRDY + CTS, polling
- class: routine (local entry or loop)
- addresses: termz80 F4D0
- aliases: QSP1 (source)
- status: verified (code + TERMZ80.ASM)

### SERPUT_FAIL — SERPUT: given up, CF = 1
- class: routine (local entry or loop)
- addresses: termz80 F4ED
- aliases: SP0 (source)
- status: verified (code + TERMZ80.ASM)

### SERPUT_SEND — SERPUT: the byte out, CF = 0
- class: routine (local entry or loop)
- addresses: termz80 F4F0
- aliases: QSP2 (source)
- status: verified (code + TERMZ80.ASM)

### SERPUT_RET — SERPUT: common exit
- class: routine (local entry or loop)
- addresses: termz80 F4F4
- aliases: SP3 (source)
- status: verified (code + TERMZ80.ASM)

### SENDN_DIGIT — SENDN: one decimal digit of weight B
- class: routine (local entry or loop)
- addresses: termz80 F511
- aliases: SN1 (source)
- status: verified (code + TERMZ80.ASM)

### SENDN_SUB — SENDN: repeated subtraction loop
- class: routine (local entry or loop)
- addresses: termz80 F513
- aliases: SN2 (source)
- status: verified (code + TERMZ80.ASM)

### SENDN_OUT — SENDN: send the digit
- class: routine (local entry or loop)
- addresses: termz80 F522
- aliases: SN3 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_WAIT — KEYOUT: ~53 ms wait for an arrow's letter after ESC
- class: routine (local entry or loop)
- addresses: termz80 F53D
- aliases: KO1 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_SEND — KEYOUT: send the key as it is, then echo
- class: routine (local entry or loop)
- addresses: termz80 F54C
- aliases: KO2 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_ECHO — KEYOUT: local echo, ESC excluded
- class: routine (local entry or loop)
- addresses: termz80 F567
- aliases: KO5 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_SHOW — KEYOUT: the key to EMUL (echo)
- class: routine (local entry or loop)
- addresses: termz80 F57C
- aliases: KO6 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_ARROW — KEYOUT: ESC + A-D becomes ESC [ / ESC O + letter
- class: routine (local entry or loop)
- addresses: termz80 F57F
- aliases: KO3 (source)
- status: verified (code + TERMZ80.ASM)

### KEYOUT_FINAL — KEYOUT: the second byte and the letter
- class: routine (local entry or loop)
- addresses: termz80 F59A
- aliases: KO4 (source)
- status: verified (code + TERMZ80.ASM)

### TOUT_TRY — TOUT: one attempt (TSEND)
- class: routine (local entry or loop)
- addresses: termz80 F5A8
- aliases: TO1 (source)
- status: verified (code + TERMZ80.ASM)

### TOUT_ABORT — TOUT: wait for the terminal's LINKERR, polling
- class: routine (local entry or loop)
- addresses: termz80 F5B1
- aliases: TO2 (source)
- status: verified (code + TERMZ80.ASM)

### TOUT_RET — TOUT: exit
- class: routine (local entry or loop)
- addresses: termz80 F5BE
- aliases: TO3 (source)
- status: verified (code + TERMZ80.ASM)

### TSEND_OFFER — TSEND: BYTEON until SERVICO, polling
- class: routine (local entry or loop)
- addresses: termz80 F5CD
- aliases: TS1 (source)
- status: verified (code + TERMZ80.ASM)

### TSEND_ECHO_LO — TSEND: wait for the low nibble's echo
- class: routine (local entry or loop)
- addresses: termz80 F5E4
- aliases: TS2 (source)
- status: verified (code + TERMZ80.ASM)

### TSEND_ECHO_HI — TSEND: wait for the high nibble's echo
- class: routine (local entry or loop)
- addresses: termz80 F5F6
- aliases: TS3 (source)
- status: verified (code + TERMZ80.ASM)

### TSEND_FAIL — TSEND: echo time-out, LINKERR sent
- class: routine (local entry or loop)
- addresses: termz80 F606
- aliases: TS4 (source)
- status: verified (code + TERMZ80.ASM)

### TGOTO_SEND — TGOTO: ESC Y row+32 col+32
- class: routine (local entry or loop)
- addresses: termz80 F620
- aliases: TG1 (source)
- status: verified (code + TERMZ80.ASM)

### TSETA_SEND — TSETA: ESC L / ESC M out
- class: routine (local entry or loop)
- addresses: termz80 F653
- aliases: TSA1 (source)
- status: verified (code + TERMZ80.ASM)

### TSETA_RET — TSETA: exit
- class: routine (local entry or loop)
- addresses: termz80 F656
- aliases: TSA2 (source)
- status: verified (code + TERMZ80.ASM)

### TPUT_DRAW — TPUT: not the bottom right cell: draw
- class: routine (local entry or loop)
- addresses: termz80 F669
- aliases: TP1 (source)
- status: verified (code + TERMZ80.ASM)

### DRAWR_RANGE — DRAWR: C = last drawable column fixed
- class: routine (local entry or loop)
- addresses: termz80 F6AC
- aliases: DR1 (source)
- status: verified (code + TERMZ80.ASM)

### DRAWR_TRIM — DRAWR: scan back over trailing blanks
- class: routine (local entry or loop)
- addresses: termz80 F6B7
- aliases: DR2 (source)
- status: verified (code + TERMZ80.ASM)

### DRAWR_FROM — DRAWR: HL = the first cell to draw
- class: routine (local entry or loop)
- addresses: termz80 F6C9
- aliases: DR3 (source)
- status: verified (code + TERMZ80.ASM)

### DRAWR_CELL — DRAWR: one cell to the terminal
- class: routine (local entry or loop)
- addresses: termz80 F6CE
- aliases: DR4 (source)
- status: verified (code + TERMZ80.ASM)

### REDR_ROW — REDR: one row, from column 0
- class: routine (local entry or loop)
- addresses: termz80 F6DE
- aliases: QRD1 (source)
- status: verified (code + TERMZ80.ASM)

### ROWP_BASE — ROWP: + SCR
- class: routine (local entry or loop)
- addresses: termz80 F701
- aliases: RP1 (source)
- status: verified (code + TERMZ80.ASM)

### MVF_PIECE — MVF: one 32-byte LDIR, then a poll
- class: routine (local entry or loop)
- addresses: termz80 F731
- aliases: MVF1 (source)
- status: verified (code + TERMZ80.ASM)

### MVF_LAST — MVF: the last 1-32 bytes
- class: routine (local entry or loop)
- addresses: termz80 F73D
- aliases: MVF2 (source)
- status: verified (code + TERMZ80.ASM)

### MVB_PIECE — MVB: one 32-byte LDDR, then a poll
- class: routine (local entry or loop)
- addresses: termz80 F749
- aliases: MVB1 (source)
- status: verified (code + TERMZ80.ASM)

### MVB_LAST — MVB: the last 1-32 bytes
- class: routine (local entry or loop)
- addresses: termz80 F755
- aliases: MVB2 (source)
- status: verified (code + TERMZ80.ASM)

### MVSUB_POLL — MVSUB: the RXPOLL tail jump
- class: routine (local entry or loop)
- addresses: termz80 F75F
- aliases: MVS1 (source)
- status: verified (code + TERMZ80.ASM)

### SHUP_BLANK — SHUP: blank row RB
- class: routine (local entry or loop)
- addresses: termz80 F78D
- aliases: SHU1 (source)
- status: verified (code + TERMZ80.ASM)

### SHDN_BLANK — SHDN: blank row RT
- class: routine (local entry or loop)
- addresses: termz80 F7B2
- aliases: SHD1 (source)
- status: verified (code + TERMZ80.ASM)

### SCRUP_LF — SCRUP: LF on the terminal's bottom row
- class: routine (local entry or loop)
- addresses: termz80 F800
- aliases: SU1 (source)
- status: verified (code + TERMZ80.ASM)

### SCRDN_RLF — SCRDN: ESC I on the terminal's top row
- class: routine (local entry or loop)
- addresses: termz80 F840
- aliases: SD1 (source)
- status: verified (code + TERMZ80.ASM)

### PUTCH_CELL — PUTCH: D, E = the cursor; insert or replace
- class: routine (local entry or loop)
- addresses: termz80 F883
- aliases: PC1 (source)
- status: verified (code + TERMZ80.ASM)

### PUTCH_OVER — PUTCH: replace mode: one cell drawn
- class: routine (local entry or loop)
- addresses: termz80 F8A5
- aliases: PC2 (source)
- status: verified (code + TERMZ80.ASM)

### PUTCH_ADVANCE — PUTCH: the column moves on
- class: routine (local entry or loop)
- addresses: termz80 F8B0
- aliases: PC3 (source)
- status: verified (code + TERMZ80.ASM)

### PUTCH_LASTCOL — PUTCH: last column: WRAPF = AWM
- class: routine (local entry or loop)
- addresses: termz80 F8C1
- aliases: PC4 (source)
- status: verified (code + TERMZ80.ASM)

### CHCNT_LEFT — CHCNT: clamp n to the cells left
- class: routine (local entry or loop)
- addresses: termz80 F8CD
- aliases: CHC1 (source)
- status: verified (code + TERMZ80.ASM)

### CHCNT_RET — CHCNT: A = cells that move
- class: routine (local entry or loop)
- addresses: termz80 F8D9
- aliases: CHC2 (source)
- status: verified (code + TERMZ80.ASM)

### ICHS_BLANK — ICHS: blank the n opened cells
- class: routine (local entry or loop)
- addresses: termz80 F900
- aliases: IC1 (source)
- status: verified (code + TERMZ80.ASM)

### DCHS_BLANK — DCHS: blank the n cells at the row's end
- class: routine (local entry or loop)
- addresses: termz80 F91F
- aliases: DC1 (source)
- status: verified (code + TERMZ80.ASM)

### ECHS_FILL — ECHS: blank n cells at the cursor (also ICHS's tail)
- class: routine (local entry or loop)
- addresses: termz80 F92A
- aliases: ECHS1 (source)
- status: verified (code + TERMZ80.ASM)

### SETCUR_COL — SETCUR: clamp the column
- class: routine (local entry or loop)
- addresses: termz80 F948
- aliases: SC1 (source)
- status: verified (code + TERMZ80.ASM)

### SETCUR_SET — SETCUR: store the cursor
- class: routine (local entry or loop)
- addresses: termz80 F950
- aliases: SC2 (source)
- status: verified (code + TERMZ80.ASM)

### EDN_START — EDN: ED 1, start of screen to cursor
- class: routine (local entry or loop)
- addresses: termz80 F982
- aliases: ED1 (source)
- status: verified (code + TERMZ80.ASM)

### ELN_FILL — ELN: blank A cells, then ESC K
- class: routine (local entry or loop)
- addresses: termz80 F9B2
- aliases: EL0 (source)
- status: verified (code + TERMZ80.ASM)

### ELN_START — ELN: EL 1, start of line to cursor
- class: routine (local entry or loop)
- addresses: termz80 F9BD
- aliases: EL1 (source)
- status: verified (code + TERMZ80.ASM)

### ELN_ALL — ELN: EL 2, the whole line
- class: routine (local entry or loop)
- addresses: termz80 F9D1
- aliases: EL2 (source)
- status: verified (code + TERMZ80.ASM)

### ESO_SET — ECTRL: GL = A (SO / SI)
- class: routine (local entry or loop)
- addresses: termz80 FA4F
- aliases: ESO1 (source)
- status: verified (code + TERMZ80.ASM)

### ECAN_SET — ECTRL: PST = A (ESC / CAN / SUB)
- class: routine (local entry or loop)
- addresses: termz80 FA58
- aliases: ECAN1 (source)
- status: verified (code + TERMZ80.ASM)

### ETAB_SET — ETAB: CCOL = the tab stop
- class: routine (local entry or loop)
- addresses: termz80 FA88
- aliases: ET1 (source)
- status: verified (code + TERMZ80.ASM)

### ESTATE_YROW — ESTATE: VT52 ESC Y's row byte
- class: routine (local entry or loop)
- addresses: termz80 FAAD
- aliases: SY1 (source)
- status: verified (code + TERMZ80.ASM)

### SSCS_SET — SSCS: G0 / G1 = graphics or ASCII
- class: routine (local entry or loop)
- addresses: termz80 FACD
- aliases: QSS1 (source)
- status: verified (code + TERMZ80.ASM)

### CSI_SAT — SCSI: parameter saturated at 255
- class: routine (local entry or loop)
- addresses: termz80 FBAA
- aliases: CS1 (source)
- status: verified (code + TERMZ80.ASM)

### CSI_STORE — SCSI: parameter stored
- class: routine (local entry or loop)
- addresses: termz80 FBAC
- aliases: CS0 (source)
- status: verified (code + TERMZ80.ASM)

### CSI_PRIV — SCSI: < = > ? or a final byte
- class: routine (local entry or loop)
- addresses: termz80 FBB7
- aliases: CS2 (source)
- status: verified (code + TERMZ80.ASM)

### CFIN_SCAN — CFIN: linear search of CTAB / PTAB
- class: routine (local entry or loop)
- addresses: termz80 FBD1
- aliases: QCF1 (source)
- status: verified (code + TERMZ80.ASM)

### CFIN_JUMP — CFIN: jump to the handler
- class: routine (local entry or loop)
- addresses: termz80 FBDC
- aliases: CF2 (source)
- status: verified (code + TERMZ80.ASM)

### CUU_LIMIT — CUU: C = the limit (TOP or 0)
- class: routine (local entry or loop)
- addresses: termz80 FC53
- aliases: CU1 (source)
- status: verified (code + TERMZ80.ASM)

### CUU_STOP — CUU: stop at the limit
- class: routine (local entry or loop)
- addresses: termz80 FC59
- aliases: CU2 (source)
- status: verified (code + TERMZ80.ASM)

### CUU_SET — CUU: store the row
- class: routine (local entry or loop)
- addresses: termz80 FC5A
- aliases: CU3 (source)
- status: verified (code + TERMZ80.ASM)

### CUD_LIMIT — CUD: C = the limit (BOT or the last row)
- class: routine (local entry or loop)
- addresses: termz80 FC78
- aliases: CD1 (source)
- status: verified (code + TERMZ80.ASM)

### CUD_STOP — CUD: stop at the limit
- class: routine (local entry or loop)
- addresses: termz80 FC7E
- aliases: CD2 (source)
- status: verified (code + TERMZ80.ASM)

### CUD_SET — CUD: store the row
- class: routine (local entry or loop)
- addresses: termz80 FC7F
- aliases: CD3 (source)
- status: verified (code + TERMZ80.ASM)

### CUF_STOP — CUF: stop at the last column
- class: routine (local entry or loop)
- addresses: termz80 FC97
- aliases: CF3 (source)
- status: verified (code + TERMZ80.ASM)

### CUF_SET — CUF: store the column
- class: routine (local entry or loop)
- addresses: termz80 FC98
- aliases: CF4 (source)
- status: verified (code + TERMZ80.ASM)

### CUB_SET — CUB: store the column
- class: routine (local entry or loop)
- addresses: termz80 FCA9
- aliases: QCB1 (source)
- status: verified (code + TERMZ80.ASM)

### SGR_NEXT — SGR: one parameter
- class: routine (local entry or loop)
- addresses: termz80 FCE6
- aliases: QSG1 (source)
- status: verified (code + TERMZ80.ASM)

### SGR_INV — SGR: 7 = inverse?
- class: routine (local entry or loop)
- addresses: termz80 FCF2
- aliases: SG4 (source)
- status: verified (code + TERMZ80.ASM)

### SGR_SET — SGR: ATTR = A
- class: routine (local entry or loop)
- addresses: termz80 FCF8
- aliases: QSG2 (source)
- status: verified (code + TERMZ80.ASM)

### SGR_SKIP — SGR: loop tail
- class: routine (local entry or loop)
- addresses: termz80 FCFB
- aliases: SG3 (source)
- status: verified (code + TERMZ80.ASM)

### NPARS_SET — NPARS: B = count
- class: routine (local entry or loop)
- addresses: termz80 FD07
- aliases: NPS1 (source)
- status: verified (code + TERMZ80.ASM)

### STBM_FULL — STBM: bottom = the last row
- class: routine (local entry or loop)
- addresses: termz80 FD1B
- aliases: ST2 (source)
- status: verified (code + TERMZ80.ASM)

### STBM_BOT — STBM: bottom checked against top
- class: routine (local entry or loop)
- addresses: termz80 FD1C
- aliases: ST3 (source)
- status: verified (code + TERMZ80.ASM)

### DSR_STATUS — DSR: DSR 5, ESC [ 0 n
- class: routine (local entry or loop)
- addresses: termz80 FD59
- aliases: DSR5 (source)
- status: verified (code + TERMZ80.ASM)

### DAREP_SEND — DAREP: send the chosen answer
- class: routine (local entry or loop)
- addresses: termz80 FD70
- aliases: DA1 (source)
- status: verified (code + TERMZ80.ASM)

### SM_SCAN — SM / RM: scan the parameters (C = 1 / 0)
- class: routine (local entry or loop)
- addresses: termz80 FD8A
- aliases: SM0 (source)
- status: verified (code + TERMZ80.ASM)

### SM_NEXT — SM / RM: one parameter (4 = IRM)
- class: routine (local entry or loop)
- addresses: termz80 FD90
- aliases: SM1 (source)
- status: verified (code + TERMZ80.ASM)

### SM_SKIP — SM / RM: loop tail
- class: routine (local entry or loop)
- addresses: termz80 FD9A
- aliases: SM2 (source)
- status: verified (code + TERMZ80.ASM)

### PSM_SCAN — PSM / PRM: scan the parameters
- class: routine (local entry or loop)
- addresses: termz80 FDA3
- aliases: PSM0 (source)
- status: verified (code + TERMZ80.ASM)

### PSM_NEXT — PSM / PRM: ?1 = DECCKM
- class: routine (local entry or loop)
- addresses: termz80 FDA9
- aliases: PS1 (source)
- status: verified (code + TERMZ80.ASM)

### PSM_AWM — PSM / PRM: ?7 = DECAWM
- class: routine (local entry or loop)
- addresses: termz80 FDB3
- aliases: PS2 (source)
- status: verified (code + TERMZ80.ASM)

### PSM_SKIP — PSM / PRM: loop tail
- class: routine (local entry or loop)
- addresses: termz80 FDBF
- aliases: PS3 (source)
- status: verified (code + TERMZ80.ASM)

### IL_SET — IL / DL: ILOP set, region checks
- class: routine (local entry or loop)
- addresses: termz80 FDCA
- aliases: IL0 (source)
- status: verified (code + TERMZ80.ASM)

### IL_COUNT — IL / DL: B = n, clamped
- class: routine (local entry or loop)
- addresses: termz80 FDEC
- aliases: IL1 (source)
- status: verified (code + TERMZ80.ASM)

### IL_SHIFT — IL / DL: one shift through JPHL
- class: routine (local entry or loop)
- addresses: termz80 FDED
- aliases: IL2 (source)
- status: verified (code + TERMZ80.ASM)

### CH_DISPATCH — ICH / DCH / ECH: push CH_REDRAW and the handler, RET into it
- class: routine (local entry or loop)
- addresses: termz80 FE16
- aliases: CH0 (source)
- status: verified (code + TERMZ80.ASM)

### CH_REDRAW — ICH / DCH / ECH: redraw the row from the cursor
- class: routine (local entry or loop)
- addresses: termz80 FE1F
- aliases: CH1 (source)
- status: verified (code + TERMZ80.ASM)

## New equates

### COM / MASK / KEYRDY / LINKERR / BYTEON / SERVICO / CSTAT / BSTAT / STMSK — the terminal link: values as z86sys.asm / z86_bios.asm (CBIOS A1.1 names)
- class: port / constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: the terminal link: values as z86sys.asm / z86_bios.asm (CBIOS A1.1 names), defined again because this is a separate image

### UART_BAUD_CHA / UART_BAUD_CHB / UART_DATA_CHA / UART_DATA_CHB / UART_CMD_CHA / UART_CMD_CHB — ports
- class: port
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: WD2123 ports, values as z86sys.asm; the channel used is the variable CTL (81h / 41h)

### ACOM / SIOWORD / IOMASK — 8251A command / status values with Z86.SYS's (CBIOS) names and values
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 8251A command / status values with Z86.SYS's (CBIOS) names and values

### SIO_SBRK — 08h
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 08h, command bit 3: send break (F_BRK)

### SIO_ER — 10h
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 10h, command bit 4: error reset, ORed into CMDV so RTS is kept

### SIO_PEOEFE — 38h
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 38h, status bits 3-5 PE OE FE (not Z86.SYS SIOERRS 78h, which adds BRKDET)

### SIO_OE — 10h
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 10h, status bit 4: overrun (counted in LOST)

### ESC / XON / XOFF — ASCII 1Bh
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: ASCII 1Bh, 11h, 13h

### VT_CUP / VT_BIAS / VT_HOME / VT_EOS / VT_EOL / VT_INVON / VT_INVOFF / VT_RLF — Terminal 3000 codes after ESC (Y +32 H J K L M I); names and values as edit.asm
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: Terminal 3000 codes after ESC (Y +32 H J K L M I); names and values as edit.asm

### FL_VT52 / FL_XON / FL_RTS / FL_ECHO / FL_CRLF — FLAGS bits 01h 02h 04h 08h 10h (TERM.ASM PFLAGS: /52 /X /R /E /C)
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: FLAGS bits 01h 02h 04h 08h 10h (TERM.ASM PFLAGS: /52 /X /R /E /C)

### PS_ESC / PS_CSI / PS_SCS / PS_HASH / PS_YROW / PS_YCOL — parser states 1-6 in PST (TERMZ80.ASM's PST comment)
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: parser states 1-6 in PST (TERMZ80.ASM's PST comment)

### NPARMAX — 4
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 4, CSI parameters kept in PARS

### NFUNC — 10
- class: constant
- addresses: termz80 equates
- aliases: none (new)
- status: verified (code + TERMZ80.ASM, z86sys.asm)
- notes: 10, functions in FTAB (T_TERM's CP 10)
