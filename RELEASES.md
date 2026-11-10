# Releases

Each release is a git tag; the GitHub release of that tag carries the disk
image (`MSDOS-FDD3000.DSK`, the file to download for a quick start), its
SHA-256, and a zip of `binaries/`. The README's "Quick start" says how to
boot it.

| Release | Tag | Disk image SHA-256 | Real hardware |
|---|---|---|---|
| v1.0-rc1 | `v1.0-rc1` | `a0eb02f1605446beaaaa15a163416136c3d3c3d5295ccd2f0aa031a43313b6b5` | not yet: emulators only |

## Unreleased (after v1.0-rc1)

**Fixes**
- TERM XMODEM: a receive that fails or is cancelled deletes its partial
  file (it was kept, and looked whole).
- TERM XMODEM: sending, one CAN alone no longer cancels; it takes two
  (as for receiving). A lone CAN answering a block is taken as a NAK.
- TERM XMODEM: receiving, TERM waits 10 s for each block once the
  transfer has started (it was 3 s; the 'C' / NAK start-up keeps 3 s).

## v1.0-rc1 (2026-11-08): release candidate

The first release. A release candidate until it has booted on a real
FDD3000; then it becomes v1.0. Everything below passed the emulator test suites (lockstep 8086 test,
fuzzers, the whole-machine tests, EDIT and TERM tests).

**New programs (by João Encarnado)**
- `MODE`: set up and show the two serial ports (PRN / AUX), any WD2123 rate
  from 50 to 19 200 baud, parity, data and stop bits.
- `TERM`: a serial terminal (VT100 or VT52 for the host; 64 or 80 columns),
  with a log to a file, XMODEM send and receive, break, XON/XOFF or RTS/CTS
  flow control.
- INT 14h calls F0h / F1h (read / set a port's settings); the WD2123's
  status bit 7 read as CTS (it has no DSR pin).

**More robust floppy handling**
- An empty drive (or no drive) no longer hangs DOS: every controller wait
  times out after about 3 s and DOS reports "Not ready" (about 10 s in all,
  as DOS 1.25 tries the FAT three times).
- A sector that keeps failing is retried from a fresh restore half-way
  through its retries.

**Fixes**
- REP MOVSW with source and destination one byte apart now copies word by
  word, as an 8086 does.
- The console status no longer reports a phantom key if the link reads
  00h-03h.
- EDIT: an arrow key at a ^K / ^Q prompt or at "Find:" no longer inserts a
  letter; ^Y no longer answers "yes" to "Abandon changes?"; a failed close
  or rename during a save no longer says "Saved".
- FORMAT /S refuses a disk whose system area has a bad track, instead of
  writing an unbootable disk and saying "System transferred".
- CPM.COM no longer runs a program it could not read completely.
- TERM: quitting lets the host go again (XON, or RTS on); before, the host
  stayed stopped, even through a new TERM.
- TERM: no bytes lost at 19 200 baud while lines scroll inside a region
  (the rows drawn again now take received bytes in time); the terminal's
  echo waits and the break also take them.
- TERM XMODEM: a key cancels a transfer; a line hit on a block's first
  byte is a bad block (it no longer ends the receive as "done" with a
  short file, or as "cancelled"), and a cancel needs two CANs; a stray
  answer while sending no longer puts every later answer a block behind;
  what the host sends while "done - a key" is shown is kept.
- TERM: `/64` is in the usage message.

**Also**
- `DISASM/`: commented disassemblies of every project binary (ten volumes),
  each reassembling byte-identical to its binary.
- `README.md`: how to install the build system (Microsoft's MASM etc.), and
  `publish.py` to publish a build; a fresh clone rebuilds every binary
  byte-identical.

**Please test on real hardware:** a boot; `DIR B:` with drive B empty (should
say "Not ready" after about 10 s); `FORMAT B:` and `FORMAT B:/S` (never tried
on the machine in any release); `MODE` and `TERM` with a real serial device;
and look at the drive LED during the boot (its polarity is still an open
question: `DISASM/notes/boot_findings.md`, item 7).

**Known limits:** FORMAT's write-track loop is not timed (a disk pulled with
the motor running still hangs it); EDIT keeps lines as LF and drops bare
CRs. TERM, left for its author (`DISASM/notes/term_findings.md` and
`termz80_findings.md`, "Verified and fixed"): key reads are not polled (a
terminal slower than about 58 µs a link step could cost a byte at 19 200
baud; to be measured), one CAN still cancels a send, a failed receive keeps
the partial file, receive waits 3 s for a block (the usual is 10 s), SGR
takes each parameter alone, 8-bit characters show as `?`, and the README's
hardware notes for TERM disagree (João to settle).

## Before the first release: the 2026-11-07 internal build

Not a release (nothing was published before v1.0-rc1); recorded because it is
the build that ran on real hardware. Git `868a965`: MS-DOS 1.25 on the Timex
FDD3000 - the 8086 interpreter and Z80 BIOS (`Z86.SYS`), the boot sector, the
I/O system, Microsoft's MS-DOS 1.25 kernel and COMMAND 1.17, and FORMAT, CPM
(CP/M 2.2 programs natively on the Z80) and EDIT, with the first version of
`DISASM/`.

**Tried on a real FDD3000** (2026-11-07, TC2048 and TC2068 terminals, that build's disk
image, SHA-256 `2d063b9364277d6313829dcb4721c449814d569221c2b57ff261c8d86a213078`):
it booted, and the DOS console tools, EDIT, CPM with a CP/M program, and the
printer and AUX serial ports worked. FORMAT was not tried. v1.0-rc1 is that
build plus everything listed above.
