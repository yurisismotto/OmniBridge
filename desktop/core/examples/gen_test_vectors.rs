//! Regenerates the shared cross-language test fixtures in `protocol/testdata`.
//!
//! Run with:
//!
//! ```text
//! cargo run -p pliwee-core --example gen_test_vectors
//! ```
//!
//! The fixtures are real certificates produced by the real desktop identity
//! code, so the Kotlin tests exercise the same X.509 the daemon would actually
//! present rather than something hand-rolled for the test. Both sides then
//! assert the same SPKI fingerprints, which makes the fingerprint construction
//! a checked cross-language contract instead of a convention.
//!
//! # The committed fixtures are frozen
//!
//! `identity-a.der` and `identity-b.der` (subject `CN=anyflow:…`) and the
//! SPKI known-answer values derived from them in both languages are frozen by
//! ADR-0020 D10: they are never regenerated to remove a historical name, and
//! `wire_identity`-style digests of them are pinned in
//! `desktop/core/tests/frozen_vectors.rs`. This program therefore refuses to
//! overwrite an existing fixture. New identity vectors, if ever wanted, are
//! new files: pass a directory that does not already hold them.
//!
//! ```text
//! cargo run -p pliwee-core --example gen_test_vectors -- <output-dir>
//! ```

use std::path::PathBuf;

use pliwee_core::identity::LocalIdentity;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../protocol/testdata")
        });
    std::fs::create_dir_all(&out)?;

    // Checked for both files before either is written, so a refusal leaves
    // nothing half-regenerated.
    for name in ["a", "b"] {
        let path = out.join(format!("identity-{name}.der"));
        if std::fs::symlink_metadata(&path).is_ok() {
            return Err(format!(
                "refusing to overwrite {}: the identity fixtures are frozen (ADR-0020 D10); \
                 write new vectors to a new directory",
                path.display()
            )
            .into());
        }
    }

    // "a" plays the paired desktop; "b" plays a different machine presenting a
    // perfectly valid certificate that simply is not the pinned one.
    for name in ["a", "b"] {
        let identity = LocalIdentity::generate("fixture", pliwee_proto::v1::Platform::Linux)?;
        let path = out.join(format!("identity-{name}.der"));
        // `create_new`: even a file that appeared since the check above is
        // never overwritten.
        use std::io::Write;
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)?
            .write_all(identity.certificate_der().as_ref())?;
        println!(
            "{}\n  device_id   {}\n  fingerprint {}",
            path.display(),
            identity.device_id(),
            identity.fingerprint().to_hex()
        );
    }
    Ok(())
}
