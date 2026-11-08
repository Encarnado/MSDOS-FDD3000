# TERMZ80 — independent verification of termz80_findings.md (2026-11-08)

Program: TERM.COM's Z80 part, `project/MSDOS/poc/TERMZ80.ASM` (2000 lines), F12Ch-FEB7h.
Checked against the source, `symbols/z80/TERMZ80.lst`, `binaries/z80/TERMZ80.BIN`,
`binaries/x86/TERM.COM`, BIOS.ASM / I86.ASM, TERM.ASM, test_term.py, and the emulator (fdd86.py).
Every experiment was run on the emulator with copies of test_term.py's helpers. The scripts are not
kept in the repository. Patched sources were built with `z86.termz80()` and spliced into TERM.COM at C7Bh; the
repository was not touched.

Read-only checks done first:
- **Gate.** The listing's bytes are TERMZ80.BIN (3468 bytes, from F12Ch). `z86.termz80()` gives
  the 16-byte header plus the same bytes, and that equals TERM.COM from C7Bh to the end (6679 bytes).
  The header is `8C0D 3BD8 4DEB E3EB 00EC 0EEC 2AF1 2CF1`. *verified.*
- **Size.** TERMEND = FEB8h; z86.py asserts `TERMEND <= FF00h-64` = FEC0h, so 8 bytes are spare.

T-state counts below use standard Z80 timings, as fdd86.py counts them (LDIR = 21k-5), at 4 MHz.
One character takes 10 bits (mode 8Eh, 8N1): **2 083 T at 19 200 baud, 4 167 T at 9 600 baud.**

## 1. Summary

| # | Title | Class | Sev. | Fix |
|---|---|---|---|---|
| 1 | RXPOLL in every wait (the echo waits are not polled) | DESIGN | medium | yes (P6, +6 B) |
| 2 | Ring 2 KB, HIWAT 1024 / LOWAT 256, TXQ | NOTE | - | no |
| 3 | RXPOLL's EXX is safe | NOTE | - | no |
| 4 | TSEND = COSEND + poll; CONOUT imported, unused | NOTE | - | no |
| 5 | Timex terminal codes; attribute reset before erase/scroll | HW | low | no |
| 6 | Shadow screen over the image copy; ROWP 64/80 | NOTE | - | no |
| 7 | CSI parser | NOTE | - | no |
| 8 | CRC-16/XMODEM | NOTE | - | no |
| 9 | Break 250 ms | NOTE | - | no |
| 10 | "at a quarter it is let go" | DOC | low | yes (0 B) |
| 11 | LOGLIM's 256-byte reserve is never used | DOC | low | yes (P3, -9 B) |
| 12 | SERPUT "2 s", HOLD "100 ms", KEYOUT "40 ms" | DOC | low | yes (0 B) |
| 13 | RXPOLL "the level, less one" | DOC | low | yes (0 B) |
| 14 | SENDN "A (1-255)" | DOC | low | yes (0 B) |
| 15 | DROPS is write-only | DESIGN | low | yes (P4, -13 B) |
| 16 | Key reads (CONIN) not polled | HW | medium | no (does not fit) |
| 17 | No polling in BRK; RECV does not count overruns | DESIGN | low | optional (P5, -6 B) |
| 18 | Error reset keeps RTS; SERR's 37h would not | NOTE | - | no |
| 19 | 8-bit input: 80h-BFh dropped, C0h-FFh as '?' | DESIGN | low | no |
| 20 | SGR takes each parameter alone (38;5;7 → inverse) | DESIGN | low | no |
| 21 | Smaller VT100 gaps (ED 3 clears the screen, ...) | DESIGN | low | no |
| 22 | IL/DL one row at a time; the only JPHL use | NOTE | - | no |
| 23 | Needs CTS for sending and for XOFF | HW | low | no |
| N1 | **DRAWR leaves > 1 character time unpolled: bytes lost at 19 200 in a scrolling region** | BUG | medium | yes (P1, +3 B) |
| N2 | **A key typed during XMODEM does not cancel it** (DOS took it to KBUF) | BUG | medium | yes (P2, -3 B) |
| N3 | README "longest gap under 1 800 T"; OVERVIEW "always taken" | DOC | low | yes (docs) |
| N4 | test_term counts every overrun twice (README "lost 1 637") | DOC | low | yes (test/docs) |

Byte budget: P1 + P2 + P3 + P4 + P6 = +3 -3 -9 -13 +6 = **-16 bytes (TERMEND FEA8h)**; with P5,
-22 (FEA2h). The whole of test_term.py passes on the patched build with P1-P6 ("all ok"; results in
`test_all56.txt`). Every code fix changes the TERMZ80 image, so TERM.COM must be rebuilt (build.py
regenerates TERMZ80.INC). The 0-byte comment fixes change no bytes.

## 2. Per finding

### 1. RXPOLL in every wait — DESIGN, medium
The list is right: RXPOLL is called in TS1 (696), TO2 (675), QSP1 (541), KO1 (615), HO1 (202),
EN1 (391), SL1 (141), DR2 every 16 cells (849-850), MVSUB (964), SHUP/SHDN (983, 998) and
PUTCH (1118). TSEND's echo waits TS2/TS3 (708-724) are not polled. One pass of TS2 costs
IN 11 + DEC 4 + JR 7 + AND 7 + CP 4 + JR 12 = 45 T, and 255 of them take 11 475 T = 2.87 ms, as the
finding says.

The finding understates two things:
- "every wait" does not make every gap short. DRAWR leaves gaps of up to 3 282 T, and that loses
  bytes at 19 200 baud (N1).
- The emulator's terminal echoes at once. If the real terminal takes time to echo each nibble, that
  time is spent with no poll, twice for every character drawn. That happens far more often than a
  key read (16). Experiment (`exp_keys2.py`): the 6 KB load at 19 200 baud with /X, the 2 ms
  terminal, and a delay e on each echo:

  | echo delay per step | bytes lost (as built) | with P6 |
  |---|---|---|
  | 250 T (63 µs) | 0 | - |
  | 500 T | 2 | 0 |
  | 750 T | 4 | 0 |
  | 1 000 T | ~326 (652 counted, see N4) | 0 |
  | 2 000 T | - | 0 |

  On the common path TS1 → TS1 is about 400 T + 2e, so losses become steady once e is above about
  840 T (210 µs). The rarer long paths lose bytes from about 290 T (70 µs).

Recommendation: **fix now (P6)**. It is cheap insurance against a terminal speed nobody has
measured. P6 polls in both echo waits:
```
-TS2:    IN A,(2Fh)
+TS2:    CALL RXPOLL
+        IN A,(2Fh)
...
-TS3:    IN A,(2Fh)
+TS3:    CALL RXPOLL
+        IN A,(2Fh)
```
+6 bytes. RXPOLL keeps every register, flags included (PUSH AF / EXX), so B, C, D and E are safe.
The echo time-out becomes 255 x 179 T = 11.4 ms; it only detects a dead link, so a longer one does
no harm. The cost: the top speed with a terminal that takes no time falls from 1 048 to 964
chars/s at 19 200 baud, and with the 2 ms terminal from 325 to 317 chars/s (test_term).

### 2. The ring — NOTE
RINGM 07h (49). RXPOLL counts a byte as lost when the new head would equal the tail (447-450), so
the ring holds 2 047 bytes. The level's high byte is compared with HIWAT 4 (454-456: 1 024 bytes).
SL4 resumes the host below LOWAT 1 (182-185: below 256 bytes), and so does SL2 once the ring is
empty. HOLD sets STOPF and HOLDF (197-200). RESUME does nothing while HOLDF is set (513-515). TXQ
goes out only when status AND 81h = 81h (413-416). RESUME overwrites a pending XOFF in TXQ
(520-521). *Verified.*

### 3. EXX — NOTE
No EXX appears in I86.ASM or BIOS.ASM (grep); only EDIT.ASM, an 8086 file, matches. TRAP saves BC
and IX (30-31). Interrupts (IM 1) are on only during FDC commands (BIOS 399-400, 464-465), never
while TERMZ80 runs. *Verified.*

### 4. TSEND = COSEND — NOTE
TSEND (686-732) matches COSEND (BIOS 160-205) code for code. `RRCA x4 / AND 0Fh` gives the same
result as COSEND's `AND 0F0h / RRCA x4`. TS4 is LKFAIL, and TOUT/TO2 is CONOUT/CO2. CONOUT is in
the header (z86.py 221: the same name list as CPMZ80) but nothing in TERMZ80 calls it. Leave it.

### 5. Terminal codes — HW, low
TESC is called only with H, J, K, L, M, Y and I. TSETA (770-781) sends 'M' for 0 and 'L' for 80h,
and only when TATTR changes. TSETA 0 comes before ESC J/K in CLRALL, CLRK and EDN, and before
LF/ESC I in SCRUP/SCRDN. TPUT skips the bottom-right cell (785-795), and SCRUP draws it again
(1059-1069). The code matches the finding. Two points can only be settled on the Timex terminal:
whether it clears in the attribute in force (the reason for the TSETA 0), and whether its LF leaves
the column alone (SCRUP never changes TCOL after the LF).

### 6. Shadow — NOTE
TERM.ASM 995-996 has `SCRBUF EQU Z80IMG`. The hello line goes in at 350-353, then DRAW. ROWP
(896-899) adds A x 16 for any COLS other than 64. *Verified.*

### 7. CSI parser — NOTE
4 parameters (1554-1556; CSEMI stops at 4). Saturation: p >= 26 → 255, and the carry from 10p + d
→ 255 (1560-1572). 20h-2Fh and ':' are dropped (1548-1553). `< = > ?` can come anywhere (1581-1585).
Unknown finals fall off the end of CTAB/PTAB. EMUL tests for controls before PST (1333-1334), so
controls act in the middle of a sequence. CAN and SUB clear PST. *Verified.*

### 8. CRC — NOTE
A Python copy of CR1-CR3 (342-375) gives 31C3h for "123456789". *Verified.*

### 9. Break — NOTE
CMDA sends CMDV OR 08h without storing it (312-314). One pass of FB2 is 6+4+4+12 = 26 T, and
1 538 x 26 = 39 988 T = 10 ms; x 25 = 250 ms. Then CMDOUT. test_term checks `breaks == 1` and
`cmd == 27h`. *Verified.*

### 10. "at a quarter" — DOC, low
LOWAT = 1 (51) means below 256 bytes, an eighth of the ring. Fix, 0 bytes:
```
-; asked to stop (XOFF, or RTS off), at a quarter it is let go again.
+; asked to stop (XOFF, or RTS off), below an eighth (256) it is let go.
```

### 11. LOGLIM — DOC, low (with a saving)
SL3 (160-171) compares after each store and stops at LOGN = LOGLIM, so LOGN never goes past
LOGSZ-256. Bytes the host sends after HOLD go to the ring. TERM.ASM LOGWR → LOGW1 → LOGSET (484-487,
519-520) sets LOGN to 0 through F_LOG before SESS runs again. So 256 bytes of LOGBUF are never used,
and the comment's reason is wrong. Fix P3, **-9 bytes**: compare with LOGSZ itself.
```
         LD (SCREND),HL
-        LD HL,(LOGSZ)
-        DEC H
-        LD (LOGLIM),HL          ; 256 bytes kept for the host's overrun
         XOR A
...
-        LD DE,(LOGLIM)
+        LD DE,(LOGSZ)
...
-LOGLIM: DW 0
```
The last store goes to LOGBUF+LOGSZ-1, so nothing overflows. LOGLIM sits after PB (13 bytes), so
F_INIT's LDIR is unaffected. test_term's log test (12 KB through the buffer, file exact) passes.

### 12. Timing comments — DOC, low (recomputed)
- SERPUT poll: CALL 17 + RXPOLL with nothing to do (11+4+13+4+12+13+4+12+8+12+4+10+10 = 117)
  = 134; the rest of QSP1 is 13+4+12+7+7+7+6+4+4+12 = 76; 210 x 65 536 = 13.76 M T = **3.44 s**
  (3.9 s when an XON/XOFF is waiting in TXQ: +29 T per poll). The comment says "about 2 s".
- HOLD: 134 + 6+4+4+12 = 160; 3 000 x 160 = 480 000 T = **120 ms** ("100 ms").
- KEYOUT: 134 + PUSH 11 + CALL PEEKEY 17 + PEEKEY with no key 60 + POP 10 + JR 7 + 6+4+4+12 =
  265; 800 x 265 = **53 ms** ("about 40 ms").
- Also checked and right: FR2's "470 about 10 ms" (one pass of FR3 is 85 T, 470 x 85 = 39 950 T)
  and FB1's 10 ms.

Fix, 0 bytes:
```
-; off for about 2 s and the byte was dropped.
+; off for about 3.5 s and the byte was dropped.
-; HOLD: stop the host and take in what it still sends for 100 ms
+; HOLD: stop the host and take in what it still sends for 120 ms
-        LD HL,800               ; about 40 ms
+        LD HL,800               ; about 50 ms
```

### 13. "the level, less one" — DOC, low
After `SBC HL,BC` (449), HL = new head - tail, which counts the byte just stored. So STOP comes at
1 024 bytes including it. Fix, 0 bytes:
```
-        LD A,H                  ; the level, less one
+        LD A,H                  ; the level with this byte, x 256
```

### 14. SENDN — DOC, low
Traced by hand: with A = 0, both SN1 calls return with nothing sent (C = 0), then '0' goes out. The
callers only pass CROW+1 and CCOL+1. Fix, 0 bytes: `; SENDN: A (0-255) in decimal to the channel`.

### 15. DROPS — DESIGN, low → remove
DROPS is written at 86 and 552-555, and read nowhere: grep of TERMZ80, TERM.ASM and test_term.py.
Fix P4, **-13 bytes**:
```
         LD (TXQ),A
-        LD (DROPS),A
...
         JR NZ,QSP1
-        LD A,(DROPS)
-        INC A
-        JR Z,SP0
-        LD (DROPS),A
-SP0:    SCF
+        SCF
...
-DROPS:  DB 0
```

### 16. Key reads not polled — HW, medium
Confirmed. PEEKEY → CONIN → CIRECV (BIOS 123-246) has no poll. Without the terminal's own time it
costs about 470 T. Measured on the emulator, the SESS key path (RXPOLL at SL1 → PEEKEY/CONIN →
GETKEY → KEYOUT → the RXPOLL in SERPUT) is about 1 150 T with an instant terminal.

The slow-terminal model (`fdd86.Link .clock/.char_t`) delays only the 0Fh that answers an output
request, which RXPOLL polls in TS1, so as it stands it says nothing about key reads.
`exp_keys.py` extends it. Each answer in the key exchange (06→05, 0F→1l, 1l→4h, 4h→50) comes d
T-states late, so a key read takes about 1 150 + 4d T. A host streams 6 KB, the terminal takes
2 ms a character and 20 ms a scroll, and a key is typed every 100 ms:

| baud (char time) | d = 250 T | 500 T | 750 T | 1 000 T |
|---|---|---|---|---|
| 9 600 (4 167 T) | 0 lost | 0 | 0 | 6 lost / 163 keys |
| 19 200 (2 083 T) | 0 | 12 / 147 keys | 28 / 142 | 43 / 140 |

The arithmetic gives the same thresholds: no byte can be lost while 1 150 + 4d < one character
time, that is **d < ~230 T (58 µs) per step at 19 200 baud and d < ~750 T (190 µs) at 9 600**.
Above that, a key pressed while the host is sending loses one byte with probability
(gap - char time) / char time.

**Flow control does not prevent it.** The first matrix (`keys_out.txt`, a key every 20 ms) gives
the same losses with /X and with /R (for example 19 200 baud, d = 1 000: 365 vs 361 counted). Both
act on the ring's level (1 024 / 256), not on the one byte the chip holds. In practice, with the
2 ms terminal, the host sends in bursts between XON and XOFF (XOFF 4-5 times per 6 KB). It is
sending about 325/1 920 ≈ 17 % of the time at 19 200 baud and 34 % at 9 600, so only keys typed
then are at risk: typically Ctrl-C or Ctrl-S during bulk output. The loss is not silent: the OE bit
makes RXPOLL count it in LOST, and the menu shows it.

No fix fits. A polled copy of CONIN inside TERMZ80 is about 100 bytes (four wait loops with RXPOLL,
the abort/retry path, and the KFLAG handover), and at most 30 bytes are free after the savings.
Recommendation: measure on hardware first. The terminal's latency per step (or simply LOST after
typing during a flood) settles whether it matters. The CBIOS's 255-pass time-outs (about 3 ms) show
only that the terminal answers within 3 ms, which is far above the 58 µs limit. Class HW.

### 17. BRK and RECV — DESIGN, low
F_BRK runs 250 ms with no poll (311-322). If the host sends during the break, the chip keeps only
the last byte, and the next RXPOLL counts **one** overrun in LOST. RECV's FR5 (261-265) clears the
errors without counting, and XMODEM's CRC/checksum catches the damage. Both are true.

Optional P5 (**-6 bytes**) polls during the break by reusing HOLD's loop (160 T a pass; 6 250 x 160
= 1.0 M T = 250 ms):
```
-        LD B,25
-FB1:    LD HL,1538              ; 10 ms
-FB2:    DEC HL
-        LD A,H
-        OR L
-        JR NZ,FB2
-        DJNZ FB1
+        LD HL,6250              ; 250 ms, taking received bytes
+        CALL HO1
         JP CMDOUT
```
The catch: if the ring reaches 1 024 during the break, STOP queues an XOFF. RXPOLL then writes it
while the break holds TxD low, so the XOFF is lost. That needs more than 544 bytes already in the
ring at the start (480 more arrive at 19 200 baud in 250 ms). Recommendation: leave it for the
author. Take it if the bytes are wanted.

### 18. Error reset — NOTE
RXPOLL (432-434) and FR5 (263-265) write CMDV OR 10h, so RTS stays as flow control left it. SERR
(I86 148-153) writes 37h. TERM never reaches SERR during a session: INT 14h F1h (SSET) runs before
INIT, and TERMZ80 never calls SPUT or SGET. Nothing to do.

### 19-21. VT100 coverage — DESIGN, low; leave
- **19.** EM8 (1354-1361) behaves as described: 80h-BFh are dropped, so £ (A3h), ° (B0h) and
  C1 CSI (9Bh) vanish, and C0h-FFh show as '?'. README says "use LANG=C".
- **20.** SGR (1755-1770) works as described. `ESC[38;5;7m` turns inverse on. Skipping the
  parameters after 38/48 would cost about 14 bytes; leave it to the author.
- **21.** All true:
  - ECTRL ignores BEL and ENQ;
  - ETAB uses fixed stops (1409-1418);
  - SAVEC keeps only the row, column and attribute;
  - PSM knows only ?1 and ?7;
  - EDN sends any parameter >= 2 to CLRALL (1262), so `ESC[3J` clears the screen. xterm's `clear`
    sends 2J 3J together, so in practice this does no harm;
  - PTAB has no 'c', so `ESC[>c` gets no answer;
  - V52ESC ignores F, G, = and >.

### 22. IL/DL — NOTE
IL0 (1869-1904) calls SHDN or SHUP n times through `CALL JPHL` (1894). This is JPHL's only use;
T_TERM and CF2 use `JP (HL)` directly. Each pass moves (RB-RT) x COLS bytes through MVF/MVB, polled.
Worst case is about 24 x 1 840 bytes x 21 T ≈ 0.93 M T (0.25 s), then REDR. Correct.

### 23. CTS — HW, low
SERPUT (544-547) and RXPOLL's TXQ test (413-416) both need status AND 81h = 81h, as SPUT does
(I86 99-102). With CTS not driven, nothing goes out, XOFF included. What the WD2123's CTS input
reads when the pin is left open on the FDD3000 is a hardware question.

## 3. New findings

### N1. DRAWR leaves more than a character time unpolled: bytes lost at 19 200 baud — BUG, medium
DR2 polls only when `B AND 15` = 0 (849-850). The scan starts at column COLS-1 or COLS-2, so up to
15 blank cells (75 T each, 1 125 T) go by before its first poll. After its last poll, up to 15 more
cells, then CELLP and TPUT → TGOTO → TESC → TOUT → TSEND, before TS1 polls (about 330 T more). There
is no poll at DRAWR's entry either, so the time spent before it adds to the gap. REDR draws row
after row, from SCRR (region scroll), IL/DL, ED 1 and DRAW.

Measured (`exp_where.py`, `exp_region.py`): 19 200 baud, /X, a region `ESC[2;23r` and 400 lines of
0-63 characters (13 136 bytes):

| build | terminal | bytes lost | gaps > 2 083 T | longest gap | screen |
|---|---|---|---|---|---|
| as built | instant | **10** | 1 387 | 3 282 T | 1 cell wrong |
| as built | 2 ms/char | **2** | 1 201 | 3 207 T | |
| as built, 9 600 baud | instant | 0 | 0 | 3 207 T | |
| P1 (with P2-P6) | instant | 0 | 1 | 2 122 T | right |
| P1 (with P2-P6) | 2 ms/char | 0 | 1 | 2 122 T | right |

The longest gaps were these:
- MVSUB's last RXPOLL in SHUP's FILL → (SCRUP → FULLSC → SCRR → REDR → DRAWR → DR2 → TPUT) → TS1:
  3 282 T;
- TS1 of one row's last cell → the next row's first TS1: 2 780 T;
- MVSUB → DR2: 2 750 T.

Flow control does not help (the ring is far from full). The whole-screen load test in test_term
shows nothing because full-screen scrolls never call REDR. Its longest gap is 1 997 T.

Fix P1, **+3 bytes**: poll at DRAWR's entry and every 8 cells.
```
-DRAWR:  LD A,(COLS)
+DRAWR:  CALL RXPOLL             ; (a row may follow a row, or a scroll)
+        LD A,(COLS)
         DEC A
         LD C,A                  ; C = the last column to draw
...
-        AND 15
+        AND 7
         CALL Z,RXPOLL
```
(The second hunk replaces `AND 15` with `AND 7` and costs 0 bytes.) After P1 the run loses
nothing. One gap of 2 122 T remains, in a single SESS pass; its cause was not traced and it lost
nothing. Changes the TERMZ80 image.

Test, which fails now (10 lost) and passes after:
```python
def region_load():
    print('5b. a scrolling region at 19200 baud')
    r = start('TERM AUX:19200')
    vt = VT()
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    rnd = random.Random(1)
    data = (ESC + '[2;23r' + ESC + '[23;1H' + ''.join('x' * rnd.randint(0, 63) + '\r\n' for _ in range(400))
            + ESC + '[r').encode()
    r.h.host(data)
    vt.feed(data)
    r.settle(4_000_000_000)
    d = differences(r.term, vt)
    check(r.h.lost == 0 and not d, 'region at 19200: lost %d; %s' % (r.h.lost, '; '.join(d[:3])))
```

### N2. A key typed during an XMODEM transfer does not cancel it — BUG, medium
RECV (FR3, 248-251) looks for a key only at the link (`IN A,(2Fh) / AND 5Fh / CP 04h`). Between
blocks TERM.COM prints the progress line (XPROG → PUTS, DOS function 9). DOS's console output checks
the BIOS status, which is T_STAT → PEEKEY. PEEKEY takes a waiting key off the link into KBUF and
sets KFLAG (BIOS 123-136). From then on the link shows 50h, so RECV never sees the key. The
transfer runs to the end, and the key is then used up by SHOW's "press a key" wait, so the "done"
line flashes past.

Experiment (`exp_xcancel.py`): XMODEM receive of 6 000 bytes at 9 600 baud, 'x' typed after 10 s.
As built: `transfer ended: ('crc', 0)`, KFLAG = 1 at the end (the key is still parked). With P2:
`CAN sent 0.13 s after the key`. XSEND waits for the answer to each block in RECV too (XANS), so it
has the same fault and the same fix.

Fix P2, **-3 bytes**: ask PEEKEY, which also sees KFLAG. Its no-key path changes only A and the
flags, so HL, DE and C are safe. With a key, CONIN uses BC and DE, but FR7 needs neither.
```
-FR2:    LD HL,470               ; about 10 ms
+FR2:    LD HL,292               ; about 10 ms
 FR3:    IN A,(C)
         BIT 1,A
         JR NZ,FR5
-        IN A,(2Fh)
-        AND 5Fh
-        CP 04h                  ; a key
-        JR Z,FR7
+        CALL PEEKEY             ; a key (DOS may have taken it to KBUF)
+        JR C,FR7
```
A pass of FR3 becomes 12+8+7+17+60+7+6+4+4+12 = 137 T, and 292 x 137 = 40 004 T = 10 ms.
Changes the TERMZ80 image.

Test (fails now, passes after):
```python
def xcancel():
    print('7b. a key during XMODEM receive')
    r = start('TERM AUX:9600')
    r.keys('\x01R', 8_000_000)
    r.keys('IN.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    gen = sender(bytes(range(256)) * 24)
    out, t0, typed, ok = next(gen), r.m.tstates, None, False
    while r.m.tstates - t0 < 400_000_000 and not ok:
        while out is not None:
            r.h.host(out)
            out = gen.send(b'')
        r.run(500_000)
        if typed is None and r.m.tstates - t0 > 40_000_000:
            r.m.keys.extend(b'x')
            typed = r.m.tstates
        got = r.tx()
        ok = typed is not None and b'\x18\x18\x18' in got and r.m.tstates - typed < 4_000_000
        try:
            out = gen.send(got)
        except StopIteration:
            break
    check(ok, 'XMODEM receive: a key did not cancel it within 1 s')
```

### N3. Docs overstate the polling — DOC, low
- README.md line 753 says "the longest time between two calls is under 1 800 T-states". It is
  1 997 T for the whole-screen load (`exp_keys.py`, d = 0) and 3 282 T in a region (N1).
- OVERVIEW.md §2.9 says "so the one byte the chip holds is always taken". That is not so before
  P1.

After P1, write: "the longest time between two calls is about 2 000 T-states, just under a
character at 19 200 baud (2 083): the margin is thin, and the terminal's own answer times (not
modelled) come on top". No binary change.

### N4. test_term counts each overrun twice — DOC, low
test_term.py adds `r.h.lost + r.word('LOST') + r.h.deaf` (fuzz, load and log). Every overrun is
counted once by the chip model (`.lost`) and once more by RXPOLL's OE count (LOST). For example,
`exp_region.py` as built gives chip 10 and LOST 10. The checks (`== 0`, `> 0`) still hold. But the
README table's "9 600 baud, no flow control: lost 1 637" is about twice the bytes lost (LOST also
counts ring-full losses, which the chip does not see). Fix in test_term.py: report `r.h.lost` and
LOST apart, and correct the README figure. No binary change.

### Checked, no fault
- RESUME without regard to the level (ENSURE before RECV/SEND/BRK): STOP re-arms on the next byte
  stored at >= 1 024.
- F_DRAW's clamp; F_MODE's mask; RGET's CF on an empty ring.
- CHCNT/ICHS/DCHS edge cases (n = 0, n > the cells left); MVF/MVB with BC = 33; SHDN's addresses.
- SENDN's digits for 100-109; PSM's 1-then-7 test (C is never 7).
- STBM's rejection of top >= bottom; TPUT's wrap tracking on the last column; KEYOUT leaving a
  non-arrow key after ESC for SESS (KFLAG).
- RECV with DX = 0 would wait 65 536 x 10 ms, but no caller passes DX = 0 with CX > 0
  (TERM.ASM 774-784).

## 4. Fix list, in priority order

| # | Fix | Bytes | Image | Notes |
|---|---|---|---|---|
| 1 | N1 / P1: CALL RXPOLL at DRAWR, DR2 `AND 7` | +3 | changes | real loss at 19 200 baud in regions |
| 2 | N2 / P2: RECV asks PEEKEY | -3 | changes | XMODEM cancel works |
| 3 | 1 / P6: RXPOLL in TS2 and TS3 | +6 | changes | insurance against a slow terminal echo; -8 % top speed |
| 4 | 15 / P4: drop DROPS | -13 | changes | pays for 1 and 3 |
| 5 | 11 / P3: drop LOGLIM, compare with LOGSZ | -9 | changes | also fixes the wrong comment |
| 6 | 10, 12, 13, 14: comments | 0 | none | |
| 7 | N3, N4: README / OVERVIEW / test_term figures | 0 | none | |
| 8 | 17 / P5: polled break via HO1 (optional) | -6 | changes | XOFF-during-break caveat |
| - | 16: polled key read | ~+100 | - | does not fit; measure on hardware first |

1-5 together: **-16 bytes, TERMEND FEA8h** (24 bytes under FEC0h). With 8: FEA2h. All of
test_term.py passes on the build with 1-5 and 8 (`test_all56.txt`: "all ok", every file exact,
lost 0 with flow control).
