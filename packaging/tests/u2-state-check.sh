#!/usr/bin/env bash
# u2-state-check.sh — G7-UP U2, observed: the state U2 asks for on the
# OmniBridge 1.0.0 guest, BEFORE the upgrade, measured instead of attested.
#
# upgrade-gates.sh --stage install stops for the half of U2 that needs the
# phone: pair the PHYSICAL Android peer (U6 later measures "reconnects without
# re-pairing" with this pairing, so fake_phone cannot stand in), grant
# clipboard.v1 and files.v1, set a clipboard policy and a notification lock
# policy, and select the peer in omnibridge-gui. pre-g8-manual-gates.sh
# records that as five items. By default the operator answers them y/n; with
# --u2-measured the coordinator runs this script and takes each item from the
# line printed here for it:
#
#   U2-1  exactly ONE peer is paired, it reports platform android, and it is
#         the device adb has attached under --adb-serial (its model is the
#         peer's name, as the Android app announces itself)
#   U2-2  clipboard.v1 AND files.v1 are granted to that peer
#   U2-3  a clipboard policy is set for it: the policy line the daemon reports
#         for THAT peer carries --expect-clipboard (default send=on receive=on)
#   U2-4  a notification lock policy is set for it: the daemon reports
#         `when locked` --expect-when-locked (default full) for THAT peer
#   U2-5  omnibridge-gui wrote gui.json, and its selected_peer is that peer's
#         fingerprint: the 16 hex digits the daemon shows are the start of the
#         64 the GUI stored. The GUI writes this file only when a person
#         selects the peer; nothing here writes it
#
# IT CHANGES NOTHING. Guest reads go through qemu-guest-agent (the CLI's
# status output and one `cat`); on the phone it asks adb only which device is
# attached and its model. Every capture is required non-empty before anything
# is concluded from it, and every observation is about the one peer U2-1
# identified, by its device id.
#
#   u2-state-check.sh --domain DOM --distro D --adb-serial SERIAL
#                     [--expect-clipboard 'send=on receive=on'] [--expect-when-locked full]
#
# Exit 0 only when all five hold; 1 when one does not; 3 when a precondition
# fails (PRECONDITION FAILED — nothing was measured).

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/guest-agent.sh
. "$HERE/lib/guest-agent.sh"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
# shellcheck source=lib/cli-report.sh
. "$HERE/lib/cli-report.sh"

DOMAIN=""; DISTRO=""; ADB_SERIAL=""; EXPECT_CLIP="send=on receive=on"; EXPECT_LOCKED="full"
GUEST_USER="${GUEST_USER:-anyflow}"; GUEST_UID="${GUEST_UID:-1000}"
while [ $# -gt 0 ]; do
    case "$1" in
        --domain) DOMAIN="${2:?}"; shift 2 ;;
        --distro) DISTRO="${2:?}"; shift 2 ;;
        --adb-serial) ADB_SERIAL="${2:?}"; shift 2 ;;
        --expect-clipboard) EXPECT_CLIP="${2:?}"; shift 2 ;;
        --expect-when-locked) EXPECT_LOCKED="${2:?}"; shift 2 ;;
        *) echo "usage: $0 --domain D --distro N --adb-serial S [--expect-clipboard P] [--expect-when-locked P]" >&2; exit 2 ;;
    esac
done
[ -n "$DOMAIN" ] && [ -n "$DISTRO" ] && [ -n "$ADB_SERIAL" ] \
    || { echo "usage: $0 --domain D --distro N --adb-serial S" >&2; exit 2; }

PASS=0; FAIL=0
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); printf 'not ok  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
abort()   { printf '\nPRECONDITION FAILED: %s\n' "$*"; exit 3; }
shown()   { sed 's/^/    | /'; }   # a capture, quoted into the log; never an ok/not ok line
gu() {
    ga_exec "$DOMAIN" "runuser -u $GUEST_USER -- env XDG_RUNTIME_DIR=/run/user/$GUEST_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GUEST_UID/bus sh -c $(printf '%q' "$*")"
}


section "Preconditions"
need_tool virsh jq adb || abort "a host tool this check depends on is missing"
ga_ping "$DOMAIN" 300 || abort "the guest agent in '$DOMAIN' does not answer"
ok "the guest agent in $DOMAIN answers"
adb_list="$(adb devices 2>/dev/null | tr -d '\r')"
grep -qxE "${ADB_SERIAL}[[:space:]]+device" <<<"$adb_list" \
    || abort "adb does not see $ADB_SERIAL as an attached, authorised device"
model="$(adb -s "$ADB_SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r[:space:]')"
[ -n "$model" ] || abort "adb returned no model for $ADB_SERIAL"
ok "the physical device is attached: $ADB_SERIAL, model $model"
ga_exec "$DOMAIN" 'pgrep -x omnibridged >/dev/null' \
    || abort "omnibridged is not running in the guest; U2 describes the OmniBridge 1.0.0 daemon's state"
ok "omnibridged (OmniBridge 1.0.0) is running in the guest"

devs="$(gu 'omnibridge devices' 2>&1)"
need_nonempty "'omnibridge devices'" "$devs" 2 || abort "'omnibridge devices' produced nothing to measure"
printf '%s\n' "$devs" | shown
table="$(ob_devices_tsv "$devs")"

section "U2-1 — exactly one paired peer, and it is the physical device"
paired="$(awk -F'\t' '$5 == "yes"' <<<"$table")"
n_paired="$(grep -c . <<<"$paired" || true)"
peer_name=""; peer_id=""; peer_fpr=""; peer_granted=""
if need_exact_count "paired peers in the guest's trust store" "$n_paired" 1; then
    IFS=$'\t' read -r peer_name peer_id peer_plat peer_fpr _ peer_granted <<<"$paired"
    if [ "$peer_plat" = android ] && [ "${peer_name,,}" = "${model,,}" ]; then
        ok "U2-1: exactly one peer is paired, '$peer_name' ($peer_id), platform android: the adb-attached $model ($ADB_SERIAL)"
    else
        notok "U2-1: the one paired peer is '$peer_name', platform '$peer_plat'; the attached device is $model (android)"
    fi
else
    notok "U2-1: $n_paired peer(s) are paired; U2 needs exactly one, the physical device"
fi

section "U2-2 — clipboard.v1 and files.v1 granted"
if [ -z "$peer_id" ]; then
    notok "U2-2: no single paired peer to read grants for"
else
    g2="$(tr ',' '\n' <<<"$peer_granted" | tr -d ' ')"
    if grep -qx 'clipboard.v1' <<<"$g2" && grep -qx 'files.v1' <<<"$g2"; then
        ok "U2-2: '$peer_name' is granted clipboard.v1 and files.v1 ($peer_granted)"
    else
        notok "U2-2: '$peer_name' is granted '${peer_granted:-nothing}', not both clipboard.v1 and files.v1"
    fi
fi

section "U2-3 — a clipboard policy for that peer"
clip="$(gu 'omnibridge clipboard status' 2>&1)"
printf '%s\n' "$clip" | shown
if [ -z "$peer_id" ]; then
    notok "U2-3: no single paired peer to read a clipboard policy for"
elif ! need_nonempty "'omnibridge clipboard status'" "$clip" 3; then
    notok "U2-3: the clipboard status is empty"
else
    pol="$(ob_peer_block "$clip" "$peer_id" | sed -n 's/^ *policy  *//p' | head -1)"
    miss=""
    for w in $EXPECT_CLIP; do grep -qw -- "$w" <<<"$(tr ' ' '\n' <<<"$pol")" || miss="$miss $w"; done
    if [ -n "$pol" ] && [ -z "$miss" ]; then ok "U2-3: the clipboard policy for '$peer_name' is '$pol'"
    else notok "U2-3: the clipboard policy for '$peer_name' is '${pol:-<none reported>}', missing:${miss:- the policy line}"; fi
fi

section "U2-4 — a notification lock policy for that peer"
notif="$(gu 'omnibridge notifications status' 2>&1)"
printf '%s\n' "$notif" | shown
if [ -z "$peer_id" ]; then
    notok "U2-4: no single paired peer to read a notification policy for"
elif ! need_nonempty "'omnibridge notifications status'" "$notif" 3; then
    notok "U2-4: the notifications status is empty"
else
    # The notifications report names a peer by its short fingerprint, not its id.
    wl="$(ob_peer_block "$notif" "($peer_fpr)" | sed -n 's/.*when locked  *\([a-z-]*\).*/\1/p' | head -1)"
    if [ "$wl" = "$EXPECT_LOCKED" ]; then ok "U2-4: '$peer_name' shows notifications 'when locked $wl'"
    else notok "U2-4: '$peer_name' shows 'when locked ${wl:-<none reported>}', not '$EXPECT_LOCKED'"; fi
fi

section "U2-5 — omnibridge-gui selected that peer (gui.json)"
gj="$(ga_exec "$DOMAIN" "cat /home/$GUEST_USER/.config/omnibridge/gui.json" 2>/dev/null)"
printf '%s\n' "$gj" | shown
sel="$(sed -n 's/.*"selected_peer" *: *"\([0-9a-fA-F]*\)".*/\1/p' <<<"$gj" | head -1 | tr '[:upper:]' '[:lower:]')"
want="$(tr -d ' ' <<<"$peer_fpr" | tr '[:upper:]' '[:lower:]')"
if [ -z "$peer_id" ]; then
    notok "U2-5: no single paired peer to compare the GUI's selection with"
elif [ -z "${gj//[[:space:]]/}" ]; then
    notok "U2-5: /home/$GUEST_USER/.config/omnibridge/gui.json does not exist or is empty: the peer was not selected in omnibridge-gui"
elif [[ "$want" =~ ^[0-9a-f]{16}$ ]] && [[ "$sel" =~ ^[0-9a-f]{64}$ ]] && [ "${sel:0:16}" = "$want" ]; then
    ok "U2-5: gui.json selects '$peer_name' (selected_peer ${sel:0:16}…, the daemon's $peer_fpr)"
else
    notok "U2-5: gui.json selects '${sel:-nothing}', not '$peer_name' ($peer_fpr)"
fi

printf '\n%s\n' "-----------------------------------------------"
printf '%s / %s: %d ok, %d not ok (U2 measured)\n' "$DISTRO" "$DOMAIN" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
