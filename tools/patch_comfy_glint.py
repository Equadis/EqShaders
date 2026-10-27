"""Patch ComfyAtmosphere's water so the sun/moon glint is a broad, view-independent specular lobe instead of a razor-thin mirror spike.

Original (src/water.cpp v0.17.1-alpha, ~line 1315): glint = pow(dot(reflect(dir, N), L), 700 / size^2) * 8 + pow(..., 60 / size^2) * 0.25.
Those powers are lobes only a few degrees wide, so the sun shows only where the mirror direction lands on it: with a high sun that is
only when the pixel's ray is steep, i.e. looking nearly straight down. At a normal third-person pitch it vanishes.
New: a GGX-shaped lobe on the HALF-VECTOR, H = normalize(L - view dir), measured against the wave normal N (world space, all vectors
normalised, no camera pitch or forward vector anywhere):
    glint = sunColour * strength * ( 4.0 * GL(a = 0.045 s) + 1.6 * GL(a = 0.38 s) + 0.15 * GL(a = 0.90 s) ),   s = Glint Size
    GL = a^4 / q^2 (peak 1)  x  smoothstep(0, 0.3, N.L)  x  (0.35 + 6 * Schlick(V.H))
a tight core (top-down glint, less peaky than before so it is not overexposed), a broad lobe that carries the reflection across normal
gameplay angles, and a soft halo (the environment). Fresnel rises toward grazing views. The moon uses the same function.
Same-length text replacement (the HLSL is plain text in the DLL, compiled at run time): the function goes where the swell's 3-line comment
was, the glint code where the old glint code was; both padded with spaces inside comments.

usage:  python -I patch_comfy_glint.py <in comfyatmos.dll> <out comfyatmos.dll>     (input never modified)
        python -I patch_comfy_glint.py --check <dll>
"""
import sys, hashlib

SW_OLD = (
"// The swell: three long trains of waves, each its own way and length (24, 17 and 11 yards x waveScale),\n"
"// at the speed of waves on deep water. 0 to 1: the surface only ever rises, so the game's flat water under\n"
"// it never shows through a trough.\n"
).encode("ascii")
SW_NEW_CODE = (
"float GL(float3 N,float3 L,float3 d,float a){float3 H=normalize(L-d);float q=pow(saturate(dot(N,H)),2.0)*(a*a-1.0)+1.0;"
"return pow(a,4.0)/(q*q)*smoothstep(0.0,0.3,dot(N,L))*(0.35+6.0*pow(1.0-saturate(dot(-d,H)),5.0));}"
)
G_START = b"    // The glint of the sun, or by night of the larger moon"
G_END = b"    // The lighthouse's glitter"
G_HEAD = "    // EqShaders: GGX-shaped glint on the half-vector (GL): tight core, broad lobe, soft halo."
G_CODE = (
"    float  sz = rsqrt(max(gGlint.x, 0.01));\n"
"    float3 glint = gSunC.rgb * (gSun.w * (4.0 * GL(N, gSun.xyz, dir, 0.045 * sz) + 1.6 * GL(N, gSun.xyz, dir, 0.38 * sz) + 0.15 * GL(N, gSun.xyz, dir, 0.9 * sz)) +\n"
"                                gMoon2.w * (4.0 * GL(N, gMoon2.xyz, dir, 0.045 * sz) + 1.6 * GL(N, gMoon2.xyz, dir, 0.38 * sz) + 0.15 * GL(N, gMoon2.xyz, dir, 0.9 * sz)));\n"
)

def sw_new():
    pad = len(SW_OLD) - len(SW_NEW_CODE) - 1
    if pad < 0: raise SystemExit("function is %d bytes too long" % -pad)
    return (SW_NEW_CODE + " " * pad + "\n").encode("ascii")

def g_new(seg_len):
    pad = seg_len - len(G_HEAD) - 1 - len(G_CODE)
    if pad < 0: raise SystemExit("glint code is %d bytes too long" % -pad)
    return (G_HEAD + " " * pad + "\n" + G_CODE).encode("ascii")

def locate(b):
    i = b.find(G_START); j = b.find(G_END, i)
    if i < 0 or j < 0 or b.count(G_START) != 1 or b.count(SW_OLD) < 1: return None
    return i, j

def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        b = open(sys.argv[2], "rb").read()
        if b.count(b"float GL(float3 N,float3 L,float3 d,float a)") >= 1 and b.count(b"// EqShaders: GGX-shaped glint") == 1: print("patched")
        else: print("original" if locate(b) else "unknown")
        return
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    b = open(sys.argv[1], "rb").read(); loc = locate(b)
    if not loc: raise SystemExit("original glint text not found exactly once (already patched, or another version)")
    i, j = loc
    assert b"pow(sd, gp1)" in b[i:j]
    out = b[:i] + g_new(j - i) + b[j:]
    out = out.replace(SW_OLD, sw_new())
    assert len(out) == len(b)
    open(sys.argv[2], "wb").write(out); print("wrote", sys.argv[2], hashlib.sha256(out).hexdigest()[:16])
main()
