"""The floppy timeouts (BIOS.ASM FDCCMD / FHOME / XFER / FDTOUT).

A real WD1770 with no disk in the drive, or no drive at all, sees no index
pulses: a spin-up, a verify or a sector search never ends.  The emulated
FDC normally ends such a command at once with an error, which hid this;
machine.FDC.no_index = True makes it hang as the chip does.  Before the
timeouts the BIOS waited for ever (DOS hung on DIR B:); now DOS must get
"Not ready" after about 3 s, and Abort must go back to the prompt.

    python3 test_fdtimeout.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cpm80ds'))
import machine  # noqa: E402
import test_fdd86 as T  # noqa: E402
import test_z86  # noqa: E402

MHZ = 4.0


def case(title, make_b):
    print(title)
    m = T.booted([test_z86.disk(), None])
    m.drives[1] = make_b()
    m.fdc.no_index = True
    t0 = m.tstates
    try:
        out = T.step(m, 'DIR B:\r', limit=60_000_000)
    except RuntimeError as e:          # the instruction limit: it hung
        T.check(False, '%s: no answer (%s)' % (title, e))
        return
    secs = (m.tstates - t0) / (MHZ * 1e6)
    T.check('Not ready error reading drive B' in out and 'Abort, Retry, Ignore?' in out,
            '%s: %r' % (title, out))
    print('  ' + out.strip().replace('\r\n', ' | '))
    print('  answered after %.1f s of Z80 time at %.0f MHz' % (secs, MHZ))
    T.check(secs < 30, '%s: took %.1f s' % (title, secs))
    out = T.step(m, 'A')
    T.check(out.rstrip().endswith('A:'), '%s: abort %r' % (title, out))
    out = T.step(m, 'DIR\r')            # drive A still works afterwards
    T.check('File(s)' in out, '%s: DIR A: after %r' % (title, out))


def main():
    case('1. no drive B (realistic: no index pulses):', lambda: None)
    case('2. drive B with no disk (realistic):',
         lambda: machine.Drive(cyls=40, heads=1, disk=None))
    print('FAILED: %d' % len(T.FAILS) if T.FAILS else 'all passed')
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
