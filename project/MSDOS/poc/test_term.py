"""TERM.COM (TERM.ASM, TERMZ80.ASM) on the emulated FDD3000 (fdd86.py), with
a model of the Terminal 3000's screen (test_edit.Term) and a host on the
WD2123's channel B that sends in real time (fdd86.WD2123: one byte per
character time; the one the chip holds is lost if the next comes first).

The terminal's screen is checked against VT, a Python model of the
VT100 / VT52 that TERM shows the host: every cell but the bottom right one
(which TERM never writes: the terminal would scroll), and the cursor.

1. Start-up: TERM AUX:9600, the line it shows.
2. Codes, one at a time: text, wrapping, cursor moves, erasing, inverse,
   scrolling regions, inserting and deleting lines and characters, tabs,
   line drawing characters, UTF-8, saving the cursor, and what TERM answers
   (cursor position, device attributes).
3. 60 batches of random codes, against VT.
4. Keys: as they are, the arrows (ESC [ A, ESC O A in cursor key mode),
   ESC alone; the menu's Ctrl-A and break. Local echo (/E, the menu's E):
   keys on the screen, CR as CR LF, not the arrows; VT52 arrows. /C (the
   menu's C): an implicit LF after each CR received.
5. Load: 6 KB of text with a terminal that takes 2 ms a character and
   20 ms a scroll (a guess at the real one), at 9600 and 19200 baud, with
   XON / XOFF, with RTS / CTS (nothing lost) and with no flow control
   (bytes lost, as expected). The speed with a terminal that takes no time.
   A scrolling region at 19200 baud (rows drawn again from the shadow):
   nothing lost.
6. The log: on, 12 KB through the 8 KB buffer, off: the file is every byte.
7. XMODEM receive (CRC, a corrupted block sent again; checksums, when the
   sender doesn't take 'C') and send (CRC, checksums): the files.
   A key cancels a transfer; a line hit on a block's SOH (into EOT or CAN)
   is a bad block, two CANs cancel; a stale answer while sending; the
   host's output after a transfer kept (/R).
   A failed or cancelled receive leaves no partial file; a receive waits
   10 s for a block once one has come; a lone CAN while sending is a line
   hit (the block goes again), two cancel.
8. /52 (a VT52 host) and /80 (80 columns).
9. Quit lets the host go (XON with /X, RTS on with /R).

    python3 test_term.py
"""
import os
import random
import sys

import mkfat
import test_edit
import test_fdd86
import test_z86
import z86

FAILS = []
B = test_z86.B
TS = z86.termz80()[1]
ESC = '\x1b'
GR = ' *#HFCLo#NV+++++~--__++++|<>p#f.'


def lost(r):
    """(bytes lost at the chip: overwritten, or sent while it could not
    take them, TERM's LOST). LOST counts each overrun once more (RXPOLL
    sees its OE bit) and a full ring, so the two are kept apart."""
    return r.h.lost + r.h.deaf, r.word('LOST')


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print('  FAIL', what)


class VT:
    """The screen the host sees: TERMZ80.ASM's VT100 subset (or VT52)."""

    def __init__(self, rows=24, cols=64, vt52=False, crlf=False):
        self.rows, self.cols, self.vt52, self.crlf = rows, cols, vt52, crlf
        self.replies = bytearray()
        self.reset()

    def reset(self):
        self.ch = [[(' ', 0)] * self.cols for _ in range(self.rows)]
        self.r = self.c = 0
        self.wrap = 0
        self.attr = 0
        self.top, self.bot = 0, self.rows - 1
        self.awm, self.irm, self.ckm = 1, 0, 0
        self.gl, self.g = 0, [0, 0]
        self.sav = (0, 0, 0)
        self.st = 0
        self.pars, self.priv = [0, 0, 0, 0], 0
        self.npar = 0

    def blank(self):
        return [(' ', 0)] * self.cols

    def setcur(self, r, c):
        self.r, self.c = min(r & 255, self.rows - 1), min(c & 255, self.cols - 1)
        self.wrap = 0

    def scroll_up(self, top, bot):
        self.ch[top:bot + 1] = self.ch[top + 1:bot + 1] + [self.blank()]

    def scroll_down(self, top, bot):
        self.ch[top:bot + 1] = [self.blank()] + self.ch[top:bot]

    def index(self):
        self.wrap = 0
        if self.r == self.bot:
            self.scroll_up(self.top, self.bot)
        elif self.r < self.rows - 1:
            self.r += 1

    def rindex(self):
        self.wrap = 0
        if self.r == self.top:
            self.scroll_down(self.top, self.bot)
        elif self.r > 0:
            self.r -= 1

    def put(self, ch):
        if self.wrap:
            self.c = 0
            self.index()
        row = self.ch[self.r]
        if self.irm:
            row[self.c + 1:] = row[self.c:-1]
        row[self.c] = (ch, self.attr)
        if self.c == self.cols - 1:
            self.wrap = self.awm
        else:
            self.c += 1

    def n(self, i=0):
        return self.pars[i] or 1

    def feed(self, data):
        for b in data:
            self.byte(b)

    def byte(self, b):
        ch = chr(b)
        if b >= 0x80:
            if not self.st and b >= 0xC0:
                self.put('?')
            return
        if b < 0x20:
            if b == 0x1B:
                self.st = 1
            elif b in (0x18, 0x1A):
                self.st = 0
            elif b == 0x0D:
                self.c = self.wrap = 0
                if self.crlf:
                    self.index()
            elif b in (0x0A, 0x0B, 0x0C):
                self.index()
            elif b == 0x08:
                self.wrap = 0
                self.c = max(0, self.c - 1)
            elif b == 0x09:
                self.c = min((self.c | 7) + 1, self.cols - 1)
                self.wrap = 0
            elif b in (0x0E, 0x0F):
                self.gl = 1 if b == 0x0E else 0
            return
        if b == 0x7F:
            return
        st = self.st
        if st == 0:
            if self.g[self.gl] and b >= 0x5F:
                ch = GR[b - 0x5F]
            self.put(ch)
        elif st == 1:
            self.st = 0
            self.esc(ch)
        elif st == 2:
            self.csi(b)
        elif st == 3:
            self.st = 0
            self.g[self.pg] = 1 if ch == '0' else 0
        elif st == 4:
            self.st = 0
        elif st == 5:
            self.yrow = (b - 32) & 255
            self.st = 6
        elif st == 6:
            self.st = 0
            self.setcur(self.yrow, (b - 32) & 255)

    def esc(self, ch):
        if self.vt52:
            self.pars[0] = 1
            if ch in 'ABCD':
                self.final(ch)
            elif ch == 'I':
                self.rindex()
            elif ch == 'H':
                self.setcur(0, 0)
            elif ch == 'J':
                self.ed(0)
            elif ch == 'K':
                self.el(0)
            elif ch == 'Z':
                self.replies += b'\x1b/Z'
            elif ch == 'Y':
                self.st = 5
            return
        if ch == '[':
            self.st, self.npar, self.priv, self.pars = 2, 0, 0, [0, 0, 0, 0]
        elif ch == '7':
            self.sav = (self.r, self.c, self.attr)
        elif ch == '8':
            self.attr = self.sav[2]
            self.setcur(*self.sav[:2])
        elif ch == 'D':
            self.index()
        elif ch == 'E':
            self.c = 0
            self.index()
        elif ch == 'M':
            self.rindex()
        elif ch == 'c':
            self.reset()
        elif ch == 'Z':
            self.replies += b'\x1b[?1;0c'
        elif ch == '#':
            self.st = 4
        elif ch in '()':
            self.pg, self.st = ch == ')', 3

    def csi(self, b):
        if b >= ord('<'):
            if b < 0x40:
                self.priv = 1
                return
            self.st = 0
            self.final(chr(b))
        elif b < ord('0') or b == ord(':'):
            return
        elif b == ord(';'):
            self.npar = min(self.npar + 1, 4)
        elif self.npar < 4:
            self.pars[self.npar] = min(255, self.pars[self.npar] * 10 + b - 48)

    def params(self):
        return self.pars[:min(self.npar, 3) + 1]

    def ed(self, p):
        if p == 0:
            self.ch[self.r][self.c:] = [(' ', 0)] * (self.cols - self.c)
            for r in range(self.r + 1, self.rows):
                self.ch[r] = self.blank()
        elif p == 1:
            for r in range(self.r):
                self.ch[r] = self.blank()
            self.ch[self.r][:self.c + 1] = [(' ', 0)] * (self.c + 1)
        else:
            self.ch = [self.blank() for _ in range(self.rows)]

    def el(self, p):
        row = self.ch[self.r]
        if p == 0:
            row[self.c:] = [(' ', 0)] * (self.cols - self.c)
        elif p == 1:
            row[:self.c + 1] = [(' ', 0)] * (self.c + 1)
        else:
            self.ch[self.r] = self.blank()

    def final(self, f):
        p0 = self.pars[0]
        if self.priv:
            if f in 'hl':
                for p in self.params():
                    if p == 1:
                        self.ckm = f == 'h'
                    if p == 7:
                        self.awm, self.wrap = int(f == 'h'), 0
            return
        if f == 'A':
            lim = self.top if self.r >= self.top else 0
            self.r, self.wrap = max(self.r - self.n(), lim), 0
        elif f in 'Be':
            lim = self.bot if self.r <= self.bot else self.rows - 1
            self.r, self.wrap = min(self.r + self.n(), lim), 0
        elif f in 'Ca':
            self.c, self.wrap = min(self.c + self.n(), self.cols - 1), 0
        elif f == 'D':
            self.c, self.wrap = max(self.c - self.n(), 0), 0
        elif f in 'Hf':
            self.setcur(self.n() - 1, self.n(1) - 1)
        elif f in 'G`':
            self.setcur(self.r, self.n() - 1)
        elif f == 'd':
            self.setcur(self.n() - 1, self.c)
        elif f == 'J':
            self.ed(p0)
        elif f == 'K':
            self.el(p0)
        elif f == 'm':
            for p in self.params():
                if p in (0, 27):
                    self.attr = 0
                elif p == 7:
                    self.attr = 0x80
        elif f == 'r':
            top = self.n() - 1
            bot = self.pars[1] if 0 < self.pars[1] < self.rows else self.rows
            if bot - 1 > top:
                self.top, self.bot = top, bot - 1
                self.setcur(0, 0)
        elif f == 'n':
            if p0 == 5:
                self.replies += b'\x1b[0n'
            elif p0 == 6:
                self.replies += b'\x1b[%d;%dR' % (self.r + 1, self.c + 1)
        elif f == 'c':
            if p0 == 0:
                self.replies += b'\x1b[?1;0c'
        elif f in 'hl':
            for p in self.params():
                if p == 4:
                    self.irm = int(f == 'h')
        elif f in 'LM':
            if self.top <= self.r <= self.bot:
                for _ in range(min(self.n(), self.bot - self.r + 1)):
                    (self.scroll_down if f == 'L' else self.scroll_up)(self.r, self.bot)
                self.c = self.wrap = 0
        elif f in '@PX':
            n = min(self.n(), self.cols - self.c)
            row = self.ch[self.r]
            if f == '@':
                row[self.c:] = [(' ', 0)] * n + row[self.c:self.cols - n]
            elif f == 'P':
                row[self.c:] = row[self.c + n:] + [(' ', 0)] * n
            else:
                row[self.c:self.c + n] = [(' ', 0)] * n
            self.wrap = 0
        elif f == 's':
            self.sav = (self.r, self.c, self.attr)
        elif f == 'u':
            self.attr = self.sav[2]
            self.setcur(*self.sav[:2])


def differences(term, vt):
    """-> what differs between the terminal's screen and VT (not the
    bottom right cell), and the cursor."""
    out = []
    for r in range(vt.rows):
        for c in range(vt.cols):
            if (r, c) == (vt.rows - 1, vt.cols - 1):
                continue
            want = vt.ch[r][c]
            got = (term.ch[r][c], 0x80 if term.inv[r][c] else 0)
            if got != want:
                out.append('(%d,%d) %r, want %r' % (r, c, got, want))
    if (term.r, term.c) != (vt.r, vt.c):
        out.append('cursor %s, want %s' % ((term.r, term.c), (vt.r, vt.c)))
    return out


class Rig:
    """The FDD3000 with a disk holding TERM.COM, the terminal's screen and
    the host on channel B."""

    def __init__(self, files=(), cols=64):
        fs = [(f, open(os.path.join(B, f), 'rb').read()) for f in ('COMMAND.COM', 'TERM.COM')]
        self.disk = mkfat.make(fs + list(files), open(os.path.join(B, 'IOFDD.SYS'), 'rb').read(),
                               open(os.path.join(B, 'MSDOS.SYS'), 'rb').read())
        self.m = test_fdd86.booted([self.disk])
        self.term = test_edit.Term(cols=cols)
        self.m.echo = lambda ch: self.term.feed(bytes([ch]))
        self.h = self.m.wd2123.b
        self.txmark = 0

    def word(self, name):
        a = TS[name]
        return self.m.m[a] | self.m.m[a + 1] << 8

    def run(self, t):
        self.m.run(until=self.m.tstates + t)

    def settle(self, most=400_000_000):
        """Run till the host has sent everything and TERM has shown it."""
        end = self.m.tstates + most
        while self.m.tstates < end:
            self.run(1_000_000)
            if not self.h.src and self.h.hold is None and self.word('RHEAD') == self.word('RTAIL'):
                self.run(1_000_000)
                return True
        return False

    def keys(self, k, t=4_000_000):
        self.m.keys.extend(k.encode('latin-1') if isinstance(k, str) else k)
        self.run(t)

    def tx(self):
        """What TERM sent since the last call."""
        out = bytes(self.h.tx[self.txmark:])
        self.txmark = len(self.h.tx)
        return out

    def file(self, name):
        return mkfat.files(self.disk).get(name)


def start(cmd='TERM AUX:9600', cols=64, files=()):
    r = Rig(files, cols)
    r.h.flow = 'x'                      # TERM's default: XON / XOFF
    r.keys(cmd + '\r', 30_000_000)
    return r


def show(r, vt, data, what):
    r.h.host(data.encode('latin-1') if isinstance(data, str) else data)
    vt.feed(data.encode('latin-1') if isinstance(data, str) else data)
    if not r.settle():
        check(False, '%s: TERM did not finish' % what)
    d = differences(r.term, vt)
    check(not d, '%s: %s' % (what, '; '.join(d[:6])))
    rep = r.tx()
    check(rep == bytes(vt.replies), '%s: answered %r, want %r' % (what, rep, bytes(vt.replies)))
    vt.replies.clear()


def startup():
    print('1. start-up')
    r = start()
    check(r.term.row(0).startswith('TERM: Ctrl-A for the menu'), 'the first line: %r' % r.term.row(0))
    check((r.h.mode, r.h.baud) == (0x8E, 14), 'set up: mode %02X baud %d' % (r.h.mode, r.h.baud))
    print('  TERM AUX:9600: the channel set up, the line shown: done')
    return r


CASES = [
    ('text, CR LF', ESC + '[2J' + ESC + '[HHello\r\nworld'),
    ('wrap at the last column', 'x' * 70 + '\r\n' + 'y' * 64 + 'z'),
    ('autowrap off', ESC + '[?7l' + '\r\n' + 'a' * 70 + ESC + '[?7h'),
    ('cursor moves', ESC + '[10;20HA' + ESC + '[3AB' + ESC + '[2BC' + ESC + '[5CD' + ESC + '[9DE'
     + ESC + '[99;99HF' + ESC + '[HG' + ESC + '[12GH' + ESC + '[7dI'),
    ('erase in line', ESC + '[5;1H' + 'abcdefghijklmnop' + ESC + '[5;5H' + ESC + '[K' + ESC + '[6;1H'
     + 'abcdefghij' + ESC + '[6;4H' + ESC + '[1K' + ESC + '[7;1Hzzzz' + ESC + '[2K'),
    ('inverse', ESC + '[8;1H' + ESC + '[7mINV' + ESC + '[0m norm ' + ESC + '[7;1mX' + ESC + '[27mY' + ESC + '[m'),
    ('erase in display', ESC + '[12;30H' + ESC + '[J' + ESC + '[3;3H' + ESC + '[1J'),
    ('scroll the whole screen', ESC + '[H' + ''.join('line %d\r\n' % i for i in range(30)) + 'last'),
    ('the bottom right cell, scrolled up', ESC + '[24;1H' + 'q' * 63 + 'Q' + '\r\nnext'),
    ('reverse index at the top', ESC + '[H' + ESC + 'M' + 'top' + ESC + 'M' + ESC + 'M'),
    ('scrolling region', ESC + '[5;10r' + ESC + '[10;1H' + 'r1\r\nr2\r\nr3' + ESC + '[5;1H' + ESC + 'M' + 'up'
     + ESC + '[r'),
    ('insert / delete lines', ESC + '[2J' + ''.join(ESC + '[%d;1Hrow %d' % (i + 1, i) for i in range(24))
     + ESC + '[4;20r' + ESC + '[6;3H' + ESC + '[2L' + ESC + '[10;1H' + ESC + '[3M' + ESC + '[1;1H' + ESC + '[L'
     + ESC + '[r'),
    ('insert / delete / erase characters', ESC + '[15;1Hthe quick brown fox' + ESC + '[15;5H' + ESC + '[3@'
     + ESC + '[15;12H' + ESC + '[2P' + ESC + '[15;1H' + ESC + '[2X'),
    ('insert mode', ESC + '[16;1Habcdef' + ESC + '[16;3H' + ESC + '[4hXY' + ESC + '[4lZ'),
    ('tabs, backspace', ESC + '[17;1H\tA\tB\t\t\t\t\t\t\tC\b\bD'),
    ('line drawing', ESC + '[18;1H' + ESC + '(0lqqk\x0e' + 'x' + ESC + ')0' + 'mj\x0f' + ESC + '(BABC'),
    ('UTF-8 and 8-bit bytes', ESC + '[19;1Ha\xc3\xa9b\xe2\x94\x80c\x80d'),
    ('save and restore the cursor', ESC + '[20;10H' + ESC + '[7m' + ESC + '7' + ESC + '[1;1H' + ESC + '[0m'
     + 'x' + ESC + '8y' + ESC + '[s' + ESC + '[2;2H' + ESC + '[uz' + ESC + '[m'),
    ('answers: cursor position, status, attributes', ESC + '[5;7H' + ESC + '[6n' + ESC + '[5n' + ESC + '[c'
     + ESC + 'Z' + ESC + '[0c' + ESC + '[>c'),
    ('controls inside a sequence, CAN, unknown codes', ESC + '[21;1H' + ESC + '[3\r;4Hq' + ESC + '[5\x18X'
     + ESC + '#8' + ESC + '=' + ESC + '[?25l' + ESC + '[1;2;3;4;5;7m' + 'inv?' + ESC + '[m\x07'),
    ('reset', 'junk' + ESC + 'c' + 'after reset'),
]


def codes(r):
    print('2. codes, one at a time')
    vt = VT()
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    for what, data in CASES:
        show(r, vt, data, what)
    print('  %d cases: done' % len(CASES))
    return vt


def fuzz(r, vt, batches=60):
    print('3. random codes, %d batches' % batches)
    rnd = random.Random(7)
    pieces = ['text', 'text', 'text', '\r\n', '\r', '\n', '\b', '\t', ESC + 'M', ESC + 'D', ESC + 'E',
              ESC + '7', ESC + '8', '\x0e', '\x0f', ESC + '(0', ESC + '(B', ESC + ')0']

    def csi():
        f = rnd.choice('ABCDHfGdJKmrLM@PXhl' + 'AB' * 3 + 'H' * 4)
        if f in 'hl':
            return ESC + '[' + rnd.choice(['4', '?7', '?1']) + f
        if f == 'm':
            return ESC + '[' + rnd.choice(['', '0', '7', '27', '1;7', '0;7']) + 'm'
        if f == 'r':
            a = rnd.randint(1, 24)
            return ESC + '[%d;%dr' % (a, rnd.randint(a, 24)) if rnd.random() < .7 else ESC + '[r'
        if f in 'Hf':
            return ESC + '[%d;%d%s' % (rnd.randint(0, 26), rnd.randint(0, 70), f)
        n = rnd.choice(['', '0', '1', '2', '3', str(rnd.randint(4, 30))])
        return ESC + '[' + n + f

    for i in range(batches):
        s = ''
        for _ in range(rnd.randint(5, 40)):
            p = rnd.choice(pieces + ['csi'] * 6)
            if p == 'text':
                p = ''.join(rnd.choice('abcdefghijklmnopqrstuvwxyz _-qxlkmj') for _ in range(rnd.randint(1, 70)))
            elif p == 'csi':
                p = csi()
            s += p
        show(r, vt, s, 'batch %d' % i)
    print('  done; lost %d (LOST %d)' % lost(r))


def keys():
    print('4. keys')
    r = start()
    r.tx()
    r.keys('ls -l\x7f\r')
    check(r.tx() == b'ls -l\x7f\r', 'plain keys')
    r.keys('\x1bA\x1bB\x1bC\x1bD')
    check(r.tx() == b'\x1b[A\x1b[B\x1b[C\x1b[D', 'arrows')
    r.h.host(b'\x1b[?1h')
    r.settle()
    r.keys('\x1bA\x1bD')
    check(r.tx() == b'\x1bOA\x1bOD', 'arrows in cursor key mode')
    r.keys('\x1b')
    r.keys('x')
    check(r.tx() == b'\x1bx', 'ESC alone, then x')
    r.keys('\x01\x01', 8_000_000)
    check(r.tx().strip(b'\x11\x13') == b'\x01', 'the menu, Ctrl-A: a Ctrl-A sent')
    r.keys('\x01B', 8_000_000)
    check(r.h.breaks == 1 and r.h.cmd == 0x27, 'the menu, B: a break (%d), command %02X' % (r.h.breaks, r.h.cmd))
    check(r.term.row(23).strip() == '', 'the bottom line after the menu: %r' % r.term.row(23))
    print('  keys, arrows, ESC, menu Ctrl-A and break: done')


def echo():
    print('4b. local echo')
    r = start('TERM AUX:9600 /E')
    vt = VT()
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    r.tx()
    r.keys('hi there\r')
    vt.feed(b'hi there\r\n')
    check(r.tx() == b'hi there\r', '/E: sent')
    r.keys('\x1bA')                     # not echoed: the cursor stays
    check(r.tx() == b'\x1b[A', '/E: the arrow sent')
    show(r, vt, '\x1b[Bfrom the host\r\n', '/E: the host after local echo')
    r.keys('\x01', 8_000_000)
    check('E echo+' in r.term.row(23), '/E: the menu: %r' % r.term.row(23))
    r.keys('E', 8_000_000)
    r.tx()
    r.keys('quiet')
    check(r.tx() == b'quiet', 'echo off: sent')
    d = differences(r.term, vt)
    check(not d, 'echo off: nothing shown: %s' % '; '.join(d[:4]))
    r.keys('\x01E', 8_000_000)
    r.keys('back')
    vt.feed(b'back')
    d = differences(r.term, vt)
    check(not d and r.tx().strip(b'\x11\x13') == b'back', 'echo on again: %s' % '; '.join(d[:4]))
    r = start('TERM AUX:9600 /52 /E')
    vt = VT(vt52=True)
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    r.tx()
    r.keys('ab\x1bAc')
    vt.feed(b'abc')
    d = differences(r.term, vt)
    check(not d and r.tx() == b'ab\x1bAc', 'VT52 /E: %s' % '; '.join(d[:4]))
    print('  /E: keys shown, CR as CR LF, arrows not; menu E off and on; VT52: done')


def crlf():
    print('4c. implicit LF (/C)')
    r = start('TERM AUX:9600 /C /E')
    vt = VT(crlf=True)
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    show(r, vt, 'one\rtwo\rthree\r\n', '/C: CR from the host')
    r.keys('typed\r')
    vt.feed(b'typed\r')                # echoed: one new line, not two
    d = differences(r.term, vt)
    check(not d and r.tx() == b'typed\r', '/C /E: %s' % '; '.join(d[:4]))
    r.keys('\x01', 8_000_000)
    menu = r.term.row(23)
    check('C lf+' in menu and 'E echo+' in menu and menu[62:] == '  ', '/C: the menu: %r' % menu)
    r.keys('C', 8_000_000)
    r.tx()                              # the menu's XOFF / XON
    vt.crlf = False
    show(r, vt, 'abc\rX', '/C off: CR alone')
    print('  /C: CR from the host as CR LF, typed CR once, menu C off: done')


def load():
    print('5. load: 6 KB, a terminal at 2 ms a character, 20 ms a scroll')
    text = b''.join(b'%04d The quick brown fox jumps over the lazy dog, again and again\r\n' % i
                    for i in range(90))
    for baud, flow, opt in ((9600, 'x', '/X'), (19200, 'x', '/X'), (9600, 'r', '/R'), (19200, 'r', '/R'),
                            (9600, None, '/N')):
        r = start('TERM AUX:%d %s' % (baud, opt))
        r.m.link.char_t, r.m.link.scroll_t = 8000, 80000
        r.h.flow = flow
        vt = VT()
        vt.feed(b'TERM: Ctrl-A for the menu')
        vt.setcur(0, 0)
        t0 = r.m.tstates
        r.h.host(text)
        vt.feed(text)
        r.settle(2_000_000_000)
        secs = (r.m.tstates - t0) / 4e6
        chip, cnt = lost(r)
        d = differences(r.term, vt)
        if flow:
            check(chip == cnt == 0 and not d, '%d baud %s: lost %d (LOST %d); %s' % (
                baud, opt, chip, cnt, '; '.join(d[:3])))
        else:
            check(chip + cnt > 0, '%d baud, no flow control: nothing lost?' % baud)
        stops = r.h.tx.count(0x13) if flow == 'x' else ''
        print('  %5d baud %s: %5.1f s, %4d chars/s, lost %d (LOST %d)%s' % (
            baud, opt, secs, len(text) / secs, chip, cnt, ', XOFF %d times' % stops if stops != '' else ''))
    for baud in (9600, 19200):
        r = start('TERM AUX:%d' % baud)
        r.h.flow = 'x'
        t0 = r.m.tstates
        r.h.host(text)
        r.settle(2_000_000_000)
        secs = (r.m.tstates - t0) / 4e6
        print('  %5d baud, a terminal that takes no time: %4d chars/s (the line: %d), XOFF %d times' % (
            baud, len(text) / secs, baud // 10, r.h.tx.count(0x13)))


def region():
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
    check(lost(r) == (0, 0) and not d, 'region at 19200: lost %d (LOST %d); %s' % (lost(r) + ('; '.join(d[:3]),)))
    print('  400 lines of 0-63 characters scrolled in rows 2-23: lost %d (LOST %d)' % lost(r))


def log():
    print('6. the log')
    r = start('TERM AUX:19200')
    r.h.flow = 'x'
    r.keys('\x01L', 8_000_000)
    r.keys('LOG.TXT\r', 8_000_000)
    rnd = random.Random(3)
    data = bytes(rnd.choice(b'abcdefghij klmnop\r\n') for _ in range(12000)) + b'\x1b[7mend\x1b[m'
    r.h.host(data)
    r.settle(2_000_000_000)
    r.keys('\x01L', 20_000_000)
    got = r.file('LOG.TXT')
    check(got == data, 'LOG.TXT: %s bytes, want %d' % (got and len(got), len(data)))
    check(lost(r) == (0, 0), 'lost %d (LOST %d)' % lost(r))
    print('  12 KB logged at 19200 baud (the 8 KB buffer written when full): %s' % (
        'the same bytes' if got == data else 'DIFFERENT'))


def xblock(n, data, crc):
    blk = bytes([1, n & 255, 255 - (n & 255)]) + data
    if crc:
        c = 0
        for b in data:
            c ^= b << 8
            for _ in range(8):
                c = (c << 1 ^ 0x1021 if c & 0x8000 else c << 1) & 0xFFFF
        return blk + bytes([c >> 8, c & 255])
    return blk + bytes([sum(data) & 255])


def drive(r, gen, most=1_200_000_000):
    """Run TERM with a host-side protocol: gen gets what TERM sent, and
    yields what the host sends (None: nothing)."""
    out = next(gen)
    end = r.m.tstates + most
    try:
        while r.m.tstates < end:
            while out is not None:
                r.h.host(out)
                out = gen.send(b'')
            r.run(500_000)
            out = gen.send(r.tx())
    except StopIteration as e:
        r.run(20_000_000)
        return e.value
    return 'timed out'


def sender(data, crc_ok=True, corrupt=()):
    """XMODEM sender on the host."""
    got = b''
    while True:
        got += yield None
        if crc_ok and b'C' in got:
            crc = True
            break
        if b'\x15' in got:
            crc = False
            break
    blocks = [data[i:i + 128].ljust(128, b'\x1a') for i in range(0, len(data), 128)]
    n, tries, naks = 0, 0, 0
    while n < len(blocks):
        blk = xblock(n + 1, blocks[n], crc)
        if n in corrupt and tries == 0:
            blk = blk[:50] + bytes([blk[50] ^ 1]) + blk[51:]
        yield blk
        got = b''
        while not got:
            got += yield None
        if got[-1:] == b'\x06':
            n, tries = n + 1, 0
        elif got[-1:] in (b'\x15', b'C'):
            tries, naks = tries + 1, naks + 1
        else:
            return 'sender: %r' % got
    yield b'\x04'
    got = b''
    while b'\x06' not in got:
        got += yield None
    return 'crc' if crc else 'sum', naks


def receiver(crc):
    """XMODEM receiver on the host. What comes before a block's SOH (the
    XON TERM sends to let the host go) is passed over, as receivers do."""
    out = bytearray()
    buf = b''
    want = 1
    size = 133 if crc else 132
    yield b'C' if crc else b'\x15'
    while True:
        buf += yield None
        buf = buf.lstrip(b'\x11\x13')
        if buf[:1] == b'\x04':
            yield b'\x06'
            return bytes(out)
        if len(buf) >= size:
            blk, buf = buf[:size], buf[size:]
            if blk == xblock(want, blk[3:131], crc):
                out += blk[3:131]
                want += 1
                yield b'\x06'
            else:
                yield b'\x15'


def xmodem():
    print('7. XMODEM')
    rnd = random.Random(5)
    data = bytes(rnd.randrange(256) for _ in range(3000))
    padded = data + b'\x1a' * (-len(data) % 128)
    for baud, crc, corrupt in ((9600, True, (5,)), (19200, True, ()), (9600, False, ())):
        r = start('TERM AUX:%d' % baud)
        r.keys('\x01R', 8_000_000)
        r.keys('IN.BIN\r', 4_000_000)
        r.tx()
        r.h.flow = None                 # and so does sx
        t0 = r.m.tstates
        res = drive(r, sender(data, crc, corrupt))
        got = r.file('IN.BIN')
        check(got == padded, 'receive at %d: %s bytes, want %d (%s)' % (baud, got and len(got), len(padded), res))
        check('done' in r.term.row(23), 'receive: the bottom line %r' % r.term.row(23))
        print('  receive at %5d baud, %s%s: %s, %.1f s' % (
            baud, 'CRC' if crc else 'checksums (after 3 tries with C)',
            ', block 6 corrupted once' if corrupt else '',
            'the same bytes' if got == padded else 'DIFFERENT', (r.m.tstates - t0) / 4e6))
        r.keys('x', 8_000_000)
    for baud, crc in ((9600, True), (19200, False)):
        r = start('TERM AUX:%d' % baud, files=[('OUT.BIN', data)])
        r.keys('\x01S', 8_000_000)
        r.keys('OUT.BIN\r', 4_000_000)
        r.tx()
        r.h.flow = None                 # rx puts the host's line in raw mode
        t0 = r.m.tstates
        got = drive(r, receiver(crc))
        check(got == padded, 'send at %d: %s' % (baud, got if isinstance(got, str) else len(got)))
        print('  send at %5d baud, %s: %s, %.1f s' % (
            baud, 'CRC' if crc else 'checksums', 'the same bytes' if got == padded else 'DIFFERENT',
            (r.m.tstates - t0) / 4e6))


def xkey():
    print('7b. a key during an XMODEM receive cancels it')
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
            r.m.keys.extend(b'x')       # while TERM shows the progress
            typed = r.m.tstates
        got = r.tx()
        ok = typed is not None and b'\x18\x18\x18' in got and r.m.tstates - typed < 4_000_000
        try:
            out = gen.send(got)
        except StopIteration:
            break
    check(ok, 'XMODEM receive: a key did not cancel it within 1 s')
    print('  x typed after 10 s: %s' % ('CAN sent' if ok else 'NOT CANCELLED'))
    r.run(20_000_000)
    check(r.file('IN.BIN') is None, 'XMODEM receive cancelled by a key: IN.BIN left behind')
    print('  the partial IN.BIN: %s' % ('deleted' if r.file('IN.BIN') is None else 'LEFT'))


def hitsender(data, first):
    """XMODEM sender (CRC) whose block 3 starts, the first time, with the
    bytes first instead of SOH (a line hit: EOT, CAN; or CAN CAN, the
    sender cancelling)."""
    got = b''
    while b'C' not in got:
        got += yield None
    blocks = [data[i:i + 128].ljust(128, b'\x1a') for i in range(0, len(data), 128)]
    n, tries = 0, 0
    while n < len(blocks):
        blk = xblock(n + 1, blocks[n], True)
        if n == 2 and tries == 0:
            if first == b'\x18\x18':
                yield first
                return 'sender: cancelled'
            blk = first + blk[1:]
        yield blk
        got = b''
        while not got:
            got += yield None
        if got[-1:] == b'\x06':
            n, tries = n + 1, 0
        elif b'\x18' in got:
            return 'sender: cancelled by TERM'
        else:
            tries += 1
    yield b'\x04'
    got = b''
    while b'\x06' not in got:
        got += yield None
    return 'sender: done'


def slowsender(data, pause):
    """XMODEM sender (CRC) that waits pause steps of drive() (0.125 s
    each) before block 3, as a slow disk or a busy host does. Returns
    what TERM sent meanwhile (a NAK or C: it gave up on the block)."""
    got = b''
    while b'C' not in got:
        got += yield None
    blocks = [data[i:i + 128].ljust(128, b'\x1a') for i in range(0, len(data), 128)]
    n, early = 0, b''
    while n < len(blocks):
        if n == 2 and not early:
            for _ in range(pause):
                early += yield None
            early = early or b'-'
        yield xblock(n + 1, blocks[n], True)
        got = b''
        while not got:
            got += yield None
        if got[-1:] == b'\x06':
            n += 1
    yield b'\x04'
    got = b''
    while b'\x06' not in got:
        got += yield None
    return early


def staleget(extra_c, nak_block, nak=b'\x15'):
    """XMODEM receiver (CRC) that sends a second 'C' as block 1 starts
    (its start-up poll crossing the block) and NAKs block nak_block once.
    Block numbers are checked as a receiver does: one behind is ACKed and
    dropped, any other cancels."""
    out, buf, want, naked = bytearray(), b'', 1, False
    yield b'C'
    sent = not extra_c
    while True:
        buf += yield None
        buf = buf.lstrip(b'\x11\x13')
        if not sent and buf[:1] == b'\x01':
            sent = True
            yield b'C'
        if buf[:1] == b'\x04':
            yield b'\x06'
            return bytes(out)
        if buf[:1] == b'\x18':
            return 'cancelled by TERM'
        if len(buf) >= 133:
            blk, buf = buf[:133], buf[133:]
            n = blk[1]
            if blk != xblock(n, blk[3:131], True):
                yield b'\x15'
            elif n == want == nak_block and not naked:
                naked = True
                yield nak
            elif n == want:
                out += blk[3:131]
                want += 1
                yield b'\x06'
            elif n == want - 1:
                yield b'\x06'
            else:
                yield b'\x18\x18\x18'
                return 'receiver: block %d, want %d' % (n, want)


def xfaults():
    print('7c. XMODEM faults')
    data = bytes(random.Random(5).randrange(256) for _ in range(1280))
    padded = data + b'\x1a' * (-len(data) % 128)
    for first, what in ((b'\x04', 'into EOT'), (b'\x18', 'into CAN')):
        r = start('TERM AUX:9600')
        r.keys('\x01R', 8_000_000)
        r.keys('IN.BIN\r', 4_000_000)
        r.tx()
        r.h.flow = None
        res = drive(r, hitsender(data, first), 400_000_000)
        got = r.file('IN.BIN')
        check(got == padded and 'done' in r.term.row(23), "block 3's SOH hit %s: %s bytes, want %d; %r (%s)" % (
            what, got and len(got), len(padded), r.term.row(23).strip(), res))
        print("  receive, block 3's SOH hit %s: %s" % (what, 'the same bytes' if got == padded else 'DIFFERENT'))
        r.keys('x', 8_000_000)
    r = start('TERM AUX:9600')
    r.keys('\x01R', 8_000_000)
    r.keys('IN.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    drive(r, hitsender(data, b'\x18\x18'), 400_000_000)
    r.run(20_000_000)
    check('Cancelled' in r.term.row(23), 'receive, two CANs: %r' % r.term.row(23).strip())
    print('  receive, two CANs from the sender: %s' % r.term.row(23).strip())
    r = start('TERM AUX:9600', files=[('OUT.BIN', data)])
    r.keys('\x01S', 8_000_000)
    r.keys('OUT.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    got = drive(r, staleget(True, 4))
    check(got == padded, 'send, a stale C and a NAK: %s' % (got if isinstance(got, str) else len(got)))
    print('  send, a second C crossing block 1, block 4 NAKed once: %s' % (
        'the same bytes' if got == padded else got))


def xmore():
    print('7e. XMODEM: no partial file, 10 s for a block, one CAN is noise')
    data = bytes(random.Random(5).randrange(256) for _ in range(1280))
    padded = data + b'\x1a' * (-len(data) % 128)
    r = start('TERM AUX:9600')
    r.keys('\x01R', 8_000_000)
    r.keys('IN.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    drive(r, hitsender(data, b'\x18\x18'), 400_000_000)
    r.run(20_000_000)
    check('Cancelled' in r.term.row(23) and r.file('IN.BIN') is None,
          'receive cancelled by the sender: %r, IN.BIN %s' % (r.term.row(23).strip(), r.file('IN.BIN') and 'LEFT'))
    print('  receive cancelled after 2 blocks: IN.BIN %s' % ('deleted' if r.file('IN.BIN') is None else 'LEFT'))
    r = start('TERM AUX:9600')
    r.keys('\x01R', 8_000_000)
    r.keys('IN.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    early = drive(r, slowsender(data, 56), 400_000_000)
    got = r.file('IN.BIN')
    check(got == padded and early == b'-', 'receive, the sender 7 s late with block 3: TERM sent %r, %s bytes'
          % (early, got and len(got)))
    print('  receive, block 3 sent 7 s late: %s, %s' % (
        'TERM waited' if early == b'-' else 'TERM sent %r' % early, 'the same bytes' if got == padded else 'DIFFERENT'))
    r.keys('x', 8_000_000)
    r = start('TERM AUX:9600', files=[('OUT.BIN', data)])
    r.keys('\x01S', 8_000_000)
    r.keys('OUT.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    got = drive(r, staleget(False, 3, b'\x18'))
    check(got == padded, 'send, block 3 answered with one CAN: %s' % (got if isinstance(got, str) else len(got)))
    print('  send, block 3 answered with one CAN (a line hit): %s' % (
        'the same bytes' if got == padded else got))
    r = start('TERM AUX:9600', files=[('OUT.BIN', data)])
    r.keys('\x01S', 8_000_000)
    r.keys('OUT.BIN\r', 4_000_000)
    r.tx()
    r.h.flow = None
    drive(r, staleget(False, 3, b'\x18\x18'), 100_000_000)
    r.run(20_000_000)
    check('Cancelled' in r.term.row(23) and r.file('OUT.BIN') == data,
          'send, two CANs: %r, OUT.BIN %s' % (r.term.row(23).strip(), 'kept' if r.file('OUT.BIN') == data else 'CHANGED'))
    print('  send, block 3 answered with two CANs: %s; OUT.BIN %s' % (
        r.term.row(23).strip(), 'kept' if r.file('OUT.BIN') == data else 'CHANGED'))


def after():
    print("7d. the host's output while 'done - a key' waits (/R)")
    r = start('TERM AUX:9600 /R')
    r.h.flow = 'r'
    r.keys('\x01R', 8_000_000)
    r.keys('IN.BIN\r', 4_000_000)
    r.tx()
    drive(r, sender(bytes(random.Random(5).randrange(256) for _ in range(1000))))
    r.h.host(b'\r\nhost$ ')             # the shell's prompt, after sx
    end = r.m.tstates + 8_000_000       # 2 s reading the bottom line: DOS
    while r.m.tstates < end:            #   waits for a key, so spin
        r.m.run(until=end)
    r.keys('x', 8_000_000)
    r.settle()
    rows = [r.term.row(i) for i in range(24)]
    check(any('host$' in row for row in rows), 'the prompt after a transfer was lost (lost %d)' % lost(r)[0])
    print('  the prompt sent 0 s after the transfer, a key 2 s later: %s' % (
        'shown' if any('host$' in row for row in rows) else 'LOST'))


def quits():
    print('9. quit lets the host go')
    for opt, flow in (('/X', 'x'), ('/R', 'r')):
        r = start('TERM AUX:9600 ' + opt)
        r.h.flow = flow
        r.keys('\x01', 8_000_000)       # the menu: the host stopped
        r.tx()
        r.keys('Q', 30_000_000)
        check(not r.h.paused and r.h.cmd & 0x20, '%s: Q left the host stopped (command %02X)' % (opt, r.h.cmd))
        if flow == 'x':
            check(r.tx().endswith(b'\x11'), '/X: no XON on quit')
        print('  %s: after Q the host %s, command %02X' % (opt, 'stopped' if r.h.paused else 'goes on', r.h.cmd))


def other():
    print('8. /52 and /80')
    r = start('TERM AUX:9600 /52')
    vt = VT(vt52=True)
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    show(r, vt, ESC + 'H' + ESC + 'J' + 'vt52' + ESC + 'Y' + chr(32 + 5) + chr(32 + 10) + 'at 5,10' + ESC + 'A'
         + 'up' + ESC + 'B' + ESC + 'B' + 'down' + ESC + 'D' + ESC + 'D' + 'L' + ESC + 'C' + 'R'
         + ESC + 'Y' + chr(32 + 20) + chr(32) + 'abcdef' + ESC + 'Y' + chr(32 + 20) + chr(32 + 3) + ESC + 'K'
         + ESC + 'H' + ESC + 'I' + 'top' + ESC + 'Z' + ESC + '[2J', 'VT52 codes')
    r.keys('\x1bA')
    check(r.tx() == b'\x1bA', 'VT52: the arrows as they are')
    r = start('TERM AUX:9600 /80', cols=80)
    vt = VT(cols=80)
    vt.feed(b'TERM: Ctrl-A for the menu')
    vt.setcur(0, 0)
    show(r, vt, ESC + '[2J' + 'w' * 85 + ESC + '[24;1H' + 'b' * 79 + 'B\r\nscrolled' + ESC + '[1;70H' + ESC + '[@@',
         '80 columns')
    print('  done')


def main():
    r = startup()
    vt = codes(r)
    fuzz(r, vt)
    keys()
    echo()
    crlf()
    load()
    region()
    log()
    xmodem()
    xkey()
    xfaults()
    xmore()
    after()
    other()
    quits()
    print('FAILED: %d' % len(FAILS) if FAILS else 'all ok')
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
