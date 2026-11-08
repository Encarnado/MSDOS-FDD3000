"""The Z80 interpreter against cpu86.py, instruction by instruction.

Boots MS-DOS on both and runs test_dos.py's steps. After every 8086
instruction the registers, IP, flags and all 52 KB of guest memory must
match; the only tolerated difference is AF after 16-bit arithmetic (the
Z80 computes it from bit 11). Then prints the Z80 T-states of each step.

    python3 test_z86.py            lockstep (about 10 seconds)
    python3 test_z86.py --fast     Z80 only, with T-states and the hot spots
"""
import datetime as dt
import os
import sys

import fddos
import mkfat
import test_dos
import z86

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, 'build')
AF = 0x10
NAMES = ['AX', 'CX', 'DX', 'BX', 'SP', 'BP', 'SI', 'DI']


class FixedClock:
    """fddos reads the time; both machines must see the same."""
    class datetime(dt.datetime):
        @classmethod
        def now(cls):
            return cls(2026, 11, 5, 12, 34, 56, 780000)

    class date(dt.date):
        @classmethod
        def today(cls):
            return cls(2026, 11, 5)

    timedelta = dt.timedelta


def disk():
    io_sys = open(os.path.join(B, 'IOFDD.SYS'), 'rb').read()
    dos_sys = open(os.path.join(B, 'MSDOS.SYS'), 'rb').read()
    files = [(f, open(os.path.join(B, f), 'rb').read()) for f in test_dos.FILES]
    return mkfat.make(files, io_sys, dos_sys)


def state(c):
    return list(c.r), list(c.s), c.ip, c.flags


def show(c, tag):
    r, s, ip, fl = state(c)
    return '%s %s  ES=%04X CS=%04X SS=%04X DS=%04X IP=%04X FL=%04X' % (
        tag, ' '.join('%s=%04X' % (n, v) for n, v in zip(NAMES, r)),
        s[0], s[1], s[2], s[3], ip, fl)


def compare(ref, z, prev):
    a, b = state(ref.cpu), state(z.cpu)
    if a[:3] != b[:3] or (a[3] ^ b[3]) & ~AF:
        return 'registers'
    rm, zm = ref.cpu.mem, z.cpu.mem
    if rm[:0xD000] != zm[:0xD000]:
        bad = [i for i in range(0xD000) if rm[i] != zm[i] and (rm[i] ^ zm[i]) != AF]
        if bad:
            return 'memory at ' + ' '.join('%05X:%02X/%02X' % (i, rm[i], zm[i]) for i in bad[:8])
        zm[:0xD000] = rm[:0xD000]       # AF in a pushed FLAGS word
    return None


def lockstep():
    fddos.datetime = FixedClock
    ref = fddos.Machine([disk()])
    z = z86.machine([disk()], count_t=True)
    ref.boot()
    z.boot()
    for name, keys, want in test_dos.STEPS:
        ref.keys += keys.encode('latin-1')
        z.keys += keys.encode('latin-1')
        n0, t0 = z.cpu.cycles, z.cpu.tstates
        while True:
            c = ref.cpu
            prev = (c.s[1], c.ip, bytes(c.mem[(c.s[1] << 4) + c.ip:(c.s[1] << 4) + c.ip + 6]))
            before = show(c, 'before')
            wr = wz = False
            try:
                ref.cpu.step()
            except fddos.WaitInput:
                wr = True
            try:
                z.cpu.step()
            except fddos.WaitInput:
                wz = True
            err = 'one side waits for input' if wr != wz else compare(ref, z, prev)
            if err:
                print('MISMATCH after instruction %d (%04X:%04X %s): %s' % (
                    ref.cpu.cycles, prev[0], prev[1], prev[2].hex(' '), err))
                print(before)
                print(show(ref.cpu, 'cpu86 '))
                print(show(z.cpu, 'z80   '))
                sys.exit(1)
            if wr:
                break
        got = z.out.decode('latin-1')
        n, t = z.cpu.cycles - n0, z.cpu.tstates - t0
        print('%-8s %7d instr %10d T  %4.0f T/instr  %5.2f s at 4 MHz' % (
            name, n, t, t / max(n, 1), t / 4e6))
    if z.out != ref.out:
        print('screens differ')
        sys.exit(1)
    c = z.cpu
    print('total    %7d instr %10d T  %4.0f T/instr  %5.2f s at 4 MHz' % (
        c.cycles, c.tstates, c.tstates / c.cycles, c.tstates / 4e6))
    print('lockstep ok: registers, flags and memory matched after every instruction')


def fast():
    fddos.datetime = FixedClock
    z = z86.machine([disk()], count_t=True)
    z.cpu.profile = prof = {}
    z.boot()
    ok = True
    for name, keys, want in test_dos.STEPS:
        mark = len(z.out)
        n0, t0 = z.cpu.cycles, z.cpu.tstates
        if keys:
            z.type(keys)
        else:
            z.run()
        got = z.out[mark:].decode('latin-1').replace('\r\n', '\n')
        bad = [w for w in want if w not in got]
        ok &= not bad
        n, t = z.cpu.cycles - n0, z.cpu.tstates - t0
        print('%-8s %7d instr %10d T  %4.0f T/instr  %5.2f s  %s' % (
            name, n, t, t / max(n, 1), t / 4e6, 'ok' if not bad else 'FAIL %r' % bad))
    c = z.cpu
    print('total    %7d instr %10d T  %4.0f T/instr  %5.2f s at 4 MHz' % (
        c.cycles, c.tstates, c.tstates / c.cycles, c.tstates / 4e6))
    syms = sorted((v, k) for k, v in c.syms.items() if 0xD800 <= v < 0xFF00)
    import bisect
    by = {}
    for pc, t in prof.items():
        i = bisect.bisect_right(syms, (pc, '~')) - 1
        lab = syms[i][1] if i >= 0 else '?'
        by[lab] = by.get(lab, 0) + t
    print('hot spots (T-states by routine):')
    for lab, t in sorted(by.items(), key=lambda kv: -kv[1])[:25]:
        print('  %-12s %9d  %4.1f%%' % (lab, t, 100 * t / c.tstates))
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    fast() if '--fast' in sys.argv else lockstep()
