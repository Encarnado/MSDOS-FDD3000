# TERM.COM — findings (2026-11-08)

Gate: PASS (`tools/roundtrip.sh term`, NASM -O0, byte-identical to bin/TERM.COM, 6679 bytes,
MD5 e28710898db1d2cb34972e30b1201089). The 8086 part (0100h-0D7Ah, 3195 bytes) matches
`../symbols/x86/TERM.LST` instruction for instruction. All 214 labels (63 renamed, with
`(src: OLD)`) sit at the addresses TERM.COM.sym gives (checked from the NASM listing). The
16-byte header at 0D7Bh is now named DW fields: length = `Z80_CODE_END-Z80_CODE` (0D8Ch =
3468), then NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS as equates, checked against
`../symbols/z80/Z86.SYS.sym`: D83B EB4D EBE3 EC00 EC0E F12A F12C. The 3468 bytes from file
offset 0C8Bh to the end are bin/TERMZ80.BIN byte for byte, and are now
`incbin "bin/TERMZ80.BIN"`. No bytes follow the image. Comment coverage 86% of instruction
lines (tools/lint.py: 794 instructions, 0 errors, 0 warnings).

Author: João Encarnado, for the FDD3000-MSDOS project (2026). This is not Microsoft code.

Hardware: **not run on a real FDD3000 in the merged build** (notes/hardware_run.md has no
TERM run). Whether João ran TERM on hardware is not recorded; see finding 12 for the
README's conflicting lines. Everything here about the serial line is verified on the
emulator (fdd86.py's WD2123 model) at best, and provisional on hardware.

## What test_term.py verifies (emulator; fdd86.py, a host on channel B sending in real time)

1. Start-up: `TERM AUX:9600` sets mode 8Eh (1.5 stop bits kept from the boot, no parity,
   8 bits, x16) and baud code 14; the top row reads "TERM: Ctrl-A for the menu".
2. 21 code cases, then 60 batches of random codes, the screen cell by cell against a Python
   VT100 (`VT`).
3. Keys: plain, arrows (ESC [ A, ESC O A in cursor-key mode), ESC alone; menu Ctrl-A sends a
   Ctrl-A; menu B gives one break and leaves the command register at 27h; the bottom line
   blank after the menu.
4. /E and the menu's E (echo off and on again; VT52 with /E); /C and the menu's C; the menu
   line holds "E echo+" / "C lf+" and its columns 62-63 stay blank.
5. 6 KB of text with a slow terminal model, at 9600 and 19200 baud: /X and /R lose nothing;
   /N loses bytes (as expected).
6. The log: 12 KB at 19200 baud through the 8 KB buffer; LOG.TXT is every byte; nothing lost.
7. XMODEM receive: CRC at 9600 with block 6 corrupted once (the XRBAD / PURGE / NAK path);
   CRC at 19200; checksums when the sender ignores 'C' (the three-'C'-then-NAK fallback).
   XMODEM send: CRC at 9600, checksums at 19200. The files are the same bytes (received
   files compared with the ^Z-padded original).
8. /52 (VT52 codes, arrows as they are) and /80 (80 columns).

Not exercised by any test: menu Q, the usage and VERMSG paths, bad port / baud / fields,
CRMSG / NFMSG, disk full (log or receive), cancel by key, CAN from the other side, the retry
limits, a duplicated block, the sender's 60 s timeout.

## Findings

1. **QUIT leaves the host stopped.** The menu is entered through TERMZ80's SMENU → HOLD,
   which sets STOPF/HOLDF and calls FLOWOFF: XOFF queued (and sent by the 100 ms of RXPOLL
   in HOLD) with /X, the command register 07h (RTS off) with /R. The host is let go only by
   RESUME, called from a later SESS (ring empty) or from ENSURE in RECV / SEND / BRK. Menu Q
   goes to QUIT → INT 20h without any of those, so after TERM ends the host stays XOFFed or
   sees RTS off until something sends XON / raises RTS. With /N nothing happens.
   *verified by reading (TERM.ASM QUIT + TERMZ80.ASM SMENU, HOLD, FLOWOFF, RESUME); not
   tested (test_term.py never presses Q); behaviour on a real host provisional.*

2. **One CAN cancels.** XR_WAIT takes a single CAN as a block's first byte as "Cancelled by
   the other side"; XS_WAITC and the per-block answer do the same. Most XMODEM programs want
   two CANs, so that line noise does not end a transfer. *verified by reading (code +
   source).*

3. **The sender's wait for 'C' / NAK is unbounded under noise.** XS_WAITC waits 60 s for one
   byte; any byte other than 'C', NAK or CAN restarts the 60 s with no count. Only a key or a
   full minute of silence ends it. Harmless (the user can press a key). *verified by
   reading.*

4. **A block numbered BLK-1 is ACKed and dropped** (the "our ACK was lost" case). With BLK = 1
   this also accepts a block 0, so a YMODEM sender's block 0 (the file name) would be ACKed
   and ignored. *verified by reading; not tested (test_term.py's sender never repeats an
   ACKed block).*

5. **A failed or cancelled receive keeps the partial file.** XFAIL / XUSER / XRCAN all end in
   XEND, which closes XFCB (AH=10h); nothing deletes it. *verified by reading.*

6. **Retry limits differ.** Receive: TRIES is shared by timeouts and bad blocks, and the
   transfer fails when it passes 10 (`JA` → 11th failure). Send: 10 sends of a block in all
   (`JB` → 9 re-sends); the EOT likewise. Receive waits 3 s for a block's first byte
   (DX = 300), send waits 10 s for an answer (XANS, DX = 1000) and 60 s for the start.
   *verified (code + source).*

7. **The received file is whole 128-byte blocks**, ^Z padding included, and the progress
   counter adds 128 a block on receive but the real byte count (XCNT) on send. Standard
   XMODEM behaviour; test_term.py compares against the padded data. *verified (code +
   test).*

8. **/64 is accepted but not documented.** OPT tests "80", "64", "52"; USEMSG and the README
   list only /80 (64 is the default). *verified (code + source).*

9. **Double close of LFCB on disk full while stopping the log.** LOGOFF calls LOGWR, whose
   disk-full path closes LFCB and logs off; LOGOFF then closes LFCB again. A second close of
   an FCB whose file is already closed is expected to be harmless (DOS 1.25 writes the
   directory entry from the FCB again), but that was not checked. *code path verified by
   reading; its effect provisional, not tested.*

10. **Three MASM 1.10 forward-reference NOPs.** `JMP LOGSW` (07BA: EB 64 90) and `JMP SHOW1`
    (0BB4: EB 22 90), as in CPM.COM; and `MOV [XBUF],SOH` (0A74: C6 06 FB 3C 01 90): XBUF is
    an EQU defined after the code (on Z80IMG), so pass 1 sized the instruction before it
    knew XBUF was a BYTE location, and pass 2 padded the saved byte with NOP. *verified
    (TERM.LST bytes); the pass-1 explanation is the usual MASM behaviour, provisional.*

11. **Header and dependencies.** z86.py termz80() builds the header with cpmz80()'s seven
    names, so TERM.COM is tied to the same Z86.SYS build as CPM.COM. TERMZ80.ASM uses JPHL,
    PEEKEY, GETKEY, CONOUT and ENDBIOS, not NEXT or DCSP; it also uses REGS-page names
    (R_AH, R_SI, R_CL, R_DX ...) and is assembled after BIOS.ASM, so it may use any BIOS
    symbol - the header checks only seven. The same gap as CPM.COM's (volume 3, finding 17).
    TERMZ80 ends at F12Ch + 0D8Ch = FEB8h; z86.py asserts TERMEND <= FF00h - 64 = FEC0h:
    8 bytes to spare. *verified (z86.py + TERMZ80.ASM + bytes).*

12. **Documentation conflict on hardware.** project/MSDOS/poc/README.md line 731, in the
    PuTTY paragraph, says "Tried on a real FDD3000."; the same section's last line (801)
    says "Not known: the real terminal's speed over the link, and anything on real
    hardware", and OVERVIEW section 4 says "Not tried on real FDD3000 hardware or a real
    terminal". notes/hardware_run.md has no TERM run. Recorded here as: not run in the
    merged build; any earlier hardware run by João is not recorded. *documentation issue.*

13. **The menu stays inside 62 columns.** "Q quit L log+" (13) + " E echo+" (8) + " C lf+"
    (6) + " R rcv S snd B brk ^A ^A" (24) + " lost " (6) + up to 5 digits = 62, so the last
    column of the bottom line, which would scroll the Timex terminal, is never written, as
    the source's note under BOTL says. test_term.py checks columns 62-63 blank. *verified
    (code + source + test).*

14. **PUTNB's DIV overflows above 655 359 bytes** (DX:AX / 10 with a quotient over FFFFh →
    INT 0, DOS's "Divide overflow"). The source says "up to 655359". Unreachable: a disk
    holds 176 KB of files (OVERVIEW 2.5). *verified by reading.*

15. **Small asymmetries, noted only.** The EOT send does not look at SEND's CTS result (a
    block send does); the random block read's AL is not looked at (CX alone decides); PURGE
    swallows a key pressed during it; the menu folds every key from 'a' up by 20h (only
    letters matter). *verified by reading.*

16. **Settings need a port.** `TERM 9600` is refused (GETW reads "9600" as a port name). The
    usage line nests the baud inside the port's brackets, so this is as documented; a port
    alone leaves the channel as it is set now, and the settings start from INT 14h AH=F0h
    (what the BIOS last set). On VERMSG the channel keeps whatever SETX gave it. *verified
    (code + source).*

## Design notes

- The split mirrors CPM.COM: the 8086 front end parses and loads; trap 1Ch with BP <> 0
  copies the image over COLD; with BP = 0 it jumps to ENDBIOS, which here is a function
  dispatcher (T_TERM, AH 0-9) that returns from the trap instead of taking the machine over.
- The image's bytes in TERM.COM become the buffers once copied (SCRBUF 0D7Bh, RINGBUF 14FBh,
  LOGBUF 1CFBh, XBUF 3CFBh-3D7Fh), running past the file's end at 1B16h.
- XMODEM is split by speed: the protocol decisions in 8086 code, the bytes in Z80 code. RECV
  sends the answer to the last block and then takes the whole next block in one call, so
  the gap between ACK and the next SOH is never spent in the slow interpreter.
- Log writes and XMODEM file I/O use DOS random block I/O with records of 1 byte (RECSZ1), so
  the log file is exactly the bytes received (DOS advances the random record by CX: MSDOS.LST
  BLKWRT / FINBLK).
- The Timex terminal codes on the bottom line (ESC Y, ESC L inverse, ESC M normal, ESC K)
  go straight to the terminal through DOS; TERMZ80's shadow does not see them, so row 23 is
  redrawn (DRAW CL = 23) after every menu command.

## Cross-volume

- Volume 10 (termz80.asm): the function contract narrated here is from TERMZ80.ASM's header
  and FTAB; finding 1 depends on SMENU / HOLD / RESUME there.
- Volume 6 / 3: same header names and the same unchecked-REGS gap (finding 11).
- Volume 8 (mode.asm): PORTS, BAUDS, ABAUDS, GETW, SAME6, COMMA, BLANKS and the settings parse
  are MODE.ASM's, nearly line for line.
- README line 731 vs 801 / OVERVIEW 4 (finding 12).

## Hardware evidence (2026-11-08)
poc README line ~731 records a TERM <-> PuTTY interactive session "Tried on a real
FDD3000" (João's build, undated); line ~699 (serial section) says "nothing has been
tried on the hardware"; line ~801's "Not known" is about the terminal's speed. Read
as: one interactive session on hardware, probably; everything else emulator-only.
To confirm with João. The merged build has not been run on hardware.

## Verified and fixed 2026-11-08

Independent verification: `verify_term.md` (classes, experiments, diffs). Fixed in TERM.ASM
(and TERMZ80.ASM for N1); TERM.COM is now 6720 bytes, TERMZ80 ends at FEA4h. Each fix has a
test in test_term.py that fails on the old build and passes on the new one.

| # | Class | Outcome |
|---|---|---|
| 1 QUIT leaves the host stopped | BUG | FIXED: QUIT1 does `XOR CX,CX / CALL SEND` (TERMZ80's ENSURE: XON, RTS on) after LOGOFF. Worse than reported: a new TERM did not free an XOFFed host either. Test: section 9 |
| 2 One CAN cancels | DESIGN | receive side FIXED with N3 (two CANs needed); send side FIXED 2026-11-09 (below) |
| 3 Wait for 'C' restarts on noise | NOTE | as Christensen's one-minute rule; nothing to do |
| 4 BLK-1 ACKed and dropped | NOTE | standard duplicate rule; nothing to do |
| 5 Partial file kept | DESIGN | FIXED 2026-11-09 (below) |
| 6 Retry limits / timeouts | DESIGN | 10 s for a block FIXED 2026-11-09 (below); retry counts left as they are |
| 7 Whole blocks | NOTE | nothing to do |
| 8 /64 not documented | DOC | FIXED: header comment, USEMSG (`[/80|/64]`, "/64 64 columns"), README, OVERVIEW |
| 9 LFCB closed twice | NOTE | harmless (MSDOS.ASM CLOSE rewrites the same entry) |
| 10 MASM NOPs | NOTE | nothing to do (now at 07CE, 0AA1, 0BEC) |
| 11 Header / REGS unchecked | DESIGN | LEFT FOR THE AUTHOR; correction: TERMZ80 does not use CONOUT |
| 12 README hardware conflict | DOC | LEFT FOR THE AUTHOR: README 731 vs 699 / 801 is João's to settle |
| 13-16 | NOTE | confirmed; nothing to do |
| N1 Host output lost while "done - a key" waits | BUG | FIXED: new TERMZ80 function 10 HOLD, called at XDONE and XEND. Complete with /R; with /X the XOFF may reach a program still in raw mode. Test: section 7d (/R) |
| N2 Stale byte puts answers a block late | BUG | FIXED: XS51 calls PURGE on any non-ACK answer; PURGE reads one byte at a time into ANSB, not XBUF. Test: section 7c (a second 'C' crossing block 1, block 4 NAKed) |
| N3 Line hit on SOH ends the receive | BUG | FIXED: EOT only with CX = 1, CAN only doubled, otherwise XRBAD. Test: section 7c (SOH into EOT, into CAN; two CANs still cancel) |
| N4 Arrow key at the menu | NOTE | LEFT FOR THE AUTHOR |
| N5 TERMZ80 "at a quarter" | DOC | FIXED in TERMZ80.ASM (comment) |

## Fixed 2026-11-09 (after v1.0-rc1)

TERM.ASM only; TERM.COM is now 6799 bytes (the 8086 part ends at 0E06h, Z80IMG at 0E07h;
the MASM NOPs of finding 10 are now at 07CF, 0ABE, 0C2D). TERMZ80 is unchanged. Each fix
has a test in test_term.py (section 7e, and 7b for the key) that fails on the v1.0-rc1
TERM.COM and passes on the new one.

| # | Fix |
|---|---|
| 5 Partial file kept | New byte XRCV: 1 in XRECV, 0 in XSEND. XEND (reached by XUSER, XFAIL and XRCAN) closes the file and, when XRCV = 1, deletes it (AH=13h). A send's file is never touched. Tests: 7b (a key), 7e (the sender's two CANs) |
| 2 One CAN cancels a send | New CAN2: after a CAN, wait up to 1 s for one more byte; only a second CAN cancels. In XS_WAITC a lone CAN is passed over; as an answer to a block it is taken as a NAK (PURGE, send again). Tests: 7e (block 3 answered with one CAN: the file arrives; with two: "Cancelled by the other side", OUT.BIN unchanged) |
| 6 3 s for a block | XR_WAIT waits 10 s for a block's first byte once a block has come (GOT = 1); before that 3 s, so the 'C' tries and the fallback to checksums keep their pace. A sender with no data for 10 s x 11 tries now takes 110 s to fail instead of 33 s. Test: 7e (block 3 sent 7 s late: no NAK, the file whole) |
