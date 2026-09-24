# Pliwee rebrand — implementation plan

| | |
| --- | --- |
| **Status** | Plan. Nothing in it is implemented. |
| **Date** | 2026-09-24 |
| **Branch / baseline** | `worktree-pliwee-rebrand-discovery` at `e84049d` (ADR-0020), tree audited at `ba408c6` |
| **Decisions** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) D1–D12, plus the four planning decisions in §0.2 |
| **Evidence** | [PLIWEE-REBRAND-DISCOVERY.md](../../audits/rebrand/PLIWEE-REBRAND-DISCOVERY.md) — its §15 lists every affected file |

**Why it lives here.** [`docs/README.md`](../../README.md) has no "plan"
category. The repository's precedent for an implementation plan written before
the work is `research/<topic>/`:
[`notifications-v1/05-IMPLEMENTATION-PLAN.md`](../notifications-v1/05-IMPLEMENTATION-PLAN.md),
[`platform-expansion/22-IMPLEMENTATION-ROADMAP.md`](../platform-expansion/22-IMPLEMENTATION-ROADMAP.md)
and `28-WAVE-0-IMPLEMENTATION-SPEC.md`. This plan follows it.

---

## 0. Ground rules

### 0.1 Rules for every wave

1. **One wave, one branch, one merge.** A wave merges only when its gate is
   green. Waves 0–7 merge into `develop`. **Nothing is released** before
   Wave 8 certifies, and the first Pliwee artifacts are published in Wave 10.
2. **No search-and-replace.** Each identifier moves in the wave that owns it
   (§2), together with the tests that pin it. A wave may leave `omnibridge`
   in the tree. It may not leave one connection, file or unit carrying two
   names at once. That is the no-hybrid rule of ADR-0020 §D4.
3. **Tests are not weakened.** A test changes only when the fact it asserts
   has changed, and the commit says which fact that is. A dead-identity list
   may drop a value only because ADR-0020 re-adopts it: `"one flow"`, per D8.
   Security and authorization suites (`desktop/daemon/tests/security_certification.rs`,
   `control.rs`, `revoked_cleanup.rs`, `file_approval.rs`, `*_log_privacy.rs`,
   Android `NotificationSecret*`, `PinnedTrustManagerTest`, `PairingProofTest`)
   may only have names changed, never assertions.
4. **Gates follow AGENTS.md.** Each gate checks that its tool exists, that its
   capture is non-empty, that its window is anchored on something the product
   wrote about this run, that its counts are exact, and that it made two
   observations around the operation. It uses the `packaging/tests/lib/assert.sh`
   primitives and never pipes into `grep -q`. An unmeasurable gate is recorded
   as **not executed, with the reason**, never as a pass.
5. **History is not rewritten** (ADR-0020 D7). Files under `docs/audits/`,
   `docs/certification/`, `docs/reports/`, `docs/research/` (other than this
   directory) and `docs/migrations/`, and ADR-0001…0019, are never edited to
   say Pliwee. When a wave invalidates a claim in one of them, it adds a
   dated superseding note that names this plan's wave and ADR-0020.
6. **Evidence per wave.** Each wave writes one report to `docs/reports/branding/`,
   the existing area for rebrand reports. Waves 8 and 11 write certifications
   to `docs/certification/rebrand/`. That is a new `<area>`, because no
   certification area covers a rename; AGENTS.md asks for a new area to be
   proposed rather than defaulting to another one.
7. **Git identity** is verified before every commit, and no AI attribution
   trailer is added (AGENTS.md § Git Authorship Policy).

### 0.2 Planning decisions added on 2026-09-24

| # | Decision | Effect on the plan |
| --- | --- | --- |
| P1 | The final Pliwee privacy-policy URL **does not block** early waves. The new repository is created only after implementation, testing and pre-migration certification. | `PrivacyPolicy.kt`, final Play metadata and every definitive public URL move to **Wave 10**, right before final Android/Play certification. Until then `PrivacyPolicy.kt` keeps the **existing, live** OmniBridge URL — a real URL, never a fake one — and it is **not** adopted as the future canonical URL. Wave 8 records it as a known pre-migration value. |
| P2 | The vector master is a **prerequisite** of all visual work. No geometry is recreated, no SVG invented, no provisional derivative made. | Wave 0 is blocked until the owner supplies the masters. All artwork derives from them. |
| P3 | Visual identity approved: **Pliwee** · *One flow. Any device.* · Inter · `#4F6BFF` `#18B8C9` `#7C5CFC` `#0B1020` `#F7F9FC` · **Flow Monogram**. "Connected Nodes" is rejected as the main mark. | Waves 0, 1 and 10. |
| P4 | Desktop **Devices** and **Trusted peers** become one main area, **Devices**. The internal distinction between device, peer, trusted peer, pairing, trust relationship and capabilities is kept. | Wave 2. |

---

## 1. Wave map

| Wave | Name | Blocked by | Hardware | Est. files |
| --- | --- | --- | --- | --: |
| 0 | Brand asset foundation | **owner-supplied masters (B1, B2)** | — | ~18 |
| 1 | Brand copy & living design docs | — | — | ~70 |
| 2 | Desktop UX — Devices consolidation | — | real desktop session (GNOME + KDE) | ~8 |
| 3 | Code naming / namespace refactor | W2 merged (to avoid churn) | — | ~200 (mechanical) |
| 4 | Linux state & upgrade migration | W3 | VMs with real v1.0.0 packages | ~15 |
| 5 | Protocol / discovery / crypto-domain migration | W3 | **Android device + Linux host** | ~30 |
| 6 | Android identity, package & signing | W5, W0 (icons), operator (D3) | **Android device; two removable media** | ~190 (163 moves) |
| 7 | Linux system integration, packaging, distribution & CI | W3, W4, W0 (icon) | **4 distros + GNOME/KDE** | ~60 |
| 8 | Pre-repository-migration certification | W0–W7 | **full real-host set + Android** | ~6 (docs) |
| 9 | New Pliwee repository migration | W8 PASS | — | ~6 + repo settings |
| 10 | Public URLs, privacy policy, OpenPGP UID, Play finalization | W9, B3 | **Android device; Play Console** | ~25 + 8 PNG |
| 11 | Final Pliwee certification | W10 | **full real-host set + Play-installed Android** | ~5 (docs) |

```
W0 ─────────────────────────────┬──────────────┬────────────┐
W1 ─┐                           │ (icons)      │ (hicolor)  │ (Play art)
W2 ─┴─► W3 ─┬─► W4 ─────────────┼──────────────► W7 ─┐      │
            └─► W5 ─► W6 ◄──────┘                    ├─► W8 ─► W9 ─► W10 ─► W11
                      └──────────────────────────────┘
```

Reordering against the brief, each for a concrete reason:

* **The Kotlin package move is in Wave 6, not Wave 3.** The Kotlin package is
  also the manifest's component namespace. Moving it separately would give test
  devices a second set of `ComponentName`s: a second notification-access grant,
  and a second tile slot. ADR-0020 §"Android component identity" freezes
  components from the first Pliwee build, so the package, the `applicationId`
  and the components move in one wave.
* **Binary names, the desktop app id / D-Bus name and the tray id are in
  Wave 7, not Wave 3.** They are installed paths and OS-persisted ids
  (`/usr/bin/*`, `ExecStart=`, `Exec=`, `StartupWMClass=`, the D-Bus service
  file, the `.desktop` basename, SNI `Id`). Renaming them apart from the
  package transition would leave an intermediate tree whose unit points at a
  binary its package does not install.
* **Wave 4 precedes Wave 7.** The state-migration code is proven against real
  v1.0.0 state first, then again through a real package upgrade in Wave 7.
  One gate that only ever ran through packaging could hide which layer failed.
* **Wave 1 carries no identifier-bearing prose.** A sentence naming a binary,
  path, package or URL changes in the wave that changes that identifier.

---

## 2. Identifier ownership

Every brand-bearing identifier from the audit has exactly one owning wave.

| Identifier | Current | Pliwee | Wave |
| --- | --- | --- | --: |
| Brand masters | `docs/design/assets/omnibridge-*.svg` | `docs/design/assets/pliwee-mark.svg`, `pliwee-mark-mono.svg` (+ wordmark/lockup, B2) | 0 |
| Product name / tagline in UI copy | OmniBridge / *One bridge. Any device.* | Pliwee / *One flow. Any device.* | 1 |
| Default device names | `OmniBridge Desktop`, `OmniBridge Device` | `Pliwee Desktop`, `Pliwee Device` (new identities only) | 1 |
| Android `ClipData` label | `OmniBridge` | `Pliwee` | 1 |
| Desktop pages | `Devices` (`devices`) + `Trusted peers` (`peers`) | `Devices` (`devices`); `peers` redirects | 2 |
| Rust crates / lib targets | `omnibridge-*`, `omnibridge_gui` | `pliwee-*`, `pliwee_gui` | 3 |
| Protobuf package / dir / `java_package` | `omnibridge.v1[.capabilities]`, `protocol/proto/omnibridge/v1/`, `io.github.yurisismotto.omnibridge.proto` | `pliwee.v1[.capabilities]`, `protocol/proto/pliwee/v1/`, `io.github.yurisismotto.pliwee.proto` | 3 |
| Kotlin type names | `OmniBridgeTheme`, `OmniBridgeType`, `OmniBridge*` composables | `PliweeTheme`, … | 3 |
| Log tags, thread names, X11 atom, temp prefixes | `OmniBridgeApp`, `omnibridge-clipboard-x11`, `_OMNIBRIDGE_CLIPBOARD_WATCH_STOP`, `.omnibridge-<id>.part` | `Pliwee*`, `pliwee-*`, `_PLIWEE_*` | 3 |
| Data dir (identity + trust store) | `~/.local/share/omnibridge` | `~/.local/share/pliwee` (+ migration) | 4 |
| Config | `~/.config/omnibridge/gui.json` | `~/.config/pliwee/gui.json` (+ migration) | 4 |
| Runtime dir / socket | `$XDG_RUNTIME_DIR/omnibridge/control.sock`, `/tmp/omnibridge-<uid>` | `…/pliwee/…`, `/tmp/pliwee-<uid>` | 4 (code) · 7 (unit `RuntimeDirectory=`) |
| Desktop download dir | `~/Downloads/OmniBridge` | `~/Downloads/Pliwee` | 4 |
| ALPN (control / data) | `omnibridge/1`, `omnibridge-data/1` | `pliwee/1`, `pliwee-data/1` (+ legacy profile) | 5 |
| mDNS / NSD | `_omnibridge._tcp.local.` | `_pliwee._tcp.local.` (+ legacy advertise/browse) | 5 |
| QR scheme | `omnibridge1:` | emits `pliwee1:`; accepts both | 5 |
| Pairing / confirm / files domains | `omnibridge/…/v1` | `pliwee/…/v1` (per profile) | 5 |
| Notification id/group/content domains | `omnibridge/notifications.v1/…` | `pliwee/notifications.v1/…` (canonical only) | 5 |
| Certificate CN (new identities) | `omnibridge:<id>` | `pliwee:<id>` | 5 |
| Android `applicationId` / `namespace` / Kotlin package | `io.github.yurisismotto.omnibridge` | `io.github.yurisismotto.pliwee` | 6 |
| Android components | `.notifications.OmniBridgeNotificationListener`, `.ui.ClipboardTileService`, `.ui.MainActivity`, `.ui.SendActivity` | under the new package, then **frozen** | 6 |
| Android Keystore aliases | `omnibridge-identity-v1`, `omnibridge-notification-secret-v1` | `pliwee-identity-v1`, `pliwee-notification-secret-v1` (restart) | 6 |
| Android intent actions | `io.github.yurisismotto.omnibridge.*` | `io.github.yurisismotto.pliwee.*` | 6 |
| Android download dir | `Download/OmniBridge` | `Download/Pliwee` | 6 |
| Android signing identity | `CN=OmniBridge`, `omnibridge-{app-signing,upload}` | `CN=Pliwee`, `pliwee-{app-signing,upload}` | 6 |
| Android build env / Gradle property | `OMNIBRIDGE_UPLOAD_KEYSTORE[_PASSWORD]`, `-Pomnibridge.release.unsigned` | `PLIWEE_*`, `-Ppliwee.release.unsigned` | 6 |
| Fixture `applicationId` | `…omnibridge.fixture` | `…pliwee.fixture` | 6 |
| Android launcher / adaptive / monochrome icons | `ic_launcher_*`, `logo_omnibridge_mark.xml` | derived from W0 masters | 6 |
| Binaries | `omnibridge`, `omnibridged`, `omnibridge-gui` | `pliwee`, `pliweed`, `pliwee-gui` | 7 |
| Desktop app id / D-Bus / `.desktop` / AppStream / hicolor / SNI | `io.github.yurisismotto.omnibridge` | `io.github.yurisismotto.pliwee` | 7 |
| systemd user unit | `omnibridged.service` | `pliweed.service` (+ transition) | 7 |
| firewalld service | `omnibridge.xml` | `pliwee.xml` (+ legacy file kept) | 7 |
| RPM / deb packages | `omnibridge`, `omnibridge-gui` | `pliwee`, `pliwee-gui` (Obsoletes/Replaces) | 7 |
| Harness / CI env vars, container names | `OMNIBRIDGE_*`, `omnibridge-rpm-buildroot` | `PLIWEE_*` | 7 |
| Release artifact names | `omnibridge-<V>…` | `pliwee-<V>…` | 7 (pipeline) · 10 (first publish) |
| Repository, remotes, badges, metadata URLs | `github.com/yurisismotto/OmniBridge` | `github.com/yurisismotto/pliwee` | 9 · 10 |
| Privacy-policy URL (compiled + Play) | `…/OmniBridge/blob/main/docs/policy/PRIVACY-POLICY.md` | decided at W10 (B3) | 10 |
| OpenPGP UID | `OmniBridge Release Signing Key` | add `Pliwee Release Signing Key` | 10 |
| Play listing, icon, feature graphic, screenshots | OmniBridge | Pliwee | 10 |

**Not renamed, in any wave:** capability ids, TCP 55432, mDNS TXT keys,
protobuf field numbers and types, the frozen DER vectors and their KATs
(D10), the v1.0.0 release and its assets, and historical documents.

---

## Wave 0 — Brand asset foundation

> **Closed 2026-09-24: BRAND APPROVED** at commit `1ea65e6`. The five
> masters (`pliwee-mark.svg`, `-mono`, `-tonal`, `pliwee-wordmark.svg`,
> `pliwee-lockup.svg`) are canonical and frozen. They are a controlled
> reconstruction of the owner's raster board, approved by the owner, rather
> than supplied SVGs; B1 and B2 are resolved by that approval. Derivatives
> (W6, W7, W10) start from them. See
> [the Wave 0 report §R4](../../reports/branding/PLIWEE-WAVE-0-BRAND-ASSET-FOUNDATION.md#r4--closure-brand-approved-2026-09-24)
> and [`BRAND.md`](../../design/BRAND.md#pliwee-vector-masters).

| | |
| --- | --- |
| **Objective** | Install the owner-approved vector masters as the single source of truth, and re-point every derivative and every outline-equality test at them. |
| **Prerequisites** | **B1:** `pliwee-mark.svg` and `pliwee-mark-mono.svg`, supplied and approved by the owner. **B2:** approved wordmark and lockup vectors, or an owner-approved rule for producing them from the board. Nothing starts without these. |
| **Master location** | `docs/design/assets/pliwee-mark.svg` and `docs/design/assets/pliwee-mark-mono.svg`. The brief suggested `assets/brand/`; the repository convention is `docs/design/assets/`, which `docs/README.md` names as the place "the build reads the app icon", `desktop/gui/build.rs` reads from, and both brand tests read the canonical outline from. A root `assets/` directory would be a second source of truth. |
| **Areas** | `docs/design/assets/` · `desktop/gui/build.rs`, `desktop/gui/data/*.gresource.xml`, `desktop/gui/src/widgets.rs` (brand mark) · `android/app/src/main/res/drawable/{logo_*_mark,ic_launcher_foreground,ic_launcher_monochrome}.xml`, `res/values/colors.xml` (launcher background) · `desktop/gui/tests/brand_assets.rs`, `android/app/src/test/…/BrandingResourcesTest.kt` · `docs/design/BRAND.md` |
| **Derived assets** | app icon (`pliwee-app-icon.svg`) · Android monochrome source (`pliwee-android-monochrome.svg`) · Android brand drawable · adaptive-icon foreground and monochrome layers · hicolor `io.github.yurisismotto.pliwee.svg`, generated by `build.rs` at build time (the gresource/icon *id* stays at W7) · wordmark and lockup · later: Play 512 px icon, feature graphic and screenshots (W10). **No favicon exists** (no web surface), no splash resource exists, and the tray uses the app icon by name, so there is no tray-icon file to derive. |
| **Identifiers** | asset filenames only; no persistent or wire identifier |
| **Migrations** | none |
| **Compatibility** | none |
| **Allowed** | adding the masters byte-for-byte as supplied; mechanical derivations whose outline tests prove equality; retiring the `omnibridge-*` artwork (deleted, as ADR-0018's visual closure did). `ribbon_connection.xml` / `OmniBridgeRibbonFlourish` is kept or removed only on an explicit owner decision. |
| **Forbidden** | redrawing, retracing, simplifying or "optically adjusting" the Flow Monogram; provisional placeholders; any "Connected Nodes" artwork; changing palette hex values; touching app ids, gresource prefixes or icon theme names (W7). |
| **Unit tests** | `brand_assets.rs`, `BrandingResourcesTest.kt`: every derivative carries the master outline **byte-for-byte**. Dead lists gain `omnibridge` and `one bridge` and lose `one flow` (the D8 re-adoption), and the new asset names avoid `flow-a`/`flow_a`/`flowing` rather than removing those entries. |
| **Integration** | `cargo build -p omnibridge-gui` compiles the new gresource; `:app:assembleDebug` resolves the launcher layers. |
| **Regression** | `DesignTokensTest.kt` and `tokens.json` unchanged (the palette is equal); the full desktop and Android unit suites. |
| **Upgrade / hardware** | none |
| **Rollback** | revert the merge; the old artwork comes back from history. |
| **Exit criteria** | masters committed exactly as supplied (SHA-256 recorded in the wave report); zero active asset outside the derivation chain; both brand tests green, with the dead-list diff shown and justified. |
| **Gate** | **G0 — artwork provenance.** Each derivative is traced to the master by test; the master digest equals the supplied file's. |
| **Unblocks** | W6 launcher icons; W7 hicolor icon; W10 Play art. W1–W5 do not depend on it. |

---

## Wave 1 — Brand copy & living design docs

| | |
| --- | --- |
| **Objective** | Every user-visible sentence that names the *product* says Pliwee, with the approved tagline. No identifier changes. |
| **Areas** | `android/app/src/main/res/values/strings.xml` (`app_name`, ~17 lines) and `themes.xml`/`colors.xml` *display* names only · 18 Android `.kt` files with product names in string literals (e.g. `SystemClipboard.DEFAULT_LABEL`) · 41 desktop `src/*.rs` files with product prose (GUI panel/views/model, tray `ITEM_TITLE`/`TOOLTIP_TITLE`, daemon/CLI `about=`, runtime messages) · the 18 test files asserting that text · default device names (`core/src/platform/unix_fs.rs:245`, `core/src/store.rs:221`) · `docs/design/BRAND.md`, `UI-GUIDELINES.md`, `tokens.json` comments · desktop panel subtitle (`panel/mod.rs:110`) |
| **Prerequisites** | none; can run in parallel with W2 |
| **Identifiers** | none. **Kept exactly:** any string that names a binary (`omnibridge pair`), a path (`Downloads/OmniBridge`), a package, a URL or an app id. Those sentences change in the wave that owns the identifier (§2). |
| **Migrations** | none. The default device name only affects identities created afterwards; existing names belong to the user and peers already store them. |
| **Compatibility** | none |
| **Allowed** | product noun, tagline, Android `app_name`, window titles, tray title and tooltip, accessibility labels, empty-state copy. |
| **Forbidden** | resource *names* (`Theme.OmniBridge`, `omnibridge_accent` belong to W3), log tags, Kotlin/Rust identifiers, and any historical document. |
| **Unit tests** | the ~18 suites that assert copy (`panel/model/tests.rs`, `panel/mod.rs` tests, `views/*` tests, Android UI-mapping tests) change their expected text and nothing else. The diff is reviewed for "expected string only". |
| **Integration** | Compose previews / Robolectric UI tests; desktop `--ignored` widget-tree test under a display. |
| **Regression** | full suites; `strings.xml` lint (no missing format args). |
| **Upgrade / hardware** | none |
| **Rollback** | revert; text only. |
| **Exit criteria** | `git grep -n 'OmniBridge'` over `android/app/src/main/res`, the desktop `src/` trees and `docs/design/` returns only (a) identifier-bearing sentences owned by later waves, each listed in the wave report, and (b) intentional history lines in `BRAND.md` ("Previous names"). |
| **Gate** | **G1 — copy census.** An exact count of remaining product-noun occurrences, each classified; zero unexplained. |
| **Unblocks** | W10 screenshots (the UI text must be final first). |

---

## Wave 2 — Desktop UX: Devices consolidation

### Current state, measured

| Page | Route | File | Holds |
| --- | --- | --- | --- |
| **Devices** | `devices` | `desktop/gui/src/views/devices.rs` (73 lines) | read-only list of every known device, revoked included: name, platform icon, **short** fingerprint, platform, paired/connected facts |
| **Trusted peers** | `peers` | `desktop/gui/src/views/peers.rs` (376 lines) | the trust store: capability grant rows (`clipboard.v1`, `files.v1`, `battery.v1`) via `Request::Grant`; **full** fingerprint; device id; "Revoke this device" (`Request::Unpair`, confirmed, fingerprint shown); "Remove from list" (`Request::HideRevokedDevice`, keyed by **fingerprint**) and "Remove all revoked devices" (`Request::HideAllRevokedDevices`); clears the GUI peer choice (`pages.forget_peer_choice`) |

Entry points: the sidebar (`Page::ALL`, `gui/src/lib.rs:268-275`), the stack
(`views/mod.rs:203-204`), and `--page <name>` / `--page=<name>`
(`Launch::parse`, pinned by the test at `lib.rs:915`: `--page=peers` →
`Page::TrustedPeers`). `app.settings`, the tray and the Quick Panel pass
**no** page, and no other view links to either page. User-facing references:
`README.md:123` and `docs/design/UI-GUIDELINES.md:210`. Authorization is
enforced by the **daemon** (`Request::Grant`, `Unpair`,
`HideRevokedDevice`), not by the GUI.

### Plan

| | |
| --- | --- |
| **Objective** | One main area, **Devices**, holding everything Trusted peers does today, with progressive disclosure. No change to what the daemon allows. |
| **Areas** | `views/devices.rs`, `views/peers.rs` (merged or reduced to helpers), `views/mod.rs`, `gui/src/lib.rs` (`Page`, `Launch::parse`), `widgets.rs` (expander/disclosure row if needed), `README.md:123`, `UI-GUIDELINES.md:210` |
| **Design** | **Card (always visible):** name · platform · status (online / offline / connected, taken from the same `DaemonState` facts that exist today) · trust state (paired / revoked) · a summary of granted capabilities. **Expanded (on demand):** capability grant toggles; full fingerprint; device id; session/connection details; "Revoke this device"; for revoked devices, "Remove from list"; page-level "Remove all revoked devices". Revoked devices stay visible and marked, as `devices.rs` shows them today. |
| **Routes** | `Page::TrustedPeers` is removed from `Page::ALL` (so from the sidebar). `Page::from_name("peers")` resolves to `Page::Devices`, so `--page peers` and `--page=peers` keep working. The `lib.rs:915` test is **kept** and changes its expected page, plus a new test proving the alias. |
| **Identifiers** | GUI route names only; no persistent or wire identifier |
| **Migrations** | `gui.json` stores a peer *selection*, keyed by fingerprint, not a page, so there is nothing to migrate. |
| **Compatibility** | `--page=peers` redirects; the daemon control protocol is unchanged. |
| **Allowed** | layout, disclosure, wording ("trusted" stays as the trust *state* label), merging render code. |
| **Forbidden** | removing a confirmation dialog; auto-granting any capability; hiding revoked devices by default; keying removal by device id or name instead of fingerprint; any change to `desktop/daemon`, `desktop/runtime`, `desktop/control` or their tests; mixing trust actions into the unauthenticated Quick Panel. |
| **Unit tests** | `Launch::parse` alias tests; page list no longer contains `TrustedPeers`; a model-level test that every control Trusted peers had exists on Devices: grant ×3, revoke, remove one, remove all. |
| **Integration** | the `#[ignore]`d `every_page_widget_tree` under a display: the Devices tree contains the grant switches, the full-fingerprint widget (in its expander), the revoke button and the confirmation dialog. |
| **Regression** | **unchanged and green:** `desktop/daemon/tests/security_certification.rs`, `control.rs`, `revoked_cleanup.rs`, `file_approval.rs`, `desktop/core/tests/revoked_tombstone.rs`. A diff check proves that no file under `desktop/{daemon,runtime,control,core}` changed. |
| **Upgrade** | a GUI started with `--page=peers` from an old `.desktop` action or script lands on Devices. |
| **Hardware** | a real GNOME and a real KDE session: keyboard navigation reaches every control, including inside the expander; screen-reader labels exist for revoke and grant. |
| **Rollback** | revert; the daemon is untouched, so rollback is GUI-only. |
| **Exit criteria** | one sidebar entry; the control-parity test green; the security suites byte-identical; both real sessions checked. |
| **Gate** | **G2 — no lost control, no widened authority.** Every Trusted-peers action is reachable, and still confirmed, from Devices. |
| **Unblocks** | W3 (touches the same files; merging W2 first avoids a rename-over-refactor conflict). |

---

## Wave 3 — Code naming / namespace refactor

| | |
| --- | --- |
| **Objective** | Rename developer-only names: crates, Rust module paths, generated protobuf packages, Kotlin *type* names, resource names, log tags, thread names, the X11 atom and temp prefixes. No persistent, installed or wire identifier moves. |
| **Areas** | 12 crates (`desktop/*/Cargo.toml`, `desktop/capabilities/*/Cargo.toml`, `desktop/Cargo.toml`, `Cargo.lock`) · 116 `.rs` files naming `omnibridge_`/`omnibridge-` · `protocol/proto/omnibridge/v1/**` → `protocol/proto/pliwee/v1/**` (6 files, `git mv`), `desktop/proto/{build.rs,src/lib.rs,tests/namespace.rs}` · 36 Kotlin files importing the generated proto · 49 Kotlin files using `OmniBridge*` type names · `res/values*/themes.xml` (`Theme.OmniBridge`), `colors.xml` (`omnibridge_*`) + manifest theme refs · `.github/workflows/{desktop-quality,portable-windows-msvc}.yml` (`-p` lists **and** the `-like 'omnibridge-*'` filter) · `rootProject.name` in `android/settings.gradle.kts` |
| **Prerequisites** | W2 merged |
| **Identifiers** | crate names; `pliwee.v1[.capabilities]`; `java_package io.github.yurisismotto.pliwee.proto[.capabilities]`; Kotlin types `Pliwee*`; log tags `Pliwee*`; `pliwee-clipboard-x11`; `_PLIWEE_CLIPBOARD_WATCH_STOP`; `.pliwee-<id>.part` |
| **Explicitly NOT in this wave** | `[[bin]] name` (W7), Kotlin **package** / `namespace` / `applicationId` / manifest components (W6), `APP_ID` constants (W7), paths (W4), wire constants (W5) |
| **Migrations** | `.omnibridge-<id>.part` leftovers in the download dir: a finished transfer never leaves one, and an interrupted transfer is not resumable. They are left alone, and W4 lists them. |
| **Compatibility** | **Protobuf:** wire-neutral. Field numbers and types are asserted unchanged by `desktop/proto/tests/namespace.rs` (extended to compare against a descriptor snapshot taken before the rename) and by the cross-language envelope tests. |
| **Allowed** | `git mv`, symbol renames, import changes. |
| **Forbidden** | any change of behaviour; any change of a field number; editing KAT constants; renaming a log tag without renaming, in the same commit, every harness pattern that looks for it. |
| **Unit tests** | full `cargo test --workspace` and `:app:testDebugUnitTest`; `namespace.rs` asserts `pliwee.v1` on all six schemas and the unchanged field table. |
| **Integration** | `desktop/daemon/tests/{e2e,wire,sessions}.rs`; the Windows MSVC portable job must still build **exactly the seven portable crates**, and its `-like` filter must match ≥ 1 line or the job fails. That is a new assertion, because a renamed filter matching nothing would pass with nothing checked. |
| **Regression** | log-anchored harnesses (`packaging/tests/security-log-evidence.sh`, Android `NotificationLoggingCanaryTest`, `lifecycle-*gates.sh`): each first proves that its anchor **is found** under the new tag, before any absence claim (AGENTS.md "the window covers the operation"). |
| **Upgrade / hardware** | none; no installed name changed. |
| **Rollback** | revert the merge (one mechanical commit series). |
| **Exit criteria** | `git grep -nE 'omnibridge[_-]'` in `desktop/**/*.rs` returns only binary names, app ids, paths and wire constants owned by W4/W5/W7, each listed; the workflow filter test green. |
| **Gate** | **G3 — rename without behaviour change.** Identical test counts before and after, per suite (exact numbers recorded, not "all pass"); proto descriptor field table identical. |
| **Unblocks** | W4, W5, W7 |

---

## Wave 4 — Linux state & upgrade migration

| | |
| --- | --- |
| **Objective** | A Pliwee daemon uses `~/.local/share/pliwee` and `~/.config/pliwee`, **and** carries an existing OmniBridge identity and trust store into them without ever creating a new identity while legacy state exists (ADR-0020 D9, D11, D12). |
| **Areas** | `desktop/core/src/platform/unix_fs.rs` (data dir), `core/src/store.rs`, `core/src/secret_store.rs` (the absent-vs-unreadable seam), a new `core/src/platform/legacy_migration.rs` (or equivalent), `desktop/gui/src/selection.rs` (config), `desktop/platform-linux/src/lib.rs` (runtime dir + `/tmp` fallback), `desktop/capabilities/files/src/{sink,destination}.rs` (download dir), daemon startup |
| **Prerequisites** | W3; **captured real v1.0.0 state** (below) |
| **Identifiers** | `$XDG_DATA_HOME/pliwee`, `$XDG_CONFIG_HOME/pliwee`, `$XDG_RUNTIME_DIR/pliwee`, `/tmp/pliwee-<uid>`, `~/Downloads/Pliwee` |
| **Migration algorithm** | 1. Resolve `P = $XDG_DATA_HOME/pliwee`, `L = $XDG_DATA_HOME/omnibridge` (each with the same HOME fallback as today). 2. If `P` holds an identity → use it; never look at `L`. 3. Else if `L` **exists** → it must be *readable and private*, or startup **fails** naming `L` (no "first run"). Then copy `identity.key` and `state.json` into a temp dir inside `P`'s parent with `0700`/`0600`, fsync, rename into place, fsync the parent, and write `P/MIGRATED_FROM` (source path, timestamp, SHA-256 of both files). `L` is not modified. 4. Else → first run, new identity. The same rule applies to `gui.json` (config), on first GUI start. 5. Idempotent: a second start sees `P` populated and does nothing. |
| **Other paths** | runtime dir and socket: rename only (volatile; daemon and clients ship together). Cache and logs: **none exist on disk today** (audit §4.2); any future cache is `$XDG_CACHE_HOME/pliwee` only. Downloads: new files go to `~/Downloads/Pliwee`; `~/Downloads/OmniBridge` is never moved or deleted; leftover `.omnibridge-*.part` files are reported in `status`, never removed. |
| **Compatibility** | Durable (D11): the legacy detection stays until an ADR names the last supported upgrade source. Downgrade: `L` is intact, so OmniBridge 1.0.0 still starts with its pre-migration state; pairings made after migration are not visible to it (documented, ADR-0020). |
| **Allowed** | new migration module; startup ordering; `status` / CLI reporting of "migrated from …". |
| **Forbidden** | moving or deleting `L`; migrating by rename (a crash mid-rename would leave neither directory whole); reading `L` when `P` has an identity; regenerating a key or certificate; changing the state schema; touching wire constants. |
| **Unit tests** | (a) `P` empty + valid `L` → copied, fingerprint equal; (b) `P` populated + `L` present → `L` ignored; (c) `L` unreadable (`EACCES`, broken symlink, non-private mode) → error naming the path, and **no** file created in `P`; (d) crash injection between copy and rename → next start completes or refuses, never half-state; (e) second start is a no-op (mtime and hash of `P` unchanged); (f) `XDG_*` unset / relative → HOME fallback for both. |
| **Integration** | daemon started on captured v1.0.0 state: `omnibridge status` (CLI still named so until W7) shows the **same** fingerprint, device id, exact peer count, grants and policies as before. |
| **Captured v1.0.0 state** | from real `v1.0.0` packages installed on Fedora 44, Ubuntu 24.04, Ubuntu 26.04 and Debian 13 guests (`packaging/tests/lib/guest-agent.sh`): daemon started, paired with a peer, grants and a clipboard/notification policy set, `~/.local/share/omnibridge` + `~/.config/omnibridge` archived with hashes. **Test fixtures come from real installs, not synthesised JSON.** |
| **Upgrade tests** | this wave proves the *code* on real state; the *package* upgrade is W7's G7-UP and W8's certification. |
| **Hardware** | guest VMs of the four distributions |
| **Rollback** | revert. Any state already migrated stays valid, because `L` was never touched. |
| **Exit criteria** | cases (a)–(f) green; the integration run on all four captured states shows identical fingerprint, device id, peer count and grants. |
| **Gate** | **G4 — no identity is ever regenerated while legacy state exists.** Two observations (before and after), equality asserted; the unreadable case produces zero new identities. |
| **Unblocks** | W7 |

---

## Wave 5 — Protocol, discovery and cryptographic-domain migration

| | |
| --- | --- |
| **Objective** | Implement ADR-0020 §D4: emit the Pliwee identifiers and accept the OmniBridge legacy profile in v1.x, selected **once per connection by the negotiated ALPN**, with no hybrid state. |
| **Areas** | Desktop: `core/src/lib.rs` (ALPN, service type), `core/src/tls.rs` (server ALPN list; `NegotiatedProtocol` → *(profile, kind)*; client config per profile), `core/src/qr.rs`, `core/src/pairing.rs`, `core/src/identity.rs` (CN), `capabilities/files/src/auth.rs`, the mDNS advertiser/browser in the runtime, the session code that carries the profile to capabilities. Android: `net/PinnedTrustManager.kt` (ALPN), `net/Discovery.kt` (two NSD browses, dedupe), `pairing/QrPayload.kt`, `pairing/PairingProof.kt`, `files/StreamAuth.kt`, `notifications/NotificationIdentity.kt`, `identity/DeviceIdentity.kt` (CN), `net/PeerConnection.kt`, `net/ConnectionCoordinator.kt`. Tests: `core/tests/{wire_identity,pairing,identity_and_store,notifications_protocol}.rs`, `core/examples/gen_test_vectors.rs`, Android `WireIdentityTest`, `PairingProofTest`, `PairingRecoveryTest`, `Fixtures.kt`, `StreamAuthTest`, `NotificationIdentityTest`. Docs: `docs/architecture/PROTOCOL.md`, `FILES.md`, `NOTIFICATIONS.md`. |
| **Prerequisites** | W3 |
| **Identifiers** | `pliwee/1`, `pliwee-data/1`, `_pliwee._tcp.local.`, `pliwee1:`, `pliwee/pairing-proof/v1`, `pliwee/pairing-confirm/v1`, `pliwee/files.v1/data-stream/v1`, `pliwee/notifications.v1/{id,group,content}/v1`, CN `pliwee:<id>`; the legacy set is unchanged and kept |
| **Profile rules (implemented and tested)** | Listener offers `pliwee/1`, `pliwee-data/1`, `omnibridge/1`, `omnibridge-data/1` in that order. A client offers **one** ALPN: canonical, unless the peer is known only as legacy (discovered on `_omnibridge._tcp` only, or paired from an `omnibridge1:` QR). The negotiated ALPN fixes the profile; pairing and data domains come from it. A data stream must match its control session's profile. Verification uses **only** the negotiated profile's domain. The profile is recorded per peer in memory for dialling, **not** persisted as trust. |
| **Discovery** | the daemon advertises one instance under **both** service types (same TXT `v`, `id`, `dn`); the app browses both and deduplicates by `id` + pinned fingerprint, preferring the canonical record. |
| **QR** | the daemon emits `pliwee1:` only; parsers accept both schemes, and the scheme fixes the profile of the pairing connection. `omnibridge2:` / `pliwee2:` stay *recognised and rejected* (ADR-0011 rule). |
| **Notifications** | canonical domains only (Android-local; desktop ids opaque). No dual path. |
| **Certificates** | CN `pliwee:<id>` for **new** identities; existing identities are never regenerated. The CN is not parsed. |
| **Frozen vectors (D10)** | `protocol/testdata/identity-{a,b}.der` and their four SPKI KATs are **byte-identical**, and a test compares their SHA-256 with the digests recorded in this wave's report. The **legacy** domain KATs stay as they are, because they now test live legacy code. The **Pliwee** domain KATs are **added**, computed independently from the documented construction (a script separate from the implementation, as ADR-0018 did); the report records the command and output. |
| **Migrations** | none persistent. Existing pairings keep working: trust is keyed by SPKI fingerprint, which is profile-independent. |
| **Compatibility** | ADR-0020 D4 table, verbatim. Removal of the legacy profile is out of scope for all of v1.x. |
| **Allowed** | the profile type; the ALPN list; dual advertisement; the dual QR parser; added KATs. |
| **Forbidden** | "try both domains" verification; a data stream across profiles; persisting the profile as a trust attribute; emitting `omnibridge1:`; changing any construction, framing, field, token size, TTL or limit; regenerating `identity-{a,b}.der`; renaming only part of the unit (e.g. mDNS without ALPN). |
| **Unit tests** | wire-identity tests on both sides pin **both** value sets as literals, with dead list `anyflow`, `fedroid`; profile selection table (each ALPN → profile, kind); QR parse matrix (`pliwee1`, `omnibridge1`, `pliwee2`, `omnibridge2`, `anyflow1` → accept, accept, reject-recognised, reject-recognised, reject); KATs for both profiles, both languages, equal across languages. |
| **Negative (no-hybrid) tests** | a proof computed under `omnibridge/pairing-proof/v1` presented on a `pliwee/1` connection → rejected, and vice versa; a `pliwee-data/1` stream carrying a credential issued on an `omnibridge/1` session → refused; a client offering both ALPNs → rejected by our own client-config tests (one ALPN per client); mDNS duplicate records → one device shown. |
| **Integration** | `desktop/daemon/tests/{wire,e2e,files,sessions}.rs` and `desktop/core/tests/pairing.rs` run **twice**, once per profile; `examples/fake_phone.rs` gains a `--profile` switch. |
| **Network compatibility gate** | see §4. Pliwee↔Pliwee on the canonical profile; the Pliwee app ↔ a **packaged, unmodified OmniBridge 1.0.0** daemon on the legacy profile; an OmniBridge app build scanning a Pliwee QR → a clean, specific refusal (documented unsupported). |
| **Hardware** | a physical Android device (API 36; the SM-X620 used by PLAY17 is suitable) and a Linux host running the real `omnibridge 1.0.0` package. |
| **Rollback** | revert the merge. No persistent state changed; pairings made in the window keep working, because trust is by fingerprint. |
| **Exit criteria** | unit, negative and KAT suites green in both languages; the §4 matrix executed on hardware with every row observed; the frozen-vector digests match. |
| **Gate** | **G5 — one connection, one identity.** Every negative test rejects; every compatibility row is observed through a product-written anchor (session id or transfer id in the daemon log), not inferred. |
| **Unblocks** | W6 |

---

## Wave 6 — Android identity, package and signing

| | |
| --- | --- |
| **Objective** | The Android app becomes `io.github.yurisismotto.pliwee`, with its Kotlin package, components, Keystore aliases, download folder, launcher icons and a **new Pliwee signing identity** (D1, D2, D3), and its component names frozen from this build on. |
| **Areas** | `android/app/build.gradle.kts` (`namespace`, `applicationId`, `signingConfigs` alias, env var names, Gradle property), `android/fixture/build.gradle.kts`, `AndroidManifest.xml`, all 163 files under `…/io/github/yurisismotto/omnibridge/` moved (`git mv`) to `…/pliwee/`, `identity/DeviceIdentity.kt`, `notifications/NotificationSecret.kt`, `files/Downloads.kt`, intent-action constants (`ConnectionService.kt:419`, `ClipboardNotifications.kt:132`, `MainActivity.kt:696,706`), `ui/PairingScanner.kt` prompt (`omnibridge pair` → until W7 renames the CLI, the prompt keeps the command's real name), `android/signing/{provision-signing-keys.sh,build-release-bundle.sh,verify-release-bundle.sh,tests/provision-selftest.sh}`, `android/signing/certs/`, `.github/workflows/android-ci.yml`, `android/README.md`, ADR-0019 addendum, superseding note in `docs/audits/android/ANDROID-PLAY-V1-DECLARATIONS.md` (PLAY14) |
| **Prerequisites** | W5 (the app must speak both profiles before it ever carries the new identity); W0 (launcher icons); **operator provisioning of the Pliwee signing identity** on two removable media |
| **Identifiers** | `applicationId` / `namespace` / package `io.github.yurisismotto.pliwee`; fixture `…pliwee.fixture`; `pliwee-identity-v1`, `pliwee-notification-secret-v1`; `io.github.yurisismotto.pliwee.{STOP,APPLY_CLIP,SEND_CLIPBOARD,CLIPBOARD_REQUEST_ID}`; `Download/Pliwee`; `pliwee-app-signing`, `pliwee-upload`, `CN=Pliwee, OU=…`; `PLIWEE_UPLOAD_KEYSTORE[_PASSWORD]`; `-Ppliwee.release.unsigned` |
| **Components (frozen at the end of this wave)** | `.notifications.PliweeNotificationListener` (notification access), `.ui.ClipboardTileService` (Quick Settings), `.ui.MainActivity` (launcher, shortcuts), `.ui.SendActivity` (share target), `.ui.PairingCaptureActivity`, `.service.ConnectionService`. From now on, renaming any of them must keep the old `ComponentName` (subclass / `activity-alias`) or it is a breaking change. |
| **Signing (D3)** | `provision-signing-keys.sh` takes the product identity as data (aliases, DNs, `~/.local/share/pliwee-android-signing/`, `~/.local/state/pliwee-android-signing/PROVISIONED`). It keeps its refusal: one identity per `applicationId`. It never reads, overwrites or removes the OmniBridge record or keystores. The selftest adds "an OmniBridge record exists → Pliwee provisioning proceeds and leaves it byte-identical" and "a Pliwee record exists → refused". The operator runs it with two media, restore-verified as ADR-0019 requires. The new public certificates are committed beside the OmniBridge ones, which stay **byte-identical** (moved with `git mv` to `certs/legacy-omnibridge/` if at all). `verify-release-bundle.sh` expects the **Pliwee** upload certificate and package. |
| **Migrations** | none possible for Android state (a new app; D1). The OmniBridge app on test devices is left installed or removed by hand; nothing uninstalls it. |
| **Compatibility** | the D1 transition preserves nothing on the phone. The desktop keeps its trust record of the old phone (D12 boundary); the Pliwee phone pairs as a new device. |
| **Allowed** | package move; manifest; Keystore alias restart; signing-script parameterisation; icons from W0. |
| **Forbidden** | generating keys in CI or in this session; committing any keystore, password or backup; overwriting or deleting the OmniBridge certificates, record or backups; a "legacy alias sweep" (the new app cannot see old aliases, so it would be dead code, as ADR-0018 found); creating the Play Console app (W10); changing `PrivacyPolicy.kt`'s URL (W10). |
| **Unit tests** | `PliweeIdentityTest` (was `DeviceIdentityTest`): `pliwee-identity-v1` present; no `omnibridge-*`/`anyflow-*` alias in this app's Keystore (instrumented); manifest-component snapshot test; the `WireIdentityTest` package assertions; `BrandingResourcesTest` over the new launcher layers; signing selftest (above). |
| **Integration** | `:app:assembleRelease` without env → refusal (Android CI keeps asserting it); the built APK read with `aapt2 dump badging`/`xmltree`: package, every component name, permissions exactly as before. |
| **Regression** | the full Android unit and instrumented suites; `NotificationSecret*`, `PinnedTrustManagerTest`, `PairingProofTest` with names changed only. |
| **Upgrade tests** | **Pliwee → Pliwee** (the first time components matter): install build N, grant notification access, add the QS tile, pin a launcher shortcut, then install N+1 over it → the grant, tile and shortcut survive. This is the component-freeze gate. |
| **Hardware** | a physical Android 16 / API 36 device: notification-listener grant (on One UI via `cmd notification allow_listener <component>`), QS tile, launcher, share target, NSD on a real LAN, pairing with a Linux host; the operator's two removable media for provisioning. |
| **Rollback** | code: revert. Signing: the Pliwee identity is not yet enrolled anywhere, so rollback before W10 costs nothing but the media; **after** W10's PEPK it is permanent (ADR-0019). |
| **Exit criteria** | APK facts match; the component upgrade test passes on hardware; the Pliwee signing identity provisioned and restore-verified, with its public fingerprints committed in the ADR-0019 addendum; the OmniBridge certificates' SHA-256 unchanged. |
| **Gate** | **G6 — a new identity, made once, and nothing old overwritten.** |
| **Unblocks** | W8 |

---

## Wave 7 — Linux system integration, packaging, distribution & CI

| | |
| --- | --- |
| **Objective** | Binaries, desktop app id, D-Bus, tray, systemd, firewalld, packages, harnesses, release pipeline and CI move to Pliwee, with an explicit, idempotent transition for installs of v1.0.0. |
| **Areas** | `desktop/{cli,daemon,gui}/Cargo.toml` `[[bin]]`; CLI/daemon `#[command(name=…)]` and every "Run: omnibridge …" hint; `APP_ID` / `DESKTOP_APP_ID` / object path in `gui/src/lib.rs:71`, `gui/build.rs:16`, `platform-linux/src/tray/model.rs:27,36`, `platform-linux/src/activation.rs:323`, `capabilities/notifications/src/backend/dbus.rs:76`; `desktop/gui/data/*` (5 files, `git mv`); `desktop/gui/tools/install-desktop-metadata.sh`; `packaging/**` (29 files with the brand + 6 named); `packaging/tests/**` + `lib/assert.sh`; `.github/workflows/*` (7); `packaging/release/*`; `desktop/platform-linux/tests/{tray_identity,dbus_activation}.rs`; `docs/architecture/*` for installed names; `packaging/*/README.md` |
| **Prerequisites** | W3, W4; W0 (hicolor icon source) |
| **Identifiers** | `pliwee`, `pliweed`, `pliwee-gui`; `io.github.yurisismotto.pliwee` (GApplication, D-Bus name, `.desktop`, `Icon=`, AppStream `<id>`, SNI `Id`/`IconName`, notification app id); `/io/github/yurisismotto/pliwee`; `pliweed.service`, `RuntimeDirectory=pliwee`; `pliwee.xml`; packages `pliwee`, `pliwee-gui`; `PLIWEE_*` harness vars; artifact names `pliwee-<V>…` |
| **systemd transition** | Invariants (ADR-0020): an install that had `omnibridged.service` **enabled** has the Pliwee daemon running after the next login; **exactly one** daemon process exists; a never-enabled install stays disabled; `systemctl --user {enable,disable,stop} pliweed` works; running the transition twice changes nothing. Candidate mechanisms: (a) ship a compatibility `omnibridged.service` through v1.x that starts `pliweed` (with `Conflicts=` so both cannot run) and makes enablement follow; (b) `pliweed` detects a stale `default.target.wants/omnibridged.service` symlink and reports the exact one-line fix; or both. The choice is made by measurement in this wave (B5), **not assumed**. No scriptlet writes into `~/.config/systemd/user/`. |
| **firewalld** | install `pliwee.xml` (TCP 55432 only); keep installing `omnibridge.xml`, identical, through v1.x; no scriptlet edits a zone (unchanged policy). |
| **Package transition** | RPM: `Obsoletes: omnibridge < <first Pliwee V>` + `Provides: omnibridge = %{version}`, the same for `-gui`. Debian: `Replaces:` + `Breaks: omnibridge (<< <V>)` + `Provides:`, with a transitional `omnibridge` package if `apt upgrade` does not pull `pliwee` otherwise (measured). The first Pliwee version is B4. |
| **Desktop integration** | the old `.desktop`, D-Bus service, AppStream file and hicolor icon are removed by the package upgrade. Dock favourites, per-app notification settings and tray visibility keyed by the old id are **reset and documented** in the migration note; nothing edits per-user desktop settings. `install-desktop-metadata.sh --uninstall` documents the removal of the old dev-install files by name. |
| **CI** | workflow `name:` values stay unchanged (they are brand-free, so required-check names survive into W9). The `-like` filter and `-p` lists were renamed in W3; here, container and buildroot names and artifact patterns. `release-artifacts.yml` produces `pliwee-*`. `RELEASE_SIGNING_KEY` stays **unconfigured**: release signing remains the operator's offline act (v1.0.0 precedent, RELEASE-SIGNING-CLOSURE-V1). |
| **Allowed** | everything listed above. |
| **Forbidden** | removing `omnibridge.xml`; any scriptlet touching user units, user desktop settings or firewall zones; changing unit hardening directives beyond the names; changing `ProtectSystem=`/`ReadWritePaths=`; publishing any artifact. |
| **Unit tests** | `tray_identity.rs` / `dbus_activation.rs` over the new id and object path; `packaging-checks.sh` (unit verifies, spec/control lint, both firewalld files present, `Obsoletes`/`Replaces` present with exact bounds); `harness-selftests.sh` (every refusal still refuses under the new names). |
| **Integration** | `systemd-analyze verify` on `pliweed.service` (and the compatibility unit if chosen); `install-smoke.sh` on each distribution; `desktop-file-validate`, `appstreamcli validate`. |
| **Upgrade tests — G7-UP** | see §3: the formal **OmniBridge v1.0.0 → Pliwee** package-upgrade scenario on all four distributions. |
| **Regression** | `lifecycle-gates.sh` and `lifecycle-peer-gates.sh` in full under the new names; `security-log-evidence.sh`. |
| **Hardware** | Fedora 44, Ubuntu 24.04, Ubuntu 26.04 and Debian 13 (the guest set used for Packaging v1), plus one real GNOME and one real KDE Plasma host for the tray, D-Bus activation and `.desktop` behaviour. |
| **Rollback** | code: revert. An install upgraded in testing can be downgraded to `omnibridge 1.0.0` with `dnf downgrade`/`apt install omnibridge=1.0.0-1`; the legacy state directory is intact (W4). Measured as part of G7-UP. |
| **Exit criteria** | G7-UP PASS on all four distributions; lifecycle and peer gates PASS; `packaging-checks` green; the release pipeline dry-run produces the exact expected `pliwee-*` artifact list (exact count, not "> 0"). |
| **Gate** | **G7 — a v1.0.0 user upgrades and notices only the name.** |
| **Unblocks** | W8 |

---

## Wave 8 — Pre-repository-migration certification

| | |
| --- | --- |
| **Objective** | Certify the complete Pliwee build **in this repository** before anything moves. Nothing is published. |
| **Prerequisites** | W0–W7 merged into `develop`; a release-candidate commit frozen |
| **Scope** | the existing certification set, re-run under Pliwee names: Security Certification v1 (SEC gates), clipboard.v1, files.v1, notifications.v1 (N6), Linux GNOME and KDE real-host, packaging lifecycle and peer gates, Release Readiness harness; **plus** G0–G7 re-executed on the RC commit, the §3 upgrade scenario and the §4 network matrix on hardware. |
| **Known pre-migration values (recorded, not failures)** | `PrivacyPolicy.kt` still points at the live OmniBridge URL (P1); metadata URLs (`Cargo.toml`, spec, debian, metainfo, unit `Documentation=`) still point at `yurisismotto/OmniBridge`; Play listing not updated. Each is listed with its owning wave (10). |
| **Remainder audit** | `docs/audits/rebrand/PLIWEE-REBRAND-REMAINDER-AUDIT.md`: every surviving `omnibridge` / `OmniBridge` classified with `LC_ALL=C grep -ai` (the DER lesson): legacy profile, legacy paths, compatibility unit and firewalld file, frozen vectors, historical docs, pre-migration URLs. **Zero unexplained.** |
| **Hardware** | the full real-host set + physical Android |
| **Rollback** | a FAIL returns to the owning wave; nothing is public yet. |
| **Exit criteria / gate** | **G8 — PRE-MIGRATION: PASS**, recorded in `docs/certification/rebrand/PLIWEE-PRE-MIGRATION-CERTIFICATION.md` with commit, hardware, commands and outputs. No partial pass. |
| **Unblocks** | W9 |

---

## Wave 9 — New Pliwee repository migration

**Not executed before G8 PASS.** Nothing here changes `yurisismotto/OmniBridge`
except the final notice and archival at the end.

### 9.1 What exists today (measured 2026-09-24, read-only)

| Setting | `yurisismotto/OmniBridge` |
| --- | --- |
| Visibility / default branch | public / `main` |
| History | recreated 2026-09-24 from `745541c` "Initial public baseline"; earlier history in `yurisismotto/omnibridge-history` |
| Branches (remote) | `main`, `develop`, `feature/project-presentation-v1`, `fix/readme-ci-trigger` |
| Tags | `v1.0.0` (annotated, not OpenPGP-signed; trust anchor is `SHA256SUMS.asc`) |
| Releases | `v1.0.0` with 18 assets |
| Branch protection / rulesets | **none** |
| Actions secrets / variables / environments | **none configured** (workflows reference `secrets.RELEASE_SIGNING_KEY` and `vars.RELEASE_SIGNING_FPR`, both optional by design) |
| Dependabot security updates | disabled; no `dependabot.yml` |
| Secret scanning / push protection | enabled / enabled |
| Issues / wiki / discussions / Pages | on / on / off / off |
| Issue & PR templates, CODEOWNERS, SECURITY.md, CONTRIBUTING.md | none |
| Description | "One bridge. Any device. Open-source, local-first device continuity between Android and Linux." |

### 9.2 Steps

1. **Freeze.** Merge the certified RC into `main` of `yurisismotto/OmniBridge`;
   tag nothing new yet.
2. **Create `yurisismotto/pliwee`** (public, empty, no auto-generated README
   or licence).
3. **History.** Push from a fresh clone: `main`, `develop`, and the tag
   `v1.0.0` (it names a real commit in this history). Feature and worktree
   branches are not carried: they are merged or discarded before step 1.
   `omnibridge-history` stays where it is and is linked from the README, not
   imported. Verify: `git rev-parse main develop v1.0.0^{}` equal in both
   repositories.
4. **Releases.** The **v1.0.0 GitHub Release is not re-created** in the new
   repository: its assets, signature and download URLs stay in
   `yurisismotto/OmniBridge` as evidence, and the new README links there. The
   first release published from `pliwee` is the first Pliwee version (W10).
5. **Actions.** Workflows run unmodified on the new repository. `name:`
   values are unchanged, so required checks keep their names. Secrets and
   variables: **none**, carrying today's state; release signing stays offline.
   `release-artifacts.yml` provenance attestations will name the new
   repository; v1.0.0 attestations remain valid for v1.0.0 artifacts only.
6. **Branch protection** on `main` and `develop`: forbid force-push and
   deletion, and require the workflow checks that run on **every** PR. All
   seven workflows trigger on `pull_request`, but a path-filtered one made
   *required* would block every PR that never triggers it, so each is checked
   for path filters before it is marked required. Today there is no
   protection, so this is new configuration (B6).
7. **Security settings:** secret scanning and push protection on (as today);
   Dependabot security updates per B6 (today off).
8. **Metadata:** description with the Pliwee tagline, homepage, topics.
   Issues on; wiki per B6; issue/PR templates optional (none exist to migrate).
9. **Pages:** only if B3 chooses Pages for the privacy policy (W10).
10. **Local remotes:** `origin` → `pliwee`; the old remote kept as `omnibridge`
    for read-only reference.
11. **Old repository.** The last commit to `yurisismotto/OmniBridge` `main`
    adds a README notice ("continues as Pliwee at …"). It leaves
    `docs/policy/PRIVACY-POLICY.md` **at its path**, with a pointer to the
    Pliwee policy above the unchanged text, so the compiled URL keeps
    resolving (ADR-0020 public-URL rule). The repository is then **archived**:
    never deleted, renamed or transferred, and releases stay.
12. **Verify:** every URL in the audit §7.1 list resolves (HTTP 200)
    afterwards, measured, including the eight v1.0.0 download URLs, the
    pubkey URL and the privacy-policy blob.

| | |
| --- | --- |
| **Rollback** | before step 11: delete the new repository; nothing else changed. After step 11: un-archive (owner action). |
| **Exit / gate** | **G9 — nothing already published stopped resolving**, and the new repository's CI is green on the migrated `main`. |
| **Unblocks** | W10 |

---

## Wave 10 — Public URLs, privacy policy, OpenPGP UID and Play finalization

| | |
| --- | --- |
| **Objective** | Point every definitive public reference at Pliwee, add the Pliwee UID to the release key, publish the first Pliwee release, and bring Android through Play registration and internal testing. |
| **Prerequisites** | W9; **B3** (privacy-policy hosting form) decided; the Pliwee Play Console app created by the operator (B7) |
| **Privacy policy** | `docs/policy/PRIVACY-POLICY.md` updated to Pliwee and published at the B3 location (blob URL in `yurisismotto/pliwee`, or GitHub Pages). `PrivacyPolicy.kt` and `PrivacyPolicyTest.kt` compile **that** URL; the test asserts HTTP 200 in CI (network) and the exact string offline. The OmniBridge copy stays live (W9 step 11). |
| **URLs** | `README.md` (badge `img.shields.io/github/v/release/yurisismotto/pliwee`, install and verify commands for the Pliwee release, and a history section linking the OmniBridge v1.0.0 release and `omnibridge-history`); `desktop/Cargo.toml` `repository`; `metainfo.xml` homepage/bugtracker; unit `Documentation=`; spec `URL:`; debian `Homepage`/`Vcs-*`/`copyright`; `PLAY-STORE-LISTING.md`. |
| **OpenPGP (D6)** | the operator adds UID `Pliwee Release Signing Key` to `F545DC18…` from offline custody and publishes the updated public key as `pliwee-release-pubkey.asc`. The OmniBridge UID is kept, not revoked. **Gate:** the v1.0.0 `SHA256SUMS.asc`, downloaded from the old repository, verifies with `verify-release.sh --fingerprint F545DC18…` against the updated key, and so does the new release. |
| **First Pliwee release** | built by `release-artifacts.yml` from a tag in `yurisismotto/pliwee`, signed offline by the operator (`sign-release.sh`), verified independently (`verify-release.sh`). The artifact list is exact. |
| **Play** | Play Console app for `io.github.yurisismotto.pliwee` (this is where the package is registered — PLAY14/PLAY18); PEPK export of the **Pliwee** app-signing key; upload certificate registered; *App signing* page fingerprints equal the ADR-0019 addendum values (anything else stops the wave); listing text, 512 px icon and 1024×500 feature graphic derived from W0; **tablet screenshots re-captured** from the final UI (W1 + W6); data-safety and declarations re-confirmed against `ANDROID-PLAY-V1-DECLARATIONS.md` (with its superseding note); internal testing track upload. |
| **Forbidden** | a fake or placeholder URL; making the OmniBridge URL the Pliwee canonical one; uploading anything signed by the OmniBridge keys; re-uploading v1.0.0 assets. |
| **Tests** | `PrivacyPolicyTest`; `verify-release-bundle.sh` on the uploaded AAB; the release-signing harness (`release-signing-tests.sh`, `release-signing-production-tests.sh`) under the new artifact names; Play pre-launch report reviewed. |
| **Hardware** | a physical Android device installing **from the Play internal track**, not sideloaded. |
| **Rollback** | URLs: revert. Release: a release can be withdrawn but is not deleted (it is evidence). **Play PEPK and package registration are irreversible**, which is why they are last and gated on G8. |
| **Exit / gate** | **G10 — every published reference resolves, and the trust roots are unchanged:** v1.0.0 and the Pliwee release both verify against `F545DC18…`; Play shows the committed Pliwee fingerprints; the Play-installed app pairs with a Pliwee daemon. |
| **Unblocks** | W11 |

---

## Wave 11 — Final Pliwee certification

| | |
| --- | --- |
| **Objective** | The final verdict on the Pliwee product as distributed: packages from the Pliwee GitHub release, and the app from Play. |
| **Scope** | G8 re-run against the **published** artifacts (not the build tree); the §3 upgrade scenario from real v1.0.0 packages to the **published** Pliwee packages; the §4 matrix with the Play-installed app; `docs/migrations/MIGRATION-OMNIBRIDGE-TO-PLIWEE.md` published (developers and v1.0.0 users: what moves, what resets, the one systemd command if B5 needs it); final remainder audit; ADR-0020 status → "Accepted · implemented (commit …)"; the ADR index updated. |
| **Hardware** | the full real-host set; a physical Android device with the Play install |
| **Exit / gate** | **G11 — PLIWEE v1.x: PASS**, in `docs/certification/rebrand/PLIWEE-FINAL-CERTIFICATION.md`. |

---

## 3. Formal gate — Linux upgrade OmniBridge v1.0.0 → Pliwee (G7-UP)

Run in W7 and re-run in W8 (build tree) and W11 (published artifacts), once
per distribution: Fedora 44, Ubuntu 24.04, Ubuntu 26.04 and Debian 13. **A
clean-install pass is not a substitute for this gate.**

| Step | Action | Observation (anchored on product output) |
| --- | --- | --- |
| U0 | tools present: `rpm`/`dpkg`, `systemctl`, `firewall-cmd` (Fedora), `sha256sum` | refuse to run if any is absent |
| U1 | install the **published** `omnibridge` + `omnibridge-gui` **1.0.0** packages, verified against `SHA256SUMS.asc` | package versions exactly `1.0.0-1` |
| U2 | `systemctl --user enable --now omnibridged.service`; pair a peer (a second host or `fake_phone`); grant `clipboard.v1` and `files.v1`; set a clipboard policy and a notification lock policy; select the peer in the GUI; on Fedora add the `omnibridge` firewalld service to a non-default zone | `omnibridge status` output archived |
| **O1 (before)** | record: local fingerprint, device id, exact trusted-peer count and each peer's fingerprint, grants, policies, revocation tombstones, `gui.json` selection; SHA-256 of `identity.key`, `state.json`, `gui.json`; unit enablement; daemon PID count = 1 | written to the evidence file |
| U3 | upgrade to the Pliwee packages with the distribution's normal command (`dnf upgrade` / `apt upgrade`), not a remove + install | the package manager's transcript shows `omnibridge` replaced by `pliwee` |
| U4 | log out/in (or `systemctl --user daemon-reexec` + a user-session restart, as the lifecycle gates do) | the journal line in which the Pliwee daemon reports "migrated from …/omnibridge" **for this boot** (anchor) |
| **O2 (after)** | same fields as O1, read through `pliwee status` and the new paths | **equal to O1**, field by field; the legacy files' SHA-256 **unchanged**; daemon PID count = 1; `pliweed` enabled because `omnibridged` was |
| U5 | `firewall-cmd --reload` (Fedora) | succeeds, with the `omnibridge` service still resolvable |
| U6 | the peer reconnects **without re-pairing**; clipboard round-trip; a file transfer | the transfer id in the daemon log; the peer's own log shows the same local fingerprint as O1 |
| U7 | restart the daemon | nothing re-migrated (`MIGRATED_FROM` unchanged); O2 still holds |
| U8 | **negative:** on a fresh VM, make `~/.local/share/omnibridge` unreadable, then install Pliwee | the daemon refuses to start and names the path; **no** `~/.local/share/pliwee/identity.key` exists |
| U9 | **negative:** a never-enabled 1.0.0 install upgraded | `pliweed` is not enabled |
| U10 | downgrade to `omnibridge 1.0.0` | it starts with its pre-migration identity (the legacy directory was untouched) |

PASS requires every row observed. A row that cannot be measured is **not
executed, with the reason**, and the gate is then not PASS.

---

## 4. Formal gate — network compatibility (G5, re-run in W8 and W11)

| # | Pair | Profile expected | Required observation |
| --- | --- | --- | --- |
| N1 | Pliwee daemon ↔ Pliwee app | canonical | discovery on `_pliwee._tcp`; pairing from `pliwee1:`; negotiated ALPN `pliwee/1` (logged); clipboard both ways; a file (data ALPN `pliwee-data/1`); notifications mirrored and dismissed |
| N2 | Pliwee app ↔ **packaged OmniBridge 1.0.0** daemon | legacy | discovery on `_omnibridge._tcp`; pairing from `omnibridge1:`; ALPN `omnibridge/1`; clipboard; a file on `omnibridge-data/1` |
| N3 | Pliwee daemon ↔ OmniBridge app (dev build, W5 only; none distributed) | legacy | discovery via the daemon's legacy advertisement; an existing pairing reconnects on `omnibridge/1` |
| N4 | Pliwee daemon upgraded from 1.0.0 (G7-UP) ↔ its pre-upgrade peer | the peer's profile | reconnects without re-pairing |
| N5 | OmniBridge app scans a **Pliwee** QR | — | a clean, specific "unsupported code" refusal; no crash; documented as unsupported |
| X1 | a legacy-domain proof on a canonical connection | — | rejected, both languages |
| X2 | a canonical-domain proof on a legacy connection | — | rejected, both languages |
| X3 | a data stream whose profile differs from its control session | — | refused before any byte of the file |
| X4 | a client configured with both ALPNs | — | impossible by construction; test proves the client offers exactly one |
| X5 | one daemon advertised twice (both types) | — | the app shows one device |

Every N row is anchored on a session id or transfer id that the product wrote
**in this run**. Every X row is a failing operation, observed to fail for the
stated reason (the log line) and not for another one.

---

## 5. Cross-cutting checklist

| Topic | Wave(s) | Where specified |
| --- | --- | --- |
| `~/.local/share/omnibridge`, config/state/cache/log paths | 4, 7 | W4 table, §3 |
| Device identity and pairing preservation (Linux) | 4, 7, 8, 11 | G4, G7-UP |
| Keystore aliases | 6 | W6 |
| Android signing identity | 6 (provision), 10 (PEPK) | W6, W10 |
| Android `applicationId` | 6 (code), 10 (registration) | W6, W10 |
| Kotlin component identities, Notification Listener, Quick Settings, shortcuts | 6 | W6 components + upgrade test |
| systemd unit | 7 | W7 + §3 U2–U4, U9 |
| firewalld | 7 | W7 + §3 U5 |
| mDNS/NSD, ALPN, QR, domain separators | 5 | W5 + §4 |
| OpenPGP | 10 | W10 |
| Protobuf source rename | 3 | W3 |
| Frozen cryptographic test vectors | 5 (verified), all (untouched) | W5 |
| Historical documentation | all (forbidden), 6, 8 (superseding notes) | §0.1 rule 5 |
| GitHub repository references | 9, 10 | W9, W10 |
| Release artifacts | 7 (pipeline), 10 (publish) | W7, W10 |
| Privacy policy | 9 (old stays live), 10 (new) | W9 step 11, W10 |
| Screenshots, Play assets | 10 (after 0, 1, 6) | W10 |
| Desktop icons (hicolor), tray icon | 0 (source), 7 (id) | W0, W7 |
| Android adaptive icons | 0 (source), 6 (layers) | W0, W6 |
| Favicon | none exists (no web surface) | — |

---

## 6. Decisions still blocked

| # | Blocks | Question |
| --- | --- | --- |
| **B1** | W0 and every artwork step after it | owner-approved `pliwee-mark.svg` and `pliwee-mark-mono.svg` |
| **B2** | W0 wordmark/lockup, W10 feature graphic | approved wordmark and lockup vectors, or an approved rule for setting them in Inter from the board |
| **B3** | W10 only | privacy-policy hosting form: blob URL in `yurisismotto/pliwee` or GitHub Pages |
| **B4** | W7 package bounds, W10 release | the first Pliwee version number (1.x, above 1.0.0) |
| B5 | W7 (decided in-wave by measurement) | systemd transition mechanism (a), (b) or both |
| B6 | W9 | branch-protection rules, Dependabot, wiki for the new repository (today: none / off / on) |
| B7 | W10 | when the operator creates the Play Console app (package registration) |

B5–B7 are execution choices inside their wave, not blockers of the plan.

> **2026-09-24:** B1 and B2 are **resolved**. Wave 0 closed BRAND APPROVED at
> `1ea65e6`, and the approved masters are in `docs/design/assets/`.

---

## 7. Recommended start

**Wave 2 (Devices consolidation), with Wave 1 in parallel.** Neither waits
on the vector master, and neither touches a persistent or wire identifier.
Wave 2 lands the only product-behaviour change in the rebrand while the tree
is otherwise stable, and it must merge before Wave 3's mechanical rename
touches the same GUI files. Wave 0 starts the moment B1/B2 arrive; Waves 3 →
4/5 → 6/7 follow in order.
