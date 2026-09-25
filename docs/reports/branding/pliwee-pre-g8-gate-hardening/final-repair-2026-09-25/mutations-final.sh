#!/usr/bin/env bash
# mutations-final.sh — the 2026-09-25 final hardening repair (a declined first
# confirmation must not create, archive or replace a gate's record). Each
# mutation re-opens one hole on a scratch copy of packaging/tests and runs
# pre-g8-manual-gates-selftests.sh, which must catch it. FM1 is the audited
# defect itself: the old code's behaviour restored.
# Run from the repository root. Nothing in the tree is modified.
set -uo pipefail
ROOT="$(pwd)"; n_caught=0; n_total=0
SUITE=pre-g8-manual-gates-selftests.sh; F=pre-g8-manual-gates.sh
mut() { # NAME then pairs of OLD NEW, all applied to $F
    local name="$1" M T out; shift
    M="$(mktemp -d)"; mkdir -p "$M/r/packaging"; cp -a "$ROOT/packaging/tests" "$M/r/packaging/tests"; T="$M/r/packaging/tests"
    python3 - "$T/$F" "$@" <<'PY' || { echo "MUTATION NOT APPLIED: $name"; rm -rf "$M"; return; }
import sys; p = sys.argv[1]; a = sys.argv[2:]; s = open(p).read()
for old, new in zip(a[0::2], a[1::2]):
    assert s.count(old) == 1, "anchor not found once: " + old[:60]
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
    out="$(TMPDIR="$M" bash "$T/$SUITE" 2>&1)"
    n_total=$((n_total + 1))
    if grep -q '^not ok' <<<"$out"; then
        n_caught=$((n_caught + 1)); printf 'CAUGHT     %s — %s\n' "$name" "$(tail -1 <<<"$out")"
        grep '^not ok' <<<"$out" | head -3 | cut -c1-130 | sed 's/^/             /; s/[[:blank:]]*$//'
    else
        printf 'SURVIVED   %s — %s\n' "$name" "$(tail -1 <<<"$out")"
    fi
    rm -rf "$M"
}
RUNNING_REC='    state_write "$g" "gate=$g" state=RUNNING "started_utc=$STARTED" "log=$LOG"
    tee_run'
mut "FM1 the audited defect: W6-COMPONENT-UPGRADE writes RUNNING before its first confirmation" \
    'RC=0; : > "$LOG"
    # Preparation:' 'RC=0; : > "$LOG"
    state_write "$g" "gate=$g" state=RUNNING "started_utc=$STARTED" "log=$LOG"
    # Preparation:' \
    "$RUNNING_REC" '    tee_run'
mut "FM2 a preparation problem records a FAIL instead of refusing" \
    '|| die "N+1 versionCode '"'"'$vn1'"'"' is not greater than N'"'"'s '"'"'$vn'"'"': it would not be an upgrade; nothing was recorded"' \
    '|| { record "$g" FAIL "N+1 versionCode is not greater"; return; }'
mut "FM3 a later declined confirmation claims the gate kept its previous state" \
    'if [ -n "$ATTEMPT" ] && [ "$(st "$GATE_RUN" attempt)" = "$ATTEMPT" ]; then' 'if false; then'
mut "FM4 any gate opens its attempt record before its gate function asks" \
    '    new_attempt; GATE_RUN="$g"' '    new_attempt; GATE_RUN="$g"; state_write "$g" "gate=$g" state=RUNNING'
printf '\n%d of %d mutations caught\n' "$n_caught" "$n_total"
[ "$n_caught" -eq "$n_total" ]
