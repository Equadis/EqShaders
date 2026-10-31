"""Patch ComfyAtmosphere's fog composite so the far fog colour does not jump where the world's depth slice ends.

Original (src/volume.cpp v0.17.1-alpha, kCompositeHlsl ~line 584): farV = raw > worldEnd ? 1.0 : smoothstep(300, 1000, dist).
farV picks the fog's light colour between Fog Brightness (near) and the sky's full-brightness horizon colour (far). Land drawn by the
client's far-horizon camera (467..2112 yards, depth 0.955..0.96) gets farV = 1 outright, while the land just in front of it, at about
437 yards where the world's slice ends, gets smoothstep(300,1000,437) = 0.1: a hard step in fog colour along the edge of every far-terrain
chunk, a pale box with straight sides (Lake Everstill, 2026-10-27). New: one continuous ramp, smoothstep(200, 1700, distance), where
far land's distance is rebuilt from its depth with the far camera's planes (z = 1 / (1/467 - f (1/467 - 1/2112)), f = (raw - 0.955) / 0.005),
so the colour changes smoothly across the slice boundary and over a much longer range. Only the sky (raw >= 0.99) stays at 1.
Same-length text replacement padded inside a comment (the HLSL is plain text in the DLL, compiled at run time).

usage:  python -I patch_comfy_fogfar.py <in comfyatmos.dll> <out comfyatmos.dll>     (input never modified)
        python -I patch_comfy_fogfar.py --check <dll>
"""
import sys, hashlib
ORIGINAL = (
"    // land and the sky lie past the world's slice; nearer, from 300 yards to full at 1000. Fog Brightness (55 there)\n"
"    // made the thick fog on the far sea darker than the sky over it and the water under it.\n"
"    float  farV = raw > worldEnd ? 1.0 : smoothstep(300.0, 1000.0, dist);\n"
).encode("ascii")
HEAD = "    // EqShaders: one continuous ramp (200..1700 yards); far land's distance comes from its depth."
CODE = (
"    float  fd = saturate((raw - 0.955) * 200.0);\n"
"    float  farV = raw >= 0.99 ? 1.0 : smoothstep(200.0, 1700.0, raw > worldEnd ? 1.0 / (0.0021413 - fd * 0.0016678) : dist);\n"
)
def build():
    n = len(ORIGINAL); pad = n - len(HEAD) - 1 - len(CODE)
    if pad < 0: raise SystemExit("replacement is %d bytes too long" % -pad)
    new = (HEAD + " " * pad + "\n" + CODE).encode("ascii"); assert len(new) == n; return new
def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        print("patched" if b.count(build()) == 1 else ("original" if b.count(ORIGINAL) == 1 else "unknown")); return
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    b = open(sys.argv[1], "rb").read()
    if b.count(ORIGINAL) != 1: raise SystemExit("original text not found exactly once")
    out = b.replace(ORIGINAL, build()); assert len(out) == len(b)
    open(sys.argv[2], "wb").write(out); print("wrote", sys.argv[2], hashlib.sha256(out).hexdigest()[:16])
main()
