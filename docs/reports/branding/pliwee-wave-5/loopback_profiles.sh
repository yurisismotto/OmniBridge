#!/usr/bin/env bash
# Wave 5 loopback evidence: the real daemon binary, the real `omnibridge pair`
# CLI and the `fake_phone` example (the Pliwee client code driven from a
# terminal), once per identity profile, on one host.
#
# NOT the plan §4 hardware matrix (no physical Android device, no packaged
# OmniBridge 1.0.0 peer is paired). It is the binary-level check that pairing,
# reconnection and a files.v1 transfer run end to end under each profile, and
# every claim is anchored on a line the daemon itself wrote in this run:
# `session established … profile=<p> alpn=<a>` and the transfer id.
#
# Usage: loopback_profiles.sh <pliwee|omnibridge> <desktop dir>
# Everything is created under a fresh mktemp directory and every process is
# bounded by `timeout`. Port 55999, no mDNS, so the run touches nothing else.
set -euo pipefail

profile="$1"
desk="$2"
daemon="$desk/target/debug/omnibridged"
cli="$desk/target/debug/omnibridge"
phone="$desk/target/debug/examples/fake_phone"
for tool in "$daemon" "$cli" "$phone"; do
    [[ -x "$tool" ]] || { echo "FAIL: tool missing: $tool"; exit 1; }
done
case "$profile" in
    pliwee) scheme=pliwee1 alpn=pliwee/1 ;;
    omnibridge) scheme=omnibridge1 alpn=omnibridge/1 ;;
    *) echo "FAIL: unknown profile $profile"; exit 1 ;;
esac

T="$(mktemp -d /tmp/w5-loop-XXXX)"
mkdir -p "$T/run" "$T/data" "$T/dl" "$T/phone"
chmod 700 "$T/run"
export XDG_RUNTIME_DIR="$T/run" FAKE_PHONE_DIR="$T/phone" FAKE_PHONE_HOLD_SECS=15
echo "run dir: $T  profile: $profile"

HOME="$T" timeout 150 "$daemon" --data-dir "$T/data" --port 55999 --no-mdns \
    --download-dir "$T/dl" --accept-files-without-asking --log info \
    > "$T/daemon.raw" 2>&1 &
dpid=$!
trap 'kill $dpid 2>/dev/null || true' EXIT
log() { sed 's/\x1b\[[0-9;]*m//g' "$T/daemon.raw"; }
for _ in $(seq 1 50); do
    [[ -S "$T/run/pliwee/control.sock" ]] && break
    sleep 0.2
done
[[ -S "$T/run/pliwee/control.sock" ]] || { echo "FAIL: daemon never opened its control socket"; exit 1; }

# 1. Pairing. The CLI prints the payload, then asks; `y` arrives after the
#    phone has had time to prove the token.
( sleep 12; echo y ) | timeout 60 "$cli" pair > "$T/pair.txt" 2>&1 &
cpid=$!
payload=""
for _ in $(seq 1 50); do
    payload="$(sed -n 's/^ *\(pliwee1:[^ ]*\)$/\1/p' "$T/pair.txt" | head -1)"
    [[ -n "$payload" ]] && break
    sleep 0.2
done
[[ -n "$payload" ]] || { echo "FAIL: the daemon emitted no pliwee1: payload"; cat "$T/pair.txt"; exit 1; }
grep -q '^ *omnibridge1:' "$T/pair.txt" && { echo "FAIL: the daemon emitted a legacy payload"; exit 1; }
echo "daemon emitted: ${payload%%:*}: (canonical only)"
# The legacy run presents the same code under the legacy scheme, as an
# OmniBridge 1.0.0 desktop would show it. The scheme fixes the profile.
scanned="$scheme:${payload#pliwee1:}"
timeout 60 "$phone" pair "$scanned" > "$T/phone-pair.txt" 2>&1
wait "$cpid" || true
grep -q "Paired with" "$T/pair.txt" || { echo "FAIL: pairing did not complete"; cat "$T/pair.txt" "$T/phone-pair.txt"; exit 1; }

# 2. Reconnect without pairing, and send a file.
device="$(log | sed -n 's/.*session established device=\([0-9a-f]*\) .*/\1/p' | head -1)"
[[ -n "$device" ]] || { echo "FAIL: no session line names the phone"; log; exit 1; }
timeout 20 "$cli" grant "$device" files.v1 > "$T/grant.txt" 2>&1
head -c 200000 /dev/urandom > "$T/sample.bin"
FAKE_PHONE_ADDR=127.0.0.1:55999 timeout 60 "$phone" --profile "$profile" send "$T/sample.bin" \
    > "$T/phone-send.txt" 2>&1

# 3. Observations, all from this run's daemon log.
sessions="$(log | grep -c "session established device=$device .*profile=$profile alpn=$alpn" || true)"
wrong="$(log | grep "session established" | grep -vc "profile=$profile alpn=$alpn" || true)"
stored="$T/dl/sample.bin"
echo "sessions under $profile/$alpn naming $device: $sessions (expected 2: pairing + reconnect)"
echo "sessions under any other profile: $wrong (expected 0)"
[[ "$sessions" == 2 && "$wrong" == 0 ]] || { echo "FAIL: session count"; log | grep "session established"; exit 1; }
[[ -f "$stored" ]] || { echo "FAIL: no stored file"; cat "$T/phone-send.txt"; exit 1; }
want="$(sha256sum < "$T/sample.bin" | cut -d' ' -f1)"
got="$(sha256sum < "$stored" | cut -d' ' -f1)"
[[ "$want" == "$got" ]] || { echo "FAIL: stored file differs"; exit 1; }
transfer="$(sed -n 's/^final: \([0-9a-f]*\) .* completed .*/\1/p' "$T/phone-send.txt" | head -1)"
[[ -n "$transfer" ]] || { echo "FAIL: the phone saw no completed transfer"; cat "$T/phone-send.txt"; exit 1; }
tlines="$(log | grep -c "transfer=$transfer" || true)"
[[ "$tlines" -gt 0 ]] || { echo "FAIL: the daemon never logged transfer $transfer"; exit 1; }
echo "transfer $transfer: stored, sha256 $got matches; daemon lines naming it: $tlines"
echo "--- daemon anchor lines"
log | grep -E "session established|transfer=$transfer" | cut -c1-240
echo "PASS: $profile"
