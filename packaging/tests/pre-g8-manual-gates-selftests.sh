#!/usr/bin/env bash
# pre-g8-manual-gates-selftests.sh — does the pre-G8 coordinator refuse what
# it must, and resume where it should?
#
# The coordinator is pointed (PRE_G8_GATES_DIR) at stub gate scripts that
# record every call and print what the real ones print. A fake `virsh` and a
# stub Gradle and signing procedure stand in for the guest, the build and the
# media. In this mode nothing it records can be a PASS for a real run, and the
# overall result is SELFTEST — both are asserted below too.
#
# What is proved, each against the failure it exists for:
#   * U10 cannot run before a U6 PASS, and a harness that exits 0 and prints
#     "ok U6" over empty or wrong-domain evidence is still a FAIL;
#   * U10 waits for the security-log gate to be run or recorded not-executed;
#   * a missing domain / package directory / serial is refused, not guessed;
#   * a declined confirmation changes nothing; a fresh-guest gate needs the
#     guest's name typed back, and cannot be the upgrade guest;
#   * one VM at a time: another configured guest running is a refusal;
#   * an interrupted gate shows BLOCKED, never PASS, and --next resumes it;
#   * evidence altered after a PASS turns it into FAIL;
#   * no gate is silently skipped: every gate is in the summary with a state,
#     not-executed needs a reason and stays BLOCKED, and self-test records do
#     not count in a real run;
#   * the signing procedure's passwords reach the terminal and nothing else;
#   * prerequisites are checked again before EVERY execution: a gate's own
#     not-executed, interrupted or retried record never waives them (the
#     --not-executed bypass, reproduced here against the old behaviour), and
#     once U10 has started, U6 and the security-log gate cannot run again;
#   * a measured FAIL, or a run that started, cannot be recorded not-executed,
#     and a retry is a new attempt that keeps the original record;
#   * no attempt exists before its first confirmation is accepted: declining
#     it (or having no terminal to answer at) leaves the current record, the
#     history and the overall result exactly as they were — on every gate that
#     asks, W6-COMPONENT-UPGRADE included (the final-repair finding).

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
COORD="$HERE/pre-g8-manual-gates.sh"

PASS=0; FAIL=0
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); printf 'not ok  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
check()   { local d="$1"; shift; if "$@"; then ok "$d"; else notok "$d"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pliwee-pre-g8-selftest.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub"; EV="$WORK/evidence"; OLD="$WORK/old"; NEW="$WORK/new"
mkdir -p "$STUB/android/signing" "$WORK/bin" "$OLD" "$NEW"
echo "old-set" > "$OLD/SHA256SUMS"; echo "new-set" > "$NEW/SHA256SUMS"
CALLS="$STUB/calls"; : > "$CALLS"

# ---------------------------------------------------------------- the stubs --
cat > "$STUB/upgrade-gates.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(cd "$(dirname "$0")" && pwd)"
. "$STUB/lib-fixture.sh"
echo "upgrade-gates $*" >> "$STUB/calls"
while [ $# -gt 0 ]; do case "$1" in
  --stage) S="$2"; shift 2 ;; --evidence) E="$2"; shift 2 ;; --distro) D="$2"; shift 2 ;;
  --domain) M="$2"; shift 2 ;; --old-pkgdir) O="$2"; shift 2 ;; *) shift ;; esac; done
case "$S" in
  install) echo "ok    U1: omnibridge and omnibridge-gui are exactly 1.0.0-1"; echo "ok    U2: omnibridged.service is enabled" ;;
  upgrade) g7up_fixture "$E" "$D" "$M" "$O/SHA256SUMS"; rm -rf "$E/U6" "$E/U6-RESULT"
           echo "ok    O2: identity equals O1"; echo "ok    Checkpoint: UPGRADE-CHECKPOINT written for run r1" ;;
  peer-u6)
    T="$(mktemp -d)"; g7up_fixture "$T" "$D" "$M"; rm -rf "$E/U6"; cp -a "$T/U6" "$T/U6-RESULT" "$E/"; rm -rf "$T"
    case "$(cat "$STUB/u6mode")" in
      empty) : > "$E/U6-RESULT" ;;
      wrongdomain) sed -i "s/^domain=.*/domain=somewhere-else/" "$E/U6-RESULT" ;;
    esac
    # A harness that claims success whatever it wrote: the coordinator must not believe it.
    echo "ok    U6: lifecycle-peer-gates.sh passed against the upgraded guest, with every U6 observation in its log; U10 may now run" ;;
  downgrade) echo "ok    U10: OmniBridge 1.0.0 starts on its pre-migration identity" ;;
  negative-unreadable) echo "ok    U8: the daemon refused and named /home/a/.local/share/omnibridge"; echo "ok    U8: no /home/a/.local/share/pliwee/identity.key was created" ;;
esac
exit 0
EOF
cp "$HERE/lib/g7up-fixture.sh" "$STUB/lib-fixture.sh"
cat > "$STUB/security-log-evidence.sh" <<'EOF'
#!/usr/bin/env bash
echo "security-log $*" >> "$(dirname "$0")/calls"; echo "ok    SEC-LOG-03: content absent"; exit 0
EOF
cat > "$STUB/lifecycle-gates.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(dirname "$0")"; echo "lifecycle $*" >> "$STUB/calls"
[ -e "$STUB/lc-sleep" ] && sleep 60
echo "ok    L1: clean install"; exit 0
EOF
cat > "$STUB/android/signing/provision-signing-keys.sh" <<'EOF'
#!/usr/bin/env bash
R="$(dirname "$0")/record"
if [ "${1:-}" = --status ]; then
    if [ -f "$R" ]; then cat "$R"; else echo "NOT PROVISIONED"; fi; exit 0
fi
echo "PASSWORD (upload keystore): S3CR3T-SENTINEL-4242"
printf 'upload  SHA-256 AA:BB\n\nbackups restore-verified:        2026-09-25T00:00:00Z\n' > "$R"
EOF
cat > "$STUB/android/gradlew" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")/app/build/outputs/androidTest-results/connected"; mkdir -p "$D"
n=5; [ -e "$(dirname "$0")/zero-tests" ] && n=0
printf '<?xml version="1.0"?>\n<testsuite name="x" tests="%s" failures="0" errors="0" skipped="0">\n</testsuite>\n' "$n" > "$D/TEST-device.xml"
echo "BUILD SUCCESSFUL"
EOF
chmod +x "$STUB"/*.sh "$STUB/android/gradlew" "$STUB/android/signing/provision-signing-keys.sh"
printf '#!/bin/sh\ncat "%s/running" 2>/dev/null; exit 0\n' "$STUB" > "$WORK/bin/virsh"; chmod +x "$WORK/bin/virsh"
# The designated device (adb) and aapt2 for W6-COMPONENT-UPGRADE. A stub "APK"
# is a text file holding its versionCode; the device remembers what it installed.
cat > "$WORK/bin/adb" <<EOF
#!/usr/bin/env bash
S="$STUB"
EOF
cat >> "$WORK/bin/adb" <<'EOF'
echo "adb $*" >> "$S/calls"
[ "$1" = devices ] && { printf 'List of devices attached\nSERIAL01\tdevice\n'; exit 0; }
[ "$1" = -s ] && shift 2
P=io.github.yurisismotto.pliwee
case "$*" in
  "install -r "*) sed -n 's/^versionCode=//p' "$3" > "$S/adb-installed"; echo Success ;;
  "shell dumpsys package $P") [ -s "$S/adb-installed" ] && echo "    versionCode=$(cat "$S/adb-installed") minSdk=26 targetSdk=35" ;;
  "shell settings get secure enabled_notification_listeners") echo "$P/$P.notifications.PliweeNotificationListener" ;;
  "shell dumpsys notification") echo "  ComponentInfo{$P/$P.notifications.PliweeNotificationListener}" ;;
  "shell settings get secure sysui_qs_tiles") echo "wifi,custom($P/.ui.ClipboardTileService)" ;;
  "exec-out screencap -p") printf 'PNG' ;;
esac
exit 0
EOF
cat > "$WORK/bin/aapt2" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "dump badging" ] || exit 1
printf "package: name='io.github.yurisismotto.pliwee' versionCode='%s' versionName='1.0'\n" "$(sed -n 's/^versionCode=//p' "$3")"
EOF
chmod +x "$WORK/bin/adb" "$WORK/bin/aapt2"
printf 'versionCode=7\n' > "$WORK/apk-n.apk"; printf 'versionCode=8\n' > "$WORK/apk-n1.apk"
printf 'versionCode=7\n' > "$WORK/apk-same.apk"
: > "$STUB/running"

cat > "$WORK/config" <<EOF
DOMAIN_fedora44=g7-f44
U8_DOMAIN_fedora44=g7-f44-fresh
LIFECYCLE_DOMAIN_fedora44=g7-f44-lc
DOMAIN_debian13=g7-d13
OLD_PKGDIR_fedora44=$OLD
NEW_PKGDIR_fedora44=$NEW
KEYRING=$WORK/keyring.gpg
FINGERPRINT=0123456789ABCDEF0123456789ABCDEF01234567
PHONE_IP=192.0.2.20
ADB_SERIAL=SERIAL01
EOF

# co [ARGS...] — run the coordinator on the stubs; stdin is the operator.
OUT=""; RC=0
co() { OUT="$(PATH="$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" PRE_G8_GATES_DIR="$STUB" \
             bash "$COORD" --evidence "$EV" "$@" 2>&1)"; RC=$?; }
gstate() { # GATE — its state in the last summary printed
    sed -n "s/^PRE_G8_GATE id=$1 state=\([A-Z]*\) .*/\1/p" <<<"$OUT"
}
calls() { cat "$CALLS"; }
ncalls() { grep -c -e "$1" "$CALLS" || true; }
# hist_with GATE STATE — the first archived record of GATE in STATE, or nothing.
hist_with() {
    local f
    for f in "$EV/state/history/$1".*; do
        [ -f "$f" ] && grep -qx "state=$2" "$f" && { printf '%s' "$f"; return 0; }
    done
    return 1
}
has_hist() { hist_with "$@" >/dev/null; }   # the same, silently, for check
# snap — every state record and every archived one, with its digest: what a
# declined confirmation must leave exactly as it found.
snap() { ( cd "$EV/state" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum ); }
# declined GATE ANSWER [ARGS...] — run GATE, answer ANSWER at its first
# confirmation, and prove nothing moved: exit 5, the state directory (current
# records and history) byte-identical, and no owning script invoked.
declined() {
    local g="$1" ans="$2" before acts0; shift 2
    before="$(snap)"; acts0="$(acts)"
    co --config "$WORK/config" "$@" --run "$g" <<<"$ans"
    [ "$RC" -eq 5 ] || { echo "exit $RC, not 5" >&2; return 1; }
    [ "$(snap)" = "$before" ] || { echo "the state directory changed" >&2; return 1; }
    [ "$(acts)" = "$acts0" ] || { echo "something was invoked: $(tail -3 "$CALLS")" >&2; return 1; }
}
# acts — calls that act: every stub call except adb's read-only queries (the
# device is looked at before the confirmation; nothing is done to it).
acts() { grep -cvE '^adb (devices|-s [^ ]+ shell (dumpsys|settings get) )' "$CALLS" || true; }
# refused FRAGMENT — the last run was a refusal (exit 2, "REFUSED:") naming
# FRAGMENT. Not merely text that a confirmation prompt might also print.
refused() { [ "$RC" -eq 2 ] && contains "$OUT" "REFUSED:" && contains "$(grep -F 'REFUSED:' <<<"$OUT")" "$1"; }

# ---------------------------------------------------------------------------
section "A fresh evidence directory: nothing is PASS"
# ---------------------------------------------------------------------------
co --status </dev/null
n_gates="$(grep -c '^PRE_G8_GATE ' <<<"$OUT")"
check "every gate is listed in the summary (37: 5 Wave 2/6 + 4 distros x 8)" need_exact_count "summary gates" "$n_gates" 37
check "no gate is PASS on an empty evidence directory" contains "$OUT" "PRE_G8_COUNTS pass=0 "
check "a stubbed run reports SELFTEST, never PASS" contains "$OUT" "PRE_G8_RESULT=SELFTEST"
real="$(XDG_RUNTIME_DIR="$WORK" bash "$COORD" --evidence "$WORK/real-ev" --status 2>&1 </dev/null)"
check "a real --status on an empty directory reports INCOMPLETE" contains "$real" "PRE_G8_RESULT=INCOMPLETE"
check "the summary is also written to the evidence directory" test -s "$EV/summary.txt"
check "an evidence directory inside the source tree is refused" \
    bash -c '! bash "$1" --evidence "$2/packaging/tests/.ev" --status >/dev/null 2>&1' _ "$COORD" "$(cd "$HERE/../.." && pwd)"

# ---------------------------------------------------------------------------
section "Missing values are refused, not guessed"
# ---------------------------------------------------------------------------
co --run G7UP-fedora44-INSTALL <<<"yes"
check "INSTALL without a configured domain is refused" refused "is not configured"
check "…and nothing was run" test ! -s "$CALLS"
co --config "$WORK/config" --run G7UP-ubuntu2404-INSTALL <<<"yes"
check "INSTALL on a distro with no configuration is refused" refused "DOMAIN_ubuntu2404"
co --config "$WORK/config" --run G7UP-debian13-INSTALL <<<"yes"
check "a domain with no package directory is refused" refused "OLD_PKGDIR_debian13"
check "…and still nothing was run" test ! -s "$CALLS"
co --run W6-INSTRUMENTED <<<"yes"
check "the instrumented suite without a designated device serial is refused" refused "--adb-serial"

# ---------------------------------------------------------------------------
section "U10 cannot run before U6"
# ---------------------------------------------------------------------------
co --config "$WORK/config" --run G7UP-fedora44-U10 <<<"yes"
check "U10 on a fresh directory is refused" refused "G7UP-fedora44-U10 is blocked"
check "…and the downgrade stage was never invoked" absent "$(calls)" "--stage downgrade"

# ---------------------------------------------------------------------------
section "Confirmation: declined means nothing changes"
# ---------------------------------------------------------------------------
co --config "$WORK/config" --run G7UP-fedora44-INSTALL <<<"no"
check "a declined INSTALL exits 5" test "$RC" -eq 5
check "…prints the exact command it would have run" contains "$OUT" "--stage install --domain g7-f44 --distro fedora44"
check "…and did not run it" absent "$(calls)" "--stage install"
co --config "$WORK/config" --status </dev/null
check "…and the gate is still PENDING" test "$(gstate G7UP-fedora44-INSTALL)" = PENDING
co --config "$WORK/config" --run G7UP-fedora44-INSTALL </dev/null
check "no answer at all (EOF) is not a yes" test "$RC" -eq 5

# ---------------------------------------------------------------------------
section "One VM at a time"
# ---------------------------------------------------------------------------
echo g7-f44-lc > "$STUB/running"
co --config "$WORK/config" --run G7UP-fedora44-INSTALL <<<"yes"
check "INSTALL is refused while another configured guest is running" refused "one VM at a time"
: > "$STUB/running"

# ---------------------------------------------------------------------------
section "The G7-UP chain, in the order §3 requires"
# ---------------------------------------------------------------------------
co --config "$WORK/config" --run G7UP-fedora44-INSTALL <<<"yes"
check "INSTALL runs after 'yes' and is PASS" test "$(gstate G7UP-fedora44-INSTALL)" = PASS
co --config "$WORK/config" --run G7UP-fedora44-U2 <<<$'y\ny\ny\ny\ny'
check "U2 (operator attestation) is PASS on five 'y'" test "$(gstate G7UP-fedora44-U2)" = PASS
co --config "$WORK/config" --run G7UP-fedora44-UPGRADE <<<"yes"
check "UPGRADE is PASS and left a checkpoint" test "$(gstate G7UP-fedora44-UPGRADE)" = PASS
check "U10 is BLOCKED while U6 has not passed" test "$(gstate G7UP-fedora44-U10)" = BLOCKED
co --config "$WORK/config" --run G7UP-fedora44-U10 <<<"yes"
check "U10 after the upgrade but before U6 is refused" refused "waiting for G7UP-fedora44-U6 PASS"
check "…and the downgrade stage was never invoked" absent "$(calls)" "--stage downgrade"

check "U6 declined with no record: nothing recorded, nothing run" declined G7UP-fedora44-U6 no
co --config "$WORK/config" --status </dev/null
check "…and U6 is still PENDING" test "$(gstate G7UP-fedora44-U6)" = PENDING
echo empty > "$STUB/u6mode"
co --config "$WORK/config" --run G7UP-fedora44-U6 <<<"yes"
check "U6 over an EMPTY U6-RESULT is FAIL, although the harness exited 0 and printed ok" test "$(gstate G7UP-fedora44-U6)" = FAIL
check "…and the RECORD says FAIL too, not only the status re-check" grep -qx 'state=FAIL' "$EV/state/G7UP-fedora44-U6"
check "…so U10 is still BLOCKED" test "$(gstate G7UP-fedora44-U10)" = BLOCKED
check "a U6 FAIL, --rerun declined: the FAIL stays current and nothing is archived" declined G7UP-fedora44-U6 no --rerun
check "…and no U6 history exists" test -z "$(hist_with G7UP-fedora44-U6 FAIL)"
echo wrongdomain > "$STUB/u6mode"
co --config "$WORK/config" --rerun --run G7UP-fedora44-U6 <<<"yes"
check "U6 evidence recorded for another domain is FAIL" test "$(gstate G7UP-fedora44-U6)" = FAIL
co --config "$WORK/config" --run G7UP-fedora44-U10 <<<"yes"
check "…and U10 is still refused" absent "$(calls)" "--stage downgrade"
echo good > "$STUB/u6mode"
co --config "$WORK/config" --rerun --run G7UP-fedora44-U6 <<<"yes"
check "U6 with real, matching evidence is PASS" test "$(gstate G7UP-fedora44-U6)" = PASS
check "U10 now waits for the security-log gate, which only the upgraded guest can run" test "$(gstate G7UP-fedora44-U10)" = BLOCKED

# Audit A, the --not-executed bypass: status() reported a not-executed record
# before evaluating prerequisites, and run_gate() let that record execute. A
# not-executed U10 therefore ran the downgrade with the security-log gate
# undecided. Reproduced here; it must now be refused.
co --config "$WORK/config" --not-executed G7UP-fedora44-U10 --reason "bypass probe" </dev/null
check "U10 can be recorded not-executed while SECLOG is undecided" grep -qx 'state=NOT_EXECUTED' "$EV/state/G7UP-fedora44-U10"
co --config "$WORK/config" --run G7UP-fedora44-U10 <<<"yes"
check "BYPASS: a not-executed U10 is still refused while SECLOG is undecided" refused "waiting for G7UP-fedora44-SECLOG"
check "…and the downgrade stage was never invoked" absent "$(calls)" "--stage downgrade"
co --config "$WORK/config" --status </dev/null
check "…U10 shows its prerequisite, not its own record, as the reason" \
    contains "$(grep -F 'id=G7UP-fedora44-U10 ' <<<"$OUT")" "waiting for G7UP-fedora44-SECLOG"
check "a not-executed U10 (nothing downgraded) leaves SECLOG runnable" test "$(gstate G7UP-fedora44-SECLOG)" = PENDING
check "SECLOG declined with no record: nothing recorded, nothing run" declined G7UP-fedora44-SECLOG no
# A downgrade started outside the coordinator leaves upgrade-gates.sh's marker.
echo "started_utc=2026-09-25T00:00:00Z" > "$EV/g7up/fedora44/U10-STARTED"
co --config "$WORK/config" --run G7UP-fedora44-SECLOG <<<"yes"
check "SECLOG is refused once upgrade-gates.sh's U10-STARTED marker exists" refused "U10 has run"
check "…and security-log-evidence.sh was never invoked" absent "$(calls)" "security-log"
rm -f "$EV/g7up/fedora44/U10-STARTED"
co --config "$WORK/config" --not-executed G7UP-fedora44-SECLOG </dev/null
check "not-executed without a reason is refused" refused "needs --reason"
co --config "$WORK/config" --not-executed G7UP-fedora44-SECLOG --reason "phone fixture unavailable on 2026-09-25" </dev/null
check "not-executed with a reason is BLOCKED, never PASS" test "$(gstate G7UP-fedora44-SECLOG)" = BLOCKED
check "…and U10's prerequisites now hold: its only block is its own not-executed record" \
    contains "$(grep -F 'id=G7UP-fedora44-U10 ' <<<"$OUT")" "not executed: bypass probe"
check "U10 declined over its not-executed record: that record stays current, unarchived" declined G7UP-fedora44-U10 no
co --config "$WORK/config" --run G7UP-fedora44-U10 <<<"yes"
check "U10 runs after a verified U6 PASS and is PASS" test "$(gstate G7UP-fedora44-U10)" = PASS
check "…and its earlier not-executed record was kept in state/history/, not overwritten" has_hist G7UP-fedora44-U10 NOT_EXECUTED
co --config "$WORK/config" --rerun --run G7UP-fedora44-U10 <<<"yes"
check "a second U10 (--rerun) is refused before the harness: the guest is already on 1.0.0" refused "U10 already started"
check "…the downgrade stage ran exactly once" need_exact_count "downgrade invocations" "$(ncalls '--stage downgrade')" 1
co --config "$WORK/config" --status </dev/null
order="$(grep -n -e '--stage peer-u6' -e '--stage downgrade' "$CALLS" | tail -2 | cut -d: -f2- | awk '{print $3}' | tr '\n' ' ')"
check "the stages ran in the order peer-u6, then downgrade" test "$order" = "peer-u6 downgrade "
check "the security-log gate can no longer be run (the upgraded guest is gone)" test "$(gstate G7UP-fedora44-SECLOG)" = BLOCKED
# The bypass itself: SECLOG's own NOT_EXECUTED record, after U10.
co --config "$WORK/config" --run G7UP-fedora44-SECLOG <<<"yes"
check "BYPASS: a not-executed SECLOG is refused after U10 destroyed the upgraded guest" refused "U10 has run"
co --config "$WORK/config" --rerun --run G7UP-fedora44-SECLOG <<<"yes"
check "…and with --rerun" refused "U10 has run"
cp "$EV/state/G7UP-fedora44-SECLOG" "$WORK/seclog.rec"
printf 'gate=G7UP-fedora44-SECLOG\nstate=RUNNING\nstarted_utc=x\nlog=\nattempt=probe\nselftest=1\n' > "$EV/state/G7UP-fedora44-SECLOG"
co --config "$WORK/config" --next </dev/null
check "…and an interrupted SECLOG is not resumed by --next after U10" absent "$OUT" "running G7UP-fedora44-SECLOG"
check "…--next moves on to the first runnable gate instead (W2-GNOME)" contains "$OUT" "running W2-GNOME"
check "…nor run directly" bash -c '! PATH="$1:$PATH" XDG_RUNTIME_DIR="$2" PRE_G8_GATES_DIR="$3" bash "$4" --evidence "$5" --config "$6" --run G7UP-fedora44-SECLOG <<<yes >/dev/null 2>&1' \
    _ "$WORK/bin" "$WORK" "$STUB" "$COORD" "$EV" "$WORK/config"
cp "$WORK/seclog.rec" "$EV/state/G7UP-fedora44-SECLOG"
check "…security-log-evidence.sh was never invoked, by any route" absent "$(calls)" "security-log"

echo "ok    L15: forged afterwards" >> "$EV/g7up/fedora44/U6/lifecycle-peer-gates.log"
co --config "$WORK/config" --status </dev/null
check "a U6 log altered after its PASS turns the gate into FAIL" test "$(gstate G7UP-fedora44-U6)" = FAIL
check "…and says why" contains "$OUT" "no longer verifies"
co --config "$WORK/config" --rerun --run G7UP-fedora44-U6 <<<"yes"
check "a U6 retry after U10 is refused: its FAIL record does not waive the upgraded guest" refused "U10 has started"
check "…and peer-u6 was not invoked again" need_exact_count "peer-u6 invocations" "$(ncalls '--stage peer-u6')" 3

# ---------------------------------------------------------------------------
section "Fresh-guest gates"
# ---------------------------------------------------------------------------
co --config "$WORK/config" --distro fedora44 --u8-domain g7-f44 --run G7UP-fedora44-U8 <<<"g7-f44"
check "U8 on the upgrade guest itself is refused" refused "is the fedora44 upgrade guest"
co --config "$WORK/config" --run G7UP-fedora44-U8 <<<"yes"
check "U8 needs the fresh guest's NAME typed back; 'yes' is not enough" test "$RC" -eq 5
co --config "$WORK/config" --run G7UP-fedora44-U8 <<<"g7-f44-fresh"
check "U8 runs on the designated fresh guest and is PASS" test "$(gstate G7UP-fedora44-U8)" = PASS

# ---------------------------------------------------------------------------
section "Interruption and resume"
# ---------------------------------------------------------------------------
touch "$STUB/lc-sleep"
( printf 'g7-f44-lc\n' | PATH="$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" PRE_G8_GATES_DIR="$STUB" \
    setsid bash "$COORD" --evidence "$EV" --config "$WORK/config" --run LIFECYCLE-fedora44 >/dev/null 2>&1 & echo $! > "$WORK/pid" )
for _ in $(seq 1 50); do grep -q '^state=RUNNING' "$EV/state/LIFECYCLE-fedora44" 2>/dev/null && break; sleep 0.2; done
kill -9 -- "-$(cat "$WORK/pid")" 2>/dev/null; sleep 0.5
rm -f "$STUB/lc-sleep"
co --config "$WORK/config" --status </dev/null
check "a gate killed mid-run is BLOCKED (interrupted), not PASS and not PENDING" test "$(gstate LIFECYCLE-fedora44)" = BLOCKED
check "…and the status says it was interrupted" contains "$OUT" "interrupted"
co --config "$WORK/config" --not-executed LIFECYCLE-fedora44 --reason "hide the interruption" </dev/null
check "an interrupted run cannot be recorded not-executed (it was executed, at least in part)" refused "was started"
co --config "$WORK/config" --next <<<"g7-f44-lc"
check "--next resumes the interrupted gate before any new one" contains "$OUT" "running LIFECYCLE-fedora44"
check "…and it completes as PASS" test "$(gstate LIFECYCLE-fedora44)" = PASS
check "…with the interrupted attempt's record kept in state/history/" has_hist LIFECYCLE-fedora44 RUNNING

# ---------------------------------------------------------------------------
section "Wave 6 signing: passwords reach the terminal and nothing else"
# ---------------------------------------------------------------------------
co --run W6-SIGNING <<<"yes"
check "signing without both media configured is refused" refused "--media-a"
co --media-a "$WORK/A" --media-b "$WORK/B" --run W6-SIGNING <<<"yes"
check "provisioning ran and is PASS once --status shows restore-verified backups" test "$(gstate W6-SIGNING)" = PASS
check "the password was shown on the operator's terminal" contains "$OUT" "S3CR3T-SENTINEL-4242"
leak="$(grep -rl "S3CR3T-SENTINEL-4242" "$EV" 2>/dev/null || true)"
check "the password is in NO file under the evidence directory" test -z "$leak"

# ---------------------------------------------------------------------------
section "Wave 6 instrumented suite"
# ---------------------------------------------------------------------------
touch "$STUB/android/zero-tests"
co --config "$WORK/config" --run W6-INSTRUMENTED <<<"yes"
check "a run whose results hold zero tests is FAIL" test "$(gstate W6-INSTRUMENTED)" = FAIL
rm -f "$STUB/android/zero-tests"
co --config "$WORK/config" --rerun --run W6-INSTRUMENTED <<<"yes"
check "a run with 5 tests and no failures is PASS" test "$(gstate W6-INSTRUMENTED)" = PASS

# ---------------------------------------------------------------------------
section "W6-COMPONENT-UPGRADE: no attempt before the first confirmation"
# ---------------------------------------------------------------------------
# Final-repair finding: the gate wrote RUNNING (archiving a FAIL on --rerun)
# before its first confirmation, so a "no" erased the current FAIL and turned
# the overall result from FAIL into INCOMPLETE with nothing measured.
C=W6-COMPONENT-UPGRADE; APKS=(--apk-n "$WORK/apk-n.apk" --apk-n1 "$WORK/apk-n1.apk")
check "(b) no record, declined: nothing recorded and no device action" declined "$C" no "${APKS[@]}"
check "…no record file exists" test ! -e "$EV/state/$C"
co --config "$WORK/config" --status </dev/null
check "…and the gate is still PENDING" test "$(gstate $C)" = PENDING
check "…with no history" contains "$(grep -F "id=$C " <<<"$OUT")" "history=0 history_fail=0"
check "(b) no record, EOF at the confirmation: the same" declined "$C" "" "${APKS[@]}"
co --config "$WORK/config" --apk-n "$WORK/apk-n.apk" --apk-n1 "$WORK/apk-same.apk" --run "$C" <<<"yes"
check "N+1 not above N is refused before the confirmation" refused "would not be an upgrade"
check "…and recorded nothing" test ! -e "$EV/state/$C"
co --config "$WORK/config" "${APKS[@]}" --run "$C" <<<$'yes
not pinned'
check "a run whose shortcut was not pinned is a measured FAIL" test "$(gstate $C)" = FAIL
comp_fail="$(cat "$EV/state/$C")"; n_fail0="$(sed -n 's/^PRE_G8_COUNTS .* fail=\([0-9]*\) .*/\1/p' <<<"$OUT")"
check "(a) FAIL, --rerun declined at the first confirmation: nothing moved" declined "$C" no --rerun "${APKS[@]}"
check "…the FAIL record is byte-identical and current" test "$(cat "$EV/state/$C" 2>/dev/null)" = "$comp_fail"
check "…and was not archived" test ! -e "$EV/state/history" -o -z "$(ls "$EV/state/history/$C".* 2>/dev/null)"
check "…the operator is told the gate keeps its previous state" contains "$OUT" "the gate keeps its previous state"
co --config "$WORK/config" --status </dev/null
check "…the gate is still FAIL, with no history" contains "$(grep -F "id=$C " <<<"$OUT")" "state=FAIL history=0 history_fail=0"
check "…and the summary's FAIL count is unchanged" test "$(sed -n 's/^PRE_G8_COUNTS .* fail=\([0-9]*\) .*/\1/p' <<<"$OUT")" = "$n_fail0"
# The same in a REAL run, where the overall result is computed. A real run
# reads its answer from the terminal; with none (setsid: no controlling tty)
# the first confirmation is refused, which must move nothing either.
command -v setsid >/dev/null 2>&1 || notok "setsid is not installed: the real-mode decline could not be measured"
RC2="$WORK/real-comp"; mkdir -p "$RC2/state"
printf 'gate=%s\nstate=FAIL\nreason=a real FAIL\nattempt=probe\nselftest=0\n' "$C" > "$RC2/state/$C"
real="$(PATH="$WORK/bin:$PATH" XDG_RUNTIME_DIR="$WORK" setsid -w bash "$COORD" --evidence "$RC2" --adb-serial SERIAL01 \
    "${APKS[@]}" --rerun --run "$C" 2>&1 </dev/null)"; rrc=$?
check "(a) REAL: FAIL, --rerun with no terminal to confirm at is refused (exit 2)" test "$rrc" -eq 2
check "…at the confirmation, after the preparation" contains "$real" "needs explicit confirmation at a terminal"
check "…the real FAIL record is byte-identical, and there is no history" \
    test "$(cat "$RC2/state/$C")" = "$(printf 'gate=%s\nstate=FAIL\nreason=a real FAIL\nattempt=probe\nselftest=0' "$C")" -a ! -e "$RC2/state/history"
real="$(XDG_RUNTIME_DIR="$WORK" bash "$COORD" --evidence "$RC2" --status 2>&1 </dev/null)"
check "…and the REAL overall result is still FAIL, not INCOMPLETE" contains "$real" "PRE_G8_RESULT=FAIL"
check "…with W6-COMPONENT-UPGRADE still FAIL" contains "$real" "id=$C state=FAIL history=0 history_fail=0 "
check "no device action was taken by any decline" test "$(ncalls "^adb -s SERIAL01 install")" -eq 1
co --config "$WORK/config" "${APKS[@]}" --rerun --run "$C" <<<$'yes
PINNED
yes
y'
check "(c) --rerun, confirmed: the new attempt runs and is PASS" test "$(gstate $C)" = PASS
check "…N then N+1 were installed" test "$(ncalls "^adb -s SERIAL01 install -r ")" -eq 3
h="$(hist_with "$C" FAIL)"
check "…and the FAIL it replaced is in state/history/, byte-identical" test -n "$h" -a "$(cat "$h" 2>/dev/null)" = "$comp_fail"
check "…the summary names it" contains "$OUT" "id=$C state=PASS history=1 history_fail=1 "
co --config "$WORK/config" "${APKS[@]}" --rerun --run "$C" <<<$'yes
PINNED
no'
check "a later confirmation declined exits 5" test "$RC" -eq 5
check "…leaving THIS attempt's record open (RUNNING), and says so" \
    test "$(sed -n 's/^state=//p' "$EV/state/$C")" = RUNNING -a -n "$(grep -F 'stays recorded as RUNNING for this attempt' <<<"$OUT")"
check "…with the PASS it replaced archived, not lost" has_hist "$C" PASS

# ---------------------------------------------------------------------------
section "Wave 2 real-session checks, GNOME and KDE separately"
# ---------------------------------------------------------------------------
co --run W2-KDE <<<"GNOME 49 Wayland"
check "a KDE record made from a GNOME session is refused" refused "does not name the session"
co --run W2-GNOME <<<$'GNOME 49 Wayland on host f44\ny\ny\ny\ny\ny\ny\ny\ny\ny\nFiles for SM-X620, switch, off\nRevoke this device, button'
check "GNOME, every item observed and both announcements recorded: PASS" test "$(gstate W2-GNOME)" = PASS
co --run W2-KDE <<<$'KDE Plasma 6.4 Wayland\ny\ny\ny\nn\ny\ny\ny\ny\ny\nFiles for SM-X620\nRevoke'
check "KDE with one item not observed: FAIL" test "$(gstate W2-KDE)" = FAIL
check "…naming the item" contains "$OUT" "Files toggles on, then off"

# ---------------------------------------------------------------------------
section "A measured FAIL is kept: FAIL -> --not-executed is refused"
# ---------------------------------------------------------------------------
kde_rec="$(cat "$EV/state/W2-KDE")"
kde_ans="$(sed -n 's/^answers=//p' "$EV/state/W2-KDE")"
co --not-executed W2-KDE --reason "the operator would rather not have a FAIL" </dev/null
check "--not-executed over a measured FAIL is refused" refused "a FAIL is evidence"
check "…the FAIL record is byte-identical afterwards" test "$(cat "$EV/state/W2-KDE")" = "$kde_rec"
co --status </dev/null
check "…the gate is still FAIL" test "$(gstate W2-KDE)" = FAIL
n_fail="$(sed -n 's/^PRE_G8_COUNTS .* fail=\([0-9]*\) .*/\1/p' <<<"$OUT")"
check "…and still counted as a FAIL in the summary (n_fail > 0 is what makes a real result FAIL)" test "${n_fail:-0}" -ge 1
co --run W2-KDE <<<$'KDE Plasma 6.4 Wayland'
check "running a FAIL again needs --rerun" refused "--rerun"
co --rerun --run W2-KDE <<<$'KDE Plasma 6.4 Wayland\ny\ny\ny\ny\ny\ny\ny\ny\ny\nFiles for SM-X620\nRevoke'
check "a retry (--rerun) is a new attempt and may PASS" test "$(gstate W2-KDE)" = PASS
h="$(hist_with W2-KDE FAIL)"
check "…the original FAIL record is preserved, byte-identical, in state/history/" test -n "$h" -a "$(cat "$h" 2>/dev/null)" = "$kde_rec"
check "…with its answers file still present and matching its digest" \
    test -s "$kde_ans" -a "$(sha256sum < "$kde_ans" | cut -d' ' -f1)" = "$(sed -n 's/^answers_sha256=//p' "$h")"
check "…and the summary names the earlier FAIL" contains "$OUT" "id=W2-KDE state=PASS history=1 history_fail=1 "
check "the earlier instrumented-suite FAIL is kept the same way" has_hist W6-INSTRUMENTED FAIL

# The same refusal in a REAL run, where the overall result is computed: a
# hand-written real FAIL record, then --not-executed, then --status.
RV="$WORK/real-fail"; mkdir -p "$RV/state"
printf 'gate=W2-GNOME\nstate=FAIL\nreason=a real FAIL\nattempt=probe\nselftest=0\n' > "$RV/state/W2-GNOME"
real="$(XDG_RUNTIME_DIR="$WORK" bash "$COORD" --evidence "$RV" --not-executed W2-GNOME --reason "go away" 2>&1 </dev/null)"; rrc=$?
check "a REAL --not-executed over a FAIL is refused (exit 2)" test "$rrc" -eq 2
check "…naming why" contains "$real" "a FAIL is evidence"
real="$(XDG_RUNTIME_DIR="$WORK" bash "$COORD" --evidence "$RV" --status 2>&1 </dev/null)"
check "…and the REAL overall result remains FAIL" contains "$real" "PRE_G8_RESULT=FAIL"

# ---------------------------------------------------------------------------
section "No gate is silently skipped"
# ---------------------------------------------------------------------------
co --config "$WORK/config" --status </dev/null
n_gates="$(grep -c '^PRE_G8_GATE ' <<<"$OUT")"
n_stated="$(grep -cE '^PRE_G8_GATE id=[A-Za-z0-9-]+ state=(PASS|FAIL|PENDING|BLOCKED) ' <<<"$OUT")"
check "all 37 gates still appear, each with a state" need_exact_count "gates with a state" "$n_stated" 37
check "gates never run are PENDING or BLOCKED, e.g. G7UP-ubuntu2404-INSTALL (W6-COMPONENT-UPGRADE is run above)" test "$(gstate G7UP-ubuntu2404-INSTALL)" = PENDING
check "…and the whole ubuntu2404 chain is present" test "$(grep -c 'id=G7UP-ubuntu2404-' <<<"$OUT")" -eq 7
real="$(XDG_RUNTIME_DIR="$WORK" bash "$COORD" --evidence "$EV" --status 2>&1 </dev/null)"
check "a REAL --status over these self-test records counts none of them as PASS" contains "$real" "PRE_G8_COUNTS pass=0 "

# ---------------------------------------------------------------------------
section "Every other confirming gate: a declined --rerun moves nothing"
# ---------------------------------------------------------------------------
check "W6-INSTRUMENTED (PASS), --rerun declined" declined W6-INSTRUMENTED no --rerun
check "G7UP-fedora44-UPGRADE (PASS), --rerun declined" declined G7UP-fedora44-UPGRADE no --rerun
check "G7UP-fedora44-U8 (PASS), --rerun with 'yes' instead of the guest's name" declined G7UP-fedora44-U8 yes --rerun
check "LIFECYCLE-fedora44 (PASS), --rerun declined" declined LIFECYCLE-fedora44 no --rerun
rm -f "$STUB/android/signing/record"
check "W6-SIGNING, not provisioned, declined" declined W6-SIGNING no --media-a "$WORK/A" --media-b "$WORK/B" --rerun
check "G7UP-debian13-INSTALL, no record, declined" declined G7UP-debian13-INSTALL no --distro debian13 --old-pkgdir "$OLD"

printf '\n-----------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
