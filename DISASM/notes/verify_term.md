# TERM.COM: an independent check of term_findings.md (2026-11-08)

Scope: TERM.COM's 8086 part (`project/MSDOS/poc/TERM.ASM`, `symbols/x86/TERM.LST`,
`binaries/x86/TERM.COM`). I read TERMZ80.ASM where a finding depends on it. This pass
was read-only. The experiments (run on the emulator; the scripts are not kept in the repository):

| script | what it does |
|---|---|
| `mkterm.py OUT TERM.ASM [TERMZ80.ASM]` | builds TERM.COM with MASM 1.10 / LINK / EXE2BIN on dosshim, as build.py does. With the unchanged sources the output is byte-identical (MD5 e28710898db1d2cb34972e30b1201089) |
| `quit_exp.py [build] [termz80]` | finding 1: menu, then Q, with /X, /R and /N, then TERM run again |
| `after_xfer.py` | new finding N1: what the host sends while "done - a key" is on screen |
| `stale_c.py` | new finding N2: a stale 'C' while TERM is sending |
| `eot_hit.py` | new finding N3: a line hit on a block's SOH while TERM is receiving |
| `menu_arrow.py` | new finding N4: an arrow key at the menu |
| `runtests.py BUILD [termz80]` | the whole test_term.py against another build |

The experiments drive `test_term.py`'s Rig on the fdd86 emulator (WD2123 model, a host
sending in real time). Builds: `build_fix` (finding 1 only), `build_init` (the optional INIT
variant), `build_fix4` (every recommended fix together: TERM_fix4.ASM + TERMZ80_hold.ASM).
`build_fix`, `build_fix3` and `build_fix4` pass the whole of test_term.py (`t_fix*.log`:
"all ok").

## 1. Summary

| # | title | class | sev. | fix |
|---|---|---|---|---|
| 1 | QUIT leaves the host stopped (XOFF / RTS off) | BUG | medium | yes |
| 2 | one CAN cancels | DESIGN (receive side folded into N3's fix) | low | with N3 |
| 3 | the sender's wait for 'C'/NAK restarts on noise | NOTE | low | no |
| 4 | block BLK-1 ACKed and dropped; block 0 too | NOTE | low | no |
| 5 | a failed receive keeps the partial file | DESIGN (leave) | low | no |
| 6 | retry limits and timeouts | DESIGN (receive's 3 s vs the usual 10 s; leave for the author) | low | no |
| 7 | whole 128-byte blocks; progress 128 vs XCNT | NOTE | - | no |
| 8 | /64 accepted, not documented | DOC | low | yes |
| 9 | LFCB closed twice on disk full in LOGOFF | NOTE (harmless: checked in MSDOS.ASM CLOSE) | low | no |
| 10 | three MASM forward-reference NOPs | NOTE | - | no |
| 11 | header checks 7 names; REGS unchecked; 8 bytes spare | DESIGN (one wrong detail: CONOUT is not used) | low | no |
| 12 | README conflicts on hardware | DOC | low | yes |
| 13 | the menu stays inside 62 columns | NOTE (verified) | - | no |
| 14 | PUTNB's DIV overflows above 655 359 | NOTE (unreachable) | - | no |
| 15 | small asymmetries | NOTE | - | no |
| 16 | settings need a port | NOTE (as documented) | - | no |
| DN | design notes (5) | all true | - | - |
| CV | cross-volume (4) | true; one addition (TERMZ80 header "a quarter") | low | doc |
| HW | hardware evidence | HW / DOC | - | ask João |
| N1 | host output lost while "done - a key" waits | BUG | low | yes |
| N2 | the sender reads answers one block late after a stale byte; a later NAK then kills the transfer | BUG | low-medium | yes |
| N3 | a line hit turning SOH into EOT ends the receive as "done" with a truncated file (into CAN: "cancelled") | BUG | medium | yes |
| N4 | an arrow key at the menu or a file-name question: ESC is taken, the letter goes to the host | NOTE | low | no |
| N5 | TERMZ80 header: "at a quarter it is let go" is really "below 256" (an eighth) | DOC (TERMZ80 volume) | low | yes |

## 2. Per finding

### 1. QUIT leaves the host stopped: BUG, medium. Confirmed by reading and by experiment

The reading is correct. SMENU calls HOLD, which sets STOPF and HOLDF and calls FLOWOFF:
XOFF is queued with /X, and the command register becomes 07h (RTS off) with /R. Only
RESUME lets the host go. RESUME is reached from F_SESS (it clears HOLDF, and calls RESUME
when the ring is empty or below LOWAT) and from ENSURE (in F_RECV, F_SEND, F_BRK). Menu
Q goes TERM.ASM QUIT → LOGOFF? → BOTTOM/BOTEND → INT 20h, and calls none of them.

**Experiment** (`quit_exp.py`). The host has 200 bytes queued; menu; then a key:

```
/X Q    : menu sent 13h; after Q nothing sent; host paused=True;
          TERM run again: still paused, 48 of 50 host bytes never arrive (rerun_tx b'')
/R Q    : command 07h after Q and after exit (RTS off); TERM run again: INIT's 27h frees it
/X ' '  : (control) any other key -> SESS -> 11h sent, host goes on
/R ' '  : (control) command back to 27h
/N Q    : nothing to undo
```

It is worse than the finding says for /X. **Running TERM again does not free the host**:
F_INIT clears STOPF, so RESUME is never called and no XON goes out until the user types
Ctrl-Q. A Unix host with `ixon` (the default for a serial getty) shows nothing. With /R,
a fresh TERM raises RTS again in F_INIT; but between the two runs RTS stays off.

**Fix: none needed in TERMZ80. TERM can call SEND with CX = 0.** F_SEND starts with
`CALL ENSURE` (HOLDF=0, and RESUME if STOPF): XON is queued and the command goes back to
27h, and it waits in EN1 until the XON has left TXQ. Then the loop at FS1 sees BC = 0
and returns AL = 0. This costs 5 bytes of 8086 code and **leaves the TERMZ80 image
unchanged** (TERMEND stays FEB8h). TERM.COM is rebuilt and grows by 5 bytes. The buffers
move with Z80IMG, which is harmless.

```diff
--- TERM.ASM
@@ QUIT
-QUIT1:  CALL    BOTTOM          ; DOS goes on from the bottom line
+QUIT1:  XOR     CX,CX           ; the host let go (SEND of nothing:
+        CALL    SEND            ;   the Z80 part's ENSURE)
+        CALL    BOTTOM          ; DOS goes on from the bottom line
```

It should come after LOGOFF, which may do disk I/O and show "Disk full", so the host is
let go as late as possible. The patched build (`build_fix`) gives `/X Q: after_tx
b'\x11', paused False`, `/R Q: cmd 27`, a re-run gets everything, and test_term.py passes.
Other ways to do it:

- A new TERMZ80 function, "10 QUIT/RESUME" = `DW ENSURE` in FTAB plus `CP 11`, costs
  2 bytes (FEBAh, 6 spare). It is more explicit, but it changes the image for no gain,
  because SEND with CX = 0 already *is* ENSURE. If the author chooses this, merge it
  with N1's `DW HOLD`, which goes in the same place.
- Optional hardening, independent of the above: F_INIT starts with STOPF = 1, so the
  first idle SESS calls RESUME and sends one XON. This covers a host left XOFFed by a
  reset or a crash during a session. The diff (`termz80_init.diff`) removes
  `LD (STOPF),A` from the clear block and adds `INC A / LD (STOPF),A` after
  `CALL F_FLSH`, which is **+1 byte** (FEB9h). It works (`build_init`: the re-run sends
  11h and the host goes on), but **four test_term checks then fail**: they compare the
  replies exactly and now see a leading 11h ("text, CR LF: answered b'\x11'"...). Adopt
  it only together with a test change that strips the first XON. I would leave this to
  the author.

**Test** (fails now: no 11h, command 07h; passes with the fix):

```python
def quit_lets_go():
    for opt, flow in (('/X', 'x'), ('/R', 'r')):
        r = start('TERM AUX:9600 ' + opt)
        r.h.flow = flow
        r.keys('\x01', 8_000_000)               # the menu: HOLD
        r.tx()
        r.keys('Q', 30_000_000)
        check(not r.h.paused and r.h.cmd & 0x20, '%s: Q left the host stopped (cmd %02X)' % (opt, r.h.cmd))
        if flow == 'x':
            check(r.tx().endswith(b'\x11'), '/X: no XON on quit')
```

### 2. One CAN cancels: DESIGN, low; the receive side is fixed together with N3

True. A single CAN as a block's first byte cancels the receive (XR2). A single CAN cancels
the send in XS1 and as a block's answer (XS5). Forsberg's ymodem.txt §4.1 ("Graceful
abort") recognizes "two consecutive CAN characters ... as a transfer abort command ...
the check for two consecutive CAN characters reduces the number of transfers aborted by
line hits", and has the aborting side send eight CANs (then eight backspaces). TERM sends
three (CANS), which is enough for any two-CAN receiver.

Which side matters: **the receive side** (see N3, demonstrated). A hit on a block's
SOH that makes 18h ends the transfer as "Cancelled by the other side", while the sender
is still sending. On the send side a hit that turns ACK (06h) into CAN (18h) ends the
transfer with a visible message and no wrong data, so it is low. N3's fix requires two
CANs on receive. I would leave the send side as it is (if the author wants it: on CAN in
XS5 / XS1, read one more byte with XANS and cancel only if it is CAN too).

### 3. The sender's wait for 'C'/NAK is unbounded under noise: NOTE, low

True (XS1: XGET CX=1, DX=6000; any other byte → `JNZ XS1`, which restarts the 60 s).
Christensen's rule for the sender is "a single very long timeout, say one minute"
(ymodem.txt §7.3.3), so TERM's 60 s matches, apart from the restart. A CAN, a key or a
minute of silence ends it. Leave.

### 4. Block BLK-1 ACKed and dropped: NOTE, low

True (XRS2: `INC AL / CMP AL,[BLK] / JZ XRACK`). This is the standard "duplicate block"
rule (Christensen: a repeated block is ACKed and thrown away). With BLK = 1 a block 0 is
ACKed too. YMODEM's block 0 is therefore swallowed. XRS2 also sets GOT = 1, so later
timeouts send NAK and never 'C', which is not what a YMODEM sender waits for. TERM
claims XMODEM only (README: `sx file` / `rx file`), so leave. Not tested.

### 5. A failed receive keeps the partial file: DESIGN, low; leave

True. XFAIL, XUSER and XRCAN all reach XEND (AH=16 close); nothing deletes the file.
Keeping the partial file is common and can be useful. Leave, or delete with AH=19 in
XEND only when receiving.

### 6. Retry limits differ: DESIGN, low; leave for the author

Counts verified. Receive: TRIES is shared by timeouts (XRTO) and bad blocks (XRBAD), and
`JA` fails on the 11th. In the start phase that is 'C' at TRIES 0-2, then NAK, so about
11 × 3 s = 33 s with no sender before "Transfer failed". Send: `JB` gives 10 sends of a
block, and the same for EOT. Timeouts: 3 s for a block's first byte (DX=300), 1 s
between bytes (F_RECV TMO=100), 10 s for an answer (XANS), 60 s for the start.

Against the convention (ymodem.txt §7.3.1-7.3.2, Christensen): "The receiver has a
10-second timeout. It sends a <nak> every time it times out", 1 s per character, "all
errors are retried 10 times". So the **10-try limit and the 1 s inter-character timeout
match**. The one deviation that can matter is **3 s instead of 10 s for SOH**. A sender
slower than 3 s between blocks (a loaded host, a sender behind a slow network hop) gets
an early NAK. That NAK then becomes a stale answer for the next block, which is exactly
the situation of N2 (seen from the sender's side, so a sender without a purge may
desync). With modern hosts 3 s is ample, and it makes the 'C' to checksum fallback
faster (9 s). I would leave it, and mention it in the README.

### 7. Whole 128-byte blocks; progress counts: NOTE

True. XRS3 writes 128 bytes, ^Z padding included. XRS4 adds 128 and XS6 adds XCNT.
This is standard XMODEM, since the length is not carried. The test compares against the
padded data.

### 8. /64 accepted, not documented: DOC, low

True (OPT: `CMP AX,"4"*256+"6"` → OPT64). USEMSG, the header comment, README and
OVERVIEW §2.9 all list only /80. Minimal fix: the header comment and the README only
(the binary stays the same):

```diff
--- TERM.ASM
-;       /80     an 80-column terminal (default 64)
+;       /80     an 80-column terminal (/64, the default: 64 columns)
```

README line 708 / 716: `[/80|/64]`, "`/80` an 80-column terminal (`/64` the default)".
Changing USEMSG as well (`[/80|/64]`) would change TERM.COM. It is optional, and the
line stays under 64 columns.

### 9. Double close of LFCB on disk full in LOGOFF: NOTE, low

The code path is true: LOGOFF → LOGWR → disk full: close, LOGON=0, LOGSET, SHOW, DRAW;
back in LOGOFF: close again, LOGSET again. **Its effect, checked in MSDOS.ASM CLOSE
(build/MSDOS.ASM 1013-1061):** CLOSE writes back a dirty buffer, finds the file by name
(GETFILE), copies the first cluster, size, date and time from the FCB into the entry,
does DIRWRITE, and writes the FAT only if it is dirty. It does not mark the FCB closed.
A second close therefore rewrites the same directory entry with the same values: one
extra sector write, and it allocates nothing, so it works on a full disk. Harmless. Leave
(or add `CMP [LOGON],0 / JZ` after LOGOFF's CALL LOGWR).

### 10. Three MASM forward-reference NOPs: NOTE

Verified in TERM.LST: `07BA EB 64 90 JMP LOGSW`, `0BB4 EB 22 90 JMP SHOW1`,
`0A74 C6 06 3CFB R 01 90 MOV [XBUF],SOH`. The usual explanation is that pass 1 does not
know the forward symbol's type and sizes `MOV [XBUF],imm` as a word store (C7 06 ll hh
ii ii, 6 bytes). In pass 2 XBUF turns out to be BYTE (it comes from Z80IMG LABEL BYTE),
so the 5-byte form gets a NOP. This explanation is the standard behaviour of MASM 1.x,
so it stays provisional, as the finding says. The other XBUF stores have a register
operand, which sizes them, so they get no NOP. Nothing to do.

### 11. Header and dependencies: DESIGN, low; one detail wrong

Verified: the header in TERM.COM (file offset 0C7Bh) is `0D8C D83B EB4D EBE3 EC00 EC0E
F12A F12C`, which matches Z86.SYS.sym. BIOS T_CPML compares exactly those 14 bytes
(CPMSYM..CPMSYE). TERMEND is FEB8h, z86.py asserts `<= FF00h-64 = FEC0h`, so there are
8 bytes spare.

**Correction:** TERMZ80.ASM does **not** use CONOUT. A scan of every identifier it does
not define gives exactly `ENDBIOS GETKEY JPHL PEEKEY R_AH R_AL R_BH R_BL R_CL R_CX R_DI
R_DL R_DX R_SI`. CONOUT appears only in a comment (line 666, TOUT "as the BIOS's
CONOUT"). The unchecked dependency is the REGS page (I86.ASM line 28, `R_xx EQU REGS+n`):
REGS is not one of the seven names, so a Z86.SYS that moved REGS would pass the check and
then fail. Same gap as CPM.COM. I would leave it: z86.py rebuilds both from the same
sources. Note also that T_CPML does not check the image's length against the stack. Only
z86.py's assert guards that.

### 12. Documentation conflict on hardware: DOC, low

True, and there is more than the finding lists. README line 51 says "Real hardware: not
tried by me". Line 699 (the Serial/WD2123 section) says "nothing has been tried on the
hardware". Line 731 (TERM, PuTTY) says "Tried on a real FDD3000". Lines 801-802 say "Not
known: ... anything on real hardware". OVERVIEW §4 says "Not tried on real FDD3000
hardware or a real terminal". notes/hardware_run.md has no TERM run. It cannot be
settled from the files; ask João. Minimal fix: README 731 becomes "Tried on a real
FDD3000 (João's build, before the merge; not recorded in detail)", or the sentence is
dropped, and 801 says "anything else on real hardware". No binary changes.

### 13. The menu stays inside 62 columns: NOTE, verified

13 + 8 + 6 + 24 + 6 + 5 = 62 (MENU1+ONOFF, MENUE+ONOFF, MENUC+ONOFF, MENU2, LOSTM, up to
65535). I also checked the other bottom-line texts. The longest are "Receive (XMODEM) as
file: " plus 28 typed characters = 54, and "Receiving: " + 6 digits + " bytes: done" +
" - a key" = 37. All are under 63.

### 14. PUTNB's DIV overflow: NOTE

True. DX:AX / 10 with a quotient over FFFFh means NBYTES ≥ 655 360, which is unreachable:
one disk holds about 180 KB, and a receive stops on disk full (XRS3 → XFAIL).

### 15. Small asymmetries: NOTE

All true. One more detail about PURGE: a key pressed during PURGE makes F_RECV return at
once with CX = 0 (or a few bytes), so PURGE also **ends early** (it does not wait for a
quiet line) as well as dropping the key. Harmless.

### 16. Settings need a port: NOTE

True. `TERM 9600`: GETW (CX=4) reads "9600" as a port name, no PORTS entry matches, BAD.
`TERM 19200`: more than 4 characters, BAD. This is as the usage line nests it. A port
alone keeps the channel's settings (PORT3 → LOAD). Settings start from INT 14h AH=F0h.
SETX runs before LOAD, so on VERMSG the channel is already changed. Leave.

### Design notes: all verified

- The split, and trap 1Ch with BP ≠ 0 / BP = 0 → ENDBIOS = T_TERM: BIOS.ASM T_CPML,
  TERMZ80.ASM 53-68.
- Buffers: 0D7Bh + 780h = 14FBh, + 800h = 1CFBh, + 2000h = 3CFBh, + 133 → 3D7Fh. The
  file ends at 0100h + 6679 - 1 = 1B16h. True.
- XMODEM split, and RECV sending the answer and taking the next block in one call:
  F_RECV (SERPUT BL, then CX bytes). True.
- Random block I/O with 1-byte records (RECSZ1: record size 1, random record 0). True.
- Bottom-line codes go through DOS, and row 23 is redrawn (SESS1: DRAW CL=23). True.

### Cross-volume: true, with one addition

- Finding 1 does depend on TERMZ80's SMENU/HOLD/RESUME/ENSURE. Its fix (above) needs
  nothing from TERMZ80.
- Same header and REGS gap as CPM.COM: true (see 11).
- MODE.ASM: GETW, BLANKS and SAME6 are identical; COMMA differs only in a label (CMBAD
  vs BAD1); PORTS/BAUDS/ABAUDS are identical except for MODE's comments. "Nearly line for
  line" holds.
- README 731 vs 801 / OVERVIEW 4: see 12 (plus lines 51 and 699).
- Addition (N5): TERMZ80.ASM's header, lines 26-27, says "at a quarter it is let go
  again". LOWAT EQU 1 and SL4 (`LEVEL / CP LOWAT / CALL C,RESUME`) let it go below
  256 bytes, an eighth of the 2 KB ring. README ("below 256") is right. For the TERMZ80
  verifier.

### Hardware evidence: HW / DOC

The earlier reading is consistent with the files: one interactive TERM session on
hardware is probable (README 731), and nothing else. Line 699 is in the Serial (MODE)
section, which makes it a direct contradiction if TERM ran: TERM sets the channel up
through the same INT 14h path. Nothing about flow control, XMODEM or speed is
hardware-verified. The emulator's WD2123 model decides finding 1 and N1-N3. They depend
only on what TERM sends and when, so I expect them to hold on hardware, with one
exception: N1 with /X depends on the host's tty timing. Confirm with João.

## 3. New findings

### N1. Host output is lost while a transfer's "done - a key" waits: BUG, low

After XDONE / XEND, SHOW waits for a key with DOS function 7 in the 8086 interpreter.
Nothing calls RXPOLL then, and ENSURE has let the host go (STOPF = 0) for the transfer.
So everything the host sends meanwhile is lost: sx/rx's closing line, the shell's prompt.
The WD2123 keeps one byte, and LOST counts the overrun once.

Experiment (`after_xfer.py`; fdd86.run returns at once while DOS waits for a key, so the
script spins the wait). The host sends `\r\nhost$ ` 1 s after the transfer; a key comes
4.5 s later:

```
now:   /X: row 1 '' chip lost 7 LOST 1      /R: row 1 '' chip lost 7 LOST 1
fixed: /X: row 1 '' chip lost 7 LOST 1      /R: row 1 'host$' chip lost 1 LOST 1
```

Fix: stop the host (HOLD) as soon as a transfer ends. TERM cannot call HOLD today; the
cheapest way is to expose it: **+2 bytes of TERMZ80** (FTAB entry, `CP 11`), TERMEND
FEBAh, 6 bytes spare. **This changes the image and forces TERM.COM's rebuild.**

```diff
--- TERMZ80.ASM
@@ header
 ;   9 MODE  DL = the flags 8 (local echo) and 10h (LF after each CR)
+;  10 HOLD  stop the host (XOFF / RTS off) till the next SESS, RECV,
+;           SEND or BRK
@@ T_TERM
-        CP 10
+        CP 11
@@ FTAB
-        DW F_FLSH, F_MODE
+        DW F_FLSH, F_MODE, HOLD
--- TERM.ASM
-XDONE:  MOV     DX,OFFSET XFCB
+XDONE:  MOV     AH,10           ; HOLD: the host stopped till SESS
+        CALL    Z80
+        MOV     DX,OFFSET XFCB
@@
 XEND:   PUSH    DX
+        MOV     AH,10           ; HOLD
+        CALL    Z80
```

HOLD takes in 100 ms of what follows. The next SESS (after the key) clears HOLDF and
calls RESUME. **Limit, /X:** the XOFF leaves about 1 ms after the last ACK, while sx/rx
probably still has the tty in raw mode. The host program then reads the XOFF as data,
and only the 100 ms window is saved; the experiment models this (flow off during the
transfer). With /R the fix is complete. Seen from the user, the prompt is missing until
Enter is pressed, hence low.

Test (fails now, passes with the fix, /R):

```python
r = start('TERM AUX:9600 /R'); r.h.flow = 'r'
r.keys('\x01R', 8_000_000); r.keys('IN.BIN\r', 4_000_000); r.tx()
drive(r, sender(data, True))
r.h.host(b'\r\nhost$ ')
end = r.m.tstates + 8_000_000
while r.m.tstates < end:            # DOS waits for a key: spin
    r.m.run(until=end)
r.keys('x', 8_000_000); r.settle()
check(any('host$' in r.term.row(i) for i in range(24)), 'the prompt after a transfer was lost')
```

### N2. Sending: one stale byte makes TERM read every answer one block late: BUG, low-medium

XANS takes the first byte in the ring as the answer to the block just sent. TERM never
discards what came before. Christensen's sender "tosses any characters in its UART buffer
immediately upon completing sending a block" (ymodem.txt §7.4), and ymodem.txt §8.2.3
says that after the first ACK a sender should ignore 'C'. TERM counts any byte other than
ACK as a NAK.

So a receiver's second start-up 'C' that crosses block 1, or any stray byte, has this
effect. TERM resends block 1. The receiver ACKs both copies (the second as a duplicate).
From then on each answer TERM reads belongs to the block before. That goes unnoticed
until the receiver NAKs a block: TERM takes the NAK as the answer to the next block,
resends the wrong one, and the receiver sees block n+1 when it wants n and cancels.

Experiment (`stale_c.py`; a receiver that sends one extra 'C' when block 1 starts, and
NAKs block 4 once):

```
now:   extra C, no NAK : the same bytes | ACK 1 dup 1 ACK 2 ... ACK 10
       extra C, NAK 4  : receiver lost sync | Cancelled by the other side | ... NAK 4 got 5 want 4: CAN
fixed: extra C, NAK 4  : the same bytes | ACK 1 dup 1 ACK 2 ACK 3 NAK 4 ACK 4 ... ACK 10
```

Fix (8086 only): on any answer other than ACK, wait until the line is quiet (PURGE)
before resending, as the receiver does before its NAK. PURGE must then stop reading
into XBUF, because it would overwrite the block that is about to be resent; my first try
did exactly that, and every resend was "bad". It reads one byte at a time into ANSB
instead, which keeps the same rule (0.3 s with nothing):

```diff
--- TERM.ASM
-XS51:   INC     [TRIES]
+XS51:   CALL    PURGE           ; not ACK: the line quiet first, so no
+        INC     [TRIES]         ;   late answer is taken for the next
@@
-; PURGE: wait till nothing comes for 0.3 s
-PURGE:  MOV     CX,133
+; PURGE: wait till nothing comes for 0.3 s (not into XBUF: XSEND sends
+; it again)
+PURGE:  MOV     CX,1
         MOV     DX,30
         XOR     BX,BX
-        CALL    XGET
+        MOV     DI,OFFSET ANSB
+        CALL    XGETDI
```

TERMZ80 is unchanged. Each retry costs 0.3 s more. I also tried a FLUSH (AH=8) before
each send, which is closer to Christensen's rule. It does not survive the emulator's
timing (the duplicate's ACK can come after the flush). Purging on a non-ACK is the robust
choice, and the receive path (XRBAD) still passes test_term's corrupted-block case.

Test: `stale_c.py`'s `receiver(extra_c=True, nak_block=4)` driven with `drive()`, then
`check(got == padded)`.

### N3. Receiving: a line hit on a block's SOH ends the transfer as "done" (or "cancelled"): BUG, medium

XR1 looks only at the first byte of what XGET returns. If it is EOT, XREOT ACKs and
reports success, even when CX = 133 (a whole block followed it). If it is CAN, the
transfer is cancelled. One hit turning 01h into 04h therefore ends the receive early
with **"Receiving: 256 bytes: done"**: a truncated file reported as complete. The sender
takes the ACK as the block's and carries on into TERM's session screen. ymodem.txt's
diagrams show receivers NAKing the first EOT for this reason. Two CANs (§4.1) protect the
CAN case.

Experiment (`eot_hit.py`, 1280 bytes, block 3's SOH hit once):

```
now:   01h->04h: file 256 bytes (want 1280) | Receiving: 256 bytes: done - a key
       01h->18h: file 256 bytes (want 1280) | Cancelled by the other side - a key
fixed: both    : file 1280 bytes, the same bytes | Receiving: 1280 bytes: done
```

Fix (8086 only): EOT counts only when nothing follows it within 1 s (CX = 1), and CAN
only as two CANs. Anything else starting with them is a bad block (PURGE, NAK).

```diff
--- TERM.ASM
         CMP     AL,EOT
         JNZ     XR2
+        CMP     CX,1            ; an EOT alone, not a block's first byte
+        JNZ     XR4             ;   hit by noise
         JMP     XREOT
 XR2:    CMP     AL,CAN
         JNZ     XR3
+        CMP     CX,1            ; two CANs, as YMODEM's graceful abort
+        JNA     XR3
+        CMP     BYTE PTR [XBUF+1],CAN
+        JNZ     XR4
         JMP     XRCAN
 XR3:    MOV     [XREPLY],0      ; noise: wait on
         JMP     XR1
+XR4:    JMP     XRBAD
```

A genuine EOT is a single byte followed by silence. That is what every sender does, and
test_term's senders still pass. A lone CAN now counts as noise. Test: `eot_hit.py`'s
sender with `hitbyte` 4 and 18h, then `check(r.file('IN.BIN') == padded and 'done' in
row 23)`.

### N4. An arrow key at the menu or at a file-name question: NOTE, low

The terminal sends an arrow as ESC + letter. The menu (any other key: back) and ASKF (ESC:
no) take the ESC, and the letter then goes to the host as typed. `menu_arrow.py`: menu
then ESC A sends `A` to the host; "Log to file:" then ESC B sends `B`. This is a small
surprise, not data loss. Leave, or have MENU7 / ASKNO drop a key that is already waiting
(PEEKEY-style AH=0Bh) after ESC.

### N5. TERMZ80 header "at a quarter": DOC, low (TERMZ80's volume)

See Cross-volume. Fix in TERMZ80.ASM line 27: "below 256 bytes it is let go again". The
change is a comment only and the image stays the same.

## 4. Recommended fixes, in order

1. **Finding 1** (BUG, medium): `XOR CX,CX / CALL SEND` in QUIT. 8086 only, TERMZ80 image
   unchanged. The optional INIT XON (+1 Z80 byte) needs a test_term change; leave it to
   the author.
2. **N3** (BUG, medium): EOT only alone and CAN only doubled, on receive (this covers
   finding 2's receive side). 8086 only.
3. **N2** (BUG, low-medium): PURGE on a non-ACK while sending; PURGE reads into ANSB.
   8086 only.
4. **N1** (BUG, low): HOLD at XDONE / XEND. **+2 bytes of TERMZ80 (FEBAh, 6 spare): the
   image changes, TERM.COM is rebuilt.**
5. **Finding 8, 12, N5** (DOC): the header comment and README for /64; README line 731
   (ask João); TERMZ80 header "an eighth / below 256". No binary change.
6. Leave: 2 (send side), 3, 4, 5, 6 (perhaps a README line about the 3 s), 7, 9-11,
   13-16, N4.

With fixes 1-4 together (TERM_fix4.ASM + TERMZ80_hold.ASM in the scratch dir):
TERMEND = FEBAh (≤ FEC0h), TERM.COM 6722 bytes (MD5 079cdf1b03d32fd85e61b176485c5219),
test_term.py "all ok", and every experiment above gives its "fixed" line. Full diffs:
`term_fix4.diff`, `termz80_hold.diff` (and `termz80_init.diff` for the optional INIT
change) in the scratch dir.
