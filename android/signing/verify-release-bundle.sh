#!/usr/bin/env bash
# Verifies a Pliwee release bundle before it goes anywhere near Play
# (ADR-0019, PLAY16; ADR-0020 §D3). Every check is exact, and every check fails loudly —
# including when the tool that would perform it is missing.
#
#   android/signing/verify-release-bundle.sh [--expect-cert PEM] APP.aab
#
# Requires: JAVA_HOME (keytool), BUNDLETOOL (path to bundletool-all-*.jar),
# python3, unzip, openssl.
#
# --expect-cert defaults to the committed PUBLIC Pliwee upload certificate,
# android/signing/certs/upload-certificate.pem. It exists so the verifier can
# be tested against a throwaway key; a production run never passes it.
#
# The retired OmniBridge certificates (ADR-0019) are kept, byte-identical, in
# certs/legacy-omnibridge/. They never sign a Pliwee artifact: a bundle signed
# by either is refused, and so is an --expect-cert that names either.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
expect_cert="$here/certs/upload-certificate.pem"
if [[ "${1:-}" == --expect-cert ]]; then expect_cert=$2; shift 2; fi
aab=${1:?usage: verify-release-bundle.sh [--expect-cert PEM] APP.aab}

# The release contract. Changing any of these is a release decision, made
# here on purpose, not discovered afterwards.
readonly PACKAGE=io.github.yurisismotto.pliwee
readonly EXPECT_SUBJECT="CN=Pliwee, OU=Android Upload"
readonly MIN_SDK=29
readonly MIN_TARGET_SDK=36
readonly PERMISSIONS="android.permission.ACCESS_NETWORK_STATE
android.permission.CAMERA
android.permission.CHANGE_NETWORK_STATE
android.permission.CHANGE_WIFI_MULTICAST_STATE
android.permission.FOREGROUND_SERVICE
android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE
android.permission.INTERNET
android.permission.POST_NOTIFICATIONS
io.github.yurisismotto.pliwee.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"

fails=0
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
die()  { printf 'STOP: %s\n' "$*" >&2; exit 2; }

# ---- the tools exist, the input exists --------------------------------------
KEYTOOL="${JAVA_HOME:?JAVA_HOME must name a JDK}/bin/keytool"
[[ -x "$KEYTOOL" ]] || die "keytool not found at $KEYTOOL"
[[ -f "${BUNDLETOOL:-}" ]] || die "BUNDLETOOL must name bundletool-all-*.jar (got '${BUNDLETOOL:-}')"
for t in python3 unzip openssl; do command -v "$t" >/dev/null || die "$t is required"; done
[[ -s "$aab" ]] || die "$aab is missing or empty"
[[ -s "$expect_cert" ]] || die "expected certificate $expect_cert is missing (the Pliwee upload
      certificate is committed there after provisioning — ADR-0019 addendum)"

# The expected certificate is Pliwee's, not a retired one. Checked before any
# verdict, so a verifier pointed at the wrong certificate cannot pass.
want=$(openssl x509 -in "$expect_cert" -noout -fingerprint -sha256 | sed 's/^.*=//')
[[ -n "$want" ]] || die "cannot read a SHA-256 fingerprint from $expect_cert"
for retired in "$here"/certs/legacy-omnibridge/*.pem; do
    [[ -s "$retired" ]] || die "the retired certificates are missing from certs/legacy-omnibridge/"
    [[ "$want" != "$(openssl x509 -in "$retired" -noout -fingerprint -sha256 | sed 's/^.*=//')" ]] \
        || die "$expect_cert is the retired OmniBridge certificate $(basename "$retired"); a Pliwee bundle is never verified against it"
done
subject=$(openssl x509 -in "$expect_cert" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
case "$subject" in
    "CN=Pliwee,OU=Android Upload"|"OU=Android Upload,CN=Pliwee") ;;
    *) die "$expect_cert has subject '$subject', not $EXPECT_SUBJECT" ;;
esac

scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
echo "verifying $aab"

# JDK tools localise their output (this build host prints Portuguese); every
# parse below reads English, so the locale is pinned rather than assumed.
# ---- signature ---------------------------------------------------------------
"$KEYTOOL" -J-Duser.language=en -J-Duser.country=US -printcert -jarfile "$aab" > "$scratch/printcert" 2>&1 || true
signers=$(grep -c '^Signer #' "$scratch/printcert" || true)
[[ "$signers" == 1 ]] && pass "exactly one signer" || fail "signers: expected 1, found ${signers:-0}"
got=$(sed -n 's/^[[:space:]]*SHA256: //p' "$scratch/printcert" | head -1)
[[ -n "$got" && "$got" == "$want" ]] && pass "signed by the expected certificate ($want)" \
    || fail "signing certificate: expected $want, found ${got:-none}"
grep -q 'CN=Android Debug' "$scratch/printcert" && fail "signed with an Android DEBUG certificate" \
    || pass "not a debug certificate"
if [[ -x "$JAVA_HOME/bin/jarsigner" ]]; then
    "$JAVA_HOME/bin/jarsigner" -J-Duser.language=en -J-Duser.country=US -verify "$aab" > "$scratch/jarsigner" 2>&1 || true
    grep -q '^jar verified' "$scratch/jarsigner" && pass "jarsigner verifies every entry" \
        || fail "jarsigner does not verify the bundle"
else
    fail "jarsigner not found — the signature over the entries was not checked"
fi

# ---- manifest ----------------------------------------------------------------
"$JAVA_HOME/bin/java" -jar "$BUNDLETOOL" dump manifest --bundle="$aab" > "$scratch/manifest.xml" 2> "$scratch/bundletool.err" \
    || die "bundletool could not read the bundle manifest"
[[ -s "$scratch/manifest.xml" ]] || die "bundletool produced an empty manifest"
python3 - "$scratch/manifest.xml" "$PACKAGE" "$MIN_SDK" "$MIN_TARGET_SDK" > "$scratch/manifest.checks" <<'PY'
import sys, xml.etree.ElementTree as ET
A = "{http://schemas.android.com/apk/res/android}"
m = ET.parse(sys.argv[1]).getroot()
pkg, min_sdk, min_target = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
sdk = m.find("uses-sdk")
app = m.find("application")
def out(ok, msg): print(("PASS" if ok else "FAIL") + "\t" + msg)
out(m.get("package") == pkg, f"package {m.get('package')} (expected {pkg})")
print("INFO\tversionCode " + str(m.get(A + "versionCode")))
print("INFO\tversionName " + str(m.get(A + "versionName")))
out(sdk is not None and int(sdk.get(A + "minSdkVersion", "0")) == min_sdk,
    f"minSdk {sdk.get(A + 'minSdkVersion') if sdk is not None else None} (expected {min_sdk})")
out(sdk is not None and int(sdk.get(A + "targetSdkVersion", "0")) >= min_target,
    f"targetSdk {sdk.get(A + 'targetSdkVersion') if sdk is not None else None} (expected >= {min_target})")
out(app is not None and app.get(A + "debuggable") not in ("true", "-1"),
    f"debuggable is {app.get(A + 'debuggable') if app is not None else None} (expected absent/false)")
out(app is not None and app.get(A + "allowBackup") == "false", "allowBackup=false")
with open(sys.argv[1] + ".perms", "w") as f:
    for p in sorted(e.get(A + "name") for e in m.findall("uses-permission")):
        f.write(p + "\n")
PY
while IFS=$'\t' read -r verdict msg; do
    case $verdict in PASS) pass "$msg" ;; FAIL) fail "$msg" ;; *) printf '  INFO  %s\n' "$msg" ;; esac
done < "$scratch/manifest.checks"
[[ -s "$scratch/manifest.checks" ]] || fail "no manifest checks ran"
if diff <(printf '%s\n' "$PERMISSIONS") "$scratch/manifest.xml.perms" > "$scratch/perms.diff"; then
    pass "permissions are exactly the expected $(wc -l < "$scratch/manifest.xml.perms")"
else
    fail "unexpected permission set:"; sed 's/^/        /' "$scratch/perms.diff"
fi

# ---- contents ----------------------------------------------------------------
unzip -Z1 "$aab" > "$scratch/entries" || die "cannot list bundle entries"
[[ -s "$scratch/entries" ]] || die "bundle has no entries"
if grep -iE '\.(p12|jks|keystore|pfx|pem|gpg|key)$|key\.properties|local\.properties|keystore\.properties' \
        "$scratch/entries" > "$scratch/secret-names"; then
    fail "signing-like files inside the bundle:"; sed 's/^/        /' "$scratch/secret-names"
else pass "no keystore / key / properties files inside the bundle"; fi
unzip -p "$aab" > "$scratch/all-bytes" 2>/dev/null || die "cannot read bundle entries"
if grep -aE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' "$scratch/all-bytes" > /dev/null; then
    fail "a PEM private key block is inside the bundle"
else pass "no PEM private key block inside the bundle"; fi
grep -qx 'base/dex/classes.dex' "$scratch/entries" && pass "dex present" || fail "no base/dex/classes.dex"
grep -qx 'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map' "$scratch/entries" \
    && pass "R8 mapping carried in bundle metadata (minification ran)" \
    || fail "no R8 mapping in the bundle — was minification disabled?"

# ---- summary -----------------------------------------------------------------
echo
echo "  SHA-256  $(sha256sum "$aab" | cut -d' ' -f1)  $(basename "$aab")"
if ((fails)); then echo "  VERDICT  FAIL ($fails)"; exit 1; fi
echo "  VERDICT  PASS"
