# Pliwee Wave 4 — Linux state & upgrade migration

| | |
| --- | --- |
| **Wave** | 4 — Linux state & upgrade migration ([plan](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md) §Wave 4) |
| **Decisions** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) D9, D11, D12 |
| **Branch / base** | `feature/pliwee-rebrand-wave4`, working tree on top of `140499e` (Wave 3). Not committed: the orchestrator owns git. |
| **Date** | 2026-09-24 |
| **Host** | Fedora 44, kernel 7.2.5, **1 CPU**, 15 GiB RAM, rustc/cargo stable. Every cargo job ran alone, one after another: `-j 2`, `CARGO_BUILD_JOBS=2`, `RUST_TEST_THREADS=2`. No VM, emulator or Gradle job was started. |
| **Gate status** | **G4 unit + daemon-binary evidence: PASS. Integration on captured real v1.0.0 state (four distributions): NOT EXECUTED → wave result BLOCKED_MANUAL.** |
| **Revision** | 2026-09-24, after a read-only audit (AUDIT_RESULT: FAIL). It found that §4 was never filled in and cited counts from the failed first run, that the mutation checks had no recorded output, and that `gui.json` deviated from ADR-0020 D9. All three are fixed below: `gui.json` now follows D9 (§1.3), and every claim in §2–§4 points to a file in `pliwee-wave-4/` produced on the final tree. |

## 1. What changed

### 1.1 Paths (plan §2, Wave 4 rows)

| Class | Before | After | Migration |
| --- | --- | --- | --- |
| Data (identity + trust store) | `$XDG_DATA_HOME/omnibridge` | `$XDG_DATA_HOME/pliwee` | **copy** from legacy, §1.2 |
| GUI config | `$XDG_CONFIG_HOME/omnibridge/gui.json` | `$XDG_CONFIG_HOME/pliwee/gui.json` | copy on first GUI start, §1.3 |
| Runtime dir / socket | `$XDG_RUNTIME_DIR/omnibridge/control.sock`, `/tmp/omnibridge-<uid>` | `$XDG_RUNTIME_DIR/pliwee/control.sock`, `/tmp/pliwee-<uid>` | none (volatile; D9) |
| Desktop downloads | `~/Downloads/OmniBridge` | `~/Downloads/Pliwee` | none: old dir never moved/deleted; `.omnibridge-*.part` leftovers are **listed in `status`**, never removed |
| Cache / logs | none on disk | none added | — |

`XDG_*` resolution: one function, `pliwee_core::platform::unix_fs::xdg_base`, now resolves
both the Pliwee and the legacy directory. A **relative** `XDG_DATA_HOME` is now ignored
(HOME fallback), as the XDG spec requires and plan case (f) asks. Before, the data dir
took a relative value literally; the config dir already ignored it.

### 1.2 The data-dir migration algorithm (`desktop/platform-linux/src/legacy_migration.rs`)

This implements the plan's steps 1–5:

1. `P = <base>/pliwee`, `L = <base>/omnibridge`, from the same base.
2. If `P` holds `identity.key` **or** `state.json`, use `P` and never look at `L`. If `P`
   cannot be examined (e.g. EACCES), that is an error, not "no".
3. If `L` exists (`symlink_metadata`, so a **broken symlink** counts as existing and then
   fails): it must be a directory with no group/world bits. Its identity is classified by
   the same read-only `Store::probe_identity` the store uses. `Available` → copy.
   Any other state (lost, corrupt, unreadable, loose key mode) → **error naming `L`**, and
   nothing is written. Both files positively absent → no identity, so first run.
   The copy goes into `.pliwee-migrating-<pid>-<ts>` next to `P`: directory 0700, files
   0600 created `O_EXCL`, each fsynced. `MIGRATED_FROM` holds the source, a timestamp and
   the SHA-256 of both files. The copies are read back and hash-checked, the staging dir is
   fsynced, then **one `rename(2)`** moves it to `P`, and the parent is fsynced. `L` is
   opened read-only and never re-moded.
4. No `L` → first run (the store creates the identity, as before).
5. Idempotent: a second start sees `P` populated and writes nothing.

Crash handling: a crash before the rename leaves no `P`, only a staging dir. The next
start removes our own stale staging dirs (they hold a key copy) and redoes the copy. If
the rename fails (e.g. `P` exists, has no identity, and is not empty), startup refuses
naming `P` and the staging copy is deleted.

**Where it lives.** The plan suggests `core/src/platform/legacy_migration.rs (or
equivalent)`. It was first written there, and the `portable_boundary` gate refused it:
a portable crate may not name `std::os::unix` outside a listed exception. Rather than
widen that exception, the module moved to the Linux adapter crate, `pliwee-linux`.
OmniBridge 1.0.0 only ever shipped on Linux, so the portable core has nothing to migrate.
The gate is unchanged.

**The legacy-mode rule.** "Private" means what v1.0.0 itself enforced: the directory has
no group/world bits and `identity.key` is private. `state.json`'s own mode is not
checked, because v1.0.0 never checked it on read. Being stricter would turn a working
install into a refusal. Copies are written 0600 regardless.

### 1.3 `gui.json`

`Selection::load()` calls `migrate_config_file`: the canonical file wins; a legacy file
is copied (0600, write-then-rename, fsync) and left in place.

An existing legacy `gui.json` that cannot be read (or examined, or is not a regular file)
**stops the GUI**, as ADR-0020 D9 requires for config ("same rules"). `pliwee_gui::run()`
loads the selection before the application is built. On error it prints
`pliwee: refusing to start: <legacy gui.json>: …` and exits with a failure code. No
window opens and no Pliwee file is created.

*Superseded in this revision:* the first implementation logged the error and started
with an in-memory, non-persisting selection. That was a deviation from D9 with no
approval, and it was removed. The application tests use `Selection::unmigrated()`, which
reads the canonical path without migrating, so a test run never copies a developer's
real config.

### 1.4 Startup and reporting (Allowed: "status / CLI reporting of 'migrated from …'")

- `omnibridged` (binary name unchanged until W7) runs the migration before
  `open_store` when no `--data-dir` is given. An explicit `--data-dir` is used as given.
- Log lines (G7-UP U4 anchor):
  `migrated from <L>: identity and trust store copied into <P>; the source directory was not modified`
  on the migrating start, and `local state was migrated from <L> by an earlier start; nothing to migrate` on later starts.
- On refusal the daemon logs `refusing to start: <L>: … Pliwee will not create a new identity …` and exits non-zero before binding anything.
- `StatusReport` gains `migrated_from: Option<MigrationReport>` (`source`, `migrated_at_unix`,
  `this_run`) and `legacy_partial_files: Vec<String>`, both `#[serde(default)]` so mixed
  client/daemon builds still parse. `omnibridge status` prints them.

### 1.5 Files

| File | Change |
| --- | --- |
| `desktop/platform-linux/src/legacy_migration.rs` (new) | migration module + unit cases (a)–(f), config rule |
| `desktop/platform-linux/src/lib.rs` | re-exports; runtime dir `pliwee`, `/tmp/pliwee-<uid>`; seam + test for the fallback |
| `desktop/platform-linux/Cargo.toml`, `desktop/Cargo.lock` | `sha2` (already in the graph; one lock edge) |
| `desktop/core/src/platform/unix_fs.rs` | `xdg_base`; `default_data_dir()` → `…/pliwee` |
| `desktop/core/src/store.rs` | doc comment only |
| `desktop/capabilities/files/src/{destination,sink}.rs` | `DOWNLOAD_SUBDIR = "Pliwee"`, `LEGACY_DOWNLOAD_SUBDIR`, `legacy_partial_files()` + tests; the default-subdir test now asserts `Pliwee` (the fact changed) |
| `desktop/daemon/src/main.rs` | migration before `open_store`; leftover `.part` scan; `LocalStateReport` |
| `desktop/runtime/src/{state,server}.rs` | `LocalStateReport` in `DaemonState`; fields in `build_status` |
| `desktop/control/src/lib.rs` | `StatusReport` fields, `MigrationReport` |
| `desktop/cli/src/main.rs` | prints migration + leftovers in `status` |
| `desktop/gui/src/selection.rs` | canonical path + `gui.json` migration; `load()` returns the refusal; two tests (refusal creates nothing; legacy choice carried over) |
| `desktop/gui/src/lib.rs` | `run()` refuses to start on a `gui.json` migration error; `App::bare`/`start` take the loaded selection |
| `desktop/gui/src/panel/{mod.rs,model/tests.rs}` | new fields in test fixtures |
| `desktop/daemon/tests/legacy_state_migration.rs` (new) | daemon-binary G4 tests, and the captured-state gate (`#[ignore]`) |
| `desktop/gui/README.md`, `docs/design/BRAND.md` | one living-doc line each (socket path; download-dir example) |

No wire constant, schema, key, certificate, unit file, package or historical document was
touched. The five brand masters in `docs/design/assets/` are unchanged (not in the diff).

## 2. Unit cases (a)–(f): `cargo test -p pliwee-linux --lib`

| Case | Test(s) | Result |
| --- | --- | --- |
| (a) `P` empty + valid `L` → copied, fingerprint equal | `a_valid_legacy_identity_is_copied_and_keeps_its_fingerprint` (same fingerprint and device id; bytes identical; hashes recorded; 0700/0600; no staging left; `L` snapshot identical: name, hash, mtime ns, mode) | pass |
| (b) `P` populated + `L` present → `L` ignored | `a_populated_canonical_directory_wins_and_the_legacy_one_is_ignored` (`L` made 0000, so any read would fail; `P` snapshot unchanged) | pass |
| (c) `L` unreadable → error naming path, nothing in `P` | EACCES dir, EACCES key, broken symlink, dir 0755, key 0644, incomplete, corrupt `state.json`, a file where the dir belongs. Each asserts `err.path == L`, the message names `L`, **`P` does not exist**, no staging left, `probe_identity(P) == NotCreated` | pass (8 tests) |
| (d) crash between copy and rename | `a_crash_between_copy_and_rename_…` (a panic in the pre-rename hook skips all cleanup, like process death: then no `P`, 1 staging dir, `P` probes `NotCreated`; the next start migrates, same fingerprint/id, staging removed, `L` unchanged); plus `a_failed_rename_into_a_non_empty_canonical_directory_…` | pass |
| (e) second start is a no-op | `a_second_start_is_a_no_op` (snapshots of `P` and `L`, with ns mtimes, equal after the second call) | pass |
| (f) `XDG_*` unset / relative → HOME fallback for both | `unset_or_relative_xdg_falls_back_to_home_for_both_directories` (data and config, via a pure resolver: mutating the env would race other tests) | pass |

Also: an empty legacy dir is a first run; no legacy dir writes nothing; `P` not traversable
is an error; record round-trip; three `gui.json` cases.

Final-tree result: `pliwee_linux src/lib.rs passed=39 failed=0` in
[`rust-suites-final.txt`](pliwee-wave-4/rust-suites-final.txt): 21 migration tests plus 1
runtime-fallback test, on top of Wave 3's 17.

**Mutation check M1 (the tests can fail)**, recorded in
[`pliwee-wave-4/mutation-m1-unit.txt`](pliwee-wave-4/mutation-m1-unit.txt) with the exact
diff. The mutation replaces the `L`-examine and `L`-metadata refusals and the probe
refusal in `migrate_data_dir` with `Ok(NoLegacyState)`. The result is
`15 passed; 6 failed`, exit 101. The failing tests are the broken-symlink, corrupt-state,
non-private-key, incomplete-identity, unreadable-directory and unreadable-key cases. The
file was then restored and verified with `cmp`.

**Mutation check M3 (`gui.json` refusal).** With `migrate_config_file(&files)?` in
`Selection::load_from` replaced by `.unwrap_or(ConfigOrigin::NoLegacyState)`,
`an_unreadable_legacy_choice_refuses_to_load_and_creates_nothing` **FAILED**
(`13 passed; 1 failed`). The file was restored and verified with `cmp`. This check was
run interactively and its output was not saved to a file. The test itself is in the
final-tree run: `pliwee_gui src/lib.rs passed=142`.

## 3. Daemon-binary evidence: `cargo test -p pliwee-daemon --test legacy_state_migration`

The real `omnibridged` binary runs as a process with `env_clear()`. `HOME` is a scratch
dir, **`XDG_DATA_HOME` is unset** (the packaged resolution), `XDG_RUNTIME_DIR` is a
scratch 0700 dir, and the session bus is pointed at a nonexistent socket so nothing
touches the real desktop session. It is queried over its control socket.

| Test | Observations |
| --- | --- |
| `an_omnibridge_identity_is_carried_over_and_never_regenerated` | Legacy state written by `Store::open` (v1.0.0's code path): one granted peer (`clipboard.v1`, `files.v1`) with non-default clipboard and notification policies, and one revoked peer. **O1** is read from the store. First start: the anchor log line `migrated from <L>: identity and trust store copied` is present; `status` fingerprint, device id, paired count (exactly 1) and per-peer grants **equal** O1; `migrated_from.this_run == true`; `L`'s SHA-256 set is unchanged; the full serialized peer list (policies and revocation included) from `P` equals O1's. Second start: no migrate line, the "earlier start" line is present, same fingerprint/id/count, `MIGRATED_FROM` byte-identical, `L` unchanged. |
| `unreadable_legacy_state_refuses_to_start_and_creates_no_identity` | **G4 negative.** `L` is 0000. Observation 1: no `P/identity.key`. The daemon exits non-zero, and its output names `L`. Observation 2: no `P/identity.key`, **no `P` at all**, no control socket. |
| `a_fresh_home_is_a_first_run_under_the_pliwee_directory_only` | no `L` → identity is created under `pliwee`; no `omnibridge` dir is created; `migrated_from` is `None` |
| `interrupted_omnibridge_transfers_are_reported_and_left_in_place` | `~/Downloads/OmniBridge/.omnibridge-00ff.part` is reported exactly (one entry); the file and a finished file are untouched; `~/Downloads/Pliwee` is created |
| `captured_v1_0_0_state_is_carried_over` (`#[ignore]`) | the integration gate on real captured state (§5). Without `W4_CAPTURED_STATE` it **fails** with `NOT EXECUTED: W4_CAPTURED_STATE is not set` (verified). It is never green over nothing. |

Final-tree result: `legacy_state_migration.rs passed=4 failed=0 ignored=1`.
[`captured-gate-without-input.txt`](pliwee-wave-4/captured-gate-without-input.txt) shows
the ignored gate, run with `W4_CAPTURED_STATE` unset. It printed
`NOT EXECUTED: W4_CAPTURED_STATE is not set` and exited 101.

**Mutation check M2**, recorded in
[`pliwee-wave-4/mutation-m2-daemon.txt`](pliwee-wave-4/mutation-m2-daemon.txt). The
daemon's `migrate_data_dir` call was replaced by `Ok(DataDirOrigin::NoLegacyState)`. The
result is `2 passed; 2 failed; 1 ignored`, exit 101. Both G4 tests failed: the carry-over
test and the refusal test. The refusal test ran past the 60 s deadline because the
daemon kept running on unreadable legacy state. The file was then restored and verified
with `cmp`.

Caveat: this legacy state is written by the same code path v1.0.0 used. It is **not**
state captured from a packaged v1.0.0 install, and the plan says "Test fixtures come
from real installs, not synthesised JSON". §5 covers that.

## 4. Regression

| Command | Result |
| --- | --- |
| `cargo fmt --all -- --check` | exit 0 on the final tree ([`fmt-final.txt`](pliwee-wave-4/fmt-final.txt)) |
| `cargo clippy --locked --workspace --all-targets --all-features -j 2 -- -D warnings` | exit 0, 0 warnings on the final tree ([`clippy-final.txt`](pliwee-wave-4/clippy-final.txt); incremental, so only `pliwee-gui` was rechecked, and cached crates replay their diagnostics) |
| `cargo test --workspace --no-fail-fast -j 2`, first run | **exit 101: 1 failure.** `portable_boundary::the_portable_crates_name_no_platform_outside_a_feature_gated_module` refused `core/src/platform/legacy_migration.rs`. Fixed by relocating the module (§1.2), not by editing the gate. Only the per-suite counts of this run survive: [`rust-suites-first-run-failed.txt`](pliwee-wave-4/rust-suites-first-run-failed.txt) (`TOTAL … passed=1083 failed=1`; the 21 migration tests are still counted under `core src/lib.rs`). The raw log was not kept. |
| `cargo test --workspace --no-fail-fast -j 2`, final tree (2026-09-24 23:01, base `140499e`) | **exit 0.** `TOTAL binaries=73 passed=1085 failed=0 ignored=25`. `portable_boundary passed=11 failed=0`. Raw log: [`workspace-final.log`](pliwee-wave-4/workspace-final.log). Counts: [`rust-suites-final.txt`](pliwee-wave-4/rust-suites-final.txt) |
| `git diff --check` | exit 0 ([`git-diff-check.txt`](pliwee-wave-4/git-diff-check.txt)) |

Against Wave 3's `rust-suites-after.txt` (1055 passed, 24 ignored, 72 binaries), the
final run adds +30 passed and +1 ignored:

- `capability_files src/lib.rs`: +2.
- `legacy_state_migration.rs`: a new binary, +4 passed and +1 ignored.
- `gui src/lib.rs`: +2.
- `linux src/lib.rs`: +22.

No other suite changed, and no suite lost a test. The run finished before the M1 and M2
mutations. Both mutated files were restored byte-identical (`cmp`), so the final tree is
the tree that was tested.

The security suites (`security_certification`, `control`, `revoked_cleanup`,
`file_approval`, the two log-privacy suites) were not edited. Their final counts are in
`pliwee-wave-4/rust-suites-final.txt`, in the same format as Wave 3's (produced by
`pliwee-wave-3/g3_suite_counts.py`) and identical to Wave 3's.

Not run: Android (no Android file changed); `packaging/tests/*` and any RPM/deb build
(W7's gates; no packaging file changed); the Windows MSVC job (CI only; the new module
is in the Linux adapter, and `portable_boundary` passes).

## 5. NOT EXECUTED — integration on captured real v1.0.0 state (exit criterion)

The plan's exit criterion needs "the integration run on all four captured states". Each
capture comes from the **packaged** v1.0.0 on Fedora 44, Ubuntu 24.04, Ubuntu 26.04 and
Debian 13 guests: daemon started, **paired with a peer**, grants and policies set, and
`~/.local/share/omnibridge` + `~/.config/omnibridge` archived with hashes.

**Status: NOT EXECUTED. Reason:** it needs four guest VMs booted, a package install and
a real pairing (human or `fake_phone` confirmation) in each. The four guests exist in
`qemu:///system` (`anyflow-f44-kde`, `anyflow-u2404`, `anyflow-u2604`, `anyflow-d13`,
all shut off), and `omnibridge{,-gui}-1.0.0-1.fc44.x86_64.rpm` are in `~/Downloads`.
But this run was told stability is a hard requirement after a previous workstation
freeze, on a 1-CPU host. This is the wave's declared hardware gate, left to the
operator. No capture was synthesized to stand in for it.

**Operator runbook, per distribution:**

1. On the guest, install the published `omnibridge` + `omnibridge-gui` 1.0.0 packages
   (verified against `SHA256SUMS.asc`) and run
   `systemctl --user enable --now omnibridged.service`.
2. Pair a peer, grant `clipboard.v1` and `files.v1`, set a clipboard policy and a
   notification lock policy, and select the peer in the GUI. Archive `omnibridge status`
   and `omnibridge devices`.
3. `tar -C ~/.local/share -cpf omnibridge-data.tar omnibridge` (and the same for
   `~/.config/omnibridge`). Record `sha256sum` of `identity.key`, `state.json`,
   `gui.json`. Copy the archives to the host.
4. On the host: `tar -xpf omnibridge-data.tar -C <dir>`, then
   `W4_CAPTURED_STATE=<dir>/omnibridge cargo test -p pliwee-daemon --test legacy_state_migration -- --ignored captured`.
   PASS requires the capture to hold ≥ 1 paired peer (asserted). The test checks
   fingerprint, device id, exact paired count, per-peer grants, the full peer records
   (policies, tombstones), the anchor log line, an unchanged `L`, and a no-op second
   start.
5. Compare the archived `omnibridge status` text with the test's O1 values by hand
   (fingerprint, device id). That is the independent observation.

## 6. Decisions and risks for review

- **Inter-wave inconsistency, owned by W7.** The packaged unit
  `packaging/common/omnibridged.service` still says `RuntimeDirectory=omnibridge`
  (plan §2: "4 (code) · 7 (unit `RuntimeDirectory=`)"). Under that unit's
  `ProtectSystem=strict` the W4 daemon cannot create `$XDG_RUNTIME_DIR/pliwee`. So a
  package built from this tree and started by systemd would have **no control socket**.
  `packaging-checks.sh`, `systemd-unit-gates.sh` and the lifecycle gates still pin the
  `omnibridge` runtime path. Nothing is released before W8, and W7 must change the unit
  and those gates together. `ReadWritePaths=%h/.local/share` already covers
  `~/.local/share/pliwee` and the staging dir, so data migration is **not** affected.
- **`gui.json` unreadable-legacy behaviour** now follows D9 and stops the GUI (§1.3). The
  earlier soft-start deviation was removed rather than left for approval.
- **Relative `XDG_DATA_HOME`.** A v1.0.0 install that ran with a *relative*
  `XDG_DATA_HOME` stored its identity relative to the daemon's working directory. The new
  resolver ignores relative values (XDG spec, plan case (f)), so it looks for `L` under
  `$HOME`. Such an install would not be found and would get a first run. This is judged
  vanishingly rare (systemd user units don't set it; the unit's `ReadWritePaths` only
  covers `~/.local/share`), and is not handled.
- **Downgrade asymmetry** (ADR-0020 D9): pairings made after migration exist only in `P`.
  Documented there, not solved.
- `--data-dir` bypasses migration by design.

## 7. Legacy identifiers intentionally preserved

- `omnibridge` as `LEGACY_DIR_NAME`, and `OmniBridge` as `LEGACY_DOWNLOAD_SUBDIR` /
  `.omnibridge-` prefix: legacy **sources**, durable per D11.
- Binaries `omnibridge`, `omnibridged`, `omnibridge-gui`, `#[command(name=…)]`, and the
  "Run: omnibridge …" hints: W7.
- `packaging/**` (unit `RuntimeDirectory=omnibridge`, harness paths): W7.
- ALPN, mDNS, QR, domain separators, cert CN: W5. Android paths and packages: W6.
- `daemon/examples/fake_phone.rs` default dir `/tmp/omnibridge-fake-phone`: a dev tool's
  own state, not a product path in plan §2. Left for W7's harness rename.

## 8. Exit criteria

| Criterion | Status |
| --- | --- |
| cases (a)–(f) green | **met** on the final tree (§2, §4: `workspace-final.log`) |
| integration on all four captured v1.0.0 states: identical fingerprint, device id, peer count, grants | **NOT EXECUTED** (§5). The harness is ready and refuses without input. |
| G4: no identity regenerated while legacy state exists; two observations; unreadable → zero new identities | **met at unit and daemon-binary level** (§2 (c), §3). Not yet on real captured state. |

**Wave result: BLOCKED_MANUAL.** The implementation and every automatable check are done.
The remaining exit criterion needs the four-guest capture in §5.
