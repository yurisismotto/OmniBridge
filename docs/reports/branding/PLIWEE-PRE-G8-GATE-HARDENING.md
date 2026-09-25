# Pliwee rebrand — pre-G8 gate hardening

| | |
| --- | --- |
| **What this is** | A harness-only hardening done after the [pre-W8 remediation](PLIWEE-PRE-W8-REMEDIATION.md) and before the G8 re-run. G7-UP could not be executed in the order the plan requires. This change fixes that, and adds one operator coordinator for the manual and hardware gates. **This is not a certification. No gate was executed. G8 is not claimed.** |
| **Problem** | `packaging/tests/upgrade-gates.sh --stage upgrade` recorded U6 as n/a and then ran U7, U9 and **U10 (the downgrade)**. The plan ([§3](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md)) requires U6 (the peer reconnects without re-pairing, a clipboard round-trip and a file) against the **upgraded** Pliwee guest, **before** U10. |
| **Decision** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md) (unchanged) |
| **Branch / base** | `feature/pliwee-pre-g8-gate-hardening`, working tree on `e68f332`. Not committed: the wrapper owns git |
| **Date** | 2026-09-25 |
| **Host** | Fedora Linux 44 Workstation, kernel 7.2.5-200.fc44, 2 CPUs, 15 GiB RAM, GNU bash 5.3.9, Python 3.14.7. **No VM, emulator, container, Gradle or cargo job was started. Nothing was done on the attached Android device. No signing key was provisioned.** One test suite ran at a time. |
| **Evidence** | [`pliwee-pre-g8-gate-hardening/`](pliwee-pre-g8-gate-hardening/) (§ 7) |
| **Result** | **HARDENING: PASS.** G7-UP now runs in §3 order. U10 refuses unless it can verify a real U6 PASS on the same distro, domain, run and guest. It refuses before the guest is contacted. Every exact assertion G7-UP had is still there, word for word (95 of 95 lines). The coordinator exists and is self-tested. Self-tests 80/0 and 62/0, static checks 136/0, mutation proof 16 of 16 caught. The manual and hardware gates are still **NOT EXECUTED**. |

> **Superseding note — 2026-09-25, hardening repair (§ 9).** An audit of this
> pass found two defects in the coordinator and one overclaim here.
> (A) A gate recorded `--not-executed` could still be run, and when it was,
> its prerequisites were not checked. That let SECLOG run after U10, and U10
> run before SECLOG was decided. (B) `--not-executed` could replace a measured
> FAIL. And "the manual and hardware gates" above means **only the 37 gates
> listed in § 2**. Several gates in pre-W8 § 8 are not driven by the
> coordinator. § 9 repairs A and B, names what stays outside, and gives the new
> test counts. The counts in this table are the first pass's and are left as
> measured.

---

## 1. G7-UP, as five stages

| Stage | Steps | Starts only if | Ends with |
| --- | --- | --- | --- |
| `--stage install` | U0 U1 U2 (automated half) | the guest has no OmniBridge/Pliwee packages or state | the operator pairs **the physical Android peer**, exactly one, and completes U2 |
| `--stage upgrade` | O1 U3 U4 O2 U5 U7 U9 | `--new-pkgdir`, `--old-pkgdir` with `SHA256SUMS`, and no earlier checkpoint in this `--evidence` (all checked before U0) | `UPGRADE-CHECKPOINT` written, and a **stop with the guest on Pliwee**. There is no U10 in this stage |
| `--stage peer-u6` | U6 | a checkpoint for this distro and domain that verifies and records 0 failed checks, and U10 not started. Checked before U0. After U0 it also checks that the live guest has the same machine-id, still has `pliwee` installed and running, and shows the same local fingerprint | `lifecycle-peer-gates.sh`'s log, and `U6-RESULT` binding its exit code and digests to the checkpoint |
| `--stage downgrade` | U10 | `g7up_verify_u6` accepts the evidence, U10 has not started, and `--old-pkgdir`'s `SHA256SUMS` is the one the upgrade recorded (all checked **before U0**). After U0, the same live-guest checks as `peer-u6` | the U10 block, unchanged. `U10-STARTED` is written just before the downgrade, so an interrupted downgrade cannot be run a second time |
| `--stage negative-unreadable` | U8 | unchanged: a fresh guest with its own `--evidence` | unchanged |

The U10 block was moved out of the upgrade stage verbatim. It reads O1 from
`O1-facts.txt`, and it refuses to run if that file's digest differs from the
one the checkpoint recorded.

### 1.1 What makes a U6 PASS (`lib/g7up-evidence.sh`)

`g7up_verify_u6 EVIDENCE DISTRO DOMAIN` accepts U6 only when **every** check
below holds. It prints the first check that fails.

1. `UPGRADE-CHECKPOINT` exists, is not trivially short, says
   `stage=upgrade` and `status=complete`, and names this distro and this
   domain. It carries a run id, a machine-id, a fingerprint, the O1 and old-set
   digests and a completion time, and `O1-facts.txt` matches its digest.
2. The upgrade stage recorded `upgrade_not_ok=0`.
3. `U6-RESULT` exists, is not trivially short, and says `stage=peer-u6`. It
   names this distro and this domain. Its run id, machine-id and fingerprint
   equal the checkpoint's. It started after the checkpoint completed, with
   `exit=0` and `verdict=PASS`.
4. The U6 log matches the digest recorded in `U6-RESULT`. It is at least 20
   lines. It has no `PRECONDITION FAILED` and zero `not ok` lines. It has
   exactly one `DISTRO / DOMAIN:` tally, and that tally reports ≥1 passed and
   0 failed.
5. The log has every observation U6 needs. Each is a line that
   `lifecycle-peer-gates.sh` prints only after measuring it:

   | U6 row | Anchor |
   | --- | --- |
   | no re-pairing | `the phone is already paired with this guest` |
   | reconnect | `the phone is connected to …`, `the newest session event is this peer's establishment` |
   | the peer sees the O1 identity | `the phone shows this guest's fingerprint` |
   | clipboard round-trip | `L14: guest -> phone clipboard send exited 0`, `L14: the phone shows 'Clipboard from …`, **and** `L14: phone -> guest arrived / recorded` |
   | a file | `L15: the guest reports the transfer completed`, `L15: N journal line(s) name transfer=<id>`, `L15: … the peer confirming it stored THIS transfer` |

6. `29-peer-identity.txt` matches its recorded digest. It names this distro and
   this domain, and its fingerprint equals the checkpoint's.
7. `43b-L15-journal.txt` contains `transfer=<id>`, where `<id>` is the one the
   log names.

Two consequences, both intended:

* **A one-way clipboard is not a round-trip.** When the Android clipboard is
  empty, `lifecycle-peer-gates.sh` records phone → guest as n/a, and adb cannot
  set that clipboard. The operator therefore copies some text on the phone
  before U6. The stage and the coordinator both say so.
* **U6 needs all of `lifecycle-peer-gates.sh` to pass**, including L16. That is
  stricter than the U6 row alone. The plan names that script as U6, and its
  exit status was the existing contract.

## 2. The operator coordinator: `packaging/tests/pre-g8-manual-gates.sh`

It runs one gate per invocation, with a state record per gate, under an
`--evidence` directory. The default is
`${XDG_STATE_HOME:-~/.local/state}/pliwee-pre-g8`. A directory inside the
source tree is refused.

| Gate | Drives | Changes something? |
| --- | --- | --- |
| `W2-GNOME`, `W2-KDE` | Wave 2 §7 procedure, recorded item by item (y/n) plus the exact screen-reader announcements. The session named must be GNOME or KDE respectively. PASS needs every item `y` and a `Files for …` announcement | no |
| `W6-SIGNING` | `android/signing/provision-signing-keys.sh`, run with the terminal's own stdio. It refuses without a terminal on stdin and stdout, and refuses if `PLIWEE_SIGNING_SELFTEST_ROOT` is set. Only `--status` output (public) is kept. PASS needs `backups restore-verified:` in it | signing media — confirmed |
| `W6-COMPONENT-UPGRADE` | N → N+1 on `--adb-serial`. The APKs are either supplied (`--apk-n/--apk-n1`) or built. N+1 is built with `-Pandroid.injected.version.code`, and the tree's `versionCode` is **not edited**. aapt2 must show the same package and a higher versionCode, so an ignored override fails. Observations: listener approval, live binding, QS tile, installed versionCode (it must move N → N+1) and a screenshot. The operator types `PINNED` before the upgrade and confirms the same shortcut afterwards | device — confirmed twice |
| `W6-INSTRUMENTED` | `ANDROID_SERIAL=… ./gradlew --max-workers=2 :app:connectedDebugAndroidTest`. PASS needs exit 0, result XML written by **this** run, more than 0 tests, and 0 failures and 0 errors | device — confirmed |
| `G7UP-<d>-INSTALL` | `upgrade-gates.sh --stage install`. Keyring and fingerprint are required: U1 cannot pass without them | VM — confirmed |
| `G7UP-<d>-U2` | operator attestation of the U2 hand steps. The upgrade stage then measures them | no |
| `G7UP-<d>-UPGRADE` | `--stage upgrade`. PASS needs the checkpoint to verify | VM — confirmed |
| `G7UP-<d>-U6` | `--stage peer-u6`. PASS needs `g7up_verify_u6`, **not** the exit code alone | VM + device — confirmed |
| `G7UP-<d>-SECLOG` | `security-log-evidence.sh` on the upgraded guest. It can only run before U10 | VM + device — confirmed |
| `G7UP-<d>-U10` | `--stage downgrade`. Refused until `g7up_verify_u6` passes on the evidence itself **and** SECLOG has been run or recorded not-executed | VM — confirmed |
| `G7UP-<d>-U8` | `--stage negative-unreadable` on `--u8-domain`. The upgrade guest is refused, and the operator types the fresh guest's **name** to designate it | VM — confirmed by name |
| `LIFECYCLE-<d>` | `lifecycle-gates.sh` on `--lifecycle-domain`, a fresh guest, confirmed by name | VM — confirmed by name |

`<d>` stands for each of `fedora44`, `ubuntu2404`, `ubuntu2604` and `debian13`,
so there are 37 gates in total.

> **Superseding note — 2026-09-25, hardening repair (§ 9.3).** These 37 gates
> are everything the coordinator drives. SEC and the clipboard, files and
> notifications hardware certifications are separate. So are
> `systemd-unit-gates.sh`, signed-bundle verification, and the QR, tray and
> D-Bus session checks. A full `lifecycle-peer-gates.sh` run outside U6 is
> separate, as is the network matrix, the container builds and Play and
> repository migration (W9/W10). Each keeps its own procedure. The "BLOCKED —
> recorded not-executed" state below did **not** stop that gate from being
> run, and did not make it check its prerequisites (§ 9.1).

**States.** A gate is in one of four states:

* **PASS** — the gate's own script exited 0, its log is clean, and the anchor
  lines are present. The evidence is re-verified every time the status is
  read. A log changed after the fact makes the gate **FAIL**, and so does a U6
  record that no longer verifies.
* **FAIL** — the gate ran and did not pass.
* **PENDING** — the gate can run now.
* **BLOCKED** — one of:
  * a prerequisite has not passed;
  * the run was interrupted;
  * provisioning is in progress;
  * the gate was recorded not-executed, which needs a reason;
  * the record came from a self-test. A real run never counts those.

**Commands.**

* `--status` and `--list` show the gates.
* `--run GATE` runs one gate. `--rerun` allows running a gate that already has
  a result.
* `--next` resumes an interrupted gate first. If there is none, it runs the
  first PENDING gate.
* `--not-executed GATE --reason TEXT` records a gate as not executed.
* `--reset-distro D` moves a distro's G7-UP chain into `superseded/` after a
  snapshot restore. Nothing is deleted.

**Safety.** Before any action on a VM, the device or the media, the
coordinator prints the exact command. It then reads the answer from
`/dev/tty`, never from a pipe. EOF, or any answer other than the token, exits 5
and changes nothing. There is a host-wide `flock`, and a gate is refused if
another configured guest is running. Values are taken from the command line or
a sourced `--config` file, where per-distro keys look like `DOMAIN_fedora44`.
A missing value is a refusal that names the flag. The coordinator does not
create repositories, publish releases, merge, add OpenPGP UIDs or touch Play.
Static check H4 enforces this.

**Summary.** Every invocation ends with `PRE_G8_SUMMARY_BEGIN … PRE_G8_SUMMARY_END`:

* the evidence directory, the commit, the worktree change count and `selftest=`;
* one `PRE_G8_GATE id=… state=… reason="…"` line per gate;
* `PRE_G8_COUNTS pass= fail= pending= blocked= total=`;
* `PRE_G8_RESULT=PASS|FAIL|INCOMPLETE|SELFTEST`. The result is PASS only if
  all 37 gates are PASS.

The same block is written to `EVIDENCE/summary.txt`.

A typical G7-UP pass for one distribution:

```bash
T=packaging/tests/pre-g8-manual-gates.sh; C=--config ~/pre-g8.conf
$T $C --run G7UP-fedora44-INSTALL      # then pair the phone in the guest
$T $C --run G7UP-fedora44-U2
$T $C --run G7UP-fedora44-UPGRADE      # stops on Pliwee
$T $C --run G7UP-fedora44-U6           # copy text on the phone first
$T $C --run G7UP-fedora44-SECLOG
$T $C --run G7UP-fedora44-U10          # refused until U6 verifies
$T $C --run G7UP-fedora44-U8           # the fresh guest; type its name
$T $C --status
```

## 3. Tests run

| Test | Result | File |
| --- | --- | --- |
| `bash -n` on every changed and new script | clean | `bash-n.txt` |
| `packaging/tests/harness-selftests.sh` | **80 passed, 0 failed**. 39 new checks in "U10 before U6": 22 verifier REJECTS (see below), 1 ACCEPTS, 15 stage-order checks and 1 static check. It also runs the coordinator suite as a sub-suite, which must report ≥50 ok | `harness-selftests.txt` |
| `packaging/tests/pre-g8-manual-gates-selftests.sh` | **62 passed, 0 failed** | `pre-g8-selftests.txt` |
| `packaging/tests/packaging-checks.sh` (static) | **136 passed, 0 failed**. The new H4 has 6 checks, and H2 now covers the coordinator | `packaging-checks-static.txt` |
| Mutation proof: 16 mutations, each on a scratch copy | **16 of 16 caught** | `mutations.sh`, `mutations.txt` |
| Assertion preservation vs `HEAD` | **95 of 95** assertion lines from the original `upgrade-gates.sh` are present, word for word | `assertion-preservation.txt` |

The verifier REJECTS cover:

* no U6, an empty result, a bare `verdict=PASS`, and no checkpoint;
* an altered log, an empty log, a peer failure, and a precondition abort;
* a re-pairing, a one-way clipboard, and an empty transfer journal;
* the wrong domain, the wrong distro, a tally for the wrong guest, and a
  distro or domain mismatch in the query;
* an earlier run, another machine, another fingerprint, a start before the
  upgrade, a failed upgrade, and a non-zero exit.

The stage-order checks drive `upgrade-gates.sh` itself with a fake `virsh` that
logs every call. **A refusal counts only if it happens with zero calls to the
guest.** The two acceptance cases must reach the guest.

The five things this task asked the tests to prove:

| Required | Where |
| --- | --- |
| U10 cannot execute before U6 PASS evidence | stage checks "downgrade with no evidence / after the upgrade but before U6" (no virsh call). Coordinator: "U10 on a fresh directory", "after the upgrade but before U6", "…and the downgrade stage was never invoked", and the peer-u6 → downgrade order in the call log |
| Empty or fake U6 evidence is rejected | verifier: empty result, bare `verdict=PASS`, altered log, empty log, missing anchors. Stage: empty and forged. Coordinator: a stub harness that exits 0 and prints `ok U6` over an empty `U6-RESULT` is FAIL in the record and in the status |
| Wrong-domain or wrong-distro U6 evidence is rejected | verifier: 5 cases. Stage: 3 cases. Coordinator: evidence recorded for another domain is FAIL |
| Resume after an interruption | coordinator: a gate killed with `kill -9` mid-run shows **BLOCKED (interrupted)**, not PASS and not PENDING. `--next` resumes that gate before any new one, and it completes. Stage: a second downgrade after `U10-STARTED` is refused |
| No manual gate is silently skipped | coordinator: all 37 gates appear with a state. Gates never run are PENDING or BLOCKED. `--not-executed` needs a reason and stays BLOCKED. A declined or EOF confirmation changes nothing. A real `--status` over self-test records counts 0 PASS. A stubbed run's result is SELFTEST, never PASS |

> **Superseding note — 2026-09-25, hardening repair (§ 9).** "No manual gate"
> above means none of the coordinator's 37 gates. It does not cover pre-W8
> § 8, part of which is outside the coordinator (§ 9.3). "Stays BLOCKED" was
> true of the status, but a not-executed gate could still be run with its
> prerequisites unchecked, and a FAIL could be recorded over as not-executed.
> Both are repaired and self-tested in § 9.

## 4. Documentation

* A dated superseding note, added below §5's table in
  [the Wave 7 report](PLIWEE-WAVE-7-LINUX-INTEGRATION-PACKAGING.md). The G7-UP
  row itself is left as written.
* Two dated superseding notes in
  [the pre-W8 remediation report](PLIWEE-PRE-W8-REMEDIATION.md): one under the
  §5 `upgrade-gates.sh` bullet and one under the §8 table. The original text is
  unchanged.
* `README.md`: `cargo test --workspace # 981 tests` becomes `# the full
  workspace test suite`, in both places. Its Android line still gives an exact
  count (`# 771 tests`). That line was outside this task's brief, so it was
  left for the owner, and it will go stale in the same way.

## 5. Not executed

**Every manual and hardware gate is still NOT EXECUTED**, and none is claimed:

* G7-UP U0–U10 on the four distributions;
* the lifecycle, peer and security-log gates;
* the Wave 2 GNOME and KDE session checks;
* Wave 6 signing provisioning, the component-upgrade test and the instrumented
  suite.

This task was forbidden from starting VMs, using the device, or provisioning
keys. The coordinator and the harnesses were exercised only against stubs and a
fake `virsh`.

Two things are untested outside stubs:

* the `/dev/tty` confirmation path. The self-tests read stdin instead, in a
  mode that can never produce PASS;
* whether AGP 8.10.1 honours `-Pandroid.injected.version.code`. If it does not,
  `W6-COMPONENT-UPGRADE` fails at the aapt2 versionCode check, and `--apk-n` /
  `--apk-n1` is the fallback.

## 6. Limitations

* **The binding is by digests and identities, not by signatures.** Someone who
  hand-writes every file consistently could still forge a U6. The verifier
  defends against accident, stale runs, wrong guests and a lying exit code. It
  does not defend against deliberate forgery by the operator.
* The W2 and U2 gates are operator attestations. They are recorded item by
  item, together with the operator's own words, and nothing in them is
  inferred.

## 7. Evidence files (`pliwee-pre-g8-gate-hardening/`)

`bash-n.txt`, `harness-selftests.txt`, `pre-g8-selftests.txt`,
`packaging-checks-static.txt`, `mutations.sh`, `mutations.txt`,
`assertion-preservation.txt`.

## 8. Files changed

| File | Change |
| --- | --- |
| `packaging/tests/upgrade-gates.sh` | five stages. Stage-order refusals before U0. The checkpoint. `peer-u6`, and `downgrade` (with the U10 block moved verbatim). The install-stage text now asks for the physical phone |
| `packaging/tests/lib/g7up-evidence.sh` | **new**: the checkpoint and U6 records, and `g7up_verify_checkpoint` / `g7up_verify_u6` |
| `packaging/tests/lib/g7up-fixture.sh` | **new, test only**: well-formed records for the self-tests |
| `packaging/tests/pre-g8-manual-gates.sh` | **new**: the coordinator |
| `packaging/tests/pre-g8-manual-gates-selftests.sh` | **new**: 62 checks against stubs |
| `packaging/tests/harness-selftests.sh` | the "U10 before U6" section, plus the coordinator suite as a sub-suite |
| `packaging/tests/packaging-checks.sh` | H2 covers the coordinator. New H4 check |
| `README.md` | the two `981 tests` comments |
| `docs/reports/branding/PLIWEE-WAVE-7-…`, `PLIWEE-PRE-W8-REMEDIATION.md` | dated superseding notes only |

No product code, protocol, state behaviour, Android version, URL or Wave 0
master was touched.

---

## 9. Repair — 2026-09-25 (audit findings A, B, C)

| | |
| --- | --- |
| **What this is** | A repair of this hardening pass after an audit, before anything was committed. It covers the coordinator (`pre-g8-manual-gates.sh`), its self-tests, and the documentation this pass wrote. **This is not a certification. No gate was executed. G8 is not claimed.** |
| **Branch / base** | `feature/pliwee-pre-g8-gate-hardening`, working tree on `e68f332`, not committed |
| **Host** | the same as above. **No VM, emulator, container, Gradle or cargo job was started. Nothing was done on the Android device. No signing media were touched. Nothing was done in Play or with repository migration.** One suite ran at a time |
| **Evidence** | [`pliwee-pre-g8-gate-hardening/repair-2026-09-25/`](pliwee-pre-g8-gate-hardening/repair-2026-09-25/) (§ 9.6). The first pass's evidence files are left as measured |
| **Result** | **HARDENING REPAIR: PASS.** Before any gate runs, its prerequisites are checked again, whatever the gate's own record says, and a not-executed record waives nothing. After U10 has started, SECLOG and U6 cannot run on that chain. `--not-executed` refuses to replace a FAIL, a PASS, or a run that started. A new attempt moves the earlier record to `state/history/` and never overwrites it. The documentation now names only the gates the coordinator drives. Self-tests 95 passed, 0 failed and 80 passed, 0 failed, static checks 136 passed, 0 failed, repair mutations 10 of 10 caught, first-pass mutations 16 of 16 still caught, frozen digests 7 of 7 |

### 9.1 A — `--not-executed` bypassed the prerequisites

**The defect.** `status()` returned `BLOCKED not executed: …` for a
NOT_EXECUTED record before it evaluated any prerequisite. `run_gate()` then
allowed a gate in RUNNING, INCOMPLETE or NOT_EXECUTED state to execute. So:

* `--not-executed G7UP-<d>-U10` followed by `--run G7UP-<d>-U10` ran the
  downgrade while SECLOG was undecided. The only check still in the way was
  `gate_g7up`'s `g7up_verify_u6`, and that check does not look at SECLOG;
* SECLOG recorded not-executed before U10, followed by `--run` after U10, ran
  `security-log-evidence.sh` against a guest the downgrade had already put
  back on OmniBridge 1.0.0. The result would be a FAIL measured against a
  precondition the coordinator itself had destroyed;
* `--rerun` did not check prerequisites either, because `status()` returned
  PASS or FAIL before reaching them.

**The repair.**

* `prereq GATE` holds the prerequisites, separately from the gate's own record.
  `status()` still reports PASS and FAIL as measured. For every other state
  (no record, RUNNING, INCOMPLETE, NOT_EXECUTED) it evaluates the
  prerequisites first. The reason shown is the unmet prerequisite, with the
  gate's own record in brackets.
* **Every execution re-checks them.** `run_gate` calls `prereq_ok` first,
  whatever the record says, and that includes `--rerun` of a PASS or a FAIL.
  `run_logged` calls it again immediately before the owning script starts.
* `u10_started D` is true if `upgrade-gates.sh`'s own `U10-STARTED` marker is
  in the chain, so a downgrade started outside the coordinator counts. It is
  also true if any U10 record, current or archived, is in a state other than
  NOT_EXECUTED. When it is true:
  * SECLOG is BLOCKED ("U10 has run");
  * U6 is BLOCKED (its upgraded guest is gone);
  * U10 is BLOCKED (a second downgrade would measure a guest already on 1.0.0).

  `--reset-distro` is the only way forward.
* **U10 stays fail-closed.** It needs a U6 PASS. It needs SECLOG
  PASS/FAIL/NOT_EXECUTED, recorded by the same kind of run. It needs U10 not
  already started. `gate_g7up` also keeps its own `g7up_verify_u6` refusal,
  unchanged.
* `--next` resumes an interrupted gate only while its prerequisites still
  hold. Otherwise it says so and moves on to the first runnable gate.

A U10 recorded as not-executed does **not** block SECLOG. No downgrade
happened, so the upgraded guest is still there. The self-tests prove this in
both directions.

### 9.2 B — a measured FAIL could be overwritten

**The defect.** `--not-executed` refused only a PASS. A FAIL, an interrupted
RUNNING record or an INCOMPLETE one could be replaced by "not executed". Every
`--rerun` also overwrote the previous record in place.

**The repair.**

* `--not-executed` is accepted only when the gate has no record or already has
  a NOT_EXECUTED one. It refuses a PASS. It refuses a FAIL ("a FAIL is
  evidence"), and names `--rerun` as the way to try again. It refuses
  RUNNING/INCOMPLETE ("it was executed at least in part").
* Every execution, and every not-executed record, is an **attempt** with its
  own `attempt=` id. Before `state_write` writes a gate's record, it moves any
  record left by another attempt, byte for byte, to
  `state/history/GATE.<utc>.<random>`. This happens only when there is a new
  record to write, so a declined or refused run still changes nothing.
  Nothing is overwritten.
* A retry is still the explicit `--rerun`. The summary line now carries
  `history=N history_fail=M`, so a PASS that came after a FAIL says so.
  `--reset-distro` moves a chain's history into `superseded/` along with its
  state.
* In a stubbed run the overall result is SELFTEST by construction. So the
  "overall remains FAIL" requirement is proved twice:
  * in self-test mode, the FAIL is still counted in `PRE_G8_COUNTS fail=` (and
    `n_fail > 0` is what sets a real result to FAIL);
  * in a **real-mode** run over a hand-written real FAIL record,
    `--not-executed` exits 2, and `--status` then reports
    `PRE_G8_RESULT=FAIL`.

### 9.3 C — what the coordinator drives, and what it does not

This pass's superseding note under pre-W8 remediation § 8 said:

> The gates in this table, except the network matrix, the container builds and
> the release pipeline, are now driven by one resumable operator coordinator

That was an overclaim. The note was this branch's own uncommitted text, so it
was **rewritten in place** to name only what the coordinator drives. The § 8
table was not touched. The overclaiming passages in this report (the header,
§ 2 and § 3) are left as written, with dated superseding notes beside them.
The Wave 7 note only says that the operator drives the G7-UP stages through the
coordinator. That is accurate, so it is unchanged.

| Driven by `pre-g8-manual-gates.sh` (37 gates) | Owning script |
| --- | --- |
| G7-UP U0–U10 on the four distributions, and U8 on a fresh guest | `upgrade-gates.sh`, five stages |
| `lifecycle-peer-gates.sh` **only as U6**, against the upgraded guest | `upgrade-gates.sh --stage peer-u6` |
| the security-log gate, once per distribution, on the upgraded guest before U10 | `security-log-evidence.sh` |
| the lifecycle gates on a fresh guest | `lifecycle-gates.sh` |
| from the GNOME/KDE real-session row, **only** the Wave 2 Devices-page keyboard and screen-reader procedure | operator record (`W2-GNOME`, `W2-KDE`) |
| Wave 6 signing-key provisioning | `provision-signing-keys.sh` |
| Wave 6 component upgrade (N → N+1) | adb + aapt2 |
| the Android instrumented suite. `HostDrivenCertificationHarness` runs only in its no-argument mode here, because Gradle uninstalls the app at the end | `:app:connectedDebugAndroidTest` |

| **Not** driven by it; each keeps its own procedure | Owner |
| --- | --- |
| Security Certification v1 (SEC gates) | its procedure |
| clipboard.v1, files.v1 and notifications.v1 (N6) hardware certifications | their procedures |
| `systemd-unit-gates.sh` | its own run |
| signed-bundle verification | W6 § 7 procedure |
| QR centre mark and scan (D8), tray, D-Bus activation, and the reset of favourites and notification settings in real sessions | operator at a GNOME host and `anyflow-f44-kde` |
| a full `lifecycle-peer-gates.sh` run outside U6, and the host-driven `HostDrivenCertificationHarness` runs (`am instrument` with `pliwee.*` arguments) | their procedures |
| § 4 network matrix N1–N5, X1–X5 | operator + tablet |
| container builds, `install-smoke.sh`, `packaging-checks --rpm/--deb`, validators on built packages | the corrected candidate |
| `release-artifacts.yml` dry run | the orchestrator |
| Play and repository migration | W9/W10 |

### 9.4 Minor — the `one_vm` comment

The comment said "the target must be running". The code does not check that:
it refuses only when *another* configured guest is running. The comment now
says what the code does, and adds that the owning harness contacts the target
first (`upgrade-gates.sh` U0 pings its guest agent). The code is unchanged.

### 9.5 Tests run

Only the targeted shell and static suites were run, one at a time, on the final
tree.

| Test | Result | File |
| --- | --- | --- |
| `bash -n` on every changed shell file and both mutation scripts | clean (10 of 10) | `bash-n.txt` |
| `pre-g8-manual-gates-selftests.sh` | **95 passed, 0 failed** (was 62/0). 33 new checks, listed below | `pre-g8-selftests.txt` |
| `packaging/tests/harness-selftests.sh` | **80 passed, 0 failed**. Its coordinator sub-suite reports 95 `ok` lines (it needs ≥50) | `harness-selftests.txt` |
| `packaging-checks.sh` (static) | **136 passed, 0 failed**. H4 still finds the bare signing invocation and no repository, release, merge, UID or Play action | `packaging-checks-static.txt` |
| repair mutations: 10, each on a scratch copy | **10 of 10 caught** | `mutations-repair.sh`, `mutations-repair.txt` |
| the first pass's 16 mutations, re-run on the repaired tree | **16 of 16 caught**. Every anchor still applies | `mutations-original-rerun.txt` |
| frozen Wave 0 masters and D10 vectors (`pliwee-pre-w8-remediation/frozen_digests.sh`) | **7 of 7**, byte-identical | `frozen-digests.txt` |
| `git diff --check`, plus a trailing-whitespace grep over the untracked files | clean | `diff-check.txt` |

> **Superseding note — 2026-09-25, final hardening repair (§ 10).** The
> "clean" in the last row was not true. At the time, 12 lines in four evidence
> files ended in spaces. `git diff --check` does not look at untracked files.
> Those lines have been stripped, so the transcripts in this directory and the
> first pass's are **normalized for trailing horizontal whitespace**. They are
> not byte-for-byte what the commands printed (§ 10.2). The "left as measured"
> in § 9's table means the same content, in the same order, with that
> normalization.

What the new coordinator self-tests prove:

* **The old bypass, reproduced and rejected.**
  * U10 recorded not-executed while SECLOG is undecided: `--run` is refused,
    naming SECLOG, and the downgrade is never invoked. The status gives the
    prerequisite as the reason. SECLOG stays PENDING.
  * After U10, a not-executed SECLOG is refused through `--run`, through
    `--rerun --run`, and as an interrupted record through `--next`, which moves
    on to W2-GNOME. `security-log-evidence.sh` is never invoked, by any route.
* **The harness's own marker.** With `U10-STARTED` present in the chain,
  SECLOG is refused.
* **Retries after U10.** A U6 retry after U10 is refused (peer-u6 invocations
  stay at exactly 3). A second U10 is refused (downgrade invocations stay at
  exactly 1).
* **FAIL cannot become not-executed.**
  * The FAIL record is byte-identical afterwards, the gate is still FAIL, and
    the summary still counts it.
  * Running it again needs `--rerun`. The retry is a new attempt, and the
    original FAIL record is kept byte-identical in `state/history/`, with its
    answers file still matching its digest. The summary shows
    `history=1 history_fail=1`.
  * The instrumented-suite FAIL is kept the same way.
  * In real mode, `--not-executed` over a FAIL exits 2, and the result stays
    `PRE_G8_RESULT=FAIL`.
* **An interrupted run cannot become not-executed.** When it is resumed, the
  interrupted attempt's record is kept. When U10 runs, its earlier
  not-executed record is kept too.

Each repair mutation re-opens one hole, and the named checks catch it:

* M1 is the audited defect itself: no prerequisite check before execution.
* M2: `status()` reports a gate's own record before its prerequisites.
* M3: SECLOG ignores that U10 started.
* M4: the `U10-STARTED` marker is ignored.
* M5: U6 can be retried after U10.
* M6: U10 can run twice.
* M7: `--not-executed` replaces a FAIL.
* M8: `--not-executed` replaces a started run.
* M9: a new attempt overwrites the previous record.
* M10: `--next` resumes an interruption whose prerequisites fail.

The two checks are layered. M1 removes **both** the `run_gate` check and the
`run_logged` check. Removing only one of them leaves the other one refusing,
which is intended.

### 9.6 Not executed, limitations, files

**Not executed:** everything § 5 lists, and everything in § 9.3's second
table. Nothing here is a gate result.

**Limitations.** The history is a set of files moved unchanged, with no
signatures. As § 6 says, it defends against accident, stale runs and a lying
exit code, not against an operator who deletes or edits the evidence
directory. `u10_started` reads the chain directory, and `--reset-distro` moves
that directory aside on purpose: it is the documented way to start a chain
again from a restored snapshot.

**Evidence** (`pliwee-pre-g8-gate-hardening/repair-2026-09-25/`):
`bash-n.txt`, `pre-g8-selftests.txt`, `harness-selftests.txt`,
`packaging-checks-static.txt`, `mutations-repair.sh`, `mutations-repair.txt`,
`mutations-original-rerun.txt`, `frozen-digests.txt`, `diff-check.txt`,
`run-rcs.txt`.

**Files changed by the repair:**

| File | Change |
| --- | --- |
| `packaging/tests/pre-g8-manual-gates.sh` | `prereq`/`prereq_ok`, re-checked in `run_gate` and `run_logged`. `u10_started`. Attempts, and `state/history/`. `--not-executed` refusals. `--next` skips blocked resumes. `history=`/`history_fail=` in the summary. `--reset-distro` moves history. The header and the `one_vm` comment |
| `packaging/tests/pre-g8-manual-gates-selftests.sh` | 33 new checks (§ 9.5) |
| `docs/reports/branding/PLIWEE-PRE-W8-REMEDIATION.md` | this branch's own § 8 superseding note, rewritten (§ 9.3). The table is untouched |
| `docs/reports/branding/PLIWEE-PRE-G8-GATE-HARDENING.md` | three dated superseding notes, and this section |

`upgrade-gates.sh`, `lib/g7up-evidence.sh`, `harness-selftests.sh`,
`packaging-checks.sh`, the Wave 7 report, `README.md`, product code, and the
Wave 0 masters were not changed by the repair.

---

## 10. Final repair — 2026-09-25 (two audit findings)

| | |
| --- | --- |
| **What this is** | The last repair of this hardening pass, before anything was committed. It fixes the two findings an audit of § 9 left open. A/B/C stay closed and are not reopened. **This is not a certification. No gate was executed. G8 is not claimed.** |
| **Branch / base** | `feature/pliwee-pre-g8-gate-hardening`, working tree on `e68f332`, not committed |
| **Host** | the same as above. **No VM, emulator, container, Gradle or cargo job was started. Nothing was done on the Android device. No signing media were touched. Nothing was done in Play or with repository migration.** One suite ran at a time |
| **Evidence** | [`pliwee-pre-g8-gate-hardening/final-repair-2026-09-25/`](pliwee-pre-g8-gate-hardening/final-repair-2026-09-25/) (§ 10.4) |
| **Result** | **FINAL HARDENING REPAIR: PASS.** A declined or unanswerable first confirmation now leaves every gate's current record, its history and the overall result as they were. That includes a FAIL being retried. A new attempt exists only once the first action is accepted. The evidence text has no trailing horizontal whitespace, and a guard now fails if any does. Coordinator self-tests 134 passed, 0 failed (was 95). Harness self-tests 80 passed, 0 failed. New mutations 4 of 4 caught. The § 9 repair mutations are still caught, 10 of 10. Guard self-test 8 passed, 0 failed. The guard over the evidence passes. `git diff --check` is clean |

### 10.1 A declined W6-COMPONENT-UPGRADE confirmation changed the state

**The defect.** `gate_component` wrote `state=RUNNING` right after it made its
evidence directory. That was before it copied or built the APKs, and before
its first `confirm_action`. `state_write` archives any record left by another
attempt. So with `--rerun` over a FAIL:

1. the FAIL went into `state/history/`, and RUNNING became current;
2. the operator answered "no", and `confirm_action` exited 5;
3. nothing had been measured. But the current FAIL was gone, the gate read
   BLOCKED (interrupted), and a real run's overall result went from **FAIL to
   INCOMPLETE**.

With no record, a "no" left an interrupted RUNNING record where PENDING should
have been. A real run with no terminal did the same: the refusal came after the
write. The APK copy, the builds and the package and versionCode checks all ran
before the confirmation, and they could also record a FAIL, so that archived
the previous record in the same way.

**The repair** (`pre-g8-manual-gates.sh`).

* Before the first confirmation, `gate_component` only prepares. It copies or
  builds the APKs (the build log goes to `run.log` in the gate's evidence
  directory), checks them with aapt2, and reads the installed versionCode.
  **It writes no state record.** A problem here is now a refusal (exit 2,
  "nothing was recorded"), not a FAIL. A wrong package, an N+1 whose versionCode
  is not higher (an ignored `-Pandroid.injected.version.code`), and a failed
  build are still loud. But they no longer turn into a gate result, and they
  cannot displace one. § 2 says an ignored override "fails". It now **refuses**.
* `state_write … state=RUNNING` is the first statement after the first
  `confirm_action` returns. From there on it is an attempt, as before. The
  install, the observations, the second confirmation and every FAIL/PASS are
  unchanged.
* `confirm_action` tells the truth about a later decline. When the attempt
  already has a record (W6-COMPONENT-UPGRADE's second confirmation, before
  N+1), the message says the action was not done and that the gate "stays
  recorded as RUNNING for this attempt", and says how to resume it. It no
  longer says "the gate keeps its previous state".

**The audit of the other gates.** Every gate that asks for confirmation was
read for a record written, archived or replaced before its first confirmation:

| Gate | First record | Before the first confirmation |
| --- | --- | --- |
| `W6-COMPONENT-UPGRADE` | was before it; **now after** | preparation only (repaired above) |
| `W6-SIGNING` | RUNNING after `confirm_action` | `--status` to a status file. When that already shows restore-verified backups, it records PASS without asking. That is a measurement with no action, so it is correct |
| `W6-INSTRUMENTED` | `run_logged`, after `confirm_action` | an evidence directory and a timestamp mark only |
| `G7UP-<d>-INSTALL` | `run_logged`, after `confirm_action` | refusals only. The `BINDING` file is written after the confirmation |
| `G7UP-<d>-UPGRADE`, `-U6`, `-SECLOG`, `-U10`, `-U8`, `LIFECYCLE-<d>` | `run_logged`, after `confirm_action` | refusals and `one_vm` only |
| `W2-*`, `G7UP-<d>-U2`, `--not-executed` | ask no confirmation. Their record is the operator's measurement or reason. An EOF at any prompt exits 5 before a record is written | — |

`W6-COMPONENT-UPGRADE` was the only case. The § 9 layering is unchanged:
`prereq_ok` still runs in `run_gate` and again in `run_logged`, before any
record.

**Seen, not changed (outside this brief).** `G7UP-<d>-U2` writes its answers
to one fixed path, `U2-operator.txt`. A `--rerun` of a U2 FAIL therefore
replaces the answers that the archived FAIL record points to. The archived
record itself is kept byte-identical, but its answers file is not. W2 does
not have this problem, because it uses a timestamped file with a digest. Left
for the owner.

### 10.2 The evidence whitespace claim was false

**The defect.** § 9.5 and `repair-2026-09-25/diff-check.txt` said a
trailing-whitespace grep over the untracked files found nothing. In fact 12
lines ended in spaces: `harness-selftests.txt` (2), `mutations.txt` (4),
`repair-2026-09-25/harness-selftests.txt` (2), and
`repair-2026-09-25/mutations-original-rerun.txt` (4). They came from
generated output: `cut -c1-130` stopping on a space, and harness messages
that end in "; ". `git diff --check` does not look at untracked files, so it
could not have seen them.

**The repair.**

* Only trailing spaces and tabs were stripped from those four files
  (`sed -i 's/[ \t]*$//'`). Nothing else changed: the same lines in the same
  order. For each file, `whitespace-normalization.txt` records the lines
  stripped, the digest before and after, and a check that the file equals its
  original once trailing whitespace is ignored (4 of 4 "yes").
* **Evidence text in `pliwee-pre-g8-gate-hardening/` is normalized for
  trailing horizontal whitespace before it is tracked.** The transcripts are
  the commands' output with that normalization, not byte-for-byte what was
  printed. The new transcripts in `final-repair-2026-09-25/` were normalized
  the same way when they were written. `mutations-final.sh` strips at the
  source.
* `repair-2026-09-25/diff-check.txt` keeps its original lines, with a dated
  superseding note under them. The truthful record is
  `final-repair-2026-09-25/diff-check.txt`.
* **A guard**, `packaging/tests/evidence-whitespace-check.sh`, reads the files
  themselves, tracked or not. By default it covers this report and its whole
  evidence directory. It fails on any line that ends in a space or a tab. It
  also fails when it scanned nothing: a missing path, or no text file. It
  counts and skips binary files. `--selftest` proves each rejection (8 checks).

### 10.3 Tests run

Only the targeted shell and static suites were run, one at a time, on the final
tree. The static `packaging-checks.sh` was not re-run. This repair adds nothing
that H2 or H4 look for: no guest harness, and no repository, release, merge,
UID or Play action. Its § 9.5 result stands, recorded n/a here.

| Test | Result | File |
| --- | --- | --- |
| `bash -n`: every changed shell file and all three mutation scripts | clean (12 of 12) | `bash-n.txt` |
| `pre-g8-manual-gates-selftests.sh` | **134 passed, 0 failed** (was 95). 39 new checks, below | `pre-g8-selftests.txt` |
| `harness-selftests.sh` (it runs the coordinator suite as a sub-suite) | **80 passed, 0 failed**. The sub-suite reports 134 | `harness-selftests.txt` |
| final-repair mutations: 4, each on a scratch copy | **4 of 4 caught** | `mutations-final.sh`, `mutations-final.txt` |
| § 9's repair mutations, re-run on this tree | **10 of 10 caught**. Every anchor still applies | `mutations-repair-rerun.txt` |
| `evidence-whitespace-check.sh --selftest` | **8 passed, 0 failed** | `whitespace-guard-selftest.txt` |
| `evidence-whitespace-check.sh` over the evidence, the new untracked files, and `git diff --check` | see the file | `diff-check.txt` |

What the new coordinator self-tests prove:

* **(a) FAIL → `--rerun` → "no".** A W6-COMPONENT-UPGRADE FAIL, measured
  through the gate itself. `--rerun --run` answered "no" exits 5. Afterwards:
  * the state directory, including every current and archived record, is
    byte-identical;
  * the FAIL is current and not archived, and the summary shows
    `state=FAIL history=0 history_fail=0`;
  * the FAIL count is unchanged, and no device action was taken.

  The same case in a **real** run with no terminal (`setsid`) is refused at
  the confirmation, after the preparation. The real FAIL record is
  byte-identical, there is no history, and the result is still
  `PRE_G8_RESULT=FAIL`, not INCOMPLETE.
* **(b) no record → "no".** No record is written. The gate stays PENDING
  with `history=0`. The same holds for an EOF. An N+1 whose versionCode is not
  higher is refused before the confirmation and records nothing.
* **(c) "yes".** `--rerun` answered `yes`, `PINNED`, `yes`, `y` runs N and
  then N+1, and ends PASS. The FAIL it replaced is in `state/history/`,
  byte-identical, and the summary shows `history=1 history_fail=1`. A
  second-confirmation "no" leaves that attempt RUNNING, and says so. The PASS
  it replaced is archived.
* **The audit, as tests.** A declined confirmation moves nothing, byte for
  byte across the state directory, and invokes nothing on:
  * U6 with no record and U6 over its FAIL (`--rerun`);
  * SECLOG with no record, and U10 over its not-executed record;
  * `--rerun` of W6-INSTRUMENTED, UPGRADE, U8 (with `yes` typed instead of
    the guest's name) and LIFECYCLE;
  * W6-SIGNING when not provisioned;
  * INSTALL with no record on a second distribution.

The mutations:

* FM1 is the audited defect restored: RUNNING written before the preparation.
  15 checks fail.
* FM2: a preparation problem records a FAIL again. 6 checks fail.
* FM3: a later decline claims the gate kept its previous state. 1 check fails.
* FM4: any gate opens its record in `run_gate`, before its gate function asks.
  47 checks fail.

### 10.4 Not executed, kept intact, files

**Not executed:** everything § 5 and § 9.3's second table list. Nothing here is
a gate result.

**Kept intact:**

* the A/B/C repairs;
* U6 before U10;
* SECLOG/U10 fail-closed ordering and `u10_started`;
* a FAIL cannot become not-executed, and every retry is archived;
* W9/W10 are outside the coordinator.

`upgrade-gates.sh`, `lib/g7up-evidence.sh`, `harness-selftests.sh`,
`packaging-checks.sh` and the Wave 0 masters were not changed by this repair.
The frozen digests were not re-run, because nothing that could change them was
touched.

**Evidence** (`pliwee-pre-g8-gate-hardening/final-repair-2026-09-25/`):
`bash-n.txt`, `pre-g8-selftests.txt`, `harness-selftests.txt`,
`mutations-final.sh`, `mutations-final.txt`, `mutations-repair-rerun.txt`,
`whitespace-guard-selftest.txt`, `whitespace-normalization.txt`,
`diff-check.txt`, `run-rcs.txt`.

**Files changed by the final repair:**

| File | Change |
| --- | --- |
| `packaging/tests/pre-g8-manual-gates.sh` | `gate_component`: no record before the first confirmation, and preparation problems are refusals. `confirm_action`: a truthful message when a later confirmation is declined (`GATE_RUN`) |
| `packaging/tests/pre-g8-manual-gates-selftests.sh` | adb and aapt2 stubs, `snap`/`declined`/`acts`, and 39 new checks (§ 10.3). One existing check's example of a never-run gate moved from W6-COMPONENT-UPGRADE, which now runs, to G7UP-ubuntu2404-INSTALL |
| `packaging/tests/evidence-whitespace-check.sh` | **new**: the guard and its self-test |
| `pliwee-pre-g8-gate-hardening/{harness-selftests,mutations}.txt`, `repair-2026-09-25/{harness-selftests,mutations-original-rerun}.txt` | trailing horizontal whitespace stripped (§ 10.2) |
| `repair-2026-09-25/diff-check.txt` | a dated superseding note appended; its original lines are kept |
| this report | a superseding note under § 9.5, and this section |
