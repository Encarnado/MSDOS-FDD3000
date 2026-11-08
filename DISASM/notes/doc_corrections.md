# Corrections for the package documents (found by the disassembly, 2026-11-08)

None of these documents was edited. Each item cites the finding that supports it.

## README.md / OVERVIEW.md
1. **"Not tried on real FDD3000 hardware"** (README intro, OVERVIEW §4): it ran on
   2026-11-07; all but FORMAT worked (`hardware_run.md`).
2. **OVERVIEW §2.2, AF:** "after 16-bit add / subtract / increment / decrement, AF
   comes from bit 11" is wrong for INC/DEC: AF is always 0 there (INC16/DEC16 end in
   RRA). Also "only DAA, DAS, AAA and AAS read AF": PUSHF, LAHF and INT copy it out
   too. (`z86_part01`, `z86_part03`; verified by running both models.)
3. **OVERVIEW §2.3 / poc README, "six IBM PC ROM BIOS interrupts":** there are seven
   (10h 11h 12h 14h 16h 17h 1Ah). (`iosys_findings`)
4. **OVERVIEW §2.6 and CPMZ80.ASM header, "swaps the bottom of memory (where DOS,
   COMMAND and CPM.COM live)":** COMMAND 1.17 is built with HIGHMEM; its resident
   part is at the top, outside the swap. (`cpmcom_findings` 1; COMMAND.LST line 24)
5. **OVERVIEW §2.7, "looks only at rows between the first and last mark":**
   simplified; the exact rule is in `edit_findings` 3.

## DISASSEMBLY_GUIDE.md
6. **Z86.SYS seeds:** add the DW tables G3BT (E853h), G3WT (E929h), G5T (EAD1h),
   reached via JP JTAB, and note that `LD IX,nn` operands are code (RESTORE).
   RADVS (E25Dh-E26Eh) is dead code. (`partition_findings`)
7. **IO.SYS row, "calls DOS init at 0060:xxxx":** exactly 0060:0000. (`iosys_findings`)

## Source comments (project/MSDOS/poc)
8. BOOT.ASM "head loaded" on latch 5Eh: no such latch bit. (`boot_findings` 1)
9. I86.ASM INC16/DEC16 header (AF from bit 11): see item 2.
10. IOFDD.ASM "MEMTOP patched by the loader": nothing patches it. (`iosys_findings`)
11. BIOS.ASM INT 14h header "AL = modem status" holds for AH=3 only. (`z86_part08`)

## Tools
12. `fdd86.py` prints a bad opcode's address one byte low (BC already points at
    it at BADSTOP). (`z86_part02`)

## The TC3256 corpus (ROMDIS)
13. `fdd3000b.asm` HRD_LED "1 = on": CBIOS's LIGHTOF sets bit 7 to put the light
    out, i.e. active low. Provisional until someone observes the LED.
    (`boot_findings` 7)
