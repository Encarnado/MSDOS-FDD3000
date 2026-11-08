"""EDIT.COM (EDIT.ASM) on the emulated FDD3000 (fdd86.py), with a model of
the Terminal 3000's screen.

After every step the screen is checked against the editor's own text (its
gap buffer, read from memory): the rows from the top line on, tabs
expanded and the first column shown applied, the status line, the cursor
on its character, and nothing in the last column. A Python model of the
editing keys (MODEL) checks the text and the cursor too.

1. Loading: tabs, a control byte, a byte above 7FH, a long line.
2. Every key, one step at a time, against MODEL; scrolling a line at a
   time must scroll the terminal (LF on the bottom row, ESC I on the top).
3. 400 random keys, a few per step, against MODEL.
4. Find (^QF, ^L, not found), help (^J), the abandon question (^KQ).
5. Saving: ^KS (CR LF and a ^Z, the old file as .BAK), ^KX, a new file,
   a disk too full (the old file stays), a write-protected disk (DOS's
   question, Retry, then the whole screen again).
6. EDIT without a name, with a wildcard, a file too big, /80.
7. The 2026-11-08 fixes: an arrow key (ESC A..D) at ^K / ^Q or at "Find:"
   inserts nothing; ^Y at "Abandon changes (Y/N)?" does not abandon.

Prints the time of some steps at 4 MHz.

    python3 test_edit.py
"""
import os
import random
import struct
import sys

import mkfat
import test_fdd86
import test_z86

FAILS = []
B = test_z86.B
ESC = '\x1b'
NR = 23                                 # text rows


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print('  FAIL', what)


class Term:
    """The Terminal 3000's screen: VT52 codes as its ROM handles them (from
    cpm80ds/tests/test_edit.py)."""

    def __init__(self, rows=24, cols=64):
        self.rows, self.cols = rows, cols
        self.ch = [[' '] * cols for _ in range(rows)]
        self.inv = [[0] * cols for _ in range(rows)]
        self.r = self.c = 0
        self.mode = None
        self.inverse = 0
        self.lastcol = 0                # characters written in the last column
        self.scrolls = 0                # scrolls up (LF on the bottom row)
        self.rscrolls = 0               # scrolls down (ESC I on the top row)

    def scroll_up(self):
        self.ch = self.ch[1:] + [[' '] * self.cols]
        self.inv = self.inv[1:] + [[self.inverse] * self.cols]

    def scroll_down(self):
        self.ch = [[' '] * self.cols] + self.ch[:-1]
        self.inv = [[self.inverse] * self.cols] + self.inv[:-1]

    def lf(self):
        if self.r == self.rows - 1:
            self.scroll_up()
            self.scrolls += 1
        else:
            self.r += 1

    def clear(self, r, c0):
        for c in range(c0, self.cols):
            self.ch[r][c] = ' '
            self.inv[r][c] = self.inverse

    def feed(self, data):
        for b in data:
            ch = chr(b)
            if self.mode == 'esc':
                self.mode = None
                if ch == 'H':
                    self.r = self.c = 0
                elif ch == 'I':
                    if self.r == 0:
                        self.scroll_down()
                        self.rscrolls += 1
                    else:
                        self.r -= 1
                elif ch == 'J':
                    self.clear(self.r, self.c)
                    for r in range(self.r + 1, self.rows):
                        self.clear(r, 0)
                elif ch == 'K':
                    self.clear(self.r, self.c)
                elif ch == 'L':
                    self.inverse = 1
                elif ch == 'M':
                    self.inverse = 0
                elif ch == 'Y':
                    self.mode = 'y1'
                continue
            if self.mode == 'y1':
                self.yr = b - 32
                self.mode = 'y2'
                continue
            if self.mode == 'y2':
                self.mode = None
                if 0 <= self.yr < self.rows and 0 <= b - 32 < self.cols:
                    self.r, self.c = self.yr, b - 32
                continue
            if ch == ESC:
                self.mode = 'esc'
            elif ch == '\r':
                self.c = 0
            elif ch == '\n':
                self.lf()
            elif ch == '\b':
                self.c = max(0, self.c - 1)
            elif 32 <= b < 127:
                if self.c == self.cols - 1:
                    self.lastcol += 1
                self.ch[self.r][self.c] = ch
                self.inv[self.r][self.c] = self.inverse
                self.c += 1
                if self.c == self.cols:     # the terminal wraps at once
                    self.c = 0
                    self.lf()

    def row(self, r):
        return ''.join(self.ch[r])

    def text(self):
        return '\n'.join(self.row(r).rstrip() for r in range(self.rows))


def expand(line):
    out = ''
    for ch in line:
        if ch == '\t':
            out += ' ' * (8 - len(out) % 8)
        elif ' ' <= ch < '\x7f':
            out += ch
        else:
            out += '?'
    return out


class Model:
    """The editing keys on (text, cursor), as EDIT.ASM does them."""

    def __init__(self, text):
        self.t, self.p, self.goal = text, 0, 0

    def ls(self, p=None):
        p = self.p if p is None else p
        return self.t.rfind('\n', 0, p) + 1

    def le(self, p):
        e = self.t.find('\n', p)
        return len(self.t) if e < 0 else e

    def col(self):
        return len(expand(self.t[self.ls():self.p]))

    def walk(self, s, e):
        c = 0
        while s < e:
            n = (c | 7) + 1 if self.t[s] == '\t' else c + 1
            if n > self.goal:
                break
            c, s = n, s + 1
        return s

    def up(self):
        s = self.ls()
        if s == 0:
            return False
        self.p = self.walk(self.ls(s - 1), s - 1)
        return True

    def down(self):
        e = self.t.find('\n', self.p)
        if e < 0:
            return False
        self.p = self.walk(e + 1, self.le(e + 1))
        return True

    @staticmethod
    def word(ch):
        return ch.isascii() and ch.isalnum()

    def ins(self, s):
        self.t = self.t[:self.p] + s + self.t[self.p:]

    def delete(self, a, b):
        self.t = self.t[:a] + self.t[b:]

    def key(self, k):
        t, p = self.t, self.p
        vert = k in ('\x05', '\x18', '\x03', '\x12', ESC + 'A', ESC + 'B')
        if k in ('\x13', ESC + 'D'):
            self.p = max(0, p - 1)
        elif k in ('\x04', ESC + 'C'):
            self.p = min(len(t), p + 1)
        elif k in ('\x05', ESC + 'A'):
            self.up()
        elif k in ('\x18', ESC + 'B'):
            self.down()
        elif k in ('\x03', '\x12'):
            for _ in range(NR - 1):
                if not (self.down() if k == '\x03' else self.up()):
                    break
        elif k == '\x06':
            while p < len(t) and self.word(t[p]):
                p += 1
            while p < len(t) and not self.word(t[p]):
                p += 1
            self.p = p
        elif k == '\x01':
            while p and not self.word(t[p - 1]):
                p -= 1
            while p and self.word(t[p - 1]):
                p -= 1
            self.p = p
        elif k == '\x11S':
            self.p = self.ls()
        elif k == '\x11D':
            self.p = self.le(p)
        elif k == '\x11R':
            self.p = 0
        elif k == '\x11C':
            self.p = len(t)
        elif k in ('\r', '\t') or ' ' <= k <= '~':
            self.ins('\n' if k == '\r' else k)
            self.p += 1
        elif k == '\x0e':
            self.ins('\n')
        elif k in ('\x7f', '\x08'):
            if p:
                self.delete(p - 1, p)
                self.p -= 1
        elif k == '\x07':
            self.delete(p, p + 1)
        elif k == '\x11Y':
            self.delete(p, self.le(p))
        elif k == '\x19':
            s, e = self.ls(), self.le(p)
            self.delete(s, e + 1)
            self.p = s
        elif k == '\x14':
            if p < len(t):
                q = p + 1
                if t[p] == '\n':
                    pass
                else:
                    if self.word(t[p]):
                        while q < len(t) and self.word(t[q]):
                            q += 1
                    while q < len(t) and t[q] in ' \t':
                        q += 1
                self.delete(p, q)
        else:
            raise ValueError(repr(k))
        if not vert:
            self.goal = self.col()


class Ed:
    """DOS on the FDD3000 with EDIT.COM on its disk; the terminal model is
    fed everything DOS and the editor send."""

    def __init__(self, files, protect=()):
        disk = [('COMMAND.COM', open(os.path.join(B, 'COMMAND.COM'), 'rb').read()),
                ('EDIT.COM', open(os.path.join(B, 'EDIT.COM'), 'rb').read())] + files
        self.d = mkfat.make(disk, open(os.path.join(B, 'IOFDD.SYS'), 'rb').read(),
                            open(os.path.join(B, 'MSDOS.SYS'), 'rb').read())
        self.m = test_fdd86.booted([self.d], protect=protect)
        self.term = Term()
        self.last = 0.0

    def type(self, keys, cols=None):
        if cols and cols != self.term.cols:
            self.term = Term(cols=cols)
        t0 = self.m.tstates
        out = test_fdd86.step(self.m, keys, limit=400_000_000)
        self.last = (self.m.tstates - t0) / 4e6
        self.term.feed(out.encode('latin-1'))
        return out

    def vars(self):
        mem = bytes(self.m.m)
        a = mem.find(b'EDIT86')
        assert a > 0, 'EDIT86 not in memory'
        v = struct.unpack('<13HB', mem[a + 6:a + 6 + 27])
        names = ('bufs gaps gape tend top topln line left ccol crow cols nr w modif').split()
        v = dict(zip(names, v))
        cs = a - 0x103                  # the segment's linear address
        v['text'] = (mem[cs + v['bufs']:cs + v['gaps']] + mem[cs + v['gape']:cs + v['tend']]).decode('latin-1')
        v['cur'] = v['gaps'] - v['bufs']
        return v

    def files(self):
        return mkfat.files(self.d)

    def verify(self, what, name='T.TXT', msg='', model=None, cursor=True):
        """The screen against the editor's text; with model, the text
        and cursor against it too. cursor=False: a question is asked, the
        cursor is after it."""
        v, t = self.vars(), self.term
        text, cur, w = v['text'], v['cur'], v['w']
        bad = []
        if model is not None and (model.t, model.p) != (text, cur):
            i = next((i for i, (a, b) in enumerate(zip(model.t, text)) if a != b),
                     min(len(model.t), len(text)))
            bad.append('text or cursor: editor %d/%d %r, model %d/%d %r' % (
                cur, len(text), text[i - 10:i + 10], model.p, len(model.t), model.t[i - 10:i + 10]))
        lines = text.split('\n')
        line = text.count('\n', 0, cur) + 1
        ls = text.rfind('\n', 0, cur) + 1
        col = len(expand(text[ls:cur]))
        if (v['line'], v['ccol']) != (line, col):
            bad.append('LINE %d CCOL %d, want %d %d' % (v['line'], v['ccol'], line, col))
        if not 0 <= line - v['topln'] < NR or v['crow'] != line - v['topln']:
            bad.append('top line %d, cursor row %d, line %d' % (v['topln'], v['crow'], line))
        if not v['left'] <= col < v['left'] + w:
            bad.append('column %d not shown from %d' % (col, v['left']))
        for r in range(NR):
            i = v['topln'] - 1 + r
            want = expand(lines[i])[v['left']:v['left'] + w] if i < len(lines) else ''
            if t.row(r + 1) != want.ljust(t.cols):
                bad.append('row %d: %r, want %r' % (r + 1, t.row(r + 1).rstrip(), want))
        st = (' A:' + name + ('*' if v['modif'] else ' ')).ljust(17) + ' Line %-5d Col %-5d %s' % (
            line, col + 1, msg)
        if t.row(0) != st.ljust(t.cols):
            bad.append('status %r, want %r' % (t.row(0).rstrip(), st))
        if t.inv[0] != [1] * 17 + [0] * (t.cols - 17) or any(any(r) for r in t.inv[1:]):
            bad.append('inverse: the name on the status line only')
        if cursor and (t.r, t.c) != (v['crow'] + 1, col - v['left']):
            bad.append('cursor at %s, want %s' % ((t.r, t.c), (v['crow'] + 1, col - v['left'])))
        if t.lastcol:
            bad.append('%d characters in the last column' % t.lastcol)
        for b in bad[:6]:
            check(False, '%s: %s' % (what, b))
        if bad:
            print('    screen:\n' + '\n'.join('      |' + t.row(r) for r in range(t.rows)))
            print('    %r' % {k: v[k] for k in v if k != 'text'})
        return not bad


def sample():
    lines = ['Line %d: the quick brown fox' % i for i in range(1, 61)]
    lines[2] = 'Tabs:\there\tand\there, ^L:\x0c high:\xe9 end'
    lines[5] = 'Long ' + ' '.join('w%03d' % i for i in range(60))
    lines[6] = ''
    lines[7] = '\tindented'
    lines[9] = 'x'
    return '\n'.join(lines) + '\n'


def dos(text):
    return text.replace('\n', '\r\n').encode('latin-1') + b'\x1a'


KEYS = [('right', '\x04'), ('left', '\x13'), ('down', '\x18'), ('up', '\x05'),
        ('ESC B', ESC + 'B'), ('ESC A', ESC + 'A'), ('ESC C', ESC + 'C'), ('ESC D', ESC + 'D'),
        ('word right', '\x06'), ('word left', '\x01'), ('line end', '\x11D'),
        ('line start', '\x11S'), ('page down', '\x03'), ('page up', '\x12'),
        ('file end', '\x11C'), ('file start', '\x11R')]


def loading():
    print('1. loading')
    text = sample()
    e = Ed([('T.TXT', dos(text))])
    e.type('EDIT T.TXT\r')
    print('  EDIT T.TXT (60 lines): %.2f s' % e.last)
    e.verify('load', model=Model(text))
    return e, text


def every_key(e, text):
    print('2. every key, against the model')
    m = Model(text)
    times = {}
    seq = (['\x18'] * 5 + ['\x11D', '\x06', '\x06', '\x01', '\x11S', '\x13', '\x04'] +
           ['\x18'] * 3 + ['\x05'] * 4 + [ESC + 'C'] * 30 + [ESC + 'B', ESC + 'A', ESC + 'D'] +
           ['\x03', '\x03', '\x12', '\x11C', '\x12', '\x11R'])
    for k in seq:
        m.key(k)
        e.type(k)
        times.setdefault(dict((b, a) for a, b in KEYS)[k], e.last)
        if not e.verify('key %r' % k, model=m):
            return
    # scrolling: a line at a time past the bottom, then back past the top
    n = 0
    for k in ['\x18'] * 25 + ['\x05'] * 25:
        m.key(k)
        top, s0, r0 = e.vars()['topln'], e.term.scrolls, e.term.rscrolls
        e.type(k)
        moved = e.vars()['topln'] - top
        if moved == 1:
            times.setdefault('down, scrolling', e.last)
        n += abs(moved)
        check((e.term.scrolls - s0, e.term.rscrolls - r0) == ((1, 0) if moved == 1 else (0, 1) if moved == -1 else (0, 0)),
              '%r: the top line moved by %d, the terminal scrolled %d up, %d down' % (
                  k, moved, e.term.scrolls - s0, e.term.rscrolls - r0))
        if not e.verify('scroll %r' % k, model=m):
            return
    check(n >= 4, 'the top line moved only %d times' % n)
    # editing
    edits = (['\x11R', 'N', 'e', 'w', ' ', '\r', '\t', 'x', '\x7f', '\x7f', '\x7f', '\x18', '\x11D',
              '\x07', '\x07', '\x11S', '\x08', '\x14', '\x14', '\x0e', '\x19', '\x18', '\x04', '\x04',
              '\x11Y', '\x11R'] + ['\x18'] * 5 + ['\x11D'] + list('abc') + ['\r'] * 3 + ['\x7f'] * 2)
    for k in edits:
        m.key(k)
        e.type(k)
        if k == 'w':
            times['type a letter'] = e.last
        if k == '\r' and 'RETURN' not in times:
            times['RETURN'] = e.last
        if not e.verify('edit %r' % k, model=m):
            return
    for k, t in times.items():
        print('  %-18s %.2f s' % (k, t))
    return m


def random_keys(e, m, n=400, seed=1):
    print('3. %d random keys, against the model' % n)
    rnd = random.Random(seed)
    pool = ([k for _, k in KEYS] * 3 + list('abcdefgh   ') * 2 +
            ['\r', '\r', '\t', '\x7f', '\x7f', '\x08', '\x07', '\x07', '\x14', '\x19', '\x11Y', '\x0e'])
    pool.remove('\x11C')                # rarely: they move the whole text
    pool.remove('\x11R')
    done = 0
    while done < n:
        keys = [rnd.choice(pool) for _ in range(rnd.randint(1, 4))]
        for k in keys:
            m.key(k)
        e.type(''.join(keys))
        done += len(keys)
        if not e.verify('random keys %r (after %d)' % (keys, done), model=m):
            return
    print('  done; the text is now %d bytes, %d lines' % (len(m.t), m.t.count('\n') + 1))


def find_help_quit():
    print('4. find, help, quit')
    text = sample()
    e = Ed([('T.TXT', dos(text))])
    e.type('EDIT T.TXT\r')
    m = Model(text)
    e.type('\x11Ffox\r')
    m.p = text.index('fox')
    e.verify('^QF fox', model=m)
    e.type('\x0c')
    m.p = text.index('fox', m.p + 1)
    e.verify('^L', model=m)
    e.type('\x11fLINE 4\r')             # capitals and small letters alike
    m.p = text.index('Line 4')
    e.verify('^QF LINE 4', model=m)
    e.type('\x11F\r')                   # nothing typed: the same again
    m.p = text.index('Line 4', m.p + 1)
    e.verify('^QF RETURN', model=m)
    e.type('\x11Flines\x7f\r')           # DEL takes back
    m.p = text.lower().index('line', m.p + 1)
    e.verify('^QF line', model=m)
    e.type('\x11Fend\x15')               # ^U gives up
    e.verify('^QF ^U', model=m)
    e.type('\x11Fzzz\r')
    e.verify('not found', model=m, msg='Not found')
    e.type('\x0a')
    check('^KS save' in e.term.text() and 'Press a key' in e.term.text(), 'help: %r' % e.term.text())
    e.type(' ')
    e.verify('after help', model=m)
    e.type('x')
    m.key('x')
    e.type('\x0bQ')
    e.verify('^KQ asks', model=m, msg='Abandon changes (Y/N)? ', cursor=False)
    check((e.term.r, e.term.c) == (0, 62), '^KQ: the cursor after the question')
    e.type('N')
    e.verify('^KQ N', model=m)
    out = e.type('\x0bqY')
    check(e.term.text().strip() == 'A:' and out.endswith('A:'), '^KQ Y: %r' % e.term.text())
    check(e.files()['T.TXT'] == dos(text), '^KQ Y: the file changed')


def prompt_fixes():
    print('7. arrow keys at prompts, ^Y at the abandon question')
    text = sample()
    e = Ed([('T.TXT', dos(text))])
    e.type('EDIT T.TXT\r')
    m = Model(text)
    m.key('x')
    e.type('x')                                 # modified, so ^KQ asks
    e.type('\x0b' + ESC + 'A')
    e.verify('^K then ESC A: nothing inserted', model=m)
    e.type('\x11' + ESC + 'C')
    e.verify('^Q then ESC C: nothing inserted', model=m)
    e.type('\x11F' + ESC + 'D')
    e.verify('Find: then ESC D: nothing inserted', model=m)
    e.type('\x0bQ\x19')
    e.verify('^KQ ^Y: still editing, nothing lost', model=m)
    out = e.type('\x0bQy')
    check(e.term.text().strip() == 'A:' and out.endswith('A:'), '^KQ y: %r' % e.term.text())


def saving():
    print('5. saving')
    text = sample()
    e = Ed([('T.TXT', dos(text))])
    e.type('EDIT T.TXT\r')
    m = Model(text)
    for k in ['\x18', '\x18', '\x11D'] + list(' more') + ['\r'] + list('new line'):
        m.key(k)
    e.type('\x18\x18\x11D more\rnew line')
    e.type('\x0bS')
    print('  ^KS, 60 lines: %.2f s' % e.last)
    e.verify('^KS', model=m, msg='Saved')
    f = e.files()
    check(f.get('T.TXT') == dos(m.t), '^KS: T.TXT is not the text')
    check(f.get('T.BAK') == dos(text), '^KS: T.BAK is not the old file')
    check('T.$$$' not in f, '^KS: T.$$$ left')
    saved = m.t
    e.type('!')
    m.key('!')
    out = e.type('\x0bx')
    check(out.endswith('A:'), '^KX: back to DOS %r' % out[-40:])
    f = e.files()
    check(f.get('T.TXT') == dos(m.t) and f.get('T.BAK') == dos(saved), '^KX: T.TXT, T.BAK')
    # a new file
    e.type('EDIT B.\r')
    e.verify('EDIT B. (new)', name='B', msg='New file', model=Model(''))
    e.type('one\rtwo\x0bD')
    f = e.files()
    check(f.get('B') == b'one\r\ntwo\x1a' and 'B.BAK' not in f, 'new file: %r' % f.get('B'))
    # a disk without room for name.$$$ beside the old file: it stays
    big = text * 6
    e = Ed([('T.TXT', dos(big))])
    used = sum((len(d) + 1023) // 1024 * 1024 for d in e.files().values())
    e = Ed([('T.TXT', dos(big)), ('FILL', bytes(180224 - used - 5 * 1024))])
    e.type('EDIT T.TXT\r')
    m = Model(big)
    e.type('X')
    m.key('X')
    e.type('\x0bS')
    e.verify('disk full', model=m, msg='Disk full: not saved')
    f = e.files()
    check(f.get('T.TXT') == dos(big) and 'T.$$$' not in f and 'T.BAK' not in f,
          'disk full: the files are %s' % sorted(f))
    # write protected: DOS asks; Retry once it is writable again
    e = Ed([('T.TXT', dos(text))], protect=(0,))
    e.type('EDIT T.TXT\r')
    m = Model(text)
    e.type('\x18X')
    m.key('\x18')
    m.key('X')
    out = e.type('\x0bS')
    check('Write protect error' in out and 'Abort, Retry, Ignore?' in out, 'protected: %r' % out[-80:])
    e.m.drives[0].protect = False
    e.type('R')
    e.verify('protected, then Retry', model=m, msg='Saved')
    check(e.files().get('T.TXT') == dos(m.t), 'protected, then Retry: T.TXT')


def errors():
    print('6. usage, wildcards, too big, /80')
    e = Ed([('T.TXT', dos(sample())), ('BIG.TXT', b'x' * 45000)])
    out = e.type('EDIT\r')
    check('Usage: EDIT name.ext' in out, 'EDIT: %r' % out)
    out = e.type('EDIT *.TXT\r')
    check('Usage: EDIT name.ext' in out, 'EDIT *.TXT: %r' % out)
    out = e.type('EDIT BIG.TXT\r')
    check('File too big for memory' in out, 'EDIT BIG.TXT: %r' % out)
    e.type('EDIT T.TXT /80\r', cols=80)
    e.verify('/80', model=Model(sample()))
    e.type('\x18\x18\x18\x18\x18\x11D')
    m = Model(sample())
    for k in '\x18\x18\x18\x18\x18':
        m.key(k)
    m.key('\x11D')
    e.verify('/80, a long line', model=m)
    e.type('\x0bQ')
    v = e.vars()
    cap = v['tend'] - v['bufs']
    print('  room for %d bytes of text' % cap)
    # the biggest file: no room for a key; then a 30 KB one, timed
    full = ('y' * 63 + '\n') * (cap // 64) + 'z' * (cap % 64)
    big = ''.join('%05d The quick brown fox jumps over the lazy dog.\n' % i for i in range(550))
    e = Ed([('FULL.TXT', full.encode()), ('BIG.TXT', dos(big))])
    e.type('EDIT FULL.TXT\r')
    m = Model(full)
    e.verify('FULL.TXT', name='FULL.TXT', model=m)
    e.type('a')
    e.verify('memory full', name='FULL.TXT', model=m, msg='Memory full')
    e.type('\x0bQ')
    e.type('EDIT BIG.TXT\r')
    print('  EDIT BIG.TXT, %d bytes: %.2f s' % (len(dos(big)), e.last))
    m = Model(big)
    e.verify('BIG.TXT', name='BIG.TXT', model=m)
    m.key('\x11C')
    e.type('\x11C')
    print('  ^QC: %.2f s' % e.last)
    e.verify('BIG.TXT ^QC', name='BIG.TXT', model=m)
    m.key('!')
    e.type('!\x0bS')
    print('  ^KS: %.2f s' % e.last)
    e.verify('BIG.TXT ^KS', name='BIG.TXT', model=m, msg='Saved')
    check(e.files().get('BIG.TXT') == dos(m.t), 'BIG.TXT saved')


def main():
    e, text = loading()
    m = every_key(e, text)
    if m:
        random_keys(e, m)
    find_help_quit()
    saving()
    errors()
    prompt_fixes()
    print('FAILED: %d' % len(FAILS) if FAILS else 'all ok')
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
