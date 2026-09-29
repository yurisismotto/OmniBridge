#!/usr/bin/env bash
# u2-state-check.sh — G7-UP U2, observed: the state U2 asks for on the
# OmniBridge 1.0.0 guest, BEFORE the upgrade, measured instead of attested.
#
# upgrade-gates.sh --stage install stops for the half of U2 that needs the
# phone: pair the PHYSICAL Android peer (U6 later measures "reconnects without
# re-pairing" with this pairing, so fake_phone cannot stand in), grant
# clipboard.v1 and files.v1, set a clipboard policy and a notification lock
# policy, and put the legacy GUI's device choice in place as migration input
# (u2-gui-fixture.sh). pre-g8-manual-gates.sh records that as five items. By
# default the operator answers them y/n; with --u2-measured the coordinator
# runs this script and takes each item from the line printed here for it:
#
#   U2-1  exactly ONE peer is paired, it reports platform android, and it is
#         the device adb has attached under --adb-serial (its model is the
#         peer's name, as the Android app announces itself)
#   U2-2  clipboard.v1 AND files.v1 are granted to that peer
#   U2-3  a clipboard policy is set for it: the policy line the daemon reports
#         for THAT peer carries --expect-clipboard (default send=on receive=on)
#   U2-4  a notification lock policy is set for it: the daemon reports
#         `when locked` --expect-when-locked (default full) for THAT peer
#   U2-5  the legacy GUI selected-peer state exists in the published
#         OmniBridge 1.0.0 format and selects the real paired peer
#         (deterministic migration fixture, method=fixture): gui.json is a
#         regular file, byte for byte the 1.0.0 serialization
#         (lib/legacy-gui-state.sh) whose selected_peer is the FULL 64-hex
#         fingerprint of the one trusted peer in the 1.0.0 trust store
#         (state.json) — the same peer U2-1 found, by device id and short
#         fingerprint. Malformed JSON, a foreign shape, an abbreviated or other
#         fingerprint, another owner than the guest user, a file mode other
#         than 0666 & ~session umask, a directory other than 0700, a moved
#         XDG_CONFIG_HOME and an existing ~/.config/pliwee are each not ok.
#         This says nothing about omnibridge-gui, which G7-UP does not certify
#
# IT CHANGES NOTHING. Guest reads go through qemu-guest-agent (the CLI's
# status output, and the bytes and metadata of state.json and gui.json); on
# the phone it asks adb only which device is attached and its model. Every capture is required non-empty before anything
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
# shellcheck source=lib/legacy-gui-state.sh
. "$HERE/lib/legacy-gui-state.sh"

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
need_tool virsh jq adb sha256sum base64 cmp || abort "a host tool this check depends on is missing"
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

section "U2-5 — the legacy GUI selected-peer state: published 1.0.0 format, the real paired peer (migration fixture)"
H="/home/$GUEST_USER"; GDIR="$H/.config/omnibridge"; GUI="$GDIR/gui.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
u25() { # the first rule U2-5 breaks, in LGS_WHY; FPR is set once the store is read
    FPR=""
    [ -n "$peer_id" ] || { LGS_WHY="no single paired peer to compare the selection with"; return 1; }
    lgs_guest_fetch "$DOMAIN" "$H/.local/share/omnibridge/state.json" "$TMP/state.json" || return 1
    local id
    lgs_one_trusted "$TMP/state.json" || return 1
    IFS=$'\t' read -r FPR id _ <<<"$LGS_PEER"
    [ "$id" = "$peer_id" ] && [ "$(lgs_short "$FPR")" = "$peer_fpr" ] \
        || { LGS_WHY="the trust store's trusted peer ($id, $(lgs_short "$FPR")) is not the daemon's ($peer_id, $peer_fpr)"; return 1; }
    lgs_config_home_default "$DOMAIN" "$GUEST_USER" "$GUEST_UID" || return 1
    [ "$(lgs_guest_stat "$DOMAIN" "$H/.config/pliwee")" = absent ] \
        || { LGS_WHY="$H/.config/pliwee exists before the upgrade: it would shadow the migration"; return 1; }
    local st typ uid gid mode umask gid_want dmode
    st="$(lgs_guest_stat "$DOMAIN" "$GUI")"
    [ -n "$st" ] || { LGS_WHY="could not stat $GUI"; return 1; }
    [ "$st" != absent ] || { LGS_WHY="$GUI does not exist: the migration input is missing (u2-gui-fixture.sh puts it in place)"; return 1; }
    IFS='|' read -r typ uid gid mode _ <<<"$st"
    [ "$typ" = "regular file" ] || { LGS_WHY="$GUI is a $typ, not a regular file"; return 1; }
    lgs_guest_fetch "$DOMAIN" "$GUI" "$TMP/gui.json" || return 1
    # awk, not sed: a file with no final newline must not glue the verdict
    # line below onto the quoted capture, where no `^not ok` would find it.
    awk '{ print "    | " $0 }' "$TMP/gui.json"
    lgs_check_gui "$TMP/gui.json" "$FPR" || return 1
    gid_want="$(ga_exec "$DOMAIN" "id -g $GUEST_USER" 2>/dev/null | tr -d '[:space:]')"
    [ "$uid:$gid" = "$GUEST_UID:$gid_want" ] || { LGS_WHY="$GUI is owned $uid:$gid, not $GUEST_UID:${gid_want:-?} ($GUEST_USER)"; return 1; }
    lgs_session_umask "$DOMAIN" "$GUEST_UID" || return 1; umask="$LGS_UMASK"
    [ "$mode" = "$(lgs_file_mode "$umask")" ] \
        || { LGS_WHY="$GUI has mode $mode; the 1.0.0 GUI creates it $(lgs_file_mode "$umask") under the session umask $umask"; return 1; }
    dmode="$(lgs_guest_stat "$DOMAIN" "$GDIR" | cut -d'|' -f4)"
    [ "$dmode" = "$LGS_GUI_DIR_MODE" ] || { LGS_WHY="$GDIR has mode ${dmode:-?}, not $LGS_GUI_DIR_MODE"; return 1; }
    U25_DETAIL="sha256 $(sha256sum < "$TMP/gui.json" | cut -d' ' -f1), $uid:$gid, mode $mode, directory $dmode"
}
if u25; then
    ok "U2-5: the legacy GUI selected-peer state exists in the published OmniBridge 1.0.0 format and selects the real paired peer '$peer_name' ($FPR; $U25_DETAIL) — method=fixture, deterministic migration input; omnibridge-gui not exercised"
else
    notok "U2-5: $LGS_WHY"
fi

printf '\n%s\n' "-----------------------------------------------"
printf '%s / %s: %d ok, %d not ok (U2 measured)\n' "$DISTRO" "$DOMAIN" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
