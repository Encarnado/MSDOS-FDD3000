"""Publish a build: copy what build.py and z86.py made into the package's
binaries/ and symbols/ (and DISASM/bin), regenerate the listings, symbol
tables and MANIFEST.sha256.

    python3 build.py ...      first (see the README, "Building")
    python3 publish.py        then this

binaries/z80   BOOT.BIN, Z86.SYS, CPMZ80.BIN, TERMZ80.BIN   (from z86.py)
binaries/x86   IO.SYS, MSDOS.SYS, COMMAND.COM, FORMAT.COM, CPM.COM,
               EDIT.COM, MODE.COM, TERM.COM                 (from build/)
binaries/disk  MSDOS-FDD3000.DSK (= build/MSDOS.DSK) and files/ (read back
               from it through the FAT)
symbols/z80    mksyms.py;  symbols/x86  the MASM listings + mkx86syms.py
DISASM/bin     the same binaries, for DISASM/tools/roundtrip.sh

Then run DISASM/tools/roundtrip.sh: a volume whose binary changed fails
until its .asm is brought in line (see DISASM/PLAN.md).
"""
import hashlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
B = os.path.join(HERE, 'build')
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cpm80ds'))

import z86  # noqa: E402

X86 = [('IOFDD.SYS', 'IO.SYS'), ('MSDOS.SYS', 'MSDOS.SYS'), ('COMMAND.COM', 'COMMAND.COM'),
       ('FORMAT.COM', 'FORMAT.COM'), ('CPM.COM', 'CPM.COM'), ('EDIT.COM', 'EDIT.COM'),
       ('MODE.COM', 'MODE.COM'), ('TERM.COM', 'TERM.COM')]
LSTS = ['IOFDD.LST', 'MSDOS.LST', 'COMMAND.LST', 'FORMAT.LST', 'CPM.LST', 'EDIT.LST',
        'MODE.LST', 'TERM.LST']


def put(path, data):
    path = os.path.join(PKG, path)
    old = open(path, 'rb').read() if os.path.exists(path) else None
    if old != data:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'wb').write(data)
        print('  updated', os.path.relpath(path, PKG))


def disasm(name, data):
    """DISASM/bin keeps only the binaries that have a volume."""
    if os.path.exists(os.path.join(PKG, 'DISASM', 'bin', name)):
        put('DISASM/bin/' + name, data)


def main():
    ipl, sys_ = z86.bootcode()
    z80 = {'BOOT.BIN': ipl[:254], 'Z86.SYS': sys_,
           'CPMZ80.BIN': z86.cpmz80()[16:], 'TERMZ80.BIN': z86.termz80()[0][16:]}
    for name, data in z80.items():
        put('binaries/z80/' + name, data)
        disasm(name, data)
    for src, dst in X86:
        data = open(os.path.join(B, src), 'rb').read()
        put('binaries/x86/' + dst, data)
        disasm(dst, data)
    dsk = open(os.path.join(B, 'MSDOS.DSK'), 'rb').read()
    put('binaries/disk/MSDOS-FDD3000.DSK', dsk)
    import fdd
    import mkfat
    for name, data in mkfat.files(fdd.Disk.load(os.path.join(B, 'MSDOS.DSK'))).items():
        put('binaries/disk/files/' + name, data)
    for lst in LSTS:                     # listings, when build.py made them here
        p = os.path.join(B, lst)
        if os.path.exists(p):
            put('symbols/x86/' + lst, open(p, 'rb').read())
    subprocess.run([sys.executable, os.path.join(HERE, 'mksyms.py')], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, os.path.join(HERE, 'mkx86syms.py'), os.path.join(PKG, 'symbols', 'x86'),
                    os.path.join(PKG, 'symbols', 'x86')], check=True, stdout=subprocess.DEVNULL)
    manifest()


def manifest():
    """MANIFEST.sha256: every package file git tracks (DISASM/ apart)."""
    files = subprocess.run(['git', 'ls-files'], cwd=PKG, capture_output=True, text=True).stdout.split('\n')
    files = [f for f in files if f and not f.startswith('DISASM/') and f not in ('.gitignore', 'MANIFEST.sha256')
             and os.path.isfile(os.path.join(PKG, f)) and not os.path.islink(os.path.join(PKG, f))]
    rows = []
    for f in sorted(files):
        d = open(os.path.join(PKG, f), 'rb').read()
        rows.append('%s %9d  %s' % (hashlib.sha256(d).hexdigest(), len(d), f))
    put('MANIFEST.sha256', ('\n'.join(rows) + '\n').encode())


if __name__ == '__main__':
    main()
