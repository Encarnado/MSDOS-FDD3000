"""Build MS-DOS 1.25 for the FDD3000 from source, with the original tools.

MASM 1.10, LINK 2.00 and EXE2BIN from MS-DOS 2.0 run on the 8086
interpreter (dosshim.py). Sources come from Microsoft's MIT-licensed
release (../mit/v1.25); the tools from ../src/v20object.

    python3 build.py           (about 6 minutes: MSDOS.ASM alone is 87 M instructions)

    python3 build.py FORMAT    (rebuild only these, then the disk)
    python3 build.py CPM
    python3 build.py EDIT

Output in build/: MSDOS.SYS, COMMAND.COM, IOFDD.SYS, FORMAT.COM, CPM.COM, EDIT.COM, MODE.COM, TERM.COM and MSDOS.DSK.
MSDOS.DSK also gets MBASIC.CPM and TTT.BAS from ~/Claude/Resources/Disks/galo-basic.dsk
(BASIC.COM there: MBASIC 5.2), if that disk is there.
"""
import os
import shutil
import sys

import dosshim
import mkfat
import z86

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, 'build')
MIT = os.path.join(HERE, '..', 'mit', 'v1.25')
TOOLS = os.path.join(HERE, '..', 'src', 'v20object')
GALO = os.path.expanduser('~/Claude/Resources/Disks/galo-basic.dsk')


def dos_text(src, dst, patches=()):
    """Copy a source as a DOS text file: CRLF lines and a ^Z at the end."""
    d = open(src, 'rb').read().replace(b'\r\n', b'\n')
    for old, new in patches:
        d = d.replace(old, new)
    open(dst, 'wb').write(d.replace(b'\n', b'\r\n') + b'\x1a')


def tool(prog, tail):
    code, n = dosshim.run_tool(B, os.path.join(B, prog), tail)
    print('  %-12s %-28s %11d instructions' % (prog, tail, n))


def build(name, main=None):
    """MASM + LINK + EXE2BIN: name.ASM (or main.ASM, which includes it) -> binary."""
    main = main or name
    ext = '.COM' if name in ('COMMAND', 'FORMAT', 'CPM', 'EDIT', 'MODE', 'TERM') else '.SYS'
    out = name + ext
    tool('MASM.EXE', '%s,%s,%s,NUL;' % (main, name, name))
    lst = open(os.path.join(B, name + '.LST'), 'rb').read()
    if b'E r r o r' in lst:
        sys.exit('%s: assembly errors, see build/%s.LST' % (name, name))
    tool('LINK.EXE', '%s;' % name)
    tool('EXE2BIN.EXE', '%s.EXE %s' % (name, out))
    return out


def main():
    os.makedirs(B, exist_ok=True)
    for t in ('MASM.EXE', 'LINK.EXE', 'EXE2BIN.EXE'):
        shutil.copy(os.path.join(TOOLS, t), B)
    for f in ('EDLIN.COM', 'DEBUG.COM', 'CHKDSK.COM'):
        shutil.copy(os.path.join(MIT, 'bin', f), B)
    s = os.path.join(MIT, 'source')
    dos_text(os.path.join(s, 'STDDOS.ASM'), os.path.join(B, 'STDDOS.ASM'))
    dos_text(os.path.join(s, 'MSDOS.ASM'), os.path.join(B, 'MSDOS.ASM'))
    # MASM 1.10 will not redefine with "=" a symbol first set with EQU
    dos_text(os.path.join(s, 'COMMAND.ASM'), os.path.join(B, 'COMMAND.ASM'),
             [(b'ZERO    EQU     $', b'ZERO    =       $')])
    dos_text(os.path.join(HERE, 'IOFDD.ASM'), os.path.join(B, 'IOFDD.ASM'))
    dos_text(os.path.join(HERE, 'FORMAT.ASM'), os.path.join(B, 'FORMAT.ASM'))
    dos_text(os.path.join(HERE, 'CPM.ASM'), os.path.join(B, 'CPM.ASM'))
    dos_text(os.path.join(HERE, 'EDIT.ASM'), os.path.join(B, 'EDIT.ASM'))
    dos_text(os.path.join(HERE, 'MODE.ASM'), os.path.join(B, 'MODE.ASM'))
    dos_text(os.path.join(HERE, 'TERM.ASM'), os.path.join(B, 'TERM.ASM'))
    z = z86.cpmz80()                    # CPM.COM's Z80 part, as DB lines
    lines = ['        DB      ' + ','.join('0%02XH' % c for c in z[i:i + 16]) for i in range(0, len(z), 16)]
    open(os.path.join(B, 'CPMZ80.INC'), 'wb').write(('\r\n'.join(lines) + '\r\n\x1a').encode())
    z = z86.termz80()[0]                # TERM.COM's Z80 part
    lines = ['        DB      ' + ','.join('0%02XH' % c for c in z[i:i + 16]) for i in range(0, len(z), 16)]
    open(os.path.join(B, 'TERMZ80.INC'), 'wb').write(('\r\n'.join(lines) + '\r\n\x1a').encode())

    only = [a.upper() for a in sys.argv[1:]]
    for name, main in (('IOFDD', None), ('COMMAND', None), ('FORMAT', None), ('CPM', None), ('EDIT', None), ('MODE', None), ('TERM', None),
                       ('MSDOS', 'STDDOS')):
        if not only or name in only:
            print(name)
            build(name, main)

    io_sys = open(os.path.join(B, 'IOFDD.SYS'), 'rb').read()
    dos_sys = open(os.path.join(B, 'MSDOS.SYS'), 'rb').read()
    files = [(f, open(os.path.join(B, f), 'rb').read())
             for f in ('COMMAND.COM', 'EDLIN.COM', 'DEBUG.COM', 'CHKDSK.COM', 'FORMAT.COM', 'CPM.COM', 'EDIT.COM', 'MODE.COM', 'TERM.COM')]
    if os.path.exists(GALO):            # MBASIC 5.2 for CPM.COM, if it is here
        import fdd
        g = {k[1]: v for k, v in fdd.Disk.load(GALO).files(fdd.A11).items()}
        files += [('MBASIC.CPM', g['BASIC.COM']), ('TTT.BAS', g['TTT.BAS'])]
    mkfat.make(files, io_sys, dos_sys).save(os.path.join(B, 'MSDOS.DSK'))
    print('build/MSDOS.DSK: IO.SYS %d, MSDOS.SYS %d bytes' % (len(io_sys), len(dos_sys)))


if __name__ == '__main__':
    main()
