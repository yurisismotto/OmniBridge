#!/usr/bin/env bash
# u2-gui-fixture.sh — G7-UP U2: the legacy GUI's device choice, put in place as
# MIGRATION INPUT in the published OmniBridge 1.0.0 format, selecting the real
# paired peer. A deterministic fixture, not a GUI test.
#
# ADR-0020 D9 migrates ~/.config/omnibridge/gui.json to ~/.config/pliwee/
# gui.json on the first start of pliwee-gui, so the upgrade stage needs that
# file to exist in the 1.0.0 state it starts from. G7-UP certifies Pliwee
# migrating FROM a valid 1.0.0 state; it does not certify the retired
# omnibridge-gui, and a person clicking a row in it proved nothing about
# Pliwee. So this script builds the file from what the published format is
# (lib/legacy-gui-state.sh: desktop/gui/src/selection.rs at v1.0.0) and what
# the REAL 1.0.0 trust store holds:
#
#   * the fingerprint is the FULL 64-hex one of the single trusted peer in
#     ~/.local/share/omnibridge/state.json, cross-checked against the daemon's
#     own device list (same device id, same short fingerprint). It is never
#     derived from the CLI's 16-digit display;
#   * the bytes are exactly the 1.0.0 serialization of that choice;
#   * it is written AS THE GUEST USER, under the umask of that user's session
#     (the one the 1.0.0 GUI's fs::write ran under), into a directory made
#     0700 — what the published GUI does;
#   * a gui.json that already exists is never written over. It is accepted
#     only when it is byte-identical to what 1.0.0 writes for that peer, with
#     the owner and modes 1.0.0 gives it; anything else is refused and left.
#
# It refuses when the trust store holds no trusted peer or several, when it is
# not a 1.0.0 (schema_version 2) store, when a ~/.config/pliwee exists already
# (it would shadow the migration), or when the session moves XDG_CONFIG_HOME.
#
#   u2-gui-fixture.sh --domain DOM --distro D --record FILE
#
# FILE receives a key=value record (method=fixture, the full fingerprint, the
# SHA-256 and metadata of the exact bytes, the format's provenance), and
# FILE.gui.json the bytes themselves. Exit 0: in place (created, or an
# identical one accepted); 1: refused, nothing written; 3: precondition failed.

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

DOMAIN=""; DISTRO=""; RECORD=""
GUEST_USER="${GUEST_USER:-anyflow}"; GUEST_UID="${GUEST_UID:-1000}"
while [ $# -gt 0 ]; do
    case "$1" in
        --domain) DOMAIN="${2:?}"; shift 2 ;;
        --distro) DISTRO="${2:?}"; shift 2 ;;
        --record) RECORD="${2:?}"; shift 2 ;;
        *) echo "usage: $0 --domain D --distro N --record FILE" >&2; exit 2 ;;
    esac
done
[ -n "$DOMAIN" ] && [ -n "$DISTRO" ] && [ -n "$RECORD" ] || { echo "usage: $0 --domain D --distro N --record FILE" >&2; exit 2; }
[ ! -e "$RECORD" ] || { echo "u2-gui-fixture: $RECORD exists; a record is never overwritten" >&2; exit 2; }

ok()     { printf 'ok    %s\n' "$*"; }
refuse() { printf 'not ok  %s\n\nREFUSED: nothing was written in the guest.\n' "$*"; exit 1; }
abort()  { printf '\nPRECONDITION FAILED: %s\n' "$*"; exit 3; }
gx() { ga_exec "$DOMAIN" "$@"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

H="/home/$GUEST_USER"
STATE="$H/.local/share/omnibridge/state.json"
GDIR="$H/.config/omnibridge"; GUI="$GDIR/gui.json"; PDIR="$H/.config/pliwee"

printf '== Preconditions ==\n'
need_tool virsh jq sha256sum base64 cmp || abort "a host tool this script depends on is missing"
ga_ping "$DOMAIN" 300 || abort "the guest agent in '$DOMAIN' does not answer"
[ "$(gx 'id -u' | tr -d '[:space:]')" = 0 ] || abort "the guest agent is not root"
[ "$(gx "id -u $GUEST_USER" 2>/dev/null | tr -d '[:space:]')" = "$GUEST_UID" ] || abort "guest user '$GUEST_USER' is not uid $GUEST_UID"
GID="$(gx "id -g $GUEST_USER" 2>/dev/null | tr -d '[:space:]')"
[[ "$GID" =~ ^[0-9]+$ ]] || abort "could not read the primary group of '$GUEST_USER'"
case "$DISTRO" in
    fedora44) vers="$(gx "rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE}\n' omnibridge-gui 2>&1")" ;;
    ubuntu2404|ubuntu2604|debian13) vers="$(gx "dpkg-query -W -f '\${Package} \${Version}\n' omnibridge-gui 2>&1")" ;;
    *) abort "unknown --distro '$DISTRO'" ;;
esac
contains_re "$vers" '^omnibridge-gui 1\.0\.0-1(\.fc44)?$' \
    || abort "omnibridge-gui 1.0.0-1 is not what is installed ('$(tr '\n' ' ' <<<"$vers")'); the fixture reproduces THAT version's file"
ok "the published omnibridge-gui 1.0.0-1 is installed: the fixture is its on-disk format"
gx 'pgrep -x omnibridged >/dev/null' || abort "omnibridged (1.0.0) is not running; its device list is the cross-check"

printf '\n== The peer, from the 1.0.0 trust store ==\n'
lgs_guest_fetch "$DOMAIN" "$STATE" "$TMP/state.json" || abort "$LGS_WHY"
state_sha="$(sha256sum < "$TMP/state.json" | cut -d' ' -f1)"
lgs_one_trusted "$TMP/state.json" || refuse "$LGS_WHY ($STATE)"
IFS=$'\t' read -r FPR PEER_ID PEER_NAME <<<"$LGS_PEER"
ok "the trust store ($STATE, sha256 $state_sha) holds exactly one trusted peer: '$PEER_NAME' ($PEER_ID), $FPR ($LGS_N_REVOKED revoked record(s) beside it)"
devs="$(gx "runuser -u $GUEST_USER -- env XDG_RUNTIME_DIR=/run/user/$GUEST_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GUEST_UID/bus omnibridge devices" 2>&1)"
need_nonempty "'omnibridge devices'" "$devs" 2 || abort "'omnibridge devices' produced nothing to cross-check"
paired="$(awk -F'\t' '$5 == "yes"' <<<"$(ob_devices_tsv "$devs")")"
[ "$(grep -c . <<<"$paired" || true)" = 1 ] || refuse "the daemon reports $(grep -c . <<<"$paired" || true) paired peer(s), not one"
IFS=$'\t' read -r _ d_id _ d_fpr _ _ <<<"$paired"
[ "$d_id" = "$PEER_ID" ] && [ "$d_fpr" = "$(lgs_short "$FPR")" ] \
    || refuse "the daemon's paired peer ($d_id, $d_fpr) is not the trust store's ($PEER_ID, $(lgs_short "$FPR"))"
ok "the daemon reports the same peer: device id $d_id, fingerprint $d_fpr = the first 16 of the 64 digits"

printf '\n== Where the 1.0.0 GUI would write, and how ==\n'
lgs_config_home_default "$DOMAIN" "$GUEST_USER" "$GUEST_UID" || refuse "$LGS_WHY"
lgs_session_umask "$DOMAIN" "$GUEST_UID" || abort "$LGS_WHY"
UMASK="$LGS_UMASK"
MODE="$(lgs_file_mode "$UMASK")"
ok "the session's umask is $UMASK: the 1.0.0 GUI creates gui.json $MODE in a $LGS_GUI_DIR_MODE directory, owned $GUEST_UID:$GID"
[ "$(lgs_guest_stat "$DOMAIN" "$PDIR")" = absent ] \
    || refuse "$PDIR already exists before the upgrade; a Pliwee config there would shadow the migration being measured"
lgs_bytes "$FPR" > "$TMP/want.json"
WANT_SHA="$(sha256sum < "$TMP/want.json" | cut -d' ' -f1)"

st="$(lgs_guest_stat "$DOMAIN" "$GUI")"
[ -n "$st" ] || abort "could not stat $GUI"
if [ "$st" = absent ]; then
    action=created
    # As the user, under the session's umask, never over an existing file
    # (noclobber): the same create_dir_all, chmod 0700 and fs::write 1.0.0 does.
    inner="umask $UMASK && mkdir -p '$GDIR' && chmod $LGS_GUI_DIR_MODE '$GDIR' && set -C && printf '{\\n  \"schema\": 1,\\n  \"selected_peer\": \"%s\"\\n}\\n' '$FPR' > '$GUI'"
    gx "runuser -u $GUEST_USER -- sh -c $(printf '%q' "$inner")" >/dev/null 2>"$TMP/err" \
        || refuse "writing $GUI as $GUEST_USER failed: $(tr '\n' ' ' < "$TMP/err")"
    st="$(lgs_guest_stat "$DOMAIN" "$GUI")"
    ok "created $GUI as $GUEST_USER"
else
    action=accepted-existing
    ok "$GUI already exists ($st): inspecting it; it is never written over"
fi
IFS='|' read -r typ uid gid mode size mtime _ <<<"$st"
dmode="$(lgs_guest_stat "$DOMAIN" "$GDIR" | cut -d'|' -f4)"
[ "$typ" = "regular file" ] || refuse "$GUI is a $typ, not a regular file"
lgs_guest_fetch "$DOMAIN" "$GUI" "$TMP/got.json" || refuse "$LGS_WHY"
lgs_check_gui "$TMP/got.json" "$FPR" || refuse "$GUI: $LGS_WHY"
[ "$uid:$gid" = "$GUEST_UID:$GID" ] || refuse "$GUI is owned $uid:$gid, not $GUEST_UID:$GID as the 1.0.0 GUI running as $GUEST_USER leaves it"
[ "$mode" = "$MODE" ] || refuse "$GUI has mode $mode, not the $MODE the 1.0.0 GUI creates under umask $UMASK"
[ "$dmode" = "$LGS_GUI_DIR_MODE" ] || refuse "$GDIR has mode $dmode, not the $LGS_GUI_DIR_MODE the 1.0.0 GUI sets"
GOT_SHA="$(sha256sum < "$TMP/got.json" | cut -d' ' -f1)"
[ "$GOT_SHA" = "$WANT_SHA" ] || refuse "sha256 $GOT_SHA is not the 1.0.0 serialization's $WANT_SHA"
ok "$GUI is the 1.0.0 file for $FPR: sha256 $GOT_SHA, $size bytes, $uid:$gid, mode $mode, directory $dmode"

cp "$TMP/got.json" "$RECORD.gui.json" || abort "cannot write $RECORD.gui.json"
{
    echo "method=fixture"
    echo "omnibridge_gui_exercised=no"
    echo "action=$action"
    echo "domain=$DOMAIN"
    echo "distro=$DISTRO"
    echo "legacy_path=$GUI"
    echo "selected_peer=$FPR"
    echo "fingerprint_source=$STATE: the one non-revoked peer (device_id $PEER_ID, '$PEER_NAME'), schema_version $LGS_V100_STATE_SCHEMA"
    echo "state_json_sha256=$state_sha"
    echo "daemon_cross_check=omnibridge devices: $d_id, $d_fpr"
    echo "sha256=$GOT_SHA"
    echo "size=$size"
    echo "uid=$uid"
    echo "gid=$gid"
    echo "mode=$mode"
    echo "dir_mode=$dmode"
    echo "mtime=$mtime"
    echo "session_umask=$UMASK"
    echo "bytes_file=$RECORD.gui.json"
    echo "format=$LGS_FORMAT"
    echo "format_commit=$LGS_V100_COMMIT"
    echo "format_selection_rs_blob=$LGS_V100_SELECTION_BLOB"
    echo "format_store_rs_blob=$LGS_V100_STORE_BLOB"
    echo "recorded_utc=$(date -u +%FT%TZ)"
} > "$RECORD.partial" && mv "$RECORD.partial" "$RECORD" || abort "cannot write $RECORD"
printf '\nFIXTURE %s method=fixture selected_peer=%s sha256=%s (record %s)\n' "$action" "$FPR" "$GOT_SHA" "$RECORD"
