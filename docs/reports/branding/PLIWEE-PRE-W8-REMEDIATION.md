# Pliwee rebrand — pre-Wave-8 remediation

| | |
| --- | --- |
| **What this is** | The fixes for the defects the first Wave 8 certification (G8) found, plus the owner decisions that certification asked for. Together they give a **corrected candidate** for the manual gates and a later G8 re-run. **This is not a certification, and it does not claim G8 PASS.** |
| **Failed run it answers** | *G8 — PRE-MIGRATION: FAIL* on candidate `6723e76` (Wave 7), 2026-09-25: `docs/certification/rebrand/PLIWEE-PRE-MIGRATION-CERTIFICATION.md` and `docs/audits/rebrand/PLIWEE-REBRAND-REMAINDER-AUDIT.md`. Those documents are **not in this branch's tree**. The orchestrator preserved them in the stash `pliwee-w8-failed-cert-evidence-20260925-100538` (untracked files, `stash@{0}^3`), and this report was written from that copy. Returning them to `docs/` is the orchestrator's call. They are evidence and are not edited here |
| **Decision** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md), with the implementation amendments **A1** and **A2** added by this remediation |
| **Plan** | [PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md) § Wave 8, § 6 |
| **Branch / base** | `feature/pliwee-rebrand-w8-remediation`, working tree on `6723e76` (= `origin/feature/pliwee-rebrand-wave7`). Not committed; the orchestrator owns git |
| **Date** | 2026-09-25 |
| **Host** | Fedora Linux 44 Workstation, kernel 7.2.5-200.fc44, **1 CPU**, 15 GiB RAM. rustc/cargo 1.98.1, Gradle 8.11.1 on Temurin 21, OpenSSL 3.5.8, GnuPG 2.4.9, Python 3.14.7. One expensive job at a time: `CARGO_BUILD_JOBS=2`, `RUST_TEST_THREADS=2`, `cargo -j 2`, Gradle `--max-workers=2`, `parallel=false`. **No VM, emulator or container was started. Nothing was installed on or removed from the attached Android device. No signing key was provisioned.** |
| **Evidence** | [`pliwee-pre-w8-remediation/`](pliwee-pre-w8-remediation/) (§ 9) |
| **Result** | Every code-level and document-level reason the first G8 failed is fixed and covered by a test that fails on the old state (D1–D8, the E7 Release Readiness failure, the open harness wording, B4). The automated regression is green (§ 6). The remainder census finds **0 defects, 0 unexplained and 0 open items** (§ 7). The manual and hardware gates are **NOT EXECUTED** (§ 8). G8 is still to be re-run. |

---

## 1. Owner decisions applied

Approved for this remediation by the project owner.

| # | Decision | Where it is recorded | What it changed in the tree |
| --- | --- | --- | --- |
| 1 | The first Pliwee version is **1.1.0** (plan B4) | ADR-0020 **A1**. Dated notes in the plan § 6 and in the Wave 7 report § 1.1 | No value. 1.1.0 was already in the five places W7 wrote it. The "provisional" wording in `packaging-checks.sh` and the metainfo comment now cites A1. The metainfo `<release>` stays `type="development"` until W10 |
| 2 | RPM transition: a **transitional `omnibridge` package**, not `Obsoletes:` on the core package | ADR-0020 **A2**, with the measured reason. Dated notes in the plan § 6 and the Wave 7 report § 1.3 | Nothing in the packaging, which already had this shape. The harnesses around it were hardened (decision 7) |
| 3 | QR centre mark: keep one, **taken from the frozen master**, never redrawn | § 2, D8 | `desktop/gui/src/views/pairing.rs`, `build.rs`, `tests/brand_assets.rs` |
| 4 | Public X.509 PEM certificates may be tracked; private or secret key material stays forbidden | § 3 | `packaging/tests/release-signing-tests.sh` |
| 5 | Living docs may be corrected now. Historical evidence stays immutable. The privacy policy and its URL stay W10 | § 4 | README (scoped), `docs/architecture/*`, `THREAT_MODEL.md`, `BRAND.md`, `UI-GUIDELINES.md`, `docs/README.md`, one line of `AGENTS.md` |
| 6 | Clean the developer-only stale names the W8 audit listed, when that is safe and behaviour-neutral | § 4 | `LocalOmniBridgeColors`, `NotOmniBridgeCode`, a test name, the instrumentation keys, 183 comment/KDoc lines |
| 7 | A missing expected OmniBridge 1.0.0 package or version is a **hard failure** in the W7 install/upgrade harnesses | § 5 | `packaging/tests/install-smoke.sh`, `packaging/tests/upgrade-gates.sh` |

Not changed, as instructed: the privacy-policy URL and `PrivacyPolicy.kt`,
the repository URL (Cargo, spec, debian, metainfo, unit `Documentation=`), the
OpenPGP UID and `omnibridge-release-pubkey.asc`, the Play listing and Play
art, and any release metadata. `git diff` holds no `github.com` line at all.

## 2. The eight G8 defects

Each fix comes with a test that fails on the state G8 measured. Every such
test was **mutation-proven**: the old text or behaviour was put back, the
test was seen to fail, and the file was restored and compared byte for byte
(`mutations.txt`).

### D1 (W7): `pliwee --version` printed `omnibridge 1.1.0`

* **Fix.** `desktop/cli/src/main.rs`: `#[command(name = "pliwee", …)]`. No
  old binary name is reintroduced; the packages still ship `/usr/bin/pliwee`
  only.
* **Test.** `cli` bin unit test `the_command_identifies_itself_as_pliwee`
  asserts the name is `pliwee`, `--version` renders exactly
  `pliwee <CARGO_PKG_VERSION>`, and that no usage, help or version text
  contains `omnibridge`.
* **Observed on the built binary** (`cli-help-observation.txt`):
  `pliwee --version` → `pliwee 1.1.0`, `Usage: pliwee <COMMAND>`.
* **Mutation:** with the name set back to `omnibridge`, the test fails
  (`left: "omnibridge"`, `right: "pliwee"`).

### D2 (W7): the Android app said "Run `omnibridge pair`"

* **Fix.** `PairingScanner.HOST_PAIR_COMMAND = "pliwee pair"`. Both the scanner
  `PROMPT` and the Home empty-state hint (`FIRST_DEVICE_HINT`, pulled out of
  `DevicesScreen`'s composable so a test can read it) are built from that
  constant. They now read "Point at the QR code shown by `pliwee pair`" and
  "Run `pliwee pair` on your computer, …".
* **Test.** New `HostCommandCopyTest` (3 cases). The command is `pliwee pair`,
  and both strings contain it and not `omnibridge`. **Every** `.kt`/`.xml`
  under `app/src/main` is scanned for `omnibridge[d] <cli verb>`, and the scan
  refuses to pass if it found fewer than 50 source files. Legacy wire values
  (`omnibridge1:`, `omnibridge/1`) do not match. `PairingScannerOrientationTest`
  still asserts that the scan request carries `PROMPT`.
* **Mutation:** with `PROMPT` set back to the W7 text, 2 of the 3 cases fail.

### D3 (W4): `pliweed --help` gave the download default as `…/OmniBridge`

* **Fix.** `desktop/daemon/src/main.rs`: "Defaults to `<XDG downloads>/Pliwee`".
* **Test.** `daemon` bin unit test `help_states_the_real_download_folder`
  checks the long help against the **constant** the sink uses:
  `<XDG downloads>/{DOWNLOAD_SUBDIR}` must be present and
  `LEGACY_DOWNLOAD_SUBDIR` must be absent. It also checks
  `pliweed --version` → `pliweed 1.1.0`.
* **Observed:** `pliweed --help` shows `Defaults to <XDG downloads>/Pliwee`.
* **Mutation:** with the old text restored, the test fails (`missing "<XDG downloads>/Pliwee"`).

### D4 (W5): the `.proto` comments gave only the obsolete `omnibridge/…` constructions

* **Fix.** Five comment sites now state the canonical construction first and
  name the legacy value explicitly as the **legacy OmniBridge 1.0.0 profile**:
  * `core.proto`: pairing proof `"pliwee/pairing-proof/v1"`, confirmation
    `"pliwee/pairing-confirm/v1"`. The legacy domains are named, with the rule
    that the domain follows the negotiated profile and is never tried under
    both.
  * `files_v1.proto`: data ALPN `"pliwee-data/1"` and MAC domain
    `"pliwee/files.v1/data-stream/v1"`, each with its legacy counterpart, and
    the rule that a stream uses its control session's profile.
  * `notifications_v1.proto`: id and group digests `"pliwee/notifications.v1/…"`.
    It states that these are **canonical on every profile**, with no legacy
    form, and that `omnibridge/notifications.v1/id/v1` was the 1.0.0 build's
    domain and is neither computed nor accepted. The two product nouns in
    that file say Pliwee.
* **Test.** New `desktop/proto/tests/schema_comments.rs`:
  `the_schema_states_the_canonical_domains` (6 constructions, each in the
  schema that defines it) and `a_legacy_value_is_named_only_as_legacy` (any
  `"omnibridge…`/`` `omnibridge… `` in any schema must be called legacy on its
  line or the line before). The second test refuses a vacuous pass when it
  finds no legacy value at all. Field numbers and types are unchanged:
  `namespace.rs`'s field-table snapshot is still green.
* **Mutation:** with the notification id domain set back to the W7 text, both
  tests fail.

### D5: `THREAT_MODEL.md` named the old commands and folders

* **Fix.** `pliwee unpair`, `pliwee grant … clipboard.v1`,
  `pliwee clipboard apply`, `<XDG downloads>/Pliwee` and Android
  `Download/Pliwee` (checked against `destination.rs` `DOWNLOAD_SUBDIR` and
  `files/Downloads.kt`). The title and 10 present-tense product nouns say
  Pliwee, and one sentence says "the project". A one-paragraph former-name
  note is dated and cites ADR-0020. The threat analysis itself is unchanged.

### D6 (W3): `UI-GUIDELINES.md` still used the pre-W3 Kotlin names

* **Fix.** The sentence now says the Kotlin names carry the `Pliwee` prefix,
  having been renamed from `OmniBridge` in W3. `Modifier.pliweeContentColumn()`
  replaces `omniBridgeContentColumn()`, checked against
  `ui/components/Surfaces.kt:187`.

### D7 (W7): `BRAND.md` called the retired `omnibridge-mark.svg` the canonical mark

* **Fix.** The *Assets* table now lists the **five Wave 0 masters** by name,
  with `pliwee-mark.svg` as the canonical mark, and then `pliwee-app-icon.svg`.
  The six OmniBridge files moved to a separate table headed
  **"Retired — OmniBridge v1.0.0 artwork, not canonical"**. The row in the
  OmniBridge-era section now says *"Canonical mark of the OmniBridge era
  (retired; not the current mark)"*. The paragraph under it opens with "Until
  Pliwee W7…". The *Logo* section's banner says no application build draws the
  mark any more. A dated note records that the W7 note ("no build draws the
  OmniBridge artwork") was not yet true because of D8, and what changed.
  The masters themselves are untouched (§ 10).

### D8 (W7): the pairing QR's centre was a Cairo redraw of the pre-Pliwee ribbon

* **Fix (owner decision 3).** `draw_ribbon` is **deleted**, along with every
  Cairo path, arc and gradient in `pairing.rs`. The centre mark is now
  `widgets::brand_mark(…)`, which is the same `gtk::Image::from_resource(
  "/io/github/yurisismotto/pliwee/pliwee-mark.svg")` the app bar uses. It is
  laid over the code with a `gtk::Overlay` and rendered by GTK's SVG loader
  from the **compiled-in frozen master**. No geometry is recreated. Nothing is
  drawn from the master's coordinates, and no derivative file is produced.
  The Cairo code now draws only the modules and a white keep-out square. One
  function, `centre_mark_px()`, gives both the keep-out square and the mark's
  pixel size (a fifth of the code's side; error correction stays at level H).
  The mark is hidden until a code is on screen.
* **Why runtime rendering, not a generated derivative.** The GUI already
  compiles the master into its gresource and renders it at every size.
  Rendering it again here needs no new file, and a new file is what would
  need a provenance test.
* **Tests** (`desktop/gui/tests/brand_assets.rs`, plus a unit test in `pairing.rs`):
  * `the_pairing_qr_centre_is_the_compiled_in_master_not_a_drawing`:
    `pairing.rs`, with comments stripped, must call `widgets::brand_mark(` and
    `add_overlay(&centre_mark)`. It must contain none of `move_to`,
    `line_to`, `curve_to`, `arc(`, `arc_negative`, `LinearGradient`,
    `RadialGradient`, `set_line_width`, `draw_ribbon`, `BRAND_GRADIENT`,
    `Pixbuf` or `omnibridge`. No `data/pliwee-mark.svg` may exist:
    `compile_resources` searches `data/` **before** the asset directory, so
    such a file would shadow the master unnoticed.
  * `the_compiled_in_centre_mark_is_the_frozen_master`: loads the **compiled**
    `pliwee.gresource`, looks up `pliwee-mark.svg` and compares it with
    `docs/design/assets/pliwee-mark.svg`. The only normalisation is what
    `xml-stripblanks` does: drop the XML declaration it adds and the blanks
    between tags it removes. It refuses a comparison against fewer than
    1000 bytes.
  * `stripblanks_normal_form_changes_only_blanks_between_tags` pins that
    normalisation, including that a changed coordinate is still a difference.
  * `the_centre_mark_is_a_fifth_of_the_code` pins the geometry function.
* **Build.** `gui/build.rs` now re-runs on any change under `data/`, not only
  on the resource list. Before, a shadow file dropped into `data/` would not
  even have triggered a rebuild.
* **Mutations** (`mutations.txt`):
  * a shadow `data/pliwee-mark.svg` with one coordinate changed fails both
    tests. The provenance test reads *"the compiled-in pliwee-mark.svg is not
    the frozen master"*;
  * a `curve_to` put back into `pairing.rs` fails with *"pairing.rs uses
    "curve_to": the centre mark must be the master, not a drawing of it"*.
* **Not verified here:** how the dialog looks. That is a GNOME session check
  (§ 8). Scannability is carried by the unchanged level-H code and keep-out
  area.

## 3. Release-signing harness (owner decision 4, the G8 E7 failure)

G8's E7 failed on **1 check**: every tracked `*.pem` was refused by **name**,
and the two public ADR-0019 certificates in
`android/signing/certs/legacy-omnibridge/` are `.pem`.

**The fix is a content proof, not a name exemption.**

* `.gpg`, `.asc` and `.key` are still refused by name, with nothing carved out.
* A tracked `.pem` passes only if a classifier proves **all** of the following:
  the file is ASCII; the words `PRIVATE` and `SECRET` appear nowhere in it;
  every PEM block is labelled exactly `CERTIFICATE`; the file holds nothing
  outside those blocks; each body is well-formed base64 of a DER `SEQUENCE`;
  and each block **parses as X.509 with `openssl x509`**. Anything else is
  `REJECT <path>: <reason>`.
* If `python3` or `openssl` is absent while a `.pem` is tracked, the result
  is a **failure** ("could NOT be proven to be public certificates"), not a
  skip.
* The tracked-tree armour scanner still reads every tracked file, whatever
  its name. Its header pattern is **broadened** from a fixed list of prefixes
  to `-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----`, which matches strictly
  more.
* **Controls, run before the tree's result is believed.** They use real,
  ephemeral keys generated in `$WORK` by `openssl`:
  * a public certificate is accepted. If it is not, the harness stops with
    `PRECONDITION FAILED`: a classifier that rejects everything would turn
    the FAIL into a statement about the classifier;
  * each of these is rejected: a PKCS#8 `PRIVATE KEY`, an `EC PRIVATE KEY`,
    an `ENCRYPTED PRIVATE KEY`, a certificate bundled with its key, a private
    key's body under a `CERTIFICATE` label (only the X.509 parse catches that
    one), and a certificate with trailing text;
  * the armour scanner finds all three PEM private-key forms, and not the
    certificate.
* **Result** (`release-signing-tests.txt`): **71 passed, 0 failed.** W8's E7
  run was 61 passed, 1 failed. `release-signing-vs-w8.txt` compares the two
  check by check. Every one of W8's 61 passing checks is present and passing.
  The 10 extra passes are the narrowed name check (`.gpg/.asc/.key`, the check
  that failed in W8) and 9 new ones: 7 classifier controls, 1 armour-scanner
  control and the tracked-`.pem` verdict. It is green because the two files **are** public certificates
  (`OU=Android App Signing, CN=OmniBridge` and `OU=Android Upload,
  CN=OmniBridge`, both parsed), not because anything was exempted.
* **Mutation proof** (`mutations.txt`, "release-signing-mutations"). Each case
  was staged with `git add -f` in a throwaway `git clone --shared`, so that
  `git ls-files` listed it; nothing was staged in this repository.

  | # | Staged file | Result |
  | --- | --- | --- |
  | M-RS1 | a PKCS#8 private key as `…/legacy-omnibridge/leaked-key.pem` | exit 1: the `.pem` is REJECTed **and** the armour scan fails (69/2) |
  | M-RS2 | certificate + private key as `…/bundle.pem` | exit 1, both checks fail (69/2) |
  | M-RS3 | a private key as `docs/notes.txt` | exit 1, the armour scan fails (70/1) |
  | M-RS4 | a private key's body relabelled `CERTIFICATE`, as `.pem` | exit 1: "a CERTIFICATE block does not parse as X.509" (70/1) |
  | M-RS5 | any `.asc` | exit 1, the name rule (70/1) |
  | baseline | nothing staged | exit 0 (71/0) |

  Secret scanning is not weakened. Every class of file W8 rejected is still
  rejected, except a `.pem` proven to hold only public certificates.

## 4. Living documentation and developer names (owner decisions 5, 6)

* **README** (scoped). A dated note under the badges says the published
  release is still OmniBridge v1.0.0, that the install, verify and CLI
  sections describe **that** release, and that this tree builds Pliwee 1.1.0
  (not yet released). *Build from source* now names `./target/release/pliweed`
  and `packaging/common/pliweed.service`. The old text named a binary and a
  file this tree does not produce, which is a developer-facing error. The CLI
  reference has a note saying the command is `pliwee` in a build of this tree.
  *Repository layout* lists `pliweed` / `pliwee` / `pliwee-gui` and ADR-0020.
  The v1.0.0 install and verify commands, badges, release URLs and OpenPGP
  identity are **unchanged** (W10).
* **`docs/architecture/`.** `PROTOCOL.md` title, and a new profile rule: a
  client offers one ALPN and requires the server to have selected exactly it
  (§ 5). Present-tense product nouns in `OVERVIEW.md`, `CLIPBOARD.md`,
  `FILES.md` and `NOTIFICATIONS.md`. The legacy-profile tables and the
  historical account in NOTIFICATIONS § "created by N2" are untouched.
* **`docs/README.md`** title. **`AGENTS.md`**: one word in the root-files table
  ("what Pliwee is"). Nothing else in AGENTS.md changed.
* **Kotlin names.** `LocalOmniBridgeColors` → `LocalPliweeColors` (4 uses).
  `PairingScanner.Outcome.NotOmniBridgeCode` → `NotPliweeCode` (4 uses); its
  KDoc now says it covers both `pliwee1:` and legacy `omnibridge1:` codes.
  The test `omnibridges_own_package_is_not_offered` →
  `pliwees_own_package_is_not_offered`. Every one is a compile-checked rename
  with no behaviour change.
* **Instrumentation argument keys**
  (`HostDrivenCertificationHarness.kt`): `omnibridge.{pairing.payload,peer,
  granted,mirror,apps,ongoing,dismiss,locked,connect}` → `pliwee.*`. No
  script in the tree passes them; only the operator's typed `am instrument`
  line does, and that usage block is updated too, with a `pliwee1:…` payload.
  The compiled test class carries the new keys (checked in the `.class`).
  Historical reports that quote the old keys are untouched.
* **Harness messages.** `lifecycle-gates.sh` (6), `lifecycle-peer-gates.sh`
  (8), `security-log-evidence.sh` (1) and the `.deb` build banner now say
  **Pliwee** where they mean the current product. That matters because these
  lines become certification transcripts. The lines about the OmniBridge
  1.0.0 transition are unchanged.
* **Comments and KDoc: 183 lines** in 85 files where "OmniBridge" meant the
  current product, renamed on those lines only (Kotlin/Rust/XML/TOML/shell
  comments, KDoc, test names and assertion messages, CI comments). **40
  lines were deliberately kept**, because they are about OmniBridge 1.0.0, its
  state, its transition or a transcript measured on it: `legacy_migration.rs`,
  `legacy_state_migration.rs`, the `.service.in` transcript, `destination.rs`'s
  legacy folder, the spec/control transitional comments, and similar. Each
  one now has a named rule in the census (§ 7).

## 5. Additional pre-G8 fixes

* **Desktop client ALPN check, now symmetric with Android.** Android's
  `TlsFactory.requireNegotiated` already refused a server that did not select
  the one ALPN offered. The desktop's `tls::client_config` offered one ALPN
  but never checked the result, and rustls lets a server that selects **no**
  ALPN finish the handshake. New `pliwee_core::tls::require_negotiated(conn,
  profile, kind)` returns `Err` unless the negotiated protocol is exactly
  *(profile, kind)*. There is no fallback and no retry under the other
  profile. It is called by every Rust TLS client in the tree:
  `daemon/examples/fake_phone.rs` (control ×2, data) and the daemon test
  harness's `tls_connect_with_profile` / `open_data_stream_with_profile`. The
  shipped daemon and GUI open no TLS client connections; the phone dials.
  * Test `wire_identity::a_client_refuses_a_server_that_negotiated_no_alpn`:
    for both profiles × both kinds, a server with an empty ALPN list completes
    the rustls handshake and `require_negotiated` refuses it. Against the real
    four-value listener it passes. The right profile with the wrong kind is
    refused too.
  * **Mutation:** a version that tolerates "no ALPN" fails the test
    (`pliwee Control, server ALPN none: Ok(())`).
  * The legacy-profile daemon suites still pass through the stricter
    connectors (§ 6, R6).
* **The W7 install/upgrade harnesses fail on a wrong starting point (owner
  decision 7).**
  * `install-smoke.sh` L17. After installing "the older build", it now
    **fails** unless exactly one `omnibridge 1.0.0-*` is installed. If an
    `omnibridge-gui` package was supplied, it also fails unless
    `omnibridge-gui 1.0.0-*` is installed. The transition assertions (core
    upgraded in place to the transitional package, alias symlink in place)
    are now **unconditional**. Before, they sat inside
    `if grep -q '^omnibridge '`, and a wrong or empty old build skipped them
    in silence.
  * `upgrade-gates.sh`. The upgrade stage now **aborts**
    (`PRECONDITION FAILED`, exit 3) without `--old-pkgdir`. Before, U10 was
    recorded `n/a` and the stage could finish green. O1 now requires,
    **before** anything changes, that `omnibridge` and `omnibridge-gui` are
    both exactly `1.0.0-1` (`need_nonempty` + `need_exact_count`, the existing
    primitives), and saves `O1-versions.txt`.
  * **Proof without containers** (`mutations.txt`,
    "install-smoke-l17-precondition"). The new L17 block, extracted verbatim
    and run on five fabricated package lists: the correct 1.0.0 pair passes;
    `pliwee 1.1.0`, nothing, `omnibridge 0.9.0`, and a gui package given but
    not installed each **FAIL**. Both scripts pass `bash -n`, and
    `packaging-checks.sh`'s static lint of every harness (H1/H2, 129/0).
    Neither harness was run end to end. They need containers and guests
    (§ 8).

    > **Superseding note — 2026-09-25, pre-G8 gate hardening
    > (`feature/pliwee-pre-g8-gate-hardening`).** The bullet above hardened
    > U10 inside the upgrade stage. That stage still recorded U6 as n/a and then
    > ran U10, so U6 could not be measured against the upgraded guest before the
    > downgrade. U10 is now its own `--stage downgrade`, and it refuses unless a
    > verified U6 PASS from `--stage peer-u6` exists for the same distro,
    > domain, run and guest. The upgrade stage still requires `--old-pkgdir` and
    > now records the digest of its `SHA256SUMS`, and U10 refuses a different
    > set. The O1 checks described above are unchanged. See
    > [PLIWEE-PRE-G8-GATE-HARDENING.md](PLIWEE-PRE-G8-GATE-HARDENING.md).
* **Certification and harness wording**: § 4, "Harness messages".
* **Compatibility values preserved.** Every L1–L9 class of the W8 audit is
  still present and still asserted: the legacy wire profile
  (`omnibridge/1`, `omnibridge-data/1`, `_omnibridge._tcp`, `omnibridge1:`,
  the legacy domains, `omnibridge.invalid`), the legacy state paths and their
  migration, the `omnibridged.service` alias, `omnibridge.xml`, the
  transitional packages and bounds, the retired app ids, the retired signing
  identity and the retired artwork. The census rows in § 7 show them.

## 6. Tests run, and their results

On the final tree, sequentially, in this order.

| # | Check | Command | Result |
| --- | --- | --- | --- |
| R1 | Frozen artefacts | `frozen_digests.sh` (the W8 script, carried into the evidence directory) | **7 passed, 0 failed**: the five masters and `identity-{a,b}.der`. `git diff HEAD` over them is empty |
| R2 | Formatting | `cargo fmt --all -- --check` | exit 0 (`fmt.txt`). The first run flagged three hunks, all in new test code (`brand_assets.rs`, `schema_comments.rs`); `cargo fmt` fixed them and the re-check is clean |
| R3 | Clippy, as CI runs it | `cargo clippy --locked --offline -j 2 --workspace --all-targets --all-features -- -D warnings` | exit 0 (`clippy.txt`) |
| R4 | Rust workspace | `cargo test -j 2 --offline --workspace` | **exit 0: 76 binaries, 1130 passed, 0 failed, 25 ignored**; 157.5 s, 0.75 GB max RSS (`workspace.log`). W8 measured 75 / 1121 / 0 / 25. The difference is exactly the 9 new tests (cli 1, daemon 1, gui lib 1, brand_assets +3, schema_comments 2 in one new binary, wire_identity +1). No test was removed or ignored |
| R5 | Targeted, before R4 | cli/daemon bins, `brand_assets`, `wire_identity`, `pliwee-proto` tests | green, then mutation-proven (§ 2, § 5) |
| R6 | Legacy profile (W5 hand-off 5; not in CI) | `PLIWEE_TEST_PROFILE=omnibridge cargo test -j 2 --offline -p pliwee-daemon --test wire --test e2e --test files --test sessions -- --nocapture` | exit 0: e2e **18/18**, files **36/36**, sessions **6/6**, wire **11/11**, the same as W8 E4. The daemon's anchor: `EVIDENCE run-profile=omnibridge daemon-session-profile=omnibridge alpn=omnibridge/1` (`daemon-suites-profile-omnibridge.txt`) |
| R7 | CLI and daemon identity on the build | `pliwee --version/--help`, `pliweed --version/--help` | `pliwee 1.1.0`, `pliweed 1.1.0`, download default `<XDG downloads>/Pliwee` (`cli-help-observation.txt`) |
| R8 | Android unit suite | `./gradlew --offline --no-build-cache --max-workers=2 -Dorg.gradle.parallel=false :app:cleanTestDebugUnitTest :app:testDebugUnitTest` | **58 suites, 867 tests, 0 failures, 0 errors, 0 skipped**, counted from the JUnit XML, every suite time-stamped in this run (`android-unit-suites.txt`). W6 measured 57 / 864. The difference is `HostCommandCopyTest` (3). An earlier run of the same inputs was served FROM-CACHE; it was re-run with `--no-build-cache` so that the recorded result is an execution |
| R9 | Android instrumented sources compile (no device) | `:app:compileDebugAndroidTestKotlin :fixture:compileDebugKotlin` | BUILD SUCCESSFUL (`android-compile-androidtest.txt`). **Compiled only, not run** |
| R10 | Packaging static checks | `bash packaging/tests/packaging-checks.sh` | **129 passed, 0 failed**, the same count as W8 E5 (`packaging-checks-static.txt`) |
| R11 | Harness self-tests | `bash packaging/tests/harness-selftests.sh` | **40 passed, 0 failed** (`harness-selftests.txt`) |
| R12 | Release Readiness: release-signing harness | `bash packaging/tests/release-signing-tests.sh` | **71 passed, 0 failed, exit 0** (§ 3) |
| R13 | Mutation proofs | see `mutations.txt` | D1, D2, D3, D4, D8 (×2), ALPN, release-signing (×5 + baseline), L17 precondition (5 inputs), census (×3): **every mutation rejected**, and every file restored byte for byte |
| R14 | Whitespace | `git diff --check` | exit 0. The untracked evidence transcripts `cli-help-observation.txt`, `harness-selftests.txt`, `release-signing-tests.txt` and `mutations.txt` carry trailing spaces **from the tools' own output** (clap's help layout and pre-existing harness messages). They are kept verbatim, as W4–W8 kept theirs. The remediation's own new harness messages were changed to leave none |
| R15 | Remainder census | `python3 docs/reports/branding/pliwee-pre-w8-remediation/remainder_census.py` | **PASS**: 0 defects, 0 unexplained, 0 open (§ 7) |

## 7. Remainder census on the corrected tree

**Tool.** [`remainder_census.py`](pliwee-pre-w8-remediation/remainder_census.py)
is the W8 census, copied, with the same method, the same refusals and the same
two independent counts. Only its rule table changed:

* every **DEFECT** and **OPEN** rule was **removed**. Each named a line this
  remediation fixed, so each became stale, and the census refuses stale
  rules. W8 audit § 6 anticipated exactly this: *"that removal is how the fix
  is recorded"*;
* the 15 explicit P-rules whose lines were renamed were removed for the same
  reason;
* new explicit rules classify the new guard tests' negative values (T1) and
  the 40 kept legacy-prose lines (N), each with its reason.

**Result.** These are the numbers in
[`census-output.txt`](pliwee-pre-w8-remediation/census-output.txt). That run
came after this report was complete and before the output file existed; see
the note after the table. W10 is lower than W8's 165/188 because the README's
*Build from source* and *Repository layout* sections now describe the tree
(§ 4).

| Category | Files | Lines | Occurrences |
| --- | --: | --: | --: |
| H — historical / rebrand record (ADR-0020 D7) | 170 | 3808 | 4836 |
| W10 — pre-migration public value (owned by W9/W10) | 14 | 158 | 182 |
| L1 — legacy wire profile (D4, W5) | 50 | 177 | 212 |
| L2 — legacy state paths and their migration (D9, W4) | 23 | 71 | 78 |
| L3 — legacy systemd unit name, alias (W7) | 12 | 58 | 64 |
| L4 — legacy firewalld service, kept (W7) | 8 | 23 | 27 |
| L5 — legacy package names, transition and bounds (W7) | 20 | 131 | 149 |
| L6 — retired app ids, removed or refused by name (W6/W7) | 11 | 15 | 17 |
| L7 — retired Android signing identity (D3, W6) | 7 | 29 | 35 |
| L8 — retired OmniBridge artwork, unused (W7) | 3 | 52 | 69 |
| L9 — G7-UP / transition harness driving the real OmniBridge 1.0.0 (W7) | 1 | 73 | 94 |
| T1 — negative / dead-list / near-miss test value | 21 | 35 | 37 |
| T2 — test fixture, sentinel or certification-guest name | 20 | 103 | 108 |
| Q — measured transcript quoted in a comment | 2 | 2 | 2 |
| N — transition notice, rename documentation, legacy prose (intentional) | 51 | 147 | 158 |
| P — product noun in developer-only prose | **0** | **0** | **0** |
| O — open cleanup | **0** | **0** | **0** |
| **D — DEFECT, blocking** | **0** | **0** | **0** |
| **? — UNEXPLAINED** | **0** | **0** | **0** |
| **TOTAL** (unique files) | **303** | **4882** | **6068** |

The independent `LC_ALL=C grep -aoi` count, **6068**, equals the census total;
exit 0. File names carrying the old name: **18** (independent count 18), 0
unexplained: 9 historical (including this report's
`daemon-suites-profile-omnibridge.txt`, which replaces W8's file of the same
name), the 6 retired SVGs (L8), the 2 retired certificates (L7) and
`omnibridge-firewalld.xml` (L4).

Compared with W8: D went from 11 files / 20 lines to **0**, O from 38 lines to
**0**, and P from 250 lines to **0**. The living-doc fixes and the 183 renamed
lines removed most of P. The 40 lines that stay on purpose are now N, each with
a named reason. L1 grew by 9 lines: the legacy values now named, as legacy, in
the `.proto` comments and in the new guard tests. H differs because the
failed-G8 documents are not in this tree and this report's are.

**Re-running the census.** The census reads every file git knows about,
untracked ones included, so its own recorded output
(`pliwee-pre-w8-remediation/census-output.txt`, written **after** the run it
records) is classified as H on the next run. H and TOTAL then rise by exactly
the occurrences in that file; every other row reproduces. Measured: a re-run
gives H 171 / 3959 / 5107 and TOTAL 304 / 5033 / 6339 (independent count
6339, exit 0). That is +1 file, +151 lines and +271 occurrences, which is
exactly `LC_ALL=C grep -aci` / `-aoi` over `census-output.txt` alone. The census is not
changed to skip its own output, for the reason W8 gave: an exclusion is the
blind spot the census exists to refuse.

**Mutations** (`mutations.txt`, "census-mutations"):

* M1: D2 put back into `DevicesScreen.kt` → *UNEXPLAINED 1*, naming the line;
* M2: a file named `zz-omnibridge-probe.txt` → *unexplained file name*;
* M3: a kept legacy line reworded → *explicit rule matched nothing (stale)*.

### What intentionally still says OmniBridge

| Class | What | Why it stays |
| --- | --- | --- |
| W10 | README install/verify/badge/URLs for the **published** v1.0.0; `PrivacyPolicy.kt` and `docs/policy/PRIVACY-POLICY.md`; metadata URLs `yurisismotto/omnibridge`; Play listing and art sources; OpenPGP UID and `omnibridge-release-pubkey.asc`; `yurisismotto/omnibridge-history` | owned by W9/W10; not moved early (§ 1) |
| L1 | `omnibridge/1`, `omnibridge-data/1`, `_omnibridge._tcp`, `omnibridge1:`, `omnibridge/pairing-{proof,confirm}/v1`, `omnibridge/files.v1/data-stream/v1`, `Profile::OmniBridge` / `WireProfile.OMNIBRIDGE`, CN prefix `omnibridge:`, `omnibridge.invalid` | ADR-0020 D4, legacy profile through v1.x |
| L2 | `~/.local/share/omnibridge`, `~/.config/omnibridge/gui.json`, `Downloads/OmniBridge`, `.omnibridge-*.part` | D9/D12 migration and detection; durable |
| L3/L4 | `omnibridged.service` alias; `omnibridge.xml` | W7 B5 and firewalld, through v1.x |
| L5/L9 | transitional `omnibridge`/`omnibridge-gui` 1.1.0 packages and bounds; `upgrade-gates.sh` driving the real 1.0.0 | ADR-0020 A2 |
| L6/L7/L8 | retired app ids (AppStream `<replaces>`, dead lists); `certs/legacy-omnibridge/`, `RETIRED_SLUG`; the six retired SVGs | history and refusals; the artwork is drawn by no application build |
| T1/T2/Q/N | negative tests, sentinels, fixture names, quoted transcripts, transition notes, legacy prose | tests and records of the rename |

## 8. Manual and hardware gates: NOT EXECUTED

None of these was run. None is claimed. Each is for the G8 re-run on a
candidate frozen on `develop`.

| Gate | Why not here | What runs it |
| --- | --- | --- |
| G7-UP U0–U10 on Fedora 44, Ubuntu 24.04, Ubuntu 26.04, Debian 13 (now with the hardened O1/U10) | VMs are forbidden in this run; needs operator pairing | `upgrade-gates.sh`, one guest at a time |
| § 4 network matrix N1–N5, X1–X5 on hardware | no install on, or use of, the physical Android device | operator + tablet |
| `install-smoke.sh` (all four distributions, including the hardened L17), RPM/`.deb` builds, `packaging-checks --rpm/--deb`, `systemd-analyze verify`, `desktop-file-validate`, `appstreamcli validate` on built packages | container builds; not started in this run | the corrected candidate |
| Security Certification v1 (SEC gates), clipboard.v1, files.v1, notifications.v1 N6 hardware certifications | real hosts and the tablet | their procedures |
| Linux GNOME and KDE real sessions, **including how the new QR centre mark looks and that the code still scans** (D8), tray, D-Bus activation, reset of favourites/notification settings | needs a person at the screen; no KDE session here | a GNOME host + `anyflow-f44-kde` |
| `lifecycle-gates.sh`, `lifecycle-peer-gates.sh`, `security-log-evidence.sh` in full; `systemd-unit-gates.sh` | guests and the tablet | as above |
| Android instrumented suite (including `HostDrivenCertificationHarness` with the renamed `pliwee.*` keys), component-upgrade test, signed-bundle verification | the device may not be touched; no Pliwee upload key exists | W6 § 7 procedure |
| `release-artifacts.yml` dry run | pushing or dispatching is the orchestrator's | the orchestrator |
| Signing-key provisioning, Play, repository migration | out of scope (W9/W10, operator) | — |

> **Superseding note — 2026-09-25, pre-G8 gate hardening
> (`feature/pliwee-pre-g8-gate-hardening`).** Some of the gates in this
> table are now driven by one resumable operator coordinator,
> `packaging/tests/pre-g8-manual-gates.sh`. It runs one gate at a time,
> confirms every VM, device or signing-media action at the terminal, and
> records PASS / FAIL / PENDING / BLOCKED from the evidence the owning scripts
> write. It drives **only** these:
>
> * G7-UP U0–U10 (with U8 on a fresh guest) on the four distributions, in §3
>   order: U6 against the upgraded guest, then U10;
> * `lifecycle-gates.sh`, on a fresh guest per distribution;
> * `security-log-evidence.sh`, once per distribution, on the upgraded G7-UP
>   guest before U10;
> * `lifecycle-peer-gates.sh` **only as U6**, run by
>   `upgrade-gates.sh --stage peer-u6` against the upgraded guest;
> * from the GNOME and KDE row, **only** the Wave 2 Devices-page keyboard and
>   screen-reader procedure;
> * the Android instrumented suite as `:app:connectedDebugAndroidTest`, where
>   `HostDrivenCertificationHarness` runs only in its no-argument mode, and
>   the component-upgrade test;
> * signing-key provisioning (`provision-signing-keys.sh`).
>
> These stay outside it, with their own procedures and owners:
>
> * the network matrix;
> * the container builds, `install-smoke.sh` and the built-package validators;
> * Security Certification v1 (SEC) and the clipboard.v1, files.v1 and
>   notifications.v1 hardware certifications;
> * `systemd-unit-gates.sh`;
> * the QR centre mark and scan (D8), tray, D-Bus activation, and the reset of
>   favourites and notification settings in real sessions;
> * a full `lifecycle-peer-gates.sh` run outside U6, and the host-driven
>   `HostDrivenCertificationHarness` runs;
> * signed-bundle verification;
> * the `release-artifacts.yml` dry run;
> * Play and repository migration (W9/W10).
>
> The table is left as written. **None of these gates has been executed.** See
> [PLIWEE-PRE-G8-GATE-HARDENING.md](PLIWEE-PRE-G8-GATE-HARDENING.md) §9.

## 9. Evidence files (`pliwee-pre-w8-remediation/`)

`frozen_digests.sh`, `frozen-digests.txt`, `fmt.txt`, `clippy.txt`,
`workspace.log`, `daemon-suites-profile-omnibridge.txt`,
`cli-help-observation.txt`, `android-unit-suites.txt`,
`android-compile-androidtest.txt`, `packaging-checks-static.txt`,
`harness-selftests.txt`, `release-signing-tests.txt`,
`release-signing-vs-w8.txt`, `mutations.txt`, `remainder_census.py`,
`census-output.txt`.

## 10. Frozen masters

`pliwee-mark.svg`, `pliwee-mark-mono.svg`, `pliwee-mark-tonal.svg`,
`pliwee-wordmark.svg` and `pliwee-lockup.svg` are **byte-for-byte unchanged**.
`git diff HEAD` over them is empty, and their SHA-256 values equal the Wave 0
R4.2 digests (R1). The frozen DER vectors are unchanged too. No file under
`docs/design/assets/` was modified, added or removed. The D8 fix *reads* the
master and never writes it.

## 11. Are the code-level reasons G8 failed resolved?

| G8 reason | State on this tree |
| --- | --- |
| D1–D8 (audit § 4) | **resolved**, each with a mutation-proven test (§ 2) |
| E7: Release Readiness harness red | **resolved** by owner decision 4: 71/0, a content proof, private keys still rejected (§ 3) |
| B4: first version not confirmed | **resolved**: 1.1.0, ADR-0020 A1 |
| RPM deviation unrecorded as a decision | **resolved**: ADR-0020 A2 |
| Harness messages to reword before the hardware run (audit § 5) | **resolved** (§ 4) |
| O-class developer names | **resolved** (§ 4). Census O = 0 |
| W0–W7 not merged into `develop`; no frozen RC on `develop` | **open**. Not a code defect; the orchestrator owns merges |
| Every hardware and real-session gate | **NOT EXECUTED** (§ 8) |

**Conclusion.** The code-level and document-level causes of the first G8 FAIL
are fixed on this candidate, and the automated regression is green. **G8 has
not passed.** It needs the merge to `develop`, a frozen candidate, and the
manual and hardware gates in § 8, run on that candidate. Wave 9 stays blocked
until then.
