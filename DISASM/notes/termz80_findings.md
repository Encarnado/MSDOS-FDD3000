# TERMZ80.BIN — findings (2026-11-08)

Gate: PASS (byte-identical, z80asm). The bytes of `../symbols/z80/TERMZ80.lst` equal
bin/TERMZ80.BIN (3468 bytes). The image equals TERM.COM from file offset C8Bh to the
end of the file. The 16-byte header at C7Bh (0D8Ch, D83B EB4D EBE3 EC00 EC0E F12A F12C)
matches NEXT JPHL PEEKEY GETKEY CONOUT DCSP ENDBIOS in Z86.SYS.sym. Lint: 0 errors,
92.8% comment coverage. 8 CRYPTIC warnings are left on author names that carry meaning
(EM8, PAR0-2, DA100, DA52, G0, G1). 126 numbered locals were renamed (dict/termz80.md).
TERM.COM embeds the image as bytes and refers to none of its names. test_term.py reads
RHEAD, RTAIL, LOST, TERMEND and ENDBIOS by name, and all of them are kept.

Hardware: João's README (../project/MSDOS/poc/README.md, TERM section, ~line 731)
records an interactive TERM session against PuTTY tried on a real FDD3000 (his build,
before the merge; serial, XON/XOFF or RTS/CTS). Its "Not known: ... anything on real
hardware" (~line 801) refers to the speed measurements. XMODEM, logging and the timing
figures are emulator results. **This merged build has not been run on real hardware.**
Timings below are T-state counts at the schematic's 4 MHz, not measurements.

## Code partition (partition_findings.md style)

Descent seeds: T_TERM; the 10 DWs of FTAB; every DW of CTAB (26 char+DW pairs) and
PTAB (2); and ICHS / DCHS / ECHS plus CH_REDRAW (src: CH1). CH_DISPATCH (src: CH0)
reaches these with `LD HL,handler / LD DE,CH_REDRAW / PUSH DE / PUSH HL / RET`. With
those seeds everything is reached and there is no dead code. Data: FTAB, CTAB, PTAB,
DA100, DA52, DSROK, GRTAB, and the variables PB..SUM (FE72h-FEB7h). IL/DL's indirect
call goes through JPHL to SHDN/SHUP, which are also called directly.

## Design points confirmed (code + source)

1. **RXPOLL in every wait.** The WD2123 holds one received byte. At 19 200 baud the
   next byte arrives 2 083 T later and overwrites it. These all call RXPOLL: TSEND's
   endless BYTEON wait, TOUT's abort wait, SERPUT, KEYOUT's ESC wait, HOLD, ENSURE,
   SESS, DRAWR's blank scan (every 16 cells), MVF/MVB (between 32-byte pieces of 672 T),
   SHUP/SHDN and PUTCH. TSEND's echo waits (255 polls, about 2.9 ms) are not polled,
   just as COSEND's are not. *verified.*
2. **The ring** is 2 KB, indices masked to 11 bits, and one slot stays empty
   (capacity 2047). The host is stopped at 1024 (HIWAT = 4 pages) by STOP, from inside
   RXPOLL, and let go below 256 (LOWAT = 1) by SESS. The menu and a full log stop it
   too, through HOLD (STOPF and HOLDF). TXQ is a one-byte queue that RXPOLL sends when
   TxRDY and CTS are both set. A later XON replaces an XOFF that has not gone out yet.
   *verified.*
3. **RXPOLL's EXX is safe.** No EXX occurs anywhere in Z86.SYS: the interpreter keeps
   only AF' (the 8086 flags) in the alternate set, and TRAP saves IX and BC itself.
   *verified (grep z86_interp.asm, z86_bios.asm).*
4. **TSEND is COSEND (CBIOS TXBY) plus a poll.** It uses the same codes, the same
   255-poll echo time-outs and the same LINKERR abort. TOUT is CONOUT's retry. The
   image imports CONOUT's header address but never calls it. *verified.*
5. **The Timex terminal is driven with ESC H J K L M Y I only.** ESC Y takes row+32
   and col+32. ESC L turns inverse on and ESC M turns it off, and only a change in
   TATTR sends one. Before every erase and scroll the attribute is set to normal,
   because the terminal model clears in the attribute in force (test_edit.Term). That
   the real terminal does this is not documented: *provisional*. A full-screen scroll
   uses the terminal's own scroll: LF on its bottom row, or ESC I on row 0. A region
   scroll, IL and DL are drawn again from the shadow. The bottom-right cell is never
   written (TPUT), and SCRUP draws it once it has moved up a row. *verified.*
6. **The shadow** (ROWS x COLS bytes; bit 7 = inverse) lies in TERM.COM's memory over
   its copy of the image (TERM.ASM SCRBUF = Z80IMG). TERM.COM writes its hello line
   straight into it and then calls DRAW. ROWP treats any COLS other than 64 as 80.
   *verified.*
7. **The CSI parser** keeps 4 parameters. Each saturates at 255 (p >= 26, or a carry
   from 10p + d). Intermediates and ':' are ignored. A private marker (< = > ?) may
   appear anywhere. Final bytes are looked up in CTAB/PTAB, and an unknown final is
   dropped. Controls are acted on in the middle of a sequence; CAN and SUB abort it.
   *verified.*
8. **CRC-16/XMODEM** uses polynomial 1021h, initial value 0, MSB first. A Python
   reimplementation of F_CRC's loop gives 31C3h for "123456789", the standard check
   value. The XMODEM tests in test_term.py exercise it end to end. *verified.*
9. **Break**: CMDV OR 08h goes out without being stored in CMDV, followed by 25 x
   1538 x 26 T = 250 ms, and CMDOUT ends it. test_term checks one break and command 27h
   afterwards. *verified.*

## Code/comment disagreements

10. **"At a quarter it is let go again"** (source header) is wrong. LOWAT = 1 means
    below 256 bytes, an eighth of the ring. README.md ("below 256") is right.
    *verified.*
11. **LOGLIM's "256 bytes kept for the host's overrun"** are never used. SESS tests
    after each store, so LOGN never passes LOGLIM. Bytes the host sends after HOLD go
    into the ring, and TERM.ASM's LOGWR/LOGSET sets LOGN to 0 before SESS runs again.
    *verified (code + TERM.ASM).*
12. **SERPUT's "about 2 s"** is wrong: a poll costs 210 T (134 for RXPOLL with nothing
    to do, 76 for the loop), and 65 536 of them take 13.8 M T, about 3.4 s at 4 MHz.
    HOLD's "100 ms" works out to 3000 x 160 T, about 120 ms. KEYOUT's "about 40 ms"
    works out to 800 x ~265 T, about 53 ms. *verified counts; clock provisional.*
13. RXPOLL's "the level, less one": A is the high byte of new head - tail, which is
    the level including the byte just stored. *verified.*
14. SENDN's "A (1-255)": 0 works too (the units digit is always sent). *verified.*

## Edge cases and latent issues

15. **DROPS is write-only.** SERPUT counts bytes it gave up on (saturating at 255),
    but nothing reads the counter: not this image, not TERM.ASM, not the tests. SEND's
    AL = 1 is the only report. *verified.*
16. **Key reads are not polled.** PEEKEY/GETKEY (Z86.SYS) call CONIN, a full link
    receive exchange with no RXPOLL. The README's "longest gap under 1 800 T" was
    measured with a terminal model that answers at once. A slower real terminal could
    let a byte be overrun while a key is taken. The byte would be counted in LOST
    through OE, not lost silently. *provisional.*
17. **No polling during BRK's 250 ms** and RECV's direct reads. During a break, only
    the last byte the host sends survives. RECV resets PE/OE/FE but does not count
    overruns in LOST, leaving it to XMODEM's CRC to reject the block. *verified by
    code.*
18. **Error reset keeps RTS.** RXPOLL and RECV write CMDV OR ER. Z86.SYS's SERR writes
    the fixed IOERR (37h), which raises RTS, and would break /R flow control.
    *verified.*
19. **8-bit input.** 80h-BFh is dropped, which covers UTF-8 continuation bytes but also
    Latin-1 A0h-BFh (for example £ and °) and C1 controls such as CSI 9Bh. C0h-FFh
    shows as '?'. *verified.*
20. **SGR** takes each parameter on its own: 0 and 27 select normal, 7 selects
    inverse, and everything else is ignored. So `ESC [ 38;5;7 m` turns inverse on, and
    `48;5;0` turns it off. *verified.*
21. **Smaller VT100 gaps:** BEL and ENQ are ignored. Tab stops are fixed every 8
    columns (no HTS/TBC). ESC 7 does not save G0/G1/GL. There is no DECOM, so CUP and
    the DSR 6 report are absolute. ED with a parameter of 2 or more clears everything,
    ESC [ 3 J included. A private `ESC [ > c` gets no answer. VT52's ESC F/G (graphics)
    and ESC = / > are ignored. *verified.*
22. **IL/DL** move the region one row at a time, n times (n x rows x COLS bytes, in
    32-byte pieces), then draw it again. This is correct but slow for a large n. This
    is the image's only use of JPHL. *verified.*
23. **CTS dependence.** SERPUT and the XON/XOFF sender need status bit 7 (CTS), the
    same IOMASK test as Z86.SYS SPUT. With CTS undriven, TERM can neither send nor
    send XOFF, whatever the flow-control switch. How CTS reads when nothing drives it
    is untested on hardware. *provisional.*

## What test_term.py verifies (emulator only)

On fdd86.py, with a host on channel B sending in real time (fdd86.WD2123 loses a byte
held when the next arrives), the test covers:

- start-up: the hello line, mode 8Eh and baud code 14;
- 21 code cases and 60 random batches, comparing the terminal model's screen and cursor
  cell by cell against a Python VT100/VT52 model, and checking DSR/DA answers;
- keys: plain keys, arrows (ESC [ A, and ESC O A in cursor-key mode), ESC alone, the
  Ctrl-A menu, and break;
- /E local echo (including VT52), /C implicit LF;
- load of 6 KB at 9 600 and 19 200 baud with XON/XOFF and RTS/CTS (nothing lost),
  with no flow control (bytes lost, as expected), and the speed;
- the log: 12 KB through the 8 KB buffer, with the file exact;
- XMODEM receive (CRC with a corrupted block resent, and checksum) and send (CRC and
  checksum);
- /52 and /80.

The terminal model answers the link instantly; real terminal speed is unknown.
