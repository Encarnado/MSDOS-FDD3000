"""Run DOS 2.0 tools (MASM, LINK, EXE2BIN) on cpu86 with INT 21h done in Python.

Host files live in one directory; DOS names are matched case-insensitively.
Usage: python3 dosshim.py DIR PROG.EXE [command tail]
"""
import os
import struct
import sys
import time

from cpu86 import CPU, Halt, AX, BX, CX, DX, SI, DI, SP, BP, ES, CS, SS, DS

PSP_SEG = 0x1000
TOP_SEG = 0x7FFF      # MASM 2.0 (MS Pascal runtime) misbehaves above 512 KB


class DosShim:
    def __init__(self, workdir, verbose=False):
        self.dir = workdir
        self.cpu = CPU()
        self.cpu.int_hook = self.int_hook
        self.handles = {}
        self.next_h = 5
        self.dta = (PSP_SEG, 0x80)
        self.exit_code = None
        self.out = sys.stdout
        self.verbose = verbose
        self.find = None
        self.mem_next = None
        self.stdin = b''

    # ---------- files ----------
    def host(self, name):
        name = name.replace('\\', '/').split(':')[-1].lstrip('/')
        want = name.upper()
        for f in os.listdir(self.dir):
            if f.upper() == want:
                return os.path.join(self.dir, f)
        return os.path.join(self.dir, want)

    def asciiz(self, seg, off):
        b = bytearray()
        while True:
            c = self.cpu.rb(seg, off + len(b))
            if c == 0:
                return b.decode('latin-1')
            b.append(c)

    # ---------- loading ----------
    def load(self, prog, tail=''):
        c = self.cpu
        data = open(prog, 'rb').read()
        psp = PSP_SEG
        base = psp << 4
        m = c.mem
        m[base:base + 256] = bytes(256)
        m[base:base + 2] = b'\xCD\x20'
        struct.pack_into('<H', m, base + 2, TOP_SEG)
        t = (' ' + tail if tail else '').encode()
        m[base + 0x80] = len(t)
        m[base + 0x81:base + 0x81 + len(t)] = t
        m[base + 0x81 + len(t)] = 13
        m[base + 0x5C:base + 0x5C + 12] = b'\x00' + b' ' * 11
        m[base + 0x6C:base + 0x6C + 12] = b'\x00' + b' ' * 11
        if data[:2] in (b'MZ', b'ZM'):
            last, pages, nrel, hdr, minx, maxx, ss, sp, ck, ip, cs, relo = \
                struct.unpack('<HHHHHHHHHHHH', data[2:26])
            size = pages * 512 - (512 - last if last else 0) - hdr * 16
            load = psp + 0x10
            img = data[hdr * 16:hdr * 16 + size]
            m[load << 4:(load << 4) + len(img)] = img
            for i in range(nrel):
                off, seg = struct.unpack_from('<HH', data, relo + 4 * i)
                a = ((load + seg) << 4) + off
                struct.pack_into('<H', m, a, (struct.unpack_from('<H', m, a)[0] + load) & 0xFFFF)
            c.s[CS], c.ip = (load + cs) & 0xFFFF, ip
            c.s[SS], c.r[SP] = (load + ss) & 0xFFFF, sp
            end_seg = load + (size + 15) // 16 + minx
        else:
            m[base + 0x100:base + 0x100 + len(data)] = data
            c.s[CS] = c.s[SS] = psp
            c.ip, c.r[SP] = 0x100, 0xFFFE
            c.ww(psp, 0xFFFE, 0)
            end_seg = psp + 0x1000
        c.s[DS] = c.s[ES] = psp
        c.r[AX] = 0
        self.mem_next = TOP_SEG + 1      # everything belongs to the program
        self.prog_end = end_seg

    # ---------- INT ----------
    def int_hook(self, n):
        c = self.cpu
        if n == 0x20:
            self.exit_code = 0
            c.halted = True
            return True
        if n != 0x21:
            if n in (0x23, 0x24):
                return False
            raise Halt('INT %02X at %04X:%04X' % (n, c.s[CS], c.ip))
        ah = c.r[AX] >> 8
        al = c.r[AX] & 0xFF
        r = c.r
        if self.verbose:
            print('INT21 %02X' % ah, file=sys.stderr)
        if ah in (0x00, 0x4C):
            self.exit_code = al if ah == 0x4C else 0
            c.halted = True
        elif ah == 0x02 or ah == 0x06 and (r[DX] & 0xFF) != 0xFF:
            self.out.write(chr(r[DX] & 0xFF))
        elif ah == 0x06:
            c.zf = 1
            c.setr8(0, 0)
        elif ah in (0x01, 0x07, 0x08):
            ch = self.stdin[:1] or b'\x1a'
            self.stdin = self.stdin[1:]
            c.setr8(0, ch[0])
        elif ah == 0x09:
            o = r[DX]
            while True:
                ch = c.rb(c.s[DS], o)
                if ch == 0x24:
                    break
                self.out.write(chr(ch))
                o += 1
        elif ah == 0x0A:
            mx = c.rb(c.s[DS], r[DX])
            line, _, self.stdin = self.stdin.partition(b'\r')
            line = line[:mx - 1]
            c.wb(c.s[DS], r[DX] + 1, len(line))
            for i, ch in enumerate(line + b'\r'):
                c.wb(c.s[DS], r[DX] + 2 + i, ch)
        elif ah == 0x0B:
            c.setr8(0, 0)
        elif ah == 0x0C:
            c.r[AX] = (c.r[AX] & 0xFF) << 8
            return self.int_hook(0x21)
        elif ah == 0x0D:
            pass
        elif ah == 0x0E:
            c.setr8(0, 1)
        elif ah == 0x19:
            c.setr8(0, 0)
        elif ah == 0x1A:
            self.dta = (c.s[DS], r[DX])
        elif ah == 0x2F:
            c.s[ES], r[BX] = self.dta
        elif ah == 0x25:
            c.ww(0, al * 4, r[DX])
            c.ww(0, al * 4 + 2, c.s[DS])
        elif ah == 0x35:
            r[BX] = c.rw(0, al * 4)
            c.s[ES] = c.rw(0, al * 4 + 2)
        elif ah == 0x2A:
            t = time.localtime()
            r[CX] = t.tm_year
            r[DX] = t.tm_mon << 8 | t.tm_mday
            c.setr8(0, (t.tm_wday + 1) % 7)
        elif ah == 0x2C:
            t = time.localtime()
            r[CX] = t.tm_hour << 8 | t.tm_min
            r[DX] = t.tm_sec << 8
        elif ah == 0x30:
            r[AX] = 0x0002
            r[BX] = r[CX] = 0
        elif ah == 0x33:
            c.r[DX] &= 0xFF00
        elif ah == 0x37:
            c.setr8(0, 0)
            c.setr8(2, ord('/'))
        elif ah == 0x29:
            self.parse_fcb()
        elif ah == 0x3C or ah == 0x3D:
            name = self.asciiz(c.s[DS], r[DX])
            path = self.host(name)
            try:
                if os.path.basename(path).split('.')[0] == 'NUL':
                    f = open(os.devnull, 'r+b')
                elif ah == 0x3C:
                    f = open(path, 'w+b')
                else:
                    f = open(path, 'r+b' if al & 3 else 'rb')
            except OSError:
                return self.iret_cf(2 if ah == 0x3D else 5)
            h = self.next_h
            self.next_h += 1
            self.handles[h] = f
            r[AX] = h
            return self.iret_cf(0)
        elif ah == 0x3E:
            f = self.handles.pop(r[BX], None)
            if f:
                f.close()
            return self.iret_cf(0)
        elif ah == 0x3F:
            if r[BX] == 0:
                data = self.stdin[:r[CX]]
                self.stdin = self.stdin[r[CX]:]
            else:
                f = self.handles.get(r[BX])
                if f is None:
                    return self.iret_cf(6)
                data = f.read(r[CX])
            for i, ch in enumerate(data):
                c.wb(c.s[DS], r[DX] + i, ch)
            r[AX] = len(data)
            return self.iret_cf(0)
        elif ah == 0x40:
            data = bytes(c.rb(c.s[DS], r[DX] + i) for i in range(r[CX]))
            if r[BX] in (1, 2):
                self.out.write(data.decode('latin-1'))
            elif r[BX] in (3, 4):
                pass
            else:
                f = self.handles.get(r[BX])
                if f is None:
                    return self.iret_cf(6)
                if r[CX] == 0:
                    f.truncate()
                f.write(data)
            r[AX] = len(data)
            return self.iret_cf(0)
        elif ah == 0x41:
            try:
                os.remove(self.host(self.asciiz(c.s[DS], r[DX])))
            except OSError:
                return self.iret_cf(2)
            return self.iret_cf(0)
        elif ah == 0x42:
            f = self.handles.get(r[BX])
            if f is None:
                return self.iret_cf(6)
            off = r[CX] << 16 | r[DX]
            if off & 0x80000000:
                off -= 1 << 32
            pos = f.seek(off, al)
            r[AX], r[DX] = pos & 0xFFFF, pos >> 16
            return self.iret_cf(0)
        elif ah == 0x43:
            p = self.host(self.asciiz(c.s[DS], r[DX]))
            if not os.path.exists(p):
                return self.iret_cf(2)
            r[CX] = 0x20
            return self.iret_cf(0)
        elif ah == 0x44:
            if al == 0:
                r[DX] = 0x80D3 if r[BX] < 5 else 0x0002
            return self.iret_cf(0)
        elif ah == 0x47:
            c.wb(c.s[DS], r[SI], 0)
            return self.iret_cf(0)
        elif ah == 0x48:
            if r[BX] == 0xFFFF or self.mem_next + r[BX] > TOP_SEG + 1:
                r[BX] = 0
                return self.iret_cf(8)
            r[AX] = self.mem_next
            self.mem_next += r[BX]
            return self.iret_cf(0)
        elif ah == 0x49:
            return self.iret_cf(0)
        elif ah == 0x4A:
            if c.s[ES] == PSP_SEG:
                self.mem_next = max(PSP_SEG + r[BX], self.prog_end)
            return self.iret_cf(0)
        elif ah == 0x4E or ah == 0x4F:
            return self.findfile(ah)
        elif ah == 0x56:
            a = self.host(self.asciiz(c.s[DS], r[DX]))
            b = self.host(self.asciiz(c.s[ES], r[DI]))
            os.replace(a, b)
            return self.iret_cf(0)
        elif ah == 0x57:
            r[CX] = r[DX] = 0
            return self.iret_cf(0)
        else:
            raise Halt('INT 21 AH=%02X at %04X:%04X' % (ah, c.s[CS], c.ip))
        return True

    def iret_cf(self, err):
        """Set CF (and AX on error) for a handle call; flags pushed by INT are
        not involved since the hook replaces the whole interrupt."""
        c = self.cpu
        c.cf = 1 if err else 0
        if err:
            c.r[AX] = err
        return True

    def findfile(self, ah):
        import fnmatch
        c = self.cpu
        if ah == 0x4E:
            pat = self.asciiz(c.s[DS], c.r[DX]).replace('\\', '/').split('/')[-1].split(':')[-1]
            names = sorted(f for f in os.listdir(self.dir)
                           if fnmatch.fnmatch(f.upper(), pat.upper()) and len(f) <= 12)
            self.find = names
        if not self.find:
            return self.iret_cf(18)
        f = self.find.pop(0)
        seg, off = self.dta
        size = os.path.getsize(os.path.join(self.dir, f))
        c.wb(seg, off + 21, 0x20)
        c.ww(seg, off + 22, 0)
        c.ww(seg, off + 24, 0)
        c.ww(seg, off + 26, size & 0xFFFF)
        c.ww(seg, off + 28, size >> 16)
        nb = f.upper().encode() + b'\0'
        for i, ch in enumerate(nb):
            c.wb(seg, off + 30 + i, ch)
        return self.iret_cf(0)

    def parse_fcb(self):
        c = self.cpu
        seg, off = c.s[DS], c.r[SI]
        s = bytearray()
        while True:
            ch = c.rb(seg, off + len(s))
            if ch < 0x21 and s:
                break
            if ch in (13, 0):
                break
            s.append(ch)
            if len(s) > 80:
                break
        txt = s.decode('latin-1')
        lead = len(txt) - len(txt.lstrip(' \t'))
        txt = txt.lstrip(' \t')
        drive = 0
        if len(txt) > 1 and txt[1] == ':':
            drive = ord(txt[0].upper()) - 64
            txt = txt[2:]
            lead += 2
        n = 0
        while n < len(txt) and txt[n] not in ' \t,;=+/"[]<>|\r':
            n += 1
        name, _, ext = txt[:n].upper().partition('.')
        fs, fo = c.s[ES], c.r[DI]
        c.wb(fs, fo, drive)
        for i, ch in enumerate(name[:8].ljust(8)):
            c.wb(fs, fo + 1 + i, ord(ch))
        for i, ch in enumerate(ext[:3].ljust(3)):
            c.wb(fs, fo + 9 + i, ord(ch))
        c.r[SI] = (c.r[SI] + lead + n) & 0xFFFF
        c.setr8(0, 1 if '?' in name + ext or '*' in name + ext else 0)

    def run(self, limit=2_000_000_000):
        c = self.cpu
        while not c.halted and c.cycles < limit:
            c.step()
        return self.exit_code


def run_tool(workdir, prog, tail='', stdin=b'', verbose=False):
    d = DosShim(workdir, verbose)
    d.stdin = stdin
    d.load(prog, tail)
    code = d.run()
    for f in d.handles.values():
        f.close()
    return code, d.cpu.cycles


if __name__ == '__main__':
    code, n = run_tool(sys.argv[1], os.path.join(sys.argv[1], sys.argv[2]), ' '.join(sys.argv[3:]))
    print('\n[exit %s after %d instructions]' % (code, n), file=sys.stderr)
