# Design references

Owner-supplied visual references. **They are not assets.** Nothing in the
product, the build or a platform pipeline reads them; the vector masters in
[`../assets/`](../assets/) are what every derivative is built from.

They are kept here, byte-for-byte as supplied, because they are the reference
the masters are compared against, and a comparison is only reproducible
against the exact pixels it was made with. Do not edit, re-export, crop,
compress or "clean up" these files.

## Pliwee brand board

Supplied by the owner on 2026-09-24 as the official visual reference for the
Pliwee identity ([ADR-0020 §D8](../../adr/ADR-0020-rename-to-pliwee.md)).

| File | What it shows | Pixels | SHA-256 |
| --- | --- | --- | --- |
| [`pliwee-brand-board-symbol.png`](pliwee-brand-board-symbol.png) | the **Flow Monogram** alone | 1254 × 1254, RGBA, transparent | `eda0c70647fee7cf1ddf7f9670608147bf020b2e459d2db26390512fdccb5e0a` |
| [`pliwee-brand-board-lockup.png`](pliwee-brand-board-lockup.png) | the horizontal lockup: Flow Monogram + **Pliwee** + *One flow. Any device.* | 2172 × 724, RGBA, transparent | `af8b65ed260ec8847d733945b7458ae5b24ffcd3909a630d99f131b57dd657c7` |

Supplied as `ChatGPT Image 24 de set. de 2026, 14_48_45.png` (symbol) and
`… 14_48_58.png` (lockup). Both carry a C2PA manifest (`caBX` chunk) naming
`ChatGPT` / `gpt-image` with `digitalSourceType` `trainedAlgorithmicMedia`:
they are synthesised rasters, with no vector payload and no recoverable SVG.

The vector masters derived from them are a **controlled reconstruction**, and
their status is recorded in [`../BRAND.md`](../BRAND.md#pliwee-vector-masters).
The measured comparison is in
[`docs/reports/branding/PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md`](../../reports/branding/PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md).

Not the logo: the "Connected Nodes" concept (ADR-0020 §D8). It is not stored
here, so that it cannot be mistaken for a reference.
