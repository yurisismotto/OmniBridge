#!/usr/bin/env bash
# g7up-evidence.sh — the records that chain the G7-UP stages together, and the
# check that U10 may only run after a real U6 on the same guest.
#
# WHY THIS EXISTS
# ---------------
# The rebrand plan §3 puts U6 (the peer reconnects without re-pairing, a
# clipboard round-trip, a file transfer) against the UPGRADED Pliwee guest,
# BEFORE U10 downgrades it. Until the pre-G8 gate hardening, the upgrade stage
# of upgrade-gates.sh recorded U6 as n/a and went straight on to U10: by the
# time anyone could run lifecycle-peer-gates.sh the guest was OmniBridge 1.0.0
# again, and U6 could no longer be measured in the order the gate defines. A
# gate that cannot be executed in its own order is a gate that never passes
# honestly.
#
# The stages are now separate processes, so something has to carry "U6 really
# ran, on this guest, after this upgrade" from one to the next. A file that
# merely exists is not that: an empty file, a hand-written "PASS", or a U6 run
# against another distribution's guest would all look alike to `test -f`. This
# library writes and verifies records that bind each stage to the one before:
#
#   UPGRADE-CHECKPOINT   written by --stage upgrade when it STOPS: the run id,
#                        the distro and domain, the guest's machine-id and the
#                        local fingerprint it showed after the upgrade, the
#                        digest of the O1 facts, and the digest of the old
#                        1.0.0 SHA256SUMS the downgrade must use.
#   U6-RESULT            written by --stage peer-u6: the same run id and guest
#                        identity, re-read live, lifecycle-peer-gates.sh's exit
#                        code, and the digests of its log and identity record.
#
# g7up_verify_u6 accepts only a U6 whose every link holds. It is the refusal
# U10 stands behind, and packaging/tests/harness-selftests.sh proves it rejects
# a missing, empty, forged, altered, wrong-domain and wrong-distro U6.
#
# Every function prints its reason with _af (lib/assert.sh) and returns
# non-zero; none exits.

# shellcheck source=assert.sh
[ -n "${PLIWEE_ASSERT_SH:-}" ] || . "$(dirname -- "${BASH_SOURCE[0]}")/assert.sh"

G7UP_CHECKPOINT=UPGRADE-CHECKPOINT
G7UP_U6_RESULT=U6-RESULT
G7UP_U6_DIR=U6
G7UP_U6_LOG=U6/lifecycle-peer-gates.log
G7UP_U6_IDENTITY=U6/29-peer-identity.txt
G7UP_U6_XFER_JOURNAL=U6/43b-L15-journal.txt
G7UP_U10_STARTED=U10-STARTED

# The lines lifecycle-peer-gates.sh prints only when the U6 observations were
# actually made. Each is an `ok` line the harness emits after measuring, never
# before; together they are the plan's U6 row:
#
#   no re-pairing        the phone was ALREADY paired with this guest -- the
#                        pairing made on OmniBridge 1.0.0 survived the upgrade
#   reconnect            the phone connected, and the newest session event is
#                        this peer's establishment
#   same fingerprint     the phone shows this guest's fingerprint
#   clipboard both ways  guest -> phone received AND phone -> guest arrived.
#                        The phone -> guest direction is n/a when the Android
#                        clipboard is empty; an n/a there is NOT a round-trip,
#                        so U6 is not PASS without it
#   a file               the guest reports the transfer completed, and the
#                        daemon journal names this transfer's id
G7UP_U6_ANCHORS=(
    '^ok    the phone is already paired with this guest; no operator action needed$'
    '^ok    the phone is connected to '
    "^ok    the newest session event is this peer's establishment"
    "^ok    the phone shows this guest's fingerprint "
    '^ok    L14: guest -> phone clipboard send exited 0$'
    "^ok    L14: the phone shows 'Clipboard from "
    '^ok    L14: phone -> guest (arrived|recorded in the guest journal)'
    '^ok    L15: the guest reports the transfer completed$'
    '^ok    L15: [0-9]+ journal line\(s\) name transfer=[0-9a-f]{8} specifically$'
    '^ok    L15: the guest journal records the peer confirming it stored THIS transfer$'
)

# g7up_kv FILE KEY — the value of KEY in a key=value record, exactly one line.
g7up_kv() {
    local file="$1" key="$2" n
    n="$(grep -c "^$key=" "$file" 2>/dev/null || true)"
    [ "${n:-0}" = 1 ] || return 1
    sed -n "s/^$key=//p" "$file"
}

g7up_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# g7up_verify_checkpoint EVIDENCE DISTRO DOMAIN — the upgrade stage completed,
# on this distro and this domain.
g7up_verify_checkpoint() {
    local ev="$1" distro="$2" domain="$3" cp v k
    cp="$ev/$G7UP_CHECKPOINT"
    [ -f "$cp" ] || { _af "no $G7UP_CHECKPOINT in $ev: the upgrade stage has not completed here"; return 1; }
    need_nonempty "$G7UP_CHECKPOINT" "$(cat "$cp")" 8 || return 1
    [ "$(g7up_kv "$cp" stage)" = upgrade ] || { _af "$G7UP_CHECKPOINT is not an upgrade-stage record"; return 1; }
    [ "$(g7up_kv "$cp" status)" = complete ] || { _af "$G7UP_CHECKPOINT does not say the upgrade stage completed"; return 1; }
    v="$(g7up_kv "$cp" distro)"
    [ "$v" = "$distro" ] || { _af "$G7UP_CHECKPOINT is for distro '${v:-<none>}', not '$distro'"; return 1; }
    v="$(g7up_kv "$cp" domain)"
    [ "$v" = "$domain" ] || { _af "$G7UP_CHECKPOINT is for domain '${v:-<none>}', not '$domain'"; return 1; }
    for k in run_id guest_machine_id guest_fingerprint o1_facts_sha256 old_sha256sums_sha256 completed_epoch; do
        v="$(g7up_kv "$cp" "$k")"
        [ -n "$v" ] || { _af "$G7UP_CHECKPOINT has no '$k'"; return 1; }
    done
    [ -f "$ev/O1-facts.txt" ] && [ "$(g7up_sha "$ev/O1-facts.txt")" = "$(g7up_kv "$cp" o1_facts_sha256)" ] \
        || { _af "O1-facts.txt is missing or is not the file the upgrade stage recorded"; return 1; }
}

# g7up_verify_u6_log LOG DISTRO DOMAIN — lifecycle-peer-gates.sh's own output
# carries every U6 observation, no failure, and the tally for this guest.
g7up_verify_u6_log() {
    local log="$1" distro="$2" domain="$3" text a n tally
    [ -f "$log" ] || { _af "no U6 log at $log"; return 1; }
    text="$(cat "$log")"
    need_nonempty "the U6 log" "$text" 20 || return 1
    if contains "$text" "PRECONDITION FAILED"; then
        _af "the U6 log records a PRECONDITION FAILED: lifecycle-peer-gates.sh stopped before measuring"; return 1
    fi
    n="$(grep -c '^not ok' <<<"$text" || true)"
    need_exact_count "failed checks in the U6 log" "$n" 0 || return 1
    # Matched as a fixed prefix: a domain name is not a regular expression.
    tally="$(awk -v p="$distro / $domain: " 'index($0, p) == 1 && $0 ~ /: [0-9]+ passed, [0-9]+ failed, [0-9]+ n\/a$/' <<<"$text")"
    [ -n "$tally" ] || { _af "the U6 log has no '$distro / $domain' tally: it was not measured on this guest"; return 1; }
    need_exact_count "the '$distro / $domain' tally lines in the U6 log" "$(grep -c . <<<"$tally" || true)" 1 || return 1
    contains_re "$tally" ': [1-9][0-9]* passed, 0 failed, ' \
        || { _af "the U6 tally is not a pass: $tally"; return 1; }
    for a in "${G7UP_U6_ANCHORS[@]}"; do
        contains_re "$text" "$a" \
            || { _af "the U6 log has no line matching /$a/: that U6 observation was not made"; return 1; }
    done
}

# g7up_verify_u6 EVIDENCE DISTRO DOMAIN — the U6 this directory holds is real,
# passed, and belongs to the upgrade checkpoint in the same directory.
g7up_verify_u6() {
    local ev="$1" distro="$2" domain="$3" cp r v k xfer jf idf
    g7up_verify_checkpoint "$ev" "$distro" "$domain" || return 1
    cp="$ev/$G7UP_CHECKPOINT"; r="$ev/$G7UP_U6_RESULT"
    [ "$(g7up_kv "$cp" upgrade_not_ok)" = 0 ] \
        || { _af "the upgrade stage recorded '$(g7up_kv "$cp" upgrade_not_ok)' failed check(s); no U6 on that run can be a PASS"; return 1; }
    [ -f "$r" ] || { _af "no $G7UP_U6_RESULT in $ev: U6 has not been run against the upgraded guest"; return 1; }
    need_nonempty "$G7UP_U6_RESULT" "$(cat "$r")" 10 || return 1
    [ "$(g7up_kv "$r" stage)" = peer-u6 ] || { _af "$G7UP_U6_RESULT is not a peer-u6 record"; return 1; }
    v="$(g7up_kv "$r" distro)"
    [ "$v" = "$distro" ] || { _af "$G7UP_U6_RESULT was recorded for distro '${v:-<none>}', not '$distro'"; return 1; }
    v="$(g7up_kv "$r" domain)"
    [ "$v" = "$domain" ] || { _af "$G7UP_U6_RESULT was recorded for domain '${v:-<none>}', not '$domain'"; return 1; }
    for k in run_id guest_machine_id guest_fingerprint; do
        v="$(g7up_kv "$r" "$k")"
        [ -n "$v" ] && [ "$v" = "$(g7up_kv "$cp" "$k")" ] \
            || { _af "$G7UP_U6_RESULT $k '${v:-<none>}' is not the upgrade checkpoint's '$(g7up_kv "$cp" "$k")'"; return 1; }
    done
    v="$(g7up_kv "$r" started_epoch)"
    [ -n "$v" ] && [ "$v" -ge "$(g7up_kv "$cp" completed_epoch)" ] 2>/dev/null \
        || { _af "U6 did not start after the upgrade stage completed (started ${v:-<none>})"; return 1; }
    [ "$(g7up_kv "$r" exit)" = 0 ] || { _af "lifecycle-peer-gates.sh exited $(g7up_kv "$r" exit) in U6"; return 1; }
    [ "$(g7up_kv "$r" verdict)" = PASS ] || { _af "$G7UP_U6_RESULT verdict is '$(g7up_kv "$r" verdict)'"; return 1; }
    [ "$(g7up_sha "$ev/$G7UP_U6_LOG")" = "$(g7up_kv "$r" log_sha256)" ] \
        || { _af "the U6 log is missing or is not the one $G7UP_U6_RESULT recorded"; return 1; }
    g7up_verify_u6_log "$ev/$G7UP_U6_LOG" "$distro" "$domain" || return 1
    idf="$ev/$G7UP_U6_IDENTITY"
    [ "$(g7up_sha "$idf")" = "$(g7up_kv "$r" identity_sha256)" ] \
        || { _af "the U6 identity record is missing or is not the one $G7UP_U6_RESULT recorded"; return 1; }
    v="$(sed -n 's/^distro  *//p' "$idf")"
    [ "$v" = "$distro" ] || { _af "lifecycle-peer-gates.sh measured distro '${v:-<none>}', not '$distro'"; return 1; }
    v="$(sed -n 's/^domain  *//p' "$idf")"
    [ "$v" = "$domain" ] || { _af "lifecycle-peer-gates.sh measured domain '${v:-<none>}', not '$domain'"; return 1; }
    v="$(sed -n 's/^fingerprint  *//p' "$idf")"
    [ "$v" = "$(g7up_kv "$cp" guest_fingerprint)" ] \
        || { _af "the peer gates saw fingerprint '${v:-<none>}', not the upgraded guest's '$(g7up_kv "$cp" guest_fingerprint)'"; return 1; }
    xfer="$(sed -n 's/^ok    L15: [0-9]* journal line(s) name transfer=\([0-9a-f]\{8\}\) specifically$/\1/p' "$ev/$G7UP_U6_LOG" | tail -1)"
    jf="$(cat "$ev/$G7UP_U6_XFER_JOURNAL" 2>/dev/null || true)"
    need_window_covers "the U6 transfer journal" "$jf" "transfer=$xfer" || return 1
}
