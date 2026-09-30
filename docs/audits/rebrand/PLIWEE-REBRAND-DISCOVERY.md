# Pliwee rebrand — discovery audit

**Branch audited:** `feature/android-google-play-v1` at `ba408c6`
**Date:** 2026-09-24
**Scope:** every tracked file, every case-insensitive occurrence of `anyflow`
and `omnibridge`, every path carrying either name, and the grep-invisible
carriers (certificates, raster images). Read-only: nothing in the product was
changed to produce this document.

**Placement.** The request named `docs/rebrand/`. This is an occurrence audit
written *before* the work ("is this ready, and what is missing?"), and
[`docs/README.md`](../../README.md) already maps that kind of document to
`docs/audits/<area>/`, with `audits/rebrand/` holding its sibling
[`OMNIBRIDGE-REBRAND-REMAINDER-AUDIT.md`](OMNIBRIDGE-REBRAND-REMAINDER-AUDIT.md).
[AGENTS.md § Documentation placement](../../../AGENTS.md#documentation-placement)
forbids creating a new directory for a document that belongs beside its
siblings, so it lives here. A later record of the rename itself belongs in
`docs/migrations/` and the decision in a new ADR (see §14).

No secret, key material, token, pairing proof or clipboard/notification
content appears in this document. Certificate *fingerprints* quoted in §6 are
public by design.

---

## 1. Executive Summary

**The name has been changed twice before, and the repository records how.**
*Fedroid Bridge → AnyFlow* ([ADR-0011](../../adr/ADR-0011-project-naming-and-wire-identifiers.md))
and *AnyFlow → OmniBridge* ([ADR-0018](../../adr/ADR-0018-rename-to-omnibridge.md))
both renamed **everything** — ALPN strings, mDNS type, HMAC domain separators,
`applicationId`, Keystore aliases, state paths — "with no compatibility aliases
and no dual-stack support". ADR-0018 could do that because, in its own words,
"There has been **no public v1 release** … there is no compatibility contract
to honour."

**That premise no longer holds, and it is the single most important finding
here.** `v1.0.0` is a published, non-draft, non-prerelease GitHub release
(published `2026-09-24T03:45:55Z`), with 14 signed Linux artifacts all named
`omnibridge*`:

```console
$ gh release view v1.0.0 -R yurisismotto/OmniBridge   # abridged
title:  OmniBridge v1.0.0      draft: false   prerelease: false
asset:  omnibridge-1.0.0-1.fc44.x86_64.rpm
asset:  ubuntu2404-omnibridge_1.0.0-1_amd64.deb
asset:  omnibridge-release-pubkey.asc
...
```

Download counts on those assets were **1–5 each** at the time of this audit
(§9.1), so the installed base is small and probably mostly the maintainer's
own verification — but it is **not zero and not knowable**. Each such install
holds a device identity and a trust store under `~/.local/share/omnibridge/`.

**Android has not shipped.** No AAB has been uploaded, no Play Console app has
been created ([ANDROID-PLAY-V1-READINESS-AUDIT.md](../android/ANDROID-PLAY-V1-READINESS-AUDIT.md)
"no bundle has been uploaded"; [ANDROID-PLAY-V1-DECLARATIONS.md](../android/ANDROID-PLAY-V1-DECLARATIONS.md):231
"when the app is created" at PLAY18), and no APK is among the release assets.
The same readiness audit records that **from 2026-09-30 every package on Play
must be registered, and creating the app in Play Console registers its package
name.** Once the app exists on Play, its `applicationId` and its app-signing
key are permanent for the life of the listing. That makes the Android identity
decisions (§14 D1–D3) time-critical: they are free today and cannot be undone
after PLAY18.

**Consequence for the wire protocol.** Because no public Android build exists,
no public Linux v1.0.0 install can be paired with anything but a self-built
phone. A clean break of the wire identifiers (ALPN, mDNS, QR prefix, domain
separators) therefore still costs almost nobody **today** — and becomes a
real dual-stack problem the day an Android build reaches Play. Whether to
rename them is a decision (D4), not a default; §10 gives the recommendation.

### Numbers

| Measure | Value |
|---|--:|
| Tracked files | 630 |
| **Affected files (content or path)** | **578** |
| — matched by content | 571 |
| — matched by path only | 7 |
| Tracked paths whose name carries the brand | 190 |
| Files containing `anyflow` (any case) | 66 |
| Files containing `omnibridge` (any case) | 536 |
| Occurrences of `anyflow` (any case) | 2 572 |
| Occurrences of `omnibridge` (any case) | 6 870 |
| Files containing `fedroid` (pre-AnyFlow name) | 9 |
| Grep-invisible brand carriers (§8, §6) | 10 (2 PEM certificates, 8 Play PNGs) |

```console
$ git grep -liaE 'anyflow|omnibridge' | wc -l                  # 571
$ git ls-files | grep -ciE 'anyflow|omnibridge'                 # 190
$ git grep -ohaiE anyflow | wc -l ; git grep -ohaiE omnibridge | wc -l
```

`-a` matters: the two DER vectors in `protocol/testdata/` contain NUL bytes and
a grep without it silently misses them — the trap the remainder audit already
recorded.

### Risk distribution over the 578 files (§15)

| Risk | Files | What it mostly is |
|---|--:|---|
| `SAFE_RENAME` | 396 | Kotlin/Rust symbols, UI strings, tests, CI, live docs |
| `DO_NOT_RENAME_WITHOUT_DECISION` | 130 | 118 historical-evidence docs + identity, signing and frozen vectors |
| `MIGRATION_REQUIRED` | 36 | state paths, app id / D-Bus name, packages, systemd unit, privacy URL |
| `COMPATIBILITY_SENSITIVE` | 16 | wire identifiers and domain separators, both languages, and the protobuf schemas |

### Historical names found

| Name | Where it survives | Status |
|---|---|---|
| **OmniBridge** / `omnibridge` / `OMNIBRIDGE` / `Omnibridge` (1 file) / `omniBridge` (Kotlin lower-camel) | everywhere active | current identity — subject of this audit |
| **AnyFlow** / `anyflow` / `ANYFLOW` | 66 files: historical evidence, ADRs, migration note, negative tests, two frozen DER vectors, code comments | classified remainder of the last rename |
| **Fedroid Bridge** / `fedroid` | 9 files: ADR-0011/0018, migration + audit docs, and four negative tests that assert it is absent | fully retired |
| `OB_` (abbreviation) | `OB_PW` (Android key provisioning), `OB_VERSION` (Debian build) | internal shell variables |
| Tagline *One bridge. Any device.* | desktop panel, `.desktop` `Comment=`, Play feature graphic (in pixels), docs | brand — needs a Pliwee tagline (D8) |

No variants `any-flow`, `any_flow`, `omni-bridge`, `omni_bridge` or `Anyflow`
exist in the tree.

---

## 2. Current Branding Inventory *(category A)*

| Surface | Current | Files |
|---|---|---|
| Android app label | `<string name="app_name">OmniBridge</string>` | `android/app/src/main/res/values/strings.xml` |
| Android UI copy | 17 lines of `strings.xml` name the product ("Send with OmniBridge", disclosure, privacy, files) | `strings.xml` |
| Android clipboard label | `DEFAULT_LABEL = "OmniBridge"` (the `ClipData` label other apps can see) | `clipboard/SystemClipboard.kt:208` |
| Android theme names | `Theme.OmniBridge`, `Theme.OmniBridge.Dialog`, colours `omnibridge_background[_dark]`, `omnibridge_accent` | `res/values*/themes.xml`, `colors.xml` |
| Desktop window/panel titles | `"OmniBridge"`, `"OmniBridge Settings"`, subtitle *One bridge. Any device.* | `desktop/gui/src/lib.rs`, `panel/mod.rs` |
| Desktop user messages | 81 source lines across the GUI ("The OmniBridge service is not running", …) | `desktop/gui/src/panel/model.rs`, `views/*.rs` |
| Tray | `ITEM_TITLE`, `TOOLTIP_TITLE = "OmniBridge"` | `desktop/platform-linux/src/tray/model.rs` |
| CLI | `about = "OmniBridge control"`, hints "Run: omnibridge pair" | `desktop/cli/src/main.rs` |
| Daemon | `about = "OmniBridge daemon"` | `desktop/daemon/src/main.rs` |
| Default device names | `"OmniBridge Desktop"`, `"OmniBridge Device"` — **persisted** into peers' trust stores as the advertised name | `desktop/core/src/platform/unix_fs.rs:245`, `store.rs:221` |
| `.desktop` entry | `Name=OmniBridge`, `Comment=One bridge. Any device. …` | `desktop/gui/data/io.github.yurisismotto.omnibridge.desktop` |
| AppStream | `<name>OmniBridge</name>`, description | `…omnibridge.metainfo.xml` |
| firewalld | `<short>OmniBridge</short>` | `packaging/fedora/omnibridge-firewalld.xml` |
| Package descriptions | spec `%description`, debian `Description:` | `packaging/fedora/omnibridge.spec`, `packaging/debian/control` |
| Play listing text | title, short/long description, website | `docs/design/PLAY-STORE-LISTING.md` |
| Privacy policy | product name throughout; its URL is compiled into the app (§7) | `docs/policy/PRIVACY-POLICY.md` |
| Brand standard | `docs/design/BRAND.md`, `UI-GUIDELINES.md`, `tokens.json` | `docs/design/` |
| Entry points | `README.md` (title, badges, install), `AGENTS.md`, `docs/README.md` title | root, `docs/` |
| Artwork | §8 | `docs/design/assets/`, Android drawables |

All of A is `SAFE_RENAME` **except** the two default device names, which are
written into state and sent to peers (a rename only affects identities created
afterwards; existing names are the user's), and the privacy-policy URL (§7).

---

## 3. Code Naming Inventory *(category B)*

| Kind | Current | Count / location | Risk |
|---|---|---|---|
| Cargo workspace | `desktop/Cargo.toml`, members listed by path; `repository = …/omnibridge` | 1 | SAFE_RENAME |
| Rust crates | `omnibridge-core`, `-proto`, `-control`, `-runtime`, `-daemon`, `-cli`, `-gui`, `-linux`, `-capability-{battery,clipboard,files,notifications}` | 12 crates; `omnibridge_*` paths in 102 `.rs` files | SAFE_RENAME (not published to crates.io — nothing external depends on the names) |
| Rust lib target | `omnibridge_gui` | `desktop/gui/Cargo.toml:25` | SAFE_RENAME |
| Kotlin package | `io.github.yurisismotto.omnibridge` (+ `.capability .clipboard .files .identity .net .notifications .pairing .service .store .ui .ui.components .ui.theme`) | 163 `.kt` files under `…/omnibridge/`; the directory path itself | SAFE_RENAME for code — **but** the package is part of three component names, see §9.2 C18 |
| Kotlin types | `OmniBridgeApp`, `OmniBridgeNotificationListener`, `OmniBridgeTheme`, `OmniBridgeType`, `OmniBridgeSpacing`, `OmniBridgeRadius`, `OmniBridgeIconSize`, `OmniBridgeStatus`, `OmniBridgeGradient`, `OmniBridgeColorScheme`, ~20 `OmniBridge*` composables (`Card`, `PrimaryButton`, `SectionLabel`, `StatusBadge`, `BrandMark`, `RibbonFlourish`, …), `omniBridgeContentColumn` | `ui/theme/*.kt`, `ui/components/*.kt`, `ui/*.kt` | SAFE_RENAME |
| Generated proto Java package | `io.github.yurisismotto.omnibridge.proto[.capabilities]` | from `java_package` | SAFE_RENAME (Android-local; §4 of protocol) |
| Gradle root project | `rootProject.name = "OmniBridge"`; modules `:app`, `:fixture` (unbranded) | `android/settings.gradle.kts` | SAFE_RENAME |
| Android `namespace` | `io.github.yurisismotto.omnibridge`, `…omnibridge.fixture` | `app/`, `fixture/build.gradle.kts` | SAFE_RENAME (decoupled from `applicationId`; drives `R` class) |
| Gradle property | `-Pomnibridge.release.unsigned=true` | `android/app/build.gradle.kts` | SAFE_RENAME (document in release procedure) |
| Binaries | `omnibridge` (CLI), `omnibridged` (daemon), `omnibridge-gui` | `[[bin]]` in `cli/`, `daemon/`, `gui/Cargo.toml` | **MIGRATION_REQUIRED** — installed at `/usr/bin/*` by v1.0.0 packages; referenced by the systemd unit, D-Bus service file, `.desktop` `Exec=`, `StartupWMClass=` |
| GResource bundle | `omnibridge.gresource`, prefix `/io/github/yurisismotto/omnibridge` | `desktop/gui/data/omnibridge.gresource.xml`, `gui/src/lib.rs`, `widgets.rs` | SAFE_RENAME (compiled in) |
| Log tags | `OmniBridgeApp`, `OmniBridgeListener`, `OmniBridgeFixture`; `omnibridge-gui:` stderr prefix | Android `TAG`s, GUI `eprintln!` | SAFE_RENAME — but certification harnesses grep these (§G) |
| Thread / lock names | `omnibridge-clipboard-x11`, multicast lock `omnibridge-discovery` | x11 backend, `Discovery.kt:63` | SAFE_RENAME |
| X11 atom | `_OMNIBRIDGE_CLIPBOARD_WATCH_STOP` | `clipboard/src/backend/x11.rs:153` | SAFE_RENAME (process-private) |
| Temp files | `.omnibridge-<id>.part`, `/tmp/omnibridge-fake-phone`, `omnibridge-bundle.XXXX` | `files/src/destination.rs:86`, examples, release script | SAFE_RENAME — but see §9.2 C14 for leftover `.part` files |
| Shell variables | `OB_PW`, `OB_VERSION` | `android/signing/provision-signing-keys.sh`, `packaging/debian/build-deb.sh` | SAFE_RENAME (optional) |

---

## 4. Persistent Identifier Inventory *(category C)*

These are strings **written somewhere that outlives the process**, or that the
operating system keys state by.

### 4.1 Android

| Identifier | Current | Where defined | What the OS keys by it | Risk |
|---|---|---|---|---|
| `applicationId` | `io.github.yurisismotto.omnibridge` | `android/app/build.gradle.kts:49` | the app's entire identity: private storage, Keystore, permissions, Play listing, signing continuity | **DO_NOT_RENAME_WITHOUT_DECISION** (D1) |
| Fixture `applicationId` | `io.github.yurisismotto.omnibridge.fixture` | `android/fixture/build.gradle.kts:48` | test-only, never shipped | SAFE_RENAME |
| Notification-listener component | `io.github.yurisismotto.omnibridge/io.github.yurisismotto.omnibridge.notifications.OmniBridgeNotificationListener` | manifest `.notifications.OmniBridgeNotificationListener` | **the user's notification-access grant** | MIGRATION_REQUIRED (§9.2 C18) |
| QS tile component | `….ui.ClipboardTileService` | manifest | the tile's slot in the user's Quick Settings | MIGRATION_REQUIRED if the package moves |
| Launcher activity | `….ui.MainActivity` | manifest | pinned launcher icon / home-screen shortcuts | MIGRATION_REQUIRED if the package moves (`activity-alias` fixes it) |
| Keystore identity alias | `omnibridge-identity-v1` | `identity/DeviceIdentity.kt:74` | the device's ECDSA P-256 identity key | **DO_NOT_RENAME_WITHOUT_DECISION** (§6) |
| Keystore notification secret | `omnibridge-notification-secret-v1` | `notifications/NotificationSecret.kt:152` | HMAC key for notification ids | DO_NOT_RENAME_WITHOUT_DECISION (§6) |
| Trust store file | `filesDir/trust-store.json` | `store/TrustStore.kt:706` | unbranded; lives inside the `applicationId` sandbox | none by itself |
| Notification channels | `connection`, `clipboard` (fixture: `omnibridge-fixture`) | `ConnectionService.kt:416`, `ClipboardNotifications.kt:128` | per-channel user settings | none (unbranded) |
| Intent actions | `io.github.yurisismotto.omnibridge.{STOP,APPLY_CLIP,SEND_CLIPBOARD}`, extra `…CLIPBOARD_REQUEST_ID` | `ConnectionService.kt:419`, `ClipboardNotifications.kt:132`, `MainActivity.kt:696,706` | embedded in `PendingIntent`s of notifications that may still be on screen across an update; the QS-tile/launcher shortcut | SAFE_RENAME (a stale notification's button stops working once) |
| Download folder | `Download/OmniBridge` (MediaStore `RELATIVE_PATH`) | `files/Downloads.kt:51` | user-visible, survives uninstall | MIGRATION_REQUIRED (policy decision, §9.2 C15) |
| Backups | `allowBackup="false"`, all domains excluded | manifest, `res/xml/data_extraction_rules.xml` | — | no backup-restore path to worry about |
| SharedPreferences / DataStore | **none** — no `getSharedPreferences` / `dataStore` call in `android/app/src/main` | — | — | none |

### 4.2 Linux desktop

| Identifier | Current | Where defined | Risk |
|---|---|---|---|
| Data directory | `$XDG_DATA_HOME/omnibridge` → `~/.local/share/omnibridge` (`identity.key`, `state.json` = identity + trust store) | `desktop/core/src/platform/unix_fs.rs:216-221`; unit comment | **MIGRATION_REQUIRED** (§11.1) |
| Config directory | `$XDG_CONFIG_HOME/omnibridge/gui.json` → `~/.config/omnibridge/gui.json` (GUI peer selection) | `desktop/gui/src/selection.rs:187` | MIGRATION_REQUIRED (low value; losing it resets a selection) |
| Runtime directory / control socket | `$XDG_RUNTIME_DIR/omnibridge/control.sock`; fallback `/tmp/omnibridge-<uid>/…` | `desktop/platform-linux/src/lib.rs:96-97`; unit `RuntimeDirectory=omnibridge` | MIGRATION_REQUIRED (tied to daemon + clients; volatile) |
| Cache / log directories | **none** — no cache dir; logs go to stderr / journald under the unit name | — | — |
| Received files | `~/Downloads/OmniBridge` | `desktop/capabilities/files/src/sink.rs:117` | MIGRATION_REQUIRED (policy, §9.2 C15) |
| Desktop application id (one string, by design) | `io.github.yurisismotto.omnibridge` — GApplication id, **D-Bus well-known name**, `.desktop` basename, `Icon=`, hicolor icon name, AppStream `<id>`, SNI `Id`/`IconName`, notification `app_name`/`APP_ID` | `desktop/gui/src/lib.rs:71`, `gui/build.rs:16`, `platform-linux/src/tray/model.rs:27,36`, `platform-linux/src/activation.rs:323`, `capabilities/notifications/src/backend/dbus.rs:76` | **MIGRATION_REQUIRED** |
| D-Bus object path | `/io/github/yurisismotto/omnibridge` | `tray/model.rs:36` | MIGRATION_REQUIRED (moves with the id) |
| D-Bus activation file | `/usr/share/dbus-1/services/io.github.yurisismotto.omnibridge.service` | `desktop/gui/data/…service.in` | MIGRATION_REQUIRED |
| systemd user unit | `omnibridged.service` → `/usr/lib/systemd/user/omnibridged.service`, enabled by the user with `systemctl --user enable --now` | `packaging/common/omnibridged.service` | **MIGRATION_REQUIRED** — the *enablement symlink* lives in the user's `~/.config/systemd/user/default.target.wants/` and the package cannot see it |
| firewalld service | `omnibridge` → `/usr/lib/firewalld/services/omnibridge.xml`; users add it to zones **by name** | `packaging/fedora/omnibridge-firewalld.xml` | **MIGRATION_REQUIRED** — a zone referencing a removed service name makes `firewall-cmd --reload` fail |
| Installed paths | `/usr/bin/omnibridge{,d,-gui}`, `/usr/share/applications/…omnibridge.desktop`, `/usr/share/metainfo/…metainfo.xml`, hicolor `…omnibridge.svg`, `/usr/share/doc/omnibridge/` | spec `%files`, debian `*.install` | MIGRATION_REQUIRED (handled by package replacement) |
| Package names | RPM `omnibridge`, `omnibridge-gui`; deb `omnibridge`, `omnibridge-gui` (source `omnibridge`) | spec, `packaging/debian/control` | MIGRATION_REQUIRED (§11.5) |
| Environment variables | `OMNIBRIDGE_UPLOAD_KEYSTORE[_PASSWORD]`, `OMNIBRIDGE_SIGNING_{KEY,FPR,SELFTEST_ROOT}`, `OMNIBRIDGE_MSRV`, `OMNIBRIDGE_SOAK[_SECS]`, `OMNIBRIDGE_HUMAN_DISMISS`, `OMNIBRIDGE_SCANNER_PY`, `OMNIBRIDGE_ASSERT_SH` | build, release, CI, harnesses | SAFE_RENAME for product (**none is read by the shipped binaries**); operator-facing ones (`UPLOAD_KEYSTORE`, `SIGNING_*`) need the custody runbook updated in the same change |
| Registry keys | none (no Windows product build) | — | — |

---

## 5. Protocol Identifier Inventory *(category D)*


Every value below is pinned as a literal on **both** sides —
`desktop/core/tests/wire_identity.rs` and
`android/app/src/test/…/WireIdentityTest.kt` — and ADR-0018 records it.

| Identifier | Current value | Desktop | Android | On the wire? | Risk |
|---|---|---|---|---|---|
| Control ALPN | `omnibridge/1` | `core/src/lib.rs:44` | `net/PinnedTrustManager.kt:123` | yes — TLS ClientHello/ServerHello | **COMPATIBILITY_SENSITIVE** |
| Data-stream ALPN | `omnibridge-data/1` | `core/src/lib.rs:56` | `PinnedTrustManager.kt:134` | yes | COMPATIBILITY_SENSITIVE |
| mDNS / NSD service type | `_omnibridge._tcp.local.` / `_omnibridge._tcp.` | `core/src/lib.rs:59` | `net/Discovery.kt:162-163` | yes — multicast DNS | COMPATIBILITY_SENSITIVE |
| QR payload scheme | `omnibridge1` (payload `omnibridge1:…`) | `core/src/qr.rs:31` | `pairing/QrPayload.kt:29` | yes — optical, one-shot | COMPATIBILITY_SENSITIVE (only matters during a pairing) |
| Pairing proof domain | `omnibridge/pairing-proof/v1` | `core/src/pairing.rs:52` | `pairing/PairingProof.kt:29` | inside HMAC input | COMPATIBILITY_SENSITIVE (only during pairing) |
| Pairing confirm domain | `omnibridge/pairing-confirm/v1` | `core/src/pairing.rs:53` | `PairingProof.kt:31` | inside HMAC input | COMPATIBILITY_SENSITIVE (only during pairing) |
| `files.v1` data-stream auth domain | `omnibridge/files.v1/data-stream/v1` | `capabilities/files/src/auth.rs:63` | `files/StreamAuth.kt:38` | inside HMAC input, every transfer | COMPATIBILITY_SENSITIVE |
| `notifications.v1` id / group / content domains | `omnibridge/notifications.v1/{id,group,content}/v1` | **not in product code** — desktop treats ids as opaque; pinned in `core/tests/notifications_protocol.rs:977-979` | `notifications/NotificationIdentity.kt:41-47` | the *outputs* are; the domains are Android-local | SAFE_RENAME at an app update (ids change once; nothing is persisted — "keeps no history") |
| Protobuf packages | `omnibridge.v1`, `omnibridge.v1.capabilities` (6 `.proto` files under `protocol/proto/omnibridge/v1/`) | `desktop/proto/build.rs`, `src/lib.rs` | via `java_package` | **no.** No `google.protobuf.Any`, no type URLs, no descriptor exchange (`git grep` for `Any`/`type_url` finds nothing). Binary protobuf carries field numbers only | SAFE_RENAME on the wire; COMPATIBILITY_SENSITIVE only as a *source* contract pinned by `desktop/proto/tests/namespace.rs` |
| Protobuf `java_package` | `io.github.yurisismotto.omnibridge.proto[.capabilities]` | — | generated classes | no | SAFE_RENAME |
| Capability IDs | `battery.v1`, `clipboard.v1`, `files.v1`, `notifications.v1` | `capabilities/*/src/lib.rs` | `capability/*.kt` | yes | **unbranded — no action** |
| TCP port | `55432` | — | — | yes | unbranded — no action (ADR-0018 kept it deliberately) |
| TLS SNI used by test client | `omnibridge.invalid` | `daemon/examples/fake_phone.rs` | — | example only | SAFE_RENAME |
| IPC / control socket name | `control.sock` inside the branded runtime dir | §4.2 | — | local | MIGRATION_REQUIRED (via the dir) |
| URI schemes / deep links | **none registered** (no `<data android:scheme>` in the manifest) | — | — | — | — |

---

## 6. Security/Identity Inventory *(category E)*

| Item | Current | Location | Persisted? | Risk | Why |
|---|---|---|---|---|---|
| Android device identity key | ECDSA P-256, non-exportable, Keystore alias `omnibridge-identity-v1` | `identity/DeviceIdentity.kt:74` | yes, Keystore of the `applicationId` | **DO_NOT_RENAME_WITHOUT_DECISION** | Renaming the alias under the same `applicationId` = the app no longer finds its key = new identity = every pairing silently broken. The alias is **invisible to users**; renaming it buys nothing. |
| Android notification HMAC secret | alias `omnibridge-notification-secret-v1` | `notifications/NotificationSecret.kt:152` | yes | DO_NOT_RENAME_WITHOUT_DECISION | Same mechanism; loss only reshuffles notification ids (cheap), but there is no gain either. |
| TLS KeyManager alias | `omnibridge-identity` | `net/PinnedTrustManager.kt:84` | **no** — in-memory `X509KeyManager` return value | SAFE_RENAME | Never stored. |
| Certificate subject CN (new identities) | `omnibridge:<device-id>` | `desktop/core/src/identity.rs:143`, Android `DeviceIdentity.kt` | in each identity's self-signed cert | SAFE_RENAME for **new** identities only | Trust is SPKI-pinned; the CN "is incidental and is never parsed" (remainder audit §5). Existing certificates keep their CN until an identity reset — do not regenerate identities to change it. |
| SPKI pins | SHA-256 over SPKI, stored in `state.json` (desktop) / `trust-store.json` (Android) | store code | yes | **no brand inside** | Pins are over key bytes; unaffected by any rename **as long as the key files are carried over** (§9.2 C3). |
| Desktop identity file | `identity.key` (`0600`) in `~/.local/share/omnibridge/` | `core/src/platform/unix_fs.rs` | yes | MIGRATION_REQUIRED | The file is unbranded; its **directory** is branded. |
| Desktop secret store | file-backed seam, no keyring / Secret Service entry | `core/src/secret_store.rs` | — | none | No named keyring item exists to migrate. |
| Frozen cross-language vectors | `protocol/testdata/identity-{a,b}.der`, `CN=anyflow:cdf2f27e…` / `CN=anyflow:8408ff88…`; SPKI pinned as KATs in Rust and Kotlin | `protocol/testdata/` | committed | DO_NOT_RENAME_WITHOUT_DECISION | Remainder audit §5 kept them deliberately; regenerating churns four KATs across two languages for no behavioural gain. Pliwee inherits the same trade-off (D10). |
| HMAC known-answer vectors | domain-dependent KATs | `desktop/core/tests/pairing.rs`, `identity_and_store.rs`, `notifications_protocol.rs`; Android `PairingProofTest.kt`, `PairingRecoveryTest.kt`, `Fixtures.kt`; generator `desktop/core/examples/gen_test_vectors.rs` | committed | COMPATIBILITY_SENSITIVE | Any domain rename requires independent recomputation, as ADR-0018 did — not copying implementation output. |
| **Android app-signing certificate** | `OU=Android App Signing, CN=OmniBridge`; SHA-256 `AB:B6:2F:53:…:AC:49`; alias `omnibridge-app-signing` | `android/signing/certs/app-signing-certificate.pem`, `provision-signing-keys.sh:43-45` | offline custody; **not yet enrolled in Play** | **DO_NOT_RENAME_WITHOUT_DECISION** (D3) | Once enrolled via PEPK it is the app's signing identity **forever**. The CN is cosmetic, but today is the only day it can be changed for free. Grep-invisible (base64). |
| **Android upload certificate** | `OU=Android Upload, CN=OmniBridge`; SHA-256 `75:FC:88:B5:…:BA:47`; alias `omnibridge-upload` | `android/signing/certs/upload-certificate.pem`, `app/build.gradle.kts:70`, `build-release-bundle.sh:89` | offline custody | DO_NOT_RENAME_WITHOUT_DECISION (D3) | Resettable via Play later, but keeping it and the app-signing key consistent is simplest if done together. |
| **Release OpenPGP key** | UID `OmniBridge Release Signing Key`, primary `F545DC184E909192C3FB6F6E64963019E731BE07`, signing subkey `E8EDE470…FD134` | `packaging/release/sign-release.sh`, README "Verifying a release download", `docs/certification/release/*` | public; the **trust anchor of v1.0.0** | **DO_NOT_RENAME_WITHOUT_DECISION** (D6) | The fingerprint, not the UID, is the anchor. Add a Pliwee UID to the same key (fingerprint unchanged) rather than minting a new key. |
| Device IDs | random hex, unbranded | identity code | yes | none | — |
| Fingerprints shown to users | derived from SPKI | — | — | none | Unchanged as long as keys are carried over. |

---

## 7. Build/CI/Distribution Inventory *(category F)*

### 7.1 GitHub repository references

`origin` is `https://github.com/yurisismotto/OmniBridge.git`. The repository
was recreated on 2026-09-24; earlier history lives in
`yurisismotto/omnibridge-history` (README.md:695-698, `docs/README.md`:101).
Two spellings are in use — `OmniBridge` and `omnibridge` — and GitHub resolves
both, case-insensitively.

| File | Reference | Kind | Risk |
|---|---|---|---|
| `README.md` | badge `img.shields.io/github/v/release/yurisismotto/OmniBridge`, releases links, 8 `curl` download URLs pinned to `v1.0.0`, pubkey URL (×2), history link, "GitHub" link | live | SAFE_RENAME — but the **v1.0.0 download URLs must keep resolving** (§13) |
| `android/app/src/main/java/…/ui/PrivacyPolicy.kt:16` | `https://github.com/yurisismotto/OmniBridge/blob/main/docs/policy/PRIVACY-POLICY.md` — **compiled into the APK** and declared to Play | live, compiled | **MIGRATION_REQUIRED** — must resolve for the life of every installed build |
| `android/app/src/test/…/PrivacyPolicyTest.kt:28` | same literal | test | SAFE_RENAME with it |
| `docs/design/PLAY-STORE-LISTING.md:32,65,93,94` | website + privacy URL for Play Console | live | SAFE_RENAME (Play Console fields are edited separately) |
| `docs/policy/PRIVACY-POLICY.md:28-29` | repo + issues URLs | live | SAFE_RENAME |
| `desktop/Cargo.toml:46` | `repository = …/omnibridge` | metadata | SAFE_RENAME |
| `desktop/gui/data/…metainfo.xml:66-67` | homepage + bugtracker | metadata, installed | SAFE_RENAME |
| `packaging/common/omnibridged.service:3` | `Documentation=` | installed | SAFE_RENAME |
| `packaging/fedora/omnibridge.spec:19` | `URL:` | metadata | SAFE_RENAME |
| `packaging/debian/control:39-41` | `Homepage`, `Vcs-Browser`, `Vcs-Git` | metadata | SAFE_RENAME |
| `packaging/debian/copyright:4` | `Source:` | metadata | SAFE_RENAME |
| `docs/adr/ADR-0011`, `ADR-0018`; `docs/research/platform-expansion/{21,25,28,README}` | `github.com/yurisismotto/anyflow/...` including CI run links | historical | **do not edit** (AGENTS.md "Historical documents are evidence") |
| 19 files under `docs/certification/`, `docs/reports/`, `docs/audits/` | old run links, old URLs | historical | **do not edit** |

**Not present in the repository:** issue templates, `CONTRIBUTING.md`,
`SECURITY.md`, `CODE_OF_CONDUCT.md`, `.github/FUNDING.yml`, `CODEOWNERS`,
Dependabot/Renovate config, a container image, a Flatpak manifest. There is
nothing to migrate for them; if they are adopted, adopt them under the new
name.

### 7.2 Workflows (`.github/workflows/`, 7 files)

| Workflow file | `name:` | Brand content | Risk |
|---|---|---|---|
| `android-ci.yml` | `Android · build + unit tests` | brand in comments / paths | SAFE_RENAME |
| `desktop-quality.yml` | `Desktop quality · fmt + clippy` | crate names in comments | SAFE_RENAME |
| `linux-distro-compat.yml` | `Linux distro compatibility · build only` | brand in comments / paths | SAFE_RENAME |
| `packaging-checks.yml` | `Packaging · checks` | `/usr/bin/omnibridged`, `packaging/common/omnibridged.service` | SAFE_RENAME with the files |
| `portable-windows-msvc.yml` | `Portable core · Windows MSVC` | 7 crate names, `-p omnibridge-*`, a `-like 'omnibridge-*'` filter | SAFE_RENAME — **the filter must be renamed with the crates or the boundary check silently checks nothing** (AGENTS.md "the tool exists / capture non-empty") |
| `release-artifacts.yml` | `Release · Linux artifacts` | artifact filename patterns `omnibridge-<V>…`, spec path | SAFE_RENAME (new names from the first Pliwee release) |
| `security-audit.yml` | `Security · dependency advisories` | comments | SAFE_RENAME |

Workflow `name:` values are unbranded, so **required status-check names in
branch protection do not change** with a rename — a useful property to keep.

### 7.3 Release scripts and artifacts

| Item | Current | Risk |
|---|---|---|
| Artifact names | `omnibridge-<V>.tar.gz`, `-vendor.tar.xz`, `.src.rpm`, `…fc44.x86_64.rpm`, `omnibridge-gui-…rpm`, `{ubuntu2404,ubuntu2604,debian13}-omnibridge[-gui]_<V>_amd64.deb`, `omnibridge-<V>-linux-x86_64.tar.gz`, SBOMs `omnibridge-<V>-<bin>_bin.cdx.json`, `omnibridge-release-pubkey.asc` | SAFE_RENAME **for future releases only**; v1.0.0 assets are immutable evidence |
| `packaging/release/make-source-bundle.sh` | `PREFIX="omnibridge-$V"`, file list incl. `…omnibridge.desktop/.service.in/.metainfo.xml`, `omnibridge-app-icon.svg` | SAFE_RENAME with the files |
| `packaging/release/sign-release.sh`, `verify-release.sh` | key UID in prose, `$WORK/omnibridge-release.gpg` | DO_NOT_RENAME_WITHOUT_DECISION — coupled to D6 |
| `android/signing/*.sh` | aliases `omnibridge-app-signing`, `omnibridge-upload`, DNAMEs `CN=OmniBridge` | DO_NOT_RENAME_WITHOUT_DECISION — coupled to D3 |
| `packaging/debian/changelog` | `omnibridge (1.0.0-1) …` entries | append-only; a rename adds a new entry under the new source name |
| `packaging/fedora/omnibridge.spec` `%changelog` | historic entries | append-only |
| Harness scratch names | `omnibridge-rpm-buildroot`, `/root/omnibridge-pkgs` | SAFE_RENAME (ephemeral) |
| MSRV variable | `OMNIBRIDGE_MSRV` | SAFE_RENAME |

---

## 8. Asset Inventory

### 8.1 Brand artwork — must be regenerated from the official Pliwee source

| Asset | Path | Consumers | Carries the name |
|---|---|---|---|
| Mark (canonical) | `docs/design/assets/omnibridge-mark.svg` | GResource; `widgets.rs:413`; Android `logo_omnibridge_mark.xml`; **tests assert every derivative has its outline byte-for-byte** (`desktop/gui/tests/brand_assets.rs`, `BrandingResourcesTest.kt`) | filename, `<title>`/ids |
| Mark, mono | `omnibridge-mark-mono.svg` | GResource | filename |
| App icon | `omnibridge-app-icon.svg` | `desktop/gui/build.rs` derives the hicolor `io.github.yurisismotto.omnibridge.svg`; source bundle | filename |
| Android monochrome | `omnibridge-android-monochrome.svg` | source of `ic_launcher_monochrome.xml` | filename |
| Wordmark | `omnibridge-wordmark.svg` | docs, README | **renders "OmniBridge"** |
| Lockup | `omnibridge-logo-lockup.svg` | docs, README | **renders "OmniBridge" + tagline** |
| Android brand drawable | `android/app/src/main/res/drawable/logo_omnibridge_mark.xml` | in-app brand mark | filename + path data |
| Android adaptive foreground | `res/drawable/ic_launcher_foreground.xml` | `mipmap-anydpi-v26/ic_launcher{,_round}.xml` | path data (no name — grep-invisible) |
| Android themed/monochrome | `res/drawable/ic_launcher_monochrome.xml` | adaptive icon `<monochrome>` | path data |
| Android launcher background | `@color/omnibridge_background` | adaptive `<background>` | colour name |
| Android decorative | `res/drawable/ribbon_connection.xml` (`OmniBridgeRibbonFlourish`) | UI | path data; decide keep/replace with the new identity |
| Play icon | `docs/design/assets/play/play-icon-512.png` | Play Console | pixels (grep-invisible) |
| Play feature graphic | `play/play-feature-graphic-1024x500.png` | Play Console | **pixels render "OmniBridge" + "One bridge. Any device."** (inspected) |
| Play screenshots | `play/screenshots/tablet/01…06-*.png` (6) | Play Console | app UI showing the product name/mark in pixels |
| Desktop hicolor icon | generated at build time as `io.github.yurisismotto.omnibridge.svg` | spec/deb install | derived — rebuilds automatically |

**No splash screen resource exists** (no `windowSplashScreen*`, no splash
drawable), no raster launcher mipmaps (adaptive only), no separate tray icon
file (the tray uses the app icon by name), and **no screenshots in AppStream**
(`metainfo.xml` says so explicitly). README carries a release badge but no
embedded images.

### 8.2 Brand-neutral — no regeneration

`docs/design/assets/icons/*.svg` (28 glyphs) and their Android
`res/drawable/ic_*.xml` counterparts are functional glyphs with no brand
content. `docs/design/tokens.json` holds colours; whether Pliwee keeps the
palette is a design decision (D8), not a rename.

### 8.3 To regenerate when the official Pliwee logo exists

1. Mark, mono mark, app icon, Android monochrome source → `docs/design/assets/pliwee-*.svg`.
2. Wordmark and lockup (+ new tagline, D8).
3. Android: `logo_*_mark.xml`, `ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`, launcher background colour; decide on `ribbon_connection.xml`.
4. Play: 512 px icon, 1024×500 feature graphic, all six tablet screenshots (and phone screenshots if added) — **after** the UI strings change, so the screenshots show the new name.
5. Desktop hicolor icon — automatic via `build.rs` once the source is swapped.
6. Update the byte-for-byte outline assertions in `brand_assets.rs` and `BrandingResourcesTest.kt` to the new mark, and extend their "dead identity" lists with `omnibridge`.

---

## 9. Compatibility Risks

### 9.1 Who is actually installed

| Population | Evidence | Size |
|---|---|---|
| Linux v1.0.0 from GitHub Releases | `gh api …/releases/tags/v1.0.0`: `omnibridge-1.0.0-1.fc44.x86_64.rpm` 5, `omnibridge-gui…rpm` 5, each `.deb` 3, tarball 3, `SHA256SUMS.asc` 2 downloads | tiny, non-zero, unknowable |
| Linux built from source | any checkout | unknown |
| Android | no Play app, no APK asset; only certification hardware | effectively the maintainer |
| AnyFlow-era installs | ADR-0018 already broke them; left untouched | out of scope |

### 9.2 Item-by-item

| # | Item | Would a plain rename break existing installs / pairings? | Compatible strategy |
|---|---|---|---|
| C1 | **Android `applicationId`** | **Yes, totally.** New id = new app: separate storage, Keystore, grants; the old app keeps running beside it. After Play enrolment it can never change for that listing. Today no user has it. | Decide **before PLAY18 / 2026-09-30** (D1). If it changes, change it now and accept a re-pair on test devices. If kept, it stays `…omnibridge` forever — invisible to users except in Play URLs and Settings → Apps → details. |
| C2 | **Device IDs** | No — unbranded random hex. | none |
| C3 | **Identity keys** | **Yes** if the Keystore alias is renamed without the `applicationId`, or if `~/.local/share/omnibridge/identity.key` is not carried over. Either yields a new fingerprint and every peer rejects it. | Android: keep the alias literally (`omnibridge-identity-v1`) — or, if the `applicationId` changes, use a fresh `pliwee-identity-v1` (new keystore anyway, as ADR-0018 did). Desktop: one-shot directory migration (§11.1). |
| C4 | **Certificates** | No, if keys are carried: CN is never parsed. | Only new identities get `CN=pliwee:<id>`. |
| C5 | **SPKI pins** | No — computed over key bytes, stored in unbranded files. At risk only indirectly via 5.3/5.7. | Carry the files. |
| C6 | **Pairing database** (`state.json` / `trust-store.json`) | Desktop: **yes** — it lives in the branded data dir. Android: only via 5.1. | §11.1. |
| C7 | **Secret-store entries** | Android notification secret: loss is harmless (ids reshuffle once; nothing persisted). Desktop: no keyring entries. | Keep the alias with the `applicationId`. |
| C8 | **Config paths** | `~/.config/omnibridge/gui.json`: loses the GUI's selected peer; cosmetic. | Migrate with 5.6, or accept. |
| C9 | **Socket / service names** | Runtime socket: only if daemon and clients disagree — shipped together, so no. systemd: **yes** — the user's enablement of `omnibridged.service` does not follow a renamed unit; after upgrade nothing starts at login. firewalld: **yes** — zones referencing `omnibridge` fail to reload if that file disappears. D-Bus name / app id: pinned taskbar launchers, GNOME/KDE notification settings and dock favourites are keyed by it and are lost. | §11.3–§11.5: ship the old unit as a transitional alias, keep the old firewalld file for a deprecation window, accept (and document) the launcher/app-id reset. |
| C10 | **Discovery identifiers** (mDNS) | **Yes** — a renamed daemon becomes invisible to an old app and vice versa. Today: no public Android, so no deployed pair. | Rename now while free (D4), or keep `_omnibridge._tcp` permanently. Dual advertisement (§11.6) only if a Play build ships first. |
| C11 | **ALPN / QR / pairing & data domains** | **Yes** — handshake failure (ALPN), unparseable QR, proof that verifies nowhere, refused data stream. The failure is loud and immediate by design. | Same as 5.10 — they must move together. Pairing domains + QR only matter at pairing time, so an existing pair survives their change **if** ALPN and data domain stay compatible. |
| C12 | **Protobuf package** | **No** — not on the wire. Source-level only. | SAFE_RENAME at any time. |
| C13 | **Notification IDs** | Android-generated HMACs; a domain change re-keys ids once. Desktop keeps no history; a mirrored notification visible during the upgrade may fail to dismiss once. | SAFE_RENAME at an app update. |
| C14 | **File-transfer state** | No persisted history on either side ("keeps no transfer history on disk"). In-flight transfers die with the process anyway. Leftover `.omnibridge-<id>.part` files in `~/Downloads/OmniBridge` would be orphaned. | Accept; optionally sweep the old prefix once. |
| C15 | **Download folders** | Existing received files stay in `Download/OmniBridge` / `~/Downloads/OmniBridge`; new ones would land elsewhere. No breakage, only a user surprise. | Policy decision (D9): keep writing to the old folder, or write to `Pliwee` and never move user files (ADR-0018 precedent). |
| C16 | **Default device name** | Peers store the advertised name; renaming the default only affects new identities. | None needed. |
| C17 | **Privacy-policy URL in the APK** | **Yes** if the path or repo changes and nothing redirects — Play policy requires the URL to resolve. | Keep the file at the same path, or leave a redirecting stub; see §13. |
| C18 | **Android component names** (listener, tile, launcher activity) | Renaming the Kotlin package (even with the same `applicationId`) changes their `ComponentName`s: **the notification-access grant is lost**, the QS tile disappears, pinned launcher shortcuts break. | Keep the manifest `android:name` values stable (move code but keep the FQN via a thin subclass), or use `activity-alias` for the launcher; or accept a re-grant while there are no users. |
| C19 | **Release signing key** | A new key would orphan everyone who pinned `F545DC18…` from the README. | Add a Pliwee UID to the existing key (D6). |

---

## 10. Proposed Canonical Pliwee Naming

**Proposals, not decisions.** Lowercase `pliwee` for machine identifiers,
`Pliwee` for display. The name is 6 ASCII letters: it fits an mDNS service
label (≤ 15), a D-Bus element, a Kotlin package segment and a Debian package
name without escaping.

| Thing | Current | Candidate | Note |
|---|---|---|---|
| Product | OmniBridge | **Pliwee** | |
| Tagline | One bridge. Any device. | *(D8)* | |
| Workspace dir | `desktop/` | `desktop/` | unbranded — keep |
| Rust crates | `omnibridge-{core,proto,control,runtime,daemon,cli,gui,linux}`, `omnibridge-capability-*` | `pliwee-{…}`, `pliwee-capability-*` | |
| CLI binary | `omnibridge` | `pliwee` | |
| Daemon binary | `omnibridged` | `pliweed` | |
| GUI binary | `omnibridge-gui` | `pliwee-gui` | |
| systemd user unit | `omnibridged.service` | `pliweed.service` (+ `Alias=omnibridged.service`, §11.3) | |
| RPM / deb packages | `omnibridge`, `omnibridge-gui` | `pliwee`, `pliwee-gui` | with `Obsoletes`/`Provides` and `Replaces`/`Breaks` |
| firewalld service | `omnibridge` | `pliwee` (keep `omnibridge.xml` for one release) | |
| Desktop app id / D-Bus name / icon | `io.github.yurisismotto.omnibridge` | `io.github.yurisismotto.pliwee` *(or a Pliwee-owned reverse-DNS, D2)* | |
| D-Bus object path | `/io/github/yurisismotto/omnibridge` | `/io/github/yurisismotto/pliwee` | follows the id |
| Data dir | `~/.local/share/omnibridge` | `~/.local/share/pliwee` | migrated, §11.1 |
| Config dir | `~/.config/omnibridge` | `~/.config/pliwee` | migrated |
| Runtime dir / socket | `$XDG_RUNTIME_DIR/omnibridge/control.sock`, `/tmp/omnibridge-<uid>` | `$XDG_RUNTIME_DIR/pliwee/control.sock`, `/tmp/pliwee-<uid>` | |
| Cache / log dirs | none | none | |
| Download folder | `Download/OmniBridge`, `~/Downloads/OmniBridge` | `Pliwee` *(D9)* | |
| Android app | OmniBridge | Pliwee | |
| Android `applicationId` | `io.github.yurisismotto.omnibridge` | **D1**: `io.github.yurisismotto.pliwee` *or* a Pliwee-owned domain *or* keep | |
| Android `namespace` / Kotlin package | `io.github.yurisismotto.omnibridge` | same root as chosen for D1 | components: §9.2 C18 |
| Gradle root project | `OmniBridge` | `Pliwee` | modules `:app`, `:fixture` unchanged |
| Fixture `applicationId` | `…omnibridge.fixture` | `….pliwee.fixture` | |
| Keystore aliases | `omnibridge-identity-v1`, `omnibridge-notification-secret-v1` | keep if D1 = keep; `pliwee-identity-v1`, `pliwee-notification-secret-v1` if the `applicationId` changes | |
| Android signing aliases / DN | `omnibridge-app-signing`, `omnibridge-upload`, `CN=OmniBridge` | `pliwee-app-signing`, `pliwee-upload`, `CN=Pliwee` *(D3)* | |
| Protobuf package | `omnibridge.v1[.capabilities]`, dir `protocol/proto/omnibridge/v1/` | `pliwee.v1[.capabilities]`, `protocol/proto/pliwee/v1/` | wire-neutral |
| `java_package` | `io.github.yurisismotto.omnibridge.proto` | `<D1 root>.proto` | |
| Control ALPN | `omnibridge/1` | `pliwee/1` *(D4)* | |
| Data ALPN | `omnibridge-data/1` | `pliwee-data/1` *(D4)* | |
| mDNS | `_omnibridge._tcp.local.` | `_pliwee._tcp.local.` *(D4)* | |
| QR scheme | `omnibridge1` | `pliwee1` *(D4)* | |
| Domain separators (×6) | `omnibridge/…` | `pliwee/…` *(D4)* | KATs recomputed independently |
| Cert CN | `omnibridge:<id>` | `pliwee:<id>` (new identities only) | |
| Env vars | `OMNIBRIDGE_*` | `PLIWEE_*` | |
| X11 atom | `_OMNIBRIDGE_CLIPBOARD_WATCH_STOP` | `_PLIWEE_CLIPBOARD_WATCH_STOP` | |
| Release key UID | `OmniBridge Release Signing Key` | add `Pliwee Release Signing Key` to the same key *(D6)* | |
| Artifacts | `omnibridge-<V>…` | `pliwee-<V>…` from the first Pliwee release | |
| GitHub repo | `yurisismotto/OmniBridge` | `yurisismotto/pliwee` (or an org, D5) | |

**Recommendation on D4 (wire identifiers).** Rename them in the same change
that renames the `applicationId`, *before* any Android build is public. The
cost today is one re-pair on test hardware plus a coordinated Linux 2.0 (a
v1.0.0 Linux install cannot pair with a Pliwee phone). The cost after Play
launch is permanent dual-stack code in two languages. If the maintainer
prefers zero wire churn, the defensible alternative is to **freeze every wire
identifier at its `omnibridge` value forever** and say so in an ADR — the
option ADR-0011 rejected ("a permanent, inexplicable artefact in a
security-relevant constant"). What should not happen is a half-rename (e.g.
new mDNS, old ALPN), which yields a peer that is discovered and then fails.

---

## 11. Required Migration Mechanisms

None of these exist today. ADR-0018 deliberately built none ("no migration
subsystem"); with a public v1.0.0 that choice needs revisiting.

1. **Desktop state migration (required for Linux v1.0.0 users).** On daemon
   start: if `$XDG_DATA_HOME/pliwee` is absent and `…/omnibridge` holds a
   readable `identity.key` + `state.json`, copy (not move) both into the new
   directory with `0700`/`0600`, fsync, then write a marker. Never overwrite a
   populated `pliwee` dir; never delete the old one. Must honour the existing
   "absent vs unreadable" contract in `core/src/secret_store.rs` — an
   unreadable old dir is an error, not "first run", or the migration becomes
   the identity-destroying bug that seam was built to prevent. Same for
   `~/.config/omnibridge/gui.json`. A gate must assert the fingerprint before
   and after is **identical** (AGENTS.md: two observations, the change asserted).
2. **Android identity continuity.** Only needed if D1 keeps the
   `applicationId`: keep the Keystore alias strings unchanged. If D1 changes
   the `applicationId`, no migration is possible (non-exportable key in
   another app's keystore) — which is acceptable only because there are no
   Android users yet.
3. **systemd unit continuity.** Ship `pliweed.service` with
   `Alias=omnibridged.service` is *not* enough on its own (aliases only apply
   on `enable`). Needed: a package scriptlet cannot touch per-user enablement,
   so either (a) keep installing `omnibridged.service` for one release as a
   thin unit that `Requires=`/starts `pliweed.service`, or (b) have the daemon
   detect and report the stale enablement, plus release notes with the one
   `systemctl --user` command. Measure it on all four distributions with the
   existing `lifecycle-gates.sh`.
4. **firewalld.** Ship `pliwee.xml`; keep shipping `omnibridge.xml` (identical
   port) for at least one release so a zone that references it still reloads.
5. **Package replacement.** RPM: `Obsoletes: omnibridge < 2.0` + `Provides:
   omnibridge = %{version}` (and for `-gui`). Debian: `Replaces:`/`Breaks:
   omnibridge (<< 2.0)` + `Provides:`, optionally a transitional
   `omnibridge` package depending on `pliwee`. Verify with `install-smoke.sh`
   upgrading a real v1.0.0 install.
6. **Wire dual-stack — only if an Android build is public before D4 lands.**
   Listener offers both ALPNs and selects by the negotiated one; daemon
   advertises both mDNS types; app browses both; QR parser accepts both
   prefixes; domain separator chosen by the negotiated ALPN. Pinned by both
   `wire_identity` tests. Not needed if D4 is executed before Play.
7. **Android component stability** (if the Kotlin package moves but the
   `applicationId` does not): keep manifest `android:name`s at their old FQNs
   via thin subclasses, `activity-alias` for the launcher.
8. **Old-name absence tests.** Extend the dead-name lists in
   `wire_identity.rs`, `WireIdentityTest.kt`, `namespace.rs`,
   `brand_assets.rs`, `BrandingResourcesTest.kt` and `DeviceIdentityTest.kt`
   with `omnibridge` — each for exactly the identifiers that D-decisions
   actually renamed, so a kept identifier is not asserted absent.
9. **Privacy-policy URL continuity** (§13).

---

## 12. Recommended Rebrand Order

Each step is its own reviewable commit with its gates green; nothing merges
half-renamed. Steps 1–3 are blocked on decisions, not code.

1. **ADR-0020 "Rename to Pliwee"** recording D1–D10, superseding ADR-0018's
   identifier tables the way ADR-0018 superseded ADR-0011.
2. **Android identity (time-critical, before PLAY18 / 2026-09-30):** execute D1
   (`applicationId`, `namespace`, Kotlin package, components), D3 (regenerate
   signing keys + DN if chosen, re-run `provision-signing-keys.sh`, update the
   committed certs and `verify-release-bundle.sh` expectations). Nothing
   uploaded until this is done.
3. **Wire + crypto identifiers (D4)** — both languages in one commit, KATs
   recomputed independently, both `wire_identity` tests updated. Protobuf
   package/dir rename can ride along (wire-neutral).
4. **Desktop persistence + migration** (§11.1) with a fingerprint-continuity
   gate on a real v1.0.0 state directory.
5. **Desktop app id / D-Bus / .desktop / metainfo / GResource / tray**, then
   `desktop/platform-linux/tests/tray_identity.rs` and `dbus_activation.rs`.
6. **Crates, binaries, CLI/daemon strings** — `cargo` rename, `Cargo.lock`,
   CI `-p` lists (including the `-like 'omnibridge-*'` filter).
7. **Packaging:** spec, debian, systemd unit + transition (§11.3), firewalld
   (§11.4), `Obsoletes/Replaces` (§11.5), harnesses; run the lifecycle and
   peer gates on all four distributions, including an **upgrade from the real
   v1.0.0 packages**.
8. **UI strings** (Android `strings.xml`, desktop GUI, tray) and Compose/Kotlin
   `OmniBridge*` symbols.
9. **Artwork** when the official logo exists (§8.3), then Play screenshots.
10. **Live docs:** README, AGENTS.md, `docs/README.md`, `BRAND.md`,
    `UI-GUIDELINES.md`, `PLAY-STORE-LISTING.md`, `PRIVACY-POLICY.md`,
    architecture docs, `android/README.md`, `packaging/*/README.md`. A new
    `docs/migrations/MIGRATION-OMNIBRIDGE-TO-PLIWEE.md` for users.
11. **Remainder audit** (`PLIWEE-REBRAND-REMAINDER-AUDIT.md`) classifying every
    surviving `omnibridge`, with `LC_ALL=C grep -a` (§1).
12. **Certification** of the Pliwee build on the existing gates, then release.

Historical documents are **never** part of any step (§14 D7).

---

## 13. Recommended Repository Migration Order

Performed **after** step 12, per the brief.

1. Freeze `main` on the certified Pliwee commit; tag it.
2. Decide D5 (rename in place vs new repository). **Renaming
   `yurisismotto/OmniBridge` in place** keeps issues, releases, stars and makes
   GitHub redirect every old URL — including the eight v1.0.0 download URLs in
   the README and the **privacy-policy URL compiled into any installed APK**.
   Creating a *new* repository gives no redirects, and if a repo named
   `OmniBridge` is ever re-created under the same owner the redirects vanish.
   If a new repo is chosen anyway, keep `yurisismotto/OmniBridge` alive and
   archived, with `docs/policy/PRIVACY-POLICY.md` and the v1.0.0 release left
   in place.
3. Move the privacy policy to a stable, repo-independent URL (GitHub Pages or a
   Pliwee domain) **before** the first Play upload, so the compiled-in URL
   never depends on a repository name again.
4. Update live URLs in one commit: `README.md` badge/links,
   `PrivacyPolicy.kt` + test, `Cargo.toml`, `metainfo.xml`, unit
   `Documentation=`, spec `URL:`, debian `Homepage/Vcs-*`/`copyright`,
   `PLAY-STORE-LISTING.md`, `PRIVACY-POLICY.md`.
5. Re-point `origin`, re-run all seven workflows on the new location; confirm
   `release-artifacts.yml` provenance (SLSA attestation names the repository —
   old attestations stay valid for old artifacts only).
6. Recreate branch protection/required checks (names are unbranded, §7.2).
7. Leave `yurisismotto/omnibridge-history` untouched; its links are evidence.
8. Publish the next release (Pliwee) signed by the **same** OpenPGP key with the
   added UID, and say so in the release notes.

---

## 14. Open Decisions

| # | Decision | Options | Deadline / why it matters |
|---|---|---|---|
| **D1** | Android `applicationId` | (a) `io.github.yurisismotto.pliwee`; (b) a Pliwee-owned reverse-DNS (needs the domain); (c) keep `io.github.yurisismotto.omnibridge` forever | **Before PLAY18 and before 2026-09-30 registration.** Irreversible afterwards. |
| **D2** | Reverse-DNS root for everything (desktop app id, D-Bus, Kotlin package) | same as D1; `io.github.<owner>` ties the id to a GitHub account name | Changing it after Flathub/distro packaging would repeat this migration. |
| **D3** | Android signing keys | (a) regenerate with `CN=Pliwee` before enrolment; (b) keep `CN=OmniBridge` (cosmetic, invisible to users) | Before PEPK enrolment. Free today, impossible later for the app-signing key. |
| **D4** | Wire / crypto identifiers | (a) rename now, clean break, before Android ships; (b) freeze at `omnibridge` permanently; (c) rename later with dual-stack | (a) is only cheap while no Android build is public. §10 recommends (a). |
| **D5** | Repository | rename in place (redirects) vs new repository (no redirects) vs GitHub organisation | Affects the compiled privacy URL and README download links. |
| **D6** | Release OpenPGP key | add a Pliwee UID to `F545DC18…` vs new key cross-signed by the old | New key breaks every user's pinned anchor. |
| **D7** | Historical documents | confirm AGENTS.md policy: never rewritten; superseding notes only | 118 files; also ADR-0011/0018 and the AnyFlow migration note. |
| **D8** | Tagline and palette | new tagline; keep or change `tokens.json` colours | Blocks lockup, feature graphic, `.desktop` `Comment=`. |
| **D9** | Download folders | keep writing to `OmniBridge`; switch to `Pliwee` and leave old files; switch and move (not recommended) | User-visible. |
| **D10** | Frozen `CN=anyflow` DER vectors | keep (remainder-audit precedent) vs regenerate + 4 KATs | Pure hygiene. |
| **D11** | Migration window | how many releases carry `omnibridged.service`/`omnibridge.xml`/`Obsoletes` and the state-dir migration | Needs a removal date in the ADR. |
| **D12** | Is Linux v1.0.0 → Pliwee an in-place upgrade (keep identity, pairings) or a documented clean install? | §11.1 vs ADR-0018-style break | With a public release, a silent identity loss would be a regression. |

---

## 15. Complete affected-file list

578 files. **Cat.** uses the brief's letters A–G plus **H = historical
evidence / decision record** (never rewritten; AGENTS.md). Counts are
case-insensitive occurrences from `LC_ALL=C grep -aoi`; `path` means the name
is only in the file's path. Category and risk were assigned by path, then
overridden by hand for the 59 files verified in §§2–7 to define a
persistent, protocol, security or distribution identifier. A file's risk is
the risk of its most sensitive identifier; most lines in a
`COMPATIBILITY_SENSITIVE` file are ordinary code.

Grep-invisible carriers not in this list (no ASCII match): the two PEM
certificates in `android/signing/certs/`, the eight PNGs in
`docs/design/assets/play/`, and `ic_launcher_foreground.xml` /
`ic_launcher_monochrome.xml` / `ribbon_connection.xml` (brand path data).
See §6 and §8.

| File | anyflow | omnibridge | Cat. | Risk |
|---|--:|--:|---|---|
| `AGENTS.md` | 1 | 1 | A | SAFE_RENAME |
| `android/app/build.gradle.kts` | 0 | 17 | C,E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/app/proguard-rules.pro` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/AppPickerUiTest.kt` | 0 | 14 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/ClipboardInstrumentedTest.kt` | 0 | 13 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/ClipboardPersistenceTest.kt` | 0 | 10 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/DeviceIdentityTest.kt` | 4 | 5 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/DownloadsTest.kt` | 0 | 7 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/HostDrivenCertificationHarness.kt` | 0 | 27 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationConsentUiTest.kt` | 0 | 12 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationHardwareGateTest.kt` | 0 | 29 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationLoggingCanaryTest.kt` | 0 | 26 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationSecretInstrumentedTest.kt` | 0 | 6 | G | SAFE_RENAME |
| `android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationUiFixtures.kt` | 0 | 12 | G | SAFE_RENAME |
| `android/app/src/main/AndroidManifest.xml` | 0 | 12 | B,C | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/BatteryCapability.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/Capability.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/ClipboardCapability.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/FilesCapability.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/NotificationsCapability.kt` | 0 | 6 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/capability/SensitiveCapabilities.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardCaches.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardDelivery.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardNotifications.kt` | 0 | 5 | B,C | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardPolicy.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardSync.kt` | 0 | 8 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardTarget.kt` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/ClipboardText.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/SystemClipboard.kt` | 0 | 7 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/DataStream.kt` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/Downloads.kt` | 0 | 4 | C | MIGRATION_REQUIRED |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/Filenames.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/FileTransferManager.kt` | 0 | 23 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/MimeTypes.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/OpenAction.kt` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/SharedFile.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/StreamAuth.kt` | 0 | 6 | D,E | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/files/TransferState.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/identity/DeviceIdentity.kt` | 6 | 8 | E | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/identity/Fingerprint.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/identity/IdentityReset.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/identity/KeyDigests.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/ConnectionCoordinator.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/ConnectionEvent.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/Discovery.kt` | 0 | 5 | D | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/Endpoints.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/FailureKind.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/Framing.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/PeerConnection.kt` | 0 | 16 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/PinnedTrustManager.kt` | 0 | 6 | D,E | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/net/Protocol.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/InstalledApps.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationApps.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationDismiss.kt` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationEcho.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationFilter.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationIdentity.kt` | 0 | 7 | D,E | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationLock.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationPolicy.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationQueue.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationReadiness.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationRoleState.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationSecret.kt` | 0 | 2 | E | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationSnapshot.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationSource.kt` | 0 | 11 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationText.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/NotificationWire.kt` | 0 | 7 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/notifications/OmniBridgeNotificationListener.kt` | 0 | 13 | B,C | MIGRATION_REQUIRED |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/OmniBridgeApp.kt` | 0 | 34 | B,C | MIGRATION_REQUIRED |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/pairing/PairingGate.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/pairing/PairingProof.kt` | 0 | 5 | D,E | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/pairing/QrPayload.kt` | 0 | 4 | D | COMPATIBILITY_SENSITIVE |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/service/ConnectionService.kt` | 0 | 27 | B,C | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/store/PeerTarget.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/store/TrustStore.kt` | 0 | 6 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/AppPickerScreen.kt` | 0 | 49 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/ClipboardShortcut.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/ClipboardTileService.kt` | 0 | 6 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/ClipboardViews.kt` | 0 | 38 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/components/Buttons.kt` | 0 | 50 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/components/Cards.kt` | 0 | 78 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/components/Exchange.kt` | 0 | 55 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/components/Indicators.kt` | 0 | 56 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/components/Surfaces.kt` | 0 | 45 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/DevicesScreen.kt` | 0 | 73 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/FilesMapping.kt` | 0 | 7 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/FilesScreen.kt` | 0 | 43 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/MainActivity.kt` | 0 | 38 | B,C | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/MainState.kt` | 0 | 19 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/Navigation.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/NotificationSettingsScreen.kt` | 0 | 93 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/NotificationUiMapping.kt` | 0 | 14 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/OmniBridgeShell.kt` | 0 | 29 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/PairingCaptureActivity.kt` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/PairingScanner.kt` | 0 | 10 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/PeerDetailScreen.kt` | 0 | 113 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/PrivacyPolicy.kt` | 0 | 3 | F | MIGRATION_REQUIRED |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/ScannerInsets.kt` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/SendActivity.kt` | 0 | 92 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/SendClipboardScreen.kt` | 0 | 48 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/SettingsScreen.kt` | 0 | 53 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Color.kt` | 0 | 7 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Dimens.kt` | 0 | 7 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Gradients.kt` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Motion.kt` | 0 | 4 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Status.kt` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Theme.kt` | 0 | 16 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/theme/Type.kt` | 0 | 20 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/TransferViews.kt` | 0 | 43 | A,B | SAFE_RENAME |
| `android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/UiMapping.kt` | 0 | 42 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_activity.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_add.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_arrow_back.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_battery.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_check.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_chevron_right.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_clipboard.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_close.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_device_desktop.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_device_generic.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_device_phone.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_device_tablet.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_download.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_files.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_file.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_home.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_launcher_monochrome.xml` | 0 | 2 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_link_off.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_link.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_more_vert.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_notifications.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_peers.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_qr.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_receive.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_search.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_send.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_settings.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_shield_check.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_shield_off.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_shield.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_trash.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/ic_warning.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/drawable/logo_omnibridge_mark.xml` | 0 | 1 | A,B | SAFE_RENAME |
| `android/app/src/main/res/values/colors.xml` | 0 | 3 | A,B | SAFE_RENAME |
| `android/app/src/main/res/values-night/themes.xml` | 0 | 5 | A,B | SAFE_RENAME |
| `android/app/src/main/res/values/strings.xml` | 0 | 21 | A,B | SAFE_RENAME |
| `android/app/src/main/res/values/themes.xml` | 0 | 6 | A,B | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/BatteryGrantTest.kt` | 0 | 6 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/BatteryReadingTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/BrandingResourcesTest.kt` | 1 | 13 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/CapabilityRegistryTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardCachesTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardPolicyTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardShortcutTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardSyncTest.kt` | 0 | 14 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardTextTest.kt` | 0 | 6 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ClipboardTruthfulnessTest.kt` | 0 | 20 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/DataStreamCopyTest.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/DesignTokensTest.kt` | 0 | 45 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/DevicesPresentationTest.kt` | 0 | 11 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/EndpointsTest.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ExchangeFlowTest.kt` | 1 | 17 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/FailureKindTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/FilenamesTest.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/FilesUxTest.kt` | 0 | 24 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/FingerprintTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/Fixtures.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/FramingTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/KeyDigestsTest.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/MultiPeerRoutingTest.kt` | 0 | 33 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationAppsTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationConvergenceTest.kt` | 0 | 18 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationDismissRulesTest.kt` | 0 | 11 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationFilterTest.kt` | 0 | 11 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationHardeningTest.kt` | 0 | 17 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationIdentityTest.kt` | 0 | 8 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationNavigationTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationPolicyStorageTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationQueueTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationReadinessTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationRolesTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationSecretTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationSourceTest.kt` | 0 | 25 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationsProtocolTest.kt` | 0 | 23 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/NotificationTextTest.kt` | 0 | 11 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PairingProofTest.kt` | 0 | 4 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PairingRecoveryTest.kt` | 0 | 32 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PairingScannerOrientationTest.kt` | 0 | 14 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PeerTargetTest.kt` | 0 | 13 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PinnedTrustManagerTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/PrivacyPolicyTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ProtocolTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/QrPayloadTest.kt` | 0 | 5 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ReconnectTest.kt` | 0 | 6 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/RevokedDeviceCleanupTest.kt` | 0 | 13 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/ScannerInsetsTest.kt` | 0 | 6 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/SendClipboardUiTest.kt` | 0 | 13 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/SendRetryTest.kt` | 0 | 13 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/StreamAuthTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/TransferStateTest.kt` | 0 | 3 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/TrustStoreTest.kt` | 0 | 2 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/UiMappingTest.kt` | 0 | 40 | G | SAFE_RENAME |
| `android/app/src/test/java/io/github/yurisismotto/omnibridge/WireIdentityTest.kt` | 1 | 21 | G | SAFE_RENAME |
| `android/fixture/build.gradle.kts` | 0 | 5 | C | SAFE_RENAME |
| `android/fixture/README.md` | 0 | 9 | A | SAFE_RENAME |
| `android/fixture/src/main/AndroidManifest.xml` | 0 | 3 | A,B | SAFE_RENAME |
| `android/fixture/src/main/java/io/github/yurisismotto/omnibridge/fixture/FixtureActivity.kt` | 0 | 14 | A,B | SAFE_RENAME |
| `android/fixture/src/main/res/values/strings.xml` | 0 | 2 | A,B | SAFE_RENAME |
| `android/README.md` | 0 | 1 | A | SAFE_RENAME |
| `android/settings.gradle.kts` | 0 | 2 | B,F | SAFE_RENAME |
| `android/signing/build-release-bundle.sh` | 0 | 14 | E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/signing/provision-signing-keys.sh` | 0 | 29 | E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `android/signing/tests/provision-selftest.sh` | 0 | 12 | G,F | SAFE_RENAME |
| `android/signing/verify-release-bundle.sh` | 0 | 3 | E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `desktop/capabilities/battery/Cargo.toml` | 0 | 4 | B,F | SAFE_RENAME |
| `desktop/capabilities/battery/src/lib.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/capabilities/battery/src/upower.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/capabilities/battery/tests/battery_presence.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/capabilities/battery/tests/real_upower.rs` | 0 | 2 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/Cargo.toml` | 0 | 5 | B,F | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/backend/mod.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/backend/wayland.rs` | 0 | 7 | A,B | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/backend/x11.rs` | 0 | 3 | D | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/lib.rs` | 0 | 10 | A,B | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/policy.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/capabilities/clipboard/src/text.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/common/mod.rs` | 0 | 8 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/logging.rs` | 0 | 2 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/loops.rs` | 0 | 5 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/real_backend.rs` | 0 | 11 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/security.rs` | 0 | 8 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/sensitive_capability.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/capabilities/clipboard/tests/truthfulness.rs` | 0 | 3 | G | SAFE_RENAME |
| `desktop/capabilities/files/Cargo.toml` | 0 | 4 | B,F | SAFE_RENAME |
| `desktop/capabilities/files/src/auth.rs` | 0 | 6 | D,E | COMPATIBILITY_SENSITIVE |
| `desktop/capabilities/files/src/destination.rs` | 0 | 6 | C | MIGRATION_REQUIRED |
| `desktop/capabilities/files/src/lib.rs` | 0 | 11 | A,B | SAFE_RENAME |
| `desktop/capabilities/files/src/limits.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/capabilities/files/src/sink.rs` | 0 | 2 | C | MIGRATION_REQUIRED |
| `desktop/capabilities/files/src/stream.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/capabilities/files/src/transfer.rs` | 0 | 2 | A,B | SAFE_RENAME |
| `desktop/capabilities/files/tests/filename_fuzz.rs` | 0 | 3 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/Cargo.toml` | 0 | 4 | B,F | SAFE_RENAME |
| `desktop/capabilities/notifications/src/backend/dbus.rs` | 0 | 5 | C | MIGRATION_REQUIRED |
| `desktop/capabilities/notifications/src/backend/mod.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/lib.rs` | 0 | 11 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/mirror.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/policy.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/queue.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/redact.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/roles.rs` | 0 | 2 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/src/text.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/common/mod.rs` | 0 | 7 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/convergence.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/dismiss.rs` | 0 | 7 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/hardening.rs` | 0 | 10 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/logging.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/real_dbus.rs` | 0 | 45 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/real_lock.rs` | 0 | 2 | G | SAFE_RENAME |
| `desktop/capabilities/notifications/tests/sink.rs` | 0 | 11 | G | SAFE_RENAME |
| `desktop/Cargo.lock` | 0 | 44 | B,F | SAFE_RENAME |
| `desktop/Cargo.toml` | 0 | 12 | B,F | SAFE_RENAME |
| `desktop/cli/Cargo.toml` | 0 | 5 | B,F | SAFE_RENAME |
| `desktop/cli/src/main.rs` | 0 | 20 | A,B | SAFE_RENAME |
| `desktop/control/Cargo.toml` | 0 | 4 | B,F | SAFE_RENAME |
| `desktop/control/src/lib.rs` | 0 | 8 | A,B | SAFE_RENAME |
| `desktop/control/src/transport.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/core/Cargo.toml` | 0 | 4 | B,F | SAFE_RENAME |
| `desktop/core/examples/gen_test_vectors.rs` | 0 | 3 | G | SAFE_RENAME |
| `desktop/core/src/clipboard_policy.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/core/src/error.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/core/src/framing.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/core/src/identity.rs` | 0 | 25 | E | DO_NOT_RENAME_WITHOUT_DECISION |
| `desktop/core/src/lib.rs` | 0 | 4 | D,E | COMPATIBILITY_SENSITIVE |
| `desktop/core/src/notification_policy.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/core/src/notifications.rs` | 0 | 2 | A,B | SAFE_RENAME |
| `desktop/core/src/pairing.rs` | 0 | 2 | D,E | COMPATIBILITY_SENSITIVE |
| `desktop/core/src/platform/mod.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/core/src/platform/unix_fs.rs` | 0 | 7 | C | MIGRATION_REQUIRED |
| `desktop/core/src/qr.rs` | 0 | 2 | D | COMPATIBILITY_SENSITIVE |
| `desktop/core/src/session.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/core/src/store.rs` | 0 | 11 | A,C | MIGRATION_REQUIRED |
| `desktop/core/tests/identity_and_store.rs` | 0 | 14 | G | SAFE_RENAME |
| `desktop/core/tests/identity_seam.rs` | 0 | 21 | G | SAFE_RENAME |
| `desktop/core/tests/identity_states.rs` | 0 | 9 | G | SAFE_RENAME |
| `desktop/core/tests/notifications_protocol.rs` | 0 | 11 | G | SAFE_RENAME |
| `desktop/core/tests/pairing.rs` | 0 | 5 | G | SAFE_RENAME |
| `desktop/core/tests/parser_fuzz.rs` | 0 | 6 | G | SAFE_RENAME |
| `desktop/core/tests/portable_boundary.rs` | 0 | 7 | G | SAFE_RENAME |
| `desktop/core/tests/protocol.rs` | 0 | 9 | G | SAFE_RENAME |
| `desktop/core/tests/revoked_tombstone.rs` | 0 | 6 | G | SAFE_RENAME |
| `desktop/core/tests/wire_identity.rs` | 2 | 11 | G | SAFE_RENAME |
| `desktop/daemon/Cargo.toml` | 0 | 12 | B,F | SAFE_RENAME |
| `desktop/daemon/examples/fake_phone.rs` | 0 | 33 | G | SAFE_RENAME |
| `desktop/daemon/src/lib.rs` | 0 | 18 | A,B | SAFE_RENAME |
| `desktop/daemon/src/main.rs` | 0 | 35 | A,B | SAFE_RENAME |
| `desktop/daemon/tests/clipboard.rs` | 0 | 3 | G | SAFE_RENAME |
| `desktop/daemon/tests/common/mod.rs` | 0 | 38 | G | SAFE_RENAME |
| `desktop/daemon/tests/control.rs` | 0 | 14 | G | SAFE_RENAME |
| `desktop/daemon/tests/e2e.rs` | 0 | 13 | G | SAFE_RENAME |
| `desktop/daemon/tests/file_approval.rs` | 0 | 8 | G | SAFE_RENAME |
| `desktop/daemon/tests/file_log_privacy.rs` | 0 | 2 | G | SAFE_RENAME |
| `desktop/daemon/tests/files.rs` | 0 | 15 | G | SAFE_RENAME |
| `desktop/daemon/tests/listen.rs` | 0 | 1 | G | SAFE_RENAME |
| `desktop/daemon/tests/notification_log_privacy.rs` | 0 | 6 | G | SAFE_RENAME |
| `desktop/daemon/tests/notifications.rs` | 0 | 44 | G | SAFE_RENAME |
| `desktop/daemon/tests/revoked_cleanup.rs` | 0 | 8 | G | SAFE_RENAME |
| `desktop/daemon/tests/security_certification.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/daemon/tests/sessions.rs` | 0 | 11 | G | SAFE_RENAME |
| `desktop/daemon/tests/wire.rs` | 0 | 7 | G | SAFE_RENAME |
| `desktop/gui/build.rs` | 0 | 6 | C,F | MIGRATION_REQUIRED |
| `desktop/gui/Cargo.toml` | 0 | 6 | B,F | SAFE_RENAME |
| `desktop/gui/data/io.github.yurisismotto.omnibridge.desktop` | 0 | 10 | A,C | MIGRATION_REQUIRED |
| `desktop/gui/data/io.github.yurisismotto.omnibridge.metainfo.xml` | 0 | 14 | A,C,F | MIGRATION_REQUIRED |
| `desktop/gui/data/io.github.yurisismotto.omnibridge.service.in` | 0 | 13 | C | MIGRATION_REQUIRED |
| `desktop/gui/data/omnibridge.gresource.xml` | 0 | 8 | B,C | SAFE_RENAME |
| `desktop/gui/data/style.css` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/gui/README.md` | 0 | 8 | A | SAFE_RENAME |
| `desktop/gui/src/approval.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/gui/src/client.rs` | 0 | 6 | A,B | SAFE_RENAME |
| `desktop/gui/src/lib.rs` | 0 | 40 | A,C | MIGRATION_REQUIRED |
| `desktop/gui/src/main.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/gui/src/panel/model.rs` | 0 | 15 | A,B | SAFE_RENAME |
| `desktop/gui/src/panel/model/tests.rs` | 0 | 8 | A,B | SAFE_RENAME |
| `desktop/gui/src/panel/mod.rs` | 0 | 29 | A,B | SAFE_RENAME |
| `desktop/gui/src/selection.rs` | 0 | 8 | C | MIGRATION_REQUIRED |
| `desktop/gui/src/theme.rs` | 0 | 1 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/clipboard.rs` | 0 | 17 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/dashboard.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/files.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/mod.rs` | 0 | 6 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/notifications.rs` | 0 | 17 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/pairing.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/peers.rs` | 0 | 6 | A,B | SAFE_RENAME |
| `desktop/gui/src/views/settings.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/gui/src/widgets.rs` | 1 | 10 | A,B | SAFE_RENAME |
| `desktop/gui/tests/brand_assets.rs` | 3 | 33 | G | SAFE_RENAME |
| `desktop/gui/tools/install-desktop-metadata.sh` | 0 | 15 | A,B | SAFE_RENAME |
| `desktop/platform-linux/Cargo.toml` | 0 | 10 | B,F | SAFE_RENAME |
| `desktop/platform-linux/src/activation.rs` | 0 | 18 | C | MIGRATION_REQUIRED |
| `desktop/platform-linux/src/lib.rs` | 0 | 23 | C,D | MIGRATION_REQUIRED |
| `desktop/platform-linux/src/tray/activate.rs` | 0 | 8 | A,B | SAFE_RENAME |
| `desktop/platform-linux/src/tray/item.rs` | 0 | 6 | A,B | SAFE_RENAME |
| `desktop/platform-linux/src/tray/menu.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/platform-linux/src/tray/model.rs` | 0 | 15 | A,C | MIGRATION_REQUIRED |
| `desktop/platform-linux/src/tray/mod.rs` | 0 | 18 | A,B | SAFE_RENAME |
| `desktop/platform-linux/src/tray/watcher.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/platform-linux/tests/common/mod.rs` | 0 | 3 | G | SAFE_RENAME |
| `desktop/platform-linux/tests/dbus_activation.rs` | 0 | 13 | G | SAFE_RENAME |
| `desktop/platform-linux/tests/tray_dbus.rs` | 0 | 14 | G | SAFE_RENAME |
| `desktop/platform-linux/tests/tray_gnome.rs` | 0 | 19 | G | SAFE_RENAME |
| `desktop/platform-linux/tests/tray_identity.rs` | 0 | 9 | G | SAFE_RENAME |
| `desktop/platform-linux/tests/tray_model.rs` | 0 | 5 | G | SAFE_RENAME |
| `desktop/proto/build.rs` | 0 | 6 | A,B | SAFE_RENAME |
| `desktop/proto/Cargo.toml` | 0 | 1 | B,F | SAFE_RENAME |
| `desktop/proto/src/lib.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/proto/tests/namespace.rs` | 1 | 17 | G | SAFE_RENAME |
| `desktop/proto/tests/notifications_schema.rs` | 0 | 4 | G | SAFE_RENAME |
| `desktop/runtime/Cargo.toml` | 0 | 11 | B,F | SAFE_RENAME |
| `desktop/runtime/src/approval.rs` | 0 | 4 | A,B | SAFE_RENAME |
| `desktop/runtime/src/lib.rs` | 0 | 7 | A,B | SAFE_RENAME |
| `desktop/runtime/src/listener.rs` | 0 | 5 | A,B | SAFE_RENAME |
| `desktop/runtime/src/mdns.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/runtime/src/renegotiate.rs` | 0 | 3 | A,B | SAFE_RENAME |
| `desktop/runtime/src/server.rs` | 0 | 51 | A,B | SAFE_RENAME |
| `desktop/runtime/src/state.rs` | 0 | 20 | A,B | SAFE_RENAME |
| `docs/adr/ADR-0001-monorepo-structure.md` | 0 | 3 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0002-android-native-kotlin.md` | 0 | 1 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0003-rust-desktop-daemon.md` | 0 | 7 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0005-lan-discovery-mdns.md` | 0 | 1 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0006-device-identity-and-pairing.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0007-tls-transport-and-pinning.md` | 0 | 1 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0008-capability-architecture.md` | 0 | 1 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0011-project-naming-and-wire-identifiers.md` | 32 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0013-file-transfer-data-stream.md` | 0 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0014-clipboard-change-notification.md` | 0 | 3 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0015-notification-access.md` | 0 | 26 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0016-notification-identity.md` | 0 | 6 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0017-capability-roles.md` | 0 | 8 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0018-rename-to-omnibridge.md` | 45 | 42 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/ADR-0019-android-app-signing.md` | 0 | 12 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/adr/README.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/architecture/CLIPBOARD.md` | 0 | 19 | A | SAFE_RENAME |
| `docs/architecture/FILES.md` | 0 | 20 | A | SAFE_RENAME |
| `docs/architecture/NOTIFICATIONS.md` | 0 | 11 | A | SAFE_RENAME |
| `docs/architecture/OVERVIEW.md` | 0 | 24 | A | SAFE_RENAME |
| `docs/architecture/PROTOCOL.md` | 0 | 11 | A | SAFE_RENAME |
| `docs/audits/android/ANDROID-PLAY-V1-DECLARATIONS.md` | 0 | 14 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/android/ANDROID-PLAY-V1-READINESS-AUDIT.md` | 0 | 12 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/linux-compat/LINUX-UBUNTU-DEBIAN-COMPAT-U0.md` | 90 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/linux-compat/LINUX-UBUNTU-DEBIAN-COMPAT-U1.md` | 34 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/linux-compat/LINUX-UBUNTU-DEBIAN-COMPAT-U2.md` | 334 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-BUILD-FOUNDATION.md` | 0 | 110 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-DBUS-ACTIVATION.md` | 1 | 30 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-DEBIAN-UBUNTU.md` | 0 | 31 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-FEDORA-INTEGRATION.md` | 0 | 54 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-READINESS-AUDIT.md` | 2 | 239 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-RELEASE-CI.md` | 0 | 33 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/PACKAGING-V1-SYSTEMD-UNIT.md` | 0 | 94 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/packaging/README.md` | 0 | 1 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/rebrand/OMNIBRIDGE-REBRAND-REMAINDER-AUDIT.md` | 18 | 27 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/release/RELEASE-HARNESS-HARDENING-V1.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/release/RELEASE-READINESS-V1-BASELINE.md` | 15 | 20 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/audits/release/RELEASE-SIGNING-FOUNDATION-V1.md` | 0 | 35 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/clipboard/CLIPBOARD-V1-CERTIFICATION.md` | 24 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/foundation/WAVE-0-CERTIFICATION-FINAL.md` | 57 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/foundation/WAVE-0-LOCAL-CERTIFICATION-REPORT.md` | 35 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/foundation/WAVE-0-POC-CORE-04-READINESS.md` | 44 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/gnome/GNOME-APPINDICATOR-V1.md` | 170 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/kde/KDE-PLASMA-REAL-CERTIFICATION-V1.md` | 204 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/PACKAGING-V1-FINAL-CERTIFICATION.md` | 0 | 24 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/PACKAGING-V1-LIFECYCLE-CERTIFICATION.md` | 0 | 27 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/RELEASE-LIFECYCLE-CLOSURE-V1.md` | 12 | 17 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/linux/RELEASE-PEER-GATES-CLOSURE-V1.md` | 11 | 18 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/notifications/NOTIFICATIONS-V1-N6-FINAL-CERTIFICATION.md` | 83 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/RC-CERTIFICATION-V1.md` | 0 | 39 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/README.md` | 0 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/RELEASE-READINESS-V1-FINAL.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/RELEASE-READINESS-V1.md` | 0 | 17 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/RELEASE-SIGNING-CLOSURE-V1.md` | 0 | 30 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/release/V1.0.0-GA-RELEASE.md` | 0 | 54 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/security/SECURITY-CERTIFICATION-V1.md` | 0 | 24 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/certification/security/SECURITY-EVIDENCE-CLOSURE-V1.md` | 2 | 6 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/design/assets/icons/activity.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/add.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/arrow_back.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/battery.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/check.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/chevron_right.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/clipboard.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/close.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/device_desktop.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/device_phone.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/device_tablet.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/download.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/files.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/file.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/home.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/link_off.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/link.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/more_vert.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/peers.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/qr.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/receive.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/send.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/settings.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/shield_check.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/shield_off.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/shield.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/trash.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/icons/warning.svg` | 0 | 1 | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-android-monochrome.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-app-icon.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-logo-lockup.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-mark-mono.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-mark.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/omnibridge-wordmark.svg` | 0 | path | A | SAFE_RENAME |
| `docs/design/assets/play/render.sh` | 0 | 2 | A | SAFE_RENAME |
| `docs/design/BRAND.md` | 5 | 50 | A | SAFE_RENAME |
| `docs/design/PLAY-STORE-LISTING.md` | 0 | 15 | A,F | SAFE_RENAME |
| `docs/design/tokens.json` | 0 | 2 | A | SAFE_RENAME |
| `docs/design/UI-GUIDELINES.md` | 0 | 24 | A | SAFE_RENAME |
| `docs/migrations/MIGRATION-ANYFLOW-TO-OMNIBRIDGE.md` | 47 | 42 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/policy/PRIVACY-POLICY.md` | 0 | 33 | A,F | MIGRATION_REQUIRED |
| `docs/README.md` | 8 | 5 | A | SAFE_RENAME |
| `docs/reports/android/ANDROID-BRANDING-FILES-UX-V1.md` | 63 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/android/ANDROID-CLIPBOARD-TRUTHFULNESS-V1.md` | 37 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/android/ANDROID-PLAY-V1-RELEASE-SMOKE.md` | 0 | 13 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/branding/OMNIBRIDGE-REBRAND-V1-VISUAL-CLOSURE.md` | 29 | 64 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/branding/QUICK-PANEL-BRANDING-V1.md` | 117 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/branding/VISUAL-IDENTITY-V1-REPORT.md` | 28 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/files/files-v1.md` | 28 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/foundation/POST-WAVE0-DEBTS-MICRO-SPRINT.md` | 8 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/foundation/wave-0-platform-abstraction.md` | 101 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/KDE-STATUSNOTIFIER-V1.md` | 151 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/SYSTEMD-USER-UNIT-CAPABILITIES-FIX.md` | 0 | 22 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/U2-HARDENING-P1-MULTIPEER.md` | 53 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/U2-HARDENING-P2-BATTERY-ABSENCE.md` | 39 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/U2-HARDENING-P3-NOTIFICATION-ROLE-CONVERGENCE.md` | 30 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/linux/U2-HARDENING-TEST-CI.md` | 43 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-DECISION-REPORT.md` | 11 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N0-REPORT.md` | 23 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N1-REPORT.md` | 48 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N2-REPORT.md` | 55 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N3-REPORT.md` | 142 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N4-REPORT.md` | 36 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-N5-REPORT.md` | 55 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/notifications/NOTIFICATIONS-V1-RESEARCH-REPORT.md` | 6 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/security/REVOKED-DEVICE-CLEANUP-V1.md` | 39 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/ux/UX-DEBT-CLEANUP-RETRY-REPAIR-SCANNER-INSETS.md` | 61 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/reports/ux/UX-HARDENING-FILE-APPROVAL-QR-ORIENTATION.md` | 57 | 0 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/00-RESEARCH-FINDINGS.md` | 0 | 12 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/01-FUNCTIONAL-SPECIFICATION.md` | 0 | 32 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/02-PROTOCOL-AND-EVENT-MODEL.md` | 0 | 15 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/03-PRIVACY-SECURITY-THREAT-MODEL.md` | 0 | 21 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/04-PLATFORM-CAPABILITY-MATRIX.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/05-IMPLEMENTATION-PLAN.md` | 0 | 7 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/06-OPEN-QUESTIONS-AND-POCS.md` | 0 | 9 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/poc/POC-NOTIF-01.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/notifications-v1/README.md` | 0 | 2 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/00-EXECUTIVE-SUMMARY.md` | 0 | 7 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/01-CURRENT-ARCHITECTURE-AUDIT.md` | 0 | 31 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/02-CROSS-PLATFORM-TARGET-ARCHITECTURE.md` | 0 | 28 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/03-PLATFORM-CAPABILITY-MATRIX.md` | 0 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/04-LINUX-PORTABILITY.md` | 0 | 30 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/05-DEBIAN-UBUNTU-COMPATIBILITY.md` | 0 | 13 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/06-KDE-PLASMA-WAYLAND.md` | 0 | 26 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/07-LINUX-PACKAGING.md` | 0 | 46 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/08-WINDOWS-FEASIBILITY.md` | 0 | 38 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/09-WINDOWS-SECURITY-AND-INTEGRATION.md` | 0 | 12 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/10-MACOS-FEASIBILITY.md` | 0 | 18 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/11-IOS-IPADOS-FEASIBILITY.md` | 0 | 26 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/12-APPLE-SECURITY-AND-INTEGRATION.md` | 0 | 10 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/13-CROSS-PLATFORM-DISCOVERY.md` | 0 | 8 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/14-CROSS-PLATFORM-IDENTITY-AND-KEY-STORAGE.md` | 0 | 8 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/15-CROSS-PLATFORM-CLIPBOARD.md` | 0 | 3 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/16-CROSS-PLATFORM-FILES.md` | 0 | 9 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/17-BACKGROUND-EXECUTION-MODEL.md` | 0 | 13 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/18-UI-PLATFORM-STRATEGY.md` | 0 | 6 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/19-PACKAGING-AND-DISTRIBUTION.md` | 0 | 6 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/20-SECURITY-THREAT-ANALYSIS.md` | 0 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/21-POC-MASTER-PLAN.md` | 1 | 37 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/22-IMPLEMENTATION-ROADMAP.md` | 0 | 9 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/23-RISKS-OPEN-QUESTIONS-AND-DECISIONS.md` | 0 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/24-SOURCE-BIBLIOGRAPHY.md` | 0 | 4 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/25-IMPLEMENTATION-BACKLOG.md` | 1 | 27 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/26-EXTERNAL-VERIFICATION-CLOSEOUT.md` | 0 | 22 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/27-ARCHITECTURE-DECISION-CLOSEOUT.md` | 0 | 16 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/28-WAVE-0-IMPLEMENTATION-SPEC.md` | 2 | 90 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/research/platform-expansion/README.md` | 1 | 5 | H | DO_NOT_RENAME_WITHOUT_DECISION |
| `docs/security/THREAT_MODEL.md` | 0 | 18 | A | SAFE_RENAME |
| `.github/workflows/android-ci.yml` | 0 | 3 | F | SAFE_RENAME |
| `.github/workflows/desktop-quality.yml` | 0 | 10 | F | SAFE_RENAME |
| `.github/workflows/linux-distro-compat.yml` | 0 | 38 | F | SAFE_RENAME |
| `.github/workflows/packaging-checks.yml` | 0 | 4 | F | SAFE_RENAME |
| `.github/workflows/portable-windows-msvc.yml` | 0 | 47 | F | SAFE_RENAME |
| `.github/workflows/release-artifacts.yml` | 0 | 22 | F | SAFE_RENAME |
| `.github/workflows/security-audit.yml` | 0 | 2 | F | SAFE_RENAME |
| `packaging/common/omnibridged.service` | 0 | 8 | C,F | MIGRATION_REQUIRED |
| `packaging/common/README.md` | 0 | 7 | F | MIGRATION_REQUIRED |
| `packaging/debian/build-deb.sh` | 0 | 11 | F | MIGRATION_REQUIRED |
| `packaging/debian/changelog` | 0 | 5 | F | MIGRATION_REQUIRED |
| `packaging/debian/control` | 0 | 13 | C,F | MIGRATION_REQUIRED |
| `packaging/debian/copyright` | 0 | 2 | F | MIGRATION_REQUIRED |
| `packaging/debian/omnibridge.docs` | 0 | path | F | MIGRATION_REQUIRED |
| `packaging/debian/omnibridge-gui.install` | 0 | 4 | F | MIGRATION_REQUIRED |
| `packaging/debian/omnibridge.install` | 0 | 4 | F | MIGRATION_REQUIRED |
| `packaging/debian/README.md` | 0 | 18 | F | MIGRATION_REQUIRED |
| `packaging/debian/README.source` | 0 | 7 | F | MIGRATION_REQUIRED |
| `packaging/debian/rules` | 0 | 15 | F | MIGRATION_REQUIRED |
| `packaging/fedora/build-rpm.sh` | 0 | 17 | F | MIGRATION_REQUIRED |
| `packaging/fedora/omnibridge-firewalld.xml` | 0 | 5 | C,F | MIGRATION_REQUIRED |
| `packaging/fedora/omnibridge.spec` | 0 | 45 | C,F | MIGRATION_REQUIRED |
| `packaging/fedora/README.md` | 0 | 53 | F | MIGRATION_REQUIRED |
| `packaging/release/make-source-bundle.sh` | 0 | 14 | F | MIGRATION_REQUIRED |
| `packaging/release/sign-release.sh` | 0 | 7 | E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `packaging/release/verify-release.sh` | 0 | 3 | E,F | DO_NOT_RENAME_WITHOUT_DECISION |
| `packaging/tests/harness-selftests.sh` | 0 | 8 | G,F | SAFE_RENAME |
| `packaging/tests/install-smoke.sh` | 0 | 47 | G,F | SAFE_RENAME |
| `packaging/tests/lib/assert.sh` | 0 | 3 | G,F | SAFE_RENAME |
| `packaging/tests/lib/phone-ui.py` | 0 | 1 | G,F | SAFE_RENAME |
| `packaging/tests/lifecycle-gates.sh` | 1 | 126 | G,F | SAFE_RENAME |
| `packaging/tests/lifecycle-peer-gates.sh` | 2 | 42 | G,F | SAFE_RENAME |
| `packaging/tests/packaging-checks.sh` | 0 | 64 | G,F | SAFE_RENAME |
| `packaging/tests/release-signing-production-tests.sh` | 0 | 7 | G,F | SAFE_RENAME |
| `packaging/tests/release-signing-tests.sh` | 0 | 34 | G,F | SAFE_RENAME |
| `packaging/tests/security-log-evidence.sh` | 1 | 26 | G,F | SAFE_RENAME |
| `packaging/tests/systemd-unit-gates.sh` | 0 | 18 | G,F | SAFE_RENAME |
| `protocol/proto/omnibridge/v1/capabilities/battery_v1.proto` | 0 | 2 | D | COMPATIBILITY_SENSITIVE |
| `protocol/proto/omnibridge/v1/capabilities/clipboard_v1.proto` | 0 | 2 | D | COMPATIBILITY_SENSITIVE |
| `protocol/proto/omnibridge/v1/capabilities/files_v1.proto` | 0 | 4 | D | COMPATIBILITY_SENSITIVE |
| `protocol/proto/omnibridge/v1/capabilities/notifications_v1.proto` | 0 | 6 | D | COMPATIBILITY_SENSITIVE |
| `protocol/proto/omnibridge/v1/core.proto` | 0 | 4 | D | COMPATIBILITY_SENSITIVE |
| `protocol/proto/omnibridge/v1/envelope.proto` | 0 | 3 | D | COMPATIBILITY_SENSITIVE |
| `protocol/testdata/identity-a.der` | 2 | 0 | E,G | DO_NOT_RENAME_WITHOUT_DECISION |
| `protocol/testdata/identity-b.der` | 2 | 0 | E,G | DO_NOT_RENAME_WITHOUT_DECISION |
| `README.md` | 5 | 123 | A,F | SAFE_RENAME |
