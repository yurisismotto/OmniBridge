#!/usr/bin/env bash
# cloud-init.sh — the NoCloud seeds the autopilot boots its guests with.
#
# TWO SEEDS, because one prepared desktop serves three guests per distro:
#
#   the TEMPLATE seed  runs once on the verified cloud image and turns it into
#                      what the gate harnesses assume a guest is (their own
#                      preconditions are listed beside each item below). It
#                      ends with a marker file; the autopilot then generalises
#                      the guest (cloud-init clean --machine-id) and keeps its
#                      disk only as a read-only backing file.
#   a ROLE seed        per guest (chain, U8, lifecycle), on its own overlay: a
#                      new instance id, its own host name and machine-id, and
#                      an identity token the autopilot records and checks on
#                      every later boot. It creates no user and installs nothing.
#
# What the template sets up, and which harness needs it:
#   * user anyflow, uid 1000 (GUEST_USER/GUEST_UID in every harness);
#   * qemu-guest-agent with guest-exec and guest-file-* allowed (guest-agent.sh
#     drives everything through them; Fedora's packaging can filter them);
#   * a GNOME desktop, graphical.target, GDM autologin for anyflow — a
#     graphical logind session for the user (lifecycle-gates.sh preconditions;
#     it restarts the display manager after terminate-user because "there is no
#     account password available to type into that greeter");
#   * no automatic screen lock or blanking, and no first-login tour, so the
#     one GUI step (selecting the peer in omnibridge-gui at U2) can be done;
#   * the tools the harnesses call in the guest (upgrade-gates.sh U0: dnf/rpm or
#     apt-get/dpkg, systemctl, sha256sum, runuser, journalctl, firewall-cmd on
#     Fedora; apt-ftparchive for the local apt repository in U3; ping);
#   * Fedora: firewalld with `work` as the default zone — upgrade-gates.sh adds
#     the omnibridge service to zone `work`, and the phone reaches the guest's
#     TCP 55432 only if the LAN interface is in that zone;
#   * background package updaters masked (unattended-upgrades, apt-daily,
#     dnf-makecache, PackageKit): a package lock held by one of them would fail
#     an install stage for a reason that is not the product.

# ap_seed_userdata_template DISTRO HOSTNAME PASSWORD_HASH — the template's user-data.
ap_seed_userdata_template() {
    local d="$1" host="$2" hash="$3" gdm pkgs desktop fw=""
    case "$d" in
        fedora44)
            gdm=/etc/gdm/custom.conf
            pkgs="qemu-guest-agent"
            desktop="dnf -y install @gnome-desktop firewalld iputils"
            fw="systemctl enable --now firewalld && firewall-cmd --set-default-zone=work"
            ;;
        ubuntu2404|ubuntu2604)
            gdm=/etc/gdm3/custom.conf
            pkgs="qemu-guest-agent"
            desktop="DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop-minimal apt-utils iputils-ping"
            ;;
        debian13)
            gdm=/etc/gdm3/custom.conf
            pkgs="qemu-guest-agent"
            desktop="DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-core gdm3 apt-utils iputils-ping"
            ;;
        *) return 1 ;;
    esac
    cat <<EOF
#cloud-config
# pre-g8-autopilot: TEMPLATE for $d. Generated; see packaging/tests/vm/cloud-init.sh.
hostname: $host
preserve_hostname: false
users:
  - name: $AP_GUEST_USER
    uid: "$AP_GUEST_UID"
    gecos: Pliwee pre-G8 test user
    shell: /bin/bash
    lock_passwd: $([ -n "$hash" ] && echo false || echo true)
$([ -n "$hash" ] && printf '    passwd: "%s"\n' "$hash")
ssh_pwauth: false
disable_root: true
package_update: true
package_upgrade: false
packages: [$pkgs]
write_files:
  - path: $gdm
    permissions: "0644"
    content: |
      # pre-g8-autopilot: a graphical session for $AP_GUEST_USER at every boot
      [daemon]
      AutomaticLoginEnable=True
      AutomaticLogin=$AP_GUEST_USER
  - path: /etc/dconf/profile/user
    permissions: "0644"
    content: |
      user-db:user
      system-db:local
  - path: /etc/dconf/db/local.d/00-pliwee-g8
    permissions: "0644"
    content: |
      # pre-g8-autopilot: no idle lock or blanking in a test guest
      [org/gnome/desktop/screensaver]
      lock-enabled=false
      [org/gnome/desktop/session]
      idle-delay=uint32 0
  - path: /usr/local/sbin/pliwee-g8-prepare
    permissions: "0755"
    content: |
      #!/bin/sh
      # pre-g8-autopilot template preparation. The marker is written last,
      # and only if every step succeeded.
      set -eu
      exec >>/var/log/pliwee-g8-prepare.log 2>&1
      echo "== \$(date -u) start"
      qga="\$(command -v qemu-ga)"
      mkdir -p /etc/systemd/system/qemu-guest-agent.service.d
      printf '[Service]\\nExecStart=\\nExecStart=%s --method=virtio-serial --path=/dev/virtio-ports/org.qemu.guest_agent.0\\n' "\$qga" \\
          > /etc/systemd/system/qemu-guest-agent.service.d/50-pliwee-g8.conf
      systemctl daemon-reload
      systemctl restart qemu-guest-agent || systemctl start qemu-guest-agent
      $desktop
      ${fw:-true}
      systemctl set-default graphical.target
      dconf update
      install -d -o $AP_GUEST_USER -g $AP_GUEST_USER /home/$AP_GUEST_USER/.config
      echo yes > /home/$AP_GUEST_USER/.config/gnome-initial-setup-done
      chown $AP_GUEST_USER:$AP_GUEST_USER /home/$AP_GUEST_USER/.config/gnome-initial-setup-done
      # Masked, not disabled: a role guest's first boot (machine-id reset by
      # the generalisation) applies systemd presets, which re-enable disabled units.
      for u in unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer apt-daily.service \\
               apt-daily-upgrade.service dnf-makecache.timer dnf-makecache.service packagekit.service; do
          systemctl stop "\$u" 2>/dev/null || true
          systemctl mask "\$u" 2>/dev/null || true
      done
      for t in systemctl sha256sum runuser journalctl loginctl ping; do command -v "\$t" >/dev/null; done
      if command -v dnf >/dev/null; then command -v rpm >/dev/null; command -v firewall-cmd >/dev/null
      else command -v apt-get >/dev/null; command -v dpkg >/dev/null; command -v apt-ftparchive >/dev/null; fi
      mkdir -p /var/lib/pliwee-g8
      date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/pliwee-g8/template-ready
      echo "== \$(date -u) done"
runcmd:
  - [/usr/local/sbin/pliwee-g8-prepare]
EOF
}

# ap_seed_userdata_role HOSTNAME TOKEN — a role guest's user-data: identity only.
ap_seed_userdata_role() {
    cat <<EOF
#cloud-config
# pre-g8-autopilot: ROLE instance. Identity only; the template prepared the rest.
hostname: $1
preserve_hostname: false
users: []
ssh_pwauth: false
write_files:
  - path: /var/lib/pliwee-g8/identity
    permissions: "0644"
    content: "$2"
EOF
}

# ap_seed_iso OUT USERDATA INSTANCE_ID — a NoCloud seed (volume label cidata).
ap_seed_iso() {
    local out="$1" ud="$2" iid="$3" dir
    dir="$(mktemp -d)" || return 1
    printf '%s\n' "$ud" > "$dir/user-data"
    printf 'instance-id: %s\nlocal-hostname: %s\n' "$iid" "$(sed -n 's/^hostname: //p' "$dir/user-data")" > "$dir/meta-data"
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -quiet -output "$out" -volid cidata -joliet -rock "$dir/user-data" "$dir/meta-data"
    else
        xorriso -as mkisofs -quiet -output "$out" -volid cidata -joliet -rock "$dir/user-data" "$dir/meta-data"
    fi
    local rc=$?
    rm -rf "$dir"
    return "$rc"
}
