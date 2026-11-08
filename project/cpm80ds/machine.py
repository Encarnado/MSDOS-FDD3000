"""The FDD3000 disk unit, emulated well enough to boot and run CP/M.

The Z80 is tmxcobol's cpmemu.Z80.  The boot ROM (when found), IPL, CCP, BDOS
and CBIOS are all real code; only the console is
done in Python, by trapping the CBIOS console routines.

Hardware model (from the CBIOS A1.1, TOS and the FDD3000 boot ROM):
    E0h  out  drive latch: bits 0-3 drive select (active low),
              bit 4 side (high = side 0, low = side 1),
              bit 7 high = head unloaded (as Fuse's FDD3000): no IDs read,
              bit 6 low = boot ROM paged in at 0000h-07FFh
    C0h       FDC command / status (WD177x-style)
    C1h       FDC track register,  C2h sector register,  C3h data register
    20h-3Fh   the computer interface; in: bit 7 = FDC DRQ
    the FDC's INTRQ drives the Z80 INT line (IM 1, RST 38h).
"""
import os
import sys

H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(H, '..', 'tmxcobol'))
from cpmemu import Z80  # noqa: E402

CONST, CONIN, CONOUT = 0xF606, 0xF609, 0xF60C       # CBIOS jump table
CONOUT_INT, CONIN_INT = 0xFAA8, 0xFB0D              # used by sign-on / error prompt
BOOT_ROM = os.environ.get('FDD_BOOT_ROM', os.path.join(H, '..', '..', 'roms', 'fdd_boot.rom'))


class Stop(Exception):
    pass


class Drive:
    """cyls = the drive's tracks; like real drives it can step two past the
    last one (COPY and BACKUP step once more after the last track)."""

    def __init__(self, cyls=80, heads=2, disk=None, protect=False):
        self.cyls, self.heads, self.disk, self.protect = cyls, heads, disk, protect
        self.cyl = 0
        self.steps = 0


class FDC:
    T_TYPE1 = 300            # instructions a seek / restore takes
    T_FIND = 120             # until the first data byte of a sector

    def __init__(self, m):
        self.m = m
        self.tr = self.sr = self.dr = 0
        self.status = 0
        self.intrq = False
        self.drq = False
        self.busy_until = None
        self.done_status = 0
        self.buf = None
        self.pos = 0
        self.writing = None
        self.log = []                   # (op, drive, cyl, side, sector)
        self.wtrack = None              # write track in progress: (drive, cyl, side)
        self.last_io = 0                # when the CPU last moved a data byte
        self.formatted = {}             # (drive object id, cyl, side) -> [(C, H, R, N)]
        self.side1_reads = 0

    def drive(self):
        return self.m.selected_drive()

    def track0(self, d):
        return 0x04 if d is not None and d.cyl == 0 else 0

    T_LOST = 2000            # instructions without the CPU taking a byte: lost data

    def tick(self):
        if self.drq and self.wtrack is None and self.m.icount - self.last_io > self.T_LOST:
            # the WD177x goes on without the CPU: zeros are written, the rest
            # of a read is dropped, the command ends with Lost Data
            if self.writing is not None:
                d, c, h, r = self.wloc
                d.disk.set_sector(c, h, r, bytes(self.writing).ljust(256, b'\0'))
            self.buf = self.writing = None
            self.drq = False
            self.finish(0x04, 20)
            return
        if self.busy_until is not None and self.m.icount >= self.busy_until:
            self.busy_until = None
            if self.buf is not None and self.pos == 0 and self.writing is None and self.done_status == -1:
                self.drq = True                 # sector found, data starts
                self.last_io = self.m.icount
                self.done_status = 0
                return
            if self.writing is not None and self.done_status == -1:
                self.drq = True
                self.last_io = self.m.icount
                self.done_status = 0
                return
            self.status = self.done_status
            self.intrq = True

    def command(self, c):
        self.intrq = False
        d = self.drive()
        if c & 0xF0 == 0xD0:                    # force interrupt
            self.busy_until = None
            self.drq = False
            self.buf = self.writing = self.wtrack = None
            self.status = self.track0(d)
            if c & 0x0F:
                self.intrq = True
            return
        self.status = 0x01
        if c & 0x80 == 0:                       # type I
            if d is None:
                self.finish(0x10, self.T_TYPE1)
                return
            op = c >> 4
            if op == 0:                         # restore
                d.steps += d.cyl
                d.cyl = 0
                self.tr = 0
            elif op == 1:                       # seek to the data register
                d.steps += abs(self.dr - self.tr)
                d.cyl = max(0, min(d.cyls + 1, d.cyl + self.dr - self.tr))
                self.tr = self.dr
            elif op in (4, 5):                  # step in
                d.cyl = min(d.cyls + 1, d.cyl + 1)
                d.steps += 1
                if op & 1:
                    self.tr = (self.tr + 1) & 0xFF
            elif op in (6, 7):                  # step out
                d.cyl = max(0, d.cyl - 1)
                d.steps += 1
                if op & 1:
                    self.tr = (self.tr - 1) & 0xFF
            else:
                raise RuntimeError('FDC command %02X' % c)
            st = self.track0(d)
            side = self.m.side() if d.heads == 2 else 0
            if c & 0x04 and (d.disk is None or d.cyl >= d.disk.cyls or self.tr != d.cyl
                             or self.m.latch & 0x80
                             or (d.cyl, side) in d.disk.unformatted):
                st |= 0x10                      # verify: no ID with this track
            self.finish(st, self.T_TYPE1)
            return
        side = self.m.side() if d is not None and d.heads == 2 else 0
        if c & 0xF0 == 0xF0:                    # write track (format)
            if d is None or d.disk is None or d.cyl >= d.disk.cyls or side >= d.disk.sides:
                self.finish(0x10, self.T_FIND)
                return
            if d.protect:
                self.finish(0x40, self.T_FIND)
                return
            self.buf = None
            self.writing = bytearray()
            self.wlen = 0                       # bytes on the track: F7 writes 2 (CRC)
            self.wtrack = (d, d.cyl, side)
            self.log.append(('F', self.m.drive_no(), d.cyl, side, None))
            self.done_status = -1
            self.busy_until = self.m.icount + self.T_FIND
            return
        if d is None or d.disk is None or d.cyl >= d.disk.cyls or side >= d.disk.sides \
                or self.m.latch & 0x80 or self.tr != d.cyl or self.sr >= d.disk.spt or (d.cyl, side) in d.disk.unformatted:
            self.finish(0x10, self.T_FIND * 4)  # record not found
            return
        if c & 0xE0 == 0x80:                    # read sector
            self.buf = bytes(d.disk.sector(d.cyl, side, self.sr))
            self.pos = 0
            self.writing = None
            self.log.append(('R', self.m.drive_no(), d.cyl, side, self.sr))
            self.side1_reads += side
            self.done_status = -1
            self.busy_until = self.m.icount + self.T_FIND
        elif c & 0xE0 == 0xA0:                  # write sector
            if d.protect:
                self.finish(0x40, self.T_FIND)
                return
            self.buf = None
            self.writing = bytearray()
            self.wloc = (d, d.cyl, side, self.sr)
            self.log.append(('W', self.m.drive_no(), d.cyl, side, self.sr))
            self.done_status = -1
            self.busy_until = self.m.icount + self.T_FIND
        else:
            raise RuntimeError('FDC command %02X' % c)

    def finish(self, st, t):
        self.done_status = st
        self.busy_until = self.m.icount + t

    def read_data(self):
        if self.buf is None or not self.drq:
            return self.dr
        self.last_io = self.m.icount
        v = self.buf[self.pos]
        self.pos += 1
        if self.pos == 256:
            self.drq = False
            self.buf = None
            self.finish(0, 20)
        return v

    T_TRACK = 6250                      # bytes in one revolution (DD, 300 rpm)

    def write_data(self, v):
        if self.wtrack is not None and self.drq:
            self.writing.append(v)
            self.wlen += 2 if v == 0xF7 else 1
            if self.wlen >= self.T_TRACK:
                self.end_track()
            return
        if self.writing is not None and self.drq:
            self.last_io = self.m.icount
            self.writing.append(v)
            if len(self.writing) == 256:
                d, c, h, r = self.wloc
                d.disk.set_sector(c, h, r, bytes(self.writing))
                self.writing = None
                self.drq = False
                self.finish(0, 20)
            return
        self.dr = v

    def end_track(self):
        """Index pulse: parse the written track (F5 = A1 sync, F7 = CRC)
        and store its sectors; the IDs are kept for the tests."""
        d, c, h = self.wtrack
        t, ids, i = bytes(self.writing), [], 0
        while True:
            i = t.find(b'\xF5\xF5\xF5\xFE', i)
            if i < 0:
                break
            cid = tuple(t[i + 4:i + 8])
            j = t.find(b'\xF5\xF5\xF5\xFB', i + 8)
            if j < 0:
                break
            data = t[j + 4:j + 4 + 256]
            ids.append(cid)
            if len(data) == 256 and cid[2] < d.disk.spt:
                d.disk.set_sector(c, h, cid[2], data)
            i = j + 4 + 256
        self.formatted[(id(d), c, h)] = ids
        if ids:
            d.disk.unformatted.discard((c, h))
        else:
            d.disk.unformatted.add((c, h))
        self.wtrack = self.writing = None
        self.drq = False
        self.finish(0, 20)

    def read_status(self):
        self.intrq = False
        st = self.status
        if self.busy_until is not None or self.drq:
            st |= 0x01
        if self.drq:
            st |= 0x02
        return st


class Machine:
    def __init__(self, drives, max_instr=400_000_000, bias=0):
        self.cpu = Z80()
        self.m = self.cpu.m
        self.drives = drives                    # list of up to 4 Drive (or None)
        self.latch = 0xFF
        self.rom = None                         # RAM under the boot ROM while it is paged in
        self.fdc = FDC(self)
        self.icount = 0
        self.max_instr = max_instr
        self.out = bytearray()
        self.input = bytearray()
        self.on_prompt = None                   # called when the CCP waits for a line
        self.polls = 0                          # console status checks with no input
        self.bias = bias                        # a MOVCPM'd system: CBIOS at F600h - bias
        self.cpu.port_in = self.port_in
        self.cpu.port_out = self.port_out

    # ---- latch ----
    def drive_no(self):
        for i in range(4):
            if not self.latch & (1 << i):
                return i
        return None

    def selected_drive(self):
        n = self.drive_no()
        return self.drives[n] if n is not None and n < len(self.drives) else None

    def side(self):
        return 0 if self.latch & 0x10 else 1

    # ---- ports ----
    def port_in(self, port):
        p = port & 0xFF
        if p == 0xC0:
            return self.fdc.read_status()
        if p == 0xC1:
            return self.fdc.tr
        if p == 0xC2:
            return self.fdc.sr
        if p == 0xC3:
            return self.fdc.read_data()
        if p & 0xE0 == 0x20:
            return 0x80 if self.fdc.drq else 0x00
        return 0xFF

    def port_out(self, port, v):
        p = port & 0xFF
        if p == 0xE0:
            self.latch = v
            if v & 0x40 and self.rom is not None:
                self.m[0:0x800] = self.rom
                self.rom = None
        elif p == 0xC0:
            self.fdc.command(v)
        elif p == 0xC1:
            self.fdc.tr = v
        elif p == 0xC2:
            self.fdc.sr = v
        elif p == 0xC3:
            self.fdc.write_data(v)

    # ---- console ----
    def ret(self):
        c = self.cpu
        c.pc = self.m[c.sp] | self.m[(c.sp + 1) & 0xFFFF] << 8
        c.sp = (c.sp + 2) & 0xFFFF

    def conin(self):
        if not self.input:
            if self.on_prompt:
                self.on_prompt(self)
            if not self.input:
                raise Stop()
        ch = self.input[0]
        del self.input[0]
        return ch

    def type(self, text):
        self.input += text.replace('\n', '\r').encode('latin-1')

    def screen(self):
        return self.out.decode('latin-1').replace('\r', '')

    # ---- run ----
    def boot(self):
        """Reset: run the FDD3000 boot ROM, which loads sector 0 of drive A
        at 3F00h and jumps there with SP=3EFFh. Without the ROM file
        (FDD_BOOT_ROM), do the same in Python."""
        if os.path.exists(BOOT_ROM):
            rom = open(BOOT_ROM, 'rb').read()
            self.rom = bytes(self.m[0:0x800])
            self.m[0:len(rom)] = rom
            self.cpu.pc = 0
            return
        a = self.drives[0]
        a.cyl = 0
        self.m[0x3F00:0x4000] = a.disk.sector(0, 0, 0)
        self.cpu.pc = 0x3F00
        self.cpu.sp = 0x3EFF

    def run(self):
        c, m, fdc = self.cpu, self.m, self.fdc
        try:
            while True:
                self.icount += 1
                if self.icount > self.max_instr:
                    raise RuntimeError('instruction limit, PC=%04X' % c.pc)
                fdc.tick()
                if fdc.intrq and c.iff1:
                    if m[c.pc] == 0x76:
                        c.pc = (c.pc + 1) & 0xFFFF
                    c.iff1 = c.iff2 = 0
                    c.sp = (c.sp - 2) & 0xFFFF
                    m[c.sp] = c.pc & 0xFF
                    m[(c.sp + 1) & 0xFFFF] = c.pc >> 8
                    c.pc = 0x38
                    continue
                pc = (c.pc + self.bias) & 0xFFFF if c.pc >= 0x0100 else c.pc
                if pc == CONOUT or pc == CONOUT_INT:
                    self.polls = 0
                    ch = c.r[1] if pc == CONOUT else c.r[7]
                    self.out.append(ch)
                    if pc == CONOUT_INT:            # PUSH DE/BC, POP DE/BC: swaps them
                        c.r[0], c.r[1], c.r[2], c.r[3] = c.r[2], c.r[3], c.r[0], c.r[1]
                        c.r[7] = 0
                    self.ret()
                    continue
                if pc == CONIN or pc == CONIN_INT:
                    self.polls = 0
                    c.r[7] = self.conin()
                    self.ret()
                    continue
                if pc == CONST:
                    # a program polling for a key gets the next input
                    # after a while; the CCP's break check does not
                    self.polls += 1
                    if not self.input and self.polls > 2000 and self.on_prompt:
                        self.polls = 0
                        self.on_prompt(self)
                    c.r[7] = 0xFF if self.input else 0
                    self.ret()
                    continue
                if m[pc] == 0x76:                   # HALT: wait for INT
                    continue
                c.step()
        except Stop:
            pass
