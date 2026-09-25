# Pliwee rebrand — Wave 1: Brand copy & living design docs

| | |
| --- | --- |
| **Status** | **WAVE 1 COMPLETE** (2026-09-24, §15): the Android unit suite ran on JDK 21, **833 passed, 0 failed**; `strings.xml` lint has **0** format-argument issues. G1: **PASS, zero unexplained occurrences**. |
| **Status at commit `86504f0`** (superseded by §15) | **WAVE 1 NOT COMPLETE** — every exit criterion is met except one: the Android unit suite was **NOT EXECUTED** (§8.2). G1: **PASS, zero unexplained occurrences**. |
| **Date** | 2026-09-24 |
| **Branch** | `worktree-pliwee-wave1-brand-copy`, based on `473b200` (`feature/pliwee-rebrand-wave1` = `develop` after PR #5); fast-forwardable onto `feature/pliwee-rebrand-wave1` |
| **Plan** | [PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md § Wave 1](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md#wave-1--brand-copy--living-design-docs) (normative) |
| **Decision** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) §D2 (three layers), §D7 (history), §D8 (name, tagline, Flow Cyan) |
| **Previous wave** | [Wave 0 — BRAND APPROVED](PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md#r4--closure-brand-approved-2026-09-24) |
| **Gate tool** | [`pliwee-wave-1/g1_copy_census.py`](pliwee-wave-1/g1_copy_census.py) |

---

## 1. Scope

Every user-visible sentence that names the **product** now says **Pliwee**,
and every place that showed the tagline now shows ***One flow. Any device.***
Nothing else moved. This is the *visual identity* layer of ADR-0020 §D2 and
only that layer.

**In scope, and done:** Android `app_name`, share-target label, UI strings,
accessibility labels, error and empty-state copy, the `ClipData` label, the
About screen's name and tagline; desktop window, sidebar and header titles,
Quick Panel title and subtitle, tooltips and accessible labels, runtime
messages and errors, the tray title, tooltip title and tooltip body, CLI and
daemon `--help` prose and the CLI's status header; default device names for
**new** identities; `BRAND.md`, `UI-GUIDELINES.md` and the `tokens.json`
comments; the palette name *Bridge Cyan* → *Flow Cyan* (§D8) wherever it is
prose; product-noun prose in the desktop `src/` comments (the G1 area).

**Out of scope, by the plan:** every identifier in plan §2 (W3–W10), the
Devices/Trusted-peers consolidation (W2), all artwork derivatives (W6, W7,
W10), historical documents, `README.md`, `docs/architecture/`,
`docs/policy/PRIVACY-POLICY.md`, `PLAY-STORE-LISTING.md` (W10), packaging
metadata and `desktop/gui/data/*` descriptors (W7). §12 lists the
user-visible consequences.

**Rule for identifier-bearing prose.** A sentence that *quotes* an identifier
keeps the identifier exactly as it is, and only the product noun around it
changed. For example, "Pliwee keeps no history … received files stay in
Downloads/OmniBridge." and "Run `omnibridge pair` on your computer". The
product must not tell a user to type `pliwee` before that binary exists (W7).

## 2. Files changed

124 files modified, 2 added, 0 renamed, 0 deleted.

| Area | Files | What |
| --- | --: | --- |
| `android/app/src/main/res/values/strings.xml` | 1 | 15 strings: `app_name`, `share_target_label` and 13 prose strings (§3) |
| `android/app/src/main/res/drawable/ic_*.xml` | 31 | XML comment "OmniBridge icon set" → "Pliwee icon set" |
| Android Kotlin (main) | 10 | user-visible literals only: `ClipboardTarget`, `SystemClipboard`, `FileTransferManager`, `DevicesScreen`, `MainActivity`, `OmniBridgeShell`, `SendActivity`, `SettingsScreen`, `UiMapping`; `ui/theme/Color.kt` (Flow Cyan, comment) |
| Android tests | 7 | unit: `BrandingResourcesTest`, `ClipboardSyncTest`, `DesignTokensTest` (message only), `SendRetryTest`, `UiMappingTest`; instrumented: `AppPickerUiTest`, `NotificationConsentUiTest` |
| Desktop `src/` | 38 | GUI (`lib.rs`, `panel/`, `views/`, `widgets.rs`, `client.rs`, `approval.rs`, `selection.rs`, `theme.rs`), tray (`platform-linux/src/tray/*`, `lib.rs`, `activation.rs`), CLI, daemon, runtime, control, core, proto, capabilities |
| Desktop tests | 5 | `core/tests/identity_and_store.rs` (+2 tests), `gui/src/panel/model/tests.rs`, `platform-linux/tests/{tray_dbus,tray_gnome,tray_model}.rs` |
| `desktop/gui/data/style.css` | 1 | comment: Bridge Cyan → Flow Cyan |
| `docs/design/` | 31 | `BRAND.md`, `UI-GUIDELINES.md`, `tokens.json` (3 `$comment`s), `assets/icons/*.svg` (28 comments) |
| **Added** | 2 | this report; `pliwee-wave-1/g1_copy_census.py` |

**Conversions** (counted from the diff; tests counted apart):

| | product noun OmniBridge → Pliwee | old → new tagline | Bridge Cyan → Flow Cyan |
| --- | --: | --: | --: |
| Android resources | 51 (20 strings + 31 comments) | — | — |
| Android Kotlin main | 16 | 1 | 2 |
| Desktop `src/` (incl. `style.css`) | 136 | 4 | 5 |
| `docs/design/` | 49 removed, section-level rewrite of `BRAND.md` | 3 | 6 |
| **Product total** | **252** | **8** | **13** |
| Tests (expected text) | 24 (Android 15, desktop 9) | 3 | 2 (messages) |

## 3. Copy: before → after

### Android

| Where | Before | After |
| --- | --- | --- |
| `app_name` (launcher, recents, Settings → Apps) | OmniBridge | **Pliwee** |
| `share_target_label` (Sharesheet) | Send with OmniBridge | Send with Pliwee |
| About screen, name + mark `contentDescription` | OmniBridge | Pliwee |
| About screen, tagline | One bridge. Any device. | **One flow. Any device.** |
| Devices screen title | OmniBridge | Pliwee |
| `ClipData` label (`SystemClipboard.DEFAULT_LABEL`, `ClipboardTarget` default) | OmniBridge | Pliwee |
| Clipboard read refusal | Android would not let OmniBridge read the clipboard. Open OmniBridge and try again … | … Pliwee … Pliwee … |
| Send failure fallback | OmniBridge could not send that file. | Pliwee could not send that file. |
| Unsendable name | that file has no name OmniBridge can send safely | … Pliwee … |
| Wrong QR | That QR code is not a OmniBridge pairing code. | That QR code is not a Pliwee pairing code. |
| Share with nothing paired / granted (×4) | Open OmniBridge and scan … / … in OmniBridge first. | Open Pliwee … / … in Pliwee first. |
| Security card, privacy card | OmniBridge talks straight … / OmniBridge has no account … | Pliwee … |
| 13 prose strings (notification disclosure, access, picker, dismiss, privacy; files scope, empty state, open failure; clip received) | OmniBridge | Pliwee (placeholders unchanged, §8.3) |
| `files_recent_scope` | … OmniBridge keeps no history … stay in Downloads/OmniBridge. | … **Pliwee** keeps no history … stay in Downloads/**OmniBridge**. (path is W6) |
| Unchanged, identifier | "Run \`omnibridge pair\` …", scanner prompt "\`omnibridge pair\`", "Saved to Downloads/OmniBridge" | unchanged (W7, W6) |

### Desktop

| Where | Before | After |
| --- | --- | --- |
| Settings window title | OmniBridge Settings | Pliwee Settings |
| Header title, sidebar and content page titles | OmniBridge | Pliwee |
| Quick Panel `AdwWindowTitle` | OmniBridge / *One bridge. Any device.* | **Pliwee / *One flow. Any device.*** |
| Quick Panel window title | OmniBridge | Pliwee |
| Header button tooltip + accessible label | Open the OmniBridge Quick Panel | Open the Pliwee Quick Panel |
| Panel button, tooltip + accessible label | Open OmniBridge Settings | Open Pliwee Settings |
| Panel status / blocked actions | Connecting to the OmniBridge service… · OmniBridge keeps trying … · The OmniBridge service is not running. · OmniBridge service is not available · … | the same with Pliwee |
| Settings page | name "OmniBridge", caption *One bridge. Any device.* | name "Pliwee", caption ***One flow. Any device.*** |
| Pairing page (text + QR accessible label) | Scan this code with OmniBridge … | … Pliwee … |
| Clipboard / notifications / transfers pages | OmniBridge keeps no … history … | Pliwee keeps no … history … |
| Dashboard / settings when the daemon is down | The OmniBridge daemon is not reachable … | The Pliwee daemon … |
| Tray `ITEM_TITLE`, `TOOLTIP_TITLE` | OmniBridge | **Pliwee** |
| Tray `TOOLTIP_BODY` | One bridge. Any device. | **One flow. Any device.** |
| Tray and activation log / error lines | … the OmniBridge tray item …, … OmniBridge's D-Bus service file … | … Pliwee … |
| CLI `--help` about, status header, pairing prompt | OmniBridge control · OmniBridge · Scan this with OmniBridge on your phone. | Pliwee control · Pliwee · Scan this with Pliwee on your phone. |
| Daemon `--help` about | OmniBridge daemon | Pliwee daemon |
| Identity/store/control errors | … OmniBridge never generates / will not generate / will not bind … | … Pliwee … |
| Unattended file decline (log) | Open the OmniBridge desktop application … | Open the Pliwee desktop application … |
| Unchanged, identifier | `#[command(name = "omnibridge")]`, `omnibridged`, "Run: omnibridge pair", `<XDG downloads>/OmniBridge` | unchanged (W7, W4) |

No harness greps any changed log or error line: every `OmniBridge`
occurrence under `packaging/` and `.github/` was checked, and none reads a
desktop log line that changed. The Android CI guard string ("OmniBridge
release signing is not configured") is in `build.gradle.kts`, which was not
touched.

## 4. Default device names

| Constant | Before | After | When it is used |
| --- | --- | --- | --- |
| `core/src/platform/unix_fs.rs` `default_device_name()` fallback | `OmniBridge Desktop` | **`Pliwee Desktop`** | only at identity **creation** (`Resolution::Create`), and only when both `/etc/hostname` and `/proc/sys/kernel/hostname` are empty |
| `core/src/store.rs` `Settings::default()` | `OmniBridge Device` | **`Pliwee Device`** | placeholder of a hand-built `Settings`; never reached by the daemon's own path |

**Existing devices are not renamed, and there is no migration.**
`StateFile.settings` has no `#[serde(default)]`, so a stored `device_name` is
always read back verbatim. Peers already store the advertised name. Fingerprints,
identities and peer records are untouched. Two tests pin this:

* `the_placeholder_device_name_is_the_product_name`: `Settings::default()` is `Pliwee Device`.
* `a_stored_device_name_survives_the_rename`: creates a store, rewrites
  `settings.device_name` in `state.json` to `OmniBridge Desktop` (after first
  asserting the field exists), reopens, and asserts the name is still
  `OmniBridge Desktop`.

The `Pliwee Desktop` fallback is not unit-tested. The machine running the
test always has a hostname, and making it reachable would mean refactoring
`default_device_name()`, which is outside a copy wave. G1 anchors the literal
(§9).

## 5. Identifiers deliberately preserved

Each is classified by owning wave in the G1 census (§9–§10). The main ones:

| Identifier (as it stays) | Owner |
| --- | --: |
| Rust crates `omnibridge-*`, paths `omnibridge_*::`, lib `omnibridge_gui`; protobuf `omnibridge.v1[.capabilities]` | W3 |
| Kotlin types `OmniBridge*` (`OmniBridgeTheme`, `OmniBridgeBrandMark`, …), `Modifier.omniBridgeContentColumn`, `OmniBridgeShell.kt` file name | W3 |
| Android resources `Theme.OmniBridge`, `Theme.OmniBridge.Dialog`, `omnibridge_background[_dark]`, `omnibridge_accent` | W3 |
| Log tags `OmniBridgeApp`/`OmniBridgeListener`, stderr prefix `omnibridge-gui:`, X11 atom, thread name, `.omnibridge-<id>.part` | W3 |
| `~/.local/share/omnibridge`, `~/.config/omnibridge/gui.json`, `$XDG_RUNTIME_DIR/omnibridge/control.sock`, `/tmp/omnibridge-<uid>`, `~/Downloads/OmniBridge` | W4 |
| ALPN `omnibridge/1`, `omnibridge-data/1`; `_omnibridge._tcp.local.`; QR `omnibridge1:`; pairing/files/notifications domains; CN `omnibridge:<id>` | W5 |
| `applicationId`/`namespace`/Kotlin package `io.github.yurisismotto.omnibridge`, intent actions, Keystore aliases, `Download/OmniBridge`, `logo_omnibridge_mark`, launcher layers | W6 |
| Binaries `omnibridge`, `omnibridged`, `omnibridge-gui` and every "Run: omnibridge …" hint; app id / D-Bus name / object path / SNI id `io.github.yurisismotto.omnibridge`; `.desktop`/metainfo/D-Bus service/gresource; `omnibridged.service`; package names | W7 |
| `omnibridge-*.svg` artwork (still what the builds draw) | W6/W7 |
| Privacy-policy URL, `github.com/yurisismotto/OmniBridge`, `PLAY-STORE-LISTING.md`, `play/render.sh` | W9/W10 |

## 6. Historical documentation deliberately preserved

Nothing under `docs/audits/`, `docs/certification/`, `docs/reports/` (except
the two added files), `docs/research/`, `docs/migrations/`, `docs/adr/` or
`docs/policy/` changed, by `git diff --name-only` over those paths (empty). No
superseding note was needed. No historical claim is contradicted by a copy
change, because Wave 1 changed no identifier that a historical document
asserts.

History kept **inside** active files, per ADR-0020 §D7:

* `BRAND.md`: *Previous names* row (OmniBridge → AnyFlow, with links to
  ADR-0020, ADR-0018 and the migration note), the lapsed OmniBridge naming
  family, the former colour name, and the icon family's provenance.
* `BRAND.md`: the sections on the OmniBridge **artwork**, retitled *Shipped
  artwork: OmniBridge, until W6 and W7*, with a dated note. That artwork is
  still what the builds draw, so it is described as shipped, not rewritten.
* `desktop/core/src/identity.rs` (×3) and `platform/unix_fs.rs` (×1):
  statements about what OmniBridge shipped and the installed v1.0.0 base.
  "Pliwee has always shipped" would be false.

## 7. Tests changed

Every change is **expected text only**. No assertion was removed, weakened or
re-scoped, and no security, authorization, protocol, persistence or identity
suite was touched.

| Test | Change | Fact that changed |
| --- | --- | --- |
| `BrandingResourcesTest` `the app label is the product name …` | `app_name` expected `Pliwee` | product name |
| `ClipboardSyncTest:615` | contains `Open Pliwee` | refusal copy |
| `SendRetryTest:419`, `UiMappingTest` (6 literals) | `Pliwee could not send that file.` / `… no name Pliwee can send safely` | error copy |
| `DesignTokensTest` | two failure *messages*: Bridge Cyan → Flow Cyan | colour name (no assertion) |
| `AppPickerUiTest` (instrumented) | own-package label fixture and its two absence checks: `Pliwee` | the app's own label is `app_name`. The own-package exclusion it proves is unchanged. |
| `NotificationConsentUiTest` (instrumented) | two on-screen substrings | disclosure copy |
| `tray_model.rs` | `ITEM_TITLE == "Pliwee"`; the T11 allow-list of strings that may leave the process: `"Pliwee"`, `"One flow. Any device."` | tray copy. The list stays exact, so the privacy property is unchanged. |
| `tray_dbus.rs`, `tray_gnome.rs` | `Title` / `facts.title` = `Pliwee`; the same allow-list | tray copy over D-Bus |
| `panel/mod.rs` tests (in `src`) | button `Open Pliwee Settings`; toast contains `Pliwee service is not available` | panel copy |
| `panel/model/tests.rs` | client-error fixture and headline | panel copy |
| `core/tests/identity_and_store.rs` | **+2 tests** (§4) | default device name |

One change was caught by the suite rather than by review. The first run of
`tray_model.rs` T11 failed because the allow-list still named `"OmniBridge"`
while the tray published `"Pliwee"`. The allow-list value was updated and the
check was kept exact.

## 8. Tests executed

**How.** A first attempt ran `cargo test --workspace` with default
parallelism (16 jobs) in the background. It exhausted the workstation and
froze it, and it produced no result, so it counts for nothing. Everything
below was then run in the foreground, one crate group at a time, with
`-j 2`.

### 8.1 Executed

| Command (from the worktree root) | Result |
| --- | --- |
| `cargo fmt --manifest-path desktop/Cargo.toml --all -- --check` | **clean** (after `cargo fmt`, which only joined three calls whose strings got shorter) |
| `cargo test … -j 2 -p omnibridge-core` | **194 passed**, 0 failed, 0 ignored (includes the 2 new tests) |
| `cargo test … -j 2 -p omnibridge-linux` | **85 passed**, 0 failed, 1 ignored (`needs a real desktop session bus`). `tray_dbus` 19 and `tray_gnome` 18 ran on a private bus. |
| `cargo test … -j 2 -p omnibridge-gui` | **156 passed** (131 unit + 25 `brand_assets`), 0 failed, 1 ignored |
| `cargo test … -j 2 -p omnibridge-gui --lib -- --ignored every_page_widget_tree` (Wayland session, `WAYLAND_DISPLAY=wayland-0`) | **1 passed**: every page's widget tree builds with the new copy |
| `cargo test … -j 2 --no-fail-fast` over `-daemon -cli -runtime -control -proto -capability-{battery,clipboard,files,notifications}` | **608 passed**, 0 failed, 22 ignored, across 49 test binaries |
| **Desktop total** | **1 044 passed, 0 failed**, 23 ignored (hardware/session gates, unchanged) |
| `python3 docs/reports/branding/pliwee-wave-1/g1_copy_census.py` | **G1 PASS** (§9) |
| G1 mutation: `<string name="mutant">Open OmniBridge</string>` added to `strings.xml` | **G1 FAIL**, 1 unexplained, exit 1. File restored, `cmp`-identical, G1 PASS again. |
| `strings.xml` validation (§8.3) | well-formed; 0 placeholder mismatches |
| Frozen masters, `sha256sum -c` against Wave 0 §R4.2 | **5/5 identical** (§11) |

### 8.2 NOT EXECUTED

> **Superseded 2026-09-24, on `feature/pliwee-rebrand-wave1` at `86504f0`:**
> JDK 21 (Temurin 21.0.12.1) is now installed. The Android unit suite and
> lint have run, and the instrumented sources compile; see §15. The table
> below is what was true at commit time.

| Suite | Reason |
| --- | --- |
| **Android unit suite** (`./gradlew :app:testDebugUnitTest`, incl. `BrandingResourcesTest`, `DesignTokensTest`, `UiMappingTest`, `SendRetryTest`, `ClipboardSyncTest`) | **NOT EXECUTED.** The Gradle wrapper is 8.11.1, which cannot run on the only JDK on this machine (OpenJDK 25.0.4.1). Wave 0 ran this suite on JDK 21, which is not installed here (no `/usr/lib/jvm/java-21*`, no Android Studio JBR, no toolchain under `~/.gradle/jdks`). No result is inferred. |
| Android instrumented tests (`AppPickerUiTest`, `NotificationConsentUiTest`, …) | **NOT EXECUTED.** They need a device. The two changed files were edited for expected text only. |
| Android lint (`:app:lintDebug`) | **NOT EXECUTED**, same toolchain reason. §8.3 covers the specific risk the plan names (format args). |
| Real GNOME / KDE visual check | Not required by the Wave 1 plan. The widget-tree test ran under a real Wayland session. |

### 8.3 `strings.xml` (the plan's "no missing format args")

Parsed with `xml.etree` before (`HEAD`) and after: same 151 string names,
15 texts changed, and **0** strings whose `%n$s`/`%n$d` placeholder multiset
differs.

## 9. G1 — copy census

Output abridged: the per-owner lines are §10 and the eight anchor lines are summarised.

```console
$ python3 docs/reports/branding/pliwee-wave-1/g1_copy_census.py
G1 copy census over: android/app/src/main/res desktop/*/src/* desktop/capabilities/*/src/* docs/design
lines matched: 576   occurrences: 612   independent count (git grep -o): 612
case variants: {'OMNIBRIDGE': 2, 'OmniBridge': 81, 'omniBridge': 1, 'omnibridge': 528}

by category:
   536  1 identifier owned by a later wave
    15  2 historical context (ADR-0020 D7)
     6  3 test fixture
    55  5 artwork still shipped until W6/W7

old tagline 'one bridge': 4 line(s), unexplained 0
anchors: 8/8 ok
UNEXPLAINED: 0

G1: PASS — ZERO UNEXPLAINED OCCURRENCES
```

**How the gate protects itself** (AGENTS.md):

| Check | How |
| --- | --- |
| the tool exists | refuses with exit 2 if `git` is absent |
| the capture is non-empty | fails if the three areas match nothing |
| the count is exact | per-token occurrence count must equal an independent `git grep -o` count (612 = 612) |
| the operation ran | 8 positive anchors must be present: `app_name` Pliwee, tray title, tray tagline, Quick Panel title + tagline, Android About tagline, both default names, `ClipData` label. An absence of "OmniBridge" does not count as a pass if Pliwee isn't there. |
| no match lost | reads `git grep` output whole; no pipe into `grep -q` |
| can fail | the mutation in §8.1 turned it red |
| case | `-i`, so `OmniBridge`, `omnibridge`, `OMNIBRIDGE` and `omniBridge` are all counted; `-a` so no binary file is skipped |

Category 4 of the brief ("compatibility value owned by a later wave") has no
member. Wave 1 introduced no compatibility value. **Category 5** was added
because the brief's list is open: *artwork still shipped until W6/W7*
(`omnibridge-*.svg` file names and prose describing the mark the builds
still draw). It is neither an identifier nor history. It is the current
product artwork, which Wave 0 said stays until its derivatives move.

**Old tagline:** 4 lines left, all classified: `BRAND.md` *Previous names* row
(history), `BRAND.md` *Tagline drawn by the lockup* (the shipped OmniBridge
lockup, W6/W7), `PLAY-STORE-LISTING.md` (W10), and `widgets.rs:352` (what
the OmniBridge mark still drawn by the GTK empty state means, W7).

## 10. Remaining occurrences, classified

612 occurrences in the three G1 areas (19 in `android/app/src/main/res`, 499
in desktop `src/`, 94 in `docs/design`), by owner and reason, as printed by
the gate:

| n | Cat. | Owner | Reason |
| --: | :-: | --- | --- |
| 249 | 1 | W3 | Rust crate path (`omnibridge_core::…`) |
| 38 | 1 | W3 | Rust crate name |
| 19 | 1 | W3 | Kotlin/Rust type or function name |
| 14 | 1 | W3 | stderr log prefix `omnibridge-gui:` |
| 13 | 1 | W3 | Android resource name |
| 4 | 1 | W3 | protobuf package |
| 4 | 1 | W3 | X11 atom / thread name / temp prefix |
| 1 | 1 | W3 | `UI-GUIDELINES.md` note on the Kotlin type prefix |
| 30 | 1 | W3/W7 | `omnibridge-gui`, both crate and binary |
| 14 | 1 | W4 | data / config / runtime path |
| 6 | 1 | W4 | path component (`join("omnibridge")`, `Some("OmniBridge")`) |
| 4 | 1 | W4 | desktop download dir |
| 13 | 1 | W5 | ALPN / mDNS / QR / domain separator |
| 1 | 1 | W5 | certificate CN |
| 1 | 1 | W6 | Android download dir (`files_recent_scope`) |
| 1 | 1 | W6 | Android drawable name `logo_omnibridge_mark` |
| 61 | 1 | W7 | CLI binary / package name in commands and hints |
| 22 | 1 | W7 | binary / unit / D-Bus service / gresource / activation name |
| 18 | 1 | W7 | desktop app id / D-Bus name / object path, incl. near-miss test fixtures |
| 2 | 1 | W7 | `BRAND.md` quoting `omnibridge pair` |
| 1 | 1 | W7 | prose naming the app id (`dbus.rs:56`) |
| 1 | 1 | W7 | doc of the `APP_ID` constant (`dbus.rs:70`) |
| 1 | 1 | W7 | app-id near-miss test comment (`activation.rs:468`) |
| 1 | 1 | W3–W10 | `BRAND.md` naming the identifier set later waves own |
| 15 | 1 | W10 | `PLAY-STORE-LISTING.md` (listing copy, lengths, URLs) |
| 2 | 1 | W10 | `play/render.sh` source paths |
| 6 | 2 | — | lapsed OmniBridge naming family (`BRAND.md`) |
| 3 | 2 | — | *Previous names* row |
| 1 | 2 | — | former colour name |
| 1 | 2 | — | icon-family provenance |
| 4 | 2 | — | what OmniBridge shipped / its installed base (`identity.rs`, `unix_fs.rs`) |
| 5 | 3 | W3 | test temp-dir prefixes, a test name, arbitrary payload bytes |
| 1 | 3 | W7 | activation-token fixture carrying the app name |
| 36 | 5 | W6/W7 | `omnibridge-*.svg` file names |
| 15 | 5 | W6/W7 | `BRAND.md` prose on the shipped artwork |
| 3 | 5 | W7 | `widgets.rs` doc on the GTK brand mark |
| 2 | 5 | W7 | tray icon is `omnibridge-app-icon.svg` |
| **612** | | | **0 unexplained** |

## 11. Frozen Wave 0 masters

`sha256sum -c` against the digests recorded in Wave 0 §R4.2, before the first
edit and again before commit: **5/5 OK**. `git diff -- docs/design/assets/pliwee-*.svg`
is empty. The Wave 1 edit script also refused any path in the frozen set.

| Master | SHA-256 |
| --- | --- |
| `pliwee-mark.svg` | `b1d927564f25c8c59361eb3a7a5cad845ce18428421a053b25cbe1943440519c` |
| `pliwee-mark-mono.svg` | `15120dd82ba288f51854baec6820f93f72d78bcc1d029451d3b88691cb510fdf` |
| `pliwee-mark-tonal.svg` | `99201df067a31aed898f45d31b0d04a01e430a6d4f4e7c595357996428d7ee1b` |
| `pliwee-wordmark.svg` | `6220f2e8d275357f010c9456ca75bddfccfe25ea587969fa61933d4aeeafaf13` |
| `pliwee-lockup.svg` | `78792f3e978bdc97b7f16efbdcd92d08f9e1771f6ad5d674ff0c9ea0423245de` |

## 12. Limitations and pending items

1. **Android unit suite not executed** (§8.2). That is the only reason this
   wave is not complete. To close it, install a JDK 21, run
   `./gradlew :app:testDebugUnitTest --max-workers=2` in `android/`, and
   record the counts here.
2. **Surfaces that still say OmniBridge after Wave 1, owned elsewhere by the
   plan**, and user-visible:
   * the launcher entry `Name=OmniBridge` / `Comment=One bridge. Any device. …`
     in `desktop/gui/data/io.github.yurisismotto.omnibridge.desktop`, and the
     AppStream `<name>` (W7: the plan moves `desktop/gui/data/*` with the app
     id);
   * the notification app name the shell shows for mirrored notifications,
     which comes from that `.desktop` file (W7);
   * `Description=` of `omnibridged.service`, firewalld `<short>`, RPM/deb
     summaries (W7);
   * the Play listing and its graphics (W10);
   * the artwork (W6, W7);
   * `README.md`, `docs/architecture/`, `docs/policy/PRIVACY-POLICY.md`,
     component READMEs, and `android/fixture` strings are not in the Wave 1
     area list. ADR-0020 §D7 expects the living ones to say Pliwee
     eventually, and no wave in the plan names them explicitly yet. **This
     needs a plan decision** before W8's remainder audit.
3. **Android Kotlin KDoc**: 87 comment mentions of OmniBridge in 41 `.kt`
   files remain. They are not user-visible and not in the G1 area (the plan
   scopes Kotlin to string literals). W6 moves all 163 files, which is the
   natural place to sweep them.
4. **`Pliwee Desktop`** is only reachable on a host with no hostname, and it
   is not unit-tested (§4).
5. The `BRAND.md` spelling rule was cut back to "one word, capital P only"
   so that it states only the approved name, not new brand rules. The
   positioning line ("A single flow between devices and platforms.") and the
   "mark is the metaphor" paragraph were adapted from the OmniBridge text to
   the Flow Monogram. Both are brand wording the owner may want to review.

## 13. Exit criteria

> **Superseded 2026-09-24 (§15):** "relevant tests green" is now **met**:
> desktop 1 044/1 044 and Android unit 833/833. The table below is the
> commit-time record.

| Criterion | Result |
| --- | --- |
| every applicable user-visible product noun says Pliwee | **met** in the Wave 1 areas; out-of-area surfaces listed in §12.2 |
| the applicable tagline says *One flow. Any device.* | **met**: Quick Panel, Settings page, tray tooltip, Android About (8 sites incl. docs) |
| new default names correct | **met**: `Pliwee Desktop`, `Pliwee Device`; existing names preserved (§4) |
| no later-wave identifier anticipated | **met**: every identifier-case token in the diff reappears unchanged; §5 |
| Wave 0 masters byte-for-byte intact | **met** (§11) |
| history not rewritten | **met** (§6) |
| relevant tests green | **partly**: desktop 1 044/1 044 green; **Android unit suite NOT EXECUTED** |
| G1 zero unexplained | **met**: 612/612 classified |

## 14. Status

> **Superseded 2026-09-24 by §15: WAVE 1 COMPLETE.** The status below is the
> commit-time record.

**WAVE 1 NOT COMPLETE.** The copy, living docs and G1 gate are done and
verified. One gate is open: the Android unit suite, which could not run on
this machine (§8.2). No PASS is claimed for it. Wave 2 has not started.

## 15. Closure: Android checks (2026-09-24)

Run on `feature/pliwee-rebrand-wave1` at `86504f0` (the Wave 1 commit), with a
clean tree. **No source, test or design file changed.** Only this report was
edited. The desktop suites and the G1 implementation are unchanged since
§8.1, so they were not rerun, except the cheap G1 census and the
master-hash check below.

**Toolchain.** `JAVA_HOME=/usr/lib/jvm/java-21-temurin-jdk` (OpenJDK
Temurin 21.0.12.1+1 LTS), Gradle wrapper 8.11.1, `--no-daemon
--max-workers=2 -Dorg.gradle.parallel=false`. Commands ran one at a time.

### 15.1 Executed

| Command (in `android/`) | Result |
| --- | --- |
| `./gradlew :app:testDebugUnitTest` | **BUILD SUCCESSFUL**, exit 0. `testDebugUnitTest` *executed* (not `FROM-CACHE`); 56 result files, all time-stamped by this run. **833 tests, 0 failures, 0 errors, 0 skipped.** The suites Wave 1 edited: `BrandingResourcesTest` 12/12, `ClipboardSyncTest` 30/30, `DesignTokensTest` 16/16, `SendRetryTest` 21/21, `UiMappingTest` 31/31. |
| `./gradlew :app:compileDebugAndroidTestKotlin` | **BUILD SUCCESSFUL**. The two edited instrumented files (`AppPickerUiTest`, `NotificationConsentUiTest`) compile. |
| `./gradlew :app:lintDebug` | exit 1: **1 error, 36 warnings**. **0** `StringFormat*` issues, so no format arguments are missing (the plan's regression check). The 10 issues on `strings.xml` are `PluralsCandidate` ×4 and `UnusedResources` ×6. The one error is `StartActivityAndCollapseDeprecated` at `ClipboardTileService.kt:100`. That file is untouched since `745541c`, and `android-ci.yml` audits the error as a false positive of a version-gated call and not a gate. |
| same `lintDebug` on the pre-Wave-1 base `473b200`, in a temporary detached worktree (removed afterwards) | exit 1: **1 error, 36 warnings**. Compared by (id, file, line) after normalising the worktree prefix, **the two issue sets are identical**. Wave 1 introduced no lint issue and removed none. |
| `python3 docs/reports/branding/pliwee-wave-1/g1_copy_census.py` | **G1 PASS**, exit 0: 612 occurrences = 612 independent, 8/8 anchors, 0 unexplained. |
| `sha256sum` of the five Wave 0 masters | **5/5** equal the digests in §11. |
| `git diff --check HEAD~1 HEAD` and on the working tree | clean |

### 15.2 Still NOT EXECUTED

| Suite | Reason |
| --- | --- |
| Android instrumented tests (`:app:connectedDebugAndroidTest`) | **NOT EXECUTED.** No emulator is installed. The only device attached is the owner's physical phone (`RX2Y500C7SY`). `connectedAndroidTest` installs and then uninstalls the app under test, which would destroy the installed app's pairing identity and data. Wave 1 lists no hardware gate ("Upgrade / hardware: none"), and Android CI's gate is compile plus unit tests. The two edited files change expected text only and compile (§15.1). |
| Compose previews / Robolectric | **n/a.** The app has no `@Preview` and no Robolectric dependency. `ClipboardShortcutTest` says so explicitly. The desktop widget-tree integration test ran (§8.1). |

### 15.3 Exit criteria, closed

Every row of §13 is **met**. "Relevant tests green" is now desktop
1 044/1 044 (§8.1) plus Android unit 833/833 (§15.1). G1 has zero
unexplained occurrences.

**WAVE 1 COMPLETE.** Wave 2 has not started.
