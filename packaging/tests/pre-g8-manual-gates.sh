#!/usr/bin/env bash
# pre-g8-manual-gates.sh — the operator's coordinator for the manual and
# hardware gates a G8 re-run needs (pre-W8 remediation §8; Wave 2 §7; Wave 6
# §7; Wave 7 §5; rebrand plan §3).
#
# WHAT IT IS
# ----------
# One resumable list of gates, one state record per gate, and one evidence
# directory. It runs the repository's own gate scripts — upgrade-gates.sh,
# lifecycle-peer-gates.sh (through upgrade-gates.sh --stage peer-u6),
# security-log-evidence.sh, lifecycle-gates.sh, provision-signing-keys.sh and
# the Gradle instrumented suite — and records what they said. It does not
# restate their assertions: a gate is PASS here only when the script that owns
# it exited 0 and the evidence it wrote still verifies.
#
# WHAT IT REFUSES TO DO
# ---------------------
#   * turn missing, empty, altered or unverifiable evidence into PASS. A gate
#     with no record is PENDING or BLOCKED; a record that no longer verifies
#     is FAIL; an interrupted run is BLOCKED until it is run again;
#   * run U10 (the downgrade) before a verified U6 PASS on the same guest, or
#     before the security-log gate on the upgraded guest has been decided;
#   * let any gate's own record — interrupted, half-done, not-executed, or a
#     result being retried — stand in for its prerequisites. They are checked
#     again before every execution; after U10 has started on a chain, neither
#     U6 nor the security-log gate can run on it again;
#   * replace a measured FAIL, or a run that started, with "not executed", or
#     overwrite any earlier record: a new attempt moves it to state/history/;
#   * guess a distro, a domain, a package directory, a phone or a device
#     serial. A missing value is a refusal naming the flag that supplies it;
#   * change a VM, the physical Android device or signing media without first
#     printing the exact action and reading an explicit answer typed at the
#     terminal (`yes`, or the domain's name for a fresh-guest gate);
#   * capture, log or store a signing password. provision-signing-keys.sh runs
#     on this terminal with nothing between it and the operator;
#   * run two things at once. One gate per invocation, a host-wide lock, and a
#     refusal if another configured guest is running;
#   * create repositories, touch Play Console, publish releases, add OpenPGP
#     UIDs, or merge branches. None of that is in here.
#
# USAGE
# -----
#   pre-g8-manual-gates.sh [--evidence DIR] [--config FILE] [options] COMMAND
#
#   COMMAND
#     --status                 every gate: PASS / FAIL / PENDING / BLOCKED
#     --list                   gate ids, in the order --next takes them
#     --next                   run the first gate that is PENDING or was
#                              interrupted (the resume point)
#     --run GATE               run one gate
#     --not-executed GATE --reason TEXT
#                              record that a gate was not executed, and why.
#                              It stays BLOCKED; it never becomes PASS, and it
#                              waives none of the gate's prerequisites. Refused
#                              over a PASS, a FAIL or a run that started
#     --reset-distro D         move one distribution's G7-UP chain aside (after
#                              restoring the guest's snapshot); nothing deleted
#
#   OPTIONS (a sourced --config FILE may set the same values; see below)
#     --distro D               the distro the per-distro options below apply to
#     --domain DOM             the guest for install/upgrade/U6/security-log/U10
#     --u8-domain DOM          a FRESH guest for U8
#     --lifecycle-domain DOM   a FRESH guest for lifecycle-gates.sh
#     --old-pkgdir DIR         the published OmniBridge 1.0.0 set + SHA256SUMS(.asc)
#     --new-pkgdir DIR         the Pliwee set + SHA256SUMS
#     --keyring FILE --fingerprint FPR   verify the 1.0.0 SHA256SUMS.asc (U1)
#     --phone-ip IP --adb-serial S       the physical Android peer
#     --media-a PATH --media-b PATH      the two offline signing media
#     --apk-n FILE --apk-n1 FILE         prebuilt Pliwee N and N+1 debug APKs
#                                        (otherwise both are built here)
#     --rerun                  allow --run on a gate that already has a result.
#                              A new attempt: the previous record is moved to
#                              EVIDENCE/state/history/, never overwritten
#
#   CONFIG FILE (bash, sourced; per-distro keys carry the distro as a suffix)
#     DOMAIN_fedora44=anyflow-f44   U8_DOMAIN_fedora44=...   LIFECYCLE_DOMAIN_fedora44=...
#     OLD_PKGDIR_fedora44=/srv/g7/omnibridge-1.0.0/fedora44   NEW_PKGDIR_fedora44=...
#     KEYRING=... FINGERPRINT=... PHONE_IP=... ADB_SERIAL=... MEDIA_A=... MEDIA_B=...
#     APK_N=... APK_N1=...   GUEST_USER=... GUEST_UID=... (passed to the harnesses)
#
# Every invocation ends with a machine-readable block between
# PRE_G8_SUMMARY_BEGIN and PRE_G8_SUMMARY_END, also written to
# EVIDENCE/summary.txt, for the closure pass that will read it.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
# shellcheck source=lib/g7up-evidence.sh
. "$HERE/lib/g7up-evidence.sh"

DISTROS=(fedora44 ubuntu2404 ubuntu2604 debian13)
APP_PKG="io.github.yurisismotto.pliwee"
LISTENER="$APP_PKG/$APP_PKG.notifications.PliweeNotificationListener"
TILE="$APP_PKG/$APP_PKG.ui.ClipboardTileService"

# The self-test (pre-g8-manual-gates-selftests.sh) points this at stub gate
# scripts. In that mode confirmations are read from stdin rather than the
# terminal, every record is marked selftest=1, and the overall result can only
# ever be SELFTEST: a stubbed run cannot produce a PASS.
GATES_DIR="$HERE"; ANDROID_DIR="$REPO/android"; SELFTEST=0
if [ -n "${PRE_G8_GATES_DIR:-}" ]; then
    GATES_DIR="$PRE_G8_GATES_DIR"; ANDROID_DIR="$PRE_G8_GATES_DIR/android"; SELFTEST=1
fi

die()  { printf 'pre-g8: REFUSED: %s\n' "$*" >&2; exit 2; }
note() { printf 'pre-g8: %s\n' "$*"; }

# ---------------------------------------------------------------- arguments --
EVIDENCE=""; CONFIG=""; CMD=""; GATE_ARG=""; REASON=""; RERUN=0; CUR_DISTRO=""
set_pd() { # KEY VALUE — a per-distro value, for the distro --distro named
    [ -n "$CUR_DISTRO" ] || die "$1 is per-distro: give --distro first"
    printf -v "${1}_${CUR_DISTRO}" '%s' "$2"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --evidence) EVIDENCE="${2:?}"; shift 2 ;;
        --config) CONFIG="${2:?}"; shift 2 ;;
        --status|--list|--next) CMD="${1#--}"; shift ;;
        --run) CMD=run; GATE_ARG="${2:?}"; shift 2 ;;
        --not-executed) CMD=not-executed; GATE_ARG="${2:?}"; shift 2 ;;
        --reset-distro) CMD=reset-distro; GATE_ARG="${2:?}"; shift 2 ;;
        --reason) REASON="${2-}"; shift 2 ;;
        --rerun) RERUN=1; shift ;;
        --distro) CUR_DISTRO="${2:?}"; shift 2
            case " ${DISTROS[*]} " in *" $CUR_DISTRO "*) : ;; *) die "unknown distro '$CUR_DISTRO' (${DISTROS[*]})" ;; esac ;;
        --domain) set_pd DOMAIN "${2:?}"; shift 2 ;;
        --u8-domain) set_pd U8_DOMAIN "${2:?}"; shift 2 ;;
        --lifecycle-domain) set_pd LIFECYCLE_DOMAIN "${2:?}"; shift 2 ;;
        --old-pkgdir) set_pd OLD_PKGDIR "${2:?}"; shift 2 ;;
        --new-pkgdir) set_pd NEW_PKGDIR "${2:?}"; shift 2 ;;
        --keyring) CLI_KEYRING="${2:?}"; shift 2 ;;
        --fingerprint) CLI_FINGERPRINT="${2:?}"; shift 2 ;;
        --phone-ip) CLI_PHONE_IP="${2:?}"; shift 2 ;;
        --adb-serial) CLI_ADB_SERIAL="${2:?}"; shift 2 ;;
        --media-a) CLI_MEDIA_A="${2:?}"; shift 2 ;;
        --media-b) CLI_MEDIA_B="${2:?}"; shift 2 ;;
        --apk-n) CLI_APK_N="${2:?}"; shift 2 ;;
        --apk-n1) CLI_APK_N1="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
        *) die "unknown argument '$1' (--help)" ;;
    esac
done
[ -n "$CMD" ] || die "no command (--status, --list, --next, --run GATE, --not-executed GATE, --reset-distro D)"

# Per-distro values given on the command line win over the config file, so
# they are kept aside while it is sourced and put back afterwards.
save_cli=()
for v in $(compgen -v | grep -E '^(DOMAIN|U8_DOMAIN|LIFECYCLE_DOMAIN|OLD_PKGDIR|NEW_PKGDIR)_' || true); do
    save_cli+=("$v=${!v}")
done
if [ -n "$CONFIG" ]; then
    [ -f "$CONFIG" ] || die "--config $CONFIG does not exist"
    # shellcheck disable=SC1090
    . "$CONFIG" || die "--config $CONFIG failed to load"
fi
for kv in "${save_cli[@]}"; do printf -v "${kv%%=*}" '%s' "${kv#*=}"; done
KEYRING="${CLI_KEYRING:-${KEYRING:-}}"; FINGERPRINT="${CLI_FINGERPRINT:-${FINGERPRINT:-}}"
PHONE_IP="${CLI_PHONE_IP:-${PHONE_IP:-}}"; ADB_SERIAL="${CLI_ADB_SERIAL:-${ADB_SERIAL:-}}"
MEDIA_A="${CLI_MEDIA_A:-${MEDIA_A:-}}"; MEDIA_B="${CLI_MEDIA_B:-${MEDIA_B:-}}"
APK_N="${CLI_APK_N:-${APK_N:-}}"; APK_N1="${CLI_APK_N1:-${APK_N1:-}}"
for v in GUEST_USER GUEST_UID IDLE_USER; do [ -n "${!v:-}" ] && export "${v?}"; done

EVIDENCE="${EVIDENCE:-${XDG_STATE_HOME:-$HOME/.local/state}/pliwee-pre-g8}"
need_abs_path "--evidence" "$EVIDENCE" || die "give --evidence as an absolute path"
case "$EVIDENCE/" in
    "$REPO/"*) die "--evidence $EVIDENCE is inside the source tree; evidence is kept outside it and copied into docs/ by a closure pass" ;;
esac
mkdir -p "$EVIDENCE/state" "$EVIDENCE/logs" || die "cannot create $EVIDENCE"
need_writable "$EVIDENCE" || die "cannot write to $EVIDENCE"

# pd KEY DISTRO — a per-distro value, or empty.
pd() { local n="${1}_${2}"; printf '%s' "${!n:-}"; }
# need_cfg VALUE FLAG WHAT — refuse a missing value instead of guessing one.
need_cfg() { [ -n "$1" ] || die "$3 is not configured: give $2 (or its key in --config). Nothing is guessed."; }

# ---------------------------------------------------------------- the gates --
all_gates() {
    printf '%s\n' W2-GNOME W2-KDE W6-SIGNING W6-COMPONENT-UPGRADE W6-INSTRUMENTED
    local d
    for d in "${DISTROS[@]}"; do
        printf '%s\n' "G7UP-$d-INSTALL" "G7UP-$d-U2" "G7UP-$d-UPGRADE" "G7UP-$d-U6" \
            "G7UP-$d-SECLOG" "G7UP-$d-U10" "G7UP-$d-U8" "LIFECYCLE-$d"
    done
}
is_gate() { grep -qxF -- "$1" <<<"$(all_gates)"; }
gate_distro() { sed -n 's/^\(G7UP\|LIFECYCLE\)-\([a-z0-9]*\).*/\2/p' <<<"$1"; }
gate_step() { sed -n 's/^G7UP-[a-z0-9]*-//p' <<<"$1"; }
chain_dir() { printf '%s' "$EVIDENCE/g7up/$1"; }

describe() {
    case "$1" in
        W2-GNOME) echo "Wave 2 Devices page, keyboard + Orca, real GNOME session (operator)" ;;
        W2-KDE) echo "Wave 2 Devices page, keyboard + screen reader, real KDE Plasma session (operator)" ;;
        W6-SIGNING) echo "Wave 6 Pliwee Android signing provisioning, two offline media (operator terminal)" ;;
        W6-COMPONENT-UPGRADE) echo "Wave 6 Pliwee N -> N+1: listener grant, QS tile, pinned shortcut survive (device)" ;;
        W6-INSTRUMENTED) echo "Wave 6 :app:connectedDebugAndroidTest on the designated device" ;;
        G7UP-*-INSTALL) echo "G7-UP U0 U1 U2(auto): OmniBridge 1.0.0 installed on $(gate_distro "$1")" ;;
        G7UP-*-U2) echo "G7-UP U2 (operator): the physical phone paired, grants, policies, GUI selection" ;;
        G7UP-*-UPGRADE) echo "G7-UP O1 U3 U4 O2 U5 U7 U9, stop on Pliwee (checkpoint)" ;;
        G7UP-*-U6) echo "G7-UP U6: lifecycle-peer-gates.sh against the upgraded guest" ;;
        G7UP-*-SECLOG) echo "security-log-evidence.sh on the upgraded guest, before U10" ;;
        G7UP-*-U10) echo "G7-UP U10: downgrade to OmniBridge 1.0.0 (only after U6 PASS)" ;;
        G7UP-*-U8) echo "G7-UP U8 negative: unreadable legacy dir, on a FRESH guest" ;;
        LIFECYCLE-*) echo "lifecycle-gates.sh L1-L26 on a FRESH guest with the Pliwee set" ;;
    esac
}

# ----------------------------------------------------------- state records --
sf() { printf '%s' "$EVIDENCE/state/$1"; }
st() { g7up_kv "$(sf "$1")" "$2" 2>/dev/null; }
hdir() { printf '%s' "$EVIDENCE/state/history"; }
# ATTEMPT names one execution (or one not-executed record). A record left by
# any other attempt is evidence of what happened then: state_write moves it to
# state/history/ before writing, so a retry never erases a FAIL, an
# interruption or an earlier reason.
ATTEMPT=""; GATE_RUN=""
new_attempt() { ATTEMPT="$(date -u +%Y%m%dT%H%M%SZ).$$"; }
state_write() { # GATE key=value...
    local g="$1" f; f="$(sf "$1")"; shift
    [ -n "$ATTEMPT" ] || die "internal: a state record written outside an attempt"
    if [ -f "$f" ] && [ "$(g7up_kv "$f" attempt 2>/dev/null)" != "$ATTEMPT" ]; then archive_record "$g"; fi
    { printf '%s\n' "$@"; echo "attempt=$ATTEMPT"; echo "selftest=$SELFTEST"; echo "recorded_utc=$(date -u +%FT%TZ)"; } > "$f.partial" \
        && mv "$f.partial" "$f"
}
archive_record() { # GATE — move its current record into the history, unchanged
    local h
    mkdir -p "$(hdir)" || die "cannot create $(hdir); the previous record of $1 was not overwritten"
    h="$(mktemp "$(hdir)/$1.$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || die "cannot archive the previous record of $1; nothing was overwritten"
    mv -f "$(sf "$1")" "$h" || die "cannot archive the previous record of $1; nothing was overwritten"
}
# hist_counts GATE — "history=N history_fail=M": archived records, and how many FAIL.
hist_counts() {
    local f n=0 nf=0
    for f in "$(hdir)/$1".*; do
        [ -f "$f" ] || continue
        n=$((n + 1)); [ "$(g7up_kv "$f" state 2>/dev/null)" = FAIL ] && nf=$((nf + 1))
    done
    printf 'history=%s history_fail=%s' "$n" "$nf"
}
# ever_started GATE — true if any record of it, current or archived, is of an
# attempt that began. Only a not-executed record is not; an unreadable one is.
ever_started() {
    local f
    for f in "$(sf "$1")" "$(hdir)/$1".*; do
        [ -f "$f" ] || continue
        [ "$(g7up_kv "$f" state 2>/dev/null)" = NOT_EXECUTED ] || return 0
    done
    return 1
}
# u10_started DISTRO — the downgrade began on this chain, through this
# coordinator or through upgrade-gates.sh directly (its own U10-STARTED marker).
# From then on the upgraded guest that U6 and the security-log gate measure is gone.
u10_started() {
    [ -e "$(chain_dir "$1")/$G7UP_U10_STARTED" ] || ever_started "G7UP-$1-U10"
}

# reverify GATE — a recorded PASS is only reported PASS while its evidence
# still says so. Prints the reason when it does not.
reverify() {
    local g="$1" log sha d why
    log="$(st "$g" log)"; sha="$(st "$g" log_sha256)"
    if [ -n "$log" ]; then
        [ -f "$log" ] || { echo "its log $log is missing"; return 1; }
        [ "$(g7up_sha "$log")" = "$sha" ] || { echo "its log $log was altered after it was recorded"; return 1; }
    fi
    case "$g" in
        W2-*)
            [ "$(g7up_sha "$(st "$g" answers)")" = "$(st "$g" answers_sha256)" ] \
                || { echo "the recorded answers are missing or altered"; return 1; } ;;
        W6-SIGNING)
            grep -q '^backups restore-verified:' "$(st "$g" status_file)" 2>/dev/null \
                || { echo "the provisioning record does not show restore-verified backups"; return 1; } ;;
        G7UP-*-UPGRADE)
            d="$(gate_distro "$g")"
            why="$(g7up_verify_checkpoint "$(chain_dir "$d")" "$d" "$(st "$g" domain)" 2>&1 >/dev/null)" \
                || { echo "${why##*$'\n'}"; return 1; } ;;
        G7UP-*-U6)
            d="$(gate_distro "$g")"
            why="$(g7up_verify_u6 "$(chain_dir "$d")" "$d" "$(st "$g" domain)" 2>&1 >/dev/null)" \
                || { echo "${why##*$'\n'}"; return 1; } ;;
    esac
    return 0
}

# status GATE — prints "STATE<TAB>reason". STATE is PASS, FAIL, PENDING or
# BLOCKED; nothing without a verified record is ever PASS.
status() {
    local g="$1" s why
    s="$(st "$g" state)"
    # A record a stubbed self-test wrote is not evidence of anything real.
    if [ -n "$s" ] && [ "$(st "$g" selftest)" != "$SELFTEST" ]; then
        printf 'BLOCKED\trecorded by a %s run, which is not evidence for this one\n' \
            "$([ "$SELFTEST" = 1 ] && echo real || echo self-test)"; return
    fi
    case "$s" in
        PASS)
            if why="$(reverify "$g")"; then printf 'PASS\t%s\n' "$(st "$g" finished_utc)"
            else printf 'FAIL\trecorded PASS no longer verifies: %s\n' "$why"; fi
            return ;;
        FAIL) printf 'FAIL\t%s\n' "$(st "$g" reason)"; return ;;
    esac
    # No record, an interrupted or half-done run, or a not-executed record:
    # each is only as runnable as its prerequisites are NOW. A record of the
    # gate's own never stands in for them.
    if ! why="$(prereq "$g")"; then
        printf '%s%s\n' "$why" "${s:+ (its own record: $s)}"; return
    fi
    case "$s" in
        RUNNING) printf 'BLOCKED\tinterrupted (started %s, log %s); resume with --next or --run %s\n' "$(st "$g" started_utc)" "$(st "$g" log)" "$g" ;;
        INCOMPLETE) printf 'BLOCKED\t%s; resume with --next or --run %s\n' "$(st "$g" reason)" "$g" ;;
        NOT_EXECUTED) printf 'BLOCKED\tnot executed: %s\n' "$(st "$g" reason)" ;;
        "") printf 'PENDING\t%s\n' "$(describe "$g")" ;;
        *) printf 'BLOCKED\tunrecognised record state %s\n' "$s" ;;
    esac
}
# prereq GATE — what must hold before GATE may execute, whatever its own
# record says. Prints "BLOCKED<TAB>reason" and fails when something does not.
prereq() {
    local g="$1" d
    d="$(gate_distro "$g")"
    case "$g" in
        G7UP-*-U2)      need_pass "G7UP-$d-INSTALL" || return 1 ;;
        G7UP-*-UPGRADE) need_pass "G7UP-$d-U2" || return 1 ;;
        G7UP-*-U6)
            need_pass "G7UP-$d-UPGRADE" || return 1
            ! u10_started "$d" \
                || { printf 'BLOCKED\tU10 has started on the %s chain; the upgraded guest U6 measures no longer exists (--reset-distro %s)\n' "$d" "$d"; return 1; } ;;
        G7UP-*-SECLOG)
            need_pass "G7UP-$d-U6" || return 1
            ! u10_started "$d" \
                || { printf 'BLOCKED\tU10 has run; the upgraded guest this gate needs no longer exists (--reset-distro %s)\n' "$d"; return 1; } ;;
        G7UP-*-U10)
            need_pass "G7UP-$d-U6" || return 1
            case "$(st "G7UP-$d-SECLOG" state)" in
                PASS|FAIL|NOT_EXECUTED) : ;;
                *) printf 'BLOCKED\twaiting for G7UP-%s-SECLOG to be run or recorded not-executed: it can only be measured before the downgrade\n' "$d"; return 1 ;;
            esac
            [ "$(st "G7UP-$d-SECLOG" selftest)" = "$SELFTEST" ] \
                || { printf 'BLOCKED\tthe G7UP-%s-SECLOG record is from another kind of run\n' "$d"; return 1; }
            ! u10_started "$d" \
                || { printf 'BLOCKED\tU10 already started on the %s chain; a second downgrade would measure a guest already on 1.0.0 (--reset-distro %s)\n' "$d" "$d"; return 1; } ;;
    esac
    return 0
}
# prereq_ok GATE — refuse unless prereq holds. Called for every execution.
prereq_ok() {
    local why
    why="$(prereq "$1")" || die "$1 is blocked: ${why#*$'\t'}"
}
need_pass() {
    [ "$(status "$1" | cut -f1)" = PASS ] && return 0
    printf 'BLOCKED\twaiting for %s PASS\n' "$1"; return 1
}

# ------------------------------------------------------------- the summary --
summary() {
    local g line s r n_pass=0 n_fail=0 n_pend=0 n_block=0 result commit dirty out
    commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    dirty="$(git -C "$REPO" status --porcelain 2>/dev/null | grep -c . || true)"
    out="PRE_G8_SUMMARY_BEGIN
evidence=$EVIDENCE
commit=$commit
worktree_changes=$dirty
selftest=$SELFTEST
generated_utc=$(date -u +%FT%TZ)"
    while IFS= read -r g; do
        line="$(status "$g")"; s="${line%%$'\t'*}"; r="${line#*$'\t'}"
        case "$s" in PASS) n_pass=$((n_pass+1)) ;; FAIL) n_fail=$((n_fail+1)) ;;
                     PENDING) n_pend=$((n_pend+1)) ;; *) n_block=$((n_block+1)) ;; esac
        out="$out
PRE_G8_GATE id=$g state=$s $(hist_counts "$g") reason=\"${r//\"/\'}\""
    done < <(all_gates)
    if [ "$SELFTEST" = 1 ]; then result=SELFTEST
    elif [ "$n_fail" -gt 0 ]; then result=FAIL
    elif [ "$n_pend" -eq 0 ] && [ "$n_block" -eq 0 ] && [ "$n_pass" -gt 0 ]; then result=PASS
    else result=INCOMPLETE; fi
    out="$out
PRE_G8_COUNTS pass=$n_pass fail=$n_fail pending=$n_pend blocked=$n_block total=$((n_pass+n_fail+n_pend+n_block))
PRE_G8_RESULT=$result
PRE_G8_SUMMARY_END"
    printf '%s\n' "$out" > "$EVIDENCE/summary.txt"
    printf '\n%s\n' "$out"
}

print_status() {
    local g line
    printf '%-28s %-8s %s\n' GATE STATE DETAIL
    while IFS= read -r g; do
        line="$(status "$g")"
        printf '%-28s %-8s %s\n' "$g" "${line%%$'\t'*}" "${line#*$'\t'}"
    done < <(all_gates)
}

# ---------------------------------------------------- operator interaction --
# Answers come from the terminal, never from a pipe: an action that changes a
# VM, the phone or the signing media must have been typed by a person. A
# self-test reads stdin instead, and cannot produce a PASS (see SELFTEST).
ask() { # PROMPT — one line from the operator; EOF is a refusal, never a default
    local a
    printf '%s ' "$1" >&2
    if [ "$SELFTEST" = 1 ]; then IFS= read -r a || return 1
    else { IFS= read -r a < /dev/tty; } 2>/dev/null || return 1; fi
    printf '%s' "$a"
}
confirm_action() { # TOKEN LINE... — print the exact action; require TOKEN typed back
    local token="$1" a; shift
    if [ "$SELFTEST" = 0 ] && ! { : < /dev/tty; } 2>/dev/null; then
        die "this action needs explicit confirmation at a terminal, and there is none"
    fi
    printf '\n=========================================================\n' >&2
    printf 'ACTION — this changes something outside this host\n' >&2
    printf '=========================================================\n' >&2
    printf '  %s\n' "$@" >&2
    printf '=========================================================\n' >&2
    a="$(ask "Type '$token' to do exactly this, anything else to stop:")" || a=""
    [ "$a" = "$token" ] && return 0
    # A gate writes its attempt's first record only after its first
    # confirmation is accepted; a later one declined leaves that attempt open.
    if [ -n "$ATTEMPT" ] && [ "$(st "$GATE_RUN" attempt)" = "$ATTEMPT" ]; then
        note "not confirmed; this action was not done. $GATE_RUN stays recorded as $(st "$GATE_RUN" state) for this attempt (--status; resume with --run $GATE_RUN)"
    else
        note "not confirmed; nothing was changed and the gate keeps its previous state"
    fi
    exit 5
}
yn() { # QUESTION — y or n, asked until one is given
    local a
    while :; do
        a="$(ask "$1 [y/n]")" || { note "no answer (EOF); nothing recorded"; exit 5; }
        case "$a" in y|n) printf '%s' "$a"; return ;; esac
    done
}

# One VM at a time: no guest this coordinator knows about, other than the
# target, may be running. Whether the target itself is up is not checked here;
# the owning harness contacts it first (upgrade-gates.sh U0 pings its agent).
one_vm() { # TARGET_DOMAIN
    local running d k other=()
    need_tool virsh || die "virsh is not installed"
    running="$(virsh -c "${GA_CONNECT:-qemu:///system}" list --name 2>/dev/null || true)"
    for d in "${DISTROS[@]}"; do for k in DOMAIN U8_DOMAIN LIFECYCLE_DOMAIN; do
        local v; v="$(pd "$k" "$d")"
        [ -n "$v" ] && [ "$v" != "$1" ] && grep -qxF -- "$v" <<<"$running" && other+=("$v")
    done; done
    [ "${#other[@]}" -eq 0 ] || die "another configured guest is running (${other[*]}); shut it down first — one VM at a time"
}

# --------------------------------------------------------------- execution --
# run_logged GATE CMD... — the gate's owning script, its output teed to a log.
# The state is RUNNING for exactly as long as it runs, so an interruption is
# visible afterwards instead of looking like a gate that never started.
LOG=""; RC=0; STARTED=""; ADBS=()
run_logged() {
    local g="$1"; shift
    # Immediately before the owning script starts, the prerequisites once more.
    prereq_ok "$g"
    STARTED="$(date -u +%FT%TZ)"
    LOG="$EVIDENCE/logs/$g.$(date -u +%Y%m%dT%H%M%SZ).log"
    state_write "$g" "gate=$g" state=RUNNING "started_utc=$STARTED" "log=$LOG"
    { printf '# %s\n# started %s\n# command:' "$g" "$STARTED"; printf ' %q' "$@"; printf '\n'; } > "$LOG"
    "$@" 2>&1 < /dev/null | tee -a "$LOG"
    RC="${PIPESTATUS[0]}"
}
# record GATE VERDICT REASON [key=value...] — close the RUNNING record.
REC_DOMAIN=""
record() {
    local g="$1" v="$2" r="$3"; shift 3
    state_write "$g" "gate=$g" "state=$v" "reason=$r" "started_utc=$STARTED" \
        "finished_utc=$(date -u +%FT%TZ)" "exit=$RC" "log=$LOG" "log_sha256=$(g7up_sha "$LOG")" \
        "domain=$REC_DOMAIN" "$@"
    note "$g: $v${r:+ — $r}"
}
# log_clean — the owning script's output holds real results and no failure.
log_clean() {
    local t n; t="$(cat "$LOG")"
    need_nonempty "the gate log" "$t" 3 >/dev/null 2>&1 || { echo "the log is empty"; return 1; }
    contains "$t" "PRECONDITION FAILED" && { echo "a precondition failed"; return 1; }
    n="$(grep -c '^not ok' <<<"$t" || true)"; [ "${n:-0}" = 0 ] || { echo "$n check(s) not ok"; return 1; }
    n="$(grep -c '^ok ' <<<"$t" || true)"; [ "${n:-0}" -gt 0 ] || { echo "no check reported ok"; return 1; }
    return 0
}
# finish_gate GATE [ANCHOR_REGEX...] — PASS only on exit 0, a clean log, and
# every anchor line the owning script prints only after measuring.
finish_gate() {
    local g="$1" why a; shift
    [ "$RC" = 0 ] || { record "$g" FAIL "the gate script exited $RC"; return; }
    why="$(log_clean)" || { record "$g" FAIL "$why"; return; }
    for a in "$@"; do contains_re "$(cat "$LOG")" "$a" || { record "$g" FAIL "no line matching /$a/ in the log"; return; }; done
    record "$g" PASS ""
}

gate_w2() { # GATE DESKTOP_REGEX
    local g="$1" re="$2" f sess items="" a fails=() files_ann revoke_ann i
    local steps=(
        "one trusted and at least two revoked devices are present before starting"
        "pliwee-gui --page=peers opens on the Devices page"
        "1. keyboard only: a trusted card's 'Details and controls' opens"
        "2. keyboard only: Files toggles on, then off"
        "3. 'Revoke this device': the dialog's focused default is Cancel, and Escape cancels"
        "4. a revoked card: 'Remove from list' — focused default Cancel, Escape cancels"
        "5. 'Remove all revoked devices' — focused default Cancel, Escape cancels"
        "Tab and arrow keys reach every control, including inside the expander; Enter/Space opens it"
        "with the screen reader on, steps 1-3 repeated and each control announced"
    )
    mkdir -p "$EVIDENCE/w2"
    f="$EVIDENCE/w2/$g.$(date -u +%Y%m%dT%H%M%SZ).txt"
    cat >&2 <<PROC

$g — $(describe "$g")
Procedure (Wave 2 report §7, with the Wave 7 command name): in a real
$([ "$g" = W2-GNOME ] && echo GNOME || echo 'KDE Plasma') session, run 'pliwee-gui --page=peers' with one trusted and at
least two revoked devices, and use ONLY the keyboard. Then repeat steps 1-3
with $([ "$g" = W2-GNOME ] && echo Orca || echo "the KDE screen reader (Orca)") and write down what is announced.
Answer each item from what you observed. Nothing here is inferred.

PROC
    sess="$(ask "Session under test (desktop, version, X11/Wayland, host):")" || { note "no answer; nothing recorded"; exit 5; }
    contains_re "$(tr '[:upper:]' '[:lower:]' <<<"$sess")" "$re" \
        || die "'$sess' does not name the session $g is for; record it from that session"
    STARTED="$(date -u +%FT%TZ)"; LOG=""; RC=0
    for i in "${steps[@]}"; do
        a="$(yn "$i")"; items="$items$a  $i"$'\n'
        [ "$a" = y ] || fails+=("$i")
    done
    files_ann="$(ask "Exactly what was announced for the Files switch:")" || files_ann=""
    revoke_ann="$(ask "Exactly what was announced for the revoke button:")" || revoke_ann=""
    contains "$files_ann" "Files for" || fails+=("the Files switch announcement does not carry 'Files for {name}'")
    [ -n "${revoke_ann//[[:space:]]/}" ] || fails+=("nothing recorded for the revoke button announcement")
    {
        echo "gate=$g"; echo "recorded_utc=$(date -u +%FT%TZ)"; echo "session=$sess"
        echo "host=$(hostname 2>/dev/null)"; echo "operator=${USER:-}"; echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
        echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"; echo "--- items (y/n) ---"; printf '%s' "$items"
        echo "--- announced: Files switch ---"; echo "$files_ann"
        echo "--- announced: revoke button ---"; echo "$revoke_ann"
    } > "$f"
    if [ "${#fails[@]}" -eq 0 ]; then
        record "$g" PASS "" "answers=$f" "answers_sha256=$(g7up_sha "$f")"
    else
        record "$g" FAIL "$(printf '%s; ' "${fails[@]}")" "answers=$f" "answers_sha256=$(g7up_sha "$f")"
    fi
}

gate_signing() {
    local g=W6-SIGNING prov="$ANDROID_DIR/signing/provision-signing-keys.sh" sf_out
    [ "$SELFTEST" = 1 ] || [ -z "${PLIWEE_SIGNING_SELFTEST_ROOT:-}" ] \
        || die "PLIWEE_SIGNING_SELFTEST_ROOT is set: that confines the procedure to a scratch root, and a self-test is not provisioning. Unset it"
    [ "$SELFTEST" = 1 ] || { [ -t 0 ] && [ -t 1 ]; } \
        || die "provisioning shows passwords to the operator and reads answers: run this in your own terminal, with stdin and stdout on it (no pipe, no tee, no redirect)"
    [ -x "$prov" ] || die "$prov is missing"
    mkdir -p "$EVIDENCE/w6"
    sf_out="$EVIDENCE/w6/signing-status.$(date -u +%Y%m%dT%H%M%SZ).txt"
    STARTED="$(date -u +%FT%TZ)"; LOG=""; RC=0
    # --status prints only the PUBLIC record (fingerprints, digests, dates) or
    # the names of completed stages. It is the only output kept.
    "$prov" --status > "$sf_out" 2>&1
    if ! grep -q '^backups restore-verified:' "$sf_out"; then
        need_cfg "$MEDIA_A" --media-a "signing medium A"
        need_cfg "$MEDIA_B" --media-b "signing medium B"
        confirm_action yes \
            "$prov --media-a $MEDIA_A --media-b $MEDIA_B" \
            "writes the encrypted Pliwee signing bundle to BOTH offline media, installs the upload" \
            "keystore under ~/.local/share/pliwee-android-signing and records the PUBLIC result." \
            "It prints three passwords ON THIS TERMINAL ONLY. This coordinator does not capture," \
            "log or store any of its output. It stops for you to eject and re-insert the media;" \
            "run this gate again afterwards to resume it."
        state_write "$g" "gate=$g" state=RUNNING "started_utc=$STARTED" "log="
        # Inherited stdio: nothing sits between the procedure and the operator.
        "$prov" --media-a "$MEDIA_A" --media-b "$MEDIA_B"
        RC=$?
        "$prov" --status > "$sf_out" 2>&1
    fi
    if grep -q '^backups restore-verified:' "$sf_out"; then
        record "$g" PASS "" "status_file=$sf_out"
    elif grep -q '^IN PROGRESS' "$sf_out"; then
        state_write "$g" "gate=$g" state=INCOMPLETE "reason=provisioning in progress ($(tr '\n' ' ' < "$sf_out" | cut -c1-120))" \
            "started_utc=$STARTED" "status_file=$sf_out" "exit=$RC"
        note "$g: in progress — resume it after the media step"
    else
        record "$g" FAIL "provisioning did not complete (exit $RC)" "status_file=$sf_out"
    fi
}

aapt2_bin() {
    local a; a="$(command -v aapt2 2>/dev/null || true)"
    [ -n "$a" ] || a="$(ls -1d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
    printf '%s' "$a"
}
apk_fact() { "$(aapt2_bin)" dump badging "$1" 2>/dev/null | sed -n "s/^package: .*$2='\([^']*\)'.*/\1/p" | head -1; }

# The W6 component observations, taken the same way lifecycle-peer-gates.sh
# checks the listener: the approval setting AND the live binding.
comp_observe() { # DIR PREFIX
    local dir="$1" p="$2"
    "${ADBS[@]}" shell settings get secure enabled_notification_listeners 2>/dev/null | tr -d '\r' > "$dir/$p-listeners.txt"
    "${ADBS[@]}" shell dumpsys notification 2>/dev/null | tr -d '\r' > "$dir/$p-dumpsys-notification.txt"
    "${ADBS[@]}" shell settings get secure sysui_qs_tiles 2>/dev/null | tr -d '\r' > "$dir/$p-qs-tiles.txt"
    comp_version > "$dir/$p-versionCode.txt"
    "${ADBS[@]}" exec-out screencap -p > "$dir/$p-screen.png" 2>/dev/null || true
}
comp_version() { "${ADBS[@]}" shell dumpsys package "$APP_PKG" 2>/dev/null | tr -d '\r' | sed -n 's/^ *versionCode=\([0-9]*\).*/\1/p' | head -1; }
comp_holds() { # DIR PREFIX — prints what is missing
    local dir="$1" p="$2" m=()
    need_nonempty "the $p listener setting" "$(cat "$dir/$p-listeners.txt")" >/dev/null 2>&1 || m+=("the listener setting could not be read")
    contains "$(cat "$dir/$p-listeners.txt")" "$LISTENER" || m+=("listener not approved")
    contains "$(cat "$dir/$p-dumpsys-notification.txt")" "ComponentInfo{$LISTENER}" || m+=("listener not bound")
    contains_re "$(cat "$dir/$p-qs-tiles.txt")" "custom\\($APP_PKG/(\\.ui|$APP_PKG\\.ui)\\.ClipboardTileService\\)" || m+=("QS tile absent")
    [ "${#m[@]}" -eq 0 ] || { printf '%s; ' "${m[@]}"; return 1; }
}
tee_run() { "$@" 2>&1 | tee -a "$LOG"; RC="${PIPESTATUS[0]}"; }

gate_component() {
    local g=W6-COMPONENT-UPGRADE dir n n1 vn vn1 why v0 v2 a
    need_cfg "$ADB_SERIAL" --adb-serial "the designated Android device's serial"
    need_tool adb || die "adb is not installed"
    [ -n "$(aapt2_bin)" ] || die "aapt2 is not found (PATH or \$ANDROID_HOME/build-tools); the APK versions could not be checked"
    ADBS=(adb -s "$ADB_SERIAL")
    grep -qw "^$ADB_SERIAL" <<<"$(adb devices 2>/dev/null)" || die "adb does not see $ADB_SERIAL"
    dir="$EVIDENCE/w6/component.$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$dir"
    STARTED="$(date -u +%FT%TZ)"; LOG="$dir/run.log"; RC=0; : > "$LOG"
    # Preparation: the APKs, and nothing on the device. No attempt exists until
    # the operator accepts the first device action below, so a problem here is
    # a refusal (the log stays in $dir), and a gate's previous record — a FAIL
    # being retried, say — stays current, unarchived and counted as it was.
    if [ -n "$APK_N" ] || [ -n "$APK_N1" ]; then
        need_cfg "$APK_N" --apk-n "the Pliwee N debug APK"; need_cfg "$APK_N1" --apk-n1 "the Pliwee N+1 debug APK"
        cp "$APK_N" "$dir/apk-N.apk" && cp "$APK_N1" "$dir/apk-N1.apk" || die "could not copy the APKs into $dir; nothing was recorded"
    else
        # N as the tree stands, then N+1 with only versionCode raised through
        # AGP's injected property: the tree's versionCode is never edited. The
        # result is checked below with aapt2, so an ignored property fails.
        tee_run bash -c 'cd "$1" && ./gradlew --max-workers=2 :app:assembleDebug' _ "$ANDROID_DIR"
        [ "$RC" = 0 ] || die "the N build failed (log $LOG); nothing was recorded"
        cp "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" "$dir/apk-N.apk"
        vn="$(apk_fact "$dir/apk-N.apk" versionCode)"
        [ -n "$vn" ] || die "could not read the N versionCode; nothing was recorded"
        tee_run bash -c 'cd "$1" && ./gradlew --max-workers=2 "-Pandroid.injected.version.code=$2" :app:assembleDebug' _ "$ANDROID_DIR" "$((vn + 1))"
        [ "$RC" = 0 ] || die "the N+1 build failed (log $LOG); nothing was recorded"
        cp "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" "$dir/apk-N1.apk"
    fi
    n="$(apk_fact "$dir/apk-N.apk" name)"; n1="$(apk_fact "$dir/apk-N1.apk" name)"
    vn="$(apk_fact "$dir/apk-N.apk" versionCode)"; vn1="$(apk_fact "$dir/apk-N1.apk" versionCode)"
    printf 'N   %s versionCode=%s sha256=%s\nN+1 %s versionCode=%s sha256=%s\n' "$n" "$vn" "$(g7up_sha "$dir/apk-N.apk")" \
        "$n1" "$vn1" "$(g7up_sha "$dir/apk-N1.apk")" | tee -a "$LOG" > "$dir/apks.txt"
    [ "$n" = "$APP_PKG" ] && [ "$n1" = "$APP_PKG" ] || die "the APKs are not both $APP_PKG ($n, $n1); nothing was recorded"
    [ "$vn1" -gt "$vn" ] 2>/dev/null || die "N+1 versionCode '$vn1' is not greater than N's '$vn': it would not be an upgrade; nothing was recorded"

    v0="$(comp_version)"
    confirm_action yes \
        "adb -s $ADB_SERIAL install -r $dir/apk-N.apk          (Pliwee versionCode $vn; installed now: ${v0:-none})" \
        "adb -s $ADB_SERIAL shell cmd notification allow_listener $LISTENER" \
        "adb -s $ADB_SERIAL shell cmd statusbar add-tile $TILE" \
        "then YOU pin a Pliwee launcher shortcut by hand (the launcher asks for confirmation)"
    # Accepted: from here on this is an attempt, and its record replaces
    # (archives) the previous one.
    state_write "$g" "gate=$g" state=RUNNING "started_utc=$STARTED" "log=$LOG"
    tee_run "${ADBS[@]}" install -r "$dir/apk-N.apk"; [ "$RC" = 0 ] || { record "$g" FAIL "installing N failed"; return; }
    tee_run "${ADBS[@]}" shell cmd notification allow_listener "$LISTENER"
    tee_run "${ADBS[@]}" shell cmd statusbar add-tile "$TILE"
    printf '\nOPERATOR: long-press the Pliwee icon, drag one of its shortcuts to the home\nscreen, and accept the launcher'"'"'s confirmation. Leave it visible.\n' >&2
    a="$(ask "Type PINNED once the shortcut is on the home screen:")" || a=""
    echo "operator before upgrade: '$a'" >> "$LOG"
    [ "$a" = PINNED ] || { record "$g" FAIL "the pinned shortcut was not confirmed before the upgrade"; return; }
    sleep 3; comp_observe "$dir" before
    need_exact_count "installed versionCode before the upgrade" "$(cat "$dir/before-versionCode.txt")" "$vn" 2>>"$LOG" \
        || { record "$g" FAIL "N (versionCode $vn) is not what is installed"; return; }
    why="$(comp_holds "$dir" before)" || { record "$g" FAIL "before the upgrade: $why"; return; }
    confirm_action yes "adb -s $ADB_SERIAL install -r $dir/apk-N1.apk          (the upgrade: versionCode $vn -> $vn1)"
    tee_run "${ADBS[@]}" install -r "$dir/apk-N1.apk"; [ "$RC" = 0 ] || { record "$g" FAIL "installing N+1 failed"; return; }
    sleep 5; comp_observe "$dir" after
    v2="$(cat "$dir/after-versionCode.txt")"
    need_ran "the installed versionCode" "$(cat "$dir/before-versionCode.txt")" "$v2" 2>>"$LOG" \
        && need_exact_count "installed versionCode after the upgrade" "$v2" "$vn1" 2>>"$LOG" \
        || { record "$g" FAIL "the upgrade did not happen ($vn -> ${v2:-?})"; return; }
    why="$(comp_holds "$dir" after)" || { record "$g" FAIL "after the upgrade: $why"; return; }
    a="$(yn "Look at the phone (and $dir/after-screen.png): is the SAME pinned shortcut still there, and does tapping it open Pliwee?")"
    echo "operator after upgrade: shortcut survives N -> N+1: $a" >> "$LOG"
    [ "$a" = y ] || { record "$g" FAIL "the operator reports the pinned shortcut did not survive the upgrade"; return; }
    record "$g" PASS "listener, QS tile and pinned shortcut survived versionCode $vn -> $vn1" "evidence_dir=$dir"
}

gate_instrumented() {
    local g=W6-INSTRUMENTED dir mark xmls t=0 f=0 e=0 x k n
    need_cfg "$ADB_SERIAL" --adb-serial "the designated Android device's serial"
    [ -x "$ANDROID_DIR/gradlew" ] || die "$ANDROID_DIR/gradlew is missing"
    dir="$EVIDENCE/w6/instrumented.$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$dir"; mark="$dir/.start"; : > "$mark"
    confirm_action yes \
        "cd $ANDROID_DIR && ANDROID_SERIAL=$ADB_SERIAL ./gradlew --max-workers=2 :app:connectedDebugAndroidTest" \
        "installs the Pliwee debug app and its test APK on $ADB_SERIAL, runs the instrumented suite," \
        "and uninstalls the test APK afterwards (Gradle's own behaviour)."
    sleep 1
    run_logged "$g" env ANDROID_SERIAL="$ADB_SERIAL" bash -c 'cd "$1" && ./gradlew --max-workers=2 :app:connectedDebugAndroidTest' _ "$ANDROID_DIR"
    xmls="$(find "$ANDROID_DIR/app/build/outputs/androidTest-results/connected" -name 'TEST-*.xml' -newer "$mark" 2>/dev/null || true)"
    [ -n "$xmls" ] || { record "$g" FAIL "no test result XML was written by this run"; return; }
    while IFS= read -r x; do
        cp "$x" "$dir/"
        for k in tests failures errors; do
            n="$(sed -n "s/.*<testsuite [^>]*$k=\"\([0-9]*\)\".*/\1/p" "$x" | head -1)"
            [ -n "$n" ] || { record "$g" FAIL "$(basename "$x") has no $k count" "evidence_dir=$dir"; return; }
            case "$k" in tests) t=$((t + n)) ;; failures) f=$((f + n)) ;; errors) e=$((e + n)) ;; esac
        done
    done <<<"$xmls"
    printf 'tests=%s failures=%s errors=%s files=%s\n' "$t" "$f" "$e" "$(grep -c . <<<"$xmls")" > "$dir/counts.txt"
    [ "$RC" = 0 ] || { record "$g" FAIL "Gradle exited $RC" "evidence_dir=$dir"; return; }
    [ "$t" -gt 0 ] || { record "$g" FAIL "the result XML holds zero tests" "evidence_dir=$dir"; return; }
    [ "$f" = 0 ] && [ "$e" = 0 ] || { record "$g" FAIL "$f failure(s), $e error(s) in $t tests" "evidence_dir=$dir"; return; }
    record "$g" PASS "$t tests, 0 failures" "evidence_dir=$dir"
}

gate_g7up() {
    local g="$1" d step dom old new ev ug binding
    d="$(gate_distro "$g")"; step="$(gate_step "$g")"
    dom="$(pd DOMAIN "$d")"; old="$(pd OLD_PKGDIR "$d")"; new="$(pd NEW_PKGDIR "$d")"
    ev="$(chain_dir "$d")"; ug="$GATES_DIR/upgrade-gates.sh"; binding="$ev/BINDING"; REC_DOMAIN="$dom"
    if [ "$step" != U8 ]; then
        need_cfg "$dom" "--distro $d --domain" "the $d upgrade guest (DOMAIN_$d)"
        # Every stage of one chain runs on the guest the chain started on.
        if [ -f "$binding" ] && [ "$(g7up_kv "$binding" domain)" != "$dom" ]; then
            die "the $d chain started on domain '$(g7up_kv "$binding" domain)', not '$dom'; use --reset-distro $d to start over"
        fi
    fi
    case "$step" in
        INSTALL)
            need_cfg "$old" "--distro $d --old-pkgdir" "the published OmniBridge 1.0.0 set for $d (OLD_PKGDIR_$d)"
            need_cfg "$KEYRING" --keyring "the OpenPGP keyring for SHA256SUMS.asc (U1 is not a PASS without it)"
            need_cfg "$FINGERPRINT" --fingerprint "the release signing fingerprint"
            [ ! -e "$ev/UPGRADE-CHECKPOINT" ] || die "$ev already holds an upgraded chain; --reset-distro $d first"
            one_vm "$dom"
            confirm_action yes "$ug --stage install --domain $dom --distro $d --evidence $ev --old-pkgdir $old --keyring $KEYRING --fingerprint $FINGERPRINT" \
                "installs OmniBridge 1.0.0 in guest $dom, enables its user unit, adds a user '${IDLE_USER:-g7idle}'" \
                "and (Fedora) the omnibridge firewalld service in zone 'work'"
            mkdir -p "$ev"; printf 'domain=%s\nold_pkgdir=%s\ndistro=%s\n' "$dom" "$old" "$d" > "$binding"
            run_logged "$g" "$ug" --stage install --domain "$dom" --distro "$d" --evidence "$ev" \
                --old-pkgdir "$old" --keyring "$KEYRING" --fingerprint "$FINGERPRINT"
            finish_gate "$g" '^ok    U1: omnibridge and omnibridge-gui are exactly 1\.0\.0-1$' '^ok    U2: omnibridged\.service is enabled$' ;;
        U2)
            local items=("exactly ONE peer is paired with the guest, and it is the physical Android device used for U6 (not fake_phone)"
                         "clipboard.v1 and files.v1 are granted to it"
                         "a clipboard policy is set for it" "a notification lock policy is set for it"
                         "omnibridge-gui was opened and the peer selected (gui.json written)") i a fails=() f
            f="$ev/U2-operator.txt"; STARTED="$(date -u +%FT%TZ)"; LOG=""; RC=0
            printf '\n%s — in guest %s, by hand (the upgrade stage then measures them in O1):\n' "$g" "$dom" >&2
            : > "$f.partial"
            for i in "${items[@]}"; do a="$(yn "$i")"; echo "$a  $i" >> "$f.partial"; [ "$a" = y ] || fails+=("$i"); done
            echo "recorded_utc=$(date -u +%FT%TZ)" >> "$f.partial"; mv "$f.partial" "$f"
            if [ "${#fails[@]}" -eq 0 ]; then record "$g" PASS "" "answers=$f"
            else record "$g" FAIL "$(printf '%s; ' "${fails[@]}")" "answers=$f"; fi ;;
        UPGRADE)
            need_cfg "$new" "--distro $d --new-pkgdir" "the Pliwee package set for $d (NEW_PKGDIR_$d)"
            need_cfg "$old" "--distro $d --old-pkgdir" "the published OmniBridge 1.0.0 set for $d (OLD_PKGDIR_$d)"
            [ "$(g7up_kv "$binding" old_pkgdir)" = "$old" ] || die "OLD_PKGDIR_$d is not the set the chain was installed from ($(g7up_kv "$binding" old_pkgdir))"
            one_vm "$dom"
            confirm_action yes "$ug --stage upgrade --domain $dom --distro $d --evidence $ev --new-pkgdir $new --old-pkgdir $old" \
                "upgrades guest $dom to Pliwee with the distribution's own command, ends the user's session" \
                "once, restarts pliweed, and STOPS with the guest on Pliwee (no downgrade)"
            run_logged "$g" "$ug" --stage upgrade --domain "$dom" --distro "$d" --evidence "$ev" --new-pkgdir "$new" --old-pkgdir "$old"
            [ "$RC" = 0 ] && ! g7up_verify_checkpoint "$ev" "$d" "$dom" >/dev/null 2>&1 && RC=97
            finish_gate "$g" '^ok    Checkpoint: UPGRADE-CHECKPOINT written for run ' ;;
        U6)
            need_cfg "$PHONE_IP" --phone-ip "the physical Android peer's LAN address"
            one_vm "$dom"
            printf '\nBefore confirming: copy some text on the phone. The phone -> guest half of the\nclipboard round-trip sends what is on the Android clipboard, and adb cannot put it there.\n' >&2
            confirm_action yes "$ug --stage peer-u6 --domain $dom --distro $d --evidence $ev --phone-ip $PHONE_IP${ADB_SERIAL:+ --adb-serial $ADB_SERIAL}" \
                "runs lifecycle-peer-gates.sh against the UPGRADED guest $dom: it drives the Pliwee app on the" \
                "phone over adb (force-stop, taps, grants, notification-source choice, the fixture) and sends a" \
                "clipboard and a file between the phone and the guest"
            run_logged "$g" "$ug" --stage peer-u6 --domain "$dom" --distro "$d" --evidence "$ev" --phone-ip "$PHONE_IP" \
                ${ADB_SERIAL:+--adb-serial "$ADB_SERIAL"}
            # The harness's exit code is not enough: the U6 record must verify.
            if [ "$RC" = 0 ] && ! g7up_verify_u6 "$ev" "$d" "$dom" >>"$LOG" 2>&1; then RC=98; fi
            finish_gate "$g" '^ok    U6: lifecycle-peer-gates\.sh passed against the upgraded guest' ;;
        SECLOG)
            need_cfg "$PHONE_IP" --phone-ip "the physical Android peer's LAN address"
            one_vm "$dom"
            confirm_action yes "$GATES_DIR/security-log-evidence.sh --domain $dom --distro $d --evidence $ev/seclog --phone-ip $PHONE_IP${ADB_SERIAL:+ --adb-serial $ADB_SERIAL}" \
                "puts a TRACE drop-in on pliweed in the UPGRADED guest $dom (removed again at the end)," \
                "restarts it, sends a file and posts a fixture notification from the phone"
            run_logged "$g" "$GATES_DIR/security-log-evidence.sh" --domain "$dom" --distro "$d" --evidence "$ev/seclog" \
                --phone-ip "$PHONE_IP" ${ADB_SERIAL:+--adb-serial "$ADB_SERIAL"}
            finish_gate "$g" ;;
        U10)
            need_cfg "$old" "--distro $d --old-pkgdir" "the published OmniBridge 1.0.0 set for $d (OLD_PKGDIR_$d)"
            # The coordinator's own refusal, before the harness's: U6 verified
            # from the evidence itself, not from a state file saying PASS.
            g7up_verify_u6 "$ev" "$d" "$dom" || die "U10 refused: no verified U6 PASS for $d on $dom in $ev"
            one_vm "$dom"
            confirm_action yes "$ug --stage downgrade --domain $dom --distro $d --evidence $ev --old-pkgdir $old" \
                "REMOVES Pliwee from guest $dom and reinstalls OmniBridge 1.0.0; the upgraded guest is gone afterwards"
            run_logged "$g" "$ug" --stage downgrade --domain "$dom" --distro "$d" --evidence "$ev" --old-pkgdir "$old"
            finish_gate "$g" '^ok    U10: OmniBridge 1\.0\.0 starts on its pre-migration identity$' ;;
        U8)
            local u8; u8="$(pd U8_DOMAIN "$d")"
            need_cfg "$u8" "--distro $d --u8-domain" "a FRESH guest for U8 on $d (U8_DOMAIN_$d)"
            need_cfg "$new" "--distro $d --new-pkgdir" "the Pliwee package set for $d (NEW_PKGDIR_$d)"
            [ "$u8" != "$dom" ] || die "U8 needs a FRESH guest; '$u8' is the $d upgrade guest"
            one_vm "$u8"
            confirm_action "$u8" "$ug --stage negative-unreadable --domain $u8 --distro $d --evidence $EVIDENCE/g7up-u8/$d --new-pkgdir $new" \
                "plants an unreadable ~/.local/share/omnibridge in guest $u8 and installs Pliwee there." \
                "$u8 must be a FRESH guest or snapshot with nothing of OmniBridge or Pliwee on it:" \
                "type its name to designate it."
            run_logged "$g" "$ug" --stage negative-unreadable --domain "$u8" --distro "$d" --evidence "$EVIDENCE/g7up-u8/$d" --new-pkgdir "$new"
            finish_gate "$g" '^ok    U8: the daemon refused and named ' '^ok    U8: no .*/identity\.key was created$' ;;
    esac
}

gate_lifecycle() {
    local g="$1" d lc new
    d="$(gate_distro "$g")"; lc="$(pd LIFECYCLE_DOMAIN "$d")"; new="$(pd NEW_PKGDIR "$d")"
    need_cfg "$lc" "--distro $d --lifecycle-domain" "a FRESH guest for the lifecycle gates on $d (LIFECYCLE_DOMAIN_$d)"
    need_cfg "$new" "--distro $d --new-pkgdir" "the Pliwee package set for $d (NEW_PKGDIR_$d)"
    [ "$lc" != "$(pd DOMAIN "$d")" ] || die "the lifecycle gates install, reboot, remove and purge: they need their own FRESH guest, not the $d upgrade guest"
    one_vm "$lc"
    confirm_action "$lc" "$GATES_DIR/lifecycle-gates.sh --domain $lc --distro $d --pkgdir $new --evidence $EVIDENCE/lifecycle/$d${PHONE_IP:+ --phone $PHONE_IP}" \
        "installs Pliwee in guest $lc, cycles the session, REBOOTS it, then removes, reinstalls and purges." \
        "type the guest's name to designate it."
    run_logged "$g" "$GATES_DIR/lifecycle-gates.sh" --domain "$lc" --distro "$d" --pkgdir "$new" \
        --evidence "$EVIDENCE/lifecycle/$d" ${PHONE_IP:+--phone "$PHONE_IP"}
    finish_gate "$g"
}

run_gate() {
    local g="$1" s
    is_gate "$g" || die "unknown gate '$g' (--list)"
    # Every execution, whatever this gate's own record says — none, RUNNING,
    # INCOMPLETE, NOT_EXECUTED, FAIL or PASS with --rerun: a resumed, retried
    # or not-executed gate waives none of its prerequisites.
    prereq_ok "$g"
    s="$(status "$g")"
    case "${s%%$'\t'*}" in
        PASS|FAIL) [ "$RERUN" = 1 ] || die "$g already has a result (${s%%$'\t'*}); --rerun to run it again (a new attempt: this record is kept under state/history/)" ;;
        BLOCKED)
            case "$(st "$g" state)" in
                RUNNING|INCOMPLETE|NOT_EXECUTED) : ;;
                *) die "$g is blocked: ${s#*$'\t'}" ;;
            esac ;;
    esac
    new_attempt; GATE_RUN="$g"
    note "running $g — $(describe "$g") (attempt $ATTEMPT)"
    case "$g" in
        W2-GNOME) gate_w2 "$g" 'gnome' ;;
        W2-KDE) gate_w2 "$g" 'kde|plasma' ;;
        W6-SIGNING) gate_signing ;;
        W6-COMPONENT-UPGRADE) gate_component ;;
        W6-INSTRUMENTED) gate_instrumented ;;
        G7UP-*) gate_g7up "$g" ;;
        LIFECYCLE-*) gate_lifecycle "$g" ;;
    esac
}

# ------------------------------------------------------------------- main --
# One coordinator at a time on this host, whatever evidence directory it uses:
# two would mean two VMs, builds or device sessions at once.
lock_file="${XDG_RUNTIME_DIR:-/tmp}/pliwee-pre-g8.lock"
case "$CMD" in
    status|list) : ;;
    *)
        need_tool flock || die "flock is not installed"
        exec 9>"$lock_file" || die "cannot open $lock_file"
        flock -n 9 || die "another pre-g8-manual-gates.sh is running (lock $lock_file); one gate at a time"
        ;;
esac

case "$CMD" in
    list) all_gates; exit 0 ;;
    status) print_status ;;
    run) run_gate "$GATE_ARG" ;;
    next)
        # The resume point first: a gate that was interrupted, or stopped
        # half-way on purpose (signing, at the media step). Then the first
        # gate that is PENDING.
        nxt=""
        while IFS= read -r g; do
            case "$(st "$g" state)" in RUNNING|INCOMPLETE) nxt="$g" ;; *) continue ;; esac
            # An interruption resumes only while its prerequisites still hold.
            prereq "$g" >/dev/null && break
            note "$g was interrupted, but it is blocked now; it keeps its record (see --status)"; nxt=""
        done < <(all_gates)
        if [ -z "$nxt" ]; then
            while IFS= read -r g; do
                [ "$(status "$g" | cut -f1)" = PENDING ] && { nxt="$g"; break; }
            done < <(all_gates)
        fi
        if [ -n "$nxt" ]; then run_gate "$nxt"
        else note "no gate is pending; the rest are PASS, FAIL or BLOCKED (see below)"; print_status; fi ;;
    not-executed)
        is_gate "$GATE_ARG" || die "unknown gate '$GATE_ARG'"
        [ -n "${REASON//[[:space:]]/}" ] || die "--not-executed needs --reason TEXT: n/a without a reason is not evidence"
        # Only a gate that never started can be "not executed". A FAIL is a
        # measurement and a RUNNING/INCOMPLETE record is a run that began:
        # neither is replaced. A retry is --rerun, which keeps the old record.
        case "$(st "$GATE_ARG" state)" in
            ""|NOT_EXECUTED) : ;;
            PASS) die "$GATE_ARG has a recorded PASS; it cannot be recorded as not executed" ;;
            FAIL) die "$GATE_ARG has a measured FAIL ($(st "$GATE_ARG" reason)); a FAIL is evidence and --not-executed cannot replace it. To try again: --rerun --run $GATE_ARG, which keeps this record under state/history/" ;;
            *) die "$GATE_ARG was started (record: $(st "$GATE_ARG" state), log $(st "$GATE_ARG" log)); it was executed at least in part and cannot be recorded as not executed. Resume it with --run $GATE_ARG" ;;
        esac
        new_attempt
        state_write "$GATE_ARG" "gate=$GATE_ARG" state=NOT_EXECUTED "reason=$REASON" "finished_utc=$(date -u +%FT%TZ)"
        note "$GATE_ARG recorded NOT EXECUTED (it stays BLOCKED, never PASS): $REASON" ;;
    reset-distro)
        case " ${DISTROS[*]} " in *" $GATE_ARG "*) : ;; *) die "unknown distro '$GATE_ARG'" ;; esac
        aside="$EVIDENCE/superseded/$GATE_ARG.$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$aside/state"
        [ -e "$(chain_dir "$GATE_ARG")" ] && mv "$(chain_dir "$GATE_ARG")" "$aside/g7up"
        for s in INSTALL U2 UPGRADE U6 SECLOG U10; do
            [ -e "$(sf "G7UP-$GATE_ARG-$s")" ] && mv "$(sf "G7UP-$GATE_ARG-$s")" "$aside/state/"
            for h in "$(hdir)/G7UP-$GATE_ARG-$s".*; do
                [ -f "$h" ] && mkdir -p "$aside/state/history" && mv "$h" "$aside/state/history/"
            done
        done
        note "the $GATE_ARG G7-UP chain was moved to $aside (restore the guest's snapshot before --run G7UP-$GATE_ARG-INSTALL)" ;;
esac
summary
