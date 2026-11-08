# Releases

Each release is a git tag; the GitHub release of that tag carries the disk
image (`MSDOS-FDD3000.DSK`, the file to download for a quick start), its
SHA-256, and a zip of `binaries/`. The README's "Quick start" says how to
boot it.

| Release | Tag | Disk image SHA-256 | Real hardware |
|---|---|---|---|
| v1.0-rc1 | `v1.0-rc1` | `2d0c2e75bf923015a1dc6b1d670b90d7c4ae786e78e3e6446671dbf6e826fc5b` | not yet: emulators only |

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
CRs; open findings in TERM for its author are listed in
`DISASM/notes/term_findings.md` and `termz80_findings.md`.

## Before the first release: the 2026-11-07 internal build

Not a release (nothing was published before v1.0-rc1); recorded because it is
the build that ran on real hardware. Git `f9e9ae1`: MS-DOS 1.25 on the Timex
FDD3000 - the 8086 interpreter and Z80 BIOS (`Z86.SYS`), the boot sector, the
I/O system, Microsoft's MS-DOS 1.25 kernel and COMMAND 1.17, and FORMAT, CPM
(CP/M 2.2 programs natively on the Z80) and EDIT, with the first version of
`DISASM/`.

**Tried on a real FDD3000** (2026-11-07, TT3000 terminal, that build's disk
image, SHA-256 `2d063b9364277d6313829dcb4721c449814d569221c2b57ff261c8d86a213078`):
it booted, and the DOS console tools, EDIT, CPM with a CP/M program, and the
printer and AUX serial ports worked. FORMAT was not tried. v1.0-rc1 is that
build plus everything listed above.
