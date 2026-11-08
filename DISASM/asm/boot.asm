;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  1/10
;  BOOT.BIN - the MS-DOS boot sector (Z80, 254 bytes, runs at 3F00h)
;==============================================================================
;
;  ROLE.  Logical sector 0 of an FDD3000 MS-DOS disk.  The FDD3000's own
;  2K boot ROM restores drive
;  0, reads track 0 sector ID 0 into 3F00h and jumps here.  This sector
;  pages that ROM out, reads the first directory sector, checks that
;  entry 0 is Z86.SYS starting at cluster 2, reads the whole file to
;  D000h and jumps into it at D0FDh (`JP COLD`, volume 2).  It is the
;  only stage that knows nothing of DOS: it reads raw sectors with
;  polled WD177x I/O, exactly as the boot ROM before it does.
;
;  WHERE IT SITS IN THE BOOT CHAIN
;     boot ROM (0000h)  ->  THIS SECTOR (3F00h)
;       ->  Z86.SYS COLD (F12Ch: serial set-up, loads IO.SYS + MSDOS.SYS)
;       ->  IO.SYS INIT (8086, 0040:0000)  ->  MSDOS.SYS  ->  COMMAND.COM
;  TOS's own boot sector plays the same part for TOS A.2; the two
;  share nothing but the entry contract: interrupts off, SP = 3EFFh, ROM still paged in.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/boot_findings.md)
;   - The latch value 5Eh is drive 0 + MFM + side 0 + boot ROM OFF +
;     IN USE LED on.  The source's gloss "head loaded" names no latch
;     bit: the latch has no head-load line and the WD1770 no HLD pin.
;     Bit 7 is ACTIVE LOW (0 = LED on): CBIOS A1.1's own LIGHTOF sets it
;     to put the light out.  An earlier reading of the boot ROM had it
;     the other way, "1 = on" (notes/boot_findings.md, item 7 -
;     provisional, no hardware observation).
;   - The track number in D is bookkeeping only - it never reaches the
;     FDC.  The WD177x's own track register, set by the Restore and kept
;     current by Step-In with u=1, is what Read Sector compares against
;     the ID field.
;   - Stepping is done without verify and the following Read Sector is
;     issued with E=0 (no 30 ms settle).  The boot ROM before it uses
;     E=1.  In practice it works: this sector booted the system on a
;     real FDD3000 (2026-11-07, notes/hardware_run.md).  One drive, one
;     disk: a marginal drive's settle time is still the place to look if
;     a boot ever fails at a track change.
;   - The retry counter TRIES lives inside this very sector image and is
;     decremented in place: 8 failures over the WHOLE boot (not per
;     sector), then HALT with interrupts off.
;   - The "Non-System disk" printer is CBIOS A1.1's TXBY byte-for-byte in
;     protocol (same request / service / nibble-tag / end codes) with its
;     256-poll echo timeout and TXERR abort removed.
;
;  HARDWARE.  Booted a real FDD3000 on 2026-11-07 from the emulator-
;  written disk, TT3000 terminal, through to COMMAND.COM
;  (notes/hardware_run.md).  The NOSYS message path was not exercised.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/BOOT.BIN with Wijnen
;  z80asm v1.8 (tools/roundtrip.sh).  Code/data partition proven twice:
;  recursive descent from 3F00h reaches every instruction of the build
;  listing ../symbols/z80/BOOT.lst, and nothing else (tools/z80dis.py).
;  The image equals the first 254 bytes of logical sector 0 of
;  binaries/disk/MSDOS-FDD3000.DSK; the sector's last two bytes are 00h.
;
;  FILE:    BOOT.BIN, 254 bytes
;  MD5:     d66faa51d34896a6b93d8e65d753c8d6
;  SHA256:  ae9d07d62f7e752c6f6d2191c9365c91b38cfe3998d2fcd1e737ef72a0738b3f
;  SOURCE:  project/MSDOS/poc/BOOT.ASM (z86.py bootcode())
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  Link and
;  WD177x idioms after the FDD3000 CP/M CBIOS A1.1 (Antonio Nobrega, TMX
;  Portugal, 85/10/29).
;==============================================================================

; =====================================================================
;                    DISK GEOMETRY AND BOOT TARGET
; =====================================================================
;
; 40 tracks x 18 sectors x 256 bytes, single-sided.  Logical sector s is
; track s / 18; inside a track logical sector e has sector ID 2e, or
; 2e - 17 from e = 9 on - a 2:1 interleave, 0 2 4 .. 16 1 3 .. 17, the
; same table as Z86.SYS's SKEW (F0F8h) and mkfat.py.
;
;   logical 0       this boot sector
;   logical 1-2/3-4 FAT 1 / FAT 2
;   logical 5-12    directory (64 entries of 32 bytes)
;   logical 13-     cluster 2 onwards, 4 sectors (1 KB) per cluster
;
; A system disk has Z86.SYS as directory entry 0, contiguous from
; cluster 2 (FORMAT /S and mkfat.py both guarantee it), so this sector
; can load it without reading the FAT.

SPT:		equ	18		; sectors per track
FIRDIR:		equ	5		; logical sector of the first directory sector
FIRREC:		equ	13		; logical sector of cluster 2
IMAGE:		equ	0D000h		; where the directory sector, then Z86.SYS, land
ENTRY:		equ	0D0FDh		; Z86.SYS's BOOTJP: JP COLD (volume 2)
DIR_CLUSTER:	equ	26		; directory entry: first cluster (word)
DIR_SIZE:	equ	28		; directory entry: file size, low word
SYS_CLUSTER:	equ	2		; Z86.SYS must start at the first data cluster
BOOT_STACK:	equ	03EFFh		; the boot ROM's SP, re-established on retry
					;   (the value the boot ROM sets)
BOOT_TRIES:	equ	8		; failures allowed over the whole boot

; =====================================================================
;                    HARDWARE (names after the CP/M CBIOS A1.1)
; =====================================================================

; ---- WD177x floppy controller ----
FDCSTS:		equ	0C0h		; status (read)
FDCMD:		equ	0C0h		; command (write)
FDCSEC:		equ	0C2h		; sector register
FDCDAT:		equ	0C3h		; data register

RSTCMD_NOVFY:	equ	01h		; Restore: h=0 (spin-up enabled), V=0 (no
					;   verify), r1r0=01 (12 ms step).  CBIOS
					;   uses 05h, the same with verify.
STICMD_NOVFY:	equ	51h		; Step-In: u=1 (track register follows the
					;   head), h=0, V=0, 12 ms.  CBIOS STICMD
					;   is 55h, the same with verify.
RDSCMD:		equ	80h		; Read Sector: single, h=0, E=0 (no settle
					;   delay).  Same value and name as CBIOS.
FDC_RDERR_MASK:	equ	1Ch		; Type II status: bit 4 record not found,
					;   bit 3 CRC error, bit 2 lost data

; ---- communication port (terminal link + DRQ readback) ----
COM:		equ	2Fh		; the terminal link; bit 7 reads the
					;   WD177x DRQ line (the boot ROM polls the same
					;   register through its partial decode 20h)
MASK:		equ	5Fh		; link bits 6 and 4-0 (bit 7 is DRQ, bit 5
					;   unwired) - CBIOS's MASK
BYTEON:		equ	0Ah		; "I have a byte for you"     (CBIOS name)
SERVICO:	equ	0Fh		; terminal: "send it"         (CBIOS name)
CSTAT:		equ	10h		; tag of the low nibble       (CBIOS name)
BSTAT:		equ	40h		; tag of the high nibble      (CBIOS name)
STMSK:		equ	50h		; end of character: CBIOS's STMSK (= its
					;   DSTAT; TXBY sends it as STMSK, and
					;   Z86.SYS owns DSTAT as a variable)

; ---- system control latch (74LS273 at E0h; its bits: see HRD_DRV0_RAM) ----
HRD:		equ	0E0h
HRD_DRV0_RAM:	equ	5Eh		; 01011110b: bit 7 = 0 IN USE LED on
					;   (active low, per CBIOS LIGHTOF), bit 6 /BOOT=1
					;   (boot ROM OUT - full 64K RAM), bit 5
					;   DDEN#=0 (MFM), bit 4 SIDE1#=1 (side 0),
					;   bits 3-0 = 1110 (drive 0 selected).
					;   the boot ROM leaves 1Eh: the same with the
					;   ROM still in.


	org	3F00h

; =====================================================================
; IPL - entry from the FDD3000 boot ROM
; ---------------------------------------------------------------------
; Entry:  interrupts off, SP = BOOT_STACK, boot ROM paged at 0000h-07FFh,
;         drive 0 spun up and at track 0 (the ROM just read us from it).
; Exit:   never returns - JP ENTRY with Z86.SYS at D000h, or HALT.
;
; The first act is to page the boot ROM out: Z86.SYS will need the
; whole 64K, and the ROM's 0000h-07FFh would otherwise shadow the
; 8086's interrupt vectors.  The Restore that follows is not strictly
; needed (the ROM left the head on track 0) but makes IPL_RETRY a clean
; restart point for the error path.
; =====================================================================
IPL:
	ld	a,HRD_DRV0_RAM	; keep drive 0 / MFM / side 0, drop the boot ROM
	out	(HRD),a		; from here on 0000h-07FFh is RAM
IPL_RETRY:				; (src: IPL0) - ERR restarts here
	ld	a,RSTCMD_NOVFY	; head to track 0: the FDC's track register = 0
	call	CMD		;   (waits for the seek to finish)
	ld	hl,IMAGE	; read the first directory sector to D000h ...
	ld	de,FIRDIR	; ... track 0 (D), logical sector 5 (E)
	ld	b,1		; one sector: entries 0-7
	call	LOAD		; returns only on success

; ---- is directory entry 0 the interpreter? ---------------------------
	ld	hl,IMAGE	; entry 0's 8+3 name against "Z86     SYS"
	ld	de,SYSNAM	;   (no attribute check: hidden 06h is expected
	ld	b,11		;   but not required)
IPL_CHECK_NAME:				; (src: CK1)
	ld	a,(de)		; expected character
	cp	(hl)		; against the directory's
	jp	nz,NOSYS	; any difference: not a system disk (the source's
					;   JR, relaxed to JP by the project assembler)
	inc	hl		; next pair
	inc	de
	djnz	IPL_CHECK_NAME	; all 11 match: it is Z86.SYS
	ld	hl,(IMAGE+DIR_CLUSTER)	; and it must start at cluster 2,
	dec	hl		;   where FORMAT /S puts it, contiguous
	dec	hl		; HL - 2 = 0 exactly when cluster = SYS_CLUSTER
	ld	a,h
	or	l
	jr	nz,NOSYS	; elsewhere: this loader cannot follow the FAT

; ---- size -> whole sectors, then load it -----------------------------
	ld	hl,(IMAGE+DIR_SIZE)	; low word of the size (Z86.SYS < 64K)
	ld	a,l		; sectors = size / 256, rounded up: H, plus
	or	a		;   one if any bytes spill into a last sector
	ld	a,h		;   (8737 bytes = 2221h -> 35 sectors)
	jr	z,IPL_SIZE_OK	; exact multiple of 256: H is the count
	inc	a		; partial last sector
IPL_SIZE_OK:				; (src: CK2)
	ld	b,a		; B sectors to D000h; z86.py asserts the file ends
	ld	hl,IMAGE	;   below FF00h, so 3F00h (this code) is never hit
	ld	de,FIRREC	; from cluster 2: track 0, logical sector 13
	call	LOAD		; the directory copy at D000h is overwritten:
					;   it is no longer needed
	jp	ENTRY		; into Z86.SYS: its JP COLD at D0FDh

; =====================================================================
; LOAD - read B consecutive logical sectors to HL
; ---------------------------------------------------------------------
; Entry:  B = sector count (1-255), HL = destination, D = track,
;         E = logical sector within the track (0-17); the head must be on
;         track D (true after IPL's Restore and every Step-In below).
; Exit:   HL advanced by 256 per sector; D/E point past the last sector;
;         head stepped in if the read crossed a track end.
; Errors: never returns - any failure jumps to ERR (stack reset there).
;
; Polled transfer as CBIOS A1.1 does it: the WD177x's DRQ is read as bit
; 7 of the COM port, so `in a,(COM) / rla` puts it straight into carry.
; While DRQ is low the status register's BUSY (bit 0) says whether to
; keep waiting or give up: a command that ends without delivering a byte
; (record not found) drops BUSY with DRQ never raised.
; =====================================================================
LOAD:
	push	bc		; B = sectors still to read (INI needs B)
	push	de		; D/E survive the transfer for the advance below
	ld	a,e		; logical sector -> sector ID (2:1 interleave):
	add	a,a		;   2e for e = 0..8,
	cp	SPT		;   ... while 2e is still a valid ID
	jr	c,LOAD_SET_SECTOR
	sub	SPT-1		;   2e - 17 for e = 9..17
LOAD_SET_SECTOR:			; (src: LD0)
	out	(FDCSEC),a	; the sector register is the only address given:
					;   the track is whatever the FDC's track
					;   register holds (see the D note above)
	ld	bc,FDCDAT	; B = 0: INI counts 256; C = the data port
	ld	a,RDSCMD	; read one sector, no settle delay
	out	(FDCMD),a
	ld	a,6		; ~23 us at 4 MHz before the first status read,
LOAD_BUSY_DELAY:			;   so BUSY is already up (src: LD1)
	dec	a
	jr	nz,LOAD_BUSY_DELAY
LOAD_POLL:				; (src: LD2)
	in	a,(COM)		; DRQ -> carry
	rla
	jr	c,LOAD_TAKE_BYTE	; a byte is waiting in the data register
	in	a,(FDCSTS)	; no byte yet: still busy?
	rra			; BUSY -> carry
	jr	c,LOAD_POLL	; yes: keep waiting for DRQ
	jr	ERR		; command over and no data: a failed read
LOAD_TAKE_BYTE:				; (src: LD3)
	ini			; (HL) <- data register, HL+1, B-1
	jr	nz,LOAD_POLL	; until 256 bytes
LOAD_WAIT_END:				; (src: LD4)
	in	a,(FDCSTS)	; let the command finish (CRC check of the data
	rra			;   field comes after the last byte)
	jr	c,LOAD_WAIT_END
	in	a,(FDCSTS)	; final status of the read
	and	FDC_RDERR_MASK	; not found, CRC, lost data?
	jr	nz,ERR		; any of them: start the boot again
	pop	de		; track / sector of the sector just read
	pop	bc		; sectors to go
	inc	e		; next logical sector ...
	ld	a,e
	cp	SPT		; ... still on this track?
	jr	nz,LOAD_NEXT
	ld	e,0		; ... past the track end: sector 0 of the next
	inc	d		;   track, and step the head in (u=1 keeps the
	ld	a,STICMD_NOVFY	;   FDC's track register in step with it)
	call	CMD		; wait for the step to complete
LOAD_NEXT:				; (src: LD5)
	djnz	LOAD		; HL already points at the next 256 bytes
	ret

; =====================================================================
; ERR - a read failed: restart the whole boot, 8 times in all
; ---------------------------------------------------------------------
; Resetting SP discards LOAD's frame and IPL's return address, so the
; restart is clean from any depth.  TRIES is a byte of this loaded
; sector, decremented in place: the budget is for the whole boot, so a
; disk that fails at the same place every time stops after 8 attempts.
; HALT with interrupts off is a permanent stop - reset is the only exit.
; =====================================================================
ERR:
	ld	sp,BOOT_STACK	; forget every frame above the entry stack
	ld	hl,TRIES	; spend one attempt
	dec	(hl)
	jp	nz,IPL_RETRY	; budget left: from the Restore again (JR in the
					;   source, relaxed to JP: 143 bytes back)
	halt			; 8 failures: give up silently (no message - the
					;   link code below is not reached from here)

; =====================================================================
; CMD - issue a WD177x Type I command and wait for it to finish
; ---------------------------------------------------------------------
; Entry:  A = command (Restore / Step-In).   Exit: A = status >> 1.
; Preserves BC.  The ~57 us DJNZ pause (12h turns) lets the controller
; raise BUSY before it is polled - the same reason as LOAD_BUSY_DELAY.
; =====================================================================
CMD:
	out	(FDCMD),a	; start the command
	push	bc		; callers keep their count in B
	ld	b,12h		; ~57 us before BUSY is trusted
CMD_DELAY:				; (src: CMD1)
	djnz	CMD_DELAY
	pop	bc
CMD_WAIT:				; (src: CMD2)
	in	a,(FDCSTS)	; BUSY (bit 0) -> carry
	rra
	jr	c,CMD_WAIT	; no timeout: a dead drive hangs here
	ret			; status is not checked (no verify was asked)

; =====================================================================
; NOSYS - print "Non-System disk" on the terminal and stop
; ---------------------------------------------------------------------
; The console link protocol of CBIOS A1.1's TXBY, sender side, per
; character:
;    BYTEON (0Ah) out, until the terminal answers SERVICO (0Fh);
;    low nibble | CSTAT (10h) out, until it is echoed back;
;    high nibble | BSTAT (40h) out, until it is echoed back;
;    STMSK (50h) out - end of character.
; CBIOS gives each echo 256 polls and sends 07h (TXERR) on a timeout;
; here there is nobody to report an error to, so the waits are endless.
; The terminal side of this dialect is the Terminal ROM's console code
; (in the TC3256's Terminal 3000 ROM), which sees the six link wires as
; bits 0-3, 6, 7 - so the tags read 80h/40h at that end.
; =====================================================================
NOSYS:
	ld	hl,NSMSG	; CR LF "Non-System disk" CR LF
NOSYS_NEXT_CHAR:			; (src: NS1)
	ld	e,(hl)		; E = character; 00h ends the message
	inc	e		; test E for zero without disturbing A
	dec	e
	jr	z,NOSYS_HALT	; end of message
NOSYS_REQUEST:				; (src: NS2)
	ld	a,BYTEON	; offer a byte ...
	out	(COM),a
	in	a,(COM)		; the terminal's answer, link bits only
	and	MASK
	cp	SERVICO		; ... until the terminal is ready for it
	jr	nz,NOSYS_REQUEST	; keep offering: no timeout here
	ld	a,e		; low nibble, tagged
	and	0Fh
	or	CSTAT		; 1st nibble carries bit 4 (CBIOS: CSTAT)
	call	NSPUT		; send it, wait for the echo
	ld	a,e		; high nibble, tagged
	rrca			; bring bits 7-4 down to 3-0
	rrca
	rrca
	rrca
	and	0Fh
	or	BSTAT		; 2nd nibble carries bit 6 (CBIOS: BSTAT)
	call	NSPUT
	ld	a,STMSK		; character complete
	out	(COM),a		; (no wait: the next BYTEON resynchronises)
	inc	hl		; next character
	jr	NOSYS_NEXT_CHAR

; ---------------------------------------------------------------------
; NSPUT - send one tagged nibble and wait for the terminal's echo
; Entry: A = nibble | tag.   Corrupts A, D.
; ---------------------------------------------------------------------
NSPUT:
	out	(COM),a		; put the nibble on the link
	ld	d,a		; keep it to compare with the echo
NSPUT_WAIT_ECHO:			; (src: NSP1)
	in	a,(COM)		; what the terminal drives back
	and	MASK		; link bits only (drop DRQ, bit 5)
	cp	d		; the echo is the acknowledgement
	jr	nz,NSPUT_WAIT_ECHO	; endless: CBIOS gives up after 256
	ret

NOSYS_HALT:				; (src: NS4)
	halt			; message shown; interrupts are off: stop here

; =====================================================================
;                              DATA
; =====================================================================
SYSNAM:
	defb	'Z86     SYS'	; directory form of Z86.SYS (8+3, space-padded)
NSMSG:
	defb	13,10,'Non-System disk',13,10,0	; 00h-terminated for NOSYS
TRIES:
	defb	BOOT_TRIES	; retry budget, decremented in place by ERR
ENDIPL:				; 3FFEh: 254 bytes; the sector's last two are 00h
