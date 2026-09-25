//! G5 — one connection, one identity (ADR-0020 §D4; plan §4 rows X1–X3).
//!
//! The real daemon listener, the real session code and the real `files.v1`
//! acceptor, driven by a client that deliberately mixes the two identity
//! profiles in ways a correct client never would. Every attempt must fail,
//! and fail **for the stated reason**: each test captures the daemon's own
//! log and finds the line that names this connection or this transfer before
//! it concludes anything.
//!
//! # Its own binary, deliberately
//!
//! Every test here installs a `tracing` capture subscriber, for the reason
//! `file_log_privacy.rs` records in its header: a capture that shares a binary
//! with subscriber-less tests can record nothing, intermittently, and a
//! refusal "observed" in an empty log proves nothing. **Keep it that way.**
//!
//! Each test also proves its refusal was about the profile and nothing else:
//! the same window, the same challenge, then succeeds under the connection's
//! own profile.

mod common;

use std::io;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::*;
use pliwee_capability_files::auth::{compute_stream_mac, StreamChallenge};
use pliwee_capability_files::stream;
use pliwee_capability_files::transfer::{TransferId, TransferState};
use pliwee_core::error::PairingError;
use pliwee_core::{framing, pairing, Profile};
use pliwee_proto::v1;
use tracing_subscriber::fmt::MakeWriter;

const GRACE: Duration = Duration::from_secs(20);

#[derive(Clone, Default)]
struct Captured(Arc<Mutex<Vec<u8>>>);

impl io::Write for Captured {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.lock().expect("not poisoned").extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl<'a> MakeWriter<'a> for Captured {
    type Writer = Captured;
    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}

impl Captured {
    fn text(&self) -> String {
        String::from_utf8_lossy(&self.0.lock().expect("not poisoned")).into_owned()
    }

    /// The capture must be real before an absence or a refusal in it means
    /// anything: non-empty, and holding daemon events.
    fn assert_live(&self) -> String {
        let text = self.text();
        assert!(
            !text.is_empty(),
            "nothing was captured, so this test proves nothing"
        );
        assert!(
            text.contains("pliwee_"),
            "no daemon event reached the capture, so this test proves nothing:\n{text}"
        );
        text
    }
}

fn subscriber(captured: &Captured) -> impl tracing::Subscriber + Send + Sync {
    tracing_subscriber::fmt()
        .with_writer(captured.clone())
        .with_max_level(tracing::Level::TRACE)
        .with_ansi(false)
        .finish()
}

/// Sends a hand-built envelope. Sequence numbers continue from `sequence`.
async fn send(
    tls: &mut tokio_rustls::client::TlsStream<tokio::net::TcpStream>,
    sequence: u64,
    body: v1::envelope::Body,
) {
    let mut message_id = vec![0u8; 16];
    message_id[..8].copy_from_slice(&sequence.to_be_bytes());
    message_id[15] = 0x5e;
    let envelope = v1::Envelope {
        protocol_version: pliwee_core::session::PROTOCOL_VERSION_MAX,
        message_id,
        sequence,
        timestamp_unix_ms: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_millis() as i64,
        correlation_id: Vec::new(),
        body: Some(body),
    };
    framing::write_envelope(tls, &envelope)
        .await
        .expect("write envelope");
}

/// X1 / X2: a pairing proof computed under the *other* profile's domain,
/// presented on a connection whose ALPN fixed this profile, is rejected by
/// the real daemon. Run for both directions.
#[tokio::test]
async fn a_pairing_proof_from_the_other_profile_is_rejected_by_the_daemon() {
    let captured = Captured::default();
    let _guard = tracing::subscriber::set_default(subscriber(&captured));

    for connection in Profile::ALL {
        let foreign = other_profile(connection);
        let server = TestServer::start().await;
        let phone = TestClient::new("phone");
        let token = server.open_pairing(Duration::from_secs(60)).await;

        // A connection that negotiated `connection`, and nothing else.
        let mut tls = phone
            .tls_connect_with_profile(server.addr, server.fingerprint, connection)
            .await
            .expect("tls");
        let anchor = tls
            .get_ref()
            .0
            .local_addr()
            .expect("local addr")
            .to_string();
        assert_eq!(
            pliwee_core::tls::negotiated_protocol(tls.get_ref().1).map(|p| p.profile),
            Some(connection)
        );

        send(
            &mut tls,
            1,
            v1::envelope::Body::Hello(v1::Hello {
                device: Some(phone.host.local_device_info()),
                min_protocol_version: pliwee_core::session::PROTOCOL_VERSION_MIN,
                max_protocol_version: pliwee_core::session::PROTOCOL_VERSION_MAX,
                capabilities: Vec::new(),
            }),
        )
        .await;
        let ack = match framing::read_envelope(&mut tls).await.expect("ack").body {
            Some(v1::envelope::Body::HelloAck(a)) => a,
            other => panic!("expected HELLO_ACK, got {other:?}"),
        };
        assert_eq!(ack.status, v1::HelloStatus::PairingRequired as i32);
        assert_eq!(ack.pairing_nonce.len(), pairing::NONCE_LEN);

        // The token is right, the fingerprints are right, the nonce is
        // right. Only the domain belongs to the other profile.
        let proof = pairing::compute_proof(
            foreign,
            &token,
            &server.fingerprint,
            &phone.fingerprint,
            &ack.pairing_nonce,
        );
        send(
            &mut tls,
            2,
            v1::envelope::Body::PairRequest(v1::PairRequest {
                proof: proof.to_vec(),
            }),
        )
        .await;
        let response = match framing::read_envelope(&mut tls).await.expect("resp").body {
            Some(v1::envelope::Body::PairResponse(r)) => r,
            other => panic!("expected PAIR_RESPONSE, got {other:?}"),
        };
        assert_eq!(
            response.status,
            v1::PairStatus::Rejected as i32,
            "{connection} connection, {foreign} proof"
        );
        assert!(response.confirmation.is_empty());
        drop(tls);

        // Two observations around the refusal: not trusted before, not
        // trusted after — the proof created nothing.
        wait_until(GRACE, || async {
            captured.text().contains(&format!("peer_addr={anchor}"))
        })
        .await;
        let text = captured.assert_live();
        let line = text
            .lines()
            .find(|l| l.contains(&format!("peer_addr={anchor}")) && l.contains("connection ended"))
            .unwrap_or_else(|| panic!("no daemon line for connection {anchor}:\n{text}"));
        let reason = pliwee_core::Error::Pairing(PairingError::BadProof).to_string();
        assert!(
            line.contains(&reason),
            "connection {anchor} ended for another reason than a bad proof: {line}"
        );
        println!("EVIDENCE X1/X2 connection={connection} proof={foreign}: {line}");
        assert!(server
            .state
            .store
            .lock()
            .await
            .trusted_peer(&phone.fingerprint)
            .is_none());

        // The same window, the same token: under the connection's own
        // profile the pairing goes through. The refusal was the domain.
        let session = phone
            .connect_with_profile(server.addr, server.fingerprint, Some(&token), connection)
            .await
            .expect("the connection's own profile pairs");
        assert!(server
            .state
            .store
            .lock()
            .await
            .trusted_peer(&phone.fingerprint)
            .is_some());
        session.close().await;
    }
}

/// X3: a data stream that negotiated the other profile is refused before a
/// single byte of the file moves — whichever domain its MAC was made under —
/// and the transfer stays intact for a stream under its own profile.
#[tokio::test]
async fn a_data_stream_from_the_other_profile_is_refused_before_any_byte() {
    let captured = Captured::default();
    let _guard = tracing::subscriber::set_default(subscriber(&captured));

    for session_profile in Profile::ALL {
        let foreign = other_profile(session_profile);
        let server = TestServer::start().await;
        let (phone, phone_captured) = TestClient::new_raw("phone");

        let token = server.open_pairing(Duration::from_secs(30)).await;
        phone
            .connect_with_profile(
                server.addr,
                server.fingerprint,
                Some(&token),
                session_profile,
            )
            .await
            .expect("pairing")
            .close()
            .await;
        server.set_grant(phone.fingerprint, "files.v1", true).await;
        let session = phone
            .connect_with_profile(server.addr, server.fingerprint, None, session_profile)
            .await
            .expect("control session");
        assert_eq!(session.handle.profile(), session_profile);

        let id = TransferId::from_bytes(&[0x5a; 16]).expect("id");
        let payload = b"one connection, one identity".to_vec();
        send_files_control(
            &session,
            pb::file_control::Body::Offer(pb::FileOffer {
                transfer_id: id.to_vec(),
                filename: "profile.txt".into(),
                size_bytes: payload.len() as u64,
                mime_type: String::new(),
                sha256: sha256_of(&payload).to_vec(),
                timestamp_unix_ms: 0,
            }),
        )
        .await;
        let accept = match phone_captured.next_control(GRACE).await.body {
            Some(pb::file_control::Body::Accept(a)) => a,
            other => panic!("expected an acceptance, got {other:?}"),
        };
        let challenge = StreamChallenge::from_bytes(&accept.stream_challenge).expect("challenge");

        // Both MACs a confused or hostile dialer could present on a stream
        // under the other profile: one under that profile's domain, one under
        // the session's own. Neither may be translated or accepted.
        for mac_profile in [foreign, session_profile] {
            let mac = compute_stream_mac(
                mac_profile,
                &challenge,
                &server.fingerprint,
                &phone.fingerprint,
                &id,
            );
            let mut io = open_data_stream_with_profile(
                server.addr,
                &phone.identity,
                server.fingerprint,
                foreign,
            )
            .await
            .expect("TLS under the other profile");
            stream::write_frame(
                &mut io,
                &pb::DataStreamAuth {
                    protocol_version: pliwee_core::session::PROTOCOL_VERSION_MAX,
                    transfer_id: id.to_vec(),
                    mac: mac.to_vec(),
                },
            )
            .await
            .expect("write");
            let ready: pb::DataStreamReady = stream::read_frame(&mut io).await.expect("reply");
            assert_eq!(
                ready.status(),
                pb::DataStreamStatus::Rejected,
                "{session_profile} session, {foreign} stream, {mac_profile} MAC"
            );
            // Refused before any byte: no stored file (only the acceptor's
            // own empty partial may exist), and no byte counted.
            assert!(!server.downloads.join("profile.txt").exists());
            let snapshot = server.transfers.snapshot_one(id).await.expect("transfer");
            assert_eq!(snapshot.bytes_transferred, 0);
            assert_eq!(snapshot.state, TransferState::Transferring);
        }

        // Anchored on the transfer id the daemon itself logged: the refusal
        // happened, twice, and for the profile mismatch.
        let text = captured.assert_live();
        // The capture spans every loop iteration, so the anchor is this
        // transfer id *and* this iteration's phone, with the two profiles
        // the daemon says it compared.
        let anchor = id.to_string();
        let peer = format!("peer={}", phone.fingerprint.to_display_short());
        let profiles = format!("session_profile={session_profile} stream_profile={foreign}");
        let refusals = text
            .lines()
            .filter(|l| {
                l.contains(&format!("transfer={anchor}"))
                    && l.contains(&peer)
                    && l.contains(&profiles)
                    && l.contains(
                        "refused a data stream whose profile differs from its control session",
                    )
            })
            .count();
        for l in text.lines().filter(|l| {
            l.contains(&format!("transfer={anchor}")) && l.contains(&peer) && l.contains(&profiles)
        }) {
            println!("EVIDENCE X3 session={session_profile} stream={foreign}: {l}");
        }
        assert_eq!(
            refusals, 2,
            "expected exactly two profile refusals for {anchor}:\n{text}"
        );

        // The challenge was not consumed: the stream under the session's own
        // profile, with the session's own MAC, completes the transfer.
        let mac = compute_stream_mac(
            session_profile,
            &challenge,
            &server.fingerprint,
            &phone.fingerprint,
            &id,
        );
        let mut io = open_data_stream_with_profile(
            server.addr,
            &phone.identity,
            server.fingerprint,
            session_profile,
        )
        .await
        .expect("TLS under the session's profile");
        stream::write_frame(
            &mut io,
            &pb::DataStreamAuth {
                protocol_version: pliwee_core::session::PROTOCOL_VERSION_MAX,
                transfer_id: id.to_vec(),
                mac: mac.to_vec(),
            },
        )
        .await
        .expect("write");
        let ready: pb::DataStreamReady = stream::read_frame(&mut io).await.expect("reply");
        assert_eq!(ready.status(), pb::DataStreamStatus::Ready);
        use tokio::io::AsyncWriteExt;
        io.write_all(&payload).await.expect("bytes");
        io.shutdown().await.expect("shutdown");

        let snapshot = wait_for_terminal(&server.transfers, id, GRACE).await;
        assert_eq!(snapshot.state, TransferState::Completed);
        assert_eq!(
            std::fs::read(server.downloads.join("profile.txt")).expect("stored"),
            payload
        );
        session.close().await;
    }
}
