#!/usr/bin/env python3
"""Derive the Android brand drawables from the frozen Pliwee masters (Wave 6).

    python3 docs/reports/branding/pliwee-wave-6/derive_android_icons.py [--check]

Reads, never writes:
    docs/design/assets/pliwee-mark.svg        (colour master)
    docs/design/assets/pliwee-mark-mono.svg   (mono master)

Writes (or, with --check, compares against):
    android/app/src/main/res/drawable/ic_launcher_foreground.xml
    android/app/src/main/res/drawable/ic_launcher_monochrome.xml
    android/app/src/main/res/drawable/logo_pliwee_mark.xml

This is a *mechanical conversion* (BRAND.md, "The derivation rule"), not a
redraw:

* every `android:pathData` of the mark is one of the four master paths
  (`silhouette`, `face-loop`, `face-tail`, `face-sweep`), copied byte for byte;
* every gradient is the master's gradient: the same user-space coordinates,
  the same stop offsets, the same colours; `stop-opacity` becomes the alpha
  byte, round(opacity * 255) — the only quantisation, and the one every 8-bit
  renderer applies;
* SVG paints a face with a radial gradient whose `gradientTransform` is
  translate · rotate · scale. VectorDrawable has no gradientTransform, but a
  <group> composes exactly T · R · S about pivot (0, 0). So each radial paint
  is a unit radial inside a group carrying the master's own five numbers,
  clipped to the face it paints (a nested <clip-path>, which is how
  VectorDrawable expresses "fill this path with that paint"). The shape the
  unit radial is painted on is the master's viewBox rectangle mapped back
  through the inverse of that transform, so it covers exactly the artwork and
  never needs astronomically large coordinates;
* the silhouette's fill with `paint-inner`, and the four faces clipped to the
  silhouette, follow the master's <symbol id="mark"> in its own order.

Placement in the 108-unit adaptive canvas is computed, not chosen: the ink of
the mark is the silhouette (every face is clipped to it), so the minimum
enclosing circle of the flattened silhouette is scaled to TARGET_RADIUS and
centred on (54, 54). BrandingResourcesTest re-measures the result.
"""

import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
ASSETS = ROOT / "docs/design/assets"
RES = ROOT / "android/app/src/main/res/drawable"

CANVAS = 108.0
CENTRE = 54.0
# The round safe zone is a 33-unit radius; the OmniBridge layers used 31.80.
TARGET_RADIUS = 31.8

FACES = ["face-loop", "face-tail", "face-sweep"]


def read(name):
    return (ASSETS / name).read_text()


def path_d(svg, pid):
    m = re.search(r'<path id="%s" d="([^"]+)"' % re.escape(pid), svg)
    if not m:
        sys.exit(f"master defines no path #{pid}")
    return m.group(1)


def gradients(svg):
    """id -> dict(kind, attrs, stops[(offset, rgb, opacity)])."""
    out = {}
    for m in re.finditer(r'<(linearGradient|radialGradient) id="([^"]+)"([^>]*)>(.*?)</\1>', svg):
        kind, gid, attrs, body = m.groups()
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))
        stops = []
        for s in re.finditer(r"<stop ([^>]*)/>", body):
            sa = dict(re.findall(r'([\w-]+)="([^"]*)"', s.group(1)))
            stops.append((sa["offset"], sa["stop-color"].upper().lstrip("#"), sa.get("stop-opacity", "1")))
        out[gid] = {"kind": kind, "attrs": a, "stops": stops}
    return out


def paint_order(svg):
    """The master's own paint order inside <symbol id="mark">."""
    sym = re.search(r'<symbol id="mark"[^>]*>(.*?)</symbol>', svg, re.S).group(1)
    base = re.search(r'^\s*<use href="#silhouette" fill="url\(#([^)]+)\)"/>', sym)
    if not base:
        sys.exit("master symbol does not start with the silhouette fill")
    clip = re.search(r'<g clip-path="url\(#clip\)">(.*?)</g>', sym, re.S).group(1)
    uses = re.findall(r'<use href="#([^"]+)" fill="url\(#([^)]+)\)"/>', clip)
    return base.group(1), uses


def argb(rgb, opacity):
    a = math.floor(float(opacity) * 255 + 0.5)  # = Math.round, as the test computes it
    if not 0 <= a <= 255:
        sys.exit(f"stop opacity out of range: {opacity}")
    return f"#{a:02X}{rgb}"


def fmt(x):
    s = f"{x:.10f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ----------------------------------------------------------------- geometry --

TOKEN = re.compile(r"[MLCZmlcz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def flatten(d, steps=200):
    toks = TOKEN.findall(d)
    pts, i, cmd, cur, start = [], 0, None, None, None
    num = lambda k: float(toks[k])
    while i < len(toks):
        t = toks[i]
        if t in "MLCZmlcz":
            if t.islower():
                sys.exit("relative commands are not expected in the masters")
            cmd = t
            i += 1
            if t == "Z":
                cur = start
                continue
        if cmd == "M":
            cur = start = (num(i), num(i + 1)); pts.append(cur); i += 2; cmd = "L"
        elif cmd == "L":
            cur = (num(i), num(i + 1)); pts.append(cur); i += 2
        elif cmd == "C":
            c1, c2, to = (num(i), num(i + 1)), (num(i + 2), num(i + 3)), (num(i + 4), num(i + 5))
            for s in range(1, steps + 1):
                u = s / steps; m = 1 - u
                pts.append((m**3 * cur[0] + 3 * m * m * u * c1[0] + 3 * m * u * u * c2[0] + u**3 * to[0],
                            m**3 * cur[1] + 3 * m * m * u * c1[1] + 3 * m * u * u * c2[1] + u**3 * to[1]))
            cur = to; i += 6
        else:
            sys.exit(f"unexpected token {t!r}")
    return pts


def circle2(a, b):
    c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    return c, math.dist(a, c)


def circle3(a, b, c):
    ax, ay = a; bx, by = b; cx, cy = c
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < 1e-12:
        return None
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
    return (ux, uy), math.dist((ux, uy), a)


def inside(circ, p):
    return circ is not None and math.dist(circ[0], p) <= circ[1] + 1e-9


def min_circle(points):
    """Welzl's algorithm, iterative form, deterministic shuffle."""
    pts = list(points)
    random.Random(6).shuffle(pts)
    c = None
    for i, p in enumerate(pts):
        if inside(c, p):
            continue
        c = (p, 0.0)
        for j in range(i):
            q = pts[j]
            if inside(c, q):
                continue
            c = circle2(p, q)
            for k in range(j):
                r = pts[k]
                if not inside(c, r):
                    c = circle3(p, q, r) or c
    return c


# ------------------------------------------------------------------ writing --

def inverse_trs(tx, ty, rot, sx, sy, x, y):
    """Map a user-space point into the local space of translate·rotate·scale."""
    x, y = x - tx, y - ty
    a = math.radians(rot)
    x, y = x * math.cos(a) + y * math.sin(a), -x * math.sin(a) + y * math.cos(a)
    return x / sx, y / sy


def radial_group(g, viewbox, indent):
    t = g["attrs"]["gradientTransform"]
    m = re.fullmatch(r"translate\(([-\d.]+) ([-\d.]+)\) rotate\(([-\d.]+)\) scale\(([-\d.]+) ([-\d.]+)\)", t)
    if not m or g["attrs"].get("cx") != "0" or g["attrs"].get("cy") != "0" or g["attrs"].get("r") != "1":
        sys.exit(f"unsupported radial gradient form: {g['attrs']}")
    tx, ty, rot, sx, sy = m.groups()
    w, h = viewbox
    corners = [inverse_trs(float(tx), float(ty), float(rot), float(sx), float(sy), x, y)
               for x, y in ((0, 0), (w, 0), (w, h), (0, h))]
    quad = "M " + " L ".join(f"{fmt(x)},{fmt(y)}" for x, y in corners) + " Z"
    items = "\n".join(
        f'{indent}                <item android:offset="{o}" android:color="{argb(c, op)}" />'
        for o, c, op in g["stops"])
    return (
        f'{indent}<group android:translateX="{tx}" android:translateY="{ty}"\n'
        f'{indent}       android:rotation="{rot}" android:scaleX="{sx}" android:scaleY="{sy}">\n'
        f'{indent}    <path android:pathData="{quad}">\n'
        f'{indent}        <aapt:attr name="android:fillColor">\n'
        f'{indent}            <gradient android:type="radial"\n'
        f'{indent}                android:centerX="0" android:centerY="0" android:gradientRadius="1">\n'
        f"{items}\n"
        f"{indent}            </gradient>\n"
        f"{indent}        </aapt:attr>\n"
        f"{indent}    </path>\n"
        f"{indent}</group>\n")


def linear_path(d, g, indent):
    a = g["attrs"]
    if a.get("gradientUnits") != "userSpaceOnUse" or "gradientTransform" in a:
        sys.exit(f"unsupported linear gradient form: {a}")
    items = "\n".join(
        f'{indent}            <item android:offset="{o}" android:color="{argb(c, op)}" />'
        for o, c, op in g["stops"])
    return (
        f'{indent}<path android:pathData="{d}">\n'
        f'{indent}    <aapt:attr name="android:fillColor">\n'
        f'{indent}        <gradient android:type="linear"\n'
        f'{indent}            android:startX="{a["x1"]}" android:startY="{a["y1"]}"\n'
        f'{indent}            android:endX="{a["x2"]}" android:endY="{a["y2"]}">\n'
        f"{items}\n"
        f"{indent}        </gradient>\n"
        f"{indent}    </aapt:attr>\n"
        f"{indent}</path>\n")


def mark_body(svg, indent):
    paths = {pid: path_d(svg, pid) for pid in ["silhouette"] + FACES}
    grads = gradients(svg)
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups()
    viewbox = (float(vb[0]), float(vb[1]))
    base, uses = paint_order(svg)

    out = [linear_path(paths["silhouette"], grads[base], indent)]
    out.append(f"{indent}<group>\n{indent}    <clip-path android:pathData=\"{paths['silhouette']}\" />\n")
    inner = indent + "    "
    open_face = None
    for face, gid in uses:
        g = grads[gid]
        if g["kind"] == "linearGradient":
            if open_face:
                out.append(f"{inner}</group>\n")
                open_face = None
            out.append(linear_path(paths[face], g, inner))
        else:
            if open_face != face:
                if open_face:
                    out.append(f"{inner}</group>\n")
                out.append(f"{inner}<group>\n{inner}    <clip-path android:pathData=\"{paths[face]}\" />\n")
                open_face = face
            out.append(radial_group(g, viewbox, inner + "    "))
    if open_face:
        out.append(f"{inner}</group>\n")
    out.append(f"{indent}</group>\n")
    return "".join(out), viewbox


def placement(svg):
    ink = flatten(path_d(svg, "silhouette"))
    (cx, cy), r = min_circle(ink)
    scale = math.floor(TARGET_RADIUS / r * 10000) / 10000
    tx, ty = CENTRE - scale * cx, CENTRE - scale * cy
    xs = [p[0] * scale + tx for p in ink]; ys = [p[1] * scale + ty for p in ink]
    return {
        "centre": (cx, cy), "radius": r, "scale": scale,
        "tx": round(tx, 3), "ty": round(ty, 3),
        "bbox": (min(xs), max(xs), min(ys), max(ys)),
        "scaled_radius": r * scale,
    }


HEADER_FG = """<?xml version="1.0" encoding="utf-8"?>
<!--
  GENERATED FROM THE PLIWEE MASTER - DO NOT HAND-EDIT.
  Regenerate with docs/reports/branding/pliwee-wave-6/derive_android_icons.py.

  Every `android:pathData` of the mark is copied byte-for-byte out of
  docs/design/assets/pliwee-mark.svg (`silhouette`, `face-loop`, `face-tail`,
  `face-sweep`), and every gradient is that file's gradient: the same
  coordinates, offsets and colours, with stop-opacity as the alpha byte.
  BrandingResourcesTest re-reads the master and fails if any of it drifts.

  Radial paints: the master's gradientTransform is translate * rotate * scale;
  a VectorDrawable <group> composes exactly that about pivot (0,0), so each
  radial is a unit radial inside a group carrying the master's own numbers,
  clipped to the face it paints.

  Placement is computed: the minimum enclosing circle of the flattened
  silhouette is centre ({cx:.2f}, {cy:.2f}), radius {r:.2f}. At scale {s} that
  radius becomes {sr:.2f} against the 33-unit round safe zone, and the ink spans
  x[{x0:.1f}, {x1:.1f}] y[{y0:.1f}, {y1:.1f}] against the 72-unit square one.
  Both are asserted by BrandingResourcesTest from this file's own numbers.
-->
"""

HEADER_MONO = """<?xml version="1.0" encoding="utf-8"?>
<!--
  GENERATED FROM THE PLIWEE MASTER - DO NOT HAND-EDIT.
  Regenerate with docs/reports/branding/pliwee-wave-6/derive_android_icons.py.

  The themed/monochrome launcher layer. It is docs/design/assets/pliwee-mark-mono.svg:
  that master paints only `silhouette`, in one colour, and so does this layer.
  `android:pathData` is byte-for-byte that path, placed exactly as
  ic_launcher_foreground.xml places the colour mark. BrandingResourcesTest
  asserts the equality and the absence of any <gradient> or brand colour.
-->
"""

HEADER_LOGO = """<?xml version="1.0" encoding="utf-8"?>
<!--
  GENERATED FROM THE PLIWEE MASTER - DO NOT HAND-EDIT.
  Regenerate with docs/reports/branding/pliwee-wave-6/derive_android_icons.py.

  The in-app brand mark, at the master's own 276x255 viewport. Same
  derivation and same guarantees as ic_launcher_foreground.xml: every
  pathData and every gradient comes out of docs/design/assets/pliwee-mark.svg
  and is asserted against it.
-->
"""


def build():
    svg = read("pliwee-mark.svg")
    mono = read("pliwee-mark-mono.svg")
    if path_d(mono, "silhouette") != path_d(svg, "silhouette"):
        sys.exit("mono master's silhouette differs from the colour master's")
    if not re.search(r'<symbol id="markMono"[^>]*>\s*<use href="#silhouette" fill="currentColor"/>\s*</symbol>', mono):
        sys.exit("mono master no longer paints the silhouette alone")

    p = placement(svg)
    x0, x1, y0, y1 = p["bbox"]
    body, (vw, vh) = mark_body(svg, "        ")
    group_open = (f'    <group android:translateX="{fmt(p["tx"])}" android:translateY="{fmt(p["ty"])}"\n'
                  f'           android:scaleX="{p["scale"]}" android:scaleY="{p["scale"]}">\n')
    fg = (HEADER_FG.format(cx=p["centre"][0], cy=p["centre"][1], r=p["radius"], s=p["scale"],
                           sr=p["scaled_radius"], x0=x0, x1=x1, y0=y0, y1=y1)
          + '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
          + '    xmlns:aapt="http://schemas.android.com/aapt"\n'
          + '    android:width="108dp" android:height="108dp"\n'
          + '    android:viewportWidth="108" android:viewportHeight="108">\n'
          + group_open + body + "    </group>\n</vector>\n")
    mono_xml = (HEADER_MONO
                + '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
                + '    android:width="108dp" android:height="108dp"\n'
                + '    android:viewportWidth="108" android:viewportHeight="108"\n'
                + '    android:tint="#FF000000">\n'
                + group_open
                + f'        <path android:pathData="{path_d(mono, "silhouette")}" android:fillColor="#FF000000" />\n'
                + "    </group>\n</vector>\n")
    logo_body, _ = mark_body(svg, "    ")
    logo = (HEADER_LOGO
            + '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            + '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            + f'    android:width="{fmt(vw)}dp" android:height="{fmt(vh)}dp"\n'
            + f'    android:viewportWidth="{fmt(vw)}" android:viewportHeight="{fmt(vh)}">\n'
            + logo_body + "</vector>\n")
    return p, {"ic_launcher_foreground.xml": fg, "ic_launcher_monochrome.xml": mono_xml,
               "logo_pliwee_mark.xml": logo}


def main():
    check = "--check" in sys.argv[1:]
    p, files = build()
    print(f"silhouette MEC centre ({p['centre'][0]:.4f}, {p['centre'][1]:.4f}) radius {p['radius']:.4f}")
    print(f"scale {p['scale']}  translate ({p['tx']}, {p['ty']})  scaled radius {p['scaled_radius']:.4f}")
    print("ink bbox x[%.3f, %.3f] y[%.3f, %.3f]" % p["bbox"])
    bad = 0
    for name, text in files.items():
        target = RES / name
        if check:
            same = target.is_file() and target.read_text() == text
            print(f"{'SAME ' if same else 'DIFF '} {target.relative_to(ROOT)}")
            bad += not same
        else:
            target.write_text(text)
            print(f"wrote {target.relative_to(ROOT)} ({len(text.encode())} bytes)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
