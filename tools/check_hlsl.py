"""Offline sanity check for PhotonWoW (no ReShade needed, Windows only).

Strips the ReShade-only syntax (textures, sampler states, annotations, techniques) and compiles every
PS_* entry point with Microsoft's D3DCompiler as ps_3_0 (what ReShade's D3D9 backend targets).
This catches HLSL type/syntax/instruction-limit errors. It cannot catch ReShade FX parser quirks,
so a clean run is necessary, not sufficient.

usage: python -I check_hlsl.py <path to Shaders/PhotonWoW.fx> [-DNAME=VALUE ...]
e.g.   python -I check_hlsl.py Shaders/PhotonWoW.fx -DPW_ENABLE_SSR=1 -DPW_ENABLE_DOF=1 -DPW_ENABLE_VOLUMETRICS=1
"""
import ctypes, os, re, sys
from ctypes import wintypes


def read_inlined(path, seen=None):
    seen = seen if seen is not None else set()
    out = []
    base = os.path.dirname(path)
    for line in open(path, encoding="utf-8").read().splitlines():
        m = re.match(r'\s*#include\s+"([^"]+)"', line)
        if m:
            inc = os.path.normpath(os.path.join(base, m.group(1)))
            if inc not in seen:
                seen.add(inc)
                out.append(read_inlined(inc, seen))
            continue
        out.append(line)
    return "\n".join(out)


def match_brace(s, i, o="{", c="}"):
    depth, j = 0, i
    while j < len(s):
        if s[j] == '"':
            j = s.index('"', j + 1)
        elif s[j] == o:
            depth += 1
        elif s[j] == c:
            depth -= 1
            if depth == 0:
                return j
        j += 1
    raise ValueError("unbalanced")


def strip_annotations(s):
    """Remove `< ... >` annotation blocks following a uniform/technique name (strings may contain '>')."""
    out, i = [], 0
    pat = re.compile(r'(uniform\s+\w+\s+\w+|technique\s+\w+)\s*<')
    while True:
        m = pat.search(s, i)
        if not m:
            out.append(s[i:])
            break
        out.append(s[i:m.end() - 1])
        j, instr = m.end(), False
        while True:
            ch = s[j]
            if ch == '"':
                instr = not instr
            elif ch == '>' and not instr:
                break
            j += 1
        i = j + 1
    return "".join(out)


def convert(src):
    s = strip_annotations(src)
    while True:  # techniques
        m = re.search(r'technique\s+\w+\s*\{', s)
        if not m:
            break
        s = s[:m.start()] + s[match_brace(s, m.end() - 1) + 1:]
    s = re.sub(r'texture\s+\w+\s*:\s*\w+\s*;', '', s)
    while True:  # texture blocks
        m = re.search(r'texture\s+\w+\s*\{', s)
        if not m:
            break
        s = s[:m.start()] + s[match_brace(s, m.end() - 1) + 1:].lstrip(';')
    # sampler-declaring macros (two-line #define with a backslash continuation)
    macro_re = r'(#define\s+(?:PW_BLOOM_SAMPLER|PW_LINEAR_SAMPLER)\(name, tex\))\s*\\\s*\n[^\n]*\n'
    s = re.sub(macro_re, lambda m: m.group(1) + " sampler2D name;\n", s)
    while True:  # sampler state blocks
        m = re.search(r'sampler\s+(\w+)\s*\{', s)
        if not m:
            break
        s = s[:m.start()] + "sampler2D " + m.group(1) + ";" + s[match_brace(s, m.end() - 1) + 1:].lstrip(';')
    # vertex shader (SV_VertexID is not SM3)
    m = re.search(r'void\s+PW_VS\s*\(', s)
    if m:
        s = s[:m.start()] + s[match_brace(s, s.index('{', m.end())) + 1:]
    s = s.replace("float4 pos : SV_Position", "float2 pos : VPOS").replace("float4 p : SV_Position", "float2 p : VPOS")
    s = s.replace(": SV_Target", ": COLOR0")
    # ReShade's `sampler` function-parameter type -> SM3 sampler2D
    s = re.sub(r'\bsampler\s+(\w+)\s*([,)])', lambda m: "sampler2D " + m.group(1) + m.group(2), s)
    # single-channel targets: ReShade lets a PS return `float`; SM3 COLOR0 must be float4 -> wrap
    for name in re.findall(r'^float\s+(PS_\w+)\s*\(', s, flags=re.M):
        s = re.sub(r'^float\s+' + name + r'\s*\(([^)]*)\)\s*:\s*COLOR0', "float " + name + r"_1ch(\1)", s, flags=re.M)
        s += "\nfloat4 " + name + "(float2 pos : VPOS, float2 uv : TEXCOORD0) : COLOR0 { return " + name + "_1ch(pos, uv).xxxx; }\n"
    return s


def blob_text(p):
    if not p.value:
        return ""
    vt = ctypes.cast(ctypes.cast(p, ctypes.POINTER(ctypes.c_void_p))[0], ctypes.POINTER(ctypes.c_void_p))
    get_ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])
    get_size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])
    return ctypes.string_at(get_ptr(p), get_size(p)).decode("utf-8", "replace")


def main():
    path = sys.argv[1]
    defines = ""
    for a in sys.argv[2:]:
        if a.startswith("-D"):
            defines += "#define " + a[2:].replace("=", " ", 1) + "\n"
    pre = ("#define BUFFER_WIDTH 1920\n#define BUFFER_HEIGHT 1080\n"
           "#define BUFFER_RCP_WIDTH (1.0/1920.0)\n#define BUFFER_RCP_HEIGHT (1.0/1080.0)\n" + defines)
    src = pre + convert(read_inlined(path))
    flat = os.path.join(os.environ.get("TEMP", "."), "photonwow_flat.hlsl")
    open(flat, "w", encoding="utf-8").write(src)

    entries = sorted(set(re.findall(r'^float4\s+(PS_\w+)\s*\(', src, flags=re.M)))
    d3d = ctypes.windll.LoadLibrary("D3DCompiler_47.dll")
    d3d.D3DCompile.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p,
                               ctypes.c_char_p, ctypes.c_char_p, wintypes.UINT, wintypes.UINT,
                               ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)]
    d3d.D3DCompile.restype = ctypes.c_long
    b = src.encode("utf-8")
    bad, seen = 0, set()
    for e in entries:
        code, err = ctypes.c_void_p(), ctypes.c_void_p()
        hr = d3d.D3DCompile(b, len(b), b"flat.hlsl", None, None, e.encode(), b"ps_3_0", 0, 0,
                            ctypes.byref(code), ctypes.byref(err))
        if hr < 0:
            bad += 1
            for l in blob_text(err).splitlines():
                if "error" in l and l not in seen:
                    seen.add(l)
                    print("   " + re.sub(r'^.*?flat\.hlsl', 'flat', l))
        print(("OK   " if hr >= 0 else "FAIL ") + e)
    print(f"{len(entries)} entry points, {bad} failures (flattened source: {flat})")
    sys.exit(1 if bad else 0)


main()
