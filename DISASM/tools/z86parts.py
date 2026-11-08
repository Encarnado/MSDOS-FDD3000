#!/usr/bin/env python3
"""z86parts.py - split asm/z86sys.asm into region parts for parallel
narration, check one part, and join them back.

    python3 tools/z86parts.py split        asm/z86sys.asm -> parts/z86_NN.asm
                                           + a frozen copy in parts/base/
    python3 tools/z86parts.py check NN     parts/z86_NN.asm + the BASE copy of
                                           every other part -> assemble, cmp
    python3 tools/z86parts.py join         parts/z86_*.asm -> asm/z86sys.asm
                                           (then tools/roundtrip.sh)

`check` assembles a part against the untouched baseline of all the others,
so edits to different parts never see each other's work in progress.
Consequence: a part may rename only labels that no other part refers to
(the check fails with an undefined label otherwise) - global names stay.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(ROOT, 'parts')
BASE = os.path.join(PARTS, 'base')
SRC = os.path.join(ROOT, 'asm', 'z86sys.asm')
REF = os.path.join(ROOT, 'bin', 'Z86.SYS')

# first label of each part (cut made above the comment block heading it)
CUTS = ['START', 'O_DAA', 'O_XCHGA', 'O_MOVI_AL', 'O_CMC', 'TRAP', 'FDCCMD']


def names():
    return sorted(f for f in os.listdir(PARTS) if f.startswith('z86_') and f.endswith('.asm'))


def split():
    if os.path.exists(PARTS) and names():
        sys.exit('parts/ already populated - refusing to overwrite')
    lines = open(SRC).read().split('\n')
    idx = []
    for name in CUTS:
        i = lines.index(name + ':')
        while i > 0 and lines[i - 1].startswith(';'):
            i -= 1
        idx.append(i)
    bounds = [0] + idx + [len(lines)]
    os.makedirs(BASE, exist_ok=True)
    for k in range(len(bounds) - 1):
        body = '\n'.join(lines[bounds[k]:bounds[k + 1]])
        if not body.endswith('\n'):
            body += '\n'
        for d in (PARTS, BASE):
            open(os.path.join(d, 'z86_%02d.asm' % (k + 1)), 'w').write(body)
        print('z86_%02d.asm  lines %5d-%5d' % (k + 1, bounds[k] + 1, bounds[k + 1]))


def assemble(files, tag):
    out = os.path.join(ROOT, 'build', 'z86_%s.asm' % tag)
    with open(out, 'w') as f:
        for p in files:
            f.write(open(p).read())
    binf = out[:-4] + '.bin'
    r = subprocess.run(['z80asm', '-o', binf, out], capture_output=True, text=True)
    if r.returncode:
        print(r.stderr.strip()[:3000])
        print('FAIL (assembly error) - line numbers refer to', out)
        return False
    if open(binf, 'rb').read() != open(REF, 'rb').read():
        a, b = open(binf, 'rb').read(), open(REF, 'rb').read()
        i = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
        print('FAIL (bytes differ) first at %04Xh (len %d vs %d)' % (0xD000 + i, len(a), len(b)))
        return False
    print('PASS', tag)
    return True


def check(nn):
    nn = '%02d' % int(nn)
    files = [os.path.join(PARTS if f == 'z86_%s.asm' % nn else BASE, f) for f in names()]
    sys.exit(0 if assemble(files, 'check' + nn) else 1)


def join():
    files = [os.path.join(PARTS, f) for f in names()]
    if not assemble(files, 'joined'):
        sys.exit(1)
    with open(SRC, 'w') as f:
        for p in files:
            f.write(open(p).read())
    print('joined ->', SRC)


if __name__ == '__main__':
    cmd = sys.argv[1]
    {'split': split, 'join': join}.get(cmd, lambda: check(sys.argv[2]))()
