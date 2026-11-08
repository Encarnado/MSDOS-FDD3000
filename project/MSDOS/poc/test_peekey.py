"""PEEKEY with the link idling at 00h-03h (BIOS.ASM, 2026-11-08 fix).

PEEKEY tested `cp 04h / ret nz`: for a link value below 04h CP leaves carry
set, so STATUS reported a phantom key (the stale KBUF) and the next INPUT
blocked.  Now `xor 04h`: only 04h means "a key is waiting".  Here PEEKEY is
called directly on the booted machine with the link forced to each value.

    python3 test_peekey.py
"""
import test_fdd86 as T
import test_z86


def call(m, addr, link_value):
    c = m.cpu
    S = m.syms
    old = m.link.read
    m.link.read = lambda: link_value
    stop = 0x3F00                        # a HALT with interrupts off ends run()
    m.m[stop] = 0x76
    c.iff1 = c.iff2 = 0
    c.sp = 0xFF00
    m.m[0xFF00], m.m[0xFF01] = stop & 0xFF, stop >> 8
    m.m[S['KFLAG']] = 0
    c.pc = addr
    m.stopped = None
    m.run(limit=200_000)
    m.link.read = old
    carry = c.F & 1
    return carry, m.m[S['KFLAG']]


def main():
    m = T.booted([test_z86.disk()])
    for v in (0x00, 0x01, 0x02, 0x03, 0x50):
        carry, kflag = call(m, m.syms['PEEKEY'], v)
        T.check(carry == 0 and kflag == 0, 'link %02Xh: PEEKEY says key (CF=%d, KFLAG=%d)' % (v, carry, kflag))
        print('  link %02Xh: CF=%d KFLAG=%d %s' % (v, carry, kflag, 'ok' if carry == 0 else 'PHANTOM KEY'))
    print('FAILED: %d' % len(T.FAILS) if T.FAILS else 'all passed')
    raise SystemExit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
