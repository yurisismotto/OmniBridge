# Android / Google Play v1 — readiness audit (PLAY0 → PLAY4)

| | |
| --- | --- |
| Date | 2026-09-24 |
| Branch | `feature/android-google-play-v1`, from `e6027f7` |
| Package | `io.github.yurisismotto.omnibridge` (unchanged) |
| Build host | Fedora 44, JDK 21.0.12 (`~/.local/jdk`), Android SDK platforms 35 + 36, build-tools 35.0.0 |
| Device | Samsung SM-X620, Android 16 / API 36, One UI 8.0 — **not attached during this audit** |
| Scope | PLAY0 audit, PLAY1 API 36 migration, PLAY2 version, PLAY3 release build, PLAY4 signing options |
| Verdict | **ANDROID PLAY V1: BLOCKED** — on the operator's app-signing decision (§6) |

This is an audit in the sense of [`docs/README.md`](../../README.md): it asks
what is ready and what is missing. It certifies nothing. The Linux v1.0.0
release and its tag are not touched by anything here.

Policy facts below were read from official Google sources on 2026-09-24. Each
carries its URL; where a source did not state something, it says so.

---

## 1. Policy baseline (as of 2026-09-24)

| Requirement | Current rule | Source |
| --- | --- | --- |
| Target API | New apps and updates after **2026-08-31** must target **API 36**; extension possible to 2026-11-01 (not needed for a new app) | https://support.google.com/googleplay/android-developer/answer/11926878 |
| AGP for API 36 | AGP **8.10** is the first line whose max supported API is 36; needs Gradle ≥ 8.11.1, JDK 17 | https://developer.android.com/build/releases/agp-8-10-0-release-notes |
| Play App Signing | Google-generated key (default; new apps get hybrid RSA-4096 + ML-DSA-65 signing) **or** developer-supplied key via PEPK; separate upload key, resettable | https://support.google.com/googleplay/android-developer/answer/9842756 |
| Developer verification | From **2026-09-30** every package on Play must be registered; creating an app in Play Console registers its package name. Play identity verification counts as developer verification | https://developer.android.com/developer-verification/guides/google-play-console · https://android-developers.googleblog.com/2026/06/android-developer-verification.html |
| Personal accounts after 2023-11-13 | Closed test, **≥ 12 testers opted in, 14 continuous days**, then apply for production | https://support.google.com/googleplay/android-developer/answer/14151465 |
| FGS declaration | Per type: description, user impact if deferred/interrupted, **video link**, use case | https://support.google.com/googleplay/android-developer/answer/13392821 |
| Data safety | "Collect" = transmitting off device; exemption for end-to-end-encrypted data unreadable by anyone but sender and recipient | https://support.google.com/googleplay/android-developer/answer/10787469 |
| Prominent disclosure | In-app, during normal use, before access, affirmative action, not privacy-policy-only | https://support.google.com/googleplay/android-developer/answer/10144311 |

The developer-verification date is six days after this audit. It does not
block a *new* app — creating it registers the package — but the operator should
create the Play app for this exact package before, not after, 2026-09-30 if
anyone else could plausibly claim it.

---

## 2. PLAY0 — repository audit

### 2.1 Build and release configuration

| Item | Before | Finding |
| --- | --- | --- |
| AGP / Gradle / Kotlin | 8.8.0 / 8.11.1 / 2.1.0 | AGP 8.8 max API is 35 — cannot compile against 36 |
| compileSdk / targetSdk / minSdk | 35 / 35 / 29 | target 35 is below the Play floor |
| versionCode / versionName | 1 / 0.1.0 | |
| `release` build type | `isMinifyEnabled = true`, `proguard-android-optimize.txt` + `proguard-rules.pro` | R8 on; resource shrinking off |
| Release signing | **none** | `bundleRelease` succeeds and writes an **unsigned** AAB with no warning — PLAY6 must make that fail loudly |
| JDK | CI: 17; local: 21 | README already requires JDK 21 locally; the module compiles to Java 17 |

### 2.2 Manifest and permissions (merged release manifest)

`INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
`CHANGE_NETWORK_STATE`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS`, `CAMERA`, and the
AndroidX-generated `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. No location,
storage, `QUERY_ALL_PACKAGES`, accessibility or overlay permission.
Package visibility is a `<queries>` for launcher intents only.

Components: `MainActivity` (exported, launcher), `SendActivity` (exported,
`SEND`/`SEND_MULTIPLE`), `PairingCaptureActivity` (not exported),
`ConnectionService` (`connectedDevice`, not exported),
`OmniBridgeNotificationListener` (bound by `BIND_NOTIFICATION_LISTENER_SERVICE`,
`default_autobind=false`), `ClipboardTileService` (bound by
`BIND_QUICK_SETTINGS_TILE`). `allowBackup="false"`; `data_extraction_rules`
excludes every domain. Cleartext traffic disabled.

`connectedDevice` prerequisite is met by `CHANGE_WIFI_MULTICAST_STATE` and
`CHANGE_NETWORK_STATE`, both of which the app actually uses (mDNS
`MulticastLock`).

### 2.3 External SDKs

AndroidX (core, lifecycle, activity, Compose BOM 2024.12.01), kotlinx-coroutines,
protobuf-javalite 4.29.1, `zxing-android-embedded` 4.3.0. **No** Google Play
Services, Firebase, ML Kit, analytics, crash reporting, advertising or
telemetry. No HTTP client. This stays so.

### 2.4 Data flows (summary; the Data Safety worksheet is PLAY9)

| Flow | Direction | Trigger | Content |
| --- | --- | --- | --- |
| Clipboard | Android → desktop | **manual only** (Send screen, QS tile → MainActivity, share-sheet text); `AUTO_SEND_SUPPORTED = false` | text ≤ 32 KiB, SHA-256, sensitive hint, ids, timestamp |
| Clipboard | desktop → Android | peer push; held pending ≤ 5 min in memory unless per-peer `autoReceive` | text |
| Files | both | user picks (SAF / share sheet); every incoming file approved | name, size, MIME, SHA-256, bytes → `Download/OmniBridge` via MediaStore |
| Notifications | Android → desktop only | per-peer grant + per-app allow-list + system access, while a granted peer is connected | package, app label, title, text, time, importance, category, flags, progress, hashed ids. No icons, actions, big text, people |
| Battery | both | on connect and on change | percentage, charging state, timestamp |
| Identity | both | HELLO / TLS | random 128-bit device id, device name (defaults to `Build.MODEL`), SPKI fingerprint, capability list. No ANDROID_ID or hardware id |

Persisted on the device: `filesDir/trust-store.json` (paired peers,
fingerprints, grants, up to four remembered addresses, clipboard and
notification policies including chosen package names); Keystore P-256
identity key (non-exportable, StrongBox when present); Keystore HMAC secret for
notification ids. No clipboard text or notification content on disk.

Transport: TLS 1.3 only, mutual authentication, SPKI pinning, no CA; pairing
by QR (`omnibridge1:<fp>:<token>:<id>:<addrs>`) plus HMAC-SHA256 proof.

### 2.5 Findings that affect Play submission

Numbered for later phases to cite. **None was fixed in this pass**; each is a
product change outside the API 36 migration and is listed for a decision.

| # | Finding | Evidence | Affects |
| --- | --- | --- | --- |
| F1 | **Battery grant is not enforced.** The per-peer *Battery* switch does not stop the reading leaving the phone: `BatteryCapability.onPeerConnected` sends it for every *negotiated* capability, and `PeerConnection.run` dispatches over `negotiatedCapabilities` without consulting grants. The card also says "Nothing is granted automatically", while pairing grants `files.v1` and `battery.v1` | `capability/BatteryCapability.kt:37-40`, `net/PeerConnection.kt:153-157`, `OmniBridgeApp.kt:534`, `ui/PeerDetailScreen.kt:151-152` | PLAY7 privacy policy truthfulness, PLAY9 |
| F2 | `POST_NOTIFICATIONS` is requested on **every** `MainActivity.onCreate`, not in context | `ui/MainActivity.kt:184-186` | PLAY8, pre-launch report |
| F3 | Notification disclosure is split: the full "what is shared" text sits at the bottom of the screen and is not a gate before the Settings intent; enabling the per-computer switch shows no confirmation. Fields shared are not enumerated | `ui/NotificationSettingsScreen.kt:177-185, 372-377`, `res/values/strings.xml:64-70, 158-159` | PLAY8 |
| F4 | No privacy-policy link anywhere in the app | `ui/SettingsScreen.kt` | PLAY7 (hard requirement) |
| F5 | Settings says "transfers are not logged", but sanitized filenames and sizes are logged at INFO and release builds keep `Log` calls | `ui/SettingsScreen.kt:84-90`, `files/FileTransferManager.kt:377, 490, 757` | PLAY7 truthfulness |
| F6 | QS tile sends immediately when exactly one computer is eligible — a user action, but no confirmation screen | `ui/MainActivity.kt:559-586` | PLAY9 note only |
| F7 | No identity-reset UI (`IdentityReset` has no caller) | `identity/IdentityReset.kt` | PLAY7 retention wording |
| F8 | FGS notification has no Stop action; stopping is from the app (Disconnect) | `service/ConnectionService.kt:388-411` | PLAY10 wording, not a defect |
| F9 | ADR-0015 and THREAT_MODEL record Play notification-access policy (OQ-09) as "not yet cleared" before any Play submission | `docs/adr/ADR-0015-notification-access.md:371-374`, `docs/security/THREAT_MODEL.md:576-578` | PLAY8 closes it |
| F10 | Lint `CustomX509TrustManager` on the pinning trust manager — intentional, may surface in pre-launch/security review | `net/PinnedTrustManager.kt:35` | PLAY19 classification |

### 2.6 CI, tests, assets, locales

* **CI**: `.github/workflows/android-ci.yml` — JDK 17, `assembleDebug`,
  `assembleDebugAndroidTest`, `testDebugUnitTest`. No release build, no
  signing, no secrets. Lint is recorded debt (one pre-existing error,
  `StartActivityAndCollapseDeprecated`, version-gated call site).
* **Tests**: 54 JVM suites; 11 instrumented suites (device only).
* **Brand assets**: `docs/design/assets/` is the canonical source; the
  launcher icon is an adaptive vector. Store assets are PLAY12.
* **Locales**: English only (`res/values`). Several UI strings are hard-coded
  in Kotlin.

### 2.7 Signing material and secrets

| Check | Result |
| --- | --- |
| Tracked `*.jks *.keystore *.p12 *.pfx *.pem *.key key.properties local.properties` | none |
| Same, anywhere in git history (`git log --all`) | none |
| `signingConfig`, `storePassword`, `keyPassword`, `storeFile`, `keyAlias` in any Gradle or properties file | none |
| GitHub Actions secrets referencing Android | none (`RELEASE_SIGNING_KEY` is the Linux GPG key for `SHA256SUMS`) |
| Keystores on the build host | only `~/.android/debug.keystore` (the SDK debug key) |
| `.gitignore` | covered `*.apk *.aab *.key local.properties`; **did not** cover `*.jks *.keystore *.p12 *.pfx key.properties` — added in this pass |

**No Android production signing material exists.**

---

## 3. PLAY1 — API 36 migration

### 3.1 What changed, and only that

| File | Change | Why required |
| --- | --- | --- |
| `android/gradle/libs.versions.toml` | `agp` 8.8.0 → **8.10.1** | AGP 8.8 cannot compile against API 36; 8.10 is the first line that can, and it runs on the existing Gradle 8.11.1 |
| `android/app/build.gradle.kts` | `compileSdk` 35 → **36**, `targetSdk` 35 → **36** | Play requirement |
| `.github/workflows/android-ci.yml` | installs the platform each module declares (36 for `:app`, 35 for `:fixture`); header facts updated | the fixture stays at 35, so CI must install both |
| `android/README.md` | platform 36, why AGP moved | |

Unchanged: Gradle 8.11.1, Kotlin 2.1.0, Compose BOM, every library, JDK 17
bytecode, minSdk 29. `:fixture` (test-only, never shipped) stays at 35 so it
remains the fixture its certification runs measured.

### 3.2 Build evidence (JDK 21.0.12, SDK platform 36 r2)

```
./gradlew --no-daemon --max-workers=2 :app:assembleDebug :fixture:assembleDebug \
    :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:assembleRelease :app:bundleRelease
BUILD SUCCESSFUL in 3m 35s
testDebugUnitTest: 54 suites, 828 tests, 0 failures, 0 errors, 0 skipped
```

`:app:lintDebug`: 1 error, 36 warnings. The error is the same pre-existing
`StartActivityAndCollapseDeprecated`; no new API 36 issue. The two
`DiscouragedApi` warnings flag `screenOrientation="unspecified"`, which is the
platform default and not a fixed orientation.

`aapt2 dump badging` of the release APK:

```
package: name='io.github.yurisismotto.omnibridge' versionCode='1' versionName='1.0.0'
  compileSdkVersion='36' compileSdkVersionCodename='16'
targetSdkVersion:'36'
```

### 3.3 Android 16 behaviour changes against OmniBridge

Source: https://developer.android.com/about/versions/16/behavior-changes-16 and
…/behavior-changes-all.

| Change (targeting 36 unless noted) | OmniBridge surface | Assessment | Proof |
| --- | --- | --- | --- |
| Edge-to-edge opt-out removed | all activities | App has no `windowOptOutEdgeToEdgeEnforcement`; it already ran edge-to-edge on Android 15+ at target 35, and the scanner has its own inset handler | device |
| Predictive back on by default; `onBackPressed` not called | navigation | No `onBackPressed` override; back is a Compose `BackHandler` (`OmniBridgeShell.kt:67`), which rides `OnBackPressedDispatcher` | device |
| sw ≥ 600dp: orientation, resizability, aspect ratio ignored | **SM-X620 is a tablet** | Only declarations are `screenOrientation="unspecified"`; `PairingScanner` disables the library's runtime lock. More recreation is possible on rotate/resize | device |
| Local network protection | mDNS, TCP to peer | Opt-in test flag only at 36; enforced from API **37** via `ACCESS_LOCAL_NETWORK`. No action now; it will matter when targeting 37 | n/a |
| Intent redirection hardening (all apps) | share sheet, tile → activity | All PendingIntents explicit and `FLAG_IMMUTABLE`; no intent relaying | code |
| JobScheduler quotas (all apps) | — | No JobScheduler / WorkManager | code |
| FGS, notification listener, clipboard, camera | — | No target-36 change listed | device smoke in PLAY17 |
| `scheduleAtFixedRate`, `elegantTextHeight`, health, Bluetooth intents, `MediaStore.getVersion` | — | not used | code |

**Not executed in this pass: every "device" row.** The SM-X620 was not
attached (`adb devices` empty). These are recorded as *not measured*, not as
passing, and are carried to PLAY17.

---

## 4. PLAY2 — version

`versionName` is now **1.0.0**. `versionCode` stays **1**.

Repository evidence that no bundle has been uploaded:
`docs/certification/release/V1.0.0-GA-RELEASE.md` (§ "No Google Play release,
no Play Console change, no AAB submission") and `RC-CERTIFICATION-V1.md`
("no Play Console release has been started"). That is evidence about the
repository, not about Play Console; the operator confirms it at the PLAY18
gate. If Play has ever received a bundle for this package, the code is raised
before anything is uploaded.

The rule from now on, recorded in `app/build.gradle.kts`:

* `versionName` follows the public semantic release version;
* `versionCode` rises for every upload to any Play track and is never reused,
  including for a rejected bundle.

---

## 5. PLAY3 — release build

`:app:bundleRelease` produces `app/build/outputs/bundle/release/app-release.aab`
(3.88 MB). R8 ran (`minifyReleaseWithR8`, 30 MB mapping): application classes
are obfuscated, the 185 `…omnibridge.proto.*` entries map to themselves as
`proguard-rules.pro` requires. The merged release manifest has no
`debuggable`.

**That AAB is not a production artifact.** It carries no signature at all:
there is no release `signingConfig`, and nothing fails. Its hash is not
recorded because it will never be uploaded. Production signing is PLAY5/PLAY6,
after the decision below.

---

## 6. PLAY4 — app signing model (operator decision)

Both models use Play App Signing: Google signs what users download, and the
maintainer signs uploads with a **separate upload key**. The difference is
who generated — and who else holds — the **app signing key**, which is the
certificate every installed copy is bound to forever.

| | **A — Google-generated app signing key** | **B — maintainer-generated, supplied to Play (PEPK)** |
| --- | --- | --- |
| Who holds the app signing key | Google only; it cannot be downloaded | maintainer (offline) **and** Google |
| GitHub APK that updates a Play install | **Impossible** — a GitHub APK must use another key, and Android refuses an update whose certificate differs | **Possible** — same certificate on both channels |
| F-Droid / other stores | Other key per store; each channel is its own install lineage | F-Droid can ship the maintainer-signed APK if builds are reproducible; otherwise F-Droid signs with its own key either way |
| Switching channel | uninstall + reinstall (app data lost) | in-place update |
| Loss of upload key | reset via Play Console | same |
| Loss of app signing key | cannot happen on the maintainer side | Play keeps signing; **off-Play distribution under that identity ends** |
| Leak of app signing key | cannot happen on the maintainer side | attacker can sign sideload "updates" that install over genuine copies; Play-side key upgrade exists but older Android versions keep trusting the old key |
| Custody burden | upload key only | a long-lived key that must outlive the project, with encrypted offline backups |
| Play-side extras | default hybrid (RSA-4096 + ML-DSA-65) signing for new apps | not stated in the help centre for a supplied key — to be checked in the console before choosing |

Developer verification (2026-09-30) lets additional signing keys be registered
for the same package in either model, which keeps a GitHub-signed APK
*installable* — but not *updatable over* a Play install under model A.

**Recommendation for OmniBridge: B.** OmniBridge ships from GitHub today, its
ADRs reject a dependency on Google services, and the users most likely to
install it are the ones who move between GitHub, F-Droid and Play. Model B is
the only one in which those remain one app. The price is custody of a key that
must never be lost or leaked; PLAY5 designs that custody before anything is
generated.

Choose **A** instead if Play is intended to be the only Android channel, or if
no one can commit to keeping an offline key safe for the life of the project.
It is the lower-risk choice for a single maintainer, and it is reversible in
the sense that GitHub APKs can still exist under a separate key.

**No key has been generated.**
