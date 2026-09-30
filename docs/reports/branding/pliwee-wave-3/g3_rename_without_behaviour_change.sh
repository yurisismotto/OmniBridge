#!/usr/bin/env bash
# G3 — rename without behaviour change (Pliwee rebrand Wave 3).
#
# The static half of the gate. The behavioural half is the test suites, whose
# per-suite counts are compared in section F from the logs this wave captured
# before and after the rename (g3_suite_counts.py). This script proves:
#
#   A. every crate is `pliwee-*`, and the three binaries keep their names (W7);
#   B. the protobuf tree moved (six schemas, `pliwee.v1[.capabilities]`,
#      `io.github.yurisismotto.pliwee.proto[.capabilities]`), and nothing else
#      under protocol/ changed — the frozen DER vectors included;
#   C. the exit-criterion census: every `omnibridge[_-]` left in
#      desktop/**/*.rs is classified as owned by a later wave, with exact
#      per-class counts and zero unexplained;
#   D. every wire constant W5 owns is still the OmniBridge literal, on both
#      sides; no persistent Android identifier W6 owns moved;
#   E. every harness pattern that looked for a renamed log name was renamed
#      with it, and the old pattern is gone;
#   F. identical test counts per suite, before and after, except for the
#      tests this wave added, which are named;
#   G. the Windows workflow builds exactly the seven portable crates and its
#      `-like` filter carries the new prefix.
#
# Usage, from the repository root:
#   bash docs/reports/branding/pliwee-wave-3/g3_rename_without_behaviour_change.sh [BASE]
# BASE defaults to 23a4503, the Wave 2 commit Wave 3 starts from.
# Exit 0 = PASS, 1 = FAIL. A missing precondition is a FAIL, never a pass.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "G3: not in a git checkout" >&2; exit 1; }
cd "$ROOT" || exit 1
# shellcheck source=packaging/tests/lib/assert.sh
. packaging/tests/lib/assert.sh

BASE="${1:-23a4503}"
HERE="docs/reports/branding/pliwee-wave-3"
fail=0
ok()    { printf 'ok    %s\n' "$*"; }
notok() { printf 'FAIL  %s\n' "$*"; fail=1; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else notok "$label"; fi; }

need_tool git python3 sha256sum diff || exit 1
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
    || { echo "G3: baseline $BASE is not a commit here" >&2; exit 1; }

# --- A. crates and binaries ------------------------------------------------
echo "== A. crates and binaries"
manifests="$(git ls-files 'desktop/*Cargo.toml' 'desktop/**/Cargo.toml' | grep -v '^desktop/Cargo.toml$' || true)"
need_nonempty "the member manifests" "$manifests" 12 || exit 1
n_manifests="$(grep -c . <<<"$manifests")"
check "exactly 12 member manifests ($n_manifests)" need_exact_count "member manifests" "$n_manifests" 12
pkgnames="$(for m in $manifests; do awk '/^\[package\]/{p=1;next} /^\[/{p=0} p&&/^name = /{print; exit}' "$m"; done)"
n_pliwee="$(grep -c '^name = "pliwee-' <<<"$pkgnames" || true)"
check "all 12 packages are pliwee-* ($n_pliwee)" need_exact_count "pliwee packages" "$n_pliwee" 12
check "no package is still omnibridge-*" absent "$pkgnames" 'omnibridge'
bins="$(for m in $manifests; do awk '/^\[\[bin\]\]/{b=1;next} /^\[/{b=0} b&&/^name = /{print}' "$m"; done | sort)"
expected_bins="$(printf 'name = "%s"\n' omnibridge omnibridge-gui omnibridged | sort)"
check "the binaries are exactly omnibridge, omnibridge-gui, omnibridged (W7 owns them)" \
    test "$bins" = "$expected_bins"
check "the GUI library target is pliwee_gui" contains "$(cat desktop/gui/Cargo.toml)" 'name = "pliwee_gui"'

# --- B. protobuf tree --------------------------------------------------------
echo "== B. protobuf tree"
protos="$(git ls-files 'protocol/proto/**.proto')"
need_nonempty "the tracked .proto files" "$protos" 6 || exit 1
check "exactly 6 schemas, all under protocol/proto/pliwee/v1" \
    need_exact_count "pliwee schemas" "$(grep -c '^protocol/proto/pliwee/v1/' <<<"$protos")" 6
check "no schema left under protocol/proto/omnibridge" absent "$protos" 'protocol/proto/omnibridge/'
pkg_lines="$(grep -h '^package ' $protos)"
check "6 package lines, all pliwee.v1[.capabilities]" \
    need_exact_count "pliwee package lines" "$(grep -cE '^package pliwee\.v1(\.capabilities)?;$' <<<"$pkg_lines")" 6
jp_lines="$(grep -h '^option java_package' $protos)"
check "6 java_package lines, all io.github.yurisismotto.pliwee.proto[.capabilities]" \
    need_exact_count "pliwee java_package lines" \
    "$(grep -cE '^option java_package = "io\.github\.yurisismotto\.pliwee\.proto(\.capabilities)?";$' <<<"$jp_lines")" 6
# Every schema is a rename of its BASE counterpart: the only changed lines are
# package / java_package / import.
schema_diff="$(git diff -M "$BASE" -- protocol/proto | grep -E '^[-+][^-+]' || true)"
need_nonempty "the schema diff" "$schema_diff" 1 || notok "the schema diff is empty; the rename did not happen"
other="$(grep -vE '^[-+](package (omnibridge|pliwee)\.v1(\.capabilities)?;|option java_package = "io\.github\.yurisismotto\.(omnibridge|pliwee)\.proto(\.capabilities)?";|import "(omnibridge|pliwee)/v1/core\.proto";)$' <<<"$schema_diff" || true)"
check "the schema diff touches only package, java_package and import lines" test -z "$other"
check "protocol/testdata (frozen DER vectors, D10) is unchanged" git diff --quiet "$BASE" -- protocol/testdata
check "the descriptor snapshot is present" test -s desktop/proto/tests/descriptor-field-table.txt

# --- C. exit-criterion census -----------------------------------------------
echo "== C. census of omnibridge[_-] in desktop/**/*.rs"
census="$(git grep -nE 'omnibridge[_-]' -- 'desktop/**/*.rs' || true)"
need_nonempty "the census" "$census" 1 || notok "the census is empty; this wave expects later-wave identifiers to remain"
python3 - "$census" <<'PY' || fail=1
import re, sys
rules = [
    ("W5 wire constant", r'ALPN "omnibridge/1"|b"omnibridge-data/1"|fn control_alpn_is_omnibridge_1|fn data_alpn_is_omnibridge_data_1|fn mdns_service_type_is_omnibridge_tcp'),
    ("W4 path", r'fn the_omnibridge_subdirectory_is_used|/tmp/omnibridge-\{\}|/tmp/omnibridge-fake-phone'),
    ("W0/W6/W7 asset or resource name", r'omnibridge-(mark|mark-mono|app-icon|android-monochrome|wordmark|logo-lockup)\.svg'),
    ("W7 binary / process name", r'omnibridge-gui|omnibridge-quickpanel'),
    ("W7 tray item id", r'fn d6_the_watcher_sees_exactly_one_omnibridge_item'),
]
expected = {
    "W5 wire constant": 6,
    "W4 path": 4,
    "W0/W6/W7 asset or resource name": 24,
    "W7 binary / process name": 45,
    "W7 tray item id": 1,
}
counts = {k: 0 for k in expected}
bad = []
for line in sys.argv[1].splitlines():
    for label, rx in rules:
        if re.search(rx, line):
            counts[label] += 1
            break
    else:
        bad.append(line)
total = sum(counts.values()) + len(bad)
for k, v in counts.items():
    status = "ok   " if v == expected[k] else "FAIL "
    print(f"{status} census: {k}: {v} (expected {expected[k]})")
print(f"{'ok   ' if not bad else 'FAIL '} census: unexplained: {len(bad)}")
for b in bad:
    print(f"        {b}")
print(f"{'ok   ' if total == sum(expected.values()) else 'FAIL '} census: total {total} (expected {sum(expected.values())})")
sys.exit(0 if not bad and counts == expected else 1)
PY

# --- D. identifiers later waves own did not move ----------------------------
echo "== D. wire (W5) and Android identity (W6) unchanged"
wire_rs="$(cat desktop/core/src/lib.rs desktop/core/src/qr.rs desktop/core/src/pairing.rs desktop/capabilities/files/src/auth.rs desktop/core/src/identity.rs)"
for lit in 'b"omnibridge/1"' 'b"omnibridge-data/1"' '"_omnibridge._tcp.local."' '"omnibridge1"' \
           'b"omnibridge/pairing-proof/v1"' 'b"omnibridge/pairing-confirm/v1"' \
           'b"omnibridge/files.v1/data-stream/v1"' 'format!("omnibridge:{device_id}")'; do
    check "desktop wire literal $lit" contains "$wire_rs" "$lit"
done
kt_main="android/app/src/main/java/io/github/yurisismotto/omnibridge"
wire_kt="$(cat "$kt_main"/net/PinnedTrustManager.kt "$kt_main"/net/Discovery.kt "$kt_main"/pairing/QrPayload.kt "$kt_main"/pairing/PairingProof.kt "$kt_main"/files/StreamAuth.kt "$kt_main"/notifications/NotificationIdentity.kt 2>/dev/null)"
need_nonempty "the Android wire sources" "$wire_kt" 50 || notok "Android wire sources unreadable"
for lit in '"omnibridge/1"' '"omnibridge-data/1"' '"_omnibridge._tcp."' '"omnibridge1"' \
           'omnibridge/pairing-proof/v1' 'omnibridge/pairing-confirm/v1' \
           'omnibridge/files.v1/data-stream/v1' 'omnibridge/notifications.v1/id/v1'; do
    check "Android wire literal $lit" contains "$wire_kt" "$lit"
done
gradle="$(cat android/app/build.gradle.kts)"
check "applicationId still io.github.yurisismotto.omnibridge (W6)" contains "$gradle" 'applicationId = "io.github.yurisismotto.omnibridge"'
check "namespace still io.github.yurisismotto.omnibridge (W6)" contains "$gradle" 'namespace = "io.github.yurisismotto.omnibridge"'
manifest="$(cat android/app/src/main/AndroidManifest.xml)"
for comp in '.notifications.OmniBridgeNotificationListener' '.ui.ClipboardTileService' '.ui.MainActivity' '.ui.SendActivity'; do
    check "manifest component $comp unchanged (W6)" contains "$manifest" "android:name=\"$comp\""
done
check "the Kotlin package directory did not move (W6)" test -d "$kt_main"
check "no desktop APP_ID moved (W7)" test "$(git grep -c 'APP_ID: &str = "io.github.yurisismotto.omnibridge"' -- desktop | grep -c .)" -ge 2

# --- E. harness patterns renamed with the names they look for ---------------
echo "== E. harness patterns"
sle="$(cat packaging/tests/security-log-evidence.sh)"
check "L16 anchors on the renamed tracing target pliwee_capability_notifications" contains "$sle" "pliwee_capability_notifications"
check "no harness still looks for omnibridge_capability_notifications" \
    test -z "$(git grep -l 'omnibridge_capability_notifications' -- packaging android desktop .github || true)"
check "L16 anchors on the renamed fixture tag PliweeFixture" contains "$sle" "PliweeFixture: op=post"
fixture="$(cat android/fixture/src/main/java/io/github/yurisismotto/omnibridge/fixture/FixtureActivity.kt)"
check "the fixture logs under PliweeFixture" contains "$fixture" 'TAG = "PliweeFixture"'
check "nothing still logs or looks for OmniBridgeFixture" \
    test -z "$(git grep -l 'OmniBridgeFixture' -- packaging android desktop .github || true)"
canary="$(cat android/app/src/androidTest/java/io/github/yurisismotto/omnibridge/NotificationLoggingCanaryTest.kt)"
check "the logging canary reads the renamed tags" contains "$canary" '"PliweeListener",'
check "the logging canary requires a line from its tags before an absence counts" contains "$canary" 'TAGS.any { tag ->'
for f in desktop/daemon/tests/file_log_privacy.rs desktop/daemon/tests/notification_log_privacy.rs; do
    check "$f anchors on the pliwee_ tracing target" contains "$(cat "$f")" 'text.contains("pliwee_")'
done
check "no Kotlin type OmniBridge* remains except the W6 listener component" \
    test -z "$(git grep -nE '\bOmniBridge[A-Z][A-Za-z]*' -- android | grep -v 'OmniBridgeNotificationListener' || true)"
check "no Kotlin source imports the old proto package" \
    test -z "$(git grep -l 'io\.github\.yurisismotto\.omnibridge\.proto' -- android || true)"

# --- F. per-suite counts ------------------------------------------------------
echo "== F. per-suite test counts, before and after"
python3 - "$HERE" <<'PY' || fail=1
import os, sys
here = sys.argv[1]
# Tests this wave added, by suite. Nothing else may move.
ADDED_RUST = {
    "<root>_proto tests/namespace.rs": 1,          # the_field_table_is_identical_to_the_pre_rename_snapshot
    "<root>_core tests/portable_boundary.rs": 2,   # the_windows_job_* x2
}
def load_rust(p):
    out = {}
    for line in open(p):
        if line.startswith("TOTAL"):
            continue
        n, crate, target, *rest = line.split()
        kv = dict(x.split("=") for x in rest)
        out[f"{crate} {target}"] = (int(kv["passed"]), int(kv["failed"]), int(kv["ignored"]))
    return out
def load_android(p):
    out = {}
    for line in open(p):
        name, tests, skipped, failures, errors = line.split()
        out[name] = tuple(int(x.strip('"')) for x in (tests, skipped, failures, errors))
    return out
bad = 0
def compare(label, before, after, added, key_count=0):
    global bad
    if not before or not after:
        print(f"FAIL  {label}: a count file is empty"); bad = 1; return
    if set(before) != set(after):
        print(f"FAIL  {label}: suites differ: -{sorted(set(before)-set(after))} +{sorted(set(after)-set(before))}"); bad = 1
    for k in sorted(set(before) & set(after)):
        b, a = before[k], after[k]
        want = (b[0] + added.get(k, 0),) + b[1:]
        if a != want:
            print(f"FAIL  {label}: {k}: before {b}, after {a}, expected {want}"); bad = 1
    for k in added:
        if k not in after:
            print(f"FAIL  {label}: the suite that gained tests, {k}, is missing"); bad = 1
    tb = sum(v[0] for v in before.values()); ta = sum(v[0] for v in after.values())
    print(f"{'ok   ' if not bad else 'FAIL '} {label}: {len(before)} suites; {tb} -> {ta} (+{sum(added.values())} added by this wave)")
rb, ra = os.path.join(here, "rust-suites-before.txt"), os.path.join(here, "rust-suites-after.txt")
if not os.path.exists(ra):
    print("FAIL  Rust: rust-suites-after.txt is missing; the after-run was not captured"); bad = 1
else:
    before = load_rust(rb)
    # the baseline was captured after the snapshot test was written, so the
    # +1 on namespace.rs is already inside it; only portable_boundary grows.
    compare("Rust", before, load_rust(ra), {"<root>_core tests/portable_boundary.rs": 2})
ab, aa = os.path.join(here, "android-suites-before.txt"), os.path.join(here, "android-suites-after.txt")
if not os.path.exists(aa):
    print("FAIL  Android: android-suites-after.txt is missing; the after-run was not captured"); bad = 1
else:
    compare("Android", load_android(ab), load_android(aa), {})
sys.exit(bad)
PY

# --- G. the Windows workflow ---------------------------------------------------
echo "== G. portable Windows workflow"
wf="$(cat .github/workflows/portable-windows-msvc.yml)"
check "the -like filter carries the pliwee- prefix" contains "$wf" "-like 'pliwee-*'"
check "the -like filter is followed by the exact-7 selection assertion" contains "$wf" '-ne 7'
check "no workflow or packaging -p argument names an omnibridge crate" \
    test -z "$(git grep -nE -- "-p omnibridge|'omnibridge-(proto|core|control|runtime|linux|daemon|cli|capability)|'omnibridge-gui'" -- .github packaging || true)"

echo
if [ "$fail" -eq 0 ]; then echo "G3 static gate: PASS"; exit 0; else echo "G3 static gate: FAIL"; exit 1; fi
