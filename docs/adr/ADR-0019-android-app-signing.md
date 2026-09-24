# ADR-0019 — Android app signing: maintainer-owned key, Play App Signing, separate upload key

Status: Accepted (2026-09-24). Operator decision recorded at PLAY4 of the
Android / Google Play v1 wave; the options as they were put are in
[`audits/android/ANDROID-PLAY-V1-READINESS-AUDIT.md` §6](../audits/android/ANDROID-PLAY-V1-READINESS-AUDIT.md#6-play4--app-signing-model-operator-decision).

## Context

Every installed copy of an Android app is bound for life to the certificate
that signed it: Android installs an update only if it is signed by the same key
(or a rotation the platform recognises). Google Play offers two ways to hold
that key under Play App Signing — Google generates it and nobody else ever
has it, or the developer generates it and gives Play a copy. Either way uploads
are signed with a separate, resettable upload key.

OmniBridge ships from GitHub today, avoids Google Play Services (ADR-0009
rejected cloud push on principle; the QR scanner is zxing rather than ML Kit),
and its users are the ones likely to move between GitHub, F-Droid
and Play. A key only Google holds would make each of those channels a
different app.

## Decision

**The maintainer generates and keeps the long-term app signing key, and
supplies it to Play App Signing. A separate upload key signs Play uploads.**

| | App signing key | Upload key |
| --- | --- | --- |
| Purpose | the identity every installed copy is bound to; Play re-signs with it | proves an upload came from the maintainer |
| Algorithm | RSA-4096, SHA256withRSA, PKCS#12 | RSA-4096, SHA256withRSA, PKCS#12 |
| Validity | 30 years (Play requires beyond 2033-10-22) | 30 years |
| Subject (public in every APK) | `CN=OmniBridge, OU=Android App Signing` | `CN=OmniBridge, OU=Android Upload` |
| Alias | `omnibridge-app-signing` | `omnibridge-upload` |
| Lives | **offline only**: encrypted backups on two media, two places | the maintainer's workstation, outside the repository, mode 0600 |
| Also held by | Google Play App Signing (after the PEPK step) | nobody — Play holds only its certificate |
| If lost | restore from either medium; if both are gone, Play keeps signing but off-Play distribution under this identity ends | restore from backup, or reset through Play Console |
| If leaked | an attacker can sign sideload "updates" that install over genuine copies — treat as an incident; Play-side key upgrade exists but older Android versions keep trusting the old key | request an upload key reset; the leaked key cannot publish on Play alone |

The two keys are distinct keys, not two aliases for one key. The provisioning
script checks that their certificates and moduli differ.

### What the repository may and may not contain

* **May:** how signing is supplied (Gradle reading an external keystore path
  and environment-supplied passwords — PLAY6), public certificates, and public
  SHA-256 / SHA-1 certificate fingerprints.
* **May not:** any keystore, any private key in any encoding, any password,
  any properties file naming a password, or the encrypted backup. `.gitignore`
  covers `*.jks *.keystore *.p12 *.pfx key.properties keystore.properties
  signing.properties`; ignoring is a second line of defence, not the first.
* **GitHub Actions** receives no private signing material. Changing that is a
  separate decision needing explicit operator approval and its own ADR.

## Custody — the provisioning procedure

One resumable script, run by the operator in their own terminal:
[`android/signing/provision-signing-keys.sh`](../../android/signing/provision-signing-keys.sh).
It follows the principle the OpenPGP release key was provisioned under
([release signing foundation §8.5](../audits/release/RELEASE-SIGNING-FOUNDATION-V1.md)):
*an unverified backup is a belief, not a backup.*

| Stage | What happens | Where secrets are |
| --- | --- | --- |
| 1 generate | both keys and three 192-bit random passwords (app keystore, upload keystore, backup) | `$XDG_RUNTIME_DIR` — tmpfs, checked, mode 0700 |
| 2 show | the three passwords printed **once**; the operator saves them in a password manager and types `SAVED`; the screen and scrollback are cleared | password manager |
| 3 backup | one bundle (both keystores + public certificates + checksums) encrypted with gpg AES-256 (S2K SHA-512, 65 011 712 iterations, a throwaway `GNUPGHOME`, no passphrase cache) written to each of two separate mounted media; the script then stops and requires both to be ejected and re-inserted | media A and B, encrypted |
| 4 verify | the operator pastes all three passwords **from the password manager**; each must equal what was generated; each bundle is read back from the **re-mounted** media (mount id must have changed), checksummed, decrypted, compared byte for byte, and each private key must sign a CSR whose public key matches its certificate | tmpfs |
| 5 install | the **upload** keystore only, to `~/.local/share/omnibridge-android-signing/` (not the desktop daemon's `~/.local/share/omnibridge`, which a pairing reset may remove) | workstation |
| 6 destroy | the tmpfs directory is shredded; a **public** record (fingerprints, bundle hashes, dates) is written to `~/.local/state/omnibridge-android-signing/PROVISIONED` | — |

It refuses to run once `PROVISIONED` exists: a second app signing key would be
a second app. It refuses media that are not mount points, that share a device
with each other or with `$HOME`, or that lie inside the repository.

The procedure is rehearsed by
[`android/signing/tests/provision-selftest.sh`](../../android/signing/tests/provision-selftest.sh)
with throwaway keys under a scratch root — the full run plus each refusal
(no media, same medium twice, media in the repository, unconfirmed passwords,
no re-mount, a mistyped password, a corrupted bundle, a second provisioning),
an independent restore by the steps printed on the media, and checks that no
password or plaintext private key reaches the media, the record or the
repository. Android CI runs it.

### Supplying the key to Play

Not part of provisioning. When the Play app exists, Play Console offers its
per-app encryption public key; the app signing keystore is restored from one
medium into tmpfs, exported with Google's PEPK tool under that key, uploaded,
and the tmpfs copy destroyed. The upload certificate (public) is registered at
the same time. That step is an operator action at PLAY18.

### Recovery

| Event | Response |
| --- | --- |
| workstation lost or wiped | restore the upload keystore from either medium |
| upload key suspected leaked | Play Console › Protected with Play › Play Store protection › Manage Play app signing › Request upload key reset (path as the help centre gave it on 2026-09-24), with a newly generated upload certificate; record the new public fingerprint with a dated note |
| one medium lost or unreadable | the other restores; write a fresh copy to new media and restore-verify it |
| both media lost | Play keeps signing with its copy; GitHub / F-Droid releases under this identity can no longer be produced. Record it; do not generate a replacement app signing key silently |
| app signing key suspected leaked | incident: announce, stop off-Play releases, use Play's app signing key upgrade, and record which Android versions still trust the old key |
| a password manager entry lost | the backup password loses both bundles; a keystore password loses that key. There is no other copy — this is why stage 4 makes the operator paste each one back |

## Consequences

* A GitHub-built APK signed with the app signing key updates a Play-installed
  copy and the other way round. F-Droid can ship maintainer-signed APKs if the
  build is made reproducible; otherwise F-Droid signs with its own key, as it
  would under either model.
* Producing a non-Play release is a deliberate local act with a medium mounted,
  like signing a Linux release — never a CI job.
* The maintainer carries a key that must outlive the project. The cost of that
  is two drives, three password-manager entries and a procedure that refuses
  to call a backup good until it has been restored.
* The help centre does not state whether a developer-supplied key receives the
  hybrid (RSA-4096 + ML-DSA-65) signing Google-generated keys get by default;
  what Play Console shows at PEPK time is recorded when it happens.

## Provisioned identity (public)

Provisioned by the operator on 2026-09-24 with the procedure above; both
offline backups restore-verified at 2026-09-24T05:05:45Z. The certificates
are committed as public files in
[`android/signing/certs/`](../../android/signing/certs/).

| Key | Certificate SHA-256 | SHA-1 | Valid |
| --- | --- | --- | --- |
| app signing (`omnibridge-app-signing`) | `AB:B6:2F:53:CB:63:32:6D:AE:3D:02:A2:5C:76:CA:45:CA:2B:95:B5:63:8A:95:5B:BB:7B:45:20:B0:23:AC:49` | `73:EB:FB:A7:90:50:7F:0D:E5:99:2A:AE:8E:69:EF:CE:91:CD:D6:F0` | 2026-09-24 → 2056-09-23 |
| upload (`omnibridge-upload`) | `75:FC:88:B5:20:72:47:EF:21:50:6B:D5:F6:EB:87:A8:15:AE:C0:13:87:41:83:30:3E:42:6A:92:7E:2F:BA:47` | `9D:65:32:06:A1:0E:77:C6:09:23:CA:32:20:AB:91:B1:BA:9B:2C:C0` | 2026-09-24 → 2056-09-23 |

After the PEPK step, Play Console's *App signing* page must show the app
signing SHA-256 above and the upload SHA-256 above. Any other value there
means a different key reached Play, and nothing is published until it is
explained.

## Building a release

`android/signing/build-release-bundle.sh` prompts for the upload keystore
password (hidden), passes it to one `--no-daemon` Gradle run through the
environment, refuses a dirty working tree, checks the password did not reach
the bundle, and runs `android/signing/verify-release-bundle.sh`, which fails
unless the bundle has exactly one signer whose certificate is the committed
upload certificate, is not debug-signed, verifies under `jarsigner`, and
carries the expected package, minSdk, targetSdk ≥ 36, no `debuggable`,
exactly the expected permissions, no key material, and an R8 mapping.

In `app/build.gradle.kts`, any task producing a release APK or bundle fails
when `OMNIBRIDGE_UPLOAD_KEYSTORE` / `OMNIBRIDGE_UPLOAD_KEYSTORE_PASSWORD` are
absent or the keystore lies inside the repository. Android CI asserts that
refusal.
