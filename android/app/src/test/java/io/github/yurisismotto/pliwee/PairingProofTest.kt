package io.github.yurisismotto.pliwee

import io.github.yurisismotto.pliwee.identity.Fingerprint
import io.github.yurisismotto.pliwee.net.WireProfile
import io.github.yurisismotto.pliwee.pairing.PairingProof
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pairing proof must be byte-identical to the Rust implementation, or
 * pairing simply fails. The known-answer test below is the cross-language
 * contract: if it changes, `desktop/core/src/pairing.rs` must change with it.
 *
 * Every property below holds under both wire profiles (ADR-0020 §D4): the
 * legacy one is live code through Pliwee v1.x and is held to the same bar.
 */
class PairingProofTest {

    private fun fp(byte: Int) = Fingerprint.fromHex("%02x".format(byte).repeat(32))!!
    private val token = ByteArray(20) { it.toByte() }
    private val nonce = ByteArray(32) { (it * 3).toByte() }

    @Test
    fun `proof is deterministic`() {
        for (profile in WireProfile.entries) {
            val a = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            val b = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            assertArrayEquals(a, b)
        }
    }

    @Test
    fun `proof is bound to the responder identity`() {
        for (profile in WireProfile.entries) {
            val honest = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            val elsewhere = PairingProof.compute(profile, token, fp(0xAA), fp(2), nonce)
            assertFalse(honest.contentEquals(elsewhere))
        }
    }

    @Test
    fun `proof is bound to the initiator identity`() {
        for (profile in WireProfile.entries) {
            val honest = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            val impostor = PairingProof.compute(profile, token, fp(1), fp(0xBB), nonce)
            assertFalse(honest.contentEquals(impostor))
        }
    }

    @Test
    fun `proof is bound to the nonce`() {
        for (profile in WireProfile.entries) {
            val a = PairingProof.compute(profile, token, fp(1), fp(2), ByteArray(32) { 1 })
            val b = PairingProof.compute(profile, token, fp(1), fp(2), ByteArray(32) { 2 })
            assertFalse(a.contentEquals(b))
        }
    }

    @Test
    fun `proof and confirmation are domain separated`() {
        for (profile in WireProfile.entries) {
            // Without separation, a captured proof could be replayed back as the
            // desktop's confirmation.
            val proof = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            val confirmation = PairingProof.computeConfirmation(profile, token, fp(1), fp(2), nonce)
            assertFalse(proof.contentEquals(confirmation))
        }
    }

    @Test
    fun `field boundaries cannot be shifted`() {
        for (profile in WireProfile.entries) {
            // Length prefixing must prevent moving bytes between adjacent fields.
            val a = PairingProof.compute(profile, token, fp(1), fp(2), byteArrayOf(1, 2, 3, 4))
            val b = PairingProof.compute(profile, token, fp(1), fp(2), byteArrayOf(1, 2, 3))
            assertFalse(a.contentEquals(b))
        }
    }

    @Test
    fun `verify rejects wrong lengths and wrong values`() {
        for (profile in WireProfile.entries) {
            val proof = PairingProof.compute(profile, token, fp(1), fp(2), nonce)
            assertTrue(PairingProof.verify(proof, proof.copyOf()))
            assertFalse(PairingProof.verify(proof, ByteArray(32)))
            assertFalse(PairingProof.verify(proof, ByteArray(0)))
            assertFalse(PairingProof.verify(proof, proof.copyOf(31)))
        }
    }

    // -----------------------------------------------------------------------
    // Cross-language known-answer vector
    // -----------------------------------------------------------------------
    //
    // The contract with `pliwee_core::pairing`. The identical vector lives in
    // `desktop/core/tests/pairing.rs`. If either side changes the domain
    // separator, the field order or the length prefixing, one of the two tests
    // fails instead of pairing mysteriously breaking on a real phone.
    //
    // The expected digests were derived independently of both implementations,
    // directly from the documented construction:
    //
    //   HMAC-SHA256(key = token,
    //               msg = domain || len32be(responder) || responder
    //                            || len32be(initiator) || initiator
    //                            || len32be(nonce)     || nonce)

    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    //
    // The legacy values are the ones committed before Wave 5, byte for byte:
    // they now test live legacy-profile code (ADR-0020 D10). The Pliwee
    // values were computed independently of both implementations by
    // `docs/reports/branding/pliwee-wave-5/pliwee_domain_kats.py`.

    @Test
    fun `legacy proof matches the cross-language known answer`() {
        val proof = PairingProof.compute(WireProfile.OMNIBRIDGE, token, fp(1), fp(2), nonce)
        assertEquals(
            "d34504e66ea816d8ac8a12de225db8ae6b9c03f7010b15a15f50cf3b53b859e1",
            hex(proof),
        )
    }

    @Test
    fun `legacy confirmation matches the cross-language known answer`() {
        val confirmation =
            PairingProof.computeConfirmation(WireProfile.OMNIBRIDGE, token, fp(1), fp(2), nonce)
        assertEquals(
            "fd1689c7fd3715e376ea9423c858c4839cce729a9471b5f6e93f76e34d0c11f3",
            hex(confirmation),
        )
    }

    @Test
    fun `pliwee proof matches the independent known answer`() {
        val proof = PairingProof.compute(WireProfile.PLIWEE, token, fp(1), fp(2), nonce)
        assertEquals(
            "3a433e1b0ec55746039eba2216abb786b0537955efd8f4ed1c92886426182510",
            hex(proof),
        )
    }

    @Test
    fun `pliwee confirmation matches the independent known answer`() {
        val confirmation =
            PairingProof.computeConfirmation(WireProfile.PLIWEE, token, fp(1), fp(2), nonce)
        assertEquals(
            "5f0bc7caae96da5c38f4a75fa78e7e43a75ec10daef83e7fa2efad04d9194672",
            hex(confirmation),
        )
    }

    // -----------------------------------------------------------------------
    // No hybrid state (ADR-0020 §D4; plan §4 rows X1, X2)
    // -----------------------------------------------------------------------

    /**
     * X1 / X2 from the phone's side: the confirmation this phone expects on
     * a connection of one profile is not satisfied by one made under the
     * other profile's domain, and neither is a proof. No fallback exists to
     * try the other domain.
     */
    @Test
    fun `a value from the other profile never verifies`() {
        for (connection in WireProfile.entries) {
            val other = WireProfile.entries.single { it != connection }
            val expectedProof = PairingProof.compute(connection, token, fp(1), fp(2), nonce)
            val foreignProof = PairingProof.compute(other, token, fp(1), fp(2), nonce)
            assertFalse(PairingProof.verify(expectedProof, foreignProof))

            val expected = PairingProof.computeConfirmation(connection, token, fp(1), fp(2), nonce)
            val foreign = PairingProof.computeConfirmation(other, token, fp(1), fp(2), nonce)
            assertFalse(PairingProof.verify(expected, foreign))
        }
    }
}
