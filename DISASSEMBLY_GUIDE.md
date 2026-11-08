# Disassembly guide

For each binary: CPU, where it is loaded, where execution starts, what is
code and what is data, and the source-level listing and symbols to check a
disassembly against. Every binary here was assembled from the sources in
`project/`, so a disassembly can be verified line by line against
`symbols/`.

Conventions in `symbols/`:

- `*.lst` (Z80): `address  bytes  source line`, from the assembler's final
  pass. Macro expansions (`;@FOR`, `;@TABLE`) are already expanded.
- `*.sym` (Z80): `address  kind  name`, kind = `code`, `data` (the label's
  line is DB / DW / DS) or `equ` (a constant, often an address inside
  REGS). Sorted by address.
- `*.LST` (8086): MASM 1.10 listings (offsets within the segment; symbol
  table at the end). `*.sym` (8086): `offset  type  name` taken from them
  (`L NEAR` code labels, `L BYTE` / `L WORD` / `V ...` data, `Number`
  constants).

## Non-standard things to tell the pipeline first

1. **`0F nn` in 8086 code is a two-byte BIOS trap**, not `POP CS`. It calls
   the Z80 BIOS function nn (table in OVERVIEW.md 2.3) and execution goes on
   at the next byte. It appears in IO.SYS (every entry), FORMAT.COM
   (`0F 1B`), CPM.COM (`0F 1C`) and in a stub CPMZ80 writes to memory
   (`CD 21 0F 1D`). Treat `0F` as a 2-byte instruction with no control-flow
   effect.
2. **The 8086 linear address space is the Z80's 0000h-CFFFh.** An 8086
   address seg:off is Z80 address `(seg*16 + off) mod 10000h`.
3. **Z80 interpreter control flow is table driven.** Every 8086 opcode
   handler ends with `JP (IX)` (IX = NEXT); handlers are reached only through
   jump tables, so a recursive-descent disassembler must be seeded from the
   tables (below), not just from the entry point.
4. **Split jump tables:** a table of handler addresses stored as 256 low
   bytes followed by 256 high bytes (two pages), not as DW pairs.
5. **Self-modifying code** in `Z86.SYS`: the low byte of these `JP`
   instructions is patched at run time to select a slot in a page-aligned
   block of fixed-size routines:

   | Instruction (address in Z86.SYS.sym) | Patched by | Target block |
   |---|---|---|
   | `ALU0J`..`ALU5J: JP BCORE` / `JP WCORE` | `LD (ALUnJ+1),A` | BCORE (D500h, 16-byte slots), WCORE (D600h, 32-byte slots): ADD OR ADC SBB AND SUB XOR CMP by (op >> 3) & 7 |
   | `G80J`, `G81J`, `G83J` | `LD (G8xJ+1),A` | the same cores, for opcodes 80h / 81h / 83h |
   | `SHB2`, `SHW2: JP SHPG` | `LD (SHB2+1),A` | SHPG (D700h): 16-bit shifts at k*16, 8-bit at 128 + k*16 |

6. **Overlays:** `CPMZ80.BIN` runs at F12Bh-FAF4h and `TERMZ80.BIN` at
   F12Bh-FEB6h, over the end of `Z86.SYS` (`COLD`, F12Bh-F21Fh), which is
   needed only at boot.
7. **Code in data pages:** the serial routines sit in the unused end of
   the register page (D03Eh-D0FAh, with two small tables at D0EBh and
   D0F2h), INT 14h's FDD3000 calls F0h / F1h (`I14X`) after the EALO
   table (D3C0h-D3EFh), their saved settings (`SAVED`, 4 bytes) after the
   EAHI table (D4C0h), and INT 14h's set-up in the unused end of the
   BCORE page (D5A2h-D5FAh). They are reached by CALL / JP from the BIOS and CPMZ80. Disassemble
   the two as separate images at the same address.

## Z80 binaries

### `binaries/z80/BOOT.BIN` (254 bytes)

- Logical sector 0 of the disk (cylinder 0, sector ID 0). The FDD3000 boot
  ROM loads it at **3F00h** and jumps to **3F00h** with interrupts off,
  SP = 3EFFh, the ROM paged in at 0000h-07FFh (the boot sector pages it out
  by writing 5Eh to the drive latch).
- Polled I/O only: WD177x at ports C0h-C3h (status/command, track, sector,
  data), DRQ = bit 7 of port 2Fh, the terminal link on port 2Fh. (Elsewhere
  in Z86.SYS: drive latch E0h; WD2123 serial at 80h/81h, 40h/41h, baud
  registers 10h/11h.)
- Ends by jumping to D0FDh. Contains its own copy of the link send routine
  and the `Non-System disk` text.
- Listing and symbols: `symbols/z80/BOOT.lst`, `BOOT.sym`.

### `binaries/z80/Z86.SYS` (8 736 bytes): the interpreter and BIOS

- Loaded at **D000h** (the file's byte 0 is D000h); entry at **D0FDh**
  (`JP COLD`), from the boot sector.
- Listing `symbols/z80/Z86.SYS.lst`, symbols `Z86.SYS.sym`.

| Range | Contents | Kind |
|---|---|---|
| D000h-D03Dh | REGS: 8086 registers (D000h AX..., D010h segment registers, D018h their bases), interpreter state, a reg8 offset table at D030h | data (variables; see the `equ` names) |
| D03Eh-D0EAh | serial routines (SPRN, SAUXO, SPUT, SAUXI, SGET, SLSTS, SWAIT, SERR, SSET, SSTAT) | code |
| D0EBh-D0FAh | LSMAP (7 bytes), BAUDT (9 bytes) | data |
| D0FBh-D0FCh | padding | data |
| D0FDh-D0FFh | `JP COLD` | code |
| D100h-D1FFh | OPLO: low bytes of the 256 opcode handlers | data (split table) |
| D200h-D2FFh | OPHI: high bytes | data (split table) |
| D300h-D3BFh, D400h-D4BFh | EALO / EAHI: ModR/M 00h-BFh memory-operand routines, low / high bytes | data (split table) |
| D3C0h-D3EFh | I14X: INT 14h AH = 4, F0h, F1h (then padding to D3FFh) | code |
| D4C0h-D4C3h | SAVED: the mode bytes of channels A and B, then their baud codes (then padding to D4FFh) | data |
| D500h-D5FFh | BCORE: 8-bit ALU routines in 16-byte slots, then INC16 / DEC16 / LOGF16, then INT 14h's set-up (I14EXT D5A2h, I14INI D5C9h) | code |
| D600h-D6FFh | WCORE: 16-bit ALU routines in 32-byte slots | code |
| D700h-D7FFh | SHPG: shift / rotate routines in 16-byte slots | code |
| D800h | START: entry into 8086 execution (`COLD` jumps here) | code |
| D83Bh | NEXT: the dispatcher (IX points here) | code |
| D83Bh-EB45h | handlers and helpers, with a few small DW tables (e.g. REPTAB, the REP string handlers) | code, some data |
| EB46h | TRAP: BIOS dispatcher (A = trap number) | code |
| EB61h-EB9Ch | TTAB: trap table, 30 DW entries | data |
| EB9Dh-F12Ah | the BIOS functions, then SKEW (F0F7h, 18-byte interleave table) and variables to F12Ah | code, then data |
| F12Bh-F21Fh | COLD (boot loader), `Disk boot failure`, the names `IO      SYS` and `MSDOS   SYS` | code, then data |

Seeds for code discovery: D0FDh, D800h, D83Bh, EB46h, every entry of the
OPLO/OPHI and EALO/EAHI tables (address = hi*256 + lo), every DW in TTAB
and REPTAB, the BCORE / WCORE / SHPG slots, the serial routines above, I14X,
and the RST 38h handler FDCINT (EDE3h; installed into 0038h at run time
during disk transfers).

### `binaries/z80/CPMZ80.BIN` (2 506 bytes): CPM.COM's Z80 part

- Runs at **F12Bh**; entry `T_CPM` at F12Bh (from trap 1Ch with BP = 0).
  The buffer FAF5h-FEF4h follows it at run time (not in the file).
- Inside CPM.COM it sits at file offset 2FCh (address 03FCh in the .COM)
  behind a 16-byte header: length (2 bytes), then the addresses of NEXT,
  JPHL, PEEKEY, GETKEY, CONOUT, DCSP, ENDBIOS in Z86.SYS (2 bytes each),
  which trap 1Ch compares with its own before copying. After the copy CPM.COM
  reads the CP/M program over this image in 8086 memory.
- Calls into Z86.SYS by absolute address (the symbols in the header and
  others: see `CPMZ80.sym`, which lists both).
- It builds, in a page just above the CP/M program (P), a `JP BDOSE` at
  P+06h, the 8086 stub `CD 21 0F 1D` at P+09h, two FCBs and a DTA, and at
  P+100h a 17-entry CP/M BIOS jump table pointing into BIOSV (F9E5h).
- BDOSE (F2FEh) dispatches BDOS functions through BDTAB (F324h, 41 DW
  entries). LIST, PUNCH, READER and LISTST call the serial routines in
  Z86.SYS's register page.
- Listing `symbols/z80/CPMZ80.lst`, symbols `CPMZ80.sym`.

### `binaries/z80/TERMZ80.BIN` (3 468 bytes): TERM.COM's Z80 part

- Runs at **F12Bh**; entry `T_TERM` at F12Bh (trap 1Ch with BP = 0),
  which dispatches on the 8086's AH through `FTAB` (10 DW entries: INIT,
  SESS, DRAW, RECV, SEND, BRK, LOG, CRC, FLUSH, MODE).
- Inside TERM.COM at file offset C7Bh (address 0D7Bh), behind the same
  16-byte header as CPMZ80.
- Data inside the code: `FTAB`; `CTAB` and `PTAB`, the CSI final byte
  tables (entries: 1 character, then a DW handler; 0 ends them); the reply
  strings `DA100`, `DA52`, `DSROK` (0-terminated); `GRTAB`, 32 bytes of
  ASCII for DEC line drawing 5Fh-7Eh; the variables from `PB` (the
  parameter block INIT copies) to `TERMEND`.
- Two dispatches to watch: `CH0` pushes a return address and a handler
  and does RET into it; `IL0` calls the line routine through `JPHL`.
- Listing `symbols/z80/TERMZ80.lst`, symbols `TERMZ80.sym`.

## 8086 binaries

All MASM 1.10 + LINK 2.00 + EXE2BIN; listings in `symbols/x86/`.

| File | Load | Entry | Notes |
|---|---|---|---|
| `IO.SYS` (332 bytes) | 0040:0000 (linear 0400h) | 0040:0000, `JMP SHORT INIT` | 0003h-002Ch: 14 DOS device entries, each `0F nn CB` (TRAP n / RETF). INIT sets vectors 10h, 11h, 12h, 14h, 16h, 17h, 1Ah to stubs `0F nn CA 02 00` (TRAP n / RETF 2), calls DOS init at 0060:xxxx (`DOSENT`), then loads COMMAND.COM through INT 21h. Drive parameter table `DPT40`. |
| `MSDOS.SYS` (6 190 bytes) | 0060:0000 | its init, called far by IO.SYS | Microsoft's MS-DOS 1.25 kernel (MSDOS.ASM with STDDOS.ASM options). `MSDOS.LST` is the full listing; the source is in Microsoft's repository. |
| `COMMAND.COM` (4 879 bytes) | .COM (DOS sets CS = PSP, IP = 100h) | 0100h | Microsoft's COMMAND 1.17; it relocates its transient part to the top of memory. `COMMAND.LST` has its segments; offsets in the listing are per segment. |
| `FORMAT.COM` (1 628 bytes) | .COM | 0100h (`JMP START`) | Variables right after the jump. Trap `0F 1B` writes a track image built in the buffer after the program (offsets `VEROFF`, `FATOFF` etc. are relative to the label TRACK). |
| `CPM.COM` (3 286 bytes) | .COM | 0100h | 8086 code and data to 03FBh, then the CPMZ80 header and image (Z80 code: data to an 8086 disassembler). Traps `0F 1C`. |
| `EDIT.COM` (4 653 bytes) | .COM | 0100h (`JMP START`) | 0103h: the ASCII signature `EDIT86`, then the editor's state words (BUFS, GAPS, GAPE, TEND, TOP, TOPLN, LINE, LEFT, CCOL, CROW, COLS, NR, W) and MODIF; strings and a 32-entry DW key table `CTAB` (indexed by control code, `JMP CTAB[BX]`) before `START`. Buffers and the text follow the label BUFFERS at the end (not in the file). No traps: console through INT 10h / INT 16h, files through INT 21h FCB calls. |
| `TERM.COM` (6 679 bytes) | .COM | 0100h (`JMP START`) | Variables, the INIT parameter block `PBLK`, FCBs (LFCB log, XFCB XMODEM), the port and baud tables (as MODE.COM), messages; code from `START` (0518h). Traps `0F 1C` (load / call the Z80 part); INT 14h AH = F0h / F1h; INT 21h. From 0D7Bh the Z80 part (Z80 code: data to an 8086 disassembler); at run time the screen copy, ring, log buffer and XMODEM block are over it. |
| `MODE.COM` (1 119 bytes) | .COM | 0100h (`JMP START`) | Variables (CHAN, MODEB, BAUDC), name tables (PORTS: 4 characters + channel; BAUDS: 16 x 6 characters, indexed by baud code; ABAUDS: 6 characters + code) and messages before `START`. Calls INT 14h with AH = F0h / F1h (the FDD3000 calls) and INT 21h; no traps. |

## The disk image

`binaries/disk/MSDOS-FDD3000.DSK` is an **Extended CPC DSK** file
("EXTENDED CPC DSK File\r\nDisk-Info\r\n"): 40 tracks, 1 side, 18 sectors of
256 bytes per track, sector IDs 0-17 stored in ID order, filler E5h.

- Logical sector n (as DOS and the BIOS number them) is track n / 18,
  sector ID `SKEW[n mod 18]`, SKEW = 0 2 4 6 8 10 12 14 16 1 3 5 7 9 11 13 15 17.
- Logical 0: boot sector; 1-2 and 3-4: FATs; 5-12: directory; 13 on: clusters
  of 4 sectors (1 KB), cluster 2 first.
- `binaries/disk/files/` holds every file read back through the FAT,
  including the hidden `Z86.SYS`, `IO.SYS`, `MSDOS.SYS` (identical to the
  copies in `binaries/z80` and `binaries/x86`).
