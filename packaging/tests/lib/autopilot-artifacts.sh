#!/usr/bin/env bash
# autopilot-artifacts.sh — the two package sets G7-UP and the lifecycle gates
# measure, and the keyring U1 verifies the old one with.
#
# OmniBridge 1.0.0 — THE PUBLISHED RELEASE, never a rebuild. Downloaded from
#   the GitHub release the README and the GA record name
#   (github.com/yurisismotto/OmniBridge, tag v1.0.0): the linux-x86_64 tarball,
#   which carries every artifact in its signed layout with SHA256SUMS and
#   SHA256SUMS.asc — "this is what verify-release.sh checks" (V1.0.0-GA-RELEASE
#   §8.1) — plus the separately published SHA256SUMS, SHA256SUMS.asc and
#   omnibridge-release-pubkey.asc. The tarball's manifest and signature must be
#   byte-identical to the published ones, the public key must carry the pinned
#   primary AND signing-subkey fingerprints, and verify-release.sh must print
#   VERIFIED over the extracted layout. That layout is OLD_PKGDIR for every
#   distribution (upgrade-gates.sh delivers each one's packages from it).
#   Only the PUBLIC key is ever handled, in a throwaway GNUPGHOME: the
#   operator's own keyrings are not read, and no private key is involved.
#
# Pliwee — built here, from ONE commit, pinned the first time and reused for
#   every gate after, so every distribution's gates measure the same source:
#   make-source-bundle.sh --rev COMMIT, then build-rpm.sh / build-deb.sh in
#   their containers, one at a time, under `taskset -c 0,1` (cargo and rpm size
#   their parallelism from the CPU affinity, so at most two build jobs),
#   nice and idle I/O, and never while a guest is running. Each distribution's
#   four packages are then laid out flat with a SHA256SUMS naming them, which
#   is the shape lifecycle-gates.sh and upgrade-gates.sh read.

# shellcheck disable=SC2034

ap_art() { printf '%s/artifacts' "$AP_STATE"; }
ap_release_url() { printf '%s' "${AP_RELEASE_BASE_URL:-https://github.com/$AP_RELEASE_REPO/releases/download/$AP_RELEASE_TAG}"; }
AP_OLD_TARBALL="omnibridge-1.0.0-linux-x86_64.tar.gz"
AP_OLD_PUBKEY="omnibridge-release-pubkey.asc"

# The files each distribution's 1.0.0 install needs, in the signed layout.
ap_old_expected() {
    case "$1" in
        fedora44) printf '%s\n' fedora44/omnibridge-1.0.0-1.fc44.x86_64.rpm fedora44/omnibridge-gui-1.0.0-1.fc44.x86_64.rpm ;;
        *) printf '%s\n' "$1/omnibridge_1.0.0-1_amd64.deb" "$1/omnibridge-gui_1.0.0-1_amd64.deb" ;;
    esac
}

# ap_keyring_from_pubkey ASC OUT — a keyring holding the release key, after
# checking it is the pinned primary with the pinned signing subkey.
ap_keyring_from_pubkey() {
    local asc="$1" out="$2" gh fprs
    gh="$(mktemp -d)" || return 1
    gpg --homedir "$gh" --batch --quiet --import "$asc" >/dev/null 2>&1 || { rm -rf "$gh"; echo "the public key does not import"; return 1; }
    fprs="$(gpg --homedir "$gh" --batch --with-colons --with-subkey-fingerprints --list-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }')"
    grep -qxF "$AP_RELEASE_FPR" <<<"$fprs" || { rm -rf "$gh"; echo "the published key is not $AP_RELEASE_FPR"; return 1; }
    grep -qxF "$AP_RELEASE_SUBKEY" <<<"$fprs" || { rm -rf "$gh"; echo "the published key has no signing subkey $AP_RELEASE_SUBKEY"; return 1; }
    gpg --homedir "$gh" --batch --export "$AP_RELEASE_FPR" > "$out.partial" 2>/dev/null && [ -s "$out.partial" ] \
        || { rm -rf "$gh" "$out.partial"; echo "the key could not be exported"; return 1; }
    mv -f "$out.partial" "$out"; rm -rf "$gh"
}

# ap_old_set_ensure — OLD_PKGDIR and KEYRING for every distribution. Sets
# OLD_LAYOUT and OLD_KEYRING.
ap_old_set_ensure() {
    local art dl lay tmp sums n f why vout rec=artifacts-old
    art="$(ap_art)/omnibridge-1.0.0"; dl="$art/download"; lay="$art/layout"
    OLD_KEYRING="$(ap_art)/keyring/omnibridge-release.gpg"; OLD_LAYOUT="$lay"
    if [ "$(ap_rec_get "$rec" state 2>/dev/null)" = ready ]; then
        [ "$(ap_sha "$lay/SHA256SUMS")" = "$(ap_rec_get "$rec" sums_sha256)" ] \
            && [ "$(ap_sha "$lay/SHA256SUMS.asc")" = "$(ap_rec_get "$rec" asc_sha256)" ] \
            && [ "$(ap_sha "$OLD_KEYRING")" = "$(ap_rec_get "$rec" keyring_sha256)" ] \
            || ap_stop "the recorded OmniBridge 1.0.0 set or keyring changed after it was verified" \
                "$lay, $OLD_KEYRING" "Evidence already refers to them; refusing to continue with different bytes."
        return 0
    fi
    [ ! -e "$lay" ] || { mv "$lay" "$lay.unverified.$(ap_stamp)" || ap_stop "cannot move aside the unverified $lay"; }
    mkdir -p "$dl" "$(dirname "$OLD_KEYRING")" || ap_stop "cannot create $art"
    ap_say RUN "ARTIFACTS-OMNIBRIDGE-1.0.0 — the published release, from $(ap_release_url)"
    for f in "$AP_OLD_TARBALL" SHA256SUMS SHA256SUMS.asc "$AP_OLD_PUBKEY"; do
        [ -s "$dl/$f" ] && [ "$f" = "$AP_OLD_TARBALL" ] && continue
        ap_fetch "$(ap_release_url)/$f" "$dl/$f" || ap_stop "cannot download $(ap_release_url)/$f" "Check the network, then resume."
    done
    why="$(ap_keyring_from_pubkey "$dl/$AP_OLD_PUBKEY" "$OLD_KEYRING")" \
        || ap_stop "the published release key was refused: $why" "Nothing was verified or used."
    tmp="$art/extract.$$"; rm -rf "$tmp"; mkdir -p "$tmp"
    tar -xzf "$dl/$AP_OLD_TARBALL" -C "$tmp" || ap_stop "cannot extract $AP_OLD_TARBALL"
    sums="$(find "$tmp" -name SHA256SUMS -type f)"; n="$(grep -c . <<<"$sums" || true)"
    [ "$n" = 1 ] || ap_stop "$AP_OLD_TARBALL holds $n SHA256SUMS files, expected exactly one (the signed layout's)"
    mv "$(dirname "$sums")" "$lay" || ap_stop "cannot place the layout at $lay"
    rm -rf "$tmp"
    cmp -s "$lay/SHA256SUMS" "$dl/SHA256SUMS" && cmp -s "$lay/SHA256SUMS.asc" "$dl/SHA256SUMS.asc" \
        || ap_stop "the tarball's SHA256SUMS/.asc are not the ones the release publishes" "Kept at $lay; nothing used."
    vout="$art/verify-release.$(ap_stamp).txt"
    "$REPO/packaging/release/verify-release.sh" --dir "$lay" --keyring "$OLD_KEYRING" --fingerprint "$AP_RELEASE_FPR" > "$vout" 2>&1 \
        && grep -qE '^VERIFIED  ' "$vout" \
        || ap_stop "verify-release.sh did not verify the published OmniBridge 1.0.0 set" "Its output: $vout"
    for d in "${AP_DISTROS[@]}"; do
        while IFS= read -r f; do
            [ -f "$lay/$f" ] || ap_stop "the verified 1.0.0 layout has no $f"
        done < <(ap_old_expected "$d")
    done
    ap_rec_put "$rec" "state=ready" "release=$AP_RELEASE_REPO@$AP_RELEASE_TAG" "url=$(ap_release_url)" \
        "tarball=$dl/$AP_OLD_TARBALL" "tarball_sha256=$(ap_sha "$dl/$AP_OLD_TARBALL")" \
        "layout=$lay" "sums_sha256=$(ap_sha "$lay/SHA256SUMS")" "asc_sha256=$(ap_sha "$lay/SHA256SUMS.asc")" \
        "keyring=$OLD_KEYRING" "keyring_sha256=$(ap_sha "$OLD_KEYRING")" "pubkey_sha256=$(ap_sha "$dl/$AP_OLD_PUBKEY")" \
        "fingerprint=$AP_RELEASE_FPR" "subkey=$AP_RELEASE_SUBKEY" "verify_output=$vout" \
        "verified_utc=$(ap_utc)" || ap_stop "cannot record the 1.0.0 set"
    ap_say PASS "ARTIFACTS-OMNIBRIDGE-1.0.0 — VERIFIED against $AP_RELEASE_FPR (signing subkey $AP_RELEASE_SUBKEY)"
}

# ------------------------------------------------------------------ Pliwee --
ap_pkg_tool() { printf '%s/%s' "${AP_PACKAGING_DIR:-$REPO/packaging}" "$1"; }
ap_build_image() {
    case "$1" in
        ubuntu2404) echo docker.io/library/ubuntu:24.04 ;; ubuntu2604) echo docker.io/library/ubuntu:26.04 ;;
        debian13) echo docker.io/library/debian:trixie ;; fedora44) echo registry.fedoraproject.org/fedora:44 ;;
    esac
}
ap_pkg_globs() {
    case "$1" in
        fedora44) printf '%s\n' 'pliwee-[0-9]*.x86_64.rpm' 'pliwee-gui-[0-9]*.x86_64.rpm' 'omnibridge-[0-9]*.noarch.rpm' 'pliwee-[0-9]*.src.rpm' ;;
        *) printf '%s\n' 'pliwee_*_amd64.deb' 'pliwee-gui_*_amd64.deb' 'omnibridge_*_all.deb' 'omnibridge-gui_*_all.deb' ;;
    esac
}
# ap_heavy LOG CMD... — a build: two CPUs, low priority, output to LOG only.
ap_heavy() {
    local log="$1"; shift
    { printf '# %s\n# command:' "$(ap_utc)"; printf ' %q' "$@"; printf '\n'; } >> "$log"
    nice -n 10 ionice -c 3 taskset -c "${AP_BUILD_CPUS:-0,1}" "$@" >> "$log" 2>&1
}

# ap_pliwee_pin — the one commit every Pliwee set is built from. Sets PIN, PIN12.
ap_pliwee_pin() {
    local head
    head="$(git -C "$REPO" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || ap_stop "$REPO is not a git checkout"
    if ap_rec_has pliwee-pin; then
        PIN="$(ap_rec_get pliwee-pin commit)"
        [ "$PIN" = "$head" ] || AP_PIN_NOTE="Pliwee packages are pinned to $PIN; the checkout is now at $head (gates keep measuring the pinned set)"
    else
        PIN="$head"
        ap_rec_put pliwee-pin "commit=$PIN" "pinned_utc=$(ap_utc)" \
            "worktree_changes_at_pin=$(git -C "$REPO" status --porcelain 2>/dev/null | grep -c . || true)" \
            || ap_stop "cannot record the Pliwee pin"
    fi
    PIN12="${PIN:0:12}"
}

# ap_bundle_ensure — the source bundle for PIN.
ap_bundle_ensure() {
    local base out rec=pliwee-bundle
    base="$(ap_art)/pliwee-$PIN12"; out="$base/bundle"; mkdir -p "$base/logs"
    if [ "$(ap_rec_get "$rec" state 2>/dev/null)" = ready ] && [ "$(ap_rec_get "$rec" commit)" = "$PIN" ]; then
        BUNDLE="$out"; return 0
    fi
    [ ! -e "$out" ] || mv "$out" "$out.interrupted.$(ap_stamp)"
    ap_one_vm "(build)"
    ap_wait_memory "${AP_BUILD_MEM_MIB:-3072}" "the Pliwee source bundle"
    ap_say RUN "BUILD-bundle — make-source-bundle.sh --rev $PIN12 (log $base/logs/bundle.log)"
    ap_heavy "$base/logs/bundle.log" "$(ap_pkg_tool release/make-source-bundle.sh)" --rev "$PIN" --output "$out.partial" \
        || ap_stop "make-source-bundle.sh failed" "Log: $base/logs/bundle.log"
    mv "$out.partial" "$out"
    BUNDLE="$out"
    ap_rec_put "$rec" "state=ready" "commit=$PIN" "dir=$out" \
        "files=$(cd "$out" && sha256sum -- * 2>/dev/null | awk '{printf "%s:%s ", $2, $1}')" "built_utc=$(ap_utc)"
}

# ap_new_set_ensure DISTRO — NEW_PKGDIR for DISTRO. Sets NEW_SET.
ap_new_set_ensure() {
    local d="$1" rec="artifacts-new-$1" base raw flat glob n f files=() img log
    ap_pliwee_pin
    base="$(ap_art)/pliwee-$PIN12"; raw="$base/raw/$d"; flat="$base/$d"; log="$base/logs/build-$d.log"
    NEW_SET="$flat"
    if [ "$(ap_rec_get "$rec" state 2>/dev/null)" = ready ]; then
        [ "$(ap_rec_get "$rec" commit)" = "$PIN" ] && [ "$(ap_sha "$flat/SHA256SUMS")" = "$(ap_rec_get "$rec" sums_sha256)" ] \
            && ( cd "$flat" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1 ) \
            || ap_stop "the recorded Pliwee set for $d ($flat) changed after it was built" \
                "Gates already refer to it; refusing to continue with different bytes."
        return 0
    fi
    ap_bundle_ensure
    for f in "$raw" "$flat"; do [ ! -e "$f" ] || mv "$f" "$f.interrupted.$(ap_stamp)"; done
    mkdir -p "$raw" "$(dirname "$log")"
    ap_one_vm "(build)"
    ap_wait_memory "${AP_BUILD_MEM_MIB:-3072}" "the Pliwee $d build"
    img="$(ap_build_image "$d")"
    ap_say RUN "BUILD-$d — Pliwee packages from $PIN12 in $img (2 CPUs; log $log)"
    if [ "$d" = fedora44 ]; then
        ap_heavy "$log" "$(ap_pkg_tool fedora/build-rpm.sh)" "$BUNDLE" --output "$raw" --image "$img"
    else
        ap_heavy "$log" "$(ap_pkg_tool debian/build-deb.sh)" --image "$img" "$BUNDLE" --output "$raw"
    fi || ap_stop "the Pliwee $d build failed" "Log: $log"
    mkdir -p "$flat.partial"
    while IFS= read -r glob; do
        n="$(find "$raw" -maxdepth 1 -name "$glob" -type f | grep -c . || true)"
        [ "$n" = 1 ] || ap_stop "the $d build left $n files matching $glob in $raw, expected exactly 1"
        f="$(find "$raw" -maxdepth 1 -name "$glob" -type f)"
        cp -p "$f" "$flat.partial/" || ap_stop "cannot copy $f"
        files+=("$(basename "$f")")
    done < <(ap_pkg_globs "$d")
    ( cd "$flat.partial" && sha256sum -- "${files[@]}" > SHA256SUMS ) || ap_stop "cannot write the $d SHA256SUMS"
    mv "$flat.partial" "$flat"
    ap_rec_put "$rec" "state=ready" "distro=$d" "commit=$PIN" "pkgdir=$flat" "image=$img" \
        "image_digest=$(podman image inspect --format '{{.Digest}}' "$img" 2>/dev/null)" \
        "sums_sha256=$(ap_sha "$flat/SHA256SUMS")" "packages=$(awk '{printf "%s:%s ", $2, $1}' "$flat/SHA256SUMS")" \
        "log=$log" "built_utc=$(ap_utc)" || ap_stop "cannot record the $d Pliwee set"
    ap_say PASS "BUILD-$d — ${#files[@]} packages from $PIN12 in $flat"
}
