# MS-DOS 1.25 on the Timex FDD3000: package

MS-DOS 1.25, rebuilt from Microsoft's MIT-licensed source, booting and
running on the **Timex FDD3000** floppy disk unit. The FDD3000 has a Z80, not
an 8086, so the package's core is an **8086 interpreter written in Z80
assembly**, with a Z80 BIOS for the FDD3000's console link and WD177x floppy
controller. The terminal stays a Timex TT3000 / TC3256 / TC2068 (Terminal
3000, VT52 codes) on the FDD3000's link. On top of that are five DOS
programs written for it: **FORMAT** for the FDD3000 disk format, **CPM**,
which runs CP/M 2.2 programs natively on the Z80 with their files on the
DOS disk, **EDIT**, a full-screen text editor, **MODE**, which sets the
serial ports' speed and format, and **TERM**, a serial terminal (VT100,
log, XMODEM). The FDD3000's two serial ports (WD2123) serve as DOS's PRN
and AUX devices, through INT 14h and INT 17h, and as CP/M's LIST, PUNCH
and READER. Their DE-9 connectors are **not** wired like a PC's: see the
pinout in `project/MSDOS/poc/README.md`, "Serial ports", before
connecting anything.

Everything was built and tested on emulators (a Python 8086 model, and an
emulated FDD3000 with its Z80, WD177x and boot ROM). The disk also boots on
FUSE. **It has not been tried on real FDD3000 hardware.**

## Start here

| Document | For |
|---|---|
| `OVERVIEW.md` | What was built, how each part works, and how the work was done and checked, step by step. Read this first. |
| `DISASSEMBLY_GUIDE.md` | Each binary: CPU, load address, entry points, code and data regions, the matching listing and symbol file, and the traps to watch for (non-standard opcodes, self-modifying code, split jump tables, overlays). |
| `DISASM/` | Commented disassemblies of every project binary (ten volumes), each reassembling byte-identical to its binary (`DISASM/tools/roundtrip.sh`); findings, conventions and the real-hardware run in `DISASM/notes`, `DISASM/dict`. Start with `DISASM/PLAN.md`. |
| `project/MSDOS/poc/README.md` | The project's own working notes: full detail, measurements, design decisions. |
| `project/MSDOS/FEASIBILITY.md` | The feasibility study written before the work started. |
| `MANIFEST.sha256` | SHA-256 and size of every file in the package. |

## What is in the package

```
binaries/
  disk/MSDOS-FDD3000.DSK    bootable system disk (Extended CPC DSK format,
                            40 cylinders x 1 side x 18 sectors of 256 bytes)
  disk/files/               every file on that disk, extracted (hidden ones too)
  z80/BOOT.BIN              boot sector (Z80, runs at 3F00h)
  z80/Z86.SYS               8086 interpreter + Z80 BIOS (Z80, loaded at D000h)
  z80/CPMZ80.BIN            CPM.COM's Z80 part (Z80, runs at F12Ch)
  z80/TERMZ80.BIN           TERM.COM's Z80 part (Z80, runs at F12Ch)
  x86/IO.SYS                FDD3000 I/O system for DOS (8086, at 0040:0000)
  x86/MSDOS.SYS             MS-DOS 1.25 kernel (8086, at 0060:0000)
  x86/COMMAND.COM           COMMAND 1.17 (8086)
  x86/FORMAT.COM, CPM.COM, EDIT.COM, MODE.COM, TERM.COM   our DOS programs (8086 .COM)
symbols/
  z80/*.lst, *.sym          address + bytes + source listings, symbol tables
                            with a code / data / equ tag per symbol
  x86/*.LST, *.sym          MASM 1.10 listings and symbol tables
DISASM/                     the commented disassemblies (asm/), their tools,
                            notes and dictionary (see DISASM/PLAN.md)
project/                    the sources and the Python tools, runnable
                            (see "Running it" below)
LICENSE-MICROSOFT-MIT.txt   Microsoft's licence for MS-DOS 1.25 / 2.0
```

## Provenance and licences

| Item | Origin |
|---|---|
| `MSDOS.SYS`, `COMMAND.COM` | Built by us from `github.com/microsoft/MS-DOS` (v1.25 source, MIT licence), with MASM 1.10, LINK 2.00 and EXE2BIN from the same repository's v2.0 (byte-identical to the ones used). One build-time patch to COMMAND.ASM (`ZERO EQU $` to `ZERO = $`, a MASM 1.10 limitation). |
| `EDLIN.COM`, `DEBUG.COM`, `CHKDSK.COM` on the disk | Microsoft's own binaries from that repository's `v1.25/bin`, unchanged. |
| Everything else (`Z86.SYS`, `BOOT.BIN`, `IO.SYS`, `FORMAT.COM`, `CPM.COM`, `CPMZ80.BIN`, `EDIT.COM`, `MODE.COM`, `TERM.COM`, `TERMZ80.BIN`, all `.ASM` except Microsoft's, the Python tools) | Written in this project. The Z80 console and floppy routines in `BIOS.ASM` follow the FDD3000's CP/M CBIOS A1.1 (link protocol, WD177x transfer loop). `MODE.COM`, `TERM.COM` and `TERMZ80.BIN` (`MODE.ASM`, `TERM.ASM`, `TERMZ80.ASM`, `test_term.py`), the INT 14h F0h / F1h calls and the WD2123 CTS correction are by João Encarnado. |

**Left out on purpose:** third-party software the project used for testing
but that is not ours to pass on: Microsoft BASIC-80 (MBASIC 5.2) and the
`TTT.BAS` game it was tested with, the CP/M 2.2 / TMX reference disk and its
tools (ASM, LOAD, M80, L80, PIP), and the FDD3000 boot ROM image. The tests
that need them skip or fail without them (see `OVERVIEW.md`, "Running it").
The documents the serial work was checked against are not included
either: the FDD3000 schematic (KiCad `fdd3-ula64kb.sch`, rev 1.1, dated
2023-08-03) and Western Digital's WD2123 DEUCE datasheet.

## Running it

Python 3.9 or later, nothing else. From `project/MSDOS/poc`:

```
python3 fdd86.py build/MSDOS.DSK          # boot the FDD3000 model, type at DOS (Ctrl-] quits)
python3 fdd86.py build/MSDOS.DSK --keys '\r\rDIR\r'     # scripted
python3 test_z86.py                       # interpreter vs Python 8086 model, every instruction
python3 fuzz_z86.py 30000 --seed 1        # random instructions on both
python3 test_dos.py                       # DOS session on the Python model
python3 test_edit.py                      # EDIT, screen and text checked every step (1.5 min)
python3 test_term.py                      # TERM against a VT100 model, load, log, XMODEM (10 min)
```

Without the boot ROM file the model does the ROM's one job (load sector 0 to
3F00h) in Python.

More tests: `test_fdd86.py` (the whole machine: DOS session, two drives, boot
cases, FORMAT, serial; groups 6 and 7 need the CP/M and MBASIC disks, which
are not in the package), `test_fdtimeout.py` (an empty drive answers "Not
ready" instead of hanging), `test_peekey.py`, `test_cpm_smoke.py` (CPM.COM
with a tiny CP/M program, no CP/M disk needed), and `fuzz_z86.py --overlap`
/ `--scan` (targeted REP MOVSW / REPNE SCASB cases).

## Building

### What builds what

| Output | Built by | Needs |
|---|---|---|
| `Z86.SYS`, `BOOT.BIN`, `CPMZ80.BIN`, `TERMZ80.BIN` | `z86.py` (the project's own Z80 assembler, in Python) | Python only |
| `IO.SYS`, `FORMAT.COM`, `CPM.COM`, `EDIT.COM`, `MODE.COM`, `TERM.COM`, `MSDOS.SYS`, `COMMAND.COM` | `build.py`: Microsoft's MASM 1.10, LINK 2.00 and EXE2BIN, run on the package's Python 8086 model (no DOS, DOSBox or PC needed) | the Microsoft repository (below) |
| `MSDOS.DSK` (the bootable disk) | `build.py`, through `mkfat.py` | the above in `build/` |

`CPM.COM` and `TERM.COM` carry their Z80 parts (`CPMZ80`, `TERMZ80`), which
are assembled against Z86.SYS's addresses and checked by BIOS trap 1Ch: after
any change to `I86.ASM` or `BIOS.ASM`, rebuild them too.

### Installing the build system

1. **Python 3.9 or later.** Nothing else for the Z80 parts and the tests.
2. **Microsoft's MS-DOS repository** (MIT licence), for MASM / LINK / EXE2BIN
   (from its `v2.0/bin`) and the MS-DOS 1.25 sources (`v1.25`). Only those
   two directories are needed:

   ```
   git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/MS-DOS.git ~/src/MS-DOS
   git -C ~/src/MS-DOS sparse-checkout set v1.25 v2.0
   ```

   and link them where `build.py` looks for them (`project/MSDOS/mit/v1.25`,
   `project/MSDOS/src/v20object`; `.gitignore` keeps both out of git; on
   Windows copy the directories instead):

   ```
   cd project/MSDOS
   ln -s ~/src/MS-DOS/v1.25 mit/v1.25
   mkdir -p src && ln -s ~/src/MS-DOS/v2.0/bin src/v20object
   ```

3. **For the disassemblies (`DISASM/`) only:** Bas Wijnen's `z80asm` 1.8 and
   NASM (2.x or 3.x):

   ```
   brew install z80asm nasm             # macOS (Homebrew)
   sudo apt install z80asm nasm         # Debian / Ubuntu
   ```

   (Wijnen's `z80asm`, not z88dk's tool of the same name.)

### Building and publishing

From `project/MSDOS/poc`:

```
python3 build.py                  # everything (about 6 minutes: MSDOS.ASM alone is 87 M instructions)
python3 build.py CPM TERM         # only these, then the disk
python3 build.py DISK             # only the disk (it takes Z86.SYS from z86.py)
python3 publish.py                # copy the build into binaries/, symbols/, DISASM/bin;
                                  # regenerate the listings, symbol tables, MANIFEST.sha256
```

`build.py` leaves everything in `build/`; `publish.py` updates only files whose
bytes changed. Built from the sources as they are, the outputs are
byte-identical to those in `binaries/`.

### The disassemblies

```
DISASM/tools/roundtrip.sh         # every volume must reassemble byte-identical to its binary
python3 DISASM/tools/lint.py      # conventions: 0 errors expected
```

After a change that alters a binary, `publish.py` puts the new binary in
`DISASM/bin` and the gate fails for its volume until the `.asm` is brought in
line (`DISASM/PLAN.md`, `DISASM/dict/CONVENTIONS.md`). For a new binary,
`DISASM/tools/z80dis.py` (Z80) and `DISASM/tools/x86dis.py` (8086) make a
byte-identical first skeleton from the binary and its listing.
