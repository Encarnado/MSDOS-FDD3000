# CPMZ80.BIN — findings (2026-11-08)

Gate: PASS (byte-identical, z80asm). The bytes of `../symbols/z80/CPMZ80.lst` equal
bin/CPMZ80.BIN (2506 bytes). The image equals CPM.COM from file offset 30Ch to its
end. The 16-byte header at 2FCh (09CAh, D83B EB60 EBF6 EC13 EC21 F12A F12C) matches
NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS in Z86.SYS.sym. The skeleton was the
source line for line, so no source comment was missing. Comment coverage 89.5%
(lint), 0 errors. 51 numbered locals were renamed; all other labels are the author's.

## Design points confirmed (code + source)

1. **BDOSE switches stacks.** It saves the program's SP and runs every handler on
   the trap-1Ch frame's Z80 stack (SHIMSP, above CFFFh). The program's stack can be
   anywhere in the TPA, including the bottom 0000h-DOSLEN that every DOS call swaps
   out. *verified.*
2. **Nothing touches the program's memory while DOS is swapped in.** FCB, record and
   search data pass through P (P+10h FCB, P+38h search FCB, P+60h DTA) or BUF
   (FAF6h). Every program-side copy (TOSCR, DMADTA, FBACK, DIRENT, DTADMA) runs
   before XCHGD-in or after XCHGD-out. *verified.*
3. **DOSCALL/T_RET.** DOSCALL stores SP in DCSP and builds the 8086 state from
   CPM.COM's saved REGS (so AL, BP, SI, DI, DF and IF are CPM.COM's), with
   CS=DS=ES=SS=P>>4, SP=0200h, IP=0009h. It then jumps to NEXT. The stub at P+09h,
   `CD 21 0F 1D`, does INT 21h and then trap 1Dh. T_RET reloads SP from DCSP, clears
   DCSP and RETs to DOSCALL's caller, and the interpreter's frames are abandoned.
   A stray trap 1Dh while DCSP is 0 does nothing. *verified (BIOS.ASM T_RET).*
4. **XCHGA/XCHGD swap 8 bytes per turn and test BC only at the 8th LDI.** Both lengths
   must therefore be multiples of 8. They are multiples of 16 (BASE = CS*16, STAGE
   rounded to a paragraph). Any other length would make the swap run through 64 KB.
   *verified.*

## Code/comment disagreements and edge cases

5. **The source says "S1 stays the program's own", but byte 13 still feeds the
   arithmetic.** FPOS and FBACK read bytes 12-13 as one 16-bit block number, so S1 is
   the high byte. Multiplied by 128 modulo 64K, an even S1 disappears (PIP's 7Ch is
   even), but an odd S1 adds 32768. FBACK then sets RC to 0 and the buffered read and
   write positions are offset. POSTO/SETPOS (random reads through BUF) write 0 into
   the program's byte 13. Latent. *verified (code reading; not run).*
6. **A random-access IX/IY/AF' hazard.** File calls that reach DOS lose IX (set to
   NEXT), AF' (set to the 8086 flags) and IY (TOSCR, SETRS, PADZ and FBACK use it).
   A read served from BUF keeps all three. CP/M 2.2's 8080 BDOS cannot touch them,
   so a Z80 program that keeps them across BDOS calls fails only sometimes. BC', DE'
   and HL' survive (there is no EXX in the interpreter, the BIOS or here). *verified
   (code); no failing program has been identified.*
7. **The drive byte stays 0, and DOS CLOSE does not flush.** MS-DOS 1.25's CLOSE
   (MSDOS.LST 1046-1058) takes the physical unit as byte 0 minus 1 = FFh, so it
   never matches BUFDRVNO and skips writing back its dirty sector buffer. GETFILE
   still finds the entry through CURDRV, so the directory is updated. The sector
   reaches the disk at the next buffer reuse or at CPM.COM's final DOS 0Dh (DSKRESET
   writes DIRTYBUF). Read and write are not affected: SETUP picks the drive from
   DEVID (byte 24), which TOSCR/FBACK carry through. If the disk is changed after a
   close and before that point, the last sector could be lost. *provisional (read
   from the DOS listing; not run).*
8. **F_FCB's handling of 33/34/40 is vestigial.** F_RRND and F_WRND route only R2≠0
   to F_FCB, and DOS rejects such a record before it moves any data. DMADTA for a
   write, PADZ, DTADMA and the F_FCB_RDERR/F_FCB_WRERR code mapping never act on
   data. `LD C,33` in F_RRND is redundant because C is already 33. *verified.*
9. **BDOS 6 with E=FEh returns console status.** That is CP/M 3 behaviour. Under
   CP/M 2.2, FEh is an ordinary character, and a program here cannot output it
   through BDOS 6. *verified.*
10. **BDOS 14 to a missing drive.** MS-DOS SELDSK (MSDOS.LST 2731) ignores a DL that
    is ≥ NUMDRV, but CPDSK and (0004h) take the new value anyway. BDOS 25 then
    reports a drive DOS is not using, and dr=0 FCBs go to DOS's actual drive. CP/M
    would stop with a Select error. *verified (code + DOS listing).*
11. **Search results.** Each file gives one directory entry: EX=0, RC = min(records,
    128), allocation all zero, slot 0. A file larger than 16 KB looks like a single
    16 KB extent and never gets more entries. Drive '?' just means the default drive.
    *verified.* (The README reports that CP/M returns slot 1 where this returns 0.)
12. **DIRENT after an open.** The source claims CP/M's BDOS leaves the directory
    record at the DMA after an open as well as after a search. CP/M 2.2 copies it
    for search (dir_to_user); for open it was not established here. *provisional.*
13. **DPB SPT = 72.** An FDD3000 DOS track is 18×256 = 36 records. DSM 175, DRM 63
    and CKS 16 do match the DOS disk. Only STAT shows SPT. ALLOCV (23 bytes) is never
    set, so STAT reports the whole disk free. *verified (arithmetic).*
14. **RC goes stale inside BUF.** FNEXT advances CR and EX but not RC. After a
    buffered read crosses an extent, RC stays the old extent's until the next DOS
    refill. *verified.*
15. **Deferred-write hazards.** (a) FERR is reported at the next write (code 2, and
    that write is dropped) or the next close (FFh), whichever file that is. (b) At
    FLUSH, FBACK writes into BFCB's memory, which the program may since have reused if
    it abandoned the FCB without closing it. (c) If the program closes a copy of the
    FCB, DOS gets the size from before the pending records went out. (d) A FLUSH
    error during CPEXIT is not reported. *verified (code reading).*
16. **Console editing compared with CP/M 2.2.** BDOS 1 echoes only characters ≥20h
    and CR (CP/M also echoes LF, TAB and BS) and does not handle ^S or ^P. BDOS 10
    rubs out with BS-space-BS, stores control characters raw, and treats ^C as warm
    boot only on an empty line. Rubbing out a TAB backs up one column. *verified
    (code); CP/M behaviour from DRI's documented BDOS.*
17. **Trap 1Ch's build check is incomplete.** The header covers 7 addresses. The REGS
    fields (D000h-D023h) and SPRN, SAUXO, SAUXI and SLSTS (D03Eh-D085h) are also
    called by fixed address but are not checked. *verified.*
18. **Zero fill (BDOS 40)** is mapped to an ordinary random write. Records skipped
    over hold whatever was in the newly allocated clusters. *verified (code);
    DOS 1.25 does not clear clusters, from the listing.*

## Side note, outside this volume

The author's notes disagree about where COMMAND's resident part sits. CPMZ80.ASM's
header and the CPM.ASM register comment put it below SWLEN, inside the swap. The
README ("left alone") and CPM.ASM's CHKSZ comment ("above TOP") put it elsewhere.
~~In MS-DOS 1.x the resident part follows DOS… That favours the first reading.~~
**Resolved by the cpmcom volume (verified):** this COMMAND 1.17 is built with
`HIGHMEM EQU TRUE` ("Run resident part above transient (high memory)", COMMAND.LST
line 24; banner "1.17H"). The resident part sits at the top, above the memory size
in PSP offset 2, so the swap never covers it. The README and CHKSZ are right;
CPMZ80.ASM's header and OVERVIEW 2.6 are wrong. Comments in cpmz80.asm corrected.
