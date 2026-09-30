#!/usr/bin/env bash
# Pliwee — Android signing key provisioning (ADR-0019, ADR-0020 §D3).
#
# ONE resumable procedure. Run it in your own terminal — never through an
# assistant's shell — because it prints passwords once, for you alone.
#
#   android/signing/provision-signing-keys.sh --media-a PATH --media-b PATH
#   android/signing/provision-signing-keys.sh --status
#
# What it does, in stages. Each stage is recorded; re-running the same command
# resumes at the first stage not yet done.
#
#   1 generate   two distinct RSA-4096 keys in two PKCS#12 keystores —
#                the app signing key and the upload key — and three random
#                passwords (one per keystore, one for the backup), all in a
#                private directory on tmpfs ($XDG_RUNTIME_DIR)
#   2 show       prints the three passwords ONCE, waits for you to save them
#                in your password manager, then clears the screen
#   3 backup     writes one encrypted bundle (both keystores, gpg AES-256,
#                backup password) to each of two offline media, then STOPS
#                and asks you to eject and re-insert both
#   4 verify     reads each bundle back from the re-mounted media, decrypts it
#                with the passwords as you paste them from your password
#                manager, proves each private key signs, and compares every
#                byte with what was generated
#   5 install    puts the UPLOAD keystore (only) in
#                ~/.local/share/pliwee-android-signing/, with the public
#                certificates; the app signing key stays offline
#   6 destroy    shreds the tmpfs directory and records the PUBLIC result in
#                ~/.local/state/pliwee-android-signing/PROVISIONED
#
# It never writes a private key or a password inside the repository, never
# sends anything anywhere, and refuses to run again once provisioning is
# complete: a second app signing key would be a second app. That refusal is
# per applicationId (ADR-0020 §D3): one signing identity per product.
#
# The retired OmniBridge identity (ADR-0019) is not touched. Its record, its
# installed upload keystore and its backup directory on the media live under
# `omnibridge-android-signing` names; every path here is derived from the
# product identity below, and a check refuses any that is an OmniBridge path.
# Nothing here reads, overwrites or removes them.
#
# Nothing here is uploaded to Play. Supplying the app signing key to Play App
# Signing (PEPK, with Play's per-app encryption key) is a later, separate step.

set -euo pipefail
umask 077

readonly VERSION=1

# ------------------------------------------------------- product identity --
# Data, not logic (ADR-0020 §D3). These are the only lines that name a
# product; the procedure below is the one ADR-0019 approved, unchanged.
readonly PRODUCT="Pliwee"
readonly SLUG=pliwee
readonly PACKAGE=io.github.yurisismotto.pliwee
readonly APP_ALIAS=$SLUG-app-signing
readonly UPLOAD_ALIAS=$SLUG-upload
readonly APP_DNAME="CN=$PRODUCT, OU=Android App Signing"
readonly UPLOAD_DNAME="CN=$PRODUCT, OU=Android Upload"
# The retired identity. Only ever compared against, never opened.
readonly RETIRED_SLUG=omnibridge

# 30 years. Play requires the app signing certificate to be valid until at
# least 2033-10-22; an app signing key cannot be replaced for older Android
# releases, so it is made to outlive the project.
readonly VALIDITY_DAYS=10957
readonly BUNDLE=$SLUG-android-signing-v${VERSION}.tar.gpg
readonly MEDIA_DIR=$SLUG-android-signing

# The self-test (android/signing/tests/provision-selftest.sh) confines every
# path under one scratch root and accepts plain directories as "media". It
# exists to prove this procedure before it is run for real; it cannot touch a
# real state directory, because every path moves under the root. Under the
# root the layout mirrors the real one (runtime/, state/, share/, each holding
# a per-product directory), so the self-test can place a retired identity
# beside this one and prove it is left alone.
SELFTEST_ROOT="${PLIWEE_SIGNING_SELFTEST_ROOT:-}"
if [[ -n "$SELFTEST_ROOT" ]]; then
    WORK="$SELFTEST_ROOT/runtime/$SLUG-android-signing"
    STATE_DIR="$SELFTEST_ROOT/state/$SLUG-android-signing"
    INSTALL_DIR="$SELFTEST_ROOT/share/$SLUG-android-signing"
else
    : "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set — this needs a per-user tmpfs}"
    WORK="$XDG_RUNTIME_DIR/$SLUG-android-signing"
    STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$SLUG-android-signing"
    INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$SLUG-android-signing"
fi
readonly WORK STATE_DIR INSTALL_DIR
readonly RECORD="$STATE_DIR/PROVISIONED"

die() { printf '\n\033[1;31mSTOP:\033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# The retired identity's paths are never ours. A check rather than a belief:
# a product identity edited to the retired slug stops here, before anything —
# even --status — looks at a path.
[[ "$SLUG" != "$RETIRED_SLUG" ]] || die "the product identity is the retired $RETIRED_SLUG identity"
for p in "$WORK" "$STATE_DIR" "$INSTALL_DIR" "$MEDIA_DIR" "$BUNDLE"; do
    [[ "$p" != *"$RETIRED_SLUG-android-signing"* ]] \
        || die "refusing a path of the retired $RETIRED_SLUG signing identity: $p"
done

stage_done() { [[ -f "$WORK/stage.$1" ]]; }
mark() { : > "$WORK/stage.$1"; }

usage() {
    sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

# ---------------------------------------------------------------- arguments --
MEDIA_A="" MEDIA_B="" STATUS=0
while (($#)); do
    case "$1" in
        --media-a) MEDIA_A="${2:?}"; shift 2 ;;
        --media-b) MEDIA_B="${2:?}"; shift 2 ;;
        --status) STATUS=1; shift ;;
        -h|--help) usage ;;
        *) die "unknown argument: $1" ;;
    esac
done

if ((STATUS)); then
    if [[ -f "$RECORD" ]]; then cat "$RECORD"; exit 0; fi
    if [[ -d "$WORK" ]]; then
        echo "IN PROGRESS — completed stages:"
        ls "$WORK" | sed -n 's/^stage\./  /p'
        exit 0
    fi
    echo "NOT PROVISIONED"; exit 0
fi

# ---------------------------------------------------------------- preflight --
if [[ -f "$RECORD" ]]; then
    cat "$RECORD"
    die "$PRODUCT Android signing keys are already provisioned (record above). This script
      never makes a second app signing key. Restore from the offline backup instead."
fi

KEYTOOL="${JAVA_HOME:+$JAVA_HOME/bin/}keytool"
command -v "$KEYTOOL" >/dev/null || die "keytool not found (set JAVA_HOME to a JDK 17+)"
for tool in gpg gpgconf openssl tar sha256sum shred findmnt; do
    command -v "$tool" >/dev/null || die "required tool missing: $tool"
done
java_major=$("$KEYTOOL" -J-version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
[[ -n "$java_major" && "$java_major" -ge 17 ]] || die "keytool must be from JDK 17 or newer (found: ${java_major:-unknown})"

# The working directory must be on tmpfs: it holds private keys and passwords
# until stage 6 destroys it. Checked, not assumed.
mkdir -p "$(dirname "$WORK")"
if [[ -z "$SELFTEST_ROOT" ]]; then
    fstype=$(findmnt -no FSTYPE --target "$(dirname "$WORK")")
    [[ "$fstype" == tmpfs ]] || die "$(dirname "$WORK") is $fstype, not tmpfs"
fi

# The repository must not be where anything is written. Every path above is
# outside it; this makes that a check rather than a belief.
repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$repo_root" ]]; then
    for p in "$WORK" "$STATE_DIR" "$INSTALL_DIR"; do
        [[ "$p/" != "$repo_root/"* ]] || die "refusing to write inside the repository: $p"
    done
fi

# ------------------------------------------------------------------- media ---
# Media are remembered from the first run, so a resume needs no arguments
# unless a mount path changed.
if [[ -d "$WORK" ]]; then
    [[ -n "$MEDIA_A" ]] || MEDIA_A=$(cat "$WORK/media-a" 2>/dev/null || true)
    [[ -n "$MEDIA_B" ]] || MEDIA_B=$(cat "$WORK/media-b" 2>/dev/null || true)
fi
[[ -n "$MEDIA_A" && -n "$MEDIA_B" ]] || die "give both offline media: --media-a PATH --media-b PATH"
MEDIA_A=$(realpath -e "$MEDIA_A") || die "media A not found"
MEDIA_B=$(realpath -e "$MEDIA_B") || die "media B not found"

check_media() {
    local m=$1 label=$2
    [[ -d "$m" && -w "$m" ]] || die "media $label ($m) is not a writable directory"
    if [[ -n "$repo_root" && "$m/" == "$repo_root/"* ]]; then
        die "media $label is inside the repository"
    fi
    if [[ -z "$SELFTEST_ROOT" ]]; then
        mountpoint -q "$m" || die "media $label ($m) is not a mount point — plug in and mount the drive"
        [[ "$(stat -c %d "$m")" != "$(stat -c %d "$HOME")" ]] || die "media $label is on the same filesystem as \$HOME"
    fi
}
check_media "$MEDIA_A" A
check_media "$MEDIA_B" B
[[ "$MEDIA_A" != "$MEDIA_B" ]] || die "media A and B are the same path"
if [[ -z "$SELFTEST_ROOT" ]]; then
    [[ "$(stat -c %d "$MEDIA_A")" != "$(stat -c %d "$MEDIA_B")" ]] || die "media A and B are the same device — use two separate drives"
fi

# The mount's identity (mount id from /proc/self/mountinfo). Stage 4 insists it
# changed since stage 3, which is what makes "read back from the media" true
# rather than "read back from the page cache".
mount_id() {
    if [[ -n "$SELFTEST_ROOT" ]]; then cat "$1/.selftest-mount-id" 2>/dev/null || echo 0; return; fi
    local target
    target=$(findmnt -no TARGET --target "$1")
    awk -v t="$target" '$5 == t { print $1 }' /proc/self/mountinfo | tail -1
}

mkdir -p "$WORK"; chmod 700 "$WORK"
printf '%s\n' "$MEDIA_A" > "$WORK/media-a"
printf '%s\n' "$MEDIA_B" > "$WORK/media-b"

# gpg gets a keyring of its own inside $WORK — nothing is added to, or cached
# by, your normal keyring or agent.
export GNUPGHOME="$WORK/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true' EXIT

say "$PRODUCT Android signing provisioning — $( [[ -n "$SELFTEST_ROOT" ]] && echo 'SELF-TEST (throwaway keys)' || echo 'PRODUCTION' )"
note "working directory (tmpfs): $WORK"
note "media A: $MEDIA_A  ($(findmnt -no SOURCE --target "$MEDIA_A" 2>/dev/null || echo '?'))"
note "media B: $MEDIA_B  ($(findmnt -no SOURCE --target "$MEDIA_B" 2>/dev/null || echo '?'))"

newpass() { openssl rand -base64 24 | tr '+/' '-_'; }   # 192 bits

fingerprint() {   # $1 = PEM, $2 = sha256|sha1
    openssl x509 -in "$1" -noout -fingerprint "-$2" | sed 's/^.*=//'
}

# ------------------------------------------------------------ 1 · generate ---
if ! stage_done generate; then
    say "1/6 generate — two distinct RSA-4096 keys"
    for existing in "$MEDIA_A/$MEDIA_DIR" "$MEDIA_B/$MEDIA_DIR"; do
        [[ ! -e "$existing" ]] || die "$existing already exists. It is from an earlier run whose working
      directory is gone (a reboot empties tmpfs). Its keys were never used — nothing is
      uploaded before provisioning completes — so move it aside and run again."
    done
    rm -f "$WORK"/*.p12 "$WORK"/*.pem "$WORK"/pw.*
    newpass > "$WORK/pw.app"; newpass > "$WORK/pw.upload"; newpass > "$WORK/pw.backup"

    KS_PW=$(cat "$WORK/pw.app") "$KEYTOOL" -genkeypair -noprompt \
        -keystore "$WORK/app-signing.p12" -storetype PKCS12 -storepass:env KS_PW \
        -alias "$APP_ALIAS" -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
        -validity "$VALIDITY_DAYS" -dname "$APP_DNAME" 2>/dev/null
    KS_PW=$(cat "$WORK/pw.upload") "$KEYTOOL" -genkeypair -noprompt \
        -keystore "$WORK/upload.p12" -storetype PKCS12 -storepass:env KS_PW \
        -alias "$UPLOAD_ALIAS" -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
        -validity "$VALIDITY_DAYS" -dname "$UPLOAD_DNAME" 2>/dev/null

    KS_PW=$(cat "$WORK/pw.app") "$KEYTOOL" -exportcert -rfc -keystore "$WORK/app-signing.p12" \
        -storepass:env KS_PW -alias "$APP_ALIAS" > "$WORK/app-signing-certificate.pem" 2>/dev/null
    KS_PW=$(cat "$WORK/pw.upload") "$KEYTOOL" -exportcert -rfc -keystore "$WORK/upload.p12" \
        -storepass:env KS_PW -alias "$UPLOAD_ALIAS" > "$WORK/upload-certificate.pem" 2>/dev/null

    app_fp=$(fingerprint "$WORK/app-signing-certificate.pem" sha256)
    up_fp=$(fingerprint "$WORK/upload-certificate.pem" sha256)
    [[ -n "$app_fp" && -n "$up_fp" ]] || die "could not read a certificate fingerprint"
    [[ "$app_fp" != "$up_fp" ]] || die "app signing and upload certificates are identical"
    app_mod=$(openssl x509 -in "$WORK/app-signing-certificate.pem" -noout -modulus)
    up_mod=$(openssl x509 -in "$WORK/upload-certificate.pem" -noout -modulus)
    [[ "$app_mod" != "$up_mod" ]] || die "app signing and upload keys are the same key"

    {
        echo "$PRODUCT Android signing — PUBLIC certificate fingerprints"
        echo "package: $PACKAGE"
        echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo
        echo "app signing key  ($APP_ALIAS, RSA-4096, $APP_DNAME)"
        echo "  SHA-256: $app_fp"
        echo "  SHA-1:   $(fingerprint "$WORK/app-signing-certificate.pem" sha1)"
        echo "  valid:   $(openssl x509 -in "$WORK/app-signing-certificate.pem" -noout -startdate -enddate | tr '\n' ' ')"
        echo
        echo "upload key       ($UPLOAD_ALIAS, RSA-4096, $UPLOAD_DNAME)"
        echo "  SHA-256: $up_fp"
        echo "  SHA-1:   $(fingerprint "$WORK/upload-certificate.pem" sha1)"
        echo "  valid:   $(openssl x509 -in "$WORK/upload-certificate.pem" -noout -startdate -enddate | tr '\n' ' ')"
    } > "$WORK/PUBLIC-FINGERPRINTS.txt"
    sha256sum "$WORK/app-signing.p12" "$WORK/upload.p12" | sed "s#$WORK/##" > "$WORK/keystores.sha256"
    mark generate
fi

# ---------------------------------------------------------------- 2 · show ---
if ! stage_done show; then
    say "2/6 show — save these three passwords in your password manager NOW"
    cat <<EOF

    They are shown this once. Nothing else will ever print them.
    Save each as its own entry, with the label exactly as written.

      $PRODUCT Android — app signing keystore      $(cat "$WORK/pw.app")
      $PRODUCT Android — upload keystore           $(cat "$WORK/pw.upload")
      $PRODUCT Android — signing backup (gpg)      $(cat "$WORK/pw.backup")

    These are new entries. Do not overwrite the retired OmniBridge entries:
    ADR-0020 §D3 keeps them.

    The backup password must NOT be written on the backup media.

EOF
    read -r -p "    Type SAVED when all three are in your password manager: " answer
    [[ "$answer" == SAVED ]] || die "not confirmed — run again to see them again"
    printf '\033[2J\033[3J\033[H'
    mark show
fi

# -------------------------------------------------------------- 3 · backup ---
write_bundle() {   # $1 = media root, $2 = label
    local dest="$1/$MEDIA_DIR"
    mkdir -p "$dest"
    local stagedir="$WORK/bundle"
    rm -rf "$stagedir"; mkdir -p "$stagedir"
    cp "$WORK/app-signing.p12" "$WORK/upload.p12" "$WORK/keystores.sha256" \
       "$WORK/PUBLIC-FINGERPRINTS.txt" "$WORK/app-signing-certificate.pem" \
       "$WORK/upload-certificate.pem" "$stagedir/"
    tar -C "$stagedir" -cf - . | gpg --batch --quiet --yes --no-symkey-cache \
        --pinentry-mode loopback --passphrase-file "$WORK/pw.backup" \
        --symmetric --cipher-algo AES256 --s2k-mode 3 --s2k-digest-algo SHA512 \
        --s2k-count 65011712 --output "$dest/$BUNDLE.partial"
    rm -rf "$stagedir"
    mv "$dest/$BUNDLE.partial" "$dest/$BUNDLE"
    ( cd "$dest" && sha256sum "$BUNDLE" > "$BUNDLE.sha256" )
    cp "$WORK/PUBLIC-FINGERPRINTS.txt" "$WORK/app-signing-certificate.pem" \
       "$WORK/upload-certificate.pem" "$dest/"
    cat > "$dest/RESTORE.txt" <<EOF
$PRODUCT Android signing — offline backup ($PACKAGE)

$BUNDLE holds BOTH keystores (app signing and
upload), encrypted with gpg AES-256. Neither password is on this media.

Restore (into a tmpfs directory, never into a repository):

  sha256sum -c $BUNDLE.sha256
  gpg --decrypt $BUNDLE | tar -xf - -C "\$DIR"
  sha256sum -c "\$DIR/keystores.sha256"

  passphrase:          password manager, "$PRODUCT Android — signing backup (gpg)"
  app-signing.p12:     password manager, "$PRODUCT Android — app signing keystore"
  upload.p12:          password manager, "$PRODUCT Android — upload keystore"

See docs/adr/ADR-0019-android-app-signing.md and its ADR-0020 addendum in the
$PRODUCT repository.
EOF
    sync
    mount_id "$1" > "$WORK/written-mount.$2"
    sha256sum "$dest/$BUNDLE" | cut -d' ' -f1 > "$WORK/bundle.sha256.$2"
}

if ! stage_done backup; then
    say "3/6 backup — one encrypted bundle to each medium"
    write_bundle "$MEDIA_A" A; note "media A written"
    write_bundle "$MEDIA_B" B; note "media B written"
    [[ "$(cat "$WORK/bundle.sha256.A")" != "" ]] || die "no bundle hash recorded for A"
    mark backup
    cat <<EOF

    Both media are written. Now, so that the next step reads the DRIVES and not
    this computer's memory of them:

      1. eject (unmount) both drives, and unplug them;
      2. plug them back in and let them mount;
      3. run this same command again. If a mount path changed, pass the new
         paths with --media-a / --media-b.

EOF
    exit 0
fi

# -------------------------------------------------------------- 4 · verify ---
verify_media() {   # $1 = media root, $2 = label
    local src="$1/$MEDIA_DIR" restore="$WORK/restore.$2"
    [[ -f "$src/$BUNDLE" ]] || die "media $2: $src/$BUNDLE not found"
    local now
    now=$(mount_id "$1")
    [[ "$now" != "$(cat "$WORK/written-mount.$2")" ]] || die "media $2 has not been re-mounted since it was
      written, so reading it back would read this computer's cache. Eject it,
      re-insert it, and run again."
    ( cd "$src" && sha256sum -c --quiet "$BUNDLE.sha256" ) || die "media $2: bundle checksum mismatch"
    [[ "$(sha256sum "$src/$BUNDLE" | cut -d' ' -f1)" == "$(cat "$WORK/bundle.sha256.$2")" ]] \
        || die "media $2: bundle differs from the one written"

    rm -rf "$restore"; mkdir -p "$restore"
    gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback \
        --passphrase-file "$WORK/typed.backup" --decrypt "$src/$BUNDLE" 2>/dev/null \
        | tar -xf - -C "$restore" || die "media $2: could not decrypt with the backup password you pasted"
    ( cd "$restore" && sha256sum -c --quiet keystores.sha256 ) || die "media $2: restored keystores differ"
    cmp -s "$restore/app-signing.p12" "$WORK/app-signing.p12" || die "media $2: app signing keystore differs"
    cmp -s "$restore/upload.p12" "$WORK/upload.p12" || die "media $2: upload keystore differs"

    # The private keys must actually sign, opened with the passwords as pasted.
    # A CSR is signed by the private key; its public key must equal the
    # certificate's, and its signature must verify.
    local ks alias pwfile cert
    for ks in app-signing upload; do
        if [[ $ks == app-signing ]]; then alias=$APP_ALIAS pwfile=$WORK/typed.app
        else alias=$UPLOAD_ALIAS pwfile=$WORK/typed.upload; fi
        cert="$restore/$ks-certificate.pem"
        KS_PW=$(cat "$pwfile") "$KEYTOOL" -certreq -keystore "$restore/$ks.p12" \
            -storepass:env KS_PW -alias "$alias" -file "$restore/$ks.csr" 2>/dev/null \
            || die "media $2: $ks keystore did not open with the password you pasted"
        openssl req -in "$restore/$ks.csr" -noout -verify 2>/dev/null \
            || die "media $2: $ks CSR signature does not verify"
        [[ "$(openssl req -in "$restore/$ks.csr" -noout -pubkey | openssl sha256)" == \
           "$(openssl x509 -in "$cert" -noout -pubkey | openssl sha256)" ]] \
            || die "media $2: $ks private key does not match its certificate"
    done
    find "$restore" -type f -exec shred -u {} +
    rm -rf "$restore"
}

if ! stage_done verify; then
    say "4/6 verify — restore both backups with the passwords from your password manager"
    note "Paste each password from your password manager (input is hidden)."
    for which in backup app upload; do
        case $which in
            backup) label="signing backup (gpg)" ;;
            app)    label="app signing keystore" ;;
            upload) label="upload keystore" ;;
        esac
        read -r -s -p "    $PRODUCT Android — $label: " typed; echo
        printf '%s' "$typed" > "$WORK/typed.$which"
        unset typed
        cmp -s <(tr -d '\n' < "$WORK/pw.$which") "$WORK/typed.$which" \
            || die "the $label password you pasted is not the one generated. Check the
      password-manager entry (it is shown nowhere else) and run again."
    done
    verify_media "$MEDIA_A" A; note "media A: decrypted, byte-identical, both keys sign"
    verify_media "$MEDIA_B" B; note "media B: decrypted, byte-identical, both keys sign"
    mark verify
fi

# ------------------------------------------------------------- 5 · install ---
if ! stage_done install; then
    say "5/6 install — the UPLOAD keystore only"
    mkdir -p "$INSTALL_DIR"; chmod 700 "$INSTALL_DIR"
    cp "$WORK/upload.p12" "$INSTALL_DIR/upload.p12"
    cp "$WORK/upload-certificate.pem" "$WORK/app-signing-certificate.pem" \
       "$WORK/PUBLIC-FINGERPRINTS.txt" "$INSTALL_DIR/"
    chmod 600 "$INSTALL_DIR"/*
    cmp -s "$INSTALL_DIR/upload.p12" "$WORK/upload.p12" || die "installed upload keystore differs"
    [[ ! -e "$INSTALL_DIR/app-signing.p12" ]] || die "app signing keystore must not be installed"
    note "$INSTALL_DIR/upload.p12"
    mark install
fi

# ------------------------------------------------------------- 6 · destroy ---
say "6/6 destroy — shred the tmpfs working copy, keep the PUBLIC record"
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
{
    cat "$WORK/PUBLIC-FINGERPRINTS.txt"
    echo
    echo "backup bundle SHA-256 (media A): $(cat "$WORK/bundle.sha256.A")"
    echo "backup bundle SHA-256 (media B): $(cat "$WORK/bundle.sha256.B")"
    echo "backups restore-verified:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "upload keystore installed at:    $INSTALL_DIR/upload.p12"
    echo "app signing keystore:            OFFLINE ONLY (media A and B)"
} > "$RECORD.partial"
gpgconf --kill gpg-agent >/dev/null 2>&1 || true
find "$WORK" -type f -exec shred -u {} +
rm -rf "$WORK"
[[ ! -e "$WORK" ]] || die "could not remove $WORK"
mv "$RECORD.partial" "$RECORD"
chmod 644 "$RECORD"

cat "$RECORD"
cat <<EOF

    PROVISIONING COMPLETE.

    Now:
      * eject both drives and store them in two different physical places;
      * the app signing key exists only on those drives from here on.

    The record above is public information. Nothing in it is secret.
EOF
