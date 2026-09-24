# Pliwee rebrand — Wave 0: Brand asset foundation

| | |
| --- | --- |
| **Status** | **AWAITING HUMAN BRAND APPROVAL** |
| **Date** | 2026-09-24 |
| **Branch** | `worktree-pliwee-wave0-brand-assets`, based on `663eb59` (implementation plan) |
| **Plan** | [PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md § Wave 0](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md#wave-0--brand-asset-foundation) |
| **Decision** | [ADR-0020 §D8](../../adr/ADR-0020-rename-to-pliwee.md) |
| **Scope** | vector masters, reference board, brand documentation, brand tests. Nothing else: no identifier, package, binary, protocol, path, platform icon or Play asset changed. |

The four masters are a **controlled vector reconstruction** of the
owner-supplied board. They compile, validate and measure closely against the
board, and **none of that makes them approved**. Until the owner approves
them, they are candidates: no platform derives from them, and the product
keeps shipping the OmniBridge artwork.

---

## 1. Why a reconstruction, and how it departs from the plan

The plan (§0.2 P2, blockers B1/B2) assumed the owner would supply SVG masters
and forbade tracing. The owner instead supplied two raster boards and
instructed, for this wave, a controlled reconstruction that must be rendered,
compared, documented and submitted for approval before it becomes canonical.
That instruction supersedes P2 for this wave; B1 and B2 now close on the
owner's **approval** of these files, not on their supply.

The boards cannot yield an original: both PNGs carry a C2PA manifest naming
`ChatGPT` / `gpt-image` with `digitalSourceType` `trainedAlgorithmicMedia`,
and contain only `IHDR`, `caBX`, `IDAT`, `IEND`. There is no vector payload.

"Controlled" means: **no coordinate, colour or letterform was chosen by eye.**

| Property | Where it comes from |
| --- | --- |
| Silhouette | the board's own alpha channel (2× bicubic, threshold 0.5), traced by potrace |
| Internal face edges | the board's own colour edges (CIELAB Sobel), split by watershed. The only human input is one seed set per face, which says *which* face a region is, never *where* its edge runs |
| Gradients | least-squares fits to the board's pixels, face by face |
| Mono tones | each face's mean CIELAB L\* on the board ÷ the brightest face's |
| Lettering | genuine Inter 4.1 outlines; instance, scale and glyph positions fitted to the board by IoU |

The scripts are kept in [`pliwee-wave-0/tooling/`](pliwee-wave-0/tooling/README.md).

---

## 2. Files

### Created

| File | What |
| --- | --- |
| `docs/design/assets/pliwee-mark.svg` | Flow Monogram, colour — **symbol master** |
| `docs/design/assets/pliwee-mark-mono.svg` | Flow Monogram, `currentColor` — **mono master** |
| `docs/design/assets/pliwee-wordmark.svg` | "Pliwee", outlined Inter — **wordmark master** |
| `docs/design/assets/pliwee-lockup.svg` | mark + Pliwee + *One flow. Any device.* — **lockup master** |
| `docs/design/references/pliwee-brand-board-symbol.png` | the board, symbol (byte-identical to the supplied file) |
| `docs/design/references/pliwee-brand-board-lockup.png` | the board, lockup (byte-identical to the supplied file) |
| `docs/design/references/README.md` | provenance and SHA-256 of both |
| `docs/reports/branding/PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md` | this report |
| `docs/reports/branding/pliwee-wave-0/pliwee-mark-comparison.png` | symbol: board vs SVG, blend, edge overlay, ΔE map, 1:1 crops |
| `docs/reports/branding/pliwee-wave-0/pliwee-lockup-comparison.png` | lockup: board vs SVG, ink difference |
| `docs/reports/branding/pliwee-wave-0/pliwee-mark-variants.png` | colour on Surface/Dark; mono as Dark, Surface, Primary Blue |
| `docs/reports/branding/pliwee-wave-0/tooling/*` | reconstruction and measurement scripts + README |

The three comparison PNGs are **validation artefacts, not product assets.**

### Changed

| File | Change |
| --- | --- |
| `docs/design/BRAND.md` | new § *Pliwee vector masters*: roles, status, derivation rule, reference; one row in § Assets. OmniBridge identity text untouched (Wave 1 owns it). |
| `docs/README.md` | directory map lists `design/references/` |
| `desktop/gui/tests/brand_assets.rs` | five tests added for the Pliwee masters (§8); no existing test or assertion changed |

### Not changed, deliberately

All `omnibridge-*` artwork (still the shipped artwork), `build.rs`, gresource,
installer, Android drawables and `colors.xml`, `tokens.json`,
`BrandingResourcesTest.kt`, every identifier the plan assigns to Waves 1–11.

---

## 3. Reference board

`docs/design/references/`. Stored byte-for-byte; `cmp` against the supplied
files reported identical.

| File | Supplied as | Pixels | SHA-256 |
| --- | --- | --- | --- |
| `pliwee-brand-board-symbol.png` | `ChatGPT Image 24 de set. de 2026, 14_48_45.png` | 1254 × 1254 RGBA | `eda0c70647fee7cf1ddf7f9670608147bf020b2e459d2db26390512fdccb5e0a` |
| `pliwee-brand-board-lockup.png` | `ChatGPT Image 24 de set. de 2026, 14_48_58.png` | 2172 × 724 RGBA | `af8b65ed260ec8847d733945b7458ae5b24ffcd3909a630d99f131b57dd657c7` |

Why `references/` and not `assets/`: `assets/` is the directory the build and
both brand tests read, and a raster there would look like something a platform
may consume. A board is never consumed.

---

## 4. The masters

| File | viewBox | width × height | Bytes | SHA-256 |
| --- | --- | --- | --: | --- |
| `pliwee-mark.svg` | `0 0 276 255` | 276 × 255 | 42 267 | `c61dec684ff648af42cbf594e06c27b9f0cf2c7b1a7a7f16116ef6c2fee13346` |
| `pliwee-mark-mono.svg` | `0 0 276 255` | 276 × 255 | 42 287 | `b3aa1f466ed1a1583425caf60c11f4cbbc72dbe8ba29e05cf7b396fef171cf89` |
| `pliwee-wordmark.svg` | `0 0 316 82` | 316 × 82 | 3 173 | `387adb7f7f42010fae2935f421c7640c01dbb3fc640a7c1196aabf589a0b20b7` |
| `pliwee-lockup.svg` | `0 0 489 143` | 489 × 143 | 54 125 | `0c430d38515aed39c30673a7d47fe1339e65bc45836bf047a609c15f4de37cb1` |

Naming follows the brief and the plan's §2 table (`pliwee-mark`,
`pliwee-mark-mono`, `pliwee-wordmark`). The lockup is `pliwee-lockup.svg`, as
the brief asks, rather than the OmniBridge-era `*-logo-lockup.svg`. Ids avoid
the retired `flow-a` / `flow_a` / `flowing` names (ADR-0020 D8).

### 4.1 Symbol structure

The mark's viewBox is the board's ink box at 0.25 unit per board pixel, plus a
2-unit margin (ink 1088 × 1003 px → 272 × 250.75 → 276 × 255).

The geometry is **four paths, each defined once** in `<defs>`:

| id | What it is | Subpaths |
| --- | --- | --: |
| `silhouette` | the whole mark: outer contour + the loop's hole | 2 |
| `face-loop` | the top loop's outer face (and everything in front of it) | 1 |
| `face-tail` | the lower tail (and the sweep in front of it) | 1 |
| `face-sweep` | the diagonal front sweep | 1 |

36 282 characters of path data; only `M`, `L`, `C`, `Z`. The faces are painted
back to front (`silhouette` → `face-loop` → `face-tail` → `face-sweep`) inside
`clip-path="url(#clip)"`, where `#clip` *is* `silhouette`. The outer edge is
therefore drawn once, by the silhouette, and each visible internal edge is
exactly the front face's traced edge. Face adjacency was measured: loop–inner,
loop–sweep, inner–sweep and sweep–tail touch, while loop and tail never do, so
their relative order has no visible effect.

`<symbol id="mark">` paints the faces in colour; `<symbol id="markMono">` paints
the same ids in `currentColor`. The root `<use>` chooses which to draw.

### 4.2 How the gradient was built (item 4)

Each face has **one linear gradient plus zero to four elliptical radial
overlays**, all in `gradientUnits="userSpaceOnUse"`:

1. **Direction.** For each face, every angle from 0° to 178° in 2° steps was
   tried. Pixels are projected onto that axis, and the colour is fitted as a
   piecewise-linear function of the projection (3–6 equally spaced stops, hat
   basis, least squares). The angle with the least residual is kept.
2. **Overlays.** The board's colour follows the ribbon's *arc*, which one
   linear axis cannot express: a single gradient left a false vertical cyan
   band on the loop and missed the darker blue at its lower left. Each overlay
   is a two-stop `radialGradient` (colour *c* at opacity *a₀* in the centre,
   fading to 0 at the ellipse edge) with `gradientTransform="translate rotate
   scale"`. Centre, radii, rotation, colour and opacity are fitted by
   non-linear least squares, multi-started from the worst-fitting pixels. The
   linear stops are re-solved *jointly* at every step. An overlay is kept only
   if it cuts the residual by ≥ 4 %.
3. Overlays paint **the same face path** (`<use href="#face-…">`). They add
   paint, never geometry.

| Face | Linear axis | Stops | Overlays | RMSE (of 255) linear-only → final |
| --- | --- | --: | --: | --- |
| inner (visible as the dark crescent) | 32° | 3 | 0 | 2.0 → 2.0 |
| loop | 18° | 6 | 4 | 7.7 → 1.8 |
| tail | 48° | 5 | 2 | 4.7 → 2.5 |
| sweep | 20° | 6 | 3 | 10.0 → 2.0 |

The stops are the board's colours, **not** the palette hex values. See §6.3.

### 4.3 How mono and colour are guaranteed to share the geometry (item 5)

* Both files come from **one template**. `diff` of the two files, split at
  tags, shows exactly two differences: the root's `color="#0B1020"` and
  `<use href="#mark"/>` vs `<use href="#markMono"/>`. Their `<defs>` are
  **byte-identical**, so the four geometry paths are the same bytes.
* Inside `markMono` there is no other shape: the same four `<use href>` refer
  to the same four ids, with `fill="currentColor"` and a `fill-opacity` tone.
* So that one tone never composites over another (which would lose the
  over/under crossing), the lower faces are masked by the face drawn in front
  of them. The masks use only those same ids, filled pure white or pure black,
  so luminance masking is unambiguous in every colour space.
* `desktop/gui/tests/brand_assets.rs :: the_pliwee_mono_mark_is_the_colour_mark_repainted`
  extracts every `<path id d>` from both files and asserts they are equal. It
  was shown to fail when one coordinate changed by 0.01 (§8.2).

Mono tones, from board L\*: loop 1.00 · sweep 0.77 · tail 0.63 · inner 0.50.
`currentColor` makes the cut work on light and dark alike, as the OmniBridge
mono cut does. See `pliwee-mark-variants.png`.

### 4.4 How the wordmark was vectorised (item 6)

* **Typeface.** InterVariable 4.1, instanced with `fontTools.varLib.instancer`.
  The board's `l` has a tail, which is Inter's own `cv05` alternate (glyph
  `l.ss02`), so it is used. The round `i` dot is Inter 4's default.
* **Instance.** "Pliwee" was searched over opsz {14, 20, 28, 32} × wght
  {800, 850, 900}; the best IoU against the board's ink is **opsz 14, wght 900**
  (0.832). The tagline, after per-glyph placement, was searched over six
  instances; the best is **opsz 24, wght 450** (IoU 0.901).
* **Scale.** From the board's cap height (`P`, 271 px) for the wordmark, and
  from `O` (overshoot matched against Inter's own `O` bounds) for the tagline.
* **Kerning.** Each glyph's x position was fitted to the board, one glyph at a
  time, by IoU (coarse 2 px, then 0.5 px). That keeps the board's visual
  spacing without modifying any letterform.
* **Outlines.** Each glyph is drawn through `TransformPen` → `SVGPathPen`, so
  the files carry `<path>` elements only: no `<text>`, no `font-family`, no
  `@font-face`, and no dependency on Inter being installed.
* **Colour.** "Pliwee" uses **Dark `#0B1020`**; the board measures `#030D25`,
  ΔE2000 3.5 away, which is rendering noise. The tagline uses the board's
  **measured `#314871`**, because no palette or neutral token is within
  ΔE2000 6.5 of it (nearest: `#333E55` at 6.55 and `#475269` at 6.78). See §7.
* The wordmark file and the lockup's `<g id="wordmark">` carry the **same
  outline bytes**; only the group's `translate` differs. This is asserted by
  a test.

### 4.5 Lockup

The lockup copies the mark master's `<defs>` verbatim, places `#mark` with
`<use width height>`, and sets the wordmark and tagline groups beside it. The
mark's placement is fitted to the board's lockup: its horizontal and vertical
scale factors from the standalone board agree to **0.32 %** (0.5331 vs 0.5314),
so the arrangement is the board's and the mark is not distorted. No other
arrangement was invented.

---

## 5. Validation (per master)

All ten checks from the brief, per file. Run with `tooling/validate.py`,
`tooling/render_checks.py` and the Rust suite.

| Check | mark | mono | wordmark | lockup |
| --- | :-: | :-: | :-: | :-: |
| 1 XML/SVG valid (`xmllint`, parsed root `svg`) | ✅ | ✅ | ✅ | ✅ |
| 2 no base64 / `data:` / `<image>` | ✅ | ✅ | ✅ | ✅ |
| 3 no external reference (every `href` starts `#`, no URL except the SVG namespace) | ✅ | ✅ | ✅ | ✅ |
| 4 viewBox present and consistent with width/height | ✅ | ✅ | ✅ | ✅ |
| 5 rendered large (resvg, 2048 px on the long side) | ✅ | ✅ | ✅ | ✅ |
| 6 transparent (all four corners alpha 0) | ✅ | ✅ | ✅ | ✅ |
| 7 compared with the board | §6 | §6 | §6 | §6 |
| 8 dimensions recorded | §4 | §4 | §4 | §4 |
| 9 mono = colour geometry | — | ✅ byte-identical | — | ✅ same paths |
| 10 no editable text / font dependency | ✅ | ✅ | ✅ outlines only | ✅ outlines only |
| no `<filter>`, `<script>`, `<foreignObject>` | ✅ | ✅ | ✅ | ✅ |

**Two independent renderers.** resvg vs librsvg 2.62.3 (via ImageMagick),
alpha IoU at 2048 px: mark 0.9954, mono 0.9956, wordmark 0.9918, lockup 0.9858.
Mean |ΔRGB| on opaque pixels: 0.00–0.66 of 255. The elements used (`symbol`,
`use`, `clipPath`, `mask`, linear and radial gradients) render the same in
both.

---

## 6. Comparison with the board

### 6.1 Symbol — `pliwee-wave-0/pliwee-mark-comparison.png`

Rendered by resvg into the board's own 1254 px frame:

| Metric | Value |
| --- | --- |
| Silhouette IoU | **0.9986** |
| Boundary distance (board px) | mean **0.19**, p99 **1.0**, max **1.41** |
| Pixels only on the board / only in the SVG | 12 / 909 (of ≈ 660 000) |
| Colour ΔE2000, median / p95 | **0.49 / 1.62** |
| ΔE2000 median per face | inner 0.40 · loop 0.51 · tail 0.48 · sweep 0.48 |

A median ΔE2000 below 1 is below what an observer can see side by side. The
1:1 crops (left crossing, upper-right fold, tail tip) are in the sheet for
human judgement.

### 6.2 Lockup — `pliwee-wave-0/pliwee-lockup-comparison.png`

| Zone | Ink IoU vs board |
| --- | --- |
| mark | 0.954 (ΔE2000 median 1.73, p95 3.59) |
| wordmark "Pliwee" | 0.832 |
| tagline | 0.898 |

### 6.3 Known visual differences (item 11)

Nothing here is hidden. Each of these is visible in the sheets.

1. **The board draws the mark twice, and the two drawings differ.** The
   lockup board's mark is not an exact scale of the symbol board's mark (IoU
   0.954 after a proportional fit). The masters use **one** geometry, the
   symbol board's, in both places, so the lockup's mark differs from the
   lockup board by that inconsistency: at most a few pixels along the outer
   loop and the tail's lower edge.
2. **The board's letters are wider than Inter.** At equal cap height, the
   board's `P` is 207 px wide against Inter Black's 193 (+7 %), and `e` is
   223 against 204 (+9 %). Inter is already at its widest instance here
   (opsz 14, wght 900), so no genuine Inter setting closes the gap; it is an
   artefact of the synthesised board. The wordmark keeps genuine,
   unstretched Inter, so that any product text set in Inter matches it, and
   places each glyph where the board places it. As a result the word is
   0.8 % shorter overall (it ends at x 2012 vs 2029 board px), and each
   letter is slightly narrower and lighter than on the board.
3. **Letter details.** The board's `i` dot is a little larger and higher than
   Inter's. The tail of the board's `l` is shaped slightly differently from
   Inter's `l.ss02`. The `w` apexes differ by a few pixels.
4. **Gradient vs palette.** The mark is painted with the board's colours.
   Primary Blue `#4F6BFF` and Accent Violet `#7C5CFC` occur on the board
   (closest pixels ΔE 0.2 and 0.5). **Flow Cyan `#18B8C9` does not**: the
   board's cyan is brighter and more saturated (closest board pixel `#05CFF8`
   at ΔE 9.2; the loop's brightest cyan `#09DDFC` is ΔE 10.0 from Flow Cyan).
   The board's violet end `#9B36FB` is ΔE 8.0 from Accent Violet. The master
   follows the board; see §7 item 3.
5. **Smooth shading → gradients.** The board's shading is continuous. The
   reconstruction uses 3–6 linear stops plus up to 4 radial overlays per face.
   Residual ΔE is below 2 over 95 % of the mark. The largest local errors are
   along the loop's lower-left inner shadow and at the sweep's upper-right
   fold (see panel E).
6. **Faint alpha speckle.** The symbol board has about 11 500 near-transparent
   pixels (alpha 1–15) around the hole: generation noise. They are not part of
   the mark and were deliberately dropped.

---

## 7. Items requiring human approval (item 12)

The owner decides; nothing below is assumed.

1. **Flow Monogram geometry** (`pliwee-mark.svg`): approve the reconstruction
   as the canonical symbol, or reject it with the differences to correct.
2. **Wordmark letterforms**: genuine Inter Black (opsz 14) with the board's
   spacing, *or* matching the board's wider letterforms. That would mean
   stretching Inter ~7–9 % horizontally, which this wave did not do because it
   modifies the brand typeface.
3. **Mark colour**: keep the board's colours (current master), *or* move the
   stops onto the palette hex values, at the cost of the board's brighter
   cyan. Only paint would change; the geometry and the tests would not.
4. **Mono tones**: tonal mono (current: 1.00 / 0.77 / 0.63 / 0.50, which
   keeps the crossing legible), *or* another scheme. In dark-on-light the loop
   is the strongest face, so the front sweep reads one step lighter.
5. **Tagline colour** `#314871` (measured; not a token): approve, or name a token.
6. **Lockup arrangement and spacing**, as fitted from the board.
7. **Inconsistency between the two boards** (§6.3 item 1): confirm the symbol
   board is the authority.

On approval, the status line in [`BRAND.md`](../../design/BRAND.md#pliwee-vector-masters)
and in this report changes to APPROVED with the date, and the platform waves
may derive. On rejection, the masters are regenerated with the tooling and
remeasured. They are never hand-edited.

---

## 8. Tests

### 8.1 Changed, and why (item 10)

**`desktop/gui/tests/brand_assets.rs`: five tests added; no existing test,
list or assertion changed.**

The OmniBridge `ASSETS` list and its dead list (which still rejects
`"one flow"`) are left exactly as they were. They guard the artwork the
product ships today, which must not carry the Pliwee tagline either. The
Pliwee masters get their own list, `PLIWEE_MASTERS`, and are held to the same
structural checks, with `<filter>`, `<foreignObject>` and any `data:` URI
refused on top:

| Test | Asserts |
| --- | --- |
| `every_pliwee_master_is_a_self_contained_vector` | SVG root and namespace, one root, viewBox; no raster, `data:`, script, font, `<text>`, filter, foreignObject; every `href` internal; no network URL; no editor/path leak; every `url(#…)` resolves; ids unique |
| `the_pliwee_mono_mark_is_the_colour_mark_repainted` | the four face ids exist, total geometry > 20 000 chars, mono geometry **equals** colour geometry, `markMono` uses `currentColor` and no gradient, the mono file draws `#markMono` |
| `the_pliwee_lockup_carries_the_mark_geometry` | every mark path is in the lockup byte for byte; the lockup places `#mark` |
| `the_pliwee_wordmark_is_outlined_and_shared_with_the_lockup` | six outlined letters; wordmark and lockup `wordmark` groups identical |
| `no_pliwee_master_carries_a_retired_identity` | dead list `anyflow`, `flow a`, `flow-a`, `flow_a`, `flowing`, `fedroid`, `omnibridge`, `one bridge`; **and** the lockup declares `aria-label="Pliwee — One flow. Any device."` |

The dead-list change is the one ADR-0020 D8 records. For the Pliwee masters
only, `"one flow"` is **not** on the list, and `omnibridge` and `one bridge`
**are**. The re-adoption is a positive assertion (the lockup must name the
approved tagline), not a removed check. The AnyFlow fragments that were never
the tagline stay dead, and the new names avoid them.

**`android/…/BrandingResourcesTest.kt`: not changed.** It inspects Android
launcher resources and `logo_omnibridge_mark.xml`, none of which this wave
touches, and its dead list (`ribbon`, `flow_a`, `flow-a`, `anyflow`,
`flowing`) contains no re-adopted term. Changing it now would weaken nothing
and prove nothing. Wave 6 re-points it at the Pliwee masters when the launcher
layers are derived. Two notes for W6: the Pliwee silhouette has **two**
subpaths (outer + hole), where the current `flatten()` asserts one; and
VectorDrawable has no `<mask>`, so the mono layer must be converted
mechanically (§ derivation rule in BRAND.md), not redrawn.

### 8.2 Proof that the new tests can fail

Each mutation was applied to an installed master, the named test was run, and
the file was restored from the generated copy (`cmp`-verified afterwards):

| Mutation | Test | Result |
| --- | --- | --- |
| mono `face-sweep` first coordinate +0.01 | mono = colour | **red** |
| mono sweep painted with `url(#paint-sweep)` | mono = colour | **red** |
| lockup `face-loop` gains a leading segment | lockup geometry | **red** |
| `<text font-family="Inter">` added to wordmark | self-contained | **red** |
| `<image href="data:image/png;base64,…">` added | self-contained | **red** |
| `<filter>` added | self-contained | **red** |
| lockup `href="other.svg#mark"` | self-contained | **red** |
| wordmark glyph path changed | wordmark = lockup lettering | **red** |
| `One bridge.` in lockup title | retired identity | **red** |
| id renamed `omnibridge-tail` | retired identity | **red** |
| id renamed `flow-a-loop` | retired identity | **red** |
| approved tagline removed from `aria-label` | retired identity | **red** |

12 of 12 mutations turned the test red.

### 8.3 Executed (item 9)

| Command | Result |
| --- | --- |
| `cargo test -p omnibridge-gui --test brand_assets` (in `desktop/`) | **22 passed**, 0 failed (17 existing + 5 new) |
| `cargo fmt -p omnibridge-gui -- --check` | clean |
| `./gradlew :app:testDebugUnitTest --tests …BrandingResourcesTest --tests …DesignTokensTest` (JDK 21) | **BrandingResourcesTest 12/12, DesignTokensTest 16/16**, 0 failures. Run because `docs/design/` is on the Android test classpath and gained files. |
| `tooling/validate.py` | 4/4 masters PASS; mono = colour = lockup geometry; `<defs>` byte-identical |
| `tooling/render_checks.py` | transparency and dual-renderer agreement as in §5 |

Not run: the full desktop and Android suites. No production code, resource or
build file changed; the one changed test file is covered above.

---

## 9. Not done in this wave (by instruction)

No product rename, Kotlin package, `applicationId`, Rust namespace, binary,
protocol id, ALPN, mDNS, crypto domain, state migration, systemd, D-Bus,
desktop app id, Play listing, repository, remote, certificate or signing key.
No platform icon sizes were generated. `omnibridge-*` artwork is not retired;
it is retired by the wave that re-points the last derivative at an
**approved** Pliwee master.
