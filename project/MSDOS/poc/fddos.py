"""MS-DOS 1.25 on a modelled FDD3000: the 8086 interpreter plus the BIOS traps.

This is the reference model for the Z80 version: the guest gets MEMTOP
paragraphs of 8086 memory (52 KB, what is left of the FDD3000's 64 KB after
the interpreter), disks are FDD3000 DSK images (16 x 256-byte sectors per
track), and the console is the terminal on the far side of the 2Fh link.

    python3 fddos.py MSDOS.DSK                 interactive
    python3 fddos.py MSDOS.DSK --keys 'DIR\\r'  scripted, prints the screen
"""
import argparse
import datetime
import os
import sys

from cpu86 import CPU, Halt, AX, BX, CX, DX, CS, DS

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'cpm80ds'))
import fdd  # noqa: E402

BIOSSEG, DOSSEG = 0x40, 0x60
MEMTOP = 0x0D00                 # 52 KB guest RAM
SPT = 18                        # sectors per track, IDs 0-17
SKEW = [0, 2, 4, 6, 8, 10, 12, 14, 16, 1, 3, 5, 7, 9, 11, 13, 15, 17]   # 2:1
FIRDIR, FIRREC = 5, 13          # first directory sector, first data sector


class WaitInput(Exception):
    pass


def chs(disk, lsec):
    """Logical sector -> (logical track, sector ID), 2:1 interleave."""
    return lsec // SPT, SKEW[lsec % SPT]


def sysfile(d, i, name):
    """Directory entry i of disk d, which must be name (as 'IO      SYS'):
    the file's contents, contiguous from its first cluster (as COLD in
    BIOS.ASM reads it)."""
    e = d.lsector(*chs(d, FIRDIR))[32 * i:32 * i + 32]
    assert e[:11] == name.encode(), 'no %s: %r' % (name, e[:11])
    clus, size = e[26] | e[27] << 8, int.from_bytes(e[28:32], 'little')
    first = FIRREC + 4 * (clus - 2)
    return Machine.read_lsecs(d, first, (size + 255) // 256)[:size]


class Machine:
    def __init__(self, disks):
        self.disks = disks
        self.cpu = CPU()
        self.cpu.trap = self.trap
        self.cpu.int_hook = lambda n: False
        self.keys = bytearray()
        self.out = bytearray()
        self.echo = None
        self.day_offset = datetime.timedelta(0)

    # ---------- boot: what the boot sector and COLD do ----------
    def boot(self):
        d = self.disks[0]
        io = sysfile(d, 1, 'IO      SYS')
        dos = sysfile(d, 2, 'MSDOS   SYS')
        m = self.cpu.mem
        m[BIOSSEG * 16:BIOSSEG * 16 + len(io)] = io
        m[DOSSEG * 16:DOSSEG * 16 + len(dos)] = dos
        c = self.cpu
        c.s[CS], c.ip = BIOSSEG, 0
        for i in range(4):
            c.s[i] = BIOSSEG if i in (CS, DS) else 0

    @staticmethod
    def read_lsecs(d, first, n):
        return b''.join(d.lsector(*chs(d, s)) for s in range(first, first + n))

    # ---------- traps ----------
    def trap(self, n):
        c = self.cpu
        r = c.r
        if n == 1:                         # STATUS
            if self.keys:
                c.setr8(0, self.keys[0])
                c.zf = 0
            else:
                c.zf = 1
        elif n == 2:                       # INP
            if not self.keys:
                c.ip = (c.ip - 2) & 0xFFFF
                raise WaitInput()
            c.setr8(0, self.keys.pop(0) & 0x7F)
        elif n == 3:                       # OUTP
            self.conout(r[AX] & 0xFF)
        elif n in (4, 6):                  # PRINT, AUXOUT
            pass
        elif n == 5:                       # AUXIN
            c.setr8(0, 0x1A)
        elif n in (7, 8):                  # READ / WRITE
            self.disk_io(n == 8)
        elif n == 9:                       # DSKCHG: don't know
            c.setr8(4, 0)
            c.cf = 0
        elif n == 10:                      # SETDATE AX = days since 1-1-80
            want = datetime.date(1980, 1, 1) + datetime.timedelta(days=r[AX])
            self.day_offset = want - datetime.date.today()
        elif n == 11:                      # SETTIME: keep host time
            pass
        elif n == 12:                      # GETTIME
            now = datetime.datetime.now()
            days = (now.date() + self.day_offset - datetime.date(1980, 1, 1)).days
            r[AX] = days & 0xFFFF
            r[CX] = now.hour << 8 | now.minute
            r[DX] = now.second << 8 | now.microsecond // 10000
        elif n == 13:                      # FLUSH
            self.keys.clear()
        elif n == 14:                      # MAPDEV
            pass
        elif n == 0x1B:                    # FORMAT TRACK (FORMAT.COM)
            self.format_track()
        elif n >= 0x10:
            self.rom_bios(n)
        else:
            raise Halt('BIOS trap %02X' % n)

    def conout(self, ch):
        self.out.append(ch)
        if self.echo:
            self.echo(ch)

    def rom_bios(self, n):
        """The bits of the IBM PC ROM BIOS that PC-DOS programs use, mapped
        onto the VT52 terminal (80 x 24)."""
        c = self.cpu
        r = c.r
        ah, al = r[AX] >> 8, r[AX] & 0xFF
        if n == 0x10:
            if ah == 0x0E:                 # teletype
                self.conout(al)
            elif ah == 0x0F:               # video mode: 80-column mono
                r[AX] = 0x5007
                r[BX] &= 0x00FF
            elif ah == 0x02:               # set cursor: VT52 ESC Y
                row, col = min(r[DX] >> 8, 23), min(r[DX] & 0xFF, 79)
                for ch in (0x1B, ord('Y'), row + 32, col + 32):
                    self.conout(ch)
            elif ah == 0x03:               # read cursor (not tracked)
                r[DX] = 0
                r[CX] = 0x0607
            elif ah in (0x06, 0x07) and al == 0:   # clear window: clear screen
                for ch in b'\x1bH\x1bJ':
                    self.conout(ch)
            elif ah in (0x09, 0x0A):       # write char CX times
                for _ in range(r[CX]):
                    self.conout(al)
        elif n == 0x11:                    # equipment: 2 floppies, mono 80x25
            r[AX] = 0x0071
        elif n == 0x12:                    # memory size in KB
            r[AX] = MEMTOP * 16 // 1024
        elif n == 0x16:                    # keyboard
            if ah == 0:
                if not self.keys:
                    c.ip = (c.ip - 2) & 0xFFFF
                    raise WaitInput()
                r[AX] = self.keys.pop(0) & 0x7F
            elif ah == 1:
                c.zf = 0 if self.keys else 1
                if self.keys:
                    r[AX] = self.keys[0] & 0x7F
            else:
                c.setr8(0, 0)
        elif n == 0x17:                    # printer: ready
            c.setr8(4, 0x90)
        elif n == 0x1A and ah == 0:        # ticks since midnight
            now = datetime.datetime.now()
            t = int((now.hour * 3600 + now.minute * 60 + now.second) * 18.2065)
            r[CX], r[DX] = t >> 16, t & 0xFFFF
            c.setr8(0, 0)

    def disk_io(self, write):
        c = self.cpu
        r = c.r
        drive = r[AX] & 0xFF
        if drive >= len(self.disks) or self.disks[drive] is None:
            c.setr8(0, 2)                  # not ready
            c.cf = 1
            return
        d = self.disks[drive]
        seg, off = c.s[DS], r[BX]
        total = d.tracks * SPT
        while r[CX]:
            s = r[DX]
            if s >= total:
                c.setr8(0, 8)              # sector not found
                c.cf = 1
                return
            base = (seg << 4) + off
            if write:
                d.set_lsector(*chs(d, s), bytes(c.mem[(base + i) & 0xFFFFF] for i in range(256)))
            else:
                data = d.lsector(*chs(d, s))
                for i in range(256):
                    c.mem[(base + i) & 0xFFFFF] = data[i]
            off += 256
            r[DX] = (r[DX] + 1) & 0xFFFF
            r[CX] -= 1
        c.cf = 0

    FMTLEN = 32 + SPT * 332

    def format_track(self):
        """AL = drive, DL = track, DS:BX = the WD177x write-track image:
        its sectors (F5 F5 F5 FE C H R N ... F5 F5 F5 FB data) go on the
        track, as BIOS.ASM's T_FMT and cpm80ds's FDC do it."""
        c = self.cpu
        r = c.r
        drive, trk = r[AX] & 0xFF, r[DX] & 0xFF
        if drive >= len(self.disks) or self.disks[drive] is None:
            c.setr8(0, 2)
            c.cf = 1
            return
        d = self.disks[drive]
        if trk >= d.cyls:
            c.setr8(0, 8)
            c.cf = 1
            return
        base = (c.s[DS] << 4) + r[BX]
        t = bytes(c.mem[base:base + self.FMTLEN])
        i, found = 0, False
        while True:
            i = t.find(b'\xF5\xF5\xF5\xFE', i)
            j = t.find(b'\xF5\xF5\xF5\xFB', i + 8) if i >= 0 else -1
            if j < 0:
                break
            sec, data = t[i + 6], t[j + 4:j + 260]
            if sec < d.spt and len(data) == 256:
                d.set_sector(trk, 0, sec, data)
                found = True
            i = j + 260
        (d.unformatted.discard if found else d.unformatted.add)((trk, 0))
        c.cf = 0

    # ---------- running ----------
    def run(self, limit=None):
        """Run until the guest waits for a key with none queued."""
        c = self.cpu
        start = c.cycles
        try:
            while not c.halted:
                c.step()
                if limit and c.cycles - start > limit:
                    raise Halt('instruction limit')
        except WaitInput:
            pass

    def type(self, s):
        self.keys += s.encode('latin-1') if isinstance(s, str) else s
        self.run()

    def screen(self):
        return self.out.decode('latin-1').replace('\r\n', '\n')


def interactive(m):
    import termios
    import tty
    m.echo = lambda ch: (sys.stdout.write(chr(ch)), sys.stdout.flush())
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        m.run()
        while True:
            ch = os.read(fd, 1)
            if ch == b'\x1d':                # Ctrl-] quits
                break
            m.keys += b'\r' if ch == b'\n' else ch
            m.run()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('disk')
    ap.add_argument('diskb', nargs='?')
    ap.add_argument('--keys', help='scripted input; \\r = Enter')
    ap.add_argument('--save', action='store_true', help='write disks back')
    a = ap.parse_args()
    disks = [fdd.Disk.load(a.disk)] + ([fdd.Disk.load(a.diskb)] if a.diskb else [])
    m = Machine(disks)
    m.boot()
    if a.keys is None:
        interactive(m)
    else:
        m.run()
        m.type(a.keys.encode().decode('unicode_escape'))
        print(m.screen())
        print('[%d instructions]' % m.cpu.cycles, file=sys.stderr)
    if a.save:
        disks[0].save(a.disk)
        if a.diskb:
            disks[1].save(a.diskb)


if __name__ == '__main__':
    main()
