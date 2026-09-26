#!/usr/bin/env bash
# pre-g8-autopilot.sh — runs every automatable pre-G8 gate, in order, and stops
# only where a person is genuinely needed.
#
#   pre-g8-autopilot.sh                 run (or resume) — the normal command
#   pre-g8-autopilot.sh --resume        the same
#   pre-g8-autopilot.sh --status        where things stand (reads only)
#   pre-g8-autopilot.sh --plan          what it would do next, in order (reads only)
#   pre-g8-autopilot.sh --cleanup-vms   stop its guests; remove those whose gates are PASS
#   pre-g8-autopilot.sh --retry GATE    one new attempt of a FAILed G7-UP/lifecycle
#                                       gate (the FAIL is kept in the history), then go on
#   pre-g8-autopilot.sh --template D    prepare (or verify) only distribution D's
#                                       template, then stop: no gate, no coordinator
#   options: --no-wait (stop at the first human step instead of waiting at it),
#            --nic IF (the wired NIC for macvtap), --evidence DIR, --grant-hours N
#
# WHAT IT IS
# ----------
# An orchestrator. It does not measure anything itself and restates no gate's
# assertions: pre-g8-manual-gates.sh remains the source of truth for every
# gate's state, and it runs every gate (`--run GATE`), which runs the gate's
# own script (upgrade-gates.sh, lifecycle-gates.sh, security-log-evidence.sh,
# u2-state-check.sh). What the autopilot adds is everything around the gates
# that an operator used to do by hand:
#
#   * the guests (vm/): official cloud images, verified and cached; one prepared
#     GNOME template per distribution; three disposable qcow2 overlays per
#     distribution (the G7-UP chain, a fresh U8 guest, a fresh lifecycle
#     guest), each with a recorded identity checked before every use;
#   * the packages (lib/autopilot-artifacts.sh): the PUBLISHED OmniBridge 1.0.0
#     release, signature-verified, and Pliwee built from one pinned commit;
#   * the coordinator's --config, derived, never typed;
#   * the phone's current address, read over adb;
#   * the confirmations: ONE authorisation typed at the terminal per 16 hours
#     (the coordinator's grant) instead of one per gate;
#   * U2 through the product's own CLI, with the two things only a person can
#     do — scanning the QR, clicking the peer — measured afterwards.
#
# ORDER. Unattended work first, then the human steps back to back:
#   1. per distribution: U8 and LIFECYCLE on fresh guests (building the image,
#      template and packages each needs first);
#   2. per distribution: INSTALL on the chain guest;
#   3. per distribution: U2 — scan a QR, click the peer;
#   4. per distribution: UPGRADE, U6 (copy a text on the tablet first), SECLOG,
#      U10 — back to back on the same running guest.
# The coordinator's prerequisite graph is not duplicated: it refuses anything
# out of order (U10 without a verified U6, SECLOG after U10, …), and the
# autopilot stops when it does.
#
# IT STOPS on a FAIL (and does not go on to anything else), on a missing
# prerequisite (with the one command that fixes it), and at a human step. It
# NEVER runs W2 or W6 gates (it reports them as manual outstanding), never
# fakes or re-records a result, never deletes evidence, never runs sudo, never
# runs two guests or builds at once, and never touches a VM it did not create.
#
# STATE lives in EVIDENCE/autopilot (default ~/.local/state/pliwee-pre-g8/
# autopilot): records, the journal, per-run console logs, REPORT.md. Images
# are cached under ~/.cache/pliwee-pre-g8. A reboot or Ctrl+C loses nothing:
# the next run reads the coordinator's records and its own, and resumes.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
# shellcheck source=lib/g7up-evidence.sh
. "$HERE/lib/g7up-evidence.sh"
# shellcheck source=lib/guest-agent.sh
. "$HERE/lib/guest-agent.sh"
# shellcheck source=lib/cli-report.sh
. "$HERE/lib/cli-report.sh"
# shellcheck source=lib/autopilot-common.sh
. "$HERE/lib/autopilot-common.sh"
# shellcheck source=lib/autopilot-host.sh
. "$HERE/lib/autopilot-host.sh"
# shellcheck source=lib/autopilot-android.sh
. "$HERE/lib/autopilot-android.sh"
# shellcheck source=lib/autopilot-artifacts.sh
. "$HERE/lib/autopilot-artifacts.sh"
# shellcheck source=lib/autopilot-u2.sh
. "$HERE/lib/autopilot-u2.sh"
# shellcheck source=lib/autopilot-report.sh
. "$HERE/lib/autopilot-report.sh"
# shellcheck source=vm/images.sh
. "$HERE/vm/images.sh"
# shellcheck source=vm/cloud-init.sh
. "$HERE/vm/cloud-init.sh"
# shellcheck source=vm/guests.sh
. "$HERE/vm/guests.sh"

COORD="$HERE/pre-g8-manual-gates.sh"
# shellcheck disable=SC2034  # GATES_DIR is read by lib/autopilot-u2.sh (the U2 pre-check)
GATES_DIR="$HERE"; AP_SELFTEST=0
# Self-test seams. PRE_G8_GATES_DIR points the coordinator (and the U2
# pre-check) at stub gate scripts, which makes every record a self-test record
# that can never count as PASS in a real run. Only then are the fixture
# overrides below honoured; in a real run they are refused, not ignored.
if [ -n "${PRE_G8_GATES_DIR:-}" ]; then
    # shellcheck disable=SC2034  # read by lib/autopilot-u2.sh
    GATES_DIR="$PRE_G8_GATES_DIR"; AP_SELFTEST=1
    ap_selftest_stdin
    AP_RELEASE_FPR="${AP_TEST_RELEASE_FPR:-$AP_RELEASE_FPR}"; AP_RELEASE_SUBKEY="${AP_TEST_RELEASE_SUBKEY:-$AP_RELEASE_SUBKEY}"
else
    for v in AP_RELEASE_BASE_URL AP_PACKAGING_DIR AP_TEST_RELEASE_FPR AP_TEST_RELEASE_SUBKEY \
             AP_IMG_URL_fedora44 AP_IMG_URL_ubuntu2404 AP_IMG_URL_ubuntu2604 AP_IMG_URL_debian13 AP_SYSFS_NET AP_MEMINFO; do
        [ -z "${!v:-}" ] || { printf 'pre-g8-autopilot: REFUSED: %s is a self-test seam; unset it for a real run\n' "$v" >&2; exit 2; }
    done
fi

# ---------------------------------------------------------------- arguments --
CMD=run; EVIDENCE=""; RETRY_GATE=""; AP_NO_WAIT=0; TEMPLATE_DISTRO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --resume) CMD=run; shift ;;
        --status) CMD=status; shift ;;
        --plan) CMD=plan; shift ;;
        --cleanup-vms) CMD=cleanup; shift ;;
        --template) CMD=template; TEMPLATE_DISTRO="${2:?--template needs a distribution}"; shift 2
            ap_abbr "$TEMPLATE_DISTRO" >/dev/null \
                || { echo "pre-g8-autopilot: --template takes one of: ${AP_DISTROS[*]}" >&2; exit 2; } ;;
        --retry) CMD=run; RETRY_GATE="${2:?--retry needs a gate}"; shift 2 ;;
        --no-wait) AP_NO_WAIT=1; shift ;;
        --nic) export AP_NIC="${2:?}"; shift 2 ;;
        --evidence) EVIDENCE="${2:?}"; shift 2 ;;
        --grant-hours) AP_GRANT_HOURS="${2:?}"; shift 2
            [[ "$AP_GRANT_HOURS" =~ ^[0-9]+$ ]] && [ "$AP_GRANT_HOURS" -ge 1 ] && [ "$AP_GRANT_HOURS" -le 48 ] \
                || { echo "pre-g8-autopilot: --grant-hours is 1..48" >&2; exit 2; } ;;
        -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
        *) echo "pre-g8-autopilot: unknown argument '$1' (--help)" >&2; exit 2 ;;
    esac
done
export AP_NO_WAIT
EVIDENCE="${EVIDENCE:-${XDG_STATE_HOME:-$HOME/.local/state}/pliwee-pre-g8}"
case "$EVIDENCE" in /*) : ;; *) echo "pre-g8-autopilot: --evidence must be absolute" >&2; exit 2 ;; esac
case "$EVIDENCE/" in "$REPO/"*) echo "pre-g8-autopilot: the evidence directory must be outside the source tree" >&2; exit 2 ;; esac
AP_STATE="$EVIDENCE/autopilot"; CFG="$AP_STATE/coordinator.conf"
mkdir -p "$AP_STATE/records" || { echo "pre-g8-autopilot: cannot create $AP_STATE" >&2; exit 2; }
# shellcheck disable=SC2034  # written by ap_say/ap_log (lib/autopilot-common.sh)
AP_JOURNAL="$AP_STATE/journal.log"

# ------------------------------------------------- the coordinator's status --
declare -A GS=() GR=()
AP_ALL_GATES=(); AP_RESULT=""
coord() { # ARGS... — the coordinator on this evidence (its stdout+stderr)
    local extra=()
    [ -f "$CFG" ] && extra=(--config "$CFG")
    bash "$COORD" --evidence "$EVIDENCE" "${extra[@]}" "$@"
}
ap_status_refresh() {
    local out line id st reason
    out="$(coord --status 2>&1 </dev/null)" || ap_stop "pre-g8-manual-gates.sh --status failed" "$(tail -3 <<<"$out")"
    AP_ALL_GATES=(); GS=(); GR=()
    while IFS= read -r line; do
        [[ "$line" =~ ^PRE_G8_GATE\ id=([^ ]+)\ state=([A-Z]+)\  ]] || continue
        id="${BASH_REMATCH[1]}"; st="${BASH_REMATCH[2]}"
        reason="${line#* reason=\"}"; reason="${reason%\"}"
        AP_ALL_GATES+=("$id"); GS[$id]="$st"; GR[$id]="$reason"
    done <<<"$out"
    # shellcheck disable=SC2034  # read by lib/autopilot-report.sh
    AP_RESULT="$(sed -n 's/^PRE_G8_RESULT=//p' <<<"$out" | tail -1)"
    [ "${#AP_ALL_GATES[@]}" -ge 37 ] || ap_stop "the coordinator's summary lists ${#AP_ALL_GATES[@]} gates, not the 37 it defines" \
        "Refusing to plan against a summary that is missing gates."
}
ap_gate_state()  { printf '%s' "${GS[$1]:-UNKNOWN}"; }
ap_gate_reason() { printf '%s' "${GR[$1]:-}"; }
ap_gate_own()    { g7up_kv "$EVIDENCE/state/$1" state 2>/dev/null; }   # the record's own state
ap_gate_log()    { g7up_kv "$EVIDENCE/state/$1" log 2>/dev/null; }
ap_describe() {
    case "$1" in
        *-INSTALL) echo "OmniBridge 1.0.0 installed on the chain guest" ;; *-U2) echo "the physical peer paired, granted, policies, GUI selection (measured)" ;;
        *-UPGRADE) echo "upgrade to Pliwee, stop on Pliwee" ;; *-U6) echo "lifecycle-peer-gates.sh against the upgraded guest" ;;
        *-SECLOG) echo "security-log evidence on the upgraded guest" ;; *-U10) echo "downgrade to OmniBridge 1.0.0" ;;
        *-U8) echo "unreadable legacy directory on a fresh guest" ;; LIFECYCLE-*) echo "lifecycle-gates.sh L1-L26 on a fresh guest" ;;
    esac
}

# ----------------------------------------------------------------- the plan --
# ap_plan — the autopilot's gates, in the order it takes them.
ap_plan() {
    local d s
    for d in "${AP_DISTROS[@]}"; do printf '%s\n' "G7UP-$d-U8" "LIFECYCLE-$d"; done
    for d in "${AP_DISTROS[@]}"; do printf '%s\n' "G7UP-$d-INSTALL"; done
    for d in "${AP_DISTROS[@]}"; do printf '%s\n' "G7UP-$d-U2"; done
    for d in "${AP_DISTROS[@]}"; do for s in UPGRADE U6 SECLOG U10; do printf '%s\n' "G7UP-$d-$s"; done; done
}
ap_human_step() {
    case "$1" in
        *-U2) echo "scan the pairing QR with the tablet; select the tablet in OmniBridge's window" ;;
        *-U6) echo "copy a short text on the tablet (adb cannot)" ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------ the coordinator config --
ap_write_config() {
    local d new tmp
    tmp="$CFG.new.$$"
    {
        echo "# Generated by pre-g8-autopilot.sh at $(ap_utc); regenerated every run. Not a place for edits."
        echo "# Consumed by: pre-g8-manual-gates.sh --config $CFG"
        for d in "${AP_DISTROS[@]}"; do
            printf 'DOMAIN_%s=%q\nU8_DOMAIN_%s=%q\nLIFECYCLE_DOMAIN_%s=%q\n' \
                "$d" "$(ap_domain "$d" chain)" "$d" "$(ap_domain "$d" u8)" "$d" "$(ap_domain "$d" lc)"
            [ -n "${OLD_LAYOUT:-}" ] && printf 'OLD_PKGDIR_%s=%q\n' "$d" "$OLD_LAYOUT"
            new="$(ap_rec_get "artifacts-new-$d" pkgdir 2>/dev/null)"
            [ -n "$new" ] && printf 'NEW_PKGDIR_%s=%q\n' "$d" "$new"
        done
        [ -n "${OLD_KEYRING:-}" ] && printf 'KEYRING=%q\nFINGERPRINT=%q\n' "$OLD_KEYRING" "$AP_RELEASE_FPR"
        [ -n "${PHONE_IP:-}" ] && printf 'PHONE_IP=%q\n' "$PHONE_IP"
        printf 'ADB_SERIAL=%q\nGUEST_USER=%q\nGUEST_UID=%q\n' "$AP_PHONE_SERIAL" "$AP_GUEST_USER" "$AP_GUEST_UID"
    } > "$tmp" || ap_stop "cannot write $tmp"
    if [ -f "$CFG" ] && ! cmp -s <(grep -v '^#' "$CFG") <(grep -v '^#' "$tmp"); then
        mkdir -p "$AP_STATE/config-history"
        mv "$CFG" "$AP_STATE/config-history/coordinator.conf.$(ap_stamp)" || ap_stop "cannot keep the previous $CFG"
    fi
    if [ -f "$CFG" ]; then rm -f "$tmp"; else mv "$tmp" "$CFG"; fi
}

# ------------------------------------------------------- running one gate --
AP_CHILD=""
# ap_coord_run GATE [COORDINATOR OPTIONS...] — the coordinator runs the gate.
# In its own session (no controlling terminal): if the grant does not cover a
# confirmation, the coordinator refuses rather than waiting at a prompt nobody
# sees. Its console goes to the run directory, not the terminal.
ap_coord_run() {
    local g="$1" log rc started elapsed=0 next=300 okn bad; shift
    log="$AP_RUN/$g.console.$(ap_stamp).log"
    ap_say RUN "$g — $(ap_describe "$g")"
    ap_detail "console: $log"
    started="$(date +%s)"
    setsid bash "$COORD" --evidence "$EVIDENCE" --config "$CFG" "$@" --run "$g" </dev/null >"$log" 2>&1 8>&- &
    AP_CHILD=$!
    while kill -0 "$AP_CHILD" 2>/dev/null; do
        sleep "$(( ${AP_POLL:-30} < 10 ? ${AP_POLL:-30} : 10 ))"
        elapsed=$(( $(date +%s) - started ))
        if [ "$elapsed" -ge "$next" ]; then
            okn="$(grep -c '^ok ' "$log" 2>/dev/null || true)"; bad="$(grep -c '^not ok' "$log" 2>/dev/null || true)"
            ap_say INFO "$g — running ${elapsed}s: ${okn:-0} ok, ${bad:-0} not ok so far"
            next=$(( next + 300 ))
        fi
    done
    wait "$AP_CHILD"; rc=$?; AP_CHILD=""
    AP_COORD_RC="$rc"; AP_COORD_LOG="$log"
}

# ap_preserve WHAT DIR — copy a harness directory an interrupted attempt wrote
# into, before a new attempt writes into it again. Copy, never move.
ap_preserve() {
    local dst
    [ -e "$2" ] || return 0
    dst="$AP_STATE/preserved/$1.$(ap_stamp)"
    mkdir -p "$dst" && cp -a "$2" "$dst/" || ap_stop "cannot preserve $2 before resuming $1"
    ap_say INFO "the interrupted attempt's files in $2 were copied to $dst"
}

# ap_prepare_gate GATE — everything a gate needs before the coordinator runs
# it, and the recovery of an interrupted attempt. Sets GUEST and RERUN.
ap_prepare_gate() {
    local g="$1" d role step own st
    d="$(ap_gate_distro "$g")"; role="$(ap_gate_role "$g")"; step="${g##*-}"
    [[ "$g" == LIFECYCLE-* ]] && step=LIFECYCLE
    own="$(ap_gate_own "$g")"; st="$(ap_gate_state "$g")"
    RERUN=()
    [ "$st" = FAIL ] && [ "$g" = "$RETRY_GATE" ] && RERUN=(--rerun)
    case "$step" in INSTALL|UPGRADE|U10) ap_old_set_ensure ;; esac
    case "$step" in U8|LIFECYCLE|UPGRADE) ap_new_set_ensure "$d" ;; esac
    ap_guest_ensure "$d" "$role"
    # The coordinator passes PHONE_IP to these gates; it is read fresh, never remembered.
    case "$step" in LIFECYCLE|U6|SECLOG) ap_phone_detect ;; esac
    ap_write_config
    case "$step" in
        U8|LIFECYCLE|INSTALL)
            if [ "$own" = RUNNING ] || [ "$own" = INCOMPLETE ]; then
                case "$step" in U8) ap_preserve "$g" "$EVIDENCE/g7up-u8/$d" ;; LIFECYCLE) ap_preserve "$g" "$EVIDENCE/lifecycle/$d" ;;
                                INSTALL) ap_preserve "$g" "$EVIDENCE/g7up/$d" ;; esac
            fi
            if ! ap_guest_is_fresh "$GUEST"; then
                ap_guest_revert "$GUEST" ap-fresh "$g needs a guest no gate has used (last used by $(ap_rec_get "$(ap_guest_rec "$GUEST")" used_by 2>/dev/null))"
            fi ;;
        UPGRADE)
            if [ "$own" = RUNNING ]; then
                [ ! -e "$EVIDENCE/g7up/$d/UPGRADE-CHECKPOINT" ] \
                    || ap_stop "$g was interrupted AFTER its checkpoint was written" \
                        "The coordinator never recorded the result, and upgrade-gates.sh refuses a second upgrade in the same chain." \
                        "This cannot be resumed automatically. Decide: inspect $EVIDENCE/g7up/$d, then start the $d chain over with" \
                        "  pre-g8-manual-gates.sh --config $CFG --reset-distro $d   (moves it aside; nothing deleted)" \
                        "and resume the autopilot (it reverts $GUEST to ap-fresh before INSTALL)."
                ap_preserve "$g" "$EVIDENCE/g7up/$d"
                ap_guest_revert "$GUEST" ap-pre-upgrade "$g was interrupted; the upgrade starts again from the U2 state"
            else
                ap_guest_snapshot "$GUEST" ap-pre-upgrade "pre-g8-autopilot: after U2 PASS, before the first UPGRADE"
            fi ;;
        SECLOG) [ "$own" = RUNNING ] && ap_preserve "$g" "$EVIDENCE/g7up/$d/seclog" ;;
    esac
}

# ap_next_uses_same GATE — the next gate in the plan runs on the same guest.
ap_next_uses_same() {
    local g="$1" next="" found=0 x
    while IFS= read -r x; do
        [ "$found" = 1 ] && [ "$(ap_gate_state "$x")" != PASS ] && { next="$x"; break; }
        [ "$x" = "$g" ] && found=1
    done < <(ap_plan)
    [ -n "$next" ] && [ "$(ap_domain "$(ap_gate_distro "$g")" "$(ap_gate_role "$g")")" = "$(ap_domain "$(ap_gate_distro "$next")" "$(ap_gate_role "$next")")" ]
}

ap_run_gate() {
    local g="$1" d role step st
    d="$(ap_gate_distro "$g")"; role="$(ap_gate_role "$g")"; step="${g##*-}"
    ap_prepare_gate "$g"
    ap_guest_start "$GUEST"
    case "$step" in
        U2) ap_u2_assist "$d" "$GUEST" ;;
        U6) ap_u6_checkpoint "$d" "$GUEST" ;;
        SECLOG) ap_seclog_checkpoint "$d" "$GUEST" ;;
    esac
    case "$role" in u8|lc) ap_guest_mark_used "$GUEST" "$g" ;; esac
    [ "$step" = INSTALL ] && ap_guest_mark_used "$GUEST" "$g"
    local opts=("${RERUN[@]}"); [ "$step" = U2 ] && opts+=(--u2-measured)
    ap_coord_run "$g" "${opts[@]}"
    ap_status_refresh
    st="$(ap_gate_state "$g")"
    case "$st" in
        PASS)
            ap_say PASS "$g"
            ap_detail "log: $(ap_gate_log "$g")"
            ap_next_uses_same "$g" || ap_guest_shutdown_or_stop "$GUEST" ;;
        FAIL)
            ap_guest_shutdown "$GUEST" || true
            ap_finish FAIL "$g — $(ap_gate_reason "$g")" \
                "gate log:  $(ap_gate_log "$g")" "console:   $AP_COORD_LOG" \
                "evidence:  $(ap_gate_evidence "$g")" \
                "Nothing after it was run. The FAIL is recorded and kept; $GUEST was shut down, not reverted." \
                "To try again after investigating: pre-g8-autopilot.sh --retry $g" ;;
        *)
            ap_finish STOP "$g did not run to a result (coordinator exit $AP_COORD_RC; state $st)" \
                "$(ap_gate_reason "$g")" "$(grep -E 'REFUSED|PRECONDITION' "$AP_COORD_LOG" | tail -3)" \
                "console: $AP_COORD_LOG" ;;
    esac
}

# --------------------------------------------------------------- lifecycle --
ap_on_finish() { # KIND MESSAGE — from ap_finish; --status and --plan only read
    case "$CMD" in run|cleanup) : ;; *) return 0 ;; esac
    [ "${#AP_ALL_GATES[@]}" -gt 0 ] || return 0
    ap_status_refresh_quiet
    ap_report_write "$1" "$2"
    [ "$CMD" = run ] && ap_final_summary
}
ap_status_refresh_quiet() {
    local out line id st reason
    out="$(coord --status 2>&1 </dev/null)" || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^PRE_G8_GATE\ id=([^ ]+)\ state=([A-Z]+)\  ]] || continue
        id="${BASH_REMATCH[1]}"; st="${BASH_REMATCH[2]}"; reason="${line#* reason=\"}"
        GS[$id]="$st"; GR[$id]="${reason%\"}"
    done <<<"$out"
    # shellcheck disable=SC2034  # read by lib/autopilot-report.sh
    AP_RESULT="$(sed -n 's/^PRE_G8_RESULT=//p' <<<"$out" | tail -1)"
}
ap_on_interrupt() {
    trap - INT TERM HUP
    if [ -n "$AP_CHILD" ]; then
        kill -INT -- "-$AP_CHILD" 2>/dev/null || kill -INT "$AP_CHILD" 2>/dev/null
        sleep 2; kill -TERM -- "-$AP_CHILD" 2>/dev/null || true
        wait "$AP_CHILD" 2>/dev/null
    fi
    local d
    while IFS= read -r d; do
        ap_is_ours "$d" && ap_virsh shutdown "$d" >/dev/null 2>&1 && ap_log "asked $d to shut down (interrupt)"
    done < <(ap_running_domains 2>/dev/null)
    ap_finish INT "interrupted — nothing was deleted; the interrupted gate stays recorded as such" \
        "Resume with: packaging/tests/pre-g8-autopilot.sh --resume" \
        "Any running autopilot guest was asked to shut down (ACPI)."
}

ap_report_manual() {
    local g s
    for g in "${AP_ALL_GATES[@]}"; do
        ap_manual_gate "$g" || continue
        s="$(ap_gate_state "$g")"
        case "$g:$s" in
            W6-*:PASS) ap_say PASS "$g — recorded; never re-run by the autopilot" ;;
            *:PASS) ap_say PASS "$g" ;;
            *) ap_say SKIP "$g — manual, $s: $(ap_gate_reason "$g" | cut -c1-90)" ;;
        esac
    done
}

cmd_run() {
    local g st own n_todo=0
    ap_take_locks
    AP_SESSION_ID="$(ap_stamp)-$$"; AP_RUN="$AP_STATE/runs/$AP_SESSION_ID"; mkdir -p "$AP_RUN"
    ap_log "=== run $AP_SESSION_ID (commit $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null), selftest=$AP_SELFTEST)"
    trap ap_on_interrupt INT TERM HUP
    ap_host_prereqs
    ap_host_info > "$AP_RUN/host.txt" 2>/dev/null
    local host_lines=()
    mapfile -t host_lines < "$AP_RUN/host.txt"
    ap_detect_nic
    ap_rec_put host "${host_lines[@]}" "nic=$NIC" >/dev/null 2>&1 || true
    ap_status_refresh
    ap_report_manual
    if [ -n "$RETRY_GATE" ]; then
        ap_owned_gate "$RETRY_GATE" || ap_stop "--retry $RETRY_GATE: the autopilot retries only G7-UP and lifecycle gates"
        [ "$(ap_gate_state "$RETRY_GATE")" = FAIL ] || ap_stop "--retry $RETRY_GATE: it is $(ap_gate_state "$RETRY_GATE"), not FAIL"
    fi
    # A FAIL anywhere in the autopilot's gates stops everything, before any work.
    for g in $(ap_plan); do
        [ "$(ap_gate_state "$g")" = FAIL ] && [ "$g" != "$RETRY_GATE" ] && \
            ap_finish FAIL "$g — $(ap_gate_reason "$g")" "gate log: $(ap_gate_log "$g")" \
                "evidence: $(ap_gate_evidence "$g")" \
                "The autopilot will not run anything else until this is decided. After investigating:" \
                "  pre-g8-autopilot.sh --retry $g      (a new attempt; this FAIL stays in the history)"
        [ "$(ap_gate_state "$g")" = PASS ] || n_todo=$((n_todo + 1))
    done
    [ "$n_todo" -gt 0 ] || ap_finish DONE "every G7-UP and lifecycle gate is PASS; nothing is left for the autopilot"
    ap_grant_ensure || {
        ap_finish WAIT "the gates need your one-time authorisation, typed at a terminal" \
            "Run pre-g8-autopilot.sh at a terminal (without --no-wait); it lists every action and asks once."
    }
    ap_old_set_ensure
    for g in $(ap_plan); do
        st="$(ap_gate_state "$g")"; own="$(ap_gate_own "$g")"
        case "$st" in
            PASS) ap_say PASS "$g"; continue ;;
            FAIL) [ "$g" = "$RETRY_GATE" ] || ap_finish FAIL "$g — $(ap_gate_reason "$g")" ;;
            BLOCKED)
                case "$own" in
                    RUNNING|INCOMPLETE) ap_say INFO "$g was interrupted earlier ($(ap_gate_reason "$g" | cut -c1-80)); resuming it" ;;
                    *) ap_finish STOP "$g is BLOCKED: $(ap_gate_reason "$g")" \
                           "The coordinator will not run it yet; the autopilot does not work around that." ;;
                esac ;;
        esac
        ap_run_gate "$g"
        [ "$g" = "$RETRY_GATE" ] && RETRY_GATE=""
    done
    ap_finish DONE "all automatable pre-G8 work is done"
}

cmd_status() {
    local g s next="" h
    ap_status_refresh
    printf '%-28s %-8s %s\n' GATE STATE DETAIL
    for g in "${AP_ALL_GATES[@]}"; do
        printf '%-28s %-8s %s\n' "$g" "$(ap_gate_state "$g")" "$(ap_gate_reason "$g" | cut -c1-100)"
    done
    for g in $(ap_plan); do [ "$(ap_gate_state "$g")" = PASS ] || { next="$g"; break; }; done
    echo
    if ap_rec_has last-stop; then
        echo "last stop:  $(ap_rec_get last-stop kind) — $(ap_rec_get last-stop message) ($(ap_rec_get last-stop recorded_utc))"
    fi
    if [ -n "$next" ]; then
        h="$(ap_human_step "$next")" && echo "next:       $next — needs you: $h" || echo "next:       $next (automatic)"
    else echo "next:       nothing — every autopilot gate is PASS"; fi
    ap_eligibility
    echo "G8 eligible: $G8_ELIGIBLE"
    [ "$G8_ELIGIBLE" = YES ] || printf '%s' "$G8_WHY" | sed 's/^/  /'
}

cmd_plan() {
    local g s d h n=0 prep
    ap_status_refresh
    echo "Order the autopilot takes (G7-UP and lifecycle only; W2/W6 are the operator's):"
    for g in $(ap_plan); do
        n=$((n + 1)); s="$(ap_gate_state "$g")"; d="$(ap_gate_distro "$g")"; prep=""
        [ "$s" = PASS ] && { printf '%2d. [DONE] %s\n' "$n" "$g"; continue; }
        ap_rec_has "template-$d" && [ "$(ap_rec_get "template-$d" state)" = ready ] || prep+=" image+template($d)"
        case "$g" in *-U8|LIFECYCLE-*|*-UPGRADE) ap_rec_has "artifacts-new-$d" || prep+=" pliwee-build($d)" ;; esac
        ap_rec_has "$(ap_guest_rec "$(ap_domain "$d" "$(ap_gate_role "$g")")")" || prep+=" guest($(ap_domain "$d" "$(ap_gate_role "$g")"))"
        if h="$(ap_human_step "$g")"; then printf '%2d. [WAIT] %s — you: %s' "$n" "$g" "$h"
        else printf '%2d. [AUTO] %s' "$n" "$g"; fi
        [ "$s" = PENDING ] || printf ' (now %s)' "$s"
        [ -z "$prep" ] || printf ' — first:%s' "$prep"
        printf '\n'
    done
    echo
    echo "Manual, never run by the autopilot:"
    for g in "${AP_ALL_GATES[@]}"; do ap_manual_gate "$g" && printf '    %-22s %s\n' "$g" "$(ap_gate_state "$g")"; done
}

# cmd_template — the one distribution's template, as infrastructure only: the
# coordinator is not called, no gate is run or recorded, no grant is needed
# (no gate acts on a guest), and no other guest is created.
cmd_template() {
    local d="$TEMPLATE_DISTRO"
    ap_take_locks
    AP_SESSION_ID="$(ap_stamp)-$$"; AP_RUN="$AP_STATE/runs/$AP_SESSION_ID"; mkdir -p "$AP_RUN"
    ap_log "=== template $d $AP_SESSION_ID (commit $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null), selftest=$AP_SELFTEST)"
    trap ap_on_interrupt INT TERM HUP
    ap_host_prereqs
    ap_detect_nic
    ap_template_ensure "$d"
    ap_finish DONE "TEMPLATE-$d is ready ($(ap_rec_get "template-$d" volume)); no gate was run or recorded" \
        "readiness: $(ap_rec_get "template-$d" readiness 2>/dev/null || echo "(verified earlier: $(ap_rec_get "template-$d" built_utc))")"
}

cmd_cleanup() {
    ap_take_locks
    AP_SESSION_ID="$(ap_stamp)-$$"; AP_RUN="$AP_STATE/runs/$AP_SESSION_ID"; mkdir -p "$AP_RUN"
    ap_status_refresh
    ap_cleanup_vms
    ap_say DONE "cleanup finished; no evidence was touched"
}

case "$CMD" in
    run) cmd_run ;;
    status) cmd_status ;;
    plan) cmd_plan ;;
    cleanup) cmd_cleanup ;;
    template) cmd_template ;;
esac
