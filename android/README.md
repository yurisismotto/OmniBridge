# Pliwee — Android app

Kotlin, Jetpack Compose, coroutines. No Google Play Services, no analytics, no
network access beyond the LAN socket to the paired computer.

## Identity

| | |
| --- | --- |
| `applicationId`, `namespace`, Kotlin root package | `io.github.yurisismotto.pliwee` ([ADR-0020](../docs/adr/ADR-0020-rename-to-pliwee.md) §D1) |
| Notification fixture (test only) | `io.github.yurisismotto.pliwee.fixture` |
| Keystore aliases | `pliwee-identity-v1`, `pliwee-notification-secret-v1` |
| Received files | `Download/Pliwee` (MediaStore) |
| Intent actions | `io.github.yurisismotto.pliwee.{STOP,APPLY_CLIP,SEND_CLIPBOARD}` |

This is a new app, not an update of the never-distributed OmniBridge build
(`io.github.yurisismotto.omnibridge`): nothing of an OmniBridge install —
identity key, trust store, notification secret, grants — carries over, and
the desktop meets the phone as a new device. An OmniBridge app left on a test
device is removed by hand; nothing uninstalls it.

**Frozen components.** From Pliwee Wave 6 on, these `ComponentName`s are
persisted by Android and must not change: `.notifications.PliweeNotificationListener`
(notification access), `.ui.ClipboardTileService` (Quick Settings tile),
`.ui.MainActivity` (launcher, shortcuts), `.ui.SendActivity` (share target),
`.ui.PairingCaptureActivity`, `.service.ConnectionService`. A rename keeps the
old name through a subclass or an `activity-alias`, or it is a breaking
change. `ManifestComponentsTest` holds the snapshot.

## Build

Requires **JDK 21** and the **Android SDK, platform 36** with build-tools
35.0.0 (platform 35 as well if you build the test-only `:fixture`). Point
Gradle at them with `JAVA_HOME` and `ANDROID_HOME`, or with an untracked
`android/local.properties`.

`:app` compiles against and targets API 36 because Google Play requires new
apps and updates submitted after 2026-08-31 to target Android 16. AGP 8.10 is
the first plugin line that supports API 36, which is the only reason it moved
from 8.8.

JDK 21 specifically: it is the runtime this build is verified on. AGP 8.8 did
not support running on JDK 25, which is what Fedora 44 ships as its default
`java`, and AGP 8.10 has not been verified there.

```bash
export JAVA_HOME=/path/to/jdk-21
export ANDROID_HOME="$HOME/Android/Sdk"

cd android
./gradlew :app:testDebugUnitTest   # 63 tests
./gradlew :app:assembleDebug       # -> app/build/outputs/apk/debug/app-debug.apk
```

### Resource limits

`gradle.properties` caps the Gradle JVM, the Kotlin daemon and the worker
count on purpose. This is a single-module project, so parallelism buys almost
nothing, while the defaults are enough to push a 16 GiB laptop into swap. Do
not raise them without a reason.

## Testing

Local JVM unit tests cover the wire rules, pinning, framing, capability
negotiation and the pairing proof. Two suites assert known-answer vectors
shared with the Rust implementation:

* `PairingProofTest` — the proof and confirmation HMACs.
* `FingerprintTest` — the SPKI fingerprints of `protocol/testdata/*.der`,
  which are real certificates emitted by the desktop identity code.

`PinnedTrustManagerTest` runs against those same real certificates rather than
a stub, so removing the pinning comparison makes it fail.

**Not covered here:** `TrustStore`'s persistence path needs a real `Context`
and `filesDir`, and proof-of-private-key-possession is the TLS handshake's
job, which a local unit test cannot stand in for. Both are on-device
concerns.

## Layout

| Path | Role |
| --- | --- |
| `identity/DeviceIdentity.kt` | P-256 key in the Android Keystore, StrongBox when available |
| `identity/Fingerprint.kt` | SHA-256 over the DER SPKI |
| `net/PinnedTrustManager.kt` | TLS 1.3 + public-key pinning. **Read the comments before editing.** |
| `net/Framing.kt` | Length-prefixed protobuf frames |
| `net/PeerConnection.kt` | Handshake, pairing, replay guard, capability routing |
| `net/Discovery.kt` | mDNS/DNS-SD browsing via `NsdManager` |
| `pairing/QrPayload.kt` | Strict parser for the scanned code |
| `pairing/PairingProof.kt` | HMAC-SHA256 proof, identical to the Rust side |
| `capability/` | The plugin model, plus `battery.v1` |
| `service/ConnectionService.kt` | `connectedDevice` foreground service |
| `store/TrustStore.kt` | Paired computers, on disk |

## Permissions, and what is deliberately missing

Held: `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
`CHANGE_NETWORK_STATE`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS`, `CAMERA`.

Not held, and not to be added without an ADR: any accessibility service, the
notification listener, `QUERY_ALL_PACKAGES`, location, or broad storage. The
project does not require root and does not use ADB.

## Protobuf

The Gradle protobuf plugin compiles `../../protocol/proto` directly — the same
files the Rust daemon compiles. There is no second copy to drift.

## Release signing

Model and custody: [ADR-0019](../docs/adr/ADR-0019-android-app-signing.md).
`signing/provision-signing-keys.sh` provisions the app signing and upload keys
once, outside this repository; `signing/tests/provision-selftest.sh` rehearses
it with throwaway keys. No keystore, private key or password is ever committed.

The signing identity is **Pliwee's** (ADR-0020 §D3): aliases `pliwee-upload`
and `pliwee-app-signing`, subjects `CN=Pliwee, OU=Android Upload` /
`CN=Pliwee, OU=Android App Signing`, custody under
`~/.local/share/pliwee-android-signing/` and
`~/.local/state/pliwee-android-signing/PROVISIONED`. A release build reads
`PLIWEE_UPLOAD_KEYSTORE` and `PLIWEE_UPLOAD_KEYSTORE_PASSWORD`; without them
every release packaging task fails (`-Ppliwee.release.unsigned=true` is the
one, labelled, escape hatch for R8 checks). The retired OmniBridge
certificates stay byte-identical in `signing/certs/legacy-omnibridge/`; the
OmniBridge record, keystore and backups are never read or touched.
