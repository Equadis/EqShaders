"""Patch ComfyAtmosphere's water so its small waves do not read as repeated parallel strips.

Original (src/water.cpp v0.17.1-alpha, WaveNormal ~line 422): six sine trains whose directions all lie within +-1.2 rad of the wind
and whose steepness is constant, so the crests run as regular parallel bands; Swell/SwellSlope (the shore swell) likewise cluster
their three directions. New: wider direction spread, slightly irregular lengths, the crest lines wander (the phase is domain-warped by
two slow noises, ~+-2 yards over ~25), and each train's strength varies over the surface (0.55..1.45, mean 1.0, so the overall look
stays). All of it is in world space. Same-length text replacement padded inside a comment (the HLSL is plain text in the DLL).

usage:  python -I patch_comfy_wavetile.py <in comfyatmos.dll> <out comfyatmos.dll>     (input never modified)
        python -I patch_comfy_wavetile.py --check <dll>
"""
import sys, hashlib
START = b"// The small waves, as a facing:"
END = b"    return normalize(float3(-(g * strength + swell), 1.0));\n}\n"
NEW_HEAD = (
"// EqShaders: the small waves as a facing. Six trains with widely spread directions, crest lines that wander (domain warp)\n"
"// and a strength that varies over the surface, so no straight repeated strips show. Heights are never drawn.\n"
"float3 WaveNormal(float2 p, float t, float strength, float2 swell, float dist)\n{\n"
"    float2 g = 0.0;\n"
"    float  a[6] = { -0.2, 1.0, -0.9, 1.9, -1.7, 0.5 };\n"
"    float  l[6] = { 7.3, 4.1, 3.1, 1.83, 1.37, 0.87 };\n"
"    float  s[6] = { 0.10, 0.10, 0.09, 0.08, 0.07, 0.06 };\n"
"    float2 wq = p * 0.043 + t * 0.012;\n"
"    float2 pw = p + (float2(ValueNoise(wq), ValueNoise(wq + 17.3)) - 0.5) * 4.0;\n"
"    float  m0 = ValueNoise(p * 0.031 + 3.7);\n"
"    float  m1 = ValueNoise(p * 0.057 - 8.1);\n"
"    [unroll] for (int i = 0; i < 6; ++i)\n    {\n"
"        float  ang = 0.7854 + a[i];\n"
"        float2 d   = float2(cos(ang), sin(ang));\n"
"        float  k   = 6.2832 / (l[i] / gWave.x);\n"
"        float  w   = sqrt(10.7 * k);\n"
"        float  am  = 0.55 + 0.9 * lerp(m0, m1, float(i) / 5.0);\n"
"        g += d * (s[i] * am * cos(k * dot(d, pw) - w * t)) / (1.0 + dist * k / (12.0 * 6.2832));\n"
"    }\n"
"    float2 q = p * 1.6 + float2(t * 0.4, t * 0.25);\n"
"    float  n0 = ValueNoise(q);\n"
"    g += float2(ValueNoise(q + float2(0.15, 0.0)) - n0, ValueNoise(q + float2(0.0, 0.15)) - n0) * 0.35 /\n"
"         (1.0 + dist / 60.0);\n"
).encode("ascii")
SWELL_OLD = b"float r[3] = { 0.15, -0.45, 0.7 };"
SWELL_NEW = b"float r[3] = { 0.15, -0.95, 1.3 };"

def build(seg_len):
    pad = seg_len - len(NEW_HEAD) - len(END)
    if pad < 0: raise SystemExit("replacement is %d bytes too long" % -pad)
    first_nl = NEW_HEAD.index(b"\n")
    head = NEW_HEAD[:first_nl] + b" " * pad + NEW_HEAD[first_nl:]   # pad inside the first comment line
    return head + END

def locate(b):
    i = b.find(START); j = b.find(END, i)
    if i < 0 or j < 0 or b.count(START) != 1: return None
    return i, j + len(END)

def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        if b.count(b"// EqShaders: the small waves as a facing") == 1 and b.count(SWELL_NEW) >= 2: print("patched")
        else: print("original" if locate(b) else "unknown")
        return
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    b = open(sys.argv[1], "rb").read(); loc = locate(b)
    if not loc: raise SystemExit("WaveNormal not found exactly once")
    seg = b[loc[0]:loc[1]]
    if seg.startswith(b"// EqShaders"): raise SystemExit("already patched")
    assert b"1.2, -1.1, 0.3" in seg and b.count(SWELL_OLD) >= 2, "unexpected original text"
    out = b[:loc[0]] + build(len(seg)) + b[loc[1]:]
    out = out.replace(SWELL_OLD, SWELL_NEW)
    assert len(out) == len(b)
    open(sys.argv[2], "wb").write(out); print("wrote", sys.argv[2], hashlib.sha256(out).hexdigest()[:16])
main()
