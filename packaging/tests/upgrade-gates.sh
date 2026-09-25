#!/usr/bin/env bash
# upgrade-gates.sh — G7-UP: an OmniBridge 1.0.0 install upgraded to Pliwee,
# inside a libvirt guest (rebrand plan §3; ADR-0020). Run once per
# distribution: Fedora 44, Ubuntu 24.04, Ubuntu 26.04, Debian 13.
#
# THREE STAGES, because two steps of §3 need a human or a second machine and a
# harness must not pretend otherwise:
#
#   --stage install    U0 U1 U2(automated half)
#       Delivers and verifies the OmniBridge 1.0.0 packages, installs them,
#       enables omnibridged.service for GUEST_USER, and on Fedora adds the
#       `omnibridge` firewalld service to a non-default zone. It then STOPS.
#       The operator pairs a peer (the phone, or fake_phone on a second host),
#       grants clipboard.v1 and files.v1, sets a clipboard policy and a
#       notification lock policy, and selects the peer in the GUI — the rest of
#       U2, which needs the other device.
#
#   --stage upgrade    O1 U3 U4 O2 U5 U7 U9 U10
#       Refuses to start unless at least --min-peers peers are paired. Records
#       O1, upgrades with the distribution's normal command, cycles the
#       session, records O2 and asserts it equal to O1 field by field, then
#       the restart (U7), the never-enabled account (U9, a second user created
#       for it before the upgrade — see below), and the downgrade (U10).
#       U6 (the peer reconnects, a clipboard round-trip and a file) needs the
#       peer and is lifecycle-peer-gates.sh, run against the upgraded guest
#       BEFORE U10; this stage prints the exact command and records U6 as
#       not executed here.
#
#   --stage negative-unreadable    U8, on a FRESH guest
#       Plants an unreadable ~/.local/share/omnibridge, installs Pliwee, and
#       asserts that the daemon refuses, names the path, and that no
#       ~/.local/share/pliwee/identity.key exists.
#
# The package sets: --old-pkgdir holds the PUBLISHED 1.0.0 artifacts for this
# distribution with SHA256SUMS (and SHA256SUMS.asc, verified when --keyring and
# --fingerprint are given — U1 is not a PASS without that). --new-pkgdir holds
# the Pliwee set: pliwee, pliwee-gui and the transitional omnibridge
# package(s), with SHA256SUMS.
#
# Every rule in AGENTS.md applies and is enforced with lib/assert.sh: tools
# present, captures non-empty, windows anchored on what the product wrote
# about THIS run (the daemon's "migrated from" line after a journal cursor
# taken before the upgrade), exact counts, two observations around every
# operation.
#
# STATUS: authored in rebrand Wave 7 and checked with `bash -n`, the H1/H2
# static checks and the self-tests of the primitives it calls. It has NOT yet
# been run against a guest; its first run is the G7-UP gate itself.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/guest-agent.sh
. "$HERE/lib/guest-agent.sh"
# shellcheck source=lib/assert.sh
. "$HERE/lib/assert.sh"

STAGE=""; DOMAIN=""; DISTRO=""; OLD_PKGDIR=""; NEW_PKGDIR=""; EVIDENCE=""
KEYRING=""; FINGERPRINT=""; MIN_PEERS=1
GUEST_USER="${GUEST_USER:-anyflow}"; GUEST_UID="${GUEST_UID:-1000}"
# U9: an account on the same guest that never enabled the unit.
IDLE_USER="${IDLE_USER:-g7idle}"

usage() {
    cat >&2 <<USAGE
usage: $0 --stage install|upgrade|negative-unreadable --domain DOM --distro NAME
          --evidence DIR [--old-pkgdir DIR] [--new-pkgdir DIR]
          [--keyring FILE --fingerprint FPR] [--min-peers N]
USAGE
    exit 2
}
while [ $# -gt 0 ]; do
    case "$1" in
        --stage) STAGE="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --distro) DISTRO="$2"; shift 2 ;;
        --old-pkgdir) OLD_PKGDIR="$2"; shift 2 ;;
        --new-pkgdir) NEW_PKGDIR="$2"; shift 2 ;;
        --evidence) EVIDENCE="$2"; shift 2 ;;
        --keyring) KEYRING="$2"; shift 2 ;;
        --fingerprint) FINGERPRINT="$2"; shift 2 ;;
        --min-peers) MIN_PEERS="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$STAGE" ] && [ -n "$DOMAIN" ] && [ -n "$DISTRO" ] && [ -n "$EVIDENCE" ] || usage

PASS=0; FAIL=0; NA=0
mkdir -p "$EVIDENCE"
ok()      { PASS=$(( PASS + 1 )); printf 'ok    %s\n' "$*"; }
notok()   { FAIL=$(( FAIL + 1 )); printf 'not ok  %s\n' "$*"; }
na()      { NA=$(( NA + 1 ));   printf 'n/a   %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
abort()   { printf '\nPRECONDITION FAILED: %s\n' "$*" >&2; exit 3; }
save()    { cat > "$EVIDENCE/$1"; }
finish()  {
    printf '\n%d ok, %d not ok, %d n/a (stage %s, %s)\n' "$PASS" "$FAIL" "$NA" "$STAGE" "$DISTRO"
    [ "$FAIL" -eq 0 ]; exit $?
}

gx() { ga_exec "$DOMAIN" "$@"; }
gu_as() { # USER UID COMMAND — as that user, inside their session bus
    ga_exec "$DOMAIN" "runuser -u $1 -- env XDG_RUNTIME_DIR=/run/user/$2 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$2/bus sh -c $(printf '%q' "$3")"
}
gu() { gu_as "$GUEST_USER" "$GUEST_UID" "$*"; }

case "$DISTRO" in
    fedora44)   PKGEXT=rpm; expect_os="Fedora Linux 44" ;;
    ubuntu2404) PKGEXT=deb; expect_os="Ubuntu 24.04" ;;
    ubuntu2604) PKGEXT=deb; expect_os="Ubuntu 26.04" ;;
    debian13)   PKGEXT=deb; expect_os="Debian GNU/Linux 13" ;;
    *) abort "unknown --distro '$DISTRO'" ;;
esac

# ---------------------------------------------------------------------------
section "U0 — preconditions and tools"
# ---------------------------------------------------------------------------
need_tool virsh jq sha256sum || abort "a host tool this harness depends on is missing"
ga_ping "$DOMAIN" 300 || abort "guest agent in '$DOMAIN' does not answer"
guest_os="$(gx 'sed -n "s/^PRETTY_NAME=//p" /etc/os-release | tr -d \"')"
contains "$guest_os" "$expect_os" || abort "--distro $DISTRO expects '$expect_os'; the guest is '${guest_os:-<unreadable>}'"
ok "U0: the guest is $guest_os"
[ "$(gx 'id -u' | tr -d '[:space:]')" = 0 ] || abort "the guest agent is not root"
gx "id -u $GUEST_USER" >/dev/null 2>&1 || abort "no guest user '$GUEST_USER'"
if [ "$PKGEXT" = rpm ]; then guest_tools="rpm dnf systemctl sha256sum firewall-cmd runuser journalctl"
else guest_tools="dpkg apt-get systemctl sha256sum runuser journalctl"; fi
missing="$(gx "for t in $guest_tools; do command -v \$t >/dev/null 2>&1 || echo \$t; done")"
[ -z "${missing//[[:space:]]/}" ] || abort "U0: guest tools missing: $missing"
ok "U0: guest tools present: $guest_tools"

deliver() { # HOSTDIR GUESTDIR — every package plus SHA256SUMS, digest-verified in the guest
    local dir="$1" to="$2" p n=0
    [ -f "$dir/SHA256SUMS" ] || abort "$dir has no SHA256SUMS"
    gx "rm -rf $to && mkdir -p $to" >/dev/null
    for p in "$dir"/*."$PKGEXT" "$dir"/SHA256SUMS "$dir"/SHA256SUMS.asc; do
        [ -f "$p" ] || continue
        ga_put "$DOMAIN" "$p" "$to/$(basename "$p")" || abort "could not deliver $(basename "$p")"
        n=$(( n + 1 ))
    done
    gx "cd $to && sha256sum --ignore-missing -c SHA256SUMS" > "$EVIDENCE/deliver-$(basename "$to").txt" 2>&1 \
        || abort "the packages in $to do not verify against SHA256SUMS inside the guest"
    printf '%s' "$n"
}

# ===========================================================================
if [ "$STAGE" = install ]; then
# ===========================================================================
[ -n "$OLD_PKGDIR" ] || usage
section "U1 — install the published OmniBridge 1.0.0 packages"
pre="$(gx "rpm -qa 'omnibridge*' 'pliwee*' 2>/dev/null; dpkg-query -W -f '\${Package}\n' 'omnibridge*' 'pliwee*' 2>/dev/null" || true)"
[ -z "${pre//[[:space:]]/}" ] || abort "the guest already has a package installed: $pre"
gx "test ! -e /home/$GUEST_USER/.local/share/omnibridge && test ! -e /home/$GUEST_USER/.local/share/pliwee" \
    || abort "the guest user already has OmniBridge or Pliwee state; U1 needs a clean account"
if [ -n "$KEYRING" ] && [ -n "$FINGERPRINT" ]; then
    need_tool gpg || abort "gpg is needed to verify SHA256SUMS.asc"
    if "$HERE/../release/verify-release.sh" --dir "$OLD_PKGDIR" --keyring "$KEYRING" \
            --fingerprint "$FINGERPRINT" > "$EVIDENCE/U1-verify-release.txt" 2>&1; then
        ok "U1: SHA256SUMS.asc verifies against $FINGERPRINT"
    else
        notok "U1: the 1.0.0 set does not verify against $FINGERPRINT (see U1-verify-release.txt)"
    fi
else
    notok "U1: no --keyring/--fingerprint given; the published set was NOT verified against SHA256SUMS.asc"
fi
n="$(deliver "$OLD_PKGDIR" /root/g7-old)"
ok "U1: $n file(s) delivered and digest-verified in the guest"
if [ "$PKGEXT" = rpm ]; then
    out="$(gx 'cd /root/g7-old && dnf install -y --disablerepo="*" ./omnibridge-1.0.0-*.x86_64.rpm ./omnibridge-gui-1.0.0-*.x86_64.rpm 2>&1')"; rc=$?
    vers="$(gx "rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE}\n' omnibridge omnibridge-gui")"
else
    out="$(gx 'cd /root/g7-old && DEBIAN_FRONTEND=noninteractive apt-get install -y ./omnibridge_1.0.0-1_amd64.deb ./omnibridge-gui_1.0.0-1_amd64.deb 2>&1')"; rc=$?
    vers="$(gx "dpkg-query -W -f '\${Package} \${Version}\n' omnibridge omnibridge-gui")"
fi
printf '%s\n' "$out" | save U1-install.txt
[ "$rc" -eq 0 ] && ok "U1: install exited 0" || notok "U1: install exited $rc"
printf '%s\n' "$vers" | save U1-versions.txt
n_ok="$(grep -cE '^omnibridge(-gui)? 1\.0\.0-1(\.fc44)?$' <<<"$vers" || true)"
need_exact_count "U1: packages at exactly 1.0.0-1" "$n_ok" 2 && ok "U1: omnibridge and omnibridge-gui are exactly 1.0.0-1" \
    || notok "U1: versions are: $(tr '\n' ' ' <<<"$vers")"

section "U2 — enable, start, firewall (the automated half)"
gu 'systemctl --user enable --now omnibridged.service' >/dev/null 2>&1
ga_wait_for "$DOMAIN" 60 "pgrep -x omnibridged >/dev/null" || abort "omnibridged did not start"
en="$(gu 'systemctl --user is-enabled omnibridged.service' | tr -d '[:space:]')"
[ "$en" = enabled ] && ok "U2: omnibridged.service is enabled" || notok "U2: is-enabled says '$en'"
gu 'omnibridge status' 2>&1 | save U2-status.txt
need_nonempty "U2: omnibridge status" "$(cat "$EVIDENCE/U2-status.txt")" 3 && ok "U2: omnibridge status archived"
# The idle account for U9 exists BEFORE the upgrade and never enables anything.
gx "id -u $IDLE_USER >/dev/null 2>&1 || useradd -m $IDLE_USER" >/dev/null
gx "test ! -e /home/$IDLE_USER/.config/systemd/user/default.target.wants/omnibridged.service" \
    && ok "U9 setup: '$IDLE_USER' exists and has never enabled omnibridged.service" \
    || notok "U9 setup: '$IDLE_USER' already has an enablement link"
if [ "$PKGEXT" = rpm ]; then
    gx 'firewall-cmd --permanent --zone=work --add-service=omnibridge && firewall-cmd --reload' > "$EVIDENCE/U2-firewall.txt" 2>&1 \
        && contains "$(gx 'firewall-cmd --permanent --zone=work --list-services')" omnibridge \
        && ok "U2: the omnibridge firewalld service is in zone 'work'" \
        || notok "U2: could not add the omnibridge service to zone 'work'"
fi
cat <<NEXT

Stage 'install' done. Now, by hand (U2, the half that needs the other device):
  * pair a peer with 'omnibridge pair' (the phone, or fake_phone on a second host);
  * omnibridge grant <peer> clipboard.v1 ; omnibridge grant <peer> files.v1
  * set a clipboard policy and a notification lock policy for it;
  * open omnibridge-gui once and select the peer (this writes gui.json).
Then run:  $0 --stage upgrade --domain $DOMAIN --distro $DISTRO --new-pkgdir DIR --evidence $EVIDENCE
NEXT
finish
fi

# Facts compared across the upgrade: identity, and per device the name, id,
# fingerprint, paired flag and grants. Taken from the CLI, whose name changes.
facts() { # CLI
    gu "$1 status" 2>/dev/null | sed -n \
        -e 's/^ *device  *\(.*\)$/device \1/p' -e 's/^ *fingerprint  *\(.*\)$/fingerprint \1/p' \
        -e 's/^ *paired  *\([0-9][0-9]*\) device(s)$/paired-count \1/p' \
        -e 's/^ *granted  *\(.*\)$/granted \1/p' -e 's/^ *paired  *\(yes\|no\)$/paired \1/p'
}
LEGACY="/home/$GUEST_USER/.local/share/omnibridge"
CANON="/home/$GUEST_USER/.local/share/pliwee"
LEGACY_CFG="/home/$GUEST_USER/.config/omnibridge/gui.json"
CANON_CFG="/home/$GUEST_USER/.config/pliwee/gui.json"
digests() { gx "sha256sum $LEGACY/identity.key $LEGACY/state.json $LEGACY_CFG 2>&1"; }

# ===========================================================================
if [ "$STAGE" = upgrade ]; then
# ===========================================================================
[ -n "$NEW_PKGDIR" ] || usage
# The downgrade (U10) is part of this stage and needs the published 1.0.0 set.
# Without it U10 used to be recorded n/a and the stage could still finish
# green having measured no way back (pre-W8 remediation, owner decision 7).
[ -n "$OLD_PKGDIR" ] \
    || abort "--old-pkgdir (the published OmniBridge 1.0.0 set) is required by the upgrade stage: U10 cannot be measured without it"
section "O1 — before"
# The transition is only measured FROM OmniBridge 1.0.0. A guest where that
# is not what is installed would run every U3 assertion against something
# else, so the expected old packages and version are a precondition, checked
# before anything is changed.
if [ "$PKGEXT" = rpm ]; then
    vers0="$(gx "rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE}\n' omnibridge omnibridge-gui 2>&1")"
else
    vers0="$(gx "dpkg-query -W -f '\${Package} \${Version}\n' omnibridge omnibridge-gui 2>&1")"
fi
printf '%s\n' "$vers0" | save O1-versions.txt
need_nonempty "O1: installed OmniBridge packages" "$vers0" 1 \
    || abort "O1: the package query returned nothing; the old version cannot be established"
n0="$(grep -cE '^omnibridge(-gui)? 1\.0\.0-1(\.fc44)?$' <<<"$vers0" || true)"
need_exact_count "O1: OmniBridge packages at exactly 1.0.0-1" "$n0" 2 \
    || abort "O1: the expected OmniBridge 1.0.0 packages are not installed ($(tr '\n' ' ' <<<"$vers0")); the transition cannot be measured"
ok "O1: omnibridge and omnibridge-gui are exactly 1.0.0-1 before the upgrade"
o1="$(facts omnibridge)"; printf '%s\n' "$o1" | save O1-facts.txt
need_nonempty "O1 facts" "$o1" 3 || abort "could not read O1 from 'omnibridge status'"
peers="$(sed -n 's/^paired-count //p' <<<"$o1")"
[ "${peers:-0}" -ge "$MIN_PEERS" ] 2>/dev/null \
    || abort "O1: $peers peer(s) paired; U2 asks for at least $MIN_PEERS — pair one before this stage"
ok "O1: $peers paired peer(s), identity '$(sed -n 's/^device //p' <<<"$o1")'"
d1="$(digests)"; printf '%s\n' "$d1" | save O1-digests.txt
need_exact_count "O1: legacy files digested" "$(grep -cE '^[0-9a-f]{64} ' <<<"$d1")" 3 \
    && ok "O1: identity.key, state.json and gui.json digested" \
    || notok "O1: not every legacy file exists (gui.json is written by selecting the peer in the GUI)"
en1="$(gu 'systemctl --user is-enabled omnibridged.service' | tr -d '[:space:]')"
pids1="$(gx 'pgrep -c -x omnibridged || true' | tr -d '[:space:]')"
[ "$en1" = enabled ] || abort "O1: omnibridged.service is '$en1'; U9 is the never-enabled case, this is not"
need_exact_count "O1: daemon processes" "$pids1" 1 && ok "O1: exactly one omnibridged, enabled"
cursor="$(gu 'journalctl --user -n0 --show-cursor 2>/dev/null' | sed -n 's/^-- cursor: //p' | tr -d '\r\n')"
[ -n "$cursor" ] || abort "no journal cursor before the upgrade; the U4 anchor could not be windowed"

section "U3 — upgrade with the distribution's normal command"
n="$(deliver "$NEW_PKGDIR" /root/g7-new)"
ok "U3: $n file(s) delivered and digest-verified"
if [ "$PKGEXT" = rpm ]; then
    out="$(gx 'cd /root/g7-new && dnf upgrade -y --disablerepo="*" ./pliwee-[0-9]*.x86_64.rpm ./pliwee-gui-[0-9]*.x86_64.rpm ./omnibridge-[0-9]*.noarch.rpm 2>&1')"; rc=$?
    after="$(gx "rpm -q --qf '%{NAME} %{VERSION}\n' omnibridge omnibridge-gui pliwee pliwee-gui 2>&1")"
else
    gx 'mkdir -p /root/g7-repo && cp /root/g7-new/*.deb /root/g7-repo/ && cd /root/g7-repo && (command -v dpkg-scanpackages >/dev/null && dpkg-scanpackages . > Packages || apt-ftparchive packages . > Packages) && echo "deb [trusted=yes] file:/root/g7-repo ./" > /etc/apt/sources.list.d/g7.list && apt-get update -qq' > "$EVIDENCE/U3-repo.txt" 2>&1 \
        || abort "could not publish the Pliwee set as a local apt repository in the guest"
    out="$(gx 'DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1')"; rc=$?
    after="$(gx "dpkg-query -W -f '\${Package} \${Version}\n' omnibridge omnibridge-gui pliwee pliwee-gui 2>&1")"
fi
printf '%s\n' "$out" | save U3-upgrade.txt; printf '%s\n' "$after" | save U3-packages-after.txt
[ "$rc" -eq 0 ] && ok "U3: the upgrade exited 0" || notok "U3: the upgrade exited $rc"
contains_re "$after" '^pliwee 1\.[1-9]' && contains_re "$after" '^pliwee-gui 1\.[1-9]' \
    && ok "U3: pliwee and pliwee-gui are installed" || notok "U3: pliwee/pliwee-gui are not both installed"
contains_re "$after" '^omnibridge 1\.[1-9]' \
    && ok "U3: omnibridge was upgraded to the transitional package (not erased)" \
    || notok "U3: omnibridge is not the transitional 1.x package"
if grep -qiE 'scriptlet failed|error in (PREIN|POSTIN|PREUN|POSTUN)|dpkg: error' <<<"$out"; then
    notok "U3: a scriptlet error appears in the upgrade output"
else ok "U3: no scriptlet error in ${#out} bytes of upgrade output"; fi
[ "$(gx 'readlink /usr/lib/systemd/user/omnibridged.service' | tr -d '[:space:]')" = pliweed.service ] \
    && ok "U3: omnibridged.service is now the alias of pliweed.service" \
    || notok "U3: omnibridged.service is not the alias of pliweed.service"

section "U4 — the next login"
gx "loginctl terminate-user $GUEST_USER" >/dev/null 2>&1
ga_wait_for "$DOMAIN" 60 "! pgrep -u $GUEST_USER -x omnibridged >/dev/null && ! pgrep -u $GUEST_USER -x pliweed >/dev/null" \
    || abort "the session did not end; the next login cannot be measured"
gx "systemctl start user@$GUEST_UID.service" >/dev/null 2>&1
ga_wait_for "$DOMAIN" 120 "pgrep -u $GUEST_USER -x pliweed >/dev/null" \
    && ok "U4: pliweed started at the next login" || notok "U4: pliweed did not start at the next login"
jnl="$(gu "journalctl --user --after-cursor '$cursor' --no-pager -o cat 2>/dev/null")"
printf '%s\n' "$jnl" | save U4-journal.txt
if need_window_covers "U4 journal after the upgrade" "$jnl" "migrated from $LEGACY"; then
    ok "U4: the daemon logged 'migrated from $LEGACY' in this boot's window"
else notok "U4: no 'migrated from' line after the pre-upgrade cursor"; fi
contains "$jnl" "systemctl --user reenable pliweed.service" \
    && ok "U4: the daemon logged the one-line reenable instruction (legacy enablement)" \
    || notok "U4: the legacy-enablement instruction was not logged"

section "O2 — after, equal to O1"
o2="$(facts pliwee)"; printf '%s\n' "$o2" | save O2-facts.txt
need_nonempty "O2 facts" "$o2" 3 || abort "could not read O2 from 'pliwee status'"
[ "$o1" = "$o2" ] && ok "O2: identity, peers, fingerprints and grants equal O1 ($(grep -c . <<<"$o2") facts)" \
    || { notok "O2 differs from O1"; diff <(printf '%s\n' "$o1") <(printf '%s\n' "$o2") | sed 's/^/        /'; }
d2="$(digests)"; printf '%s\n' "$d2" | save O2-legacy-digests.txt
[ "$d1" = "$d2" ] && ok "O2: the legacy identity.key, state.json and gui.json are byte-identical" \
    || notok "O2: A LEGACY FILE CHANGED"
rec="$(gx "cat $CANON/MIGRATED_FROM")"; printf '%s\n' "$rec" | save O2-MIGRATED_FROM.txt
for f in identity.key state.json; do
    want="$(awk -v f="$LEGACY/$f" '$2 == f { print $1 }' <<<"$d1")"
    contains "$rec" "sha256.$f=$want" && [ -n "$want" ] \
        && ok "O2: MIGRATED_FROM records the O1 digest of $f" || notok "O2: MIGRATED_FROM does not carry the O1 digest of $f"
done
gx "test -f $CANON_CFG" && ok "O2: gui.json exists under ~/.config/pliwee" || notok "O2: no ~/.config/pliwee/gui.json"
pids2="$(gx 'pgrep -c -x pliweed || true' | tr -d '[:space:]'; )"; old2="$(gx 'pgrep -c -x omnibridged || true' | tr -d '[:space:]')"
need_exact_count "O2: pliweed processes" "$pids2" 1 && need_exact_count "O2: omnibridged processes" "$old2" 0 \
    && ok "O2: exactly one daemon, and it is pliweed"

if [ "$PKGEXT" = rpm ]; then
section "U5 — firewalld reload"
    fw="$(gx 'firewall-cmd --reload && firewall-cmd --permanent --zone=work --list-services && firewall-cmd --info-service=omnibridge' 2>&1)"; rc=$?
    printf '%s\n' "$fw" | save U5-firewall.txt
    [ "$rc" -eq 0 ] && contains "$fw" omnibridge && contains "$fw" "55432/tcp" \
        && ok "U5: reload succeeds and the omnibridge service still resolves to 55432/tcp" \
        || notok "U5: the firewall did not reload cleanly with the omnibridge service"
else na "U5: firewalld is not part of the $DISTRO packaging (audit §9.3)"; fi

na "U6: the peer reconnect, clipboard round-trip and file are lifecycle-peer-gates.sh, run now against this guest: $HERE/lifecycle-peer-gates.sh --domain $DOMAIN --distro $DISTRO ..."

section "U7 — restart: nothing re-migrated"
m1="$(gx "stat -c '%Y %s' $CANON/MIGRATED_FROM; sha256sum $CANON/MIGRATED_FROM")"
gu 'systemctl --user restart pliweed.service' >/dev/null 2>&1
ga_wait_for "$DOMAIN" 60 "pgrep -x pliweed >/dev/null" || notok "U7: pliweed did not come back"
m2="$(gx "stat -c '%Y %s' $CANON/MIGRATED_FROM; sha256sum $CANON/MIGRATED_FROM")"
[ -n "$m1" ] && [ "$m1" = "$m2" ] && ok "U7: MIGRATED_FROM unchanged across the restart" || notok "U7: MIGRATED_FROM changed"
[ "$(facts pliwee)" = "$o1" ] && ok "U7: O2 still equals O1" || notok "U7: the facts moved after a restart"

section "U9 — the account that never enabled it"
en9="$(gx "test -e /home/$IDLE_USER/.config/systemd/user/default.target.wants/pliweed.service || test -e /home/$IDLE_USER/.config/systemd/user/default.target.wants/omnibridged.service; echo \$?" | tr -d '[:space:]')"
[ "$en9" = 1 ] && ok "U9: '$IDLE_USER' has no enablement link for either name" || notok "U9: '$IDLE_USER' is enabled"

section "U10 — downgrade to OmniBridge 1.0.0"
deliver "$OLD_PKGDIR" /root/g7-old >/dev/null
if [ "$PKGEXT" = rpm ]; then
    out="$(gx 'dnf remove -y omnibridge pliwee-gui pliwee 2>&1 && cd /root/g7-old && dnf install -y --disablerepo="*" ./omnibridge-1.0.0-*.x86_64.rpm ./omnibridge-gui-1.0.0-*.x86_64.rpm 2>&1')"; rc=$?
else
    gx 'rm -f /etc/apt/sources.list.d/g7.list && apt-get update -qq' >/dev/null 2>&1
    out="$(gx 'DEBIAN_FRONTEND=noninteractive apt-get remove -y omnibridge omnibridge-gui pliwee-gui pliwee 2>&1 && cd /root/g7-old && DEBIAN_FRONTEND=noninteractive apt-get install -y ./omnibridge_1.0.0-1_amd64.deb ./omnibridge-gui_1.0.0-1_amd64.deb 2>&1')"; rc=$?
fi
printf '%s\n' "$out" | save U10-downgrade.txt
[ "$rc" -eq 0 ] && ok "U10: the 1.0.0 packages are back" || notok "U10: the downgrade exited $rc"
gu 'systemctl --user enable --now omnibridged.service' >/dev/null 2>&1
ga_wait_for "$DOMAIN" 60 "pgrep -x omnibridged >/dev/null" || notok "U10: omnibridged 1.0.0 did not start"
o10="$(facts omnibridge)"; printf '%s\n' "$o10" | save U10-facts.txt
[ "$(sed -n 's/^device //p' <<<"$o10")" = "$(sed -n 's/^device //p' <<<"$o1")" ] \
    && [ "$(sed -n 's/^fingerprint //p' <<<"$o10")" = "$(sed -n 's/^fingerprint //p' <<<"$o1")" ] \
    && ok "U10: OmniBridge 1.0.0 starts on its pre-migration identity" \
    || notok "U10: the downgraded daemon does not show the O1 identity"
finish
fi

# ===========================================================================
if [ "$STAGE" = negative-unreadable ]; then
# ===========================================================================
[ -n "$NEW_PKGDIR" ] || usage
section "U8 — an unreadable legacy directory, on a fresh guest"
pre="$(gx "rpm -qa 'omnibridge*' 'pliwee*' 2>/dev/null; dpkg-query -W -f '\${Package}\n' 'omnibridge*' 'pliwee*' 2>/dev/null" || true)"
[ -z "${pre//[[:space:]]/}" ] || abort "U8 needs a fresh guest; installed: $pre"
gx "test ! -e $CANON" || abort "U8 needs a fresh account; $CANON exists"
gx "install -d -o $GUEST_USER -m 0000 $LEGACY && test -d $LEGACY" || abort "could not plant the unreadable $LEGACY"
ok "U8: planted $LEGACY with mode 0000"
deliver "$NEW_PKGDIR" /root/g7-new >/dev/null
if [ "$PKGEXT" = rpm ]; then gx 'cd /root/g7-new && dnf install -y --disablerepo="*" ./pliwee-[0-9]*.x86_64.rpm ./pliwee-gui-[0-9]*.x86_64.rpm' > "$EVIDENCE/U8-install.txt" 2>&1
else gx 'cd /root/g7-new && DEBIAN_FRONTEND=noninteractive apt-get install -y ./pliwee_*_amd64.deb ./pliwee-gui_*_amd64.deb' > "$EVIDENCE/U8-install.txt" 2>&1; fi \
    || abort "could not install the Pliwee packages"
cursor="$(gu 'journalctl --user -n0 --show-cursor 2>/dev/null' | sed -n 's/^-- cursor: //p' | tr -d '\r\n')"
[ -n "$cursor" ] || abort "no journal cursor; the refusal could not be windowed"
gu 'systemctl --user start pliweed.service' >/dev/null 2>&1; sleep 5
jnl="$(gu "journalctl --user --after-cursor '$cursor' --no-pager -o cat 2>/dev/null")"
printf '%s\n' "$jnl" | save U8-journal.txt
need_window_covers "U8 journal" "$jnl" "refusing to start: $LEGACY" \
    && ok "U8: the daemon refused and named $LEGACY" || notok "U8: no refusal naming $LEGACY in this run's window"
gx "test ! -e $CANON/identity.key" && ok "U8: no $CANON/identity.key was created" || notok "U8: A NEW IDENTITY WAS CREATED"
finish
fi

usage
