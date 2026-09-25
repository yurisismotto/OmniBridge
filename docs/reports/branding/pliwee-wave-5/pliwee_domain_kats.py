#!/usr/bin/env python3
"""Independent known-answer vectors for the Pliwee Wave 5 domains.

ADR-0020 D10 and the Wave 5 plan require the Pliwee-profile KATs to be
computed "independently from the documented construction (a script separate
from the implementation, as ADR-0018 did)". This script is that computation.
It uses only Python's standard library (hmac, hashlib, struct), and neither
the Rust nor the Kotlin code, so the values it prints are the ones those
implementations must reproduce, not values copied from them.

The inputs are the fixed inputs both test suites already use:

* pairing: token = 00 01 .. 13, responder = 01 * 32, initiator = 02 * 32,
  nonce[i] = i * 3 (mod 256), i in 0..32
* files.v1 data stream: challenge = 01 * 32, acceptor = 02 * 32,
  dialer = 03 * 32, transfer id = 04 * 16
* notifications.v1: secret[i] = i (i in 0..32), other secret[i] = i + 1,
  platform key "0|example.fixture.app|1|null|10123", other key
  "0|example.other.app|1|null|10124", group key "0|example.fixture.app|g:chat"

The legacy (omnibridge) rows are printed as well. They must equal the KATs
that were already committed before Wave 5 (d34504e6…, fd1689c7…, 503aaf7d…,
3c8effce…, b9f8d940…, 3561179d…, e88bcb16…). If they do, the script's reading
of the construction matches the one the frozen KATs were derived from, which
is what makes its Pliwee rows trustworthy.

Run: python3 docs/reports/branding/pliwee-wave-5/pliwee_domain_kats.py
"""

import hashlib
import hmac
import struct


def len32(n: int) -> bytes:
    return struct.pack(">I", n)


def lp(data: bytes) -> bytes:
    return len32(len(data)) + data


def hmac_sha256(key: bytes, msg: bytes) -> bytes:
    return hmac.new(key, msg, hashlib.sha256).digest()


TOKEN = bytes(range(20))
RESPONDER = bytes([0x01]) * 32
INITIATOR = bytes([0x02]) * 32
NONCE = bytes((i * 3) % 256 for i in range(32))

CHALLENGE = bytes([0x01]) * 32
ACCEPTOR = bytes([0x02]) * 32
DIALER = bytes([0x03]) * 32
TRANSFER_ID = bytes([0x04]) * 16

SECRET = bytes(range(32))
OTHER_SECRET = bytes((i + 1) % 256 for i in range(32))
PLATFORM_KEY = b"0|example.fixture.app|1|null|10123"
OTHER_KEY = b"0|example.other.app|1|null|10124"
GROUP_KEY = b"0|example.fixture.app|g:chat"


def pairing(domain: bytes) -> str:
    return hmac_sha256(TOKEN, domain + lp(RESPONDER) + lp(INITIATOR) + lp(NONCE)).hex()


def stream_mac(domain: bytes) -> str:
    return hmac_sha256(CHALLENGE, domain + lp(ACCEPTOR) + lp(DIALER) + lp(TRANSFER_ID)).hex()


def notification_id(domain: bytes, secret: bytes, key: bytes) -> str:
    return hmac_sha256(secret, domain + lp(key))[:16].hex()


def group_id(domain: bytes, key: bytes) -> str:
    return hashlib.sha256(domain + lp(key)).digest()[:8].hex()


def main() -> None:
    for brand in ("omnibridge", "pliwee"):
        b = brand.encode("ascii")
        nid = b + b"/notifications.v1/id/v1"
        gid = b + b"/notifications.v1/group/v1"
        print(f"[{brand}]")
        print(f"pairing-proof      {pairing(b + b'/pairing-proof/v1')}")
        print(f"pairing-confirm    {pairing(b + b'/pairing-confirm/v1')}")
        print(f"files-data-stream  {stream_mac(b + b'/files.v1/data-stream/v1')}")
        print(f"notif-id           {notification_id(nid, SECRET, PLATFORM_KEY)}")
        print(f"notif-id-other-key {notification_id(nid, SECRET, OTHER_KEY)}")
        print(f"notif-id-other-sec {notification_id(nid, OTHER_SECRET, PLATFORM_KEY)}")
        print(f"notif-group        {group_id(gid, GROUP_KEY)}")
        print()


if __name__ == "__main__":
    main()
