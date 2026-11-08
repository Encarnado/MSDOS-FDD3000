#!/usr/bin/env python3
"""x86dis.py - first-cut NASM disassembly of an 8086 .COM/.SYS image,
reconciled with its MASM 1.10 listing.  Skeleton only: after --install the
.asm in asm/ is the master and tools/roundtrip.sh is the gate.

    python3 tools/x86dis.py FORMAT            -> build/FORMAT.skel.asm + report
    python3 tools/x86dis.py FORMAT --install  -> asm/format.asm (never overwrites)

Method:
  1. The MASM listing gives the offset at which each source line starts, and
     whether it is an instruction or data; the BINARY gives the bytes (the
     listing shows words in value order and relocations as 'R', so its byte
     column is not used).  A line covers [its offset, next offset).
  2. Instruction slices are decoded independently by ndisasm; a decode that
     does not consume exactly the slice is reported.  0Fh nn (the
     interpreter's BIOS trap; POP CS on a real 8086) becomes `TRAP nn`.
  3. Numbers in decoded operands are replaced by a symbol when the author's
     source operand names a symbol of that value (.sym file).
  4. The whole file is assembled with a NASM listing and compared with the
     binary line by line; a line whose NASM encoding differs from MASM's
     (8086 has redundant encodings) is emitted as `db` with the instruction
     as its comment.  Repeat until byte-identical.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PKG = os.path.join(ROOT, '..')

IMAGES = {
    'IOSYS': dict(bin='bin/IO.SYS', lst='symbols/x86/IOFDD.LST', sym='symbols/x86/IO.SYS.sym',
                  org=0x0000, asm='iosys.asm'),
    'FORMAT': dict(bin='bin/FORMAT.COM', lst='symbols/x86/FORMAT.LST', sym='symbols/x86/FORMAT.COM.sym',
                   org=0x0100, asm='format.asm'),
    'CPMCOM': dict(bin='bin/CPM.COM', lst='symbols/x86/CPM.LST', sym='symbols/x86/CPM.COM.sym',
                   org=0x0100, asm='cpmcom.asm'),
    'EDIT': dict(bin='bin/EDIT.COM', lst='symbols/x86/EDIT.LST', sym='symbols/x86/EDIT.COM.sym',
                 org=0x0100, asm='edit.asm'),
    'MODE': dict(bin='bin/MODE.COM', lst='symbols/x86/MODE.LST', sym='symbols/x86/MODE.COM.sym',
                 org=0x0100, asm='mode.asm'),
    'TERM': dict(bin='bin/TERM.COM', lst='symbols/x86/TERM.LST', sym='symbols/x86/TERM.COM.sym',
                 org=0x0100, asm='term.asm'),
}

DATA_OPS = {'DB', 'DW', 'DD'}


# ------------------------------------------------------------------ listing
def read_lst(path):
    """-> list of dict(off, src, macro) in listing order (source lines only)."""
    recs = []
    for raw in open(path, encoding='latin-1'):
        raw = raw.rstrip('\n').rstrip('\x0c')
        if 'Microsoft MACRO Assembler' in raw:
            continue
        if re.match(r'^(Segments and groups|Symbols|Macros|Structures)', raw.strip(), re.I):
            break
        m = re.match(r'^\s*(\d+)\t(.*)$', raw)
        if m:
            fields = m.group(2).split('\t')
            head = fields[0]
            src = '\t'.join(fields[1:])
            # strip the byte-column filler: listing uses ' \t' cells
            src = re.sub(r'^(\s?\t)*', '', src) if src.startswith(' ') or src.startswith('\t') else src
            om = re.match(r'^\s?([0-9A-F]{4})\b', head)
            off = int(om.group(1), 16) if om else None
            macro = '+' in head or src.startswith('+')
            src = src.lstrip('+').lstrip('\t')
            # an offset with only byte continuation and no source text
            hasb = bool(re.match(r'^\s?[0-9A-F]{4}\s+[0-9A-F]{2}', head))
            recs.append(dict(off=off, src=src, macro=macro, head=head, hasb=hasb))
        elif raw.startswith('\t') and recs:
            cont = re.sub(r'^\t \t \t \t', '', raw)     # exact wrap filler
            recs[-1]['src'] += cont
    return recs


def split_src(src):
    s, com, q = src, '', None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in '"\'':
            q = ch
        elif ch == ';':
            com, s = s[i + 1:].strip(), s[:i]
            break
    lab = None
    m = re.match(r'^([A-Za-z_?@$][\w?@$]*)(:|\s+(?=(DB|DW|DD|EQU|LABEL|PROC|ENDP|SEGMENT|ENDS|GROUP|=)\b))', s, re.I)
    if m:
        lab = m.group(1)
        s = s[m.end():]
    s = s.strip()
    p = s.split(None, 1)
    op = p[0].upper() if p else ''
    args = p[1].strip() if len(p) > 1 else ''
    return lab, op, args, com


def read_sym(path):
    labs, nums = {}, {}
    for line in open(path):
        if line.startswith(';') or not line.strip():
            continue
        p = line.split()
        v = int(p[0], 16)
        name = p[-1]
        if p[1] == 'Number':
            nums[name] = v
        else:
            labs[name] = v
    return labs, nums


# ------------------------------------------------------------------ decode
def ndisasm(data, off):
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(data)
        tmp = f.name
    out = subprocess.run(['ndisasm', '-b', '16', '-o', str(off), tmp],
                         capture_output=True, text=True).stdout
    os.unlink(tmp)
    res = []
    for line in out.splitlines():
        m = re.match(r'^([0-9A-F]{8})\s+([0-9A-F]+)\s+(.*)$', line)
        if m:
            res.append((int(m.group(1), 16), len(m.group(2)) // 2, m.group(3).strip()))
        elif res and re.match(r'^\s+-([0-9A-F]+)$', line):      # long-byte continuation
            a, ln, t = res[-1]
            res[-1] = (a, ln + len(line.strip()[1:]) // 2, t)
    return res


DBIT_OPS = {0x02: 'add', 0x0A: 'or', 0x12: 'adc', 0x1A: 'sbb', 0x22: 'and',
            0x2A: 'sub', 0x32: 'xor', 0x3A: 'cmp', 0x8A: 'mov'}
JCC = re.compile(r'^(j(?!mp)[a-z]+|loop[a-z]*|jcxz)\s+(?!short)')


def masm_form(text, b):
    """Spell an instruction so NASM (-O0) emits MASM's bytes.
    - reg,reg ALU/MOV with the direction bit set (MASM's choice, NASM never
      makes it): the `_d` macro family, e.g. `xor_d bp,bp` = 33 ED.
    - 8086 conditional jumps / LOOP / JCXZ are always short: say so (with -O0
      NASM would otherwise emit a 386 near Jcc)."""
    if len(b) == 2 and b[1] >= 0xC0 and (b[0] & 0xFE) in DBIT_OPS:
        mn, _, ops = text.partition(' ')
        return '%s_d %s' % (DBIT_OPS[b[0] & 0xFE], ops)
    if b[:1] == b'\x83' and 'byte' not in text.rsplit(',', 1)[-1]:
        head, _, imm = text.rpartition(',')
        return '%s,byte %s' % (head, imm.strip().lstrip('+'))      # imm8, sign-extended
    if b[:1] == b'\xeb' and text.startswith('jmp ') and 'short' not in text:
        return 'jmp short ' + text[4:]
    if JCC.match(text):
        mn, _, ops = text.partition(' ')
        return '%s short %s' % (mn, ops)
    return text


def symbolize(text, src_args, labs, nums):
    """Replace 0x.. numbers in ndisasm text by symbols named in the source."""
    names = set(re.findall(r'[A-Za-z_?@$][\w?@$]*', src_args or ''))
    cand = {}
    for n in names:
        if n in labs:
            cand.setdefault(labs[n], n)
        elif n in nums:
            cand.setdefault(nums[n], n)

    def f(m):
        v = int(m.group(1), 16)
        return cand.get(v, m.group(0))
    head, _, ops = text.partition(' ')
    if not ops:
        return text
    return head + ' ' + re.sub(r'\b0x([0-9a-fA-F]+)\b', f, ops)


def outside_quotes(text, fn):
    """Apply fn to the parts of text that are not inside '...' or "..."."""
    out, cur, q = [], '', None
    for ch in text:
        if q:
            cur += ch
            if ch == q:
                out.append(cur)
                cur, q = '', None
        elif ch in '"\'':
            out.append(fn(cur))
            cur, q = ch, ch
        else:
            cur += ch
    out.append(cur if q else fn(cur))
    return ''.join(out)


def masm_data_to_nasm(op, args):
    a = outside_quotes(args, lambda t: re.sub(r'\bOFFSET\s+', '', t, flags=re.I))
    m = re.match(r'^(\S+)\s+DUP\s*\((.*)\)$', a, re.I)
    if m:
        v = m.group(2).strip()
        v = '0' if v == '?' else v
        return 'times %s %s %s' % (m.group(1), op.lower(), v)
    a = outside_quotes(a, lambda t: re.sub(r'(?<![\w])\?(?![\w])', '0', t))
    return '%s %s' % (op.lower(), a)


# ------------------------------------------------------------------ build
def build(name):
    img = IMAGES[name]
    data = open(os.path.join(ROOT, img['bin']), 'rb').read()
    org = img['org']
    end = org + len(data)
    recs = read_lst(os.path.join(PKG, img['lst']))
    labs, nums = read_sym(os.path.join(PKG, img['sym']))

    # offsets of byte-producing lines: an offset line whose next offset differs
    seq = [r for r in recs if r['off'] is not None]
    lines = []          # (kind, text, comment, label, start, length)
    report = []
    offs = sorted({r['off'] for r in seq if r['hasb'] and org <= r['off'] <= end} | {end})
    nxt = {o: offs[i + 1] for i, o in enumerate(offs[:-1])}
    seen_bytes = set()
    for r in recs:
        lab, op, args, com = split_src(r['src'])
        o = r['off']
        if r['macro'] and o is None:
            continue
        if op in ('SEGMENT', 'ENDS', 'GROUP'):
            continue
        if op in ('SEGMENT', 'ENDS', 'GROUP'):
            continue
        if o is None or op in ('ORG', 'SEGMENT', 'ENDS', 'ASSUME', 'END', 'EQU', '=', 'PROC',
                               'ENDP', 'MACRO', 'ENDM') or op == '':
            if op in ('EQU', '=') and lab:
                lines.append(('equ', '%s equ %s' % (lab, masm_data_to_nasm('', args)[1:].strip()),
                              com, None, None, 0))
            elif lab and o is not None:
                lines.append(('label', '', com, lab, o, 0))
            elif not op and not lab and r['src'].strip().startswith(';'):
                lines.append(('comment', '', r['src'].strip()[1:].strip(), None, None, 0))
            elif not r['src'].strip():
                lines.append(('blank', '', '', None, None, 0))
            elif op == 'LABEL' and lab:
                lines.append(('label', '', com, lab, o, 0))
            continue
        if not r['hasb'] and op not in DATA_OPS:
            if lab:
                lines.append(('label', '', com, lab, o, 0))
            continue
        if o < org or o >= end or o in seen_bytes:
            if lab and o is not None and o >= end:
                lines.append(('equ', '%s equ 0%Xh' % (lab, o), com + ' (beyond the file)', None, None, 0))
            continue
        seen_bytes.add(o)
        ln = nxt[o] - o
        chunk = data[o - org:o - org + ln]
        if op in DATA_OPS:
            lines.append(('data', masm_data_to_nasm(op, args), com, lab, o, ln))
            continue
        # instructions: decode the slice
        dec = ndisasm(chunk, o)
        if chunk[:1] == b'\x0f' and ln == 2:
            lines.append(('code', 'TRAP %02Xh' % chunk[1], com, lab, o, ln))
            continue
        if sum(d[1] for d in dec) != ln:
            report.append('SLICE %04X: decode %s vs %d bytes (%s)' % (o, [d[2] for d in dec], ln, r['src'].strip()))
        for k, (a, dl, t) in enumerate(dec):
            t = masm_form(t, data[a - org:a - org + dl])
            t = symbolize(t, args, labs, nums)
            lines.append(('code', t, com if k == 0 else '', lab if k == 0 else None, a, dl))
    return img, data, org, lines, report


NASM_RESERVED = re.compile(
    r'^(st[0-7]|dr[0-7]|cr[0-7]|tr[0-7]|mm[0-7]|xmm\d+|ymm\d+|zmm\d+|k[0-7]|bnd[0-3]|'
    r'seg|wrt|abs|rel|strict|near|far|short|byte|word|dword|qword|tword|oword|to|time|times)$', re.I)


def nasm_escape(line):
    """Author symbols that are NASM reserved words (ST1 = an x87 register,
    DR0 = a debug register) are written $ST1 / $DR0 outside comments."""
    code, sep, com = line.partition(';')
    def f(m):
        w = m.group(0)
        return '$' + w if NASM_RESERVED.match(w) and w.isupper() else w
    code = re.sub(r'(?<![\w$.])[A-Za-z_][\w]*', f, code)
    return code + sep + com


def render(lines, fallback, owners=None):
    out = _render(lines, fallback, owners)
    return [nasm_escape(l) for l in out]


def _render(lines, fallback, owners=None):
    out = ['bits 16']
    own = [None]
    for kind, text, com, lab, start, ln in lines:
        c = ('\t; ' + com) if com else ''
        if kind == 'comment':
            out.append('; ' + com if com else ';')
        elif kind == 'blank':
            out.append('')
        elif kind == 'equ':
            out.append(text + c)
        elif kind == 'label':
            out.append('%s:%s' % (lab, c))
        else:
            if lab:
                out.append('%s:' % lab)
                own.append(None)
            if start in fallback:
                out.append('\tdb\t%s\t; %s%s' % (fallback[start], text, ('  -- ' + com) if com else ''))
            else:
                out.append('\t%s%s' % (text, c))
            own.append((start, ln))
        while len(own) < len(out):
            own.append(None)
    if owners is not None:
        owners[:] = own
    return out


MACROS = ['%macro TRAP 1', '\tdb\t0Fh, %1\t; BIOS trap: POP CS on an 8086, a Z80 call here', '%endmacro',
          '; _d forms: reg,reg with the direction bit set - MASM\'s encoding of the',
          '; same operation (NASM would emit the r/m,reg form).  xor_d bp,bp = 33 ED.',
          '%define R16_ax 0', '%define R16_cx 1', '%define R16_dx 2', '%define R16_bx 3',
          '%define R16_sp 4', '%define R16_bp 5', '%define R16_si 6', '%define R16_di 7',
          '%define R8_al 0', '%define R8_cl 1', '%define R8_dl 2', '%define R8_bl 3',
          '%define R8_ah 4', '%define R8_ch 5', '%define R8_dh 6', '%define R8_bh 7',
          '%macro _D 3', '%ifdef R16_%2', '\tdb\t%1+3, 0C0h+(R16_%2<<3)+R16_%3', '%else',
          '\tdb\t%1+2, 0C0h+(R8_%2<<3)+R8_%3', '%endif', '%endmacro'] + \
         sum([['%%macro %s_d 2' % m, '\t_D %s, %%1, %%2' % h, '%endmacro']
              for m, h in (('add', '00h'), ('or', '08h'), ('adc', '10h'), ('sbb', '18h'), ('and', '20h'),
                           ('sub', '28h'), ('xor', '30h'), ('cmp', '38h'), ('mov', '88h'))], [])


def assemble_check(src_lines, img, data, org, lines):
    body = MACROS + ['org %s' % hex(org)] + src_lines
    with tempfile.TemporaryDirectory() as d:
        a = os.path.join(d, 'x.asm')
        open(a, 'w').write('\n'.join(body) + '\n')
        r = subprocess.run(['nasm', '-O0', '-f', 'bin', '-o', os.path.join(d, 'x.bin'),
                            '-l', os.path.join(d, 'x.lst'), a], capture_output=True, text=True)
        if r.returncode:
            return None, r.stderr, body
        return open(os.path.join(d, 'x.bin'), 'rb').read(), open(os.path.join(d, 'x.lst')).read(), body


def main():
    name = sys.argv[1]
    img, data, org, lines, report = build(name)
    fallback = {}
    def as_bytes(st, l):
        return ','.join('0%02Xh' % b if b >= 0xA0 else '%02Xh' % b for b in data[st - org:st - org + l])

    def text_of(st):
        return next(t for k, t, c, lb, s0, l0 in lines if s0 == st)

    for it in range(60):
        owners = []
        src = render(lines, fallback, owners)
        out, lst, body = assemble_check(src, img, data, org, lines)
        nhead = len(body) - len(src)              # MACROS + org lines before src
        if out is None:
            bad = [int(m) - 1 - nhead for m in re.findall(r':(\d+): error', lst)]
            hits = {owners[b] for b in bad if 0 <= b < len(owners) and owners[b]}
            hits = {h for h in hits if h[0] not in fallback}
            if not hits:
                print(lst[:2000])
                sys.exit('unresolvable assembly error')
            for st, l in hits:
                fallback[st] = as_bytes(st, l)
                report.append('ERROR %04X: NASM rejects -> db (%s)' % (st, text_of(st)))
            continue
        if out == data:
            break
        # bytes emitted per source line, from NASM's listing (macro lines
        # '<n>' belong to the source line that invoked them)
        per = {}
        cur = None
        for L in lst.splitlines():
            m = re.match(r'^\s*(\d+)\s+([0-9A-F]{8})\s+([0-9A-F()\[\]]+)\s*(<\d+>)?', L)
            m0 = re.match(r'^\s*(\d+)\s', L)
            if m0 and not re.search(r'<\d+>', L[:40]):
                cur = int(m0.group(1)) - 1 - nhead
            if m:
                key = cur
                o = org + int(m.group(2), 16)
                b = bytes.fromhex(re.sub(r'[^0-9A-F]', '', m.group(3)))
                if key is not None and 0 <= key < len(owners) and owners[key]:
                    per.setdefault(owners[key], []).append((o, b))
        # 1) lines whose SIZE differs from their slice: all culprits at once
        reps = {st for k, t, c, lb, st, l in lines if t.startswith('times ')}   # listed once
        size_bad = [(st, l) for (st, l), parts in per.items()
                    if st not in fallback and st not in reps and sum(len(b) for o, b in parts) != l]
        if size_bad:
            for st, l in size_bad:
                fallback[st] = as_bytes(st, l)
                report.append('SIZE %04X: NASM %s, MASM %d bytes -> db (%s)' % (
                    st, sum(len(b) for o, b in per[(st, l)]), l, text_of(st)))
            continue
        # 2) sizes all agree: same-size lines whose bytes differ (encoding choice)
        enc_bad = [(st, l) for (st, l), parts in per.items() if st not in fallback and st not in reps and
                   b''.join(b for o, b in sorted(parts)) != data[st - org:st - org + l]]
        if not enc_bad:
            sys.exit('bytes differ but no line localised (first diff %04X)' %
                     (org + next(i for i in range(min(len(out), len(data))) if out[i] != data[i])))
        for st, l in enc_bad:
            fallback[st] = as_bytes(st, l)
            report.append('ENCODING %04X: NASM %s vs MASM %s -> db (%s)' % (
                st, b''.join(b for o, b in sorted(per[(st, l)])).hex(), data[st - org:st - org + l].hex(),
                text_of(st)))
    else:
        sys.exit('did not converge')
    final = ['; %s - skeleton generated by tools/x86dis.py (MASM listing + ndisasm + NASM reconcile)' % name,
             '; assemble: nasm -O0 -f bin'] + MACROS + [
             '\torg\t%s' % ('0%Xh' % org if org else '0')] + render(lines, fallback)
    skel = os.path.join(ROOT, 'build', name + '.skel.asm')
    open(skel, 'w').write('\n'.join(final) + '\n')
    open(os.path.join(ROOT, 'build', name + '.dis-report.txt'), 'w').write('\n'.join(report) + '\n')
    ncode = sum(1 for l in lines if l[0] == 'code')
    print('%s: %d bytes, %d instructions, %d db fallbacks; report %d lines'
          % (name, len(data), ncode, len(fallback), len(report)))
    for r in report[:30]:
        print('  ' + r)
    if '--install' in sys.argv:
        dst = os.path.join(ROOT, 'asm', img['asm'])
        if os.path.exists(dst):
            sys.exit('refusing to overwrite ' + dst)
        open(dst, 'w').write('\n'.join(final) + '\n')
        print('installed', dst)


if __name__ == '__main__':
    main()
