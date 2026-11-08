# Z86.SYS part 07 (EB46h-EDDBh: TRAP .. WRSEC) — findings (2026-11-08)

Gate: `python3 tools/z86parts.py check 7` PASS. lint: 0 errors, coverage 89.1 %
(the 4 CRYPTIC warnings are ZF1/ZF0/CF1/CF0, global author names used by part 08:
kept).

Evidence: BIOS.ASM, Z86.SYS.lst / CPMZ80.lst, CBIOS A1.1 `bios_z80asm.asm`
(TXBYTE/TXBY 1045-1122, RXBYTE/RXBY 1124-1199, CONST 302, RDDSK 671, WRDSK 720,
RD256/WR256 640-715), fdd86.py `Link`, fddos.py `trap`, IOFDD.ASM, z86.py.

## Bugs and edge cases

1. **PEEKEY can report a phantom key.** `in a,(COM) / and MASK / cp 04h / ret nz`:
   CP sets carry when A < 04h, so a link value 00h-03h returns CF=1 with A = the stale
   KBUF and KFLAG still 0. T_STAT then says "key ready" (ZF=0, AL = old key) and the
   following INP blocks in CONIN for a real one. Also hits CPMZ80's DIO1 / F_CST /
   B_CONST (they test CF). The source comment `RET NZ ; (NC)` is therefore wrong for
   A < 4. Code: *verified*. Whether a real terminal or an unplugged link ever reads
   00h-03h: *provisional* (fdd86 Link idles at 50h/04h only). Fix in the same 2 bytes:
   `xor 04h` instead of `cp 04h`.
2. **SECTIO's retries never move the head.** Each retry calls SEEK, which returns at
   once when FDCTRK already equals DTRK; so the 10 tries re-read in place. A head/track
   register mismatch is not recovered at this level (CBIOS RD256 also retries in
   place). *verified (code)*; practical effect *provisional*.
3. **Transfer length is the FDC's, not 256.** RDSEC/WRSEC never count (B unset, INI's
   Z ignored); only INTRQ ends them. A 512-byte sector with a matching ID (PC disks use
   IDs 1-9, which DSEC can be) would put 512 bytes at DADDR, beyond DISKIO's
   "buffer < CF01h" guard, possibly over D000h. Same in CBIOS. *provisional (untested)*.
4. **DSTAT is redundant.** SECTIO stores A to DSTAT, decrements DTRY (A untouched) and,
   when the count runs out, reloads DSTAT into A — the value already there. DSTAT has
   no other reader in Z86.SYS or CPMZ80. *verified*.
5. **TRAP n >= 1Eh is a silent no-op**; cpu86.py's `_no_trap` and fddos.py's `trap`
   halt instead (fddos also halts on 00h and 0Fh, which TTAB maps to TNONE). No shipped
   code issues these. *verified*. The bound is build-checked: z86.py asserts
   `TTEND - TTAB == 2*0x1E`.
6. **Disk limits differ from fddos.py:** Z80 checks DX against the fixed NSECT 720
   (fddos: the mounted disk's size) and refuses buffers >= CF01h with AL=0Ch
   (fddos has no such check). Both give AL=8 for DX past the end (Z80 via ERRTAB bit
   10h). *verified*.
7. **DS:BX is a 16-bit add** (B_DS + BX); a buffer past linear FFFFh wraps to low
   memory and passes the CF01h check. Consistent with the interpreter's documented
   "segment wrap not modelled". *verified*.

## Console link vs CBIOS A1.1 (line by line)

| Z86.SYS | CBIOS | Kept | Changed |
|---|---|---|---|
| CONOUT | TXBYTE | retry loop: on failure wait until the link reads 07h, resend from BYTEON | no PUSH DE/BC; CHATMP -> COCHR; final XOR A comes from COSEND |
| COSEND | TXBY | identical instruction sequence: BYTEON until SERVICO (endless), CSTAT nibble + echo, BSTAT nibble + echo, STMSK; 255-poll echo time-outs (C=0, DEC C before test) | literals instead of names (bytes equal) |
| CONIN | RXBYTE | retry loop: on failure wait WHILE the link reads 07h, then ask again | no PUSH BC/DE |
| CIRECV | RXBY | identical: WSTA until STANDBY (endless), 0Fh, CSTAT nibble (AND 50h test) echo raw, BSTAT nibble (bit 6 only) echo raw, AND 7Fh, wait 50h or 07h (endless), answer 50h; 255-poll nibble time-outs | none in bytes |
| LKFAIL | TXERR + RXERR | 07h out, AND A (NZ) | the two identical copies merged |
| PEEKEY/GETKEY/KBUF | CONST | the 04h "key waiting" test | STATUS must return the key, so it is received and held (CONST only answered FF/00) |

- **CBIOS TXBYTE pops crossed** (`push de / push bc ... pop de / pop bc`): CBIOS's
  caller gets BC and DE swapped. Harmless under CP/M; Z86 drops the pushes. *verified
  (CBIOS source)*. The OVERVIEW/README phrase "CBIOS's send and receive routines,
  unchanged" is true of the protocol and time-outs, not of the register saving.
- Time-outs at 4 MHz (crystal undocumented, *provisional*): COSEND echo loop 45 T ->
  ~2.9 ms; CIRECV low nibble 52 T -> ~3.3 ms, high nibble 42 T -> ~2.7 ms.
- The asymmetric abort handshakes (CONOUT waits for 07h, CONIN waits for 07h to go)
  are CBIOS's; their correctness on a real terminal is *provisional*. A key may be
  lost or doubled if the final STMSK exchange aborts (terminal-dependent).
- `ld a,0Fh` in CIRECV is the FDD sending the SERVICO code (CBIOS: bare 0Fh,
  "flag ready"); written SERVICO here.

## Disk upper layer

- RDSEC/WRSEC = CBIOS RDDSK/WRDSK; changes: C = FDCDAT set locally (CBIOS relied on
  PREPARA), IM 1 also in WRSEC. ~50 T/byte vs 32 us/byte MFM. *verified (code)*.
- Write protect: SECTIO returns at once (DOS asks Abort/Retry/Ignore); CBIOS WR256
  prompted on the console (DSKPRT). *verified*.
- ERRTAB maps the highest set bit of 80h (SEEK) / 40h WP / 20h (SELECT) / 10h RNF /
  08h CRC; everything else (04h lost data, 01h bad buffer) -> 0Ch. *verified*.
- On error CX = sectors left, DX = failing sector, BX unchanged. *verified*.
- One relaxed jump: `JR NC,DNRDY` (ECE7h) is `JP NC` in the bytes. *verified*.
- OVERVIEW 2.3 "10 retries, then restore and retry" describes SEEK (part 08); the
  sector layer does 10 in-place tries with no restore between them.

## New equates (this part)
WSTA 06h (CBIOS name), KEYRDY 04h, LINKERR 07h, RDSCMD 80h, WRSCMD A0h (CBIOS names).
Checked against Z86.SYS.sym, CPMZ80.sym, BOOT.sym and parts/ (base and current).
Join note: if another part also defines any of them, keep one.
