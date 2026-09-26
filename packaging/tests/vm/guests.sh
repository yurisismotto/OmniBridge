#!/usr/bin/env bash
# guests.sh — the autopilot's libvirt guests: one prepared template per
# distribution, and three disposable guests on top of it.
#
#   pliwee-g8-base-<d>.qcow2     the verified cloud image (images.sh)
#     └ pliwee-g8-<d>-tmpl.qcow2   the prepared desktop (cloud-init.sh), then
#       │                          generalised and never booted again
#       ├ pliwee-g8-<d>-chain      INSTALL U2 UPGRADE U6 SECLOG U10, one guest
#       ├ pliwee-g8-<d>-u8         U8 — a FRESH guest
#       └ pliwee-g8-<d>-lc         the lifecycle gates — a FRESH guest
#
# Every guest is a qcow2 overlay in the libvirt pool (qemu cannot read a 0700
# home directory, and the pool needs no sudo). A new guest boots once with its
# own seed, is checked, shut down, and snapshotted `ap-fresh` (an internal
# qcow2 snapshot, taken while off). A fresh-guest gate runs only on a guest
# that is at `ap-fresh` and has never been used; the chain gets a second
# snapshot, `ap-pre-upgrade`, before the upgrade stage first runs.
#
# IDENTITY. Each guest's record holds its domain UUID, MAC, disk volume and the
# template it was built on (whose own record holds the volume's size,
# allocation and mtime), and, from inside the guest, its machine-id, host name
# and a random identity token cloud-init wrote. All of it is checked before a
# guest is used; a guest that no longer matches is refused and left alone. A
# `pliwee-g8-*` domain or volume without a record is refused too: nothing here
# adopts, repairs or replaces a guest it cannot prove it created.
#
# ONE AT A TIME. Nothing starts while another guest runs (autopilot-host.sh
# ap_one_vm) or while the host is short of memory (ap_wait_memory). A chain
# guest is only ever shut down cleanly — ACPI, then the agent — never forced.

# shellcheck disable=SC2034

AP_GUEST_MEM_MIB="${AP_GUEST_MEM_MIB:-4096}"
AP_GUEST_VCPUS="${AP_GUEST_VCPUS:-2}"
AP_MEM_RESERVE_MIB="${AP_MEM_RESERVE_MIB:-2048}"
AP_DISK_GIB="${AP_DISK_GIB:-30}"
AP_BOOT_TIMEOUT="${AP_BOOT_TIMEOUT:-900}"
AP_TEMPLATE_TIMEOUT="${AP_TEMPLATE_TIMEOUT:-5400}"
# How long guest-exec may stay confined by SELinux before the template gives
# up: the prepare script lifts it a minute or two after boot (cloud-init.sh).
AP_CONFINED_LIMIT="${AP_CONFINED_LIMIT:-1800}"
AP_FAIL_DETAIL=()
AP_SHUTDOWN_TIMEOUT="${AP_SHUTDOWN_TIMEOUT:-300}"
AP_META_NS="https://github.com/yurisismotto/OmniBridge/pre-g8-autopilot"

ap_dom_exists() { grep -qxF -- "$1" <<<"$(ap_virsh list --all --name 2>/dev/null)"; }
ap_dom_state() { ap_virsh domstate "$1" 2>/dev/null | head -1; }
ap_dom_running() { [ "$(ap_dom_state "$1")" = running ]; }
ap_new_mac() { printf '52:54:00:%s' "$(od -An -N3 -tx1 /dev/urandom | tr -s ' ' ':' | sed 's/^://; s/:$//')"; }
ap_new_token() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

# ap_domain_xml NAME DISTRO ROLE DISK_VOL SEED_VOL MAC NIC — a minimal q35
# guest: BIOS boot (internal snapshots need no pflash), virtio disk from the
# pool, the NoCloud seed as a SATA cdrom, macvtap on the wired NIC, the agent
# channel, SPICE for the one GUI step, and our ownership in <metadata>.
ap_domain_xml() {
    local name="$1" d="$2" role="$3" disk="$4" seed="$5" mac="$6" nic="$7"
    cat <<EOF
<domain type='kvm'>
  <name>$name</name>
  <metadata>
    <g8:guest xmlns:g8='$AP_META_NS'><distro>$d</distro><role>$role</role></g8:guest>
  </metadata>
  <memory unit='MiB'>$AP_GUEST_MEM_MIB</memory>
  <currentMemory unit='MiB'>$AP_GUEST_MEM_MIB</currentMemory>
  <vcpu placement='static'>$AP_GUEST_VCPUS</vcpu>
  <os><type arch='x86_64' machine='q35'>hvm</type><boot dev='hd'/></os>
  <features><acpi/><apic/></features>
  <cpu mode='host-passthrough' check='none'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff><on_reboot>restart</on_reboot><on_crash>destroy</on_crash>
  <devices>
    <disk type='volume' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source pool='$AP_POOL' volume='$disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='volume' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source pool='$AP_POOL' volume='$seed'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='direct'>
      <mac address='$mac'/>
      <source dev='$nic' mode='bridge'/>
      <model type='virtio'/>
    </interface>
    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
    <channel type='spicevmc'><target type='virtio' name='com.redhat.spice.0'/></channel>
    <graphics type='spice'><listen type='none'/></graphics>
    <video><model type='virtio' heads='1' primary='yes'/></video>
    <controller type='usb' model='qemu-xhci'/>
    <input type='tablet' bus='usb'/>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
    <memballoon model='virtio'/>
    <serial type='pty'/>
    <console type='pty'/>
  </devices>
</domain>
EOF
}

# ap_dom_facts DOM — "uuid mac disk_volume nic metadata_role" as libvirt describes it now.
ap_dom_facts() {
    local x
    x="$(ap_virsh dumpxml --inactive "$1" 2>/dev/null)" || return 1
    [ -n "$x" ] || return 1
    python3 - "$x" "$AP_META_NS" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.fromstring(sys.argv[1]); ns = {"g8": sys.argv[2]}
def a(path, attr):
    e = r.find(path)
    return e.get(attr) if e is not None and e.get(attr) else "-"
disk = "-"
for d in r.findall("devices/disk"):
    if d.get("device") == "disk":
        s = d.find("source"); disk = (s.get("volume") or s.get("file") or "-") if s is not None else "-"
        break
role = r.find("metadata/g8:guest/g8:role", ns)
print((r.findtext("uuid") or "-").strip(), a("devices/interface/mac", "address"), disk,
      a("devices/interface/source", "dev"), role.text if role is not None else "-")
PY
}

# ap_probe DOM — one guest-exec, key=value lines: what the autopilot checks
# inside a guest. The marker comment lets a self-test's fake guest answer it.
# The last group is diagnosis only, for ap_probe_summary. When the agent itself
# fails, its error comes back as probe_error= instead of being thrown away: an
# empty probe is not "not ready yet", it is "not observed".
ap_probe() {
    local out rc
    out="$(ga_exec "$1" '# ap-probe
echo "identity=$(cat /var/lib/pliwee-g8/identity 2>/dev/null)"
echo "template_ready=$(test -e /var/lib/pliwee-g8/template-ready && echo yes)"
echo "machine_id=$(cat /etc/machine-id 2>/dev/null)"
echo "hostname=$(hostname 2>/dev/null)"
cis="$(cloud-init status --long 2>/dev/null)"
echo "cloud_init=$(printf "%s\n" "$cis" | sed -n "s/^status: //p")"
echo "ci_extended=$(printf "%s\n" "$cis" | sed -n "s/^extended_status: //p")"
echo "ci_error=$(printf "%s\n" "$cis" | sed -n "/^errors:/{n;p;}" | sed "s/^[[:space:]]*- //" | cut -c1-160)"
echo "user_uid=$(id -u '"$AP_GUEST_USER"' 2>/dev/null)"
s="$(loginctl show-user '"$AP_GUEST_USER"' -p Display --value 2>/dev/null)"
echo "session_type=$([ -n "$s" ] && loginctl show-session "$s" -p Type --value 2>/dev/null)"
echo "default_target=$(systemctl get-default 2>/dev/null)"
echo "os=$(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
echo "kernel=$(uname -r)"
echo "sel_context=$(tr -d "\0" < /proc/self/attr/current 2>/dev/null)"
echo "sel_enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null)"
echo "datasource=$(cat /run/cloud-init/cloud-id 2>/dev/null)"
echo "pkg_procs=$(pgrep -c -x "dnf|dnf5|dnf-3|rpm|apt-get|apt|dpkg" 2>/dev/null)"
echo "net_ipv4=$(ip -4 -o addr show scope global 2>/dev/null | awk "{print \$4}" | head -1)"
echo "prepare_stage=$(grep "^== " /var/log/pliwee-g8-prepare.log 2>/dev/null | tail -1 | cut -c4-80)"
echo "prepare_running=$(pgrep -c -f "^/bin/sh /usr/local/sbin/pliwee-g8-prepare" 2>/dev/null)"
echo "prepare_failed=$(cat /var/lib/pliwee-g8/template-failed 2>/dev/null)"
echo "prepare_error=$(grep -m1 -A1 -E "dpkg: error processing|^E: |^Error: " /var/log/pliwee-g8-prepare.log 2>/dev/null | tr "\n" " " | cut -c1-200)"
echo "uptime_s=$(cut -d. -f1 /proc/uptime 2>/dev/null)"' 2>&1)"; rc=$?
    grep -E '^[a-z_0-9]+=' <<<"$out"
    [ "$rc" = 0 ] || printf 'probe_error=%s\n' "$(grep -vE '^[a-z_0-9]+=' <<<"$out" | tr '\n' ' ' | cut -c1-240)"
}
ap_kv() { sed -n "s/^$2=//p" <<<"$1" | head -1; }   # TEXT KEY

# ap_probe_confined PROBE — guest-exec answered, but SELinux kept it from
# reading what the probe asks: uname answered, yet neither the host name nor
# cloud-init's status nor the default target could be read, and the command
# ran in the agent's domain (or its own context was unreadable too). This is
# what the first real Fedora 44 template looked like, for 50 minutes, from
# the host. A working guest always has a host name.
ap_probe_confined() {
    [ -n "$(ap_kv "$1" kernel)" ] && [ -z "$(ap_kv "$1" hostname)" ] && [ -z "$(ap_kv "$1" cloud_init)" ] \
        && [ -z "$(ap_kv "$1" default_target)" ] || return 1
    case "$(ap_kv "$1" sel_context)" in ""|*virt_qemu_ga_t*) return 0 ;; esac
    return 1
}
# ap_probe_summary PROBE — one line saying what the guest is doing, as far as
# the host can observe it. Every clause is a measurement or says it is missing.
ap_probe_summary() {
    local p="$1" ci s=() sel_ctx sel_enf ci_ext ci_err
    ci_ext="$(ap_kv "$p" ci_extended)"; ci_err="$(ap_kv "$p" ci_error)"
    sel_ctx="$(ap_kv "$p" sel_context)"; sel_enf="$(ap_kv "$p" sel_enforce)"
    if [ -n "$(ap_kv "$p" probe_error)" ] && [ -z "$(ap_kv "$p" kernel)" ]; then
        printf 'QGA unavailable or guest-exec failed: %s' "$(ap_kv "$p" probe_error)"; return
    fi
    [ -n "$(ap_kv "$p" kernel)" ] || { printf 'no probe output (guest-exec returned nothing)'; return; }
    if ap_probe_confined "$p"; then
        s+=("guest-exec confined by SELinux (${sel_ctx:-context unreadable}, enforce=${sel_enf:-unreadable}): cloud-init, host name and marker unreadable")
    else
        ci="$(ap_kv "$p" cloud_init)"
        case "$ci" in
            "") s+=("cloud-init status unreadable") ;;
            disabled) s+=("cloud-init disabled: guest booted but no datasource") ;;
            error) s+=("cloud-init error${ci_ext:+ ($ci_ext)}${ci_err:+: $ci_err}")
               [ -n "$(ap_kv "$p" datasource)" ] || s+=("datasource missing") ;;
            *) s+=("cloud-init ${ci}")
               [ -n "$(ap_kv "$p" datasource)" ] || s+=("datasource missing") ;;
        esac
    fi
    [ -z "$(ap_kv "$p" prepare_failed)" ] || s+=("prepare FAILED ($(ap_kv "$p" prepare_failed))")
    case "$(ap_kv "$p" pkg_procs)" in
        ""|0) : ;; *) s+=("package transaction active ($(ap_kv "$p" pkg_procs) processes)") ;;
    esac
    if [ -n "$(ap_kv "$p" net_ipv4)" ]; then s+=("net $(ap_kv "$p" net_ipv4)"); else s+=("network: no IPv4 address"); fi
    [ -z "$(ap_kv "$p" prepare_stage)" ] || s+=("prepare: $(ap_kv "$p" prepare_stage)")
    s+=("marker $([ "$(ap_kv "$p" template_ready)" = yes ] && echo present || echo absent)")
    local IFS=';'; printf '%s' "${s[*]}" | sed 's/;/; /g'
}

# ap_probe_terminal PROBE — the template's preparation has ended without its
# marker, and nothing left in the guest can still write it. Prints why. Only
# two observations count, because only they are final:
#   * the prepare script recorded its own failure (template-failed: it exited
#     non-zero and wrote no marker);
#   * cloud-init has finished every stage with an error ("error - done"), and
#     neither the prepare script nor a package manager is running.
# A cloud-init error while it is still running, a package transaction in
# progress, or anything the probe could not read is NOT terminal: waiting goes
# on. (The first real TEMPLATE-ubuntu2404 reached "error - done" at 960 s,
# runcmd exit 100, and was then waited on until 5400 s.)
ap_probe_terminal() {
    local p="$1" pf
    [ "$(ap_kv "$p" template_ready)" = yes ] && return 1
    pf="$(ap_kv "$p" prepare_failed)"
    if [ -n "$pf" ]; then
        printf 'the prepare script failed (%s)' "$pf"; return 0
    fi
    if [ "$(ap_kv "$p" cloud_init)" = error ] && [[ "$(ap_kv "$p" ci_extended)" == *done* ]] \
        && [ "$(ap_kv "$p" prepare_running)" = 0 ] && [ "$(ap_kv "$p" pkg_procs)" = 0 ]; then
        printf 'cloud-init finished with an error and nothing running can still write the marker'; return 0
    fi
    return 1
}

# ap_wait_probe DOM TIMEOUT WHAT CONDITION_FN [TERMINAL_FN] — poll the probe
# until CONDITION_FN (given the probe text) succeeds. Sets PROBE, and WAIT_WHY
# to why it gave up: timeout, not-running, confined (guest-exec stayed confined
# by SELinux for AP_CONFINED_LIMIT seconds — waiting longer cannot help), or
# terminal (TERMINAL_FN said the work has ended without success; its words are
# in WAIT_DETAIL).
ap_wait_probe() {
    local dom="$1" limit="$2" what="$3" fn="$4" term="${5:-}" waited=0 poll="${AP_POLL:-30}" next_say="${AP_SAY_EVERY:-300}" confined=0
    local seen="" now
    PROBE=""; WAIT_WHY=""; WAIT_DETAIL=""
    while [ "$waited" -lt "$limit" ]; do
        PROBE="$(ap_probe "$dom")"
        # The journal keeps every change in what the guest was observed doing.
        now="$(ap_probe_summary "$PROBE")"
        [ "$now" = "$seen" ] || { ap_log "$what — observed at ${waited}s (up $(ap_kv "$PROBE" uptime_s)s): $now"; seen="$now"; }
        "$fn" "$PROBE" && return 0
        ap_dom_running "$dom" || { WAIT_WHY=not-running; return 1; }
        if [ -n "$term" ] && WAIT_DETAIL="$("$term" "$PROBE")"; then
            WAIT_WHY=terminal; WAIT_WAITED="$waited"; return 1
        fi
        WAIT_DETAIL=""
        if ap_probe_confined "$PROBE"; then
            confined=$(( confined + poll ))
            [ "$confined" -lt "$AP_CONFINED_LIMIT" ] || { WAIT_WHY=confined; return 1; }
        else
            confined=0
        fi
        if [ "$waited" -ge "$next_say" ]; then
            ap_say INFO "$what — still waiting (${waited}s of ${limit}s; $now)"
            next_say=$(( next_say + ${AP_SAY_EVERY:-300} ))
        fi
        sleep "$poll"; waited=$(( waited + poll ))
    done
    WAIT_WHY=timeout
    return 1
}

# ------------------------------------------------------------ start / stop --
# ap_guest_boot DOM [AGENT_TIMEOUT] — start it (one VM, enough memory) and wait
# for the agent. A template's first boot passes AP_TEMPLATE_TIMEOUT: some cloud
# images only get qemu-guest-agent from cloud-init, minutes after boot.
ap_guest_power_on() { # DOM — one VM, enough memory, started
    ap_one_vm "$1"
    ap_wait_memory $(( AP_GUEST_MEM_MIB + AP_MEM_RESERVE_MIB )) "starting $1"
    ap_virsh start "$1" >/dev/null || ap_stop "libvirt refused to start $1"
    ap_log "started $1"
}
ap_guest_boot() {
    local dom="$1" agent_wait="${2:-$AP_BOOT_TIMEOUT}"
    ap_dom_running "$dom" && { ga_ping "$dom" "$agent_wait" >/dev/null 2>&1; return; }
    ap_guest_power_on "$dom"
    ga_ping "$dom" "$agent_wait" >/dev/null 2>&1 \
        || ap_stop "$dom booted but its guest agent did not answer within ${agent_wait}s" \
            "Running does not mean ready; nothing was run on it. It was left running for inspection (--cleanup-vms stops it)."
}
# ap_guest_shutdown DOM — clean power-off, or failure. Never forced.
ap_guest_shutdown() {
    local dom="$1" waited=0 poll="${AP_POLL:-30}" mode
    ap_dom_running "$dom" || return 0
    for mode in acpi agent; do
        ap_virsh shutdown --mode "$mode" "$dom" >/dev/null 2>&1 || true
        waited=0
        while [ "$waited" -lt "$AP_SHUTDOWN_TIMEOUT" ]; do
            ap_dom_running "$dom" || { ap_log "shut down $dom ($mode)"; return 0; }
            sleep "$((poll < 5 ? poll : 5))"; waited=$(( waited + (poll < 5 ? poll : 5) ))
        done
    done
    return 1
}
ap_guest_shutdown_or_stop() {
    ap_guest_shutdown "$1" || ap_stop "$1 did not shut down cleanly within $((2 * AP_SHUTDOWN_TIMEOUT))s; it was not forced" \
        "Look at it (virt-viewer -c $AP_CONNECT --attach $1), shut it down, then resume."
}

# ------------------------------------------------------------- the template --
ap_tmpl_vol() { printf 'pliwee-g8-%s-tmpl.qcow2' "$(ap_abbr "$1")"; }
ap_tmpl_ready_fn() {
    [ "$(ap_kv "$1" template_ready)" = yes ] && [ "$(ap_kv "$1" user_uid)" = "$AP_GUEST_UID" ] \
        && [ "$(ap_kv "$1" default_target)" = graphical.target ]
}
ap_session_fn() { case "$(ap_kv "$1" session_type)" in wayland|x11) return 0 ;; esac; return 1; }

# ap_template_check DOM — what the gate harnesses need from a template, read
# from the prepared guest after its reboot: key=value lines.
ap_template_check() {
    ga_exec "$1" '# ap-template-check
q() { for n in "$@"; do
        if command -v rpm >/dev/null; then
            rpm -q "$n" >/dev/null 2>&1 && { rpm -q --qf "%{VERSION}-%{RELEASE}" "$n"; return; }
        else
            v="$(dpkg-query -W -f="\${Status} \${Version}" "$n" 2>/dev/null)"
            case "$v" in "install ok installed "*) echo "${v##* }"; return ;; esac
        fi
      done; }
echo "pkg_gnome_shell=$(q gnome-shell)"
echo "pkg_gdm=$(q gdm gdm3)"
echo "pkg_qga=$(q qemu-guest-agent)"
c="$(cat /var/lib/pliwee-g8/gdm-conf 2>/dev/null)"
echo "gdm_conf=$c"
echo "gdm_conf_read_by_gdm=$([ -n "$c" ] && grep -aqF "$c" /usr/libexec/gdm-session-worker 2>/dev/null && echo yes)"
echo "autologin=$([ -n "$c" ] && grep -qx "AutomaticLoginEnable=True" "$c" 2>/dev/null && sed -n "s/^AutomaticLogin=//p" "$c" | head -1)"
echo "no_lock=$(grep -qx "lock-enabled=false" /etc/dconf/db/local.d/00-pliwee-g8 2>/dev/null && echo yes)"
echo "initial_setup_done=$(test -e /home/'"$AP_GUEST_USER"'/.config/gnome-initial-setup-done && echo yes)"
echo "default_target=$(systemctl get-default 2>/dev/null)"
echo "selinux=$(getenforce 2>/dev/null)"
echo "qga_permissive=$(semodule -l 2>/dev/null | grep -x pliwee-g8-qga >/dev/null && echo yes)"
echo "marker=$(cat /var/lib/pliwee-g8/template-ready 2>/dev/null)"' 2>&1
}
# ap_template_check_fn CHECK — every line present and as required. On an SELinux
# guest the system must still be Enforcing: only the agent's domain was changed.
ap_template_check_fn() {
    local c="$1" k
    for k in pkg_gnome_shell pkg_gdm pkg_qga marker gdm_conf; do [ -n "$(ap_kv "$c" "$k")" ] || return 1; done
    [ "$(ap_kv "$c" gdm_conf_read_by_gdm)" = yes ] || return 1
    [ "$(ap_kv "$c" autologin)" = "$AP_GUEST_USER" ] && [ "$(ap_kv "$c" no_lock)" = yes ] \
        && [ "$(ap_kv "$c" initial_setup_done)" = yes ] && [ "$(ap_kv "$c" default_target)" = graphical.target ] || return 1
    case "$(ap_kv "$c" selinux)" in
        "") return 0 ;;
        Enforcing) [ "$(ap_kv "$c" qga_permissive)" = yes ] ;;
        *) return 1 ;;
    esac
}

# ap_template_verify DISTRO — its record says ready, and the volume is unchanged.
ap_template_verify() {
    local d="$1" rec="template-$1" vol facts
    vol="$(ap_tmpl_vol "$d")"
    facts="$(ap_vol_facts "$vol")" || ap_stop "the $d template volume $vol is gone from pool $AP_POOL" \
        "Every $d guest is an overlay on it. --cleanup-vms retires them; then resume to rebuild."
    [ "$facts" = "$(ap_rec_get "$rec" facts)" ] \
        || ap_stop "the $d template volume $vol no longer matches its record" \
            "recorded: $(ap_rec_get "$rec" facts)" "now:      $facts" \
            "Something wrote to a backing file every $d guest depends on. Refusing to continue."
}

# ap_template_diagnose DOM DIR — everything the host can learn about a guest
# whose preparation did not finish, into DIR: the last probe and its reading,
# libvirt's view, the agent's own view (no guest-exec needed), and the guest's
# logs through guest-exec. A step that cannot be observed says so in its file.
ap_template_diagnose() {
    local dom="$1" dir="$2" q
    mkdir -p "$dir" || return 1
    printf '%s\n' "$PROBE" > "$dir/probe.txt"
    printf '%s\n' "$(ap_probe_summary "$PROBE")" > "$dir/summary.txt"
    { ap_virsh dominfo "$dom"; ap_virsh domstate --reason "$dom"; } > "$dir/libvirt.txt" 2>&1
    for q in guest-ping guest-info guest-get-osinfo guest-network-get-interfaces; do
        printf '## %s\n' "$q"
        ap_virsh qemu-agent-command "$dom" "{\"execute\":\"$q\"}" 2>&1 || printf '(no answer: exit %s)\n' "$?"
    done > "$dir/qga.txt"
    ga_exec "$dom" '# ap-diagnose
for f in /var/log/pliwee-g8-prepare.log /var/log/cloud-init-output.log /var/log/cloud-init.log; do
    echo "## tail $f"; tail -n 200 "$f" 2>&1
done
echo "## cloud-init status --long"; cloud-init status --long 2>&1
echo "## semodule -l | grep pliwee"; semodule -l 2>&1 | grep pliwee
echo "## package processes"; pgrep -a -x "dnf|dnf5|dnf-3|rpm|apt-get|apt|dpkg" 2>&1
echo "## ip -br addr"; ip -br addr 2>&1
echo "## resolv.conf"; cat /etc/resolv.conf 2>&1
echo "## AVC denials (last 40)"; grep -h "avc: *denied" /var/log/audit/audit.log 2>&1 | tail -n 40
echo "## journal warnings (last 100)"; journalctl -b -p warning --no-pager 2>&1 | tail -n 100' \
        > "$dir/guest-logs.txt" 2>&1 || printf '\n(guest-exec failed: exit %s)\n' "$?" >> "$dir/guest-logs.txt"
}

# ap_template_fail DISTRO DOM WHY — the template's preparation did not finish.
# Infrastructure, not a gate: no gate is run, recorded or failed. The logs are
# kept, the guest is shut down cleanly (never forced), the record says failed,
# and a resume discards it and builds the template again.
ap_template_fail() {
    local d="$1" dom="$2" why="$3" dir stopped
    dir="$AP_STATE/templates/$d/failure.$(ap_stamp)"
    ap_template_diagnose "$dom" "$dir"
    if ap_guest_shutdown "$dom"; then stopped="shut down cleanly"
    else stopped="did NOT shut down within $((2 * AP_SHUTDOWN_TIMEOUT))s and was not forced; shut it down yourself"; fi
    ap_rec_set "template-$d" "state=failed" "failed_utc=$(ap_utc)" "failed_why=$(tr '\n' ' ' <<<"$why")" "failure_dir=$dir" \
        || ap_say WARN "cannot record the $d template's failure"
    ap_stop "TEMPLATE-$d — infrastructure preparation FAILED: $why (no gate was run or recorded)" \
        "${AP_FAIL_DETAIL[@]}" \
        "last observed: $(ap_probe_summary "$PROBE")" \
        "diagnosis:     $dir/summary.txt" \
        "guest logs:    $dir/guest-logs.txt" \
        "agent view:    $dir/qga.txt" \
        "$dom $stopped. Resuming discards it and builds the template again."
}

# ap_template_ensure DISTRO — the prepared, generalised desktop for DISTRO.
ap_template_ensure() {
    local d="$1" rec="template-$1" vol dom seed host pw hash mac nic xml facts
    vol="$(ap_tmpl_vol "$d")"; dom="pliwee-g8-$(ap_abbr "$d")-tmpl"; seed="pliwee-g8-$(ap_abbr "$d")-tmpl-seed.iso"
    host="g8-$(ap_abbr "$d")-tmpl"
    if [ "$(ap_rec_get "$rec" state 2>/dev/null)" = ready ]; then ap_template_verify "$d"; return 0; fi
    ap_base_ensure "$d"
    case "$(ap_rec_get "$rec" state 2>/dev/null)" in building|failed)
        ap_say INFO "TEMPLATE-$d — an unfinished build ($(ap_rec_get "$rec" state)) is discarded and started again (a template is not evidence)"
        ap_dom_running "$dom" && ap_virsh destroy "$dom" >/dev/null 2>&1
        ap_dom_exists "$dom" && ap_virsh undefine "$dom" --snapshots-metadata >/dev/null 2>&1
        ap_vol_exists "$vol" && ap_virsh vol-delete --pool "$AP_POOL" "$vol" >/dev/null
        ap_vol_exists "$seed" && ap_virsh vol-delete --pool "$AP_POOL" "$seed" >/dev/null
    esac
    if ap_dom_exists "$dom" || ap_vol_exists "$vol"; then
        ap_stop "$dom / $vol exist, but no record says this autopilot created them" \
            "Refusing to use or replace them. Remove them yourself if they are stale, then resume."
    fi
    ap_need_pool_space 20 "the $d template"
    ap_detect_nic; nic="$NIC"; mac="$(ap_new_mac)"
    mkdir -p "$AP_STATE/templates/$d" || ap_stop "cannot create $AP_STATE/templates/$d"
    pw="$AP_STATE/templates/$d/$AP_GUEST_USER-password"
    hash=""
    if command -v openssl >/dev/null 2>&1; then
        ( umask 077; od -An -N12 -tx1 /dev/urandom | tr -d ' \n' > "$pw" )
        hash="$(openssl passwd -6 -stdin < "$pw" 2>/dev/null)" || hash=""
    fi
    ap_rec_put "$rec" "state=building" "domain=$dom" "volume=$vol" "seed=$seed" "base=$BASE_VOL" \
        "nic=$nic" "mac=$mac" "started_utc=$(ap_utc)" || ap_stop "cannot record the $d template"
    ap_seed_iso "$AP_STATE/templates/$d/seed.iso" "$(ap_seed_userdata_template "$d" "$host" "$hash")" "g8-tmpl-$d-$(ap_stamp)" \
        || ap_stop "cannot build the $d template's cloud-init seed"
    cp "$AP_STATE/templates/$d/seed.iso" "$AP_STATE/templates/$d/seed.$(ap_stamp).iso" 2>/dev/null || true
    ap_virsh vol-create-as --pool "$AP_POOL" --name "$vol" --capacity "${AP_DISK_GIB}G" --format qcow2 \
        --backing-vol "$BASE_VOL" --backing-vol-format qcow2 >/dev/null || ap_stop "cannot create the $d template overlay $vol"
    ap_vol_upload "$seed" "$AP_STATE/templates/$d/seed.iso" || ap_stop "cannot upload the $d template seed"
    xml="$AP_STATE/templates/$d/domain.xml"
    ap_domain_xml "$dom" "$d" tmpl "$vol" "$seed" "$mac" "$nic" > "$xml"
    ap_virsh define "$xml" >/dev/null || ap_stop "libvirt refused the $d template definition ($xml)"
    ap_say RUN "TEMPLATE-$d — installing a GNOME desktop into $dom (unattended; typically 5-60 min, at most ${AP_TEMPLATE_TIMEOUT}s)"
    ap_guest_power_on "$dom"
    PROBE=""
    ga_ping "$dom" "$AP_TEMPLATE_TIMEOUT" >/dev/null 2>&1 \
        || ap_template_fail "$d" "$dom" "QGA unavailable: the guest agent did not answer within ${AP_TEMPLATE_TIMEOUT}s of boot"
    if ! ap_wait_probe "$dom" "$AP_TEMPLATE_TIMEOUT" "TEMPLATE-$d" ap_tmpl_ready_fn ap_probe_terminal; then
        case "$WAIT_WHY" in
            terminal)
                AP_FAIL_DETAIL=(
                    "cloud-init:      $(ap_kv "$PROBE" cloud_init)${PROBE:+ ($(ap_kv "$PROBE" ci_extended))}"
                    "failing module:  $(ap_kv "$PROBE" ci_error)"
                    "prepare:         $(ap_kv "$PROBE" prepare_stage)${PROBE:+; $(ap_kv "$PROBE" prepare_failed)}"
                    "package manager: $([ "$(ap_kv "$PROBE" pkg_procs)" = 0 ] && echo inactive || echo "$(ap_kv "$PROBE" pkg_procs) process(es)")"
                    "reason:          $(ap_kv "$PROBE" prepare_error)")
                ap_template_fail "$d" "$dom" "reached a terminal error after ${WAIT_WAITED}s: $WAIT_DETAIL" ;;
            confined) ap_template_fail "$d" "$dom" "guest-exec stayed confined by SELinux for ${AP_CONFINED_LIMIT}s; the template's readiness cannot be observed" ;;
            not-running) ap_template_fail "$d" "$dom" "the guest stopped running during preparation" ;;
            *) ap_template_fail "$d" "$dom" "not ready after ${AP_TEMPLATE_TIMEOUT}s" ;;
        esac
    fi
    printf '%s\n' "$PROBE" > "$AP_STATE/templates/$d/prepared-probe.txt"
    ap_say INFO "TEMPLATE-$d — prepared; rebooting once to prove a graphical session comes up by itself"
    ap_guest_shutdown_or_stop "$dom"
    ap_guest_power_on "$dom"
    ga_ping "$dom" "$AP_BOOT_TIMEOUT" >/dev/null 2>&1 \
        || ap_template_fail "$d" "$dom" "QGA unavailable after the proving reboot (no answer within ${AP_BOOT_TIMEOUT}s)"
    ap_wait_probe "$dom" "$AP_BOOT_TIMEOUT" "TEMPLATE-$d session" ap_session_fn \
        || ap_template_fail "$d" "$dom" "no graphical session for $AP_GUEST_USER after a reboot (session: '$(ap_kv "$PROBE" session_type)')"
    local check
    check="$(ap_template_check "$dom")"
    printf '%s\n' "$check" > "$AP_STATE/templates/$d/readiness.txt"
    ap_template_check_fn "$check" \
        || ap_template_fail "$d" "$dom" "the readiness check did not pass: $(tr '\n' ' ' <<<"$check" | cut -c1-400)"
    ga_exec "$dom" 'if command -v rpm >/dev/null; then rpm -qa | sort; else dpkg-query -W | sort; fi' \
        > "$AP_STATE/templates/$d/packages.txt" 2>/dev/null
    [ -s "$AP_STATE/templates/$d/packages.txt" ] \
        || ap_template_fail "$d" "$dom" "the package list came back empty; the template is not described"
    printf '%s\n' "$PROBE" > "$AP_STATE/templates/$d/probe.txt"
    ga_exec "$dom" '# ap-generalize
cloud-init clean --logs --machine-id --seed >/dev/null 2>&1 || { rm -rf /var/lib/cloud/instances /var/lib/cloud/instance; : > /etc/machine-id; }
rm -f /var/lib/pliwee-g8/identity
sync
(sleep 2; systemctl poweroff) >/dev/null 2>&1 &' >/dev/null 2>&1
    local waited=0
    while ap_dom_running "$dom" && [ "$waited" -lt "$AP_SHUTDOWN_TIMEOUT" ]; do sleep 5; waited=$((waited + 5)); done
    ap_dom_running "$dom" && ap_stop "TEMPLATE-$d did not power off after generalising" "It was not forced; shut $dom down, then resume."
    ap_virsh undefine "$dom" --snapshots-metadata >/dev/null || ap_stop "cannot retire the template domain $dom"
    ap_virsh vol-delete --pool "$AP_POOL" "$seed" >/dev/null 2>&1 || true
    facts="$(ap_vol_facts "$vol")" || ap_stop "cannot describe $vol"
    ap_rec_put "$rec" "state=ready" "volume=$vol" "path=$(ap_vol_path "$vol")" "facts=$facts" "base=$BASE_VOL" \
        "base_sha256=$(ap_rec_get "base-$d" image_sha256)" "os=$(ap_kv "$PROBE" os)" "kernel=$(ap_kv "$PROBE" kernel)" \
        "packages=$AP_STATE/templates/$d/packages.txt" "packages_sha256=$(ap_sha "$AP_STATE/templates/$d/packages.txt")" \
        "readiness=$AP_STATE/templates/$d/readiness.txt" "readiness_sha256=$(ap_sha "$AP_STATE/templates/$d/readiness.txt")" \
        "password_file=$([ -n "$hash" ] && echo "$pw")" "built_utc=$(ap_utc)" || ap_stop "cannot record the $d template"
    ap_say PASS "TEMPLATE-$d — $(ap_kv "$PROBE" os), graphical session verified, generalised ($vol)"
}

# ------------------------------------------------------------ role guests --
ap_guest_rec() { printf 'guest-%s' "$1"; }
ap_role_ready_fn() {
    [ "$(ap_kv "$1" identity)" = "$AP_EXPECT_TOKEN" ] && [ "$(ap_kv "$1" hostname)" = "$AP_EXPECT_HOST" ] \
        && [ "$(ap_kv "$1" cloud_init)" != running ] && [ -n "$(ap_kv "$1" machine_id)" ] \
        && [ "$(ap_kv "$1" user_uid)" = "$AP_GUEST_UID" ] && ap_session_fn "$1"
}

# ap_guest_ensure DISTRO ROLE — the guest exists, as recorded. Creates it
# (fresh, snapshotted ap-fresh) when it does not. Sets GUEST.
ap_guest_ensure() {
    local d="$1" role="$2" dom rec vol seed host token mac nic xml st
    dom="$(ap_domain "$d" "$role")"; rec="$(ap_guest_rec "$dom")"; GUEST="$dom"
    vol="$dom.qcow2"; seed="$dom-seed.iso"; host="$(ap_hostname "$d" "$role")"
    st="$(ap_rec_get "$rec" state 2>/dev/null)"
    if [ "$st" = ready ]; then ap_guest_verify_static "$dom"; return 0; fi
    ap_template_ensure "$d"
    if [ "$st" = creating ]; then
        ap_say INFO "$dom — an interrupted creation is discarded (no gate ever ran on it) and done again"
        ap_dom_running "$dom" && ap_virsh destroy "$dom" >/dev/null 2>&1
        ap_dom_exists "$dom" && ap_virsh undefine "$dom" --snapshots-metadata >/dev/null 2>&1
        ap_vol_exists "$vol" && ap_virsh vol-delete --pool "$AP_POOL" "$vol" >/dev/null
        ap_vol_exists "$seed" && ap_virsh vol-delete --pool "$AP_POOL" "$seed" >/dev/null
    fi
    if ap_dom_exists "$dom" || ap_vol_exists "$vol"; then
        ap_stop "$dom exists, but no record says this autopilot created it" \
            "Refusing to use, adopt or replace it. Remove it yourself if it is stale, then resume."
    fi
    ap_need_pool_space 6 "guest $dom"
    ap_detect_nic; token="$(ap_new_token)"; mac="$(ap_new_mac)"; nic="$NIC"
    mkdir -p "$AP_STATE/guests/$dom" || ap_stop "cannot create $AP_STATE/guests/$dom"
    ap_rec_put "$rec" "state=creating" "domain=$dom" "distro=$d" "role=$role" "volume=$vol" "seed=$seed" \
        "hostname=$host" "token=$token" "mac=$mac" "nic=$nic" "template=$(ap_tmpl_vol "$d")" \
        "started_utc=$(ap_utc)" || ap_stop "cannot record $dom"
    ap_seed_iso "$AP_STATE/guests/$dom/seed.iso" "$(ap_seed_userdata_role "$host" "$token")" "$dom-$(ap_stamp)" \
        || ap_stop "cannot build the seed for $dom"
    ap_virsh vol-create-as --pool "$AP_POOL" --name "$vol" --capacity "${AP_DISK_GIB}G" --format qcow2 \
        --backing-vol "$(ap_tmpl_vol "$d")" --backing-vol-format qcow2 >/dev/null || ap_stop "cannot create the overlay $vol"
    ap_vol_upload "$seed" "$AP_STATE/guests/$dom/seed.iso" || ap_stop "cannot upload the seed for $dom"
    xml="$AP_STATE/guests/$dom/domain.xml"
    ap_domain_xml "$dom" "$d" "$role" "$vol" "$seed" "$mac" "$nic" > "$xml"
    ap_virsh define "$xml" >/dev/null || ap_stop "libvirt refused the definition of $dom ($xml)"
    ap_say RUN "GUEST-$dom — first boot from the $d template"
    ap_guest_boot "$dom"
    AP_EXPECT_TOKEN="$token"; AP_EXPECT_HOST="$host"
    ap_wait_probe "$dom" "$AP_BOOT_TIMEOUT" "GUEST-$dom" ap_role_ready_fn \
        || ap_stop "$dom did not come up as recorded (identity '$(ap_kv "$PROBE" identity)', host '$(ap_kv "$PROBE" hostname)', session '$(ap_kv "$PROBE" session_type)')" \
            "It is left as it is; resuming discards it and creates it again."
    printf '%s\n' "$PROBE" > "$AP_STATE/guests/$dom/first-boot-probe.txt"
    ap_guest_shutdown_or_stop "$dom"
    ap_virsh detach-disk "$dom" sda --config >/dev/null 2>&1 || ap_stop "cannot detach the seed from $dom"
    ap_virsh vol-delete --pool "$AP_POOL" "$seed" >/dev/null 2>&1 || true
    ap_virsh snapshot-create-as --domain "$dom" --name ap-fresh \
        --description "pre-g8-autopilot: never used by a gate" --atomic >/dev/null \
        || ap_stop "cannot snapshot $dom as ap-fresh"
    ap_rec_put "$rec" "state=ready" "domain=$dom" "distro=$d" "role=$role" "volume=$vol" "hostname=$host" \
        "token=$token" "machine_id=$(ap_kv "$PROBE" machine_id)" "mac=$mac" "nic=$nic" \
        "facts=$(ap_dom_facts "$dom")" "template=$(ap_tmpl_vol "$d")" \
        "template_facts=$(ap_rec_get "template-$d" facts)" "os=$(ap_kv "$PROBE" os)" \
        "created_utc=$(ap_utc)" "fresh=yes" || ap_stop "cannot record $dom"
    ap_say PASS "GUEST-$dom — created, identity recorded, snapshot ap-fresh"
}

# ap_guest_verify_static DOM — the libvirt side still matches the record.
ap_guest_verify_static() {
    local dom="$1" rec facts d
    rec="$(ap_guest_rec "$dom")"; d="$(ap_rec_get "$rec" distro)"
    ap_dom_exists "$dom" || ap_stop "$dom is recorded, but libvirt no longer has it" \
        "Its gates' evidence stays bound to the recorded guest. If it was removed on purpose: --cleanup-vms, then resume."
    facts="$(ap_dom_facts "$dom")" || ap_stop "cannot describe $dom"
    [ "$facts" = "$(ap_rec_get "$rec" facts)" ] || ap_stop "$dom no longer matches its recorded identity" \
        "recorded: $(ap_rec_get "$rec" facts)" "now:      $facts" \
        "(uuid, mac, disk volume, nic, role). Refusing to use it; nothing was changed."
    ap_template_verify "$d"
    [ "$(ap_rec_get "$rec" template_facts)" = "$(ap_rec_get "template-$d" facts)" ] \
        || ap_stop "$dom was built on a template that is not the one recorded now"
    [ "$(ap_vol_facts "$(ap_rec_get "$rec" volume)" | awk '{print $4}')" = "$(ap_rec_get "template-$d" path)" ] \
        || ap_stop "$dom's disk is no longer an overlay on the recorded $d template"
    [ -e "${AP_SYSFS_NET:-/sys/class/net}/$(ap_rec_get "$rec" nic)" ] \
        || ap_stop "$dom is bridged onto $(ap_rec_get "$rec" nic), which this host no longer has" \
            "Plug the adapter back in (the guests' MAC and LAN placement depend on it), then resume."
}
# ap_guest_start DOM — boot a recorded guest and prove, from inside, it is it.
ap_guest_start() {
    local dom="$1" rec
    rec="$(ap_guest_rec "$dom")"
    ap_guest_verify_static "$dom"
    ap_guest_boot "$dom"
    AP_EXPECT_TOKEN="$(ap_rec_get "$rec" token)"; AP_EXPECT_HOST="$(ap_rec_get "$rec" hostname)"
    if ! ap_wait_probe "$dom" "$AP_BOOT_TIMEOUT" "$dom" ap_role_ready_fn; then
        ap_guest_shutdown "$dom" || true
        ap_stop "$dom is not the recorded guest, or not ready" \
            "identity token: recorded $(ap_rec_get "$rec" token), now '$(ap_kv "$PROBE" identity)'" \
            "host name:      recorded $(ap_rec_get "$rec" hostname), now '$(ap_kv "$PROBE" hostname)'" \
            "session:        '$(ap_kv "$PROBE" session_type)'" \
            "Refusing to run a gate on it."
    fi
    [ "$(ap_kv "$PROBE" machine_id)" = "$(ap_rec_get "$rec" machine_id)" ] || {
        ap_guest_shutdown "$dom" || true
        ap_stop "$dom's machine-id is '$(ap_kv "$PROBE" machine_id)', recorded '$(ap_rec_get "$rec" machine_id)'" \
            "It is not the guest the evidence describes. Refusing to run a gate on it."
    }
}

# ap_guest_fresh DOM — at ap-fresh and never used. Reverts a guest whose only
# use was an attempt that never finished (a record with used_by but no result
# the caller cares about); the caller decides whether that is allowed.
ap_guest_is_fresh() { [ "$(ap_rec_get "$(ap_guest_rec "$1")" fresh)" = yes ]; }
ap_guest_revert() { # DOM SNAPSHOT WHY
    local dom="$1" snap="$2"
    ap_guest_shutdown_or_stop "$dom"
    grep -qxF -- "$snap" <<<"$(ap_virsh snapshot-list --domain "$dom" --name 2>/dev/null)" \
        || ap_stop "$dom has no snapshot '$snap' to return to"
    ap_virsh snapshot-revert --domain "$dom" --snapshotname "$snap" >/dev/null \
        || ap_stop "cannot revert $dom to $snap"
    [ "$snap" = ap-fresh ] && ap_rec_set "$(ap_guest_rec "$dom")" "fresh=yes" "reverted_utc=$(ap_utc)" "reverted_why=$3"
    [ "$snap" = ap-fresh ] || ap_rec_set "$(ap_guest_rec "$dom")" "reverted_to=$snap" "reverted_utc=$(ap_utc)" "reverted_why=$3"
    ap_say INFO "$dom reverted to $snap ($3)"
}
ap_guest_mark_used() { # DOM GATE
    ap_rec_set "$(ap_guest_rec "$1")" "fresh=no" "used_by=$2" "used_utc=$(ap_utc)"
}
ap_guest_snapshot() { # DOM NAME DESCRIPTION — once; the guest must be off
    local dom="$1" snap="$2"
    grep -qxF -- "$snap" <<<"$(ap_virsh snapshot-list --domain "$dom" --name 2>/dev/null)" && return 0
    ap_guest_shutdown_or_stop "$dom"
    ap_virsh snapshot-create-as --domain "$dom" --name "$snap" --description "$3" --atomic >/dev/null \
        || ap_stop "cannot snapshot $dom as $snap"
    ap_rec_set "$(ap_guest_rec "$dom")" "snapshot_$snap=$(ap_utc)"
    ap_say INFO "$dom snapshotted as $snap"
}

# ap_cleanup_vms — stop every autopilot guest; remove those whose work is done.
# A guest is removed only when every gate that runs on it is PASS; the chain
# only once U10 is PASS. A FAIL leaves its guest for inspection, a guest in
# the middle of its chain is kept, and templates and bases go only when no
# guest of that distribution is left. Nothing outside pliwee-g8-* is touched,
# and no evidence is: only libvirt objects.
ap_cleanup_vms() {
    local d role dom keep g
    while IFS= read -r dom; do
        ap_is_ours "$dom" || continue
        ap_say INFO "stopping $dom"
        ap_guest_shutdown "$dom" || ap_say WAIT "$dom did not shut down cleanly; it was not forced (shut it down yourself)"
    done < <(ap_running_domains)
    for d in "${AP_DISTROS[@]}"; do
        keep=0
        for role in "${AP_ROLES[@]}"; do
            dom="$(ap_domain "$d" "$role")"
            ap_dom_exists "$dom" || ap_rec_has "$(ap_guest_rec "$dom")" || continue
            case "$role" in
                chain) g="G7UP-$d-U10" ;; u8) g="G7UP-$d-U8" ;; lc) g="LIFECYCLE-$d" ;;
            esac
            if [ "$(ap_gate_state "$g")" = PASS ] && ! ap_dom_running "$dom"; then
                ap_virsh undefine "$dom" --snapshots-metadata >/dev/null 2>&1
                ap_virsh vol-delete --pool "$AP_POOL" "$dom.qcow2" >/dev/null 2>&1
                ap_rec_set "$(ap_guest_rec "$dom")" "state=removed" "removed_utc=$(ap_utc)"
                ap_say DONE "removed $dom ($g is PASS; its evidence is untouched)"
            else
                keep=1
                ap_say INFO "kept $dom ($g is $(ap_gate_state "$g"))"
            fi
        done
        if [ "$keep" = 0 ] && [ "$(ap_rec_get "template-$d" state 2>/dev/null)" = ready ]; then
            ap_virsh vol-delete --pool "$AP_POOL" "$(ap_tmpl_vol "$d")" >/dev/null 2>&1 \
                && ap_rec_set "template-$d" "state=removed" "removed_utc=$(ap_utc)" && ap_say DONE "removed the $d template"
            ap_virsh vol-delete --pool "$AP_POOL" "pliwee-g8-base-$(ap_abbr "$d").qcow2" >/dev/null 2>&1 \
                && ap_rec_set "base-$d" "state=removed" "removed_utc=$(ap_utc)" && ap_say DONE "removed the $d base image volume"
        fi
    done
}
