#!/usr/bin/env bash
# cli-report.sh — reading the OmniBridge 1.0.0 CLI's reports, one way.
#
# u2-state-check.sh (which measures U2) and pre-g8-autopilot.sh (which brings a
# guest to U2 and must know when it has) read the same trust store; they parse
# it with these functions so the two can never disagree about which peer is
# paired. The shapes are 1.0.0's desktop/cli/src/main.rs print_device and the
# clipboard / notifications status reports.

# ob_devices_tsv TEXT — `omnibridge devices` as one TSV line per device:
# name, id, platform, fingerprint, paired, granted. A device block starts at a
# line holding a name, two spaces and a hex device id.
ob_devices_tsv() {
    awk '
        function flush() { if (have) printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, id, plat, fpr, paired, granted }
        /^ *(platform|fingerprint|paired|connected|state|granted|last|battery) / {
            if (!have) next
            line = $0; sub(/^ +/, "", line); key = line; sub(/ .*/, "", key); val = line; sub(/^[a-z]+ +/, "", val)
            if (key == "platform") plat = val; else if (key == "fingerprint") fpr = val
            else if (key == "paired") paired = val; else if (key == "granted") granted = val
            next
        }
        /^ *[^ ].*  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+ *$/ {
            flush(); have = 1; line = $0; sub(/^ +/, "", line); sub(/ +$/, "", line)
            id = line; sub(/.*  /, "", id); name = line; sub(/  [0-9a-f]+$/, "", name)
            plat = fpr = paired = granted = ""
        }
        END { flush() }' <<<"$1"
}

# ob_peer_block TEXT NEEDLE — the lines of one peer's block in `clipboard
# status` or `notifications status`: after the line containing NEEDLE (a device
# id, or "(FINGERPRINT)"), up to the next peer line (four-space indent).
ob_peer_block() {
    awk -v id="$2" '
        index($0, id) && !inb { inb = 1; next }
        inb && /^    [^ ]/ { exit }
        inb { print }' <<<"$1"
}
