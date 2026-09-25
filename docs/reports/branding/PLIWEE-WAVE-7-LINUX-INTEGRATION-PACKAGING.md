# Pliwee Wave 7 — Linux system integration, packaging, distribution & CI

| | |
| --- | --- |
| **Wave** | 7 — Linux system integration, packaging, distribution & CI ([plan](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md) §Wave 7, §3 G7-UP) |
| **Decisions** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) §"Legacy systemd, firewalld and desktop integration", D8, D9; plan B4 (first Pliwee version), B5 (systemd transition, decided here by measurement) |
| **Branch / base** | `feature/pliwee-rebrand-wave7`, working tree on top of `ca5f6ef` (Wave 6). Not committed: the orchestrator owns git. |
| **Date** | 2026-09-25 |
| **Host** | Fedora 44, kernel 7.2.5, systemd 259.9, rpm 6.0.2, dnf5, podman (rootless). Every cargo job ran alone, `-j 2`, `CARGO_BUILD_JOBS=2`, `RUST_TEST_THREADS=2`. Containers ran one at a time, all with `--network=none` except the Fedora `install-smoke.sh` container, which installs runtime dependencies from Fedora's mirrors by design. The public v1.0.0 Fedora assets were downloaded from the GitHub release (read-only) and verified before use (§4.17). **No VM, emulator or Gradle job was started.** |
| **Gate status** | **G7 — NOT PASSED: BLOCKED_MANUAL.** Everything a single host can measure is green (§4). G7-UP on the four distributions, the lifecycle and peer gates, the real GNOME/KDE sessions and the GitHub release-pipeline run need guests and hardware this host does not provide, and are **NOT EXECUTED** (§5). B4 needs the owner's confirmation (§1.1). |

---

## 1. Decisions taken in this wave

### 1.1 B4 — the first Pliwee version: **1.1.0, provisional**

> **Superseded 2026-09-25 (pre-Wave-8 remediation,
> `feature/pliwee-rebrand-w8-remediation`).** The owner approved **1.1.0**
> ([ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) amendment A1). The value
> is no longer provisional. Nothing in the tree changed, because 1.1.0 is what
> this wave wrote. The text below is the record as written.

The plan makes B4 an owner decision "chosen at release time", and says it
blocks the Wave 7 package bounds. The bounds cannot be written, and the upgrade
cannot be measured at all, without a version above 1.0.0: with both at 1.0.0-1,
`Breaks: omnibridge (<< 1.0.0)` does not break the installed package and a
transitional `omnibridge 1.0.0-1` is not an upgrade. ADR-0020 fixes the shape
("a 1.x version above 1.0.0"). So the tree now says **1.1.0**
(`desktop/Cargo.toml` `[workspace.package]`, the spec, `debian/changelog`, the
metainfo `<release>` marked `type="development"`), and every bound is written
against that literal. `packaging-checks.sh` pins it in one variable,
`FIRST_PLIWEE_VERSION`, and fails if it is not above 1.0.0 or is above the
workspace version.

**The owner must confirm 1.1.0 (or name another 1.x) before Wave 10 publishes
anything.** Changing it is one literal in five files, each asserted.
Nothing is published by this wave.

### 1.2 B5 — the systemd transition: **(a) an alias symlink + (b) daemon-side detection**, both, by measurement

Measured on systemd 259 (Fedora 44) with
[`pliwee-wave-7/b5-systemd-probe.sh`](pliwee-wave-7/b5-systemd-probe.sh)
(output: [`b5-systemd-probe.txt`](pliwee-wave-7/b5-systemd-probe.txt)).
Half A uses `systemctl --root` on a scratch tree; half B uses disposable units
under `$XDG_RUNTIME_DIR/systemd/user` on the live user manager, which are removed
afterwards (0 processes, 0 files left).

| # | Observation | Consequence |
| --- | --- | --- |
| A1 | `omnibridged.service` shipped as a **symlink to `pliweed.service`** in the same directory is loaded as an **alias** (`is-enabled omnibridged.service` → `alias`) | the OmniBridge enablement link in `~/.config/systemd/user/default.target.wants/` keeps working, with no scriptlet writing into a home |
| B1 | a target that `Wants=` the old name starts **one** unit, `Id=pliweed…`, `Names=` both; starting both names explicitly still leaves **1** process | exactly one daemon **by construction**; no `Conflicts=` needed, because an alias *is* the same unit |
| B2 | an OmniBridge unit **already running** when the file becomes the alias is merged into the new unit on `daemon-reload` (same MainPID); `start pliweed` then starts nothing (old binary 1, new 0) | an upgrade under a logged-in user never produces two daemons |
| A2, A4 | `systemctl --user disable pliweed.service` also removes the legacy `omnibridged.service` link | "disable works under the Pliwee name" |
| A1 | but `is-enabled pliweed.service` reports **`disabled`** while only the legacy link exists | a truthful-status gap → (b) |
| A6, A7 | `systemctl --user reenable pliweed.service` removes the legacy link and creates the canonical one; running it again changes nothing | the one-line fix, idempotent |
| A8 | a never-enabled install stays disabled | U9 invariant |

So the packages ship `/usr/lib/systemd/user/omnibridged.service → pliweed.service`
(RPM `ln -s` in `%install`; Debian `debian/pliwee.links`), and `pliweed` reads, never
writes, the account's `default.target.wants/`. When only the legacy link exists
it logs once per start: *"…still starts at login, but `systemctl --user
is-enabled pliweed.service` reports it disabled. To record it under the new
name, run once: systemctl --user reenable pliweed.service"*
(`desktop/platform-linux/src/systemd_transition.rs`, 7 unit tests). The unit
file carries **no** `Alias=`: an `Alias=` acts only on `enable`, and the accounts
that need the alias enabled the old name before it existed. `packaging-checks.sh`
asserts that no `Alias=` line comes back.

### 1.3 The package transition: a **transitional `omnibridge` package**, not `Obsoletes:` on the core — a measured deviation from the plan's RPM line

> **2026-09-25 (pre-Wave-8 remediation).** The owner approved this deviation.
> It is recorded as [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md)
> amendment A2, with the measurement below as its rationale. The text below is
> unchanged.

The plan writes the RPM transition as `Obsoletes: omnibridge < V` + `Provides:`.
Measured with the real package managers on dummy packages carrying the same
relations and file ownership
([`package-transition-probe.sh`](pliwee-wave-7/package-transition-probe.sh),
output [`package-transition-probe.txt`](pliwee-wave-7/package-transition-probe.txt)):

* On Fedora 44 the OmniBridge 1.0.0 RPM's `%preun` is
  `%systemd_user_preun omnibridged.service`. That expands to
  `systemd-update-helper remove-user-units omnibridged.service` when `$1 = 0`,
  and `remove-user-units` runs `systemctl --user -M <uid>@ disable --now` **for
  every logged-in user**.
* **R1** (the plan's `Obsoletes:` + `Provides:`): omnibridge-1.0.0 is *erased*.
  Its `%preun` runs with **`arg=0`**, so the person typing `dnf upgrade` would lose
  their enablement and their running daemon. This breaks ADR-0020's first
  invariant.
* **R2** (a transitional `omnibridge` 1.1.0 that `Requires: pliwee`, no
  `Obsoletes:`): omnibridge is *upgraded*. `%preun` runs with **`arg=1`**, nothing is
  disabled, and `pliwee` comes in as a dependency.
* **R3** (both): dnf takes the `Obsoletes:` path again (**`arg=0`**). So the core
  carries **no** `Obsoletes:` at all.
* `omnibridge-gui` 1.0.0 has no systemd scriptlet, so for it the plan's
  `Obsoletes: omnibridge-gui < 1.1.0` + `Provides: omnibridge-gui =
  %{version}-%{release}` is kept exactly.
* **RF** (the shipped shape, with real file ownership): `dnf upgrade` →
  `omnibridge-1.1.0`, `pliwee-1.1.0`, `pliwee-gui-1.1.0`. `omnibridged.service
  -> pliweed.service`; both `omnibridge.xml` and `pliwee.xml` installed;
  `rpm -V pliwee` clean; a second `dnf upgrade` → *Nothing to do*; removing the
  three and reinstalling the 1.0.0 set restores the old unit file.
* **RL**: `dnf upgrade ./files` and `dnf install ./files` both give the same
  result, with `%preun` at `arg=1`. (`upgrade` prints *"available, but not
  installed"* for `pliwee`, then installs it as a dependency.)
* **Debian/Ubuntu (D1, D2)** on `ubuntu:24.04` and `ubuntu:26.04`: with
  `Replaces:`/`Breaks:`/`Provides:` alone, `apt upgrade` upgrades **nothing**,
  because apt installs no package that nothing depends on. With transitional
  `omnibridge`/`omnibridge-gui` 1.1.0, `apt upgrade` upgrades both and installs
  `pliwee`/`pliwee-gui`, and the old postrm runs with **`upgrade`**, never
  `remove`, so debhelper's `remove` path cannot mask the unit. `apt-get upgrade`
  keeps them back, and `apt-get dist-upgrade` / `apt full-upgrade` take them.
  A second `apt upgrade` changes nothing. `debian:13` was **not** measured; no
  trixie image was cached, and nothing was pulled.

**Confirmed on the published artifact, not only on dummies.**
`rpm -qp --scripts` on the real `omnibridge-1.0.0-1.fc44.x86_64.rpm`, downloaded
and verified against `SHA256SUMS.asc` (§4.17), shows a `%preun` of
`if [ $1 -eq 0 ] … /usr/lib/systemd/systemd-update-helper remove-user-units
omnibridged.service`. `omnibridge-gui-1.0.0` has no scriptlets at all
([`v1.0.0-rpm-scriptlets.txt`](pliwee-wave-7/v1.0.0-rpm-scriptlets.txt)).
The real transaction was then run from those packages to the built Pliwee RPMs
by `install-smoke.sh` (§4.16).

The Debian packages declare `Replaces:` + `Breaks: omnibridge (<< 1.1.0~)` and the
same for `-gui`, with **no** `Provides:` of the transitional names: the name is a
real package again, and a virtual one beside it would give apt two answers.
The plan anticipated this ("a transitional `omnibridge` package if `apt
upgrade` does not pull `pliwee` otherwise (measured)"). For the RPM core
package it is a deviation, forced by ADR-0020's first invariant.

### 1.4 Desktop artwork re-pointed at the frozen masters (ADR-0020 D8; BRAND.md "the desktop from W7")

* The GTK `brand_mark` compiles in `pliwee-mark.svg` itself, and the gresource
  carries `pliwee-mark.svg` and `pliwee-mark-mono.svg` **byte for byte** under
  `/io/github/yurisismotto/pliwee`.
* The application icon (hicolor `io.github.yurisismotto.pliwee.svg`, the window
  icon, the tray `IconName`) is the new
  [`docs/design/assets/pliwee-app-icon.svg`](../../design/assets/pliwee-app-icon.svg).
  It is produced by
  [`derive_desktop_app_icon.py`](pliwee-wave-7/derive_desktop_app_icon.py),
  which copies the master's whole `<defs>` block (four paths, the clip, 13
  gradients, `<symbol id="mark">`) byte for byte and draws one
  `<use href="#mark" x="50" y="50" width="412" height="412"/>`: the same
  50-unit margin as the OmniBridge icon, and a uniform scale. It is a
  placement, not a conversion. `--check` → `SAME`. Render, old vs new:
  [`app-icon-render-old-vs-new.png`](pliwee-wave-7/app-icon-render-old-vs-new.png).
* The five masters are **unchanged**: `sha256sum -c` against the Wave 0 R4.2
  digests gives 5/5.
* The OmniBridge SVGs stay in the tree, unused and still structurally checked.
  They are not deleted in this wave.
* The QR-centre "ribbon" drawn in Cairo (`views/pairing.rs::draw_ribbon`) is
  **not** changed. It is hand-drawn geometry, and re-deriving a master as Cairo
  paths would be a redraw, which D8 forbids. It is listed in §6 for Wave 8.

---

## 2. What changed

### 2.1 Identifiers (plan §2, Wave 7 rows)

| Identifier | Before | After |
| --- | --- | --- |
| binaries (`[[bin]]`, clap `name`) | `omnibridge`, `omnibridged`, `omnibridge-gui` | `pliwee`, `pliweed`, `pliwee-gui` |
| app id / GApplication / D-Bus name / `.desktop` / `Icon=` / AppStream `<id>` / SNI `Id`+`IconName` / notification `desktop-entry` | `io.github.yurisismotto.omnibridge` | `io.github.yurisismotto.pliwee` (AppStream `<replaces>` the old id) |
| D-Bus object path, gresource prefix | `/io/github/yurisismotto/omnibridge` | `/io/github/yurisismotto/pliwee` |
| `StartupWMClass`, D-Bus `Exec=` | `omnibridge-gui` | `pliwee-gui` |
| user unit | `omnibridged.service`, `RuntimeDirectory=omnibridge` | `pliweed.service`, `RuntimeDirectory=pliwee`; **`omnibridged.service` kept as an alias symlink** (§1.2) |
| firewalld | `omnibridge.xml` | `pliwee.xml` **added**; `omnibridge.xml` kept **byte-identical** (sha256 `af8fa0c6…ab2d`, pinned) |
| packages | `omnibridge`, `omnibridge-gui` | `pliwee`, `pliwee-gui` + transitional `omnibridge` (RPM noarch; Debian `all`) and `omnibridge-gui` (Debian `all`) |
| harness / CI env | `OMNIBRIDGE_{MSRV,SIGNING_KEY,SIGNING_FPR,SCANNER_PY,ASSERT_SH,HUMAN_DISMISS,SOAK,SOAK_SECS}` | `PLIWEE_*` |
| container / buildroot / temp names | `omnibridge-rpm-buildroot`, `omnibridge-*.XXXX` | `pliwee-*` |
| artifacts | `omnibridge-<V>…`, `omnibridge_<V>…` | `pliwee-<V>…`, `pliwee_<V>…` (+ the two transitional names) |
| version | 1.0.0 | 1.1.0 (§1.1) |

Kept exactly, as the plan requires: every workflow `name:`; unit hardening,
`ProtectSystem=`, `ReadWritePaths=` (the unit's directive set differs from
`ca5f6ef` only in `Description=`, `ExecStart=` and `RuntimeDirectory=`);
`Documentation=`, `URL:`, `Homepage:`/`Vcs-*`, metainfo URLs and `copyright`
`Source:` (Wave 10); `RELEASE_SIGNING_KEY` unconfigured; the release-pubkey file
name `omnibridge-release-pubkey.asc` (Wave 10); `README.md` (Wave 10, §6).

### 2.2 Files

| Area | Files |
| --- | --- |
| Rust, identifiers | `desktop/{cli,daemon,gui}/Cargo.toml` (`[[bin]]`), `cli/src/main.rs`, `daemon/src/{main,lib}.rs`, `gui/{build.rs,src/lib.rs,src/widgets.rs,src/client.rs,…}`, `platform-linux/src/{activation.rs,tray/*.rs,lib.rs}`, `capabilities/notifications/src/backend/dbus.rs`, every "Run: omnibridge …" hint and doc comment naming a binary (targeted rules, not a global replace; script in §7) |
| Rust, new | `desktop/platform-linux/src/systemd_transition.rs` (B5 (b)), wired in `daemon/src/main.rs` |
| Rust, tests (facts changed) | `platform-linux/tests/{tray_identity,tray_dbus,tray_gnome,tray_model,dbus_activation,common/mod}.rs`, `gui/tests/brand_assets.rs` (+2 tests), `activation.rs` near-miss list (+ the OmniBridge id as a near miss), `daemon/tests/legacy_state_migration.rs` (`CARGO_BIN_EXE_pliweed`), `capabilities/notifications/tests/real_dbus.rs` (env names) |
| desktop data (`git mv`) | `desktop/gui/data/io.github.yurisismotto.pliwee.{desktop,metainfo.xml,service.in}`, `pliwee.gresource.xml` |
| installer | `desktop/gui/tools/install-desktop-metadata.sh`: Pliwee id and icon; `--uninstall` also removes the OmniBridge dev-install files **by exact name** (tested in a scratch prefix: 8 files + 1 symlink removed, an unrelated `.desktop` left) |
| artwork | `docs/design/assets/pliwee-app-icon.svg` (new, derived); `docs/design/BRAND.md` (dated W7 note, rows) |
| packaging | `packaging/common/pliweed.service` (`git mv`), `packaging/common/README.md` ("Upgrading from OmniBridge"), `packaging/fedora/pliwee.spec` (`git mv`), `packaging/fedora/pliwee-firewalld.xml` (new), `packaging/fedora/{build-rpm.sh,README.md}`, `packaging/debian/{control,changelog,rules,copyright,README.md,README.source,build-deb.sh}`, `packaging/debian/pliwee{,-gui}.install` + `pliwee.docs` (`git mv`), `packaging/debian/pliwee.links` (new) |
| release | `packaging/release/{make-source-bundle,sign-release,verify-release}.sh` |
| harnesses | `packaging/tests/{packaging-checks,install-smoke,lifecycle-gates,lifecycle-peer-gates,security-log-evidence,systemd-unit-gates,harness-selftests,release-signing-tests,release-signing-production-tests}.sh`, `lib/assert.sh`; **new** `packaging/tests/upgrade-gates.sh` (G7-UP, §5) |
| CI | `.github/workflows/{desktop-quality,linux-distro-compat,packaging-checks,release-artifacts}.yml` (`name:` values unchanged) |
| living docs | `docs/architecture/{OVERVIEW,CLIPBOARD,FILES}.md` (installed names), `desktop/gui/README.md` |
| evidence | `docs/reports/branding/pliwee-wave-7/*` |

**Defects found and fixed while doing it** (each would have been a silent
failure):

* `build-rpm.sh` extracted only `RPMS/x86_64` and `SRPMS`. The `noarch`
  transitional package, the one that makes the upgrade work, would have been
  dropped without a word. It now extracts `RPMS/noarch` and asserts the four
  files by name.
* `build-deb.sh` derived the version with `sed 's/^omnibridge-//'`, which would
  have produced a wrong version for `pliwee-1.1.0.tar.gz`.
* `lifecycle-gates.sh` installed `./omnibridge-0*.rpm`, a glob that never
  matched a 1.x version, and `./*.deb`, which would now install the
  transitional packages too. It now names the Pliwee packages, and
  `want_pkgs` is 4 per distribution.
* `lifecycle-peer-gates.sh` expected an `omnibridge1:` pairing payload. Since
  Wave 5 the daemon emits `pliwee1:` only.
* `release-artifacts.yml` counted `*.rpm`/`*.deb` (3 and 2). It now asserts every
  artifact by name, plus a total of **21** (§4.6).

---

## 3. Tests: what they assert, and what changed in them

* **`packaging-checks.sh`** gains the group *"OmniBridge -> Pliwee transition"*:
  the first-version bound; no `Obsoletes:`/`Provides: omnibridge` on the core;
  the transitional `%package -n omnibridge` (noarch, `Requires: %{name} =
  %{version}-%{release}`, empty `%files`); `Obsoletes: omnibridge-gui < 1.1.0`
  and `Provides: omnibridge-gui = %{version}-%{release}` exactly; the alias
  symlink in the spec and in `debian/pliwee.links`; no `Alias=` in the unit;
  Debian `Replaces:`/`Breaks: (<< 1.1.0~)` exactly and no `Provides:` of the
  transitional names; the transitional Debian stanzas; the changelog's top
  entry; the metainfo `<replaces>`. It also covers **both firewalld files**,
  each declaring exactly `tcp/55432`, with the legacy one pinned by sha256;
  built-package checks for the alias symlink, both firewalld files and an
  empty transitional package; `upgrade-gates.sh` in H2; and the new bundle
  inputs.
* **Mutation proof** ([`packaging-checks-mutations.txt`](pliwee-wave-7/packaging-checks-mutations.txt),
  script beside it). 14 hand-made defects, one fact each, each **REJECTED by
  its own named check**, with the tree restored and re-verified (sha256)
  after every one. Among them: `Obsoletes: omnibridge` on the core, a wrong
  gui bound, no alias (RPM and Debian), the legacy firewalld file edited or
  its port changed, a wrong `Breaks:` bound, a `Provides: omnibridge`, a
  missing transitional stanza, `RuntimeDirectory=omnibridge`, an `Alias=` in
  the unit, a missing `<replaces>`, the workspace at 1.0.0, and a
  transitional package that does not require pliwee. A first run recorded two
  cases as "NOT REJECTED": both failed the run, but not with the message the
  script expected. The expected strings were corrected and the run repeated;
  the file holds the second run.
* **`brand_assets.rs`**: 25 → **27**. The two new tests are
  `the_desktop_app_icon_is_a_placement_of_the_pliwee_master` (the icon's
  `<defs>` equals the master's byte for byte, a length floor so equality means
  something, one square `<use>`, no `preserveAspectRatio`, the dead list) and
  `the_desktop_compiles_in_the_pliwee_masters`. Changed facts: K now requires
  `pliwee-app-icon.svg` and the Pliwee geometry, and the retired-mark dead list
  in the icon path gains `omnibridge-mark` and `omnibridge-app-icon`.
  Mutation proof ([`brand-assets-mutations.txt`](pliwee-wave-7/brand-assets-mutations.txt)):
  a stretched placement, one edited gradient stop, `brand_mark` pointed at the
  OmniBridge mark, and `build.rs` pointed at the OmniBridge icon each fail
  exactly the intended test (26 passed, 1 failed).
* **`tray_identity.rs` / `dbus_activation.rs` / `tray_dbus.rs` / `tray_gnome.rs` /
  `tray_model.rs`**: the expected id and object path are now the Pliwee ones,
  because that fact changed; no assertion was removed.
  `activation.rs::the_name_must_match_exactly` keeps its five near misses,
  renamed, and **adds** `io.github.yurisismotto.omnibridge`: a stale OmniBridge
  service file must not count as Pliwee's own.
* **Security suites** (`security_certification.rs`, `control.rs`,
  `revoked_cleanup.rs`, `file_approval.rs`, `*_log_privacy`): comment text only
  (`omnibridge pair` → `pliwee pair`) in `revoked_cleanup.rs`, `file_approval.rs`
  and `control.rs`. **No assertion changed**; `security_certification.rs` is
  untouched (7/7).

---

## 4. Evidence — executed

| # | Command | Result |
| --- | --- | --- |
| 4.1 | `cargo fmt --all -- --check` | exit 0 (after `cargo fmt` reflowed two new blocks) |
| 4.2 | `cargo clippy -j 2 --offline --locked --workspace --all-targets --all-features -- -D warnings` (+ a forced re-check of `pliwee-gui`, `pliwee-proto`) | exit 0, 0 warnings, all 12 crates ([`clippy-final.txt`](pliwee-wave-7/clippy-final.txt)) |
| 4.3 | `cargo test -j 2 --offline --workspace` | **exit 0. 75 binaries, 1121 passed, 0 failed, 25 ignored.** Wave 5 recorded 75 / 1112 / 25; the **+9** are exactly `systemd_transition` (+7) and `brand_assets` (+2). `security_certification` 7/7, `portable_boundary` 11/11, `legacy_state_migration` 4 (+1 ignored), `tray_identity` 5, `dbus_activation` 11 (+1 ignored). [`rust-suites-final.txt`](pliwee-wave-7/rust-suites-final.txt), raw [`workspace-final.log`](pliwee-wave-7/workspace-final.log) |
| 4.4 | `packaging/tests/packaging-checks.sh` (static) | **129 passed, 0 failed** ([`packaging-checks-static.txt`](pliwee-wave-7/packaging-checks-static.txt)); 14/14 mutations rejected (§3) |
| 4.5 | `make-source-bundle.sh --worktree` → `packaging-checks.sh --bundle` | bundle `pliwee-1.1.0.tar.gz` + `pliwee-1.1.0-vendor.tar.xz` (270 crates, all with checksums); **159 passed, 0 failed** ([`make-source-bundle.txt`](pliwee-wave-7/make-source-bundle.txt), [`packaging-checks-bundle.txt`](pliwee-wave-7/packaging-checks-bundle.txt)). `--worktree` mode: a validation bundle, not a release one |
| 4.6 | release pipeline, expected artifact list | written into `release-artifacts.yml` by name: 2 tarballs; `pliwee-V-*.src.rpm`, `pliwee-V-*.x86_64.rpm`, `pliwee-gui-V-*.x86_64.rpm`, `omnibridge-V-*.noarch.rpm`; per Debian target `pliwee_V-*_amd64.deb`, `pliwee-gui_V-*_amd64.deb`, `omnibridge_V-*_all.deb`, `omnibridge-gui_V-*_all.deb` (×3); 3 SBOMs → **exactly 21** before `SHA256SUMS`. The workflow itself was **not run** (§5) |
| 4.7 | RPM build (offline, disposable container), `packaging-checks.sh --rpm`, rpmlint | see §4.10 |
| 4.8 | `harness-selftests.sh` | **40 passed, 0 failed** ([`harness-selftests.txt`](pliwee-wave-7/harness-selftests.txt)); every refusal still refuses under the new names |
| 4.9 | `systemd-analyze verify` (systemd 259, disposable container, stand-in `/usr/bin/pliweed` as CI does) | `pliweed.service` **rc=0**; the alias `omnibridged.service` **rc=0**; negative control without the binary → rc=1 naming it ([`systemd-analyze-verify.txt`](pliwee-wave-7/systemd-analyze-verify.txt)) |
| 4.11 | `desktop-file-validate` on the `.desktop`; `appstreamcli validate --no-net` and `appstream-util validate-relax --nonet` on the metainfo | all pass (the installer runs the last two again, as the spec's `%install` does) |
| 4.12 | `release-signing-tests.sh` (fixture keys) | **61 passed, 1 failed**. The failure is **pre-existing and not Wave 7's**: *"a key-shaped file is committed"* for the two public Android certificates `android/signing/certs/legacy-omnibridge/*.pem`. The check matches tracked `*.pem` by name, and the count of such files is **2** at `89a629f` (before the rebrand), at `HEAD~1` and at `HEAD`, so the result is identical on the committed tree. Not weakened, not exempted here; it belongs to the Android signing owner ([`release-signing-tests.txt`](pliwee-wave-7/release-signing-tests.txt)) |
| 4.13 | B5 probes; package-transition probes | §1.2, §1.3 |
| 4.14 | derivation `--check`; masters `sha256sum -c` | `SAME`; 5/5 masters unchanged |
| 4.15 | `git diff --check` | exit 0, empty ([`git-diff-check.txt`](pliwee-wave-7/git-diff-check.txt)); the untracked new files were scanned for trailing whitespace separately: none |
| 4.16 | `install-smoke.sh --image fedora:44 --upgrade-from <published omnibridge 1.0.0 + omnibridge-gui 1.0.0> <built pliwee, pliwee-gui, omnibridge 1.1.0>` | **36 passed, 0 failed** ([`install-smoke-fedora44.txt`](pliwee-wave-7/install-smoke-fedora44.txt)). A clean install: every file, the alias symlink, the unit disabled, no daemon started, both firewalld files. Then **L17 from the real 1.0.0 RPMs**: the older build installed (`omnibridge 1.0.0-1.fc44`); the upgrade exited 0 with no scriptlet error; **`omnibridge` upgraded in place to the transitional 1.1.0**; the alias present; planted trust stores in **both** `~/.local/share/omnibridge` and `~/.local/share/pliwee` byte- and mode-identical; no daemon started. Remove and reinstall leave user state alone. A container has no user session, so this is the package-transaction layer of G7-UP, **not** G7-UP |
| 4.17 | the published v1.0.0 Fedora assets | `SHA256SUMS.asc` → `GOODSIG`, `VALIDSIG E8EDE470…D134 … F545DC184E909192C3FB6F6E64963019E731BE07` (the README's primary fingerprint); both RPM digests match the signed list ([`v1.0.0-fedora-verify.txt`](pliwee-wave-7/v1.0.0-fedora-verify.txt)) |

### 4.10 RPM build

`rpmbuild -bs` then `-bb` of `packaging/fedora/pliwee.spec` over the bundle of
§4.5 (`pliwee-1.1.0.tar.gz` sha256 `f08172bf…894f`, vendor `2ec86117…23b2`).
It ran as user `builder` in a disposable container from the cached Fedora 44
buildroot image (`localhost/omnibridge-rpm-buildroot:708828`: every
BuildRequires already present; systemd 259.9, rust 1.98.1), with
**`--network=none`**. This is `build-rpm.sh`'s build stage, run without its
network-bound `dnf builddep` stage ([`rpmbuild-summary.txt`](pliwee-wave-7/rpmbuild-summary.txt),
full log [`rpmbuild.log`](pliwee-wave-7/rpmbuild.log)):

* produced **exactly four** packages: `pliwee-1.1.0-1.fc44.src.rpm`,
  `pliwee-1.1.0-1.fc44.x86_64.rpm`, `pliwee-gui-1.1.0-1.fc44.x86_64.rpm` and
  `omnibridge-1.1.0-1.fc44.noarch.rpm` (the transitional package, written to
  `RPMS/noarch`, which the old extraction loop would have lost);
* `%check`, which runs `cargo test --release` over the whole workspace:
  **75 binaries, 1121 passed, 0 failed, 25 ignored**, the same counts as the
  debug run of §4.3;
* `packaging-checks.sh --rpm` over the three binary packages: **152 passed,
  0 failed** ([`packaging-checks-rpm.txt`](pliwee-wave-7/packaging-checks-rpm.txt)).
  That covers the core files, both firewalld files, the
  `omnibridged.service -> pliweed.service` symlink read from the package
  header, the GUI files and its absolute D-Bus `Exec=`, and the transitional
  package with **0 files** and `Requires: pliwee = 1.1.0-1.fc44`. Relations
  as built: core, no Obsoletes; gui, `Obsoletes: omnibridge-gui < 1.1.0` and
  `Provides: omnibridge-gui = 1.1.0-1.fc44`
  ([`rpm-metadata.txt`](pliwee-wave-7/rpm-metadata.txt)).
  * **A false FAIL found and fixed in the harness itself.** The first `--rpm`
    run reported *"the transitional omnibridge package carries files: (não
    contém arquivos)"*: on this pt_BR host `rpm -qpl` translates its "(contains
    no files)" placeholder. That was a FAIL about the test, not the product
    (AGENTS.md). The check now counts the header's `FILENAMES` array, and
    listings run under `LC_ALL=C`. Negative control: a dummy `omnibridge`
    1.1.0 that carries one file is rejected, *"carries 1 file(s)"*
    ([`packaging-checks-rpm-negative.txt`](pliwee-wave-7/packaging-checks-rpm-negative.txt)).
* rpmlint 2.8.0 ([`rpmlint.txt`](pliwee-wave-7/rpmlint.txt)): 3 errors, 12
  warnings.
  * The errors are all `spelling-error` on the words "systemd" and "gui" in
    `%description`. The same words are in the committed 1.0.0 descriptions
    ("systemd --user", "omnibridge-gui"); no 1.0.0 rpmlint run is on record to
    compare against, so that is stated rather than claimed.
  * Warnings the Packaging v1 audit already recorded: `unstripped-binary-or-object`
    ×3 (`debug_package %{nil}`), `no-manual-page-for-binary` ×3,
    `empty-%postun`, and the two `invalid-url` Source lines.
  * New, and inherent to an empty transitional package:
    `omnibridge.noarch: no-documentation` and
    `name-repeated-in-summary OmniBridge`.

**Order of events, stated so nothing is over-claimed.** After the bundle was
cut and the RPMs built, three comment/test-name-only edits were made
(`gui/src/client.rs` and `platform-linux/src/activation.rs` doc comments, and
`tray_dbus.rs` renaming `d6_…_omnibridge_item` → `d6_…_pliwee_item`), plus
the `--rpm` check fix above. They were re-verified on the tree by `cargo fmt
--check` (clean), `cargo test -p pliwee-linux --test tray_dbus` (19/19) and
`cargo clippy -p pliwee-linux -p pliwee-gui … -D warnings` (clean). The
built binaries differ from the tree only in those comments.

---

## 5. NOT EXECUTED — with the reason

| Gate | Why not | What runs it |
| --- | --- | --- |
| **G7-UP** (§3, U0–U10) on Fedora 44, Ubuntu 24.04, Ubuntu 26.04, Debian 13 | needs four libvirt guests with a graphical session, the **published** 1.0.0 packages verified against `SHA256SUMS.asc`, and a paired peer. None was started: the resource rules for this run forbid starting VMs here, and the Wave 4 captured-state guests do not exist yet either. The package-transaction layer is measured on dummies (§1.3) and the systemd layer on this host (§1.2), and **neither is a substitute** (plan §3: "a clean-install pass is not a substitute"). | `packaging/tests/upgrade-gates.sh` — **new in this wave, never yet run**: `--stage install` (U0–U2), then the operator pairs; `--stage upgrade` (O1, U3, U4 anchored on this boot's "migrated from …" line after a pre-upgrade journal cursor, O2 = O1 field by field plus `MIGRATED_FROM` digests = O1 digests, U5, U7, U9 on a second account, U10); U6 = `lifecycle-peer-gates.sh` against the upgraded guest; `--stage negative-unreadable` (U8) on a fresh guest. Checked only with `bash -n`, H1/H2 and the self-tests of the primitives it calls |
| `lifecycle-gates.sh`, `lifecycle-peer-gates.sh` in full, `security-log-evidence.sh` | same guests; the peer gates need the Android device | the same guests, after G7-UP |
| `install-smoke.sh` on **Ubuntu 24.04, Ubuntu 26.04, Debian 13** | needs a `.deb` build per distribution (`build-deb.sh`: three more full container builds, each needing its archive's build dependencies from the network). **Fedora 44 was executed** (§4.16). The Debian packaging is therefore checked statically (`packaging-checks`) and by the apt probes (§1.3), but **no `.deb` was built in this wave**, and what `dh_installsystemduser` does with the `omnibridged.service` symlink that `dh_link` creates is **not measured** | Wave 8 build tree, or here once B4 is confirmed |
| real GNOME and KDE Plasma host: tray, D-Bus activation, `.desktop`, the reset of dock favourite / notification settings / tray visibility | no real session was driven in this run | Wave 8 real-host set |
| `release-artifacts.yml` dry run on GitHub Actions | pushing a branch or dispatching a workflow is the orchestrator's (git boundary) and publishes CI runs | the orchestrator, on the Wave 7 branch |
| `release-signing-production-tests.sh` | needs a real signed release set; the next one is the first Pliwee release | Wave 10 |
| Debian 13 in the package-transition probe | no `debian:trixie` image was cached, and nothing was pulled | G7-UP on Debian 13 |

---

## 6. Remaining `omnibridge` in the Wave 7 areas — classified

`LC_ALL=C git grep -n -i -I omnibridge -- desktop packaging .github docs/architecture`
(lowercase and mixed case). **357** lowercase-bearing lines (capitalised
product prose is not counted here; it is Wave 1's census and the living docs'
own "was OmniBridge" history):

| Count | Class | Why it stays |
| --: | --- | --- |
| 66 | wire legacy profile (`omnibridge/1`, `_omnibridge._tcp`, `omnibridge1:`, domains, `Profile::OmniBridge`) | ADR-0020 D4, accepted through v1.x (Wave 5) |
| 26 | legacy state paths (`~/.local/share/omnibridge`, `~/.config/omnibridge`, `Downloads/OmniBridge`, `.omnibridge-*.part`) | the durable D9 migration source (Wave 4) |
| 38 | `omnibridged.service` | the alias symlink, its detection (`LEGACY_UNIT`), its tests and its documentation (this wave, v1.x) |
| 20 | `omnibridge.xml` / `omnibridge-firewalld.xml` | the legacy firewalld service, kept byte-identical (v1.x) |
| 76 | `omnibridge` / `omnibridge-gui` package names | the transitional packages, the exact bounds and their checks (this wave) |
| 10 | `io.github.yurisismotto.omnibridge` | AppStream `<replaces>`, the installer's by-name removal of old dev-install files, the activation near-miss test |
| 20 | `omnibridge-*.svg` | retired artwork, no longer built; structural checks kept |
| 15 | `omnibridge-release-pubkey.asc`, the signing fixtures' scratch keyring | Wave 10 (OpenPGP UID, D6) |
| 36 | transcripts and measurements quoted verbatim, dead lists, metadata URLs `github.com/yurisismotto/omnibridge` | history (D7) and Wave 10 URLs |
| 50 | the rest, read line by line | legacy-profile test names and doc comments (`legacy_control_alpn_is_omnibridge_1`, "renamed from `omnibridge`"); neutral test payloads (`"omnibridge ordinary sentinel"`); the fake-phone state directory `/tmp/omnibridge-fake-phone`, kept so a peer's identity survives an upgrade test; the measured `omnibridge-gui` transcript in the D-Bus service header; comments explaining the transition. **None is an installed or persistent Pliwee identifier.** Three stale ones found in this pass were fixed (a `client.rs` socket-path comment, an `activation.rs` doc diagram, a `tray_dbus` test name). |

**Outside the areas, owned by later waves:** `README.md` still says OmniBridge
and documents the published v1.0.0 install, which is true until Wave 10
publishes Pliwee. Its "build from source" and CLI sections name the old
binaries; the plan gives the README to Wave 10. Also outside:
`views/pairing.rs::draw_ribbon` (§1.4, Wave 8 remainder audit).

---

## 7. Method notes

* The renames were applied by two rule scripts, each with an explicit
  exclusion list and a bare-word dry run read line by line before it was
  applied. They were not a search-and-replace. Every file's diff was then
  read. Four historical quotes the rules touched were put back verbatim (the
  `omnibridge-dbgsym` measurements in `debian/rules` and `debian/README.md`,
  the `omnibridge-release-pubkey.asc` path in a comment, `omnibridge-13
  (trixie)` in `build-deb.sh`).
* No historical document (`docs/audits`, `docs/certification`, other
  `docs/reports`, `docs/research`, `docs/migrations`, ADR-0001…0019) was
  edited.
* No scriptlet touches a home directory, a user unit, a desktop setting or a
  firewall zone. `packaging-checks.sh` R6/§9 and the new checks assert it.

---

## 8. Exit criteria

| Criterion (plan, Wave 7) | Status |
| --- | --- |
| G7-UP PASS on all four distributions | **NOT EXECUTED** (§5) |
| lifecycle and peer gates PASS | **NOT EXECUTED** (§5) |
| `packaging-checks` green | **met**: static 129/0, bundle 159/0, 14/14 mutations rejected |
| release pipeline dry-run produces the exact expected `pliwee-*` list (exact count) | **partly**: the exact list (21) is encoded in the workflow, and `build-rpm.sh`/`build-deb.sh` assert theirs by name. The Fedora half is measured locally: exactly the 4 expected RPMs (§4.10). The `.deb` half and the GitHub run are **NOT EXECUTED** |
| `install-smoke.sh` on each distribution | **Fedora 44 met** (36/0, including the upgrade from the real 1.0.0 RPMs); the three Debian-family targets **NOT EXECUTED** |
| unit tests (`tray_identity`, `dbus_activation`, `packaging-checks`, `harness-selftests`) | **met** |
| `systemd-analyze verify` on `pliweed.service` and the compatibility unit | **met** |
| `desktop-file-validate`, `appstreamcli validate` | **met** |
| B4 | **provisional 1.1.0, owner confirmation required** |

**Gate G7 — "a v1.0.0 user upgrades and notices only the name": NOT PASSED.
Wave result: BLOCKED_MANUAL.** The implementation is as ready as one host can
make it; the four-distribution upgrade, the lifecycle and peer gates, the real
desktop sessions and the owner's B4 confirmation remain.
