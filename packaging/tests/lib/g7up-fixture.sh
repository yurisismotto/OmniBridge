#!/usr/bin/env bash
# g7up-fixture.sh — TEST ONLY. Writes the G7-UP stage records exactly as
# upgrade-gates.sh writes them after a good upgrade and a good U6, so the
# self-tests can prove that g7up_verify_u6 ACCEPTS the real shape and then
# REJECTS each way of breaking it. Nothing outside the self-tests sources this.

# g7up_fixture EVIDENCE DISTRO DOMAIN [OLD_SHA256SUMS_FILE]
g7up_fixture() {
    local ev="$1" distro="$2" dom="$3" sums="${4:-}" now
    now="$(date +%s)"
    mkdir -p "$ev/U6"
    printf 'device g7-host (0123456789abcdef)\nfingerprint AB12 CD34 EF56 7890\npaired-count 1\n' > "$ev/O1-facts.txt"
    {
        echo "stage=upgrade"; echo "status=complete"; echo "distro=$distro"; echo "domain=$dom"
        echo "run_id=g7up-$distro-20260925T000000Z-0badc0de"
        echo "guest_os=fixture"; echo "guest_machine_id=5f0c0ffee5f0c0ffee5f0c0ffee5f0c0"
        echo "guest_fingerprint=AB12 CD34 EF56 7890"
        echo "o1_facts_sha256=$(sha256sum "$ev/O1-facts.txt" | awk '{print $1}')"
        if [ -n "$sums" ]; then echo "old_sha256sums_sha256=$(sha256sum "$sums" | awk '{print $1}')"
        else echo "old_sha256sums_sha256=$(printf '0%.0s' $(seq 1 64))"; fi
        echo "new_sha256sums_sha256=$(printf '1%.0s' $(seq 1 64))"
        echo "upgrade_ok=31"; echo "upgrade_not_ok=0"; echo "upgrade_na=1"
        echo "completed_utc=2026-09-25T00:00:00Z"; echo "completed_epoch=$(( now - 60 ))"
    } > "$ev/UPGRADE-CHECKPOINT"
    {
        echo "distro        $distro"; echo "domain        $dom"; echo "hostname      g7-host"
        echo "device_name   g7-host"; echo "device_id     0123456789abcdef"
        echo "fingerprint   AB12 CD34 EF56 7890"; echo "guest_ip      192.0.2.10"
        echo "phone         SM-X620  192.0.2.20"; echo "recorded_at   2026-09-25T00:01:00Z"
    } > "$ev/U6/29-peer-identity.txt"
    {
        echo "== Preconditions =="
        for i in $(seq 1 12); do echo "ok    precondition $i holds"; done
        echo "ok    the phone is already paired with this guest; no operator action needed"
        echo "ok    the phone is connected to g7-host"
        echo "ok    the newest session event is this peer's establishment, so it describes the live session"
        echo "ok    the phone shows this guest's fingerprint (AB12 CD34), so the selected peer is the guest under test"
        echo "ok    L14: guest -> phone clipboard send exited 0"
        echo "ok    L14: the phone shows 'Clipboard from g7-host' -- receipt attributed to the guest under test"
        echo "ok    L14: phone -> guest arrived; the daemon's clipboard cache grew 1 -> 2 inside the bracketing window"
        echo "ok    L15: the guest reports the transfer completed"
        echo "ok    L15: 3 journal line(s) name transfer=1a2b3c4d specifically"
        echo "ok    L15: the guest journal records the peer confirming it stored THIS transfer"
        echo "n/a   L16: the 'no content in the journal' half is NOT asserted here"
        echo "-----------------------------------------------"
        echo "$distro / $dom: 34 passed, 0 failed, 1 n/a"
        echo "evidence: $ev/U6"
    } > "$ev/U6/lifecycle-peer-gates.log"
    printf 'files: offering transfer=1a2b3c4d size=48\nfiles: transfer=1a2b3c4d the peer confirmed it stored the file\n' \
        > "$ev/U6/43b-L15-journal.txt"
    {
        echo "stage=peer-u6"; echo "distro=$distro"; echo "domain=$dom"
        echo "run_id=g7up-$distro-20260925T000000Z-0badc0de"
        echo "guest_machine_id=5f0c0ffee5f0c0ffee5f0c0ffee5f0c0"; echo "guest_fingerprint=AB12 CD34 EF56 7890"
        echo "phone_ip=192.0.2.20"; echo "started_epoch=$(( now - 30 ))"; echo "finished_epoch=$now"; echo "exit=0"
        echo "log_sha256=$(sha256sum "$ev/U6/lifecycle-peer-gates.log" | awk '{print $1}')"
        echo "identity_sha256=$(sha256sum "$ev/U6/29-peer-identity.txt" | awk '{print $1}')"
        echo "verdict=PASS"
    } > "$ev/U6-RESULT"
}

# g7up_fixture_rehash EVIDENCE — after a deliberate edit, make the digests in
# U6-RESULT match again, so a case isolates the ONE property it breaks.
g7up_fixture_rehash() {
    local ev="$1"
    sed -i -e "s/^log_sha256=.*/log_sha256=$(sha256sum "$ev/U6/lifecycle-peer-gates.log" | awk '{print $1}')/" \
           -e "s/^identity_sha256=.*/identity_sha256=$(sha256sum "$ev/U6/29-peer-identity.txt" | awk '{print $1}')/" \
        "$ev/U6-RESULT"
}
