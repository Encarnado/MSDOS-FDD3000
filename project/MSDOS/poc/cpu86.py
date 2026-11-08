"""Intel 8086 interpreter (real mode, 1 MB), reference model for the FDD3000 port.

Registers: r[0..7] = AX CX DX BX SP BP SI DI, s[0..3] = ES CS SS DS.
Opcode 0Fh (POP CS on the 8086, never used by real code) is the BIOS trap:
0F nn calls self.trap(nn). INT n first asks self.int_hook(n); if it returns
True the interrupt is handled in Python, otherwise it goes through the
vector table like a real 8086.
"""

ES, CS, SS, DS = 0, 1, 2, 3
AX, CX, DX, BX, SP, BP, SI, DI = range(8)

PARITY = bytes(1 if bin(i).count('1') % 2 == 0 else 0 for i in range(256))


class Halt(Exception):
    pass


class CPU:
    def __init__(self, mem=None):
        self.mem = mem if mem is not None else bytearray(0x100000)
        self.r = [0] * 8
        self.s = [0] * 4
        self.ip = 0
        self.cf = self.pf = self.af = self.zf = self.sf = 0
        self.tf = self.if_ = self.df = self.of = 0
        self.seg = None          # segment override for the current instruction
        self.halted = False
        self.cycles = 0          # instructions executed
        self.int_hook = lambda n: False
        self.trap = self._no_trap
        self.port_in = lambda port, w: 0xFFFF if w else 0xFF
        self.port_out = lambda port, v, w: None
        self.ops = [self.op_bad] * 256
        self._build()

    def _no_trap(self, n):
        raise Halt('trap %02X at %04X:%04X' % (n, self.s[CS], self.ip))

    # ---------------- memory ----------------
    def rb(self, seg, off):
        return self.mem[((seg << 4) + (off & 0xFFFF)) & 0xFFFFF]

    def rw(self, seg, off):
        b = seg << 4
        m = self.mem
        return m[(b + (off & 0xFFFF)) & 0xFFFFF] | m[(b + ((off + 1) & 0xFFFF)) & 0xFFFFF] << 8

    def wb(self, seg, off, v):
        self.mem[((seg << 4) + (off & 0xFFFF)) & 0xFFFFF] = v & 0xFF

    def ww(self, seg, off, v):
        b = seg << 4
        self.mem[(b + (off & 0xFFFF)) & 0xFFFFF] = v & 0xFF
        self.mem[(b + ((off + 1) & 0xFFFF)) & 0xFFFFF] = (v >> 8) & 0xFF

    def fetchb(self):
        v = self.mem[((self.s[CS] << 4) + self.ip) & 0xFFFFF]
        self.ip = (self.ip + 1) & 0xFFFF
        return v

    def fetchw(self):
        v = self.rw(self.s[CS], self.ip)
        self.ip = (self.ip + 2) & 0xFFFF
        return v

    def fetchsb(self):
        v = self.fetchb()
        return v - 256 if v & 0x80 else v

    def push(self, v):
        self.r[SP] = (self.r[SP] - 2) & 0xFFFF
        self.ww(self.s[SS], self.r[SP], v)

    def pop(self):
        v = self.rw(self.s[SS], self.r[SP])
        self.r[SP] = (self.r[SP] + 2) & 0xFFFF
        return v

    # ---------------- registers ----------------
    def getr8(self, i):
        return (self.r[i & 3] >> 8) & 0xFF if i & 4 else self.r[i] & 0xFF

    def setr8(self, i, v):
        if i & 4:
            self.r[i & 3] = (self.r[i & 3] & 0x00FF) | ((v & 0xFF) << 8)
        else:
            self.r[i] = (self.r[i] & 0xFF00) | (v & 0xFF)

    @property
    def flags(self):
        return (0xF002 | self.cf | self.pf << 2 | self.af << 4 | self.zf << 6 | self.sf << 7 |
                self.tf << 8 | self.if_ << 9 | self.df << 10 | self.of << 11)

    @flags.setter
    def flags(self, v):
        self.cf, self.pf, self.af = v & 1, (v >> 2) & 1, (v >> 4) & 1
        self.zf, self.sf, self.tf = (v >> 6) & 1, (v >> 7) & 1, (v >> 8) & 1
        self.if_, self.df, self.of = (v >> 9) & 1, (v >> 10) & 1, (v >> 11) & 1

    # ---------------- ModR/M ----------------
    def modrm(self):
        """Decode ModR/M. Returns (reg, mod, rm, seg, off); seg/off valid if mod != 3."""
        b = self.fetchb()
        mod, reg, rm = b >> 6, (b >> 3) & 7, b & 7
        if mod == 3:
            return reg, 3, rm, 0, 0
        r = self.r
        dseg = DS
        if rm == 0:
            off = r[BX] + r[SI]
        elif rm == 1:
            off = r[BX] + r[DI]
        elif rm == 2:
            off = r[BP] + r[SI]; dseg = SS
        elif rm == 3:
            off = r[BP] + r[DI]; dseg = SS
        elif rm == 4:
            off = r[SI]
        elif rm == 5:
            off = r[DI]
        elif rm == 6:
            if mod == 0:
                off = 0
            else:
                off = r[BP]; dseg = SS
        else:
            off = r[BX]
        if mod == 0:
            if rm == 6:
                off = self.fetchw()
        elif mod == 1:
            off += self.fetchsb()
        else:
            off += self.fetchw()
        seg = self.s[self.seg] if self.seg is not None else self.s[dseg]
        return reg, mod, rm, seg, off & 0xFFFF

    def get_rm(self, m, w):
        reg, mod, rm, seg, off = m
        if mod == 3:
            return self.r[rm] if w else self.getr8(rm)
        return self.rw(seg, off) if w else self.rb(seg, off)

    def set_rm(self, m, w, v):
        reg, mod, rm, seg, off = m
        if mod == 3:
            if w:
                self.r[rm] = v & 0xFFFF
            else:
                self.setr8(rm, v)
        elif w:
            self.ww(seg, off, v)
        else:
            self.wb(seg, off, v)

    # ---------------- flags helpers ----------------
    def szp(self, v, w):
        self.zf = 1 if v == 0 else 0
        self.sf = (v >> (15 if w else 7)) & 1
        self.pf = PARITY[v & 0xFF]

    def alu(self, op, a, b, w):
        mask = 0xFFFF if w else 0xFF
        top = 0x8000 if w else 0x80
        if op == 0 or op == 2:              # ADD / ADC
            c = self.cf if op == 2 else 0
            res = a + b + c
            self.cf = 1 if res > mask else 0
            res &= mask
            self.of = 1 if (~(a ^ b) & (a ^ res) & top) else 0
            self.af = ((a ^ b ^ res) >> 4) & 1
        elif op == 3 or op == 5 or op == 7:  # SBB / SUB / CMP
            c = self.cf if op == 3 else 0
            res = a - b - c
            self.cf = 1 if res < 0 else 0
            res &= mask
            self.of = 1 if ((a ^ b) & (a ^ res) & top) else 0
            self.af = ((a ^ b ^ res) >> 4) & 1
        else:
            if op == 1:
                res = a | b
            elif op == 4:
                res = a & b
            else:
                res = a ^ b
            self.cf = self.of = 0
            self.af = 0
        self.szp(res, w)
        return res

    # ---------------- execution ----------------
    def step(self):
        self.seg = None
        self.rep = 0
        op = self.fetchb()
        while True:
            if op in (0x26, 0x2E, 0x36, 0x3E):
                self.seg = (op >> 3) & 3
            elif op == 0xF2 or op == 0xF3:
                self.rep = op
            elif op != 0xF0:
                break
            op = self.fetchb()
        self.cycles += 1
        self.ops[op](op)

    def run(self, n=None):
        if n is None:
            while not self.halted:
                self.step()
        else:
            for _ in range(n):
                if self.halted:
                    break
                self.step()

    def interrupt(self, n):
        if self.int_hook(n):
            return
        self.push(self.flags)
        self.if_ = self.tf = 0
        self.push(self.s[CS])
        self.push(self.ip)
        self.ip = self.rw(0, n * 4)
        self.s[CS] = self.rw(0, n * 4 + 2)

    def op_bad(self, op):
        raise Halt('bad opcode %02X at %04X:%04X' % (op, self.s[CS], (self.ip - 1) & 0xFFFF))

    def _build(self):
        o = self.ops
        for i in range(0x40):
            if i & 7 < 6:
                o[i] = self.op_alu
        for i in (0x06, 0x0E, 0x16, 0x1E):
            o[i] = self.op_push_seg
        for i in (0x07, 0x17, 0x1F):
            o[i] = self.op_pop_seg
        o[0x0F] = self.op_trap
        o[0x27] = self.op_daa
        o[0x2F] = self.op_das
        o[0x37] = self.op_aaa
        o[0x3F] = self.op_aas
        for i in range(0x40, 0x60):
            o[i] = self.op_incdec_push_pop_r
        for i in range(0x60, 0x80):
            o[i] = self.op_jcc
        for i in range(0x80, 0x84):
            o[i] = self.op_grp1
        o[0x84] = o[0x85] = self.op_test_rm
        o[0x86] = o[0x87] = self.op_xchg_rm
        for i in range(0x88, 0x8C):
            o[i] = self.op_mov_rm
        o[0x8C] = self.op_mov_rm_sreg
        o[0x8D] = self.op_lea
        o[0x8E] = self.op_mov_sreg_rm
        o[0x8F] = self.op_pop_rm
        for i in range(0x90, 0x98):
            o[i] = self.op_xchg_ax
        o[0x98] = self.op_cbw
        o[0x99] = self.op_cwd
        o[0x9A] = self.op_call_far
        o[0x9B] = lambda op: None
        o[0x9C] = lambda op: self.push(self.flags)
        o[0x9D] = self.op_popf
        o[0x9E] = self.op_sahf
        o[0x9F] = self.op_lahf
        for i in range(0xA0, 0xA4):
            o[i] = self.op_mov_moffs
        for i in range(0xA4, 0xB0):
            o[i] = self.op_string
        o[0xA8] = o[0xA9] = self.op_test_acc
        for i in range(0xB0, 0xC0):
            o[i] = self.op_mov_imm_r
        o[0xC0] = o[0xC2] = self.op_ret_imm
        o[0xC1] = o[0xC3] = self.op_ret
        o[0xC4] = o[0xC5] = self.op_lxs
        o[0xC6] = o[0xC7] = self.op_mov_rm_imm
        o[0xC8] = o[0xCA] = self.op_retf_imm
        o[0xC9] = o[0xCB] = self.op_retf
        o[0xCC] = lambda op: self.interrupt(3)
        o[0xCD] = lambda op: self.interrupt(self.fetchb())
        o[0xCE] = lambda op: self.interrupt(4) if self.of else None
        o[0xCF] = self.op_iret
        for i in range(0xD0, 0xD4):
            o[i] = self.op_shift
        o[0xD4] = self.op_aam
        o[0xD5] = self.op_aad
        o[0xD6] = self.op_salc
        o[0xD7] = self.op_xlat
        for i in range(0xD8, 0xE0):
            o[i] = self.op_esc
        for i in range(0xE0, 0xE4):
            o[i] = self.op_loop
        for i in (0xE4, 0xE5, 0xEC, 0xED):
            o[i] = self.op_in
        for i in (0xE6, 0xE7, 0xEE, 0xEF):
            o[i] = self.op_out
        o[0xE8] = self.op_call
        o[0xE9] = self.op_jmp
        o[0xEA] = self.op_jmp_far
        o[0xEB] = self.op_jmp_short
        o[0xF4] = self.op_hlt
        o[0xF5] = self.op_cmc
        o[0xF6] = o[0xF7] = self.op_grp3
        o[0xF8] = self.op_flagop
        for i in range(0xF8, 0xFE):
            o[i] = self.op_flagop
        o[0xFE] = o[0xFF] = self.op_grp45

    # ---- 00-3F ----
    def op_alu(self, op):
        alu_op = op >> 3
        kind = op & 7
        w = op & 1
        if kind < 4:
            m = self.modrm()
            reg = m[0]
            rv = self.r[reg] if w else self.getr8(reg)
            mv = self.get_rm(m, w)
            if kind & 2:     # reg, rm
                res = self.alu(alu_op, rv, mv, w)
                if alu_op != 7:
                    if w:
                        self.r[reg] = res
                    else:
                        self.setr8(reg, res)
            else:            # rm, reg
                res = self.alu(alu_op, mv, rv, w)
                if alu_op != 7:
                    self.set_rm(m, w, res)
        else:
            if w:
                res = self.alu(alu_op, self.r[AX], self.fetchw(), 1)
                if alu_op != 7:
                    self.r[AX] = res
            else:
                res = self.alu(alu_op, self.r[AX] & 0xFF, self.fetchb(), 0)
                if alu_op != 7:
                    self.setr8(0, res)

    def op_push_seg(self, op):
        self.push(self.s[(op >> 3) & 3])

    def op_pop_seg(self, op):
        self.s[(op >> 3) & 3] = self.pop()

    def op_trap(self, op):
        self.trap(self.fetchb())

    def op_daa(self, op):
        al = self.r[AX] & 0xFF
        old_al, old_cf = al, self.cf
        if (al & 0xF) > 9 or self.af:
            al += 6
            self.af = 1
        else:
            self.af = 0
        if old_al > 0x99 or old_cf:
            al += 0x60
            self.cf = 1
        else:
            self.cf = 0
        al &= 0xFF
        self.setr8(0, al)
        self.szp(al, 0)

    def op_das(self, op):
        al = self.r[AX] & 0xFF
        old_al, old_cf = al, self.cf
        if (al & 0xF) > 9 or self.af:
            al -= 6
            self.af = 1
        else:
            self.af = 0
        if old_al > 0x99 or old_cf:
            al -= 0x60
            self.cf = 1
        else:
            self.cf = 0
        al &= 0xFF
        self.setr8(0, al)
        self.szp(al, 0)

    def op_aaa(self, op):
        ax = self.r[AX]
        if (ax & 0xF) > 9 or self.af:
            ax = (ax + 0x106) & 0xFFFF
            self.af = self.cf = 1
        else:
            self.af = self.cf = 0
        self.r[AX] = ax & 0xFF0F

    def op_aas(self, op):
        ax = self.r[AX]
        if (ax & 0xF) > 9 or self.af:
            al = ((ax & 0xFF) - 6) & 0xFF
            ah = ((ax >> 8) - 1) & 0xFF
            ax = ah << 8 | al
            self.af = self.cf = 1
        else:
            self.af = self.cf = 0
        self.r[AX] = ax & 0xFF0F

    # ---- 40-5F ----
    def op_incdec_push_pop_r(self, op):
        i = op & 7
        k = op >> 3
        if k == 8:       # INC
            v = self.r[i]
            res = (v + 1) & 0xFFFF
            self.of = 1 if v == 0x7FFF else 0
            self.af = ((v ^ 1 ^ res) >> 4) & 1
            self.szp(res, 1)
            self.r[i] = res
        elif k == 9:     # DEC
            v = self.r[i]
            res = (v - 1) & 0xFFFF
            self.of = 1 if v == 0x8000 else 0
            self.af = ((v ^ 1 ^ res) >> 4) & 1
            self.szp(res, 1)
            self.r[i] = res
        elif k == 10:    # PUSH (PUSH SP pushes the new value on the 8086)
            if i == SP:
                self.r[SP] = (self.r[SP] - 2) & 0xFFFF
                self.ww(self.s[SS], self.r[SP], self.r[SP])
            else:
                self.push(self.r[i])
        else:            # POP
            v = self.pop()
            self.r[i] = v

    # ---- 70-7F ----
    def cond(self, c):
        k = c >> 1
        if k == 0:
            v = self.of
        elif k == 1:
            v = self.cf
        elif k == 2:
            v = self.zf
        elif k == 3:
            v = self.cf | self.zf
        elif k == 4:
            v = self.sf
        elif k == 5:
            v = self.pf
        elif k == 6:
            v = self.sf ^ self.of
        else:
            v = (self.sf ^ self.of) | self.zf
        return v ^ (c & 1)

    def op_jcc(self, op):
        d = self.fetchsb()
        if self.cond(op & 0xF):
            self.ip = (self.ip + d) & 0xFFFF

    # ---- 80-8F ----
    def op_grp1(self, op):
        w = op & 1
        m = self.modrm()
        a = self.get_rm(m, w)
        if op == 0x81:
            b = self.fetchw()
        elif op == 0x83:
            b = self.fetchsb() & 0xFFFF
        else:
            b = self.fetchb()
        res = self.alu(m[0], a, b, w)
        if m[0] != 7:
            self.set_rm(m, w, res)

    def op_test_rm(self, op):
        w = op & 1
        m = self.modrm()
        rv = self.r[m[0]] if w else self.getr8(m[0])
        self.alu(4, self.get_rm(m, w), rv, w)

    def op_xchg_rm(self, op):
        w = op & 1
        m = self.modrm()
        rv = self.r[m[0]] if w else self.getr8(m[0])
        mv = self.get_rm(m, w)
        self.set_rm(m, w, rv)
        if w:
            self.r[m[0]] = mv
        else:
            self.setr8(m[0], mv)

    def op_mov_rm(self, op):
        w = op & 1
        m = self.modrm()
        if op & 2:
            v = self.get_rm(m, w)
            if w:
                self.r[m[0]] = v
            else:
                self.setr8(m[0], v)
        else:
            self.set_rm(m, w, self.r[m[0]] if w else self.getr8(m[0]))

    def op_mov_rm_sreg(self, op):
        m = self.modrm()
        self.set_rm(m, 1, self.s[m[0] & 3])

    def op_lea(self, op):
        m = self.modrm()
        self.r[m[0]] = m[4]

    def op_mov_sreg_rm(self, op):
        m = self.modrm()
        self.s[m[0] & 3] = self.get_rm(m, 1)

    def op_pop_rm(self, op):
        # the address uses SP after the pop
        sp = self.r[SP]
        v = self.pop()
        m = self.modrm()
        self.set_rm(m, 1, v)

    # ---- 90-9F ----
    def op_xchg_ax(self, op):
        i = op & 7
        self.r[AX], self.r[i] = self.r[i], self.r[AX]

    def op_cbw(self, op):
        al = self.r[AX] & 0xFF
        self.r[AX] = al | (0xFF00 if al & 0x80 else 0)

    def op_cwd(self, op):
        self.r[DX] = 0xFFFF if self.r[AX] & 0x8000 else 0

    def op_call_far(self, op):
        ip = self.fetchw()
        cs = self.fetchw()
        self.push(self.s[CS])
        self.push(self.ip)
        self.ip, self.s[CS] = ip, cs

    def op_popf(self, op):
        self.flags = self.pop()

    def op_sahf(self, op):
        ah = self.r[AX] >> 8
        self.flags = (self.flags & 0xFF00) | ah

    def op_lahf(self, op):
        self.setr8(4, self.flags & 0xD5 | 2)

    # ---- A0-AF ----
    def op_mov_moffs(self, op):
        off = self.fetchw()
        seg = self.s[self.seg if self.seg is not None else DS]
        if op == 0xA0:
            self.setr8(0, self.rb(seg, off))
        elif op == 0xA1:
            self.r[AX] = self.rw(seg, off)
        elif op == 0xA2:
            self.wb(seg, off, self.r[AX])
        else:
            self.ww(seg, off, self.r[AX])

    def op_test_acc(self, op):
        if op & 1:
            self.alu(4, self.r[AX], self.fetchw(), 1)
        else:
            self.alu(4, self.r[AX] & 0xFF, self.fetchb(), 0)

    def op_string(self, op):
        w = op & 1
        kind = op & 0xFE
        r = self.r
        n = 2 if w else 1
        d = -n if self.df else n
        sseg = self.s[self.seg if self.seg is not None else DS]
        es = self.s[ES]
        rep = self.rep
        if rep:
            if r[CX] == 0:
                return
        while True:
            if kind == 0xA4:       # MOVS
                if w:
                    self.ww(es, r[DI], self.rw(sseg, r[SI]))
                else:
                    self.wb(es, r[DI], self.rb(sseg, r[SI]))
                r[SI] = (r[SI] + d) & 0xFFFF
                r[DI] = (r[DI] + d) & 0xFFFF
            elif kind == 0xA6:     # CMPS
                a = self.rw(sseg, r[SI]) if w else self.rb(sseg, r[SI])
                b = self.rw(es, r[DI]) if w else self.rb(es, r[DI])
                self.alu(7, a, b, w)
                r[SI] = (r[SI] + d) & 0xFFFF
                r[DI] = (r[DI] + d) & 0xFFFF
            elif kind == 0xAA:     # STOS
                if w:
                    self.ww(es, r[DI], r[AX])
                else:
                    self.wb(es, r[DI], r[AX])
                r[DI] = (r[DI] + d) & 0xFFFF
            elif kind == 0xAC:     # LODS
                if w:
                    r[AX] = self.rw(sseg, r[SI])
                else:
                    self.setr8(0, self.rb(sseg, r[SI]))
                r[SI] = (r[SI] + d) & 0xFFFF
            else:                  # SCAS
                b = self.rw(es, r[DI]) if w else self.rb(es, r[DI])
                self.alu(7, r[AX] if w else r[AX] & 0xFF, b, w)
                r[DI] = (r[DI] + d) & 0xFFFF
            if not rep:
                return
            r[CX] = (r[CX] - 1) & 0xFFFF
            if r[CX] == 0:
                return
            if kind == 0xA6 or kind == 0xAE:
                if rep == 0xF3 and not self.zf:
                    return
                if rep == 0xF2 and self.zf:
                    return

    # ---- B0-BF ----
    def op_mov_imm_r(self, op):
        if op & 8:
            self.r[op & 7] = self.fetchw()
        else:
            self.setr8(op & 7, self.fetchb())

    # ---- C0-CF ----
    def op_ret_imm(self, op):
        n = self.fetchw()
        self.ip = self.pop()
        self.r[SP] = (self.r[SP] + n) & 0xFFFF

    def op_ret(self, op):
        self.ip = self.pop()

    def op_retf_imm(self, op):
        n = self.fetchw()
        self.ip = self.pop()
        self.s[CS] = self.pop()
        self.r[SP] = (self.r[SP] + n) & 0xFFFF

    def op_retf(self, op):
        self.ip = self.pop()
        self.s[CS] = self.pop()

    def op_lxs(self, op):
        m = self.modrm()
        self.r[m[0]] = self.rw(m[3], m[4])
        self.s[ES if op == 0xC4 else DS] = self.rw(m[3], m[4] + 2)

    def op_mov_rm_imm(self, op):
        w = op & 1
        m = self.modrm()
        self.set_rm(m, w, self.fetchw() if w else self.fetchb())

    def op_iret(self, op):
        self.ip = self.pop()
        self.s[CS] = self.pop()
        self.flags = self.pop()

    # ---- D0-DF ----
    def op_shift(self, op):
        w = op & 1
        m = self.modrm()
        n = (self.r[CX] & 0xFF) if op & 2 else 1
        if n == 0:
            return
        v = self.get_rm(m, w)
        bits = 16 if w else 8
        mask = (1 << bits) - 1
        top = bits - 1
        k = m[0]
        cf = self.cf
        for _ in range(n):
            if k == 0:      # ROL
                cf = (v >> top) & 1
                v = ((v << 1) | cf) & mask
            elif k == 1:    # ROR
                cf = v & 1
                v = (v >> 1) | (cf << top)
            elif k == 2:    # RCL
                nc = (v >> top) & 1
                v = ((v << 1) | cf) & mask
                cf = nc
            elif k == 3:    # RCR
                nc = v & 1
                v = (v >> 1) | (cf << top)
                cf = nc
            elif k == 4 or k == 6:  # SHL/SAL
                cf = (v >> top) & 1
                v = (v << 1) & mask
            elif k == 5:    # SHR
                cf = v & 1
                v >>= 1
            else:           # SAR
                cf = v & 1
                v = (v >> 1) | (v & (1 << top))
        self.cf = cf
        msb = (v >> top) & 1
        if k == 0 or k == 2 or k >= 4 and k != 5 and k != 7:
            self.of = msb ^ cf
        elif k == 1 or k == 3:
            self.of = msb ^ ((v >> (top - 1)) & 1)
        elif k == 5:
            self.of = (self.get_rm(m, w) >> top) & 1 if n == 1 else 0
        else:
            self.of = 0
        if k >= 4:
            self.szp(v, w)
            self.af = 0
        self.set_rm(m, w, v)

    def op_aam(self, op):
        base = self.fetchb()
        if base == 0:
            self.interrupt(0)
            return
        al = self.r[AX] & 0xFF
        ah, al = divmod(al, base)
        self.r[AX] = ah << 8 | al
        self.szp(al, 0)

    def op_aad(self, op):
        base = self.fetchb()
        ax = self.r[AX]
        al = ((ax >> 8) * base + (ax & 0xFF)) & 0xFF
        self.r[AX] = al
        self.szp(al, 0)

    def op_salc(self, op):
        self.setr8(0, 0xFF if self.cf else 0)

    def op_xlat(self, op):
        seg = self.s[self.seg if self.seg is not None else DS]
        self.setr8(0, self.rb(seg, self.r[BX] + (self.r[AX] & 0xFF)))

    def op_esc(self, op):
        self.modrm()

    # ---- E0-EF ----
    def op_loop(self, op):
        d = self.fetchsb()
        if op == 0xE3:
            if self.r[CX] == 0:
                self.ip = (self.ip + d) & 0xFFFF
            return
        cx = self.r[CX] = (self.r[CX] - 1) & 0xFFFF
        if cx == 0:
            return
        if op == 0xE2 or (op == 0xE1 and self.zf) or (op == 0xE0 and not self.zf):
            self.ip = (self.ip + d) & 0xFFFF

    def op_in(self, op):
        port = self.fetchb() if op < 0xE8 else self.r[DX]
        w = op & 1
        v = self.port_in(port, w)
        if w:
            self.r[AX] = v & 0xFFFF
        else:
            self.setr8(0, v)

    def op_out(self, op):
        port = self.fetchb() if op < 0xE8 else self.r[DX]
        w = op & 1
        self.port_out(port, self.r[AX] if w else self.r[AX] & 0xFF, w)

    def op_call(self, op):
        d = self.fetchw()
        self.push(self.ip)
        self.ip = (self.ip + d) & 0xFFFF

    def op_jmp(self, op):
        d = self.fetchw()
        self.ip = (self.ip + d) & 0xFFFF

    def op_jmp_far(self, op):
        ip = self.fetchw()
        self.s[CS] = self.fetchw()
        self.ip = ip

    def op_jmp_short(self, op):
        d = self.fetchsb()
        self.ip = (self.ip + d) & 0xFFFF

    # ---- F0-FF ----
    def op_hlt(self, op):
        self.halted = True

    def op_cmc(self, op):
        self.cf ^= 1

    def op_flagop(self, op):
        if op == 0xF8:
            self.cf = 0
        elif op == 0xF9:
            self.cf = 1
        elif op == 0xFA:
            self.if_ = 0
        elif op == 0xFB:
            self.if_ = 1
        elif op == 0xFC:
            self.df = 0
        else:
            self.df = 1

    def op_grp3(self, op):
        w = op & 1
        m = self.modrm()
        k = m[0]
        v = self.get_rm(m, w)
        if k == 0 or k == 1:      # TEST imm
            self.alu(4, v, self.fetchw() if w else self.fetchb(), w)
        elif k == 2:              # NOT
            self.set_rm(m, w, ~v)
        elif k == 3:              # NEG
            res = self.alu(5, 0, v, w)
            self.cf = 1 if v else 0
            self.set_rm(m, w, res)
        elif k == 4:              # MUL
            if w:
                res = (self.r[AX]) * v
                self.r[AX] = res & 0xFFFF
                self.r[DX] = res >> 16
                self.cf = self.of = 1 if self.r[DX] else 0
            else:
                res = (self.r[AX] & 0xFF) * v
                self.r[AX] = res
                self.cf = self.of = 1 if res & 0xFF00 else 0
        elif k == 5:              # IMUL
            if w:
                a = self.r[AX] - 0x10000 if self.r[AX] & 0x8000 else self.r[AX]
                b = v - 0x10000 if v & 0x8000 else v
                res = (a * b) & 0xFFFFFFFF
                self.r[AX] = res & 0xFFFF
                self.r[DX] = res >> 16
                lo = res & 0xFFFF
                ext = 0xFFFF if lo & 0x8000 else 0
                self.cf = self.of = 0 if self.r[DX] == ext else 1
            else:
                al = self.r[AX] & 0xFF
                a = al - 256 if al & 0x80 else al
                b = v - 256 if v & 0x80 else v
                res = (a * b) & 0xFFFF
                self.r[AX] = res
                ext = 0xFF if res & 0x80 else 0
                self.cf = self.of = 0 if (res >> 8) == ext else 1
        elif k == 6:              # DIV
            if v == 0:
                self.interrupt(0)
                return
            if w:
                num = self.r[DX] << 16 | self.r[AX]
                q, rem = divmod(num, v)
                if q > 0xFFFF:
                    self.interrupt(0)
                    return
                self.r[AX], self.r[DX] = q, rem
            else:
                num = self.r[AX]
                q, rem = divmod(num, v)
                if q > 0xFF:
                    self.interrupt(0)
                    return
                self.r[AX] = rem << 8 | q
        else:                     # IDIV
            if v == 0:
                self.interrupt(0)
                return
            if w:
                num = self.r[DX] << 16 | self.r[AX]
                if num & 0x80000000:
                    num -= 0x100000000
                d = v - 0x10000 if v & 0x8000 else v
                q = abs(num) // abs(d)
                if (num < 0) != (d < 0):
                    q = -q
                rem = num - q * d
                if q > 0x7FFF or q < -0x8000:
                    self.interrupt(0)
                    return
                self.r[AX], self.r[DX] = q & 0xFFFF, rem & 0xFFFF
            else:
                num = self.r[AX]
                if num & 0x8000:
                    num -= 0x10000
                d = v - 256 if v & 0x80 else v
                q = abs(num) // abs(d)
                if (num < 0) != (d < 0):
                    q = -q
                rem = num - q * d
                if q > 0x7F or q < -0x80:
                    self.interrupt(0)
                    return
                self.r[AX] = (rem & 0xFF) << 8 | (q & 0xFF)

    def op_grp45(self, op):
        w = op & 1
        m = self.modrm()
        k = m[0]
        if k == 0 or k == 1:      # INC / DEC
            v = self.get_rm(m, w)
            mask = 0xFFFF if w else 0xFF
            if k == 0:
                res = (v + 1) & mask
                self.of = 1 if v == (mask >> 1) else 0
            else:
                res = (v - 1) & mask
                self.of = 1 if v == (mask >> 1) + 1 else 0
            self.af = ((v ^ 1 ^ res) >> 4) & 1
            self.szp(res, w)
            self.set_rm(m, w, res)
        elif k == 2:              # CALL rm
            t = self.get_rm(m, 1)
            self.push(self.ip)
            self.ip = t
        elif k == 3:              # CALL far m
            ip, cs = self.rw(m[3], m[4]), self.rw(m[3], m[4] + 2)
            self.push(self.s[CS])
            self.push(self.ip)
            self.ip, self.s[CS] = ip, cs
        elif k == 4:              # JMP rm
            self.ip = self.get_rm(m, 1)
        elif k == 5:              # JMP far m
            self.ip, self.s[CS] = self.rw(m[3], m[4]), self.rw(m[3], m[4] + 2)
        else:                     # PUSH rm
            self.push(self.get_rm(m, 1))
