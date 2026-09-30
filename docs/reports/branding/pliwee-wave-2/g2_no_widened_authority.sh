#!/usr/bin/env bash
# G2 — no lost control, no widened authority (Pliwee rebrand Wave 2).
#
# The static half of the gate. The behavioural half is the unit tests in
# desktop/gui/src/views/devices.rs and lib.rs, plus the display section
# `the_devices_page_widget_tree`. This script proves what those tests cannot
# see:
#
#   A. the wave changed the GUI and nothing under desktop/{daemon,runtime,
#      control,core}. The window is anchored: the changed-file list must name
#      desktop/gui/src/views/devices.rs before its silence about the daemon
#      means anything;
#   B. the five security/regression suites the plan names are byte-identical
#      to the baseline. That is an exact count of 5, compared by blob hash;
#   C. the four trust requests Trusted peers sent are each sent from Devices,
#      and the old page is gone;
#   D. no trust action was mixed into the unauthenticated Quick Panel;
#   E. every destructive request is behind a dialog whose default and close
#      response are Cancel.
#
# Usage, from the repository root:
#   bash docs/reports/branding/pliwee-wave-2/g2_no_widened_authority.sh [BASE]
# BASE defaults to 1566279, the merge of Wave 1 that Wave 2 starts from.
# Exit 0 = PASS, 1 = FAIL. A missing precondition is a FAIL, never a pass.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "G2: not in a git checkout" >&2; exit 1; }
cd "$ROOT" || exit 1
# shellcheck source=packaging/tests/lib/assert.sh
. packaging/tests/lib/assert.sh

BASE="${1:-1566279}"
fail=0
ok()    { printf 'ok    %s\n' "$*"; }
notok() { printf 'FAIL  %s\n' "$*"; fail=1; }

need_tool git sha256sum || exit 1
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
    || { echo "G2: baseline $BASE is not a commit here" >&2; exit 1; }

# --- A. what changed, anchored ---------------------------------------------
changed="$(
    { git diff --name-only "$BASE" --; git ls-files --others --exclude-standard; } | sort -u
)"
if need_window_covers "changed-file list since $BASE" "$changed" "desktop/gui/src/views/devices.rs"; then
    ok "A0 the changed-file list covers this wave (anchor: views/devices.rs)"
else
    notok "A0 the changed-file list does not cover the wave; A1 would be vacuous"
fi
forbidden="$(grep -E '^desktop/(daemon|runtime|control|core)/' <<<"$changed" || true)"
n_forbidden="$(grep -c . <<<"$forbidden" || true)"
if need_exact_count "files changed under desktop/{daemon,runtime,control,core}" "$n_forbidden" 0; then
    ok "A1 0 files changed under desktop/{daemon,runtime,control,core}"
else
    notok "A1 forbidden paths changed: $forbidden"
fi

# --- B. security suites byte-identical --------------------------------------
suites=(
    desktop/daemon/tests/security_certification.rs
    desktop/daemon/tests/control.rs
    desktop/daemon/tests/revoked_cleanup.rs
    desktop/daemon/tests/file_approval.rs
    desktop/core/tests/revoked_tombstone.rs
)
identical=0
for f in "${suites[@]}"; do
    if [ ! -f "$f" ]; then notok "B  $f is missing"; continue; fi
    was="$(git rev-parse --verify --quiet "$BASE:$f")" || { notok "B  $f is not in $BASE"; continue; }
    now="$(git hash-object -- "$f")"
    if [ "$was" = "$now" ]; then
        identical=$((identical + 1))
        ok "B  $f blob $now (= $BASE)  sha256 $(sha256sum -- "$f" | cut -c1-16)…"
    else
        notok "B  $f changed: $was -> $now"
    fi
done
need_exact_count "byte-identical security suites" "$identical" 5 || fail=1

# --- C. control parity in source ---------------------------------------------
dev="desktop/gui/src/views/devices.rs"
src="$(cat -- "$dev" 2>/dev/null || true)"
need_nonempty "$dev" "$src" 100 || fail=1
for req in 'Request::Grant {' 'Request::Unpair {' 'Request::HideRevokedDevice {' 'Request::HideAllRevokedDevices'; do
    if contains "$src" "$req"; then ok "C  Devices sends $req"; else notok "C  Devices does not send $req"; fi
done
for label in '"Revoke this device"' '"Remove from list"' '"Remove all revoked devices"' 'gtk::Switch::new()'; do
    if contains "$src" "$label"; then ok "C  Devices draws $label"; else notok "C  Devices lost $label"; fi
done
if [ -e desktop/gui/src/views/peers.rs ]; then notok "C  views/peers.rs still exists"; else ok "C  views/peers.rs is gone (merged into devices.rs)"; fi
lib="$(cat desktop/gui/src/lib.rs)"
need_nonempty "desktop/gui/src/lib.rs" "$lib" 100 || fail=1
if absent "$lib" "TrustedPeers"; then ok "C  Page::TrustedPeers no longer exists"; else notok "C  Page::TrustedPeers still present"; fi
if contains "$lib" 'const LEGACY_PEERS_PAGE: &str = "peers";'; then ok "C  --page peers alias is defined"; else notok "C  --page peers alias missing"; fi

# --- D. nothing trust-related in the Quick Panel ------------------------------
panel="$(cat desktop/gui/src/panel/*.rs desktop/gui/src/panel/model/*.rs 2>/dev/null || true)"
need_nonempty "Quick Panel sources" "$panel" 100 || fail=1
for req in 'Request::Grant' 'Request::Unpair' 'Request::HideRevokedDevice' 'Request::HideAllRevokedDevices'; do
    if absent "$panel" "$req"; then ok "D  Quick Panel does not send $req"; else notok "D  Quick Panel sends $req"; fi
done

# --- E. every destructive request is confirmed, Cancel by default -------------
n_dialogs="$(grep -c 'let dialog = confirmation(' <<<"$src" || true)"
need_exact_count "confirmation dialogs in $dev" "$n_dialogs" 3 && ok "E  3 confirmation dialogs (revoke, remove, remove all)" || fail=1
for line in 'dialog.set_default_response(Some("cancel"));' 'dialog.set_close_response("cancel");' 'adw::ResponseAppearance::Destructive'; do
    if contains "$src" "$line"; then ok "E  $line"; else notok "E  missing $line"; fi
done

if [ "$fail" -eq 0 ]; then echo "G2: PASS (static half; base $BASE)"; else echo "G2: FAIL"; fi
exit "$fail"
