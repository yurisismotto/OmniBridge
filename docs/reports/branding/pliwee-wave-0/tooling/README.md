# Pliwee Wave 0 — reconstruction tooling

Evidence, not a build step. Nothing in the repository runs these scripts; they
are kept so that the four Pliwee masters and every number in
[`../../PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md`](../../PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md)
can be reproduced from the reference board.

Environment used on 2026-09-24: Python 3.14 in a throwaway venv with
`numpy scipy scikit-image fonttools resvg-py potracer opencv-python-headless`,
ImageMagick 7 with librsvg 2.62.3, `xmllint`, and Inter 4.1
(`Inter-4.1.zip` from the rsms/inter GitHub release, SHA-256
`9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e`, OFL-1.1).

```sh
export INTER_DIR=/path/to/unzipped/Inter-4.1
cp ../../../../design/references/pliwee-brand-board-symbol.png ref-mark.png
cp ../../../../design/references/pliwee-brand-board-lockup.png ref-lockup.png
mkdir -p out sheets
python seg.py                # silhouette + face segmentation (watershed on CIELAB edges)
python build_mark.py         # potrace the faces, first gradient fit, mono tones
python fit_paint.py          # joint linear + radial-overlay paint fit per face
python emit_mark.py out      # pliwee-mark.svg, pliwee-mark-mono.svg (one template)
python compare_mark.py out/pliwee-mark.svg
python fit_wordmark.py       # Inter instance + per-glyph placement for "Pliwee"
python fit_tag2.py           # Inter instance + per-glyph placement for the tagline
python emit_lockup.py out    # pliwee-wordmark.svg, pliwee-lockup.svg
python compare_lockup.py
python render_checks.py out  # resvg vs librsvg, transparency, mono light/dark sheet
python make_sheets.py sheets # the three comparison PNGs beside this directory
python validate.py out       # structural checks + geometry equality
```

| Script | Decides |
| --- | --- |
| `seg.py` | *which* ribbon face a pixel belongs to — one hand-placed seed set per face; the reference's own colour edges decide *where* each boundary runs |
| `build_mark.py` | the outlines (potrace, 2× supersampled, alpha threshold 0.5), the viewBox, the monochrome tones (face L\* ÷ brightest face L\*) |
| `fit_paint.py` | every gradient stop, vector and overlay, by least squares against the board's pixels |
| `fit_wordmark.py`, `fit_tag2.py` | the Inter instance, scale and glyph positions, by IoU against the board's ink |
| `emit_*.py` | nothing — serialisation only |
