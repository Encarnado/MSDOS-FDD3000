"""Make an MS-DOS 1.25 disk for the FDD3000: FAT12 on 40 x 18 x 256-byte sectors.

Layout (logical sectors, 18 per track, 2:1 interleave inside a track):
    0       boot sector (BOOT.ASM)
    1-2     FAT 1         3-4   FAT 2
    5-12    directory (64 entries)
    13-716  clusters of 4 sectors (1 KB), clusters 2..177 (717-719 unused)

A system disk has three hidden files first, each contiguous from the
first cluster on, as the boot sector and COLD (BIOS.ASM) read them:
    Z86.SYS     the 8086 interpreter and BIOS (Z80 code, loaded at D000h)
    IO.SYS      loaded at 0040:0000
    MSDOS.SYS   loaded at 0060:0000
FORMAT /S writes them the same way.

    python3 mkfat.py OUT.DSK [FILE ...]          a system disk
    python3 mkfat.py --nosys OUT.DSK [FILE ...]  a data disk
"""
import os
import sys

import z86
from fddos import chs, fdd, SPT, FIRDIR, FIRREC

HERE = os.path.dirname(os.path.abspath(__file__))
SECTORS, RESERVED, NFAT, FATSECS, DIRSECS, SPC = 720, 1, 2, 2, 8, 4
assert FIRDIR == RESERVED + NFAT * FATSECS and FIRREC == FIRDIR + DIRSECS
MAXCLUS = (SECTORS - FIRREC) // SPC + 1        # last cluster number: 177
HIDDEN = 0x06                                  # hidden, system


def put(disk, lsec, data):
    for i in range(0, len(data), 256):
        disk.set_lsector(*chs(disk, lsec + i // 256), data[i:i + 256].ljust(256, b'\0'))


def make(files, io_sys=None, dos_sys=None):
    """files: [(name, data)]. With io_sys and dos_sys: a system disk."""
    disk = fdd.Disk(40, 1, fill=0xE5, spt=SPT)
    ipl, z86_sys = z86.bootcode()
    put(disk, 0, ipl)
    entries = []
    if io_sys is not None:
        assert len(io_sys) <= 512, 'IO.SYS must end before MSDOS.SYS at 0600h'
        entries = [('Z86.SYS', z86_sys, HIDDEN), ('IO.SYS', io_sys, HIDDEN),
                   ('MSDOS.SYS', dos_sys, HIDDEN)]
    entries += [(name, data, 0) for name, data in files]
    fat = [0xFFE, 0xFFF] + [0] * (MAXCLUS - 1)
    dirent = bytearray()
    clus = 2
    for name, data, attr in entries:
        base, _, ext = os.path.basename(name).upper().partition('.')
        n = (len(data) + SPC * 256 - 1) // (SPC * 256)
        first = clus if n else 0
        for k in range(n):
            put(disk, FIRREC + (clus - 2) * SPC, data[k * SPC * 256:(k + 1) * SPC * 256].ljust(SPC * 256, b'\0'))
            fat[clus] = clus + 1 if k < n - 1 else 0xFFF
            clus += 1
        assert clus - 1 <= MAXCLUS, 'disk full'
        dirent += (base.ljust(8) + ext.ljust(3)).encode() + bytes([attr]) + bytes(10)
        dirent += (0).to_bytes(2, 'little') + (0).to_bytes(2, 'little')   # time, date
        dirent += first.to_bytes(2, 'little') + len(data).to_bytes(4, 'little')
    assert len(dirent) <= DIRSECS * 256, 'directory full'
    raw = bytearray()
    for i in range(0, len(fat), 2):
        a = fat[i]
        b = fat[i + 1] if i + 1 < len(fat) else 0
        raw += bytes([a & 0xFF, (a >> 8) | ((b & 0xF) << 4), b >> 4])
    raw = bytes(raw[:FATSECS * 256]).ljust(FATSECS * 256, b'\0')
    for k in range(NFAT):
        put(disk, RESERVED + k * FATSECS, raw)
    put(disk, FIRDIR, bytes(dirent).ljust(DIRSECS * 256, b'\0'))
    for s in range(FIRREC + (clus - 2) * SPC, SECTORS):
        disk.set_lsector(*chs(disk, s), b'\xE5' * 256)
    return disk


def files(disk):
    """-> {'NAME.EXT': bytes} of the files on a disk (hidden ones too)."""
    get = lambda lsec: disk.lsector(*chs(disk, lsec))
    raw = b''.join(get(RESERVED + k) for k in range(FATSECS))
    fat = lambda c: (raw[c * 3 // 2] | raw[c * 3 // 2 + 1] << 8) >> (4 if c & 1 else 0) & 0xFFF
    d = b''.join(get(FIRDIR + k) for k in range(DIRSECS))
    out = {}
    for i in range(0, len(d), 32):
        e = d[i:i + 32]
        if e[0] == 0:
            break
        if e[0] == 0xE5:
            continue
        name = e[:8].decode().rstrip() + ('.' + e[8:11].decode().rstrip() if e[8:11].strip() else '')
        size, c, data = int.from_bytes(e[28:32], 'little'), int.from_bytes(e[26:28], 'little'), b''
        while 2 <= c <= MAXCLUS and len(data) < size:
            data += b''.join(get(FIRREC + (c - 2) * SPC + k) for k in range(SPC))
            c = fat(c)
        out[name] = data[:size]
    return out


def main():
    args = sys.argv[1:]
    nosys = '--nosys' in args
    args = [a for a in args if a != '--nosys']
    out = args[0]
    build = os.path.join(HERE, 'build')
    files = [(f, open(f, 'rb').read()) for f in args[1:]]
    if nosys:
        disk = make(files)
    else:
        disk = make(files, open(os.path.join(build, 'IOFDD.SYS'), 'rb').read(),
                    open(os.path.join(build, 'MSDOS.SYS'), 'rb').read())
    disk.save(out)
    print('%s: %d files, clusters 2-%d' % (out, len(files), MAXCLUS))


if __name__ == '__main__':
    main()
