"""Patch ComfyAtmosphere's water shader so shallow water keeps the colour of the bed under it.

comfyatmos.dll carries its HLSL as plain text and compiles it at run time, so the colour model can be changed without a rebuild
as long as the replacement text is exactly as long as the original (the text is padded with spaces inside a comment).

Original (src/water.cpp, v0.17.1-alpha, around line 1287): whatever lay under the water was pulled 70..90 % of the way to the
water's hue from the first millimetre, keeping only its brightness. Mud, rock and sand all became the same blue-green, which is
the "fixed blue overlay" look. New: the bed keeps its own colour, and takes the water's hue only as the water gets deeper
(continuous, no bands); the per-channel absorption that follows (T = exp(-gAbs * path)) already fades the bed into the water's
own colour with depth, so very shallow water is mostly bed, mid water is a mix, deep water is body colour + sky reflection.

usage:  python -I patch_comfy_water.py <in comfyatmos.dll> <out comfyatmos.dll>        (the input is never modified)
        python -I patch_comfy_water.py --check <dll>                                   (reports patched / original / unknown)
"""
import sys, hashlib

ORIGINAL = (
"    // Seen through it, the bed takes the water's hue, keeping its own brightness, more with every yard of water.\n"
"    // Filtering alone could not do it: orange sand has hardly any blue to keep, and under blue water it turned\n"
"    // olive green whatever the colour was set to (2026-10-02).\n"
"    float3 tint = gDeep.rgb / max(dot(gDeep.rgb, float3(0.299, 0.587, 0.114)), 1e-3);\n"
"    float  lum  = dot(bed, float3(0.299, 0.587, 0.114));\n"
"    // Half of it even in the thinnest water at the very edge: the water has its colour right up to the foam line\n"
"    // (2026-10-02: clear at the edge, sandy water came between the blue and the line).\n"
"    bed = lerp(bed, lum * tint, 0.7 + 0.2 * (1.0 - exp(-2.5 * path)));\n"
"    float3 body = bed * T + gDeep.rgb * (1.0 - T);\n"
).encode("ascii")

TAIL = (
"    float3 tint = gDeep.rgb / max(dot(gDeep.rgb, float3(0.299, 0.587, 0.114)), 1e-3);\n"
"    float  lum  = dot(bed, float3(0.299, 0.587, 0.114));\n"
"    bed = lerp(bed, lum * tint, 0.62 * (1.0 - exp(-0.32 * path)));\n"
"    float3 body = bed * T + gDeep.rgb * (1.0 - T);\n"
)
HEAD1 = "    // EqShaders: the bed seen through shallow water keeps its own colour (mud, rock, sand) and takes the water's hue only with\n"
HEAD2 = "    // depth, 0.62 of the way at most (smooth, no bands). The absorption below does the rest: shallow = bed, deep = body + sky.\n"

def build_replacement():
    n = len(ORIGINAL)
    base = (HEAD1 + HEAD2 + TAIL).encode("ascii")
    pad = n - len(base)
    if pad < 0:
        raise SystemExit("replacement is %d bytes too long" % -pad)
    # pad inside the second comment line (before its newline) so the line count and the code are untouched
    head2 = HEAD2.rstrip("\n") + " " * pad + "\n"
    new = (HEAD1 + head2 + TAIL).encode("ascii")
    assert len(new) == n, (len(new), n)
    return new

def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        new = build_replacement()
        print("patched" if b.count(new) == 1 else ("original" if b.count(ORIGINAL) == 1 else "unknown"))
        return
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    b = open(src, "rb").read()
    if b.count(ORIGINAL) != 1:
        raise SystemExit("the original water text was not found exactly once (already patched, or another comfyatmos version)")
    out = b.replace(ORIGINAL, build_replacement())
    assert len(out) == len(b)
    open(dst, "wb").write(out)
    print("wrote", dst, "sha256", hashlib.sha256(out).hexdigest()[:16], "(input sha256", hashlib.sha256(b).hexdigest()[:16] + ")")

main()
