# BOOT.BIN — findings (2026-11-08)

Gate: PASS (byte-identical, z80asm). Partition: descent from 3F00h reaches all
222 code bytes of BOOT.lst and nothing else; data = SYSNAM, NSMSG, TRIES (32 bytes).
Image = first 254 bytes of DSK logical sector 0; sector bytes 254-255 = 00h.

1. **Source gloss "head loaded" for latch 5Eh is fiction.** 5Eh = LED off,
   /BOOT=1 (ROM out), DDEN#=0 (MFM), SIDE1#=1 (side 0), drive 0. No latch bit loads a
   head (the latch's bit map); the WD1770 has no HLD output. *verified (bit map).*
2. **Track D never reaches the FDC.** LOAD writes only the sector register. The
   track compare uses the FDC track register (Restore → 0, Step-In u=1 → +1). D is
   bookkeeping only. *verified (code).*
3. **No verify, no settle.** Restore 01h / Step-In 51h with V=0; Read Sector 80h
   with E=0. The FDD3000 boot ROM uses E=1 (8Ch). **Works on real hardware:** the system booted
   on a real FDD3000 on 2026-11-07 (notes/hardware_run.md). One drive tested, so a
   marginal drive's settle time stays the first suspect for a boot that fails at a
   track change.
4. **TRIES is in the loaded sector image** (3FFDh) and decremented in place: 8
   failures per boot, not per sector. Deterministic failures exhaust it.
   *verified.*
5. **Relaxed jumps:** the source's `JR NZ,NOSYS` (3F1E) and `JR NZ,IPL0` (3F91)
   are `JP NZ` in the bytes (project assembler relaxation). *verified.*
6. **NOSYS = CBIOS A1.1 TXBY minus timeouts:** same codes (BYTEON 0Ah, SERVICO
   0Fh, CSTAT 10h, BSTAT 40h, STMSK 50h, MASK 5Fh), no 256-poll echo limit, no
   TXERR 07h. *verified against `ROMS/FDD_Interface/bios_z80asm.asm` TXBY.*

Timing (4 MHz assumed; nothing documents the FDD3000 crystal): LOAD_BUSY_DELAY 91 T
≈ 23 µs; CMD_DELAY 229 T ≈ 57 µs.

7. **Latch bit 7 (IN USE LED) is active low**: 0 = on. Evidence: CBIOS A1.1
   (`ROMS/FDD_Interface/bios_z80asm.asm`) routine `LIGHTOF` does `set LUZ,a` (LUZ =
   7) before `out (HRD),a`, and drive selection does `res LUZ,a`. This matches the
   Shugart convention (all interface lines active low). It **contradicts an earlier reading of the FDD3000 boot ROM**, which had "1 = on" and
   explained the LED "still lighting" at 1Eh: with an active-low bit, 1Eh simply
   means LED on during the boot read. *Provisional* (CBIOS code + naming; no
   hardware observation; the 2026-11-07 hardware run did not record the LED).
   Also found independently in the Z86.SYS BIOS review (`notes/z86_part08_findings.md`).
