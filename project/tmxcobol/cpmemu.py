#!/usr/bin/env python3
"""cpmemu.py - self-contained Z80 + CP/M 2.2 emulator (Python 3.9, stdlib only).

Modelled on the Timex FDD3000 CP/M 2.2 (CBIOS A1.1) memory map:

    0000h  JP F603h          (warm boot vector -> BIOS WBOOT)
    0003h  IOBYTE
    0004h  current drive/user
    0005h  JP E806h          (BDOS entry; (0006h) = E806h = top of TPA)
    005Ch  default FCB 1, 006Ch default FCB 2, 0080h command tail / DMA
    0100h  TPA (program load address)
    E000h  CCP
    E806h  BDOS entry  (trapped in Python)
    F600h  CBIOS jump table, 17 entries (trapped in Python)

Execution reaching E806h is emulated in Python as a BDOS call followed by a
RET; execution reaching a BIOS jump-table entry is emulated likewise.  A jump
to 0000h, BIOS BOOT/WBOOT or BDOS function 0 terminates the run.

Library use:

    from cpmemu import CPM
    cpm = CPM(directory='work', stdin_lines=['42', 'HELLO'])
    res = cpm.run_com('PROG.COM', 'FILE.DAT')
    print(res.console, res.printer, res.exit_reason, res.instructions)

Command line:

    python3 cpmemu.py [--dir D] [--no-echo] [--trace] [--trace-instr]
                      [--max N] [--printer FILE] [--stats] PROG.COM [args...]
"""

import os
import sys
import time

__all__ = ['Z80', 'Z80Error', 'CPM', 'RunResult', 'EmulatorError']

# ---------------------------------------------------------------------------
# Flag tables
# ---------------------------------------------------------------------------
FC, FN, FPV, F3, FH, F5, FZ, FS = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

SZ = [(v & 0x80) | (FZ if v == 0 else 0) for v in range(256)]
PAR = [0 if bin(v).count('1') & 1 else FPV for v in range(256)]
SZP = [SZ[v] | PAR[v] for v in range(256)]

# condition codes NZ Z NC C PO PE P M -> (mask, want_set)
CC = [(FZ, 0), (FZ, 1), (FC, 0), (FC, 1), (FPV, 0), (FPV, 1), (FS, 0), (FS, 1)]


class Z80Error(Exception):
    """Raised by the CPU for HALT / unknown opcodes."""


class Z80(object):
    """Z80 CPU.  Registers: r = [B, C, D, E, H, L, F, A] (index 6 holds F,
    which is free because encoding 6 means (HL))."""

    def __init__(self, mem=None):
        self.m = mem if mem is not None else bytearray(65536)
        self.r = [0] * 8
        self.alt = [0] * 8          # B' C' D' E' H' L' F' A'
        self.xy = [0xFFFF, 0xFFFF]  # IX, IY
        self.pc = 0
        self.sp = 0xFFFF
        self.i = 0
        self.rreg = 0
        self.iff1 = 0
        self.iff2 = 0
        self.im = 0
        self.port_in = lambda port: 0xFF
        self.port_out = lambda port, val: None
        self._build()

    # ---- convenience register properties (for tests / dumps) -------------
    def _p8(i):
        return property(lambda s: s.r[i],
                        lambda s, v: s.r.__setitem__(i, v & 0xFF))

    def _p16(hi, lo):
        def g(s):
            return (s.r[hi] << 8) | s.r[lo]

        def st(s, v):
            s.r[hi] = (v >> 8) & 0xFF
            s.r[lo] = v & 0xFF
        return property(g, st)

    B, C, D, E, H, L, F, A = (_p8(0), _p8(1), _p8(2), _p8(3), _p8(4), _p8(5),
                              _p8(6), _p8(7))
    BC, DE, HL, AF = _p16(0, 1), _p16(2, 3), _p16(4, 5), _p16(7, 6)
    IX = property(lambda s: s.xy[0], lambda s, v: s.xy.__setitem__(0, v & 0xFFFF))
    IY = property(lambda s: s.xy[1], lambda s, v: s.xy.__setitem__(1, v & 0xFFFF))
    del _p8, _p16

    def step(self):
        """Execute one instruction."""
        pc = self.pc
        self.pc = (pc + 1) & 0xFFFF
        self.ops[self.m[pc]]()

    def regs_str(self):
        r = self.r
        m = self.m
        pc = self.pc
        ob = ' '.join('%02X' % m[(pc + i) & 0xFFFF] for i in range(4))
        return ('PC=%04X [%s] AF=%02X%02X BC=%02X%02X DE=%02X%02X HL=%02X%02X '
                'IX=%04X IY=%04X SP=%04X (SP)=%04X F=%s' % (
                    pc, ob, r[7], r[6], r[0], r[1], r[2], r[3], r[4], r[5],
                    self.xy[0], self.xy[1], self.sp,
                    m[self.sp] | (m[(self.sp + 1) & 0xFFFF] << 8),
                    ''.join(ch if r[6] & bit else '-' for ch, bit in
                            zip('SZ5H3PNC', (0x80, 0x40, 0x20, 0x10, 8, 4, 2, 1)))))

    # ---------------------------------------------------------------------
    def _build(self):
        c = self
        r = self.r
        m = self.m
        xy = self.xy
        alt = self.alt

        MAIN = [None] * 256
        DDT = [None] * 256
        FDT = [None] * 256
        EDT = [None] * 256
        CBT = [None] * 256
        XCB = [None] * 256

        def fetch():
            pc = c.pc
            c.pc = (pc + 1) & 0xFFFF
            return m[pc]

        def fetch16():
            pc = c.pc
            c.pc = (pc + 2) & 0xFFFF
            return m[pc] | (m[(pc + 1) & 0xFFFF] << 8)

        def rd16(a):
            return m[a] | (m[(a + 1) & 0xFFFF] << 8)

        def wr16(a, v):
            m[a] = v & 0xFF
            m[(a + 1) & 0xFFFF] = (v >> 8) & 0xFF

        def push(v):
            sp = (c.sp - 2) & 0xFFFF
            c.sp = sp
            m[sp] = v & 0xFF
            m[(sp + 1) & 0xFFFF] = (v >> 8) & 0xFF

        def pop():
            sp = c.sp
            c.sp = (sp + 2) & 0xFFFF
            return m[sp] | (m[(sp + 1) & 0xFFFF] << 8)

        self._push = push
        self._pop = pop

        # ---- 8-bit ALU ---------------------------------------------------
        def add_a(v):
            a = r[7]
            res = a + v
            r[6] = (SZ[res & 0xFF] | ((a ^ v ^ res) & FH) |
                    (((a ^ res) & (v ^ res) & 0x80) >> 5) | (res >> 8))
            r[7] = res & 0xFF

        def adc_a(v):
            a = r[7]
            res = a + v + (r[6] & 1)
            r[6] = (SZ[res & 0xFF] | ((a ^ v ^ res) & FH) |
                    (((a ^ res) & (v ^ res) & 0x80) >> 5) | (res >> 8))
            r[7] = res & 0xFF

        def sub_a(v):
            a = r[7]
            res = a - v
            r[6] = (SZ[res & 0xFF] | ((a ^ v ^ res) & FH) |
                    (((a ^ v) & (a ^ res) & 0x80) >> 5) | FN | ((res >> 8) & 1))
            r[7] = res & 0xFF

        def sbc_a(v):
            a = r[7]
            res = a - v - (r[6] & 1)
            r[6] = (SZ[res & 0xFF] | ((a ^ v ^ res) & FH) |
                    (((a ^ v) & (a ^ res) & 0x80) >> 5) | FN | ((res >> 8) & 1))
            r[7] = res & 0xFF

        def and_a(v):
            a = r[7] & v
            r[7] = a
            r[6] = SZP[a] | FH

        def xor_a(v):
            a = r[7] ^ v
            r[7] = a
            r[6] = SZP[a]

        def or_a(v):
            a = r[7] | v
            r[7] = a
            r[6] = SZP[a]

        def cp_a(v):
            a = r[7]
            res = a - v
            r[6] = (SZ[res & 0xFF] | ((a ^ v ^ res) & FH) |
                    (((a ^ v) & (a ^ res) & 0x80) >> 5) | FN | ((res >> 8) & 1))

        ALU = [add_a, adc_a, sub_a, sbc_a, and_a, xor_a, or_a, cp_a]

        def inc8(v):
            res = (v + 1) & 0xFF
            r[6] = ((r[6] & FC) | SZ[res] | (0 if res & 0x0F else FH) |
                    (FPV if res == 0x80 else 0))
            return res

        def dec8(v):
            res = (v - 1) & 0xFF
            r[6] = ((r[6] & FC) | FN | SZ[res] |
                    (FH if (res & 0x0F) == 0x0F else 0) |
                    (FPV if res == 0x7F else 0))
            return res

        # ---- rotates / shifts (CB) ---------------------------------------
        def rlc(v):
            res = ((v << 1) | (v >> 7)) & 0xFF
            r[6] = SZP[res] | (v >> 7)
            return res

        def rrc(v):
            res = ((v >> 1) | (v << 7)) & 0xFF
            r[6] = SZP[res] | (v & 1)
            return res

        def rl(v):
            res = ((v << 1) | (r[6] & 1)) & 0xFF
            r[6] = SZP[res] | (v >> 7)
            return res

        def rr(v):
            res = (v >> 1) | ((r[6] & 1) << 7)
            r[6] = SZP[res] | (v & 1)
            return res

        def sla(v):
            res = (v << 1) & 0xFF
            r[6] = SZP[res] | (v >> 7)
            return res

        def sra(v):
            res = (v >> 1) | (v & 0x80)
            r[6] = SZP[res] | (v & 1)
            return res

        def sll(v):
            res = ((v << 1) | 1) & 0xFF
            r[6] = SZP[res] | (v >> 7)
            return res

        def srl(v):
            res = v >> 1
            r[6] = SZP[res] | (v & 1)
            return res

        ROT = [rlc, rrc, rl, rr, sla, sra, sll, srl]

        # ---- 16-bit arithmetic -------------------------------------------
        def add16(a, b):
            res = a + b
            r[6] = ((r[6] & (FS | FZ | FPV)) | (((a ^ b ^ res) >> 8) & FH) |
                    (res >> 16))
            return res & 0xFFFF

        def adc16(a, b):
            res = a + b + (r[6] & 1)
            r[6] = (((res >> 8) & FS) | (0 if res & 0xFFFF else FZ) |
                    (((a ^ b ^ res) >> 8) & FH) |
                    (((a ^ res) & (b ^ res) & 0x8000) >> 13) | (res >> 16))
            return res & 0xFFFF

        def sbc16(a, b):
            res = a - b - (r[6] & 1)
            r[6] = (((res >> 8) & FS) | (0 if res & 0xFFFF else FZ) |
                    (((a ^ b ^ res) >> 8) & FH) |
                    (((a ^ b) & (a ^ res) & 0x8000) >> 13) | FN |
                    ((res >> 16) & 1))
            return res & 0xFFFF

        # ---- register pair accessors -------------------------------------
        def mk_pairs(k):
            def gbc():
                return (r[0] << 8) | r[1]

            def sbc_(v):
                r[0] = v >> 8
                r[1] = v & 0xFF

            def gde():
                return (r[2] << 8) | r[3]

            def sde(v):
                r[2] = v >> 8
                r[3] = v & 0xFF

            if k is None:
                def ghl():
                    return (r[4] << 8) | r[5]

                def shl(v):
                    r[4] = v >> 8
                    r[5] = v & 0xFF
            else:
                def ghl():
                    return xy[k]

                def shl(v):
                    xy[k] = v

            def gsp():
                return c.sp

            def ssp(v):
                c.sp = v

            def gaf():
                return (r[7] << 8) | r[6]

            def saf(v):
                r[7] = v >> 8
                r[6] = v & 0xFF
            return ([gbc, gde, ghl, gsp], [sbc_, sde, shl, ssp],
                    [gbc, gde, ghl, gaf], [sbc_, sde, shl, saf])

        def mk_addr(k):
            if k is None:
                return lambda: (r[4] << 8) | r[5]

            def f():
                pc = c.pc
                c.pc = (pc + 1) & 0xFFFF
                d = m[pc]
                return (xy[k] + d - ((d & 0x80) << 1)) & 0xFFFF
            return f

        def halt():
            raise Z80Error('HALT executed')

        def nop():
            pass

        # ---- misc single ops -----------------------------------------------
        def rlca():
            a = r[7]
            r[7] = ((a << 1) | (a >> 7)) & 0xFF
            r[6] = (r[6] & (FS | FZ | FPV)) | (a >> 7)

        def rrca():
            a = r[7]
            r[7] = ((a >> 1) | (a << 7)) & 0xFF
            r[6] = (r[6] & (FS | FZ | FPV)) | (a & 1)

        def rla():
            a = r[7]
            r[7] = ((a << 1) | (r[6] & 1)) & 0xFF
            r[6] = (r[6] & (FS | FZ | FPV)) | (a >> 7)

        def rra():
            a = r[7]
            r[7] = (a >> 1) | ((r[6] & 1) << 7)
            r[6] = (r[6] & (FS | FZ | FPV)) | (a & 1)

        def daa():
            a = r[7]
            f = r[6]
            diff = 0
            cf = f & FC
            if (f & FH) or (a & 0x0F) > 9:
                diff = 6
            if cf or a > 0x99:
                diff |= 0x60
                cf = 1
            if f & FN:
                h = FH if (f & FH) and (a & 0x0F) < 6 else 0
                a = (a - diff) & 0xFF
            else:
                h = FH if (a & 0x0F) > 9 else 0
                a = (a + diff) & 0xFF
            r[7] = a
            r[6] = SZP[a] | h | (f & FN) | cf

        def cpl():
            r[7] ^= 0xFF
            r[6] |= FH | FN

        def scf():
            r[6] = (r[6] & (FS | FZ | FPV)) | FC

        def ccf():
            f = r[6]
            r[6] = ((f & (FS | FZ | FPV)) | (FH if f & FC else 0) |
                    ((f & FC) ^ FC))

        def ex_af():
            r[6], alt[6] = alt[6], r[6]
            r[7], alt[7] = alt[7], r[7]

        def exx():
            for i in range(6):
                r[i], alt[i] = alt[i], r[i]

        def ex_de_hl():
            r[2], r[3], r[4], r[5] = r[4], r[5], r[2], r[3]

        def djnz():
            d = fetch()
            b = (r[0] - 1) & 0xFF
            r[0] = b
            if b:
                c.pc = (c.pc + d - ((d & 0x80) << 1)) & 0xFFFF

        def jr():
            d = fetch()
            c.pc = (c.pc + d - ((d & 0x80) << 1)) & 0xFFFF

        def ret():
            c.pc = pop()

        def jp():
            c.pc = fetch16()

        def call():
            nn = fetch16()
            push(c.pc)
            c.pc = nn

        def di():
            c.iff1 = c.iff2 = 0

        def ei():
            c.iff1 = c.iff2 = 1

        def out_n():
            n = fetch()
            c.port_out((r[7] << 8) | n, r[7])

        def in_n():
            n = fetch()
            r[7] = c.port_in((r[7] << 8) | n) & 0xFF

        def cb_prefix():
            CBT[fetch()]()

        def dd_prefix():
            DDT[fetch()]()

        def fd_prefix():
            FDT[fetch()]()

        def ed_prefix():
            EDT[fetch()]()

        # ---- main / index table construction -------------------------------
        def mk_table(k):
            T = [None] * 256
            G, S, G2, S2 = mk_pairs(k)
            ghl, shl = G[2], S[2]
            ADDR = mk_addr(k)
            idx = k is not None

            def g8(i):
                if idx and i == 4:
                    return lambda: xy[k] >> 8
                if idx and i == 5:
                    return lambda: xy[k] & 0xFF
                return lambda: r[i]

            def s8(i):
                if idx and i == 4:
                    def f(v):
                        xy[k] = (xy[k] & 0xFF) | (v << 8)
                    return f
                if idx and i == 5:
                    def f(v):
                        xy[k] = (xy[k] & 0xFF00) | v
                    return f

                def f(v):
                    r[i] = v
                return f

            def make(op):
                x = op >> 6
                y = (op >> 3) & 7
                z = op & 7
                p = y >> 1
                q = y & 1
                if x == 1:
                    if op == 0x76:
                        return halt
                    if y == 6:
                        def f():
                            m[ADDR()] = r[z]
                        return f
                    if z == 6:
                        def f():
                            r[y] = m[ADDR()]
                        return f
                    if not idx or (y not in (4, 5) and z not in (4, 5)):
                        def f():
                            r[y] = r[z]
                        return f
                    gs = g8(z)
                    sd = s8(y)

                    def f():
                        sd(gs())
                    return f
                if x == 2:
                    fn = ALU[y]
                    if z == 6:
                        def f():
                            fn(m[ADDR()])
                    elif idx and z in (4, 5):
                        gs = g8(z)

                        def f():
                            fn(gs())
                    else:
                        def f():
                            fn(r[z])
                    return f
                if x == 0:
                    if z == 0:
                        if y == 0:
                            return nop
                        if y == 1:
                            return ex_af
                        if y == 2:
                            return djnz
                        if y == 3:
                            return jr
                        mask, want = CC[y - 4]
                        if want:
                            def f():
                                d = fetch()
                                if r[6] & mask:
                                    c.pc = (c.pc + d - ((d & 0x80) << 1)) & 0xFFFF
                        else:
                            def f():
                                d = fetch()
                                if not r[6] & mask:
                                    c.pc = (c.pc + d - ((d & 0x80) << 1)) & 0xFFFF
                        return f
                    if z == 1:
                        if q == 0:
                            setp = S[p]

                            def f():
                                setp(fetch16())
                            return f
                        getp = G[p]

                        def f():
                            shl(add16(ghl(), getp()))
                        return f
                    if z == 2:
                        if q == 0:
                            if p == 0:
                                def f():
                                    m[(r[0] << 8) | r[1]] = r[7]
                            elif p == 1:
                                def f():
                                    m[(r[2] << 8) | r[3]] = r[7]
                            elif p == 2:
                                def f():
                                    wr16(fetch16(), ghl())
                            else:
                                def f():
                                    m[fetch16()] = r[7]
                        else:
                            if p == 0:
                                def f():
                                    r[7] = m[(r[0] << 8) | r[1]]
                            elif p == 1:
                                def f():
                                    r[7] = m[(r[2] << 8) | r[3]]
                            elif p == 2:
                                def f():
                                    shl(rd16(fetch16()))
                            else:
                                def f():
                                    r[7] = m[fetch16()]
                        return f
                    if z == 3:
                        getp, setp = G[p], S[p]
                        if q == 0:
                            def f():
                                setp((getp() + 1) & 0xFFFF)
                        else:
                            def f():
                                setp((getp() - 1) & 0xFFFF)
                        return f
                    if z in (4, 5):
                        fn = inc8 if z == 4 else dec8
                        if y == 6:
                            def f():
                                a = ADDR()
                                m[a] = fn(m[a])
                        elif idx and y in (4, 5):
                            gs, sd = g8(y), s8(y)

                            def f():
                                sd(fn(gs()))
                        else:
                            def f():
                                r[y] = fn(r[y])
                        return f
                    if z == 6:
                        if y == 6:
                            def f():
                                a = ADDR()
                                m[a] = fetch()
                        elif idx and y in (4, 5):
                            sd = s8(y)

                            def f():
                                sd(fetch())
                        else:
                            def f():
                                r[y] = fetch()
                        return f
                    return [rlca, rrca, rla, rra, daa, cpl, scf, ccf][y]
                # x == 3
                if z == 0:
                    mask, want = CC[y]
                    if want:
                        def f():
                            if r[6] & mask:
                                c.pc = pop()
                    else:
                        def f():
                            if not r[6] & mask:
                                c.pc = pop()
                    return f
                if z == 1:
                    if q == 0:
                        setp = S2[p]

                        def f():
                            setp(pop())
                        return f
                    if p == 0:
                        return ret
                    if p == 1:
                        return exx
                    if p == 2:
                        def f():
                            c.pc = ghl()
                        return f

                    def f():
                        c.sp = ghl()
                    return f
                if z == 2:
                    mask, want = CC[y]
                    if want:
                        def f():
                            nn = fetch16()
                            if r[6] & mask:
                                c.pc = nn
                    else:
                        def f():
                            nn = fetch16()
                            if not r[6] & mask:
                                c.pc = nn
                    return f
                if z == 3:
                    if y == 0:
                        return jp
                    if y == 1:
                        if not idx:
                            return cb_prefix

                        def f():
                            a = ADDR()
                            XCB[fetch()](a)
                        return f
                    if y == 2:
                        return out_n
                    if y == 3:
                        return in_n
                    if y == 4:
                        def f():
                            sp = c.sp
                            v = rd16(sp)
                            wr16(sp, ghl())
                            shl(v)
                        return f
                    if y == 5:
                        return ex_de_hl
                    if y == 6:
                        return di
                    return ei
                if z == 4:
                    mask, want = CC[y]
                    if want:
                        def f():
                            nn = fetch16()
                            if r[6] & mask:
                                push(c.pc)
                                c.pc = nn
                    else:
                        def f():
                            nn = fetch16()
                            if not r[6] & mask:
                                push(c.pc)
                                c.pc = nn
                    return f
                if z == 5:
                    if q == 0:
                        getp = G2[p]

                        def f():
                            push(getp())
                        return f
                    return [call, dd_prefix, ed_prefix, fd_prefix][p]
                if z == 6:
                    fn = ALU[y]

                    def f():
                        fn(fetch())
                    return f
                vec = y * 8

                def f():
                    push(c.pc)
                    c.pc = vec
                return f

            for op in range(256):
                T[op] = make(op)
            return T

        MAIN[:] = mk_table(None)
        DDT[:] = mk_table(0)
        FDT[:] = mk_table(1)

        HL = lambda: (r[4] << 8) | r[5]

        # ---- CB table -----------------------------------------------------
        def mk_cb(op):
            x = op >> 6
            y = (op >> 3) & 7
            z = op & 7
            if x == 0:
                fn = ROT[y]
                if z == 6:
                    def f():
                        a = HL()
                        m[a] = fn(m[a])
                else:
                    def f():
                        r[z] = fn(r[z])
                return f
            mask = 1 << y
            if x == 1:
                if z == 6:
                    def f():
                        t = m[HL()] & mask
                        r[6] = (r[6] & FC) | FH | SZ[t] | (0 if t else FPV)
                else:
                    def f():
                        t = r[z] & mask
                        r[6] = (r[6] & FC) | FH | SZ[t] | (0 if t else FPV)
                return f
            if x == 2:
                nm = 0xFF ^ mask
                if z == 6:
                    def f():
                        a = HL()
                        m[a] &= nm
                else:
                    def f():
                        r[z] &= nm
                return f
            if z == 6:
                def f():
                    a = HL()
                    m[a] |= mask
            else:
                def f():
                    r[z] |= mask
            return f

        # ---- DDCB/FDCB table (takes effective address) ---------------------
        def mk_xcb(op):
            x = op >> 6
            y = (op >> 3) & 7
            z = op & 7
            if x == 0:
                fn = ROT[y]
                if z == 6:
                    def f(a):
                        m[a] = fn(m[a])
                else:
                    def f(a):
                        v = fn(m[a])
                        m[a] = v
                        r[z] = v
                return f
            mask = 1 << y
            if x == 1:
                def f(a):
                    t = m[a] & mask
                    r[6] = (r[6] & FC) | FH | SZ[t] | (0 if t else FPV)
                return f
            if x == 2:
                nm = 0xFF ^ mask
                if z == 6:
                    def f(a):
                        m[a] &= nm
                else:
                    def f(a):
                        v = m[a] & nm
                        m[a] = v
                        r[z] = v
                return f
            if z == 6:
                def f(a):
                    m[a] |= mask
            else:
                def f(a):
                    v = m[a] | mask
                    m[a] = v
                    r[z] = v
            return f

        for op in range(256):
            CBT[op] = mk_cb(op)
            XCB[op] = mk_xcb(op)

        # ---- ED table -----------------------------------------------------
        G0, S0, _, _ = mk_pairs(None)

        def set3(bc, de, hl):
            r[0] = bc >> 8
            r[1] = bc & 0xFF
            r[2] = de >> 8
            r[3] = de & 0xFF
            r[4] = hl >> 8
            r[5] = hl & 0xFF

        def ldx(step, repeat):
            hl = (r[4] << 8) | r[5]
            de = (r[2] << 8) | r[3]
            bc = (r[0] << 8) | r[1]
            if not repeat:
                m[de] = m[hl]
                hl = (hl + step) & 0xFFFF
                de = (de + step) & 0xFFFF
                bc = (bc - 1) & 0xFFFF
                set3(bc, de, hl)
                r[6] = (r[6] & (FS | FZ | FC)) | (FPV if bc else 0)
                return
            n = bc or 0x10000
            if step == 1 and hl + n <= 0x10000 and de + n <= 0x10000:
                if de <= hl or de >= hl + n:
                    m[de:de + n] = m[hl:hl + n]
                else:
                    per = de - hl
                    pat = bytes(m[hl:de])
                    rep = (pat * (n // per + 1))[:n]
                    m[de:de + n] = rep
                hl += n
                de += n
            else:
                for _ in range(n):
                    m[de] = m[hl]
                    hl = (hl + step) & 0xFFFF
                    de = (de + step) & 0xFFFF
            set3(0, de & 0xFFFF, hl & 0xFFFF)
            r[6] = r[6] & (FS | FZ | FC)

        def cpx(step, repeat):
            hl = (r[4] << 8) | r[5]
            bc = (r[0] << 8) | r[1]
            a = r[7]
            while True:
                v = m[hl]
                res = (a - v) & 0xFF
                hl = (hl + step) & 0xFFFF
                bc = (bc - 1) & 0xFFFF
                if not repeat or bc == 0 or res == 0:
                    break
            r[0] = bc >> 8
            r[1] = bc & 0xFF
            r[4] = hl >> 8
            r[5] = hl & 0xFF
            r[6] = ((r[6] & FC) | FN | SZ[res] | ((a ^ v ^ res) & FH) |
                    (FPV if bc else 0))

        def inx(step, repeat):
            while True:
                hl = (r[4] << 8) | r[5]
                m[hl] = c.port_in((r[0] << 8) | r[1]) & 0xFF
                hl = (hl + step) & 0xFFFF
                r[4] = hl >> 8
                r[5] = hl & 0xFF
                r[0] = (r[0] - 1) & 0xFF
                if not repeat or r[0] == 0:
                    break
            r[6] = (r[6] & FC) | SZ[r[0]] | FN

        def outx(step, repeat):
            while True:
                hl = (r[4] << 8) | r[5]
                v = m[hl]
                r[0] = (r[0] - 1) & 0xFF
                c.port_out((r[0] << 8) | r[1], v)
                hl = (hl + step) & 0xFFFF
                r[4] = hl >> 8
                r[5] = hl & 0xFF
                if not repeat or r[0] == 0:
                    break
            r[6] = (r[6] & FC) | SZ[r[0]] | FN

        def ld_a_i():
            r[7] = c.i
            r[6] = (r[6] & FC) | SZ[c.i] | (FPV if c.iff2 else 0)

        def ld_a_r():
            c.rreg = (c.rreg & 0x80) | ((c.rreg + 0x35) & 0x7F)
            r[7] = c.rreg
            r[6] = (r[6] & FC) | SZ[r[7]] | (FPV if c.iff2 else 0)

        def ld_i_a():
            c.i = r[7]

        def ld_r_a():
            c.rreg = r[7]

        def rrd():
            a_ = HL()
            t = m[a_]
            a = r[7]
            m[a_] = ((a & 0x0F) << 4) | (t >> 4)
            a = (a & 0xF0) | (t & 0x0F)
            r[7] = a
            r[6] = (r[6] & FC) | SZP[a]

        def rld():
            a_ = HL()
            t = m[a_]
            a = r[7]
            m[a_] = ((t << 4) | (a & 0x0F)) & 0xFF
            a = (a & 0xF0) | (t >> 4)
            r[7] = a
            r[6] = (r[6] & FC) | SZP[a]

        def neg():
            a = r[7]
            r[7] = 0
            sub_a(a)

        def retn():
            c.pc = pop()
            c.iff1 = c.iff2

        def mk_ed(op):
            x = op >> 6
            y = (op >> 3) & 7
            z = op & 7
            p = y >> 1
            q = y & 1
            if x == 1:
                if z == 0:
                    def f():
                        v = c.port_in((r[0] << 8) | r[1]) & 0xFF
                        r[6] = (r[6] & FC) | SZP[v]
                        if y != 6:
                            r[y] = v
                    return f
                if z == 1:
                    def f():
                        c.port_out((r[0] << 8) | r[1], r[y] if y != 6 else 0)
                    return f
                if z == 2:
                    getp = G0[p]
                    fn = sbc16 if q == 0 else adc16

                    def f():
                        v = fn((r[4] << 8) | r[5], getp())
                        r[4] = v >> 8
                        r[5] = v & 0xFF
                    return f
                if z == 3:
                    getp, setp = G0[p], S0[p]
                    if q == 0:
                        def f():
                            wr16(fetch16(), getp())
                    else:
                        def f():
                            setp(rd16(fetch16()))
                    return f
                if z == 4:
                    return neg
                if z == 5:
                    return retn
                if z == 6:
                    mode = [0, 0, 1, 2, 0, 0, 1, 2][y]

                    def f():
                        c.im = mode
                    return f
                return [ld_i_a, ld_r_a, ld_a_i, ld_a_r, rrd, rld, nop, nop][y]
            if x == 2 and z <= 3 and y >= 4:
                step = 1 if (y & 1) == 0 else -1
                repeat = y >= 6
                fn = [ldx, cpx, inx, outx][z]
                return lambda: fn(step, repeat)

            def bad():
                raise Z80Error('unknown opcode ED %02X' % op)
            return bad

        for op in range(256):
            EDT[op] = mk_ed(op)

        self.ops = MAIN
        self.dd_ops = DDT
        self.fd_ops = FDT
        self.ed_ops = EDT
        self.cb_ops = CBT


# ---------------------------------------------------------------------------
# T-states (for CPM(count_cycles=True)).  Conditional instructions are timed
# from the state after them: JR cc by its condition (the flags are kept),
# DJNZ by B, CALL cc and RET cc by whether SP moved.
_T_MAIN = [
    4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,          # 00
    8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,         # 10
    7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,        # 20
    7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,     # 30
] + [0] * 128 + [
    5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 0, 10, 17, 7, 11,     # C0
    5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 0, 7, 11,      # D0
    5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 0, 7, 11,       # E0
    5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 0, 7, 11,        # F0
]
for _o in range(0x40, 0xC0):
    _T_MAIN[_o] = 7 if (_o & 7) == 6 or (0x40 <= _o < 0x80 and (_o >> 3) & 7 == 6) else 4
_T_MAIN[0x76] = 4
_T_COND = {}                 # opcode: taken T-states
for _o in (0x20, 0x28, 0x30, 0x38):
    _T_COND[_o] = 12
_T_COND[0x10] = 13
for _o in range(0xC0, 0x100, 8):
    _T_COND[_o] = 11
    _T_COND[_o + 4] = 17
_JR_FLAG = {0x20: (0x40, 0), 0x28: (0x40, 0x40), 0x30: (1, 0), 0x38: (1, 1)}
_T_ED = [8] * 256
for _o in range(0x40, 0x80):
    _T_ED[_o] = [12, 12, 15, 20, 8, 14, 8, 9][_o & 7]
for _o in (0x4A, 0x5A, 0x6A, 0x7A):
    _T_ED[_o] = 15
for _o in (0x67, 0x6F):
    _T_ED[_o] = 18
for _o in (0x77, 0x7F):
    _T_ED[_o] = 8
for _o in (0xA0, 0xA1, 0xA2, 0xA3, 0xA8, 0xA9, 0xAA, 0xAB,
           0xB0, 0xB1, 0xB2, 0xB3, 0xB8, 0xB9, 0xBA, 0xBB):
    _T_ED[_o] = 16


def _tstates(m, pc, op, newpc, cpu=None, sp0=None):
    """T-states of the instruction op at pc that left the PC at newpc
    (and, for conditional ones, the CPU in cpu, SP before it sp0)."""
    t = _T_MAIN[op]
    if t:
        c = _T_COND.get(op)
        if c is not None:
            if op == 0x10:
                taken = cpu.r[0] != 0
            elif op < 0x40:
                mask, val = _JR_FLAG[op]
                taken = (cpu.r[6] & mask) == val
            else:
                taken = cpu.sp != sp0
            return c if taken else t
        return t
    op2 = m[(pc + 1) & 0xFFFF]
    if op == 0xCB:
        if (op2 & 7) == 6:
            return 12 if 0x40 <= op2 < 0x80 else 15
        return 8
    if op == 0xED:
        if op2 >= 0xB0 and newpc == pc:
            return 21
        return _T_ED[op2]
    # DD / FD
    if op2 == 0xCB:
        return 20 if 0x40 <= m[(pc + 3) & 0xFFFF] < 0x80 else 23
    if op2 in (0x34, 0x35):
        return 23
    if op2 == 0x36:
        return 19
    if 0x40 <= op2 < 0xC0 and op2 != 0x76 and (
            (op2 & 7) == 6 or (op2 < 0x80 and (op2 >> 3) & 7 == 6)):
        return 19
    t = _T_MAIN[op2]
    return (t or 4) + 4


# ---------------------------------------------------------------------------
# CP/M side
# ---------------------------------------------------------------------------
class EmulatorError(Exception):
    """Unsupported BDOS function etc.  .result holds partial RunResult when
    raised from run_com(raise_on_error=True)."""
    result = None


class ExitRun(Exception):
    def __init__(self, reason):
        Exception.__init__(self, reason)
        self.reason = reason


class RunResult(object):
    def __init__(self, console_bytes, printer_bytes, exit_reason, instructions,
                 error=None, elapsed=0.0):
        self.console_bytes = bytes(console_bytes)
        self.printer_bytes = bytes(printer_bytes)
        self.exit_reason = exit_reason
        self.instructions = instructions
        self.error = error
        self.elapsed = elapsed

    @property
    def console(self):
        return self.console_bytes.decode('latin-1')

    @property
    def printer(self):
        return self.printer_bytes.decode('latin-1')

    @property
    def ok(self):
        return self.error is None

    def __repr__(self):
        return ('RunResult(exit_reason=%r, instructions=%d, error=%r, '
                'console=%r)' % (self.exit_reason, self.instructions,
                                 self.error, self.console[-200:]))


def _to_input_bytes(data):
    if data is None:
        return b''
    if isinstance(data, (bytes, bytearray)):
        return bytes(data)
    if isinstance(data, str):
        return data.encode('latin-1')
    # iterable of lines
    return ''.join(str(s) + '\n' for s in data).encode('latin-1')


class ConsoleInput(object):
    """Scripted (bytes) and/or streamed (binary file, line at a time) input."""

    def __init__(self, data=b'', stream=None, before_read=None):
        self.buf = bytearray(data)
        self.pos = 0
        self.stream = stream
        self.before_read = before_read

    def _fill(self):
        if self.pos < len(self.buf):
            return True
        if self.stream is None:
            return False
        if self.before_read:
            self.before_read()
        line = self.stream.readline()
        if not line:
            self.stream = None
            return False
        self.buf = bytearray(line)
        self.pos = 0
        return True

    def ready(self):
        return self.pos < len(self.buf)

    def read_line(self):
        """Return next line (bytes, without newline) or None at EOF."""
        if not self._fill():
            return None
        i = self.buf.find(b'\n', self.pos)
        if i < 0:
            line = bytes(self.buf[self.pos:])
            self.pos = len(self.buf)
        else:
            line = bytes(self.buf[self.pos:i])
            self.pos = i + 1
        if line.endswith(b'\r'):
            line = line[:-1]
        return line

    def read_char(self):
        """Return next char (LF / CRLF -> CR) or None at EOF."""
        if not self._fill():
            return None
        ch = self.buf[self.pos]
        self.pos += 1
        if ch == 10:
            return 13
        if ch == 13 and self.pos < len(self.buf) and self.buf[self.pos] == 10:
            self.pos += 1
        return ch


class CRLFWriter(object):
    """Writes console bytes to a binary stream, collapsing CR LF to LF."""

    def __init__(self, stream):
        self.s = stream
        self.cr = False

    def write(self, b):
        out = bytearray()
        if self.cr:
            self.cr = False
            if b == 10:
                self.s.write(b'\n')
                return
            out.append(13)
        if b == 13:
            self.cr = True
        else:
            out.append(b)
        if out:
            self.s.write(bytes(out))

    def flush(self, pending=True):
        if pending and self.cr:
            self.cr = False
            self.s.write(b'\r')
        try:
            self.s.flush()
        except Exception:
            pass


_FCB_CHARS = set(b'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$#&@!%\'()-{}~`^_+')


def host_to_fcbname(name):
    """Host file name -> 11-byte CP/M name, or None if not representable."""
    up = name.upper()
    if up.count('.') > 1:
        return None
    base, dot, ext = up.partition('.')
    if not 1 <= len(base) <= 8 or len(ext) > 3 or (dot and not ext):
        return None
    try:
        raw = (base + ext).encode('ascii')
    except UnicodeEncodeError:
        return None
    if any(ch not in _FCB_CHARS for ch in raw):
        return None
    return (base.ljust(8) + ext.ljust(3)).encode('ascii')


def fcbname_to_host(nm):
    base = nm[:8].decode('latin-1').rstrip()
    ext = nm[8:11].decode('latin-1').rstrip()
    return base + ('.' + ext if ext else '')


def _match(pat, nm):
    for p, n in zip(pat, nm):
        if p != 0x3F and p != n:
            return False
    return True


def parse_fcb_arg(tok):
    """CCP-style parse of one command-line token -> 12 bytes (dr + name)."""
    dr = 0
    if len(tok) >= 2 and tok[1] == ':':
        dr = ord(tok[0].upper()) - 64
        if not 1 <= dr <= 16:
            dr = 0
        tok = tok[2:]
    base, _, ext = tok.partition('.')

    def field(s, n):
        out = ''
        for ch in s:
            if ch == '*':
                out += '?' * (n - len(out))
                break
            out += ch
        return out[:n].ljust(n)
    return bytes([dr]) + (field(base, 8) + field(ext, 3)).upper().encode('latin-1', 'replace')


class CPM(object):
    CCP = 0xE000
    BDOS = 0xE806
    BIOS = 0xF600
    NBIOS = 17
    DPB = 0xF700
    DPH = 0xF720
    DIRBUF = 0xF740
    ALV = 0xF7C0
    CSV = 0xF7E0
    INPUT_EOF_LIMIT = 10000   # char-input reads at EOF before giving up

    def __init__(self, directory='.', stdin_lines=None, echo=True,
                 max_instr=200000000, live_output=None, trace=False,
                 trace_instr=False, const_ready=False, input_stream=None,
                 trace_file=None, count_cycles=False):
        self.dir = os.path.abspath(directory)
        self.cpu = Z80()
        self.mem = self.cpu.m
        self.echo = echo
        self.max_instr = max_instr
        self.count_cycles = count_cycles
        self.cycles = 0              # T-states (count_cycles)
        self.starts = []             # cycles at each start of a program at 0100h
        self.bdos_calls = {}         # BDOS function: number of calls
        self.profile = None          # a dict: T-states by instruction address
        self.trace = trace
        self.trace_instr = trace_instr
        self.trace_file = trace_file or sys.stderr
        self.const_ready = const_ready
        self.live = CRLFWriter(live_output) if live_output is not None else None
        self.input = ConsoleInput(_to_input_bytes(stdin_lines), input_stream,
                                  self._before_input)
        self.out = bytearray()
        self.lst = bytearray()
        self.handles = {}
        self.path_cache = {}
        self.search_list = []
        self.cur_disk = 0
        self.user = 0
        self.dma = 0x80
        self.eof_hits = 0
        self.traps = {0x0000: self._trap_zero, self.BDOS: self._bdos}
        for i in range(self.NBIOS):
            self.traps[self.BIOS + 3 * i] = self._mk_bios_trap(i)
        self.bdos_fns = {
            0: self._f_reset, 1: self._f_conin, 2: self._f_conout,
            3: self._f_reader, 4: self._f_punch, 5: self._f_list,
            6: self._f_dirio, 7: self._f_get_iobyte, 8: self._f_set_iobyte,
            9: self._f_print, 10: self._f_readbuf, 11: self._f_const,
            12: self._f_version, 13: self._f_reset_disk, 14: self._f_select,
            15: self._f_open, 16: self._f_close, 17: self._f_search_first,
            18: self._f_search_next, 19: self._f_delete, 20: self._f_read_seq,
            21: self._f_write_seq, 22: self._f_make, 23: self._f_rename,
            24: self._f_login_vec, 25: self._f_cur_disk, 26: self._f_set_dma,
            27: self._f_alloc_vec, 28: self._f_zero, 29: self._f_ro_vec,
            30: self._f_zero, 31: self._f_dpb, 32: self._f_user,
            33: self._f_read_rand, 34: self._f_write_rand,
            35: self._f_file_size, 36: self._f_set_rand, 37: self._f_zero,
            40: self._f_write_rand,
        }

    # ------------------------------------------------------------------ setup
    def _init_memory(self):
        m = self.mem
        m[:] = bytes(65536)
        m[0:3] = bytes([0xC3, 0x03, self.BIOS >> 8])      # JP F603
        m[5:8] = bytes([0xC3, self.BDOS & 0xFF, self.BDOS >> 8])  # JP E806
        m[self.BDOS] = 0xC9
        for i in range(self.NBIOS):
            a = self.BIOS + 3 * i
            tgt = self.BIOS + 0x60 + i
            m[a:a + 3] = bytes([0xC3, tgt & 0xFF, tgt >> 8])
            m[tgt] = 0xC9
        # Fake disk parameter block: SPT BSH BLM EXM DSM DRM AL0 AL1 CKS OFF
        dpb = [32, 0, 3, 7, 0, 255, 0, 63, 0, 0xC0, 0, 16, 0, 2, 0]
        m[self.DPB:self.DPB + len(dpb)] = bytes(dpb)
        dph = [0, 0, 0, 0, 0, 0, 0, 0, self.DIRBUF & 0xFF, self.DIRBUF >> 8,
               self.DPB & 0xFF, self.DPB >> 8, self.CSV & 0xFF, self.CSV >> 8,
               self.ALV & 0xFF, self.ALV >> 8]
        m[self.DPH:self.DPH + 16] = bytes(dph)

    def _set_cmdline(self, args):
        m = self.mem
        args = (args or '').strip().upper()
        tail = (' ' + args) if args else ''
        tb = tail.encode('latin-1', 'replace')[:126]
        m[0x80] = len(tb)
        m[0x81:0x81 + len(tb)] = tb
        m[0x81 + len(tb)] = 0
        toks = args.split()
        blank = bytes([0]) + b' ' * 11
        f1 = parse_fcb_arg(toks[0]) if len(toks) > 0 else blank
        f2 = parse_fcb_arg(toks[1]) if len(toks) > 1 else blank
        m[0x5C:0x5C + 12] = f1
        m[0x68:0x6C] = bytes(4)
        m[0x6C:0x6C + 12] = f2
        m[0x78:0x80] = bytes(8)

    def _reset_state(self):
        self.out = bytearray()
        self.lst = bytearray()
        self.search_list = []
        self.cur_disk = 0
        self.user = 0
        self.dma = 0x80
        self.eof_hits = 0
        self.path_cache = {}
        self._close_all()
        c = self.cpu
        c.r[:] = [0] * 8
        c.alt[:] = [0] * 8
        c.xy[:] = [0xFFFF, 0xFFFF]

    def run_com(self, prog, args='', stdin=None, raise_on_error=False, drive=0):
        """Load and run a .COM (path or bytes).  Returns RunResult.
        drive: the current drive (0 = A:), as the CCP leaves it."""
        if stdin is not None:
            self.input = ConsoleInput(_to_input_bytes(stdin), None,
                                      self._before_input)
        if isinstance(prog, (bytes, bytearray)):
            data = bytes(prog)
        else:
            with open(prog, 'rb') as fh:
                data = fh.read()
        if len(data) > self.CCP - 0x100 - 0x100:
            raise ValueError('program too large for TPA (%d bytes)' % len(data))
        self._reset_state()
        self._init_memory()
        m = self.mem
        self.cur_disk = drive
        m[4] = (self.user << 4) | drive
        m[0x100:0x100 + len(data)] = data
        self._set_cmdline(args)
        c = self.cpu
        c.sp = self.CCP
        c._push(0x0000)
        c.pc = 0x100
        t0 = time.perf_counter()
        reason, err, n = self._execute()
        el = time.perf_counter() - t0
        self._close_all()
        if self.live:
            self.live.flush()
        res = RunResult(self.out, self.lst, reason, n, err, el)
        if err and raise_on_error:
            e = EmulatorError(err)
            e.result = res
            raise e
        return res

    def _execute(self):
        c = self.cpu
        m = c.m
        ops = c.ops
        traps = self.traps
        limit = self.max_instr
        n = 0
        pc = c.pc
        try:
            if self.count_cycles:
                return self._execute_counted(limit)
            if self.trace_instr:
                tf = self.trace_file
                for n in range(limit):
                    pc = c.pc
                    if pc in traps:
                        traps[pc]()
                        continue
                    tf.write(c.regs_str() + '\n')
                    c.pc = (pc + 1) & 0xFFFF
                    ops[m[pc]]()
            else:
                for n in range(limit):
                    pc = c.pc
                    if pc in traps:
                        traps[pc]()
                        continue
                    c.pc = (pc + 1) & 0xFFFF
                    ops[m[pc]]()
            c.pc = c.pc
            return ('limit', 'instruction limit (%d) reached\n%s'
                    % (limit, c.regs_str()), limit)
        except ExitRun as e:
            return e.reason, None, n + 1
        except (Z80Error, EmulatorError) as e:
            c.pc = pc
            return 'error', '%s at PC=%04X\n%s' % (e, pc, c.regs_str()), n

    def _execute_counted(self, limit):
        c = self.cpu
        m = c.m
        ops = c.ops
        traps = self.traps
        bdos = self.BDOS
        calls = self.bdos_calls
        tst = _tstates
        cyc = self.cycles
        prof = self.profile
        n = 0
        try:
            for n in range(limit):
                pc = c.pc
                if pc in traps:
                    if pc == bdos:
                        fn = c.r[1]
                        calls[fn] = calls.get(fn, 0) + 1
                    self.cycles = cyc
                    traps[pc]()
                    continue
                if pc == 0x100:
                    self.starts.append(cyc)
                op = m[pc]
                c.pc = (pc + 1) & 0xFFFF
                if op == 0xED and m[(pc + 1) & 0xFFFF] >= 0xB0:
                    # block repeats run in one step: 21 T-states a repeat
                    op2 = m[(pc + 1) & 0xFFFF]
                    r = c.r
                    if op2 & 2:
                        n0 = r[0]
                        ops[op]()
                        k = ((n0 - r[0]) & 0xFF) or 0x100
                    else:
                        n0 = (r[0] << 8) | r[1]
                        ops[op]()
                        k = ((n0 - ((r[0] << 8) | r[1])) & 0xFFFF) or 0x10000
                    cyc += 21 * k - 5
                    continue
                sp0 = c.sp
                ops[op]()
                t = tst(m, pc, op, c.pc, c, sp0)
                cyc += t
                if prof is not None:
                    prof[pc] = prof.get(pc, 0) + t
        finally:
            self.cycles = cyc
        return ('limit', 'instruction limit (%d) reached\n%s'
                % (limit, c.regs_str()), limit)

    # ------------------------------------------------------------- console
    def _before_input(self):
        if self.live:
            self.live.flush()

    def _conout(self, b):
        self.out.append(b)
        if self.live:
            self.live.write(b)

    def _lstout(self, b):
        self.lst.append(b)

    def _conin_char(self):
        ch = self.input.read_char()
        if ch is None:
            self.eof_hits += 1
            if self.eof_hits > self.INPUT_EOF_LIMIT:
                raise ExitRun('input exhausted')
            return None
        return ch

    # ------------------------------------------------------------- traps
    def _trap_zero(self):
        raise ExitRun('jp0')

    def _mk_bios_trap(self, i):
        def f():
            self._bios(i)
        return f

    def _ret(self):
        self.cpu.pc = self.cpu._pop()

    def _bios(self, i):
        c = self.cpu
        r = c.r
        if self.trace:
            self.trace_file.write('BIOS %2d BC=%02X%02X\n' % (i, r[0], r[1]))
        if i == 0:
            raise ExitRun('boot')
        if i == 1:
            raise ExitRun('wboot')
        if i == 2:
            r[7] = 0xFF if (self.const_ready and self.input.ready()) else 0
        elif i == 3:
            ch = self._conin_char()
            r[7] = 0x1A if ch is None else ch
        elif i == 4:
            self._conout(r[1])
        elif i == 5:
            self._lstout(r[1])
        elif i == 6:
            pass
        elif i == 7:
            r[7] = 0x1A
        elif i == 8:
            pass
        elif i == 9:
            hl = self.DPH if r[1] < 16 else 0
            r[4], r[5] = hl >> 8, hl & 0xFF
        elif i in (10, 11):
            pass
        elif i == 12:
            self.dma = (r[0] << 8) | r[1]
        elif i in (13, 14):
            r[7] = 1        # no raw disk access
        elif i == 15:
            r[7] = 0xFF
        elif i == 16:
            r[4], r[5] = r[0], r[1]
        self._ret()

    def _bdos(self):
        c = self.cpu
        r = c.r
        fn = r[1]
        de = (r[2] << 8) | r[3]
        if self.trace:
            m = self.mem
            ret = m[c.sp] | (m[(c.sp + 1) & 0xFFFF] << 8)
            extra = ''
            if fn in (15, 16, 17, 19, 20, 21, 22, 23, 33, 34, 35, 36, 40):
                extra = ' FCB=%d:%r' % (m[de], bytes(m[de + 1:de + 12]).decode('latin-1'))
            self.trace_file.write('BDOS %2d DE=%04X from %04X%s\n' % (fn, de, (ret - 3) & 0xFFFF, extra))
        h = self.bdos_fns.get(fn)
        if h is None:
            raise EmulatorError('unsupported BDOS function %d (DE=%04X)' % (fn, de))
        val = h(de)
        if val is not None:
            val &= 0xFFFF
            r[4] = r[0] = val >> 8
            r[5] = r[7] = val & 0xFF
        self._ret()

    # ------------------------------------------------------- BDOS: char I/O
    def _f_reset(self, de):
        raise ExitRun('bdos0')

    def _f_conin(self, de):
        ch = self._conin_char()
        if ch is None:
            return 0x1A
        if self.echo and (ch >= 0x20 or ch in (8, 9, 10, 13)):
            self._conout(ch)
        return ch

    def _f_conout(self, de):
        self._conout(de & 0xFF)

    def _f_reader(self, de):
        return 0x1A

    def _f_punch(self, de):
        return None

    def _f_list(self, de):
        self._lstout(de & 0xFF)

    def _f_dirio(self, de):
        e = de & 0xFF
        if e == 0xFF:
            ch = self._conin_char()
            return 0 if ch is None else ch
        if e == 0xFE:
            return 0xFF if (self.const_ready and self.input.ready()) else 0
        self._conout(e)
        return 0

    def _f_get_iobyte(self, de):
        return self.mem[3]

    def _f_set_iobyte(self, de):
        self.mem[3] = de & 0xFF

    def _f_print(self, de):
        m = self.mem
        a = de
        for _ in range(65536):
            b = m[a]
            if b == 0x24:
                break
            self._conout(b)
            a = (a + 1) & 0xFFFF

    def _f_readbuf(self, de):
        m = self.mem
        line = self.input.read_line()
        if line is None:
            raise ExitRun('input exhausted')
        mx = m[de]
        line = line[:mx]
        m[(de + 1) & 0xFFFF] = len(line)
        for i, b in enumerate(line):
            m[(de + 2 + i) & 0xFFFF] = b
        if self.echo:
            for b in line:
                self._conout(b)
            self._conout(13)

    def _f_const(self, de):
        return 0xFF if (self.const_ready and self.input.ready()) else 0

    def _f_version(self, de):
        return 0x0022

    # ------------------------------------------------------ BDOS: disk misc
    def _f_reset_disk(self, de):
        self.dma = 0x80
        self.cur_disk = 0
        self.mem[4] = (self.user << 4)
        return 0

    def _f_select(self, de):
        self.cur_disk = de & 0x0F
        self.mem[4] = (self.user << 4) | self.cur_disk
        return 0

    def _f_login_vec(self, de):
        v = 1
        for d in range(1, 16):
            if os.path.isdir(os.path.join(self.dir, chr(65 + d))):
                v |= 1 << d
        return v | (1 << self.cur_disk)

    def _f_cur_disk(self, de):
        return self.cur_disk

    def _f_set_dma(self, de):
        self.dma = de

    def _f_alloc_vec(self, de):
        return self.ALV

    def _f_zero(self, de):
        return 0

    def _f_ro_vec(self, de):
        return 0

    def _f_dpb(self, de):
        return self.DPB

    def _f_user(self, de):
        e = de & 0xFF
        if e == 0xFF:
            return self.user
        self.user = e & 0x0F
        self.mem[4] = (self.user << 4) | self.cur_disk
        return 0

    # ------------------------------------------------------ files: helpers
    def _drive_dir(self, drive):
        if drive == 0:
            return self.dir
        sub = os.path.join(self.dir, chr(65 + drive))
        return sub if os.path.isdir(sub) else self.dir

    def _fcb(self, a):
        m = self.mem
        dr = m[a]
        drive = self.cur_disk if dr == 0 or dr > 16 else dr - 1
        nm = bytes((b & 0x7F) for b in m[a + 1:a + 12]).upper()
        return drive, nm

    def _listdir(self, drive):
        d = self._drive_dir(drive)
        out = []
        try:
            names = sorted(os.listdir(d))
        except OSError:
            return out
        for name in names:
            p = os.path.join(d, name)
            if not os.path.isfile(p):
                continue
            nm = host_to_fcbname(name)
            if nm is not None:
                out.append((nm, p))
        return out

    def _lookup(self, drive, nm):
        key = (drive, nm)
        p = self.path_cache.get(key)
        if p is not None and os.path.isfile(p):
            return p
        for n2, p2 in self._listdir(drive):
            if n2 == nm:
                self.path_cache[key] = p2
                return p2
        self.path_cache.pop(key, None)
        return None

    def _handle(self, path):
        h = self.handles.get(path)
        if h is None:
            try:
                h = open(path, 'r+b', buffering=0)
            except OSError:
                h = open(path, 'rb', buffering=0)
            self.handles[path] = h
        return h

    def _close_path(self, path):
        h = self.handles.pop(path, None)
        if h is not None:
            h.close()

    def _close_all(self):
        for h in list(self.handles.values()):
            try:
                h.close()
            except OSError:
                pass
        self.handles = {}

    def _recs(self, path):
        h = self.handles.get(path)
        size = os.fstat(h.fileno()).st_size if h else os.path.getsize(path)
        return (size + 127) // 128

    @staticmethod
    def _ext_rc(recs, ext_no):
        return max(0, min(128, recs - ext_no * 128))

    def _fcb_rec(self, a):
        m = self.mem
        return (((m[a + 14] & 0x3F) * 32 + (m[a + 12] & 0x1F)) * 128 +
                m[a + 32])

    def _fill_alloc(self, a, rc):
        m = self.mem
        nblk = (rc + 7) // 8
        for i in range(16):
            m[a + 16 + i] = (i + 2) if i < nblk else 0

    def _set_pos(self, a, rec, path):
        m = self.mem
        ext_no = rec >> 7
        m[a + 12] = ext_no & 0x1F
        m[a + 14] = (ext_no >> 5) & 0x3F
        m[a + 32] = rec & 0x7F
        rc = self._ext_rc(self._recs(path), ext_no)
        m[a + 15] = rc
        self._fill_alloc(a, rc)

    def _rand_rec(self, a):
        m = self.mem
        return m[a + 33] | (m[a + 34] << 8), m[a + 35]

    def _read_rec(self, path, rec):
        h = self._handle(path)
        h.seek(rec * 128)
        data = h.read(128) or b''
        if not data:
            return 1
        if len(data) < 128:
            data = data + b'\x1A' * (128 - len(data))
        d = self.dma
        if d + 128 <= 0x10000:
            self.mem[d:d + 128] = data
        else:
            for i in range(128):
                self.mem[(d + i) & 0xFFFF] = data[i]
        return 0

    def _write_rec(self, path, rec):
        h = self._handle(path)
        d = self.dma
        data = bytes(self.mem[(d + i) & 0xFFFF] for i in range(128)) \
            if d + 128 > 0x10000 else bytes(self.mem[d:d + 128])
        h.seek(rec * 128)
        h.write(data)
        return 0

    # ------------------------------------------------------ files: BDOS fns
    def _f_open(self, de):
        m = self.mem
        drive, nm = self._fcb(de)
        if b'?' in nm:
            path = None
            for n2, p2 in self._listdir(drive):
                if _match(nm, n2):
                    path = p2
                    m[de + 1:de + 12] = n2
                    break
        else:
            path = self._lookup(drive, nm)
        if path is None:
            return 0xFF
        try:
            self._handle(path)
        except OSError:
            return 0xFF
        ext_no = (m[de + 14] & 0x3F) * 32 + (m[de + 12] & 0x1F)
        recs = self._recs(path)
        if ext_no > 0 and ext_no * 128 >= recs:
            return 0xFF
        m[de + 13] = 0
        rc = self._ext_rc(recs, ext_no)
        m[de + 15] = rc
        self._fill_alloc(de, rc)
        return 0

    def _f_close(self, de):
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        if path is None:
            return 0xFF
        return 0

    def _dir_entry(self, nm, ext_no, rc):
        nblk = (rc + 7) // 8
        alloc = bytes((i + 2) if i < nblk else 0 for i in range(16))
        return (bytes([self.user]) + nm +
                bytes([ext_no & 0x1F, 0, (ext_no >> 5) & 0x3F, rc]) + alloc)

    def _f_search_first(self, de):
        m = self.mem
        dr = m[de]
        if dr == 0x3F:
            drive = self.cur_disk
            pat = b'?' * 11
            all_ext = True
        else:
            drive, pat = self._fcb(de)
            all_ext = m[de + 12] == 0x3F
        entries = []
        for nm, path in self._listdir(drive):
            if not _match(pat, nm):
                continue
            recs = self._recs(path)
            if all_ext:
                for e in range(max(1, (recs + 127) // 128)):
                    entries.append(self._dir_entry(nm, e, self._ext_rc(recs, e)))
            else:
                entries.append(self._dir_entry(nm, 0, self._ext_rc(recs, 0)))
        self.search_list = entries
        return self._f_search_next(de)

    def _f_search_next(self, de):
        if not self.search_list:
            return 0xFF
        ent = self.search_list.pop(0)
        d = self.dma
        buf = ent + b'\xE5' * 96
        for i in range(128):
            self.mem[(d + i) & 0xFFFF] = buf[i]
        return 0

    def _f_delete(self, de):
        drive, pat = self._fcb(de)
        found = False
        for nm, path in self._listdir(drive):
            if _match(pat, nm):
                self._close_path(path)
                try:
                    os.remove(path)
                    found = True
                except OSError:
                    pass
        self.path_cache = {}
        return 0 if found else 0xFF

    def _f_make(self, de):
        m = self.mem
        drive, nm = self._fcb(de)
        if b'?' in nm or not nm.strip():
            return 0xFF
        path = self._lookup(drive, nm)
        ext_no = (m[de + 14] & 0x3F) * 32 + (m[de + 12] & 0x1F)
        try:
            if path is None:
                path = os.path.join(self._drive_dir(drive), fcbname_to_host(nm))
                open(path, 'wb').close()
                self.path_cache[(drive, nm)] = path
            elif ext_no == 0:
                self._handle(path).truncate(0)
            self._handle(path)
        except OSError:
            return 0xFF
        m[de + 13] = 0
        rc = self._ext_rc(self._recs(path), ext_no)
        m[de + 15] = rc
        self._fill_alloc(de, rc)
        return 0

    def _f_rename(self, de):
        m = self.mem
        drive, nm = self._fcb(de)
        new = bytes((b & 0x7F) for b in m[de + 17:de + 28]).upper()
        path = self._lookup(drive, nm)
        if path is None or b'?' in new:
            return 0xFF
        newpath = os.path.join(os.path.dirname(path), fcbname_to_host(new))
        old = self._lookup(drive, new)
        self._close_path(path)
        if old is not None and old != path:
            self._close_path(old)
            os.remove(old)
        os.rename(path, newpath)
        self.path_cache = {}
        return 0

    def _f_read_seq(self, de):
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        if path is None:
            return 1
        rec = self._fcb_rec(de)
        if rec >= self._recs(path):
            return 1
        rv = self._read_rec(path, rec)
        if rv == 0:
            self._set_pos(de, rec + 1, path)
        return rv

    def _f_write_seq(self, de):
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        if path is None:
            return 1
        rec = self._fcb_rec(de)
        try:
            self._write_rec(path, rec)
        except OSError:
            return 2
        self._set_pos(de, rec + 1, path)
        return 0

    def _f_read_rand(self, de):
        rec, r2 = self._rand_rec(de)
        if r2:
            return 6
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        if path is None:
            return 1
        recs = self._recs(path)
        self._set_pos(de, rec, path)
        if rec >= recs:
            last_ext = (recs - 1) >> 7 if recs else -1
            return 1 if (rec >> 7) <= last_ext else 4
        return self._read_rec(path, rec)

    def _f_write_rand(self, de):
        rec, r2 = self._rand_rec(de)
        if r2:
            return 6
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        if path is None:
            return 1
        try:
            self._write_rec(path, rec)
        except OSError:
            return 2
        self._set_pos(de, rec, path)
        return 0

    def _f_file_size(self, de):
        m = self.mem
        drive, nm = self._fcb(de)
        path = self._lookup(drive, nm)
        recs = self._recs(path) if path else 0
        m[de + 33] = recs & 0xFF
        m[de + 34] = (recs >> 8) & 0xFF
        m[de + 35] = (recs >> 16) & 0xFF
        return 0 if path else 0xFF

    def _f_set_rand(self, de):
        m = self.mem
        rec = self._fcb_rec(de)
        m[de + 33] = rec & 0xFF
        m[de + 34] = (rec >> 8) & 0xFF
        m[de + 35] = (rec >> 16) & 0xFF


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(
        description='Z80 + CP/M 2.2 emulator (Timex FDD3000 memory map)')
    ap.add_argument('--dir', default='.', help='host directory for drive A:')
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--no-echo', action='store_true',
                   help='do not echo console input (default: echo unless stdin is a tty)')
    g.add_argument('--echo', action='store_true', help='always echo console input')
    ap.add_argument('--trace', action='store_true', help='trace BDOS/BIOS calls to stderr')
    ap.add_argument('--trace-instr', action='store_true', help='trace every instruction to stderr')
    ap.add_argument('--max', type=int, default=200000000, help='instruction limit')
    ap.add_argument('--printer', metavar='FILE', help='save LST: output to FILE')
    ap.add_argument('--const-ready', action='store_true',
                    help='console status reports pending input as ready')
    ap.add_argument('--stats', action='store_true', help='print instruction count/speed')
    ap.add_argument('prog')
    ap.add_argument('args', nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)

    prog = a.prog
    if not os.path.exists(prog) and os.path.exists(prog + '.COM'):
        prog += '.COM'
    elif not os.path.exists(prog) and os.path.exists(prog + '.com'):
        prog += '.com'
    if a.no_echo:
        echo = False
    elif a.echo:
        echo = True
    else:
        echo = not sys.stdin.isatty()
    cpm = CPM(directory=a.dir, echo=echo, max_instr=a.max,
              live_output=sys.stdout.buffer, trace=a.trace,
              trace_instr=a.trace_instr, const_ready=a.const_ready,
              input_stream=sys.stdin.buffer)
    res = cpm.run_com(prog, ' '.join(a.args))
    sys.stdout.flush()
    if a.printer:
        with open(a.printer, 'wb') as fh:
            fh.write(res.printer_bytes)
    if a.stats:
        ips = res.instructions / res.elapsed if res.elapsed else 0
        sys.stderr.write('[%s] %d instructions in %.2fs (%.0f instr/s)\n'
                         % (res.exit_reason, res.instructions, res.elapsed, ips))
    if res.exit_reason == 'input exhausted':
        sys.stderr.write('\ncpmemu: stopped - program wanted console input after EOF\n')
    if res.error:
        sys.stderr.write('\ncpmemu: %s\n' % res.error)
        return 2 if res.exit_reason == 'limit' else 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
