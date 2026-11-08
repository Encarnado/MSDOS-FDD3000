"""Z80 instruction decoder (documented + the common undocumented forms).

decode(mem, addr) -> (length, mnemonic, operands, info)
  mem      : callable a -> byte (or a bytes-like with .__getitem__ and base)
  mnemonic : lower-case z80asm spelling ('ld', 'jp', ...)
  operands : list of operand strings; numeric fields are rendered with
             placeholders so a caller can symbolise them:
               {n}   8-bit immediate           {nn}  16-bit immediate
               {(nn)} 16-bit memory address    {e}   relative target (abs)
               {d}   signed IX/IY displacement {p}   port number
  info     : dict with 'n', 'nn', 'e', 'd', 'p' values present, plus
             'flow': None | 'jump' | 'call' | 'ret' | 'stop' (no fall-through),
             'cond': True if conditional, 'target': branch target or None.

Written for the FDD3000-MSDOS disassembly corpus (DISASM/), checked by the
z80asm round-trip gate: every decoded line must reassemble to its bytes.
"""

R8 = ['b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a']
R16 = ['bc', 'de', 'hl', 'sp']
R16AF = ['bc', 'de', 'hl', 'af']
CC = ['nz', 'z', 'nc', 'c', 'po', 'pe', 'p', 'm']
ALU = ['add', 'adc', 'sub', 'sbc', 'and', 'xor', 'or', 'cp']
ROT = ['rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl']


def _s8(v):
    return v - 256 if v >= 128 else v


def decode(mem, addr):
    b = lambda i: mem((addr + i) & 0xFFFF)
    info = {'flow': None, 'cond': False, 'target': None}
    op = b(0)

    if op in (0xDD, 0xFD):
        return _decode_index(b, addr, 'ix' if op == 0xDD else 'iy', info)
    if op == 0xCB:
        o = b(1)
        x, y, z = o >> 6, (o >> 3) & 7, o & 7
        if x == 0:
            return 2, ROT[y], [R8[z]], info
        return 2, ['', 'bit', 'res', 'set'][x], [str(y), R8[z]], info
    if op == 0xED:
        return _decode_ed(b, addr, info)

    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    p, q = y >> 1, y & 1
    n = b(1)
    nn = b(1) | (b(2) << 8)

    if x == 1:
        if op == 0x76:
            info['flow'] = 'stop'
            return 1, 'halt', [], info
        return 1, 'ld', [R8[y], R8[z]], info
    if x == 2:
        return 1, ALU[y], _alu_ops(y, R8[z]), info

    if x == 0:
        if z == 0:
            if y == 0:
                return 1, 'nop', [], info
            if y == 1:
                return 1, 'ex', ['af', "af'"], info
            tgt = (addr + 2 + _s8(n)) & 0xFFFF
            info.update(e=tgt, target=tgt, flow='jump')
            if y == 2:
                info['cond'] = True
                return 2, 'djnz', ['{e}'], info
            if y == 3:
                info['flow'] = 'jump'
                return 2, 'jr', ['{e}'], info
            info['cond'] = True
            return 2, 'jr', [CC[y - 4], '{e}'], info
        if z == 1:
            if q == 0:
                info['nn'] = nn
                return 3, 'ld', [R16[p], '{nn}'], info
            return 1, 'add', ['hl', R16[p]], info
        if z == 2:
            if q == 0:
                if p == 0:
                    return 1, 'ld', ['(bc)', 'a'], info
                if p == 1:
                    return 1, 'ld', ['(de)', 'a'], info
                info['nn'] = nn
                if p == 2:
                    return 3, 'ld', ['{(nn)}', 'hl'], info
                return 3, 'ld', ['{(nn)}', 'a'], info
            if p == 0:
                return 1, 'ld', ['a', '(bc)'], info
            if p == 1:
                return 1, 'ld', ['a', '(de)'], info
            info['nn'] = nn
            if p == 2:
                return 3, 'ld', ['hl', '{(nn)}'], info
            return 3, 'ld', ['a', '{(nn)}'], info
        if z == 3:
            return 1, 'inc' if q == 0 else 'dec', [R16[p]], info
        if z == 4:
            return 1, 'inc', [R8[y]], info
        if z == 5:
            return 1, 'dec', [R8[y]], info
        if z == 6:
            info['n'] = n
            return 2, 'ld', [R8[y], '{n}'], info
        return 1, ['rlca', 'rrca', 'rla', 'rra', 'daa', 'cpl', 'scf', 'ccf'][y], [], info

    # x == 3
    if z == 0:
        info.update(flow='ret', cond=True)
        return 1, 'ret', [CC[y]], info
    if z == 1:
        if q == 0:
            return 1, 'pop', [R16AF[p]], info
        if p == 0:
            info['flow'] = 'ret'
            return 1, 'ret', [], info
        if p == 1:
            return 1, 'exx', [], info
        if p == 2:
            info['flow'] = 'stop'           # jp (hl): computed
            return 1, 'jp', ['(hl)'], info
        return 1, 'ld', ['sp', 'hl'], info
    if z == 2:
        info.update(nn=nn, target=nn, flow='jump', cond=True)
        return 3, 'jp', [CC[y], '{nn}'], info
    if z == 3:
        if y == 0:
            info.update(nn=nn, target=nn, flow='jump')
            return 3, 'jp', ['{nn}'], info
        if y == 2:
            info['p'] = n
            return 2, 'out', ['({p})', 'a'], info
        if y == 3:
            info['p'] = n
            return 2, 'in', ['a', '({p})'], info
        if y == 4:
            return 1, 'ex', ['(sp)', 'hl'], info
        if y == 5:
            return 1, 'ex', ['de', 'hl'], info
        if y == 6:
            return 1, 'di', [], info
        return 1, 'ei', [], info
    if z == 4:
        info.update(nn=nn, target=nn, flow='call', cond=True)
        return 3, 'call', [CC[y], '{nn}'], info
    if z == 5:
        if q == 0:
            return 1, 'push', [R16AF[p]], info
        info.update(nn=nn, target=nn, flow='call')
        return 3, 'call', ['{nn}'], info
    if z == 6:
        info['n'] = n
        return 2, ALU[y], _alu_ops(y, '{n}'), info
    info.update(flow='call', target=y * 8)
    return 1, 'rst', ['%02xh' % (y * 8) if y * 8 < 0xA0 else '0%02xh' % (y * 8)], info


def _alu_ops(y, src):
    # z80asm (Wijnen) spelling: add a,r / adc a,r / sbc a,r ; sub r / and r ...
    if y in (0, 1, 3):
        return ['a', src]
    return [src]


def _decode_ed(b, addr, info):
    o = b(1)
    x, y, z = o >> 6, (o >> 3) & 7, o & 7
    p, q = y >> 1, y & 1
    nn = b(2) | (b(3) << 8)
    if x == 1:
        if z == 0:
            return 2, 'in', [R8[y] if y != 6 else 'f', '(c)'], info
        if z == 1:
            return 2, 'out', ['(c)', R8[y] if y != 6 else '0'], info
        if z == 2:
            return 2, 'sbc' if q == 0 else 'adc', ['hl', R16[p]], info
        if z == 3:
            info['nn'] = nn
            if q == 0:
                return 4, 'ld', ['{(nn)}', R16[p]], info
            return 4, 'ld', [R16[p], '{(nn)}'], info
        if z == 4:
            return 2, 'neg', [], info
        if z == 5:
            info['flow'] = 'ret'
            return 2, 'reti' if y == 1 else 'retn', [], info
        if z == 6:
            return 2, 'im', [['0', '0', '1', '2'][y & 3]], info
        return 2, ['ld', 'ld', 'ld', 'ld', 'rrd', 'rld', 'nop', 'nop'][y], \
            [['i', 'a'], ['r', 'a'], ['a', 'i'], ['a', 'r'], [], [], [], []][y], info
    if x == 2 and z <= 3 and y >= 4:
        names = [['ldi', 'cpi', 'ini', 'outi'], ['ldd', 'cpd', 'ind', 'outd'],
                 ['ldir', 'cpir', 'inir', 'otir'], ['lddr', 'cpdr', 'indr', 'otdr']]
        return 2, names[y - 4][z], [], info
    return 2, 'defb', ['0edh', '0%02xh' % o], info      # invalid ED: data


def _decode_index(b, addr, ir, info):
    o = b(1)
    if o in (0xDD, 0xFD, 0xED):
        return 1, 'defb', ['0%02xh' % b(0)], info
    if o == 0xCB:
        d = _s8(b(2))
        o3 = b(3)
        x, y, z = o3 >> 6, (o3 >> 3) & 7, o3 & 7
        info['d'] = d
        m = '(%s{d})' % ir
        if z != 6:          # undocumented copy-to-register forms: emit as data
            return 4, 'defb', ['0%02xh' % b(0), '0cbh', '0%02xh' % b(2), '0%02xh' % o3], info
        if x == 0:
            return 4, ROT[y], [m], info
        return 4, ['', 'bit', 'res', 'set'][x], [str(y), m], info

    x, y, z = o >> 6, (o >> 3) & 7, o & 7
    p, q = y >> 1, y & 1
    n2 = b(2)
    nn = b(2) | (b(3) << 8)
    d = _s8(b(2))
    m = '(%s{d})' % ir
    rh = {4: ir + 'h', 5: ir + 'l'}

    def reg(r, allow_half=True):
        if r == 6:
            return None
        if r in rh and allow_half:
            return rh[r]
        return R8[r]

    if o == 0x21:
        info['nn'] = nn
        return 4, 'ld', [ir, '{nn}'], info
    if o == 0x22:
        info['nn'] = nn
        return 4, 'ld', ['{(nn)}', ir], info
    if o == 0x2A:
        info['nn'] = nn
        return 4, 'ld', [ir, '{(nn)}'], info
    if o in (0x09, 0x19, 0x29, 0x39):
        return 2, 'add', [ir, [  'bc', 'de', ir, 'sp'][p]], info
    if o == 0x23:
        return 2, 'inc', [ir], info
    if o == 0x2B:
        return 2, 'dec', [ir], info
    if o == 0x34:
        info['d'] = d
        return 3, 'inc', [m], info
    if o == 0x35:
        info['d'] = d
        return 3, 'dec', [m], info
    if o == 0x36:
        info['d'] = d
        info['n'] = b(3)
        return 4, 'ld', [m, '{n}'], info
    if o == 0xE1:
        return 2, 'pop', [ir], info
    if o == 0xE5:
        return 2, 'push', [ir], info
    if o == 0xE3:
        return 2, 'ex', ['(sp)', ir], info
    if o == 0xE9:
        info['flow'] = 'stop'
        return 2, 'jp', ['(%s)' % ir], info
    if o == 0xF9:
        return 2, 'ld', ['sp', ir], info
    if x == 1 and o != 0x76:
        if y == 6:
            info['d'] = d
            return 3, 'ld', [m, R8[z]], info
        if z == 6:
            info['d'] = d
            return 3, 'ld', [R8[y], m], info
        if y in (4, 5) or z in (4, 5):
            return 2, 'ld', [reg(y), reg(z)], info
    if x == 2:
        if z == 6:
            info['d'] = d
            return 3, ALU[y], _alu_ops(y, m), info
        if z in (4, 5):
            return 2, ALU[y], _alu_ops(y, rh[z]), info
    if x == 0 and z in (4, 5) and y in (4, 5):
        return 2, 'inc' if z == 4 else 'dec', [rh[y]], info
    if x == 0 and z == 6 and y in (4, 5):
        info['n'] = n2
        return 3, 'ld', [rh[y], '{n}'], info
    # prefix with no effect: emit the prefix byte as data
    return 1, 'defb', ['0%02xh' % b(0)], info
