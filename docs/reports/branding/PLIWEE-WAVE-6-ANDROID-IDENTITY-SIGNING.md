# Pliwee Wave 6 — Android identity, package and signing

| | |
| --- | --- |
| **Wave** | 6 — Android identity, package and signing ([plan](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md) §Wave 6) |
| **Decisions** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) D1, D2, D3, D8, D9, §"Android component identity" |
| **Branch / base** | `feature/pliwee-rebrand-wave6`, working tree on top of `e119bba` (Wave 5). Not committed: the orchestrator owns git. |
| **Date** | 2026-09-24 → 2026-09-25 (the runs crossed midnight, UTC−3) |
| **Host** | Fedora 44, kernel 7.2.5, **1 CPU**, 15 GiB RAM. Temurin JDK 21 (`/usr/lib/jvm/java-21-temurin-jdk`), Gradle wrapper 8.11.1, build-tools 35.0.0 (`aapt2`), bundletool 1.18.3. Gradle ran alone, one job after another (`--no-daemon --max-workers=2`, `org.gradle.parallel=false`). No emulator or VM was started. No cargo job ran: this wave touches no Rust. |
| **Evidence files** | `pliwee-wave-6/` (listed in §9) |
| **Gate status** | **G6 automated part: PASS.** APK facts match, the retired certificates are byte-identical, the frozen masters are unchanged, and the unit suites and the signing self-test are green. **Still open, needing the operator: Pliwee signing identity provisioning (two media, restore-verified) and the component-upgrade test on hardware, both NOT EXECUTED → wave result BLOCKED_MANUAL.** |

---

## 1. What changed

### 1.1 Identity (ADR-0020 §D1, §D2)

| Identifier | Was | Is |
| --- | --- | --- |
| `applicationId`, `namespace`, Kotlin root package | `io.github.yurisismotto.omnibridge` | **`io.github.yurisismotto.pliwee`** |
| Fixture `applicationId` / `namespace` | `…omnibridge.fixture` | **`…pliwee.fixture`** |
| Identity Keystore alias | `omnibridge-identity-v1` | **`pliwee-identity-v1`** (restarts at v1; no legacy sweep) |
| Notification-secret alias | `omnibridge-notification-secret-v1` | **`pliwee-notification-secret-v1`** |
| JSSE key-manager alias (in memory, not persisted) | `omnibridge-identity` | `pliwee-identity` |
| Intent actions / extras | `io.github.yurisismotto.omnibridge.{STOP,APPLY_CLIP,SEND_CLIPBOARD,CLIPBOARD_REQUEST_ID,TARGET_FINGERPRINT}` | **`io.github.yurisismotto.pliwee.*`** |
| Received files (MediaStore) | `Download/OmniBridge` | **`Download/Pliwee`** (also the two UI strings that name it) |
| Multicast-lock tag (W5 hand-off) | `omnibridge-discovery` | `pliwee-discovery` |
| In-app brand drawable | `logo_omnibridge_mark` | **`logo_pliwee_mark`** |

**Package move.** All 165 tracked files under `…/io/github/yurisismotto/omnibridge/`
in the four source roots (`app/src/{main,test,androidTest}`, `fixture/src/main`)
were moved with `git mv`. The plan counted 163; W5 added `net/WireProfile.kt`
and `net/PeerProfiles.kt`. `git diff --cached -M` records 168 renames: the 165,
plus `logo_pliwee_mark.xml` and the two retired certificates. Package lines,
imports, fully-qualified references and the test-side source paths
(`src/main/java/io/github/yurisismotto/…`) were rewritten from the
`io.github.yurisismotto.omnibridge` root to `…pliwee`. That covers the app's
own reverse-DNS root and nothing else. No `omnibridge` value outside that root
was touched by the mechanical step: the legacy wire profile is in §8.

### 1.2 Components, frozen from this build (ADR-0020 §"Android component identity")

| Component | Role Android keys by it |
| --- | --- |
| `.notifications.PliweeNotificationListener` (was `OmniBridgeNotificationListener`, `git mv`) | notification-access grant |
| `.ui.ClipboardTileService` | Quick Settings slot |
| `.ui.MainActivity` | launcher, pinned shortcuts |
| `.ui.SendActivity` | share target / direct-share ranking |
| `.ui.PairingCaptureActivity` | — |
| `.service.ConnectionService` | — |

The listener rename is the one component name chosen freshly. D1 preserves
nothing anyway. The new `ManifestComponentsTest` pins this set exactly and
resolves each name to a compiled class. It also pins the role wired to each
component (LAUNCHER, SEND ×2 + SEND_MULTIPLE, the listener's action, QS_TILE)
and the Gradle `applicationId`/`namespace` of the app and the fixture. The
comment there, and `android/README.md` §Identity, state the rule: from now on a
rename keeps the old `ComponentName` (subclass or `activity-alias`), or it is a
breaking change.

### 1.3 Launcher icons and in-app mark from the W0 masters (ADR-0020 §D8)

`docs/reports/branding/pliwee-wave-6/derive_android_icons.py` generates
`ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml` and
`logo_pliwee_mark.xml` from `pliwee-mark.svg` / `pliwee-mark-mono.svg`. It only
reads the masters. The conversion is mechanical (BRAND.md, derivation rule):

* each `pathData` is one of the master's four paths, byte for byte (the
  silhouette, as Wave 0 noted, has **two** subpaths: outer and hole);
* each gradient is the master's own gradient: the same user-space coordinates,
  offsets and colours. `stop-opacity` becomes the alpha byte, round-half-up of
  opacity × 255. A real divergence was caught here: `0.70 × 255 = 178.5`
  gives 178 under Python's banker's rounding and 179 under half-up. The script
  and the test now both use half-up;
* each of the 9 radial paints keeps the master's
  `translate · rotate · scale` numbers in a `<group>`, which VectorDrawable
  composes identically about pivot (0,0). The paint is clipped to the face it
  paints (nested `<clip-path>`). The shape it is painted on is the master's
  viewBox mapped through the inverse transform, so no coordinate is
  astronomically large, even for `scale(23035315.03 36.55)`.

The placement was computed. Welzl's minimum enclosing circle of the flattened
silhouette has centre (149.14, 129.30) and radius 148.08. At scale 0.2147 that
radius is **31.79 of the 33-unit round zone**. The ink spans x[22.4, 80.8]
y[26.7, 80.5], inside the 72-unit square zone, and its span (58.4) is ≥ 0.7 × 72.

`BrandingResourcesTest` now reads the Pliwee masters. It asserts:

* the silhouette and the three faces are carried byte for byte;
* the themed layer draws exactly one path, the silhouette;
* each of the master's stops is present as an `<item>`, and each of the 9
  radial transforms as a `<group>`;
* there are exactly 13 gradients (4 linear + 9 radial);
* the foreground paints with exactly the master's colour set (it was a subset
  check with "≥ 10" before);
* the masks hold, with two subpaths required;
* the dead list gained `omnibridge`. `logo_omnibridge_mark.xml` must be gone,
  and no source may ask for `R.drawable.logo_omnibridge_mark`.

It passes 13/13; it was 12/12.

**Render check** (`render_check.py`, evidence `render-check.txt`). A separate
interpreter re-expresses each generated VectorDrawable as SVG under
VectorDrawable's rules. The result is rendered with librsvg and compared with
the master:

| Comparison | mean \|Δ\| | pixels with any channel \|Δ\| > 16 |
| --- | --- | --- |
| `logo_pliwee_mark.xml` vs `pliwee-mark.svg`, 1104 px | 0.038 / 255 | **2** of 1 126 080 (666 098 ink) |
| `ic_launcher_foreground.xml` vs master placed at the same numbers, 864 px | 0.012 / 255 | **16** of 746 496 (127 448 ink) |
| **Negative control:** one radial's rotation 71.8 → 0 | 1.015 / 255 | **100 690** |

This proves the conversion is faithful *under VectorDrawable semantics*. It does
not prove how Android's own renderer draws the result; that is part of the
hardware look (§7). Preview: `pliwee-wave-6/launcher-render-check.png`.

### 1.4 Signing (ADR-0020 §D3)

* `provision-signing-keys.sh` takes the product identity as data. There is one
  block (`PRODUCT`, `SLUG`, `PACKAGE`, aliases, DNs), with `RETIRED_SLUG=omnibridge`
  used only for comparison. Aliases are `pliwee-app-signing` / `pliwee-upload`,
  DNs `CN=Pliwee, OU=…`. Custody paths are `~/.local/{share,state}/pliwee-android-signing/`,
  and the media directory and bundle are `pliwee-android-signing[-v1.tar.gpg]`.
  The password-manager labels are "Pliwee Android — …", with an explicit "do
  not overwrite the retired OmniBridge entries". `RESTORE.txt` names the Pliwee
  bundle. The one-identity refusal is kept. A new guard refuses any path of the
  retired identity before anything runs (proved: exit 1, nothing created).
  Self-test mode now mirrors the real `runtime/ state/ share/` layout, so a
  retired identity can sit beside the new one. The self-test environment
  variable is `PLIWEE_SIGNING_SELFTEST_ROOT`.
* `tests/provision-selftest.sh` plants a retired OmniBridge identity first: its
  record, an installed upload keystore, and backup directories on both media
  (16-line manifest of names, modes, sizes and SHA-256). It then proves:
  **"an OmniBridge record exists → Pliwee provisioning proceeds, and it is left
  byte-identical"**, and **"a Pliwee record exists → refused"**, with the Pliwee
  record unchanged by that refusal. It also checks the subjects, the aliases,
  that the record names the Pliwee package, and that the record mentions nothing
  of the retired identity.
* `verify-release-bundle.sh` expects package `io.github.yurisismotto.pliwee` and
  the permission `io.github.yurisismotto.pliwee.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  It expects exactly one signer, whose certificate is the **Pliwee** upload
  certificate (`certs/upload-certificate.pem`). Before any verdict it refuses an
  expected certificate that is missing, that is either retired OmniBridge
  certificate, or whose subject is not `CN=Pliwee, OU=Android Upload`.
* `build-release-bundle.sh`: `PLIWEE_UPLOAD_KEYSTORE[_PASSWORD]`, the
  `pliwee-android-signing` default path, the `pliwee-upload` alias, the
  package, and a refusal of any `omnibridge-android-signing` keystore.
* `app/build.gradle.kts`: `PLIWEE_UPLOAD_KEYSTORE[_PASSWORD]`,
  `-Ppliwee.release.unsigned`, `keyAlias = "pliwee-upload"`, and the guard
  message "Pliwee release signing is not configured". `.github/workflows/android-ci.yml`
  greps for the new message. The step's `name:` is unchanged.
* **Certificates.** The OmniBridge PEMs were moved with `git mv` to
  `android/signing/certs/legacy-omnibridge/`, byte-identical (§5).
  `certs/README.md` states what lives where. **No Pliwee certificate exists
  yet** (§7).

### 1.5 Other files

| File | Change |
| --- | --- |
| `android/README.md` | title; new §Identity (ids, frozen components, "a new app"); signing paragraph for the Pliwee identity |
| `android/fixture/README.md` | the three `adb` lines name `…pliwee.fixture` |
| `docs/design/BRAND.md` | dated W6 note; Android rows now say what derives from the Pliwee masters (desktop rows unchanged, W7) |
| `docs/adr/ADR-0019-android-app-signing.md` | dated superseding note under Status; **Addendum — Pliwee signing identity** at the end, with the fingerprint table *pending operator provisioning*. The original text is unchanged. |
| `docs/audits/android/ANDROID-PLAY-V1-DECLARATIONS.md` | dated superseding note under PLAY14 (ADR-0020 D1 requires it). The original text is unchanged. |
| `packaging/tests/lifecycle-peer-gates.sh`, `security-log-evidence.sh` | **only** `APP_PKG`, `FIXTURE_PKG` and the listener component name (§6) |

---

## 2. Tests executed

All runs were sequential, JDK 21, `--offline --no-daemon --max-workers=2`.

| # | Command | Result |
| --- | --- | --- |
| T1 | `./gradlew :app:assembleDebug :app:testDebugUnitTest :app:assembleDebugAndroidTest :fixture:assembleDebug` | **BUILD SUCCESSFUL.** Old results were deleted first; all 57 result files are newer than the start (23:57:30). **57 suites, 864 tests, 0 failures, 0 errors, 0 skipped.** Against W5 (56 / 854): `BrandingResourcesTest` 12 → 13, `WireIdentityTest` 20 → 24, `ManifestComponentsTest` new (5). No suite lost a test. `NotificationSecretTest` 14, `PinnedTrustManagerTest` 7, `PairingProofTest` 12 are unchanged in count and assertions. The instrumented sources compile and package. Per suite: `android-suites-after.txt`. |
| T2 | Mutation run: a stop alpha `#B3E049FB → #B2E049FB`, and the manifest listener renamed back to `OmniBridgeNotificationListener`; `--tests '*BrandingResourcesTest' --tests '*ManifestComponentsTest'` | **Failed as it must:** 4 failures (the stop/transform test; the snapshot, class-resolution and role tests). Both files were restored and checked with `cmp`. `mutation-proof.txt`. |
| T3 | `:app:assembleRelease` and `:app:bundleRelease` with no signing environment | **Refused, for the right reason:** "Pliwee release signing is not configured: PLIWEE_UPLOAD_KEYSTORE is not set.", exit 1, both tasks. |
| T4 | `-Ppliwee.release.unsigned=true :app:assembleRelease` (R8) | BUILD SUCCESSFUL. Labelled "UNSIGNED … must never be uploaded". |
| T5 | `aapt2 dump badging` + `xmltree` on the debug and the R8 release APK, against the pre-W6 APKs of the same variants | **Package** `io.github.yurisismotto.pliwee` (was `…omnibridge`). **Permissions identical** apart from the app's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` root (9 = 9). **Own components exactly** the frozen 6 + `.PliweeApp`, the same roster as before apart from the names. Library components unchanged. `apk-facts-{before,after}.txt`, `aapt2-after-*.txt`. |
| T6 | dex scan of both APKs; `aapt2` of the fixture APK | `Lio/github/yurisismotto/omnibridge/`: **0** matches in any dex. `…/pliwee/proto/Envelope;` is present in the R8 dex, so the keep rule still matches. Fixture package `io.github.yurisismotto.pliwee.fixture`, permission `POST_NOTIFICATIONS`. `dex-and-fixture-facts.txt`. |
| T7 | `-Ppliwee.release.unsigned=true :app:bundleRelease`, then `verify-release-bundle.sh` | V1 default certificate → **STOP** (Pliwee certificate missing). V2/V3 `--expect-cert` on either retired certificate → **STOP** ("retired OmniBridge certificate"). V4 the verifier's `PACKAGE` / `PERMISSIONS` against `bundletool dump manifest` of this R8 bundle → **PASS / PASS (9 = 9)**. `verify-release-bundle-checks.txt`. |
| T8 | `android/signing/tests/provision-selftest.sh` (the test Android CI runs) | **39 passed, 0 failed.** Throwaway keys under `/run/user/1000/pliwee-signing-selftest.*`, shredded on exit. `provision-selftest.txt`. The host's **real** OmniBridge custody files (5: `PROVISIONED`, `upload.p12` and three public files) are byte-identical before and after. No `pliwee-android-signing` directory exists on the host. |
| T9 | provisioning guard: a temp copy with `SLUG=omnibridge`, `--status` | exit 1, "the product identity is the retired omnibridge identity"; nothing created. |
| T10 | `:app:lintDebug` | **1 error, 49 warnings** (W5: 1 error, 36). The error is the known `StartActivityAndCollapseDeprecated` at `ClipboardTileService.kt:100` (CI documents it as a non-gate). New: `VectorPath` 5 → 17 and `VectorRaster` 1, from the master's long paths (performance advice, expected). `CustomX509TrustManager` 1 and `ModifierParameter` 1 are on files whose only change is the `package`/`import` lines (`PinnedTrustManager.kt` diff shown in the session). The likeliest reason they were absent from W5's capture is lint's partial-result cache (every file moved, so everything was re-analysed). This was not investigated further. `android-lint-results.txt`. |
| T11 | `derive_android_icons.py --check` | three files SAME. |
| T12 | digests (§5) | PASS × 11 |
| — | Edited after T1: `docs/design/BRAND.md`, `android/README.md`, `certs/README.md`, the ADR/audit notes and this report. No Android or desktop test reads any of them. `docs/design/` is on the Android test classpath, but only `tokens.json` and `assets/*.svg` are read, and those are unchanged. | T1 is not invalidated |
| T13 | `git diff --check`; YAML parse of `android-ci.yml`; `bash -n` on the 4 signing scripts and 2 harnesses; no new pipe into `grep -q` | clean / ok / ok / none |

---

## 3. Negative and precondition evidence (AGENTS.md)

* **The tool exists:** the verifier dies without keytool, bundletool or the
  expected certificate (unchanged). The new precondition is that the expected
  certificate is Pliwee's.
* **The operation ran:** T1 deleted the old test results and counted fresh
  ones. The APK facts are compared across two observations (pre-W6 APKs, whose
  manifest and Gradle file are unchanged since `140499e`, against this build).
  The selftest compares a 16-line manifest before and after.
* **Exact counts:** 9 = 9 permissions, 6 + 1 components, 13 gradients, 9 radial
  transforms, 2 subpaths, 16 manifest lines, 39/39, 864 = 854 + 10.
* **Can fail:** T2 (4 failures), the render negative control (100 690 pixels),
  and T7 V1–V3.

---

## 4. G6 — exit criteria

| Exit criterion (plan §Wave 6) | Status | Evidence |
| --- | --- | --- |
| APK facts match (package, every component name, permissions exactly as before) | **PASS** | T5, T6 |
| The component upgrade test passes on hardware (Pliwee N → N+1: grant, tile, shortcut survive) | **NOT EXECUTED** | §7 |
| The Pliwee signing identity provisioned and restore-verified, with public fingerprints committed in the ADR-0019 addendum | **NOT EXECUTED (operator)** | §7; the addendum holds a *pending* table |
| The OmniBridge certificates' SHA-256 unchanged | **PASS** | §5 |
| (Unit) `PliweeIdentityTest`, manifest snapshot, `WireIdentityTest` package assertions, `BrandingResourcesTest` over the new layers, signing selftest | **PASS**, except that `PliweeIdentityTest` is instrumented and was **compiled, not run** | T1, T8; §7 |
| (Integration) `:app:assembleRelease` without env → refusal; APK read with aapt2 | **PASS** | T3, T5 |
| (Regression) full Android unit suite; `NotificationSecret*`, `PinnedTrustManagerTest`, `PairingProofTest` names only | **PASS** (unit). Instrumented suite **NOT EXECUTED**. | T1; §7 |

---

## 5. Frozen things, measured

`frozen-digests.txt`:

* **Brand masters (Wave 0 R4 digests): 5/5 PASS**
  (`pliwee-mark.svg` `b1d92756…519c`, `-mono` `15120dd8…0fdf`, `-tonal` `99201df0…ee1b`,
  `wordmark` `6220f2e8…af13`, `lockup` `78792f3e…245de`).
* **Retired OmniBridge certificates:** bytes equal to the `HEAD` blob; file
  SHA-256 `f7629404…c3f4` (app signing) / `f7b92130…f06e` (upload); certificate
  SHA-256 `AB:B6:2F:53:…:AC:49` / `75:FC:88:B5:…:BA:47`, equal to ADR-0019's
  table and ADR-0020 §D3. **6/6 PASS.**

---

## 6. Scope notes

* **`packaging/tests/{lifecycle-peer-gates,security-log-evidence}.sh`** belong
  to W7, but they hold the **Android** package, which this wave owns. Left
  alone, they would fail loudly on a device that has only Pliwee installed.
  On the tablet that still has the OmniBridge app (the plan leaves it installed),
  they would pass their "is installed" check and **measure the wrong app**,
  which is a false green of exactly the AGENTS.md kind. So only `APP_PKG`,
  `FIXTURE_PKG` and the listener component changed (6 lines). Units, drop-ins,
  CLI names and `GUEST_USER` are W7's and untouched.
* **Not done (forbidden or other waves):** no key generated, apart from the
  self-test's throwaway keys, which is the plan's own unit test. No keystore,
  password or backup committed. No Play Console action. `PrivacyPolicy.kt`
  URL unchanged (W10). No legacy-alias sweep. No desktop artwork (W7).

---

## 7. Not executed, and why

| Gate | Why it was not run | How to run it |
| --- | --- | --- |
| **Pliwee signing identity provisioning** (two removable media, restore-verified), then the certificates committed and the fingerprints recorded in the ADR-0019 addendum | The plan forbids generating the keys in CI or in this session. The procedure prints passwords for the operator alone and needs two physical media that are ejected and re-inserted. | The operator, in their own terminal: `JAVA_HOME=/usr/lib/jvm/java-21-temurin-jdk android/signing/provision-signing-keys.sh --media-a /run/media/…/A --media-b /run/media/…/B` (run twice, with the re-mount between runs). Then copy `~/.local/share/pliwee-android-signing/{upload,app-signing}-certificate.pem` to `android/signing/certs/`, and fill the addendum table from `~/.local/state/pliwee-android-signing/PROVISIONED`. The OmniBridge media directory may sit on the same drives; it is not touched. |
| **Component upgrade test** (Pliwee N → N+1: notification-listener grant, QS tile, pinned launcher shortcut survive) and the other hardware checks (share target, NSD on a real LAN, pairing with a Linux host) | A physical SM-X620 (`RX2Y500C7SY`) was **detected** with a read-only `adb devices` and **not used**. It is the maintainer's certification tablet, and the gate installs a new app on it, grants that app notification access, adds a QS tile and pins a shortcut. Those are device changes the operator authorises, and the shortcut pin needs the launcher's confirmation UI. | Build N: `./gradlew :app:assembleDebug`; `adb install -r app/build/outputs/apk/debug/app-debug.apk`; `adb shell cmd notification allow_listener io.github.yurisismotto.pliwee/io.github.yurisismotto.pliwee.notifications.PliweeNotificationListener`; `adb shell cmd statusbar add-tile io.github.yurisismotto.pliwee/io.github.yurisismotto.pliwee.ui.ClipboardTileService`; pin a shortcut by hand. Record `dumpsys notification` (listener `ComponentInfo`), `settings get secure sysui_qs_tiles` and a launcher screenshot. Bump `versionCode`, rebuild N+1, `adb install -r`, and record the same three observations again. |
| **Instrumented suite** (`connectedDebugAndroidTest`, including `PliweeIdentityTest`'s alias checks and `NotificationSecretInstrumentedTest`) | Same device and same reason. Several suites also need the fixture and a granted listener. The sources compile and package (T1). | `./gradlew :app:connectedDebugAndroidTest` on a device the operator designates, or at least `-Pandroid.testInstrumentationRunnerArguments.class=io.github.yurisismotto.pliwee.PliweeIdentityTest`. |
| **Real signed-bundle verification** (`build-release-bundle.sh` → `verify-release-bundle.sh` PASS) | This needs the Pliwee upload key, which does not exist yet. | After provisioning: `BUNDLETOOL=… android/signing/build-release-bundle.sh` |

---

## 8. Legacy identifiers intentionally preserved

| What | Where | Why |
| --- | --- | --- |
| Legacy wire profile: `omnibridge/1`, `omnibridge-data/1`, `_omnibridge._tcp.`, `omnibridge1`, `omnibridge/…/v1` domains, `WireProfile.OMNIBRIDGE` | `net/WireProfile.kt`, `PinnedTrustManager.kt`, `Discovery.kt`, `QrPayload.kt` and their tests | ADR-0020 §D4 through v1.x (W5) |
| `"Run \`omnibridge pair\`"`, scanner `PROMPT` | `DevicesScreen.kt`, `PairingScanner.kt` | the CLI's real name until W7 (plan W6 Areas) |
| `PrivacyPolicy.URL` → `yurisismotto/OmniBridge` | `ui/PrivacyPolicy.kt`, `PrivacyPolicyTest` | W10 (plan P1) |
| Package name in `docs/policy/PRIVACY-POLICY.md` | policy text | W10 owns the privacy policy |
| Retired OmniBridge certificates | `android/signing/certs/legacy-omnibridge/` | ADR-0020 §D3: kept byte-identical |
| `RETIRED_SLUG=omnibridge`, retired-path guards, dead-list entries | signing scripts, `PliweeIdentityTest`, `BrandingResourcesTest`, `WireIdentityTest` | they assert the absence of the old name |
| Instrumentation argument keys `omnibridge.{pairing.payload,peer,granted,…}` | `HostDrivenCertificationHarness.kt` | host-side harness keys with no consumer in the tree; renaming them belongs with the W7 harness rename |
| Canary strings `OMNIBRIDGE-N3-…`, `OMNIBRIDGE-N1-FIXTURE-TITLE`; fixture channel ids `omnibridge-fixture[-group]`; label "OmniBridge Fixture" | androidTest, fixture | test fixtures recorded in certification transcripts; the fixture label is copy (W3 §8) |
| `LocalOmniBridgeColors` (Kotlin type name) | `ui/theme/Theme.kt`, `Status.kt` | a W3 code-namespace leftover, not an OS-persisted identifier; recorded for the W8 remainder audit |
| Test hostnames `omnibridge-d13`, `-u2404`, `-u2604` | unit tests | names of the real certification guests |
| "OmniBridge" in code comments and manifest comments | throughout | prose, recorded by W3 §8 as copy, not code |
| `omnibridge-*.svg` artwork | `docs/design/assets/` | still drawn by the desktop until W7 |
| Historical docs | `docs/audits`, `docs/certification`, `docs/reports` | D7: only the PLAY14 superseding note was added |

---

## 9. Evidence files (`pliwee-wave-6/`)

`derive_android_icons.py`, `render_check.py`, `render-check.txt`,
`launcher-render-check.png`, `android-build-and-unit.txt`,
`android-suites-after.txt`, `mutation-proof.txt`, `apk-facts-before.txt`,
`apk-facts-after.txt`, `aapt2-after-{debug,release}-{badging,manifest-xmltree}.txt`,
`dex-and-fixture-facts.txt`, `verify-release-bundle-checks.txt`,
`provision-selftest.txt`, `frozen-digests.txt`, `android-lint-results.txt`.

---

## 10. Risks and hand-offs

1. **VectorDrawable cost.** The foreground holds long paths (12k characters)
   and 13 gradients with nested clips. Lint flags this as `VectorPath`.
   Launchers rasterise the icon once, so the in-app mark is the only repeated
   draw. It is converted faithfully, but whether it renders correctly on the
   device is part of the hardware look (§7). If it proves slow, ADR-0020 still
   forbids redrawing; the answer would be a rasterised *derivative* made by the
   same script.
2. **Test tablet.** Its OmniBridge app is not uninstalled by anything. After
   the Pliwee app is installed, the device has two apps and two notification
   listeners, so the grant must go to the Pliwee component.
3. **The W7 harness rename** must keep the three Android values set here.
4. **Provisioning order.** Pliwee keys → commit the certificates → fill the
   addendum → then W10 creates the Play app. Until PEPK, rolling back costs
   only the media.

---

## 11. Gate verdict

**G6 — a new identity, made once, and nothing old overwritten.**

* *nothing old overwritten:* **PASS.** The certificates are byte-identical,
  the host's real OmniBridge custody files are unchanged, the self-test proves
  coexistence, and the retired-path guards refuse.
* *a new identity:* the code, manifest, aliases, component snapshot and APK
  facts are **PASS**.
* *made once:* the provisioning itself is **NOT EXECUTED** (operator, two
  media), and so is the hardware component-upgrade test.

**Wave result: BLOCKED_MANUAL.** Everything that can be automated is done and
green. The remaining gates need the operator and the hardware.
