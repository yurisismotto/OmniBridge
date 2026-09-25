# ADR-0020 — Rename to Pliwee

Status: **Accepted (2026-09-24) · not yet implemented.** Decisions D1–D12
approved by the project owner on the evidence of
[`audits/rebrand/PLIWEE-REBRAND-DISCOVERY.md`](../audits/rebrand/PLIWEE-REBRAND-DISCOVERY.md)
(branch `worktree-pliwee-rebrand-discovery`, audit commit `be70911`, tree
audited at `ba408c6`).

**Relationship to earlier ADRs.**

* **Supersedes** [ADR-0018](ADR-0018-rename-to-omnibridge.md)'s identifier
  tables and its rule "no compatibility aliases and no dual-stack support",
  from the commit that implements this ADR. Until then ADR-0018's values are
  what the tree carries.
* **Amends** [ADR-0019](ADR-0019-android-app-signing.md): the custody model
  stands; the identity it provisioned is retired before first use and a Pliwee
  identity is provisioned under the same procedure (§D3).
* **Amends the quoted values, not the constructions,** of
  [ADR-0005](ADR-0005-lan-discovery-mdns.md) (service type),
  [ADR-0006](ADR-0006-device-identity-and-pairing.md) (QR prefix, identity
  path), [ADR-0007](ADR-0007-tls-transport-and-pinning.md) (ALPN),
  [ADR-0013](ADR-0013-file-transfer-data-stream.md) (data ALPN, data-stream
  domain) and [ADR-0016](ADR-0016-notification-identity.md) (notification
  domains).
* [ADR-0011](ADR-0011-project-naming-and-wire-identifiers.md) is already
  historical; it is not touched again. Its reasoning about dead names in
  security constants is reused in §D4.

Nothing in this ADR changes code, identifiers, keys, certificates, CI, URLs
or the repository remote. Every "is" in the tables below is the **canonical
target** the implementation must reach; every "was" is what the tree carries
today.

---

## Context

The product has been renamed twice: *Fedroid Bridge → AnyFlow* (ADR-0011) and
*AnyFlow → OmniBridge* (ADR-0018). Both times everything was renamed,
including wire identifiers and HMAC domain separators, with no compatibility,
because nothing had been released.

**That premise is false for this rename.** Three facts from the discovery
audit decide the shape of this ADR:

1. **Linux v1.0.0 is public.** `yurisismotto/OmniBridge` release `v1.0.0`
   (published 2026-09-24T03:45:55Z, not draft, not prerelease) ships 14
   signed Linux artifacts, all named `omnibridge*`, with 1–5 downloads each at
   audit time. Each install may hold a device identity and a trust store under
   `~/.local/share/omnibridge/`. The installed base is small, non-zero and
   unknowable.
2. **Android has not shipped.** No APK or AAB is attached to `v1.0.0` in this
   repository or in `yurisismotto/omnibridge-history`; no Play Console app
   exists (PLAY18 not reached); the repository carries no F-Droid, Obtainium
   or IzzyOnDroid metadata. The only release-signed install on record is the
   maintainer's own test tablet (Samsung SM-X620,
   [`ANDROID-PLAY-V1-RELEASE-SMOKE.md`](../reports/android/ANDROID-PLAY-V1-RELEASE-SMOKE.md),
   signed by the *upload* key).
3. **Protobuf names never reach the wire** (no `Any`, no type URLs), and the
   capability ids (`battery.v1`, `clipboard.v1`, `files.v1`,
   `notifications.v1`), the TCP port `55432` and the mDNS TXT keys (`v`, `id`,
   `dn`) carry no brand.

---

## Decision

### Three layers, kept apart (D2)

The rename touches three kinds of name. They change for different reasons,
carry different risks, and must not be changed by one search-and-replace.

| Layer | What it is | Who sees it | Rule |
| --- | --- | --- | --- |
| **Visual identity** | product name, tagline, artwork, UI copy, store listing | users | changes freely; §D8 |
| **Code namespace** | Rust crates, Kotlin packages, Gradle project, type names, generated proto packages | developers | changes freely **except** where a code name is also an OS-persisted identifier (Android component names, §"Android component identity") |
| **Persistent and wire identifiers** | `applicationId`, desktop app id, D-Bus name, paths, systemd/firewalld names, Keystore aliases, ALPN, mDNS, QR, domain separators | the OS, the network, other installs | change only with a specified migration or compatibility rule — this ADR |

**Canonical reverse-DNS root: `io.github.yurisismotto.pliwee`**, used wherever
a reverse-DNS name is technically applicable:

| Use | Was | Is |
| --- | --- | --- |
| Android `applicationId` | `io.github.yurisismotto.omnibridge` | **`io.github.yurisismotto.pliwee`** (D1) |
| Android `namespace` / Kotlin root package | `io.github.yurisismotto.omnibridge` | **`io.github.yurisismotto.pliwee`** |
| Notification fixture `applicationId` (test only) | `…omnibridge.fixture` | **`…pliwee.fixture`** |
| Protobuf `java_package` | `io.github.yurisismotto.omnibridge.proto[.capabilities]` | **`io.github.yurisismotto.pliwee.proto[.capabilities]`** |
| Desktop application id — GApplication id, **D-Bus well-known name**, `.desktop` basename, `Icon=`, hicolor icon name, AppStream `<id>`, SNI `Id`/`IconName`, desktop-notification app id | `io.github.yurisismotto.omnibridge` | **`io.github.yurisismotto.pliwee`** — still one string, as ADR-0018 required |
| D-Bus object path / GResource prefix | `/io/github/yurisismotto/omnibridge` | **`/io/github/yurisismotto/pliwee`** |
| Intent actions | `io.github.yurisismotto.omnibridge.{STOP,APPLY_CLIP,SEND_CLIPBOARD,CLIPBOARD_REQUEST_ID}` | **`io.github.yurisismotto.pliwee.*`** |

The `io.github.<owner>` form keeps ADR-0011's reasoning: it is backed by an
account the project controls, and it agrees with the new repository
`github.com/yurisismotto/pliwee` (D5) — which Flathub-style `io.github` ids
expect.

### D1 — Android `applicationId`

**`io.github.yurisismotto.pliwee`.** It is set before the Play Console app is
created, and from that moment it is **permanent**: Play takes the package from
the first upload and never lets it change.

Consequences that follow from Android, not from choice:

* A new `applicationId` is a **new app**: new private storage, new Keystore,
  new permission grants. Nothing of an OmniBridge Android install — identity
  key, trust store, notification secret, grants — can be migrated into it: the
  identity key is non-exportable and lives in another app's Keystore
  (ADR-0018 §Identity; ADR-0006). This is acceptable **only** because no
  OmniBridge Android build was ever distributed (Context, fact 2). It is
  recorded here so that the D11/D12 guarantees below are never read as
  covering Android.
* Keystore aliases **restart at v1** under the new app, exactly as ADR-0018
  did: `pliwee-identity-v1`, `pliwee-notification-secret-v1`. There is no
  sweep of `omnibridge-*` aliases: the new app cannot see them.
* The readiness audit's 2026-09-30 note is a **package-name squatting**
  concern ("create the Play app for this exact package before … 2026-09-30 if
  anyone else could plausibly claim it"), not a hard gate. This ADR sets no
  date; it sets the **order**: identity decided (done here) → implemented and
  certified → Play app created for `io.github.yurisismotto.pliwee`.
* [`ANDROID-PLAY-V1-DECLARATIONS.md`](../audits/android/ANDROID-PLAY-V1-DECLARATIONS.md)
  PLAY14 says the package "must be `io.github.yurisismotto.omnibridge`". It is
  evidence and is not edited; the implementation adds a dated superseding note
  pointing here.

### D3 — Android signing identity

**A new Pliwee production signing identity is provisioned before the Play app
is created. The OmniBridge identity from ADR-0019 is retired unused and
preserved, never overwritten.**

**Blocker check — no blocker.** ADR-0019's model is "every installed copy is
bound for life to the certificate that signed it". Replacing the key would be
a blocker only if some external distribution needed an in-place update signed
by the OmniBridge key. The repository shows none: no APK/AAB in either
release, no store metadata, no Play app, and the one release-signed install is
the maintainer's test tablet, signed by the *upload* key, under the
`applicationId` that D1 abandons anyway. If that evidence is contradicted
before implementation — an OmniBridge-signed APK is found to have been handed
to anyone — this decision stops and becomes a BLOCKER for re-decision.

| | OmniBridge (ADR-0019) — retired | Pliwee — to provision |
| --- | --- | --- |
| App signing subject | `CN=OmniBridge, OU=Android App Signing` | `CN=Pliwee, OU=Android App Signing` |
| Upload subject | `CN=OmniBridge, OU=Android Upload` | `CN=Pliwee, OU=Android Upload` |
| Aliases | `omnibridge-app-signing`, `omnibridge-upload` | `pliwee-app-signing`, `pliwee-upload` |
| Public record | `android/signing/certs/*.pem`; SHA-256 `AB:B6:2F:53:…:AC:49` / `75:FC:88:B5:…:BA:47` | new files; fingerprints recorded in an ADR-0019 addendum |
| Local custody paths | `~/.local/share/omnibridge-android-signing/`, `~/.local/state/omnibridge-android-signing/PROVISIONED` | `~/.local/share/pliwee-android-signing/`, `~/.local/state/pliwee-android-signing/PROVISIONED` |

Rules:

* Algorithm, validity, the two-key split, offline custody, the verified
  two-medium backup and the "no private material in the repository or CI"
  rules of ADR-0019 are unchanged. Only the subject, aliases and paths change.
* ADR-0019's refusal — "it refuses to run once `PROVISIONED` exists: a second
  app signing key would be a second app" — is **kept**, and is read as *one
  signing identity per `applicationId`*. The Pliwee provisioning uses its own
  record path, so it neither trips nor erases the OmniBridge record, and a
  second Pliwee provisioning is still refused.
* The OmniBridge certificates stay committed **byte-identical** (a `git mv` to a
  legacy location is allowed; overwriting is not). The OmniBridge offline
  backups and password-manager entries are kept. The OmniBridge keys never
  sign a Pliwee artifact and are never supplied to Play.
* `verify-release-bundle.sh` must expect exactly one signer whose certificate is
  the **Pliwee** upload certificate and the package `io.github.yurisismotto.pliwee`.
* No key is generated by this ADR.

### D4 — Wire, protocol and cryptographic identifiers

**Pliwee has its own canonical identifiers. Pliwee always emits them. During
the Pliwee v1.x line, Pliwee also accepts the OmniBridge identifiers where
this section says it is safe, and nowhere else.**

#### Canonical values

| Identifier | Was (legacy profile) | Is (canonical profile) | Where today |
| --- | --- | --- | --- |
| Control ALPN | `omnibridge/1` | **`pliwee/1`** | `desktop/core/src/lib.rs:44`, `net/PinnedTrustManager.kt:123` |
| Data-stream ALPN | `omnibridge-data/1` | **`pliwee-data/1`** | `lib.rs:56`, `PinnedTrustManager.kt:134` |
| mDNS / NSD service type | `_omnibridge._tcp.local.` | **`_pliwee._tcp.local.`** | `lib.rs:59`, `net/Discovery.kt:162` |
| QR payload scheme | `omnibridge1:` | **`pliwee1:`** | `core/src/qr.rs:31`, `pairing/QrPayload.kt:29` |
| Pairing proof domain | `omnibridge/pairing-proof/v1` | **`pliwee/pairing-proof/v1`** | `core/src/pairing.rs:52`, `pairing/PairingProof.kt:29` |
| Pairing confirm domain | `omnibridge/pairing-confirm/v1` | **`pliwee/pairing-confirm/v1`** | `pairing.rs:53`, `PairingProof.kt:31` |
| `files.v1` data-stream domain | `omnibridge/files.v1/data-stream/v1` | **`pliwee/files.v1/data-stream/v1`** | `capabilities/files/src/auth.rs:63`, `files/StreamAuth.kt:38` |
| `notifications.v1` id / group / content domains | `omnibridge/notifications.v1/{id,group,content}/v1` | **`pliwee/notifications.v1/{id,group,content}/v1`** | `notifications/NotificationIdentity.kt:41-47` (Android only) |
| Certificate subject CN (new identities) | `omnibridge:<device-id>` | **`pliwee:<device-id>`** | `core/src/identity.rs:143`, `identity/DeviceIdentity.kt:138` |
| Protobuf package / directory | `omnibridge.v1[.capabilities]`, `protocol/proto/omnibridge/v1/` | **`pliwee.v1[.capabilities]`**, `protocol/proto/pliwee/v1/` | 6 schemas |

Unchanged, because they carry no brand: capability ids, TCP `55432`, mDNS TXT
keys, every protobuf field number and type, and every construction — framing,
envelope, fingerprint, proof, HMAC-SHA256, length prefixing, token size, TTL,
attempt limit, confirmation gate, TLS 1.3, ECDSA P-256, SPKI pinning.

#### The profile rule — no hybrid states

A connection runs under exactly one **identity profile**: `pliwee`
(canonical) or `omnibridge` (legacy). The profile is decided **once**, by the
ALPN the TLS handshake negotiates, and every brand-bearing value used on that
connection is derived from it. Nothing is ever tried "under both".

* The listener offers, in preference order, `pliwee/1`, `pliwee-data/1`,
  `omnibridge/1`, `omnibridge-data/1`, and maps the negotiated value to
  *(profile, control | data)* — an extension of today's `NegotiatedProtocol`
  (`desktop/core/src/tls.rs:374`).
* A client offers the profile it intends to use. A Pliwee client that knows
  the peer only as legacy (discovered on `_omnibridge._tcp`, or paired from an
  `omnibridge1:` QR) offers the legacy ALPN; otherwise the canonical one.
* A data-stream connection must negotiate **the same profile** as the control
  session that issued its transfer credential; a mismatch is refused, not
  translated.
* A proof, confirmation or data-stream MAC is verified under the negotiated
  profile's domain only. A value that would verify only under the other
  profile's domain is a failure. There is no fallback verification.

This keeps security intact: ALPN is inside the TLS 1.3 transcript, so an
on-path attacker cannot rewrite the negotiated profile without failing the
handshake; peers are SPKI-pinned; and the two profiles share one construction,
so selecting the legacy profile is a change of label, not a weaker algorithm.
What must never exist is a peer that is discovered under one name and
authenticated under another — which is why mDNS, ALPN, QR and the pairing and
data domains are one unit and are never renamed separately.

#### What may be dual-accepted, and what may not

| Identifier | Pliwee emits | Pliwee v1.x accepts | Mechanism / limit |
| --- | --- | --- | --- |
| mDNS | advertises `_pliwee._tcp` **and** `_omnibridge._tcp` (same instance data) | browses both; deduplicates by TXT `id` and pinned fingerprint | the legacy advertisement is what lets an un-upgraded OmniBridge v1.0.0 peer still see a Pliwee daemon |
| Control / data ALPN | canonical first | legacy | profile rule |
| QR scheme | **`pliwee1:` only** | parses `pliwee1:` and `omnibridge1:` | the QR's scheme selects the profile for the pairing connection. An OmniBridge build **cannot** scan a Pliwee QR — unsupported, stated, not worked around by emitting legacy QRs |
| Pairing proof / confirm domains | per profile | per profile | profile rule; pairing is a one-time act, so this matters only while pairing |
| `files.v1` data-stream domain | per profile | per profile | profile rule |
| `notifications.v1` domains | **canonical only** | n/a | computed only on Android; the desktop treats ids as opaque (ADR-0016). Switching re-keys ids once, at the app change D1 already forces. No dual form is needed, so none is built |
| Certificate CN | `pliwee:<id>` for **new** identities only | any — the CN is never parsed; trust is SPKI-pinned | existing identities are **never** regenerated to change their CN (D12) |
| Protobuf package | renamed | n/a | not on the wire; source-only rename |

**Who the legacy profile serves.** Un-upgraded OmniBridge **v1.0.0 Linux
daemons**, which a Pliwee Android app must be able to discover, pair with
(from their `omnibridge1:` QR) and use, and any OmniBridge development build.
Because no OmniBridge Android build exists outside test hardware, the
daemon-side acceptance is kept for symmetry and simplicity, not because a
population depends on it.

**Removing the legacy profile is a breaking change.** It does not happen
silently or within Pliwee v1.x. It requires its own ADR and a major version.
Until then, the legacy values are pinned as literals in the wire-identity
tests on both sides, next to the canonical ones, so neither can drift.

**OmniBridge is not a permanent canonical identity.** The legacy profile is an
acceptance path with an end, not a second name for the protocol.

### D5 — Repository

A **new** repository, `github.com/yurisismotto/pliwee`, is created **after**
Pliwee is implemented and certified in this repository. Renaming
`yurisismotto/OmniBridge` is not the primary strategy.

`yurisismotto/OmniBridge` stays **available** — archived / read-only, never
deleted, never re-purposed — with a notice that the project continues as
Pliwee, so that:

* the v1.0.0 release, its assets, `SHA256SUMS`, `SHA256SUMS.asc` and the
  public key keep their URLs;
* the README install commands and verification instructions already copied by
  users keep resolving;
* the privacy-policy URL compiled into the current Android sources keeps
  resolving (§Privacy policy).

`yurisismotto/omnibridge-history` is left untouched.

**Public-URL rule.** No URL that has been compiled into a distributed binary,
declared to a store, or published in a release may be invalidated without a
redirect or a compatibility copy at the old location. Archiving preserves
reads; deleting or renaming the old repository would break the rule.

### D6 — Release OpenPGP key

The key `F545DC184E909192C3FB6F6E64963019E731BE07` (signing subkey
`E8EDE4706F067739A8D3A8B74C48CB81694FD134`) **remains the release trust
root.** No new key is created for the rename.

* At the operational phase a UID **`Pliwee Release Signing Key`** is added to
  the existing key and published. The UID **`OmniBridge Release Signing Key`**
  is kept and **not revoked**.
* `packaging/release/verify-release.sh` checks the fingerprint, not the UID
  (`--fingerprint`, lines 158–182), so adding a UID changes no verification
  result. The gate for this step: the same `v1.0.0` `SHA256SUMS.asc` verifies
  against the updated public key, and a Pliwee release verifies against the
  same fingerprint.
* Release artifacts are named `pliwee-<V>…` from the first Pliwee release;
  the `v1.0.0` `omnibridge*` assets are immutable evidence and are never
  renamed or re-uploaded.

### D7 — Historical documentation

Historical documents are not rewritten. `Fedroid Bridge`, `AnyFlow` and
`OmniBridge` stay wherever they record a fact, a decision, a version, a
measurement or an audit — including every file under `docs/audits/`,
`docs/certification/`, `docs/reports/`, `docs/research/`, `docs/migrations/`
and ADR-0001 … ADR-0019. AGENTS.md § "Historical documents are evidence"
governs: a later change is recorded as a **dated superseding note** that names
this ADR, with the original text left standing beneath it.

Living, normative documentation — README, AGENTS.md, `docs/README.md`,
`docs/architecture/`, `docs/design/`, `docs/policy/`, `docs/security/`,
component READMEs — uses **Pliwee**, and may carry a one-line note of the
former names.

### D8 — Visual identity

| | |
| --- | --- |
| **Name** | **Pliwee** — not translated |
| **Tagline** | **One flow. Any device.** |
| **Symbol** | the **Flow Monogram**, as drawn on the owner-supplied Pliwee board |
| **Wordmark** | Pliwee |
| **Typeface** | Inter |
| **Palette** | Primary Blue `#4F6BFF` · Flow Cyan `#18B8C9` · Accent Violet `#7C5CFC` · Dark `#0B1020` · Surface `#F7F9FC` |
| **Not the logo** | the alternative "Connected Nodes" concept |

* The owner-supplied board is the canonical reference. The symbol's geometry
  is **not reinterpreted, redrawn or retraced** during implementation; every
  platform derivative is produced from one approved source file committed to
  `docs/design/assets/`, as the existing build already does with
  `omnibridge-app-icon.svg`. The existing outline-equality tests are the
  mechanism that keeps it so.
* The palette hex values equal the current ones in
  [`BRAND.md`](../design/BRAND.md); "Bridge Cyan" is renamed **Flow Cyan**.
  The accessibility-derived text tones (`#10747E`, `#445CDD`, `#6A49EE`, …) are
  derived from these and are not changed by this ADR.
* **Known collision.** The tagline is AnyFlow's former tagline (ADR-0011:
  *One flow. Any device.*), and the active dead-identity tests reject it:
  `desktop/gui/tests/brand_assets.rs:323` fails on `"one flow"` (and on
  `"flow a"`, `"flow-a"`, `"flow_a"`) in any active asset;
  `BrandingResourcesTest.kt:283` rejects `flow_a`, `flow-a` and `flowing` in
  resource names. The implementation **changes these lists deliberately**, in
  the same commit that installs the Pliwee lockup: `"one flow"` leaves the
  dead list, `"one bridge"` and `"omnibridge"` join it. Asset and resource
  names for the Flow Monogram must avoid the retired `flow-a`/`flow_a`/`flowing`
  names rather than weaken those checks. This is a recorded re-adoption, not a
  gate relaxed to pass.
* No asset is created by this ADR.

### D9 — Paths and directories

New installations use Pliwee names only. OmniBridge paths are **legacy
sources** for migration and compatibility, never canonical.

**Invariant (the identity rule).** *The absence of a Pliwee directory is never,
by itself, a reason to create a new identity.* Before generating an identity,
the daemon checks the legacy location. If legacy state exists but cannot be
read, that is an **error** that stops startup and names the path — never "first
run" — which is exactly the "absent vs unreadable" contract of
`desktop/core/src/secret_store.rs`.

| Class | Legacy (OmniBridge) | Canonical (Pliwee) | Migration |
| --- | --- | --- | --- |
| Data / state (identity + trust store) | `$XDG_DATA_HOME/omnibridge/` → `~/.local/share/omnibridge/` (`identity.key`, `state.json`) | `…/pliwee/` | **copy** into the new directory (0700 dir, 0600 files, write-then-rename, fsync) when the new one holds no identity; never overwrite a populated Pliwee directory; never move or delete the legacy one |
| Config | `$XDG_CONFIG_HOME/omnibridge/gui.json` | `…/pliwee/gui.json` | copy on first GUI start, same rules |
| Runtime / socket | `$XDG_RUNTIME_DIR/omnibridge/control.sock`, fallback `/tmp/omnibridge-<uid>` | `…/pliwee/control.sock`, `/tmp/pliwee-<uid>` | none — volatile; daemon and clients ship together |
| Cache | none exists | if ever introduced: `$XDG_CACHE_HOME/pliwee` | — |
| Logs | none on disk (stderr / journald by unit) | journald under the Pliwee unit | — |
| Received files, desktop | `~/Downloads/OmniBridge/` | `~/Downloads/Pliwee/` | new files go to Pliwee; existing files are user data and are **never moved or deleted**; stale `.omnibridge-*.part` files may be listed, never silently removed |
| Received files, Android | `Download/OmniBridge` (MediaStore) | `Download/Pliwee` | same; and a new `applicationId` cannot reach the old app's MediaStore entries anyway |
| Android private state | `filesDir/trust-store.json`, Keystore aliases of `…omnibridge` | same file name, aliases `pliwee-*-v1` under `…pliwee` | **impossible** by Android sandboxing (D1); none attempted |
| System integration | §"Legacy systemd, firewalld and desktop integration" | | |
| Env vars | `OMNIBRIDGE_*` (build, release, harness only — no product binary reads one) | `PLIWEE_*` | none — operator runbooks change in the same commit |

After a successful copy the legacy directory is left intact, which keeps a
downgrade to OmniBridge v1.0.0 possible for state that existed at the moment
of migration. Pairings made afterwards exist only in the Pliwee directory;
that asymmetry is documented, not solved.

### D10 — Frozen test vectors

`protocol/testdata/identity-a.der` and `identity-b.der` (subject
`CN=anyflow:cdf2f27e…` and `CN=anyflow:8408ff88…`) and the known-answer
constants derived from them in both languages are **frozen**. They are not
regenerated to remove a historical name. Legacy-profile domain KATs are also
kept byte-for-byte, because under D4 the legacy profile is live code in v1.x.

Pliwee-profile domain KATs are **added beside** them, computed independently
from the construction as documented — as ADR-0018 did — never by copying what
the implementation emits. New identity vectors, if ever wanted, are new files.

### D11 — Compatibility windows

Two classes, with different windows:

| Class | Window | Removal |
| --- | --- | --- |
| **Local state and identity** (D9 migration, legacy-path detection) | **Durable.** Kept for as long as a supported upgrade path from OmniBridge exists; not tied to v1.x. A Pliwee install must never forget an identity or a pairing because the old directory is still called `omnibridge`. | only by an explicit ADR that names the last supported upgrade source |
| **Wire / protocol** (D4 legacy profile) | **the Pliwee v1.x line**, for the identifiers marked accepted in D4's table | a breaking change: its own ADR + a major version |
| **System integration** (legacy unit, firewalld service) | at least the whole Pliwee v1.x line | release notes + ADR amendment |

The ADR deliberately **does not promise**: that an OmniBridge Android build
can pair with or reach a Pliwee daemon via a Pliwee QR; that any OmniBridge
Android state survives (D1); that notification ids stay stable across the D1
app change; or that pairings made after migration are visible to a downgraded
OmniBridge.

### D12 — Upgrading a Linux OmniBridge v1.0.0 install

**Mandatory.** An OmniBridge v1.0.0 Linux install upgraded to Pliwee keeps,
when they exist: the device identity and its key (so its **fingerprint is
unchanged**), the device id, every trusted peer and its pinned SPKI, every
capability grant, clipboard and notification policies, revocation tombstones,
and the GUI's peer selection — i.e. the entire contents of `identity.key`,
`state.json` and `gui.json`. There is no other secret on the desktop: the
secret store is file-backed and has no keyring entry (audit §6).

This preserves **state**, not names: the preserved state lives under Pliwee
paths and is used by Pliwee binaries under Pliwee identifiers.

**Peer-side boundary, stated so it is not misread.** A pairing between that
desktop and an OmniBridge *Android* build survives on the desktop, but the
phone side cannot (D1); after the phone moves to Pliwee the desktop meets a
new device. Pairings with peers whose own identity survives — another Linux
install upgraded under D12 — survive on both ends.

### Legacy systemd, firewalld and desktop integration

The implementation provides **explicit and idempotent** migration; running it
twice changes nothing the second time.

* **systemd.** A user who ran `systemctl --user enable --now omnibridged.service`
  must, after upgrading, have the Pliwee daemon running at the next login —
  the enablement symlink lives in `~/.config/systemd/user/` where no package
  scriptlet may write, so it cannot simply vanish with the old unit file.
  Invariants: **exactly one** daemon runs (two would contend for port 55432 and
  the control socket); enabling, disabling and stopping work under the Pliwee
  name; a user who never enabled the service does not get it enabled. The
  mechanism (a compatibility `omnibridged.service` shipped through v1.x, a
  daemon-side detection with an exact instruction, or both) is chosen by the
  implementation and measured by `packaging/tests/lifecycle-gates.sh` on all
  four distributions.
* **firewalld.** `pliwee.xml` is installed beside `omnibridge.xml` (same single
  port, TCP 55432); the legacy file stays through v1.x so a zone that names
  `omnibridge` still reloads. No scriptlet ever edits a zone — unchanged from
  today.
* **Packages.** `pliwee` / `pliwee-gui` replace `omnibridge` / `omnibridge-gui`
  as a normal upgrade: RPM `Obsoletes:` + `Provides:`, Debian `Replaces:` +
  `Breaks:` + `Provides:` (a transitional package if needed). The first Pliwee
  release is a 1.x version above 1.0.0.
* **Desktop integration.** The `.desktop` file, D-Bus activation file,
  AppStream file and icon move to the new id. What the desktop keyed by the old
  id — dock favourites, per-app notification settings, tray visibility — is
  **reset and documented**; the package does not edit per-user desktop
  settings. Leftover development-install files (`install-desktop-metadata.sh`)
  get a documented removal step, as the AnyFlow migration note did.

### Android component identity

**Keeping the `applicationId` stable would not be enough, and the
`applicationId` is changing anyway.** Android persists state against
`ComponentName`s — package **plus class name** — not against the app alone:

| Component | Current `android:name` | What Android keys by it |
| --- | --- | --- |
| Notification listener | `.notifications.OmniBridgeNotificationListener` | the user's notification-access grant |
| Quick Settings tile | `.ui.ClipboardTileService` | the tile's slot in the user's panel |
| Launcher activity | `.ui.MainActivity` | pinned icons, shortcuts |
| Share target | `.ui.SendActivity` | direct-share ranking |

For the **D1 transition itself** nothing is preserved regardless (new app), so
the Pliwee component names are chosen freely. The rule applies **from the
first Pliwee release onwards**: once a Pliwee build is distributed, its
manifest component names are **frozen identifiers**. A later package or class
rename must keep the old `ComponentName` (a stable subclass or
`activity-alias`) or be treated as a breaking change. The gate: the component
names are read back from the **built APK** with `aapt2` and pinned in a test,
as the rebrand remainder audit already did for OmniBridge.

### Privacy policy

The current Android sources compile
`https://github.com/yurisismotto/OmniBridge/blob/main/docs/policy/PRIVACY-POLICY.md`
(`ui/PrivacyPolicy.kt:16`). Under D5 that URL keeps resolving because the
repository is archived, not deleted. The public-URL rule (D5) applies to it.

The **Pliwee** app compiles and declares to Play a privacy-policy URL that
must resolve **on the day the first Pliwee build is uploaded** and must not
depend on a repository that does not yet exist. Where it lives is an open
question below.

---

## Required gates before the Pliwee rebrand is certified

Each is a gate in the AGENTS.md sense: it fails when its precondition is
absent, it anchors on something the product wrote about this run, and it
asserts a change with two observations.

1. **Wire identity, both languages.** Canonical and legacy values pinned as
   literals in `desktop/core/tests/wire_identity.rs` and
   `WireIdentityTest.kt`; dead list `anyflow`, `fedroid`.
2. **Profile integrity.** A proof, confirmation or data-stream MAC produced
   under one profile is rejected on a connection negotiated under the other; a
   data stream whose profile differs from its control session is refused.
3. **KATs.** Pliwee-profile domain vectors computed independently; legacy
   vectors and the frozen DERs byte-identical (D10).
4. **Interop.** A Pliwee Android build discovers, pairs with (from an
   `omnibridge1:` QR) and exchanges clipboard and a file with an unmodified,
   **packaged OmniBridge 1.0.0** daemon; and with a Pliwee daemon on the
   canonical profile.
5. **Linux v1.0.0 upgrade (D12).** From the real `v1.0.0` packages on each of
   Fedora 44, Ubuntu 24.04, Ubuntu 26.04 and Debian 13: fingerprint, device id,
   exact trusted-peer count, grants and policies observed before and after
   upgrade and asserted equal; the legacy directory byte-identical afterwards;
   a second start changes nothing.
6. **Unreadable legacy state.** Legacy directory present but unreadable → the
   daemon refuses to start and names the path; no Pliwee identity is created.
7. **Service continuity.** Enabled-before-upgrade → running after re-login,
   exactly one daemon process; never-enabled stays disabled; a zone naming
   `omnibridge` still reloads.
8. **Android components.** Manifest component names read from the built APK and
   pinned.
9. **Artwork.** Every derivative carries the approved Flow Monogram outline
   byte-for-byte; dead lists amended as D8 states.
10. **Release trust.** `v1.0.0` and the first Pliwee release both verify
    against fingerprint `F545DC18…` (D6).

---

## Consequences

* The rename is no longer a clean break. It carries a legacy wire profile
  through v1.x and a durable state migration, which is more code than ADR-0018
  needed — the price of a public v1.0.0.
* Every Android development pairing breaks once (new app, new identity), as
  under ADR-0018. Linux pairings do not.
* The OmniBridge Android signing identity of ADR-0019 is retired without ever
  having signed a distributed build; its records stay as evidence.
* The public trust anchor for releases does not change.
* A grep for `omnibridge` in active code will legitimately hit the legacy
  profile, the legacy paths and the compatibility integration files during
  v1.x. The next remainder audit classifies each; any other hit is a bug.
* `yurisismotto/OmniBridge` becomes a permanent read-only dependency of every
  URL already published.

## Open questions

Only these block part of the implementation; everything else above is decided.

1. **Privacy-policy location for the Pliwee app.** Which URL is compiled into
   the first Pliwee build and declared to Play, given that the Pliwee
   repository is created only after certification (D5)? It must resolve
   before the first upload and survive the later repository move. Blocks the
   `PrivacyPolicy.kt` change and the Play listing, not the rest.
2. **The canonical Flow Monogram source file.** The board is the reference,
   but the implementation needs the approved vector master (SVG) and its
   monochrome form to derive from; the artwork step (and the Play graphics
   and screenshots after it) cannot start without it.

   > **Resolved 2026-09-24.** The canonical Flow Monogram source is
   > `docs/design/assets/pliwee-mark.svg` (with `-mono`, `-tonal`,
   > `pliwee-wordmark.svg` and `pliwee-lockup.svg`). It is a controlled vector
   > reconstruction of the owner-supplied board that received final human
   > brand approval at commit `1ea65e6`, and it is frozen. See
   > [`BRAND.md`](../design/BRAND.md#pliwee-vector-masters).

## Unresolved risks (not blocking)

* **Package-name claim window.** The Play app for
  `io.github.yurisismotto.pliwee` is created only after certification; until
  then the name is unregistered. The `io.github.<owner>` form makes a third-
  party claim unlikely, but the operator may choose to create the Play app
  earlier. Creating it does not upload anything and does not fix the signing
  key, which is supplied later through PEPK.
* **Unknown Linux installed base.** Download counts show a handful of
  installs; none can be contacted. D12's gate is the only protection they
  have, so it runs against the real `v1.0.0` packages, not a simulation.
* **Desktop-settings resets** keyed by the old app id (dock favourites,
  notification settings, tray visibility) are accepted losses, documented but
  not prevented.
* **Downgrade asymmetry** after state migration (D9).
* **Version bounds.** Package `Obsoletes`/`Breaks` bounds are written against
  the first Pliwee version number, chosen at release time.

---

## Implementation amendments

Added after acceptance and appended here, never edited into the text above
(D7, AGENTS.md § "Historical documents are evidence"). Each one names its date,
its branch and the measurement behind it. The text it amends stays standing
where it is.

### A1 (2026-09-25) — The first Pliwee version is **1.1.0**

*Owner decision, approved 2026-09-25 for the pre-Wave-8 remediation
(`feature/pliwee-rebrand-w8-remediation`).* This resolves plan decision **B4**
and the risk "Version bounds" under *Unresolved risks* above.

* The first Pliwee version is **1.1.0**. It satisfies §"Legacy systemd,
  firewalld and desktop integration" ("a 1.x version above 1.0.0").
* Rebrand Wave 7 had already written 1.1.0 into the tree **provisionally**
  (`desktop/Cargo.toml` `[workspace.package]`, the RPM spec, `debian/changelog`,
  the metainfo `<release>`, and `FIRST_PLIWEE_VERSION` in
  `packaging/tests/packaging-checks.sh`). Every transition bound is written
  against that literal, and `packaging-checks.sh` asserts that it is above
  1.0.0 and not above the workspace version. The approval changes no value.
  It turns "provisional" into "decided".
* Nothing is published by this amendment. The metainfo `<release>` stays
  `type="development"` until Wave 10 publishes it.

### A2 (2026-09-25) — RPM transition: a transitional `omnibridge` package, **not** `Obsoletes:` on the core package

*Owner decision, approved 2026-09-25 for the pre-Wave-8 remediation, on
Wave 7's measurement.* This amends the **Packages** bullet of §"Legacy systemd,
firewalld and desktop integration", which reads *"RPM `Obsoletes:` +
`Provides:`"*, for the **core** package only.

**What is decided.**

| Package | Mechanism | Unchanged from the text above? |
| --- | --- | --- |
| `omnibridge` (RPM) → `pliwee` | a **transitional `omnibridge` 1.1.0** that `Requires: pliwee`, carries no files, and is an ordinary *upgrade* of `omnibridge` 1.0.0. `pliwee` carries **no** `Obsoletes: omnibridge` | **amended** |
| `omnibridge-gui` (RPM) → `pliwee-gui` | `Obsoletes: omnibridge-gui < 1.1.0` + `Provides: omnibridge-gui = %{version}-%{release}` | as written |
| `omnibridge`, `omnibridge-gui` (Debian) | `Replaces:` + `Breaks: … (<< 1.1.0~)`, plus transitional 1.1.0 packages, which the text above already allowed ("a transitional package if needed") | as written |

**Why: measured, not preferred.** The published OmniBridge 1.0.0 RPM's `%preun`
is `%systemd_user_preun omnibridged.service`. When the package is **erased**
(`$1 = 0`), that runs `systemd-update-helper remove-user-units`, which runs
`systemctl --user disable --now` for every logged-in user. `Obsoletes:` makes
dnf *erase* the obsoleted package. Wave 7 measured this with dnf5 on Fedora 44
and confirmed it on the real downloaded `omnibridge-1.0.0-1.fc44.x86_64.rpm`
(`rpm -qp --scripts`):

* `Obsoletes:` + `Provides:` (the text above): `%preun` ran with **`$1 = 0`**.
  The person running `dnf upgrade` would lose their enablement and their
  running daemon. That breaks this ADR's own first systemd invariant ("must,
  after upgrading, have the Pliwee daemon running at the next login").
* A transitional package with no `Obsoletes:`: `omnibridge` is **upgraded**,
  `%preun` runs with **`$1 = 1`**, nothing is disabled, and `pliwee` arrives as
  a dependency.
* Both together: dnf takes the `Obsoletes:` path again (`$1 = 0`). So the core
  package carries none.
* `omnibridge-gui` 1.0.0 has no scriptlets at all, so the text above is kept
  for it.

The evidence is recorded in
[`PLIWEE-WAVE-7-LINUX-INTEGRATION-PACKAGING.md`](../reports/branding/PLIWEE-WAVE-7-LINUX-INTEGRATION-PACKAGING.md)
§1.3, with `pliwee-wave-7/package-transition-probe.{sh,txt}` and
`pliwee-wave-7/v1.0.0-rpm-scriptlets.txt`.

**Compatibility that stays.**

* **Upgrade.** `dnf upgrade` (or `dnf install`) with the Pliwee set moves an
  OmniBridge 1.0.0 install in place. State migration (D9, D12) and the
  `omnibridged.service` alias are unchanged.
* **Downgrade.** Removing `omnibridge pliwee pliwee-gui` and reinstalling the
  1.0.0 packages restores the 1.0.0 package set and its unit file (Wave 7
  measured this, RF). The D9 migration copies and never moves, so OmniBridge
  1.0.0 then starts on its untouched `~/.local/share/omnibridge`. G7-UP U10
  measures that on hardware. It is **not yet executed**.
* **Window.** The transitional package ships through the Pliwee v1.x line,
  under the *System integration* row of D11. Removing it needs a release note
  and a further amendment here.

**Enforced by** `packaging/tests/packaging-checks.sh`: no `Obsoletes:` of the
core name, exact bounds against `FIRST_PLIWEE_VERSION`, and the transitional
package's shape. The install/upgrade harnesses now **fail** when the expected
OmniBridge 1.0.0 packages are missing, instead of skipping the transition
assertions (`install-smoke.sh` L17, `upgrade-gates.sh` O1/U10). Report:
[`PLIWEE-PRE-W8-REMEDIATION.md`](../reports/branding/PLIWEE-PRE-W8-REMEDIATION.md).
