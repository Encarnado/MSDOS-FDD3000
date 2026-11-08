"""Random single instructions on cpu86.py and the Z80 interpreter.

Each case: random registers, flags and prefixes, a random instruction
(opcode from the whole 8086 set, random ModR/M, displacement and
immediates), executed once on both. Registers, IP, flags and memory must
match (AF only for 8-bit and logic ops: see af_loose). Cases that touch memory above the 52 KB guest are skipped.

    python3 fuzz_z86.py [N] [--seed S] [--op XX] [--scan]

--scan: only REP SCASB / SCASW with CX up to 2000 (the interpreter passes
over REPNE SCASB with CPIR / CPDR).
--overlap: only REP MOVSW with DI = SI +- 1, either direction, ES = DS (a
word copy is not a byte copy there: MWCHK / MWSLOW, 2026-11-08).
"""
import random
import sys

import cpu86
import z86

AF = 0x10
LIMIT = 0xD000
CODE_SEG = 0x0C80                       # code at linear C800h
SKIP = {0x0F, 0xF1, 0xF4,                 # trap, undefined, HLT
        0x26, 0x2E, 0x36, 0x3E, 0xF0, 0xF2, 0xF3}   # prefixes: added by case()


class Out(Exception):
    pass


class CheckCPU(cpu86.CPU):
    """cpu86 that refuses to touch memory above the guest's 52 KB."""

    def _chk(self, seg, off):
        a = (seg << 4) + (off & 0xFFFF)
        if a >= LIMIT - 1:
            raise Out()

    def rb(self, seg, off):
        self._chk(seg, off)
        return super().rb(seg, off)

    def rw(self, seg, off):
        self._chk(seg, off)
        return super().rw(seg, off)

    def wb(self, seg, off, v):
        self._chk(seg, off)
        super().wb(seg, off, v)

    def ww(self, seg, off, v):
        self._chk(seg, off)
        super().ww(seg, off, v)


def overlap_case(rng):
    pre = [0xF3]
    if rng.random() < 0.3:
        pre.insert(0, rng.choice([0x26, 0x2E, 0x36, 0x3E]))
    regs = [rng.randrange(0x10000) for _ in range(8)]
    regs[4] = rng.randrange(0x100, 0x3000) & 0xFFFE         # SP
    regs[6] = rng.randrange(0x40, 0x2000)                   # SI
    regs[7] = (regs[6] + rng.choice([1, -1, 1, -1, 2, -2, 0])) & 0xFFFF   # DI
    regs[1] = rng.randrange(0, 40)                          # CX
    seg = rng.randrange(0x0400)
    segs = [seg, CODE_SEG, seg, seg]                        # ES = SS = DS
    flags = (rng.randrange(0x10000) & 0x0BD5 | 0xF002) | rng.choice([0, 0x400])
    return bytes(pre + [0xA5] + [0] * 6), regs, segs, flags


def case(rng, only=None, scan=False, overlap=False):
    if overlap:
        return overlap_case(rng)
    if scan:
        code, regs, segs, flags = case(rng, rng.choice([0xAE, 0xAE, 0xAE, 0xAF]))
        i = code.index(0xAE if 0xAE in code[:3] else 0xAF)
        code = code[:i].replace(b'\xf2', b'').replace(b'\xf3', b'') + bytes(
            [rng.choice([0xF2, 0xF2, 0xF3])]) + code[i:]
        regs[1] = rng.randrange(2000)
        return code, regs, segs, flags
    op = only if only is not None else rng.choice([o for o in range(256) if o not in SKIP])
    pre = []
    if rng.random() < 0.25:
        pre.append(rng.choice([0x26, 0x2E, 0x36, 0x3E]))
    if 0xA4 <= op <= 0xAF and rng.random() < 0.6:
        pre.insert(rng.randrange(len(pre) + 1), rng.choice([0xF2, 0xF3]))
    body = [rng.randrange(256) for _ in range(6)]
    if op in (0xFE,):
        body[0] = (body[0] & 0xC7) | rng.choice([0, 8])     # only INC / DEC r/m8
    # LES / LDS / CALL FAR / JMP FAR need a memory operand: a register one
    # is undefined on the 8086 (cpu86 reads offset 0)
    if op in (0xC4, 0xC5) or op == 0xFF and (body[0] >> 3) & 7 in (3, 5):
        body[0] &= 0xBF
    regs = [rng.randrange(0x10000) for _ in range(8)]
    for i in (3, 5, 6, 7):                                  # BX BP SI DI: mostly low
        if rng.random() < 0.7:
            regs[i] = rng.randrange(0x3000)
    regs[4] = rng.randrange(0x100, 0x3000) & 0xFFFE         # SP
    if rng.random() < 0.7:
        regs[1] = rng.randrange(0, 12)                      # CX: short REPs and shifts
    segs = [rng.randrange(0x0400) for _ in range(4)]
    segs[1] = CODE_SEG
    flags = rng.randrange(0x10000) & 0x0FD5 | 0xF002
    return bytes(pre + [op] + body), regs, segs, flags


def af_loose(code):
    """16-bit add / subtract / inc / dec: the Z80 sets AF from bit 11."""
    i = 0
    while code[i] in (0x26, 0x2E, 0x36, 0x3E, 0xF2, 0xF3):
        i += 1
    op, reg = code[i], (code[i + 1] >> 3) & 7
    if op < 0x40 and op & 7 in (1, 3, 5) and op >> 3 in (0, 2, 3, 5, 7):
        return True
    return (0x40 <= op < 0x50 or op in (0x81, 0x83) and reg in (0, 2, 3, 5, 7)
            or op == 0xF7 and reg == 3 or op == 0xFF and reg in (0, 1)
            or op in (0xA7, 0xAF))


def setup(c, mem, code, regs, segs, flags):
    c.mem[:LIMIT] = mem
    c.mem[CODE_SEG * 16:CODE_SEG * 16 + len(code)] = code
    for i in range(8):
        c.r[i] = regs[i]
    for i in (0, 2, 3, 1):
        c.s[i] = segs[i]
    c.ip = 0
    c.flags = flags


def main():
    args = sys.argv[1:]
    n = int(args[0]) if args and args[0].isdigit() else 20000
    seed = int(args[args.index('--seed') + 1]) if '--seed' in args else 1
    only = int(args[args.index('--op') + 1], 16) if '--op' in args else None
    rng = random.Random(seed)
    ref = CheckCPU()
    z = z86.Z86()
    mem = bytes(rng.randrange(256) for _ in range(LIMIT))
    # interrupt vectors point at an IRET-free area inside the guest
    done = skipped = fails = 0
    seen = set()
    for k in range(n):
        code, regs, segs, flags = case(rng, only, '--scan' in args, '--overlap' in args)
        setup(ref, mem, code, regs, segs, flags)
        try:
            ref.step()
        except Out:
            skipped += 1
            continue
        zz = z.z
        zz.pc, zz.sp, zz.xy[0] = z.NEXT, 0, z.NEXT
        setup(z, mem, code, regs, segs, flags)
        z.step()
        a = (list(ref.r), list(ref.s), ref.ip, ref.flags)
        b = (list(z.r), list(z.s), z.ip, z.flags)
        bad = None
        if a[:3] != b[:3]:
            bad = 'registers'
        elif (a[3] ^ b[3]) & ~(AF if af_loose(code) else 0):
            bad = 'flags %04X / %04X' % (a[3], b[3])
        elif ref.mem[:LIMIT] != z.mem[:LIMIT]:
            diff = [i for i in range(LIMIT) if ref.mem[i] != z.mem[i]]
            bad = 'memory ' + ' '.join('%04X:%02X/%02X' % (i, ref.mem[i], z.mem[i]) for i in diff[:6])
        done += 1
        seen.add(code[len(code) - 7])
        if bad:
            fails += 1
            if fails <= 15:
                print('case %d: %s  %s' % (k, code.hex(' '), bad))
                print('   in  regs %s segs %s flags %04X' % (
                    ' '.join('%04X' % v for v in regs), ' '.join('%04X' % v for v in segs), flags))
                print('   ref regs %s ip %04X fl %04X' % (' '.join('%04X' % v for v in a[0]), a[2], a[3]))
                print('   z80 regs %s ip %04X fl %04X' % (' '.join('%04X' % v for v in b[0]), b[2], b[3]))
    print('%d cases run, %d skipped (memory above the guest), %d opcodes, %d mismatches'
          % (done, skipped, len(seen), fails))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
