#!/usr/bin/env bash
# mutations.sh — each mutation breaks one refusal added by the pre-G8 gate
# hardening, on a scratch copy of packaging/tests, and runs the self-test suite
# that must catch it. A mutation that leaves its suite green is a vacuous test.
# Run from the repository root. Nothing in the tree is modified.
set -uo pipefail
ROOT="$(pwd)"; n_caught=0; n_total=0
mut() { # NAME SUITE PYTHON-EDIT(file, old, new)
    local name="$1" suite="$2" file="$3" old="$4" new="$5" M T out
    M="$(mktemp -d)"; mkdir -p "$M/r/packaging"; cp -a "$ROOT/packaging/tests" "$M/r/packaging/tests"; T="$M/r/packaging/tests"
    python3 - "$T/$file" "$old" "$new" <<'PY' || { echo "MUTATION NOT APPLIED: $name"; rm -rf "$M"; return; }
import sys; p, a, b = sys.argv[1:]; s = open(p).read()
assert a in s, "anchor not found"; open(p, "w").write(s.replace(a, b, 1))
PY
    out="$(TMPDIR="$M" bash "$T/$suite" 2>&1)"
    n_total=$((n_total + 1))
    if grep -q '^not ok' <<<"$out"; then
        n_caught=$((n_caught + 1)); printf 'CAUGHT     %-58s %s\n' "$name" "$(tail -1 <<<"$out")"
        grep '^not ok' <<<"$out" | head -2 | cut -c1-130 | sed 's/^/             /'
    else
        printf 'SURVIVED   %-58s %s\n' "$name" "$(tail -1 <<<"$out")"
    fi
    rm -rf "$M"
}
mut "downgrade stage skips the U6 evidence check" harness-selftests.sh upgrade-gates.sh \
    '        g7up_verify_u6 "$EVIDENCE" "$DISTRO" "$DOMAIN" \' '        true \'
mut "g7up_verify_u6 accepts everything" harness-selftests.sh lib/g7up-evidence.sh \
    'g7up_verify_u6() {' 'g7up_verify_u6() { return 0'
mut "U6 log anchors not required" harness-selftests.sh lib/g7up-evidence.sh \
    '    for a in "${G7UP_U6_ANCHORS[@]}"; do' '    for a in; do'
mut "U6 identity record not bound to distro" harness-selftests.sh lib/g7up-evidence.sh \
    '[ "$v" = "$distro" ] || { _af "lifecycle-peer-gates.sh measured distro' ': || { _af "lifecycle-peer-gates.sh measured distro'
mut "peer-u6 runs without a checkpoint" harness-selftests.sh upgrade-gates.sh \
    '        g7up_verify_checkpoint "$EVIDENCE" "$DISTRO" "$DOMAIN" \' '        true \'
mut "U10 put back into the upgrade stage" harness-selftests.sh upgrade-gates.sh \
    'section "U9 — the account that never enabled it"' 'section "U10 — downgrade"
section "U9 — the account that never enabled it"'
mut "coordinator trusts the U6 harness's exit code" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    'if [ "$RC" = 0 ] && ! g7up_verify_u6' 'if false && ! g7up_verify_u6'
mut "coordinator never re-verifies a recorded PASS" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    'reverify() {' 'reverify() { return 0'
mut "U10 does not wait for the security-log gate" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    "                *) printf 'BLOCKED\twaiting for G7UP-%s-SECLOG" "                *) : ;; *) printf 'BLOCKED\twaiting for G7UP-%s-SECLOG"
mut "U10 has no prerequisites in the coordinator" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    '        G7UP-*-U10)
            need_pass' '        G7UP-*-U10X)
            need_pass'
mut "self-test records count in a real run" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    '[ "$(st "$g" selftest)" != "$SELFTEST" ]' 'false'
mut "signing output teed into the evidence directory" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    '        "$prov" --media-a "$MEDIA_A" --media-b "$MEDIA_B"
' '        "$prov" --media-a "$MEDIA_A" --media-b "$MEDIA_B" | tee "$EVIDENCE/w6/prov.log"
'
mut "--next ignores an interrupted gate" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    'in RUNNING|INCOMPLETE) nxt=' 'in NEVER) nxt='
mut "confirmation accepts anything" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    '    [ "$a" = "$token" ] && return 0' '    return 0'
mut "missing domain is guessed instead of refused" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    'need_cfg() { [ -n "$1" ] ||' 'need_cfg() { true ||'
mut "not-executed accepted without a reason" pre-g8-manual-gates-selftests.sh pre-g8-manual-gates.sh \
    '[ -n "${REASON//[[:space:]]/}" ] ||' 'true ||'
printf '\n%d of %d mutations caught\n' "$n_caught" "$n_total"
[ "$n_caught" -eq "$n_total" ]
