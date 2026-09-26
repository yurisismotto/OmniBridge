#!/usr/bin/env bash
# images.sh — the official cloud image each guest is built from: where it comes
# from, how it is checked, where it is cached, and how it reaches the pool.
#
# Sourced by pre-g8-autopilot.sh. The images are the distributions' own:
#
#   fedora44    download.fedoraproject.org, Cloud/x86_64/images, the Generic
#               qcow2. Its CHECKSUM file is clear-signed by the Fedora 44 key;
#               when the host carries that key (a Fedora 44 host does, at
#               /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary) the signature
#               is verified and only the signed text is read.
#   ubuntu2404  cloud-images.ubuntu.com/releases/24.04/release, SHA256SUMS.
#   ubuntu2604  cloud-images.ubuntu.com/releases/26.04/release, SHA256SUMS.
#               SHA256SUMS.gpg is fetched and kept; it is verified only when
#               AP_UBUNTU_KEYRING names a keyring holding the signing key, and
#               the provenance says which.
#   debian13    cloud.debian.org/images/cloud/trixie/latest, the generic
#               image (the cloud kernel lacks desktop drivers), SHA512SUMS.
#
# A digest is ALWAYS required: an image whose digest does not match the
# distribution's list is refused and kept aside, never used. What was and was
# not verified is recorded, not assumed.

# shellcheck disable=SC2034

ap_cache_dir() { printf '%s/pliwee-pre-g8/images' "${XDG_CACHE_HOME:-$HOME/.cache}"; }

# ap_image_catalog DISTRO — sets IMG_DIR_URL IMG_RE IMG_SUMS_RE IMG_ALGO
# IMG_SIG IMG_SIGKEY (the regexes are matched against the directory listing
# for Fedora, whose compose number changes; for the others they are literal
# names).
ap_image_catalog() {
    IMG_SIG=""; IMG_SIGKEY=""
    case "$1" in
        fedora44)
            IMG_DIR_URL="${AP_IMG_URL_fedora44:-https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images}"
            IMG_RE='Fedora-Cloud-Base-Generic-44-[0-9.]+\.x86_64\.qcow2'
            IMG_SUMS_RE='Fedora-Cloud-44-[0-9.]+-x86_64-CHECKSUM'
            IMG_ALGO=sha256; IMG_SIG=clearsigned
            IMG_SIGKEY="${AP_FEDORA_KEY:-/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary}" ;;
        ubuntu2404|ubuntu2604)
            local v; v="$([ "$1" = ubuntu2404 ] && echo 24.04 || echo 26.04)"
            local k="AP_IMG_URL_$1"
            IMG_DIR_URL="${!k:-https://cloud-images.ubuntu.com/releases/$v/release}"
            IMG_RE="ubuntu-$v-server-cloudimg-amd64\\.img"
            IMG_SUMS_RE='SHA256SUMS'
            IMG_ALGO=sha256; IMG_SIG=detached:SHA256SUMS.gpg; IMG_SIGKEY="${AP_UBUNTU_KEYRING:-}" ;;
        debian13)
            IMG_DIR_URL="${AP_IMG_URL_debian13:-https://cloud.debian.org/images/cloud/trixie/latest}"
            IMG_RE='debian-13-generic-amd64\.qcow2'
            IMG_SUMS_RE='SHA512SUMS'
            IMG_ALGO=sha512 ;;
        *) return 1 ;;
    esac
}

ap_fetch() { # URL OUT — resumable, fail-closed; OUT only exists when complete
    curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 -C - -o "$2.partial" "$1" \
        && mv -f "$2.partial" "$2"
}
# ap_resolve_name REGEX LISTING — the one file name the listing offers.
ap_resolve_name() {
    local names n
    names="$(grep -oE "(href=\")?$1\"?" <<<"$2" | sed 's/^href="//; s/"$//' | sort -u)"
    n="$(grep -c . <<<"$names" || true)"
    [ "$n" = 1 ] || return 1
    printf '%s' "$names"
}
# ap_sums_lookup SUMS_TEXT NAME — the digest the list gives NAME, in any of the
# three formats the distributions use: "HEX  NAME", "HEX *NAME" and
# "SHA256 (NAME) = HEX". Exactly one entry, or nothing.
ap_sums_lookup() {
    local text="$1" name="$2" hits
    hits="$(awk -v n="$name" '
        ($2 == n || $2 == "*" n) && $1 ~ /^[0-9a-f]+$/ { print $1; next }
        $2 == "(" n ")" && $3 == "=" && $4 ~ /^[0-9a-f]+$/ { print $4 }' <<<"$text")"
    [ "$(grep -c . <<<"$hits" || true)" = 1 ] || return 1
    printf '%s' "$hits"
}

# ap_image_fetch DISTRO — downloads (or reuses the cached copy of) the image,
# verifies it, and records its provenance in records/image-DISTRO. Sets
# IMG_FILE and IMG_DIGEST.
ap_image_fetch() {
    local d="$1" dir listing name sums_name sums_file sums_text="" signed="" sig_status digest got k tmp
    ap_image_catalog "$d" || ap_stop "no image catalogue entry for $d"
    dir="$(ap_cache_dir)/$d"; mkdir -p "$dir" || ap_stop "cannot create $dir"
    if [[ "$IMG_RE" == *'[0-9.]+'* ]]; then
        listing="$(curl -fsSL --retry 3 --connect-timeout 30 "$IMG_DIR_URL/" 2>/dev/null)" \
            || ap_stop "cannot list $IMG_DIR_URL/ to find the $d image" "Check the network, then resume."
        name="$(ap_resolve_name "$IMG_RE" "$listing")" || ap_stop "$IMG_DIR_URL/ does not offer exactly one image matching $IMG_RE"
        sums_name="$(ap_resolve_name "$IMG_SUMS_RE" "$listing")" || ap_stop "$IMG_DIR_URL/ does not offer exactly one checksum list matching $IMG_SUMS_RE"
    else
        name="${IMG_RE//\\/}"; sums_name="$IMG_SUMS_RE"
    fi
    sums_file="$dir/$sums_name.$(ap_stamp)"
    ap_fetch "$IMG_DIR_URL/$sums_name" "$sums_file" || ap_stop "cannot download $IMG_DIR_URL/$sums_name"
    sig_status="none published"
    case "$IMG_SIG" in
        clearsigned)
            if [ -f "$IMG_SIGKEY" ]; then
                tmp="$(mktemp -d)"
                if gpg --homedir "$tmp" --batch --quiet --import "$IMG_SIGKEY" >/dev/null 2>&1 \
                        && signed="$(gpg --homedir "$tmp" --batch --status-fd 3 --decrypt "$sums_file" 2>/dev/null 3>"$tmp/status")" \
                        && grep -q '^\[GNUPG:\] VALIDSIG ' "$tmp/status"; then
                    sig_status="verified: $(sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p' "$tmp/status" | head -1) ($IMG_SIGKEY)"
                    sums_text="$signed"
                else
                    rm -rf "$tmp"
                    ap_stop "the signature on $sums_name does not verify against $IMG_SIGKEY" \
                        "The list was kept at $sums_file. Nothing was downloaded or used."
                fi
                rm -rf "$tmp"
            else
                sig_status="NOT verified: $IMG_SIGKEY is not on this host"
            fi ;;
        detached:*)
            k="${IMG_SIG#detached:}"
            if ap_fetch "$IMG_DIR_URL/$k" "$sums_file.$k" 2>/dev/null; then
                if [ -n "$IMG_SIGKEY" ] && [ -f "$IMG_SIGKEY" ]; then
                    gpgv --keyring "$IMG_SIGKEY" "$sums_file.$k" "$sums_file" >/dev/null 2>&1 \
                        || ap_stop "$k does not verify $sums_name against $IMG_SIGKEY" "Kept at $sums_file."
                    sig_status="verified: $k with $IMG_SIGKEY"
                else
                    sig_status="NOT verified: $k kept at $sums_file.$k; no keyring given (AP_UBUNTU_KEYRING)"
                fi
            else
                sig_status="NOT verified: $k could not be fetched"
            fi ;;
    esac
    [ -n "$sums_text" ] || sums_text="$(cat "$sums_file")"
    digest="$(ap_sums_lookup "$sums_text" "$name")" || ap_stop "$sums_name does not list $name exactly once"
    IMG_FILE="$dir/$name"
    if [ -f "$IMG_FILE" ]; then
        got="$("${IMG_ALGO}sum" "$IMG_FILE" | awk '{print $1}')"
        if [ "$got" != "$digest" ]; then
            mv "$IMG_FILE" "$IMG_FILE.mismatch.$(ap_stamp)"
            ap_say INFO "the cached $name no longer matches $sums_name; kept aside and downloading again"
        fi
    fi
    if [ ! -f "$IMG_FILE" ]; then
        ap_say RUN "IMAGE-$d — downloading $IMG_DIR_URL/$name"
        ap_fetch "$IMG_DIR_URL/$name" "$IMG_FILE" || ap_stop "the download of $IMG_DIR_URL/$name failed" \
            "A partial file stays at $IMG_FILE.partial and the next run resumes it."
    fi
    got="$("${IMG_ALGO}sum" "$IMG_FILE" | awk '{print $1}')"
    if [ "$got" != "$digest" ]; then
        mv "$IMG_FILE" "$IMG_FILE.mismatch.$(ap_stamp)"
        ap_stop "$name does not match its $IMG_ALGO in $sums_name (got $got)" \
            "It was kept aside as $IMG_FILE.mismatch.*; nothing was used. Resume to download it again."
    fi
    IMG_DIGEST="$got"
    ap_rec_put "image-$d" "distro=$d" "url=$IMG_DIR_URL/$name" "file=$IMG_FILE" "name=$name" \
        "algo=$IMG_ALGO" "digest=$digest" "sha256=$(ap_sha "$IMG_FILE")" "sums_url=$IMG_DIR_URL/$sums_name" \
        "sums_file=$sums_file" "sums_sha256=$(ap_sha "$sums_file")" "signature=$sig_status" \
        "size=$(stat -c %s "$IMG_FILE")" || ap_stop "cannot record the $d image"
    ap_say PASS "IMAGE-$d — $name ($IMG_ALGO verified; signature: $sig_status)"
}

# ------------------------------------------------------------------ pool --
ap_vol_exists() { grep -qxF -- "$1" <<<"$(ap_virsh vol-list "$AP_POOL" 2>/dev/null | awk 'NR > 2 && NF { print $1 }')"; }
ap_vol_path() { ap_virsh vol-path --pool "$AP_POOL" "$1" 2>/dev/null; }
# ap_vol_facts NAME — "capacity allocation mtime backing_path format" from the
# pool's own description of the volume: the identity a later run compares.
ap_vol_facts() {
    local x
    x="$(ap_virsh vol-dumpxml --pool "$AP_POOL" "$1" 2>/dev/null)" || return 1
    [ -n "$x" ] || return 1
    python3 - "$x" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.fromstring(sys.argv[1])
def t(p):
    e = r.find(p)
    return (e.text or "").strip() if e is not None and e.text else "-"
fmt = r.find("target/format")
print(t("capacity"), t("allocation"), t("target/timestamps/mtime"), t("backingStore/path"),
      fmt.get("type") if fmt is not None else "-")
PY
}
# ap_vol_upload NAME FILE — a new raw volume holding exactly FILE's bytes,
# proved by reading it back through libvirt.
ap_vol_upload() {
    local name="$1" file="$2" size back tmp
    size="$(stat -c %s "$file")" || return 1
    ap_virsh vol-create-as --pool "$AP_POOL" --name "$name" --capacity "${size}b" --format raw >/dev/null || return 1
    ap_virsh vol-upload --pool "$AP_POOL" "$name" "$file" >/dev/null || return 1
    ap_virsh pool-refresh "$AP_POOL" >/dev/null 2>&1 || true
    tmp="$(dirname "$file")/.readback.$$"
    ap_virsh vol-download --pool "$AP_POOL" "$name" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
    back="$(ap_sha "$tmp")"; rm -f "$tmp"
    [ -n "$back" ] && [ "$back" = "$(ap_sha "$file")" ]
}

# ap_base_ensure DISTRO — the verified cloud image as a pool volume that is
# only ever a backing file. Sets BASE_VOL.
ap_base_ensure() {
    local d="$1" rec="base-$1" facts
    BASE_VOL="pliwee-g8-base-$(ap_abbr "$d").qcow2"
    if [ "$(ap_rec_get "$rec" state 2>/dev/null)" = ready ]; then
        facts="$(ap_vol_facts "$BASE_VOL")" \
            || ap_stop "the base volume $BASE_VOL recorded for $d is gone from pool $AP_POOL" \
                "Every $d guest is built on it. Run --cleanup-vms to retire the $d guests, then resume to rebuild."
        [ "$facts" = "$(ap_rec_get "$rec" facts)" ] \
            || ap_stop "the base volume $BASE_VOL no longer matches its record" \
                "recorded: $(ap_rec_get "$rec" facts)" "now:      $facts" \
                "It was written after it was verified; nothing built on it is trusted. Refusing to continue."
        return 0
    fi
    if ap_vol_exists "$BASE_VOL"; then
        [ "$(ap_rec_get "$rec" state 2>/dev/null)" = uploading ] \
            || ap_stop "pool $AP_POOL already holds $BASE_VOL, but no record says this autopilot created it" \
                "Refusing to use or replace it. Remove it yourself if it is stale, then resume."
        ap_say INFO "an interrupted upload of $BASE_VOL is discarded and redone"
        ap_virsh vol-delete --pool "$AP_POOL" "$BASE_VOL" >/dev/null || ap_stop "cannot remove the interrupted $BASE_VOL"
    fi
    ap_image_fetch "$d"
    ap_need_pool_space 4 "the $d base image"
    ap_rec_put "$rec" "state=uploading" "volume=$BASE_VOL" "image_sha256=$IMG_DIGEST" "started_utc=$(ap_utc)"
    ap_say RUN "BASE-$d — uploading the verified image into pool $AP_POOL as $BASE_VOL"
    ap_vol_upload "$BASE_VOL" "$IMG_FILE" || ap_stop "uploading $IMG_FILE as $BASE_VOL failed or did not read back identical"
    facts="$(ap_vol_facts "$BASE_VOL")" || ap_stop "cannot describe $BASE_VOL"
    ap_rec_put "$rec" "state=ready" "volume=$BASE_VOL" "path=$(ap_vol_path "$BASE_VOL")" "facts=$facts" \
        "image=$(ap_rec_get "image-$d" name)" "image_url=$(ap_rec_get "image-$d" url)" \
        "image_sha256=$(ap_rec_get "image-$d" sha256)" "uploaded_utc=$(ap_utc)"
    ap_say PASS "BASE-$d — $BASE_VOL reads back byte-identical to the verified image"
}
