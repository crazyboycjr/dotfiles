#!/usr/bin/env python3
"""Warm up the INNOCN PU15-PRE towards D65 with a calibration curve (vcgt) in its ICC profile.

    warm.py <mired> [tint%]

mired: how much colder than D65 the panel is assumed to be (0 = no change, 25 = a ~7770K panel).
tint%: green adjustment, negative is more magenta. The profile is macOS's own EDID profile with
its identity vcgt replaced, so primaries and tone curve stay as macOS derived them.
"""
import os, struct, subprocess, sys, glob

BASE = "/Library/ColorSync/Profiles/Displays/PU15-PRE-DB36DCA8-111C-4D25-BFB2-9E49A104EC88.icc"
OUT_DIR = os.path.expanduser("~/Library/ColorSync/Profiles")
HERE = os.path.dirname(os.path.abspath(__file__))
PRIMARIES = [(0.6846, 0.3135), (0.2432, 0.7070), (0.1387, 0.0547)]   # from the panel's EDID

def solve3(a, v):  # Cramer's rule, a is 3x3 rows
    det = lambda m: (m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1]) - m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0]) + m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]))
    d = det(a)
    return [det([[v[r] if c == k else a[r][c] for c in range(3)] for r in range(3)]) / d for k in range(3)]

def xyz(x, y): return [x/y, 1.0, (1-x-y)/y]

def daylight(T):
    x = (-4.6070e9/T**3 + 2.9678e6/T**2 + 0.09911e3/T + 0.244063) if T <= 7000 else (-2.0064e9/T**3 + 1.9018e6/T**2 + 0.24748e3/T + 0.237040)
    return x, -3.0*x*x + 2.87*x - 0.275

def gains(mired, tint):
    cols = [xyz(*p) for p in PRIMARIES]
    P = [[cols[c][r] for c in range(3)] for r in range(3)]
    s = solve3(P, xyz(0.3127, 0.3290))
    M = [[P[r][c]*s[c] for c in range(3)] for r in range(3)]
    native = solve3(M, xyz(*daylight(1e6/(1e6/6504 - mired)))) if mired else [1.0, 1.0, 1.0]
    g = [1/v for v in native]; g[1] *= 1 + tint/100
    return [v/max(g) for v in g]

def build(mired, tint, rgb=None):
    data = bytearray(open(BASE, "rb").read())
    n = struct.unpack(">I", data[128:132])[0]
    entries = [struct.unpack(">4sII", data[132+12*i:144+12*i]) for i in range(n)]
    lin = rgb or gains(mired, tint)
    enc = [v ** (1/2.2) for v in lin]
    name = f"PU15-PRE rgb {lin[0]:g} {lin[1]:g} {lin[2]:g}" if rgb else f"PU15-PRE warm {mired:+g} tint {tint:+g}"
    blobs = {}
    for sig, off, size in entries:
        blobs.setdefault((off, size), bytes(data[off:off+size]))
    out_tags = []
    for sig, off, size in entries:
        blob = blobs[(off, size)]
        if sig == b"vcgt":
            blob = b"vcgt" + bytes(4) + struct.pack(">I", 1) + b"".join(struct.pack(">iii", 65536, 0, round(e*65536)) for e in enc)
        elif sig == b"desc":
            a = name.encode() + b"\0"
            blob = b"desc" + bytes(4) + struct.pack(">I", len(a)) + a + bytes(8) + bytes(3) + bytes(67)
        elif sig == b"dscm":
            u = name.encode("utf-16-be")
            blob = b"mluc" + bytes(4) + struct.pack(">II", 1, 12) + b"enUS" + struct.pack(">II", len(u), 28) + u
        out_tags.append((sig, (off, size) if sig not in (b"vcgt", b"desc", b"dscm") else sig, blob))
    # lay the tags out again, keeping shared data shared
    body, placed, table = bytearray(), {}, []
    start = 128 + 4 + 12*len(out_tags)
    for sig, key, blob in out_tags:
        if key not in placed:
            while (start + len(body)) % 4: body += b"\0"
            placed[key] = (start + len(body), len(blob)); body += blob
        table.append((sig,) + placed[key])
    header = bytearray(data[:128])
    total = start + len(body)
    header[0:4] = struct.pack(">I", total); header[84:100] = bytes(16)
    out = header + struct.pack(">I", len(table)) + b"".join(struct.pack(">4sII", *t) for t in table) + body
    os.makedirs(OUT_DIR, exist_ok=True)
    for old in glob.glob(os.path.join(OUT_DIR, "PU15-PRE-warm-*.icc")):
        os.remove(old)
    tag = "rgb-" + "_".join(f"{v:g}" for v in lin) if rgb else f"{mired:g}_{tint:g}"
    path = os.path.join(OUT_DIR, f"PU15-PRE-warm-{tag}.icc")
    open(path, "wb").write(out)
    print(f"{name}: linear gains R {lin[0]:.3f} G {lin[1]:.3f} B {lin[2]:.3f} (vcgt max {enc[0]:.3f} {enc[1]:.3f} {enc[2]:.3f})")
    return path

if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--rgb":          # explicit linear gains, for tests
        path = build(0, 0, [float(v) for v in sys.argv[2:5]])
    else:
        mired = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0
        tint = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
        path = build(mired, tint)
    subprocess.run([os.path.join(HERE, "csprofile"), path], check=False)
