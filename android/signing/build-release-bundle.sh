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
#
#   --install             also install the release build on the one attached
#                         device (adb), for the physical release smoke. The APK
#                         is derived from this bundle by bundletool and signed
#                         with the upload key — the same code Play will serve,
#                         under the upload certificate instead of Play's.
#   --uninstall-existing  with --install: if an OmniBridge signed with a
#                         different key (a debug build) is installed, remove it
#                         first. That deletes its pairings and settings, so it
#                         is never done without this flag.

set -euo pipefail
umask 077

here=$(cd "$(dirname "$0")" && pwd)
android=$(cd "$here/.." && pwd)
keystore="${OMNIBRIDGE_UPLOAD_KEYSTORE:-${XDG_DATA_HOME:-$HOME/.local/share}/omnibridge-android-signing/upload.p12}"
aab="$android/app/build/outputs/bundle/release/app-release.aab"

die() { printf '\nSTOP: %s\n' "$*" >&2; exit 1; }

install=0 uninstall_existing=0
for arg in "$@"; do
    case $arg in
        --install) install=1 ;;
        --uninstall-existing) uninstall_existing=1 ;;
        *) die "unknown argument: $arg" ;;
    esac
done
readonly PACKAGE=io.github.yurisismotto.omnibridge

: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+ (JDK 21 is the verified one)}"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
[[ -f "${BUNDLETOOL:-}" ]] || die "set BUNDLETOOL to bundletool-all-*.jar — the bundle is not accepted unverified"
[[ -f "$keystore" ]] || die "upload keystore not found at $keystore"
[[ "$(stat -c %a "$keystore")" == 600 ]] || die "$keystore must be mode 600 (is $(stat -c %a "$keystore"))"
if ((install)); then
    command -v adb >/dev/null || die "--install needs adb"
    devices=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    [[ -n "$devices" ]] || die "--install: no device attached (adb devices is empty or unauthorised)"
    [[ $(wc -l <<<"$devices") == 1 ]] || die "--install: more than one device attached; attach only the test device"
fi
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
rm -f "$tmp"

"$here/verify-release-bundle.sh" "$aab"
echo "  commit   $commit"

if ((install)); then
    echo
    echo "installing a release build derived from this bundle on $devices"
    work=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omnibridge-install.XXXXXX")
    trap 'rm -rf "$work"; rm -f "$tmp"' EXIT
    # The password reaches bundletool through a file descriptor, never argv.
    "$JAVA_HOME/bin/java" -jar "$BUNDLETOOL" build-apks --mode=universal \
        --bundle="$aab" --output="$work/release.apks" \
        --ks="$keystore" --ks-key-alias=omnibridge-upload \
        --ks-pass=file:<(printf '%s' "$pw") --key-pass=file:<(printf '%s' "$pw")
    unset pw

    # A copy signed with another key cannot be updated in place. The APK is
    # signed v2/v3 only (minSdk 29), which keytool cannot read: apksigner can.
    adb shell pm path "$PACKAGE" > "$work/pm-path" 2>/dev/null || true
    if grep -q '^package:' "$work/pm-path"; then
        apksigner=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
        [[ -x "$apksigner" ]] || die "apksigner not found under $ANDROID_HOME/build-tools"
        adb pull "$(sed -n 's/^package://p' "$work/pm-path" | tr -d '\r' | head -1)" "$work/installed.apk" >/dev/null
        "$apksigner" verify --print-certs "$work/installed.apk" > "$work/installed.cert" 2>/dev/null || true
        installed_cert=$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$work/installed.cert" | head -1)
        [[ -n "$installed_cert" ]] || die "could not read the installed OmniBridge's signing certificate"
        want=$(openssl x509 -in "$here/certs/upload-certificate.pem" -noout -fingerprint -sha256 \
            | sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f')
        if [[ "$installed_cert" != "$want" ]]; then
            if ((uninstall_existing)); then
                echo "removing the installed OmniBridge (signed by $installed_cert); its pairings go with it"
                adb uninstall "$PACKAGE"
            else
                die "the installed OmniBridge is signed by another key ($installed_cert),
      most likely a debug build. Replacing it deletes its pairings and settings.
      Re-run with --install --uninstall-existing to do that."
            fi
        fi
    fi
    "$JAVA_HOME/bin/java" -jar "$BUNDLETOOL" install-apks --apks="$work/release.apks"
    adb shell dumpsys package "$PACKAGE" > "$work/dumpsys"
    grep -E 'versionCode=|versionName=' "$work/dumpsys" | head -2 | sed 's/^ */  installed: /'
fi
unset pw
