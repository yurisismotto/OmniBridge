#!/usr/bin/env bash
# legacy-gui-state.sh — the OmniBridge 1.0.0 GUI's device choice, as the
# published 1.0.0 wrote it to disk, and the one trusted peer it must name.
#
# WHY THIS EXISTS
# ---------------
# ADR-0020 D9 carries `$XDG_CONFIG_HOME/omnibridge/gui.json` over to
# `…/pliwee/gui.json` on the first start of pliwee-gui. G7-UP certifies PLIWEE
# migrating FROM a valid OmniBridge 1.0.0 state, so that file has to be part of
# the migration input. It does NOT certify the retired OmniBridge GUI: clicking
# a peer in omnibridge-gui measured nothing about Pliwee and needed a person at
# a VM console for it. The file is therefore built here as a deterministic
# fixture, byte for byte what 1.0.0 writes, from the full fingerprint of the
# peer the REAL 1.0.0 trust store holds — and recorded as method=fixture, never
# as a GUI result.
#
# THE FORMAT, AND WHERE IT IS PROVED
# ----------------------------------
# desktop/gui/src/selection.rs at tag v1.0.0 (commit below), Selection::persist:
#
#     let mut doc = serde_json::Map::new();
#     doc.insert("schema".into(), SCHEMA.into());            // const SCHEMA: u32 = 1
#     doc.insert("selected_peer".into(), hex.into());         // normalise(): trimmed, lowercase hex
#     serde_json::to_string_pretty(&doc) … fs::write(&self.path, body + "\n")
#
# after `create_dir_all(dir)` and `set_permissions(dir, 0o700)`. serde_json's
# pretty printer indents by two spaces and writes `"key": value`; the keys come
# out as `schema`, `selected_peer` whether the map keeps insertion order or
# sorts (they are in both orders at once). `fs::write` creates the file with
# 0666 & ~umask, the umask of the session the GUI ran in. The value the GUI
# passes to `choose()` is `peer.fingerprint` from the daemon's device list,
# which is `Fingerprint::to_hex()`: 64 lowercase hex digits of the SPKI
# SHA-256 — the same string `state.json` stores for the peer
# (desktop/core/src/store.rs, `TrustedPeer.fingerprint`, schema_version 2).
# The CLI shows only `to_display_short()` (16 uppercase hex in groups of 4);
# that form "is never parsed back", and neither is it here.
#
# packaging/tests/pre-g8-autopilot-selftests.sh re-derives these constants
# from the tag when the repository has it, and the Rust test
# selection::tests::a_published_1_0_0_choice_migrates_byte_for_byte builds the
# same bytes and runs the real Selection::load over them.

# shellcheck disable=SC2034  # the constants are read by the scripts that source this
LGS_V100_TAG=v1.0.0
LGS_V100_COMMIT=f72d30e5288cb2a907aab258c99a96652a0f708b
LGS_V100_SELECTION_BLOB=bf9c0b6c28d334954126bad8a6c090dad4f86928   # desktop/gui/src/selection.rs
LGS_V100_STORE_BLOB=5c8125baa7a04aff7fa7818bd531f873866360c3       # desktop/core/src/store.rs
LGS_V100_STATE_SCHEMA=2
LGS_FORMAT="OmniBridge 1.0.0 gui.json (schema 1; selected_peer = 64 lowercase hex, the SPKI fingerprint; serde_json::to_string_pretty + LF; directory 0700, file 0666 & ~session umask) — desktop/gui/src/selection.rs Selection::persist at $LGS_V100_TAG ($LGS_V100_COMMIT, blob $LGS_V100_SELECTION_BLOB)"
LGS_GUI_DIR_MODE=700
LGS_PLIWEE_DIR_MODE=700     # desktop/platform-linux/src/legacy_migration.rs DIR_MODE
LGS_PLIWEE_FILE_MODE=600    # … FILE_MODE (write_new)
LGS_APP_ID=io.github.yurisismotto.pliwee

LGS_WHY=""
_lgs_no() { LGS_WHY="$*"; return 1; }

lgs_is_fpr() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

# lgs_bytes FPR — exactly what OmniBridge 1.0.0 writes for that choice.
lgs_bytes() {
    lgs_is_fpr "$1" || { _lgs_no "'$1' is not a full lowercase fingerprint (64 hex)"; return 1; }
    printf '{\n  "schema": 1,\n  "selected_peer": "%s"\n}\n' "$1"
}
lgs_sha() { lgs_bytes "$1" >/dev/null || return 1; lgs_bytes "$1" | sha256sum | cut -d' ' -f1; }

# lgs_file_mode UMASK — the octal mode fs::write gives a new file under it.
lgs_file_mode() {
    [[ "$1" =~ ^0?[0-7]{3,4}$ ]] || { _lgs_no "'$1' is not a umask"; return 1; }
    printf '%o' $(( 0666 & ~(8#$1) ))
}

# lgs_store_ok STATE_JSON_FILE — a 1.0.0 trust store (schema_version 2, a
# peers array) whose every trusted record has a 64-lowercase-hex fingerprint.
# Run it directly, not in $(…), so that LGS_WHY reaches the caller.
lgs_store_ok() {
    local f="$1" v bad
    [ -s "$f" ] || { _lgs_no "the trust store capture is empty"; return 1; }
    jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { _lgs_no "state.json is not a JSON object"; return 1; }
    v="$(jq -r '.schema_version | tostring' "$f")"
    [ "$v" = "$LGS_V100_STATE_SCHEMA" ] \
        || { _lgs_no "state.json has schema_version '$v', not OmniBridge 1.0.0's $LGS_V100_STATE_SCHEMA"; return 1; }
    jq -e '.peers | type == "array"' "$f" >/dev/null 2>&1 || { _lgs_no "state.json has no peers array"; return 1; }
    bad="$(jq -r '.peers[] | select(.revoked != true) | .fingerprint | tostring | select(test("^[0-9a-f]{64}$") | not)' "$f")"
    [ -z "$bad" ] || { _lgs_no "a trusted peer's fingerprint is not 64 lowercase hex: $bad"; return 1; }
}

# lgs_trusted_fprs STATE_JSON_FILE — every non-revoked peer of a store
# lgs_store_ok accepted, one per line, as "fpr<TAB>device_id<TAB>device_name".
lgs_trusted_fprs() {
    jq -r '.peers[] | select(.revoked != true) | [.fingerprint, .device_id, .device_name] | @tsv' "$1"
}

# lgs_one_trusted STATE_JSON_FILE — the ONE trusted peer, into LGS_PEER (same
# shape); refuses zero or several. Also sets LGS_N_REVOKED (tombstones and
# revoked records, which stay and are not selectable). Globals, not stdout: a
# caller in $(…) would lose the count.
lgs_one_trusted() {
    local all n
    LGS_PEER=""; LGS_N_REVOKED=""
    lgs_store_ok "$1" || return 1
    all="$(lgs_trusted_fprs "$1")"
    n="$(grep -c . <<<"$all" || true)"
    LGS_N_REVOKED="$(jq '[.peers[] | select(.revoked == true)] | length' "$1")"
    [ "$n" = 1 ] || { _lgs_no "the 1.0.0 trust store holds $n trusted peer(s); this gate needs exactly one"; return 1; }
    LGS_PEER="$all"
}

# lgs_short FPR — the CLI's rendering of it (Fingerprint::to_display_short).
lgs_short() { local u; u="$(tr '[:lower:]' '[:upper:]' <<<"${1:0:16}")"; printf '%s %s %s %s' "${u:0:4}" "${u:4:4}" "${u:8:4}" "${u:12:4}"; }

# lgs_check_gui FILE FPR — FILE is the 1.0.0 gui.json that selects FPR, byte
# for byte. On refusal LGS_WHY says which rule: malformed JSON, a foreign
# shape, an abbreviated or other fingerprint, or 1.0.0-equal content in bytes
# 1.0.0 does not write.
lgs_check_gui() {
    local f="$1" want="$2" sel keys
    [ -f "$f" ] || { _lgs_no "no gui.json capture"; return 1; }
    [ -s "$f" ] || { _lgs_no "gui.json is empty"; return 1; }
    jq -e . "$f" >/dev/null 2>&1 || { _lgs_no "gui.json is not valid JSON"; return 1; }
    keys="$(jq -c 'if type == "object" then keys else "not an object" end' "$f")"
    [ "$keys" = '["schema","selected_peer"]' ] \
        || { _lgs_no "gui.json holds $keys, not exactly the 1.0.0 keys schema and selected_peer"; return 1; }
    [ "$(jq -c .schema "$f")" = 1 ] || { _lgs_no "gui.json schema is $(jq -c .schema "$f"), not 1"; return 1; }
    sel="$(jq -r 'if (.selected_peer | type) == "string" then .selected_peer else "<not a string>" end' "$f")"
    if ! lgs_is_fpr "$sel"; then
        if [[ "${sel,,}" =~ ^[0-9a-f]{1,63}$ ]] && [ "${want:0:${#sel}}" = "${sel,,}" ]; then
            _lgs_no "gui.json selects '$sel', an ABBREVIATED fingerprint (${#sel} hex digits); 1.0.0 stores all 64"
        else
            _lgs_no "gui.json selects '$sel', which is not a full lowercase fingerprint"
        fi
        return 1
    fi
    [ "$sel" = "$want" ] || { _lgs_no "gui.json selects $sel, not the paired peer $want"; return 1; }
    cmp -s "$f" <(lgs_bytes "$want") \
        || { _lgs_no "gui.json names the right peer but its bytes are not what OmniBridge 1.0.0 writes (sha256 $(sha256sum < "$f" | cut -d' ' -f1), 1.0.0 would write $(lgs_sha "$want"))"; return 1; }
}

# ------------------------------------------------------------ in the guest --
# These need lib/guest-agent.sh.

# lgs_guest_fetch DOM PATH OUT — PATH's exact bytes into OUT. `$(…)` would drop
# a trailing newline, so the bytes travel as base64. Fails if PATH is not a
# readable file; OUT is then removed.
lgs_guest_fetch() {
    local b64
    b64="$(ga_exec "$1" "base64 -w0 -- '$2'" 2>/dev/null)" || { rm -f "$3"; _lgs_no "$2 cannot be read in the guest"; return 1; }
    printf '%s' "$b64" | base64 -d > "$3" 2>/dev/null || { rm -f "$3"; _lgs_no "$2 did not arrive intact"; return 1; }
}

# lgs_guest_stat DOM PATH — "type|uid|gid|mode|size|mtime|inode" without
# following a symlink; "absent" when there is nothing at PATH.
lgs_guest_stat() {
    ga_exec "$1" "if [ -e '$2' ] || [ -L '$2' ]; then stat -c '%F|%u|%g|%a|%s|%Y|%i' -- '$2'; else echo absent; fi" 2>/dev/null
}

# lgs_session_umask DOM UID — the umask of that user's systemd --user
# manager, which every application the desktop starts inherits: the umask
# the 1.0.0 GUI's fs::write ran under. Into LGS_UMASK.
lgs_session_umask() {
    LGS_UMASK="$(ga_exec "$1" "p=\$(pgrep -u $2 -x systemd | head -1); [ -n \"\$p\" ] && sed -n 's/^Umask:[[:space:]]*//p' /proc/\$p/status" 2>/dev/null | tr -d '[:space:]')"
    [[ "$LGS_UMASK" =~ ^[0-7]{4}$ ]] || { _lgs_no "no systemd --user manager for uid $2, so no session umask (read '${LGS_UMASK:-nothing}')"; return 1; }
}

# lgs_config_home_default DOM USER UID — the user's session does not move
# XDG_CONFIG_HOME away from ~/.config; the GUI (1.0.0 and Pliwee alike) would
# otherwise read and write somewhere these paths do not name.
lgs_config_home_default() {
    local env x
    env="$(ga_exec "$1" "runuser -u $2 -- env XDG_RUNTIME_DIR=/run/user/$3 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$3/bus systemctl --user show-environment" 2>/dev/null)"
    [ -n "${env//[[:space:]]/}" ] || { _lgs_no "the user manager's environment could not be read"; return 1; }
    x="$(sed -n 's/^XDG_CONFIG_HOME=//p' <<<"$env")"
    [ -z "$x" ] || [ "$x" = "/home/$2/.config" ] \
        || { _lgs_no "the session sets XDG_CONFIG_HOME=$x; the GUI would not use /home/$2/.config"; return 1; }
}
