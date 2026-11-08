# Real-hardware run — 2026-11-07 (reported by the user 2026-11-08)

The package binaries were run on a **real Timex FDD3000**.

| Item | Result |
|---|---|
| Disk | `binaries/disk/MSDOS-FDD3000.DSK`, written by the emulator tools (not made on the machine) |
| Terminal | TT3000 (user: "I believe") |
| Boot ROM → BOOT.BIN → Z86.SYS COLD → IO.SYS → MSDOS.SYS → COMMAND.COM | worked |
| DOS console tools (DIR, COPY, TYPE, CHKDSK…) | worked |
| EDIT | worked |
| CPM (CP/M program under CPM.COM) | worked |
| PRN / AUX serial | worked (covered by "all but FORMAT") |
| FORMAT | **not exercised** |
| Drive LED during boot | not observed |
| Speed | "slow but bearable for console tools"; no timing taken |

## What this settles

- **Floppy read path on real drives:** the boot sector's Restore/Step-In without verify
  and Read Sector with E=0 (no settle delay), the 2:1 interleave, BIOS READ/WRITE with
  RST 38h end-of-transfer: all work on the drive used. Settle and retry risks
  are not seen in practice. A marginal drive could still differ, so "verified on one
  machine", not "proven".
- **Console link with a real terminal (TT3000):** the CBIOS-derived protocol, PEEKEY/
  STATUS key handling and the 255-poll timeouts work with a real terminal end. The
  PEEKEY 00h–03h phantom-key edge (z86 part 07) was not reported; it stays a latent
  code finding.
- **WD2123 serial set-up and PRN/AUX transfer** work on the real chip.
- **CPMZ80** runs natively on the real Z80 with its files on the DOS disk.

## Still open

- FORMAT and BIOS trap 1Bh (WD177x write-track image), and FORMAT /S: untested on
  hardware.
- Latch bit 7 / LED polarity (boot_findings item 7): unobserved.
- Clock speed (4 MHz assumed everywhere) and real timings.
- Terminal model: TT3000 by recollection.

Claims written before this report are tagged `HW-PENDING` in the 8086 notes and are
resolved against this table.

## Note (2026-11-08)
The run above used the BASELINE build (git 868a965). The floppy-timeout build
that followed (same size; CPMZ80/CPM.COM unchanged) has passed the emulator
suites but not yet run on the real machine.
