#!/usr/bin/env python3
"""Render check for the Wave 6 Android brand drawables.

    python3 docs/reports/branding/pliwee-wave-6/render_check.py OUTDIR

Reads each generated VectorDrawable with a separate interpreter (this file
does not import derive_android_icons.py), re-expresses it as SVG under the
VectorDrawable rules — a <group> is translate · rotate · scale about (0,0), a
<clip-path> clips its group's later children and intersects with outer clips,
gradient coordinates are in the path's local space, colours are #AARRGGBB —
renders it and the frozen master with librsvg (ImageMagick `rsvg:` delegate),
and compares pixels.

This proves the conversion is faithful under those rules. It does not prove
Android's own renderer draws them the same way; that is the hardware check.
"""

import io
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
A = "{http://schemas.android.com/apk/res/android}"
AAPT = "{http://schemas.android.com/aapt}"


def colour(c):
    c = c.lstrip("#")
    if len(c) == 6:
        c = "FF" + c
    return "#" + c[2:], int(c[:2], 16) / 255


class Svg:
    def __init__(self):
        self.defs, self.n = [], 0

    def uid(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def paint(self, path_el):
        fill = path_el.get(A + "fillColor")
        if fill:
            rgb, a = colour(fill)
            return f'fill="{rgb}" fill-opacity="{a:.6f}"'
        attr = path_el.find(AAPT + "attr")
        g = attr.find("gradient")
        gid = self.uid("g")
        stops = "".join(
            f'<stop offset="{i.get(A + "offset")}" stop-color="{colour(i.get(A + "color"))[0]}" '
            f'stop-opacity="{colour(i.get(A + "color"))[1]:.6f}"/>' for i in g.findall("item"))
        if g.get(A + "type") == "linear":
            self.defs.append(
                f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" '
                f'x1="{g.get(A + "startX")}" y1="{g.get(A + "startY")}" '
                f'x2="{g.get(A + "endX")}" y2="{g.get(A + "endY")}">{stops}</linearGradient>')
        else:
            self.defs.append(
                f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" '
                f'cx="{g.get(A + "centerX")}" cy="{g.get(A + "centerY")}" '
                f'r="{g.get(A + "gradientRadius")}">{stops}</radialGradient>')
        return f'fill="url(#{gid})"'

    def children(self, el):
        out, open_clips = [], 0
        for c in el:
            if c.tag == "clip-path":
                cid = self.uid("c")
                self.defs.append(f'<clipPath id="{cid}"><path d="{c.get(A + "pathData")}"/></clipPath>')
                out.append(f'<g clip-path="url(#{cid})">')
                open_clips += 1
            elif c.tag == "path":
                out.append(f'<path d="{c.get(A + "pathData")}" {self.paint(c)}/>')
            elif c.tag == "group":
                for k in ("pivotX", "pivotY"):
                    assert c.get(A + k) is None, "pivot not supported"
                t = (f'translate({c.get(A + "translateX", "0")} {c.get(A + "translateY", "0")}) '
                     f'rotate({c.get(A + "rotation", "0")}) '
                     f'scale({c.get(A + "scaleX", "1")} {c.get(A + "scaleY", "1")})')
                out.append(f'<g transform="{t}">' + "".join(self.children(c)) + "</g>")
        out.append("</g>" * open_clips)
        return out

    def document(self, vector, w, h, background=None):
        body = "".join(self.children(vector))
        vw, vh = vector.get(A + "viewportWidth"), vector.get(A + "viewportHeight")
        bg = f'<rect width="{vw}" height="{vh}" fill="{background}"/>' if background else ""
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {vw} {vh}">'
                f'<defs>{"".join(self.defs)}</defs>{bg}{body}</svg>')


def render(svg_text, name, width):
    p = OUT / f"{name}.svg"
    p.write_text(svg_text)
    png = subprocess.run(["magick", "-background", "none", "-density", "384", f"rsvg:{p}",
                          "-resize", f"{width}x", "png:-"], capture_output=True, check=True).stdout
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    img.save(OUT / f"{name}.png")
    return img


def compare(a, b, label):
    b = b.resize(a.size)
    diff = ImageChops.difference(a, b)
    stat = ImageStat.Stat(diff)
    mean = sum(stat.mean) / 4
    # Pixels differing by more than 16/255 in any channel.
    big = sum(1 for px in diff.getdata() if max(px) > 16)
    total = a.size[0] * a.size[1]
    ink = sum(1 for px in a.getdata() if px[3] > 0)
    return mean, big, total, ink


def main():
    master = (ROOT / "docs/design/assets/pliwee-mark.svg").read_text()
    res = ROOT / "android/app/src/main/res/drawable"
    lines = []
    W = 1104

    # 1. In-app mark: same 276x255 viewport as the master.
    logo = ET.parse(res / "logo_pliwee_mark.xml").getroot()
    got = render(Svg().document(logo, 276, 255), "logo_pliwee_mark-as-svg", W)
    ref = render(master, "master-pliwee-mark", W)
    mean, big, total, ink = compare(ref, got, "logo")
    lines.append(f"logo_pliwee_mark.xml vs pliwee-mark.svg at {W}px: mean |d| {mean:.3f}/255, "
                 f"pixels with any channel |d|>16: {big} of {total} ({ink} ink pixels in the master)")

    # 2. Launcher foreground: the master placed with the drawable's own group numbers.
    fg = ET.parse(res / "ic_launcher_foreground.xml").getroot()
    grp = fg.find("group")
    s, tx, ty = grp.get(A + "scaleX"), grp.get(A + "translateX"), grp.get(A + "translateY")
    inner = re.sub(r"^<svg[^>]*>", "", master.strip()).rsplit("</svg>", 1)[0]
    placed = (f'<svg xmlns="http://www.w3.org/2000/svg" width="108" height="108" viewBox="0 0 108 108">'
              f'<g transform="translate({tx} {ty}) scale({s})"><svg width="276" height="255" viewBox="0 0 276 255">'
              f"{inner}</svg></g></svg>")
    ref = render(placed, "master-placed-108", 864)
    got = render(Svg().document(fg, 108, 108), "ic_launcher_foreground-as-svg", 864)
    mean, big, total, ink = compare(ref, got, "fg")
    lines.append(f"ic_launcher_foreground.xml vs master placed at scale {s} translate ({tx},{ty}), 864px: "
                 f"mean |d| {mean:.3f}/255, pixels with any channel |d|>16: {big} of {total} ({ink} ink)")

    # 3. Composite on the launcher background, for a human look.
    bg = Svg().document(fg, 108, 108, background="#0B1020")
    render(bg, "launcher-on-background", 432)
    mono = ET.parse(res / "ic_launcher_monochrome.xml").getroot()
    render(Svg().document(mono, 108, 108, background="#F7F9FC"), "launcher-monochrome", 432)

    (OUT / "render-check.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
