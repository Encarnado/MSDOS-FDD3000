#!/usr/bin/env python3
"""lint.py - style and hazard checks for the Z80 volumes (dict/CONVENTIONS.md).

    python3 tools/lint.py                 all asm/*.asm
    python3 tools/lint.py parts/z86_03.asm   given files

ERRORS (must be 0):
  R3  8-bit operand opening with a <reg8>_ symbol (z80asm reads the register)
  R2  jump/call target named <cond>_...
  RAW in/out with a numeric port (use the shared hardware equates)
WARNINGS:
  CRYPTIC  label still looks like a numbered source local (CB1, LD2, S8R7)
           and carries no (src: ...) mark
REPORT: comment coverage = instruction lines with a comment / instruction lines
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R8OPS = {'ld', 'add', 'adc', 'sub', 'sbc', 'and', 'xor', 'or', 'cp'}
REG8 = re.compile(r'^[ABCDEHLIR]_', re.I)
COND = re.compile(r'^(NZ|Z|NC|C|PO|PE|P|M)_', re.I)
R16 = {'bc', 'de', 'hl', 'sp', 'ix', 'iy', 'af'}


def split_ops(s):
    out, depth, cur, q = [], 0, '', None
    for ch in s:
        if q:
            cur += ch
            q = None if ch == q else q
            continue
        if ch in "'\"" and not cur.lower().endswith('af'):
            q = ch
        if ch == '(':
            depth += 1
        if ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            continue
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def lint_nasm(path):
    ins = com = 0
    for line in open(path):
        code, _, comment = line.rstrip('\n').partition(';')
        if not code.startswith('\t') or not code.strip():
            continue
        mn = code.split()[0].lower()
        if mn in ('db', 'dw', 'dd', 'times', 'incbin', 'org', 'bits', 'equ') or mn.startswith('%'):
            continue
        ins += 1
        com += bool(comment.strip())
    return [], [], ins, com


def lint(path):
    if any(l.strip() == 'bits 16' for l in open(path)):
        return lint_nasm(path)
    errs, warns = [], []
    ins = com = 0
    for n, line in enumerate(open(path), 1):
        code, _, comment = line.rstrip('\n').partition(';')
        m = re.match(r'^([A-Za-z_]\w*):', code)
        if m:
            lab = m.group(1)
            rest = code[m.end():].strip()
            if re.fullmatch(r'[A-Z]{1,5}\d{1,2}[A-Z]?\d?', lab) and 'src:' not in comment \
                    and not rest.lower().startswith('equ'):
                warns.append('%s:%d CRYPTIC %s' % (path, n, lab))
            continue
        if not code.startswith('\t') or not code.strip():
            continue
        parts = code.strip().split(None, 1)
        mn = parts[0].lower()
        if mn in ('defb', 'defw', 'defs', 'defm', 'org', 'equ'):
            continue
        ins += 1
        if comment.strip():
            com += 1
        ops = split_ops(parts[1]) if len(parts) > 1 else []
        if mn in R8OPS and ops:
            src = ops[-1]
            dst = ops[0] if len(ops) > 1 else ''
            if not src.startswith('(') and REG8.match(src) and dst.lower() not in R16:
                errs.append('%s:%d R3 %s' % (path, n, code.strip()))
        if mn in ('jp', 'jr', 'call', 'djnz') and ops and COND.match(ops[-1]) \
                and ops[-1].lower() not in ('nz', 'z', 'nc', 'c', 'po', 'pe', 'p', 'm'):
            errs.append('%s:%d R2 %s' % (path, n, code.strip()))
        if mn in ('in', 'out'):
            for o in ops:
                if re.fullmatch(r'\((0?[0-9A-Fa-f]+h|\d+)\)', o):
                    errs.append('%s:%d RAW %s' % (path, n, code.strip()))
    return errs, warns, ins, com


def main():
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, 'asm', '*.asm')))
    te = tw = 0
    for f in files:
        e, w, ins, com = lint(f)
        te += len(e)
        tw += len(w)
        for x in e + w:
            print(x)
        print('%-28s instr %5d  commented %5.1f%%  errors %d  warnings %d'
              % (os.path.basename(f), ins, 100.0 * com / max(ins, 1), len(e), len(w)))
    sys.exit(1 if te else 0)


if __name__ == '__main__':
    main()
