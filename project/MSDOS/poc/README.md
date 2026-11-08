# MS-DOS 1.25 on the FDD3000: proof of concept, steps 1 to 4

MS-DOS 1.25 boots and runs on the FDD3000's Z80, through an 8086 interpreter
written in Z80 assembly (`I86.ASM`), on an emulated Z80. The TT3000 / TC3256 /
TC2068 stays the terminal.

**Status:**
- **Step 1 (Python model):** DOS boots to `A:` and runs DIR, COPY, REN, DEL,
  TYPE, CHKDSK, EDLIN and DEBUG, from a FDD3000 disk (40 tracks × 18 ×
  256-byte sectors, 180 KB), with 52 KB of 8086 memory. All of it was built from
  source by Microsoft's own 1983 tools running on the same interpreter.
- **Step 2 (Z80 interpreter):** the same session runs on `I86.ASM`, 6.9 KB of
  Z80 code at D000h. It matches the Python model register for register, flag
  for flag and byte for byte of memory after every one of the session's
  146 779 instructions, and on 84 000+ random single instructions. On a 4 MHz
  Z80 the session's commands take 0.4 to 1.7 s each.
- **Step 3 (Z80 BIOS):** the console and disk calls are Z80 code too
  (`BIOS.ASM`, 1.4 KB), built from CBIOS A1.1's routines: the nibble
  protocol on port 2Fh and the WD177x. DOS runs on cpm80ds's FDD3000 model
  (Z80, WD177x, drive latch) with nothing trapped in Python, against a
  model of the terminal's end of the link. The session's screens and the
  disk afterwards are byte-identical to step 1's. Two drives,
  write-protect and a missing drive also work.
- **Step 4 (boot):** the disk boots itself. The FDD3000 boot ROM loads
  the boot sector (`BOOT.ASM`, 254 bytes), which loads the interpreter and
  BIOS (the hidden file `Z86.SYS`) to D000h; the BIOS's `COLD` loads the
  hidden IO.SYS and MSDOS.SYS and starts the 8086. Python only models the
  hardware now.
- **Disk format:** 18 sectors per track (2 more than CP/M and TOS put in
  the same space) and the system in hidden files instead of reserved
  tracks: a data disk holds 180 KB, a system disk has 154 KB free.
- **FORMAT:** `FORMAT [d:] [/S]` formats a disk in this format (the BIOS
  writes each track with the WD177x's write-track command), reads it back,
  marks bad clusters, and with `/S` makes it bootable. It works with one
  drive too.
- **CP/M programs:** `CPM program [arguments]` runs a CP/M 2.2 program
  natively on the Z80, with its files on the DOS disk. ASM, LOAD, M80,
  L80, PIP and MBASIC 5.2 write byte-identical files to what they write
  under CP/M itself. See [CP/M programs](#cpm-programs-cpmcom).
- **EDIT:** `EDIT name.ext [/80]` is a full-screen text editor in 8086
  code, with the keys and status line of TMX CP/M's EDIT. See
  [EDIT](#edit-editasm).
- **Serial ports:** the FDD3000's WD2123 (two 8251A-compatible channels)
  is PRN (channel A) and AUX (channel B), as CP/M's LIST and
  PUNCH/READER are on CBIOS A1.1; INT 14h and INT 17h work, and so do
  LIST, PUNCH and READER for CP/M programs. `MODE` (MODE.COM) changes a
  channel's speed and format. See [Serial](#serial-ports-wd2123).
- **TERM:** `TERM` (TERM.COM) is a serial terminal, like PuTTY's serial
  mode: a VT100 (or VT52) for the host on the other end, a log to a file,
  XMODEM both ways. See [TERM](#term-termasm-termz80asm).
- **Real hardware:** not tried by me; the disk boots and runs on FUSE.

```
MS-DOS version 1.25
Copyright 1981,82 Microsoft, Inc.

Command v. 1.17H
...
A:CHKDSK

   180224 bytes total disk space
    17408 bytes in 3 hidden files
    16384 bytes in 4 user files
   146432 bytes available on disk

    52128 bytes total memory
    42816 bytes free
```

## Files

| File | What it is |
|---|---|
| `cpu86.py` | 8086 interpreter. Opcode `0F nn` (POP CS, never used by real 8086 code) is the BIOS trap. |
| `dosshim.py` | INT 21h in Python, enough to run MASM, LINK and EXE2BIN from MS-DOS 2.0. |
| `IOFDD.ASM` | IO.SYS for the FDD3000 (MASM source). Each of the 14 BIOS entries is `TRAP n / RETF`. It also has a minimal IBM PC ROM BIOS: INT 10h teletype and cursor (as VT52 `ESC Y`), plus INT 11h, 12h, 14h, 16h, 17h and 1Ah, so PC-DOS programs such as IBM's DEBUG and CHKDSK work. |
| `fddos.py` | The machine: interpreter, traps, FDD3000 DSK disks (via `../../cpm80ds/fdd.py`) and the console. |
| `mkfat.py` | Makes a disk: FAT12 on 18-sector FDD3000 tracks, the boot sector, and (unless `--nosys`) the system files. |
| `build.py` | Builds everything from source. |
| `test_dos.py` | Boots and runs 10 command steps, checking the output. |
| `I86.ASM` | The 8086 interpreter in Z80 assembly (step 2). |
| `z86.py` | Assembles `I86.ASM` (tmxcobol's `z80asm`) and runs it on tmxcobol's Z80 emulator, counting T-states. Its `Z86` class looks like `cpu86.CPU`, so `fddos.Machine` drives it unchanged; the BIOS traps are hooked in Python. |
| `test_z86.py` | Runs `test_dos.py`'s session on `cpu86.py` and `I86.ASM` side by side and compares them after every instruction. `--fast`: Z80 only, with a profile. |
| `fuzz_z86.py` | Random single instructions (all opcodes, prefixes, REP) on both, compared. |
| `BIOS.ASM` | The BIOS traps in Z80 code (step 3), assembled after `I86.ASM`. |
| `BOOT.ASM` | The boot sector (step 4): loads the interpreter and BIOS and jumps to `COLD`. `z86.bootcode()` assembles it. |
| `fdd86.py` | DOS on cpm80ds's FDD3000 model, all in Z80 code, booted from the boot ROM. `Link` models the terminal's end of the 2Fh link byte by byte; `WD2123` models the two serial channels (mode, sync and command order, status, CTS; what they send and receive; optionally a host sending in real time, overruns, XON / XOFF and RTS). The link can also model a terminal that takes time to draw. |
| `FORMAT.ASM` | FORMAT.COM (MASM source), built like IO.SYS. |
| `CPM.ASM` | CPM.COM (MASM source): loads a CP/M program and runs it on the Z80. |
| `CPMZ80.ASM` | CPM.COM's Z80 part: the BDOS and BIOS a CP/M program sees. Assembled after `BIOS.ASM` with its symbols; `build.py` puts it in CPM.COM as `CPMZ80.INC`. |
| `EDIT.ASM` | EDIT.COM (MASM source): the full-screen text editor. |
| `MODE.ASM` | MODE.COM (MASM source): sets and shows the serial channels' speed and format. |
| `TERM.ASM` | TERM.COM (MASM source): the terminal's command line, menu, log and XMODEM. |
| `TERMZ80.ASM` | TERM.COM's Z80 part: the session, the VT100 / VT52 screen, the channel. Assembled after `BIOS.ASM` like `CPMZ80.ASM`; `build.py` puts it in TERM.COM as `TERMZ80.INC`. |
| `test_term.py` | TERM.COM on `fdd86.py` against a Python VT100 model, with a host sending in real time: codes, random codes, keys, load and flow control, the log, XMODEM. |
| `test_edit.py` | EDIT.COM on `fdd86.py`, checked after every step against a model of the terminal's screen and a Python model of the editing keys. |
| `BDOSTEST.MAC` | M80 source of a CP/M program that prints the results of BDOS calls (random records, file size, search, rename, BIOS CONOUT), for the test. |
| `test_fdd86.py` | The session on `fdd86.py` against `fddos.py` (screens and disk must match), plus two drives, write protect, a missing drive, booting (random RAM at power-on, unreadable boot tracks), FORMAT, CP/M programs and MBASIC under CPM.COM (against CP/M itself), the serial ports and MODE.COM. |

## Use

```bash
python3 build.py
```

```bash
python3 test_dos.py
```

```bash
python3 fddos.py build/MSDOS.DSK
```

- `build.py` builds `build/` from source in about 6 minutes;
  `python3 build.py FORMAT` rebuilds only FORMAT.COM and the disk (30 s),
  `python3 build.py CPM` only CPM.COM, `python3 build.py EDIT` only
  EDIT.COM, `python3 build.py MODE` only MODE.COM, `python3 build.py TERM` only TERM.COM. Z86.SYS and CPM.COM must come from
  the same build (see below).
- `test_dos.py` runs the regression test in under a second.
- `fddos.py` runs DOS interactively. Ctrl-] quits.

`python3 fddos.py build/MSDOS.DSK --keys '\r\rDIR\r'` runs a scripted session.

The Z80 interpreter:

```bash
python3 test_z86.py
```

```bash
python3 fuzz_z86.py 30000 --seed 1
```

```bash
python3 z86.py build/MSDOS.DSK
```

- `test_z86.py` is the lockstep comparison (about 10 seconds).
- `fuzz_z86.py` runs 30 000 random instructions on both CPUs (about 10 seconds).
- `z86.py` runs DOS on the Z80 interpreter interactively (`--keys` works too).

The whole FDD3000 (steps 3 and 4):

```bash
python3 test_fdd86.py
```

```bash
python3 fdd86.py build/MSDOS.DSK
```

- `test_fdd86.py` takes about 3 minutes.
- `test_edit.py` (EDIT.COM) takes about 1.5 minutes.
- `test_term.py` (TERM.COM) takes about 10 minutes.
- `fdd86.py` resets the FDD3000 model and boots the disk through the boot
  ROM (`../../roms/fdd_boot.rom`), then runs DOS interactively; a second
  disk image is drive B:, `--keys` and `--save` work as in `fddos.py`. A
  disk made before step 4 has no boot code: run `build.py` again.

## How it was built

- **Kernel:** `MSDOS.ASM` + `STDDOS.ASM` (MIT release, `../mit/v1.25/source`), MS-DOS version (not IBM). MASM 1.10 assembled it with 0 errors in 87 M emulated instructions. LINK 2.00 and EXE2BIN then made the 6190-byte `MSDOS.SYS`.
- **COMMAND.COM 1.17:** same route. One change: MASM 1.10 won't redefine a symbol with `=` after `EQU`, so `ZERO EQU $` becomes `ZERO = $`. `build.py` patches this in the build copy only.
- **IOFDD.SYS:** 332 bytes.
- **Memory snag:** MASM 1.10 (MS Pascal runtime) computes its stack with a signed compare and fails above 512 KB, so `dosshim` reports 512 KB.

## Disk format (`mkfat.py`)

40 tracks of 18 sectors of 256 bytes, sector IDs 0-17: 720 sectors, 180 KB.

| Logical sectors | Contents |
|---|---|
| 0 | boot sector (`BOOT.ASM`) |
| 1–2, 3–4 | FAT 1, FAT 2 |
| 5–12 | directory, 64 entries |
| 13–716 | 176 clusters of 1 KB (717–719 unused) |

A system disk starts with three hidden files (attribute 06h, so DIR, COPY
and DEL don't see them, and CHKDSK counts them as hidden), contiguous from
cluster 2. The boot sector and `COLD` find them by their directory entries:

| Entry | File | Size | Loaded at |
|---|---|---|---|
| 0 | `Z86.SYS`: the Z80 interpreter and BIOS | 8 736 bytes | D000h |
| 1 | `IO.SYS` | 332 bytes | 0040:0000 |
| 2 | `MSDOS.SYS` | 6 190 bytes | 0060:0000 |

Free space, against the first layout (16 sectors per track, 80 reserved
sectors for the system):

| | 16 sectors, reserved | 18 sectors, files |
|---|---|---|
| data disk | 140 288 bytes | 180 224 bytes |
| system disk with COMMAND.COM | 135 168 bytes | 157 696 bytes |

- **18 sectors:** CP/M and TOS write 16 sectors (4 KB, so a track is a
  power of two: 1 KB CP/M blocks and 4 KB TOS units fit whole tracks, and
  track and sector come from shifts). A double-density track at 300 rpm
  holds 6 250 bytes; 18 sectors with gaps of 32 bytes at the start and 16
  after each sector take 6 044, leaving 3% for a fast drive. Timex disks
  with 17 and 18 sectors exist (PFile, Gestin: tomato reads them), so the
  FDD3000 handles them. CP/M and tomato see only sectors 0-15 of a track,
  which doesn't matter for these disks. DSK images are saved as extended
  DSK with 18 sectors per track.
- **Interleave 2:1:** logical sector *n* is track *n*/18, sector ID
  0 2 4 … 16 1 3 … 17 by *n* mod 18 (`SKEW` in BIOS.ASM, computed in the
  boot sector). Between two sectors of a multi-sector read the BIOS needs
  about 0.4 ms; one sector passes in about 10 ms, so a track reads in two
  turns. The emulator has no rotation, so this is untested: on real
  hardware a different interleave may read faster.
- **DOS's view:** IO.SYS's drive table says 256-byte sectors, 1 reserved
  sector, 2 FATs, 64 entries, 720 sectors; DOS 1.25 works out 2 sectors per
  FAT and clusters 2-177 from that itself.

## The Z80 interpreter (`I86.ASM`)

| Z80 | Holds |
|---|---|
| BC | host address of the next 8086 code byte (CS base + IP) |
| IX | the dispatcher; every handler ends with `JP (IX)` |
| AF' | the 8086 arithmetic flags: F' = S Z AF OF CF in the Z80's S Z H V C bits, A' = low byte of the last result (PF is its parity, computed only when FLAGS is read) |

- **Memory:** guest linear address *n* is Z80 address *n* (0000h-CFFFh).
  Each segment register keeps its base (seg × 16), so an operand's address
  is one 16-bit add.
- **Registers:** the 8086 registers sit in a page of Z80 memory. ModR/M
  decoding therefore always gives a pointer, into guest memory or into that
  page, and one handler covers register and memory operands.
- **Dispatch:** split low/high jump tables indexed by opcode, 58 T-states
  per instruction including the `JP (IX)`.
- **Segment overrides:** a prefix sets the operand bases and points IX at a
  routine that restores them after the instruction.
- **REP:** `REP MOVS` and `REP STOS` use `LDIR` / `LDDR`. `REPNE SCASB`
  passes over all but its last compare with `CPIR` / `CPDR` (21 T-states a
  byte instead of about 300), then does that compare the normal way, so
  the flags, CX and DI come out as on the 8086; not if DI would wrap round
  the segment. The other repeated string instructions loop in Z80 code.
  `fuzz_z86.py --scan` checks REP SCASB / SCASW with CX up to 2000.
- **BIOS traps:** opcode `0F nn` calls `TRAP`. For now that is a `RET` that
  `z86.py` hooks to run fddos's Python BIOS.
- **One known difference from an 8086:** AF after 16-bit add, subtract,
  increment and decrement comes from bit 11 (the Z80 way), not bit 3. Only
  DAA, DAS, AAA and AAS read AF, and only after 8-bit arithmetic in real
  code. The tests allow exactly this difference and nothing else.

Memory map of the FDD3000 while DOS runs:

| Address | Contents |
|---|---|
| 0000h-CFFFh | the 8086's 52 KB |
| D000h-EB45h | the interpreter: registers, tables, code (the unused ends of four of its pages hold serial code: D03Eh-D0F0h, the register page; D3C0h-D3EFh, the EALO table's page; D4C0h-D4C3h, the EAHI table's page, the settings INT 14h F0h returns; D5A2h-D5FAh, the 8-bit ALU page) |
| EB46h-F12Ah | the BIOS: code and variables |
| F12Bh-F21Fh | the BIOS's `COLD`, needed only at boot |
| F220h-FFFFh | free (3.5 KB), and the Z80 stack from FFFFh down |

While a CP/M program runs, F12Bh-FAF4h (over `COLD`) holds CPM.COM's Z80
part and FAF5h-FEF4h its 1 KB file buffer. The Z80 stack needs about 30
bytes; `z86.py` checks that the buffer ends below FF00h. TERM.COM's Z80
part goes there too, F12Bh-FEB6h (its buffers are in the 8086's memory).

D0FDh, at the end of the register page, holds `JP COLD`: the boot sector
jumps there, so it works with any build of `Z86.SYS`.

## The Z80 BIOS (`BIOS.ASM`)

IO.SYS's 14 entries and its 6 PC ROM BIOS interrupts are each `TRAP n`.
The interpreter calls `TRAP` with A = n; the handler works on the 8086
registers in REGS and sets ZF / CF in AF'.

- **Console:** CBIOS A1.1's send (FAA8h) and receive (FB0Dh) routines,
  unchanged: each byte goes as two nibbles, each echoed by the other side.
  The terminal says 04h when a key is waiting. The link can't look at a key
  without taking it, so STATUS (and INT 16h AH=1) takes it and keeps it for
  the next INP.
- **Disk:** logical sector *n* is track *n*/18 (a short division loop),
  sector ID from the 2:1 interleave table, read or written straight into the 8086's buffer. As in CBIOS A1.1,
  the transfer loop is `IN A,(2Fh) / RLA / JR NC / INI` (DRQ is bit 7 of
  2Fh), and the FDC's INTRQ ends it through RST 38h. 0038h is the 8086's
  INT 0Eh vector, so the BIOS points it at its handler for the call and puts
  it back. Seeks verify; 10 retries, then restore and retry. Errors go to DOS
  as its codes: write protect, not ready (no drive: restore never finds track
  0), seek, sector not found, CRC.
- **Clock:** the FDD3000 has none. The date and time are what DOS was last
  told (1-1-80 0:00 after boot); DIR shows that on new files. INT 1Ah's tick
  count goes up by one per call, so programs that wait on it don't hang.

- **CPM.COM (traps 1Ch, 1Dh):** 1Ch copies CPM.COM's Z80 part to F12Bh
  (`ENDBIOS`, over `COLD`), or with BP = 0 runs it; 1Dh ends an INT 21h that the Z80
  part started. See [CP/M programs](#cpm-programs-cpmcom).
- **Serial (traps 4, 5, 6, 14h, 17h):** see [Serial](#serial-ports-wd2123).
- **FORMAT TRACK (trap 1Bh):** for FORMAT.COM. AL = drive, DL = track,
  DS:BX = a track image of 6008 bytes as the WD177x write-track command
  takes it (F5h = sync, F7h = CRC). It restores and seeks without verify
  (a blank disk has no IDs to verify against), writes the image, and the
  FDC fills the rest of the turn with 4Eh. The write loop is CP/M FORMAT
  2.0's (`cpm80ds/progs/format.asm`).

## FORMAT (`FORMAT.ASM`)

```
A:FORMAT B:/S

Insert new diskette for drive B:
and strike any key when ready

Formatting...Format complete
System transferred

   180224 bytes total disk space
    22528 bytes used by system
   157696 bytes available on disk

Format another (Y/N)?
```

- **Tracks:** 18 sectors of 256 bytes, IDs 0-17, data E5h, with the
  shorter gaps above. Each track is read back with INT 25h. If a track
  from 1 on fails, its clusters (5 or 6) are marked bad (FF7h) in the FAT;
  a bad track 0 (boot sector, FATs, directory) fails the format.
- **Boot sector, FAT and directory:** written with INT 26h. Every disk
  gets the current drive's boot sector, so a disk without the system says
  `Non-System disk` instead of hanging. Media byte FEh, an empty directory
  of zeros (DOS 1.25 treats 00 as the end of the directory).
- **`/S`:** copies the hidden Z86.SYS, IO.SYS and MSDOS.SYS, then
  COMMAND.COM, from the current drive, as files: extended FCBs carry the
  hidden attribute. On the empty disk DOS puts them in the first directory
  entries and the first clusters, in order, as the boot code needs. All
  four are read into memory before the new disk is asked for, so
  `FORMAT A:/S` works with a single drive. FORMAT needs about 36 KB of
  memory for this.
- **Keys:** like DOS's own FORMAT, it throws away typed-ahead keys before
  each prompt.
- **Time:** 9.9 s of Z80 time on the emulator for `FORMAT B:/S`. A real
  drive adds the turns of the disk: one per track to write it, about two
  to read it back, so roughly 30 s in all.

Both BIOSes have the trap (Python `fddos.py` too), and the test checks that
FORMAT B:/S gives the same screens and the same disk on both.

## CP/M programs (`CPM.COM`)

```
A:CPM MBASIC
BASIC-80 Rev. 5.2
[CP/M Version]
Copyright 1977, 78, 79, 80 (C) by Microsoft
Created: 14-Jul-80
15686 Bytes free
Ok
LOAD "TTT"
Ok
SYSTEM

A:CPM ASM TX
CP/M ASSEMBLER - VER 2.0
025E
001H USE FACTOR
END OF ASSEMBLY

A:
```

`CPM program [arguments]` runs `program.CPM` (or `program.COM` if there
is no `.CPM`) as a CP/M 2.2 program. The FDD3000's CPU is a Z80, so the
program runs natively, at full speed; only its file calls go through
DOS. Keep CP/M programs as `.CPM`: DOS would run a CP/M `.COM` typed at
its prompt as 8086 code and crash. The arguments become the command tail
at 0080h and the FCBs at 005Ch and 006Ch, as the CCP makes them.

**How it works.** A CP/M program must run at 0100h, which is where DOS
lives. So:
- CPM.COM (8086) has BIOS trap 1Ch copy its Z80 part (`CPMZ80.ASM`) to
  the Z80's free memory above the BIOS, reads the program over that copy,
  and calls trap 1Ch again to run it.
- The Z80 part exchanges the 8086 memory from 0000h to the end of
  CPM.COM with the top of the memory DOS gave CPM.COM, moves the program
  to 0100h, fills in page zero and jumps to it. COMMAND's resident part,
  above that, is left alone.
- **Console calls** (BDOS 1, 2, 6, 9, 10, 11 and the BIOS's CONST, CONIN
  and CONOUT, which MBASIC calls directly) are the Z80 BIOS's console
  code, with no DOS involved.
- **File calls** use DOS. The FCB (and the record, for a write) is copied
  to a page above the program (P), DOS and CPM.COM's PSP (9.3 KB) are
  exchanged back in, and the 8086 interpreter runs `INT 21h` from a stub in
  P. Trap 1Dh brings control back, and DOS is exchanged out again. DOS
  1.25's FCB calls are CP/M's, with the same numbers and the same first 32
  bytes of FCB. The rest is translation: record size 128 where CP/M has
  S2 and RC, the RC that CP/M programs expect, ^Z after the end of a
  file, and CP/M's return codes. CP/M's BDOS leaves the directory record
  at the DMA after a search or an open, so this does too. DOS writes the
  drive's number into an FCB it opens; CP/M doesn't, so that byte is not
  copied back (MBASIC's NAME compares it with the new name's 0). Byte 13
  (S1) is CP/M's to ignore and programs use it (PIP stores 7Ch there when
  it copies from a device), but to DOS it is the high byte of the block
  number: DOS gets 0 there, and the program's own byte stays.
- **Buffering:** reads and writes, sequential and random, go through a
  1 KB buffer (8 records of one file), so DOS is exchanged in once for up
  to 8 records. Random ones count: MBASIC LOADs and SAVEs with random
  reads and writes. A random write leaves the FCB's record number (R0-R2)
  as the program set it, as CP/M does; MBASIC counts in it. Any other
  file call writes the buffer out first. A write that fails there (disk
  full) is reported on the next write or the close.
- **Warm boot** (JP 0, BDOS 0, ^C on an empty input line) exchanges DOS
  and CPM.COM back and returns from the trap. CPM.COM resets the disks
  and exits to COMMAND, which reloads its transient part.

**Memory:** the program gets 0100h-A0FFh (40.25 KB; BDOS at A106h, BIOS
at A200h), 18 KB less than TMX CP/M gives. MBASIC has 15 686 bytes free
(33 862 under TMX CP/M); linking the same program, L80 reports 30 709
(48 885). The Z80's 64 KB hold, besides the program, the interpreter and
BIOS (8.5 KB), DOS's own memory (9.3 KB, kept while the program runs),
COMMAND's resident part (1.1 KB) and this (3.5 KB), so about 2 KB more
is all there could be.

**What's there:** BDOS 0-40 except the disk-parameter calls. 24
(login vector) says A: and B:, 27 and 31 give a fake allocation vector
and DPB for a 1 KB-block disk, 28-30 and 32 do nothing. The BIOS's disk
entries return errors, so programs that use the disk through the BIOS
(STAT's disk report, SYSGEN, FORMAT) don't work. LIST, PUNCH and READER
(BDOS 3-5 and the BIOS entries) are the serial channels, as on CBIOS A1.1. Users are always 0, and
CP/M's file attributes (the top bits of the name) mean nothing to DOS.

**Z86.SYS and CPM.COM go together.** The Z80 part calls the BIOS's
console code and runs the interpreter at fixed addresses. CPM.COM carries
the addresses it was built against (`CPMSYM`), and trap 1Ch refuses a
CPM.COM from another build of Z86.SYS: `CPM.COM does not match Z86.SYS`.

**MBASIC 5.2** (`BASIC.COM` on `Resources/Disks/galo-basic.dsk`, as
`MBASIC.CPM`; `build.py` puts it and the tic-tac-toe game TTT.BAS on
`build/MSDOS.DSK` when that disk is there). `test_fdd86.py` group 7
LOADs TTT.BAS, SAVEs it as ASCII and tokenized, runs a program that uses
a random file (OPEN "R", FIELD, PUT, GET, LOF), a sequential one
(WRITE #, INPUT #), KILL, NAME and FILES, and plays the game. The same
under CP/M: the saved files and the random file are byte-identical, and
so is the program's output. As under CP/M, MBASIC reads the keyboard
while a program runs, so keys typed ahead of an INPUT are lost.

**Checked against CP/M itself.** `test_fdd86.py` group 6 runs the TMX
CP/M disk's own ASM, LOAD, M80, L80 and PIP under CPM.COM, and the same
commands under CP/M 2.2 with the TMX CBIOS on cpm80ds's emulated
FDD3000. TX.PRN, TX.HEX, TX.COM (ASM, LOAD), CROMLIB.REL (M80) and TX2.ASM
(PIP, with a backspace typed at its prompt) are byte-identical.
BDOSTEST.COM, built under CPM.COM with M80 and L80, prints the same
results on both. The one difference is the directory code: CP/M returns
1 for an entry in the second slot of its directory record, DOS 0, and
programs test only for FFh.

**Speed** (Z80 at 4 MHz; the emulated drive has no rotation):

| Command | Time |
|---|---|
| `CPM ASM TX` (1.4 KB source) | 9.7 s |
| `CPM LOAD TX` | 3.7 s |
| `CPM M80 =CROMLIB` (4 KB source) | 13.4 s |
| `CPM PIP` (copy 1.4 KB, typed at its prompt) | 6.7 s |
| `CPM BDOSTEST` | 5.8 s |
| `CPM MBASIC` to `Ok` | 1.1 s |
| MBASIC `LOAD "TTT"` (2.4 KB) | 2.8 s |
| MBASIC `SAVE "T2",A` (2.4 KB) | 3.7 s |
| MBASIC `SAVE "T3"` (tokenized, 2 KB) | 2.1 s |

Each `CPM` command includes about 2 s for DOS to load CPM.COM and for
COMMAND to reload itself afterwards. Exchanging 9.3 KB in and out takes 0.2 s
per DOS call. Before the buffer, ASM TX took 25 s, 20 s of it
exchanging; now 4 s of its 9.7 s are exchanges and 2.4 s are DOS.

**Not tested:** a disk error while a CP/M program runs.
DOS's Abort, Retry, Ignore comes from COMMAND's resident part, which is
in place. By the design, Abort should end CPM.COM and go back to COMMAND,
leaving about 30 bytes of Z80 stack behind each time; that is untried.

## EDIT (`EDIT.ASM`)

```
EDIT name.ext          edit a file (or make a new one), 64 columns
EDIT name.ext /80      the same on an 80 column terminal (/64 to /80)
```

```
 A:T.TXT          Line 4     Col 9     Saved
Line 1: the quick brown fox
Line 2: the quick brown fox
Tabs:   here    and     here, ^L:? high:? end
Line 4: the quick brown fox
...
```

A full-screen editor for DOS itself, in 8086 code (4.5 KB). It has the
keys and the status line of TMX CP/M's EDIT (`cpm80ds/progs/edit.asm`),
so the two work alike; `^J` lists the keys.

| Keys | |
|---|---|
| `^E` `^X` `^S` `^D` or the arrow keys | up, down, left, right |
| `^A` `^F` | word left, word right |
| `^R` `^C` | page up, page down |
| `^QS` `^QD` | start, end of the line |
| `^QR` `^QC` | start, end of the file |
| DEL (or `^H`), `^G` | delete left, delete right |
| `^T` `^Y` `^QY` | delete a word, the line, to the end of the line |
| RETURN, `^N`, TAB | new line, split the line, tab |
| `^QF`, `^L` | find (capitals and small letters alike), find again |
| `^KS`, `^KX` (or `^KD`), `^KQ` | save, save and exit, quit (asks if there are changes) |
| `^J` | the list of keys |

- **The file:** held whole in memory, in a gap buffer: up to 33 539
  bytes with DOS's 52 KB (a bigger file gets `File too big for memory`).
  Lines end in CR LF in the file and LF inside; CRs are dropped when the
  file is read, and the text ends at a ^Z in its last 128 bytes. Saving
  writes `name.$$$` (with a ^Z at the end), then renames the old file to
  `name.BAK` and the new one to `name.ext`. If the disk fills up, the old
  file stays as it was and the status line says `Disk full: not saved`.
  If DOS asks Abort, Retry, Ignore during a save (INT 24h, write-protect
  for example), EDIT notices and redraws the whole screen afterwards.
- **The terminal:** the VT52 codes TMX EDIT uses, read from the Terminal
  3000's ROM: `ESC Y`, `ESC H ESC J`, `ESC K`, `ESC L`/`ESC M` (inverse)
  for the name on the status line, and `ESC I` on the top row. Nothing
  is written in the last column. Output goes through INT 10h (teletype),
  keys come from INT 16h, so `^C` and `^S` reach EDIT and not DOS. Tabs
  show to the next multiple of 8, other control bytes and bytes above 7Eh
  as `?`; lines longer than the screen scroll sideways (up to column 1024).
- **Drawing on the interpreter:** at about 17 000 8086 instructions a
  second, TMX EDIT's method (draw the whole screen in memory, compare it
  with a copy of the terminal's) would cost more than a second a key.
  Instead each text row carries a mark, the first column to send again,
  set by the command that changed it. Only the rows from the first mark
  to the last are even looked at, and the status line's fields (the `*`,
  line, column, message) are sent only when they change. A line moved
  past the bottom or the top scrolls the terminal (LF on the bottom row,
  `ESC I` on the top one) instead of redrawing it. Drawing stops while a
  key is waiting, so typing ahead is not held up by the screen.

Speed at 4 MHz, from `test_edit.py` (the 60-line file is 1.9 KB):

| Step | Time |
|---|---|
| `EDIT T.TXT` to the full screen | 1.4 s |
| a letter typed, a cursor key | 0.03 to 0.07 s |
| down past the bottom (the terminal scrolls) | 0.13 s |
| RETURN (the rows below are sent again) | 0.9 s |
| page down, page up | 1.05 to 1.07 s |
| ^KS | 0.8 s |
| `EDIT BIG.TXT` (28.6 KB) | 3.3 s |
| ^QC in it | 1.3 s |
| ^KS of it | 3.8 s |

A full screen is about 1 s: each character costs 3 900 T-states through
INT 10h, against 1 900 for the BIOS alone. The big-file steps scan the
whole text (for CRs, for LFs to count lines, to write CR LF) with
`REPNE SCASB`, which the interpreter now runs with `CPIR`: before that,
at about 300 T-states a byte, loading BIG.TXT took 5.5 s, ^QC 3.5 s and
^KS 5.9 s. What is left is mostly the 8086 code between the scans, one
pass per line, and DOS.

**The test** (`test_edit.py`, about 1.5 minutes) checks, after every
step, the terminal model's screen against EDIT's own text read from
memory (rows, tabs, the first column shown, the status line, inverse,
the cursor, nothing in the last column), and the text and cursor
against a Python model of the keys. It runs every key, scrolling a line
at a time (each one must scroll the terminal exactly once), 400 random
keys, find, help, the abandon question, saving (.BAK, a new file, a
full disk, a write-protected disk with Retry), the biggest file, memory
full, the usage messages and /80. Not tried on a real terminal.

## Serial ports (WD2123)

The FDD3000 has a Western Digital WD2123 (DEUCE): two 8251A-compatible
serial channels with their own baud-rate generators. CBIOS A1.1 (TMX CP/M)
uses them as follows, read from its code and from TMX CONFIGUR 1.3, and
this BIOS does the same:

| | Channel A | Channel B |
|---|---|---|
| Data / control and status port | 80h / 81h | 40h / 41h |
| Baud-rate register | 10h | 11h |
| CP/M (CBIOS A1.1) | LIST | PUNCH, READER |
| DOS | PRN (and `^P` echo, INT 17h), INT 14h port 0 | AUX, INT 14h port 1 |
| Connector | J4 (DE-9) | J5 (DE-9) |

**The connectors** (from the FDD3000's schematic, `fdd3-ula64kb.sch`
rev 1.1; SN75188 drivers, SN75189 receivers). Both DE-9s are wired the
same way, and **not** as a PC's:

| Pin | FDD3000 | PC (DE-9, DTE) |
|---|---|---|
| 1 | +5 V | DCD |
| 2 | TxD, out | RxD |
| 3 | RxD, in | TxD |
| 4 | RTS, out | DTR |
| 5 | CTS, in (status bit 7) | GND |
| 6 | - | DSR |
| 7 | GND | RTS |
| 8 | - | CTS |
| 9 | +12 V through 1 kΩ | RI |

The WD2123 has no DSR, DTR or DCD pins. A plain DE-9 cable to a PC
would join the PC's RTS output to the FDD3000's ground and leave no
common ground, and the FDD3000 would put +5 V and +12 V on the PC's DCD
and RI, so use a cable made for it. To a PC: FDD3000 2 to PC 2,
3 to 3, 7 to 5 (ground), 4 to 8 (the PC's CTS), 5 to 7 (the PC's RTS).
FDD3000 pin 9 can instead be joined to pin 5 to hold CTS on; on the PC
side, 4 to 6 if its software wants DSR. The crystal
is 1.8432 MHz, the WD2123's standard one, so the baud codes give the
rates below.

- **Set-up at boot:** as CBIOS A1.1 sets them: 8 data bits, no parity,
  1.5 stop bits, ×16 clock (mode byte 8Eh), baud code 8 (1200 baud).
  The sequence is 00h 00h 00h 40h (40h, internal reset, makes the next
  control write the mode; the 00h before it are CBIOS A1.1's and do no
  harm), the mode, command 07h (transmitter, CS, receiver on), then the
  baud code.
- **Commands** (WD2123 datasheet): bit 0 transmit, 1 CS, 2 receive, 3
  break, 4 error reset, 5 RTS, 6 internal reset, 7 loop-back. CS is an
  8251A's DTR bit, but here it selects the clocks, and it must stay 1:
  with 1 and SELCLK high (it is tied high on the FDD3000) both come from
  the baud-rate generator; with 0 the receiver's clock is SELCLK itself,
  and nothing is received. Every command written here and in CBIOS A1.1
  has it.
- **Baud codes** (the order TMX CONFIGUR lists them, its 4-bit code for
  the WD2123): 0 = 50, 1 = 75, 2 = 110, 3 = 134.5, 4 = 150, 5 = 200,
  6 = 300, 7 = 600, 8 = 1200, 9 = 1800, 10 = 2400, 11 = 3600, 12 = 4800,
  13 = 7200, 14 = 9600, 15 = 19200.
- **Sending** (PRN, AUX, CP/M's LIST and PUNCH): command 27h (RTS on too),
  clear any error flags (command 37h), wait for CTS and TxRDY, send. DOS's
  PRINT and AUXOUT have no way to report an error, so like CP/M they wait
  as long as it takes: a printer that is off holds DOS until it is on.
- **Receiving** (AUX, READER): command 27h, wait for RxRDY (clearing
  parity, overrun and framing errors), read, then command 07h: RTS is on
  only while a byte is awaited, as CBIOS A1.1's READER does.
- **INT 14h** (DX = 0 channel A, 1 channel B): AH = 0 set up from AL in
  the PC's format (110 to 9600 baud, parity, 1 or 2 stop bits, 5 to 8
  data bits); 1 send AL; 2 receive into AL; 3 status; 4 set up from BX and
  CX in the PS/2 format (adds 19200 baud). Sending and receiving give up
  after about 1.5 s and set bit 7 of AH. AH returns the line status (data
  ready, overrun, parity, framing, break, transmitter empty), AL the modem
  status: CTS (status bit 7), and DSR always on (there is no DSR line).
  Two FDD3000 calls reach what the PC
  formats can't (50 to 7200 baud, 1.5 stop bits): AH = F0h returns the
  channel's mode byte in AL and baud code in AH, as the BIOS last set them
  (the chip can't be read back, so `SSET` keeps a copy); AH = F1h sets
  the channel up from AL (mode byte; bits 1-0 are forced to the ×16 clock)
  and CL (baud code 0-15) and returns the status.
- **INT 17h:** AH = 0 prints AL on channel A (giving up after about
  1.5 s), 2 returns the status: 90h ready (CTS on), 10h busy, +1 timed out.
- **Where the code is:** the shared routines (`SPRN`, `SAUXO`, `SAUXI`,
  `SLSTS`, `SPUT`, `SGET`, `SSET`, `SSTAT`) are in the unused end of the
  interpreter's register page, INT 14h's set-up in the unused end of
  its 8-bit ALU page, the F0h / F1h calls (`I14X`) after the EALO table
  and their copy of the settings (`SAVED`) after the EAHI table, so that
  they take no room from CPM.COM's Z80 part above the BIOS. The BIOS has
  only the trap entries. (`z86.py`'s `;@FILL` puts code after a jump
  table in its page, and the build checks that none of these page ends
  overflows.)

**MODE.COM** sets a channel up and shows its settings:

```
MODE port[:] [baud][,[parity][,[data bits][,stop bits]]]
MODE [port[:]]
```

- port: `PRN`, `LPT1` or `COM1` for channel A, `AUX` or `COM2` for
  channel B (COM1 and COM2 are INT 14h's ports 0 and 1).
- baud: any of the 16 codes' rates, `50` to `19200` (`134.5` or `134`),
  or the PC's short forms `11 15 30 60 12 24 48 96 19`.
- parity `N`, `O` or `E`; data bits `5` to `8`; stop bits `1`, `1.5` or
  `2`. A field left out keeps its setting (the PC's MODE puts in defaults
  instead), so `MODE COM1:,E` changes only the parity.
- With a port alone it shows that channel, with nothing both:
  `PRN: 1200 baud, no parity, 8 data bits, 1.5 stop bits`. After a
  change it shows the new settings; on a bad parameter it shows its usage
  and changes nothing.
- It works through INT 14h F0h and F1h, so the settings hold for DOS's
  PRN and AUX and for CP/M programs under CPM.COM. Each boot goes back to
  1200 baud, 8N1.5: for others, put MODE lines in `AUTOEXEC.BAT`.

**The test** (`test_fdd86.py` group 8) runs on `fdd86.WD2123`, a model of
the chip that follows the 8251A's order of mode, sync characters and
commands, so a wrong set-up sequence would show: the boot set-up,
`COPY` to PRN, to AUX and from AUX, `^P` echo, a printer without CTS (DOS
waits, then prints), and INT 14h / INT 17h from a small program (both
set-up forms, send, receive, a time-out, status, printer busy). Under
CPM.COM, `PIP LST:=`, `PIP PUN:=` and `PIP R.TXT=RDR:` send and write the
same bytes as under CP/M itself with its own CBIOS on the same model.
(That test found an older bug in CPM.COM, fixed: PIP could not close a
file it had copied from a device, CON: or RDR:, because of the S1 byte.)
Group 9 runs MODE.COM: every port name, all four fields, fields left
out, the PC's baud names, showing the settings, and nine bad command
lines; after each it checks the mode byte and baud code the model's
WD2123 received, and that the model saw no write out of order.

**Checked against the WD2123 datasheet** (Western Digital, "WD2123
DEUCE", pages 177-192): status bit 7 is CTS; the status, mode and command
bits; the register addressing (rate register: C/D low channel A, high B,
so ports 10h and 11h); the baud table (1.8432 MHz, x16); reprogramming
with 40h; no minimum time between writes is given. **Not known:**
nothing has been tried on the hardware.

## TERM (`TERM.ASM`, `TERMZ80.ASM`)

A serial terminal: the host on one of the WD2123's channels (another
computer, a modem, a serial console) gets a VT100, or a VT52, of 24 lines
by 64 (or 80) columns; the Timex terminal shows it and its keyboard types
to it.

```
TERM [port[:] [baud][,[parity][,[data bits][,stop bits]]]] [/80] [/52] [/X|/R|/N] [/E] [/C]
```

- port and settings as for MODE; with none, AUX as it is set now.
- `/80` an 80-column terminal; `/52` a host that sends VT52 codes;
  flow control `/X` XON / XOFF (the default), `/R` RTS / CTS, `/N` none;
  `/E` local echo: what is typed shows on the screen too (Enter as CR
  LF; not ESC and the arrow keys), for a host that doesn't echo, such as
  another terminal; `/C` an implicit LF after each CR received (as
  PuTTY's "Implicit LF in every CR"), for one that ends lines with CR
  alone.
- **Ctrl-A** shows the menu on the bottom line: `Q` quit, `L` log to a
  file, `E` local echo, `C` implicit LF, `R` receive a file by XMODEM,
  `S` send one, `B` a break (250 ms), Ctrl-A a Ctrl-A; any other key goes
  back. `+` and `-` after L, E and C show which are on, and it
  shows how many received bytes were lost, if any.
- **With PuTTY** (on a PC, cable as in "The connectors"): Connection
  type Serial, the same speed, 8 data bits, 1 stop bit, no parity, flow
  control XON/XOFF (RTS/CTS with `/R` and those wires). Two terminals
  face each other: what is typed on one shows on the other. Terminal →
  "Implicit LF in every CR" on, and `/E /C` on TERM's side (PuTTY's
  "Local echo: Force on" for the other way) show each side its own
  typing, a line at a time. Tried on a real FDD3000. **PuTTY has no
  XMODEM**: for files use Tera Term (File → Transfer → XMODEM, CRC or
  checksum, *not* 1K: TERM takes 128-byte blocks), with its flow control
  set to none (or RTS/CTS with `/R`): with XON/XOFF on, the PC's serial
  driver takes the XON / XOFF bytes out of a binary file TERM sends.
- **On the host:** tell it the size and the terminal, for instance
  `stty rows 24 cols 64` and `TERM=vt100` (or `vt102`; `vt52` with
  `/52`), and use `LANG=C`: other characters show as `?`. The Timex
  terminal's arrow keys (ESC A-D) go out as ESC [ A-D (ESC O A-D in
  cursor key mode); DEL as DEL. For XMODEM, `sx file` / `rx file`.

**How it works.** TERM.COM (8086) reads the command line, has BIOS trap
1Ch copy its Z80 part over `COLD` (as CPM.COM does) and calls it; the
buffers are in TERM.COM's own memory, over the copy of the Z80 part. The
Z80 part does everything that has to be quick:

- **The channel.** The WD2123 holds one received byte; the next one,
  about 2 100 T-states later at 19 200 baud, overwrites it. Every loop
  that waits, for the terminal's link or for the channel, calls `RXPOLL`,
  which moves a received byte to a 2 KB ring; long block moves go in
  32-byte pieces with `RXPOLL` between them, and a character drawn or a
  line scrolled calls it on the way. Measured on the emulator, the
  longest time between two calls is under 1 800 T-states. At 1 KB in the ring the host
  is asked to stop (XOFF, or RTS off), below 256 it is let go (XON, RTS
  on). The menu and a full log buffer stop the host the same way first.
- **The screen.** The Timex terminal knows only ESC H I J K L M Y and
  wraps as soon as the last column is written. TERM keeps a copy of the
  host's screen and turns the host's codes into those: the cursor goes by
  ESC Y, a scroll of the whole screen is the terminal's own (LF on its
  bottom line, ESC I on its top), a scroll inside a region and inserted
  or deleted lines are drawn again from the copy. The bottom right cell
  is never written (the terminal would scroll); TERM draws it again when
  the screen scrolls up and it moves into view.
- **Codes:** text with VT100 wrapping; CR LF BS TAB VT FF; ESC [ A B C D
  e a H f G ` d (cursor), J K (erase), m (only inverse: 0 7 27), r
  (scrolling region), L M (lines), @ P X (characters), h l (4 insert mode;
  ?1 cursor keys, ?7 autowrap), n (5, 6: answers), c (answers "VT100"),
  s u; ESC 7 8 D E M c Z, ESC ( ) 0 / B with SO SI (line drawing as
  + - |), ESC # x ignored, CAN SUB. UTF-8 and 8-bit characters show
  as `?`. With `/52`: ESC A B C D H I J K Y Z.
- **The log** collects the raw bytes in an 8 KB buffer; when it is
  nearly full TERM stops the host, writes it (DOS random block write, so
  the file is exact) and goes on.
- **XMODEM** (CRC-16 or checksums, 128-byte blocks; receive tries `C`
  three times, then NAK): the protocol is in the 8086 part, the bytes in
  the Z80 part (RECV takes a whole block in one call, sending the answer
  to the last one first; CRC in Z80 code).

**The test** (`test_term.py`) runs TERM on the FDD3000 model with a host
on channel B that sends at the real rate (`fdd86.WD2123`: a byte the
chip holds is lost when the next one comes in), and checks the terminal
model's screen, cell by cell and the cursor, against `VT`, a Python
model of the VT100 / VT52 above: 21 cases of codes, then 60 batches of
random ones; keys; the log (12 KB at 19 200 baud, through the 8 KB
buffer); XMODEM receive (CRC with a corrupted block sent again, at 9 600
and 19 200; checksums) and send (CRC; checksums): the files are the same
bytes. With a terminal model that takes 2 ms a character and 20 ms a
scroll (a guess: the real terminal's speed isn't known), 6 KB of text:

| | lost | chars/s |
|---|---|---|
| 9 600 or 19 200 baud, XON / XOFF | 0 | 325 |
| 9 600 or 19 200 baud, RTS / CTS | 0 | 325 |
| 9 600 baud, no flow control | 1 637 | - |
| a terminal that takes no time, 9 600 / 19 200 baud | 0 | 861 / 1 048 |

So the terminal's speed sets the pace; flow control keeps it from losing
anything. With a terminal that takes no time, TERM itself manages about
1 050 characters a second of text.

**Not known:** the real terminal's speed over the link, and anything on
real hardware.

## The boot (`BOOT.ASM`, `COLD`)

1. **Boot ROM** (2 KB, `roms/fdd_boot.rom`): at reset it restores drive A,
   waits for the motor, reads sector ID 0 of track 0 to 3F00h and jumps
   there with interrupts off, SP = 3EFFh and itself still paged in at
   0000h-07FFh.
2. **Boot sector** at 3F00h: pages the ROM out (latch 5Eh), restores,
   and reads the first directory sector to D000h. If entry 0 is
   `Z86.SYS` at cluster 2, it reads the file to D000h (stepping in at each
   new track) and jumps to D0FDh. Otherwise it prints `Non-System disk`
   with its own copy of the link's send protocol, and stops. All polled,
   no interrupts. A missing sector or a CRC error restores and starts
   again, 8 times, then it stops (HALT).
3. **`COLD`** in the BIOS: clears the 8086 vectors (0000h-03FFh: RAM is
   random at power-on), reads the directory, checks entries 1 and 2 are
   IO.SYS and MSDOS.SYS, reads them from their first clusters through the
   BIOS's own READ, sets CS = DS = 0040h, IP = 0, and jumps to the
   interpreter's `START`. On a read error or a missing file it prints
   `Disk boot failure` and stops.

`fdd86.py` runs this on cpm80ds's `machine.py`: the WD177x model there
(DRQ, INTRQ, write protect, record not found, lost data) is the one CP/M's
CBIOS was tested on. The terminal is modelled from the FDD side of the
protocol, as the terminal ROMs' source isn't here. It answers at once, so
the FDD's timeouts are never tested.

### Speed

Measured on the emulator, with T-states from tmxcobol's Z80 timing tables.
The seconds assume a 4 MHz clock: the schematic has a 16 MHz crystal,
divided by 4 (74LS393) for the Z80.

Step 2, the interpreter alone (BIOS calls in Python, not counted):

| Step | 8086 instructions | Z80 T-states | T / instr | at 4 MHz |
|---|---|---|---|---|
| boot to date prompt | 13 560 | 3 335 277 | 246 | 0.83 s |
| DIR (4 files) | 16 537 | 4 120 861 | 249 | 1.03 s |
| CHKDSK | 26 648 | 6 558 307 | 246 | 1.64 s |
| COPY 2 KB file | 11 438 | 2 461 849 | 215 | 0.62 s |
| EDLIN create, 2 lines, save | 24 405 | 5 409 952 | 222 | 1.35 s |
| TYPE | 6 654 | 1 562 912 | 235 | 0.39 s |
| DEBUG: load, enter and run a program | 15 639 | 3 482 460 | 223 | 0.87 s |
| REN, DEL, DIR | 29 188 | 6 859 277 | 235 | 1.71 s |
| whole session | 146 779 | 34 506 220 | 235 | 8.6 s |

That is about 17 000 8086 instructions a second, below step 1's guess of
25 000. It is still usable: each command takes one to two seconds.

Step 3, everything (`test_fdd86.py`): the BIOS adds 3.2 M T-states (0.8 s)
to the session, for 209 sectors and every character on the screen. A real
terminal answering slower than the model would add to the console part.
Since step 4 the boot row starts at reset, with the boot ROM.

| Step | Z80 T-states | at 4 MHz | sectors |
|---|---|---|---|
| boot to date prompt (from step 4: from reset) | 9 604 143 | 2.40 s | 108 |
| DIR | 4 259 907 | 1.06 s | 2 |
| CHKDSK | 6 897 244 | 1.72 s | 12 |
| COPY | 3 003 546 | 0.75 s | 30 |
| EDLIN | 5 998 100 | 1.50 s | 28 |
| TYPE | 1 675 158 | 0.42 s | 3 |
| DEBUG | 3 989 378 | 1.00 s | 26 |
| REN, DEL, DIR | 7 055 496 | 1.76 s | 10 |
| whole session | 43 249 941 | 10.8 s | 275 |

The boot from reset, step 4:

| Part | Z80 T-states | at 4 MHz | sectors |
|---|---|---|---|
| boot ROM, mostly its own delay for the motor | 4 493 165 | 1.12 s | 1 |
| boot sector: directory, Z86.SYS | 524 710 | 0.13 s | 35 |
| `COLD`: directory, IO.SYS and MSDOS.SYS | 436 664 | 0.11 s | 28 |
| DOS starts, loads COMMAND.COM, asks the date | 4 245 893 | 1.06 s | 46 |

The emulated drive has no rotation, so a real disk adds its own time: with
the 2:1 interleave a track takes about 2 turns (0.4 s at 300 rpm), so the
boot sector and `COLD` together need roughly 1.5 s more.

The most expensive remaining instructions (`test_z86.py --fast` profiles by
routine):

| Instruction | T-states each |
|---|---|
| `ADD r16,r/m16` | 330 |
| near `CALL` | 290 |
| far `CALL` to the BIOS | 630 |
| `INT` | 950 |

## Next steps

1. ~~Z80 8086 interpreter, checked against `cpu86.py` instruction by instruction.~~ Done (step 2).
2. ~~Z80 trap handlers taken from CBIOS A1.1, run on `cpm80ds/machine.py`.~~ Done (step 3).
3. ~~Boot: the boot ROM reads sector 0 to 3F00h. An IPL there loads the interpreter, then IO.SYS and MSDOS.SYS.~~ Done (step 4).
4. Real hardware with a TT3000 / TC3256: write `build/MSDOS.DSK` to a
   40-track disk (or an HxC image) and boot the FDD3000 from it.
5. ~~MBASIC~~: done, under CPM.COM. An 8086 BASIC for DOS would also
   run, but much slower (about 17 000 8086 instructions a second). Tim
   Paterson's listings (`../ext/Paterson-Listings`, from
   github.com/DOS-History) hold the runtime library of the BASIC-86
   *compiler* (BASCOM-86, 1981), not the interpreter, and not the
   compiler itself.
