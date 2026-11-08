"""Write the Z80 listings and symbol tables of the package's symbols/z80/:
Z86.SYS.lst / .sym, CPMZ80.lst / .sym, and (when TERMZ80.ASM is there)
TERMZ80.lst / .sym.

    python3 mksyms.py OUTDIR          (default: ../../../symbols/z80)

Listing lines are `address  bytes  source` (bytes from the assembled image,
8 a row; a row shows its line's start address), from the preprocessed source
(;@FOR / ;@TABLE / ;@SLACK expanded), as tmxcobol's z80asm assembles it in
z86.py.  Each line's address comes from a label put in front of it before
assembling (ZZL<n>:), so the listing cannot drift from the bytes.
Symbol tables: `address  kind  name`, kind = code / data / equ.
"""
import os
import re
import sys

import z86

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tmxcobol'))
import z80asm  # noqa: E402

LABEL = re.compile(r'^([A-Za-z_][\w]*):?(?=\s|$|;)')
DATA = re.compile(r'^\s*(DB|DW|DS|DEFB|DEFW|DEFS|DEFM)\b', re.I)


def statement(line):
    """-> (label, rest-without-label, opcode upper) of a source line."""
    code = line.split(';', 1)[0]
    lab = None
    m = LABEL.match(code)
    if m and not code[:1].isspace():
        lab = m.group(1)
        code = code[m.end():].lstrip(':')
    rest = code.strip()
    op = rest.split(None, 1)[0].upper() if rest else ''
    return lab, rest, op


def assemble_with_lines(text):
    lines = text.split('\n')
    marked = []
    for i, l in enumerate(lines):
        marked.append('ZZL%d:' % i)
        marked.append(l)
    a = z80asm.Assembler()
    out = bytes(a.assemble('\n'.join(marked)))
    syms = {k: v for k, v in a.symbols.items() if isinstance(v, int)}
    addr = [syms['ZZL%d' % i] for i in range(len(lines))]
    return lines, addr, out, syms


def listing(lines, addr, out, lo, hi, ptr):
    """Listing rows for lines[lo:hi]; ptr = output offset of lines[lo].
    -> (rows, ptr after)."""
    rows = []
    for i in range(lo, hi):
        l = lines[i]
        lab, rest, op = statement(l)
        n = 0 if op == 'ORG' or i + 1 >= len(addr) else addr[i + 1] - addr[i]
        n = max(n, 0)
        b = out[ptr:ptr + n]
        ptr += n
        if n:
            for k in range(0, n, 8):
                row = '%04X  %s' % (addr[i], ' '.join('%02X' % x for x in b[k:k + 8]))
                rows.append(row.ljust(32) + (l if k == 0 else ''))
        elif lab or op == 'EQU':
            rows.append(('%04X' % addr[i]).ljust(32) + l)
        else:
            rows.append(' ' * 32 + l)
    return rows, ptr


def symtab(lines, lo, hi, syms):
    """Labels and EQUs defined in lines[lo:hi] -> {name: (addr, kind)}."""
    res = {}
    for i in range(lo, hi):
        lab, rest, op = statement(lines[i])
        if not lab:
            continue
        if op == 'EQU':
            kind = 'equ'
        elif rest:
            kind = 'data' if DATA.match(rest) else 'code'
        else:                       # a label alone: the very next line decides
            nxt = statement(lines[i + 1]) if i + 1 < hi else (None, '', '')
            kind = 'data' if DATA.match(nxt[1]) else 'code'   # (also through a
                                                               #  labelled DB line)
        res[lab] = (syms[lab], kind)
    return res


def write_sym(path, head, table):
    with open(path, 'w') as f:
        f.write(head)
        for name, (a, kind) in sorted(table.items(), key=lambda t: (t[1][0], t[0])):
            f.write('%04X  %-4s  %s\n' % (a, kind, name))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', '..', 'symbols', 'z80')
    bios = open(z86.BIOS).read()
    i86 = open(z86.SRC).read()
    cpm = open(z86.CPMZ80).read()
    text = z86.preprocess(i86 + bios.replace('\n        END\n', '\n') + cpm)
    lines, addr, out, syms = assemble_with_lines(text)
    split = next(i for i, l in enumerate(lines) if statement(l)[2] == 'ORG' and 'ENDBIOS' in l)
    z86rows, ptr = listing(lines, addr, out, 0, split, 0)
    z86rows += [' ' * 32, ' ' * 32 + '        END', ' ' * 32]
    cpmrows, _ = listing(lines, addr, out, split, len(lines), ptr)
    with open(os.path.join(outdir, 'Z86.SYS.lst'), 'w') as f:
        f.write('; Z86.SYS: I86.ASM + BIOS.ASM (macros expanded), loaded at D000h\n'
                '; address  bytes  source\n' + '\n'.join(z86rows) + '\n')
    with open(os.path.join(outdir, 'CPMZ80.lst'), 'w') as f:
        f.write("; CPMZ80.BIN: CPM.COM's Z80 part, loaded at %04Xh (over COLD)\n"
                '; address  bytes  source\n' % syms['ENDBIOS'] + '\n'.join(cpmrows) + '\n')
    zt0 = symtab(lines, 0, split, syms)
    ct = symtab(lines, split, len(lines), syms)
    lo_c = syms['ENDBIOS']
    # Z86.SYS.sym: every symbol of either part from D000h to BIOSEND (the
    # image's range; CPMZ80's labels over COLD included); CPMZ80.sym: its
    # own, plus the BIOS labels in its range
    zt = {k: v for k, v in list(zt0.items()) + list(ct.items()) if 0xD000 <= v[0] <= syms['BIOSEND']}
    ct.update({k: v for k, v in zt0.items() if lo_c <= v[0] <= syms['BIOSEND'] and v[1] != 'equ'})
    write_sym(os.path.join(outdir, 'Z86.SYS.sym'),
              '; Z86.SYS at D000h (CPMZ80 symbols from %04Xh are in CPMZ80.sym)\n'
              '; address  kind  name   (kind: code / data / equ, from the source line)\n' % lo_c, zt)
    write_sym(os.path.join(outdir, 'CPMZ80.sym'),
              '; CPMZ80.BIN at %04Xh\n'
              '; address  kind  name   (kind: code / data / equ, from the source line)\n' % lo_c, ct)
    if os.path.exists(getattr(z86, 'TERMZ80', '')):
        term(outdir)
    print('wrote', outdir)


def term(outdir):
    """TERMZ80.lst / .sym: TERMZ80.ASM assembled after I86.ASM and BIOS.ASM
    (z86.termz80); the listing from its ORG on, the table with every
    label and EQU of TERMZ80.ASM."""
    bios = open(z86.BIOS).read().replace('\n        END\n', '\n')
    head = z86.preprocess(open(z86.SRC).read() + bios)
    text = z86.preprocess(open(z86.SRC).read() + bios + open(z86.TERMZ80).read())
    lines, addr, out, syms = assemble_with_lines(text)
    first = len(head.split('\n')) - 1          # TERMZ80.ASM's first line
    split = next(i for i in range(first, len(lines))
                 if statement(lines[i])[2] == 'ORG' and 'ENDBIOS' in lines[i])
    ptr = syms['BIOSEND'] - 0xD000
    rows, _ = listing(lines, addr, out, split, len(lines), ptr)
    with open(os.path.join(outdir, 'TERMZ80.lst'), 'w') as f:
        f.write("; TERMZ80.BIN: TERM.COM's Z80 part, loaded at %04Xh (over COLD)\n"
                '; address  bytes  source\n' % syms['ENDBIOS'] + '\n'.join(rows) + '\n')
    write_sym(os.path.join(outdir, 'TERMZ80.sym'),
              '; TERMZ80.BIN at %04Xh, and the EQUs of TERMZ80.ASM\n'
              '; address  kind  name   (kind: code / data / equ, from the source line)\n' % syms['ENDBIOS'],
              symtab(lines, first, len(lines), syms))


if __name__ == '__main__':
    main()
