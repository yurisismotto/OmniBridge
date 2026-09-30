package io.github.yurisismotto.pliwee.net

/**
 * The wire identity profile of one connection (ADR-0020 §D4).
 *
 * The mirror of `pliwee_core::Profile`. Pliwee always emits its canonical
 * identifiers; through the v1.x line it also speaks the OmniBridge ones, so
 * this app can still discover, pair with and use an un-upgraded OmniBridge
 * 1.0.0 desktop. Which set a connection uses is decided **once**: this client
 * offers exactly one ALPN — its profile's — and the handshake either
 * negotiates it or fails. Every brand-bearing value on that connection (the
 * pairing proof and confirmation domains, the `files.v1` data-stream domain)
 * comes from the profile. Nothing is ever tried "under both".
 *
 * The two profiles share one construction: same TLS 1.3, same SPKI pinning,
 * same HMAC-SHA256, same framing. Selecting the legacy profile is a change of
 * label, not a weaker algorithm.
 *
 * A peer's profile is remembered **in memory only**, to know what to dial.
 * It is never persisted and is not trust: trust is the SPKI pin.
 *
 * `notifications.v1` is deliberately absent. Its ids are derived on this
 * device alone and are opaque to the desktop, so they use the canonical
 * domains only and have no legacy form.
 */
enum class WireProfile(
    /** Short name, matching the desktop's `Profile::as_str`. */
    val id: String,
    val controlAlpn: String,
    val dataAlpn: String,
    /** NSD form: no `.local.` suffix, unlike the desktop's `mdns-sd`. */
    val serviceType: String,
    val qrScheme: String,
    val pairingProofDomain: String,
    val pairingConfirmDomain: String,
    val filesDataStreamDomain: String,
) {
    /** Canonical. */
    PLIWEE(
        id = "pliwee",
        controlAlpn = "pliwee/1",
        dataAlpn = "pliwee-data/1",
        serviceType = "_pliwee._tcp.",
        qrScheme = "pliwee1",
        pairingProofDomain = "pliwee/pairing-proof/v1",
        pairingConfirmDomain = "pliwee/pairing-confirm/v1",
        filesDataStreamDomain = "pliwee/files.v1/data-stream/v1",
    ),

    /**
     * Legacy acceptance path for OmniBridge 1.0.0 desktops. Removing it is a
     * breaking change that needs its own ADR and a major version.
     */
    OMNIBRIDGE(
        id = "omnibridge",
        controlAlpn = "omnibridge/1",
        dataAlpn = "omnibridge-data/1",
        serviceType = "_omnibridge._tcp.",
        qrScheme = "omnibridge1",
        pairingProofDomain = "omnibridge/pairing-proof/v1",
        pairingConfirmDomain = "omnibridge/pairing-confirm/v1",
        filesDataStreamDomain = "omnibridge/files.v1/data-stream/v1",
    ),
    ;

    companion object {
        /** What a peer is dialled with when nothing says otherwise. */
        val CANONICAL = PLIWEE

        /** The profile whose control ALPN is [alpn], or null. Never a guess. */
        fun ofControlAlpn(alpn: String?): WireProfile? = entries.firstOrNull { it.controlAlpn == alpn }

        /** The profile whose data ALPN is [alpn], or null. */
        fun ofDataAlpn(alpn: String?): WireProfile? = entries.firstOrNull { it.dataAlpn == alpn }

        /** The profile whose QR scheme tag is exactly [scheme], or null. */
        fun ofQrScheme(scheme: String): WireProfile? = entries.firstOrNull { it.qrScheme == scheme }
    }
}
