"""Patch ComfyAtmosphere's water shader so the shoreline blends instead of cutting.

Original (src/water.cpp v0.17.1-alpha, ~line 1234): our water's opacity rises from 0 to 1 over the first 0.03 yards of depth, i.e. a
hard seam along the whole bank. New: the ramp is 0.3 yards of depth on a gentle bank and about a yard along the ground on a steep one (depth x 0.3 / slope) and its width varies in world space between
0.13 and 0.43 yards (two crossed warped sines, periods of 50 to 90 yards), so the transition never follows the geometry as one clean
line. Through the wider ramp the screen copy under the water (the sand, wet, with the swash film) shows, then the bed through the thin water.
Same-length text replacement, padded with spaces inside a comment (the DLL carries its HLSL as text and compiles it at run time).

usage:  python -I patch_comfy_shore.py <in comfyatmos.dll> <out comfyatmos.dll>        (the input is never modified)
        python -I patch_comfy_shore.py --check <dll>
"""
import sys, hashlib
ORIGINAL = (
"    // The surface: drawn by us where the water is (depth > 0), over the game's. Without the screen copy, or\n"
"    // with [water] surface 0, the game's water shows with the foam over it, as before.\n"
"    float  wv = smoothstep(0.0, 0.03, depthS) * gDeep.w * gWave.z;\n"
).encode("ascii")
HEAD = "    // EqShaders\n"
CODE = (
"    float2 q = rel.xy + gCam.xy;\n"
"    float  sw = 0.3 * (1.0 + 0.45 * sin(q.x * 0.11 + sin(q.y * 0.07) * 2.0) * sin(q.y * 0.13 + sin(q.x * 0.09) * 1.7));\n"
"    float  wv = smoothstep(0.0, sw, min(depthS, depthS / slope * 0.3)) * gDeep.w * gWave.z;\n"
)
def build():
    n = len(ORIGINAL); pad = n - len((HEAD + CODE).encode("ascii"))
    if pad < 0: raise SystemExit("replacement is %d bytes too long" % -pad)
    new = (HEAD.rstrip("\n") + " " * pad + "\n" + CODE).encode("ascii")
    assert len(new) == n
    return new
def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        print("patched" if b.count(build()) == 1 else ("original" if b.count(ORIGINAL) == 1 else "unknown")); return
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    b = open(sys.argv[1], "rb").read()
    if b.count(ORIGINAL) != 1: raise SystemExit("the original text was not found exactly once")
    out = b.replace(ORIGINAL, build()); assert len(out) == len(b)
    open(sys.argv[2], "wb").write(out); print("wrote", sys.argv[2], hashlib.sha256(out).hexdigest()[:16])
main()
