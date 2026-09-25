//! The frozen cross-language identity vectors (ADR-0020 D10).
//!
//! `protocol/testdata/identity-a.der` and `identity-b.der` — subject
//! `CN=anyflow:…`, from before two renames — and the SPKI known-answer values
//! derived from them in both languages are frozen. They are not regenerated
//! to remove a historical name. The four SPKI values stay pinned where they
//! always were (`identity_and_store.rs`, `Fixtures.kt`); this test pins the
//! files themselves, byte for byte, by SHA-256.
//!
//! The digests were measured on the committed blobs (`git show
//! HEAD:protocol/testdata/identity-{a,b}.der | sha256sum`, base `b7a8789`) and
//! are recorded in `docs/reports/branding/PLIWEE-WAVE-5-PROTOCOL-DISCOVERY-CRYPTO.md`.
//! A mismatch here means a frozen vector was regenerated or edited, which D10
//! forbids: new identity vectors, if ever wanted, are new files.

use sha2::{Digest, Sha256};

fn fixture(name: &str) -> Vec<u8> {
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../protocol/testdata")
        .join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("missing fixture {}: {e}", path.display()))
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[test]
fn identity_a_der_is_byte_identical_to_the_frozen_vector() {
    let der = fixture("identity-a.der");
    assert!(!der.is_empty(), "an empty fixture proves nothing");
    assert_eq!(
        sha256_hex(&der),
        "cdb976416b52d73b00faeadcb1890e35515061527559cd0643e451b7c46baa41"
    );
}

#[test]
fn identity_b_der_is_byte_identical_to_the_frozen_vector() {
    let der = fixture("identity-b.der");
    assert!(!der.is_empty(), "an empty fixture proves nothing");
    assert_eq!(
        sha256_hex(&der),
        "a3b55bf1b9db309585eec391efb5de42ca0cd3c4810ba03d4cc1986ce26561a8"
    );
}

/// The frozen files still carry their historical subject. If this ever
/// reads `pliwee:` or `omnibridge:`, someone regenerated them.
#[test]
fn the_frozen_vectors_keep_their_historical_subject() {
    for name in ["identity-a.der", "identity-b.der"] {
        let der = fixture(name);
        let (_, cert) = x509_parser::parse_x509_certificate(&der).expect("x509");
        let cn: Vec<&str> = cert
            .subject()
            .iter_common_name()
            .map(|a| a.as_str().expect("utf8 CN"))
            .collect();
        assert_eq!(cn.len(), 1, "{name}");
        assert!(cn[0].starts_with("anyflow:"), "{name}: {}", cn[0]);
    }
}
