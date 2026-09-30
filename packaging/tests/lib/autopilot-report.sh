#!/usr/bin/env bash
# autopilot-report.sh — REPORT.md and the final summary.
#
# The report states what the coordinator's own summary says, gate by gate, and
# where each gate's evidence is. It adds provenance (host, images, templates,
# guests, package sets) and one conclusion: whether G8 may run. G8 is eligible
# only when the coordinator's result is PASS — every gate PASS, W2 and W6
# included — in a real (not self-test) run. Nothing here can turn a gate
# PASS: it reads records and never writes one.

# ap_manual_gate G — the gates a person runs with the coordinator (the
# autopilot never runs them).
ap_manual_gate() { case "$1" in W2-*|W6-*) return 0 ;; esac; return 1; }

# ap_gate_evidence G — the paths the coordinator's record names.
ap_gate_evidence() {
    local f="$EVIDENCE/state/$1" k v out=()
    [ -f "$f" ] || return 0
    for k in log answers status_file evidence_dir; do
        v="$(g7up_kv "$f" "$k" 2>/dev/null)"; [ -n "$v" ] && out+=("$k: \`$v\`")
    done
    case "$1" in
        G7UP-*-U8) out+=("harness: \`$EVIDENCE/g7up-u8/$(ap_gate_distro "$1")\`") ;;
        LIFECYCLE-*) out+=("harness: \`$EVIDENCE/lifecycle/$(ap_gate_distro "$1")\`") ;;
        G7UP-*-SECLOG) out+=("harness: \`$EVIDENCE/g7up/$(ap_gate_distro "$1")/seclog\`") ;;
        G7UP-*) out+=("chain: \`$EVIDENCE/g7up/$(ap_gate_distro "$1")\`") ;;
    esac
    local IFS='; '; printf '%s' "${out[*]}"
}

# ap_eligibility — sets G8_ELIGIBLE (YES/NO) and G8_WHY (lines).
ap_eligibility() {
    local g s
    G8_WHY=""
    for g in "${AP_ALL_GATES[@]}"; do
        s="$(ap_gate_state "$g")"
        [ "$s" = PASS ] && continue
        if ap_manual_gate "$g"; then G8_WHY+="- $g is $s — MANUAL OUTSTANDING (operator gate; the autopilot never runs it)"$'\n'
        else G8_WHY+="- $g is $s"$'\n'; fi
    done
    [ "${AP_SELFTEST:-0}" = 1 ] && G8_WHY+="- this is a self-test run: stub gates, nothing measured"$'\n'
    [ "$AP_RESULT" = PASS ] || G8_WHY+="- the coordinator's overall result is ${AP_RESULT:-unknown}, not PASS"$'\n'
    if [ -z "$G8_WHY" ]; then G8_ELIGIBLE=YES; else G8_ELIGIBLE=NO; fi
}

ap_report_write() { # KIND MESSAGE
    local report="$AP_STATE/REPORT.md" g s r d role dom rec k tmp
    [ -n "${AP_ALL_GATES[*]:-}" ] || return 0
    ap_eligibility
    tmp="$report.partial.$$"
    {
        echo "# Pliwee pre-G8 autopilot report"
        echo
        echo "Generated $(ap_utc) by \`packaging/tests/pre-g8-autopilot.sh\`$([ "${AP_SELFTEST:-0}" = 1 ] && echo ' — **SELF-TEST RUN** (stub gates; nothing here is evidence)')."
        echo
        echo "| | |"; echo "|---|---|"
        echo "| Source commit | \`$(git -C "$REPO" rev-parse HEAD 2>/dev/null)\` ($(git -C "$REPO" status --porcelain 2>/dev/null | grep -c . || true) uncommitted change(s)) |"
        echo "| Pliwee packages built from | \`$(ap_rec_get pliwee-pin commit 2>/dev/null || echo 'not built yet')\` |"
        echo "| Evidence | \`$EVIDENCE\` |"
        echo "| Coordinator result | \`PRE_G8_RESULT=${AP_RESULT:-unknown}\` |"
        echo "| This run stopped | **$1** — $2 |"
        echo "| **G8 eligible** | **$G8_ELIGIBLE** |"
        echo
        if [ "$G8_ELIGIBLE" = NO ]; then echo "## Why G8 is not eligible"; echo; printf '%s' "$G8_WHY"; echo; fi
        echo "## Manual outstanding"
        echo
        local any=0
        for g in "${AP_ALL_GATES[@]}"; do
            ap_manual_gate "$g" || continue
            s="$(ap_gate_state "$g")"
            [ "$s" = PASS ] && continue
            any=1; echo "- **$g** — $s: $(ap_gate_reason "$g")"
        done
        [ "$any" = 1 ] || echo "- none"
        echo
        echo "The autopilot never runs, retries, or re-records W2 or W6 gates: they stay exactly as the"
        echo "operator's coordinator runs left them (\`pre-g8-manual-gates.sh --run W2-KDE\`, …)."
        echo
        echo "## Failures"
        echo
        any=0
        for g in "${AP_ALL_GATES[@]}"; do
            [ "$(ap_gate_state "$g")" = FAIL ] || continue
            any=1; echo "- **$g** — $(ap_gate_reason "$g")  "; echo "  $(ap_gate_evidence "$g")"
        done
        [ "$any" = 1 ] || echo "- none"
        echo
        echo "## Every gate"
        echo
        echo "| Gate | State | Detail | Evidence |"; echo "|---|---|---|---|"
        for g in "${AP_ALL_GATES[@]}"; do
            r="$(ap_gate_reason "$g" | tr '|' '/')"
            echo "| $g | $(ap_gate_state "$g") | ${r:0:160} | $(ap_gate_evidence "$g" | tr '|' '/') |"
        done
        echo
        echo "## Host"
        echo
        echo '```'; cat "$AP_STATE/records/host" 2>/dev/null || echo "(not recorded)"; echo '```'
        echo
        echo "## Images, templates and guests"
        echo
        for d in "${AP_DISTROS[@]}"; do
            echo "### $d"
            echo
            for rec in "image-$d" "base-$d" "template-$d"; do
                ap_rec_has "$rec" || { echo "- $rec: not created yet"; continue; }
                echo "- **$rec**"
                for k in state url name algo digest signature sums_url volume facts os kernel packages_sha256 built_utc uploaded_utc; do
                    local v; v="$(ap_rec_get "$rec" "$k" 2>/dev/null)" && [ -n "$v" ] && echo "  - $k: \`$v\`"
                done
            done
            for role in "${AP_ROLES[@]}"; do
                dom="$(ap_domain "$d" "$role")"; rec="$(ap_guest_rec "$dom")"
                ap_rec_has "$rec" || { echo "- $dom: not created yet"; continue; }
                echo "- **$dom** — $(ap_rec_get "$rec" state 2>/dev/null), host \`$(ap_rec_get "$rec" hostname 2>/dev/null)\`, machine-id \`$(ap_rec_get "$rec" machine_id 2>/dev/null)\`, mac \`$(ap_rec_get "$rec" mac 2>/dev/null)\`, fresh=$(ap_rec_get "$rec" fresh 2>/dev/null), used by $(ap_rec_get "$rec" used_by 2>/dev/null || echo -)"
            done
            echo
        done
        echo "## Package artifacts"
        echo
        if ap_rec_has artifacts-old; then
            echo "- **OmniBridge 1.0.0 (published, not rebuilt)** — \`$(ap_rec_get artifacts-old release)\` from \`$(ap_rec_get artifacts-old url)\`"
            for k in tarball_sha256 layout sums_sha256 asc_sha256 keyring keyring_sha256 fingerprint subkey verify_output verified_utc; do
                echo "  - $k: \`$(ap_rec_get artifacts-old "$k" 2>/dev/null)\`"
            done
        else echo "- OmniBridge 1.0.0: not fetched yet"; fi
        for d in "${AP_DISTROS[@]}"; do
            if ap_rec_has "artifacts-new-$d"; then
                echo "- **Pliwee $d** — commit \`$(ap_rec_get "artifacts-new-$d" commit)\`, \`$(ap_rec_get "artifacts-new-$d" pkgdir)\`, image \`$(ap_rec_get "artifacts-new-$d" image)\` \`$(ap_rec_get "artifacts-new-$d" image_digest 2>/dev/null)\`"
                echo "  - packages: \`$(ap_rec_get "artifacts-new-$d" packages)\`"
                echo "  - build log: \`$(ap_rec_get "artifacts-new-$d" log)\`"
            else echo "- Pliwee $d: not built yet"; fi
        done
        [ -z "${AP_PIN_NOTE:-}" ] || { echo; echo "> $AP_PIN_NOTE"; }
        echo
        echo "## Autopilot state"
        echo
        echo "- journal: \`$AP_STATE/journal.log\`"
        echo "- this run: \`${AP_RUN:-}\`"
        echo "- coordinator config: \`$AP_STATE/coordinator.conf\`"
    } > "$tmp" && mv "$tmp" "$report"
    [ -z "${AP_RUN:-}" ] || cp "$report" "$AP_RUN/REPORT.md" 2>/dev/null || true
}

ap_final_summary() {
    local g s n_pass=0 n_fail=0 n_other=0
    for g in "${AP_ALL_GATES[@]}"; do
        s="$(ap_gate_state "$g")"
        case "$s" in PASS) n_pass=$((n_pass + 1)) ;; FAIL) n_fail=$((n_fail + 1)) ;; *) n_other=$((n_other + 1)) ;; esac
    done
    ap_eligibility
    printf '\n----------------------------------------------------------\n'
    printf 'Pre-G8: %d PASS, %d FAIL, %d not yet PASS (of %d gates)\n' "$n_pass" "$n_fail" "$n_other" "${#AP_ALL_GATES[@]}"
    for g in "${AP_ALL_GATES[@]}"; do
        ap_manual_gate "$g" || continue
        s="$(ap_gate_state "$g")"; [ "$s" = PASS ] || printf '  MANUAL OUTSTANDING  %-22s %s\n' "$g" "$s"
    done
    printf 'G8 eligible: %s\n' "$G8_ELIGIBLE"
    printf 'Report: %s\n' "$AP_STATE/REPORT.md"
    printf -- '----------------------------------------------------------\n'
}
