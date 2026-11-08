;==============================================================================
;  MS-DOS 1.25 ON THE TIMEX FDD3000  --  THE DISASSEMBLIES  --  2/7
;  Z86.SYS - the 8086 interpreter and the Z80 BIOS (Z80, 8 737 bytes, D000h)
;==============================================================================
;
;  ROLE.  The heart of the system: an 8086 emulated in Z80 code, plus the
;  BIOS that does every device job natively.  The FDD3000 has a Z80, so
;  MS-DOS 1.25 (8086 code) runs on this interpreter at ~17 000 8086
;  instructions a second.  Guest memory is the Z80's 0000h-CFFFh (8086
;  linear n = Z80 n); the 8086 registers live in the REGS page at D000h,
;  so every ModR/M operand decodes to a host pointer.  IO.SYS's device
;  entries and the PC ROM BIOS vectors are 2-byte traps (0Fh nn) that
;  land in TRAP, here, with the work done in Z80 code.
;
;  MAP
;     D000-D0FF  REGS page: registers, segment bases, interpreter state;
;                serial routines in its unused end; BOOTJP (D0FDh) = JP COLD
;     D100-D4FF  split jump tables OPLO/OPHI (opcodes), EALO/EAHI (ModR/M)
;     D500-D7FF  page-aligned slot blocks BCORE / WCORE / SHPG, selected by
;                self-modifying JPs (ALU0J-ALU5J, G80J-G83J, SHB2/SHW2);
;                INT 14h set-up in BCORE's end
;     D800-EB45  START, NEXT (the dispatcher, 58 T/instruction), prefixes,
;                ModR/M, the opcode handlers, REP string engine
;     EB46-F12B  the BIOS: TRAP + TTAB, console link, disk, serial, clock,
;                PC BIOS emulation, CPM.COM support, SKEW, variables
;     F12C-F220  COLD, the boot loader (overwritten by CPMZ80, volume 3)
;
;  IN THE CHAIN.  BOOT.BIN (volume 1) loads this file and jumps to D0FDh;
;  COLD loads IO.SYS + MSDOS.SYS and starts the 8086 at 0040:0000.
;
;  KEY FINDINGS OF THIS DISASSEMBLY (notes/z86sys_findings.md indexes the
;  per-region notes notes/z86_part01..08_findings.md)
;   - BUG: REP MOVSW with source and destination one byte apart (DI = SI+1,
;     DF=0, or DI = SI-1, DF=1) copies byte by byte through LDIR/LDDR, so
;     memory differs from an 8086, which moves whole words.  SI/DI/CX are
;     right.  Verified by running against cpu86.py; the fuzzer draws SI and
;     DI independently and almost never hits it.            (part 04)
;   - The overview's "AF from bit 11 after 16-bit inc/dec" is wrong for
;     INC/DEC: INC16/DEC16 end in RRA, which clears H, so AF is always 0
;     (INC AX, AX=000Fh: F002h here, F012h in cpu86).  Bit 11 holds for
;     16-bit ADD/ADC/SUB/SBB/CMP.  And not only DAA/DAS/AAA/AAS read AF:
;     PUSHF, LAHF and INT copy it out.  Verified by running.  (parts 01, 03)
;   - Latent PEEKEY bug: `cp 04h / ret nz` leaves carry set if the link
;     reads 00h-03h, so STATUS reports a phantom key and the next INPUT
;     blocks.  Code verified; whether the link ever reads 00h-03h is
;     untested.  Same 2 bytes fixed: `xor 04h`.             (part 07)
;   - Divergences from cpu86.py, all outside DOS's code paths: FE /2-/7 stops
;     at BADSTOP where cpu86 runs the FF word forms; FF F4 pushes the old SP
;     while 54h pushes the new; LES/LDS with a register operand read two
;     adjacent registers; OUT DX goes to O_NOP; F1h (LOCK) is rejected by
;     both models.  IN returns FFh/FFFFh and OUT does nothing - every device
;     is a trap.                                             (parts 02, 05, 06)
;   - RST 38h borrowing: 0038h is also the 8086's INT 0Eh vector, so HOOK38
;     owns it only while the 8086 is stopped inside a trap.  A disk buffer
;     covering 0038h-003Ah would collide with the hook (read only, never
;     seen in DOS 1.25).                                     (part 08)
;   - FIXED 2026-11-08 (this build): floppy waits had no timeout - with no
;     disk or no drive the WD1770 sees no index pulses and DOS hung for
;     good on DIR B: - and disk retries never moved the head.  FDCCMD,
;     FHOME and XFER's first-byte wait now time out (~3 s; DOS answers
;     "Not ready" after ~10 s, its FAT fallback asking three times), and
;     SECTIO restores half-way through its retries.  The byte loop is
;     untouched.  (parts 07, 08; test_fdtimeout.py)
;   - RTS stays raised more often than the README says.      (part 01)
;   - Latch bit 7 (IN USE LED) is active low: CBIOS's own LIGHTOF sets it.
;     ROMDIS fdd3000b.asm says the opposite (boot_findings item 7).
;   - The guide's code seeds miss three DW tables (G3BT, G3WT, G5T, via
;     JP JTAB) and code reached only by LD IX,nn (RESTORE).  RADVS
;     (E25Dh-E26Eh) is dead: nothing refers to it.  (notes/partition_findings.md)
;   - Assembler hazard found here: in an 8-bit operand, Wijnen z80asm reads
;     B_ES as register B - `add a,B_ES&0FFh` assembles `add a,b`, silently.
;     Five sites are written `0FFh&B_ES` (dict/CONVENTIONS.md rule 3).
;
;  VERSION.  This volume is the 2026-11-08 build: the 2026-11-07 Z86.SYS
;  plus the floppy timeouts and the re-seek above.  Same size (8 737 bytes);
;  everything from SECTIO to the BIOS data moved, SKEW / variables /
;  ENDBIOS did not (padding before SKEW), so CPMZ80 and CPM.COM are
;  unchanged.  The new code is in the free ends of the EALO and EAHI pages
;  (z86.py ;@SLACK).  Baseline volume: git eeadb54.
;
;  HARDWARE.  The 2026-11-07 BUILD ran on a real FDD3000 (emulator-written
;  disk, TT3000 terminal): boot, DOS console tools, EDIT, CPM.COM and
;  PRN/AUX all worked (notes/hardware_run.md).  THIS build has passed the
;  emulator suites (lockstep, fuzz, test_fdd86 groups 1-5 and 8, test_edit,
;  test_fdtimeout) but has NOT yet run on the real machine; the floppy byte
;  loop that did run there is unchanged.  Not exercised on hardware in
;  either build: FORMAT TRACK (trap 1Bh).  PEEKEY values 00h-03h stay a
;  code finding.
;
;  VERIFICATION.  Reassembles BYTE-IDENTICAL to bin/Z86.SYS with Wijnen z80asm
;  v1.8 (tools/roundtrip.sh).  Code/data partition: recursive descent from the
;  guide's seeds plus the three tables above reaches every instruction of
;  ../symbols/z80/Z86.SYS.lst except dead RADVS, with zero disagreements
;  (tools/z80dis.py).  Narrated in eight regions in parallel, each checked
;  against the frozen baseline of the other seven (tools/z86parts.py), then
;  joined; lint 0 errors, 87.8% of instruction lines commented.
;
;  NAMES.  Global names are the author's (I86.ASM / BIOS.ASM): O_xxx opcode
;  handlers, EAnn ModR/M routines, T_xxx traps, R_xx / B_xx register and base
;  cells.  182 numbered locals were renamed; each label line keeps
;  `; (src: OLD)`, and dict/z86_part01..08.md hold the alias entries.
;
;  FILE:    Z86.SYS, 8 737 bytes
;  MD5:     df195b7170363dc6913d740fe2512296
;  SHA256:  0ebfdf104d29ad19a95ba4dc6e0ff8802f4087665110f4997814e4652a41f291
;  SOURCE:  project/MSDOS/poc/I86.ASM + BIOS.ASM (z86.py build(bios=True))
;
;  CREDITS.  Original code: the FDD3000-MSDOS project (2026).  Console link,
;  WD177x transfer and WD2123 set-up after the FDD3000 CP/M CBIOS A1.1
;  (Antonio Nobrega, TMX Portugal, 85/10/29).  Disassembly and annotation in
;  the style of "The Complete TMX Portugal ROM Disassemblies", LoadZX Museum,
;  2026.
;==============================================================================
	org	0d000h

; =====================================================================
;   HARDWARE - one shared block for the whole volume.  Names follow
;   fdd3000b.asm (ROMDIS), TOSDIS and the CP/M CBIOS A1.1 so the same
;   port reads the same in both corpora (dict/CONVENTIONS.md).
; =====================================================================
; ---- WD177x floppy controller ----
FDCSTS:		equ	0C0h		; status (read)
FDCMD:		equ	0C0h		; command (write)
FDCTRK:		equ	0C1h		; track register
FDCSEC:		equ	0C2h		; sector register
FDCDAT:		equ	0C3h		; data register
; ---- communication port: terminal link, bit 7 = WD177x DRQ ----
COM:		equ	2Fh
MASK:		equ	5Fh		; link bits 6, 4-0 (CBIOS MASK)
BYTEON:		equ	0Ah		; FDD: "I have a byte"       (CBIOS)
SERVICO:	equ	0Fh		; terminal: "send it"        (CBIOS)
STANDBY:	equ	05h		; terminal idle/request code (CBIOS)
CSTAT:		equ	10h		; low-nibble tag             (CBIOS)
BSTAT:		equ	40h		; high-nibble tag            (CBIOS)
STMSK:		equ	50h		; end of character (CBIOS STMSK = its DSTAT;
					;   DSTAT here is the BIOS disk-status byte)
; ---- system control latch (74LS273; bit map in fdd3000b.asm HRD_*) ----
HRD:		equ	0E0h
; ---- WD2123 dual UART (8251A-compatible channels) ----
; Each channel: data port, control port = data + 1 (status on read,
; mode / command on write), and its own baud-rate register.  The serial
; routines below rely on that pairing: they hold the control port in C
; and reach the data port with DEC C.  Channel A is CP/M's LIST and
; DOS's PRN; channel B is PUNCH / READER and AUX (CBIOS A1.1 layout).
UART_BAUD_CHA:	equ	10h		; baud-rate register, channel A (printer)
UART_BAUD_CHB:	equ	11h		; baud-rate register, channel B (AUX)
UART_DATA_CHB:	equ	40h		; channel B data (CBIOS CANALB)
UART_CMD_CHB:	equ	41h		; status (read) / mode+command (write)
UART_DATA_CHA:	equ	80h		; channel A data (CBIOS CANALA)
UART_CMD_CHA:	equ	81h		; status (read) / mode+command (write)

; ---- 8251A command and status values used in this part ----
; Command byte (write to the control port once the mode is set):
;   bit 0 TxEN, 1 DTR, 2 RxE, 3 send break, 4 ER (error reset),
;   5 RTS, 6 IR (internal reset), 7 EH (enter hunt; sync mode only).
; Status byte (read from the control port):
;   bit 0 TxRDY, 1 RxRDY, 2 TxEMPTY, 3 PE, 4 OE, 5 FE,
;   6 SYNDET/BRKDET, 7 DSR.
; Names and values are CBIOS A1.1's where it has them (one name, one
; value across both corpora).
ACOM:		equ	07h		; TxEN + DTR + RxE, RTS off   (CBIOS ACOM)
SIOWORD:	equ	27h		; ACOM + RTS                  (CBIOS SIOWORD)
IOERR:		equ	37h		; SIOWORD + ER: clear PE/OE/FE (CBIOS IOERR)
SIORESET:	equ	40h		; IR: back to "expecting a mode byte"
IOMASK:		equ	81h		; status DSR + TxRDY: both needed to send
					;   (CBIOS IOMASK; CBIOS's comment calls
					;   bit 7 "CTS" - it is DSR on an 8251A)
RXRDY:		equ	1		; status bit number of RxRDY  (CBIOS RXRDY)
SIOERRS:	equ	78h		; status bits 3-6: PE OE FE BRKDET (CBIOS
					;   ERR, renamed: ERR is BOOT.BIN's label)
SIO_X16:	equ	02h		; mode bits 1-0 = 10: async, x16 clock


; =====================================================================
;   THE TWO HALVES - one binary, two files, mirroring the author's
;   I86.ASM and BIOS.ASM.  Assembly is in address order, so the BIOS
;   pieces that live in interpreter pages (the serial routines in the
;   REGS page end, D03Eh-D0F0h; INT 14h set-up in the BCORE page end,
;   D5A2h-D5FFh - guide item 7) stay physically in z86_interp.asm, each
;   marked as BIOS code.  Include paths are relative to DISASM/, where
;   tools/roundtrip.sh runs.
; =====================================================================
	include	"asm/z86_interp.asm"	; D000h-EB45h  the 8086 interpreter (I86.ASM)
	include	"asm/z86_bios.asm"	; EB46h-F220h  the Z80 BIOS and COLD (BIOS.ASM)

