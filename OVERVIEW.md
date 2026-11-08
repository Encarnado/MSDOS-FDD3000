# MS-DOS 1.25 on the Timex FDD3000: overview of the work

This document describes what was built, how each part works, and how the
work was done and checked. Addresses are hexadecimal; T-states are Z80
clock cycles, and times assume a 4 MHz Z80 (nothing at hand documents the
FDD3000's crystal). The project's working notes, with every measurement,
are in `project/MSDOS/poc/README.md`.

## 1. The machine and the idea

The **Timex FDD3000** is a floppy disk unit for the Timex Sinclair
computers. It has its own **Z80**, 64 KB of RAM, a **WD177x** floppy
controller, up to four drives, and a 2 KB boot ROM. It talks to a Timex
computer acting as its terminal (TT3000 / TC3256 / TC2068, the "Terminal
3000") over a link on port **2Fh**. Under TOS and Timex's CP/M 2.2 (TMX
CP/M, CBIOS A1.1) the programs run on the FDD3000's Z80 and the computer
is only the screen and keyboard.

MS-DOS needs an 8086. The plan, from `FEASIBILITY.md`: keep the FDD3000
exactly as it is and **interpret the 8086 in Z80 code**. MS-DOS 1.25 is
small (MSDOS.SYS is 6 KB) and leaves all hardware to its I/O system, so
only the I/O system has to know about the FDD3000, and it can hand every
device call straight to native Z80 code.

The FDD3000's two serial ports (a WD2123) are DOS's printer and AUX
devices, as they are CP/M's LIST and PUNCH/READER.

Result: the disk boots from the FDD3000 boot ROM into MS-DOS 1.25 with
52 KB of 8086 memory (about 43 KB free for programs). The interpreter runs
about **17 000 8086 instructions a second** (235 T-states each); DIR takes
about 1.1 s, CHKDSK 2 s, booting from reset to the date prompt 2.4 s plus
disk rotation.

## 2. The parts

| Part | File (source) | CPU | Size | Where it runs |
|---|---|---|---|---|
| Boot sector | `BOOT.ASM` | Z80 | 254 bytes | 3F00h |
| Interpreter + BIOS | `I86.ASM` + `BIOS.ASM` = `Z86.SYS` | Z80 | 8 737 bytes | D000h-F220h |
| I/O system | `IOFDD.ASM` = `IO.SYS` | 8086 | 332 bytes | 0040:0000 (linear 0400h) |
| DOS kernel | Microsoft `MSDOS.ASM` + `STDDOS.ASM` = `MSDOS.SYS` | 8086 | 6 190 bytes | 0060:0000 |
| Command processor | Microsoft `COMMAND.ASM` = `COMMAND.COM` | 8086 | 4 879 bytes | DOS loads it |
| Disk formatter | `FORMAT.ASM` = `FORMAT.COM` | 8086 + trap | 1 628 bytes | .COM |
| CP/M program runner | `CPM.ASM` = `CPM.COM`, with `CPMZ80.ASM` inside | 8086 + Z80 | 3 286 bytes | .COM; Z80 part at F12Ch |
| Text editor | `EDIT.ASM` = `EDIT.COM` | 8086 | 4 653 bytes | .COM |

### 2.1 Memory map of the FDD3000 while DOS runs

| Z80 address | Contents |
|---|---|
| 0000h-CFFFh | the 8086's memory: **8086 linear address n is Z80 address n** (52 KB) |
| D000h-D0FFh | REGS: the 8086 registers and interpreter state; the serial routines in its unused end (D03Eh-D0F0h); D0FDh holds `JP COLD` |
| D100h-D4FFh | split jump tables: opcode handlers (OPLO/OPHI), ModR/M routines (EALO/EAHI) |
| D500h-EB45h | the interpreter's code (some page-aligned blocks; INT 14h's set-up in the end of the first, D5A2h-D5FFh) |
| EB46h-F12Bh | the BIOS: trap dispatcher, console, disk, serial traps, clock, PC ROM BIOS emulation |
| F12Ch-F220h | `COLD`, the boot loader, needed only at boot |
| F221h-FFFFh | free, and the Z80 stack from FFFFh down |
| (CP/M program running) F12Ch-FAF5h | CPM.COM's Z80 part, loaded over `COLD` |
| (CP/M program running) FAF6h-FEF5h | its 1 KB file buffer |

The 8086 sees 0000h-CFFFh only. Segment arithmetic wraps within 64 KB
(there is no memory above), and each segment register keeps its base
(seg × 16) beside it so an operand address is one 16-bit add.

### 2.2 The 8086 interpreter (`I86.ASM`)

- **Registers:** the 8086's registers are in the REGS page, so ModR/M
  decoding always yields a pointer, into guest memory or into REGS, and
  one handler serves register and memory operands.
- **Z80 register use while 8086 code runs:** BC = host address of the next
  8086 code byte (CS base + IP); IX = NEXT, the dispatcher (every handler
  ends with `JP (IX)`); AF' = the 8086 arithmetic flags (S Z AF OF CF in the
  Z80's S Z H V C positions; A' = low byte of the last result, PF computed
  from it only when FLAGS is read). A, DE, HL, IY and SP are scratch.
- **Dispatch:** the opcode indexes two 256-byte tables (low bytes, high
  bytes of the handler address): 58 T-states per instruction including the
  `JP (IX)`.
- **Prefixes:** a segment override changes the operand bases and points IX
  at a routine that restores them after the instruction. REP is kept in
  REGS (`REPT`).
- **String instructions:** `REP MOVS` / `REP STOS` use `LDIR` / `LDDR`.
  `REPNE SCASB` passes over all but the last compare with `CPIR` / `CPDR`
  (21 T-states a byte instead of about 300), then makes the last compare
  the normal way, so the flags, CX and DI end exactly as on an 8086; not if
  DI would wrap round the segment. Other REP forms loop in Z80 code.
- **BIOS traps:** opcode **`0F nn`** (`POP CS` on an 8086, which no real code
  uses) calls the BIOS's `TRAP` with A = nn. The handler works on the 8086
  registers in REGS and sets ZF / CF in AF'.
- **One known difference from an 8086:** after 16-bit add / subtract /
  increment / decrement, AF comes from bit 11 (the Z80 way) instead of
  bit 3. Only DAA, DAS, AAA and AAS read AF, and only after 8-bit
  arithmetic in real code. The tests allow exactly this difference.
- **Checked:** against `cpu86.py` (a Python 8086 written for the project)
  register for register, flag for flag and byte for byte of memory after
  every one of a DOS session's 156 000 instructions, and on 30 000+ random
  single instructions (all opcodes, prefixes, REP) plus 3 000 random long
  REP SCAS cases.

### 2.3 The Z80 BIOS (`BIOS.ASM`)

IO.SYS's 14 DOS device entries, six IBM PC ROM BIOS interrupts, and three
extra functions are each a trap:

| Trap | Function |
|---|---|
| 1-3 | console status, input, output |
| 4, 5, 6 | printer output (serial channel A), AUX input and output (channel B) |
| 7, 8 | disk read, write (AL drive, DS:BX buffer, CX sectors, DX first logical sector) |
| 9-13 | disk changed, set date, set time, get time, flush console |
| 10h, 11h, 12h, 14h, 16h, 17h, 1Ah | INT 10h (teletype, cursor as VT52 `ESC Y`, clear), 11h, 12h, 14h (serial), 16h (keyboard), 17h (printer), 1Ah (tick count) |
| 1Bh | FORMAT TRACK: write a whole track image with the WD177x write-track command |
| 1Ch | CPM.COM: copy its Z80 part to F12Ch (after checking it was built for this BIOS), or with BP = 0 run it |
| 1Dh | CPM.COM: the end of a DOS call its Z80 part started |

- **Console:** CBIOS A1.1's send and receive routines, unchanged: each byte
  crosses the link as two nibbles, each echoed by the other side; the
  terminal says 04h when a key is waiting. The link cannot look at a key
  without taking it, so STATUS takes it and keeps it for the next INPUT.
  (`fdd86.py`'s `Link` class models the terminal's end byte by byte.)
- **Disk:** logical sector n is track n / 18, sector ID from a 2:1
  interleave table (`SKEW`). The transfer loop is CBIOS A1.1's
  `IN A,(2Fh) / RLA / JR NC / INI` (DRQ is bit 7 of port 2Fh); the FDC's
  INTRQ ends it through RST 38h. Since 0038h is in the 8086's memory (the
  INT 0Eh vector), the BIOS points it at its handler for each transfer and
  puts the vector back afterwards. Seeks verify; 10 retries, then restore
  and retry; a sector read or write is also re-tried from a fresh restore
  half-way through its 10 tries. Every controller wait times out after
  about 3 s (an empty drive gives the WD1770 no index pulses, so it would
  otherwise wait for ever): DOS then gets "not ready" instead of hanging
  (added 2026-11-08, after the hardware run; `test_fdtimeout.py`). Errors
  go to DOS as its codes (write protect, not ready, seek, sector not
  found, CRC).
- **Serial:** the FDD3000's WD2123 holds two 8251A-compatible channels
  with their own baud-rate generators: A at ports 80h (data) / 81h
  (control, status), baud register 10h; B at 40h / 41h, 11h. As in CBIOS
  A1.1, channel A is the printer (CP/M's LIST, DOS's PRN) and B is
  PUNCH / READER (DOS's AUX). Both are set up at boot as CBIOS A1.1 does
  (8 bits, no parity, 1.5 stop bits, 1200 baud). Output waits for DSR and
  TxRDY; input raises RTS only while it waits. INT 14h (set-up in PC and
  PS/2 form, send, receive, status, with time-outs) and INT 17h work. The
  baud codes 0-15 are 50 75 110 134.5 150 200 300 600 1200 1800 2400 3600
  4800 7200 9600 19200 (TMX CONFIGUR's list). The shared routines live in
  unused page ends of the interpreter, so that they cost CPM.COM no room.
- **Clock:** the FDD3000 has none: date and time are what DOS was last
  told; INT 1Ah counts up by one per call so programs waiting on it don't hang.

### 2.4 Booting

1. **Boot ROM** (2 KB): at reset restores drive A, reads sector ID 0 of
   track 0 to 3F00h and jumps there (interrupts off, SP = 3EFFh, ROM still
   paged in at 0000h-07FFh).
2. **Boot sector** (`BOOT.ASM`, at 3F00h): pages the ROM out (latch 5Eh),
   reads the first directory sector to D000h; if entry 0 is `Z86.SYS` at
   cluster 2, reads the file to D000h track by track and jumps to D0FDh.
   Otherwise prints `Non-System disk` (with its own copy of the link send
   routine) and stops. Retries 8 times, then HALT.
3. **`COLD`** (end of the BIOS, F12Ch): sets up the serial channels, clears the 8086 vectors (RAM is
   random at power-on), checks directory entries 1 and 2 are IO.SYS and
   MSDOS.SYS, reads them through the BIOS's own READ, sets CS = DS = 0040h,
   IP = 0, and starts the interpreter. On failure: `Disk boot failure`.
4. **IO.SYS** sets the PC ROM BIOS vectors (each pointing at
   `TRAP n / RETF 2`), calls DOS's init with its drive table, then loads
   COMMAND.COM with DOS function calls, as Seattle Computer's I/O system
   does.

### 2.5 The disk format (`mkfat.py`, `FORMAT.ASM`)

40 tracks × 18 sectors × 256 bytes = 720 sectors, 180 KB; single-sided.
CP/M and TOS use 16 sectors per track; a double-density track at 300 rpm
holds 6 250 bytes and 18 sectors with short gaps take 6 044.

| Logical sectors | Contents |
|---|---|
| 0 | boot sector |
| 1-2, 3-4 | FAT 1, FAT 2 (FAT12, media byte FEh) |
| 5-12 | directory, 64 entries |
| 13-716 | 176 clusters of 1 KB (clusters 2-177) |

A system disk starts with three hidden files (attribute 06h) in the first
directory entries and contiguous from cluster 2: `Z86.SYS`, `IO.SYS`,
`MSDOS.SYS`. 157 696 bytes stay free on a system disk with COMMAND.COM.

`FORMAT [d:] [/S]` builds each track image (gaps, ID fields, sync and CRC
marks as the WD177x write-track command wants them), has trap 1Bh write it,
reads it back with INT 25h, marks the clusters of a bad track as bad
(FF7h), writes boot sector, FATs and directory with INT 26h, and with `/S`
copies the three hidden files and COMMAND.COM (read into memory first, so
it works with one drive).

### 2.6 CP/M programs (`CPM.COM`, `CPMZ80.ASM`)

`CPM program [arguments]` runs a CP/M 2.2 program (`program.CPM`, or
`.COM`) **natively on the Z80**, with its files on the DOS disk.

- The 8086 part checks the build (trap 1Ch compares a table of BIOS
  addresses), has the Z80 part copied to F12Ch, reads the program, builds
  the FCBs and command tail as the CCP would, and calls trap 1Ch with
  BP = 0.
- The Z80 part swaps the bottom of memory (where DOS, COMMAND and CPM.COM
  live, below the program's 0100h) out to a save area at the top, moves
  the program to 0100h, and builds page zero, a BDOS entry at 0005h and
  a 17-entry CP/M BIOS jump table in a page above the program.
- **Console BDOS calls** go straight to the Z80 BIOS routines.
  **File calls** are translated to DOS 1.25 FCB calls with 128-byte
  records: for each one the Z80 part swaps DOS's memory back in, runs
  `INT 21h` on the interpreter from a stub (`CD 21 0F 1D`: INT 21h, then trap
  1Dh back to Z80), and swaps out again (about 0.2 s). A 1 KB buffer of
  8 records serves sequential and random reads (read-ahead) and writes
  (write-behind) so most record calls need no DOS call.
- Details that mattered: CP/M's random-record fields, record counts and
  extents (RC, S2) are translated; the last partial record is padded with
  ^Z; search results become CP/M directory records; DOS writes the drive
  number into byte 0 of an FCB it opens and CP/M does not, so that byte is
  not copied back; byte 13 (S1) is CP/M's to ignore and PIP uses it, but
  to DOS it is the block number's high byte, so DOS gets 0 there; MBASIC
  counts records in the FCB itself, so the buffer keeps the program's own
  record fields. LIST, PUNCH and READER go to the serial channels.
- TPA 0100h-A0FFh (40 KB). ASM, LOAD, M80, L80, PIP and MBASIC 5.2 were run
  under CPM.COM and under real CP/M 2.2 on the emulated FDD3000; every file
  they wrote was byte-identical.

### 2.7 EDIT (`EDIT.ASM`)

`EDIT name.ext [/80]`: a full-screen editor in 8086 code with the
WordStar-style keys and status line of TMX CP/M's EDIT, so the two work
alike. The whole file is in memory in a gap buffer (up to 33 539 bytes);
lines are LF inside and CR LF in the file; saving writes `name.$$$`, then
renames the old file to `.BAK`. Disk full keeps the old file; DOS's own
"Abort, Retry, Ignore" during a save is noticed through INT 24h and the
screen is redrawn afterwards.

On an interpreter running 17 000 instructions a second, comparing a whole
screen copy per key (the CP/M EDIT's method) costs over a second. EDIT
instead keeps a mark per text row (the first column to send again), looks
only at rows between the first and last mark, sends status-line fields only
when they change, scrolls the terminal itself for one-line moves (LF on the
bottom row, `ESC I` on the top), and stops drawing while a key is waiting.
A key costs 0.03-0.07 s; a page 1 s.

Terminal codes (from the Terminal 3000 ROM): `ESC Y row+32 col+32`,
`ESC H ESC J` clear, `ESC K` clear to end of line, `ESC L` / `ESC M`
inverse on / off, `ESC I` on the top row scrolls down. Nothing is ever
written in the last column (the terminal wraps there).

## 3. How the work was done

The work went in steps, each one checked against the one before, so that
at every point there was a known-good reference to compare with.

1. **A Python 8086 and the original tools.** `cpu86.py` (an 8086
   interpreter) and `dosshim.py` (enough of INT 21h) run **MASM 1.10,
   LINK 2.00 and EXE2BIN from MS-DOS 2.0**. With them MS-DOS 1.25's kernel
   and COMMAND.COM were assembled from Microsoft's source by Microsoft's
   own 1983 tools (MSDOS.ASM alone is 87 million emulated instructions).
   `IOFDD.ASM` was written as the I/O system, each entry a trap, and
   `fddos.py` provided the traps in Python. DOS booted to `A:` and ran DIR,
   COPY, REN, DEL, TYPE, CHKDSK, EDLIN and DEBUG from an FDD3000 disk image.
   This session (`test_dos.py`) became the reference.
2. **The Z80 interpreter.** `I86.ASM` was written and run on a Z80
   emulator (`tmxcobol/cpmemu.py`) beside `cpu86.py`, compared after every
   instruction (`test_z86.py`), plus random single instructions
   (`fuzz_z86.py`). Profiling by routine guided the speed work.
3. **The Z80 BIOS.** The traps moved from Python to Z80 code (`BIOS.ASM`)
   taken from CBIOS A1.1's link and WD177x routines, run on `cpm80ds`'s
   FDD3000 model (Z80, WD177x with DRQ / INTRQ / write protect / record not
   found, drive latch), the same model CP/M's CBIOS had been tested on.
   The terminal's end of the link is modelled byte by byte. The screens and
   the disk after the session had to be byte-identical to step 1's.
4. **Booting.** The boot sector and `COLD` replaced the Python loader. The
   test starts at reset with the boot ROM, with random RAM, with unreadable
   tracks, and with a data disk.
5. **The disk format** moved from 16 sectors and reserved system tracks to
   18 sectors and hidden system files (+40 KB per disk); **FORMAT** was
   written and checked against the Python BIOS (same screens, same disk).
6. **CPM.COM:** every program's output files compared byte for byte with
   the same commands under real CP/M 2.2 on the emulated FDD3000; a test
   program (`BDOSTEST.MAC`) exercises the BDOS calls one by one.
7. **MBASIC 5.2** under CPM.COM: LOAD, SAVE (ASCII and tokenised), random
   and sequential files, KILL, NAME, a game; files compared with CP/M's.
8. **EDIT**, with a test that after every step rebuilds the text from the
   editor's gap buffer in emulated memory and checks the emulated
   terminal's screen cell by cell (and the inverse attribute, the cursor,
   and nothing in the last column), and checks the text and cursor against
   a Python model of the keys; 400 random keys among them.
9. **REPNE SCASB with CPIR**, checked with the lockstep test, the fuzzer and
   a new scan-only fuzz mode (deliberately breaking the fast path made the
   fuzzer report 159 mismatches, so it does catch errors). Making room for
   it moved `COLD` to the end of the BIOS so that CPM.COM's Z80 part loads
   over it.
10. **Serial ports.** The WD2123's use was read from CBIOS A1.1 (ports,
   set-up, LIST / PUNCH / READER, error handling) and TMX CONFIGUR 1.3
   (what the setting bytes and the 16 baud codes mean). An emulator model
   of the chip (`fdd86.WD2123`) follows the 8251A's mode / sync / command
   order, so a wrong set-up sequence would show. The test copies to and
   from PRN and AUX, runs INT 14h / INT 17h from a small program, and runs
   `PIP LST:=`, `PIP PUN:=` and `PIP R.TXT=RDR:` under CPM.COM and under
   real CP/M with its own CBIOS on the same model: the same bytes.

### Problems found along the way (selected)

- MASM 1.10's runtime computes its stack with a signed compare and fails
  with more than 512 KB, so the shim reports 512 KB. MASM 1.10 also won't
  redefine with `=` a symbol first set with `EQU` (one patch to COMMAND.ASM).
- CPM.COM first saved memory over COMMAND's resident part; the top of
  usable memory must come from the PSP (offset 2), not a constant.
- MBASIC's NAME failed until the FCB drive byte was left alone; its LOAD and
  SAVE use random records, so random I/O had to go through the buffer too;
  a first buffered-write version overwrote MBASIC's own record count and
  lost records (caught by the byte comparison with CP/M).
- `PIP R.TXT=RDR:` (or `=CON:`) under CPM.COM could not close its file:
  PIP keeps 7Ch in FCB byte 13 (CP/M's S1), which DOS read as the high
  byte of the block number, so the write went far past the end of the
  disk. Found by the serial test.
- EDIT's first version spent most of each key scanning lines that needed no
  redraw (0.16 s a key); limiting the work to the marked rows made it 0.07 s.
- The interpreter's REPNE SCASB at about 300 T-states a byte made big-file
  operations slow (loading 28 KB: 5.5 s; now 3.3 s with CPIR).

## 4. Status, limits and what is untested

- **Not tried on real FDD3000 hardware or a real terminal.** It boots on
  FUSE. The emulated drive has no rotation, so the 2:1 interleave is not
  tuned; the terminal model answers at once, so link timeouts are untested.
- Speed: 17 000 8086 instructions a second; a full EDIT screen about 1 s;
  each `CPM` command spends about 2 s on DOS loading CPM.COM and COMMAND
  reloading itself.
- Under CPM.COM, MBASIC has 15 686 bytes free (33 862 under TMX CP/M): the
  interpreter, DOS and COMMAND share the 64 KB.
- A disk error during a CP/M program run is untested.
- Serial: the baud rates are the WD2123 codes as TMX CONFIGUR names them;
  the FDD3000's crystal, connectors and DSR wiring are not checked.
- `Z86.SYS` and `CPM.COM` must come from the same build (CPM.COM checks).

## 5. Running it

See `README.md` in the package root. Test suites: `test_z86.py` (lockstep,
10 s), `fuzz_z86.py` (10 s), `test_dos.py` (under 1 s), `test_edit.py`
(1.5 min), `test_fdd86.py` (3 min; groups 6 and 7 need the CP/M reference
disk and the MBASIC disk, which are not in the package).
