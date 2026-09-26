#!/usr/bin/env bash
# autopilot-common.sh — names, records, output and stops for pre-g8-autopilot.sh.
#
# Sourced, never run. Everything the autopilot remembers lives under
# AP_STATE (EVIDENCE/autopilot), outside the repository, as small key=value
# records written atomically. A record is never overwritten by a different
# one: the old version moves to AP_STATE/records/history/ first, the same rule
# pre-g8-manual-gates.sh applies to gate records. Nothing here deletes a file.

# shellcheck disable=SC2034  # constants read by the other autopilot modules

AP_DISTROS=(fedora44 ubuntu2404 ubuntu2604 debian13)
AP_ROLES=(chain u8 lc)
AP_CHAIN_STEPS=(INSTALL U2 UPGRADE U6 SECLOG U10)

# The historical release and the device the project certifies with. Pinned
# here, never guessed; a self-test may point the release at a fixture.
AP_RELEASE_REPO="yurisismotto/OmniBridge"
AP_RELEASE_TAG="v1.0.0"
AP_RELEASE_FPR="F545DC184E909192C3FB6F6E64963019E731BE07"
AP_RELEASE_SUBKEY="E8EDE4706F067739A8D3A8B74C48CB81694FD134"
AP_PHONE_SERIAL="RX2Y500C7SY"
AP_PHONE_MODEL="SM-X620"
AP_GUEST_USER="anyflow"; AP_GUEST_UID=1000

# ap_abbr DISTRO — the short form used in domain and host names. Host names
# never contain "fedora": lifecycle-peer-gates.sh recognises the tablet's
# pairing with the HOST daemon by that word in the phone's UI.
ap_abbr() {
    case "$1" in
        fedora44) echo f44 ;; ubuntu2404) echo u2404 ;; ubuntu2604) echo u2604 ;; debian13) echo d13 ;;
        *) return 1 ;;
    esac
}
ap_domain()   { printf 'pliwee-g8-%s-%s' "$(ap_abbr "$1")" "$2"; }   # DISTRO ROLE
ap_hostname() { printf 'g8-%s-%s' "$(ap_abbr "$1")" "$2"; }          # DISTRO ROLE
ap_is_ours()  { [[ "$1" == pliwee-g8-* ]]; }
# ap_gate_role GATE — which of the distro's three guests a gate runs on.
ap_gate_role() {
    case "$1" in
        G7UP-*-U8) echo u8 ;;
        LIFECYCLE-*) echo lc ;;
        G7UP-*) echo chain ;;
        *) return 1 ;;
    esac
}
ap_gate_distro() { sed -n 's/^\(G7UP\|LIFECYCLE\)-\([a-z0-9]*\).*/\2/p' <<<"$1"; }
ap_owned_gate()  { [[ "$1" == G7UP-* || "$1" == LIFECYCLE-* ]]; }

# ---------------------------------------------------------------- output --
# One short line per transition on the terminal; everything also goes to the
# journal. Full logs are files, never the terminal.
AP_JOURNAL=""
ap_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ap_stamp() { date -u +%Y%m%dT%H%M%SZ; }
ap_say() { # TAG MESSAGE
    local tag="$1"; shift
    printf '[%-4s] %s\n' "$tag" "$*"
    [ -z "$AP_JOURNAL" ] || printf '%s [%s] %s\n' "$(ap_utc)" "$tag" "$*" >> "$AP_JOURNAL" 2>/dev/null || true
}
ap_detail() { printf '       %s\n' "$@"; }
ap_log() { [ -z "$AP_JOURNAL" ] || printf '%s %s\n' "$(ap_utc)" "$*" >> "$AP_JOURNAL" 2>/dev/null || true; }

# --------------------------------------------------------------- records --
# A record is key=value lines, each key at most once. Writers keep it so
# (ap_rec_put refuses anything else) and readers refuse a record that is not:
# with two state= lines there is no telling which one is current, and a
# resumable run must not guess.
ap_rec()      { printf '%s/records/%s' "$AP_STATE" "$1"; }
ap_rec_has()  { [ -f "$(ap_rec "$1")" ]; }
# ap_rec_problems LINE... — what is wrong with these lines as a record (one
# line per problem), or nothing.
ap_rec_problems() {
    [ $# -gt 0 ] || { echo "no lines"; return; }
    awk '!/^[A-Za-z0-9_.-]+=/ { printf "line %d is not key=value: %.60s\n", NR, $0; next }
         { k = $0; sub(/=.*/, "", k); if (n[k]++ == 1) dup[++m] = k }
         END { for (i = 1; i <= m; i++) printf "key %s appears %d times\n", dup[i], n[dup[i]] }' \
        <<<"$(printf '%s\n' "$@")"
}
# ap_rec_file_problems NAME — the same, for the record on disk.
ap_rec_file_problems() {
    local cur=()
    mapfile -t cur < "$(ap_rec "$1")" || { echo "unreadable"; return; }
    ap_rec_problems "${cur[@]}"
}
# ap_rec_get NAME KEY — the one KEY= value. Absent: exit 1. The key twice: a
# refusal on stderr and exit 2, never one of the values.
ap_rec_get() {
    local f; f="$(ap_rec "$1")"
    [ -f "$f" ] || return 1
    awk -v k="$2" '{ key = $0; sub(/=.*/, "", key) }
        key == k && index($0, "=") { n++; v = substr($0, length(k) + 2) }
        END { if (n == 1) { print v; exit 0 }
              if (n > 1) { printf "pre-g8-autopilot: REFUSED: record %s has %d %s= lines; not guessing which is current\n", FILENAME, n, k > "/dev/stderr"; exit 2 }
              exit 1 }' "$f"
}
# ap_rec_put NAME key=value... — write a whole record. Refused (exit 1, nothing
# written) unless every line is key=value with no key twice. An existing record
# with different content is copied to records/history/ first; the new one then
# replaces it in one rename, so an interruption leaves the old version or the
# new one, never neither. Identical content is left alone (a resume re-deriving
# the same facts does not churn the history).
ap_rec_put() {
    local name="$1" f tmp bad; shift
    bad="$(ap_rec_problems "$@")"
    [ -z "$bad" ] || { printf 'pre-g8-autopilot: REFUSED to write record %s: %s\n' "$name" "$(tr '\n' ';' <<<"$bad")" >&2; return 1; }
    f="$(ap_rec "$name")"; tmp="$f.partial.$$"
    mkdir -p "$(dirname "$f")" "$AP_STATE/records/history" || return 1
    printf '%s\n' "$@" > "$tmp" || { rm -f "$tmp"; return 1; }
    if [ -f "$f" ]; then
        if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
        cp -p "$f" "$(mktemp "$AP_STATE/records/history/$name.$(ap_stamp).XXXXXX")" || { rm -f "$tmp"; return 1; }
    fi
    mv -f "$tmp" "$f"
}
# ap_rec_set NAME key=value... — the record with these keys set: a key it has
# is replaced where it stands, a new key is added at the end, every other line
# is kept as it is. A new version, the old one kept in the history. A record
# that is already malformed is refused, not repaired: the run stops.
ap_rec_set() {
    local name="$1" line k bad cur=() out=(); shift
    declare -A upd=()
    bad="$(ap_rec_problems "$@")"
    [ -z "$bad" ] || ap_stop "internal: an update to record $name is malformed: $(tr '\n' ';' <<<"$bad")"
    if ap_rec_has "$name"; then
        bad="$(ap_rec_file_problems "$name")"
        [ -z "$bad" ] || ap_stop "record $(ap_rec "$name") is malformed; refusing to update it" \
            "$bad" "Nothing was changed. Its earlier versions are in $AP_STATE/records/history/."
        mapfile -t cur < "$(ap_rec "$name")"
    fi
    for line in "$@"; do upd["${line%%=*}"]="$line"; done
    for line in "${cur[@]}"; do
        k="${line%%=*}"
        if [ -n "${upd[$k]+set}" ]; then out+=("${upd[$k]}"); unset "upd[$k]"; else out+=("$line"); fi
    done
    for line in "$@"; do
        k="${line%%=*}"
        [ -n "${upd[$k]+set}" ] && { out+=("$line"); unset "upd[$k]"; }
    done
    ap_rec_put "$name" "${out[@]}"
}
# ap_records_verify — every current record is well-formed, before anything
# reads one. A malformed record stops the run, naming it and what is wrong.
ap_records_verify() {
    local f name bad all=()
    for f in "$AP_STATE"/records/*; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        case "$name" in *.partial.*) continue ;; esac
        bad="$(ap_rec_file_problems "$name")"
        [ -z "$bad" ] || all+=("$f: $(tr '\n' ';' <<<"$bad")")
    done
    [ "${#all[@]}" -eq 0 ] || ap_stop "malformed autopilot records; refusing to guess which values are current" \
        "${all[@]}" "Nothing was changed. Earlier versions are in $AP_STATE/records/history/."
}

# --------------------------------------------------------------- stopping --
# Every way the autopilot ends goes through ap_finish, which writes the
# report, records where it stopped, and exits with a code the self-tests read:
#   0 DONE      nothing automatable left
#   1 FAIL      a gate measured FAIL (or its evidence stopped verifying)
#   3 STOP      a prerequisite is missing or a state is not safe to continue
#   4 WAIT      a person has to do something the autopilot cannot
#   130         interrupted (Ctrl+C / TERM)
AP_EXIT_DONE=0; AP_EXIT_FAIL=1; AP_EXIT_STOP=3; AP_EXIT_WAIT=4; AP_EXIT_INT=130
AP_FINISHING=0
ap_finish() { # KIND MESSAGE [DETAIL...]
    local kind="$1" msg="$2" code; shift 2
    [ "$AP_FINISHING" = 0 ] || exit "${AP_LAST_CODE:-3}"
    AP_FINISHING=1
    case "$kind" in
        DONE) code=$AP_EXIT_DONE ;; FAIL) code=$AP_EXIT_FAIL ;; WAIT) code=$AP_EXIT_WAIT ;;
        INT) code=$AP_EXIT_INT ;; *) code=$AP_EXIT_STOP ;;
    esac
    AP_LAST_CODE=$code
    ap_say "$kind" "$msg"
    [ $# -eq 0 ] || ap_detail "$@"
    if [ -n "${AP_STATE:-}" ] && [ -d "$AP_STATE" ]; then
        ap_rec_put last-stop "kind=$kind" "message=$(tr '\n' ' ' <<<"$msg")" "detail=$(printf '%s | ' "$@" | tr '\n' ' ')" \
            "session=${AP_SESSION_ID:-}" "recorded_utc=$(ap_utc)" "exit=$code" 2>/dev/null || true
        declare -F ap_on_finish >/dev/null && ap_on_finish "$kind" "$msg"
    fi
    exit "$code"
}
ap_stop() { ap_finish STOP "$@"; }

# -------------------------------------------------------------- terminal --
# Answers come from the terminal (a self-test: stdin). No terminal is not a
# default answer: it is a WAIT, recorded, and the run can be resumed.
ap_have_tty() {
    [ "${AP_SELFTEST:-0}" = 1 ] && return 0
    { : < /dev/tty; } 2>/dev/null
}
ap_read() { # PROMPT — one line typed at the terminal; EOF fails
    local a
    printf '%s ' "$1" >&2
    # A self-test's "terminal" is fd 7 (ap_selftest_stdin), so that no child
    # can read the operator's answers from a shared stdin.
    if [ "${AP_SELFTEST:-0}" = 1 ]; then IFS= read -r a <&7 || return 1
    else { IFS= read -r a < /dev/tty; } 2>/dev/null || return 1; fi
    printf '%s' "$a"
}
# ap_selftest_stdin — in a self-test, the answers move to fd 7 and every child
# gets /dev/null, as a real run's children never see /dev/tty's answers.
ap_selftest_stdin() { exec 7<&0 0</dev/null; }
ap_banner() { # TITLE LINE... — the one checkpoint block a person has to act on
    local t="$1"; shift
    printf '\n=========================================================\n'
    printf '%s\n' "$t"
    printf '=========================================================\n'
    printf '  %s\n' "$@"
    printf '=========================================================\n'
}

# ------------------------------------------------------------------ misc --
ap_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
ap_q() { printf '%q' "$1"; }
# ap_mem_available_mib — MemAvailable from AP_MEMINFO (default /proc/meminfo).
ap_mem_available_mib() {
    awk '/^MemAvailable:/ { printf "%d", $2 / 1024; found = 1 } END { if (!found) exit 1 }' "${AP_MEMINFO:-/proc/meminfo}"
}
