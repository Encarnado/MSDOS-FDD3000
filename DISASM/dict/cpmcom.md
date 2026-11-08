# cpmcom — dictionary (volume 6, CPM.COM)

Renames (cryptic numbered locals) and new equates/labels in asm/cpmcom.asm. All other
labels (BEGIN BASE DRIVE STGOFF PFCB PARMS FCB1 FCB2 TAIL USEMSG NFMSG BIGMSG VERMSG START
PROG OPEN NOTFND USAGE TOOBIG MSG CHKSZ SKIP SKIPNM TCOPY TAILX OPENP STKTOP Z80 STAGE)
and PSIZE are the author's (CPM.COM.sym), unchanged.

## Renames

### SKIP_NEXT — step past one leading blank/TAB of the DOS tail
- class: routine (loop label)
- addresses: cpmcom 0316
- aliases: SKIP1 (source)
- status: verified (code + CPM.ASM)

### TAIL_START — the arguments begin: store the CP/M tail length, start the copy
- class: routine (label)
- addresses: cpmcom 032A
- aliases: TAIL0 (source)
- status: verified (code + CPM.ASM)

### TCOPY_STORE — store one (upper-cased) tail character
- class: routine (loop label)
- addresses: cpmcom 033C
- aliases: TC1 (source)
- status: verified (code + CPM.ASM)

## New labels (header at 03FCh)

### Z80_LEN — header word 0: length of the Z80 code (09CAh = 2506)
- class: variable
- addresses: cpmcom 03FC (= Z80 = STAGE)
- status: verified (code + Z86.SYS T_CPML + z86.py cpmz80())
- notes: assembled as `Z80_CODE_END-Z80_CODE`, so it follows the incbin.

### Z80_SYMS — header words 1-7: the Z86.SYS addresses CPMZ80 was built against
- class: table
- addresses: cpmcom 03FE-040B
- status: verified (values = Z86.SYS.sym)
- notes: NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS, BIOS.ASM CPMSYM's order;
  T_CPML compares the 14 bytes and refuses a mismatch (CF=1).

### Z80_CODE / Z80_CODE_END — the CPMZ80 image (incbin bin/CPMZ80.BIN, volume 3)
- class: table
- addresses: cpmcom 040C-0CD5 (file offsets 030C-0CD5)
- status: verified (cmp with bin/CPMZ80.BIN)

## New equates

### TRAP_CPM — 1Ch, BIOS trap: load (BP ≠ 0) or run (BP = 0) the Z80 part
- class: constant
- status: verified (Z86.SYS TTAB / T_CPML)
- notes: same pattern as iosys.asm's TRAP_* names.

### TRAP_DOSRET — 1Dh, BIOS trap: end of a DOS call started by CPMZ80 (stub CD 21 0F 1D)
- class: constant
- status: verified (Z86.SYS T_RET)
- notes: not issued by CPM.COM's 8086 code; defined for cross-volume naming.

### PSP_TOP / PSP_FCB1 / PSP_TAILLEN / PSP_TAIL — PSP offsets 02h, 5Ch, 80h, 81h
- class: constant
- status: verified (MSDOS.LST SETMEM; COMMAND.LST)
- notes: PSP_TOP is MEMSIZ under COMMAND 1.17H: the start of COMMAND's resident part.

### FCB_EXT / FCB_RECSIZ / FCB_SIZE / FCB_SIZEHI / FCB_RR — DOS 1.25 FCB offsets 9, 14, 16, 18, 33
- class: constant
- status: verified (CPM.ASM's PFCB+n expressions; MS-DOS 1.25 FCB)

### NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS — Z86.SYS addresses (D83B EB60 EBF6 EC13 EC21 F12A F12C)
- class: constant
- status: verified (../symbols/z80/Z86.SYS.sym)
- notes: author's names, as in cpmz80.asm; used only in the header.
