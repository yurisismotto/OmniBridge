#!/usr/bin/env bash
# Rehearses android/signing/provision-signing-keys.sh end to end with THROWAWAY
# keys under a scratch root, and proves each refusal rejects the failure it
# exists for. Nothing here touches a real state directory, real media or the
# repository: the script under test moves every path under
# PLIWEE_SIGNING_SELFTEST_ROOT.
#
# ADR-0020 §D3: the retired OmniBridge identity is planted under the same root
# before anything runs — its record, its installed upload keystore and its
# backup directories on both media — and must be byte-identical at the end.
#
#   JAVA_HOME=/path/to/jdk-17+ android/signing/tests/provision-selftest.sh

set -euo pipefail
umask 077

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../provision-signing-keys.sh"
repo=$(git -C "$here" rev-parse --show-toplevel)
root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pliwee-signing-selftest.XXXXXX")
trap 'find "$root" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$root"' EXIT
export PLIWEE_SIGNING_SELFTEST_ROOT=$root

work="$root/runtime/pliwee-android-signing"
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

# ---- the retired OmniBridge identity, planted first -------------------------
# Stand-in bytes at the exact places ADR-0019's provisioning wrote. The script
# must never read, overwrite or remove any of them. Sizes, modes, names and
# SHA-256 are taken now and compared at the end.
legacy_dirs=(state/omnibridge-android-signing share/omnibridge-android-signing
             media-a/omnibridge-android-signing media-b/omnibridge-android-signing)
mkdir -p "${legacy_dirs[@]/#/$root/}"
printf 'OmniBridge Android signing — PUBLIC certificate fingerprints\npackage: io.github.yurisismotto.omnibridge\n' \
    > "$root/state/omnibridge-android-signing/PROVISIONED"
head -c 4096 /dev/urandom > "$root/share/omnibridge-android-signing/upload.p12"
for m in "$A" "$B"; do
    head -c 8192 /dev/urandom > "$m/omnibridge-android-signing/omnibridge-android-signing-v1.tar.gpg"
    printf 'OmniBridge RESTORE stand-in\n' > "$m/omnibridge-android-signing/RESTORE.txt"
done
legacy_manifest() {
    (cd "$root" && find "${legacy_dirs[@]}" -printf '%p %m %s\n' | sort \
        && find "${legacy_dirs[@]}" -type f -exec sha256sum {} + | sort -k2)
}
legacy_before=$(legacy_manifest)
# 4 directories + 6 files listed, then 6 digests: the capture is exact, so an
# empty or partial manifest cannot compare equal to another empty one.
legacy_lines=$(grep -c . <<<"$legacy_before" || true)
if [[ "$legacy_lines" == 16 ]]; then ok "the retired OmniBridge identity is planted (4 dirs, 6 files)"
else bad "planted OmniBridge identity: expected 16 manifest lines, got $legacy_lines"; exit 1; fi

# ---- refusals before anything exists ----------------------------------------
expect_refusal "refuses without media" "give both offline media" -- "$script" </dev/null
expect_refusal "refuses the same medium twice" "same path" -- "$script" --media-a "$A" --media-b "$A" </dev/null
rm -rf "$work"
expect_refusal "refuses media inside the repository" "inside the repository" -- \
    "$script" --media-a "$repo/android" --media-b "$B" </dev/null
rm -rf "$work"
expect_refusal "an unconfirmed show stage stops" "not confirmed" -- run <<<"no"

# ---- stage 1-3 --------------------------------------------------------------
# An OmniBridge record exists (planted above): Pliwee provisioning proceeds.
out=$(run <<<"SAVED" 2>&1) || { bad "stages 1-3 ran"; echo "$out"; exit 1; }
ok "stages 1-3 ran, with an OmniBridge record present"
[[ -f "$A/pliwee-android-signing/pliwee-android-signing-v1.tar.gpg" && \
   -f "$B/pliwee-android-signing/pliwee-android-signing-v1.tar.gpg" ]] \
    && ok "an encrypted bundle is on each medium" || bad "bundles missing"
grep -q "eject (unmount) both drives" <<<"$out" && ok "it stops and asks for a re-mount" || bad "no re-mount stop"
grep -q "$(tr -d '\n' < "$work/pw.upload")" <<<"$out" && ok "passwords were shown in stage 2" || bad "passwords not shown"
grep -q "Pliwee Android — upload keystore" <<<"$out" \
    && ok "password-manager labels name Pliwee, not the retired entries" || bad "password labels do not name Pliwee"

# Passwords must not be recoverable from the media.
leak=0
for pw in pw.app pw.upload pw.backup; do
    p=$(tr -d '\n' < "$work/$pw")
    if grep -rqF -- "$p" "$A" "$B"; then leak=1; fi
done
((leak == 0)) && ok "no password appears anywhere on either medium" || bad "a password is on the media"
if grep -rqa "PRIVATE KEY" "$A" "$B"; then bad "plaintext private key on the media"; else ok "no plaintext private key on the media"; fi

# The bundle is really encrypted: tar cannot read it without gpg.
if tar -tf "$A/pliwee-android-signing/pliwee-android-signing-v1.tar.gpg" >/dev/null 2>&1; then
    bad "bundle is readable as a plain tar"; else ok "bundle is not a plain tar"; fi

# The certificates carry the Pliwee subjects and aliases (ADR-0020 §D3).
app_subject=$(openssl x509 -in "$work/app-signing-certificate.pem" -noout -subject -nameopt RFC2253)
up_subject=$(openssl x509 -in "$work/upload-certificate.pem" -noout -subject -nameopt RFC2253)
# RFC 2253 prints the RDNs in reverse encoding order; either order is the
# same two-RDN name, and nothing else is accepted.
case "$app_subject" in
    "subject=CN=Pliwee,OU=Android App Signing"|"subject=OU=Android App Signing,CN=Pliwee")
        ok "app signing subject is CN=Pliwee, OU=Android App Signing" ;;
    *) bad "app signing subject: $app_subject" ;;
esac
case "$up_subject" in
    "subject=CN=Pliwee,OU=Android Upload"|"subject=OU=Android Upload,CN=Pliwee")
        ok "upload subject is CN=Pliwee, OU=Android Upload" ;;
    *) bad "upload subject: $up_subject" ;;
esac
if KS_PW=$(tr -d '\n' < "$work/pw.upload") "${JAVA_HOME:+$JAVA_HOME/bin/}keytool" -list \
       -keystore "$work/upload.p12" -storepass:env KS_PW -alias pliwee-upload >/dev/null 2>&1 \
   && KS_PW=$(tr -d '\n' < "$work/pw.app") "${JAVA_HOME:+$JAVA_HOME/bin/}keytool" -list \
       -keystore "$work/app-signing.p12" -storepass:env KS_PW -alias pliwee-app-signing >/dev/null 2>&1; then
    ok "aliases are pliwee-upload and pliwee-app-signing"
else bad "keystores do not carry the pliwee-* aliases"; fi

# ---- stage 4 refusals -------------------------------------------------------
expect_refusal "refuses to verify without a re-mount" "has not been re-mounted" -- run < <(typed)
echo 2 > "$A/.selftest-mount-id"; echo 2 > "$B/.selftest-mount-id"
expect_refusal "refuses a mistyped password" "is not the one generated" -- \
    run < <(echo wrong; tr -d '\n' < "$work/pw.app"; echo; tr -d '\n' < "$work/pw.upload"; echo)

# A corrupted bundle must be caught, then restored.
bundleA="$A/pliwee-android-signing/pliwee-android-signing-v1.tar.gpg"
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
share="$root/share/pliwee-android-signing"
[[ -f "$share/upload.p12" ]] && ok "upload keystore installed" || bad "upload keystore not installed"
[[ ! -e "$share/app-signing.p12" ]] && ok "app signing keystore NOT installed" || bad "app signing keystore installed"
record="$root/state/pliwee-android-signing/PROVISIONED"
[[ -f "$record" ]] && ok "public record written" || bad "no record"
grep -q "SHA-256:" "$record" && ok "record carries fingerprints" || bad "record lacks fingerprints"
grep -qx "package: io.github.yurisismotto.pliwee" "$record" \
    && ok "record names package io.github.yurisismotto.pliwee" || bad "record does not name the Pliwee package"
if grep -qi "omnibridge" "$record"; then bad "the Pliwee record mentions omnibridge"; else ok "the Pliwee record names nothing of the retired identity"; fi
app_fp=$(sed -n '/^app signing key/,/^$/s/^  SHA-256: //p' "$record")
up_fp=$(sed -n '/^upload key/,/^$/s/^  SHA-256: //p' "$record")
[[ -n "$app_fp" && -n "$up_fp" && "$app_fp" != "$up_fp" ]] && ok "app signing and upload keys are distinct" || bad "keys not distinct"
[[ "$app_fp_expected" == *"$app_fp" ]] && ok "record fingerprint matches the generated certificate" || bad "fingerprint mismatch"
if grep -qF -- "$(tr -d '\n' < "$root/upload-pass")" "$record"; then bad "a password is in the record"; else ok "no password in the record"; fi
if grep -qa "PRIVATE KEY" "$record"; then bad "private key in the record"; else ok "no private key in the record"; fi

# ---- independent restore, as RESTORE.txt describes --------------------------
grep -q "pliwee-android-signing-v1.tar.gpg" "$A/pliwee-android-signing/RESTORE.txt" \
    && ok "RESTORE.txt names the Pliwee bundle" || bad "RESTORE.txt does not name the Pliwee bundle"
restore="$root/independent"; mkdir -p "$restore"; mkdir -m 700 "$root/gh"
if gpg --batch --quiet --homedir "$root/gh" --pinentry-mode loopback --passphrase-file "$root/backup-pass" \
       --decrypt "$bundleA" 2>/dev/null | tar -xf - -C "$restore" \
   && (cd "$restore" && sha256sum -c --quiet keystores.sha256); then
    ok "RESTORE.txt procedure recovers both keystores"
else bad "independent restore failed"; fi
if KS_PW=$(tr -d '\n' < "$root/upload-pass") "${JAVA_HOME:+$JAVA_HOME/bin/}keytool" -list \
       -keystore "$restore/upload.p12" -storepass:env KS_PW >/dev/null 2>&1; then
    ok "restored upload keystore opens with its password"; else bad "restored upload keystore does not open"; fi
gpgconf --homedir "$root/gh" --kill gpg-agent >/dev/null 2>&1 || true

# ---- never twice ------------------------------------------------------------
# A Pliwee record exists: refused, and the record is left as it was.
record_before=$(sha256sum "$record")
expect_refusal "refuses to provision a second time (a Pliwee record exists)" "already provisioned" -- run </dev/null
[[ "$(sha256sum "$record")" == "$record_before" ]] \
    && ok "the refusal leaves the Pliwee record byte-identical" || bad "the refusal changed the Pliwee record"

# ---- the retired identity is untouched --------------------------------------
legacy_after=$(legacy_manifest)
if [[ "$legacy_after" == "$legacy_before" ]]; then
    ok "the OmniBridge record, upload keystore and both media backups are byte-identical (names, modes, sizes, SHA-256)"
else
    bad "the retired OmniBridge identity changed:"
    diff <(printf '%s\n' "$legacy_before") <(printf '%s\n' "$legacy_after") | sed 's/^/        /'
fi

# ---- the repository holds nothing -------------------------------------------
if git -C "$repo" status --porcelain --ignored | grep -E '\.(p12|jks|keystore|pfx|gpg)$|PROVISIONED' ; then
    bad "signing material appeared in the repository"
else ok "no signing material in the repository working tree"; fi

echo
echo "  $pass passed, $fail failed"
((fail == 0))
