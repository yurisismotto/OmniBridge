//! The wire identity profile of one connection (ADR-0020 §D4).
//!
//! Pliwee has its own canonical identifiers and always emits them. Through the
//! Pliwee v1.x line it also accepts the OmniBridge identifiers, so that an
//! un-upgraded OmniBridge 1.0.0 peer keeps working. Which set a connection
//! uses is decided **once**, by the ALPN its TLS handshake negotiated, and
//! every brand-bearing value on that connection — the pairing proof and
//! confirmation domains, the `files.v1` data-stream domain — is derived from
//! it. Nothing is ever tried "under both": a value that would verify only
//! under the other profile's domain is a failure.
//!
//! The two profiles share one construction. Selecting the legacy profile is a
//! change of label, not a weaker algorithm: same TLS 1.3, same SPKI pinning,
//! same HMAC-SHA256, same framing.
//!
//! The profile is a property of a connection, never of a peer's trust. It is
//! not persisted: trust is keyed by SPKI fingerprint, which no profile
//! changes.

/// One of the two identity profiles a connection can run under.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Profile {
    /// Canonical: `pliwee/1`, `_pliwee._tcp`, `pliwee1:`, `pliwee/…/v1`.
    Pliwee,
    /// Legacy acceptance path for OmniBridge 1.0.0 peers. Removing it is a
    /// breaking change that needs its own ADR and a major version.
    OmniBridge,
}

impl Profile {
    /// Both profiles, canonical first. This is also the listener's order of
    /// preference.
    pub const ALL: [Profile; 2] = [Profile::Pliwee, Profile::OmniBridge];

    /// Short name, for logs and `--profile` switches.
    pub fn as_str(self) -> &'static str {
        match self {
            Profile::Pliwee => "pliwee",
            Profile::OmniBridge => "omnibridge",
        }
    }

    /// Parses [`Profile::as_str`]. Anything else is `None`, never a default.
    pub fn from_name(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|p| p.as_str() == name)
    }

    /// ALPN identifier of this profile's control session.
    pub fn control_alpn(self) -> &'static [u8] {
        match self {
            Profile::Pliwee => crate::ALPN_PROTOCOL,
            Profile::OmniBridge => crate::LEGACY_ALPN_PROTOCOL,
        }
    }

    /// ALPN identifier of this profile's bulk data stream.
    pub fn data_alpn(self) -> &'static [u8] {
        match self {
            Profile::Pliwee => crate::ALPN_DATA_PROTOCOL,
            Profile::OmniBridge => crate::LEGACY_ALPN_DATA_PROTOCOL,
        }
    }

    /// DNS-SD service type this profile is advertised under.
    pub fn service_type(self) -> &'static str {
        match self {
            Profile::Pliwee => crate::SERVICE_TYPE,
            Profile::OmniBridge => crate::LEGACY_SERVICE_TYPE,
        }
    }

    /// QR payload scheme tag of this profile.
    pub fn qr_scheme(self) -> &'static str {
        match self {
            Profile::Pliwee => crate::qr::QR_SCHEME,
            Profile::OmniBridge => crate::qr::LEGACY_QR_SCHEME,
        }
    }

    /// Domain separator of the initiator's pairing proof.
    pub fn pairing_proof_domain(self) -> &'static [u8] {
        match self {
            Profile::Pliwee => b"pliwee/pairing-proof/v1",
            Profile::OmniBridge => b"omnibridge/pairing-proof/v1",
        }
    }

    /// Domain separator of the responder's pairing confirmation.
    pub fn pairing_confirm_domain(self) -> &'static [u8] {
        match self {
            Profile::Pliwee => b"pliwee/pairing-confirm/v1",
            Profile::OmniBridge => b"omnibridge/pairing-confirm/v1",
        }
    }
}

impl std::fmt::Display for Profile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}
