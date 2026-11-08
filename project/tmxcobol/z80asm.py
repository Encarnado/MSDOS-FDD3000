#!/usr/bin/env python3
"""z80asm.py - small two-pass Z80 assembler used by the TMX COBOL compiler.

Syntax: Zilog mnemonics, one statement per line, ';' comments,
labels as 'name:' (or bare in column 1 before EQU), directives
ORG / EQU / DB DEFB DEFM / DW DEFW / DS DEFS / END / INCLUDE file / BSS
(after BSS only DS may follow; it reserves memory but stores nothing).
Symbols are case-insensitive.  Numbers: 123, 0x7F, 7Fh, $7F, %1010, 'c'.

    python3 z80asm.py in.asm out.com [-sym out.sym]
"""
import os
import re
import sys

R8 = {'B': 0, 'C': 1, 'D': 2, 'E': 3, 'H': 4, 'L': 5, '(HL)': 6, 'A': 7}
RP = {'BC': 0, 'DE': 1, 'HL': 2, 'SP': 3}
RP2 = {'BC': 0, 'DE': 1, 'HL': 2, 'AF': 3}
CC = {'NZ': 0, 'Z': 1, 'NC': 2, 'C': 3, 'PO': 4, 'PE': 5, 'P': 6, 'M': 7}
ALU = {'ADD': 0, 'ADC': 1, 'SUB': 2, 'SBC': 3, 'AND': 4, 'XOR': 5, 'OR': 6, 'CP': 7}
ROT = {'RLC': 0, 'RRC': 1, 'RL': 2, 'RR': 3, 'SLA': 4, 'SRA': 5, 'SLL': 6, 'SRL': 7}
SIMPLE = {
    'NOP': [0x00], 'RLCA': [0x07], 'RRCA': [0x0F], 'RLA': [0x17], 'RRA': [0x1F],
    'DAA': [0x27], 'CPL': [0x2F], 'SCF': [0x37], 'CCF': [0x3F], 'HALT': [0x76],
    'DI': [0xF3], 'EI': [0xFB], 'EXX': [0xD9],
    'NEG': [0xED, 0x44], 'RETN': [0xED, 0x45], 'RETI': [0xED, 0x4D],
    'RRD': [0xED, 0x67], 'RLD': [0xED, 0x6F],
    'LDI': [0xED, 0xA0], 'CPI': [0xED, 0xA1], 'INI': [0xED, 0xA2], 'OUTI': [0xED, 0xA3],
    'LDD': [0xED, 0xA8], 'CPD': [0xED, 0xA9], 'IND': [0xED, 0xAA], 'OUTD': [0xED, 0xAB],
    'LDIR': [0xED, 0xB0], 'CPIR': [0xED, 0xB1], 'INIR': [0xED, 0xB2], 'OTIR': [0xED, 0xB3],
    'LDDR': [0xED, 0xB8], 'CPDR': [0xED, 0xB9], 'INDR': [0xED, 0xBA], 'OTDR': [0xED, 0xBB],
}


class AsmError(Exception):
    pass


class Rel:
    """Relocatable value: sym + c, where sym is '$SEG' (the segment being
    assembled) or 'X:NAME' (an external symbol)."""
    __slots__ = ('c', 'sym')

    def __init__(self, c, sym):
        self.c, self.sym = c, sym

    def __add__(self, o):
        if isinstance(o, Rel):
            raise AsmError('cannot add two relocatable values')
        return Rel(self.c + o, self.sym)

    __radd__ = __add__

    def __sub__(self, o):
        if isinstance(o, Rel):
            if o.sym != self.sym:
                raise AsmError('difference of unrelated relocatable values')
            return self.c - o.c
        return Rel(self.c - o, self.sym)

    def __rsub__(self, o):
        raise AsmError('relocatable value subtracted from a constant')

    def __repr__(self):
        return 'Rel(%s%+d)' % (self.sym, self.c)


class RelaxJR(Exception):
    def __init__(self, line):
        Exception.__init__(self, line)
        self.line = line


def split_operands(s):
    out, cur, depth, q = [], '', 0, None
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
            continue
        if ch in '"\'':
            # AF' is a register, not a quote
            if ch == "'" and cur.strip().upper() == 'AF':
                cur += ch
                continue
            q = ch
            cur += ch
        elif ch == '(':
            depth += 1
            cur += ch
        elif ch == ')':
            depth -= 1
            cur += ch
        elif ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def strip_comment(line):
    q = None
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = None
        elif ch in '"\'':
            if ch == "'" and line[:i].upper().rstrip().endswith('AF'):
                continue
            q = ch
        elif ch == ';':
            return line[:i]
    return line


class Expr:
    TOK = re.compile(r"\s*(?:(0x[0-9A-Fa-f]+|\$[0-9A-Fa-f]+|%[01]+|[0-9][0-9A-Fa-f]*[Hh]|[0-9]+)"
                     r"|('(?:[^']|'')')|(<<|>>|[-+*/%&|^~()])|([A-Za-z_.?@][A-Za-z0-9_.?@$]*)|(\$))")

    def __init__(self, asm, text):
        self.asm = asm
        self.toks = []
        pos = 0
        text = text.strip()
        while pos < len(text):
            m = self.TOK.match(text, pos)
            if not m or m.end() == pos:
                raise AsmError('bad expression: %r' % text)
            pos = m.end()
            num, ch, op, sym, dollar = m.groups()
            if num is not None:
                if num.lower().startswith('0x'):
                    v = int(num[2:], 16)
                elif num.startswith('$'):
                    v = int(num[1:], 16)
                elif num.startswith('%'):
                    v = int(num[1:], 2)
                elif num[-1] in 'Hh':
                    v = int(num[:-1], 16)
                else:
                    v = int(num)
                self.toks.append(('n', v))
            elif ch is not None:
                self.toks.append(('n', ord(ch[1])))
            elif op is not None:
                self.toks.append(('o', op))
            elif sym is not None:
                self.toks.append(('s', sym.upper()))
            elif dollar is not None:
                self.toks.append(('n', asm.here(0)))
            else:
                break
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self):
        t = self.peek()
        self.i += 1
        return t

    def value(self):
        v = self.binop(0)
        if self.i != len(self.toks):
            raise AsmError('trailing junk in expression')
        return v

    LEVELS = [['|'], ['^'], ['&'], ['<<', '>>'], ['+', '-'], ['*', '/', '%']]

    def binop(self, lvl):
        if lvl == len(self.LEVELS):
            return self.unary()
        v = self.binop(lvl + 1)
        while True:
            k, o = self.peek()
            if k == 'o' and o in self.LEVELS[lvl]:
                self.take()
                r = self.binop(lvl + 1)
                if (isinstance(v, Rel) or isinstance(r, Rel)) and o not in '+-':
                    raise AsmError('operator %s on a relocatable value' % o)
                if o == '|': v |= r
                elif o == '^': v ^= r
                elif o == '&': v &= r
                elif o == '<<': v <<= r
                elif o == '>>': v >>= r
                elif o == '+': v += r
                elif o == '-': v -= r
                elif o == '*': v *= r
                elif o == '/': v = int(v / r) if r else 0
                elif o == '%': v = v % r if r else 0
            else:
                return v

    def unary(self):
        k, o = self.take()
        if k == 'o' and o in '-~':
            v = self.unary()
            if isinstance(v, Rel):
                raise AsmError('operator %s on a relocatable value' % o)
            return -v if o == '-' else ~v
        if k == 'o' and o == '+':
            return self.unary()
        if k == 'o' and o == '(':
            v = self.binop(0)
            k2, o2 = self.take()
            if o2 != ')':
                raise AsmError('missing )')
            return v
        if k == 'n':
            return o
        if k == 's':
            if o in self.asm.symbols:
                return self.asm.symbols[o]
            if o in self.asm.externals:
                return Rel(0, 'X:' + o)
            if self.asm.final:
                raise AsmError('undefined symbol %s' % o)
            self.asm.unresolved = True
            return 0
        raise AsmError('bad expression')


class Assembler:
    """reloc=False: absolute code at ORG (default 100h).
    reloc=True: the segment starts at offset 0 and its labels, '$' and
    the names in `externals` stay symbolic; every 16-bit field holding
    one is listed in self.relocs as (offset, sym, addend)."""

    def __init__(self, reloc=False, externals=(), symbols=None):
        self.reloc = reloc
        self.externals = set(externals)
        self.symbols = dict(symbols or {})

    def here(self, n):
        return Rel(self.pc + n, '$SEG') if self.reloc else self.pc + n

    def ev(self, text):
        return Expr(self, text).value()

    def emit(self, *bs):
        for b in bs:
            if isinstance(b, Rel):
                raise AsmError('relocatable value in a byte field')
            self.out.append(b & 0xFF)
        self.pc += len(bs)

    def emit_w(self, v):
        if isinstance(v, Rel):
            self.relocs.append((len(self.out), v.sym, v.c))
            self.emit(0, 0)
            return
        self.emit(v & 0xFF, (v >> 8) & 0xFF)

    @staticmethod
    def is_mem(op):
        if not (op.startswith('(') and op.endswith(')')):
            return False
        depth = 0
        for i, ch in enumerate(op):
            depth += ch == '('
            depth -= ch == ')'
            if depth == 0 and i != len(op) - 1:
                return False
        return True

    def idx(self, op):
        """(IX+d) / (IY-d) / (IX) -> (prefix, d) or None"""
        u = op.upper().replace(' ', '')
        if self.is_mem(u) and (u[1:3] in ('IX', 'IY')):
            inner = u[3:-1]
            d = self.ev(inner) if inner else 0
            if isinstance(d, Rel):
                raise AsmError('relocatable index offset')
            if self.final and not -128 <= d <= 127:
                raise AsmError('index offset out of range')
            return (0xDD if u[1:3] == 'IX' else 0xFD, d & 0xFF)
        return None

    def assemble(self, text):
        lines = text.split('\n')
        self.long_jr = set()       # JR lines relaxed to JP
        while True:
            try:
                return self._assemble(lines)
            except RelaxJR as r:
                self.long_jr.add(r.line)

    def _assemble(self, lines):
        prev_sizes = None
        for p in range(6):
            self.final = False
            self.unresolved = False
            sizes = self.pass_(lines)
            if sizes == prev_sizes and not self.unresolved:
                break
            prev_sizes = sizes
        self.final = True
        self.pass_(lines)
        return bytes(self.out)

    def pass_(self, lines):
        self.pc = 0 if self.reloc else 0x100
        self.out = bytearray()
        self.relocs = []
        self.defined = set()
        self.bss = False
        sizes = []
        for n, raw in enumerate(lines, 1):
            self.cur_line = n
            try:
                before = self.pc
                self.line(raw)
                sizes.append(self.pc - before)
            except RelaxJR:
                raise
            except AsmError as e:
                if self.final:
                    raise AsmError('line %d: %s\n  %s' % (n, e, raw.strip()))
                sizes.append(-1)
            except (ValueError, KeyError, IndexError) as e:
                raise AsmError('line %d: %s\n  %s' % (n, e, raw.strip()))
        return sizes

    def define(self, name, value):
        name = name.upper()
        if name in self.defined:
            raise AsmError('symbol %s defined twice' % name)
        self.defined.add(name)
        self.symbols[name] = value

    def line(self, raw):
        line = strip_comment(raw).rstrip()
        if not line.strip():
            return
        label = None
        m = re.match(r'^([A-Za-z_.?@][A-Za-z0-9_.?@$]*):\s*(.*)$', line.strip())
        if m:
            label, rest = m.group(1), m.group(2)
        elif not line[0].isspace():
            parts = line.split(None, 1)
            label, rest = parts[0], (parts[1] if len(parts) > 1 else '')
        else:
            rest = line.strip()
        parts = rest.split(None, 1)
        mnem = parts[0].upper() if parts else ''
        args = parts[1] if len(parts) > 1 else ''
        if mnem == 'EQU':
            self.define(label, self.ev(args))
            return
        if label:
            self.define(label, self.here(0))
        if not mnem:
            return
        ops = split_operands(args)
        self.instr(mnem, ops)

    def data_bytes(self, ops):
        for op in ops:
            if len(op) >= 2 and op[0] in '"\'' and op[-1] == op[0]:
                for ch in op[1:-1]:
                    self.emit(ord(ch))
            else:
                self.emit(self.ev(op))

    def instr(self, mn, ops):
        U = [o.upper().replace(' ', '') if not o.startswith(("'", '"')) else o for o in ops]
        n = len(ops)
        if mn == 'ORG':
            if self.reloc:
                raise AsmError('ORG in a relocatable segment')
            self.pc = self.ev(ops[0])
            return
        if mn == 'END':
            return
        if mn in ('DB', 'DEFB', 'DEFM'):
            return self.data_bytes(ops)
        if mn in ('DW', 'DEFW'):
            for o in ops:
                self.emit_w(self.ev(o))
            return
        if mn == 'BSS':
            self.bss = True
            return
        if mn in ('DS', 'DEFS') and self.bss:
            self.pc += self.ev(ops[0])
            return
        if self.bss:
            raise AsmError('only DS is allowed after BSS')
        if mn in ('DS', 'DEFS'):
            cnt = self.ev(ops[0])
            if isinstance(cnt, Rel):
                raise AsmError('relocatable DS count')
            fill = self.ev(ops[1]) if n > 1 else 0
            self.emit(*([fill] * cnt))
            return
        if mn in SIMPLE and n == 0:
            return self.emit(*SIMPLE[mn])
        a = U[0] if n > 0 else None
        b = U[1] if n > 1 else None

        def r8(o):
            return R8.get(o)

        if mn == 'LD':
            return self.ld(a, b, ops)
        if mn in ('PUSH', 'POP'):
            base = 0xC5 if mn == 'PUSH' else 0xC1
            if a in ('IX', 'IY'):
                return self.emit(0xDD if a == 'IX' else 0xFD, base + 0x20)
            return self.emit(base + RP2[a] * 16)
        if mn == 'EX':
            if a == 'DE' and b == 'HL':
                return self.emit(0xEB)
            if a == 'AF' and b == "AF'":
                return self.emit(0x08)
            if a == '(SP)':
                if b == 'HL':
                    return self.emit(0xE3)
                return self.emit(0xDD if b == 'IX' else 0xFD, 0xE3)
        if mn in ALU:
            if n == 2 and a in ('HL', 'IX', 'IY'):
                if a in ('IX', 'IY'):
                    pre = 0xDD if a == 'IX' else 0xFD
                    rr = b if b != a else 'HL'
                    return self.emit(pre, 0x09 + RP[rr] * 16)
                if mn == 'ADD':
                    return self.emit(0x09 + RP[b] * 16)
                if mn == 'ADC':
                    return self.emit(0xED, 0x4A + RP[b] * 16)
                if mn == 'SBC':
                    return self.emit(0xED, 0x42 + RP[b] * 16)
            src, srco = (b, ops[1]) if n == 2 else (a, ops[0])
            k = ALU[mn]
            ix = self.idx(src)
            if ix:
                return self.emit(ix[0], 0x86 + k * 8, ix[1])
            if r8(src) is not None:
                return self.emit(0x80 + k * 8 + r8(src))
            return self.emit(0xC6 + k * 8, self.ev(srco))
        if mn in ('INC', 'DEC'):
            ix = self.idx(a)
            if ix:
                return self.emit(ix[0], (0x34 if mn == 'INC' else 0x35), ix[1])
            if r8(a) is not None:
                return self.emit((0x04 if mn == 'INC' else 0x05) + r8(a) * 8)
            if a in ('IX', 'IY'):
                return self.emit(0xDD if a == 'IX' else 0xFD, 0x23 if mn == 'INC' else 0x2B)
            return self.emit((0x03 if mn == 'INC' else 0x0B) + RP[a] * 16)
        if mn == 'JP':
            if n == 1:
                if a == '(HL)':
                    return self.emit(0xE9)
                if a in ('(IX)', '(IY)'):
                    return self.emit(0xDD if a == '(IX)' else 0xFD, 0xE9)
                self.emit(0xC3)
                return self.emit_w(self.ev(ops[0]))
            self.emit(0xC2 + CC[a] * 8)
            return self.emit_w(self.ev(ops[1]))
        if mn in ('JR', 'DJNZ'):
            if mn == 'DJNZ':
                opc, tgt = 0x10, ops[0]
            elif n == 1:
                opc, tgt = 0x18, ops[0]
            else:
                opc, tgt = {'NZ': 0x20, 'Z': 0x28, 'NC': 0x30, 'C': 0x38}[a], ops[1]
            if mn == 'JR' and self.cur_line in self.long_jr:
                self.emit(0xC3 if n == 1 else {'NZ': 0xC2, 'Z': 0xCA, 'NC': 0xD2, 'C': 0xDA}[a])
                return self.emit_w(self.ev(tgt))
            d = self.ev(tgt) - self.here(2)
            if isinstance(d, Rel):
                raise AsmError('relative jump to an external symbol')
            if self.final and not -128 <= d <= 127:
                if mn == 'JR':
                    raise RelaxJR(self.cur_line)
                raise AsmError('relative jump out of range')
            return self.emit(opc, d & 0xFF)
        if mn == 'CALL':
            if n == 1:
                self.emit(0xCD)
                return self.emit_w(self.ev(ops[0]))
            self.emit(0xC4 + CC[a] * 8)
            return self.emit_w(self.ev(ops[1]))
        if mn == 'RET':
            if n == 0:
                return self.emit(0xC9)
            return self.emit(0xC0 + CC[a] * 8)
        if mn == 'RST':
            return self.emit(0xC7 + self.ev(ops[0]))
        if mn in ROT or mn in ('BIT', 'SET', 'RES'):
            if mn in ROT:
                base, tgt = ROT[mn] * 8, a
            else:
                bit = self.ev(ops[0])
                base = {'BIT': 0x40, 'RES': 0x80, 'SET': 0xC0}[mn] + bit * 8
                tgt = b
            ix = self.idx(tgt)
            if ix:
                return self.emit(ix[0], 0xCB, ix[1], base + 6)
            return self.emit(0xCB, base + R8[tgt])
        if mn == 'IM':
            return self.emit(0xED, {0: 0x46, 1: 0x56, 2: 0x5E}[self.ev(ops[0])])
        if mn == 'IN':
            if b == '(C)':
                return self.emit(0xED, 0x40 + R8[a] * 8)
            return self.emit(0xDB, self.ev(ops[1][1:-1]))
        if mn == 'OUT':
            if a == '(C)':
                return self.emit(0xED, 0x41 + R8[b] * 8)
            return self.emit(0xD3, self.ev(ops[0][1:-1]))
        raise AsmError('unknown instruction %s %s' % (mn, ','.join(ops)))

    def ld(self, a, b, ops):
        ia, ib = self.idx(a), self.idx(b)
        if ia:   # LD (IX+d),r / n
            if b in R8 and b != '(HL)':
                return self.emit(ia[0], 0x70 + R8[b], ia[1])
            return self.emit(ia[0], 0x36, ia[1], self.ev(ops[1]))
        if ib:
            return self.emit(ib[0], 0x46 + R8[a] * 8, ib[1])
        if a in R8 and b in R8:
            if a == '(HL)' and b == '(HL)':
                raise AsmError('bad LD')
            return self.emit(0x40 + R8[a] * 8 + R8[b])
        if a == 'A':
            if b == '(BC)': return self.emit(0x0A)
            if b == '(DE)': return self.emit(0x1A)
            if b == 'I': return self.emit(0xED, 0x57)
            if b == 'R': return self.emit(0xED, 0x5F)
            if self.is_mem(b):
                self.emit(0x3A)
                return self.emit_w(self.ev(ops[1].strip()[1:-1]))
        if b == 'A':
            if a == '(BC)': return self.emit(0x02)
            if a == '(DE)': return self.emit(0x12)
            if a == 'I': return self.emit(0xED, 0x47)
            if a == 'R': return self.emit(0xED, 0x4F)
            if self.is_mem(a):
                self.emit(0x32)
                return self.emit_w(self.ev(ops[0].strip()[1:-1]))
        if a in R8:
            return self.emit(0x06 + R8[a] * 8, self.ev(ops[1]))
        if a == 'SP' and b in ('HL', 'IX', 'IY'):
            if b == 'HL':
                return self.emit(0xF9)
            return self.emit(0xDD if b == 'IX' else 0xFD, 0xF9)
        if a in RP or a in ('IX', 'IY'):
            pre = []
            if a in ('IX', 'IY'):
                pre, reg = [0xDD if a == 'IX' else 0xFD], 'HL'
            else:
                reg = a
            if self.is_mem(b):
                addr = self.ev(ops[1].strip()[1:-1])
                if reg == 'HL':
                    self.emit(*(pre + [0x2A]))
                else:
                    self.emit(0xED, 0x4B + RP[reg] * 16)
                return self.emit_w(addr)
            self.emit(*(pre + [0x01 + RP[reg] * 16]))
            return self.emit_w(self.ev(ops[1]))
        if self.is_mem(a) and (b in RP or b in ('IX', 'IY')):
            addr = self.ev(ops[0].strip()[1:-1])
            if b in ('IX', 'IY'):
                self.emit(0xDD if b == 'IX' else 0xFD, 0x22)
            elif b == 'HL':
                self.emit(0x22)
            else:
                self.emit(0xED, 0x43 + RP[b] * 16)
            return self.emit_w(addr)
        raise AsmError('bad LD %s,%s' % (a, b))


def expand_includes(text, basedir, depth=0):
    """Replace 'INCLUDE file' lines (path relative to basedir) by the file."""
    out = []
    for line in text.split('\n'):
        code = strip_comment(line).split()
        if len(code) == 2 and code[0].upper() == 'INCLUDE':
            if depth > 8:
                raise AsmError('INCLUDE nested too deeply')
            path = os.path.join(basedir, code[1].strip('"\''))
            with open(path) as f:
                out.append(expand_includes(f.read(), os.path.dirname(path), depth + 1))
        else:
            out.append(line)
    return '\n'.join(out)


def assemble(text):
    a = Assembler()
    code = a.assemble(text)
    return code, a.symbols


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1]) as f:
        src = expand_includes(f.read(), os.path.dirname(os.path.abspath(sys.argv[1])))
    try:
        code, syms = assemble(src)
    except AsmError as e:
        sys.stderr.write('error: %s\n' % e)
        sys.exit(1)
    open(sys.argv[2], 'wb').write(code)
    if '-sym' in sys.argv:
        with open(sys.argv[sys.argv.index('-sym') + 1], 'w') as f:
            for k, v in sorted(syms.items(), key=lambda kv: kv[1]):
                f.write('%04X %s\n' % (v & 0xFFFF, k))
    print('%d bytes' % len(code))


if __name__ == '__main__':
    main()
