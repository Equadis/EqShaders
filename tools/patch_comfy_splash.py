"""Patch ComfyAtmosphere so the game's rain splashes on the ground are fainter.

The game's rain splashes (textures\Weather\RainDropSplash01.blp, vertex format 0x142) are drawn through Comfy's splash pixel shader
(water.cpp, kSplashPsHlsl), which drops the ones under water and returns the rest as the game would. New: the returned alpha is
multiplied by 0.45, so the splashes on dry ground (roads, paths, stone) blend in at under half their opacity. The factor is the number in
the text below; change it in this file and rebuild the patched DLL to tune it. Same-length text replacement (the HLSL is plain text in
the DLL, compiled at run time), padded inside a comment.

usage:  python -I patch_comfy_splash.py <in comfyatmos.dll> <out comfyatmos.dll>      (input never modified)
        python -I patch_comfy_splash.py --check <dll>
"""
import sys, hashlib
FACTOR = "0.45"
ORIGINAL = (
"    clip(A.z - lv - 0.05);   // under the water, or on it: ours draws the rain there\n"
"    return c;\n"
).encode("ascii")
HEAD = "    clip(A.z - lv - 0.05);   // EqShaders: fainter"
CODE = "    return float4(c.rgb, c.a * %s);\n" % FACTOR
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
