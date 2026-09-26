#!/usr/bin/env bash
# autopilot-android.sh — the physical Android peer, as adb reports it. READ ONLY.
#
# The autopilot finds the project's device (serial RX2Y500C7SY, an SM-X620) and
# its CURRENT Wi-Fi address every run — never a remembered one — and checks, before
# a gate that drives the phone, that its screen is on and unlocked, because a
# gate that taps a locked screen fails for a reason that is not the product.
# Nothing here installs, grants, launches or changes anything on the device;
# the gates that do (U6, the security-log gate) say so in their own
# confirmation, and the fixture app is installed by the operator.

# shellcheck disable=SC2034

AP_APP_PKG="io.github.yurisismotto.pliwee"
AP_FIXTURE_PKG="io.github.yurisismotto.pliwee.fixture"

# ap_adb_state TEXT SERIAL — the state `adb devices` gives SERIAL (device,
# unauthorized, offline…), or nothing.
ap_adb_state() { awk -v s="$2" '$1 == s { print $2; exit }' <<<"$1"; }
# ap_parse_ipv4 TEXT — the one global IPv4 address in `ip -4 -br addr show
# wlan0` ("wlan0  UP  192.168.68.63/22") or `ip -4 addr show wlan0`
# ("    inet 192.168.68.63/22 brd … scope global wlan0"). Nothing if none, or
# more than one.
ap_parse_ipv4() {
    local ips
    ips="$(tr -d '\r' <<<"$1" | awk '
        $1 == "inet" { split($2, a, "/"); print a[1]; next }
        $1 ~ /^wlan/ { for (i = 3; i <= NF; i++) { split($i, a, "/"); if (a[1] ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print a[1] } }' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^(127\.|169\.254\.)' | sort -u)"
    [ "$(grep -c . <<<"$ips" || true)" = 1 ] || return 1
    printf '%s' "$ips"
}
# ap_same_subnet IP CIDR — IP is inside CIDR (a.b.c.d/n).
ap_same_subnet() {
    local ip="$1" net="${2%/*}" bits="${2#*/}" a b c d n1 n2 mask
    IFS=. read -r a b c d <<<"$ip"; n1=$(( (a << 24) | (b << 16) | (c << 8) | d ))
    IFS=. read -r a b c d <<<"$net"; n2=$(( (a << 24) | (b << 16) | (c << 8) | d ))
    mask=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    [ $(( n1 & mask )) -eq $(( n2 & mask )) ]
}

# ap_phone_detect — sets PHONE_IP, PHONE_MODEL_SEEN. Stops, with exactly what
# to do, when the device is not attached, not authorised, not the SM-X620, not
# on Wi-Fi, or not on the guests' LAN.
ap_phone_detect() {
    local list st model ipout nic cidr
    list="$(adb devices 2>/dev/null | tr -d '\r')"
    st="$(ap_adb_state "$list" "$AP_PHONE_SERIAL")"
    case "$st" in
        device) : ;;
        unauthorized) ap_finish WAIT "the tablet $AP_PHONE_SERIAL is attached but has not authorised this host" \
                          "Unlock it and accept the USB debugging prompt, then resume." ;;
        "") ap_finish WAIT "the tablet $AP_PHONE_MODEL / $AP_PHONE_SERIAL is not attached over adb" \
                "Connect it by USB (USB debugging on), then resume." ;;
        *) ap_finish WAIT "the tablet $AP_PHONE_SERIAL is '$st' in adb" "Reconnect it, then resume." ;;
    esac
    model="$(adb -s "$AP_PHONE_SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r[:space:]')"
    [ "$model" = "$AP_PHONE_MODEL" ] \
        || ap_stop "adb serial $AP_PHONE_SERIAL reports model '${model:-<none>}', not $AP_PHONE_MODEL" \
            "Refusing to use a device that is not the project's peer."
    PHONE_MODEL_SEEN="$model"
    ipout="$(adb -s "$AP_PHONE_SERIAL" shell ip -4 -br addr show wlan0 2>/dev/null)"
    PHONE_IP="$(ap_parse_ipv4 "$ipout")" \
        || PHONE_IP="$(ap_parse_ipv4 "$(adb -s "$AP_PHONE_SERIAL" shell ip -4 addr show wlan0 2>/dev/null)")" \
        || ap_finish WAIT "the tablet has no single Wi-Fi IPv4 address (wlan0)" \
            "Connect it to the same Wi-Fi/LAN as the wired NIC, then resume."
    ap_detect_nic; nic="$NIC"
    cidr="$(ip -4 -o addr show dev "$nic" scope global 2>/dev/null | awk '{print $4; exit}')"
    if [ -n "$cidr" ] && ! ap_same_subnet "$PHONE_IP" "$cidr"; then
        ap_finish WAIT "the tablet is at $PHONE_IP, outside the guests' LAN $cidr ($nic)" \
            "The guests are bridged onto $nic; the tablet must be on that network. Move it, then resume."
    fi
    ap_log "phone $AP_PHONE_SERIAL $model at $PHONE_IP (host $nic $cidr)"
}

# ap_phone_apps — the Pliwee app and the notification fixture (with
# POST_NOTIFICATIONS) are installed; lifecycle-peer-gates.sh and
# security-log-evidence.sh refuse without them. Prints what is missing.
ap_phone_apps() {
    local pk miss=()
    pk="$(adb -s "$AP_PHONE_SERIAL" shell pm list packages 2>/dev/null | tr -d '\r')"
    grep -qx "package:$AP_APP_PKG" <<<"$pk" || miss+=("the Pliwee app ($AP_APP_PKG)")
    grep -qx "package:$AP_FIXTURE_PKG" <<<"$pk" || miss+=("the notification fixture ($AP_FIXTURE_PKG)")
    if grep -qx "package:$AP_FIXTURE_PKG" <<<"$pk"; then
        grep -q 'android.permission.POST_NOTIFICATIONS: granted=true' \
            <<<"$(adb -s "$AP_PHONE_SERIAL" shell dumpsys package "$AP_FIXTURE_PKG" 2>/dev/null)" \
            || miss+=("POST_NOTIFICATIONS for the fixture")
    fi
    [ "${#miss[@]}" -eq 0 ] || { printf '%s; ' "${miss[@]}"; return 1; }
}

# ap_phone_awake — 0 when the screen is on and not locked, 1 when it is off or
# locked, 2 when adb's answers could not be read (the caller asks a person).
ap_phone_awake() {
    local p w
    p="$(adb -s "$AP_PHONE_SERIAL" shell dumpsys power 2>/dev/null | tr -d '\r')"
    w="$(adb -s "$AP_PHONE_SERIAL" shell dumpsys window 2>/dev/null | tr -d '\r')"
    [ -n "$p" ] && [ -n "$w" ] || return 2
    grep -qE 'mWakefulness=Awake' <<<"$p" || { grep -qE 'mWakefulness=' <<<"$p" && return 1; return 2; }
    grep -qE '(mDreamingLockscreen|mShowingLockscreen|isKeyguardShowing|KeyguardShowing)=true' <<<"$w" && return 1
    grep -qE '(mDreamingLockscreen|mShowingLockscreen|isKeyguardShowing|KeyguardShowing)=false' <<<"$w" && return 0
    return 2
}
