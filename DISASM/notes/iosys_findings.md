# IO.SYS — findings (2026-11-08)

Gate: PASS (byte-identical, `nasm -O0 -f bin`, `tools/roundtrip.sh iosys`).
Every byte agrees with `symbols/x86/IOFDD.LST` (0000h-014Bh). Partition: code
0000h-00D1h (entries, INIT, COMERR, the 7 stubs), data 00D2h-014Bh (ROMTAB,
MEMTOP, DOSENT, INITTAB, DPT40, BADCOM, FCB). No numbered locals, so no renames;
the `db 0FH,n,0CBH` entries and stubs are now spelled `TRAP TRAP_xxx` / `retf` /
`retf 2` (same bytes). Real-hardware status from `notes/hardware_run.md`.

1. **The 14 entries are DOS 1.25's SEGBIOS, trap n = entry n at offset 3n.**
   STATUS 01, INP 02, OUTP 03, PRINT 04, AUXIN 05, AUXOUT 06, READ 07, WRITE 08,
   DSKCHG 09, SETDATE 0A, SETTIME 0B, GETTIME 0C, FLUSH 0D, MAPDEV 0E; offsets
   03h..2Ah match MSDOS.LST 199-251 (BIOSSTAT..BIOSMAPDEV). Flags returned
   (z86sys.asm handlers): STATUS ZF (ZF=0 + AL = key, not consumed); READ / WRITE
   CF (CF=1: AL = DOS code, CX = sectors left); DSKCHG AH=0 + CF=0; all others
   set no flags. MAPDEV is TNONE: AL (device number) back unchanged = identity
   mapping, which is what DOS's FATREAD needs for a single format.
   *verified (code + IOFDD.ASM + MSDOS.LST + z86sys TTAB); entries for console,
   disk, PRN, AUX verified on real hardware (hardware_run.md).*
2. **Plain RETF suffices for the device entries; RETF 2 is needed for the ROM
   stubs.** DOS reaches the entries by far CALL (no FLAGS pushed), so RETF returns
   the trap's flags as they are. A PC program reaches the stubs by INT (FLAGS, CS,
   IP pushed): IRET would reload the caller's old FLAGS over ZF / CF; RETF 2 pops
   CS:IP and discards the FLAGS word (z86sys O_RETFN: SP += imm16), the IBM BIOS
   convention. Side effect: IF / TF stay cleared after such a call (bookkeeping
   only on the interpreter). *verified (code + z86sys O_RETFN / DOINT).*
3. **INT 25h / 26h land on the same RETF entries.** DOSINIT (MSDOS.LST 3992-3998)
   points vectors 25h / 26h straight at 0040:0015 / 0040:0018. Reached by INT,
   the RETF leaves the FLAGS word on the stack: exactly DOS 1.x's documented
   INT 25h/26h contract (the caller POPFs). Not an IO.SYS bug; worth knowing
   when reading FORMAT.COM's INT 25h/26h use. *verified (MSDOS.LST).*
4. **INITTAB / DPT40 decoded against DOSINIT.** NUMIO 2; units 0, 1 (DRVNUM, also
   the READ/WRITE AL and the FATSIZTAB index, so two separate FAT buffers); DPT =
   SECSIZ 256, 4 sec/cluster, 1 reserved, 2 FATs, 64 entries, 720 sectors. DOS
   derives DIRSEC 8, FATSIZ 2 (trial 1 -> 2, trial 2 -> 2: converged), FIRDIR 5,
   FIRREC 13, MAXCLUS 177 — the constants Z86.SYS hard-codes for COLD and mkfat.py
   writes, and OVERVIEW 2.5's table. *verified (arithmetic against FIGFATSIZ /
   FIGMAX, MSDOS.LST 4034-4055).*
5. **Source comment wrong: MEMTOP "(patched by the loader)".** COLD (z86sys
   F12Ch) copies IO.SYS unchanged and patches nothing; no build script (z86.py,
   build.py, fddos.py) writes offset 00E7h. DOS always gets 0D00h paragraphs
   (= GTOP D000h, = fddos.py MEMTOP). *verified (code + scripts grep).*
6. **No CLD in INIT.** SETROM's STOSW counts up only because COLD leaves DF = 0
   (FLAGHI = 0). Harmless with this loader; a different loader would break it.
   *verified (code).*
7. **Stack at 0000:0400h** grows down into vectors F8h-FFh (unused). COLD left
   SS:SP = 0:0; INIT fixes it before any push. *verified.*
8. **COMMAND.COM loader = SCP's method** (Set DTA 100h, open FCB "A:COMMAND.COM",
   RR = 0, RECSIZ = 1, Block Read CX = [6] records, start at seg:0100h with SP =
   5Ch over a 0 word). The line-for-line SCP comparison could not be made here: no
   SCP I/O-system source is in the workspace. *code verified; SCP identity
   provisional (author's claim).*
9. **Edge: Block Read count is [6] = bytes in the segment from offset 0**, but the
   DTA is offset 100h, so the request may reach 256 bytes past ENDMEM. DOS
   trims only at a 64K wrap. Harmless (COMMAND.COM 1.17 is a few KB; the read
   stops at EOF). Inherited from the SCP method. *verified (code + SETMEM,
   MSDOS.LST 3412-3425).*
10. **Error checks:** COMERR on open failure (AL <> 0), zero records read (CX = 0),
    or AL bit 0 clear after the read: AL = 0 (file filled the request: refused as
    too big) or 2 (DTA wrap). AL = 1/3 (EOF reached) is success. COMERR prints
    via AH=09h and spins in STALL (no HLT). *verified (code + BLKRD / SETFCB,
    MSDOS.LST 1453-1484, 1988-2001); never exercised by tests or the hardware
    run.*
11. **Unserved ROM vectors stay 0000:0000.** 13h, 15h, 18h, 19h (and the rest)
    have no stub; COLD zeroed them, so a program calling one jumps to linear 0
    (the divide-error vector's bytes). Only matters for PC-DOS programs beyond
    those tested (DEBUG, CHKDSK). *verified (code); consequence not tested.*
12. **Doc count wrong: "six" ROM BIOS interrupts** in OVERVIEW.md 2.3 ("six IBM PC
    ROM BIOS interrupts") and poc/README.md ("its 6 PC ROM BIOS interrupts"); the
    code and both docs' own tables have seven (10h 11h 12h 14h 16h 17h 1Ah).
    *verified.* Cross-volume: docs only.
13. **DISASSEMBLY_GUIDE says DOS init "at 0060:xxxx"**: it is exactly 0060:0000
    (DOSENT dw 0, DOSSEG; MSDOS.SYS starts with JMP DOSINIT). *verified.*

Real hardware (hardware_run.md, 2026-11-07): boot chain through INIT, DOSINIT and
the COMMAND.COM load worked on a real FDD3000 + TC2048 / TC2068; console tools, EDIT, CPM,
PRN/AUX worked. No item above remains HW-PENDING; COMERR and the unserved-vector
edge are simply untested anywhere.
