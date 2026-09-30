//! TLS 1.3 transport with public-key pinning.
//!
//! # The shape of the problem
//!
//! There is no CA in this system and there never will be one — provisioning a
//! PKI for two devices on a home network is absurd. So the usual WebPKI chain
//! validation has nothing to validate against. What we do instead is pin the
//! peer's SPKI fingerprint, exactly as the pairing step established it.
//!
//! This means writing custom `rustls` verifiers, which is the single most
//! dangerous thing in this codebase. The trap everyone falls into is a
//! verifier that returns `Ok(())` from `verify_tls13_signature`. Doing that
//! disables the proof-of-possession step: any attacker could then replay a
//! *copy* of the legitimate certificate (certificates are public!) and be
//! accepted without ever holding the private key. Both verifiers below
//! therefore delegate to `rustls::crypto::verify_tls13_signature`, which is
//! the real check.
//!
//! What each verifier does:
//!
//! * [`PinnedServerCertVerifier`] — used when dialing a known peer. Requires
//!   the presented leaf's SPKI fingerprint to equal the pinned one. Any other
//!   identity, including a valid certificate for a different device, is
//!   rejected.
//!
//! * [`RecordingClientCertVerifier`] — used when listening. It cannot pin,
//!   because during pairing the client is by definition not yet known. It
//!   requires client authentication, checks the certificate is well-formed
//!   and that the client actually holds the private key, and then defers the
//!   *authorization* decision to the session layer, which requires either a
//!   trust-store hit or a valid pairing proof. Discovery and reachability
//!   grant nothing (principle: discovery is not trust).
//!
//! TLS 1.2 and below are not merely discouraged, they are not compiled in:
//! the configs are built with `TLS13` only and both `verify_tls12_signature`
//! implementations return an error unconditionally.

use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::{DigitallySignedStruct, DistinguishedName, SignatureScheme};
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};

use crate::error::{Error, Result};
use crate::fingerprint::Fingerprint;
use crate::identity::IdentityProvider;
use crate::profile::Profile;

/// Only TLS 1.3. Not a runtime toggle, and not overridable by a peer.
static TLS13_ONLY: &[&rustls::SupportedProtocolVersion] = &[&rustls::version::TLS13];

fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Signature schemes we accept for the handshake signature.
///
/// P-256/SHA-256 is what our own certificates use. The wider set is offered
/// because rustls requires us to declare what we can verify, and rejecting
/// schemes we could verify would only produce confusing failures for future
/// peers that legitimately use a stronger key.
fn supported_schemes() -> Vec<SignatureScheme> {
    vec![
        SignatureScheme::ECDSA_NISTP256_SHA256,
        SignatureScheme::ECDSA_NISTP384_SHA384,
        SignatureScheme::ED25519,
        SignatureScheme::RSA_PSS_SHA256,
        SignatureScheme::RSA_PSS_SHA384,
        SignatureScheme::RSA_PSS_SHA512,
    ]
}

/// Structural checks every peer certificate must pass, whether or not it is
/// pinned: it must parse as X.509, and it must be within its validity window.
///
/// Validity is a hygiene check, not the trust anchor — the pin is. It is
/// checked anyway so that a long-forgotten certificate surfaces as a clear
/// error instead of working forever. A generous skew allowance keeps a phone
/// with a slightly wrong clock from being locked out.
const CLOCK_SKEW_TOLERANCE_SECS: u64 = 86_400;

fn validate_certificate_structure(
    cert_der: &[u8],
    now: UnixTime,
) -> std::result::Result<(), rustls::Error> {
    let (_, cert) = x509_parser::parse_x509_certificate(cert_der)
        .map_err(|_| rustls::Error::InvalidCertificate(rustls::CertificateError::BadEncoding))?;

    let now_secs = now.as_secs();
    let not_before = cert.validity().not_before.timestamp() as u64;
    let not_after = cert.validity().not_after.timestamp() as u64;

    if now_secs + CLOCK_SKEW_TOLERANCE_SECS < not_before {
        return Err(rustls::Error::InvalidCertificate(
            rustls::CertificateError::NotValidYet,
        ));
    }
    if now_secs > not_after.saturating_add(CLOCK_SKEW_TOLERANCE_SECS) {
        return Err(rustls::Error::InvalidCertificate(
            rustls::CertificateError::Expired,
        ));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Client side: pin the server
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct PinnedServerCertVerifier {
    expected: Fingerprint,
    provider: Arc<rustls::crypto::CryptoProvider>,
}

impl PinnedServerCertVerifier {
    pub fn new(expected: Fingerprint) -> Self {
        Self {
            expected,
            provider: provider(),
        }
    }
}

impl ServerCertVerifier for PinnedServerCertVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, rustls::Error> {
        validate_certificate_structure(end_entity, now)?;

        // The identity check. Note that `_server_name` is ignored on purpose:
        // hostnames and IPs are not identity in this protocol (principle 6),
        // and our certificates carry no SANs precisely so that nobody can
        // accidentally reintroduce name-based trust.
        let presented = Fingerprint::from_certificate_der(end_entity).map_err(|_| {
            rustls::Error::InvalidCertificate(rustls::CertificateError::BadEncoding)
        })?;

        if presented != self.expected {
            return Err(rustls::Error::InvalidCertificate(
                rustls::CertificateError::ApplicationVerificationFailure,
            ));
        }

        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        // Unreachable with a TLS1.3-only config; an explicit refusal so that
        // it stays unreachable if someone widens the version list later.
        Err(rustls::Error::PeerIncompatible(
            rustls::PeerIncompatible::Tls12NotOffered,
        ))
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        // Proof of possession. Without this, pinning would be worthless:
        // certificates are public, so anyone could present a copy.
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        supported_schemes()
    }
}

// ---------------------------------------------------------------------------
// Server side: authenticate possession, authorize later
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct RecordingClientCertVerifier {
    provider: Arc<rustls::crypto::CryptoProvider>,
    empty_hints: Vec<DistinguishedName>,
}

impl RecordingClientCertVerifier {
    pub fn new() -> Self {
        Self {
            provider: provider(),
            empty_hints: Vec::new(),
        }
    }
}

impl Default for RecordingClientCertVerifier {
    fn default() -> Self {
        Self::new()
    }
}

impl ClientCertVerifier for RecordingClientCertVerifier {
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        // No CA, so no hints to give.
        &self.empty_hints
    }

    fn client_auth_mandatory(&self) -> bool {
        // A connection without a client certificate has no identity at all
        // and can never be authorized. Reject it during the handshake.
        true
    }

    fn verify_client_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        now: UnixTime,
    ) -> std::result::Result<ClientCertVerified, rustls::Error> {
        // We accept an unknown certificate here, and that is safe *only*
        // because of two things:
        //
        //   1. `verify_tls13_signature` below still proves the peer holds the
        //      matching private key, so the SPKI we extract after the
        //      handshake genuinely belongs to whoever is on the socket.
        //   2. The session layer treats such a peer as `Unauthenticated`. It
        //      may send HELLO and PAIR_REQUEST and nothing else, and only
        //      while a pairing window is open.
        //
        // If either of those is ever removed, this becomes an
        // accept-all-clients hole. See `session.rs`.
        validate_certificate_structure(end_entity, now)?;
        Ok(ClientCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        Err(rustls::Error::PeerIncompatible(
            rustls::PeerIncompatible::Tls12NotOffered,
        ))
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        supported_schemes()
    }
}

// ---------------------------------------------------------------------------
// Config builders
// ---------------------------------------------------------------------------

/// Server config: TLS 1.3 only, mandatory client certificates.
///
/// The certificate and its key arrive through a rustls *resolver* rather than
/// as PKCS#8 bytes. That is the entire portability change in this file: a
/// `CertifiedKey` holds an `Arc<dyn SigningKey>`, which a TPM, a Secure
/// Enclave or an Android Keystore can supply and which no hardware keystore
/// could ever export as bytes. Nothing else here moves — `TLS13_ONLY`, both
/// pinning verifiers, `verify_tls13_signature`, ALPN and
/// `send_tls13_tickets = 0` are untouched.
pub fn server_config<I: IdentityProvider + ?Sized>(
    identity: &I,
) -> Result<Arc<rustls::ServerConfig>> {
    let mut config = rustls::ServerConfig::builder_with_provider(provider())
        .with_protocol_versions(TLS13_ONLY)
        .map_err(Error::Tls)?
        .with_client_cert_verifier(Arc::new(RecordingClientCertVerifier::new()))
        .with_cert_resolver(Arc::new(rustls::sign::SingleCertAndKey::from(
            identity.certified_key(),
        )));

    // Both protocols of both identity profiles are offered on one listener,
    // canonical first (ADR-0020 §D4). Which one a connection is carrying —
    // and so which profile and which kind — is decided by ALPN during the
    // handshake and read back with [`negotiated_protocol`], so the listener
    // never has to guess from the first bytes. rustls selects by the server's
    // order only among values the client offered, and our clients offer
    // exactly one, so the order never picks a profile the client did not ask
    // for.
    config.alpn_protocols = SERVER_ALPN_PROTOCOLS.iter().map(|p| p.to_vec()).collect();
    // Session resumption is disabled: it would let a peer skip a full
    // handshake, and full handshakes are where our pinning check lives.
    // Handshakes happen rarely enough that the cost is irrelevant.
    config.send_tls13_tickets = 0;
    Ok(Arc::new(config))
}

/// The listener's ALPN list, in preference order: `pliwee/1`,
/// `pliwee-data/1`, `omnibridge/1`, `omnibridge-data/1` (ADR-0020 §D4).
pub const SERVER_ALPN_PROTOCOLS: [&[u8]; 4] = [
    crate::ALPN_PROTOCOL,
    crate::ALPN_DATA_PROTOCOL,
    crate::LEGACY_ALPN_PROTOCOL,
    crate::LEGACY_ALPN_DATA_PROTOCOL,
];

/// Client config that will accept exactly one server identity, for a control
/// session under `profile`.
///
/// The client offers **one** ALPN — the profile's — never both profiles'.
/// Offering both would let the server pick the profile, and a peer that is
/// discovered under one name must never be authenticated under another.
pub fn client_config<I: IdentityProvider + ?Sized>(
    identity: &I,
    expected_server: Fingerprint,
    profile: Profile,
) -> Result<Arc<rustls::ClientConfig>> {
    client_config_with_alpn(identity, expected_server, profile.control_alpn())
}

/// Client config for a bulk data stream under `profile`.
///
/// Identical to [`client_config`] in every security-relevant way — same
/// pinned verifier, same client certificate, same TLS 1.3-only version list.
/// The only difference is the ALPN identifier, which tells the listener what
/// kind of connection this is. A data stream is emphatically *not* a weaker
/// connection than a control session; it is the same connection carrying
/// different traffic. `profile` must be the profile of the control session
/// that issued the transfer: the listener refuses a stream whose profile
/// differs.
pub fn data_stream_client_config<I: IdentityProvider + ?Sized>(
    identity: &I,
    expected_server: Fingerprint,
    profile: Profile,
) -> Result<Arc<rustls::ClientConfig>> {
    client_config_with_alpn(identity, expected_server, profile.data_alpn())
}

fn client_config_with_alpn<I: IdentityProvider + ?Sized>(
    identity: &I,
    expected_server: Fingerprint,
    alpn: &[u8],
) -> Result<Arc<rustls::ClientConfig>> {
    let mut config = rustls::ClientConfig::builder_with_provider(provider())
        .with_protocol_versions(TLS13_ONLY)
        .map_err(Error::Tls)?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(PinnedServerCertVerifier::new(expected_server)))
        // Same seam as the server side: a resolver, not a private key. See
        // `server_config`.
        .with_client_cert_resolver(Arc::new(rustls::sign::SingleCertAndKey::from(
            identity.certified_key(),
        )));

    config.alpn_protocols = vec![alpn.to_vec()];
    Ok(Arc::new(config))
}

/// What kind of traffic a connection carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionKind {
    /// The control session: HELLO, pairing, capability messages.
    Control,
    /// A bulk data stream carrying one transfer's bytes.
    Data,
}

/// What a completed handshake turned out to be: which identity profile, and
/// which kind of connection. Both come from the one ALPN value negotiated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NegotiatedProtocol {
    pub profile: Profile,
    pub kind: ConnectionKind,
}

impl NegotiatedProtocol {
    /// Maps an ALPN value to *(profile, kind)*. Anything but the four known
    /// values is `None`.
    pub fn from_alpn(alpn: &[u8]) -> Option<Self> {
        Profile::ALL.into_iter().find_map(|profile| {
            let kind = if alpn == profile.control_alpn() {
                ConnectionKind::Control
            } else if alpn == profile.data_alpn() {
                ConnectionKind::Data
            } else {
                return None;
            };
            Some(Self { profile, kind })
        })
    }
}

/// Reads back which ALPN protocol the handshake selected.
///
/// A peer that negotiated no ALPN at all, or something unrecognised, gets
/// `None` and must be dropped. Guessing "probably control" from an absent
/// ALPN would hand an unknown client the handshake path by default, which is
/// exactly the wrong direction to fail in. Guessing a profile would be worse:
/// the profile decides which domain a proof is verified under.
pub fn negotiated_protocol(conn: &rustls::CommonState) -> Option<NegotiatedProtocol> {
    NegotiatedProtocol::from_alpn(conn.alpn_protocol()?)
}

/// Client side: requires that the server selected **exactly** the one ALPN
/// this client offered, for `profile` and `kind`.
///
/// rustls refuses a server that selects a protocol the client did not offer,
/// but it lets a server that selects *none* complete the handshake, leaving
/// the connection with no negotiated profile. That profile must never be
/// assumed: it decides which domain a proof is computed under. So every
/// client checks after the handshake and closes on anything else, exactly as
/// Android's `TlsFactory.requireNegotiated` does. There is no fallback to
/// another profile and no retry under one.
pub fn require_negotiated(
    conn: &rustls::CommonState,
    profile: Profile,
    kind: ConnectionKind,
) -> Result<()> {
    let expected = NegotiatedProtocol { profile, kind };
    if negotiated_protocol(conn) == Some(expected) {
        Ok(())
    } else {
        Err(Error::Protocol(
            "the server did not negotiate the one ALPN this client offered",
        ))
    }
}

/// Extracts the peer's pinned-identity fingerprint from a completed handshake.
///
/// Returns an error if the peer sent no certificate. That should be
/// impossible on the server side (client auth is mandatory) and on the client
/// side (a server always sends one), so it is treated as a hard failure
/// rather than an anonymous-peer fallback.
pub fn peer_fingerprint(conn: &rustls::CommonState) -> Result<Fingerprint> {
    let certs = conn
        .peer_certificates()
        .ok_or(Error::Certificate("peer presented no certificate"))?;
    let leaf = certs
        .first()
        .ok_or(Error::Certificate("empty peer certificate chain"))?;
    Fingerprint::from_certificate_der(leaf)
}
