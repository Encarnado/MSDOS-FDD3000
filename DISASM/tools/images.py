"""Per-image facts for z80dis.py, taken from DISASSEMBLY_GUIDE.md.
Paths are relative to DISASM/."""

PKG = '../'

IMAGES = {
    'BOOT': dict(
        bin='bin/BOOT.BIN', asm='boot.asm', org=0x3F00,
        lst=PKG + 'symbols/z80/BOOT.lst', sym=PKG + 'symbols/z80/BOOT.sym',
        seeds=[0x3F00],
    ),
    'Z86': dict(
        bin='bin/Z86.SYS', asm='z86sys.asm', org=0xD000,
        lst=PKG + 'symbols/z80/Z86.SYS.lst', sym=PKG + 'symbols/z80/Z86.SYS.sym',
        # D0FD JP COLD, D800 START, D83B NEXT, EB46 TRAP, EDE3 FDCINT (RST 38h
        # handler installed at run time); serial routines in the REGS page and
        # INT 14h set-up in the BCORE page are filled in from the .sym.
        seeds=[0xD0FD, 0xD800, 0xD83B, 0xEB46, 0xEDE3,
               # serial routines in the REGS page (guide: D03Eh-D0E0h)
               0xD03E, 0xD042, 0xD048, 0xD062, 0xD067, 0xD085, 0xD08F,
               0xD098, 0xD0A2, 0xD0BF,
               # tail of the BCORE page: INC16 / DEC16 / LOGF16, INT 14h set-up
               0xD580, 0xD58C, 0xD598, 0xD5A2, 0xD5C9],
        split_tables=[(0xD100, 0xD200, 256), (0xD300, 0xD400, 0xC0)],
        word_tables=[(0xEB61, 30), (0xE21D, 12),    # TTAB, REPTAB (guide)
                     # not in the guide's seed list - found by the descent
                     # report: group F6h / F7h / FFh dispatch, via JP JTAB
                     (0xE853, 8), (0xE929, 8), (0xEAD1, 8)],   # G3BT G3WT G5T
        ix_targets=True,         # LD IX,nn loads the dispatcher: nn is code
        dead_code=[(0xE25D, 0xE26E)],   # RADVS: no reference anywhere
        slot_blocks=[(0xD500, 16, 8), (0xD600, 32, 8), (0xD700, 16, 16)],
    ),
    'CPMZ80': dict(
        bin='bin/CPMZ80.BIN', asm='cpmz80.asm', org=0xF12C,
        lst=PKG + 'symbols/z80/CPMZ80.lst', sym=PKG + 'symbols/z80/CPMZ80.sym',
        # T_CPM (trap 1Ch, BP=0); BDOSE (JP at P+06h); BDTAB 41 DW; BIOSV 17 DW
        seeds=[0xF12C, 0xF2FF],
        word_tables=[(0xF325, 41), (0xF9E6, 17)],
        # symbols defined outside the listing: Z86.SYS addresses, and the
        # equates at the head of CPMZ80.ASM (above its ORG)
        extern_syms=[PKG + 'symbols/z80/Z86.SYS.sym'],
        extern_equ_src=PKG + 'project/MSDOS/poc/CPMZ80.ASM',
    ),
}
