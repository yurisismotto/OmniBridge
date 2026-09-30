#!/usr/bin/env bash
#
# Builds Pliwee's RPMs in a disposable container, offline.
#
#   ./build-rpm.sh dist
#   ./build-rpm.sh dist --output out/fedora44
#
# `dist` is a directory produced by packaging/release/make-source-bundle.sh.
#
# Why this exists alongside `mock`
# --------------------------------
# `mock` is the better instrument and `packaging/fedora/README.md` still tells
# a Fedora packager to use it: it reproduces koji's buildroot exactly. But it
# needs the `mock` group and a privileged helper, which a GitHub runner does
# not have, so the release pipeline needs a path that works without one.
#
# This is that path, and it is deliberately the same shape as
# `packaging/debian/build-deb.sh` so the two formats are built and reasoned
# about the same way. The three properties that matter are preserved:
#
#   * the buildroot installs **nothing by name** — only what `dnf builddep`
#     derives from the spec — so an under-declared BuildRequires fails the
#     build rather than being covered by whatever the image happens to carry;
#   * the build runs with **`--network=none`**, so a Cargo fetch is impossible
#     rather than merely unnecessary. That is what the vendored bundle is for;
#   * it builds as a **normal user**, never root. `pliwee-core`'s store
#     tests chmod a directory to 0000 and assert the read comes back
#     PermissionDenied; root has CAP_DAC_OVERRIDE and reads it anyway, so a
#     root build would pass a test that proves nothing. `%check` runs the full
#     suite, so this is not a detail.

set -euo pipefail

BUNDLE=""
OUTPUT=""
IMAGE="registry.fedoraproject.org/fedora:44"

die() { printf '\nbuild-rpm: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTPUT="${2:?--output needs a directory}"; shift 2 ;;
        --image)  IMAGE="${2:?--image needs a container image}"; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown argument: $1" ;;
        *) BUNDLE="$1"; shift ;;
    esac
done

[ -n "$BUNDLE" ] || die "pass the bundle directory produced by make-source-bundle.sh"
[ -d "$BUNDLE" ] || die "not a directory: $BUNDLE"
command -v podman >/dev/null || die "podman is required"

ROOT="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
BUNDLE="$(cd -- "$BUNDLE" && pwd)"
OUTPUT="${OUTPUT:-$ROOT/dist-rpm}"
mkdir -p "$OUTPUT"
# Resolved to an absolute path, and that is not tidiness. `podman -v` treats a
# NON-ABSOLUTE source as a named volume rather than a bind mount, so
# `--output out` silently wrote every artifact into a podman volume and left
# the directory empty. The build reported success, the container listed the
# files it had just written, and the host had nothing.
OUTPUT="$(cd -- "$OUTPUT" && pwd)"

SRC_TARBALL="$(find "$BUNDLE" -maxdepth 1 -name 'pliwee-*.tar.gz' ! -name '*vendor*' | head -1)"
VENDOR_TARBALL="$(find "$BUNDLE" -maxdepth 1 -name 'pliwee-*-vendor.tar.xz' | head -1)"
[ -n "$SRC_TARBALL" ] || die "no source tarball in $BUNDLE"
[ -n "$VENDOR_TARBALL" ] || die "no vendor tarball in $BUNDLE"

printf '\n==> %s\n    source %s\n    vendor %s\n' \
    "$IMAGE" "$(basename "$SRC_TARBALL")" "$(basename "$VENDOR_TARBALL")"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pliwee-rpm.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/in"
cp -- "$SRC_TARBALL" "$VENDOR_TARBALL" "$STAGE/in/"
# The spec travels from the checkout rather than out of the tarball, so a
# packaging change can be built before it is committed. The release path
# passes a bundle made with --rev, where the two are the same thing anyway.
cp -- "$ROOT/packaging/fedora/pliwee.spec" "$STAGE/in/"

cat > "$STAGE/prepare.sh" <<'PREPARE'
set -euo pipefail
# --- everything in this script needs the network, and only this script does --
dnf -y install rpm-build rpmlint dnf-plugins-core >/dev/null
dnf -y builddep /in/pliwee.spec >/dev/null
useradd -m builder
mkdir -p /build/{SOURCES,SPECS,RPMS,SRPMS,BUILD,BUILDROOT} /out
cp /in/*.tar.* /build/SOURCES/
cp /in/pliwee.spec /build/SPECS/
chown -R builder /build /out
# Proof the script actually ran. `bash -s` with no stdin exits 0 having done
# nothing, and every failure after that points somewhere else.
id builder
rpmbuild --version
PREPARE

cat > "$STAGE/build.sh" <<'BUILD'
set -euo pipefail
# --- and nothing in this script may touch the network ----------------------
cd /build
rpmbuild --define "_topdir /build" -bs SPECS/pliwee.spec
rpmbuild --define "_topdir /build" -bb SPECS/pliwee.spec
# The artifacts stay inside the container. They are extracted with `podman cp`
# rather than written through a bind mount: under rootless podman the build
# user maps to a subuid with no write access to a host directory, which fails
# as `Permission denied` on the copy after a build that otherwise succeeded.
find /build/RPMS /build/SRPMS -name '*.rpm' -printf '%f\n' | sort
BUILD

CONTAINER="pliwee-rpm-$$"
cleanup() {
    podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
    podman rm -f "pliwee-rpmbuild-$$" >/dev/null 2>&1 || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

# Two stages, because the network has to be available for exactly one of them.
# Installing build dependencies needs it; the build must not have it. Running
# them in one container with --network=none would make dnf fail, and running
# the build with a network would make "offline" a claim rather than a fact.
printf '\n--> Buildroot, derived from the spec and nothing else\n'
# `-i` is load-bearing: without it podman does not attach stdin, `bash -s`
# reads nothing, exits 0, and the commit below captures a pristine image. That
# failed as `unable to find user builder` two steps later, which is a long way
# from the cause.
podman run -i --name "$CONTAINER" \
    -v "$STAGE/in:/in:ro,z" \
    "$IMAGE" bash -s < "$STAGE/prepare.sh"
podman commit "$CONTAINER" "pliwee-rpm-buildroot:$$" >/dev/null
podman rm "$CONTAINER" >/dev/null

printf '\n--> Build, as a normal user, with no network namespace at all\n'
BUILDER="pliwee-rpmbuild-$$"
podman run -i --name "$BUILDER" --network=none --user builder \
    "pliwee-rpm-buildroot:$$" bash -s < "$STAGE/build.sh"

printf '\n--> Extracting\n'
# RPMS/noarch as well: the transitional `omnibridge` package is noarch, and a
# loop that only knew x86_64 would drop it without a word — the one package
# that makes an OmniBridge 1.0.0 install upgrade in place.
for d in /build/RPMS/x86_64 /build/RPMS/noarch /build/SRPMS; do
    podman cp "$BUILDER:$d/." "$OUTPUT/" 2>/dev/null || true
done
podman rm "$BUILDER" >/dev/null
# Exact, by name: pliwee, pliwee-gui, the transitional omnibridge, the SRPM.
produced="$(find "$OUTPUT" -maxdepth 1 -name '*.rpm' | wc -l)"
if [ "$produced" -eq 0 ]; then
    die "the build reported success but no .rpm reached $OUTPUT"
fi
for want in 'pliwee-[0-9]*.x86_64.rpm' 'pliwee-gui-[0-9]*.x86_64.rpm' \
            'omnibridge-[0-9]*.noarch.rpm' 'pliwee-[0-9]*.src.rpm'; do
    n="$(find "$OUTPUT" -maxdepth 1 -name "$want" | wc -l)"
    [ "$n" -eq 1 ] || die "expected exactly one $want in $OUTPUT, found $n"
done
[ "$produced" -eq 4 ] || die "expected exactly 4 .rpm files in $OUTPUT, found $produced"
ls -l "$OUTPUT"/*.rpm

printf '\n--> rpmlint\n'
podman run --rm -v "$OUTPUT:/out:ro,z" "pliwee-rpm-buildroot:$$" \
    bash -c 'rpmlint /out/*.x86_64.rpm /out/*.noarch.rpm 2>&1 | tail -20' | tee "$OUTPUT/rpmlint.txt" || true

podman rmi "pliwee-rpm-buildroot:$$" >/dev/null 2>&1 || true
printf '\nPackages in %s\n' "$OUTPUT"
