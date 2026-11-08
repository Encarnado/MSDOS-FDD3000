#!/usr/bin/env python3
"""z80dis.py - first-cut disassembly of a Z80 image, cross-checked against
the build listing.  Produces the SKELETON that the narration pass then
edits by hand; after that the .asm in asm/ is the master and
tools/roundtrip.sh is the gate.

    python3 tools/z80dis.py BOOT            -> build/BOOT.skel.asm + report
    python3 tools/z80dis.py BOOT --install  -> also asm/boot.asm (refuses to
                                               overwrite an existing file)

Method (independent of the source, then reconciled with it):
  1. Code discovery is recursive descent over the BYTES, seeded from the
     entry points and tables named in DISASSEMBLY_GUIDE.md (images.py).
  2. Every decoded instruction must coincide with an instruction line of
     the build listing (same address, same bytes): the code/data partition
     is thereby proven twice.  Listing instructions the descent did not
     reach are reported (table-reached code missing a seed, or dead code).
  3. Labels come from symbols/*.sym; the author's symbolic operand and data
     expressions are taken from the listing where the bytes agree - the
     round-trip gate proves each expression evaluates to the same bytes.
     Mnemonics always come from the decode (the project assembler relaxes
     an out-of-range JR into JP: the bytes, not the source, are canon).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from z80decode import decode  # noqa: E402
import images  # noqa: E402

REGS = {'a', 'b', 'c', 'd', 'e', 'h', 'l', 'f', 'i', 'r', 'af', "af'", 'bc',
        'de', 'hl', 'sp', 'ix', 'iy', 'ixh', 'ixl', 'iyh', 'iyl',
        'nz', 'z', 'nc', 'po', 'pe', 'p', 'm'}


# ------------------------------------------------------------------ listing
def read_listing(path):
    """addr -> dict(bytes=[...], src=str, label=str|None, op=str, args=str,
    comment=str); plus ordered list of (addr|None, src) for comment lines."""
    ent = {}
    order = []
    last = None
    for raw in open(path, encoding='latin-1'):
        raw = raw.rstrip('\n')
        if raw.startswith(';') and last is None and not order:
            continue                                   # file banner
        head, src = raw[:32], raw[32:]
        m = re.match(r'^([0-9A-F]{4})  ((?:[0-9A-F]{2} ?)*)', head)
        addr = int(m.group(1), 16) if m else None
        bys = [int(x, 16) for x in m.group(2).split()] if m else []
        if m and not src.strip() and last is not None and bys:
            ent[last]['bytes'] += bys                  # DS continuation
            continue
        lab, op, args, com = split_source(src)
        if addr is not None and bys:
            ent[addr] = dict(bytes=bys, src=src, label=lab, op=op,
                             args=args, comment=com)
            last = addr
            order.append((addr, src))
        else:
            order.append((None, src))
            if op and op.upper() not in ('EQU', 'ORG', 'END'):
                last = None
    return ent, order


def split_source(src):
    s = src
    com = ''
    # comment = first ';' outside quotes
    q = None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in "'\"":
            # AF' is not a quote
            if ch == "'" and s[max(0, i - 2):i].upper() == 'AF':
                continue
            q = ch
        elif ch == ';':
            com = s[i + 1:].strip()
            s = s[:i]
            break
    lab = None
    m = re.match(r'^([A-Za-z_.$?@][\w.$?@]*):?\s*', s)
    if m and not s[:1].isspace():
        lab = m.group(1)
        s = s[m.end():]
    s = s.strip()
    parts = s.split(None, 1)
    op = parts[0] if parts else ''
    args = parts[1].strip() if len(parts) > 1 else ''
    if op.upper() == 'EQU':
        return lab, op, args, com
    return lab, op, args, com


def split_args(args):
    out, depth, q, cur = [], 0, None, ''
    for i, ch in enumerate(args):
        if q:
            cur += ch
            if ch == q:
                q = None
            continue
        if ch in "'\"" and not (ch == "'" and cur.strip().upper().endswith('AF')):
            q = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            continue
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


REG8_PREFIX = re.compile(r'^[ABCDEHLIRabcdehlir]_')


def guard8(expr):
    """z80asm (Wijnen) lexes a symbol whose name starts with an 8-bit
    register letter + '_' (B_ES, H_X, R_AX ...) as that REGISTER when it
    opens an 8-bit operand: 'add a,B_ES&0FFh' assembles as 'add a,b',
    silently.  Keep such a symbol off the front of the operand."""
    if not REG8_PREFIX.match(expr):
        return expr
    m = re.match(r'^(\w+)\s*&\s*(0FFh|0ffh|255)$', expr)
    if m:
        return '0FFh&' + m.group(1)
    return '0+' + expr


def lower_regs(text):
    def f(m):
        w = m.group(0)
        return w.lower() if w.lower() in REGS else w
    return re.sub(r"[A-Za-z][A-Za-z0-9_']*", f, text)


# ------------------------------------------------------------------ symbols
def read_sym(path):
    labels = {}
    equs = {}
    for line in open(path):
        if line.startswith(';') or not line.strip():
            continue
        p = line.split()
        if len(p) == 2:
            a, name = int(p[0], 16), p[1]
            kind = 'code'
        else:
            a, kind, name = int(p[0], 16), p[1], p[2]
        if kind == 'equ':
            equs.setdefault(a, []).append(name)
        else:
            labels.setdefault(a, []).append(name)
    return labels, equs


# ------------------------------------------------------------------ descent
def discover(img, mem, lo, hi, seeds):
    code = {}
    work = list(seeds)
    while work:
        a = work.pop()
        while lo <= a < hi and a not in code:
            ln, mn, ops, info = decode(mem, a)
            code[a] = (ln, mn, ops, info)
            t = info.get('target')
            if t is not None and info['flow'] in ('jump', 'call') and lo <= t < hi:
                if mn != 'rst':
                    work.append(t)
            if img.get('ix_targets') and mn == 'ld' and ops[:1] == ['ix'] \
                    and ops[1] == '{nn}' and lo <= info['nn'] < hi:
                work.append(info['nn'])
            if info['flow'] in ('ret', 'stop') and not info['cond']:
                break
            if info['flow'] == 'jump' and not info['cond']:
                break
            if a in img.get('noreturn_calls', ()) or \
               (info['flow'] == 'call' and t in img.get('noreturn', ())):
                break
            a += ln
    return code


# ------------------------------------------------------------------ emit
def fmt_num(v, bits):
    s = '%0*xh' % (2 if bits == 8 else 4, v)
    return '0' + s if s[0] in 'abcdef' else s


def render(mn, ops, info, src_entry, symname):
    """Operands from the decode, symbolic text from the listing if it agrees."""
    srcops = None
    if src_entry and src_entry['op'] and src_entry['op'].upper() not in ('DB', 'DW', 'DS'):
        srcops = split_args(src_entry['args'])
    out = []
    for i, o in enumerate(ops):
        if '{' not in o:
            out.append(o)
            continue
        cand = srcops[i] if srcops and len(srcops) == len(ops) else None
        if cand is not None:
            cand = lower_regs(cand)
            if o in ('{n}',) or '{p}' in o:
                cand = guard8(cand)
            if o.startswith('(') and o != '{(nn)}':      # (ix{d}) forms
                out.append(cand)
                continue
            out.append(cand)
            continue
        # no listing text: plain numbers, labels for branch targets
        if '{e}' in o:
            out.append(symname(info['e']) or fmt_num(info['e'], 16))
        elif '{nn}' in o and o == '{nn}':
            v = info['nn']
            out.append((symname(v) if info.get('target') == v else None) or fmt_num(v, 16))
        elif '{(nn)}' in o:
            out.append('(%s)' % (symname(info['nn']) or fmt_num(info['nn'], 16)))
        elif '{n}' in o:
            out.append(o.replace('{n}', fmt_num(info['n'], 8)))
        elif '{p}' in o:
            out.append(o.replace('{p}', fmt_num(info['p'], 8)))
        elif '{d}' in o:
            d = info['d']
            out.append(o.replace('{d}', ('+%s' % fmt_num(d, 8)) if d >= 0 else ('-%s' % fmt_num(-d, 8))))
    return out


def data_line(src_entry):
    op = src_entry['op'].upper()
    kw = {'DB': 'defb', 'DW': 'defw', 'DS': 'defs'}[op]
    args = src_entry['args']
    return kw, args


def add_externs(img, out):
    if not img.get('extern_syms') and not img.get('extern_equ_src'):
        return out
    text = '\n'.join(l.split(';')[0] for l in out)
    defined = set(re.findall(r'^([A-Za-z_]\w*):', text, re.M))
    used = set(re.findall(r'\b([A-Za-z_]\w*)\b', '\n'.join(
        l.split(';')[0].split('\t', 2)[-1] for l in out if l.startswith('\t'))))
    used -= REGS | defined
    used = {u for u in used if not re.match(r'^(defb|defw|defs|defm|org|equ)$', u, re.I)
            and not re.match(r'^[0-9]', u) and not re.match(r'^[0-9a-fA-F]+h$', u)}
    vals = {}
    for f in img.get('extern_syms', ()):
        for line in open(os.path.join(ROOT, f)):
            p = line.split()
            if len(p) == 3 and not line.startswith(';'):
                vals.setdefault(p[2], int(p[0], 16))
    srcequ = {}
    if img.get('extern_equ_src'):
        for line in open(os.path.join(ROOT, img['extern_equ_src'])):
            m = re.match(r'^(\w+)\s+EQU\s+([^;]+?)\s*(;.*)?$', line)
            if m:
                srcequ[m.group(1)] = (m.group(2), m.group(3) or '')
    blk = ['', '; ---- symbols defined outside this image ----']
    loc = [u for u in sorted(used) if u in srcequ and u not in defined]
    ext = [u for u in sorted(used, key=lambda n: vals.get(n, 0)) if u in vals and u not in srcequ]
    missing = sorted(used - set(loc) - set(ext))
    for u in loc:
        blk.append('%s:\tequ\t%s\t%s' % (u, srcequ[u][0], srcequ[u][1]))
    for u in ext:
        blk.append('%s:\tequ\t%s\t; Z86.SYS' % (u, fmt_num(vals[u], 16)))
    if missing:
        blk.append('; UNRESOLVED: ' + ' '.join(missing))
    blk.append('')
    return out[:2] + blk + out[2:]


def main():
    name = sys.argv[1]
    img = images.IMAGES[name]
    data = open(os.path.join(ROOT, img['bin']), 'rb').read()
    org = img['org']
    lo, hi = org, org + len(data)
    mem = lambda a: data[a - org] if lo <= a < hi else 0
    lst, order = read_listing(os.path.join(ROOT, img['lst']))
    labels, equs = read_sym(os.path.join(ROOT, img['sym']))

    seeds = set(img['seeds'])
    for t in img.get('split_tables', ()):          # (lo_addr, hi_addr, count)
        for k in range(t[2]):
            seeds.add(mem(t[0] + k) | (mem(t[1] + k) << 8))
    for t in img.get('word_tables', ()):           # (addr, count)
        for k in range(t[1]):
            seeds.add(mem(t[0] + 2 * k) | (mem(t[0] + 2 * k + 1) << 8))
    if img.get('seed_listing_dw'):          # dispatch tables of (char, DW handler)
        for a, e in lst.items():
            if e['op'].upper() == 'DW':
                b = e['bytes']
                for k in range(0, len(b) - 1, 2):
                    seeds.add(b[k] | b[k + 1] << 8)
    for base, size, count in img.get('slot_blocks', ()):   # SMC JP targets
        for k in range(count):
            seeds.add(base + k * size)
    seeds = {s for s in seeds if lo <= s < hi}
    code = discover(img, mem, lo, hi, seeds)

    def symname(v):
        n = labels.get(v)
        return n[0] if n else None

    # ---- reconcile with listing
    rep = []
    lst_instr = {a for a, e in lst.items()
                 if e['op'] and e['op'].upper() not in ('DB', 'DW', 'DS')}
    for a, (ln, mn, ops, info) in sorted(code.items()):
        e = lst.get(a)
        mine = list(data[a - org:a - org + ln])
        if e is None:
            rep.append('MISALIGNED %04X: decoded %s %s, no listing line here' % (a, mn, ops))
        elif e['bytes'][:ln] != mine:
            rep.append('BYTES %04X: decode %s vs listing %s' % (a, mine, e['bytes']))
        elif a not in lst_instr:
            rep.append('CODE-IN-DATA %04X: decoded %s, listing says %s' % (a, mn, e['src'].strip()))
    unreached = sorted(lst_instr - set(code))
    # collapse unreached into runs
    runs, start, prev = [], None, None
    for a in unreached:
        if start is None:
            start = prev = a
        elif a - prev <= 4:
            prev = a
        else:
            runs.append((start, prev))
            start = prev = a
    if start is not None:
        runs.append((start, prev))
    for s, p in runs:
        rep.append('UNREACHED %04X-%04X (first: %s %s)' % (s, p, lst[s]['label'] or '', lst[s]['src'].strip()[:50]))

    # ---- emit skeleton: walk the listing order (keeps comments + equs),
    #      emitting code from the decode and data from the listing
    out = []
    out.append('; %s - skeleton generated by tools/z80dis.py (decode + listing reconcile)' % name)
    out.append('\torg\t%s' % fmt_num(org, 16))
    pending_comments = []
    for addr, src in order:
        if addr is None:
            lab, op, args, com = split_source(src)
            if op.upper() == 'EQU' and lab:
                out.append('%s:\tequ\t%s%s' % (lab, args, ('\t; ' + com) if com else ''))
            elif op.upper() in ('ORG', 'END'):
                continue
            elif src.strip().startswith(';') or not src.strip():
                out.append(src.strip() if src.strip() else '')
            elif lab and not op:
                out.append('%s:%s' % (lab, ('\t; ' + com) if com else ''))
            continue
        e = lst[addr]
        if e['label']:
            out.append('%s:' % e['label'])
        com = ('\t; ' + e['comment']) if e['comment'] else ''
        if addr in code:
            ln, mn, ops, info = code[addr]
            rops = render(mn, ops, info, e, symname)
            out.append('\t%s\t%s%s' % (mn, ','.join(rops), com) if rops else '\t%s%s' % (mn, com))
            # listing instruction that spans more than one decode? (never expected)
        elif e['op'] and e['op'].upper() in ('DB', 'DW', 'DS'):
            kw, args = data_line(e)
            out.append('\t%s\t%s%s' % (kw, args, com))
        else:
            # listing instruction the descent never reached: keep as code,
            # flagged, so the gate still checks it
            # decode it from the bytes all the same (linear, at the
            # listing's own boundary); the report lists these runs
            ln, mn, ops, info = decode(mem, addr)
            if list(data[addr - org:addr - org + ln]) != e['bytes'][:ln]:
                raise SystemExit('listing/decode disagree at %04X' % addr)
            rops = render(mn, ops, info, e, symname)
            out.append('\t%s\t%s%s' % (mn, ','.join(rops), com) if rops else '\t%s%s' % (mn, com))
    out = add_externs(img, out)
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    skel = os.path.join(ROOT, 'build', name + '.skel.asm')
    open(skel, 'w').write('\n'.join(out) + '\n')
    repf = os.path.join(ROOT, 'build', name + '.dis-report.txt')
    open(repf, 'w').write('\n'.join(rep) + '\n')
    ncode = sum(c[0] for c in code.values())
    print('%s: %d bytes, %d code bytes by descent from %d seeds; %d report lines'
          % (name, len(data), ncode, len(seeds), len(rep)))
    for r in rep[:40]:
        print('  ' + r)
    if '--install' in sys.argv:
        dst = os.path.join(ROOT, 'asm', img['asm'])
        if os.path.exists(dst):
            sys.exit('refusing to overwrite ' + dst)
        open(dst, 'w').write('\n'.join(out) + '\n')
        print('installed', dst)


if __name__ == '__main__':
    main()
