# Dictionary — Z86.SYS part 07 (EB46h-EDDBh: TRAP .. WRSEC)

Renames (each label line carries `; (src: OLD)`; no reference outside part 07 in
Z86.SYS.lst or CPMZ80.lst) and new equates.

## Renamed labels

### TRAP_EXIT — TRAP's common exit: restore IX (NEXT) and BC (8086 code pointer)
- class: routine
- addresses: Z86.SYS EB5Ch
- aliases: TRAPX (source)
- status: verified (code + BIOS.ASM)

### FLUSH_DRAIN — T_FLUSH loop: receive and discard keys while the terminal shows KEYRDY
- class: routine
- addresses: Z86.SYS EBEAh
- aliases: FL1 (source)
- status: verified (code + BIOS.ASM)

### PEEKEY_HELD — PEEKEY exit with the held key: A = KBUF, CF=1
- class: routine
- addresses: Z86.SYS EC0Eh
- aliases: PK1 (source)
- status: verified (code + BIOS.ASM)

### CONOUT_RETRY — CONOUT (re)start: send COCHR through COSEND
- class: routine
- addresses: Z86.SYS EC24h
- aliases: CO1 (source)
- status: verified (code + BIOS.ASM)

### CONOUT_WAIT_ABORT — CONOUT after a failed send: wait for the terminal to show LINKERR (07h)
- class: routine
- addresses: Z86.SYS EC2Ch
- aliases: CO2 (source)
- status: verified (code + BIOS.ASM)

### COSEND_OFFER — COSEND: BYTEON until SERVICO (CBIOS TXBY READY)
- class: routine
- addresses: Z86.SYS EC42h
- aliases: COS1 (source)
- status: verified (code + BIOS.ASM)

### COSEND_ECHO_LO — COSEND: wait (255 polls) for the low-nibble echo (CBIOS TXTW1)
- class: routine
- addresses: Z86.SYS EC56h
- aliases: COS2 (source)
- status: verified (code + BIOS.ASM)

### COSEND_ECHO_HI — COSEND: wait (255 polls) for the high-nibble echo (CBIOS TXTW2)
- class: routine
- addresses: Z86.SYS EC68h
- aliases: COS3 (source)
- status: verified (code + BIOS.ASM)

### CONIN_WAIT_ABORT — CONIN after a failed receive: wait until the link stops reading LINKERR
- class: routine
- addresses: Z86.SYS EC83h
- aliases: CI1 (source)
- status: verified (code + BIOS.ASM)

### CONIN_GOT — CONIN exit: A = key from B
- class: routine
- addresses: Z86.SYS EC8Dh
- aliases: CI2 (source)
- status: verified (code + BIOS.ASM)

### CIRECV_LO — CIRECV: wait (255 polls) for the CSTAT-tagged low nibble, echo it (CBIOS RXTW1)
- class: routine
- addresses: Z86.SYS ECA1h
- aliases: CIR1 (source)
- status: verified (code + BIOS.ASM)

### CIRECV_HI — CIRECV: wait (255 polls) for the bit-6 (BSTAT) high nibble, echo it (CBIOS RXTW2)
- class: routine
- addresses: Z86.SYS ECB5h
- aliases: CIR2 (source)
- status: verified (code + BIOS.ASM)

### CIRECV_END — CIRECV: wait for STMSK (or LINKERR) and answer STMSK (CBIOS RXTW3)
- class: routine
- addresses: Z86.SYS ECCAh
- aliases: CIR3 (source)
- status: verified (code + BIOS.ASM)

### DLOOP_DIV18 — DISKIO: DX / 18 by repeated subtraction (B = track)
- class: routine
- addresses: Z86.SYS ED26h
- aliases: DV1 (source)
- status: verified (code + BIOS.ASM)

### DFAIL_SCAN — DFAIL: find the highest set status bit 7..3 -> ERRTAB index
- class: routine
- addresses: Z86.SYS ED68h
- aliases: DF1 (source)
- status: verified (code + BIOS.ASM)

### DFAIL_CODE — DFAIL: A = DOS error code from ERRTAB
- class: routine
- addresses: Z86.SYS ED6Eh
- aliases: DF2 (source)
- status: verified (code + BIOS.ASM)

### SECTIO_TRY — SECTIO attempt: SEEK, set FDCSEC, transfer (re-entered per retry)
- class: routine
- addresses: Z86.SYS ED8Bh
- aliases: SIO1 (source)
- status: verified (code + BIOS.ASM)

### SECTIO_WRITE — SECTIO: write branch (CALL WRSEC)
- class: routine
- addresses: Z86.SYS EDA2h
- aliases: SIO2 (source)
- status: verified (code + BIOS.ASM)

### SECTIO_CHECK — SECTIO: judge the FDC status; WP returns at once, else retry
- class: routine
- addresses: Z86.SYS EDA5h
- aliases: SIO3 (source)
- status: verified (code + BIOS.ASM)

### RDSEC_LOOP — RDSEC: DRQ-polled INI loop, left only through INTRQ/FDCINT (CBIOS RLP)
- class: routine
- addresses: Z86.SYS EDC1h
- aliases: RD1 (source)
- status: verified (code + BIOS.ASM)

### WRSEC_LOOP — WRSEC: DRQ-polled OUTI loop, left only through INTRQ/FDCINT (CBIOS WRLP)
- class: routine
- addresses: Z86.SYS EDD3h
- aliases: WR1 (source)
- status: verified (code + BIOS.ASM)

## New equates

### WSTA — FDD to terminal: "I am waiting for a key" (CIRECV's request)
- class: constant
- addresses: value 06h (Z86.SYS part 07)
- aliases: none (the source writes the literal)
- status: verified (code + BIOS.ASM + CBIOS RXBY; CBIOS name WSTA equ 06h)
- notes: CBIOS's own name and value.

### KEYRDY — terminal idle code: a key is waiting
- class: constant
- addresses: value 04h (Z86.SYS part 07)
- aliases: none (the source writes the literal)
- status: verified (code + BIOS.ASM + CBIOS CONST + fdd86.py Link)
- notes: CBIOS tests the bare 04 (no name); name new.

### LINKERR — link abort code, sent by either side
- class: constant
- addresses: value 07h (Z86.SYS part 07)
- aliases: none (the source writes the literal)
- status: verified (code + CBIOS TXERR/RXERR + fdd86.py Link)
- notes: CBIOS has labels TXERR/RXERR but no constant name; name new.

### RDSCMD — WD177x Read Sector (single, h=0, E=0)
- class: constant
- addresses: value 80h (Z86.SYS part 07)
- aliases: none (the source writes the literal)
- status: verified (code + BIOS.ASM + CBIOS RDSCMD)
- notes: Same name/value as CBIOS and boot.asm (boot.asm defines its own copy; separate volume).

### WRSCMD — WD177x Write Sector (single, precomp on, E=0)
- class: constant
- addresses: value 0A0h (Z86.SYS part 07)
- aliases: none (the source writes the literal)
- status: verified (code + BIOS.ASM + CBIOS WRSCMD)
- notes: Same name/value as CBIOS.
