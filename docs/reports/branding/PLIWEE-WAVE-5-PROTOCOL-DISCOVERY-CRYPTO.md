# Pliwee Wave 5 — Protocol, discovery and cryptographic-domain migration

| | |
| --- | --- |
| **Wave** | 5 — Protocol, discovery and cryptographic-domain migration ([plan](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md) §Wave 5, §4) |
| **Decisions** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) D4, D10, D12 |
| **Branch / base** | `feature/pliwee-rebrand-wave5`, working tree on top of `b7a8789` (Wave 4). Not committed: the orchestrator owns git. |
| **Date** | 2026-09-24 |
| **Host** | Fedora 44, kernel 7.2.5, **1 CPU**, 15 GiB RAM. rustc/cargo 1.98.1. Temurin JDK 21 (`/usr/lib/jvm/java-21-temurin-jdk`), Gradle wrapper 8.11.1. Every cargo and Gradle job ran alone, one after another (`-j 2`, `CARGO_BUILD_JOBS=2`, `RUST_TEST_THREADS=2`, Gradle `--max-workers=2`, `org.gradle.parallel=false`). No VM or emulator was started. |
| **Gate status** | **G5 automated part: PASS.** Unit, negative (X1–X4, X5 logic) and KAT suites are green in both languages, and the frozen-vector digests match. **§4 network matrix on hardware (N1–N5, and X1–X5 observed on a device): NOT EXECUTED → wave result BLOCKED_MANUAL.** |

## 1. What changed

### 1.1 The profile, once per connection (ADR-0020 §D4)

Each side now has one type that owns every brand-bearing wire value:

* desktop: `pliwee_core::Profile` (`desktop/core/src/profile.rs`)
* Android: `net.WireProfile` (`net/WireProfile.kt`)

Nothing else spells those values, apart from the constants they re-export.

| Identifier | Canonical `Profile::Pliwee` / `PLIWEE` | Legacy `Profile::OmniBridge` / `OMNIBRIDGE` |
| --- | --- | --- |
| Control ALPN | `pliwee/1` | `omnibridge/1` |
| Data ALPN | `pliwee-data/1` | `omnibridge-data/1` |
| mDNS / NSD | `_pliwee._tcp.local.` / `_pliwee._tcp.` | `_omnibridge._tcp.local.` / `_omnibridge._tcp.` |
| QR scheme | `pliwee1` (emitted) | `omnibridge1` (parsed, never emitted) |
| Pairing proof / confirm | `pliwee/pairing-proof/v1`, `pliwee/pairing-confirm/v1` | `omnibridge/pairing-proof/v1`, `omnibridge/pairing-confirm/v1` |
| `files.v1` data stream | `pliwee/files.v1/data-stream/v1` | `omnibridge/files.v1/data-stream/v1` |
| `notifications.v1` id / group / content | `pliwee/notifications.v1/{id,group,content}/v1` | **none** (canonical only, no dual path) |
| Certificate CN, new identities | `pliwee:<device-id>` (both sides) | not parsed; existing certificates untouched |

Where each profile rule lives:

| Rule (plan "Profile rules") | Desktop | Android |
| --- | --- | --- |
| Listener offers `pliwee/1`, `pliwee-data/1`, `omnibridge/1`, `omnibridge-data/1`, in that order | `tls::SERVER_ALPN_PROTOCOLS`, `server_config` | — (the phone never listens) |
| A client offers **one** ALPN | `tls::client_config(…, profile)` / `data_stream_client_config(…, profile)`: `alpn_protocols = vec![one]` | `TlsFactory.harden(socket, alpn)`: no default, one value; `requireNegotiated` checks the server picked it |
| Negotiated ALPN → *(profile, kind)* | `NegotiatedProtocol { profile, kind: ConnectionKind }`, `NegotiatedProtocol::from_alpn`; `runtime/src/listener.rs` fixes `profile` once and passes it on | `PeerConnection.profile`, taken from what was offered and required to be negotiated |
| Pairing domains come from the profile | `pairing::compute_proof/compute_confirmation(profile, …)`; `PairingSession::verify_and_consume(profile, …)`; `SessionHost::verify_pairing_proof(profile, …)`; `session::{accept,connect}_handshake(…, profile, …)` | `PairingProof.compute/computeConfirmation(profile, …)` |
| A data stream must match its control session's profile | `TransferRecord.profile` from the session (`CapabilityContext.profile`); `accept_data_stream(…, profile)` refuses a mismatch **before** the MAC and before any byte; MAC keyed to `record.profile` only | `FileTransferManager.Transport.profile` = the session's; `DataStream.open(…, profile)` and `StreamAuth.compute(profile, …)` |
| Verify under the negotiated domain only, never "try both" | there is no code path that computes the other domain for verification | same |
| Profile recorded per peer **in memory** for dialling, never persisted | `SessionHandle::profile()`, `TransferManager` session map | `net.PeerProfiles` (in-memory map keyed by pinned fingerprint): canonical unless paired from `omnibridge1:` or discovered on `_omnibridge._tcp` only; newest evidence wins |
| Dual advertisement / dual browse, dedupe preferring canonical | `runtime/src/mdns.rs`: one instance registered under both types (same instance, port, TXT) | `Discovery.browse()` runs one NSD browse per type, each result tagged with its profile; `Discovery.merge` / `mergeFor` fold records by TXT `id`, canonical wins |
| QR: emit `pliwee1:` only; parse both; scheme fixes profile; `…2:` recognised-and-rejected | `QrPayload::encode` (always `pliwee1`), `QrPayload.profile`, `profile_of_scheme` → `"unsupported QR payload version"` vs `"unknown QR scheme"` | `QrPayload.scan` → `Accepted` / `UnsupportedVersion` / `Invalid`; `QrPayload.profile` |
| Notifications canonical only | desktop ids opaque; the Rust cross-check (`core/tests/notifications_protocol.rs`) now mirrors the canonical domains | `NotificationIdentity.{ID,GROUP,CONTENT}_DOMAIN` = `pliwee/…` |
| CN for new identities | `LocalIdentity::issue_certificate` (reached only from `generate`) | `DeviceIdentity` (reached only when a new key is generated) |

Unchanged, as the plan requires: every construction, framing, field, token size (160 bits), nonce
(32 bytes), TTL (120 s), attempt limit (3), protobuf schema, TCP 55432, the mDNS TXT keys, and the
frozen DERs. No state is persisted and no schema changed.

### 1.2 Files touched

* **Desktop.**
  * Core sources: `core/src/{lib,profile (new),tls,qr,pairing,session,capability,identity}.rs`.
  * Files capability: `capabilities/files/src/{auth,lib}.rs`.
  * Runtime: `runtime/src/{listener,mdns,state}.rs`.
  * GUI: `gui/src/views/mod.rs` (the "Secure connection" tooltip now names `pliwee/1`, and `omnibridge/1` for an OmniBridge 1.0.0 device).
  * Examples: `core/examples/gen_test_vectors.rs` now refuses to overwrite a fixture (D10). `daemon/examples/fake_phone.rs` gains `--profile`.
  * Core tests: `core/tests/{wire_identity,pairing,identity_and_store,identity_seam,notifications_protocol,frozen_vectors (new)}.rs`.
  * Daemon tests: `daemon/tests/{common/mod,files,sessions,wire,profile_isolation (new)}.rs`.
  * Other tests: `capabilities/battery/tests/battery_presence.rs` (the context field only).
* **Android.**
  * Main sources: `net/{WireProfile (new),PeerProfiles (new),PinnedTrustManager,Discovery,PeerConnection}.kt`, `pairing/{QrPayload,PairingProof}.kt`, `files/{StreamAuth,DataStream,FileTransferManager}.kt`, `notifications/NotificationIdentity.kt`, `identity/DeviceIdentity.kt`, `service/ConnectionService.kt`, `PliweeApp.kt`.
  * Unit tests: `WireIdentityTest`, `PairingProofTest`, `PairingRecoveryTest`, `StreamAuthTest`, `NotificationIdentityTest`, `QrPayloadTest`, `FingerprintTest`, `Fixtures.kt`.
  * Instrumented: `HostDrivenCertificationHarness.kt` (its pairing log line now names the profile, as a hardware anchor).
  * `ConnectionCoordinator.kt` needed no change: it orders dials, and the profile is chosen in `PliweeApp.connect`.
* **Docs.**
  * Living docs: `docs/architecture/{PROTOCOL,FILES,CLIPBOARD}.md` and `docs/design/UI-GUIDELINES.md`.
  * `NOTIFICATIONS.md` spells no domain string, so it was not touched.
  * Dated superseding notes (plan §0.1 rule 5) sit under the status line of ADR-0005, 0006, 0007, 0013, 0016 and 0018. The original text is unchanged beneath each note.

## 2. Frozen vectors (D10)

`protocol/testdata/identity-{a,b}.der` are **byte-identical**: `git diff` over `protocol/testdata`
is empty, and the digests below come from the committed blobs (`git show HEAD:protocol/testdata/identity-{a,b}.der | sha256sum`,
base `b7a8789`, identical to the working files):

| File | SHA-256 |
| --- | --- |
| `identity-a.der` | `cdb976416b52d73b00faeadcb1890e35515061527559cd0643e451b7c46baa41` |
| `identity-b.der` | `a3b55bf1b9db309585eec391efb5de42ca0cd3c4810ba03d4cc1986ce26561a8` |

Two tests compare them with these digests:

* `desktop/core/tests/frozen_vectors.rs`, 3/3 passing. It also asserts that the fixtures still carry their historical `CN=anyflow:` subject.
* Android `FingerprintTest.the frozen fixture files are byte-identical` (constants in `Fixtures.kt`).

The four SPKI KATs are untouched: `FIXTURE_{A,B}_FINGERPRINT` in Rust and
`IDENTITY_{A,B}_FINGERPRINT` in Kotlin, both still green. `gen_test_vectors` now refuses to overwrite
an existing fixture.

## 3. Domain KATs — independent computation

**Command:** `python3 docs/reports/branding/pliwee-wave-5/pliwee_domain_kats.py`. The script uses only the Python
standard library (`hmac`, `hashlib`, `struct`) and neither implementation. Output
([`pliwee-domain-kats-output.txt`](pliwee-wave-5/pliwee-domain-kats-output.txt)):

```text
[omnibridge]
pairing-proof      d34504e66ea816d8ac8a12de225db8ae6b9c03f7010b15a15f50cf3b53b859e1
pairing-confirm    fd1689c7fd3715e376ea9423c858c4839cce729a9471b5f6e93f76e34d0c11f3
files-data-stream  503aaf7d8c15b38971f4fbcc3ec34742ae27263ac94f2507ecab7c3691764576
notif-id           3c8effce6feb1582a65e100aeea1a810
notif-id-other-key 3561179daf1a26a8a047f3f44758eaf3
notif-id-other-sec e88bcb16b74b498c91090bc76fc3b2d9
notif-group        b9f8d940e134bccb

[pliwee]
pairing-proof      3a433e1b0ec55746039eba2216abb786b0537955efd8f4ed1c92886426182510
pairing-confirm    5f0bc7caae96da5c38f4a75fa78e7e43a75ec10daef83e7fa2efad04d9194672
files-data-stream  de3164a18f2cfb5e042b4b755d45f30f3049e41a93d0f727b33b26e17bafc3f9
notif-id           c66b87d0c2045df6dda2925297262cb8
notif-id-other-key 889ab0ae9dd2c6ed9a4529e54f68ce1e
notif-id-other-sec 4cf44891803581d358fe6043497e1d98
notif-group        74935dada71d629f
```

Every `[omnibridge]` row equals the KAT committed before this wave. So the script reads the
construction the same way the frozen KATs were derived, and that is what makes its `[pliwee]` rows
trustworthy.

Where each set lives now:

* **Legacy pairing and data-stream KATs** stay byte-for-byte, pinned under the legacy profile in both languages:
  * Rust: `legacy_{proof,confirmation}_matches_the_cross_language_known_answer`, `the_legacy_mac_matches_the_published_cross_language_vector`.
  * Kotlin: `legacy proof/confirmation …`, `the legacy mac …`.
* **Pliwee KATs** are added beside them, in both languages, and are equal across languages.
* **Notifications** have no legacy profile. The Rust mirror and `NotificationIdentityTest` now pin the independently computed Pliwee values. The four pre-Wave-5 values are recorded above, since there is no live code left for them to test.

## 4. Tests executed

All logs are in [`pliwee-wave-5/`](pliwee-wave-5/). Trailing whitespace and trailing blank lines were
stripped from these captured logs so that `git diff --check` passes. No other byte was changed.

| Command | Result |
| --- | --- |
| `cargo test -p pliwee-core --test wire_identity --test pairing --test identity_and_store --test frozen_vectors --test identity_seam` | exit 0. wire_identity **18/18**, pairing **25/25**, identity_and_store **28/28**, frozen_vectors **3/3**, identity_seam **8/8** ([`core-targeted.txt`](pliwee-wave-5/core-targeted.txt)) |
| `cargo test -p pliwee-core --test notifications_protocol -p pliwee-capability-files --lib` | exit 0. notifications_protocol **47/47**, files lib **74/74**, core lib 25/25 ([`notif-files-targeted.txt`](pliwee-wave-5/notif-files-targeted.txt)) |
| `cargo test -p pliwee-daemon --test profile_isolation -- --nocapture` | exit 0, **2/2**, with the daemon's own lines as evidence (§5) ([`profile-isolation.txt`](pliwee-wave-5/profile-isolation.txt)) |
| `PLIWEE_TEST_PROFILE=pliwee cargo test -p pliwee-daemon --test wire --test e2e --test files --test sessions` | exit 0. e2e **18/18**, files **36/36**, sessions **6/6**, wire **10/10** ([`daemon-suites-profile-pliwee.txt`](pliwee-wave-5/daemon-suites-profile-pliwee.txt)) |
| `PLIWEE_TEST_PROFILE=omnibridge cargo test …` (same four suites) | exit 0. e2e **18/18**, files **36/36**, sessions **6/6**, wire **10/10** ([`daemon-suites-profile-omnibridge.txt`](pliwee-wave-5/daemon-suites-profile-omnibridge.txt)). A genuine second run: different test order, separate log. |
| `PLIWEE_TEST_PROFILE={pliwee,omnibridge} cargo test -p pliwee-daemon --test wire -- --nocapture` (after adding the run anchor) | exit 0, **11/11** each. The daemon-side anchor was `EVIDENCE run-profile=pliwee daemon-session-profile=pliwee alpn=pliwee/1` and `EVIDENCE run-profile=omnibridge daemon-session-profile=omnibridge alpn=omnibridge/1` ([`wire-profile-pliwee.txt`](pliwee-wave-5/wire-profile-pliwee.txt), [`wire-profile-omnibridge.txt`](pliwee-wave-5/wire-profile-omnibridge.txt)) |
| `PLIWEE_TEST_PROFILE=bogus cargo test -p pliwee-daemon --test sessions` | fails loudly: `PLIWEE_TEST_PROFILE="bogus" is not a profile`. A typo cannot quietly re-run the canonical profile. |
| `cargo fmt --all -- --check` | exit 0 ([`fmt-final.txt`](pliwee-wave-5/fmt-final.txt)) |
| `cargo clippy --locked --workspace --all-targets --all-features -j 2 -- -D warnings` | exit 0 on the final tree ([`clippy-final.txt`](pliwee-wave-5/clippy-final.txt)) |
| `cargo test --workspace --no-fail-fast -j 2`, final Rust tree | **exit 0. 75 binaries, 1112 passed, 0 failed, 25 ignored.** Wave 4 had 73 binaries and 1085 passed; the two new binaries are `frozen_vectors` and `profile_isolation`. `portable_boundary` 11/11, `security_certification` 7/7. Per suite: [`rust-suites-final.txt`](pliwee-wave-5/rust-suites-final.txt). Raw: [`workspace-final.log`](pliwee-wave-5/workspace-final.log). |
| `./gradlew --offline --max-workers=2 :app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :fixture:assembleDebug` (JDK 21) | **BUILD SUCCESSFUL.** `compileDebugKotlin`, `compileDebugUnitTestKotlin`, `testDebugUnitTest` and `compileDebugAndroidTestKotlin` all *executed* (none up-to-date or from cache). Old results were deleted first, and all 56 result files are time-stamped by this run. **854 tests, 0 failures, 0 errors, 0 skipped** (Wave 3 had 833). WireIdentityTest 20, PairingProofTest 12, StreamAuthTest 12, NotificationIdentityTest 19, QrPayloadTest 13, FingerprintTest 7, PairingRecoveryTest 30, PinnedTrustManagerTest 7, NotificationSecretTest 14 ([`android-unit.log`](pliwee-wave-5/android-unit.log), [`android-suites-after.txt`](pliwee-wave-5/android-suites-after.txt)) |
| `./gradlew --offline --max-workers=2 :app:lintDebug` | exit 1: **1 error, 36 warnings**, identical to the Wave 1 baseline. The one error is the pre-existing `StartActivityAndCollapseDeprecated` in the untouched `ClipboardTileService.kt:100`. No issue points at a Wave 5 line ([`android-lint-results.txt`](pliwee-wave-5/android-lint-results.txt)). |
| `git diff --check` (untracked files included via a temporary intent-to-add, index restored afterwards) | exit 0 ([`git-diff-check.txt`](pliwee-wave-5/git-diff-check.txt)) |

The protected security suites changed **names only, never assertions** (plan §0.1 rule 3).
`PairingProofTest`'s existing assertions are byte-identical; its property tests now loop over both
profiles, its two KATs gained a `legacy` name prefix and an explicit `OMNIBRIDGE` argument, and tests
were only *added*. `PinnedTrustManagerTest` and `NotificationSecret*` are untouched. Among the Rust
security suites (`security_certification.rs`, `control.rs`, `revoked_cleanup.rs`,
`file_approval.rs`, `*_log_privacy.rs`), none was edited.

## 5. G5 — negative (no-hybrid) evidence

| Row | Test | Observation |
| --- | --- | --- |
| **X1** legacy proof on a canonical connection | Rust `pairing.rs::a_proof_from_the_other_profile_is_rejected`, Kotlin `a value from the other profile never verifies`, **real daemon** `profile_isolation.rs::a_pairing_proof_from_the_other_profile_is_rejected_by_the_daemon` | `PAIR_RESPONSE = REJECTED`, no trust written (checked before and after). The daemon line is anchored on this connection's own source port: `connection ended peer_addr=127.0.0.1:36100 error=pairing failed: invalid proof`. The same window then pairs under the connection's own profile, so the refusal was the domain and nothing else. |
| **X2** canonical proof on a legacy connection | same tests, other direction | `connection ended peer_addr=127.0.0.1:48254 error=pairing failed: invalid proof`, then an own-profile pairing succeeds |
| **X3** data stream across profiles | `profile_isolation.rs::a_data_stream_from_the_other_profile_is_refused_before_any_byte`; Rust `auth.rs::a_mac_from_one_profile_does_not_verify_under_the_other`; Kotlin `a mac from one profile does not verify under the other` | Both MAC variants (the other profile's domain and the session's own) are refused with `DataStreamReady = REJECTED`: 0 bytes counted, no stored file, transfer still `Transferring`. Exactly 2 daemon lines per direction name this transfer id, this peer and both profiles: `refused a data stream whose profile differs from its control session transfer=5a5a5a5a peer=F075 F3FD AE89 8FE5 session_profile=pliwee stream_profile=omnibridge` (and the mirror image). The untouched challenge then completes the transfer under the session's profile. |
| **X4** client with both ALPNs | Rust `wire_identity.rs::a_client_config_offers_exactly_one_alpn`, `a_real_handshake_negotiates_the_offered_profile_and_nothing_else`, `a_legacy_only_server_refuses_a_canonical_client`; Kotlin `a hardened client socket offers exactly one ALPN` | Impossible by construction, and proved: every config the production code builds carries exactly one ALPN, and a real loopback handshake negotiates exactly the offered *(profile, kind)* for all four values |
| **X5** one daemon advertised twice | Kotlin `a daemon advertised under both types is one device, dialled canonically`, `… seen only on the legacy type is dialled with the legacy profile`, `merging for one device …`; desktop side observed on the LAN (§6) | merge logic: PASS. **The app showing one device on a real device: NOT EXECUTED** (§7). |

Also asserted: the profile selection table (each ALPN → one *(profile, kind)*, unknown → none), both
value sets and the dead list `anyflow`, `fedroid` in both languages, and the QR parse matrix in both
languages: `pliwee1` accept, `omnibridge1` accept, `pliwee2`/`omnibridge2` recognised-reject,
`anyflow1` reject.

## 6. Binary-level observations on this host (not the §4 matrix)

These use the real binaries and a real LAN. They are **not** a substitute for §4, which needs a
physical Android device and a packaged OmniBridge 1.0.0 peer. They are recorded because each one is
anchored on a line the product wrote in this run.

1. **Dual advertisement** ([`mdns-dual-advertisement.txt`](pliwee-wave-5/mdns-dual-advertisement.txt), [`mdns-daemon.log`](pliwee-wave-5/mdns-daemon.log)). A throwaway `target/debug/omnibridged` ran with `--port 55999`, temporary data, runtime and download dirs, under `timeout 30`. It logged `advertising _pliwee._tcp.local. … profile=pliwee` and `advertising _omnibridge._tcp.local. … profile=omnibridge`. `avahi-browse -rpt` then resolved its device id `dfbdafa3505c934a21ba2abaa79c18ec` in **4 records under each type** (2 interfaces × 2 families), with the same port and TXT (`id`, `dn`, `v=1`, `pv=1-1`). The host's **packaged OmniBridge 1.0.0** daemon (`omnibridge-1.0.0-1.fc44`, id `7ca9ec07…`, port 55432) resolved under `_omnibridge._tcp` **only**. That is exactly the case `Discovery.merge` dials with the legacy profile.
2. **What the packaged 1.0.0 daemon accepts** ([`omnibridge-1.0.0-alpn-probe.txt`](pliwee-wave-5/omnibridge-1.0.0-alpn-probe.txt)). `openssl s_client -tls1_3` with a throwaway P-256 certificate offered one ALPN at a time and sent no application data. Nothing was paired and nothing changed on that daemon. `pliwee/1` and `pliwee-data/1` got `No ALPN negotiated`, `alert no application protocol`; `omnibridge/1` and `omnibridge-data/1` were negotiated. So a canonical dial to a 1.0.0 desktop fails at the handshake. That is a transport failure, which the app retries; the retry round's discovery finds the desktop on the legacy type only and dials it legacy (`PeerProfiles`).
3. **Loopback pairing, reconnect and file transfer per profile** ([`loopback_profiles.sh`](pliwee-wave-5/loopback_profiles.sh), [`loopback-pliwee.txt`](pliwee-wave-5/loopback-pliwee.txt), [`loopback-omnibridge.txt`](pliwee-wave-5/loopback-omnibridge.txt)). The run used the throwaway daemon (`--no-mdns`, port 55999), the real `omnibridge pair` CLI answering `y`, and `fake_phone`. The daemon emitted a `pliwee1:` payload and never a legacy one. The legacy run presented the same body under `omnibridge1:`, as an OmniBridge 1.0.0 desktop would show it. Each run found exactly **2** `session established … profile=<p> alpn=<p's ALPN>` lines for its phone and **0** under the other profile. Its file transfer (`dac640a4` canonical, `4a6b50e7` legacy) was `received, verified and stored`, with the SHA-256 of the stored file equal to the sent one. **PASS both.**

## 7. Not executed — the §4 network compatibility gate (G5 hardware)

The plan's exit criteria require "the §4 matrix executed on hardware with every row observed". None
of it was executed. A physical SM-X620 (API 36) *is* attached to this host (`adb` serial `RX2Y500C7SY`),
and the host *does* run the packaged `omnibridge 1.0.0`. Neither was used, for these reasons:

* The device's installed app has the same `applicationId`. Installing a Wave 5 build would replace the operator's app, possibly with a different signature, and put their pairings at risk. That needs the operator's decision.
* Pairing the Pliwee app with the packaged 1.0.0 daemon writes into the operator's real trust store (`~/.local/share/omnibridge`).
* N3 and N5 need an **OmniBridge app dev build** on a device next to the Pliwee build. N4 depends on W7's G7-UP.

| Row | Status | What an operator must observe (anchor) |
| --- | --- | --- |
| N1 Pliwee daemon ↔ Pliwee app, canonical | **NOT EXECUTED** (manual) | discovery on `_pliwee._tcp`; pairing from `pliwee1:` (the app logs `pair payload-parsed profile=pliwee …` in the host-driven harness); daemon `session established … profile=pliwee alpn=pliwee/1`; clipboard both ways; a file (daemon `transfer=<id>` lines); notifications mirrored and dismissed |
| N2 Pliwee app ↔ packaged OmniBridge 1.0.0 daemon, legacy | **NOT EXECUTED** (manual) | discovery on `_omnibridge._tcp` only; pairing from `omnibridge1:`; the 1.0.0 daemon's own `session established` line; clipboard; a file on `omnibridge-data/1` |
| N3 Pliwee daemon ↔ OmniBridge app dev build | **NOT EXECUTED** (manual; needs that build) | daemon `session established … profile=omnibridge alpn=omnibridge/1` for an existing pairing |
| N4 upgraded daemon ↔ pre-upgrade peer | **NOT EXECUTED**, owned by W7 G7-UP | reconnect without re-pairing |
| N5 OmniBridge app scans a Pliwee QR | **NOT EXECUTED** (manual; needs the old build) | a clean, specific refusal; no crash; documented as unsupported |
| X1–X5 on hardware | **NOT EXECUTED** (manual) | as §5, observed on the device and the daemon log |

Suggested operator procedure: use `HostDrivenCertificationHarness` (its pairing line now names the
profile), and read `journalctl --user` for the daemon's `session established … profile= alpn=` and
`transfer=` lines. Anchor every row on a session or transfer id written during that run.

## 8. Legacy identifiers intentionally preserved

* **The whole legacy profile, pinned as literals next to the canonical one in both languages:** `omnibridge/1`, `omnibridge-data/1`, `_omnibridge._tcp.local.` / `_omnibridge._tcp.`, `omnibridge1`, `omnibridge/pairing-proof/v1`, `omnibridge/pairing-confirm/v1` and `omnibridge/files.v1/data-stream/v1`. Removal is a breaking change (own ADR, major version).
* The legacy KAT values (`d34504e6…`, `fd1689c7…`, `503aaf7d…`), byte for byte.
* `protocol/testdata/identity-{a,b}.der` with `CN=anyflow:…` (D10), and the four SPKI KATs.
* Existing certificates' CNs (`omnibridge:<id>` or older): identities are never regenerated (D12). Only new identities get `pliwee:<id>`.
* Everything owned by later waves, deliberately untouched here:
  * binary and CLI names, and every "Run: omnibridge …" hint (W7);
  * `Discovery`'s multicast-lock tag `omnibridge-discovery` (a W3/W6-era internal tag);
  * the Kotlin package `io.github.yurisismotto.omnibridge` and the Keystore aliases (W6);
  * the TLS server-name placeholder `omnibridge.invalid` in untouched tests (it is ignored by the pinning verifier);
  * the `fake_phone` default directory `/tmp/omnibridge-fake-phone`;
  * the `PairingScanner.Outcome.NotOmniBridgeCode` type name.

## 9. Risks and hand-offs

1. **`packaging/tests/lifecycle-peer-gates.sh:248–251` extracts an `omnibridge1:` payload.** The Wave 5 daemon emits only `pliwee1:`, so this harness will now **abort loudly** ("produced no omnibridge1: payload"). That is a red gate, not a false green. `lifecycle-gates.sh:558–563` (L10) still passes, because the daemon keeps the legacy record, but it no longer observes the canonical record. Both files are W7-owned (`packaging/tests/**`: "lifecycle and peer gates in full under the new names"). They were not edited here, because this host cannot run them to prove an edit. **W7 must update both** (L10 should assert *both* types).
2. **Legacy peers after an app restart.** `PeerProfiles` is memory-only by design, so the first dial to an OmniBridge 1.0.0 desktop after a restart is canonical. It fails at the handshake (observed in §6.2) and is retried, and the next round's discovery switches the profile. That costs one extra reconnect round. If discovery is unavailable (no multicast), a legacy-only peer reachable only by a remembered address cannot be reached until it is re-paired from its `omnibridge1:` code. The trade-off is ADR-0020's rule ("not persisted as trust"). It should be measured in N2.
3. **Notification ids re-key** in this build, because only canonical domains are used. On a device that runs this Wave 5 build over the existing OmniBridge app (same `applicationId` until W6), mirrored notifications get new ids once. ADR-0020 expects the re-key at the D1 app change. During W5–W6 development builds it happens one wave earlier. The effect is cosmetic (one reconciliation), never a security effect.
4. **`UnsupportedVersion` is not surfaced in the Android UI.** The scanner still shows its generic "not a pairing code" outcome for `pliwee2:`/`omnibridge2:`. The parser distinguishes the cases, and the matrix tests pin it. A specific message is copy work, not wire work.
5. **The daemon suites' second run** is selected by `PLIWEE_TEST_PROFILE`. CI (`.github/workflows`, W7-owned) runs them once, canonical by default. W7 should add the `omnibridge` run so that the "run twice" requirement is enforced in CI, not only in this report.

## 10. Gate verdict

| Exit criterion | Status |
| --- | --- |
| Unit, negative and KAT suites green in both languages | **PASS** (§4, §5) |
| Frozen-vector digests match | **PASS** (§2) |
| §4 matrix executed on hardware with every row observed | **NOT EXECUTED** (§7) |
| G5 — "every negative test rejects; every compatibility row is observed through a product-written anchor" | negatives: **PASS**. Compatibility rows N1–N5: **NOT EXECUTED**. |

**Wave 5 result: BLOCKED_MANUAL.** The implementation is complete as far as automation can go. The
remaining gate is the operator's §4 hardware matrix.
