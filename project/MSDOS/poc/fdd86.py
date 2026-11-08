"""MS-DOS 1.25 on an emulated FDD3000, everything in Z80 code.

The interpreter (I86.ASM) and the BIOS (BIOS.ASM) run on cpm80ds's FDD3000
model: its Z80, WD177x and drive latch. Nothing is trapped in Python; the
console is a model of the terminal's end of the 2Fh link (Link), which
speaks the CBIOS A1.1 nibble protocol byte by byte.

It boots as the real unit does: the FDD3000 boot ROM loads the disk's
boot sector (BOOT.ASM), which loads the interpreter and BIOS from the
disk; the BIOS's COLD loads IO.SYS and MSDOS.SYS and starts the 8086.

    python3 fdd86.py MSDOS.DSK [B.DSK]          interactive (Ctrl-] quits)
    python3 fdd86.py MSDOS.DSK --keys 'DIR\\r'   scripted, prints the screen
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cpm80ds'))
import machine  # noqa: E402
import fdd  # noqa: E402
import z86  # noqa: E402
import fddos  # noqa: E402
from cpmemu import _tstates  # noqa: E402


class LinkError(Exception):
    pass


class Link:
    """The terminal's end of the link: what the FDD3000 reads on port 2Fh
    (bits 0-6) and how the terminal answers what the FDD writes there.

    send a character:   FDD 0A -> 0F, 1l -> 1l, 4h -> 4h, 50 (done)
    receive a key:      FDD 06 -> 05 (a key is there), 0F -> 1l,
                        1l -> 4h, 4h -> 50, 50 (done)
    idle:               04 when a key is waiting, else 50
    07 from either side aborts. The terminal answers at once, so the
    FDD's timeouts never run out here."""

    def __init__(self):
        self.keys = bytearray()
        self.out = bytearray()
        self.echo = None
        self.state = 'idle'
        self.v = 0x50
        self.waits = 0                  # 06 with no key: DOS waits for one
        self.key = 0

    def read(self):
        if self.state == 'idle':
            return 0x04 if self.keys else 0x50
        if self.state == 'abort':
            self.state = 'idle'
            return 0x07
        return self.v

    def write(self, v):
        v &= 0x7F
        s = self.state
        if v == 0x07:
            self.state = 'abort'
        elif s in ('idle', 'abort') and v == 0x0A:
            self.state, self.v = 'out1', 0x0F
        elif s in ('idle', 'abort') and v == 0x06:
            if self.keys:
                self.state, self.v, self.waits = 'in0', 0x05, 0
            else:
                self.state = 'idle'
                self.waits += 1
        elif s == 'out1' and v & 0x70 == 0x10:
            self.lo, self.v, self.state = v & 15, v, 'out2'
        elif s == 'out2' and v & 0x70 == 0x40:
            self.hi, self.v, self.state = v & 15, v, 'out3'
        elif s == 'out3' and v == 0x50:
            ch = self.hi << 4 | self.lo
            self.out.append(ch)
            if self.echo:
                self.echo(ch)
            self.state = 'idle'
        elif s == 'in0' and v == 0x0F:
            self.key = self.keys[0]
            self.v, self.state = 0x10 | self.key & 15, 'in1'
        elif s == 'in1' and v & 0x50 == 0x10:
            self.v, self.state = 0x40 | self.key >> 4, 'in2'
        elif s == 'in2' and v & 0x40:
            self.v, self.state = 0x50, 'in3'
        elif s == 'in3' and v == 0x50:
            del self.keys[0]
            self.state = 'idle'
        else:
            raise LinkError('link: FDD wrote %02X in state %s' % (v, s))


class WD2123:
    """The FDD3000's WD2123: two 8251A-compatible serial channels (A: data
    80h, control / status 81h; B: 40h, 41h) and their baud registers (10h,
    11h). What a channel transmits is kept in .tx, .rx is what it will
    receive, .dsr its DSR input. The 8251A's mode / sync / command order is
    modelled, so a wrong set-up sequence shows."""

    class Channel:
        def __init__(self):
            self.state = 'mode'         # after reset: the next control byte is the mode
            self.mode = self.cmd = self.baud = None
            self.syncs = 0
            self.tx = bytearray()
            self.rx = bytearray()
            self.dsr = True
            self.errors = 0             # status bits 3-6
            self.dropped = 0            # bytes written with the transmitter off

        def control(self, v):
            if self.state == 'sync':
                self.syncs -= 1
                if not self.syncs:
                    self.state = 'cmd'
            elif self.state == 'mode':
                self.mode = v
                if v & 3:               # asynchronous
                    self.state = 'cmd'
                else:                   # synchronous: one or two sync characters follow
                    self.state, self.syncs = 'sync', 1 if v & 0x80 else 2
            elif v & 0x40:              # internal reset
                self.state, self.cmd = 'mode', None
            else:
                self.cmd = v
                if v & 0x10:
                    self.errors = 0

        def status(self):
            cmd = self.cmd or 0
            return (0x01 | 0x04 | (0x02 if self.rx and cmd & 4 else 0) | self.errors
                    | (0x80 if self.dsr else 0))

        def write(self, v):
            if self.cmd is not None and self.cmd & 1 and self.state == 'cmd':
                self.tx.append(v)
            else:
                self.dropped += 1

        def read(self):
            return self.rx.pop(0) if self.rx else 0

    def __init__(self):
        self.a, self.b = self.Channel(), self.Channel()

    def port_in(self, p):
        """-> the byte read, or None if p is not ours."""
        ch = {0x80: self.a, 0x81: self.a, 0x40: self.b, 0x41: self.b}.get(p)
        if ch is None:
            return None
        return ch.status() if p & 1 else ch.read()

    def port_out(self, p, v):
        """-> True if p is ours."""
        if p in (0x10, 0x11):
            (self.a if p == 0x10 else self.b).baud = v
        elif p in (0x80, 0x81, 0x40, 0x41):
            ch = self.a if p & 0x80 else self.b
            ch.control(v) if p & 1 else ch.write(v)
        else:
            return False
        return True

    def attach(self, m):
        """Put it on a cpm80ds machine.Machine (the FDD3000 under CP/M)."""
        pin, pout = m.cpu.port_in, m.cpu.port_out

        def port_in(port):
            v = self.port_in(port & 0xFF)
            return pin(port) if v is None else v

        def port_out(port, v):
            if not self.port_out(port & 0xFF, v):
                pout(port, v)
        m.cpu.port_in, m.cpu.port_out = port_in, port_out
        return self


class FDD86(machine.Machine):
    """The FDD3000 running the interpreter and BIOS. disks: fdd.Disk or
    None per drive (A: B: ...); protect: drive numbers write-protected."""

    def __init__(self, disks, protect=(), count_t=True):
        drives = [machine.Drive(cyls=d.cyls, heads=d.sides, disk=d, protect=i in protect)
                  if d is not None else None for i, d in enumerate(disks)]
        self.link = Link()
        self.wd2123 = WD2123()
        super().__init__(drives, max_instr=1 << 62)
        self.disks = disks
        self.syms = z86.build(bios=True)[1]    # the disk's image must match
        self.count_t = count_t
        self.tstates = 0
        self.cycles = 0                 # 8086 instructions
        self.halted = False             # the 8086 ran HLT
        self.stopped = None             # Z80 HALT with interrupts off: at this PC
        self.limit = None

    # the console side: Link instead of trapping the CBIOS
    keys = property(lambda s: s.link.keys, lambda s, v: setattr(s.link, 'keys', v))
    out = property(lambda s: s.link.out, lambda s, v: setattr(s.link, 'out', v))
    echo = property(lambda s: s.link.echo, lambda s, f: setattr(s.link, 'echo', f))

    def port_in(self, port):
        if port & 0xE0 == 0x20:
            return (0x80 if self.fdc.drq else 0) | self.link.read()
        v = self.wd2123.port_in(port & 0xFF)
        return super().port_in(port) if v is None else v

    def port_out(self, port, v):
        if port & 0xFF == 0x2F:
            self.link.write(v)
        elif not self.wd2123.port_out(port & 0xFF, v):
            super().port_out(port, v)

    def boot(self):
        """Reset: the boot ROM runs from 0000h (machine.Machine.boot; without
        the ROM file, its load of sector 0 to 3F00h is done in Python)."""
        super().boot()

    def run(self, limit=None):
        """Run until DOS waits for a key with none typed. limit: Z80
        instructions (default self.limit, None = no limit)."""
        limit = limit or self.limit
        c, m, fdc, link = self.cpu, self.m, self.fdc, self.link
        ops = c.ops
        S = self.syms
        nxt, halt, bad = S['NEXT'], S['HALTED'], S['BADSTOP']
        count = self.count_t
        start = self.icount
        link.waits = 0
        while True:
            if link.waits > 1 and not link.keys:
                return
            self.icount += 1
            if fdc.busy_until is not None or fdc.drq:
                fdc.tick()
            if fdc.intrq and c.iff1:            # IM 1
                c.iff1 = c.iff2 = 0
                c.sp = (c.sp - 2) & 0xFFFF
                m[c.sp] = c.pc & 0xFF
                m[(c.sp + 1) & 0xFFFF] = c.pc >> 8
                c.pc = 0x38
                self.tstates += 13
                continue
            pc = c.pc
            if pc == nxt:
                self.cycles += 1
            elif pc == halt:
                self.halted = True
                return
            elif pc == bad:
                raise RuntimeError('bad 8086 opcode at %04X' % ((c.r[0] << 8 | c.r[1]) - 1))
            if limit and self.icount - start > limit:
                raise RuntimeError('Z80 instruction limit, PC=%04X' % pc)
            op = m[pc]
            if op == 0x76 and not c.iff1:
                self.stopped = pc
                return
            c.pc = (pc + 1) & 0xFFFF
            if count:
                if op == 0xED and m[(pc + 1) & 0xFFFF] >= 0xB0 and m[(pc + 1) & 0xFFFF] & 2 == 0:
                    n0 = (c.r[0] << 8) | c.r[1]
                    ops[op]()
                    k = ((n0 - ((c.r[0] << 8) | c.r[1])) & 0xFFFF) or 0x10000
                    self.tstates += 21 * k - 5
                else:
                    sp0 = c.sp
                    ops[op]()
                    self.tstates += _tstates(m, pc, op, c.pc, c, sp0)
            else:
                ops[op]()

    def type(self, s):
        self.keys.extend(s.encode('latin-1') if isinstance(s, str) else s)
        self.run()

    def screen(self):
        return self.out.decode('latin-1').replace('\r\n', '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('disk')
    ap.add_argument('diskb', nargs='?')
    ap.add_argument('--keys', help='scripted input; \\r = Enter')
    ap.add_argument('--save', action='store_true', help='write disks back')
    a = ap.parse_args()
    disks = [fdd.Disk.load(a.disk)] + ([fdd.Disk.load(a.diskb)] if a.diskb else [])
    m = FDD86(disks)
    m.boot()
    if a.keys is None:
        fddos.interactive(m)
    else:
        m.run()
        m.type(a.keys.encode().decode('unicode_escape'))
        print(m.screen())
        print('[%d 8086 instructions, %d Z80 T-states, %.1f s at 4 MHz]'
              % (m.cycles, m.tstates, m.tstates / 4e6), file=sys.stderr)
    if a.save:
        disks[0].save(a.disk)
        if a.diskb:
            disks[1].save(a.diskb)


if __name__ == '__main__':
    main()
