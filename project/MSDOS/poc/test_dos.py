"""Boot MS-DOS 1.25 on the FDD3000 model and run commands; prints the 8086
instruction count of each step (the Z80 interpreter's workload).

    python3 test_dos.py
"""
import os
import sys

import fddos
import mkfat

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, 'build')
FILES = ['COMMAND.COM', 'EDLIN.COM', 'DEBUG.COM', 'CHKDSK.COM']

STEPS = [
    ('boot', '', ['MS-DOS version 1.25', 'Enter new date:']),
    ('date', '\r', ['Enter new time:']),
    ('time', '\r', ['A:']),
    ('DIR', 'DIR\r', ['COMMAND  COM     4879', '4 File(s)']),
    ('CHKDSK', 'CHKDSK\r', ['180224 bytes total disk space', '17408 bytes in 3 hidden files',
                            '52128 bytes total memory']),
    ('COPY', 'COPY EDLIN.COM ED2.COM\r', ['1 File(s) copied']),
    ('EDLIN', 'EDLIN HELLO.TXT\rI\rHello from MS-DOS\ron the Timex FDD3000\r\x1a\rE\r', ['New file']),
    ('TYPE', 'TYPE HELLO.TXT\r', ['Hello from MS-DOS\non the Timex FDD3000']),
    # DEBUG: enter MOV AH,2 / MOV DL,'!' / INT 21 / INT 20 at 100 and run it
    ('DEBUG', 'DEBUG\rE 100 B4 02 B2 21 CD 21 CD 20\rG\rQ\r', ['!\nProgram terminated normally']),
    ('REN+DEL', 'REN ED2.COM ED3.COM\rDEL ED3.COM\rDIR\r', ['HELLO    TXT', '5 File(s)']),
]


def main():
    io_sys = open(os.path.join(B, 'IOFDD.SYS'), 'rb').read()
    dos_sys = open(os.path.join(B, 'MSDOS.SYS'), 'rb').read()
    files = [(f, open(os.path.join(B, f), 'rb').read()) for f in FILES]
    m = fddos.Machine([mkfat.make(files, io_sys, dos_sys)])
    m.boot()
    ok = True
    for name, keys, want in STEPS:
        mark = len(m.out)
        n0 = m.cpu.cycles
        if keys:
            m.type(keys)
        else:
            m.run()
        got = m.out[mark:].decode('latin-1').replace('\r\n', '\n')
        bad = [w for w in want if w not in got]
        ok &= not bad
        print('%-8s %9d instr  %s' % (name, m.cpu.cycles - n0, 'ok' if not bad else 'FAIL %r' % bad))
        if bad:
            print(got)
    print('total    %9d instr' % m.cpu.cycles)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
