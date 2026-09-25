#!/usr/bin/env bash
# harness-selftests.sh — does the harness fail when it should?
#
# Every certification gate in this repository rests on an assumption nobody had
# tested: that when the thing being measured is absent, the harness says so.
# Twenty-nine times across four waves, it did not. This file tests that
# assumption directly.
#
# Each case does two things, and BOTH matter:
#
#   REJECTS  the primitive returns non-zero on its failure mode
#   ACCEPTS  the primitive returns zero on the good case
#
# Without the second half a primitive hard-coded to `return 1` would pass every
# rejection test here — which is the same vacuity in a new place. Without the
# first half the whole file is decoration.
#
# The failure modes are the ones actually observed, named in
# packaging/tests/lib/assert.sh against the wave that suffered them.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"

PASS=0; FAIL=0; declare -a FAILED=()
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); FAILED+=("$*"); printf 'not ok  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

# rejects DESC CMD... — the primitive must return non-zero, and must say why.
rejects() {
    local desc="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
        notok "REJECTS $desc — returned 0; the harness would have passed on nothing"
    elif [ -z "${out//[[:space:]]/}" ]; then
        notok "REJECTS $desc — returned $rc but printed no diagnostic; a silent failure is hard to act on"
    elif grep -qiE 'syntax error|command not found|no such file' <<<"$out"; then
        # The rejection must come from the PRIMITIVE, not from a shell that
        # could not load it. Measured: on an Ubuntu runner `/bin/sh` is dash,
        # which cannot parse assert.sh's arrays and here-strings, so a case
        # spawned with `sh -c` returned non-zero for a reason that had nothing
        # to do with the thing under test -- and this file recorded it as a
        # pass. A false green inside the suite whose subject is false greens.
        notok "REJECTS $desc — returned $rc because the SHELL failed, not the primitive: $(tr '\n' ' ' <<<"$out" | head -c 110)"
    else
        ok "REJECTS $desc — $(printf '%s' "$out" | sed 's/^assert: FAILED: //' | tr '\n' ' ' | head -c 105)"
    fi
}
# The two kinds are checked differently, on purpose.
#
#   need_*            ASSERTIONS. They must return non-zero AND print why, because
#                     whoever reads the run needs to know what was missing.
#   contains/absent   PREDICATES. They must return the right answer and print
#                     NOTHING, because the caller composes them into its own
#                     message: `contains "$cap" "$s" || notok "the window missed it"`.
#                     Requiring a diagnostic from these would push duplicate text
#                     into every call site.
#
# is_false/is_true check a predicate's answer alone.
is_false() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        notok "PREDICATE $desc — answered true, and the truth is false"
    else
        ok "PREDICATE $desc — answers false, as it must"
    fi
}
is_true() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ok "PREDICATE $desc — answers true, as it must"
    else
        notok "PREDICATE $desc — answered false, and the truth is true"
    fi
}

# accepts DESC CMD... — the primitive must return zero on the good case.
accepts() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ok "ACCEPTS $desc"
    else
        notok "ACCEPTS $desc — returned non-zero on a case that is fine; a primitive that rejects everything proves nothing"
    fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pliwee-selftest.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
section "A missing executable  (Packaging v1: an absent runuser)"
# ---------------------------------------------------------------------------
rejects "a tool that is not installed" \
    need_tool omnibridge-definitely-not-a-real-tool-4f9a
rejects "one absent tool among several present ones" \
    need_tool sh grep omnibridge-definitely-not-a-real-tool-4f9a
accepts "tools that are installed" need_tool sh grep find

# ---------------------------------------------------------------------------
section "An empty capture  (Packaging v1: an empty tracing capture; L16: one line)"
# ---------------------------------------------------------------------------
rejects "an empty capture"            need_nonempty "the journal" ""
rejects "a whitespace-only capture"   need_nonempty "the journal" $'  \n\t\n  '
rejects "a capture below the minimum" need_nonempty "the journal" $'one line' 20
accepts "a capture with real content" need_nonempty "the journal" $'line one\nline two'
accepts "a capture meeting an explicit minimum" \
    need_nonempty "the journal" "$(seq 1 30)" 20

# ---------------------------------------------------------------------------
section "A search that loses a match  (Evidence closure: 225 misses in 300 runs)"
# ---------------------------------------------------------------------------
# The capture is deliberately large and the match deliberately early: that is
# the exact shape that made `printf | grep -q` fail three times in four.
BIG="$(seq 1 4000 | sed 's/^/filler line /')"
BIG="MATCHME-EARLY-SENTINEL
$BIG"
is_true  "contains(), on a sentinel near the start of a 4000-line capture" \
    contains "$BIG" "MATCHME-EARLY-SENTINEL"
is_false "contains(), on a string the capture does not hold" \
    contains "$BIG" "THIS-STRING-IS-NOT-THERE-91af"
is_true  "absent(), on a string that really is absent" \
    absent "$BIG" "THIS-STRING-IS-NOT-THERE-91af"
is_false "absent(), on a string that is present — the privacy-gate direction" \
    absent "$BIG" "MATCHME-EARLY-SENTINEL"

# The regression itself: run the match many times and require it never to be
# lost. Under the old `printf | grep -q` form this failed ~75% of iterations.
miss=0
for _ in $(seq 1 200); do contains "$BIG" "MATCHME-EARLY-SENTINEL" || miss=$(( miss + 1 )); done
[ "$miss" -eq 0 ] \
    && ok "REGRESSION: 200/200 searches of a large capture found a present sentinel (the pipe form missed 75%)" \
    || notok "REGRESSION: $miss of 200 searches LOST a present sentinel; the pipefail/SIGPIPE defect is back"

# ---------------------------------------------------------------------------
section "A window that does not cover the operation  (defects 2, 9, 19)"
# ---------------------------------------------------------------------------
rejects "a window with no anchor for this operation" \
    need_window_covers "the journal" $'unrelated line\nanother unrelated line' "transfer=abc12345"
rejects "an empty window, before any anchor is even looked for" \
    need_window_covers "the journal" "" "transfer=abc12345"
accepts "a window carrying this operation's own anchor" \
    need_window_covers "the journal" $'noise\noffering a file transfer=abc12345 size=48\nnoise' "transfer=abc12345"

# ---------------------------------------------------------------------------
section "A wrong artifact count  (Packaging v1: six built, one shipped)"
# ---------------------------------------------------------------------------
rejects "a count that is wrong"                need_exact_count "installed packages" "1" "2"
rejects "a count that is zero"                 need_exact_count "installed packages" "0" "2"
rejects "a count that could not be read"       need_exact_count "installed packages" "" "2"
accepts "a count that is exactly right"        need_exact_count "installed packages" "2" "2"
accepts "a count with the whitespace guests add" need_exact_count "installed packages" $' 2 \n' "2"

# ---------------------------------------------------------------------------
section "A glob that matched nothing  (Packaging v1: L17 skipped its group)"
# ---------------------------------------------------------------------------
mkdir -p "$WORK/pkgs"
: > "$WORK/pkgs/pliwee_1.0_amd64.deb"
: > "$WORK/pkgs/pliwee-gui_1.0_amd64.deb"
rejects "a glob that matches nothing"        need_glob "$WORK/pkgs" '*.rpm' 2
rejects "a glob that matches the wrong number" need_glob "$WORK/pkgs" '*.deb' 3
rejects "a directory that does not exist"    need_glob "$WORK/nope" '*.deb' 2
accepts "a glob that matches exactly the expected count" need_glob "$WORK/pkgs" '*.deb' 2

# ---------------------------------------------------------------------------
section "A relative mount path  (Packaging v1: read as a named volume)"
# ---------------------------------------------------------------------------
rejects "a relative path used as a mount source"  need_abs_path "--pkgdir" "artifacts/fedora44"
rejects "a bare name used as a mount source"      need_abs_path "--pkgdir" "artifacts"
accepts "an absolute mount source"                need_abs_path "--pkgdir" "/tmp/artifacts"

# ---------------------------------------------------------------------------
section "A directory nothing can write to  (Packaging v1: the subuid case)"
# ---------------------------------------------------------------------------
mkdir -p "$WORK/ro" && chmod 500 "$WORK/ro"
if [ "$(id -u)" -eq 0 ]; then
    printf 'n/a   running as root, which can write to a 0500 directory; the unwritable case cannot be staged\n'
else
    rejects "a directory the harness cannot write to" need_writable "$WORK/ro"
fi
accepts "a writable directory" need_writable "$WORK"

# ---------------------------------------------------------------------------
section "An operation that never ran  (defects 10, 11: the session was torn down)"
# ---------------------------------------------------------------------------
rejects "a counter that did not move across the operation" need_ran "mirrored" "3" "3"
rejects "a before/after observation that is missing"       need_ran "mirrored" "3" ""
accepts "a counter that moved"                             need_ran "mirrored" "3" "4"

# ---------------------------------------------------------------------------
section "A delta that is not the one claimed  (defect 14: 'mirrored now' is not a total)"
# ---------------------------------------------------------------------------
rejects "no change where exactly one was expected"   need_delta "mirrored" "3" "3" 1
rejects "two arrivals counted as the one under test" need_delta "mirrored" "3" "5" 1
rejects "a non-numeric observation"                  need_delta "mirrored" "three" "4" 1
accepts "exactly the expected delta"                 need_delta "mirrored" "3" "4" 1
accepts "a delta of one from a cleared baseline"     need_delta "mirrored" "0" "1" 1

# ---------------------------------------------------------------------------
section "A prompt with no stdin  (Packaging v1 bash -s; defect 4: silent decline)"
# ---------------------------------------------------------------------------
# The mechanical half. `pliwee pair` read EOF from its [y/N] prompt and
# answered "no" while exiting 0, and two operator scans were lost before one
# journal line explained it. What a harness can check before starting such a
# command is that its stdin is not already closed.
# `bash -c`, not `sh -c`: lib/assert.sh declares `#!/usr/bin/env bash` and uses
# arrays and here-strings. On an Ubuntu runner /bin/sh is dash, which cannot
# parse it -- see the note in rejects() for what that cost.
accepts "a command given a real answer on stdin" \
    bash -c '. '"$HERE"'/lib/assert.sh; need_stdin_answer "pliwee pair" <<<"y"'
rejects "a command whose stdin is closed" \
    bash -c '. '"$HERE"'/lib/assert.sh; exec 0<&-; need_stdin_answer "pliwee pair"'

# ---------------------------------------------------------------------------
section "U10 before U6  (pre-G8 gate hardening: U6 recorded n/a, then U10 ran)"
# ---------------------------------------------------------------------------
# upgrade-gates.sh used to record U6 as n/a and downgrade (U10) in the same
# stage, so U6 could never be measured against the upgraded guest in the
# order §3 defines. The stages are now separate, and U10 stands behind
# g7up_verify_u6. It must refuse every U6 that is not a real PASS on the same
# guest and run — and accept the one that is, or it proves nothing.
# shellcheck source=lib/g7up-evidence.sh
. "$HERE/lib/g7up-evidence.sh"
# shellcheck source=lib/g7up-fixture.sh
. "$HERE/lib/g7up-fixture.sh"
G7="$WORK/g7"; mkdir -p "$G7"
g7up_fixture "$G7/base" fedora44 g7-f44
u6case() { # NAME SHELL-EDIT — a copy of the good record with one thing broken ($E is the copy)
    rm -rf "$G7/$1"; cp -a "$G7/base" "$G7/$1"
    E="$G7/$1" bash -c ". '$HERE/lib/g7up-fixture.sh'; $2"
}
accepts "a real U6 PASS on the same distro, domain, run and guest" \
    g7up_verify_u6 "$G7/base" fedora44 g7-f44
u6case no-u6 'rm -rf "$E/U6" "$E/U6-RESULT"'
rejects "U10 with no U6 at all (the old order: upgrade, then straight to the downgrade)" \
    g7up_verify_u6 "$G7/no-u6" fedora44 g7-f44
u6case empty-result ': > "$E/U6-RESULT"'
rejects "an empty U6-RESULT file" g7up_verify_u6 "$G7/empty-result" fedora44 g7-f44
u6case bare-pass 'printf "verdict=PASS\n" > "$E/U6-RESULT"'
rejects "a hand-written 'verdict=PASS' and nothing else" g7up_verify_u6 "$G7/bare-pass" fedora44 g7-f44
u6case no-checkpoint 'rm -f "$E/UPGRADE-CHECKPOINT"'
rejects "a U6 record with no upgrade checkpoint behind it" g7up_verify_u6 "$G7/no-checkpoint" fedora44 g7-f44
u6case altered-log 'echo "ok    L15: something added later" >> "$E/U6/lifecycle-peer-gates.log"'
rejects "a U6 log altered after it was recorded" g7up_verify_u6 "$G7/altered-log" fedora44 g7-f44
u6case empty-log ': > "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "an empty U6 log, even with a matching digest" g7up_verify_u6 "$G7/empty-log" fedora44 g7-f44
u6case peer-failed 'sed -i "s/: 34 passed, 0 failed/: 33 passed, 1 failed/" "$E/U6/lifecycle-peer-gates.log"; echo "not ok  L15: no incoming-file prompt" >> "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "a U6 run in which lifecycle-peer-gates.sh failed a check" g7up_verify_u6 "$G7/peer-failed" fedora44 g7-f44
u6case aborted 'echo "PRECONDITION FAILED: pliweed is not running in the guest" >> "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "a U6 run that stopped on a precondition" g7up_verify_u6 "$G7/aborted" fedora44 g7-f44
u6case repaired 'sed -i "/already paired with this guest/d" "$E/U6/lifecycle-peer-gates.log"; echo "ok    the phone paired with g7-host after 20s" >> "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "a U6 that re-paired the phone (U6 is 'reconnects WITHOUT re-pairing')" g7up_verify_u6 "$G7/repaired" fedora44 g7-f44
u6case one-way 'sed -i "s/^ok    L14: phone -> guest arrived.*/n\/a   L14: phone -> guest NOT EXERCISED. The Android clipboard is empty/" "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "a clipboard that went one way only (n/a is not a round-trip)" g7up_verify_u6 "$G7/one-way" fedora44 g7-f44
u6case no-xfer-journal ': > "$E/U6/43b-L15-journal.txt"'
rejects "a file transfer with no journal line naming its id" g7up_verify_u6 "$G7/no-xfer-journal" fedora44 g7-f44
u6case wrong-domain 'sed -i "s/^domain=.*/domain=g7-u2404/" "$E/U6-RESULT"'
rejects "a U6 recorded for another domain" g7up_verify_u6 "$G7/wrong-domain" fedora44 g7-f44
u6case wrong-distro-id 'sed -i "s/^distro .*/distro        ubuntu2404/" "$E/U6/29-peer-identity.txt"; g7up_fixture_rehash "$E"'
rejects "a U6 whose peer gates measured another distribution" g7up_verify_u6 "$G7/wrong-distro-id" fedora44 g7-f44
u6case wrong-domain-tally 'sed -i "s|^fedora44 / g7-f44: |fedora44 / g7-f44-clone: |" "$E/U6/lifecycle-peer-gates.log"; g7up_fixture_rehash "$E"'
rejects "a U6 log whose tally names another guest" g7up_verify_u6 "$G7/wrong-domain-tally" fedora44 g7-f44
rejects "the right U6 asked about as another distro" g7up_verify_u6 "$G7/base" ubuntu2404 g7-f44
rejects "the right U6 asked about as another domain" g7up_verify_u6 "$G7/base" fedora44 g7-u2404
u6case old-run 'sed -i "s/^run_id=.*/run_id=g7up-fedora44-20260101T000000Z-00000001/" "$E/U6-RESULT"'
rejects "a U6 from an earlier upgrade run" g7up_verify_u6 "$G7/old-run" fedora44 g7-f44
u6case other-guest 'sed -i "s/^guest_machine_id=.*/guest_machine_id=ffffffffffffffffffffffffffffffff/" "$E/U6-RESULT"'
rejects "a U6 measured on another machine" g7up_verify_u6 "$G7/other-guest" fedora44 g7-f44
u6case other-fpr 'sed -i "s/^fingerprint .*/fingerprint   9999 9999 9999 9999/" "$E/U6/29-peer-identity.txt"; g7up_fixture_rehash "$E"'
rejects "a U6 whose peer saw a different local fingerprint than the upgraded guest's" g7up_verify_u6 "$G7/other-fpr" fedora44 g7-f44
u6case before-upgrade 'sed -i "s/^started_epoch=.*/started_epoch=1/" "$E/U6-RESULT"'
rejects "a U6 that started before the upgrade stage completed" g7up_verify_u6 "$G7/before-upgrade" fedora44 g7-f44
u6case upgrade-failed 'sed -i "s/^upgrade_not_ok=.*/upgrade_not_ok=2/" "$E/UPGRADE-CHECKPOINT"'
rejects "a U6 on a run whose upgrade stage failed checks" g7up_verify_u6 "$G7/upgrade-failed" fedora44 g7-f44
u6case nonzero-exit 'sed -i "s/^exit=.*/exit=1/" "$E/U6-RESULT"'
rejects "a U6 whose lifecycle-peer-gates.sh exited non-zero" g7up_verify_u6 "$G7/nonzero-exit" fedora44 g7-f44

# The stages themselves. A fake `virsh` records every call: a refusal that
# happens before the guest is contacted leaves it empty, and the acceptance
# case must reach the guest (and then stop, since there is none).
mkdir -p "$WORK/bin"
printf '#!/bin/sh\necho "$*" >> "%s/virsh.calls"\nexit 1\n' "$WORK" > "$WORK/bin/virsh"; chmod +x "$WORK/bin/virsh"
command -v jq >/dev/null 2>&1 || { printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/jq"; chmod +x "$WORK/bin/jq"; }
mkdir -p "$WORK/old"; printf '%s  omnibridge_1.0.0-1_amd64.deb\n' "$(printf 'a%.0s' $(seq 1 64))" > "$WORK/old/SHA256SUMS"
g7up_fixture "$G7/stage-ok" fedora44 g7-f44 "$WORK/old/SHA256SUMS"
# Stage cases start from stage-ok, whose 1.0.0 set matches --old-pkgdir, so
# each is refused for the ONE thing it breaks and not for the set's digest.
stcase() { # NAME SHELL-EDIT
    rm -rf "$G7/$1"; cp -a "$G7/stage-ok" "$G7/$1"
    E="$G7/$1" bash -c ". '$HERE/lib/g7up-fixture.sh'; $2"
}
stcase st-no-u6 'rm -rf "$E/U6" "$E/U6-RESULT"'
stcase st-empty ': > "$E/U6-RESULT"'
stcase st-bare 'printf "verdict=PASS\n" > "$E/U6-RESULT"'
stcase st-wrong-domain 'sed -i "s/^domain=.*/domain=g7-u2404/" "$E/U6-RESULT"'
stcase st-wrong-distro 'sed -i "s/^distro .*/distro        ubuntu2404/" "$E/U6/29-peer-identity.txt"; g7up_fixture_rehash "$E"'
stcase st-upgrade-failed 'sed -i "s/^upgrade_not_ok=.*/upgrade_not_ok=2/" "$E/UPGRADE-CHECKPOINT"'
stage() { # EXPECT(refuse|reach) DESC MESSAGE-FRAGMENT ARGS...
    local expect="$1" desc="$2" frag="$3" out rc calls; shift 3
    rm -f "$WORK/virsh.calls"
    out="$(PATH="$WORK/bin:$PATH" GA_EXEC_TIMEOUT=5 bash "$HERE/upgrade-gates.sh" "$@" 2>&1)"; rc=$?
    calls="$(cat "$WORK/virsh.calls" 2>/dev/null || true)"
    if [ "$expect" = refuse ]; then
        if [ "$rc" -ne 0 ] && [ -z "$calls" ] && contains "$out" "$frag"; then
            ok "STAGE refuses $desc — exit $rc before contacting the guest: $(grep -m1 -F "$frag" <<<"$out" | cut -c1-90)"
        else
            notok "STAGE refuses $desc — exit $rc, virsh calls: ${calls:-none}, output: $(tr '\n' ' ' <<<"$out" | cut -c1-160)"
        fi
    else
        if [ -n "$calls" ] && ! contains "$out" "U10 refused" && ! contains "$out" "U6 refused"; then
            ok "STAGE accepts $desc — it passed the evidence gate and went on to contact the guest"
        else
            notok "STAGE accepts $desc — it never reached the guest (exit $rc): $(tr '\n' ' ' <<<"$out" | cut -c1-160)"
        fi
    fi
}
stage refuse "--stage downgrade with no evidence at all" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/none" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade after the upgrade but before U6" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/st-no-u6" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade over an empty U6-RESULT" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/st-empty" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade over a forged 'verdict=PASS'" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/st-bare" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade over a U6 recorded for another domain" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/st-wrong-domain" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade over a U6 that measured another distribution" "no verified U6 PASS" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/st-wrong-distro" --old-pkgdir "$WORK/old"
stage refuse "--stage downgrade on another domain than the one U6 measured" "no verified U6 PASS" \
    --stage downgrade --domain g7-other --distro fedora44 --evidence "$G7/stage-ok" --old-pkgdir "$WORK/old"
mkdir -p "$WORK/old2"; printf 'different\n' > "$WORK/old2/SHA256SUMS"
stage refuse "--stage downgrade with a different 1.0.0 set than the upgrade recorded" "not the 1.0.0 set" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/stage-ok" --old-pkgdir "$WORK/old2"
stage reach "--stage downgrade over a real U6 PASS" "" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/stage-ok" --old-pkgdir "$WORK/old"
cp -a "$G7/stage-ok" "$G7/stage-interrupted"; echo "run_id=x" > "$G7/stage-interrupted/U10-STARTED"
stage refuse "a second --stage downgrade after one was interrupted" "already started" \
    --stage downgrade --domain g7-f44 --distro fedora44 --evidence "$G7/stage-interrupted" --old-pkgdir "$WORK/old"
stage refuse "--stage peer-u6 before the upgrade stage completed" "no completed upgrade stage" \
    --stage peer-u6 --domain g7-f44 --distro fedora44 --evidence "$G7/none" --phone-ip 192.0.2.20
stage refuse "--stage peer-u6 once U10 has started" "U10 has already started" \
    --stage peer-u6 --domain g7-f44 --distro fedora44 --evidence "$G7/stage-interrupted" --phone-ip 192.0.2.20
stage refuse "--stage peer-u6 after an upgrade stage that failed checks" "failed check(s)" \
    --stage peer-u6 --domain g7-f44 --distro fedora44 --evidence "$G7/st-upgrade-failed" --phone-ip 192.0.2.20
stage reach "--stage peer-u6 after a completed upgrade stage" "" \
    --stage peer-u6 --domain g7-f44 --distro fedora44 --evidence "$G7/st-no-u6" --phone-ip 192.0.2.20
stage refuse "a second --stage upgrade into an evidence directory that already has one" "already holds a completed upgrade" \
    --stage upgrade --domain g7-f44 --distro fedora44 --evidence "$G7/stage-ok" --old-pkgdir "$WORK/old" --new-pkgdir "$WORK/old"
up_block="$(awk '/^if \[ "\$STAGE" = upgrade \]; then/ {f=1; next} f && /^if \[ "\$STAGE" = / {exit} f' "$HERE/upgrade-gates.sh")"
if [ "$(grep -c . <<<"$up_block")" -ge 100 ] && contains "$up_block" 'section "U9' \
        && ! contains "$up_block" 'section "U10' && contains "$up_block" 'G7UP_CHECKPOINT'; then
    ok "STATIC the upgrade stage ($(grep -c . <<<"$up_block") lines, O1 through U9) contains no U10: it stops on Pliwee and writes the checkpoint"
else
    notok "STATIC the upgrade stage still contains a U10 section, lacks the checkpoint, or could not be read"
fi

# ---------------------------------------------------------------------------
section "The pre-G8 coordinator  (pre-g8-manual-gates-selftests.sh)"
# ---------------------------------------------------------------------------
# Non-vacuous: a suite that ran nothing would also "pass".
if bash "$HERE/pre-g8-manual-gates-selftests.sh" > "$WORK/coord.txt" 2>&1 \
        && [ "$(grep -c '^ok ' "$WORK/coord.txt")" -ge 50 ]; then
    ok "the coordinator's self-tests pass ($(grep -c '^ok ' "$WORK/coord.txt") checks)"
else
    notok "the coordinator's self-tests FAILED:"; grep '^not ok' "$WORK/coord.txt" | sed 's/^/        /'
fi

printf '\n-----------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then printf '\nFailed:\n'; for g in "${FAILED[@]}"; do printf '  %s\n' "$g"; done; fi
[ "$FAIL" -eq 0 ]
