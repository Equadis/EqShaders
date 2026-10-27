"""Patch ComfyAtmosphere's water so the sky reflection does not draw the wave pattern as bands.

Original (src/water.cpp v0.17.1-alpha, ~line 1370): R = reflect(dir, N) with N the full small-wave normal. Where the reflected ray
crosses the sky's gradient or the sunset glow band (saturate(R.z / 0.05 + 0.35)) the wave tilt switches the reflection between sky
tones, which reads as regular bright/dark strips across the surface. New: the reflection sees the normal with its slope halved
(x and y x 0.5), so the reflected sky and the sun's glint still shimmer with the waves but the band edges are much less contrasty.
The refraction (bend) and the foam keep the full normal. Same-length text replacement, padded inside a comment.

usage:  python -I patch_comfy_reflect.py <in comfyatmos.dll> <out comfyatmos.dll>     (input never modified)
        python -I patch_comfy_reflect.py --check <dll>
"""
import sys, hashlib
ORIGINAL = (
"    // turned it the pale fog colour, as the sand (2026-10-02, the 0.6 above).\n"
"    float  hz   = 1.0 - saturate(-relN / dist / 0.035);\n"
"    hz *= hz;\n"
"    F = max(F, 0.7 * hz);\n"
"    float3 R    = reflect(dir, N);\n"
).encode("ascii")
TAIL = (
"    float  hz   = 1.0 - saturate(-relN / dist / 0.035);\n"
"    hz *= hz;\n"
"    F = max(F, 0.7 * hz);\n"
"    float3 R    = reflect(dir, normalize(N * float3(.5, .5, 1.)));\n"
)
HEAD = "    // EqShaders: half-slope reflection."
def build():
    n = len(ORIGINAL); pad = n - len(HEAD) - 1 - len(TAIL)
    if pad < 0: raise SystemExit("replacement is %d bytes too long" % -pad)
    new = (HEAD + " " * pad + "\n" + TAIL).encode("ascii"); assert len(new) == n; return new
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
