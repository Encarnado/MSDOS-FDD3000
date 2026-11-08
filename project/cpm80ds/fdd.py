"""FDD3000 disk images for the 80-track CBIOS: DSK files and CP/M layouts.

A Disk holds cyls x sides tracks of spt sectors of 256 bytes, sector IDs
0 to spt-1: 16 (4 KB tracks) for CP/M and TOS, 18 for the MS-DOS disks of
../MSDOS (and some Timex disks, PFile and Gestin, have 17 or 18).
Logical CP/M track t is cylinder t // sides, side t % sides (TOS 80DS order),
which is also the order of the track records in a DSK file.
"""
import struct

SKEW_5 = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11]


class Layout:
    def __init__(self, name, tracks, off, bls, dsm, drm):
        self.name, self.tracks, self.off, self.bls, self.dsm, self.drm = name, tracks, off, bls, dsm, drm
        self.skew = SKEW_5
        self.big = dsm > 255                      # 16-bit block numbers in AL
        self.exm = (bls // 1024 if not self.big else bls // 2048) - 1
        self.ndirb = ((drm + 1) * 32 + bls - 1) // bls

    def block_sectors(self, b):
        """(logical track, sector ID) of each 256-byte sector of block b, in order."""
        spb = self.bls // 256
        bpt = 4096 // self.bls
        t = self.off + b // bpt
        return [(t, self.skew[(b % bpt) * spb + i]) for i in range(spb)]


A11 = Layout('CBIOS A1.1', 40, 2, 1024, 151, 63)
DS80 = Layout('CBIOS A1.1 80-track 2-sided', 160, 2, 2048, 315, 127)


class Disk:
    def __init__(self, cyls=80, sides=2, fill=0xE5, spt=16):
        self.cyls, self.sides, self.spt = cyls, sides, spt
        self.trk = [bytearray([fill]) * (spt * 256) for _ in range(cyls * sides)]
        self.unformatted = set()            # (cyl, side) with no sector IDs

    @property
    def tracks(self):
        return self.cyls * self.sides

    # ---- physical access: (cylinder, side, sector ID) ----
    def sector(self, c, h, r):
        t = self.trk[c * self.sides + h]
        return t[r * 256:r * 256 + 256]

    def set_sector(self, c, h, r, data):
        assert len(data) == 256
        self.trk[c * self.sides + h][r * 256:r * 256 + 256] = data

    # ---- logical access ----
    def lsector(self, t, r):
        return bytes(self.trk[t][r * 256:r * 256 + 256])

    def set_lsector(self, t, r, data):
        self.trk[t][r * 256:r * 256 + 256] = data

    def set_system(self, img):
        """8 KB of system tracks, sector-ID order, onto logical tracks 0-1."""
        assert len(img) == 8192
        self.trk[0][:] = img[:4096]
        self.trk[1][:] = img[4096:]

    def system(self):
        return bytes(self.trk[0] + self.trk[1])

    # ---- CP/M files (to build test disks and check results) ----
    def read_block(self, lay, b):
        return b''.join(self.lsector(t, r) for t, r in lay.block_sectors(b))

    def write_block(self, lay, b, data):
        data = data.ljust(lay.bls, b'\xE5')
        for i, (t, r) in enumerate(lay.block_sectors(b)):
            self.set_lsector(t, r, data[i * 256:i * 256 + 256])

    def dir_entries(self, lay):
        d = b''.join(self.read_block(lay, b) for b in range(lay.ndirb))
        return [d[i * 32:i * 32 + 32] for i in range(lay.drm + 1)]

    @staticmethod
    def al(lay, e):
        if lay.big:
            return [b for b in struct.unpack('<8H', e[16:32]) if b]
        return [b for b in e[16:32] if b]

    def files(self, lay):
        """{(user, 'NAME.EXT'): bytes} of every live file, whole records."""
        ext = {}
        for e in self.dir_entries(lay):
            if e[0] > 15:
                continue
            name = (e[1:9].decode('latin-1').rstrip() + '.' +
                    bytes(c & 0x7F for c in e[9:12]).decode('latin-1').rstrip())
            exn = (e[12] & 0x1F) + 32 * (e[14] & 0x3F)
            ext.setdefault((e[0], name), []).append((exn, e))
        out = {}
        for key, es in ext.items():
            es.sort()
            data = b''
            for exn, e in es:
                recs = (exn & lay.exm) * 128 + e[15]
                blk = b''.join(self.read_block(lay, b) for b in self.al(lay, e))
                data += blk[:recs * 128]
            out[key] = data
        return out

    def add_files(self, lay, files):
        """Write {'NAME.EXT': bytes} (user 0) into an empty directory, blocks
        in order after the directory. One entry per 16 KB (EXM is 0)."""
        ents, b = [], lay.ndirb
        per = 16 if not lay.big else 8               # block numbers per entry
        for name, data in files.items():
            base, _, ext = name.upper().partition('.')
            fn = base.ljust(8).encode() + ext.ljust(3).encode()
            data = data + b'\x1a' * (-len(data) % 128)
            n = 0
            while True:
                chunk = data[n * 16384:(n + 1) * 16384]
                recs = len(chunk) // 128
                blocks = []
                for i in range(0, len(chunk), lay.bls):
                    self.write_block(lay, b, chunk[i:i + lay.bls])
                    blocks.append(b)
                    b += 1
                assert b - 1 <= lay.dsm, 'disk full'
                if lay.big:
                    al = struct.pack('<8H', *(blocks + [0] * (8 - len(blocks))))
                else:
                    al = bytes(blocks + [0] * (16 - len(blocks)))
                ents.append(bytes([0]) + fn + bytes([n & 0x1F, 0, n >> 5, recs]) + al)
                n += 1
                if (n * 16384) >= len(data):
                    break
        assert len(ents) <= lay.drm + 1, 'directory full'
        d = b''.join(ents).ljust(lay.ndirb * lay.bls, b'\xE5')
        for i in range(lay.ndirb):
            self.write_block(lay, i, d[i * lay.bls:(i + 1) * lay.bls])

    # ---- DSK files ----
    def save(self, path, edsk=True):
        hdr = bytearray(256)
        hdr[:34] = (b'EXTENDED CPC DSK File\r\nDisk-Info\r\n' if edsk
                    else b'MV - CPCEMU Disk-File\r\nDisk-Info\r\n')
        hdr[34:48] = b'cpm80ds fdd.py'
        hdr[48], hdr[49] = self.cyls, self.sides
        if edsk:
            for i in range(self.tracks):
                hdr[52 + i] = self.spt + 1
        else:
            hdr[50:52] = struct.pack('<H', (self.spt + 1) * 256)
        out = bytearray(hdr)
        for c in range(self.cyls):
            for h in range(self.sides):
                th = bytearray(256)
                th[:13] = b'Track-Info\r\n\x00'
                th[16], th[17] = c, h
                th[20], th[21], th[22], th[23] = 1, self.spt, 0x2A, 0xE5
                for r in range(self.spt):
                    th[24 + 8 * r:32 + 8 * r] = struct.pack('<BBBBBBH', c, h, r, 1, 0, 0, 256)
                out += th + self.trk[c * self.sides + h]
        open(path, 'wb').write(out)

    @classmethod
    def load(cls, path):
        d = open(path, 'rb').read()
        ext = d[:8] == b'EXTENDED'
        assert ext or d[:8] == b'MV - CPC', path
        cyls, sides = d[48], d[49]
        tracks, o = [], 256
        for i in range(cyls * sides):
            tsz = d[52 + i] * 256 if ext else d[50] | d[51] << 8
            assert d[o:o + 10] == b'Track-Info', (path, i)
            n = d[o + 21]
            p, secs = o + 256, []
            for k in range(n):
                c, h, r, sz, s1, s2, ln = struct.unpack('<BBBBBBH', d[o + 24 + 8 * k:o + 32 + 8 * k])
                ln = ln if ext else 128 << sz
                if ln >= 256:
                    secs.append((r, d[p:p + 256]))
                p += ln
            tracks.append(secs)
            o += tsz
        # 18 sectors (IDs 0-17) if any track has them, else the usual 16
        spt = 18 if any(r in (16, 17) for t in tracks for r, _ in t) else 16
        disk = cls(cyls, sides, spt=spt)
        for i, secs in enumerate(tracks):
            for r, data in secs:
                if r < spt:
                    disk.trk[i][r * 256:r * 256 + 256] = data
        return disk
