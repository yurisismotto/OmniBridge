#!/usr/bin/env bash
# The OmniBridge 1.0.0 -> Pliwee package transition, measured with the real
# package managers on DUMMY packages (rebrand plan, Wave 7). The dummies carry
# the relations and file ownership the real spec/control declare; their
# scriptlets only print which argument they were called with. Every container
# is disposable and runs with --network=none; nothing is installed on the host.
#
#   RPM (dnf5, Fedora 44):
#     R1  pliwee: Obsoletes omnibridge < 1.1.0 + Provides        (the plan's form)
#     R2  transitional omnibridge 1.1.0 Requires pliwee, no Obsoletes
#     R3  both at once
#     RF  the shipped shape: transitional core + Obsoletes/Provides for -gui,
#         real file ownership (unit file -> alias symlink, firewalld files);
#         then idempotence and a rollback to 1.0.0
#     RL  the same set as local files: `dnf upgrade ./*.rpm` and `dnf install`
#   DEB (apt, each cached Debian-family image):
#     D1  Replaces/Breaks/Provides only, no transitional package
#     D2  transitional omnibridge/omnibridge-gui 1.1.0, as shipped
#
# What matters is the argument the OLD package's scriptlet sees. On Fedora 44
# omnibridge 1.0.0's %preun is `systemd-update-helper remove-user-units
# omnibridged.service` when $1 = 0 (erase), which disables and stops the unit
# for every logged-in user; $1 = 1 (upgrade) does nothing.
set -uo pipefail
need() { command -v "$1" >/dev/null 2>&1 || { echo "PRECONDITION: $1 missing"; exit 3; }; }
need podman; need rpmbuild; need createrepo_c
FEDORA=registry.fedoraproject.org/fedora:44
DEB_IMAGES=(docker.io/library/ubuntu:24.04 docker.io/library/ubuntu:26.04)
W="$(mktemp -d /tmp/w7-transition.XXXXXX)"; trap 'rm -rf "$W"' EXIT
echo "rpm: $(rpm --version); $(rpm -q systemd-rpm-macros 2>/dev/null)"
echo "--- what %systemd_user_preun expands to on this host:"
rpm --eval '%systemd_user_preun omnibridged.service' | sed '/^\s*$/d; s/^/    /'
echo "--- and what remove-user-units does:"
sed -n '/remove-user-units)/,/;;/p' /usr/lib/systemd/systemd-update-helper | sed 's/^/    /'

spec() { # name version extra-preamble extra-sections
cat <<EOF
Name: $1
Version: $2
Release: 1
Summary: W7 probe
License: none
BuildArch: noarch
$3
%description
probe
$4
%preun
echo "W7PROBE $1-$2 preun arg=\$1"
EOF
}
build() { rpmbuild --define "_topdir $W/$1" -bb "$2" >/dev/null 2>&1 || { echo "BUILD FAILED: $2"; exit 3; }; }
simple_files='%install
mkdir -p %{buildroot}/usr/share/w7probe; echo x > %{buildroot}/usr/share/w7probe/%{name}
%files
/usr/share/w7probe/%{name}'

# --- R1..R3 ------------------------------------------------------------------
spec omnibridge 1.0.0 "" "$simple_files" > "$W/old.spec"; build old "$W/old.spec"
spec pliwee 1.1.0 $'Obsoletes: omnibridge < 1.1.0\nProvides: omnibridge = %{version}-%{release}' "$simple_files" > "$W/r1.spec"; build r1 "$W/r1.spec"
spec pliwee 1.1.0 "" "$simple_files" > "$W/r2p.spec"; build r2 "$W/r2p.spec"
spec omnibridge 1.1.0 'Requires: pliwee = %{version}-%{release}' "$simple_files" > "$W/r2o.spec"; build r2 "$W/r2o.spec"
spec pliwee 1.1.0 'Obsoletes: omnibridge < 1.1.0' "$simple_files" > "$W/r3p.spec"; build r3 "$W/r3p.spec"
cp "$W/r2o.spec" "$W/r3o.spec"; build r3 "$W/r3o.spec"
for s in r1 r2 r3; do mkdir -p "$W/repo-$s"; cp "$W/$s"/RPMS/noarch/*.rpm "$W/repo-$s/"; createrepo_c -q "$W/repo-$s"; done
mkdir -p "$W/oldrpm"; cp "$W/old/RPMS/noarch/"*.rpm "$W/oldrpm/"

# --- RF: the shipped shape -----------------------------------------------------
cat > "$W/rf-old.spec" <<'EOF'
Name: omnibridge
Version: 1.0.0
Release: 1
Summary: probe
License: none
BuildArch: noarch
%description
p
%package gui
Summary: gui
Requires: omnibridge = 1.0.0-1
%description gui
g
%install
mkdir -p %{buildroot}/usr/lib/systemd/user %{buildroot}/usr/lib/firewalld/services %{buildroot}/usr/bin
echo old-unit > %{buildroot}/usr/lib/systemd/user/omnibridged.service
echo fw > %{buildroot}/usr/lib/firewalld/services/omnibridge.xml
echo bin > %{buildroot}/usr/bin/omnibridged; echo gui > %{buildroot}/usr/bin/omnibridge-gui
%files
/usr/lib/systemd/user/omnibridged.service
/usr/lib/firewalld/services/omnibridge.xml
/usr/bin/omnibridged
%files gui
/usr/bin/omnibridge-gui
%preun
echo "W7PROBE omnibridge-1.0.0 preun arg=$1"
%preun gui
echo "W7PROBE omnibridge-gui-1.0.0 preun arg=$1"
EOF
cat > "$W/rf-new.spec" <<'EOF'
Name: pliwee
Version: 1.1.0
Release: 1
Summary: probe
License: none
BuildArch: noarch
%description
p
%package -n omnibridge
Summary: transitional
Requires: pliwee = %{version}-%{release}
%description -n omnibridge
t
%package gui
Summary: gui
Requires: pliwee = %{version}-%{release}
Obsoletes: omnibridge-gui < 1.1.0
Provides: omnibridge-gui = %{version}-%{release}
%description gui
g
%install
mkdir -p %{buildroot}/usr/lib/systemd/user %{buildroot}/usr/lib/firewalld/services %{buildroot}/usr/bin
echo new-unit > %{buildroot}/usr/lib/systemd/user/pliweed.service
ln -s pliweed.service %{buildroot}/usr/lib/systemd/user/omnibridged.service
echo fw > %{buildroot}/usr/lib/firewalld/services/omnibridge.xml
echo fw > %{buildroot}/usr/lib/firewalld/services/pliwee.xml
echo bin > %{buildroot}/usr/bin/pliweed; echo gui > %{buildroot}/usr/bin/pliwee-gui
%files
/usr/lib/systemd/user/pliweed.service
/usr/lib/systemd/user/omnibridged.service
/usr/lib/firewalld/services/omnibridge.xml
/usr/lib/firewalld/services/pliwee.xml
/usr/bin/pliweed
%files -n omnibridge
%files gui
/usr/bin/pliwee-gui
EOF
build rf "$W/rf-old.spec"; build rf "$W/rf-new.spec"
mkdir -p "$W/rf-oldpkgs" "$W/rf-repo"
cp "$W"/rf/RPMS/noarch/omnibridge-1.0.0-1.noarch.rpm "$W"/rf/RPMS/noarch/omnibridge-gui-1.0.0-1.noarch.rpm "$W/rf-oldpkgs/"
cp "$W"/rf/RPMS/noarch/pliwee-*.rpm "$W"/rf/RPMS/noarch/omnibridge-1.1.0-1.noarch.rpm "$W/rf-repo/"
createrepo_c -q "$W/rf-repo"

in_fedora() { timeout 600 podman run --rm --network=none -v "$W:/w:ro,z" "$FEDORA" bash -c "$1" 2>&1; }
repo() { printf "printf '[probe]\\\\nname=probe\\\\nbaseurl=file:///w/%s\\\\ngpgcheck=0\\\\n' > /etc/yum.repos.d/probe.repo;" "$1"; }
filt() { grep -E 'W7PROBE|^-- |^omnibridge|^pliwee|->|rror|Nothing to do|available, but not installed|^clean$|^old-unit$|^missing|^S\.|^\.\.' | sed 's/^/    /'; }

for s in r1 r2 r3; do
    echo; echo "=== $s: dnf upgrade from omnibridge-1.0.0"
    in_fedora "$(repo repo-$s) rpm -i /w/oldrpm/*.rpm; dnf -y -q --disablerepo='*' --enablerepo=probe upgrade; echo '-- installed after:'; rpm -qa 'omnibridge*' 'pliwee*' | sort" | filt
done
echo; echo "=== RF: the shipped shape — dnf upgrade, then again (idempotence), then rollback to 1.0.0"
in_fedora "$(repo rf-repo) rpm -i /w/rf-oldpkgs/*.rpm; echo '-- installed before:'; rpm -qa 'omnibridge*' 'pliwee*' | sort
dnf -y -q --disablerepo='*' --enablerepo=probe upgrade
echo '-- installed after:'; rpm -qa 'omnibridge*' 'pliwee*' | sort
echo '-- omnibridged.service:'; ls -l /usr/lib/systemd/user/omnibridged.service | sed 's/.*omnibridged/omnibridged/'
echo '-- firewalld services:'; ls /usr/lib/firewalld/services/
echo '-- rpm -V pliwee:'; rpm -V pliwee && echo clean
echo '-- second upgrade:'; dnf -y --disablerepo='*' --enablerepo=probe upgrade 2>&1 | tail -1
echo '-- rollback: rpm -e omnibridge pliwee-gui pliwee; rpm -i the 1.0.0 set:'
rpm -e omnibridge pliwee-gui pliwee && rpm -i /w/rf-oldpkgs/*.rpm && rpm -qa 'omnibridge*' 'pliwee*' | sort
echo '-- omnibridged.service after rollback:'; cat /usr/lib/systemd/user/omnibridged.service" | filt
for mode in upgrade install; do
    echo; echo "=== RL: dnf $mode with the new set as local files"
    in_fedora "rpm -i /w/rf-oldpkgs/*.rpm; dnf -y --disablerepo='*' $mode /w/rf-repo/*.rpm 2>&1 | grep -E 'W7PROBE|available, but not installed|rror'; echo '-- installed after:'; rpm -qa 'omnibridge*' 'pliwee*' | sort; echo \"-- omnibridged.service -> \$(readlink /usr/lib/systemd/user/omnibridged.service)\"" | filt
done

# --- DEB -------------------------------------------------------------------------
cat > "$W/deb-probe.sh" <<'SH'
set -eu
mk() { d=/tmp/b/$1-$2; mkdir -p $d/DEBIAN $d/usr/share/w7probe
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: p <p@p>\nDescription: probe\n%b' "$1" "$2" "$3" > $d/DEBIAN/control
  echo "$1-$2" > $d/usr/share/w7probe/$1
  printf '#!/bin/sh\necho "W7PROBE %s-%s postrm arg=$1"\n' "$1" "$2" > $d/DEBIAN/postrm; chmod 755 $d/DEBIAN/postrm
  dpkg-deb -b -Zgzip $d /tmp/b/$4 >/dev/null; }
index() { r=$1; shift; mkdir -p /repo/$r; : > /repo/$r/Packages
  for f in "$@"; do cp $f /repo/$r/; b=$(basename $f)
    { dpkg-deb -f $f; printf 'Filename: ./%s\nSize: %s\nSHA256: %s\n\n' $b $(stat -c%s $f) $(sha256sum $f | cut -d' ' -f1); } >> /repo/$r/Packages; done; }
mkdir -p /tmp/b
mk omnibridge 1.0.0-1 '' old-core.deb
mk omnibridge-gui 1.0.0-1 'Depends: omnibridge (= 1.0.0-1)\n' old-gui.deb
mk pliwee 1.1.0-1 'Replaces: omnibridge (<< 1.1.0~)\nBreaks: omnibridge (<< 1.1.0~)\nProvides: omnibridge (= 1.1.0-1)\n' d1-core.deb
mk pliwee-gui 1.1.0-1 'Depends: pliwee (= 1.1.0-1)\nReplaces: omnibridge-gui (<< 1.1.0~)\nBreaks: omnibridge-gui (<< 1.1.0~)\nProvides: omnibridge-gui (= 1.1.0-1)\n' d1-gui.deb
rm -rf /tmp/b/pliwee-1.1.0-1 /tmp/b/pliwee-gui-1.1.0-1
mk pliwee 1.1.0-1 'Replaces: omnibridge (<< 1.1.0~)\nBreaks: omnibridge (<< 1.1.0~)\n' d2-core.deb
mk pliwee-gui 1.1.0-1 'Depends: pliwee (= 1.1.0-1)\nReplaces: omnibridge-gui (<< 1.1.0~)\nBreaks: omnibridge-gui (<< 1.1.0~)\n' d2-gui.deb
mk omnibridge 1.1.0-1 'Depends: pliwee (>= 1.1.0-1)\nSection: oldlibs\n' d2-trans.deb
mk omnibridge-gui 1.1.0-1 'Depends: pliwee-gui (>= 1.1.0-1)\nSection: oldlibs\n' d2-trans-gui.deb
index d1 /tmp/b/d1-core.deb /tmp/b/d1-gui.deb
index d2 /tmp/b/d2-core.deb /tmp/b/d2-gui.deb /tmp/b/d2-trans.deb /tmp/b/d2-trans-gui.deb
rm -f /etc/apt/sources.list.d/* /etc/apt/sources.list
state() { dpkg-query -W -f='${Package} ${Version} ${db:Status-Abbrev}\n' 'omnibridge*' 'pliwee*' 2>/dev/null | sort | sed 's/^/-- /'; }
run() { echo "--- $1 / $2 $3"
  dpkg --purge pliwee-gui pliwee omnibridge-gui omnibridge >/dev/null 2>&1 || true
  dpkg -i /tmp/b/old-core.deb /tmp/b/old-gui.deb >/dev/null
  echo "deb [trusted=yes] file:/repo/$1 ./" > /etc/apt/sources.list.d/p.list; apt-get -qq update >/dev/null 2>&1
  $2 -y $3 2>&1 | grep -E 'W7PROBE|kept back|upgraded,|Upgrading:|Installing:|Not upgrading' || true; state; }
run d1 apt upgrade; run d2 apt upgrade; run d2 apt-get upgrade; run d2 apt-get dist-upgrade
echo "--- d2: apt upgrade a second time"; apt -y upgrade 2>&1 | grep -E 'upgraded,|Upgrading:|Installing:|Nothing|Summary' || echo '-- (apt printed no upgrade summary)'
SH
for img in "${DEB_IMAGES[@]}"; do
    echo; echo "=== DEB on $img ($(podman image inspect --format '{{.Id}}' "$img" 2>/dev/null | cut -c1-12))"
    timeout 600 podman run --rm --network=none -v "$W:/w:ro,z" "$img" bash /w/deb-probe.sh 2>&1 \
        | grep -E 'W7PROBE|^---|^-- |kept back|upgraded,|Upgrading:|Installing:|Not upgrading|rror' | sed 's/^/    /'
done
