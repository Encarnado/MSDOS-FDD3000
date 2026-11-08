# Z86.SYS part 08 (EDDCh-F220h: FDCCMD to BIOSEND) - findings (2026-11-08)

Gate: `python3 tools/z86parts.py check 8` PASS. lint: 0 errors, 2 warnings
(HOOK38, SAV38: author globals, kept). Comment coverage 85.5% of 495
instruction lines.

## Design (verified, code + BIOS.ASM / CBIOS A1.1)

1. **The disk interrupt is borrowed from the 8086's vector table.** Z80 0038h
   (RST 38h, IM 1) = 8086 linear 0038h = INT 0Eh vector (0Eh x 4): offset and
   low segment byte. HOOK38 saves the 3 bytes in SAV38 and writes `JP FDCINT`;
   UNHOOK (DI first) puts them back. The guest owns the vector table (COLD
   zeroes it; programs may set INT 0Eh via INT 21h), so 0038h is only usable
   while the 8086 is stopped in a trap. Outside disk calls interrupts are
   off throughout (START does DI). Lineage: CBIOS SAVJMP / PUTJMP / BUFINT.
2. **FDCINT unwinds the waiting loop.** `POP AF` drops the address the
   interrupt pushed (FDCW / RD1 / WR1), RET goes to the caller of FDCCMD /
   RDSEC / WRSEC with A = status AND 5Ch. No EI: interrupts stay off after.
   The transfer loops cannot end any other way. CBIOS INTRPT byte for byte
   except the mask.
3. **EI before OUT in FDCCMD**: EI's one-instruction delay means the command
   (whose write also clears INTRQ) is out before any interrupt can be taken.
   FHOME (polled) and T_FMT's last status read clear INTRQ, so no stale INTRQ
   reaches the next EI.
4. **SELECT keeps one track register for four drives** in TRKTAB (saved only on
   a drive change); unknown (FFh) -> Restore; failed Restore -> CURDRV = FFh,
   A = 20h (DOS 2, not ready). SEEK skips the command when FDCTRK already =
   DTRK; otherwise Seek-verify 15h, Restore on failure, 10 tries (STRY,
   separate from SECTIO's DTRY: worst case 10 x 10).
5. **T_FMT** swaps RESCMD to 01h (Restore without verify: a blank disk has no
   IDs) around SELECT and restores 05h immediately; the flags of SELECT survive
   because only LDs follow. Seek 11h (no verify), then Write Track FEh polled
   with interrupts off (FDCCMD left them off). Image FMTLEN = 32 + 18 x 332 =
   6008 bytes (FORMAT.ASM MKTRACK, decoded in the header), then 4Eh until the
   index pulse ends the command.
6. **T_CPML header contract** (z86.py cpmz80()): length word + the 7 addresses
   NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS, compared byte by byte with
   CPMSYM; then LDIR to ENDBIOS over COLD. BP = 0 jumps to ENDBIOS (T_CPM) with
   TRAP's frame on the stack. T_RET (1Dh) restores SP from DCSP and RETs out
   of DOSCALL; DCSP = 0 makes a stray 1Dh a no-op.
7. **COLD** = CBIOS serial set-up (SIOTAB 02h+0Ch+00+00+80h = mode 8Eh, baud
   code 08 = 1200), zero 0000h-03FFh, directory sector to C000h, entry 1 must
   be IO.SYS (< 3 sectors, to 0400h), entry 2 MSDOS.SYS (< 41 sectors, to
   0600h), contiguous from the first cluster (no FAT), loaded through T_READ;
   regs zero, CS = DS = 0040h, IP = 0, F' = 0 with A' = 1 (PF = 0). SS:SP =
   0:0 is fine because IOFDD.ASM INIT sets SS/SP first.
8. **CFILE's stack trick:** pushes BC, AF, HL; `POP BC` later takes the pushed
   AF so B = the sector limit; the last `POP HL` is the load address, falling
   into CLOAD.

## Wrong or misleading source comments

9. **LATCHC "head loaded (bit 7 low)"**: no latch bit loads a head
   (boot_findings #1). Bit 7 is CBIOS's LUZ (light: `res` = on in LIGHT, `set` =
   off in LIGHTOF); this BIOS follows CBIOS. **Conflict:** an earlier reading
   of the FDD3000 boot ROM says 1 = on, the opposite of CBIOS. Provisional;
   boot.asm's first "5Eh = LED off" followed that reading (since corrected).
10. **T_I14 header "AL = modem status"**: true only for AH = 3; for AH = 1 AL
    is the byte sent (unchanged), for AH = 2 the byte received. Verified.
11. **FDCINT mask differs from CBIOS**: CBIOS INTRPT keeps 9Ch (bit 7); on a
    WD1770 bit 7 is Motor On, not Not Ready, so 5Ch (write protect instead)
    is the sound choice. What CBIOS's mask did on hardware: provisional.

## Edge cases / bugs (verified by reading; never observed)

12. **Buffer over 0038h-003Ah clashes with the hook**: a read there overwrites
    `JP FDCINT` mid-transfer (INTRQ then jumps into data) and UNHOOK writes the
    old vector bytes over the data; a write sends C3 E3 ED. DISKIO / T_FMT check
    only the top of memory. No DOS 1.25 path reads to linear 0000h-00FFh.
13. **FDCCMD has no timeout** (`JR FDCW` forever). Whether a WD177x always ends
    a Type I command with no disk / no index pulses: provisional.
14. **T_FMT ignores lost data** (only bit 6 tested); FORMAT.COM's INT 25h
    read-back covers it (verified, FORMAT.ASM).
15. **Trap 1Ch with BP = 0 before a load runs COLD** (still at ENDBIOS): a
    full DOS reboot. CPM.COM never does it.
16. **CFILE accepts size 0** (loads nothing, then starts garbage). Only the
    low size word is used (fine: limits are 512 B / 10 KB).
17. **INT 10h divergences from a PC** (all as fddos.py): AH 09h/0Ah move the
    cursor (CONOUT); AH 06h/07h AL = 0 clears the whole screen, ignoring the
    window; AL <> 0 scroll ignored; AH 03h returns CX = 0607h (CGA shape) while
    AH 0Fh reports mode 7.
18. **Divergences from fddos.py**: INT 17h reads channel A DSR (90h / 10h) where
    fddos always says 90h; INT 1Ah counts +1 per call (first call 0) where fddos
    returns host time; AH = 1 (set ticks) ignored.
19. **Clock** frozen at the last SETDATE / SETTIME (boot: 1-1-80 0:00).
20. **T_FMT `JP NC,DNRDY`** is `JR NC` in BIOS.ASM, relaxed (D2h in the bytes).

## Notes

- The CPMZ80.ASM header and its equates (PBDOS..NBUF) appear after BIOSEND
  because z86.py assembles I86+BIOS+CPMZ80 as one text; they emit no bytes.
- Timeouts for INT 14h/17h (HL = FFFFh polls): ~1.6 s SPUT, ~2.3 s SGET at an
  assumed 4 MHz (T-state counts of the SWAIT loops). Provisional.
- WTKCMD FEh "as FORMAT 2.0" rests on the source comment only.

## Fixed 2026-11-08
- FDCCMD's endless wait: FIXED (timeout -> FDTOUT, "not ready"); the RST 38h
  design is unchanged. FORMAT TRACK's write-track loop stays untimed
  (documented residual); the seek before it is timed.
