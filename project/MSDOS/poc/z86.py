"""The Z80 8086 interpreter (I86.ASM): build it and run it on a Z80 emulator.

    python3 z86.py                      assemble, print the size and layout
    python3 z86.py MSDOS.DSK [--keys K] run DOS on it (like fddos.py)

Z86 has the interface of cpu86.CPU (r, s, ip, flags, mem, step, cycles), so
fddos.Machine drives it unchanged: the BIOS traps stay in Python here (the
interpreter's TRAP routine is hooked). The Z80 is tmxcobol's cpmemu.Z80 and
T-states are counted with its timing tables.
"""
import functools
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tmxcobol'))
import z80asm  # noqa: E402
import cpmemu  # noqa: E402
from cpu86 import Halt  # noqa: E402

SRC = os.path.join(HERE, 'I86.ASM')
BIOS = os.path.join(HERE, 'BIOS.ASM')
BOOT = os.path.join(HERE, 'BOOT.ASM')
CPMZ80 = os.path.join(HERE, 'CPMZ80.ASM')
R16 = ['AX', 'CX', 'DX', 'BX', 'SP', 'BP', 'SI', 'DI']
R8 = ['AL', 'CL', 'DL', 'BL', 'AH', 'CH', 'DH', 'BH']
SEGS = ['ES', 'CS', 'SS', 'DS']
JCC = ['JO', 'JNO', 'JB', 'JNB', 'JZ', 'JNZ', 'JBE', 'JA',
       'JS', 'JNS', 'JP', 'JNP', 'JL', 'JGE', 'JLE', 'JG']


def op_table():
    """8086 opcode -> handler label (the same decoding as cpu86.py)."""
    t = ['O_BAD'] * 256
    for op in range(0x40):
        if op & 7 < 6:
            t[op] = 'O_ALU%d' % (op & 7)
    for i, s in enumerate(SEGS):
        t[0x06 + 8 * i] = 'O_PUSH_' + s
        t[0x26 + 8 * i] = 'O_SEG_' + s
    t[0x07], t[0x17], t[0x1F] = 'O_POP_ES', 'O_POP_SS', 'O_POP_DS'
    t[0x3C] = 'O_CMPAL'
    t[0x0F] = 'O_TRAP'
    t[0x27], t[0x2F], t[0x37], t[0x3F] = 'O_DAA', 'O_DAS', 'O_AAA', 'O_AAS'
    for i, r in enumerate(R16):
        t[0x40 + i] = 'O_INC_' + r
        t[0x48 + i] = 'O_DEC_' + r
        t[0x50 + i] = 'O_PUSH_' + r
        t[0x58 + i] = 'O_POP_' + r
        t[0xB8 + i] = 'O_MOVI_' + r
        t[0xB0 + i] = 'O_MOVI_' + R8[i]
    for i, j in enumerate(JCC):
        t[0x60 + i] = t[0x70 + i] = 'O_' + j
    t[0x80:0x84] = ['O_GRP80', 'O_GRP81', 'O_GRP80', 'O_GRP83']
    t[0x84:0x90] = ['O_TEST84', 'O_TEST85', 'O_XCHG86', 'O_XCHG87',
                    'O_MOV88', 'O_MOV89', 'O_MOV8A', 'O_MOV8B',
                    'O_MOV8C', 'O_LEA', 'O_MOV8E', 'O_POP8F']
    t[0x90] = 'O_NOP'
    for i in range(1, 8):
        t[0x90 + i] = 'O_XCHGA'
    t[0x98:0xA0] = ['O_CBW', 'O_CWD', 'O_CALLF', 'O_NOP',
                    'O_PUSHF', 'O_POPF', 'O_SAHF', 'O_LAHF']
    t[0xA0:0xB0] = ['O_MOVA0', 'O_MOVA1', 'O_MOVA2', 'O_MOVA3',
                    'O_MOVSB', 'O_MOVSW', 'O_CMPSB', 'O_CMPSW',
                    'O_TESTA8', 'O_TESTA9', 'O_STOSB', 'O_STOSW',
                    'O_LODSB', 'O_LODSW', 'O_SCASB', 'O_SCASW']
    t[0xC0:0xD0] = ['O_RETN', 'O_RET', 'O_RETN', 'O_RET', 'O_LES', 'O_LDS',
                    'O_MOVC6', 'O_MOVC7', 'O_RETFN', 'O_RETF', 'O_RETFN', 'O_RETF',
                    'O_INT3', 'O_INTN', 'O_INTO', 'O_IRET']
    t[0xD0:0xD8] = ['O_SHD0', 'O_SHD1', 'O_SHD2', 'O_SHD3',
                    'O_AAM', 'O_AAD', 'O_SALC', 'O_XLAT']
    for op in range(0xD8, 0xE0):
        t[op] = 'O_ESC'
    t[0xE0:0xF0] = ['O_LOOPNZ', 'O_LOOPZ', 'O_LOOP', 'O_JCXZ',
                    'O_INB', 'O_INW', 'O_OUTI', 'O_OUTI',
                    'O_CALLN', 'O_JMPN', 'O_JMPF', 'O_JREL8',
                    'O_INDXB', 'O_INDXW', 'O_NOP', 'O_NOP']
    t[0xF0:0x100] = ['O_LOCK', 'O_BAD', 'O_REP', 'O_REP', 'O_HLT', 'O_CMC',
                     'O_GRP3B', 'O_GRP3W', 'O_CLC', 'O_STC', 'O_CLI', 'O_STI',
                     'O_CLD', 'O_STD', 'O_GRP4', 'O_GRP5']
    return t


def ea_table():
    """ModR/M 00-BF -> memory operand routine EA<mod><rm>."""
    return ['EA%d%d' % (m >> 6, m & 7) for m in range(0xC0)]


def table_text(lo, hi, labels, slack=None):
    """A split jump table: 256 low bytes, then 256 high bytes, each part on
    its own page.  A part with fewer than 256 entries ends in free bytes; a
    ;@SLACK block named after the part (EALO, EAHI) is assembled there, and
    the rest is zero-filled to the page end (<part>END marks the slack's
    end; _build asserts it stays inside the page)."""
    slack = slack or {}
    out = ['        DS (($+255)&0FF00h)-$', lo + ':']
    for part, fmt in ((lo, '%s&0FFh'), (hi, '%s>>8')):
        if part == hi:
            out.append(hi + ':')
        vals = [fmt % l for l in labels]
        for i in range(0, len(vals), 8):
            out.append('        DB ' + ', '.join(vals[i:i + 8]))
        if len(vals) < 256:
            out += slack.get(part, [])
            out += [part + 'END:', '        DS %s+256-$' % part]
    return out


def preprocess(text):
    """;@FOR V a b c ... ;@END repeats a block with {V} replaced;
    ;@TABLE LO HI ops|ea inserts a split 256-entry jump table;
    ;@SLACK NAME ... ;@END blocks are lifted out and assembled in the free
    end of table page NAME (EALO, EAHI) or at a ;@SLACKAT NAME marker."""
    lines = text.split('\n')
    # ;@SLACK PART ... ;@END: lift the block out; it is assembled in the free
    # end of the table page PART (see table_text)
    slack, kept, i = {}, [], 0
    while i < len(lines):
        m = re.match(r'\s*;@SLACK\s+(\w+)', lines[i])
        if m:
            j = i + 1
            while not re.match(r'\s*;@END', lines[j]):
                j += 1
            slack.setdefault(m.group(1), []).extend(lines[i + 1:j])
            i = j + 1
            continue
        kept.append(lines[i])
        i += 1
    out, lines, i = [], kept, 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'\s*;@FOR\s+(\w+)\s+(.*)', line)
        if m:
            var, vals = m.group(1), m.group(2).split(';')[0].split()
            j = i + 1
            while not re.match(r'\s*;@END', lines[j]):
                j += 1
            for v in vals:
                out += [l.replace('{%s}' % var, v) for l in lines[i + 1:j]]
            i = j + 1
            continue
        m = re.match(r'\s*;@SLACKAT\s+(\w+)', line)
        if m:                           # a free page end marked in the source
            out += slack.get(m.group(1), [])
            i += 1
            continue
        m = re.match(r'\s*;@TABLE\s+(\w+)\s+(\w+)\s+(\w+)', line)
        if m:
            labels = op_table() if m.group(3) == 'ops' else ea_table()
            out += table_text(m.group(1), m.group(2), labels, slack)
        else:
            out.append(line)
        i += 1
    return '\n'.join(out)


def build(bios=False):
    """-> (image loaded at D000h, symbols). bios: with the Z80 BIOS
    (BIOS.ASM); otherwise TRAP is a RET for Python to hook."""
    code, syms = _build(bios)
    if bios:
        code = code[:syms['BIOSEND'] - 0xD000]
    return code, syms


@functools.lru_cache(None)
def _build(bios):
    """I86.ASM, then BIOS.ASM and CPMZ80.ASM (which follows BIOSEND in the
    output, but is assembled for ENDBIOS: over COLD)."""
    if bios:
        tail = open(BIOS).read().replace('\n        END\n', '\n') + open(CPMZ80).read()
    else:
        tail = 'TRAP:   RET\nCOLD:   HALT\n        END\n'
    a = z80asm.Assembler()
    code = bytes(a.assemble(preprocess(open(SRC).read() + tail)))
    syms = {k: v for k, v in a.symbols.items() if isinstance(v, int)}
    assert syms['REGS'] == 0xD000 and syms['BOOTJP'] == 0xD0FD
    assert syms['WCORE'] == syms['BCORE'] + 0x100, 'the end of the BCORE page overflows'
    if bios:
        assert syms['SKEW'] == syms['SKEWAT'], 'BIOS code runs past SKEWAT (F0F8h)'
    assert syms['BOOTJP'] == 0xD0FD, 'the REGS page slack overflows into BOOTJP'
    for part in ('EALO', 'EAHI'):
        assert syms[part + 'END'] <= syms[part] + 0x100, 'the ;@SLACK block overflows ' + part
    if bios:
        assert syms['TTEND'] - syms['TTAB'] == 2 * 0x1E, 'TRAP checks CP 1Eh'
        assert len(code) == syms['BIOSEND'] - 0xD000 + syms['CPMEND'] - syms['ENDBIOS']
    return code, syms


def cpmz80():
    """-> CPM.COM's Z80 part, as BIOS trap 1Ch takes it: length, the
    addresses of CPMSYM, the code (for ENDBIOS)."""
    code, syms = _build(True)
    z = code[syms['BIOSEND'] - 0xD000:]
    names = ('NEXT', 'JPHL', 'PEEKEY', 'GETKEY', 'CONOUT', 'DCSP', 'ENDBIOS')
    assert syms['CPMSYE'] - syms['CPMSYM'] == 2 * len(names)
    assert syms['BUFEND'] <= 0xFF00, 'CPMZ80 runs into the Z80 stack'
    hdr = len(z).to_bytes(2, 'little') + b''.join(syms[n].to_bytes(2, 'little') for n in names)
    return hdr + z


@functools.lru_cache(None)
def bootcode():
    """-> (boot sector, Z86.SYS) for a disk: BOOT.ASM goes in logical
    sector 0; Z86.SYS, the interpreter with the BIOS, is the first file
    (see mkfat), which the boot sector reads to D000h."""
    image, syms = build(bios=True)
    assert 0xD000 + len(image) <= 0xFF00, 'Z86.SYS too big for the boot sector'
    a = z80asm.Assembler()
    ipl = a.assemble(open(BOOT).read())
    assert len(ipl) <= 256, 'boot sector: %d bytes' % len(ipl)
    return bytes(ipl), bytes(image)


class RegView:
    """r[i] / s[i] backed by Z80 memory words at base + 2i."""

    def __init__(self, m, base, on_set=None):
        self.m, self.base, self.on_set = m, base, on_set

    def __getitem__(self, i):
        a = self.base + 2 * i
        return self.m[a] | self.m[a + 1] << 8

    def __setitem__(self, i, v):
        a = self.base + 2 * i
        self.m[a], self.m[a + 1] = v & 0xFF, (v >> 8) & 0xFF
        if self.on_set:
            self.on_set(i, v & 0xFFFF)

    def __len__(self):
        return 8 if self.on_set is None else 4

    def __iter__(self):
        return (self[i] for i in range(len(self)))


class Z86:
    """The interpreter on a Z80, seen as an 8086 (cpu86.CPU's interface)."""

    def __init__(self, image=None, syms=None, count_t=False):
        if image is None:
            image, syms = build()
        self.syms = S = syms
        self.z = cpmemu.Z80()
        self.m = self.mem = self.z.m
        self.m[0xD000:0xD000 + len(image)] = image
        self.NEXT, self.TRAPA, self.HALTA = S['NEXT'], S['TRAP'], S['HALTED']
        self.BADA = S['BADSTOP']
        self.R, self.SB = S['R_AX'], S['B_ES']
        self.r = RegView(self.m, S['R_AX'])
        self.s = RegView(self.m, S['R_ES'], self._seg_set)
        self.trap = lambda n: (_ for _ in ()).throw(Halt('trap %02X' % n))
        self.cycles = 0
        self.tstates = 0
        self.count_t = count_t
        self.halted = False
        self.profile = None             # {Z80 pc: T-states} when a dict
        z = self.z
        z.sp = 0
        z.xy[0] = self.NEXT             # IX
        z.pc = self.NEXT
        self.flags = 0xF002
        self._ww(S['STEP1'], 1)
        self._ww(S['STEP2'], 2)

    # ---- memory words ----
    def _rw(self, a):
        return self.m[a] | self.m[a + 1] << 8

    def _ww(self, a, v):
        self.m[a], self.m[a + 1] = v & 0xFF, (v >> 8) & 0xFF

    # ---- segments: keep the bases and BC in step ----
    def _seg_set(self, i, v):
        S = self.syms
        if i == 1:                      # CS: keep IP
            ip = self.ip
            self._ww(self.SB + 2, (v << 4) & 0xFFFF)
            self.ip = ip
            return
        self._ww(self.SB + 2 * i, (v << 4) & 0xFFFF)
        if i == 3:
            self._ww(S['EADS'], (v << 4) & 0xFFFF)
        if i == 2:
            self._ww(S['EASS'], (v << 4) & 0xFFFF)

    @property
    def ip(self):
        z = self.z
        return (((z.r[0] << 8) | z.r[1]) - self._rw(self.SB + 2)) & 0xFFFF

    @ip.setter
    def ip(self, v):
        bc = (self._rw(self.SB + 2) + v) & 0xFFFF
        self.z.r[0], self.z.r[1] = bc >> 8, bc & 0xFF

    def setr8(self, i, v):
        a = self.R + (i & 3) * 2 + (i >> 2)
        self.m[a] = v & 0xFF

    def getr8(self, i):
        return self.m[self.R + (i & 3) * 2 + (i >> 2)]

    # ---- flags: F' (alt[6]) and A' (alt[7]), FLAGHI ----
    @property
    def flags(self):
        f, a = self.z.alt[6], self.z.alt[7]
        pf = 1 if bin(a).count('1') % 2 == 0 else 0
        hi = self.m[self.syms['FLAGHI']]
        return (0xF002 | (f & 0xD1) | pf << 2 | hi << 8 | ((f >> 2) & 1) << 11)

    @flags.setter
    def flags(self, v):
        f = (v & 0xD1) | ((v >> 11) & 1) << 2
        self.z.alt[6] = f
        self.z.alt[7] = 0 if v & 4 else 1
        self.m[self.syms['FLAGHI']] = (v >> 8) & 7
        df = (v >> 10) & 1
        self._ww(self.syms['STEP1'], 0xFFFF if df else 1)
        self._ww(self.syms['STEP2'], 0xFFFE if df else 2)

    def _flag(bit):
        return property(lambda s: (s.z.alt[6] >> bit) & 1,
                        lambda s, v: s.z.alt.__setitem__(6, (s.z.alt[6] & ~(1 << bit)) | (bool(v) << bit)))
    cf, zf, sf, of = _flag(0), _flag(6), _flag(7), _flag(2)
    del _flag

    # ---- running ----
    def step(self):
        """One 8086 instruction: run the Z80 until it is back at NEXT."""
        self.cycles += 1
        z, m = self.z, self.m
        ops = z.ops
        nxt, trap, halt, bad = self.NEXT, self.TRAPA, self.HALTA, self.BADA
        count = self.count_t
        tst = cpmemu._tstates
        first = True
        while True:
            pc = z.pc
            if pc == nxt and not first:
                return
            first = False
            if pc == trap:
                try:
                    self.trap(z.r[7])
                except Exception:
                    # WaitInput: the trap rewound IP; abandon the handler
                    z.sp = (z.sp + 2) & 0xFFFF
                    z.pc = nxt
                    raise
            elif pc == halt:
                self.halted = True
                return
            elif pc == bad:
                raise Halt('bad 8086 opcode %02X at %04X:%04X' % (
                    m[(z.r[0] << 8 | z.r[1])], self.s[1], self.ip))
            op = m[pc]
            z.pc = (pc + 1) & 0xFFFF
            if count:
                if op == 0xED and m[(pc + 1) & 0xFFFF] >= 0xB0 and m[(pc + 1) & 0xFFFF] & 2 == 0:
                    n0 = (z.r[0] << 8) | z.r[1]
                    ops[op]()
                    k = ((n0 - ((z.r[0] << 8) | z.r[1])) & 0xFFFF) or 0x10000
                    t = 21 * k - 5
                else:
                    sp0 = z.sp
                    ops[op]()
                    t = tst(m, pc, op, z.pc, z, sp0)
                self.tstates += t
                if self.profile is not None:
                    self.profile[pc] = self.profile.get(pc, 0) + t
            else:
                ops[op]()

    def run(self, n=None):
        k = 0
        while not self.halted and (n is None or k < n):
            self.step()
            k += 1


def machine(disks, count_t=False):
    """fddos.Machine with the Z80 interpreter as its CPU."""
    import fddos
    m = fddos.Machine(disks)
    m.cpu = Z86(count_t=count_t)
    m.cpu.trap = m.trap
    return m


def main():
    image, syms = build()
    if len(sys.argv) < 2:
        end = syms['ENDCODE']
        print('I86: D000h-%04Xh, %d bytes (%d free below FF00h for the stack)'
              % (end - 1, end - 0xD000, 0xFF00 - end))
        for k in ('OPLO', 'EALO', 'BCORE', 'WCORE', 'SHPG', 'START', 'NEXT', 'TRAP'):
            print('  %-6s %04Xh' % (k, syms[k]))
        return
    import argparse
    import fddos
    sys.path.insert(0, os.path.join(HERE, '..', '..', 'cpm80ds'))
    import fdd
    ap = argparse.ArgumentParser()
    ap.add_argument('disk')
    ap.add_argument('--keys')
    a = ap.parse_args()
    m = machine([fdd.Disk.load(a.disk)], count_t=True)
    m.boot()
    if a.keys is None:
        fddos.interactive(m)
    else:
        m.run()
        m.type(a.keys.encode().decode('unicode_escape'))
        print(m.screen())
        c = m.cpu
        print('[%d 8086 instructions, %d T-states]' % (c.cycles, c.tstates), file=sys.stderr)


if __name__ == '__main__':
    main()
