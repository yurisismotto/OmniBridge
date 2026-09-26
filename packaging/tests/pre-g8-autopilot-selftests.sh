#!/usr/bin/env bash
# pre-g8-autopilot-selftests.sh — does the autopilot do what it must, refuse
# what it must, and resume where it should? Without a single real guest.
#
# The REAL autopilot drives the REAL coordinator (pre-g8-manual-gates.sh),
# pointed with PRE_G8_GATES_DIR at stub gate scripts — so every record is a
# self-test record that can never count as PASS in a real run. Around them:
#   * lib/autopilot-fakes/virsh    a stateful libvirt with a guest agent that
#                                  emulates cloud-init and the guest commands,
#                                  and records any second guest started while
#                                  one runs (one VM at a time);
#   * lib/autopilot-fakes/adb      the tablet, read-only, recording anything
#                                  that would change it;
#   * lib/autopilot-fakes/curl     the release and the cloud images, served
#                                  from fixtures (a real OpenPGP key signs the
#                                  release manifest and the Fedora CHECKSUM, and
#                                  the real verify-release.sh checks it);
#   * stub build scripts           recording their CPU affinity and overlap.
#
# Proved, each against the failure it exists for: the first-run plan; resume;
# a PASS gate is skipped; a FAIL stops everything (and --retry keeps it in the
# history); an interrupted gate resumes on a reverted guest; W2 is never
# promoted and W6 never re-run; U6 before SECLOG before U10, and no U10 after
# a U6 FAIL; U8 and the lifecycle gates each get their own fresh guest; one VM
# at a time; a guest whose identity changed is refused; a missing host tool is
# ONE stop with ONE command; low memory pauses; Ctrl+C deletes nothing;
# existing evidence stays byte-identical; nothing signing-related is touched;
# the generated config; the phone's address parsing; and the report says G8 is
# NOT eligible while W2 is unresolved. And the template, against what the
# first real Fedora 44 run met: an agent confined by SELinux, whose probe read
# every answer as empty, so a template ready in five minutes was waited on for
# fifty — now fixed in the seed, diagnosed in one line, bounded, and failed as
# infrastructure, never as a gate.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"
AP="$HERE/pre-g8-autopilot.sh"

PASS=0; FAIL=0
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); printf 'not ok  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
check()   { local d="$1"; shift; if "$@"; then ok "$d"; else notok "$d"; fi; }

for t in python3 gpg jq setsid taskset flock; do
    command -v "$t" >/dev/null 2>&1 || { echo "PRECONDITION FAILED: $t is needed by these self-tests" >&2; exit 3; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pliwee-autopilot-selftest.XXXXXXXX")"
# The operator's real evidence (records included) is read here, once before
# and once after, and must come out byte-identical: no self-test writes to it.
REAL_EV="${XDG_STATE_HOME:-$HOME/.local/state}/pliwee-pre-g8"
real_ev_snap() { [ -d "$REAL_EV" ] || { echo absent; return; }; ( cd "$REAL_EV" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum ); }
REAL_EV_BEFORE="$(real_ev_snap)"
# AP_SELFTEST_KEEP=1 keeps the work directory for a post-mortem.
trap '[ "${AP_SELFTEST_KEEP:-0}" = 1 ] && echo "kept: $WORK" || rm -rf "$WORK"' EXIT

# ------------------------------------------------------------------ fakes --
BIN="$WORK/bin"; mkdir -p "$BIN"
for f in "$HERE"/lib/autopilot-fakes/*; do ln -s "$f" "$BIN/$(basename "$f")"; done
printf '#!/bin/sh\necho "$0 $*" >> "%s/gui-launches"\n' "$WORK" > "$BIN/xdg-open"; cp "$BIN/xdg-open" "$BIN/virt-viewer"
chmod +x "$BIN/xdg-open" "$BIN/virt-viewer"

# ------------------------------------------------------------- stub gates --
STUB="$WORK/stub"; mkdir -p "$STUB/mode" "$STUB/android/signing"
cp "$HERE/lib/g7up-fixture.sh" "$STUB/lib-fixture.sh"
cat > "$STUB/upgrade-gates.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(cd "$(dirname "$0")" && pwd)"; . "$STUB/lib-fixture.sh"
echo "upgrade-gates $*" >> "$STUB/calls"
while [ $# -gt 0 ]; do case "$1" in
  --stage) S="$2"; shift 2 ;; --evidence) E="$2"; shift 2 ;; --distro) D="$2"; shift 2 ;;
  --domain) M="$2"; shift 2 ;; --old-pkgdir) O="$2"; shift 2 ;; *) shift ;; esac; done
mode="$(cat "$STUB/mode/$S-$D" 2>/dev/null)"
[ "$mode" = fail ] && { echo "not ok  $S: stub failure for $D"; exit 1; }
case "$S" in
  install) echo "ok    U1: omnibridge and omnibridge-gui are exactly 1.0.0-1"; echo "ok    U2: omnibridged.service is enabled" ;;
  upgrade) g7up_fixture "$E" "$D" "$M" "$O/SHA256SUMS"; rm -rf "$E/U6" "$E/U6-RESULT"
           echo "ok    Checkpoint: UPGRADE-CHECKPOINT written for run r1" ;;
  peer-u6) T="$(mktemp -d)"; g7up_fixture "$T" "$D" "$M"; rm -rf "$E/U6"; cp -a "$T/U6" "$T/U6-RESULT" "$E/"; rm -rf "$T"
           echo "ok    U6: lifecycle-peer-gates.sh passed against the upgraded guest, with every U6 observation in its log; U10 may now run" ;;
  downgrade) echo "ok    U10: OmniBridge 1.0.0 starts on its pre-migration identity" ;;
  negative-unreadable) echo "ok    U8: the daemon refused and named /home/anyflow/.local/share/omnibridge"
                       echo "ok    U8: no /home/anyflow/.local/share/pliwee/identity.key was created" ;;
esac
EOF
cat > "$STUB/security-log-evidence.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(dirname "$0")"; echo "security-log $*" >> "$STUB/calls"; echo "ok    SEC-LOG-03: content absent"
EOF
cat > "$STUB/lifecycle-gates.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(dirname "$0")"; echo "lifecycle $*" >> "$STUB/calls"
while [ $# -gt 0 ]; do case "$1" in --distro) D="$2"; shift 2 ;; --evidence) E="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$E" && { date -u; echo "attempt $$ $(date +%N)"; } > "$E/00-preconditions.txt"   # as the real harness writes first (one per attempt)
case "$(cat "$STUB/mode/lifecycle-$D" 2>/dev/null)" in
  fail) echo "not ok  L6: stub failure"; exit 1 ;;
  sleep) echo "ok    L1: started"; sleep 120 ;;
esac
echo "ok    L1: clean install"
EOF
cat > "$STUB/u2-state-check.sh" <<'EOF'
#!/usr/bin/env bash
STUB="$(dirname "$0")"; echo "u2-state-check $*" >> "$STUB/calls"
for n in 1 2 3 4 5; do echo "ok    U2-$n: observed"; done
EOF
# The signing procedure and Gradle: the autopilot must never reach them.
printf '#!/bin/sh\necho "SIGNING $*" >> "%s/forbidden"\n' "$STUB" > "$STUB/android/signing/provision-signing-keys.sh"
printf '#!/bin/sh\necho "GRADLE $*" >> "%s/forbidden"\n' "$STUB" > "$STUB/android/gradlew"
chmod +x "$STUB"/*.sh "$STUB/android/signing/provision-signing-keys.sh" "$STUB/android/gradlew"

# ------------------------------------------------------- stub build tools --
FPKG="$WORK/packaging"; mkdir -p "$FPKG/release" "$FPKG/fedora" "$FPKG/debian"
cat > "$FPKG/release/make-source-bundle.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --output) O="$2"; shift 2 ;; --rev) R="$2"; shift 2 ;; *) shift ;; esac; done
echo "start bundle $(taskset -cp $$ | sed 's/.*: //') rev=$R" >> "$FAKE_BUILD"; sleep 0.2
mkdir -p "$O"; echo src > "$O/pliwee-1.1.0.tar.gz"; echo vendor > "$O/pliwee-1.1.0-vendor.tar.xz"
echo "end bundle" >> "$FAKE_BUILD"
EOF
cat > "$FPKG/fedora/build-rpm.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --output) O="$2"; shift 2 ;; --image) I="$2"; shift 2 ;; *) B="$1"; shift ;; esac; done
echo "start rpm $(taskset -cp $$ | sed 's/.*: //') $I" >> "$FAKE_BUILD"; sleep 0.2
mkdir -p "$O"; for p in pliwee-1.1.0-1.fc44.x86_64.rpm pliwee-gui-1.1.0-1.fc44.x86_64.rpm omnibridge-1.1.0-1.fc44.noarch.rpm pliwee-1.1.0-1.fc44.src.rpm; do echo "$p" > "$O/$p"; done
echo lint > "$O/rpmlint.txt"; echo "end rpm" >> "$FAKE_BUILD"
EOF
cat > "$FPKG/debian/build-deb.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --output) O="$2"; shift 2 ;; --image) I="$2"; shift 2 ;; *) B="$1"; shift ;; esac; done
echo "start deb $(taskset -cp $$ | sed 's/.*: //') $I" >> "$FAKE_BUILD"; sleep 0.2
mkdir -p "$O"; for p in pliwee_1.1.0-1_amd64.deb pliwee-gui_1.1.0-1_amd64.deb omnibridge_1.1.0-1_all.deb omnibridge-gui_1.1.0-1_all.deb; do echo "$I $p" > "$O/$p"; done
echo lint > "$O/lintian.txt"; echo "end deb" >> "$FAKE_BUILD"
EOF
chmod +x "$FPKG"/*/*.sh

# ------------------------------------------- the release, signed for real --
GH="$WORK/gnupg"; mkdir -p "$GH"; chmod 700 "$GH"
g() { gpg --homedir "$GH" --batch --quiet --pinentry-mode loopback --passphrase '' "$@"; }
g --quick-gen-key 'Autopilot Selftest Release <release@selftest.invalid>' ed25519 cert 1d >/dev/null 2>&1
RFPR="$(g --with-colons --list-keys release@selftest.invalid | awk -F: '$1 == "fpr" { print $10; exit }')"
g --quick-add-key "$RFPR" ed25519 sign 1d >/dev/null 2>&1
RSUB="$(g --with-colons --with-subkey-fingerprints --list-keys "$RFPR" | awk -F: '$1 == "fpr" { print $10 }' | sed -n 2p)"
g --quick-gen-key 'Fedora Selftest <fedora@selftest.invalid>' ed25519 default 1d >/dev/null 2>&1
[ -n "$RFPR" ] && [ -n "$RSUB" ] || { echo "PRECONDITION FAILED: could not create the test release key" >&2; exit 3; }
WEB="$WORK/web"; REL="$WEB/release"; LAYOUT="$WORK/relbuild/omnibridge-1.0.0-linux-x86_64"
mkdir -p "$REL" "$LAYOUT"/{fedora44,ubuntu2404,ubuntu2604,debian13}
for p in omnibridge-1.0.0-1.fc44.x86_64.rpm omnibridge-gui-1.0.0-1.fc44.x86_64.rpm omnibridge-1.0.0-1.fc44.src.rpm; do echo "$p" > "$LAYOUT/fedora44/$p"; done
for d in ubuntu2404 ubuntu2604 debian13; do for p in omnibridge_1.0.0-1_amd64.deb omnibridge-gui_1.0.0-1_amd64.deb; do echo "$d $p" > "$LAYOUT/$d/$p"; done; done
echo src > "$LAYOUT/omnibridge-1.0.0.tar.gz"
( cd "$LAYOUT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS )
g --local-user "$RSUB!" --armor --detach-sign --output "$LAYOUT/SHA256SUMS.asc" "$LAYOUT/SHA256SUMS"
tar -czf "$REL/omnibridge-1.0.0-linux-x86_64.tar.gz" -C "$WORK/relbuild" omnibridge-1.0.0-linux-x86_64
cp "$LAYOUT/SHA256SUMS" "$LAYOUT/SHA256SUMS.asc" "$REL/"
g --armor --export "$RFPR" > "$REL/omnibridge-release-pubkey.asc"

# ------------------------------------------------------ the cloud images --
IMG="$WEB/img"; mkdir -p "$IMG"/{fedora44,ubuntu2404,ubuntu2604,debian13}
echo "fedora qcow2" > "$IMG/fedora44/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
printf 'SHA256 (Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2) = %s\n' "$(sha256sum < "$IMG/fedora44/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2" | cut -d' ' -f1)" > "$WORK/fcs"
g --local-user fedora@selftest.invalid --clearsign --output "$IMG/fedora44/Fedora-Cloud-44-1.7-x86_64-CHECKSUM" "$WORK/fcs"
printf '<a href="Fedora-Cloud-44-1.7-x86_64-CHECKSUM">x</a>\n<a href="Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2">x</a>\n<a href="Fedora-Cloud-Base-UEFI-UKI-44-1.7.x86_64.qcow2">x</a>\n' > "$IMG/fedora44/index.html"
g --armor --export fedora@selftest.invalid > "$WORK/fedora.key"
for v in 2404 2604; do
    n="ubuntu-${v:0:2}.${v:2:2}-server-cloudimg-amd64.img"; echo "ubuntu $v" > "$IMG/ubuntu$v/$n"
    printf '%s *%s\n' "$(sha256sum < "$IMG/ubuntu$v/$n" | cut -d' ' -f1)" "$n" > "$IMG/ubuntu$v/SHA256SUMS"; echo sig > "$IMG/ubuntu$v/SHA256SUMS.gpg"
done
echo "debian qcow2" > "$IMG/debian13/debian-13-generic-amd64.qcow2"
printf '%s  debian-13-generic-amd64.qcow2\n' "$(sha512sum < "$IMG/debian13/debian-13-generic-amd64.qcow2" | cut -d' ' -f1)" > "$IMG/debian13/SHA512SUMS"

# ---------------------------------------------- scenarios and the runner --
# A scenario is an evidence directory with the operator's existing W2/W6
# records in it, a libvirt, a tablet, a build log and a stub-call log.
new_evidence() { # DIR — W2-GNOME FAIL, W2-KDE pending, three W6 PASS (self-test records)
    local e="$1"; mkdir -p "$e/state" "$e/w2" "$e/w6" "$e/logs"
    printf 'items\nFiles switch announced: "switch"\n' > "$e/w2/W2-GNOME.answers.txt"
    printf '%s\n' gate=W2-GNOME state=FAIL "reason=the Files switch announcement does not carry 'Files for {name}'; " \
        started_utc=2026-09-25T21:20:19Z finished_utc=2026-09-25T21:22:59Z exit=0 log= log_sha256= domain= \
        "answers=$e/w2/W2-GNOME.answers.txt" "answers_sha256=$(sha256sum < "$e/w2/W2-GNOME.answers.txt" | cut -d' ' -f1)" \
        attempt=20260925T211934Z.1 selftest=1 recorded_utc=2026-09-25T21:22:59Z > "$e/state/W2-GNOME"
    printf 'upload SHA-256 AA\nbackups restore-verified:  2026-09-25T00:00:00Z\n' > "$e/w6/signing-status.txt"
    printf '%s\n' gate=W6-SIGNING state=PASS reason= started_utc=x finished_utc=2026-09-25T21:43:04Z exit=0 log= log_sha256= domain= \
        "status_file=$e/w6/signing-status.txt" attempt=a1 selftest=1 recorded_utc=x > "$e/state/W6-SIGNING"
    for g in W6-COMPONENT-UPGRADE W6-INSTRUMENTED; do
        printf '%s\n' "gate=$g" state=PASS "reason=measured" started_utc=x finished_utc=x exit=0 log= log_sha256= domain= \
            attempt=a2 selftest=1 recorded_utc=x > "$e/state/$g"
    done
}
SC=""
scenario() { # NAME — a fresh scenario, made current
    SC="$WORK/sc-$1"; mkdir -p "$SC"/{rt,cache,libvirt,adb,sysnet/enp9s0/device}
    echo 1 > "$SC/sysnet/enp9s0/carrier"
    echo "MemAvailable:   16000000 kB" > "$SC/meminfo"
    new_evidence "$SC/ev"; : > "$STUB/calls"; : > "$WEB.calls"; rm -f "$STUB/mode/"* "$STUB/forbidden"
}
# save_scenario / restore_scenario — a tamper test works on the scenario in
# place (records hold absolute paths, and the logs' digests cover them), then
# puts it back exactly as it was.
save_scenario()    { rm -rf "$SC.saved"; cp -a "$SC" "$SC.saved"; cp "$STUB/calls" "$SC.saved.calls"; }
restore_scenario() { rm -rf "$SC"; cp -a "$SC.saved" "$SC"; cp "$SC.saved.calls" "$STUB/calls"; }
apenv() {
    env PATH="$BIN:$PATH" FAKE_LIBVIRT="$SC/libvirt" FAKE_ADB="$SC/adb" FAKE_WEB="$WEB" FAKE_BUILD="$SC/build" \
        PRE_G8_GATES_DIR="$STUB" AP_PACKAGING_DIR="$FPKG" AP_RELEASE_BASE_URL=https://fixture.invalid/release \
        AP_TEST_RELEASE_FPR="$RFPR" AP_TEST_RELEASE_SUBKEY="$RSUB" AP_FEDORA_KEY="$WORK/fedora.key" \
        AP_IMG_URL_fedora44=https://fixture.invalid/img/fedora44 AP_IMG_URL_ubuntu2404=https://fixture.invalid/img/ubuntu2404 \
        AP_IMG_URL_ubuntu2604=https://fixture.invalid/img/ubuntu2604 AP_IMG_URL_debian13=https://fixture.invalid/img/debian13 \
        AP_SYSFS_NET="$SC/sysnet" AP_MEMINFO="$SC/meminfo" AP_POLL=1 AP_UI_SLEEP=0 AP_MEM_WAIT="${MEMWAIT:-3}" \
        AP_BOOT_TIMEOUT=4 AP_TEMPLATE_TIMEOUT=6 AP_SHUTDOWN_TIMEOUT=3 \
        AP_TEST_HIDE_TOOLS="${HIDE:-}" XDG_RUNTIME_DIR="$SC/rt" XDG_CACHE_HOME="$SC/cache" "$@"
}
OUT=""; RC=0
apx() { # STDIN ARGS... — the autopilot on the current scenario
    local in="$1"; shift
    OUT="$(apenv bash "$AP" --evidence "$SC/ev" "$@" 2>&1 <<<"$in")"; RC=$?
    printf '%s\n' "$OUT" >> "$SC/autopilot.out"
}
cstate() { # GATE — the coordinator's state for GATE in this scenario
    apenv bash "$HERE/pre-g8-manual-gates.sh" --evidence "$SC/ev" --status </dev/null 2>/dev/null \
        | sed -n "s/^PRE_G8_GATE id=$1 state=\([A-Z]*\) .*/\1/p"
}
evsnap() { ( cd "$SC/ev" && find . -path ./autopilot -prune -o -path ./summary.txt -prune -o -type f -print0 | sort -z | xargs -0 -r sha256sum ); }
vcalls() { cat "$SC/libvirt/calls" 2>/dev/null; }
nlines() { grep -c -- "$1" "$2" 2>/dev/null || true; }
yes_then() { printf 'yes\n'; local i; for ((i = 0; i < ${1:-0}; i++)); do printf '\n'; done; }
enters() { local i; for ((i = 0; i < $1; i++)); do printf 'ok\n'; done; }   # visible: $(…) strips bare newlines
line_of() { grep -n -m1 -- "$1" "$2" 2>/dev/null | cut -d: -f1; }   # PATTERN FILE — first line number

# ---------------------------------------------------------------------------
section "Units: the phone's address, adb, subnets"
# ---------------------------------------------------------------------------
UNIT() { ( AP_STATE="$WORK/unit"; mkdir -p "$AP_STATE/records"
           . "$HERE/lib/autopilot-common.sh"; . "$HERE/lib/autopilot-host.sh"; . "$HERE/lib/autopilot-android.sh"
           . "$HERE/vm/images.sh"; . "$HERE/vm/cloud-init.sh"; . "$HERE/lib/cli-report.sh"; "$@" ); }
check "ip -br wlan0 with a CR: 192.168.68.63" test "$(UNIT ap_parse_ipv4 $'wlan0            UP             192.168.68.63/22 \r')" = 192.168.68.63
check "ip addr (classic) wlan0: 192.168.68.63" test "$(UNIT ap_parse_ipv4 $'31: wlan0: <UP>\n    inet 192.168.68.63/22 brd 192.168.71.255 scope global wlan0')" = 192.168.68.63
is_false_u() { if UNIT "$@" >/dev/null 2>&1; then return 1; else return 0; fi; }
check "a link-local address alone is refused" is_false_u ap_parse_ipv4 'wlan0 UP 169.254.3.4/16'
check "wlan0 down (no address) is refused" is_false_u ap_parse_ipv4 'wlan0 DOWN'
check "two addresses are refused, not guessed between" is_false_u ap_parse_ipv4 $'    inet 192.168.68.63/22 scope global wlan0\n    inet 10.0.0.9/8 scope global wlan0'
check "adb devices: the serial's state" test "$(UNIT ap_adb_state $'List of devices attached\nRX2Y500C7SY\tdevice\nOTHER\toffline' RX2Y500C7SY)" = device
check "adb devices: unauthorized is reported as such" test "$(UNIT ap_adb_state $'List of devices attached\nRX2Y500C7SY\tunauthorized' RX2Y500C7SY)" = unauthorized
check "adb devices: an absent serial is nothing" test -z "$(UNIT ap_adb_state $'List of devices attached\nOTHER\tdevice' RX2Y500C7SY)"
check "192.168.68.63 is on 192.168.68.69/22" UNIT ap_same_subnet 192.168.68.63 192.168.68.69/22
check "192.168.72.1 is not on 192.168.68.69/22" is_false_u ap_same_subnet 192.168.72.1 192.168.68.69/22

# ---------------------------------------------------------------------------
section "Units: checksum lists, listings, cloud-init, domain XML, the trust store"
# ---------------------------------------------------------------------------
check "SHA256SUMS 'HEX *NAME' (Ubuntu)" test "$(UNIT ap_sums_lookup "$(printf 'aa11 *x.img\nbb22 *y.img')" x.img)" = aa11
check "SHA512SUMS 'HEX  NAME' (Debian)" test "$(UNIT ap_sums_lookup "$(printf 'cc33  d.qcow2')" d.qcow2)" = cc33
check "CHECKSUM 'SHA256 (NAME) = HEX' (Fedora)" test "$(UNIT ap_sums_lookup 'SHA256 (f.qcow2) = dd44' f.qcow2)" = dd44
check "a name listed twice is refused" is_false_u ap_sums_lookup "$(printf 'aa *x.img\nbb *x.img')" x.img
check "the Fedora listing resolves exactly one Generic image (not the UEFI-UKI one)" \
    test "$(UNIT ap_resolve_name 'Fedora-Cloud-Base-Generic-44-[0-9.]+\.x86_64\.qcow2' "$(cat "$IMG/fedora44/index.html")")" = Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
check "a listing offering two composes is refused" is_false_u ap_resolve_name 'F-[0-9.]+\.q' $'<a href="F-1.1.q">\n<a href="F-1.2.q">'
yaml_ok() { # DISTRO — the template user-data parses and says what the harnesses need
    UNIT bash -c 'AP_GUEST_USER=anyflow AP_GUEST_UID=1000; . "$0/vm/cloud-init.sh"; ap_seed_userdata_template "$1" g8-x-tmpl "\$6\$salt\$hash"' "$HERE" "$1" > "$WORK/ud-$1.yaml" \
        && python3 - "$WORK/ud-$1.yaml" "$1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); distro = sys.argv[2]
u = d["users"][0]; files = {w["path"]: w["content"] for w in d["write_files"]}
assert u["name"] == "anyflow" and str(u["uid"]) == "1000" and u["lock_passwd"] is False
assert "qemu-guest-agent" in d["packages"]
# The file each distribution's GDM reads (its packaged gdm-session-worker,
# measured 2026-09-26). It is a conffile of the gdm package: never written
# before the desktop is installed (dpkg's conffile prompt), always after it.
gdm = {"fedora44": "/etc/gdm/custom.conf", "debian13": "/etc/gdm3/daemon.conf"}.get(distro, "/etc/gdm3/custom.conf")
assert not any("gdm" in f for f in files), sorted(files)
prep = files["/usr/local/sbin/pliwee-g8-prepare"]
assert "gdmconf=" + gdm + "\n" in prep and "AutomaticLogin=anyflow" in prep
assert prep.index("stage=desktop") < prep.index("gdmconf=") < prep.index("stage=session")
assert "grep -aqF \"$gdmconf\" /usr/libexec/gdm-session-worker" in prep
assert "trap failed EXIT" in prep and "template-failed" in prep
assert "template-ready" in prep and "graphical.target" in prep and "qemu-ga" in prep
assert ("set-default-zone=work" in prep) == (distro == "fedora44")
assert d["runcmd"] == [["/usr/local/sbin/pliwee-g8-prepare"]]
PY
}
for d in fedora44 ubuntu2404 ubuntu2604 debian13; do check "the $d template seed is valid cloud-config with anyflow/1000, the agent, GDM autologin (after the desktop, in the file GDM reads), the marker" yaml_ok "$d"; done
role_ok() {
    UNIT bash -c '. "$0/vm/cloud-init.sh"; ap_seed_userdata_role g8-f44-u8 0123abcd' "$HERE" > "$WORK/role.yaml" \
        && python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert d["users"]==[] and d["hostname"]=="g8-f44-u8" and d["write_files"][0]["content"]=="0123abcd"' "$WORK/role.yaml"
}
check "a role seed creates no user and writes only the host name and identity token" role_ok
xml_ok() {
    UNIT bash -c '. "$0/lib/autopilot-host.sh"; . "$0/vm/guests.sh"; ap_domain_xml pliwee-g8-f44-u8 fedora44 u8 v.qcow2 s.iso 52:54:00:aa:bb:cc enp9s0' "$HERE" > "$WORK/dom.xml" \
        && python3 - "$WORK/dom.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
assert r.find("name").text == "pliwee-g8-f44-u8" and r.find("memory").text == "4096" and r.find("vcpu").text == "2"
i = r.find("devices/interface"); assert i.get("type") == "direct" and i.find("source").get("mode") == "bridge" and i.find("source").get("dev") == "enp9s0"
assert any(c.find("target").get("name") == "org.qemu.guest_agent.0" for c in r.findall("devices/channel"))
assert r.find("os/type").get("machine") == "q35" and r.find("os/loader") is None
PY
}
check "the domain XML: 2 vCPU, 4096 MiB, macvtap bridge on the NIC, the agent channel, q35 BIOS" xml_ok
DEVS=$'SM-X620  0123456789abcdef\n   platform    android\n   fingerprint ABCD 1234 5678 9ABC\n   paired      yes\n   connected   yes\n   state       live\n   granted     clipboard.v1, files.v1\n\nold-laptop  fedcba9876543210\n   platform    linux\n   fingerprint 1111 2222 3333 4444\n   paired      no\n   connected   no\n   state       revoked\n   granted     -'
check "the 1.0.0 trust store parses: the paired phone and the revoked laptop" \
    test "$(UNIT ob_devices_tsv "$DEVS" | cut -f1,2,3,5 | tr '\t\n' '|;')" = "SM-X620|0123456789abcdef|android|yes;old-laptop|fedcba9876543210|linux|no;"
mem_ok() { # low memory pauses, then goes on once memory is back
    # shellcheck disable=SC2034  # AP_POLL and AP_MEM_WAIT are read by ap_wait_memory
    ( AP_STATE="$WORK/unit"; AP_MEMINFO="$WORK/mem-unit"; AP_POLL=1; AP_MEM_WAIT=10
      . "$HERE/lib/autopilot-common.sh"; . "$HERE/lib/autopilot-host.sh"
      echo "MemAvailable: 1000000 kB" > "$AP_MEMINFO"; ( sleep 2; echo "MemAvailable: 9000000 kB" > "$AP_MEMINFO" ) &
      ap_wait_memory 6144 "starting x" ) > "$WORK/mem-unit.out" 2>&1
    grep -q '^\[WAIT\] starting x paused' "$WORK/mem-unit.out" && grep -q 'memory recovered' "$WORK/mem-unit.out"
}
check "low memory: the launch WAITs, then continues once memory is back" mem_ok

# ---------------------------------------------------------------------------
section "Records: one value per key, replaced in place, malformed refused"
# ---------------------------------------------------------------------------
# REC DIR CMD... — CMD with the record functions, AP_STATE=DIR (a fresh one per test).
REC() { local st="$1"; shift; ( AP_STATE="$st"; mkdir -p "$AP_STATE/records"
        . "$HERE/lib/autopilot-common.sh"; . "$HERE/lib/autopilot-host.sh"; . "$HERE/vm/guests.sh"; "$@" ); }
is_false_r() { if REC "$@" >/dev/null 2>&1; then return 1; else return 0; fi; }
RS="$WORK/rec"; rm -rf "$RS"
nhist() { find "$1/records/history" -name "$2.*" 2>/dev/null | grep -c .; }
REC "$RS/a" ap_rec_set t "state=building" "domain=d1"
check "first insert: exactly the lines given, no history" \
    test "$(cat "$RS/a/records/t")" = $'state=building\ndomain=d1' -a "$(nhist "$RS/a" t)" = 0
REC "$RS/a" ap_rec_set t "state=ready" "built_utc=x"
check "update: the key replaced where it stands, other keys kept, a new key appended" \
    test "$(cat "$RS/a/records/t")" = $'state=ready\ndomain=d1\nbuilt_utc=x'
check "…the previous version is in the history, byte-identical" \
    test "$(nhist "$RS/a" t)" = 1 -a "$(cat "$RS/a/records/history"/t.*)" = $'state=building\ndomain=d1'
for v in failed building ready removed ready; do REC "$RS/a" ap_rec_set t "state=$v" "n_$v=1"; done
check "repeated updates: ONE state= line, the last value, every other key kept" \
    test "$(grep -c '^state=' "$RS/a/records/t")" = 1 -a "$(REC "$RS/a" ap_rec_get t state)" = ready \
         -a "$(REC "$RS/a" ap_rec_get t domain)" = d1 -a "$(REC "$RS/a" ap_rec_get t n_failed)" = 1
check "state changes: every version kept in the history (building→ready→failed→building→ready→removed→ready)" \
    test "$(nhist "$RS/a" t)" = 6
REC "$RS/a" ap_rec_set t "state=ready"
check "setting a value it already has changes nothing and adds no history" test "$(nhist "$RS/a" t)" = 6
absent_ok() { local out rc; out="$(REC "$RS/a" ap_rec_get t nosuchkey)"; rc=$?; [ "$rc" = 1 ] && [ -z "$out" ]; }
check "ap_rec_get: an absent key is exit 1, nothing printed" absent_ok

# fresh=yes -> fresh=no -> (revert) fresh=yes, through the functions the autopilot uses
REC "$RS/f" ap_rec_put guest-g1 "state=ready" "domain=g1" "fresh=yes"
REC "$RS/f" ap_guest_mark_used g1 LIFECYCLE-fedora44
check "fresh=yes → used: ONE fresh=no line, used_by recorded, not fresh" \
    test "$(grep -c '^fresh=' "$RS/f/records/guest-g1")" = 1 -a "$(REC "$RS/f" ap_rec_get guest-g1 fresh)" = no \
         -a "$(REC "$RS/f" ap_rec_get guest-g1 used_by)" = LIFECYCLE-fedora44
check "…ap_guest_is_fresh says no" is_false_r "$RS/f" ap_guest_is_fresh g1
REC "$RS/f" ap_rec_set guest-g1 "fresh=yes" "reverted_utc=t1" "reverted_why=w"   # what ap_guest_revert writes
fresh_again() { [ "$(grep -c '^fresh=' "$RS/f/records/guest-g1")" = 1 ] && REC "$RS/f" ap_guest_is_fresh g1; }
check "reverted: ONE fresh=yes line, and ap_guest_is_fresh says yes (it said no forever before)" fresh_again
REC "$RS/f" ap_guest_mark_used g1 LIFECYCLE-fedora44
REC "$RS/f" ap_rec_set guest-g1 "fresh=yes" "reverted_utc=t2" "reverted_why=w2"
REC "$RS/f" ap_guest_mark_used g1 LIFECYCLE-fedora44
check "used, reverted, used again: still ONE line per key (fresh, used_by, reverted_utc)" \
    test "$(cut -d= -f1 "$RS/f/records/guest-g1" | sort | uniq -d)" = "" -a "$(REC "$RS/f" ap_rec_get guest-g1 reverted_utc)" = t2

# malformed input: refused, never guessed at, never rewritten
mkdir -p "$RS/m/records"; printf 'state=building\ndomain=d\nstate=failed\n' > "$RS/m/records/t"; cp "$RS/m/records/t" "$RS/m-t.orig"
out="$(REC "$RS/m" ap_rec_get t state 2>"$RS/m-err")"; rc=$?
check "a record with state= twice: ap_rec_get exits 2 and prints NO value" test "$rc" = 2 -a -z "$out"
check "…saying so on stderr" contains "$(cat "$RS/m-err")" "has 2 state= lines; not guessing which is current"
check "…its other keys still read" test "$(REC "$RS/m" ap_rec_get t domain)" = d
out="$(REC "$RS/m" ap_rec_set t "state=ready" 2>&1)"; rc=$?
check "ap_rec_set on it: STOP (exit 3), naming the key" test "$rc" = 3 -a -n "$(grep 'key state appears 2 times' <<<"$out")"
check "…and the record is byte-identical (not repaired, not guessed)" cmp -s "$RS/m/records/t" "$RS/m-t.orig"
out="$(REC "$RS/m" ap_records_verify 2>&1)"; rc=$?
check "ap_records_verify: STOP (exit 3) naming the file and the duplicate" \
    test "$rc" = 3 -a -n "$(grep "$RS/m/records/t: key state appears 2 times" <<<"$out")"
REC "$RS/p" ap_rec_put t "state=a" "state=b" 2>/dev/null; rc=$?
check "ap_rec_put with a key twice: refused (exit 1), nothing written" test "$rc" = 1 -a ! -e "$RS/p/records/t"
REC "$RS/p" ap_rec_put t "state=a" $'why=two\nlines' 2>/dev/null; rc=$?
check "ap_rec_put with a value that would split into a second line: refused" test "$rc" = 1 -a ! -e "$RS/p/records/t"
REC "$RS/p" ap_rec_put t "state=a" "no equals sign" 2>/dev/null; rc=$?
check "ap_rec_put with a line that is not key=value: refused" test "$rc" = 1 -a ! -e "$RS/p/records/t"
out="$(REC "$RS/a" ap_rec_set t "state=x" "state=y" 2>&1)"; rc=$?
check "ap_rec_set asked to set one key twice: STOP, record unchanged" \
    test "$rc" = 3 -a "$(REC "$RS/a" ap_rec_get t state)" = ready

# an interrupted write: the old version or the new one, never neither
REC "$RS/i" ap_rec_put template-x "state=building" "domain=d"
printf 'state=ready\n' > "$RS/i/records/template-x.partial.12345"   # a write killed before its rename
check "interrupted write: the record still reads its last complete version" \
    test "$(REC "$RS/i" ap_rec_get template-x state)" = building
check "…and the leftover partial file does not fail the startup check" REC "$RS/i" ap_records_verify
REC "$RS/i" ap_rec_set template-x "state=failed" "failure_dir=/f1"   # the failed build …
REC "$RS/i" ap_rec_put template-x "state=building" "domain=d"        # … discarded and started again on resume
REC "$RS/i" ap_rec_set template-x "state=failed" "failure_dir=/f2"
check "interrupted/failed/resumed template: one state=, one failure_dir=, the latest" \
    test "$(REC "$RS/i" ap_rec_get template-x state)" = failed -a "$(REC "$RS/i" ap_rec_get template-x failure_dir)" = /f2 \
         -a "$(cut -d= -f1 "$RS/i/records/template-x" | sort | uniq -d)" = ""

# ---------------------------------------------------------------------------
section "Refusals before anything is done"
# ---------------------------------------------------------------------------
scenario refuse
real="$(env -u PRE_G8_GATES_DIR AP_RELEASE_BASE_URL=https://example.invalid bash "$AP" --evidence "$SC/ev" --status 2>&1)"; rrc=$?
check "a self-test seam in a REAL run is refused (exit 2), not ignored" test "$rrc" -eq 2
check "…naming it" contains "$real" "AP_RELEASE_BASE_URL is a self-test seam"
before="$(evsnap)"
HIDE="qrencode podman" apx "yes"
check "missing host tools: ONE stop (exit 3)" test "$RC" -eq 3
check "…with ONE exact command, naming both packages" test "$(grep -c '^ *sudo dnf install -y qrencode podman$' <<<"$OUT")" = 1
check "…and nothing else: no libvirt call, no download" test -z "$(vcalls | grep -vE '^(uri|pool-info)' )" -a ! -s "$WEB.calls"
check "…and the evidence is untouched" test "$(evsnap)" = "$before"
rm -rf "$SC/sysnet/enp9s0"
apx "yes"
check "no wired NIC with carrier: a stop that says what to plug in" test "$RC" -eq 3 -a -n "$(grep 'no wired network interface with carrier' <<<"$OUT")"
mkdir -p "$SC/sysnet/enp9s0/device"; echo 1 > "$SC/sysnet/enp9s0/carrier"
apx "" --no-wait
check "no authorisation typed (EOF): WAIT (exit 4) before any guest or download" \
    test "$RC" -eq 4 -a -z "$(vcalls | grep -E '^(define|start|vol-create-as)')"
check "…saying what is needed" contains "$OUT" "the gates need your one-time authorisation"

# ---------------------------------------------------------------------------
section "Read-only views: --plan and --status on a first run"
# ---------------------------------------------------------------------------
: > "$SC/libvirt/calls"; : > "$WEB.calls"
apx "" --plan
check "--plan lists the 32 autopilot gates, U8/lifecycle first" \
    test "$(grep -cE '^ *[0-9]+\. \[(AUTO|WAIT|DONE)\]' <<<"$OUT")" = 32 -a -n "$(grep -E '^ 1\. \[AUTO\] G7UP-fedora44-U8' <<<"$OUT")"
check "…U2 and U6 marked as needing the operator, and nothing else" \
    test "$(grep -c '\[WAIT\]' <<<"$OUT")" = 8
check "…with what must be built first" contains "$OUT" "first: image+template(fedora44) pliwee-build(fedora44) guest(pliwee-g8-f44-u8)"
check "…and W2/W6 listed as manual, never run by it" contains_re "$OUT" '^ +W2-GNOME +FAIL$'
check "--plan created no guest and downloaded nothing" test -z "$(vcalls | grep -vE '^(uri|pool-info)')" -a ! -s "$WEB.calls"
apx "" --status
check "--status: G8 is NOT eligible, and says why (W2-GNOME FAIL, W2-KDE PENDING)" \
    test -n "$(grep -x 'G8 eligible: NO' <<<"$OUT")" -a -n "$(grep 'W2-GNOME is FAIL' <<<"$OUT")" -a -n "$(grep 'W2-KDE is PENDING' <<<"$OUT")"
check "--status names the next step" contains "$OUT" "next:       G7UP-fedora44-U8 (automatic)"

# ---------------------------------------------------------------------------
section "Low memory: the first guest is not launched"
# ---------------------------------------------------------------------------
scenario lowmem
echo "MemAvailable:   1000000 kB" > "$SC/meminfo"
MEMWAIT=2 apx "yes" --no-wait
check "a host short of memory: STOP (exit 3) after pausing" test "$RC" -eq 3 -a -n "$(grep '^\[WAIT\] .* paused — ' <<<"$OUT")"
check "…and no guest and no build was started" test -z "$(vcalls | grep '^start ')" -a ! -s "$SC/build"

# ---------------------------------------------------------------------------
section "First run, unattended: every automatic gate, then WAIT at U2"
# ---------------------------------------------------------------------------
scenario main
BEFORE="$(evsnap)"; cp -a "$SC/ev/state" "$WORK/state-before"
apx "$(yes_then 0)" --no-wait
check "the first run stops at the first human step (exit 4)" test "$RC" -eq 4
check "…which is the fedora44 pairing" contains "$OUT" "[WAIT] G7UP-fedora44-U2 — physical Android pairing required"
for d in fedora44 ubuntu2404 ubuntu2604 debian13; do
    check "$d: U8, LIFECYCLE and INSTALL are PASS" test "$(cstate "G7UP-$d-U8")$(cstate "LIFECYCLE-$d")$(cstate "G7UP-$d-INSTALL")" = PASSPASSPASS
done
check "nothing past INSTALL ran (no upgrade, no U6, no downgrade)" test "$(nlines '--stage upgrade\|--stage peer-u6\|--stage downgrade' "$STUB/calls")" = 0
check "order: every U8 and lifecycle gate before any INSTALL" \
    test "$(grep -n 'lifecycle .*debian13' "$STUB/calls" | cut -d: -f1)" -lt "$(line_of '--stage install' "$STUB/calls")"
for d in f44 u2404 u2604 d13; do
    check "U8 ($d) ran on its own guest, pliwee-g8-$d-u8" test "$(grep -c -- "--stage negative-unreadable --domain pliwee-g8-$d-u8 " "$STUB/calls")" = 1
    check "lifecycle ($d) ran on its own guest, pliwee-g8-$d-lc" test "$(grep -c -- "^lifecycle --domain pliwee-g8-$d-lc " "$STUB/calls")" = 1
done
check "each fresh-guest gate got a guest that was fresh when it began (record history)" \
    test "$(grep -lx 'fresh=yes' "$SC/ev/autopilot/records/history"/guest-pliwee-g8-*-u8.* 2>/dev/null | grep -c .)" -ge 4
check "one VM at a time: no guest was ever started while another ran" test ! -s "$SC/libvirt/violations"
check "each distribution's image was downloaded once and its template built once" \
    test "$(grep -c '\.qcow2$\|\.img$' "$WEB.calls")" = 4 -a "$(vcalls | grep -c '^define .*templates/')" = 4
check "builds: sequential (never two at once)" test "$(awk '/^start/ { if (open) bad = 1; open = 1 } /^end/ { open = 0 } END { print bad + 0 }' "$SC/build")" = 0
check "builds: pinned to two CPUs (at most two build jobs)" test "$(grep -c '^start' "$SC/build")" = 5 -a "$(grep '^start' "$SC/build" | awk '$3 != "0,1" && $3 != "0-1"' | grep -c .)" = 0
check "the Pliwee set was built from the checkout's commit" contains "$(cat "$SC/build")" "rev=$(git -C "$HERE/../.." rev-parse HEAD)"
check "the published 1.0.0 set was VERIFIED by verify-release.sh against the pinned key" \
    contains "$(cat "$SC/ev/autopilot/artifacts/omnibridge-1.0.0/"verify-release.*.txt)" "VERIFIED  "
check "…Fedora's image list was signature-checked" contains "$(cat "$SC/ev/autopilot/records/image-fedora44")" "signature=verified: "
CFGF="$SC/ev/autopilot/coordinator.conf"
check "config: the three guests per distribution" test "$(grep -cE '^(DOMAIN|U8_DOMAIN|LIFECYCLE_DOMAIN)_(fedora44|ubuntu2404|ubuntu2604|debian13)=pliwee-g8-' "$CFGF")" = 12
check "config: the published layout as OLD_PKGDIR, a flat Pliwee set as NEW_PKGDIR" \
    test "$(grep -c '^OLD_PKGDIR_.*omnibridge-1.0.0/layout$' "$CFGF")" = 4 -a "$(grep -cE '^NEW_PKGDIR_[a-z0-9]+=.*/pliwee-[0-9a-f]{12}/' "$CFGF")" = 4
check "config: keyring, pinned fingerprint, the phone's CURRENT address and serial" \
    test -n "$(grep "^FINGERPRINT=$RFPR$" "$CFGF")" -a -n "$(grep '^PHONE_IP=192.168.68.63$' "$CFGF")" -a -n "$(grep '^ADB_SERIAL=RX2Y500C7SY$' "$CFGF")" -a -n "$(grep '^KEYRING=' "$CFGF")"
check "config: no signing media, no APKs" test -z "$(grep -E '^(MEDIA_|APK_)' "$CFGF")"
check "the grant: typed once, private, naming the guests and the fresh ones" \
    test "$(stat -c %a "$(sed -n 's/^file=//p' "$SC/ev/autopilot/records/grant-current")")" = 600 -a \
         -n "$(grep '^fresh_domains=.*pliwee-g8-f44-u8.*pliwee-g8-f44-lc' "$(sed -n 's/^file=//p' "$SC/ev/autopilot/records/grant-current")")"
check "every gate the coordinator ran was confirmed by that grant (no terminal prompt)" \
    test "$(grep -l '^# confirmed by: autopilot grant g-' "$SC/ev/logs"/*.log | grep -c .)" = 12
check "the flat Pliwee set verifies against its own SHA256SUMS" \
    bash -c 'cd "$(sed -n "s/^NEW_PKGDIR_debian13=//p" "$1")" && sha256sum --quiet -c SHA256SUMS && [ "$(ls *.deb | wc -l)" = 4 ]' _ "$CFGF"

# ---------------------------------------------------------------------------
section "W2 and W6: never run, never promoted, byte-identical"
# ---------------------------------------------------------------------------
check "W2-GNOME's FAIL record is byte-identical" cmp -s "$WORK/state-before/W2-GNOME" "$SC/ev/state/W2-GNOME"
check "W2-KDE has no record (still PENDING)" test ! -e "$SC/ev/state/W2-KDE" -a "$(cstate W2-KDE)" = PENDING
for g in W6-SIGNING W6-COMPONENT-UPGRADE W6-INSTRUMENTED; do check "$g's PASS record is byte-identical" cmp -s "$WORK/state-before/$g" "$SC/ev/state/$g"; done
check "the signing procedure and Gradle were never invoked" test ! -e "$STUB/forbidden"
check "the autopilot never asked the coordinator to run a W2 or W6 gate" test -z "$(find "$SC/ev/autopilot/runs" -name 'W[26]-*')"
check "the tablet was never changed outside a gate (no install, grant, rm, settings)" test ! -s "$SC/adb/violations"

# ---------------------------------------------------------------------------
section "Identity: a guest that is not the recorded one is refused"
# ---------------------------------------------------------------------------
save_scenario
sed -i "s/<mac address='[^']*'/<mac address='52:54:00:de:ad:00'/" "$SC/libvirt/doms/pliwee-g8-f44-chain/xml"
n0="$(grep -c . "$STUB/calls")"
apx "" --no-wait
check "a chain guest whose MAC changed: STOP (exit 3)" test "$RC" -eq 3
check "…saying it no longer matches its recorded identity" contains "$OUT" "pliwee-g8-f44-chain no longer matches its recorded identity"
check "…and no gate ran" test "$(grep -c . "$STUB/calls")" = "$n0"
restore_scenario
python3 - "$SC/libvirt/vols/pliwee-g8-f44-chain.qcow2.guest" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["identity"] = "not-the-recorded-token"; json.dump(d, open(p, "w"))
PY
apx "" --no-wait
check "a chain guest whose in-guest identity token changed: STOP (exit 3), guest shut down" \
    test "$RC" -eq 3 -a -n "$(grep 'is not the recorded guest' <<<"$OUT")" -a "$(cat "$SC/libvirt/doms/pliwee-g8-f44-chain/state")" = "shut off"
restore_scenario
python3 - "$SC/libvirt/vols/pliwee-g8-f44-tmpl.qcow2.meta" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["mtime"] += 7; json.dump(d, open(p, "w"))
PY
apx "" --no-wait
check "a template written after it was sealed: STOP before its guests are used" \
    test "$RC" -eq 3 -a -n "$(grep 'template volume pliwee-g8-f44-tmpl.qcow2 no longer matches its record' <<<"$OUT")"
restore_scenario
scenario stranger
mkdir -p "$SC/libvirt/doms/pliwee-g8-f44-u8/snaps"; echo "<domain><name>pliwee-g8-f44-u8</name></domain>" > "$SC/libvirt/doms/pliwee-g8-f44-u8/xml"
apx "yes" --no-wait
check "a pliwee-g8-* domain with no record is refused, never adopted or replaced" \
    test "$RC" -eq 3 -a -n "$(grep 'pliwee-g8-f44-u8 exists, but no record says this autopilot created it' <<<"$OUT")"
check "…and it is still there, untouched" test -e "$SC/libvirt/doms/pliwee-g8-f44-u8/xml" -a -z "$(vcalls | grep -E '^(undefine|destroy|start) pliwee-g8-f44-u8')"

# ---------------------------------------------------------------------------
section "Resume: U2 (measured), the upgrade, and a U6 FAIL that stops everything"
# ---------------------------------------------------------------------------
SC="$WORK/sc-main"; cp "$SC.saved.calls" "$STUB/calls"
echo fail > "$STUB/mode/peer-u6-fedora44"
apx "$(enters 6)"
check "the resume ran U2 for all four and the fedora44 upgrade, then stopped on the U6 FAIL (exit 1)" \
    test "$RC" -eq 1 -a "$(cstate G7UP-debian13-U2)" = PASS -a "$(cstate G7UP-fedora44-UPGRADE)" = PASS -a "$(cstate G7UP-fedora44-U6)" = FAIL
check "U2 was paired through the product (omnibridge pair) and the QR shown" \
    test -n "$(grep 'omnibridge1:' "$SC/ev/autopilot/runs"/*/U2-fedora44-pair-qr.png 2>/dev/null)"
check "U2 grants and policies went through the 1.0.0 CLI" \
    test -z "$(grep -c '^\$ omnibridge ' "$SC/ev/autopilot/runs"/*/U2-fedora44-cli.txt | grep -v ':5$')"
check "U2 was recorded by the coordinator as MEASURED" contains "$(cat "$SC/ev/state/G7UP-fedora44-U2")" "method=measured"
check "U2 was measured before the coordinator recorded it (the autopilot's pre-check), then by the coordinator" \
    test "$(grep -c '^u2-state-check --domain pliwee-g8-f44-chain' "$STUB/calls")" = 2
check "the upgrade stage ran on a guest snapshotted ap-pre-upgrade first" \
    test -n "$(vcalls | grep '^snapshot-create-as --domain pliwee-g8-f44-chain --name ap-pre-upgrade')"
check "after the U6 FAIL: no security-log gate and no downgrade ran anywhere" \
    test "$(nlines '^security-log ' "$STUB/calls")" = 0 -a "$(nlines '--stage downgrade' "$STUB/calls")" = 0
check "…and nothing of the next distribution" test "$(nlines '--stage upgrade --domain pliwee-g8-u2404' "$STUB/calls")" = 0
check "…the failing gate and its log are named" contains "$OUT" "[FAIL] G7UP-fedora44-U6"
check "…and its guest was shut down, not reverted" \
    test "$(cat "$SC/libvirt/doms/pliwee-g8-f44-chain/state")" = "shut off" -a -z "$(vcalls | grep 'snapshot-revert --domain pliwee-g8-f44-chain')"
u6fail="$(cat "$SC/ev/state/G7UP-fedora44-U6")"; n0="$(grep -c . "$STUB/calls")"; s0="$(vcalls | grep -c '^start ')"
apx "$(enters 3)"
check "a plain resume over the FAIL stops again at once (exit 1), running nothing, starting nothing" \
    test "$RC" -eq 1 -a "$(grep -c . "$STUB/calls")" = "$n0" -a "$(vcalls | grep -c '^start ')" = "$s0"
check "…and suggests --retry" contains "$OUT" "pre-g8-autopilot.sh --retry G7UP-fedora44-U6"

# ---------------------------------------------------------------------------
section "--retry, then the rest: U6 before SECLOG before U10, to the end"
# ---------------------------------------------------------------------------
rm -f "$STUB/mode/peer-u6-fedora44"
apx "$(enters 8)" --retry G7UP-fedora44-U6
check "after --retry the run finishes every automatable gate (exit 0)" test "$RC" -eq 0
check "…the U6 FAIL is kept, byte-identical, in the coordinator's history" \
    bash -c 'for f in "$1"/state/history/G7UP-fedora44-U6.*; do [ "$(cat "$f")" = "$2" ] && exit 0; done; exit 1' _ "$SC/ev" "$u6fail"
for d in fedora44 ubuntu2404 ubuntu2604 debian13; do
    u6="$(grep -n -- "--stage peer-u6 .*--distro $d " "$STUB/calls" | tail -1 | cut -d: -f1)"
    sl="$(grep -n "^security-log .*--distro $d " "$STUB/calls" | tail -1 | cut -d: -f1)"
    u10="$(grep -n -- "--stage downgrade .*--distro $d " "$STUB/calls" | tail -1 | cut -d: -f1)"
    check "$d: U6 (line ${u6:-?}) < SECLOG (${sl:-?}) < U10 (${u10:-?}), all on the chain guest" \
        test -n "$u6" -a -n "$sl" -a -n "$u10" -a "${u6:-0}" -lt "${sl:-0}" -a "${sl:-0}" -lt "${u10:-0}"
done
check "U6, SECLOG and U10 ran back to back on one running guest (no reboot between)" \
    test "$(vcalls | awk '/^start pliwee-g8-u2404-chain/ { n++ } END { print n }')" -le 4
n_pass=0; for d in fedora44 ubuntu2404 ubuntu2604 debian13; do for s in INSTALL U2 UPGRADE U6 SECLOG U10 U8; do [ "$(cstate "G7UP-$d-$s")" = PASS ] && n_pass=$((n_pass + 1)); done; [ "$(cstate "LIFECYCLE-$d")" = PASS ] && n_pass=$((n_pass + 1)); done
check "…all 32 G7-UP and lifecycle gates" test "$n_pass" = 32
check "one VM at a time, over the whole run" test ! -s "$SC/libvirt/violations"
check "no guest is left running" test -z "$(for f in "$SC/libvirt/doms"/*/state; do grep -x running "$f"; done)"

# ---------------------------------------------------------------------------
section "The report: G8 is NOT eligible while W2 is unresolved"
# ---------------------------------------------------------------------------
R="$SC/ev/autopilot/REPORT.md"
check "REPORT.md exists" test -s "$R"
check "it says G8 eligible: NO" contains "$(cat "$R")" "| **G8 eligible** | **NO** |"
check "…because of W2-GNOME (FAIL) and W2-KDE (PENDING), as manual outstanding" \
    test -n "$(grep '^- W2-GNOME is FAIL — MANUAL OUTSTANDING' "$R")" -a -n "$(grep '^- W2-KDE is PENDING — MANUAL OUTSTANDING' "$R")"
check "…and, the rest being PASS, for no gate of the autopilot's" test -z "$(grep -E '^- (G7UP|LIFECYCLE)-' "$R")"
check "it carries the source commit, image and package provenance, and every gate" \
    test -n "$(grep "Source commit | \`$(git -C "$HERE/../.." rev-parse HEAD)\`" "$R")" -a -n "$(grep 'Fedora-Cloud-Base-Generic-44-1.7' "$R")" \
         -a -n "$(grep 'OmniBridge 1.0.0 (published, not rebuilt)' "$R")" -a "$(grep -cE '^\| (W[26]|G7UP|LIFECYCLE)-' "$R")" = 37
check "the final summary says the same" test -n "$(grep -x 'G8 eligible: NO' <<<"$OUT")" -a -n "$(grep 'MANUAL OUTSTANDING  W2-GNOME' <<<"$OUT")"
check "existing evidence is byte-identical after the whole run" \
    bash -c 'diff <(printf "%s\n" "$1") <(printf "%s\n" "$2" | grep -Ff <(printf "%s\n" "$1" | cut -c67-))' _ "$BEFORE" "$(evsnap)"
apx ""
check "a resume with nothing left: DONE at once (exit 0), nothing run" test "$RC" -eq 0 -a -n "$(grep 'nothing is left for the autopilot' <<<"$OUT")"

# ---------------------------------------------------------------------------
section "--cleanup-vms: guests whose gates are PASS go; evidence stays"
# ---------------------------------------------------------------------------
before="$(evsnap)"
apx "" --cleanup-vms
check "every autopilot guest removed (all their gates are PASS)" test -z "$(compgen -G "$SC/libvirt/doms/pliwee-g8-*")"
check "…templates and base volumes too" test -z "$(find "$SC/libvirt/vols" -name '*tmpl*' -o -name '*base*')"
check "…and the evidence is byte-identical" test "$(evsnap)" = "$before"

# ---------------------------------------------------------------------------
section "A FAIL stops everything; --retry keeps it"
# ---------------------------------------------------------------------------
scenario failstop
echo fail > "$STUB/mode/lifecycle-fedora44"
apx "yes" --no-wait
check "LIFECYCLE-fedora44 FAIL: the run stops (exit 1)" test "$RC" -eq 1 -a "$(cstate LIFECYCLE-fedora44)" = FAIL
check "…after U8 fedora44 and before anything of ubuntu2404" \
    test "$(cstate G7UP-fedora44-U8)" = PASS -a "$(nlines 'ubuntu2404' "$STUB/calls")" = 0
check "…naming the gate and its log" test -n "$(grep '^\[FAIL\] LIFECYCLE-fedora44' <<<"$OUT")" -a -n "$(grep 'gate log:  /' <<<"$OUT")"
lcfail="$(cat "$SC/ev/state/LIFECYCLE-fedora44")"
lcfail_files="$(cd "$SC/ev/lifecycle/fedora44" && sha256sum ./* )"
rm -f "$STUB/mode/lifecycle-fedora44"
apx "" --no-wait --retry LIFECYCLE-fedora44
check "--retry: a new attempt on a guest reverted to ap-fresh, now PASS" \
    test "$(cstate LIFECYCLE-fedora44)" = PASS -a -n "$(vcalls | grep 'snapshot-revert --domain pliwee-g8-f44-lc --snapshotname ap-fresh')"
check "…the FAIL record kept byte-identical in the history" \
    bash -c 'for f in "$1"/state/history/LIFECYCLE-fedora44.*; do [ "$(cat "$f")" = "$2" ] && exit 0; done; exit 1' _ "$SC/ev" "$lcfail"
check "…and the run went on to the next gates" test "$(cstate G7UP-ubuntu2404-U8)" = PASS
# The retry writes the same file names as the FAILed attempt (the stub, like
# lifecycle-gates.sh, rewrites 00-preconditions.txt): that attempt's files are
# evidence and must be copied aside, verified, before it runs.
lcpres="$(ls -d "$SC/ev/autopilot/preserved/LIFECYCLE-fedora44."* 2>/dev/null | head -1)"
check "--retry: the FAILed attempt's harness files were copied aside first, byte-identical" \
    test -n "$lcpres" -a "$(cd "$lcpres/fedora44" 2>/dev/null && sha256sum ./*)" = "$lcfail_files"
check "…and the retry did write over the originals (so the copy was needed)" \
    test "$(cd "$SC/ev/lifecycle/fedora44" && sha256sum ./*)" != "$lcfail_files"
check "…saying so" contains "$OUT" "the FAILed attempt's files in $SC/ev/lifecycle/fedora44 were copied to"

scenario retryonly
echo fail > "$STUB/mode/lifecycle-fedora44"
apx "yes" --no-wait
rm -f "$STUB/mode/lifecycle-fedora44"
n0="$(grep -c . "$STUB/calls")"
apx "" --no-wait --retry LIFECYCLE-fedora44 --only
check "--retry GATE --only: that gate alone, now PASS, then DONE (exit 0)" \
    test "$RC" -eq 0 -a "$(cstate LIFECYCLE-fedora44)" = PASS -a -n "$(grep 'retried alone (--only): PASS; no other gate was run' <<<"$OUT")"
check "…exactly one gate ran (the retried one) and nothing of ubuntu2404" \
    test "$(( $(grep -c . "$STUB/calls") - n0 ))" = 1 -a "$(nlines 'ubuntu2404' "$STUB/calls")" = 0 -a "$(cstate G7UP-ubuntu2404-U8)" = PENDING
check "…on its guest reverted to ap-fresh, with the FAILed attempt's files preserved first" \
    test -n "$(vcalls | grep 'snapshot-revert --domain pliwee-g8-f44-lc --snapshotname ap-fresh')" -a -n "$(compgen -G "$SC/ev/autopilot/preserved/LIFECYCLE-fedora44.*/fedora44")"
check "…and no guest is left running" test -z "$(for f in "$SC/libvirt/doms"/*/state; do grep -x running "$f"; done)"
apx "" --only
check "--only without --retry is refused (exit 2)" test "$RC" -eq 2

# ---------------------------------------------------------------------------
section "Ctrl+C mid-gate: nothing deleted, the gate resumes on a reverted guest"
# ---------------------------------------------------------------------------
scenario interrupt
before="$(evsnap)"
echo sleep > "$STUB/mode/lifecycle-fedora44"
# A background job in a script starts with SIGINT ignored, which no trap can
# undo; python restores the default so this is the operator's Ctrl+C.
( cd "$SC" && apenv python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp("bash", ["bash"] + sys.argv[1:])' \
    "$AP" --evidence "$SC/ev" --no-wait > "$SC/int.out" 2>&1 <<<"yes" ) &
apid=$!
for _ in $(seq 1 240); do grep -q '^lifecycle ' "$STUB/calls" 2>/dev/null && break; sleep 0.5; done
sleep 1
for p in $(pgrep -f "pre-g8-autopilot.sh --evidence $SC/ev" 2>/dev/null); do kill -INT "$p" 2>/dev/null; done
wait "$apid"; irc=$?
check "Ctrl+C during the lifecycle gate: exit 130, reported as interrupted" \
    test "$irc" -eq 130 -a -n "$(grep '^\[INT \] interrupted — nothing was deleted' "$SC/int.out")"
check "…the gate is BLOCKED (interrupted), never PASS" test "$(cstate LIFECYCLE-fedora44)" = BLOCKED
check "…its record says RUNNING, with its log" test "$(sed -n 's/^state=//p' "$SC/ev/state/LIFECYCLE-fedora44")" = RUNNING
check "…no pre-existing evidence file changed or vanished" \
    bash -c 'diff <(printf "%s\n" "$1") <(printf "%s\n" "$2" | grep -Ff <(printf "%s\n" "$1" | cut -c67-))' _ "$before" "$(evsnap)"
check "…and the running guest was asked to shut down" test -n "$(vcalls | grep '^shutdown pliwee-g8-f44-lc')"
rm -f "$STUB/mode/lifecycle-fedora44"
apx "" --no-wait
check "the resume reverts the lifecycle guest to ap-fresh and runs the gate again: PASS" \
    test "$(cstate LIFECYCLE-fedora44)" = PASS -a -n "$(vcalls | grep 'snapshot-revert --domain pliwee-g8-f44-lc --snapshotname ap-fresh')"
check "…the interrupted attempt's record is in the history" \
    bash -c 'grep -lx "state=RUNNING" "$1"/state/history/LIFECYCLE-fedora44.* >/dev/null' _ "$SC/ev"
check "…and the files it had written were copied aside first" test -d "$(ls -d "$SC/ev/autopilot/preserved/LIFECYCLE-fedora44."* 2>/dev/null | head -1)"
check "…and the run went on to the WAIT at U2 (exit 4)" test "$RC" -eq 4

# ---------------------------------------------------------------------------
section "Units: what the template probe says about a guest"
# ---------------------------------------------------------------------------
UNITG() { ( AP_STATE="$WORK/unit"; mkdir -p "$AP_STATE/records"
            . "$HERE/lib/autopilot-common.sh"; . "$HERE/lib/autopilot-host.sh"; . "$HERE/vm/guests.sh"; "$@" ); }
# The probe the first real Fedora 44 template answered for 50 minutes: the
# guest had finished; SELinux (virt_qemu_ga_t, enforcing) denied every read.
CONFINED=$'identity=\ntemplate_ready=\nmachine_id=5e0c\nhostname=\ncloud_init=\nuser_uid=1000\nsession_type=\ndefault_target=\nos=Fedora Linux 44 (Cloud Edition)\nkernel=7.0.9-200.fc44.x86_64\nsel_context=system_u:system_r:virt_qemu_ga_t:s0\nsel_enforce=1\ndatasource=\npkg_procs=\nnet_ipv4=192.168.68.200/22\nprepare_stage=\nuptime_s=900'
check "the observed Fedora 44 probe is recognised as a confined agent" UNITG ap_probe_confined "$CONFINED"
check "…and summarised as such, not as 'cloud-init: '" \
    contains "$(UNITG ap_probe_summary "$CONFINED")" "guest-exec confined by SELinux (system_u:system_r:virt_qemu_ga_t:s0, enforce=1)"
check "…also when the agent's own context is unreadable" \
    UNITG ap_probe_confined "$(sed 's/^sel_context=.*/sel_context=/; s/^sel_enforce=.*/sel_enforce=/' <<<"$CONFINED")"
is_false_g() { if UNITG "$@" >/dev/null 2>&1; then return 1; else return 0; fi; }
check "a probe with a host name is never 'confined'" is_false_g ap_probe_confined "$(sed 's/^hostname=$/hostname=g8-f44-tmpl/' <<<"$CONFINED")"
check "the agent failing: 'QGA unavailable', with its error" \
    contains "$(UNITG ap_probe_summary 'probe_error=guest-agent: FATAL: guest-exec rejected by x: error: Guest agent is not responding')" "QGA unavailable or guest-exec failed: guest-agent: FATAL"
check "no output at all is said to be no output" contains "$(UNITG ap_probe_summary '')" "no probe output"
BUSY=$'hostname=g8\ncloud_init=running\nkernel=k\ndatasource=nocloud\npkg_procs=2\nnet_ipv4=\nprepare_stage=stage: desktop\ntemplate_ready='
check "cloud-init running, a package transaction, no network, the prepare stage, no marker — each named" \
    test "$(UNITG ap_probe_summary "$BUSY")" = "cloud-init running; package transaction active (2 processes); network: no IPv4 address; prepare: stage: desktop; marker absent"
check "cloud-init disabled: 'guest booted but no datasource'" \
    contains "$(UNITG ap_probe_summary $'hostname=g8\ncloud_init=disabled\nkernel=k')" "guest booted but no datasource"
check "cloud-init done without a datasource id: 'datasource missing'" \
    contains "$(UNITG ap_probe_summary $'hostname=g8\ncloud_init=done\nkernel=k\ndatasource=')" "datasource missing"
GOOD=$'pkg_gnome_shell=49.1-1\npkg_gdm=49.0-1\npkg_qga=10.2.2-1\ngdm_conf=/etc/gdm/custom.conf\ngdm_conf_read_by_gdm=yes\nautologin=anyflow\nno_lock=yes\ninitial_setup_done=yes\ndefault_target=graphical.target\nselinux=Enforcing\nqga_permissive=yes\nmarker=2026-09-26T00:00:00Z'
check "readiness: a complete Fedora template passes" UNITG ap_template_check_fn "$GOOD"
check "readiness: no gnome-shell fails" is_false_g ap_template_check_fn "$(sed 's/^pkg_gnome_shell=.*/pkg_gnome_shell=/' <<<"$GOOD")"
check "readiness: a system made Permissive fails (only the agent's domain may change)" is_false_g ap_template_check_fn "$(sed 's/^selinux=.*/selinux=Permissive/' <<<"$GOOD")"
check "readiness: Enforcing without the agent-domain module fails" is_false_g ap_template_check_fn "$(sed 's/^qga_permissive=.*/qga_permissive=/' <<<"$GOOD")"
check "readiness: autologin written to a file GDM does not read fails (Debian reads daemon.conf)" is_false_g ap_template_check_fn "$(sed 's/^gdm_conf_read_by_gdm=.*/gdm_conf_read_by_gdm=/' <<<"$GOOD")"
check "readiness: no recorded GDM file fails" is_false_g ap_template_check_fn "$(sed 's/^gdm_conf=.*/gdm_conf=/' <<<"$GOOD")"
check "readiness: autologin for someone else fails" is_false_g ap_template_check_fn "$(sed 's/^autologin=.*/autologin=root/' <<<"$GOOD")"
check "readiness: no marker fails" is_false_g ap_template_check_fn "$(sed 's/^marker=.*/marker=/' <<<"$GOOD")"
check "readiness: an empty check fails" is_false_g ap_template_check_fn ""
seed_fix_ok() { # the Fedora seed makes virt_qemu_ga_t permissive BEFORE the desktop, and verifies it
    python3 - "$WORK/ud-fedora44.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
prep = {w["path"]: w["content"] for w in d["write_files"]}["/usr/local/sbin/pliwee-g8-prepare"]
i, j = prep.index("(typepermissive virt_qemu_ga_t)"), prep.index("@gnome-desktop")
assert i < j and "semodule -i" in prep and "grep -qx pliwee-g8-qga" in prep
assert "setenforce" not in prep and "SELINUX=permissive" not in prep
PY
}
check "the Fedora seed makes only virt_qemu_ga_t permissive, verifies it, before the desktop (never setenforce)" seed_fix_ok

# ---------------------------------------------------------------------------
section "TEMPLATE: a confined agent, a timeout, no agent, an incomplete desktop"
# ---------------------------------------------------------------------------
tmpl_fail_common() { # LABEL — what every template failure must be
    local label="$1" rec="$SC/ev/autopilot/records/template-fedora44" dir
    dir="$(sed -n 's/^failure_dir=//p' "$rec" 2>/dev/null)"
    check "$label: STOP (exit 3) as infrastructure, not a gate FAIL" \
        test "$RC" -eq 3 -a -n "$(grep '^\[STOP\] TEMPLATE-fedora44 — infrastructure preparation FAILED' <<<"$OUT")"
    check "$label: the template is recorded failed, with its diagnosis directory" \
        test "$(sed -n 's/^state=//p' "$rec")" = failed -a -s "$dir/summary.txt" -a -s "$dir/probe.txt" -a -s "$dir/qga.txt" -a -e "$dir/guest-logs.txt"
    check "$label: the paths are printed" contains "$OUT" "diagnosis:     $dir/summary.txt"
    check "$label: the guest was shut down cleanly (not destroyed)" \
        test "$(cat "$SC/libvirt/doms/pliwee-g8-f44-tmpl/state")" = "shut off" -a -z "$(vcalls | grep '^destroy pliwee-g8-f44-tmpl')"
    check "$label: no gate ran and no gate was recorded" \
        test ! -s "$STUB/calls" -a -z "$(find "$SC/ev/state" -maxdepth 1 \( -name 'G7UP-*' -o -name 'LIFECYCLE-*' \))" -a "$(cstate G7UP-fedora44-U8)" = PENDING
    check "$label: the evidence is byte-identical" test "$(evsnap)" = "$before"
}
tmpl_faildir() { sed -n 's/^failure_dir=//p' "$SC/ev/autopilot/records/template-fedora44"; }
scenario tmplconf
before="$(evsnap)"
FAKE_STAY_CONFINED=pliwee-g8-f44-tmpl AP_CONFINED_LIMIT=5 AP_SAY_EVERY=2 apx "yes" --no-wait
tmpl_fail_common "agent confined by SELinux"
check "…ended by the confinement limit, not the full timeout" contains "$OUT" "guest-exec stayed confined by SELinux for 5s"
check "…the waiting line says what the guest is doing, never an empty 'cloud-init: '" \
    test -n "$(grep '^\[INFO\] TEMPLATE-fedora44 — still waiting (.*guest-exec confined by SELinux' <<<"$OUT")" -a -z "$(grep 'cloud-init: )' <<<"$OUT")"
check "…the journal records the observed state as it changed" \
    test -n "$(grep 'TEMPLATE-fedora44 — observed at 0s (up [0-9]*s): guest-exec confined by SELinux' "$SC/ev/autopilot/journal.log")"
check "…the guest's AVC denials are in the kept logs" contains "$(cat "$(tmpl_faildir)/guest-logs.txt")" "virt_qemu_ga_t"
FAKE_AGENT_DEAD=pliwee-g8-f44-u8 apx "" --no-wait
check "resume after the failure: the failed template is discarded and built again, and is ready" \
    test -n "$(grep 'TEMPLATE-fedora44 — an unfinished build (failed) is discarded' <<<"$OUT")" -a \
         -n "$(grep '^\[PASS\] TEMPLATE-fedora44' <<<"$OUT")" -a "$(sed -n 's/^state=//p' "$SC/ev/autopilot/records/template-fedora44")" = ready
RDY="$SC/ev/autopilot/templates/fedora44/readiness.txt"
check "…its readiness check was recorded: Enforcing, the agent's domain permissive, GNOME present" \
    test -n "$(grep -x 'selinux=Enforcing' "$RDY")" -a -n "$(grep -x 'qga_permissive=yes' "$RDY")" -a -n "$(grep -x 'pkg_gnome_shell=49.1-1' "$RDY")"
check "…and the failure's diagnosis is still there" test -n "$(compgen -G "$SC/ev/autopilot/templates/fedora44/failure.*/summary.txt")"

scenario tmpltimeout
before="$(evsnap)"
FAKE_PREPARE_NEVER=pliwee-g8-f44-tmpl AP_SAY_EVERY=2 apx "yes" --no-wait
tmpl_fail_common "preparation never finishes"
check "…bounded: 'not ready after 6s' (AP_TEMPLATE_TIMEOUT)" contains "$OUT" "infrastructure preparation FAILED: not ready after 6s"
check "…the waiting line: cloud-init running, the prepare stage, marker absent" \
    test -n "$(grep '^\[INFO\] TEMPLATE-fedora44 — still waiting (.*cloud-init running; .*prepare: stage: desktop; marker absent' <<<"$OUT")"

scenario tmplnoqga
before="$(evsnap)"
FAKE_AGENT_DEAD=pliwee-g8-f44-tmpl apx "yes" --no-wait
tmpl_fail_common "no guest agent"
check "…said as 'QGA unavailable'" contains "$OUT" "infrastructure preparation FAILED: QGA unavailable"
check "…and the agent's silence is in qga.txt" contains "$(cat "$(tmpl_faildir)/qga.txt")" "(no answer"

scenario tmplnognome
before="$(evsnap)"
FAKE_NO_GNOME=pliwee-g8-f44-tmpl apx "yes" --no-wait
tmpl_fail_common "no GNOME in the prepared guest"
check "…the readiness check names what is missing" contains "$OUT" "the readiness check did not pass: pkg_gnome_shell= "

scenario tmplonly
before="$(evsnap)"
apx "" --template fedora44
check "--template fedora44: DONE (exit 0), the template ready, its readiness recorded" \
    test "$RC" -eq 0 -a "$(sed -n 's/^state=//p' "$SC/ev/autopilot/records/template-fedora44")" = ready \
         -a -s "$SC/ev/autopilot/templates/fedora44/readiness.txt" -a -n "$(grep '^\[DONE\] TEMPLATE-fedora44 is ready' <<<"$OUT")"
check "…no gate ran or was recorded, and no grant was asked for" \
    test ! -s "$STUB/calls" -a -z "$(find "$SC/ev/state" -maxdepth 1 \( -name 'G7UP-*' -o -name 'LIFECYCLE-*' \))" \
         -a ! -e "$SC/ev/autopilot/records/grant-current" -a -z "$(grep -i 'authoris' <<<"$OUT")"
check "…nothing else was built: no Pliwee build, one image, one guest defined (the template)" \
    test ! -s "$SC/build" -a "$(grep -c '\.qcow2$\|\.img$' "$WEB.calls")" = 1 -a "$(vcalls | grep -c '^define ')" = 1
check "…and the evidence is byte-identical" test "$(evsnap)" = "$before"
apx "" --template fedora44
check "--template on a ready template verifies it and builds nothing" \
    test "$RC" -eq 0 -a "$(vcalls | grep -c '^define ')" = 1
apx "" --template fedora45
check "--template with an unknown distribution is refused (exit 2)" test "$RC" -eq 2

# ---------------------------------------------------------------------------
section "TEMPLATE-ubuntu2404: a terminal cloud-init error stops at once; a running one does not"
# ---------------------------------------------------------------------------
# The probe the first real TEMPLATE-ubuntu2404 would have answered from 960 s
# on (templates/ubuntu2404/failure.20260926T101307Z: probe.txt, and cloud-init
# status --long in guest-logs.txt): runcmd exited 100 because dpkg stopped at
# the /etc/gdm3/custom.conf conffile prompt; nothing was left running.
UBU_REAL=$'identity=\ntemplate_ready=\nmachine_id=188228fba496438f983fed3822f75250\nhostname=g8-u2404-tmpl\ncloud_init=error\nci_extended=error - done\nci_error=(\'scripts_user\', RuntimeError(\'Runparts: 1 failures (runcmd) in 1 attempted commands\'))\nuser_uid=1000\nsession_type=\ndefault_target=graphical.target\nos=Ubuntu 24.04.5 LTS\nkernel=6.8.0-139-generic\nsel_context=unconfined\nsel_enforce=\ndatasource=nocloud\npkg_procs=0\nnet_ipv4=192.168.68.80/22\nprepare_stage=stage: desktop\nprepare_running=0\nprepare_failed=\nprepare_error=dpkg: error processing package gdm3 (--configure):  end of file on stdin at conffile prompt \nuptime_s=5875'
check "the real Ubuntu probe is terminal: cloud-init 'error - done', nothing running, no marker" \
    contains "$(UNITG ap_probe_terminal "$UBU_REAL")" "cloud-init finished with an error and nothing running can still write the marker"
check "…and its summary names the error and the module" \
    contains "$(UNITG ap_probe_summary "$UBU_REAL")" "cloud-init error (error - done): ('scripts_user', RuntimeError('Runparts: 1 failures (runcmd)"
check "the prepare script's own failure record is terminal by itself" \
    contains "$(UNITG ap_probe_terminal "$(sed 's/^prepare_failed=$/prepare_failed=exit=100 stage=desktop/; s/^cloud_init=.*/cloud_init=running/; s/^ci_extended=.*/ci_extended=running/' <<<"$UBU_REAL")")" "the prepare script failed (exit=100 stage=desktop)"
not_term() { is_false_g ap_probe_terminal "$(sed "$1" <<<"$UBU_REAL")"; }
check "NOT terminal: cloud-init error while cloud-init is still running ('error - running')" not_term 's/^ci_extended=.*/ci_extended=error - running/'
check "NOT terminal: cloud-init error but the prepare script is still running" not_term 's/^prepare_running=.*/prepare_running=1/'
check "NOT terminal: cloud-init error but a package transaction is active" not_term 's/^pkg_procs=.*/pkg_procs=2/'
check "NOT terminal: whether anything still runs could not be read" not_term 's/^pkg_procs=.*/pkg_procs=/; s/^prepare_running=.*/prepare_running=/'
check "NOT terminal: cloud-init running, package transaction active (the first 900 s of the real run)" \
    not_term 's/^cloud_init=.*/cloud_init=running/; s/^ci_extended=.*/ci_extended=running/; s/^pkg_procs=.*/pkg_procs=2/; s/^prepare_running=.*/prepare_running=1/'
check "NOT terminal: the marker is there, whatever cloud-init says" not_term 's/^template_ready=.*/template_ready=yes/'

ubu_rec() { sed -n "s/^$1=//p" "$SC/ev/autopilot/records/template-ubuntu2404"; }
# ---------------------------------------------------------------------------
section "The probe, run for real against cloud-init's own status output"
# ---------------------------------------------------------------------------
# ap_probe's guest script, executed here by sh with a cloud-init that prints
# what the real guests printed: the failed TEMPLATE-ubuntu2404 ("error - done",
# one error) and the one that passed ("degraded done": an empty errors: list,
# recoverable warnings only — whose ci_error once read "recoverable_errors:").
mkdir -p "$WORK/ci/fail" "$WORK/ci/ok"
printf '#!/bin/sh\ncat <<X\nstatus: error\nextended_status: error - done\nboot_status_code: enabled-by-generator\ndetail: DataSourceNoCloud [seed=/dev/sr0]\nerrors:\n\t- (%s)\nrecoverable_errors:\nDEPRECATED:\n\t- Deprecated cloud-config provided: users.0.uid\nX\n' \
    "'scripts_user', RuntimeError('Runparts: 1 failures (runcmd) in 1 attempted commands')" > "$WORK/ci/fail/cloud-init"
printf '#!/bin/sh\ncat <<X\nstatus: done\nextended_status: degraded done\nboot_status_code: enabled-by-generator\ndetail: DataSourceNoCloud [seed=/dev/sr0]\nerrors:\nrecoverable_errors:\nDEPRECATED:\n\t- Deprecated cloud-config provided: users.0.uid\nX\n' > "$WORK/ci/ok/cloud-init"
chmod +x "$WORK/ci/fail/cloud-init" "$WORK/ci/ok/cloud-init"
probe_local() { PATH="$1:$PATH" UNITG eval 'ga_exec() { shift; sh -c "$*"; }; ap_probe local'; }
pf="$(probe_local "$WORK/ci/fail")"; po="$(probe_local "$WORK/ci/ok")"
check "real 'error - done' output: cloud_init=error, ci_extended='error - done', ci_error names scripts_user" \
    test "$(UNITG ap_kv "$pf" cloud_init)" = error -a "$(UNITG ap_kv "$pf" ci_extended)" = "error - done" \
         -a "$(UNITG ap_kv "$pf" ci_error)" = "('scripts_user', RuntimeError('Runparts: 1 failures (runcmd) in 1 attempted commands'))"
check "real 'degraded done' output: cloud_init=done and NO error (not the next header, 'recoverable_errors:')" \
    test "$(UNITG ap_kv "$po" cloud_init)" = "done" -a "$(UNITG ap_kv "$po" ci_extended)" = "degraded done" -a -z "$(UNITG ap_kv "$po" ci_error)"
check "…and 'degraded done' is not terminal" is_false_g ap_probe_terminal "$po"

scenario ubuterm
before="$(evsnap)"
FAKE_CONFFILE_FAIL=pliwee-g8-u2404-tmpl apx "" --template ubuntu2404
check "a terminal cloud-init error: STOP (exit 3) as infrastructure, at once, not at the timeout" \
    test "$RC" -eq 3 -a -n "$(grep '^\[STOP\] TEMPLATE-ubuntu2404 — infrastructure preparation FAILED: reached a terminal error after [0-9]*s: the prepare script failed (exit=100 stage=desktop)' <<<"$OUT")" \
         -a -z "$(grep 'not ready after' <<<"$OUT")"
check "…naming the failing module, the stage, the package manager and the dpkg error" \
    test -n "$(grep "failing module:  ('scripts_user', RuntimeError('Runparts: 1 failures (runcmd)" <<<"$OUT")" \
         -a -n "$(grep 'package manager: inactive' <<<"$OUT")" -a -n "$(grep 'prepare:         stage: desktop; exit=100 stage=desktop' <<<"$OUT")" \
         -a -n "$(grep 'reason:          dpkg: error processing package gdm3 (--configure):  end of file on stdin at conffile prompt' <<<"$OUT")"
check "…the template recorded failed, its diagnostics kept, the paths printed" \
    test "$(ubu_rec state)" = failed -a -s "$(ubu_rec failure_dir)/summary.txt" -a -s "$(ubu_rec failure_dir)/guest-logs.txt" \
         -a -n "$(grep "diagnosis:     $(ubu_rec failure_dir)/summary.txt" <<<"$OUT")"
check "…the guest shut down cleanly (not destroyed)" \
    test "$(cat "$SC/libvirt/doms/pliwee-g8-u2404-tmpl/state")" = "shut off" -a -z "$(vcalls | grep '^destroy pliwee-g8-u2404-tmpl')"
check "…no gate ran or was recorded: nothing became LIFECYCLE-ubuntu2404 FAIL" \
    test ! -s "$STUB/calls" -a -z "$(find "$SC/ev/state" -maxdepth 1 \( -name 'G7UP-*' -o -name 'LIFECYCLE-*' \))" -a "$(cstate LIFECYCLE-ubuntu2404)" = PENDING
check "…and the evidence is byte-identical" test "$(evsnap)" = "$before"
apx "" --template ubuntu2404
check "resume: the failed template is discarded and built again from the base image, and is ready" \
    test "$RC" -eq 0 -a -n "$(grep 'TEMPLATE-ubuntu2404 — an unfinished build (failed) is discarded' <<<"$OUT")" -a "$(ubu_rec state)" = ready \
         -a -n "$(vcalls | grep '^vol-delete --pool default pliwee-g8-u2404-tmpl.qcow2')"
RDY="$SC/ev/autopilot/templates/ubuntu2404/readiness.txt"
check "…its autologin is in /etc/gdm3/custom.conf, the file Ubuntu's GDM reads" \
    test -n "$(grep -x 'gdm_conf=/etc/gdm3/custom.conf' "$RDY")" -a -n "$(grep -x 'gdm_conf_read_by_gdm=yes' "$RDY")" -a -n "$(grep -x 'autologin=anyflow' "$RDY")"
check "…and the failure's diagnostics are still there" test -s "$(sed -n 's/^failure_dir=//p' "$SC/ev/autopilot/records/history"/template-ubuntu2404.* | tail -1)/summary.txt"

scenario ubuslow
FAKE_SLOW_PREPARE=pliwee-g8-u2404-tmpl FAKE_SLOW_PROBES=4 apx "" --template ubuntu2404
check "a package transaction still running is waited for, not stopped: the template is ready" \
    test "$RC" -eq 0 -a -n "$(grep 'TEMPLATE-ubuntu2404 — observed at 0s .*package transaction active (2 processes)' "$SC/ev/autopilot/journal.log")"
scenario ubuciwarn
FAKE_SLOW_PREPARE=pliwee-g8-u2404-tmpl FAKE_CI_ERROR_RUNNING=pliwee-g8-u2404-tmpl FAKE_SLOW_PROBES=4 apx "" --template ubuntu2404
check "a cloud-init error while cloud-init still runs ('error - running') is waited through: ready" \
    test "$RC" -eq 0 -a -n "$(grep 'TEMPLATE-ubuntu2404 — observed at 0s .*cloud-init error (error - running)' "$SC/ev/autopilot/journal.log")"

scenario debgdm
apx "" --template debian13
RDY="$SC/ev/autopilot/templates/debian13/readiness.txt"
check "Debian 13: autologin goes into /etc/gdm3/daemon.conf, the only file its GDM reads, and a session comes up" \
    test "$RC" -eq 0 -a -n "$(grep -x 'gdm_conf=/etc/gdm3/daemon.conf' "$RDY")" -a -n "$(grep -x 'gdm_conf_read_by_gdm=yes' "$RDY")"
scenario u2604gdm
apx "" --template ubuntu2604
check "Ubuntu 26.04: the same fix (custom.conf written after the desktop), ready" \
    test "$RC" -eq 0 -a -n "$(grep -x 'gdm_conf=/etc/gdm3/custom.conf' "$SC/ev/autopilot/templates/ubuntu2604/readiness.txt")"

# ---------------------------------------------------------------------------
section "Nothing in the autopilot touches signing, releases, history or the phone's data"
# ---------------------------------------------------------------------------
SRC=("$AP" "$HERE"/lib/autopilot-*.sh "$HERE"/vm/*.sh "$HERE/u2-state-check.sh")
forbid() { # PATTERN — no code line (comments and quoted messages aside) matches
    local hits
    hits="$(grep -nE -e "$1" "${SRC[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE -e "\"[^\"]*($1)[^\"]*\"")"
    [ -z "$hits" ] || { printf '%s\n' "$hits" >&2; return 1; }
}
check "no signing procedure, media or keystore" forbid 'provision-signing-keys|--media-[ab]|MEDIA_[AB]|keystore'
check "no --run of a W2/W6 gate, and no --next (which would pick W2-KDE)" forbid '--run W[26]|--next'
check "no release publication, repository creation, push or merge" forbid 'gh (release|repo)|git (push|merge|commit|rebase)'
check "no sudo and no host reboot, as a command" forbid '^[[:space:]]*(sudo|reboot|shutdown|systemctl reboot)( |$)'
check "no install, uninstall or data wipe on the phone" forbid 'adb[^|]* (install|uninstall)|pm clear'

# ---------------------------------------------------------------------------
section "Records across every scenario, and the real evidence"
# ---------------------------------------------------------------------------
all_records_ok() { # every current record every scenario wrote: key=value, each key once
    local f bad=0 n=0
    for f in "$WORK"/sc-*/ev/autopilot/records/*; do
        [ -f "$f" ] || continue
        case "$f" in *.partial.*) continue ;; esac
        n=$((n + 1))
        if [ -n "$(cut -d= -f1 "$f" | sort | uniq -d)" ]; then
            echo "duplicate key: $f" >&2; bad=1
        elif grep -qvE '^[A-Za-z0-9_.-]+=' "$f"; then
            echo "not key=value: $f" >&2; bad=1
        fi
    done
    [ "$n" -gt 50 ] && [ "$bad" = 0 ]
}
check "every record written in every scenario has one line per key (more than 50 records checked)" all_records_ok
check "the interrupted-then-resumed lifecycle guest: ONE fresh= line, fresh=no (used by the resumed gate)" \
    test "$(grep -c '^fresh=' "$WORK/sc-interrupt/ev/autopilot/records/guest-pliwee-g8-f44-lc")" = 1 \
         -a "$(sed -n 's/^fresh=//p' "$WORK/sc-interrupt/ev/autopilot/records/guest-pliwee-g8-f44-lc")" = no
check "…and its revert is in the record once (reverted_why=)" \
    test "$(grep -c '^reverted_why=' "$WORK/sc-interrupt/ev/autopilot/records/guest-pliwee-g8-f44-lc")" = 1
check "the real Pre-G8 evidence ($REAL_EV) is byte-identical after the whole suite" test "$(real_ev_snap)" = "$REAL_EV_BEFORE"

printf '\n-----------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
