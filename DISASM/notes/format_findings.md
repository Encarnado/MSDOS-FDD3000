# FORMAT.COM — findings (2026-11-08)

Gate: PASS (`tools/roundtrip.sh format`, NASM -O0, byte-identical). All
addresses agree with ../symbols/x86/FORMAT.LST; TRACK = 075Ch = end of file.
Instruction lines commented: all of them (431/431), about 90% at intent level.

Hardware status (notes/hardware_run.md): the 2026-11-07 run on a real FDD3000
did NOT exercise FORMAT.  Everything about the write-track path (image, trap
1Bh, /S) is "checked on the emulator against the Python BIOS; not yet run on a
real FDD3000".  The disk layout FORMAT produces is the one mkfat.py wrote for
the disk that did boot on hardware: indirect support for the layout only.

1. **Track byte budget matches OVERVIEW 2.5.** Image = 32 + 18 x 332 = 6008
   (TRKLEN); each sector has 2 F7h bytes, each written as 2 CRC bytes, so the
   disk gets 32 + 18 x 334 = 6044 of 6250 bytes (300 rpm, 250 kbit/s MFM).
   Slack 206 bytes (3.3%) = gap 4, fed as 4Eh by T_FMT until the index pulse.
   *verified (arithmetic, code, z86sys T_FMT).*  Whether a real drive's speed
   keeps within it: *provisional — not yet run on a real FDD3000.*
2. **Short gaps, no index address mark.** Gap 1 is 32 x 4Eh with no
   F6h F6h F6h FCh IAM; gap 2 = 22 (standard); gap 3 = 16 (IBM uses 54 for
   256-byte MFM).  The WD177x does not need the IAM.  A 16-byte gap 3 leaves
   little write-splice margin when a sector is later rewritten at a slightly
   different speed.  *provisional — emulators have no rotation; not yet run on
   a real FDD3000.*
3. **Special bytes:** only F5h (A1h with missing clock, CRC preset) and F7h
   (2 CRC bytes) are used; F6h (C2h) is not.  FEh/FBh follow three F5h as the
   ID / data address marks; data fill E5h.  *verified (code + source).*
4. **The interleave is not in the image.** IDs are written 0..17 in physical
   order (test_fdd86.py checks this); the 2:1 interleave comes from Z86.SYS's
   SKEW mapping logical e -> ID 2e / 2e-17.  *verified.*  The plan's phrase
   "18 sectors with the 2:1 interleave SKEW" should be read that way.
5. **/S does not guarantee bootability.** boot.asm loads Z86.SYS from
   cluster 2 and COLD loads IO.SYS / MSDOS.SYS, all contiguously without the
   FAT.  PUTSYS relies on DOS allocating an empty disk in order; if
   MARKBAD marked clusters inside the system span (track 1 = clusters 3-7, in
   Z86.SYS's 2-10; tracks 2-5 hit IO.SYS / MSDOS.SYS), DOS skips them, the
   files fragment, the disk will not boot, and FORMAT still prints "System
   transferred".  *verified by code; no test covers it.*
6. **Dead store in SETFCB:** `MOV WORD PTR [FCB+14],1` is undone by open and
   create, which set the record size to 128 (MSDOS.LST 03E1h, 0405h).  GETSYS
   and PUTSYS rewrite it after the call, so behaviour is right.  *verified.*
7. **MASM padding:** REPORT ends `JMP DNUMM` (EB 10) + NOP — MASM reserved 3
   bytes for a forward jump.  *verified (bytes + listing).*
8. **Default drive is the current drive.** `FORMAT` with no drive formats the
   drive it was run from (after the "Insert new diskette" prompt).  Design, as
   in DOS 1.x FORMAT.  *verified.*
9. **Error mapping:** trap 1Bh and INT 26h AL 0 -> "Write protect error", 2 ->
   "Drive not ready", others -> "Format failure"; a track-0 read-back failure
   -> "Format failure" without looking at AL.  T_FMT checks only write protect
   at the end (no lost-data check); the INT 25h read-back catches the rest.
   *verified (code + z86sys).*
10. **INT 25h / 26h leave the flags on the stack** (`POP BP` after each):
    MSDOS.LST points INT 25h / 26h at IO.SYS BIOSREAD / BIOSWRITE, which are
    `TRAP 7 / RETF` and `TRAP 8 / RETF` (IOFDD.LST 0015h).  *verified.*
11. **Memory test** `[6] >= TRACK+BUFEND+256` = 8CD4h (36 052 bytes, README's
    "about 36 KB").  GETSYS caps the four files at SYSMAX = 22 528 bytes (they
    take 22 clusters on the disk in the test).  *verified.*
12. **Edge:** the switch scanner consumes the character after any "/", so
    "//S" misses /S; any switch other than S is silently ignored.  Trivial.
    *verified.*
13. **MARKBAD:** a track touches 5 or 6 clusters (e.g. track 10: 43-48,
    6144 bytes, as tested); track 39's last would be 178 and is clipped at
    MAXCLUS; logical 717-719 belong to no cluster.  *verified.*

Cross-volume: z86sys T_FMT accepts drives 0-3 (its NDRIVE = 4), FORMAT
restricts to 0-1 (IO.SYS's two drives) — consistent, not a bug.  Trap 1Bh is named
TRAP_FMTTRK, per the 8086-volume TRAP_* set (iosys.md; 1Ch TRAP_CPM, 1Dh
TRAP_DOSRET); z86sys.asm names only the handler, T_FMT.

## Fixed 2026-11-08
- 5 (/S never checks the system files are contiguous): FIXED - PUTSYS
  checks that the clusters of Z86.SYS, IO.SYS and MSDOS.SYS from cluster 2
  are free in the new FAT and otherwise prints "Bad track in the system
  area: system not transferred". test_fdd86.py group 5: track 1 bad -> refused.
