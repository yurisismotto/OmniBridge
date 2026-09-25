#!/usr/bin/env bash
# mutations-realworld.sh — the 2026-09-25 real-world gate repair. Each
# mutation re-opens one hole on a scratch copy of packaging/tests and runs
# pre-g8-manual-gates-selftests.sh, which must catch it. RW1, RW2 and RW7 are
# the three defects themselves: the old code restored.
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
mut "RW1 the real defect: apk_fact's substring parser (.*name= matches compileSdkVersionCodename)" \
    '    badging_field "$line" "$2"
}' '    sed -n "s/^package: .*$2='"'"'\([^'"'"']*\)'"'"'.*/\1/p" <<<"$line" | head -1
}' \
    '[ "$(grep -c . <<<"$line")" = 1 ] || return 1' ':'
mut "RW2 the real defect: N+1 through -Pandroid.injected.version.code, in the checkout" \
    '        n1_scratch_build "$vn" "$dir/apk-N1.apk"' \
    '        tee_run bash -c '"'"'cd "$1" && ./gradlew --max-workers=2 "-Pandroid.injected.version.code=$2" :app:assembleDebug'"'"' _ "$ANDROID_DIR" "$((vn + 1))"
        cp "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" "$dir/apk-N1.apk"'
mut "RW3 the scratch tree is not removed" \
    'n1_cleanup() { [ -z "$N1_SCRATCH" ] || rm -rf -- "$N1_SCRATCH"; N1_SCRATCH=""; }' 'n1_cleanup() { N1_SCRATCH=""; }'
mut "RW4 the edit accepts more than one versionCode assignment" \
    '    [ "$(grep -c . <<<"$lines")" = 1 ] \' '    true \'
mut "RW5 the built N+1 is only checked to be higher, not to be the edited source" \
    '    [ "$got" = "$want" ] || die' '    true || die'
mut "RW6 uncommitted Android sources are not refused" \
    '    [ -z "$dirty" ] || die' '    true || die'
mut "RW7 the known defect: every U2 attempt writes \$ev/U2-operator.txt" \
    'f="$ev/U2-operator.$ATTEMPT.txt"' 'f="$ev/U2-operator.txt"' \
    '[ ! -e "$f" ] && [ ! -e "$f.partial" ] || die' 'true || die' \
    'chmod a-w "$f.partial"; mv -n "$f.partial" "$f"' 'mv "$f.partial" "$f"'
mut "RW8 U2's answers digest is not re-verified" \
    '        W2-*|G7UP-*-U2)' '        W2-*)'
mut "RW9 the versionCode edit is made in the checkout, not the scratch copy" \
    'got="$(bump_version_code "$N1_SCRATCH/android/app/build.gradle.kts" "$vn")"' \
    'got="$(bump_version_code "$ANDROID_DIR/app/build.gradle.kts" "$vn")"'
printf '\n%d of %d mutations caught\n' "$n_caught" "$n_total"
[ "$n_caught" -eq "$n_total" ]
