#!/usr/bin/env bash
# B5 — how systemd treats `omnibridged.service` shipped as a symlink to
# `pliweed.service` (rebrand plan, Wave 7). Two halves, both non-destructive:
#
#   A. install logic (enable / disable / reenable / is-enabled), measured with
#      `systemctl --root` on a scratch tree: nothing outside it is touched;
#   B. the running user manager: disposable units under
#      $XDG_RUNTIME_DIR/systemd/user (volatile, gone at logout) that run
#      `sleep`, started, counted and removed again. Nothing under ~/.config.
#
# Probe unit names are b5probe*, never the product's.
set -uo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "PRECONDITION: $1 missing"; exit 3; }; }
need systemctl; need pgrep
systemctl --version | head -1

echo
echo "=== A. install logic, systemctl --root (scratch tree) ==="
T="$(mktemp -d /tmp/b5-root.XXXXXX)"; trap 'rm -rf "$T"' EXIT
U="$T/usr/lib/systemd/user"; W="$T/etc/systemd/user/default.target.wants"
mkdir -p "$U" "$T/etc/systemd/user"
printf '[Unit]\nDescription=probe\n[Service]\nExecStart=/usr/bin/sleep infinity\n[Install]\nWantedBy=default.target\n' > "$U/pliweed.service"
show() {
    find "$T/etc" -type l -printf '    link %p -> %l\n' | sed "s#$T##" | sort
    for u in pliweed.service omnibridged.service; do
        printf '    is-enabled %-20s %s\n' "$u" "$(systemctl --root="$T" --global is-enabled "$u" 2>&1)"
    done
}
legacy() { rm -rf "$T/etc/systemd/user"; mkdir -p "$W"; ln -s /usr/lib/systemd/user/omnibridged.service "$W/omnibridged.service"; }
q() { systemctl --root="$T" --global "$@" 2>&1 | grep -v 'non-existent unit' | sed 's/^/    /'; }

cp "$U/pliweed.service" "$U/omnibridged.service"
echo "A0  OmniBridge 1.0.0 state: omnibridged.service a real unit, enabled"
q enable omnibridged.service; show
rm "$U/omnibridged.service"; ln -s pliweed.service "$U/omnibridged.service"
echo "A1  after the upgrade: omnibridged.service -> pliweed.service, legacy link kept"; show
echo "A2  disable pliweed.service (legacy link only)"; q disable pliweed.service; show
echo "A3  enable pliweed.service with the legacy link present"; legacy; q enable pliweed.service; show
echo "A4  ...then disable pliweed.service"; q disable pliweed.service; show
echo "A5  disable omnibridged.service (the alias name)"; legacy; q disable omnibridged.service; show
echo "A6  reenable pliweed.service with the legacy link present (the logged fix)"; legacy; q reenable pliweed.service; show
echo "A7  reenable pliweed.service again (idempotence)"; q reenable pliweed.service; show
echo "A8  never enabled, then upgraded: nothing enabled"; rm -rf "$T/etc/systemd/user"; mkdir -p "$T/etc/systemd/user"; show

echo
echo "=== B. the running user manager (disposable runtime units) ==="
[ -n "${XDG_RUNTIME_DIR:-}" ] && systemctl --user is-system-running >/dev/null 2>&1 || true
systemctl --user show-environment >/dev/null 2>&1 || { echo "PRECONDITION: no user manager reachable; half B NOT EXECUTED"; exit 0; }
R="$XDG_RUNTIME_DIR/systemd/user"; mkdir -p "$R"
for f in b5probe.target b5probe.target.wants b5probenew.service b5probeold.service; do
    [ ! -e "$R/$f" ] || { echo "PRECONDITION: $R/$f already exists; refusing"; exit 3; }
done
cleanup_b() {
    systemctl --user stop b5probe.target b5probenew.service b5probeold.service >/dev/null 2>&1
    pkill -u "$(id -u)" -f '^/usr/bin/sleep 60[0-9]$' 2>/dev/null
    rm -rf "$R/b5probe.target" "$R/b5probe.target.wants" "$R/b5probenew.service" "$R/b5probeold.service"
    systemctl --user daemon-reload; systemctl --user reset-failed >/dev/null 2>&1
}
trap 'cleanup_b; rm -rf "$T"' EXIT
count() { pgrep -u "$(id -u)" -fc "^/usr/bin/sleep $1\$" || true; }
props() { systemctl --user show -p Id -p Names -p ActiveState -p MainPID "$1" | tr '\n' ' '; }

echo "B1  a target that Wants the OLD name, which is an alias of the new unit"
printf '[Unit]\nDescription=B5 probe new (disposable)\n[Service]\nExecStart=/usr/bin/sleep 600\n' > "$R/b5probenew.service"
ln -s b5probenew.service "$R/b5probeold.service"
printf '[Unit]\nDescription=B5 probe target (disposable)\n' > "$R/b5probe.target"
mkdir -p "$R/b5probe.target.wants"; ln -s "$R/b5probeold.service" "$R/b5probe.target.wants/b5probeold.service"
systemctl --user daemon-reload; systemctl --user start b5probe.target
echo "    old name: $(props b5probeold.service)"
echo "    new name: $(props b5probenew.service)"
systemctl --user start b5probenew.service b5probeold.service
echo "    after also starting both names explicitly: sleep-600 processes = $(count 600)"
cleanup_b

echo "B2  the upgrade while the old unit is RUNNING: file -> alias, then daemon-reload"
printf '[Unit]\nDescription=B5 probe old (disposable)\n[Service]\nExecStart=/usr/bin/sleep 601\n' > "$R/b5probeold.service"
systemctl --user daemon-reload; systemctl --user start b5probeold.service
echo "    before: $(props b5probeold.service)"
printf '[Unit]\nDescription=B5 probe new (disposable)\n[Service]\nExecStart=/usr/bin/sleep 602\n' > "$R/b5probenew.service"
rm "$R/b5probeold.service"; ln -s b5probenew.service "$R/b5probeold.service"
systemctl --user daemon-reload
echo "    after reload, old name: $(props b5probeold.service)"
echo "    after reload, new name: $(props b5probenew.service)"
systemctl --user start b5probenew.service; sleep 1
echo "    after 'start' of the new name: old-binary processes = $(count 601), new-binary processes = $(count 602)"
cleanup_b
echo "    cleanup: probe processes left = $(( $(count 600) + $(count 601) + $(count 602) )), probe files left = $(ls "$R" 2>/dev/null | grep -c b5probe || true)"
