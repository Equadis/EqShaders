"""Patch ComfyAtmosphere's water so the sky reflection and the sun/moon glint fade out in the shallows.

Why: at the bank the water still carried the full sky reflection and glint, so near the shore it read as a pale, bright sheet that
ends in a hard edge against the dark land (rain/night frames at Lake Everstill, 2026-10-27), however wide the opacity ramp was.
New: sh = smoothstep(0, 0.9, min(depthS, depthS / slope * 0.5)): 0 at the waterline, 1 from about 0.9 yards of depth on a gentle bank or
about 1.8 yards along the ground on a steep one. F (the sky's share, Fresnel + horizon) and the glint are both multiplied by it, so the
bed shows through the shallows and sky/glint come in with depth. Applies on top of patch_comfy_reflect.py (it rewrites the lines that patch
produced). Same-length text replacement padded inside comments (the HLSL is plain text in the DLL, compiled at run time).

usage:  python -I patch_comfy_shoref.py <in comfyatmos.dll> <out comfyatmos.dll>      (input never modified)
        python -I patch_comfy_shoref.py --check <dll>
"""
import sys, hashlib
START = b"    // The horizon (2026-10-03). In the last 2 degrees"
END = b"    float3 R    = reflect(dir, normalize(N * float3(.5, .5, 1.)));\n"
CODE = (
"    float  hz   = 1.0 - saturate(-relN / dist / 0.035);\n"
"    hz *= hz;\n"
"    F = max(F, 0.7 * hz);\n"
"    float  sh   = smoothstep(0.0, 0.9, min(depthS, depthS / slope * 0.5));\n"
"    F *= sh;\n"
"    float3 R    = reflect(dir, normalize(N * float3(.5, .5, 1.)));\n"
)
HEAD = "    // EqShaders: the reflection sees half the wave slope, and sky and glint fade out in the shallows (sh).\n"
G_OLD = (
"    // it while the moon itself still showed through the sky: the glint went out before the moon had set.\n"
"    water += glint * (1.0 - 0.5 * fogF);\n"
).encode("ascii")
G_HEAD = "    // EqShaders: the glint fades in the shallows."
G_CODE = "    water += glint * (1.0 - 0.5 * fogF) * sh;\n"

def locate(b):
    i = b.find(START); j = b.find(END, i)
    if i < 0 or j < 0 or b.count(START) != 1: return None
    return i, j + len(END)

def build_main(seg_len):
    pad = seg_len - len(HEAD) - len(CODE)
    if pad < 0: raise SystemExit("main replacement is %d bytes too long" % -pad)
    return (HEAD.rstrip("\n") + " " * pad + "\n" + CODE).encode("ascii")

def build_glint():
    n = len(G_OLD); pad = n - len(G_HEAD) - 1 - len(G_CODE)
    if pad < 0: raise SystemExit("glint replacement is %d bytes too long" % -pad)
    new = (G_HEAD + " " * pad + "\n" + G_CODE).encode("ascii"); assert len(new) == n; return new

def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        print("patched" if b.count(b"F *= sh;") == 1 and b.count(G_CODE.encode()) == 1 else ("original" if locate(b) and b.count(G_OLD) == 1 else "unknown")); return
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    b = open(sys.argv[1], "rb").read(); loc = locate(b)
    if not loc or b.count(G_OLD) != 1: raise SystemExit("expected text not found exactly once (apply patch_comfy_reflect.py first)")
    seg = b[loc[0]:loc[1]]
    assert b"F = max(F, 0.7 * hz);" in seg
    out = b[:loc[0]] + build_main(len(seg)) + b[loc[1]:]
    out = out.replace(G_OLD, build_glint())
    assert len(out) == len(b)
    open(sys.argv[2], "wb").write(out); print("wrote", sys.argv[2], hashlib.sha256(out).hexdigest()[:16])
main()
