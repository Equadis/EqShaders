"""Dump a BLP1 texture from the client's MPQs to a PNG and print its header.
usage: python -I blp_dump.py <mpq> <path inside the archive> <out.png>
Handles BLP1 palettised (compression 1, alpha 0/1/4/8 bits); prints the header for other kinds."""
import sys, struct, zlib
sys.path.insert(0, r"D:\Octowow\EqAmbience\tools")
from mpq import MPQ


def png(path, w, h, rgba):
    raw = b"".join(b"\0" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def ch(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


def main():
    mpq, name, out = sys.argv[1:4]
    d = MPQ(mpq).read(name)
    magic = d[:4]
    if magic == b"BLP2":
        # BLP2: type u32, encoding u8 (1 palette, 2 DXT), alphaDepth u8, alphaEncoding u8, hasMips u8, w u32, h u32, offsets[16], sizes[16], palette
        typ, enc, abits, aenc, hasmips, w, h = struct.unpack_from("<IBBBBII", d, 4)
        offs = struct.unpack_from("<16I", d, 20)
        sizes = struct.unpack_from("<16I", d, 84)
        print(name, magic, "type", typ, "encoding", enc, "(1 palette, 2 DXT)", "alphaDepth", abits, "alphaEncoding", aenc, "size", w, h,
              "mips", sum(1 for s in sizes if s), "bytes", len(d))
        if enc != 1:
            return
        pal = d[148:148 + 1024]
    else:
        comp, abits, w, h, pt, pst = struct.unpack_from("<IIIIII", d, 4)
        offs = struct.unpack_from("<16I", d, 28)
        sizes = struct.unpack_from("<16I", d, 92)
        print(name, magic, "compression", comp, "alphaBits", abits, "size", w, h, "picType", pt, "mips", sum(1 for s in sizes if s), "bytes", len(d))
        if magic != b"BLP1" or comp != 1:
            return
        pal = d[156:156 + 1024]
    o = offs[0]
    idx = d[o:o + w * h]
    al = d[o + w * h:o + w * h + ((w * h * abits + 7) // 8)]
    rgba = bytearray()
    for i in range(w * h):
        b, g, r, _ = pal[idx[i] * 4:idx[i] * 4 + 4]
        a = 255
        if abits == 1:
            a = 255 if (al[i >> 3] >> (i & 7)) & 1 else 0
        elif abits == 8:
            a = al[i]
        elif abits == 4:
            a = ((al[i >> 1] >> (4 * (i & 1))) & 15) * 17
        rgba += bytes((r, g, b, a))
    png(out, w, h, rgba)
    print("->", out)


main()
