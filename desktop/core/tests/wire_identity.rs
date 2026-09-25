//! The wire identities, pinned as literals.
//!
//! # Why literals, and why here
//!
//! Every value below is a **cross-implementation contract**: the Android app
//! carries the same string, and a peer that disagrees about any one of them
//! does not fail gracefully. A wrong ALPN fails the TLS handshake, a wrong
//! service type makes the daemon invisible to discovery, a wrong QR prefix
//! rejects a valid pairing code, and a wrong domain separator produces a
//! proof that verifies nowhere — all of which look like "the network is
//! broken" rather than "somebody renamed a constant".
//!
//! Asserting `SERVICE_TYPE == SERVICE_TYPE` would prove nothing, so these
//! tests spell the expected bytes out. The mirror image of this file is
//! `android/app/src/test/.../WireIdentityTest.kt`, which spells out the same
//! strings from the Kotlin side. Changing an identity means changing both, in
//! the same commit — which is exactly the reviewable event the OmniBridge
//! rename (and the AnyFlow rename before it, ADR-0011) needed and did not
//! have.
//!
//! # Two profiles (ADR-0020 §D4)
//!
//! Pliwee emits its canonical identifiers and, through the v1.x line, accepts
//! the OmniBridge ones as a legacy profile. **Both** sets are pinned here, side
//! by side, so neither can drift: removing the legacy profile is a breaking
//! change that needs its own ADR, and this file is where it would show.
//!
//! The OmniBridge values were recorded in ADR-0018; the Pliwee values in
//! ADR-0020.

use pliwee_core::identity::LocalIdentity;
use pliwee_core::qr::{LEGACY_QR_SCHEME, QR_SCHEME};
use pliwee_core::tls::{self, ConnectionKind, NegotiatedProtocol, SERVER_ALPN_PROTOCOLS};
use pliwee_core::{
    Fingerprint, Profile, ALPN_DATA_PROTOCOL, ALPN_PROTOCOL, LEGACY_ALPN_DATA_PROTOCOL,
    LEGACY_ALPN_PROTOCOL, LEGACY_SERVICE_TYPE, SERVICE_TYPE,
};

// -- canonical profile -------------------------------------------------------

#[test]
fn control_alpn_is_pliwee_1() {
    assert_eq!(ALPN_PROTOCOL, b"pliwee/1");
    assert_eq!(Profile::Pliwee.control_alpn(), b"pliwee/1");
}

#[test]
fn data_alpn_is_pliwee_data_1() {
    assert_eq!(ALPN_DATA_PROTOCOL, b"pliwee-data/1");
    assert_eq!(Profile::Pliwee.data_alpn(), b"pliwee-data/1");
}

#[test]
fn mdns_service_type_is_pliwee_tcp() {
    assert_eq!(SERVICE_TYPE, "_pliwee._tcp.local.");
    assert_eq!(Profile::Pliwee.service_type(), "_pliwee._tcp.local.");
}

#[test]
fn qr_scheme_is_pliwee1() {
    assert_eq!(QR_SCHEME, "pliwee1");
    assert_eq!(Profile::Pliwee.qr_scheme(), "pliwee1");
}

#[test]
fn pliwee_pairing_domains() {
    assert_eq!(
        Profile::Pliwee.pairing_proof_domain(),
        b"pliwee/pairing-proof/v1"
    );
    assert_eq!(
        Profile::Pliwee.pairing_confirm_domain(),
        b"pliwee/pairing-confirm/v1"
    );
}

// -- legacy profile ----------------------------------------------------------

#[test]
fn legacy_control_alpn_is_omnibridge_1() {
    assert_eq!(LEGACY_ALPN_PROTOCOL, b"omnibridge/1");
    assert_eq!(Profile::OmniBridge.control_alpn(), b"omnibridge/1");
}

#[test]
fn legacy_data_alpn_is_omnibridge_data_1() {
    assert_eq!(LEGACY_ALPN_DATA_PROTOCOL, b"omnibridge-data/1");
    assert_eq!(Profile::OmniBridge.data_alpn(), b"omnibridge-data/1");
}

#[test]
fn legacy_mdns_service_type_is_omnibridge_tcp() {
    assert_eq!(LEGACY_SERVICE_TYPE, "_omnibridge._tcp.local.");
    assert_eq!(
        Profile::OmniBridge.service_type(),
        "_omnibridge._tcp.local."
    );
}

#[test]
fn legacy_qr_scheme_is_omnibridge1() {
    assert_eq!(LEGACY_QR_SCHEME, "omnibridge1");
    assert_eq!(Profile::OmniBridge.qr_scheme(), "omnibridge1");
}

#[test]
fn legacy_pairing_domains() {
    assert_eq!(
        Profile::OmniBridge.pairing_proof_domain(),
        b"omnibridge/pairing-proof/v1"
    );
    assert_eq!(
        Profile::OmniBridge.pairing_confirm_domain(),
        b"omnibridge/pairing-confirm/v1"
    );
}

// -- the rules between them --------------------------------------------------

#[test]
fn the_four_alpn_identifiers_are_distinct() {
    // The listener decides which connection it just accepted — profile and
    // kind — from this value alone, before reading an application byte.
    for (i, a) in SERVER_ALPN_PROTOCOLS.iter().enumerate() {
        for b in &SERVER_ALPN_PROTOCOLS[i + 1..] {
            assert_ne!(a, b);
        }
    }
}

#[test]
fn the_listener_offers_canonical_first_in_the_approved_order() {
    let offered: Vec<&[u8]> = SERVER_ALPN_PROTOCOLS.to_vec();
    assert_eq!(
        offered,
        vec![
            &b"pliwee/1"[..],
            &b"pliwee-data/1"[..],
            &b"omnibridge/1"[..],
            &b"omnibridge-data/1"[..],
        ]
    );
}

/// The profile selection table: each ALPN → exactly one *(profile, kind)*.
#[test]
fn each_alpn_selects_exactly_one_profile_and_kind() {
    let table: [(&[u8], Profile, ConnectionKind); 4] = [
        (b"pliwee/1", Profile::Pliwee, ConnectionKind::Control),
        (b"pliwee-data/1", Profile::Pliwee, ConnectionKind::Data),
        (
            b"omnibridge/1",
            Profile::OmniBridge,
            ConnectionKind::Control,
        ),
        (
            b"omnibridge-data/1",
            Profile::OmniBridge,
            ConnectionKind::Data,
        ),
    ];
    for (alpn, profile, kind) in table {
        assert_eq!(
            NegotiatedProtocol::from_alpn(alpn),
            Some(NegotiatedProtocol { profile, kind }),
            "{}",
            String::from_utf8_lossy(alpn)
        );
    }
    for unknown in [
        &b""[..],
        b"anyflow/1",
        b"anyflow-data/1",
        b"pliwee/2",
        b"omnibridge/2",
        b"h2",
    ] {
        assert_eq!(NegotiatedProtocol::from_alpn(unknown), None);
    }
}

/// X4: a client offers exactly one ALPN — its profile's — and never both
/// profiles'. Checked on the real configs production builds.
#[test]
fn a_client_config_offers_exactly_one_alpn() {
    let identity =
        LocalIdentity::generate("wire-test", pliwee_proto::v1::Platform::Linux).expect("identity");
    let pinned = Fingerprint::from_hex(&"11".repeat(32)).expect("fp");
    for profile in Profile::ALL {
        let control = tls::client_config(&identity, pinned, profile).expect("control config");
        assert_eq!(
            control.alpn_protocols,
            vec![profile.control_alpn().to_vec()]
        );
        let data = tls::data_stream_client_config(&identity, pinned, profile).expect("data config");
        assert_eq!(data.alpn_protocols, vec![profile.data_alpn().to_vec()]);
    }
}

#[test]
fn profile_names_round_trip_and_nothing_else_parses() {
    for profile in Profile::ALL {
        assert_eq!(Profile::from_name(profile.as_str()), Some(profile));
    }
    assert_eq!(Profile::Pliwee.as_str(), "pliwee");
    assert_eq!(Profile::OmniBridge.as_str(), "omnibridge");
    for bad in ["", "anyflow", "Pliwee", "both"] {
        assert_eq!(Profile::from_name(bad), None);
    }
}

#[test]
fn no_pre_rename_identity_survives() {
    // The point of a clean pre-v1 rename is that a grep for the dead name is
    // unambiguously a bug (ADR-0011 "Consequences", carried into ADR-0018 and
    // ADR-0020). Neither live profile may carry one.
    for dead in ["anyflow", "fedroid"] {
        for profile in Profile::ALL {
            assert!(!String::from_utf8_lossy(profile.control_alpn()).contains(dead));
            assert!(!String::from_utf8_lossy(profile.data_alpn()).contains(dead));
            assert!(!profile.service_type().contains(dead));
            assert!(!profile.qr_scheme().contains(dead));
            assert!(!String::from_utf8_lossy(profile.pairing_proof_domain()).contains(dead));
            assert!(!String::from_utf8_lossy(profile.pairing_confirm_domain()).contains(dead));
        }
    }
}

// -- negotiation over a real handshake ---------------------------------------

/// Runs a real TLS 1.3 handshake over loopback between the production server
/// config and a client config for `profile`, and returns what each side read
/// back from the handshake.
async fn negotiate(
    client_config: std::sync::Arc<rustls::ClientConfig>,
    server_config: std::sync::Arc<rustls::ServerConfig>,
) -> (Option<NegotiatedProtocol>, Option<NegotiatedProtocol>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind");
    let addr = listener.local_addr().expect("addr");
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.expect("accept");
        let tls = tokio_rustls::TlsAcceptor::from(server_config)
            .accept(stream)
            .await
            .ok()?;
        let (_, conn) = tls.get_ref();
        tls::negotiated_protocol(conn)
    });
    let stream = tokio::net::TcpStream::connect(addr).await.expect("connect");
    let name = rustls_pki_types::ServerName::try_from("pliwee.invalid").expect("name");
    let client = tokio_rustls::TlsConnector::from(client_config)
        .connect(name, stream)
        .await
        .ok()
        .and_then(|tls| tls::negotiated_protocol(tls.get_ref().1));
    (server.await.expect("join"), client)
}

/// Each client negotiates its own profile and kind with the four-value
/// listener; the listener's canonical preference never overrides the one ALPN
/// a client offered.
#[tokio::test]
async fn a_real_handshake_negotiates_the_offered_profile_and_nothing_else() {
    let server = LocalIdentity::generate("srv", pliwee_proto::v1::Platform::Linux).expect("srv");
    let client = LocalIdentity::generate("cli", pliwee_proto::v1::Platform::Android).expect("cli");
    for profile in Profile::ALL {
        for kind in [ConnectionKind::Control, ConnectionKind::Data] {
            let config = match kind {
                ConnectionKind::Control => {
                    tls::client_config(&client, server.fingerprint(), profile)
                }
                ConnectionKind::Data => {
                    tls::data_stream_client_config(&client, server.fingerprint(), profile)
                }
            }
            .expect("client config");
            let (seen_by_server, seen_by_client) =
                negotiate(config, tls::server_config(&server).expect("server config")).await;
            let expected = Some(NegotiatedProtocol { profile, kind });
            assert_eq!(seen_by_server, expected, "{profile} {kind:?}");
            assert_eq!(seen_by_client, expected, "{profile} {kind:?}");
        }
    }
}

/// A server that speaks only the legacy profile — the shape of an OmniBridge
/// 1.0.0 daemon — refuses a canonical client at the handshake. There is no
/// quiet downgrade: the Pliwee client must choose the legacy profile itself.
#[tokio::test]
async fn a_legacy_only_server_refuses_a_canonical_client() {
    let server = LocalIdentity::generate("srv", pliwee_proto::v1::Platform::Linux).expect("srv");
    let client = LocalIdentity::generate("cli", pliwee_proto::v1::Platform::Android).expect("cli");
    let legacy_only = {
        let mut config = (*tls::server_config(&server).expect("server config")).clone();
        config.alpn_protocols = vec![
            LEGACY_ALPN_PROTOCOL.to_vec(),
            LEGACY_ALPN_DATA_PROTOCOL.to_vec(),
        ];
        std::sync::Arc::new(config)
    };

    let canonical = tls::client_config(&client, server.fingerprint(), Profile::Pliwee).expect("c");
    assert_eq!(
        negotiate(canonical, legacy_only.clone()).await,
        (None, None)
    );

    let legacy = tls::client_config(&client, server.fingerprint(), Profile::OmniBridge).expect("c");
    let expected = Some(NegotiatedProtocol {
        profile: Profile::OmniBridge,
        kind: ConnectionKind::Control,
    });
    assert_eq!(negotiate(legacy, legacy_only).await, (expected, expected));
}

/// A server that selects **no** ALPN completes the handshake in rustls: the
/// client is left with no negotiated profile. `require_negotiated` is the
/// client's check after the handshake (the mirror of Android's
/// `TlsFactory.requireNegotiated`), and it must refuse that connection rather
/// than assume a profile. Against the real listener the same check passes.
#[tokio::test]
async fn a_client_refuses_a_server_that_negotiated_no_alpn() {
    let server = LocalIdentity::generate("srv", pliwee_proto::v1::Platform::Linux).expect("srv");
    let client = LocalIdentity::generate("cli", pliwee_proto::v1::Platform::Android).expect("cli");
    let no_alpn = {
        let mut config = (*tls::server_config(&server).expect("server config")).clone();
        config.alpn_protocols.clear();
        std::sync::Arc::new(config)
    };

    for profile in Profile::ALL {
        for kind in [ConnectionKind::Control, ConnectionKind::Data] {
            let config = match kind {
                ConnectionKind::Control => {
                    tls::client_config(&client, server.fingerprint(), profile)
                }
                ConnectionKind::Data => {
                    tls::data_stream_client_config(&client, server.fingerprint(), profile)
                }
            }
            .expect("client config");

            for (server_config, should_pass) in [
                (no_alpn.clone(), false),
                (tls::server_config(&server).expect("server config"), true),
            ] {
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
                    .await
                    .expect("bind");
                let addr = listener.local_addr().expect("addr");
                let accept = tokio::spawn(async move {
                    let (stream, _) = listener.accept().await.expect("accept");
                    tokio_rustls::TlsAcceptor::from(server_config)
                        .accept(stream)
                        .await
                        .map(|_| ())
                });
                let stream = tokio::net::TcpStream::connect(addr).await.expect("connect");
                let name = rustls_pki_types::ServerName::try_from("pliwee.invalid").expect("name");
                // The handshake itself succeeds in both cases: that is the
                // gap this check closes.
                let tls = tokio_rustls::TlsConnector::from(config.clone())
                    .connect(name, stream)
                    .await
                    .expect("rustls completes the handshake");
                accept.await.expect("join").expect("server handshake");
                let verdict = tls::require_negotiated(tls.get_ref().1, profile, kind);
                assert_eq!(
                    verdict.is_ok(),
                    should_pass,
                    "{profile} {kind:?}, server ALPN {}: {verdict:?}",
                    if should_pass { "offered" } else { "none" }
                );
                // Right profile, wrong kind: refused as well.
                let other = match kind {
                    ConnectionKind::Control => ConnectionKind::Data,
                    ConnectionKind::Data => ConnectionKind::Control,
                };
                assert!(tls::require_negotiated(tls.get_ref().1, profile, other).is_err());
            }
        }
    }
}
