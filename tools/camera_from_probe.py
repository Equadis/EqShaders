"""Read the camera orientation out of ComfyAtmosphere's F12 probe capture (Logs\\comfyatmos.log).

Press F12 in-game (needs [general] hotkeys = 1), then run:  python -I camera_from_probe.py
The capture lists, per draw, world/view/proj matrices as the client set them. For the world draws the 3x3 part of the view matrix
is the camera's rotation (D3D row-vector convention: camera-space = world * view). The script prints the distinct view matrices and,
for the ones that are rotations, the camera's forward / up / right vectors in world space with yaw and pitch.

WoW world axes: +X north, +Y west, +Z up (so yaw 0 looks north, 90 looks west).
"""
import re, math, sys

LOG = r"D:\Octowow\Logs\comfyatmos.log"
lines = open(LOG, encoding="utf-8", errors="replace").read().split("\n")
starts = [i for i, l in enumerate(lines) if "begin frame" in l and "capture" in l]
if not starts:
    sys.exit("no probe capture in the log: press F12 in-game first")
cap = lines[starts[-1]:]
num = r"\s+(-?[\d\.]+(?:e[-+]?\d+)?)"
views, i = [], 0
while i < len(cap):
    if re.match(r"\s+view\[0\] =", cap[i]):
        m = []
        for k in range(4):
            mm = re.match(r"\s+view\[%d\] =" % k + num * 4, cap[i + k])
            if mm:
                m.append([float(x) for x in mm.groups()])
        if len(m) == 4:
            views.append((i, m))
        i += 4
    else:
        i += 1

def norm(v): return math.sqrt(sum(x * x for x in v))
seen = set()
for ln, m in views:
    key = tuple(round(x, 3) for r in m for x in r)
    if key in seen:
        continue
    seen.add(key)
    # columns of the 3x3 are the camera axes expressed in world coordinates
    right = [m[0][0], m[1][0], m[2][0]]
    up    = [m[0][1], m[1][1], m[2][1]]
    fwd   = [m[0][2], m[1][2], m[2][2]]
    ortho = abs(norm(right) - 1) < 0.02 and abs(norm(up) - 1) < 0.02 and abs(norm(fwd) - 1) < 0.02
    yaw = math.degrees(math.atan2(fwd[1], fwd[0]))
    pitch = math.degrees(math.asin(max(-1, min(1, fwd[2]))))
    print("capture line %d: %s" % (ln, "rotation" if ortho else "not a pure rotation (scale/other)"))
    for r in m:
        print("   " + " ".join("%9.4f" % x for x in r))
    if ortho:
        print("   forward (world) = (%.3f %.3f %.3f)  yaw %.1f deg  pitch %.1f deg (negative = looking down)" % (fwd[0], fwd[1], fwd[2], yaw, pitch))
        print("   up      (world) = (%.3f %.3f %.3f)" % tuple(up))
print("distinct view matrices: %d" % len(seen))

# ---- from the sun: the probe also logs where the sky draws the sun in CAMERA space ("SKY SUN camera-space (x y z)"), and the sun's
# world azimuth/elevation. With the sun's elevation known, its up/forward components in camera space fix the camera's PITCH
# (two solutions: facing the sun's side or away from it; the one that looks down is the usual third-person view).
sun = None
for l in cap:
    m = re.search(r"SKY SUN\s+camera-space \((-?[\d\.]+) (-?[\d\.]+) (-?[\d\.]+)\)", l)
    if m:
        sun = [float(x) for x in m.groups()]
        break
elev = None
for l in lines:
    m = re.search(r"the last sky with sun-shaped quads .* drew 1: (-?[\d\.]+)/(-?[\d\.]+)", l)
    if m:
        az, elev = float(m.group(1)), float(m.group(2))
if sun and elev is not None:
    n = norm(sun)
    up_c, fwd_c, side_c = sun[1] / n, sun[2] / n, sun[0] / n    # camera space: +z forward, so a negative z means the sun is behind the camera (the probe prints w<0 for it)
    a, s = math.cos(math.radians(elev)), math.sin(math.radians(elev))
    print("sun in camera space: up %.3f  forward %.3f  side %.3f   (world az %.1f el %.1f)" % (up_c, fwd_c, side_c, az, elev))
    A2 = up_c ** 2 + fwd_c ** 2 - s ** 2
    if A2 >= 0:
        for sign in (+1, -1):
            A = sign * math.sqrt(A2)       # = cos(el) * cos(sun azimuth - camera yaw)
            sin_t = (-A * up_c + s * fwd_c) / (A * A + s * s)
            pitch = math.degrees(math.asin(max(-1, min(1, sin_t))))
            c = max(-1, min(1, A / a)) if a > 1e-6 else 1
            d = math.degrees(math.acos(c))
            print("  solution %+d: camera pitch %.1f deg (negative = looking down); the camera yaw is within %.1f deg of %s the sun's azimuth"
                  % (sign, pitch, d, "facing" if sign > 0 else "facing away from"))