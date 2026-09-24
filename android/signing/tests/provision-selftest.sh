#!/usr/bin/env bash
# Rehearses android/signing/provision-signing-keys.sh end to end with THROWAWAY
# keys under a scratch root, and proves each refusal rejects the failure it
# exists for. Nothing here touches a real state directory, real media or the
# repository: the script under test moves every path under
# OMNIBRIDGE_SIGNING_SELFTEST_ROOT.
#
#   JAVA_HOME=/path/to/jdk-17+ android/signing/tests/provision-selftest.sh

set -euo pipefail
umask 077

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../provision-signing-keys.sh"
repo=$(git -C "$here" rev-parse --show-toplevel)
root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omnibridge-signing-selftest.XXXXXX")
trap 'find "$root" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$root"' EXIT
export OMNIBRIDGE_SIGNING_SELFTEST_ROOT=$root

work="$root/runtime/omnibridge-android-signing"
A="$root/media-a" B="$root/media-b"
mkdir -p "$A" "$B"
echo 1 > "$A/.selftest-mount-id"; echo 1 > "$B/.selftest-mount-id"

pass=0 fail=0
ok()   { echo "  PASS  $*"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail + 1)); }
# expect_refusal NAME PATTERN -- command...   (stdin passes through)
expect_refusal() {
    local name=$1 pattern=$2; shift 3
    local out rc=0
    out=$("$@" 2>&1) || rc=$?
    if ((rc != 0)) && grep -q -- "$pattern" <<<"$out"; then ok "$name"
    else bad "$name (rc=$rc)"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; fi
}
run() { "$script" --media-a "$A" --media-b "$B" "$@"; }
typed() { tr -d '\n' < "$work/pw.backup"; echo; tr -d '\n' < "$work/pw.app"; echo; tr -d '\n' < "$work/pw.upload"; echo; }

echo "provision-signing-keys.sh self-test (throwaway keys, root $root)"

# ---- refusals before anything exists ----------------------------------------
expect_refusal "refuses without media" "give both offline media" -- "$script" </dev/null
expect_refusal "refuses the same medium twice" "same path" -- "$script" --media-a "$A" --media-b "$A" </dev/null
rm -rf "$work"
expect_refusal "refuses media inside the repository" "inside the repository" -- \
    "$script" --media-a "$repo/android" --media-b "$B" </dev/null
rm -rf "$work"
expect_refusal "an unconfirmed show stage stops" "not confirmed" -- run <<<"no"

# ---- stage 1-3 --------------------------------------------------------------
out=$(run <<<"SAVED" 2>&1) || { bad "stages 1-3 ran"; echo "$out"; exit 1; }
ok "stages 1-3 ran"
[[ -f "$A/omnibridge-android-signing/omnibridge-android-signing-v1.tar.gpg" && \
   -f "$B/omnibridge-android-signing/omnibridge-android-signing-v1.tar.gpg" ]] \
    && ok "an encrypted bundle is on each medium" || bad "bundles missing"
grep -q "eject (unmount) both drives" <<<"$out" && ok "it stops and asks for a re-mount" || bad "no re-mount stop"
grep -q "$(tr -d '\n' < "$work/pw.upload")" <<<"$out" && ok "passwords were shown in stage 2" || bad "passwords not shown"

# Passwords must not be recoverable from the media.
leak=0
for pw in pw.app pw.upload pw.backup; do
    p=$(tr -d '\n' < "$work/$pw")
    if grep -rqF -- "$p" "$A" "$B"; then leak=1; fi
done
((leak == 0)) && ok "no password appears anywhere on either medium" || bad "a password is on the media"
if grep -rqa "PRIVATE KEY" "$A" "$B"; then bad "plaintext private key on the media"; else ok "no plaintext private key on the media"; fi

# The bundle is really encrypted: tar cannot read it without gpg.
if tar -tf "$A/omnibridge-android-signing/omnibridge-android-signing-v1.tar.gpg" >/dev/null 2>&1; then
    bad "bundle is readable as a plain tar"; else ok "bundle is not a plain tar"; fi

# ---- stage 4 refusals -------------------------------------------------------
expect_refusal "refuses to verify without a re-mount" "has not been re-mounted" -- run < <(typed)
echo 2 > "$A/.selftest-mount-id"; echo 2 > "$B/.selftest-mount-id"
expect_refusal "refuses a mistyped password" "is not the one generated" -- \
    run < <(echo wrong; tr -d '\n' < "$work/pw.app"; echo; tr -d '\n' < "$work/pw.upload"; echo)

# A corrupted bundle must be caught, then restored.
bundleA="$A/omnibridge-android-signing/omnibridge-android-signing-v1.tar.gpg"
cp "$bundleA" "$root/bundleA.good"
printf 'X' | dd of="$bundleA" bs=1 seek=100 conv=notrunc status=none
expect_refusal "refuses a corrupted bundle" "checksum mismatch" -- run < <(typed)
cp "$root/bundleA.good" "$bundleA"

# Keep what an independent restore needs, before stage 6 destroys it.
cp "$work/pw.backup" "$root/backup-pass"; cp "$work/pw.upload" "$root/upload-pass"
app_fp_expected=$(openssl x509 -in "$work/app-signing-certificate.pem" -noout -fingerprint -sha256)

# ---- stages 4-6 -------------------------------------------------------------
out=$(run < <(typed) 2>&1) || { bad "stages 4-6 ran"; echo "$out" | tail; exit 1; }
ok "stages 4-6 ran"
grep -q "media A: decrypted, byte-identical, both keys sign" <<<"$out" && \
grep -q "media B: decrypted, byte-identical, both keys sign" <<<"$out" \
    && ok "both media restore-verified" || bad "restore verification not reported"
[[ ! -e "$work" ]] && ok "tmpfs working directory destroyed" || bad "working directory remains"
[[ -f "$root/share/upload.p12" ]] && ok "upload keystore installed" || bad "upload keystore not installed"
[[ ! -e "$root/share/app-signing.p12" ]] && ok "app signing keystore NOT installed" || bad "app signing keystore installed"
record="$root/state/PROVISIONED"
[[ -f "$record" ]] && ok "public record written" || bad "no record"
grep -q "SHA-256:" "$record" && ok "record carries fingerprints" || bad "record lacks fingerprints"
app_fp=$(sed -n '/^app signing key/,/^$/s/^  SHA-256: //p' "$record")
up_fp=$(sed -n '/^upload key/,/^$/s/^  SHA-256: //p' "$record")
[[ -n "$app_fp" && -n "$up_fp" && "$app_fp" != "$up_fp" ]] && ok "app signing and upload keys are distinct" || bad "keys not distinct"
[[ "$app_fp_expected" == *"$app_fp" ]] && ok "record fingerprint matches the generated certificate" || bad "fingerprint mismatch"
if grep -qF -- "$(tr -d '\n' < "$root/upload-pass")" "$record"; then bad "a password is in the record"; else ok "no password in the record"; fi
if grep -qa "PRIVATE KEY" "$record"; then bad "private key in the record"; else ok "no private key in the record"; fi

# ---- independent restore, as RESTORE.txt describes --------------------------
restore="$root/independent"; mkdir -p "$restore"; mkdir -m 700 "$root/gh"
if gpg --batch --quiet --homedir "$root/gh" --pinentry-mode loopback --passphrase-file "$root/backup-pass" \
       --decrypt "$bundleA" 2>/dev/null | tar -xf - -C "$restore" \
   && (cd "$restore" && sha256sum -c --quiet keystores.sha256); then
    ok "RESTORE.txt procedure recovers both keystores"
else bad "independent restore failed"; fi
if OB_PW=$(tr -d '\n' < "$root/upload-pass") "${JAVA_HOME:+$JAVA_HOME/bin/}keytool" -list \
       -keystore "$restore/upload.p12" -storepass:env OB_PW >/dev/null 2>&1; then
    ok "restored upload keystore opens with its password"; else bad "restored upload keystore does not open"; fi
gpgconf --homedir "$root/gh" --kill gpg-agent >/dev/null 2>&1 || true

# ---- never twice ------------------------------------------------------------
expect_refusal "refuses to provision a second time" "already provisioned" -- run </dev/null

# ---- the repository holds nothing -------------------------------------------
if git -C "$repo" status --porcelain --ignored | grep -E '\.(p12|jks|keystore|pfx|gpg)$|PROVISIONED' ; then
    bad "signing material appeared in the repository"
else ok "no signing material in the repository working tree"; fi

echo
echo "  $pass passed, $fail failed"
((fail == 0))
