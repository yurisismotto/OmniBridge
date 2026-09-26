#!/usr/bin/env bash
# autopilot-host.sh — the Fedora host: prerequisites, libvirt, the wired NIC the
# guests are bridged onto, memory, and "one VM at a time".
#
# Nothing here installs anything or runs sudo. A missing prerequisite is ONE
# stop that prints the exact command for the operator, and nothing else is done
# in that invocation.

# shellcheck disable=SC2034

AP_CONNECT="${GA_CONNECT:-qemu:///system}"
AP_POOL="${AP_POOL:-default}"
# C locale: this host's virsh speaks Portuguese otherwise ("Estado: executando").
ap_virsh() { LC_ALL=C virsh -c "$AP_CONNECT" "$@"; }

# tool:package — the Fedora package that provides each host tool.
AP_HOST_TOOLS=(
    virsh:libvirt-client virt-install:virt-install virt-viewer:virt-viewer qemu-img:qemu-img
    jq:jq curl:curl gpg:gnupg2 sha256sum:coreutils flock:util-linux taskset:util-linux
    setsid:util-linux ionice:util-linux xz:xz tar:tar git:git adb:android-tools
    qrencode:qrencode python3:python3 podman:podman cargo:cargo
)

# ap_host_prereqs — every tool present, one ISO writer, libvirt reachable.
ap_host_prereqs() {
    local tp t p missing=() pkgs=()
    for tp in "${AP_HOST_TOOLS[@]}"; do
        t="${tp%%:*}"; p="${tp#*:}"
        # A self-test hides a tool that the host does have (AP_TEST_HIDE_TOOLS).
        if [ "${AP_SELFTEST:-0}" = 1 ] && [[ " ${AP_TEST_HIDE_TOOLS:-} " == *" $t "* ]]; then :
        else command -v "$t" >/dev/null 2>&1 && continue; fi
        missing+=("$t")
        case " ${pkgs[*]} " in *" $p "*) : ;; *) pkgs+=("$p") ;; esac
    done
    if ! command -v genisoimage >/dev/null 2>&1 && ! command -v xorriso >/dev/null 2>&1; then
        missing+=(genisoimage); pkgs+=(genisoimage)
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        ap_stop "host prerequisites missing: ${missing[*]}" \
            "Nothing was installed and nothing else was done. Run this once, then run the autopilot again:" \
            "" "    sudo dnf install -y ${pkgs[*]}" ""
    fi
    ap_virsh uri >/dev/null 2>&1 \
        || ap_stop "libvirt at $AP_CONNECT is not reachable as $(id -un)" \
            "The gates drive guests through qemu:///system without sudo; that needs membership of the libvirt group:" \
            "" "    sudo usermod -aG libvirt $(id -un)      # then log out and in again" ""
    grep -Eq '^(State|Estado):[[:space:]]+(running|executando)' <<<"$(ap_virsh pool-info "$AP_POOL" 2>/dev/null)" \
        || ap_stop "the libvirt storage pool '$AP_POOL' is not active" \
            "" "    virsh -c $AP_CONNECT pool-start $AP_POOL" ""
}

# ap_pool_free_gib — free space in the pool, whole GiB.
ap_pool_free_gib() {
    ap_virsh pool-info "$AP_POOL" --bytes 2>/dev/null \
        | awk -F: '/^(Available|Disponível)/ { gsub(/[^0-9]/, "", $2); printf "%d", $2 / 1073741824; f = 1 } END { if (!f) exit 1 }'
}
ap_need_pool_space() { # GIB WHY
    local free
    free="$(ap_pool_free_gib)" || ap_stop "cannot read the free space of pool '$AP_POOL'"
    [ "$free" -ge "$1" ] || ap_stop "pool '$AP_POOL' has ${free} GiB free; $2 needs about $1 GiB" \
        "Nothing was created. Free space under the pool's directory (never the evidence), then resume."
}

# ap_detect_nic — the wired interface the guests are bridged onto with macvtap
# (lifecycle-peer-gates.sh: mDNS and inbound TCP 55432 must flow between the
# guest and the phone; macvtap over Wi-Fi is impossible at the driver level).
# --nic IF wins; otherwise exactly one physical, wired, up interface with
# carrier. Anything else is a stop that names the choice. Sets NIC; never
# called inside $(…), where a stop would only end the subshell.
ap_detect_nic() {
    local sys="${AP_SYSFS_NET:-/sys/class/net}" n c=() want="${AP_NIC:-}"
    NIC=""
    if [ -n "$want" ]; then
        [ -e "$sys/$want" ] || ap_stop "--nic $want: no such interface"
        [ "$(cat "$sys/$want/carrier" 2>/dev/null)" = 1 ] \
            || ap_stop "--nic $want has no carrier" "Plug in its cable (or the USB Ethernet adapter), then resume."
        NIC="$want"; return
    fi
    for n in "$sys"/*; do
        n="${n##*/}"
        case "$n" in lo|wl*|virbr*|vnet*|macvtap*|tap*|docker*|podman*|veth*|br-*|tun*|wg*) continue ;; esac
        [ -e "$sys/$n/device" ] || continue
        [ -d "$sys/$n/wireless" ] && continue
        [ "$(cat "$sys/$n/carrier" 2>/dev/null)" = 1 ] || continue
        c+=("$n")
    done
    case "${#c[@]}" in
        1) NIC="${c[0]}" ;;
        0) ap_stop "no wired network interface with carrier" \
               "The guests sit on the physical LAN through macvtap, which needs a wired NIC (not Wi-Fi)." \
               "Connect the Ethernet cable / USB adapter, then resume (or name one with --nic IF)." ;;
        *) ap_stop "several wired interfaces have carrier: ${c[*]}" "Name the one on the phone's LAN with --nic IF." ;;
    esac
}

# ap_wait_memory NEED_MIB WHAT — pause, never launch, while the host is short.
ap_wait_memory() {
    local need="$1" what="$2" have waited=0 limit="${AP_MEM_WAIT:-1800}" poll="${AP_POLL:-30}" said=0
    while :; do
        have="$(ap_mem_available_mib)" || ap_stop "cannot read MemAvailable from ${AP_MEMINFO:-/proc/meminfo}"
        [ "$have" -ge "$need" ] && { [ "$said" = 0 ] || ap_say INFO "memory recovered (${have} MiB available); continuing"; return 0; }
        if [ "$said" = 0 ]; then
            ap_say WAIT "$what paused — ${have} MiB available, ${need} MiB needed; waiting for the host to free memory"
            said=1
        fi
        [ "$waited" -lt "$limit" ] || ap_stop "$what not started: only ${have} MiB of memory available after ${waited}s (${need} MiB needed)" \
            "Close something on the workstation, then resume. Nothing was started."
        sleep "$poll"; waited=$(( waited + poll ))
    done
}

ap_running_domains() { ap_virsh list --name 2>/dev/null | sed '/^[[:space:]]*$/d'; }
# ap_one_vm TARGET — before TARGET starts: no other guest may run. Another
# autopilot guest is ours and is shut down cleanly; anything else is the
# operator's and is never touched.
ap_one_vm() {
    local target="$1" d others=()
    while IFS= read -r d; do
        [ -n "$d" ] && [ "$d" != "$target" ] || continue
        if ap_is_ours "$d"; then
            ap_say INFO "$d is still running from an earlier stage; shutting it down (one VM at a time)"
            ap_guest_shutdown "$d" || ap_stop "$d did not shut down; it was not forced" \
                "Shut it down yourself (virsh -c $AP_CONNECT shutdown $d), then resume."
        else
            others+=("$d")
        fi
    done < <(ap_running_domains)
    [ "${#others[@]}" -eq 0 ] || ap_stop "another VM is running: ${others[*]}" \
        "One test guest at a time, and the autopilot never touches a VM it did not create." \
        "Shut it down, then resume."
}

# Locks: one autopilot, and never alongside a manual coordinator run.
ap_take_locks() {
    local rt="${XDG_RUNTIME_DIR:-/tmp}"
    exec 8>"$rt/pliwee-pre-g8-autopilot.lock" || ap_stop "cannot open $rt/pliwee-pre-g8-autopilot.lock"
    flock -n 8 || ap_stop "another pre-g8-autopilot.sh is running (lock $rt/pliwee-pre-g8-autopilot.lock)"
    if [ -e "$rt/pliwee-pre-g8.lock" ] && ! flock -n "$rt/pliwee-pre-g8.lock" true 2>/dev/null; then
        ap_stop "pre-g8-manual-gates.sh is running (lock $rt/pliwee-pre-g8.lock); one gate at a time"
    fi
}

# ap_host_info — what the report records about this host.
ap_host_info() {
    printf 'hostname=%s\n' "$(hostname 2>/dev/null)"
    printf 'os=%s\n' "$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
    printf 'kernel=%s\n' "$(uname -r)"
    printf 'cpus=%s\n' "$(nproc 2>/dev/null)"
    printf 'cpu_model=%s\n' "$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)"
    printf 'mem_total_mib=%s\n' "$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' /proc/meminfo 2>/dev/null)"
    printf 'libvirt=%s\n' "$(ap_virsh version 2>/dev/null | tr '\n' ';' | sed 's/;*$//')"
    printf 'connect=%s\n' "$AP_CONNECT"
    printf 'pool=%s free_gib=%s\n' "$AP_POOL" "$(ap_pool_free_gib 2>/dev/null)"
}
