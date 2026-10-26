"""Solve the near/far plane of a standard D3D perspective depth buffer from two readings.

Read raw depth with PhotonWoW 'Debug view = Depth probe' while the centre crosshair sits on surfaces at two
KNOWN, DIFFERENT distances (e.g. stand 5 yd and 40 yd from a wall; measure along the view axis, not radially).

    z = a - a*N*u        with u = 1/d and a = F/(F-N)        (z is linear in 1/d)

usage: python -I solve_depth.py z1 d1 z2 d2        e.g.  python -I solve_depth.py 0.9610000 5 0.9951000 40
"""
import sys

z1, d1, z2, d2 = map(float, sys.argv[1:5])
u1, u2 = 1.0 / d1, 1.0 / d2
slope = (z2 - z1) / (u2 - u1)      # = -a*N
a = z1 - slope * u1                # intercept = a
n = -slope / a
f = a * n / (a - 1.0) if a != 1.0 else float("inf")
print(f"a = {a:.6f}\nnear = {n:.4f} yd\nfar  = {f:.1f} yd")
if not (0.01 < n < 20 and 20 < f < 20000):
    print("warning: values look implausible - depth may not be standard perspective (try Depth encoding / Reversed), or the distances were not along the view axis.")
