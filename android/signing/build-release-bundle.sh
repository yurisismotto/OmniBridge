#!/usr/bin/env bash
# Builds the production OmniBridge release bundle, signed with the UPLOAD key,
# and verifies it (ADR-0019). Run it in your own terminal: it asks for the
# upload keystore password with hidden input and hands it to exactly one
# Gradle run through the environment. Nothing is written to disk but the
# bundle.
#
#   JAVA_HOME=/path/to/jdk-21 ANDROID_HOME=~/Android/Sdk \
#   BUNDLETOOL=/path/to/bundletool-all-1.18.3.jar \
#       android/signing/build-release-bundle.sh
#
# OMNIBRIDGE_UPLOAD_KEYSTORE overrides the keystore path (default: where
# provision-signing-keys.sh installed it).

set -euo pipefail
umask 077

here=$(cd "$(dirname "$0")" && pwd)
android=$(cd "$here/.." && pwd)
keystore="${OMNIBRIDGE_UPLOAD_KEYSTORE:-${XDG_DATA_HOME:-$HOME/.local/share}/omnibridge-android-signing/upload.p12}"
aab="$android/app/build/outputs/bundle/release/app-release.aab"

die() { printf '\nSTOP: %s\n' "$*" >&2; exit 1; }

: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+ (JDK 21 is the verified one)}"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
[[ -f "${BUNDLETOOL:-}" ]] || die "set BUNDLETOOL to bundletool-all-*.jar — the bundle is not accepted unverified"
[[ -f "$keystore" ]] || die "upload keystore not found at $keystore"
[[ "$(stat -c %a "$keystore")" == 600 ]] || die "$keystore must be mode 600 (is $(stat -c %a "$keystore"))"
[[ -z "$(git -C "$android" status --porcelain)" ]] \
    || die "the working tree has uncommitted changes; a release is built from a commit"
commit=$(git -C "$android" rev-parse HEAD)

read -r -s -p "Upload keystore password (OmniBridge Android — upload keystore): " pw; echo
[[ -n "$pw" ]] || die "empty password"

# --no-daemon: no Gradle process outlives this run holding the password in its
# environment. `clean` so nothing from an earlier unsigned or debug run is
# mistaken for this bundle.
( cd "$android" && \
  OMNIBRIDGE_UPLOAD_KEYSTORE="$keystore" OMNIBRIDGE_UPLOAD_KEYSTORE_PASSWORD="$pw" \
  ./gradlew --no-daemon --max-workers=2 clean :app:bundleRelease )

# The password must not have found its way into the bundle, in any entry.
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
unzip -p "$aab" > "$tmp"
if grep -aqF -- "$pw" "$tmp" || grep -aqF -- "$pw" "$aab"; then
    die "the keystore password appears inside the bundle — do not upload it"
fi
unset pw
rm -f "$tmp"

"$here/verify-release-bundle.sh" "$aab"
echo "  commit   $commit"
