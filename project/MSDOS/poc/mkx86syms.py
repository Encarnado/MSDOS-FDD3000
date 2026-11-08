"""symbols/x86/*.sym from the MASM 1.10 listings: `offset  type  name`
from each listing's symbol table (L NEAR / L BYTE / L WORD / V ..., Number),
in the listing's order.  Aliases and segment names are left out.

    python3 mkx86syms.py LSTDIR OUTDIR   (default: build -> ../../../symbols/x86)
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = [('IOFDD.LST', 'IO.SYS'), ('MSDOS.LST', 'MSDOS.SYS'), ('COMMAND.LST', 'COMMAND.COM'),
         ('FORMAT.LST', 'FORMAT.COM'), ('CPM.LST', 'CPM.COM'), ('EDIT.LST', 'EDIT.COM')]
ROW = re.compile(r'^(\S+?)\s*(?:\. ?)*\.?\t(L NEAR|L FAR|L BYTE|L WORD|L DWORD|V BYTE|V WORD|V DWORD|Number)\s*\t([0-9A-F]{4})')


def convert(lst, binary):
    text = open(lst, encoding='latin-1').read().replace('\r', '')
    table = text[text.index('\nSymbols:'):]
    rows = ['; %s (from %s): offset  type  name' % (binary, os.path.basename(lst))]
    for line in table.split('\n'):
        m = ROW.match(line)
        if m:
            rows.append('%s  %s  %s' % (m.group(3), m.group(2), m.group(1).rstrip('.').rstrip()))
    return '\n'.join(rows) + '\n'


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'build')
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '..', '..', '..', 'symbols', 'x86')
    for lst, binary in FILES:
        p = os.path.join(src, lst)
        if os.path.exists(p):
            open(os.path.join(dst, binary + '.sym'), 'w').write(convert(p, binary))
            print('wrote', binary + '.sym')


if __name__ == '__main__':
    main()
