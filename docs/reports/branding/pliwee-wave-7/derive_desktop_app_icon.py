#!/usr/bin/env python3
"""Derive the desktop application icon from the frozen Pliwee master (Wave 7).

    python3 docs/reports/branding/pliwee-wave-7/derive_desktop_app_icon.py [--check]

Reads, never writes:
    docs/design/assets/pliwee-mark.svg      (colour master)

Writes (or, with --check, compares against):
    docs/design/assets/pliwee-app-icon.svg

This is a *placement*, not a conversion and not a redraw (BRAND.md, "The
derivation rule"). SVG can express everything the master does, so nothing is
translated:

* the master's whole <defs>…</defs> block — the four paths, the clip, all
  thirteen gradients and <symbol id="mark"> — is copied byte for byte;
* the icon draws exactly one thing: <use href="#mark"> on the 512-unit square
  grid the OmniBridge app icon used (the same 50-unit margin, so the ink
  occupies the same share of the tile);
* the symbol keeps its own viewBox (276 x 255) and the default
  preserveAspectRatio (xMidYMid meet), so the mark is scaled uniformly and
  centred; no coordinate of the artwork is touched.

desktop/gui/tests/brand_assets.rs re-proves all three facts from the files.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
ASSETS = ROOT / "docs/design/assets"
MASTER = ASSETS / "pliwee-mark.svg"
TARGET = ASSETS / "pliwee-app-icon.svg"

GRID = 512
MARGIN = 50


def derive() -> str:
    master = MASTER.read_text(encoding="utf-8")
    m = re.search(r"<defs>.*</defs>", master, re.S)
    if m is None:
        sys.exit(f"{MASTER}: no <defs> block")
    defs = m.group(0)
    if defs.count("<symbol id=\"mark\"") != 1:
        sys.exit(f"{MASTER}: expected exactly one <symbol id=\"mark\">")
    size = GRID - 2 * MARGIN
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{GRID}" height="{GRID}" '
        f'viewBox="0 0 {GRID} {GRID}" role="img" aria-label="Pliwee"><title>Pliwee</title>\n'
        f"{defs}\n"
        f'<use href="#mark" x="{MARGIN}" y="{MARGIN}" width="{size}" height="{size}"/></svg>\n'
    )


def main() -> None:
    out = derive()
    if "--check" in sys.argv[1:]:
        have = TARGET.read_text(encoding="utf-8") if TARGET.exists() else None
        if have == out:
            print(f"SAME {TARGET.relative_to(ROOT)}")
            return
        print(f"DIFFERS {TARGET.relative_to(ROOT)}")
        sys.exit(1)
    TARGET.write_text(out, encoding="utf-8")
    print(f"wrote {TARGET.relative_to(ROOT)} ({len(out)} bytes)")


if __name__ == "__main__":
    main()
