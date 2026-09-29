#!/usr/bin/env bash
# g7up-gui-migration-selftests.sh — the legacy GUI device choice through G7-UP,
# without a VM: the REAL u2-gui-fixture.sh, u2-state-check.sh and
# upgrade-gates.sh --stage upgrade, against lib/fake-guest (a guest agent that
# runs their guest commands for real in a directory standing for the guest's
# root, with stateful rpm/dnf/systemctl/loginctl/journalctl/pliwee-gui).
#
# Proved, each both ways:
#   * the fixture writes EXACTLY the OmniBridge 1.0.0 bytes for the full
#     fingerprint read from state.json, as the guest user, 0666 & ~umask in a
#     0700 directory; records method=fixture; accepts an identical existing
#     file without rewriting it; refuses 0 or 2 trusted peers, a malformed or
#     non-1.0.0 trust store, a differing / abbreviated / re-serialized /
#     wrongly-moded / symlinked existing file (leaving it byte-identical), an
#     existing ~/.config/pliwee, a moved XDG_CONFIG_HOME and a daemon that
#     reports another peer; and never launches omnibridge-gui;
#   * u2-state-check.sh U2-5 passes that fixture and fails a wrong, an
#     abbreviated, a malformed, a re-keyed, a wrongly-moded, a foreign-owned
#     or a missing file, a trust store with two trusted peers, and an existing
#     ~/.config/pliwee;
#   * the upgrade stage archives the legacy bytes in O1, starts pliwee-gui in
#     a graphical session it has to bring back after U4, and proves in O2 that
#     the migrated file is the O1 bytes (digest and cmp), selects the O1 full
#     fingerprint, has modes 0600/0700, was logged once, left the legacy file
#     as O1 recorded it, and that a second start changes nothing — and that
#     each of those claims turns red when the GUI breaks it.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
# shellcheck source=lib/legacy-gui-state.sh
. "$HERE/lib/legacy-gui-state.sh"

PASS=0; FAIL=0
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); printf 'not ok  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
check()   { local d="$1"; shift; if "$@"; then ok "$d"; else notok "$d"; fi; }
has()     { contains "$1" "$2"; }

for t in python3 jq base64 sha256sum cmp stat; do
    command -v "$t" >/dev/null 2>&1 || { echo "PRECONDITION FAILED: $t is needed by these self-tests" >&2; exit 3; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pliwee-gui-migration-selftest.XXXXXXXX")"
trap '[ "${G7UP_SELFTEST_KEEP:-0}" = 1 ] && echo "kept: $WORK" || rm -rf "$WORK"' EXIT

UID_H="$(id -u)"; GID_H="$(id -g)"; U=anyflow; H="/home/$U"
FPR="3f9a0c7be1d24a6f8b05c3e9d17a2b4c6e8f0a1b2c3d4e5f60718293a4b5c6d7"
FPR2="b6d0e2f4a8c1e3f5a7b9c0d2e4f6a8b0c2d4e6f8a0b2c4d6e8f0a2b4c6d8e0f2"
SERIAL=R52X90FAKE

# ------------------------------------------------------------------ fakes --
HBIN="$WORK/hostbin"; GBIN="$WORK/guestbin"; mkdir -p "$HBIN" "$GBIN"
ln -s "$HERE/lib/fake-guest/virsh" "$HBIN/virsh"
for p in runuser id pgrep omnibridge pliwee rpm dnf firewall-cmd loginctl journalctl busctl systemd-run systemctl; do
    ln -s "$HERE/lib/fake-guest/fakeguest" "$GBIN/$p"
done
cat > "$HBIN/adb" <<EOF
#!/bin/sh
case "\$*" in
  devices) printf 'List of devices attached\n$SERIAL\tdevice\n' ;;
  "-s $SERIAL shell getprop ro.product.model") echo SM-X620 ;;
  *) exit 1 ;;
esac
EOF
# ga_wait_for polls every 3 s; a fault that never clears would wait its whole
# timeout. The polls still run, only without the pauses.
printf '#!/bin/sh\nexit 0\n' > "$HBIN/sleep"
chmod +x "$HBIN/adb" "$HBIN/sleep"

# fg_new NAME [UMASK] — a guest with OmniBridge 1.0.0 installed, the tablet
# paired, granted and with policies (U2 minus the GUI choice), one revoked
# tombstone beside it. Makes it current (R).
R=""
fg_new() {
    R="$WORK/fg-$1/root"
    mkdir -p "$R"/{root,etc,proc/4242,usr/lib/systemd/user,run/user/"$UID_H"} "$R$H/.local/share/omnibridge" "$R$H/.config"
    mkdir -p "$R/home/g7idle"
    chmod 700 "$R$H/.local/share/omnibridge"
    printf 'PRETTY_NAME="Fedora Linux 44 (Workstation Edition)"\n' > "$R/etc/os-release"
    printf '0123456789abcdef0123456789abcdef\n' > "$R/etc/machine-id"
    printf 'Name:\tsystemd\nUmask:\t%s\nState:\tS\n' "${2:-0022}" > "$R/proc/4242/status"
    head -c 64 /dev/urandom > "$R$H/.local/share/omnibridge/identity.key"; chmod 600 "$R$H/.local/share/omnibridge/identity.key"
    fg_store "$FPR"
    python3 - "$R/.state.json" "$U" "$UID_H" "$GID_H" "$FPR" <<'PY'
import json, sys
p, u, uid, gid, fpr = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
json.dump({"user": u, "users": {u: {"uid": uid, "gid": gid}, "g7idle": {"uid": uid + 1, "gid": gid + 1}},
           "pkgs": {"omnibridge": "1.0.0-1.fc44", "omnibridge-gui": "1.0.0-1.fc44"},
           "daemon": "omnibridged", "daemon_pid": 500, "manager": True, "greeter": False,
           "sessions": [{"id": "2", "user": u, "type": "wayland"}],
           "env": {"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0", "XDG_SESSION_TYPE": "wayland"},
           "journal": [{"unit": None, "msg": "omnibridged: listening on 0.0.0.0:55432"}], "units": {}, "bus": {},
           "local_name": "fake-f44", "local_fpr": "1111 2222 3333 4444",
           "peer": {"name": "SM-X620", "id": "0123456789abcdef", "fpr": fpr, "grants": ["clipboard.v1", "files.v1"],
                    "clipboard": "send=on receive=on", "when_locked": "full"}}, open(p, "w"), indent=1)
PY
}
# fg_store FPR... — state.json (schema 2) trusting those peers, plus a tombstone.
fg_store() {
    local peers="" f n=0
    for f in "$@"; do
        n=$((n + 1)); [ "$n" = 1 ] || peers+=","
        peers+="{\"device_id\":\"$( [ "$n" = 1 ] && echo 0123456789abcdef || echo fedcba98765432$n)\",\"device_name\":\"SM-X620\",\"platform\":2,\"fingerprint\":\"$f\",\"paired_at_unix\":1790000000,\"granted_capabilities\":{\"clipboard.v1\":true,\"files.v1\":true},\"revoked\":false,\"hidden\":false}"
    done
    [ -n "$peers" ] && peers+=","
    peers+="{\"device_id\":\"\",\"device_name\":\"\",\"platform\":0,\"fingerprint\":\"$(printf 'e%.0s' {1..64})\",\"paired_at_unix\":0,\"revoked\":true,\"hidden\":true}"
    printf '{\n  "schema_version": %s,\n  "device_id": "d-local",\n  "certificate_der_b64": "MIIB",\n  "settings": {},\n  "peers": [%s]\n}' \
        "${SCHEMA:-2}" "$peers" > "$R$H/.local/share/omnibridge/state.json"
}
fgset() { python3 - "$R/.state.json" "$1" <<'PY'
import json, sys; p = sys.argv[1]; s = json.load(open(p)); exec(sys.argv[2]); json.dump(s, open(p, "w"))
PY
}
fgenv() {
    env PATH="$HBIN:$PATH" FAKE_GUEST_ROOT="$R" FAKE_GUEST_BIN="$GBIN" FAKE_GUEST_DOMAIN=fake-f44 \
        FAKE_GUEST_FAULTS="${FAULTS:-}" FAKE_GUEST_LIVE_PID="$$" GUEST_USER="$U" GUEST_UID="$UID_H" GA_EXEC_TIMEOUT=30 "$@"
}
OUT=""; RC=0
run() { OUT="$(fgenv "$@" 2>&1)"; RC=$?; }
fixture() { local rec="$WORK/rec.$RANDOM$RANDOM"; run bash "$HERE/u2-gui-fixture.sh" --domain fake-f44 --distro fedora44 --record "$rec"; REC="$rec"; }
statecheck() { run bash "$HERE/u2-state-check.sh" --domain fake-f44 --distro fedora44 --adb-serial "$SERIAL"; }
GUI="$H/.config/omnibridge/gui.json"
gfile() { printf '%s' "$R$GUI"; }
put_gui() { mkdir -p "$R$H/.config/omnibridge"; chmod 700 "$R$H/.config/omnibridge"; printf '%b' "$1" > "$(gfile)"; chmod "${2:-644}" "$(gfile)"; }
fsnap() { stat -c '%i %Y %a %s' "$1" 2>/dev/null; sha256sum < "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
section "The format: exactly what OmniBridge 1.0.0 writes"
# ---------------------------------------------------------------------------
check "lgs_bytes is the serde_json pretty form plus LF, 105 bytes for a 64-hex choice" \
    test "$(lgs_bytes "$FPR" | od -An -c | tr -s ' ' | tr -d '\n')" = "$(printf '{\n  "schema": 1,\n  "selected_peer": "%s"\n}\n' "$FPR" | od -An -c | tr -s ' ' | tr -d '\n')" \
         -a "$(lgs_bytes "$FPR" | wc -c)" = 105
no_bytes() { ! lgs_bytes "$1" >/dev/null 2>&1; }
check "…and refuses an abbreviated fingerprint" no_bytes 3f9a0c7be1d24a6f
check "…and an uppercase one" no_bytes "${FPR^^}"
if git -C "$HERE/../.." rev-parse -q --verify "$LGS_V100_TAG^{commit}" >/dev/null 2>&1; then
    check "the pinned provenance is the tag: commit $LGS_V100_COMMIT" \
        test "$(git -C "$HERE/../.." rev-parse "$LGS_V100_TAG^{commit}")" = "$LGS_V100_COMMIT"
    check "…selection.rs and store.rs at the tag are the pinned blobs" \
        test "$(git -C "$HERE/../.." rev-parse "$LGS_V100_TAG:desktop/gui/src/selection.rs")" = "$LGS_V100_SELECTION_BLOB" \
             -a "$(git -C "$HERE/../.." rev-parse "$LGS_V100_TAG:desktop/core/src/store.rs")" = "$LGS_V100_STORE_BLOB"
    v100="$(git -C "$HERE/../.." show "$LGS_V100_TAG:desktop/gui/src/selection.rs")"
    check "…whose persist() is the shape lgs_bytes reproduces (schema 1, to_string_pretty, LF, dir 0700)" \
        test -n "$(grep -F 'const SCHEMA: u32 = 1;' <<<"$v100")" -a -n "$(grep -F 'serde_json::to_string_pretty(&doc)' <<<"$v100")" \
             -a -n "$(grep -F 'std::fs::write(&self.path, body + "\n")' <<<"$v100")" -a -n "$(grep -F 'from_mode(0o700)' <<<"$v100")" \
             -a -n "$(grep -F 'doc.insert("selected_peer".into(), hex.into());' <<<"$v100")"
    check "…and 1.0.0's trust store is schema_version $LGS_V100_STATE_SCHEMA with a to_hex fingerprint" \
        test -n "$(git -C "$HERE/../.." show "$LGS_V100_TAG:desktop/core/src/store.rs" | grep -F "pub const SCHEMA_VERSION: u32 = $LGS_V100_STATE_SCHEMA;")"
else
    printf 'n/a   the %s tag is not in this clone; the pinned provenance is not re-derived here\n' "$LGS_V100_TAG"
fi
check "the Pliwee modes the harness expects are legacy_migration.rs's" \
    test -n "$(grep -F "const DIR_MODE: u32 = 0o$LGS_PLIWEE_DIR_MODE;" "$HERE/../../desktop/platform-linux/src/legacy_migration.rs")" \
         -a -n "$(grep -F "const FILE_MODE: u32 = 0o$LGS_PLIWEE_FILE_MODE;" "$HERE/../../desktop/platform-linux/src/legacy_migration.rs")"
check "the migration line the harness anchors on is the one selection.rs prints" \
    test -n "$(grep -F '"pliwee: migrated from {}: device choice copied to {}; the' "$HERE/../../desktop/gui/src/selection.rs")"

# ---------------------------------------------------------------------------
section "u2-gui-fixture.sh: builds the migration input"
# ---------------------------------------------------------------------------
fg_new created
fixture
check "a paired guest with no gui.json: the fixture is created (exit 0)" test "$RC" -eq 0
check "…its bytes are exactly the 1.0.0 serialization of the FULL fingerprint" cmp -s "$(gfile)" <(lgs_bytes "$FPR")
check "…owned by the guest user ($UID_H:$GID_H), mode 644 under umask 0022, directory 700" \
    test "$(stat -c '%u:%g %a' "$(gfile)")" = "$UID_H:$GID_H 644" -a "$(stat -c %a "$R$H/.config/omnibridge")" = 700
check "…written as the guest user, under the session umask, never over a file (runuser, umask, set -C)" \
    test -n "$(grep -F "runuser -u $U -- sh -c umask\\ 0022" "$R/.commands")" -a -n "$(grep -F 'set\ -C' "$R/.commands")"
check "…the record says method=fixture, and that omnibridge-gui was not exercised" \
    test "$(sed -n 's/^method=//p' "$REC")" = fixture -a -n "$(grep -x 'omnibridge_gui_exercised=no' "$REC")"
check "…the record binds the full fingerprint, the file's SHA-256 and metadata, and the format's provenance" \
    test -n "$(grep -x "selected_peer=$FPR" "$REC")" -a -n "$(grep -x "sha256=$(lgs_sha "$FPR")" "$REC")" \
         -a -n "$(grep -x 'mode=644' "$REC")" -a -n "$(grep -x "uid=$UID_H" "$REC")" -a -n "$(grep -x 'dir_mode=700' "$REC")" \
         -a -n "$(grep -x "format_commit=$LGS_V100_COMMIT" "$REC")" -a -n "$(grep -x 'action=created' "$REC")"
check "…the fingerprint's source is state.json, cross-checked with the daemon's short form" \
    test -n "$(grep "^fingerprint_source=$H/.local/share/omnibridge/state.json" "$REC")" -a -n "$(grep -x 'daemon_cross_check=omnibridge devices: 0123456789abcdef, 3F9A 0C7B E1D2 4A6F' "$REC")"
check "…and its copy of the bytes is the file" cmp -s "$REC.gui.json" "$(gfile)"
check "…omnibridge-gui was never launched (only queried as a package), nor any display touched" \
    test -z "$(grep -vE '^(rpm|dpkg-query) ' "$R/.commands" | grep -E 'omnibridge-gui|virt-viewer|WAYLAND_DISPLAY=|setsid')"
before="$(fsnap "$(gfile)")"
fixture
check "run again over its own file: accepted (exit 0, action=accepted-existing)" test "$RC" -eq 0 -a -n "$(grep -x 'action=accepted-existing' "$REC")"
check "…and not rewritten (inode, mtime, mode, bytes)" test "$(fsnap "$(gfile)")" = "$before"

fg_new umask2 0002
fixture
check "a session umask of 0002: the 1.0.0 GUI's file is 664, and so is the fixture" \
    test "$RC" -eq 0 -a "$(stat -c %a "$(gfile)")" = 664 -a -n "$(grep -x 'session_umask=0002' "$REC")"

refused() { # LABEL NEEDLE — the last fixture run refused, saying NEEDLE, and wrote nothing
    check "$1: refused (exit 1)" test "$RC" -eq 1
    check "…saying: $2" has "$OUT" "$2"
}
fg_new zero; fg_store; fixture
refused "no trusted peer" "holds 0 trusted peer(s)"
check "…and no gui.json was created" test ! -e "$(gfile)"
fg_new two; fg_store "$FPR" "$FPR2"; fixture
refused "two trusted peers" "holds 2 trusted peer(s)"
check "…and no gui.json was created" test ! -e "$(gfile)"
fg_new malformed; printf '{"schema_version": 2, "peers": [' > "$R$H/.local/share/omnibridge/state.json"; fixture
refused "a malformed trust store" "state.json is not a JSON object"
fg_new schema1; SCHEMA=1 fg_store "$FPR"; fixture
refused "a trust store that is not 1.0.0's" "schema_version '1', not OmniBridge 1.0.0's 2"
fg_new crossid; fgset 's["peer"]["id"] = "aaaaaaaaaaaaaaaa"'; fixture
refused "a daemon that reports another peer than state.json" "is not the trust store's"

refuses_existing() { # LABEL CONTENT MODE NEEDLE
    fg_new "ex-$RANDOM"; put_gui "$2" "$3"; local b; b="$(fsnap "$(gfile)")"
    fixture
    refused "an existing gui.json, $1" "$4"
    check "…left byte-identical, same inode, mode and mtime" test "$(fsnap "$(gfile)")" = "$b"
}
refuses_existing "naming another peer" "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR2\"\n}\n" 644 "not the paired peer $FPR"
refuses_existing "abbreviated" "{\n  \"schema\": 1,\n  \"selected_peer\": \"3f9a0c7be1d24a6f\"\n}\n" 644 "ABBREVIATED fingerprint"
refuses_existing "the same peer in bytes 1.0.0 does not write" "{\"schema\":1,\"selected_peer\":\"$FPR\"}\n" 644 "bytes are not what OmniBridge 1.0.0 writes"
refuses_existing "malformed" "{\"schema\": 1, \"selected_peer\": \"$FPR\"\n" 644 "not valid JSON"
refuses_existing "with a key 1.0.0 never writes" "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\",\n  \"x\": 1\n}\n" 644 "not exactly the 1.0.0 keys"
refuses_existing "right bytes, mode 600" "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n" 600 "has mode 600, not the 644"
fg_new symlink; mkdir -p "$R$H/.config/omnibridge"; chmod 700 "$R$H/.config/omnibridge"; lgs_bytes "$FPR" > "$R/elsewhere.json"
ln -s elsewhere.json "$(gfile)"; fixture
refused "a gui.json that is a symlink" "is a symbolic link, not a regular file"
fg_new pliwee-exists; mkdir -p "$R$H/.config/pliwee"; fixture
refused "an existing ~/.config/pliwee" "would shadow the migration"
check "…and no gui.json was created" test ! -e "$(gfile)"
fg_new xdg; fgset 's["env"]["XDG_CONFIG_HOME"] = "/home/anyflow/cfg"'; fixture
refused "a session that moves XDG_CONFIG_HOME" "the session sets XDG_CONFIG_HOME=/home/anyflow/cfg"
fg_new not100; fgset 's["pkgs"]["omnibridge-gui"] = "1.0.1-1.fc44"'; fixture
check "omnibridge-gui 1.0.0-1 not installed: PRECONDITION FAILED (exit 3), nothing written" \
    test "$RC" -eq 3 -a ! -e "$(gfile)" -a -n "$(grep 'omnibridge-gui 1.0.0-1 is not what is installed' <<<"$OUT")"

# ---------------------------------------------------------------------------
section "u2-state-check.sh U2-5: measures it"
# ---------------------------------------------------------------------------
fg_new sc; fixture; n0="$(wc -l < "$R/.commands")"; statecheck
check "the fixture in place: all five U2 items ok (exit 0)" test "$RC" -eq 0 -a "$(grep -c '^ok    U2-[1-5]: ' <<<"$OUT")" = 5
check "…U2-5 names the format, the full fingerprint and method=fixture, and says the old GUI was not exercised" \
    has "$OUT" "ok    U2-5: the legacy GUI selected-peer state exists in the published OmniBridge 1.0.0 format and selects the real paired peer 'SM-X620' ($FPR;"
check "…ending: method=fixture, deterministic migration input; omnibridge-gui not exercised" \
    contains_re "$OUT" 'method=fixture, deterministic migration input; omnibridge-gui not exercised$'
check "…and u2-state-check.sh changed nothing: none of its guest commands writes" \
    test "$(tail -n +"$((n0 + 1))" "$R/.commands" | grep -c .)" -gt 5 \
         -a -z "$(tail -n +"$((n0 + 1))" "$R/.commands" | sed -E 's#[12]?>/dev/null##g; s#2>&1##g' | grep -E 'chmod|mkdir|set.-C|touch|rm |mv |>')"
u25_fails() { # LABEL NEEDLE — the last check failed U2-5, and only U2-5, saying NEEDLE
    check "$1: U2-5 not ok (exit 1)" test "$RC" -eq 1 -a -n "$(grep '^not ok  U2-5: ' <<<"$OUT")" -a "$(grep -c '^ok    U2-[1-4]: ' <<<"$OUT")" = 4
    check "…saying: $2" has "$(grep '^not ok  U2-5: ' <<<"$OUT")" "$2"
}
sc_with() { fg_new "sc-$RANDOM"; put_gui "$1" "${2:-644}"; statecheck; }
sc_with "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR2\"\n}\n";                       u25_fails "a wrong fingerprint" "not the paired peer"
sc_with "{\n  \"schema\": 1,\n  \"selected_peer\": \"3f9a0c7be1d24a6f\"\n}\n";            u25_fails "the abbreviated fingerprint" "ABBREVIATED"
sc_with "{\n  \"schema\": 1,\n  \"selected_peer\": \"$(tr a-f A-F <<<"$FPR")\"\n}\n";  u25_fails "an uppercase fingerprint" "not a full lowercase fingerprint"
sc_with "{\"schema\": 1, \"selected_peer\": \"$FPR\"";                                      u25_fails "malformed JSON" "not valid JSON"
sc_with "{\n  \"schema\": 2,\n  \"selected_peer\": \"$FPR\"\n}\n";                         u25_fails "schema 2" "schema is 2, not 1"
sc_with "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n" 600;                     u25_fails "mode 600" "has mode 600"
sc_with "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n"; chmod 755 "$R$H/.config/omnibridge"; statecheck
u25_fails "a 755 directory" "has mode 755, not 700"
fg_new sc-owner; put_gui "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n"
fgset "s['users']['anyflow']['uid'] = $((UID_H + 7))"; OUT="$(fgenv env GUEST_UID=$((UID_H + 7)) bash "$HERE/u2-state-check.sh" --domain fake-f44 --distro fedora44 --adb-serial "$SERIAL" 2>&1)"; RC=$?
u25_fails "a file another user owns" "not $((UID_H + 7))"
fg_new sc-missing; statecheck;                                                             u25_fails "no gui.json" "does not exist: the migration input is missing"
fg_new sc-two; fg_store "$FPR" "$FPR2"; put_gui "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n"; statecheck
u25_fails "a trust store with two trusted peers" "holds 2 trusted peer(s)"
fg_new sc-pliwee; put_gui "{\n  \"schema\": 1,\n  \"selected_peer\": \"$FPR\"\n}\n"; mkdir -p "$R$H/.config/pliwee"; statecheck
u25_fails "an existing ~/.config/pliwee" "would shadow the migration"

# ---------------------------------------------------------------------------
section "U2 -> UPGRADE end to end: pliwee-gui migrates the fixture, O2 measures it against O1"
# ---------------------------------------------------------------------------
NEW="$WORK/new"; OLD="$WORK/old"; mkdir -p "$NEW" "$OLD"
for p in pliwee-1.1.0-1.fc44.x86_64.rpm pliwee-gui-1.1.0-1.fc44.x86_64.rpm omnibridge-1.1.0-1.fc44.noarch.rpm; do echo "$p" > "$NEW/$p"; done
( cd "$NEW" && sha256sum ./*.rpm | sed 's| \./| |' > SHA256SUMS ); echo "old set" > "$OLD/SHA256SUMS"
upgrade() { # NAME [FAULTS] — a fresh guest, the fixture, U2 measured, then the upgrade stage
    fg_new "up-$1"; FAULTS=""; fixture; FIXREC="$REC"; statecheck; U2RC="$RC"
    EV="$WORK/ev-$1"; FAULTS="${2:-}"
    run bash "$HERE/upgrade-gates.sh" --stage upgrade --domain fake-f44 --distro fedora44 --evidence "$EV" \
        --new-pkgdir "$NEW" --old-pkgdir "$OLD"
    FAULTS=""; printf '%s\n' "$OUT" > "$EV.log"
}
upgrade clean
check "U2 measured PASS on the guest the upgrade starts from" test "$U2RC" -eq 0
check "the upgrade stage passes (exit 0, no not ok) and writes its checkpoint" \
    test "$RC" -eq 0 -a -z "$(grep '^not ok' <<<"$OUT")" -a -f "$EV/UPGRADE-CHECKPOINT"
check "O1 archived the legacy bytes: the very file U2's fixture recorded" cmp -s "$EV/O1-legacy-gui.json" "$FIXREC.gui.json"
check "…with the full fingerprint, digest, metadata and path" \
    test -n "$(grep -x "selected_peer=$FPR" "$EV/O1-gui.txt")" -a -n "$(grep -x "sha256=$(lgs_sha "$FPR")" "$EV/O1-gui.txt")" \
         -a -n "$(grep -x "legacy_path=$GUI" "$EV/O1-gui.txt")" -a -n "$(grep -x 'mode=644' "$EV/O1-gui.txt")"
check "O2: no Pliwee gui.json before pliwee-gui started" has "$OUT" "ok    O2: before pliwee-gui starts there is no $H/.config/pliwee/gui.json"
check "O2: the graphical session U4 ended was brought back by restarting the display manager" \
    contains_re "$OUT" '^ok    O2: no graphical session after U4 .* the display manager was restarted for one autologin'
check "O2: pliwee-gui was started twice, each as its own transient unit in the user's manager" \
    test "$(jq -r '.units | keys[]' "$R/.state.json" | grep -cE '^g7up-pliwee-gui-[12]-')" = 2 -a "$(jq .gui_starts "$R/.state.json")" = 2
check "O2: it came up (application id owned by its process) and was closed" \
    contains_re "$OUT" '^ok    O2: pliwee-gui started in the graphical session .* is owned by its process'
check "O2: the migration was logged exactly once" has "$OUT" "ok    O2: pliwee-gui logged the migration once: 'pliwee: migrated from $GUI: device choice copied to $H/.config/pliwee/gui.json; the source was not modified'"
check "O2: SHA-256 equal to O1's, bytes equal to O1's, the full O1 fingerprint selected" \
    test -n "$(grep "^ok    O2: its SHA-256 is the O1 legacy gui.json's ($(lgs_sha "$FPR"))" <<<"$OUT")" \
         -a -n "$(grep '^ok    O2: its bytes are the O1 bytes, unchanged' <<<"$OUT")" -a -n "$(grep "^ok    O2: it selects the full fingerprint recorded in O1: $FPR" <<<"$OUT")"
check "O2: modes 600 and 700, owner the guest user" \
    test -n "$(grep '^ok    O2: modes are 600 (file) and 700' <<<"$OUT")" -a -n "$(grep "^ok    O2: .* owned by $U ($UID_H:$GID_H)" <<<"$OUT")"
check "O2: the legacy file is as O1 recorded it, after each start" \
    test -n "$(grep '^ok    O2: the legacy .* is byte-identical to O1 and unmodified' <<<"$OUT")" -a -n "$(grep '^ok    O2: the legacy gui.json is still the O1 file after the second start' <<<"$OUT")"
check "O2: the second start migrated nothing and changed nothing" \
    test -n "$(grep '^ok    O2: the second start logged no migration and no refusal' <<<"$OUT")" -a -n "$(grep '^ok    O2: .* is unchanged by the second start' <<<"$OUT")"
check "…and on disk: the Pliwee file is the fixture's bytes, 600" \
    test "$(stat -c %a "$R$H/.config/pliwee/gui.json")" = 600 -a -n "$(cmp "$R$H/.config/pliwee/gui.json" "$FIXREC.gui.json" && echo same)"

o2_fails() { # FAULTS NEEDLE — that fault turns the stage red, on the line that names it
    upgrade "f-${1//,/-}" "$1"
    check "fault $1: the upgrade stage fails (exit 1)" test "$RC" -eq 1
    check "…on: $2" has "$(grep '^not ok' <<<"$OUT")" "$2"
}
o2_fails gui-no-migrate    "pliwee-gui did not create $H/.config/pliwee/gui.json"
o2_fails gui-alter         "its SHA-256 is"
o2_fails gui-mode-644      "modes are 644 (file)"
o2_fails gui-quiet         "migration 0 time(s), not once"
o2_fails gui-remigrate     "the second start logged 1 migration"
o2_fails gui-touch-legacy  "THE LEGACY gui.json CHANGED"
o2_fails gui-no-bus        "pliwee-gui did not come up"
o2_fails gui-hangs         "did not go away when its unit was stopped"
o2_fails daemon-writes-gui "exists before pliwee-gui ever started"
upgrade no-dm no-autologin
check "no graphical session can be brought back: PRECONDITION FAILED (exit 3), not a FAIL of the product" \
    test "$RC" -eq 3 -a -n "$(grep 'no graphical session for anyflow came back' <<<"$OUT")"
# O1 binds O2: without the migration input in O1 there is nothing to compare.
fg_new up-noinput; FAULTS=""; EV="$WORK/ev-noinput"
run bash "$HERE/upgrade-gates.sh" --stage upgrade --domain fake-f44 --distro fedora44 --evidence "$EV" --new-pkgdir "$NEW" --old-pkgdir "$OLD"
check "no legacy gui.json at O1: O1 says so, and O2 refuses to compare against nothing (exit 1)" \
    test "$RC" -eq 1 -a -n "$(grep "^not ok  O1: the legacy GUI device choice is not usable migration input: $GUI does not exist" <<<"$OUT")" \
         -a -n "$(grep '^not ok  O2: no O1 record of the legacy gui.json in this run' <<<"$OUT")"

printf '\n%s\n' "-----------------------------------------------"
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
