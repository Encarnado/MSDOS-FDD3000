# Z86.SYS part 01 (D000h-D7FFh) - dictionary

Renamed labels (all local to part 01; checked against Z86.SYS.lst and CPMZ80.lst) and new equates.

### SPUT_FOREVER — SPRN/SAUXO common tail: E = byte, HL = 0 (no poll limit), falls into SPUT
- class: routine (local label)
- addresses: Z86.SYS D044
- aliases: SPF (source)
- status: verified (code + I86.ASM)

### SPUT_POLL — SPUT's status poll: waits for DSR + TxRDY (IOMASK), charging SWAIT
- class: routine (local label)
- addresses: Z86.SYS D04F
- aliases: SP1 (source)
- status: verified (code + I86.ASM)

### SPUT_SEND — SPUT's send: DEC C to the data port, OUT E, INC C back
- class: routine (local label)
- addresses: Z86.SYS D05D
- aliases: SP2 (source)
- status: verified (code + I86.ASM)

### SGET_POLL — SGET's poll: SERR, then RxRDY test, charging SWAIT
- class: routine (local label)
- addresses: Z86.SYS D06B
- aliases: SG1 (source)
- status: verified (code + I86.ASM)

### SGET_TAKE — SGET's receive: read the data port, drop RTS (ACOM), A = byte, CF = 0
- class: routine (local label)
- addresses: Z86.SYS D07A
- aliases: SG2 (source)
- status: verified (code + I86.ASM)

### SSTAT_MAP — SSTAT's 7-pass loop mapping 8251A status bits (LSMAP) into PC line-status bits
- class: routine (local label)
- addresses: Z86.SYS D0C7
- aliases: SS1 (source)
- status: verified (code + I86.ASM)

### I14EXT_STOP — I14EXT after the parity decode: adds the stop bits from BL
- class: routine (local label)
- addresses: Z86.SYS D5B8
- aliases: I14E1 (source)
- status: verified (code + I86.ASM)

### I14INI_MERGE — I14INI after the stop-bit choice: merges parity, extracts the baud index
- class: routine (local label)
- addresses: Z86.SYS D5D9
- aliases: I14I1 (source)
- status: verified (code + I86.ASM)

### I14SET_FETCH — I14SET after the BAUDT page-carry guard: E = baud code, CALL SSET, JP SSTAT
- class: routine (local label)
- addresses: Z86.SYS D5F4
- aliases: I14S1 (source)
- status: verified (code + I86.ASM)

### SH16_ROL — SHPG 16-bit slot ROL (k = 0, slot D700h) loop head
- class: routine (local label)
- addresses: Z86.SYS D700
- aliases: S16R0 (source)
- status: verified (code + I86.ASM)

### SH16_ROL_NEXT — SHPG 16-bit ROL: count step after the wrap-around bit
- class: routine (local label)
- addresses: Z86.SYS D704
- aliases: S16R0A (source)
- status: verified (code + I86.ASM)

### SH16_ROR — SHPG 16-bit slot ROR (k = 1, slot D710h) loop head
- class: routine (local label)
- addresses: Z86.SYS D710
- aliases: S16R1 (source)
- status: verified (code + I86.ASM)

### SH16_ROR_NEXT — SHPG 16-bit ROR: count step after the wrap-around bit
- class: routine (local label)
- addresses: Z86.SYS D718
- aliases: S16R1A (source)
- status: verified (code + I86.ASM)

### SH16_RCL — SHPG 16-bit slot RCL (k = 2, slot D720h) loop head
- class: routine (local label)
- addresses: Z86.SYS D722
- aliases: S16R2 (source)
- status: verified (code + I86.ASM)

### SH16_RCR — SHPG 16-bit slot RCR (k = 3, slot D730h) loop head
- class: routine (local label)
- addresses: Z86.SYS D732
- aliases: S16R3 (source)
- status: verified (code + I86.ASM)

### SH16_SHL — SHPG 16-bit slot SHL (k = 4, slot D740h) loop head
- class: routine (local label)
- addresses: Z86.SYS D740
- aliases: S16R4 (source)
- status: verified (code + I86.ASM)

### SH16_SHR — SHPG 16-bit slot SHR (k = 5, slot D750h) loop head
- class: routine (local label)
- addresses: Z86.SYS D750
- aliases: S16R5 (source)
- status: verified (code + I86.ASM)

### SH16_SAL — SHPG 16-bit slot SAL (k = 6, slot D760h) loop head
- class: routine (local label)
- addresses: Z86.SYS D760
- aliases: S16R6 (source)
- status: verified (code + I86.ASM)

### SH16_SAR — SHPG 16-bit slot SAR (k = 7, slot D770h) loop head
- class: routine (local label)
- addresses: Z86.SYS D770
- aliases: S16R7 (source)
- status: verified (code + I86.ASM)

### SH8_ROL — SHPG 8-bit slot ROL (k = 0, slot D780h) loop head
- class: routine (local label)
- addresses: Z86.SYS D780
- aliases: S8R0 (source)
- status: verified (code + I86.ASM)

### SH8_ROR — SHPG 8-bit slot ROR (k = 1, slot D790h) loop head
- class: routine (local label)
- addresses: Z86.SYS D790
- aliases: S8R1 (source)
- status: verified (code + I86.ASM)

### SH8_RCL — SHPG 8-bit slot RCL (k = 2, slot D7A0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7A2
- aliases: S8R2 (source)
- status: verified (code + I86.ASM)

### SH8_RCR — SHPG 8-bit slot RCR (k = 3, slot D7B0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7B2
- aliases: S8R3 (source)
- status: verified (code + I86.ASM)

### SH8_SHL — SHPG 8-bit slot SHL (k = 4, slot D7C0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7C0
- aliases: S8R4 (source)
- status: verified (code + I86.ASM)

### SH8_SHR — SHPG 8-bit slot SHR (k = 5, slot D7D0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7D0
- aliases: S8R5 (source)
- status: verified (code + I86.ASM)

### SH8_SAL — SHPG 8-bit slot SAL (k = 6, slot D7E0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7E0
- aliases: S8R6 (source)
- status: verified (code + I86.ASM)

### SH8_SAR — SHPG 8-bit slot SAR (k = 7, slot D7F0h) loop head
- class: routine (local label)
- addresses: Z86.SYS D7F0
- aliases: S8R7 (source)
- status: verified (code + I86.ASM)

### ACOM — 8251A command: TxEN + DTR + RxE, RTS off
- class: constant
- addresses: equ 07h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A command: TxEN + DTR + RxE, RTS off. SSET's final command; SGET after a byte (drop RTS). CBIOS A1.1 ACOM, same value.

### SIOWORD — 8251A command: ACOM + RTS
- class: constant
- addresses: equ 27h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A command: ACOM + RTS. Written by SPUT and SGET before polling. CBIOS A1.1 SIOWORD, same value.

### IOERR — 8251A command: SIOWORD + ER (error reset of PE OE FE)
- class: constant
- addresses: equ 37h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A command: SIOWORD + ER (error reset of PE OE FE). Written by SERR. CBIOS A1.1 IOERR, same value.

### SIORESET — 8251A command IR (internal reset): next control write is a mode byte
- class: constant
- addresses: equ 40h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A command IR (internal reset): next control write is a mode byte. SSET, after three 00h. new; not in CBIOS.

### IOMASK — 8251A status DSR (bit 7) + TxRDY (bit 0): SPUT sends when both are set
- class: constant
- addresses: equ 81h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A status DSR (bit 7) + TxRDY (bit 0): SPUT sends when both are set. CBIOS A1.1 IOMASK, same value; CBIOS's comment calls bit 7 CTS (8251A: DSR).

### RXRDY — 8251A status bit NUMBER of RxRDY (for BIT n,A)
- class: constant
- addresses: equ 1 (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A status bit NUMBER of RxRDY (for BIT n,A). SGET. CBIOS A1.1 RXRDY, same value and use.

### SIOERRS — 8251A status bits 3-6: PE OE FE SYNDET/BRKDET
- class: constant
- addresses: equ 78h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A status bits 3-6: PE OE FE SYNDET/BRKDET. SERR's test. CBIOS A1.1 calls it ERR; renamed because ERR is BOOT.BIN's error label.

### SIO_X16 — 8251A mode bits 1-0 = 10: asynchronous, x16 clock
- class: constant
- addresses: equ 02h (part 01)
- aliases: none
- status: verified (code + I86.ASM + 8251A command/status format); real WD2123 behaviour provisional (untested on hardware)
- notes: 8251A mode bits 1-0 = 10: asynchronous, x16 clock. OR-ed in by I14SET. new; = CBIOS SIOTAB's first byte (02).
