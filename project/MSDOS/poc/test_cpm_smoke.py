"""CPM.COM smoke test that needs no CP/M disk: a tiny CP/M program
(BDOS 9, print a string, then return to the CCP) run with `CPM HI` on a
disk made from build/.  Covers CPM.COM's load (and its read check, 2026-11-08),
trap 1Ch, CPMZ80 natively on the Z80, a BDOS call, and the way back to DOS.

    python3 test_cpm_smoke.py
"""
import os

import mkfat
import test_fdd86 as T

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, 'build')
# org 100h: ld c,9 / ld de,msg / call 5 / ret / msg: "HELLO FROM CP/M",13,10,"$"
HI = bytes([0x0E, 0x09, 0x11, 0x09, 0x01, 0xCD, 0x05, 0x00, 0xC9]) + b'HELLO FROM CP/M\r\n$'


def main():
    files = [(f, open(os.path.join(B, f), 'rb').read()) for f in ('COMMAND.COM', 'CPM.COM')]
    files.append(('HI.CPM', HI))
    d = mkfat.make(files, open(os.path.join(B, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(B, 'MSDOS.SYS'), 'rb').read())
    m = T.booted([d])
    out = T.step(m, 'CPM HI\r', limit=200_000_000)
    print('  ' + out.strip().replace('\r\n', ' | '))
    T.check('HELLO FROM CP/M' in out, 'CPM HI: %r' % out)
    T.check(out.rstrip().endswith('A:'), 'back at the DOS prompt: %r' % out)
    out = T.step(m, 'DIR\r')
    T.check('HI       CPM' in out, 'DOS works after CPM: %r' % out)
    out = T.step(m, 'CPM NOSUCH\r', limit=200_000_000)
    T.check('Program not found' in out, 'CPM NOSUCH: %r' % out)
    print('FAILED: %d' % len(T.FAILS) if T.FAILS else 'all passed')
    raise SystemExit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
