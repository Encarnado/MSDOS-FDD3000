"""MS-DOS on the emulated FDD3000 with the Z80 BIOS, against fddos.py.

1. test_dos.py's session on both: each step's screen output must be the
   same byte for byte, and so must the disk afterwards. fddos's clock is
   fixed at 1-1-80 0:00, where the FDD3000's (which has none) starts.
2. Two drives: COPY to B:, DIR B:, and B: write-protected.
3. No drive B: DOS gets an error, and A (Abort) goes back to the prompt.
4. The boot: every machine here starts from the FDD3000 boot ROM, which
   loads the boot sector, which loads the interpreter and BIOS, which load
   DOS. With random RAM at power-on DOS must still boot the same. With the
   interpreter's track unreadable the boot sector gives up (Z80 HALT in
   it); with MSDOS.SYS's track unreadable the BIOS says "Disk boot failure";
   a disk without the system says "Non-System disk".
5. FORMAT.COM: FORMAT B:/S on a blank disk, on both machines (screens and
   the new disk must match), then boot from that disk. FORMAT B: without
   /S over a used disk, a track that does not read back (its clusters
   marked bad), a write-protected disk, and FORMAT A:/S with one drive
   (the disk swapped at the prompt).
6. CPM.COM: CP/M 2.2 programs from the TMX CP/M disk (cpm80ds/ref) run
   natively on the Z80: ASM and LOAD, M80, L80, PIP (typing at its
   prompt), and BDOSTEST.MAC (random records, file size, search,
   rename, BIOS CONOUT), built here with M80 / L80. The same commands
   run under CP/M itself (cpm80ds's emulated FDD3000 with the TMX CBIOS)
   and every file they write must be the same, byte for byte. DOS must
   work after each.
7. MBASIC 5.2 under CPM.COM (BASIC.COM from Resources/Disks/galo-basic.dsk;
   skipped without it): LOAD, SAVE as ASCII and tokenized, a random file
   (OPEN "R", FIELD, PUT, GET, LOF), a sequential one (WRITE #, INPUT #),
   KILL, NAME, FILES, a game of tic-tac-toe, SYSTEM. The same under CP/M;
   the files must be the same and so must FILE.BAS's output.
8. The serial channels (WD2123, modelled by fdd86.WD2123): both set up at
   boot as CBIOS A1.1 sets them; COPY to PRN (channel A) and AUX (channel
   B), COPY from AUX, ^P printer echo, a printer without CTS (DOS waits);
   INT 14h (set up in PC and PS/2 form, send, receive, time-out, status)
   and INT 17h from a small program; PIP to LST: and PUN: and from RDR:
   under CPM.COM, against the same under CP/M with the same model.

Prints the Z80 T-states of each step, now with the console and disk code.

    python3 test_fdd86.py
"""
import datetime as dt
import os
import random
import sys

import fddos
import fdd86
import mkfat
import test_dos
import test_z86
import z86
import fdd
from fdd import Disk


class Clock1980:
    class datetime(dt.datetime):
        @classmethod
        def now(cls):
            return cls(1980, 1, 1)

    class date(dt.date):
        @classmethod
        def today(cls):
            return cls(1980, 1, 1)

    timedelta = dt.timedelta


FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print('  FAIL', what)


def step(m, keys, limit=20_000_000):
    m.limit = limit                     # a step takes at most about 2 M
    mark = len(m.out)
    if keys:
        m.type(keys)
    else:
        m.run()
    return m.out[mark:].decode('latin-1')


def session():
    print('1. test_dos session, FDD3000 (Z80 BIOS) against fddos:')
    fddos.datetime = Clock1980
    ref = fddos.Machine([test_z86.disk()])
    z = fdd86.FDD86([test_z86.disk()])
    ref.boot()
    z.boot()
    for name, keys, want in test_dos.STEPS:
        n0, t0, k0 = z.cycles, z.tstates, len(z.fdc.log)
        a, b = step(ref, keys), step(z, keys)
        check(a == b, '%s: screens differ\n--- fddos\n%s\n--- fdd86\n%s' % (name, a, b))
        got = b.replace('\r\n', '\n')
        check(all(w in got for w in want), '%s: expected %r' % (name, want))
        n, t = z.cycles - n0, z.tstates - t0
        print('  %-8s %7d instr %10d T  %5.2f s at 4 MHz  %3d sectors' % (
            name, n, t, t / 4e6, len(z.fdc.log) - k0))
    check(ref.disks[0].trk == z.disks[0].trk, 'disks differ after the session')
    print('  total    %7d instr %10d T  %5.2f s at 4 MHz' % (z.cycles, z.tstates, z.tstates / 4e6))
    return z


def booted(disks, protect=()):
    m = fdd86.FDD86(disks, protect=protect)
    m.boot()
    step(m, '')
    step(m, '\r\r')
    return m


def two_drives():
    print('2. two drives:')
    b = Disk(40, 1, fill=0xE5, spt=18)
    b.trk = [bytearray(t) for t in test_z86.disk().trk]     # a copy of A:
    m = booted([test_z86.disk(), b])
    out = step(m, 'DIR B:\r')
    check('4 File(s)' in out, 'DIR B:')
    out = step(m, 'COPY EDLIN.COM B:NEW.COM\r')
    check('1 File(s) copied' in out, 'COPY to B:')
    out = step(m, 'DIR B:NEW.COM\r')
    check('NEW      COM' in out, 'DIR B:NEW.COM')
    out = step(m, 'B:NEW B:T.TXT\rQ\rY\r')
    check('New file' in out, 'run NEW.COM (EDLIN) from B: %r' % out)
    print('  DIR B:, COPY to B:, run a program from B: done')
    w = booted([test_z86.disk(), b], protect=(1,))
    out = step(w, 'COPY EDLIN.COM B:NEW2.COM\r')
    check('Write protect error' in out and 'Abort, Retry, Ignore?' in out,
          'write-protected B: %r' % out)
    out = step(w, 'A')
    check('A:' in out, 'abort after write protect')
    print('  write-protected B:, Abort: done')


def no_drive():
    print('3. no drive B:')
    m = booted([test_z86.disk()])
    out = step(m, 'DIR B:\r')
    check('Not ready error reading drive B' in out and 'Abort, Retry, Ignore?' in out,
          'DIR B: with no drive %r' % out)
    print('  ' + out.strip().replace('\r\n', ' | '))
    out = step(m, 'A')
    check(out.rstrip().endswith('A:'), 'abort %r' % out)


def boot():
    print('4. boot:')
    ref = booted([test_z86.disk()])
    junk = fdd86.FDD86([test_z86.disk()])
    rnd = random.Random(86)
    junk.m[:] = bytes(rnd.randrange(256) for _ in range(0x10000))
    junk.boot()
    step(junk, '')
    step(junk, '\r\r')
    check(junk.out == ref.out, 'random RAM: boot screens differ %r' % junk.out)
    a, b = step(ref, 'DIR\r'), step(junk, 'DIR\r')
    check(a == b, 'random RAM: DIR differs %r' % b)
    print('  random RAM at power-on: same boot and DIR')

    d = test_z86.disk()
    d.unformatted.add((1, 0))           # sectors 18-35: in Z86.SYS
    m = fdd86.FDD86([d])
    m.boot()
    step(m, '')
    check(m.stopped is not None and 0x3F00 <= m.stopped < 0x4000 and not m.out,
          'interpreter unreadable: stopped at %r, %r' % (m.stopped, m.out))
    print('  interpreter unreadable: the boot sector stops at %04X' % (m.stopped or 0))

    d = test_z86.disk()
    d.unformatted.add((3, 0))           # sectors 54-71: in MSDOS.SYS
    m = fdd86.FDD86([d])
    m.boot()
    step(m, '')
    check(m.stopped is not None and m.stopped >= 0xD000 and b'Disk boot failure' in m.out,
          'MSDOS.SYS unreadable: stopped at %r, %r' % (m.stopped, m.out))
    print('  MSDOS.SYS unreadable: %r' % m.out.decode().strip())

    m = fdd86.FDD86([mkfat.make([('EDLIN.COM', b'x' * 100)])])
    m.boot()
    step(m, '')
    check(m.stopped is not None and 0x3F00 <= m.stopped < 0x4000 and m.out == b'\r\nNon-System disk\r\n',
          'data disk: %r' % m.out)
    print('  data disk: %r' % m.out.decode().strip())


def sysdisk():
    """test_z86.disk() with FORMAT.COM on it"""
    b = test_z86.B
    files = [(f, open(os.path.join(b, f), 'rb').read()) for f in test_dos.FILES + ['FORMAT.COM']]
    return mkfat.make(files, open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                      open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())


def blank():
    d = Disk(40, 1, fill=0, spt=18)
    d.unformatted.update((t, 0) for t in range(40))
    return d


def formats(m, cmd, answers=' N'):
    """FORMAT cmd, a key at each prompt"""
    out = step(m, cmd + '\r')
    for k in answers:
        out += step(m, k, 100_000_000)
    return out


def format_disk():
    print('5. FORMAT:')
    fddos.datetime = Clock1980
    ref = fddos.Machine([sysdisk(), blank()])
    z = fdd86.FDD86([sysdisk(), blank()])
    ref.boot()
    z.boot()
    for m in (ref, z):
        step(m, '')
        step(m, '\r\r')
    a, b = formats(ref, 'FORMAT B:/S'), formats(z, 'FORMAT B:/S')
    check(a == b, 'FORMAT B:/S: screens differ\n--- fddos\n%s\n--- fdd86\n%s' % (a, b))
    check('Format complete' in b and 'System transferred' in b and
          '22528 bytes used by system' in b and '157696 bytes available on disk' in b,
          'FORMAT B:/S %r' % b)
    check(not z.disks[1].unformatted and ref.disks[1].trk == z.disks[1].trk,
          'FORMAT B:/S: the new disks differ')
    ids = list(z.fdc.formatted.values())
    check(len(ids) == 40 and all([r for c, h, r, n in t] == list(range(18)) for t in ids),
          'FORMAT B:/S: tracks without all 18 sectors')
    out = step(z, 'DIR B:\r')
    check('COMMAND  COM' in out and '1 File(s)' in out, 'DIR B: after FORMAT %r' % out)
    out = step(z, 'CHKDSK B:\r')
    check('17408 bytes in 3 hidden files' in out and '157696 bytes available' in out,
          'CHKDSK B: after FORMAT %r' % out)
    print('  FORMAT B:/S: same screens and new disk as with the Python BIOS')
    new = fdd86.FDD86([z.disks[1]])
    new.boot()
    out = step(new, '') + step(new, '\r\rDIR\r')
    check('MS-DOS version 1.25' in out and 'COMMAND  COM' in out, 'boot the new disk %r' % out)
    print('  the new disk boots')

    used = Disk(40, 1, spt=18)
    used.trk = [bytearray(t) for t in sysdisk().trk]
    m = fdd86.FDD86([sysdisk(), used])
    m.boot()
    step(m, '')
    step(m, '\r\r')
    out = formats(m, 'FORMAT B:')
    check('Format complete' in out and 'System' not in out and
          '180224 bytes available on disk' in out, 'FORMAT B: %r' % out)
    out = step(m, 'DIR B:\r')
    check('File not found' in out, 'DIR B: after FORMAT B: %r' % out)
    print('  FORMAT B: over a used disk: empty')

    m = fdd86.FDD86([sysdisk(), blank()])
    end_track = m.fdc.end_track

    def bad10():                        # track 10 never reads back
        cyl = m.fdc.wtrack[1]
        end_track()
        if cyl == 10:
            m.disks[1].unformatted.add((10, 0))
    m.fdc.end_track = bad10
    m.boot()
    step(m, '')
    step(m, '\r\r')
    out = formats(m, 'FORMAT B:')
    check('6144 bytes in bad sectors' in out and '174080 bytes available' in out,
          'bad track %r' % out)
    out = step(m, 'CHKDSK B:\r')
    check('6144 bytes in bad sectors' in out, 'CHKDSK B: bad track %r' % out)
    print('  track 10 bad: its 6 clusters marked, CHKDSK agrees')

    m = fdd86.FDD86([sysdisk(), blank()])
    end_track1 = m.fdc.end_track

    def bad1():                         # track 1: inside Z86.SYS's clusters
        cyl = m.fdc.wtrack[1]
        end_track1()
        if cyl == 1:
            m.disks[1].unformatted.add((1, 0))
    m.fdc.end_track = bad1
    m.boot()
    step(m, '')
    step(m, '\r\r')
    out = formats(m, 'FORMAT B:/S')
    check('Bad track in the system area' in out and 'System transferred' not in out,
          'FORMAT B:/S over a bad system area %r' % out)
    print('  FORMAT B:/S, track 1 bad: refused, not "System transferred"')

    m = fdd86.FDD86([sysdisk(), blank()])
    m.boot()
    step(m, '')
    step(m, '\r\r')
    formats(m, 'FORMAT B:')
    n = fdd86.FDD86([m.disks[1]])
    n.boot()
    step(n, '')
    check(n.out == b'\r\nNon-System disk\r\n', 'boot FORMAT B: disk %r' % n.out)
    print('  a disk from FORMAT B: says Non-System disk')

    m = fdd86.FDD86([sysdisk(), blank()], protect=(1,))
    m.boot()
    step(m, '')
    step(m, '\r\r')
    out = formats(m, 'FORMAT B:')
    check('Write protect error' in out and 'Format complete' not in out, 'write protect %r' % out)
    print('  write-protected B:: Write protect error')

    m = fdd86.FDD86([sysdisk()])
    m.boot()
    step(m, '')
    step(m, '\r\r')
    out = step(m, 'FORMAT A:/S\r')
    check('Insert new diskette for drive A:' in out, 'FORMAT A:/S %r' % out)
    new = blank()
    m.drives[0].disk = m.disks[0] = new
    out = step(m, ' ', 100_000_000)
    check('System transferred' in out, 'FORMAT A:/S, swapped disk %r' % out)
    step(m, 'N')
    n = fdd86.FDD86([new])
    n.boot()
    out = step(n, '') + step(n, '\r\rDIR\r')
    check('COMMAND  COM' in out and '1 File(s)' in out, 'boot after FORMAT A:/S %r' % out)
    print('  FORMAT A:/S with one drive, disk swapped: boots')


CPMREF = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'cpm80ds', 'ref', 'CPM22A11.DSK')
CPMCMDS = ['ASM TX', 'LOAD TX', 'M80 =CROMLIB', 'PIP|TX2.ASM=TX.AS\x08SM|']
CPMOUT = ['TX.PRN', 'TX.HEX', 'TX.COM', 'CROMLIB.REL', 'TX2.ASM']


def under_cpm(cmds, extra=None, keep=None, wd=None):
    """Run cmds under CP/M 2.2 on cpm80ds's emulated FDD3000, from the
    reference disk (plus extra files; only the files named in keep, if
    given) -> (screen, its files). A command is typed at A> (| = Enter),
    or is (text, keys): keys typed once text has appeared. wd: a
    fdd86.WD2123 to put on the machine."""
    import machine
    d = Disk.load(CPMREF)
    if extra:                           # the directory is written anew
        old = {k[1]: v for k, v in d.files(fdd.A11).items() if keep is None or k[1] in keep}
        d.add_files(fdd.A11, {**old, **extra})
    steps = [c if isinstance(c, tuple) else ('A>', c.replace('|', '\r') + '\r') for c in cmds]
    m = machine.Machine([machine.Drive(40, 1, d)], max_instr=400_000_000)
    if wd:
        wd.attach(m)
    mark = [0]

    def prompt(m):
        if steps and steps[0][0] in m.out[mark[0]:].decode('latin-1'):
            mark[0] = len(m.out)
            m.input += steps.pop(0)[1].encode('latin-1')
    m.on_prompt = prompt
    m.boot()
    try:
        m.run()
    except RuntimeError:
        pass
    return m.out.decode('latin-1'), {k[1]: v for k, v in d.files(fdd.A11).items()}


def bdostest_line(out):
    """The results BDOSTEST prints; directory codes (0-3, CP/M says which
    of the 4 entries of a directory record) as 'ok'."""
    t = out[out.index('BDOSTEST '):].split('END')[0].split()
    for i in (1, 6, 7, 17, 21, 22):           # make, close, open, close, rename, open
        if t[i] in ('00', '01', '02', '03'):
            t[i] = 'ok'
    return ' '.join(t)


def cpm_programs():
    print('6. CPM.COM: CP/M programs on the Z80')
    ref = {k[1]: v for k, v in Disk.load(CPMREF).files(fdd.A11).items()}
    b = test_z86.B
    mac = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'BDOSTEST.MAC'), 'rb').read()
    cpm = open(os.path.join(b, 'CPM.COM'), 'rb').read()
    bad = bytearray(cpm)
    i = bad.find(z86.cpmz80())
    bad[i + 2] ^= 0xFF                  # CPMSYM: NEXT, as if for another Z86.SYS
    files = [('COMMAND.COM', open(os.path.join(b, 'COMMAND.COM'), 'rb').read()), ('CPM.COM', cpm),
             ('BADCPM.COM', bytes(bad)), ('BIG.CPM', bytes(40000))]
    files += [(n + '.CPM', ref[n + '.COM']) for n in ('DUMP', 'ASM', 'LOAD', 'M80', 'L80', 'PIP')]
    files += [(n, ref[n]) for n in ('TX.ASM', 'RX.ASM', 'CROMLIB.MAC')]
    files += [('BDOSTEST.MAC', mac.replace(b'\n', b'\r\n') + b'\x1a')]
    d = mkfat.make(files, open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())
    m = booted([d])
    out = step(m, 'CPM\r')
    check('Usage: CPM program' in out, 'CPM: %r' % out)
    out = step(m, 'CPM NOSUCH\r')
    check('Program not found' in out, 'CPM NOSUCH: %r' % out)
    out = step(m, 'CPM BIG\r')
    check('Program too big' in out, 'CPM BIG: %r' % out)
    out = step(m, 'BADCPM DUMP RX.ASM\r')
    check('CPM.COM does not match Z86.SYS' in out, 'BADCPM: %r' % out)
    cmds = CPMCMDS + ['M80 =BDOSTEST', 'L80 BDOSTEST,BDOSTEST/N/E', 'BDOSTEST']
    screens = {}
    for c in cmds:
        t0 = m.tstates
        out = step(m, 'CPM ' + c.replace('|', '\r') + '\r', limit=200_000_000)
        screens[c] = out
        check(out.rstrip().endswith('A:'), 'CPM %s: back to DOS %r' % (c, out[-200:]))
        print('  CPM %-26s %6.2f s at 4 MHz' % (c.split('|')[0], (m.tstates - t0) / 4e6))
    out = step(m, 'DIR\r')
    check('BDOSTEST COM' in out and 'TX2      ASM' in out, 'DIR after: %r' % out)
    got = mkfat.files(m.disks[0])
    check(got['COMMAND.COM'] == files[0][1], 'COMMAND.COM changed')
    check('22 # END' in screens['BDOSTEST'], 'BDOSTEST: %r' % screens['BDOSTEST'])

    rout, rfiles = under_cpm(cmds[:4] + ['BDOSTEST'], {'BDOSTEST.COM': got['BDOSTEST.COM']})
    for n in CPMOUT:
        check(got.get(n) == rfiles.get(n), '%s differs from CP/M\'s' % n)
    check(bdostest_line(screens['BDOSTEST']) == bdostest_line(rout),
          'BDOSTEST: %r, CP/M %r' % (bdostest_line(screens['BDOSTEST']), bdostest_line(rout)))
    check(got.get('S.DAT') == rfiles.get('S.DAT') and len(got.get('S.DAT', b'')) == 512, 'S.DAT')
    print('  %s and BDOSTEST\'s results: the same as under CP/M' % ', '.join(CPMOUT))
    print('  ' + bdostest_line(screens['BDOSTEST']))


GALO = os.path.expanduser('~/Claude/Resources/Disks/galo-basic.dsk')
FILEBAS = (b'10 OPEN "R",1,"R.DAT",32: FIELD 1,32 AS A$\r\n'
           b'20 FOR I=1 TO 5: LSET A$="REC"+STR$(I): PUT 1,I: NEXT\r\n'
           b'30 GET 1,3: PRINT A$: PRINT LOF(1): CLOSE 1\r\n'
           b'40 OPEN "O",1,"S.TXT": WRITE #1,"HELLO",42: CLOSE: OPEN "I",1,"S.TXT": INPUT #1,X$,N: PRINT X$;N: CLOSE\r\n'
           b'50 KILL "S.TXT": NAME "R.DAT" AS "Q.DAT": FILES "*.DAT"\r\n\x1a')


def mbasic():
    print('7. MBASIC under CPM.COM')
    if not os.path.exists(GALO):
        print('  skipped: no %s' % GALO)
        return
    g = {k[1]: v for k, v in Disk.load(GALO).files(fdd.A11).items()}
    b = test_z86.B
    files = [(f, open(os.path.join(b, f), 'rb').read()) for f in ('COMMAND.COM', 'CPM.COM')]
    files += [('MBASIC.CPM', g['BASIC.COM']), ('TTT.BAS', g['TTT.BAS']), ('FILE.BAS', FILEBAS)]
    d = mkfat.make(files, open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())
    m = booted([d])
    keys = ['CPM MBASIC\r', 'LOAD "TTT"\r', 'SAVE "T2",A\r', 'SAVE "T3"\r', 'RUN "FILE"\r',
            'RUN "TTT"\r', '1\r', '4\r', '2\r', '5\r', '3\r', 'N\r', 'SYSTEM\r']
    outs = []
    for k in keys:
        t0 = m.tstates
        outs.append(step(m, k, limit=200_000_000))
        if k in keys[:5]:
            print('  %-16s %5.2f s at 4 MHz' % (k.strip(), (m.tstates - t0) / 4e6))
    check('Bytes free' in outs[0], 'MBASIC: %r' % outs[0])
    check('PLAYER X WINS!' in outs[10] and 'THANKS FOR PLAYING' in outs[11], 'TTT: %r' % outs[10:12])
    check(outs[-1].rstrip().endswith('A:'), 'SYSTEM: %r' % outs[-1])
    got = mkfat.files(m.disks[0])
    cm = [('A>', 'BASIC\r')] + [('Ok', k) for k in keys[1:5]] + [('Ok', 'SYSTEM\r')]
    rout, rfiles = under_cpm(cm, {'BASIC.COM': g['BASIC.COM'], 'TTT.BAS': g['TTT.BAS'], 'FILE.BAS': FILEBAS},
                             keep=())
    for n in ('T2.BAS', 'T3.BAS', 'Q.DAT'):
        check(got.get(n) is not None and got.get(n) == rfiles.get(n), '%s differs from CP/M\'s' % n)
    lines = lambda o: [l.strip() for l in o.replace('\r', '').split('\n')[1:] if l.strip() and l.strip() != 'Ok']
    ours, theirs = lines(outs[4]), lines(rout.split('RUN "FILE"')[1].split('Ok')[0])
    check(ours == theirs, 'RUN "FILE": %r, CP/M %r' % (ours, theirs))
    print('  T2.BAS, T3.BAS, Q.DAT and FILE.BAS\'s output: the same as under CP/M')
    print('  ' + ' | '.join(ours))


def main():
    session()
    two_drives()
    no_drive()
    boot()
    format_disk()
    cpm_programs()
    mbasic()
    serial()
    mode()
    print('FAILED: %d' % len(FAILS) if FAILS else 'all ok')
    sys.exit(1 if FAILS else 0)


def int14_prog():
    """A .COM that calls INT 14h and INT 17h and keeps AX after each call
    behind 'SERRES': COM1 set up as 9600 8N1 (AH=0, AL=E3h), send 'X',
    status; COM2 set up as 19200 7E2 (AH=4); receive twice (the second
    times out); INT 17h print 'P', status."""
    calls = [
        bytes([0xB8, 0xE3, 0x00, 0xBA, 0x00, 0x00, 0xCD, 0x14]),         # AX=00E3 DX=0
        bytes([0xB8, 0x58, 0x01, 0xCD, 0x14]),                           # AX=0158
        bytes([0xB4, 0x03, 0xCD, 0x14]),                                 # AH=3
        bytes([0xB8, 0x00, 0x04, 0xBB, 0x01, 0x02, 0xB9, 0x08, 0x02,     # AH=4 BX=0201
               0xBA, 0x01, 0x00, 0xCD, 0x14]),                           #   CX=0208 DX=1
        bytes([0xB4, 0x02, 0xCD, 0x14]),                                 # AH=2
        bytes([0xB4, 0x02, 0xCD, 0x14]),                                 # AH=2
        bytes([0xB8, 0x50, 0x00, 0xCD, 0x17]),                           # INT 17h AH=0 'P'
        bytes([0xB4, 0x02, 0xCD, 0x17]),                                 # INT 17h AH=2
    ]
    body = b''.join(c + b'\xAB' for c in calls) + b'\xCD\x20'          # STOSW after each
    res = 0x100 + 4 + len(body) + 6                                     # CLD, MOV DI,res
    return b'\xFC\xBF' + res.to_bytes(2, 'little') + body + b'SERRES' + b'\xEE' * 16


def int14_results(m):
    mem = bytes(m.m)
    i = -1
    while True:
        i = mem.find(b'SERRES', i + 1)
        if i < 0:
            return None
        r = mem[i + 6:i + 22]
        if r != b'\xEE' * 16:
            return [int.from_bytes(r[k:k + 2], 'little') for k in range(0, 16, 2)]


def serial():
    print('8. serial channels (WD2123)')
    b = test_z86.B
    files = [('COMMAND.COM', open(os.path.join(b, 'COMMAND.COM'), 'rb').read()),
             ('CPM.COM', open(os.path.join(b, 'CPM.COM'), 'rb').read()),
             ('T.TXT', b'Hello printer\r\nline 2\r\n\x1a'), ('SER.COM', int14_prog())]
    have_cpm = os.path.exists(CPMREF)
    if have_cpm:
        ref = {k[1]: v for k, v in Disk.load(CPMREF).files(fdd.A11).items()}
        files.append(('PIP.CPM', ref['PIP.COM']))
    d = mkfat.make(files, open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())
    m = booted([d])
    A, B = m.wd2123.a, m.wd2123.b
    check((A.mode, A.baud, A.cmd, B.mode, B.baud, B.cmd, A.dropped + B.dropped) == (0x8E, 8, 7, 0x8E, 8, 7, 0),
          'boot set-up: A %s %s %s, B %s %s %s' % (A.mode, A.baud, A.cmd, B.mode, B.baud, B.cmd))
    out = step(m, 'COPY T.TXT PRN\r')
    check('1 File(s) copied' in out and bytes(A.tx) == b'Hello printer\r\nline 2\r\n', 'COPY to PRN: %r' % bytes(A.tx))
    out = step(m, 'COPY T.TXT AUX\r')
    check(bytes(B.tx) == b'Hello printer\r\nline 2\r\n\x1a', 'COPY to AUX: %r' % bytes(B.tx))
    B.rx += b'from aux\r\n\x1a'
    step(m, 'COPY AUX R.TXT\r')
    check(mkfat.files(d).get('R.TXT') == b'from aux\r\n\x1a', 'COPY from AUX: %r' % mkfat.files(d).get('R.TXT'))
    A.tx.clear()
    step(m, '\x10DIR\r')                # ^P echo on, ^N off (DOS 1.25)
    step(m, '\x0e')
    check(bytes(A.tx).startswith(b'DIR\r\nCOMMAND  COM') and bytes(A.tx).endswith(b'A:'),
          '^P echo: %r' % bytes(A.tx)[-40:])
    print('  set up at boot; COPY to PRN, to AUX, from AUX; ^P echo: done')
    A.tx.clear()
    A.cts = False                       # the printer is off: DOS waits for it
    try:
        out = step(m, 'COPY T.TXT PRN\r', limit=3_000_000)
    except RuntimeError:                # the instruction limit: still waiting
        out = m.out.decode('latin-1')
    check(not A.tx and not out.endswith('A:'), 'no CTS: sent %r, %r' % (bytes(A.tx), out[-20:]))
    A.cts = True
    out = step(m, '')
    check(bytes(A.tx) == b'Hello printer\r\nline 2\r\n' and out.endswith('A:'), 'CTS back: %r' % bytes(A.tx))
    print('  printer without CTS: DOS waits, then prints: done')
    A.tx.clear()
    B.rx[:] = b'Q'
    step(m, 'SER\r', limit=60_000_000)
    r = int14_results(m)
    want = [0x6030, 0x6058, 0x6030, 0x6130, 0x6051, 0xE000, 0x9050, 0x9050]
    check(r == want, 'INT 14h / 17h: %s, want %s' % (r and ['%04X' % v for v in r], ['%04X' % v for v in want]))
    check((A.mode, A.baud, B.mode, B.baud) == (0x4E, 14, 0xFA, 15) and bytes(A.tx) == b'XP',
          'INT 14h set-up and output: A %02X %d B %02X %d %r' % (A.mode, A.baud, B.mode, B.baud, bytes(A.tx)))
    A.cts = False
    B.rx[:] = b'Q'
    step(m, 'SER\r', limit=60_000_000)
    r = int14_results(m)
    want = [0x6020, 0xE058, 0x6020, 0x6130, 0x6051, 0xE000, 0x1150, 0x1050]
    check(r == want, 'INT 14h / 17h without CTS: %s, want %s' % (r and ['%04X' % v for v in r], ['%04X' % v for v in want]))
    A.cts = True
    print('  INT 14h (AH 0-4, time-outs), INT 17h (ready, busy, time-out): done')
    if not have_cpm:
        print('  (no %s: CP/M devices skipped)' % CPMREF)
        return
    text = b''.join(b'%03d The quick brown fox\r\n' % i for i in range(40)) + b'\x1a'
    feed = b'Read from the reader\r\nsecond line\r\n\x1a'
    cmds = ['PIP LST:=T.TXT', 'PIP PUN:=T.TXT', 'PIP R.TXT=RDR:']
    wd = fdd86.WD2123()
    wd.b.rx += feed
    _, cf = under_cpm(cmds, extra={'T.TXT': text}, keep={'PIP.COM'}, wd=wd)
    d = mkfat.make([f for f in files if f[0] != 'T.TXT'] + [('T.TXT', text)], open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())
    m = booted([d])
    m.wd2123.b.rx += feed
    for c in cmds:
        step(m, 'CPM ' + c + '\r', limit=200_000_000)
    df = mkfat.files(d)
    check(bytes(m.wd2123.a.tx) == bytes(wd.a.tx) and len(wd.a.tx) >= 1000,
          'PIP LST: %d bytes, CP/M %d' % (len(m.wd2123.a.tx), len(wd.a.tx)))
    check(bytes(m.wd2123.b.tx) == bytes(wd.b.tx) and len(wd.b.tx) >= 1000,
          'PIP PUN: %d bytes, CP/M %d' % (len(m.wd2123.b.tx), len(wd.b.tx)))
    check(df.get('R.TXT') == cf.get('R.TXT') and cf.get('R.TXT', b'').startswith(feed[:-1]),
          'PIP R.TXT=RDR: %r, CP/M %r' % (df.get('R.TXT', b'')[:40], cf.get('R.TXT', b'')[:40]))
    print('  CPM PIP LST:, PUN:, RDR: the same bytes as under CP/M: done')


def mode():
    print('9. MODE.COM')
    b = test_z86.B
    files = [(f, open(os.path.join(b, f), 'rb').read()) for f in ('COMMAND.COM', 'MODE.COM')]
    files.append(('T.TXT', b'Hello printer\r\n\x1a'))
    d = mkfat.make(files, open(os.path.join(b, 'IOFDD.SYS'), 'rb').read(),
                   open(os.path.join(b, 'MSDOS.SYS'), 'rb').read())
    m = booted([d])
    A, B = m.wd2123.a, m.wd2123.b
    boot = 'PRN: 1200 baud, no parity, 8 data bits, 1.5 stop bits\r\n' \
           'AUX: 1200 baud, no parity, 8 data bits, 1.5 stop bits\r\n'
    out = step(m, 'MODE\r')
    check(boot in out, 'MODE: %r' % out)
    # command, the channel's mode byte and baud code after it, MODE's line
    for cmd, ch, mb, bc, line in (
            ('MODE PRN:9600,N,8,1', A, 0x4E, 14, 'PRN: 9600 baud, no parity, 8 data bits, 1 stop bit\r\n'),
            ('mode aux 19200,e,7,2', B, 0xFA, 15, 'AUX: 19200 baud, even parity, 7 data bits, 2 stop bits\r\n'),
            ('MODE COM1:,O', A, 0x5E, 14, 'PRN: 9600 baud, odd parity, 8 data bits, 1 stop bit\r\n'),
            ('MODE LPT1: 134.5 , , 5 , 1.5', A, 0x92, 3, 'PRN: 134.5 baud, odd parity, 5 data bits, 1.5 stop bits\r\n'),
            ('MODE COM2:11', B, 0xFA, 2, 'AUX: 110 baud, even parity, 7 data bits, 2 stop bits\r\n'),
            ('MODE AUX:50,N,6,1', B, 0x46, 0, 'AUX: 50 baud, no parity, 6 data bits, 1 stop bit\r\n'),
            ('MODE PRN:', A, 0x92, 3, 'PRN: 134.5 baud, odd parity, 5 data bits, 1.5 stop bits\r\n'),
            # a comma after the port closes the (empty) baud field: parity only
            ('MODE PRN,E', A, 0xB2, 3, 'PRN: 134.5 baud, even parity, 5 data bits, 1.5 stop bits\r\n')):
        out = step(m, cmd + '\r')
        check((ch.mode, ch.baud, ch.cmd) == (mb, bc, 7) and line in out and 'Invalid' not in out,
              '%s: mode %02X baud %d cmd %02X, %r' % (cmd, ch.mode, ch.baud, ch.cmd, out))
    check(A.dropped + B.dropped == 0, 'writes the WD2123 model did not expect: %d' % (A.dropped + B.dropped))
    print('  ports, all fields, fields left out, PC baud names, settings shown: done')
    state = (A.mode, A.baud, B.mode, B.baud)
    for cmd in ('MODE COM3', 'MODE PRN 9601', 'MODE PRN 9600,X', 'MODE PRN 9600,N,9', 'MODE PRN 9600,N,8,3',
                'MODE PRN 9600,N,8,1,1', 'MODE PRN 9600,N,8,1.4', 'MODE PRNTR', 'MODE PRN 1234567',
                'MODE PRN,,E'):          # E in the data bits field
        out = step(m, cmd + '\r')
        check('Invalid parameter' in out and 'Usage: MODE' in out and (A.mode, A.baud, B.mode, B.baud) == state,
              '%s: %r' % (cmd, out[-80:]))
    print('  bad parameters: usage, nothing changed: done')
    step(m, 'MODE PRN:9600,N,8,1\r')
    A.tx.clear()
    step(m, 'COPY T.TXT PRN\r')
    check(bytes(A.tx) == b'Hello printer\r\n', 'COPY to PRN after MODE: %r' % bytes(A.tx))
    print('  PRN after MODE: done')


if __name__ == '__main__':
    main()
