#!/usr/bin/env bash
# Each mutation changes one fact, runs packaging-checks.sh, expects a named FAIL, restores.
set -u
cd "$(git rev-parse --show-toplevel)"
B=$(mktemp -d /tmp/w7-mut.XXXX)
run() { # name file sed-expr expected-fail-substring
  local name="$1" f="$2" expr="$3" want="$4"
  cp -p "$f" "$B/orig"; sum0=$(sha256sum "$f" | cut -d' ' -f1)
  sed -i "$expr" "$f"
  [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$sum0" ] || { echo "MUTATION $name: sed changed nothing — INVALID"; cp -p "$B/orig" "$f"; return; }
  out="$(bash packaging/tests/packaging-checks.sh 2>&1)"; rc=$?
  cp -p "$B/orig" "$f"; [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sum0" ] || { echo "RESTORE FAILED $f"; exit 9; }
  hit="$(grep -F "FAIL  " <<<"$out" | grep -F -- "$want" | head -1)"
  if [ "$rc" -ne 0 ] && [ -n "$hit" ]; then echo "REJECTED  $name (rc=$rc): ${hit#*FAIL  }"; else echo "NOT REJECTED  $name (rc=$rc)"; fi
}
run M1-core-obsoletes packaging/fedora/pliwee.spec 's/^Suggests:       wl-clipboard$/Suggests:       wl-clipboard\nObsoletes:      omnibridge < 1.1.0/' "declares Obsoletes"
run M2-gui-bound packaging/fedora/pliwee.spec 's/^Obsoletes:      omnibridge-gui < 1.1.0$/Obsoletes:      omnibridge-gui < 1.0.1/' "Obsoletes: omnibridge-gui < 1.1.0"
run M3-no-alias-rpm packaging/fedora/pliwee.spec '/^ln -s pliweed.service/d' "alias symlink"
run M4-no-alias-deb packaging/debian/pliwee.links 's/omnibridged/omnibridge/' "pliwee.links"
run M5-legacy-fw-edited packaging/fedora/omnibridge-firewalld.xml 's/<short>OmniBridge</<short>Pliwee</' "must stay as shipped"
run M6-legacy-fw-port packaging/fedora/omnibridge-firewalld.xml 's/port="55432"/port="55433"/' "omnibridge-firewalld.xml declares"
run M7-deb-breaks packaging/debian/control 's/^Breaks: omnibridge (<< 1.1.0~)$/Breaks: omnibridge (<< 1.0.0)/' "Breaks: omnibridge (<< 1.1.0~)"
run M8-deb-provides packaging/debian/control 's/^Breaks: omnibridge (<< 1.1.0~)$/Breaks: omnibridge (<< 1.1.0~)\nProvides: omnibridge/' "Provides: omnibridge; the name belongs to the transitional package"
run M9-deb-no-transitional packaging/debian/control 's/^Package: omnibridge-gui$/Package: omnibridge-gui-old/' "transitional omnibridge-gui"
run M10-unit-runtime packaging/common/pliweed.service 's/^RuntimeDirectory=pliwee$/RuntimeDirectory=omnibridge/' "RuntimeDirectory=pliwee"
run M11-unit-alias-directive packaging/common/pliweed.service 's/^WantedBy=default.target$/WantedBy=default.target\nAlias=omnibridged.service/' "Alias="
run M12-metainfo-replaces desktop/gui/data/io.github.yurisismotto.pliwee.metainfo.xml 's#<id>io.github.yurisismotto.omnibridge</id>#<id>io.github.yurisismotto.other</id>#' "<replace>"
run M13-workspace-version desktop/Cargo.toml '0,/^version = "1.1.0"/s//version = "1.0.0"/' "workspace version"
run M14-transitional-requires packaging/fedora/pliwee.spec '/^%package -n omnibridge$/,/^%description -n omnibridge$/s/^Requires:.*$/Requires:       pliwee/' "transitional omnibridge package is missing"
rm -rf "$B"
echo "final tree check:"; bash packaging/tests/packaging-checks.sh 2>&1 | tail -1
