#!/usr/bin/env python3
"""
Convert a standard "MV - CPCEMU" DSK image to EXTENDED CPC DSK, in place.

WHY: WinAPE does not write standard DSKs back faithfully -- on the first sector
write it re-saves the file as an Extended DSK containing ONLY the modified
track, discarding every other track (this destroyed the game disc: after F1
saved to track 40, the file shrank from 204544 to 5120 bytes and TERRA.BIN was
gone).  Feeding WinAPE an Extended DSK from the start avoids the lossy
conversion: it updates the image in place and every track survives.

Usage: python3 tools/dsk2ext.py build/terracpc.dsk
"""
import sys

def convert(path):
    d = open(path, "rb").read()
    if d[:8] == b"EXTENDED":
        print("%s: already extended (%d bytes)" % (path, len(d)))
        return
    assert d[:8] == b"MV - CPC", "not a standard DSK: %r" % d[:16]
    ntrk = d[0x30]
    nside = d[0x31]
    tsize = d[0x32] | (d[0x33] << 8)     # uniform track size incl. Track-Info
    assert nside == 1, "single-sided images only"
    assert 256 + ntrk * tsize <= len(d), "truncated DSK"

    # extended disc header: track-size TABLE (1 byte/track = size/256) at 0x34
    hdr = bytearray(256)
    hdr[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    hdr[0x22:0x30] = b"dsk2ext       "[:14]
    hdr[0x30] = ntrk
    hdr[0x31] = nside
    # 0x32-33 unused in extended format
    for t in range(ntrk):
        hdr[0x34 + t] = tsize >> 8       # e.g. 4864/256 = 19

    out = bytearray(hdr)
    for t in range(ntrk):
        blk = bytearray(d[256 + t * tsize: 256 + (t + 1) * tsize])
        assert blk[:10] == b"Track-Info", "track %d: bad Track-Info" % t
        nsec = blk[0x15]
        for i in range(nsec):            # extended: per-sector actual length
            e = 0x18 + i * 8
            n = blk[e + 3]
            blk[e + 6] = 0               # len = 128 << N
            blk[e + 7] = (128 << n) >> 8
        out += blk

    open(path, "wb").write(out)
    print("%s: standard -> extended, %d tracks, %d bytes" % (path, ntrk, len(out)))

if __name__ == "__main__":
    convert(sys.argv[1] if len(sys.argv) > 1 else "build/terracpc.dsk")
