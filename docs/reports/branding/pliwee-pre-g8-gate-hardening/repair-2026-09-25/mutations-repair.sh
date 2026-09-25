#!/usr/bin/env bash
# mutations-repair.sh — the 2026-09-25 hardening repair (audit findings A and
# B). Each mutation re-opens one hole the repair closed, on a scratch copy of
# packaging/tests, and runs pre-g8-manual-gates-selftests.sh, which must catch
# it. M1 is the audited defect itself: the old code's behaviour restored.
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
        n_caught=$((n_caught + 1)); printf 'CAUGHT     %-66s %s\n' "$name" "$(tail -1 <<<"$out")"
        grep '^not ok' <<<"$out" | head -3 | cut -c1-130 | sed 's/^/             /'
    else
        printf 'SURVIVED   %-66s %s\n' "$name" "$(tail -1 <<<"$out")"
    fi
    rm -rf "$M"
}
mut "M1 the audited bypass: no prerequisite check before execution" \
    '    prereq_ok "$g"
    s="$(status "$g")"' '    s="$(status "$g")"' \
    '    # Immediately before the owning script starts, the prerequisites once more.
    prereq_ok "$g"
' ''
mut "M2 status() reports a gate's own record before its prerequisites" \
    '    if ! why="$(prereq "$g")"; then' '    if [ -z "$s" ] && ! why="$(prereq "$g")"; then'
mut "M3 SECLOG ignores that U10 started" \
    '                || { printf '"'"'BLOCKED\tU10 has run;' '                || true || { printf '"'"'BLOCKED\tU10 has run;'
mut "M4 upgrade-gates.sh's U10-STARTED marker ignored" \
    '    [ -e "$(chain_dir "$1")/$G7UP_U10_STARTED" ] || ever_started' '    ever_started'
mut "M5 U6 may be retried after U10" \
    '                || { printf '"'"'BLOCKED\tU10 has started on the %s chain' '                || true || { printf '"'"'BLOCKED\tU10 has started on the %s chain'
mut "M6 U10 may run a second time" \
    '                || { printf '"'"'BLOCKED\tU10 already started' '                || true || { printf '"'"'BLOCKED\tU10 already started'
mut "M7 --not-executed replaces a measured FAIL" \
    '            FAIL) die "$GATE_ARG has a measured FAIL' '            FAIL) : "$GATE_ARG has a measured FAIL'
mut "M8 --not-executed replaces a run that started" \
    '            *) die "$GATE_ARG was started' '            *) : "$GATE_ARG was started'
mut "M9 a new attempt overwrites the previous record" \
    '    mv -f "$(sf "$1")" "$h" ||' '    rm -f "$h" ||'
mut "M10 --next resumes an interruption whose prerequisites fail" \
    '            prereq "$g" >/dev/null && break' '            break'
printf '\n%d of %d mutations caught\n' "$n_caught" "$n_total"
[ "$n_caught" -eq "$n_total" ]
