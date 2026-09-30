package io.github.yurisismotto.pliwee.net

import java.util.concurrent.ConcurrentHashMap

/**
 * Which [WireProfile] to dial each paired computer with (ADR-0020 §D4).
 *
 * The rule: canonical, unless the computer is known **only** as legacy —
 * paired from an `omnibridge1:` code, or found by discovery on
 * `_omnibridge._tcp` and not on `_pliwee._tcp`. The newest evidence wins, so
 * an OmniBridge 1.0.0 desktop that is later upgraded to Pliwee is dialled
 * canonically as soon as discovery sees its canonical record.
 *
 * **Memory only, and not trust.** Keyed by the pinned fingerprint and never
 * written to disk: the profile says what to offer, not whom to believe.
 * Trust stays the SPKI pin, which no profile changes. After a restart the
 * map is empty, a legacy computer's first canonical dial fails at the TLS
 * handshake (a transport failure, retried), and the next round's discovery
 * finds it on the legacy type only.
 */
class PeerProfiles {

    private val known = ConcurrentHashMap<String, WireProfile>()

    /** The one profile to offer when dialling [fingerprintHex]. */
    fun forDialing(fingerprintHex: String): WireProfile =
        known[fingerprintHex] ?: WireProfile.CANONICAL

    /** A pairing from a scanned code completed under [profile]. */
    fun learnedFromPairing(fingerprintHex: String, profile: WireProfile) {
        known[fingerprintHex] = profile
    }

    /**
     * Discovery found this computer; [profile] is the merged verdict of
     * [Discovery.merge] — canonical if any record was canonical.
     */
    fun learnedFromDiscovery(fingerprintHex: String, profile: WireProfile) {
        known[fingerprintHex] = profile
    }
}
