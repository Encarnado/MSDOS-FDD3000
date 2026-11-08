# MS-DOS 1.1 / 2.0 on FDD3000 + TT3000 / TC3256: feasibility

Source: `src/` (clone of github.com/michaelmsonne/MS-DOS: `v11source`, `v11object`,
`v20source`, `v20object`). License note: that release (Computer History Museum terms)
is non-commercial and forbids reposting. If anything from here is ever published,
base it on github.com/microsoft/MS-DOS, which has 1.25 and 2.0 under MIT.

> **Update 2026-11-06:** proof-of-concept steps 1 to 4 are done (see
> `poc/README.md`). MS-DOS 1.25 was built from source and boots with FDD3000
> disks and 52 KB of memory, leaving 43 KB free for programs. It runs first
> on a Python 8086 model, then on the Z80 interpreter `I86.ASM` (6.9 KB),
> which matches the model after every instruction.
>
> Since step 3 the console and disk calls are Z80 code too (`BIOS.ASM`,
> 1.1 KB, from CBIOS A1.1's link and WD177x routines). Since step 4 the
> disk boots itself from the FDD3000 boot ROM: a 134-byte boot sector loads
> the interpreter and BIOS, and the BIOS loads DOS. On the emulated FDD3000
> nothing is left in Python but the hardware. It also boots on FUSE.
> `FORMAT [d:] [/S]` makes new disks, bootable with `/S`. The disk format
> now has 18 sectors per track and the system in hidden files (the first
> version had 16 and 80 reserved sectors): 180 KB on a data disk.
>
> The measured speed is 235 Z80 T-states per 8086 instruction, about 17 k
> instructions/s at 4 MHz. That is within the estimate below. With the BIOS,
> DIR takes about 1.1 s and CHKDSK about 1.7 s. Reset to the date prompt
> takes 2.4 s on the emulator, plus a few seconds of disk rotation on a real
> drive.

## Short answer

**Not natively.** MS-DOS 1.x and 2.x are written entirely in 8086 assembly. They also
only run 8086 programs (COMMAND, EDLIN, DEBUG, BASIC, everything in `v*object`). Every
machine involved is a Z80:

| Machine | CPU | RAM usable by a program |
|---|---|---|
| FDD3000 | Z80A (~4 MHz?) | 64 KB flat |
| TT3000 | Z80 + SCLD | ~16 KB (4000h–7FFFh), ROM terminal |
| TC3256 | Z80 3.5 MHz | 256 KB DRAM, but only through a 4 KB window at 3000h |

**Yes, as a project: an 8086 interpreter written in Z80, running on the FDD3000.**
The TT3000 or TC3256 stays exactly what it is today, a VT52 80×24 terminal on the
nibble link. No terminal ROM changes are needed. DOS 1.1 is a realistic target.
DOS 2.0 is marginal on memory.

## Why the FDD3000 is the right host

- It already owns the disk (WD177x on C0h–C3h, latch E0h) and the console link (2Fh).
  These are the only two things the DOS BIOS (IO.SYS) needs.
- It has 64 KB of flat RAM. The TC3256's 256 KB sits behind a 4 KB window, so every
  emulated memory access would need a bank check. That would be several times slower,
  and the TC3256 also has to draw the screen.
- MS-DOS was designed for this split. IO.SYS is the OEM layer: `v11source/IO.ASM`
  for SCP hardware, and `v20source/SKELIO.ASM`, a skeleton OEM BIOS (Altos). Under
  emulation, IO.SYS becomes a few 8086 stubs that execute an escape opcode, and the
  emulator handles them in native Z80:
  - CONIN / CONOUT / CONST → the existing CBIOS nibble routines (FB0Dh / FAA8h / IN 2Fh).
  - READ / WRITE sector → WD177x code taken from CBIOS A1.1.
- The disk format can stay native. The DOS kernel takes sector size per drive
  (`SECSIZ` in the DPB, `v11source/MSDOS.ASM:131`). A FAT12 volume with
  256-byte sectors × 16 per track works on the existing 40T SS / 80T DS geometry
  without new formatting code. Reading real PC disks (512 B × 9 sectors) would also
  need the FDC sector-length handling, which can come later.
- The console needs nothing special. DOS 1/2, COMMAND, EDLIN and DEBUG are all
  teletype-style (CR, LF, BS, BEL). The VT52 terminals are enough. ANSI.SYS (2.0)
  would not match; skip it.

## Memory budget (guest = 8086 address space mapped into the FDD's 64 KB)

| Item | Approx. size |
|---|---|
| Boot ROM page / Z80 vectors + 8086 interpreter (Z80) | 8–10 KB |
| Guest RAM available | ~52 KB |
| DOS 1.1: vectors 1 KB + IO stubs <1 KB + MSDOS ~6–7 KB + COMMAND 5 KB | ~13 KB → **~38 KB TPA** |
| DOS 2.0: MSDOS.SYS 16.7 KB + SYSINIT/IO + buffers + COMMAND 15.5 KB | ~36 KB → **~15 KB TPA** |

Guest memory would simply be guest linear address N = host address base+N, with
segment arithmetic done in the interpreter. Anything above ~52 KB faults. DOS 1.1
originally ran on 32 KB PCs, so it fits comfortably. DOS 2.0 boots, but most
programs won't fit.

## Speed (estimate)

A Z80 interpreting 8086 code (ModR/M decoding, lazy flags, segment adds) costs
roughly 100–250 T-states per simple instruction. That is about 20–40 k 8086
instructions/s at 4 MHz, or **~15–30× slower than an IBM PC**:

- The prompt, DIR, TYPE, COPY and EDLIN are usable. Disk I/O runs at native speed
  because it happens in Z80.
- MASM, LINK and BASICA would be very slow.
- BASICA/BASIC.COM in `v11object` are IBM-ROM-BASIC dependent and won't run anyway.

## Alternatives considered

1. **Translate the DOS source to Z80** (the reverse of `v11source/TRANS.ASM`, which
   translated Z80→8086). This gives a native, fast FAT12 DOS on Z80, but it is a new OS
   and still can't run any .COM/.EXE program. It is only worthwhile as a file system,
   and for that a CP/M utility that reads and writes FAT disks is far less work.
2. **Run the emulator on the TC3256.** Possible with the 4 KB window, but slower.
   It would also need its own disk/link code via the interface ROM. No benefit over
   option A.
3. **TT3000 alone:** 16 KB of RAM. Not possible.

## Suggested proof-of-concept path

1. Write the 8086 interpreter first in Python inside `cpm80ds/machine.py`, as a
   reference model. Boot an assembled DOS 1.1 kernel + COMMAND with trapped I/O.
   This needs an 8086 assembler for the sources: they are in SCP ASM / MASM syntax,
   `v20object/MASM.EXE` can run under DOSBox, or use the MIT 1.25 binaries.
2. Write the Z80 interpreter and test it on the same emulator against the Python
   model.
3. Build a FAT12 boot disk (256 B sectors) with tomato or a new `mkfat.py`. Boot it
   from the FDD boot ROM (3F00h IPL → load interpreter + DOS image).
4. Test on real hardware with a TC3256 or TT3000 terminal.
