#!/usr/bin/env python3
"""Convert a flat binary to a $readmemh file: one little-endian 32-bit word per line."""
import struct, sys
d = open(sys.argv[1], 'rb').read()
d += b'\0' * (-len(d) % 4)
with open(sys.argv[2], 'w') as f:
    for (w,) in struct.iter_unpack('<I', d):
        f.write('%08x\n' % w)
