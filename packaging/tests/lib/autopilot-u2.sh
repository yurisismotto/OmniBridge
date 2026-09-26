#!/usr/bin/env bash
# autopilot-u2.sh — the steps a person is still needed for, reduced to what a
# person actually has to do, and checked afterwards: the one-time grant, the
# U2 pairing and GUI selection, and the phone before U6 and the security-log gate.
#
# WHAT IS AUTOMATED IN U2, AND WHY IT STILL MEANS U2
# ---------------------------------------------------
# U2 (upgrade-gates.sh --stage install, "the half that needs the other device")
# is: pair the PHYSICAL phone with the OmniBridge 1.0.0 guest, grant
# clipboard.v1 and files.v1, set a clipboard policy and a notification lock
# policy, and select the peer in omnibridge-gui. The autopilot does, through
# the product's own interfaces, the parts that have one:
#   * `omnibridge pair` in the guest (answering its prompt once, bounded, as
#     lifecycle-peer-gates.sh does), the QR on this screen, and the tablet's
#     Pliwee scanner opened by a tap found in its live view hierarchy. The
#     QR is scanned by the operator: pairing is by camera, and the app has no
#     other path (lifecycle-peer-gates.sh);
#   * `omnibridge grant`, `omnibridge clipboard allow … send|receive on` and
#     `omnibridge notifications when-locked … full` — the CLI commands the
#     install stage itself tells the operator to type;
#   * omnibridge-gui opened on its Devices page in the guest's session, and the
#     guest's screen opened here. The SELECTION is the operator's click:
#     gui.json is written only by the GUI (desktop/gui/src/selection.rs) and
#     nothing here writes it.
# Pressing ENTER proves nothing. After it, u2-state-check.sh measures all five
# items; only when every one holds does the coordinator run G7UP-D-U2 — with
# --u2-measured, so the record is what was observed, not what was typed.

# shellcheck disable=SC2034

AP_U2_TTL=240
AP_U2_CLIP_SEND=on; AP_U2_CLIP_RECEIVE=on; AP_U2_WHEN_LOCKED=full

# ---------------------------------------------------------------- the grant --
ap_grant_domains() { # ROLES... — the domains of those roles, every distro
    local d r out=()
    for d in "${AP_DISTROS[@]}"; do for r in "$@"; do out+=("$(ap_domain "$d" "$r")"); done; done
    printf '%s' "${out[*]}"
}
ap_grant_text() { # EXPIRES_UTC
    cat <<EOF
On the guests THIS autopilot creates (pliwee-g8-<distro>-chain|u8|lc, for
fedora44 ubuntu2404 ubuntu2604 debian13; never any other VM) it may, without
asking again until $1:

  * create, start, stop, snapshot and revert its own guests, from the verified
    cloud images and templates it built;
  * INSTALL  upgrade-gates.sh --stage install: installs the PUBLISHED OmniBridge
             1.0.0 in the chain guest, enables its user unit, adds a user
             'g7idle' and (Fedora) the omnibridge firewalld service in zone 'work';
  * U2       in the chain guest: 'omnibridge pair', 'omnibridge grant' of
             clipboard.v1 and files.v1, 'clipboard allow send on' / 'receive on'
             and 'notifications when-locked $AP_U2_WHEN_LOCKED' for the paired tablet, and opens
             omnibridge-gui; on the tablet: opens the Pliwee pairing scanner
             (start the app, one tap). YOU scan the QR and select the tablet in
             the GUI; both are then measured;
  * UPGRADE  upgrade-gates.sh --stage upgrade: upgrades the chain guest to
             Pliwee, ends the user's session once, restarts pliweed, and stops
             with the guest on Pliwee (no downgrade);
  * U6       upgrade-gates.sh --stage peer-u6 (lifecycle-peer-gates.sh) against
             the UPGRADED guest: drives the Pliwee app on the tablet over adb
             (force-stop, taps, grants, notification-source choice, the fixture)
             and sends a clipboard and a file between the tablet and the guest;
  * SECLOG   security-log-evidence.sh: a TRACE drop-in on pliweed in the
             UPGRADED guest (removed at the end), restarts it, sends a file and
             posts a fixture notification from the tablet;
  * U10      upgrade-gates.sh --stage downgrade: REMOVES Pliwee and reinstalls
             OmniBridge 1.0.0 (only after a verified U6 PASS);
  * U8       designates the -u8 guest FRESH (only right after creating it or
             reverting it to its never-used snapshot) and runs
             --stage negative-unreadable on it;
  * LIFECYCLE designates the -lc guest FRESH (likewise) and runs
             lifecycle-gates.sh: installs Pliwee, cycles the session, REBOOTS
             it, removes, reinstalls and purges.

It NEVER: runs a W2 or W6 gate, touches signing media or keys, installs
anything on the tablet, publishes, pushes, merges, or uses sudo.
EOF
}
# ap_grant_ensure — a valid grant for this evidence directory, or a new one
# typed at the terminal now. Exports the coordinator's two variables. Returns
# 1 when there is none and none can be asked for.
ap_grant_ensure() {
    local cur f id now exp hours="${AP_GRANT_HOURS:-16}" a
    now="$(date +%s)"
    cur="$(ap_rec_get grant-current file 2>/dev/null)"
    if [ -n "$cur" ] && [ -f "$cur" ] && [ "$(g7up_kv "$cur" evidence)" = "$EVIDENCE" ] \
            && [ "$(g7up_kv "$cur" expires_epoch)" -gt $(( now + 900 )) ] 2>/dev/null; then
        PRE_G8_AUTOPILOT_SESSION="$(g7up_kv "$cur" session)" || return 1
        export PRE_G8_AUTOPILOT_GRANT="$cur" PRE_G8_AUTOPILOT_SESSION
        ap_say INFO "using the authorisation typed at $(g7up_kv "$cur" typed_utc) (valid until $(g7up_kv "$cur" expires_utc))"
        return 0
    fi
    # Asked even with --no-wait: that option is for leaving the run alone after
    # starting it, and the one authorisation is typed when it is started.
    ap_have_tty || return 1
    exp=$(( now + hours * 3600 ))
    id="g-$(ap_stamp)-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    mkdir -p "$AP_STATE/grants" || ap_stop "cannot create $AP_STATE/grants"
    ap_grant_text "$(date -u -d "@$exp" +%FT%TZ)" > "$AP_STATE/grants/$id.actions.txt"
    ap_banner "AUTHORISATION — once, for the gates the autopilot runs" "$(cat "$AP_STATE/grants/$id.actions.txt")" >&2
    a="$(ap_read "Type 'yes' to authorise exactly this for ${hours}h, anything else to stop:")" || a=""
    [ "$a" = yes ] || return 1
    f="$AP_STATE/grants/$id.grant"
    ( umask 077
      printf '%s\n' "id=$id" "session=$id" "evidence=$EVIDENCE" "typed=yes" "typed_utc=$(ap_utc)" \
          "expires_epoch=$exp" "expires_utc=$(date -u -d "@$exp" +%FT%TZ)" \
          "guest_domains=$(ap_grant_domains chain)" "fresh_domains=$(ap_grant_domains u8 lc)" \
          "actions_sha256=$(ap_sha "$AP_STATE/grants/$id.actions.txt")" "operator=${USER:-}" > "$f" ) \
        || ap_stop "cannot write the grant $f"
    ap_rec_put grant-current "file=$f" "id=$id" "typed_utc=$(g7up_kv "$f" typed_utc)"
    export PRE_G8_AUTOPILOT_GRANT="$f" PRE_G8_AUTOPILOT_SESSION="$id"
    ap_say PASS "authorised until $(g7up_kv "$f" expires_utc) (grant $id)"
}

# ------------------------------------------------------------ in the guest --
ap_gu() { # DOM COMMAND — as the desktop user, inside their session bus
    ga_exec "$1" "runuser -u $AP_GUEST_USER -- env XDG_RUNTIME_DIR=/run/user/$AP_GUEST_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$AP_GUEST_UID/bus sh -c $(printf '%q' "$2")"
}
# ap_wait_person TITLE LINES... — a checkpoint: print it, wait for ENTER. With
# no terminal (or --no-wait) it is a WAIT: the run stops, resumable.
ap_wait_person() {
    local title="$1"; shift
    if ! ap_have_tty || [ "${AP_NO_WAIT:-0}" = 1 ]; then
        ap_finish WAIT "$title" "$@" "Run pre-g8-autopilot.sh --resume at a terminal to do this step."
    fi
    ap_say WAIT "$title"
    ap_banner "ACTION REQUIRED — $title" "$@" "" "When done, press ENTER (or type q and ENTER to stop here)." >&2
    local a
    a="$(ap_read ">")" || ap_finish WAIT "$title — no answer at the terminal"
    [ "$a" != q ] || ap_finish WAIT "$title — stopped by the operator" "Resume when ready: pre-g8-autopilot.sh --resume"
}

# ap_phone_ready WHY — the tablet is awake and unlocked, or a person makes it so.
ap_phone_ready() {
    local rc
    while :; do
        ap_phone_awake; rc=$?
        [ "$rc" = 0 ] && return 0
        if [ "$rc" = 2 ]; then
            ap_wait_person "check the tablet before $1" "Device: $AP_PHONE_MODEL / $AP_PHONE_SERIAL" \
                "adb could not tell whether its screen is on and unlocked." \
                "Make sure it is unlocked and stays on (the gate taps its screen)."
            return 0
        fi
        ap_wait_person "unlock the tablet before $1" "Device: $AP_PHONE_MODEL / $AP_PHONE_SERIAL" \
            "Its screen is off or locked; $1 drives the Pliwee app by tapping it." \
            "Unlock it and leave it on."
    done
}
ap_phone_apps_or_stop() { # WHY
    local miss
    miss="$(ap_phone_apps)" || ap_finish WAIT "the tablet is missing what $1 needs: $miss" \
        "The autopilot installs nothing on the phone. From the repository, once:" \
        "  (cd android && ./gradlew :fixture:assembleDebug)" \
        "  adb -s $AP_PHONE_SERIAL install -r android/fixture/build/outputs/apk/debug/fixture-debug.apk" \
        "  adb -s $AP_PHONE_SERIAL shell pm grant $AP_FIXTURE_PKG android.permission.POST_NOTIFICATIONS" \
        "(and the Pliwee app itself if it is missing). Then resume."
}

# ap_u2_peer DOM — the one paired peer as "id<TAB>name<TAB>platform<TAB>fpr", or fail.
ap_u2_peer() {
    local devs table paired
    devs="$(ap_gu "$1" 'omnibridge devices' 2>/dev/null)"
    table="$(ob_devices_tsv "$devs")"
    paired="$(awk -F'\t' '$5 == "yes"' <<<"$table")"
    [ "$(grep -c . <<<"$paired" || true)" = 1 ] || return 1
    awk -F'\t' '{ printf "%s\t%s\t%s\t%s\n", $2, $1, $3, $4 }' <<<"$paired"
}
ap_u2_npaired() { awk -F'\t' '$5 == "yes"' <<<"$(ob_devices_tsv "$(ap_gu "$1" 'omnibridge devices' 2>/dev/null)")" | grep -c . || true; }

# ap_u2_open_scanner — the tablet's pairing scanner, opened the way
# lifecycle-peer-gates.sh does (PairingCaptureActivity is not exported, so the
# button is tapped at coordinates read from the live hierarchy), but without
# the force-stop. Returns non-zero if it could not be verified open.
ap_u2_open_scanner() {
    local ui xy top
    adb -s "$AP_PHONE_SERIAL" shell am start -n "$AP_APP_PKG/.ui.MainActivity" >/dev/null 2>&1
    sleep "${AP_UI_SLEEP:-6}"
    adb -s "$AP_PHONE_SERIAL" shell uiautomator dump /sdcard/ob-ui.xml >/dev/null 2>&1
    ui="$(adb -s "$AP_PHONE_SERIAL" shell cat /sdcard/ob-ui.xml 2>/dev/null)"
    xy="$(tr '>' '\n' <<<"$ui" | grep -i 'content-desc="Pair a new device"' \
        | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -1 \
        | awk '{print int(($1+$3)/2), int(($2+$4)/2)}')"
    [ -n "$xy" ] || return 1
    # shellcheck disable=SC2086
    adb -s "$AP_PHONE_SERIAL" shell input tap $xy >/dev/null 2>&1
    sleep "${AP_UI_SLEEP:-4}"
    top="$(adb -s "$AP_PHONE_SERIAL" shell dumpsys activity activities 2>/dev/null | sed -n 's/.*topResumedActivity=ActivityRecord{[^ ]* [^ ]* \([^ ]*\).*/\1/p' | head -1)"
    [[ "$top" == *PairingCaptureActivity* ]]
}

# ap_u2_pair D DOM — until exactly one peer, the tablet, is paired.
ap_u2_pair() {
    local d="$1" dom="$2" payload png waited n
    while :; do
        n="$(ap_u2_npaired "$dom")"
        [ "$n" = 0 ] || break
        ap_phone_ready "pairing"
        ap_gu "$dom" "printf 'y\\n' | nohup omnibridge pair --ttl $AP_U2_TTL > /tmp/g8-pair.txt 2>&1 &" >/dev/null 2>&1
        sleep "${AP_UI_SLEEP:-6}"
        payload="$(ga_exec "$dom" 'sed -n "s/^ *\(omnibridge1:[^ ]*\) *$/\1/p" /tmp/g8-pair.txt | head -1' 2>/dev/null | tr -d '[:space:]')"
        [[ "$payload" == omnibridge1:* ]] || ap_stop "'omnibridge pair' in $dom printed no omnibridge1: payload" \
            "Nothing was paired. $(ga_exec "$dom" 'tail -5 /tmp/g8-pair.txt' 2>/dev/null | tr '\n' ' ')"
        png="$AP_RUN/U2-$d-pair-qr.png"
        qrencode -o "$png" -s 12 -m 4 "$payload" || ap_stop "qrencode failed"
        if ap_u2_open_scanner; then local scan="the tablet's Pliwee scanner is already open (verified)"
        else local scan="open Pliwee on the tablet and tap 'Pair a new device'"; fi
        [ "${AP_SELFTEST:-0}" = 1 ] || { ( setsid xdg-open "$png" >/dev/null 2>&1 & ) || true; }
        ap_say WAIT "G7UP-$d-U2 — physical Android pairing required"
        ap_banner "ACTION REQUIRED — Android pairing (G7UP-$d-U2)" \
            "Guest:   $d ($dom), OmniBridge 1.0.0 installed" \
            "Device:  $AP_PHONE_MODEL / $AP_PHONE_SERIAL" "" \
            "1. $scan." "2. Scan this QR with it (also opened as $png):" >&2
        qrencode -t ANSIUTF8 -m 2 "$payload" >&2 2>/dev/null || true
        printf '   The code is single-use and expires in %ss. The autopilot continues by itself once\n   the guest reports the pairing.\n' "$AP_U2_TTL" >&2
        waited=0
        while [ "$waited" -lt "$AP_U2_TTL" ]; do
            n="$(ap_u2_npaired "$dom")"; [ "$n" = 0 ] || break
            sleep 5; waited=$(( waited + 5 ))
        done
        [ "$n" = 0 ] || break
        ap_wait_person "the pairing code expired (G7UP-$d-U2)" "Press ENTER to show a new code."
    done
    [ "$n" = 1 ] || ap_stop "$dom now has $n paired peers; U2 needs exactly one, the tablet" \
        "Nothing was unpaired. Inspect with: omnibridge devices (in $dom)."
    ap_say PASS "G7UP-$d-U2 — the guest reports one paired peer"
}

# ap_u2_assist D DOM — bring the chain guest to U2 and verify it. Returns when
# u2-state-check.sh observes all five items.
ap_u2_assist() {
    local d="$1" dom="$2" peer id name plat fpr out gj notok
    ap_phone_detect
    ap_u2_pair "$d" "$dom"
    peer="$(ap_u2_peer "$dom")" || ap_stop "cannot read the one paired peer in $dom"
    IFS=$'\t' read -r id name plat fpr <<<"$peer"
    [ "$plat" = android ] && [ "${name,,}" = "${AP_PHONE_MODEL,,}" ] \
        || ap_stop "the peer paired with $dom is '$name' ($plat), not the tablet $AP_PHONE_MODEL" \
            "U2 is the PHYSICAL device (U6 measures this pairing). Nothing was changed; inspect $dom."
    out="$AP_RUN/U2-$d-cli.txt"
    {
        for c in "omnibridge grant $id clipboard.v1" "omnibridge grant $id files.v1" \
                 "omnibridge clipboard allow $id send $AP_U2_CLIP_SEND" "omnibridge clipboard allow $id receive $AP_U2_CLIP_RECEIVE" \
                 "omnibridge notifications when-locked $id $AP_U2_WHEN_LOCKED"; do
            printf '$ %s\n' "$c"; ap_gu "$dom" "$c" 2>&1; printf '(exit %s)\n' "$?"
        done
    } > "$out"
    grep -q '^(exit [1-9]' "$out" && ap_stop "a U2 CLI step failed in $dom" "See $out."
    ap_say PASS "G7UP-$d-U2 — clipboard.v1 and files.v1 granted, clipboard and lock policies set (CLI; $out)"
    while :; do
        gj="$(ga_exec "$dom" "cat /home/$AP_GUEST_USER/.config/omnibridge/gui.json" 2>/dev/null)"
        if ! grep -qi "\"selected_peer\" *: *\"$(tr -d ' ' <<<"$fpr" | tr '[:upper:]' '[:lower:]')" <<<"${gj,,}"; then
            ga_exec "$dom" "runuser -u $AP_GUEST_USER -- env XDG_RUNTIME_DIR=/run/user/$AP_GUEST_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$AP_GUEST_UID/bus WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 setsid -f omnibridge-gui --page=peers >/dev/null 2>&1" >/dev/null 2>&1 || true
            [ "${AP_SELFTEST:-0}" = 1 ] || { ( setsid virt-viewer -c "$AP_CONNECT" --attach "$dom" >/dev/null 2>&1 & ) || true; }
            ap_wait_person "select the tablet in OmniBridge (G7UP-$d-U2)" \
                "Guest:   $d ($dom) — its screen is open on this host (virt-viewer)" \
                "Device:  $AP_PHONE_MODEL / $AP_PHONE_SERIAL, fingerprint $fpr" "" \
                "In the guest, OmniBridge is open on its Devices page (if not, open 'OmniBridge'" \
                "from its applications). Click $name so it is the selected device." \
                "This writes the GUI's own gui.json; the autopilot never writes it."
        fi
        out="$AP_RUN/U2-$d-precheck.$(ap_stamp).log"
        "$GATES_DIR/u2-state-check.sh" --domain "$dom" --distro "$d" --adb-serial "$AP_PHONE_SERIAL" \
            --expect-clipboard "send=$AP_U2_CLIP_SEND receive=$AP_U2_CLIP_RECEIVE" \
            --expect-when-locked "$AP_U2_WHEN_LOCKED" > "$out" 2>&1 && return 0
        notok="$(grep -E '^(not ok|PRECONDITION FAILED)' "$out")"
        ap_say INFO "G7UP-$d-U2 — not all five U2 items are observed yet (nothing recorded):"
        ap_detail "${notok:-see $out}"
        ap_wait_person "U2 is not complete yet (G7UP-$d-U2)" "What is still missing:" "$notok" "" \
            "Fix it in the guest, then press ENTER to measure again."
    done
}

# ap_u6_checkpoint D DOM — the clipboard text adb cannot provide.
ap_u6_checkpoint() {
    local d="$1" dom="$2"
    ap_phone_detect
    ap_phone_apps_or_stop "U6"
    ap_wait_person "copy some text on the tablet (G7UP-$d-U6)" \
        "Guest:   $d ($dom), upgraded to Pliwee" \
        "Device:  $AP_PHONE_MODEL / $AP_PHONE_SERIAL" "" \
        "U6 sends the tablet's clipboard to the guest, and adb cannot put text there." \
        "1. Unlock the tablet and keep it unlocked." \
        "2. Copy any short text on it (select a word in any app, then Copy)." \
        "adb cannot read the clipboard either: U6 itself measures that it arrived."
    ap_phone_ready "U6"
}
ap_seclog_checkpoint() { # D DOM
    ap_phone_detect
    ap_phone_apps_or_stop "the security-log gate"
    ap_phone_ready "G7UP-$1-SECLOG"
}
