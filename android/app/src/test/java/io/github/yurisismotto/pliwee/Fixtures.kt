package io.github.yurisismotto.pliwee

import java.io.ByteArrayInputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

/**
 * The shared cross-language fixtures in `protocol/testdata`.
 *
 * These are real certificates emitted by the real desktop identity code
 * (`cargo run -p pliwee-core --example gen_test_vectors`), not something
 * hand-built for the test. `identity-a` plays the paired computer;
 * `identity-b` plays a different machine whose certificate is perfectly valid
 * and simply is not the pinned one.
 *
 * `desktop/core/tests/identity_and_store.rs` asserts the same fingerprints
 * against the same two files. The files are frozen (ADR-0020 D10);
 * `gen_test_vectors` refuses to overwrite them.
 */
object Fixtures {

    /** Must equal `FIXTURE_A_FINGERPRINT` in the Rust suite. */
    const val IDENTITY_A_FINGERPRINT =
        "1b759fb323a5c5260a0f762692d1f42458c5102f68e1e271699f1fa694769821"

    /** Must equal `FIXTURE_B_FINGERPRINT` in the Rust suite. */
    const val IDENTITY_B_FINGERPRINT =
        "f6b9ec37af6fa7cde4ea5377399c067cdfcb09def4d2ac701e11c95521d8efb7"

    /**
     * SHA-256 of the fixture files themselves. The fixtures are **frozen**
     * (ADR-0020 D10): never regenerated to remove the historical `anyflow:`
     * subject they carry. The same digests are pinned by
     * `desktop/core/tests/frozen_vectors.rs` and recorded in the Wave 5
     * report.
     */
    const val IDENTITY_A_DER_SHA256 =
        "cdb976416b52d73b00faeadcb1890e35515061527559cd0643e451b7c46baa41"
    const val IDENTITY_B_DER_SHA256 =
        "a3b55bf1b9db309585eec391efb5de42ca0cd3c4810ba03d4cc1986ce26561a8"

    fun certificateDer(name: String): ByteArray =
        checkNotNull(Fixtures::class.java.classLoader?.getResourceAsStream(name)) {
            "missing fixture $name; regenerate protocol/testdata"
        }.use { it.readBytes() }

    fun certificate(name: String): X509Certificate =
        CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(certificateDer(name))) as X509Certificate

    fun identityA(): X509Certificate = certificate("identity-a.der")

    fun identityB(): X509Certificate = certificate("identity-b.der")
}
