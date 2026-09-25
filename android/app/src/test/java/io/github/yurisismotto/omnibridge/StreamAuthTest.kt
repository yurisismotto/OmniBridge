package io.github.yurisismotto.omnibridge

import io.github.yurisismotto.omnibridge.files.StreamAuth
import io.github.yurisismotto.omnibridge.identity.Fingerprint
import io.github.yurisismotto.omnibridge.net.WireProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The data-stream MAC.
 *
 * The vectors below are asserted by the Rust suite too
 * (`auth::tests::the_legacy_mac_matches_the_published_cross_language_vector`
 * and `the_pliwee_mac_matches_the_independent_cross_language_vector`), which
 * makes the construction a checked cross-language contract rather than two
 * implementations that happen to agree today. If one of these two tests is
 * ever changed, the other must change with it or the phone and the desktop
 * stop being able to open a data stream.
 */
class StreamAuthTest {

    private fun fp(byte: Int) = requireNotNull(Fingerprint.fromHex("%02x".format(byte).repeat(32)))
    private fun challenge(byte: Int) = ByteArray(32) { byte.toByte() }
    private fun id(byte: Int) = ByteArray(16) { byte.toByte() }

    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }

    /**
     * The legacy value is the one committed before Wave 5, byte for byte; it
     * now tests live legacy-profile code (ADR-0020 D10). The Pliwee value was
     * computed independently by
     * `docs/reports/branding/pliwee-wave-5/pliwee_domain_kats.py`.
     */
    @Test
    fun `the legacy mac matches the published cross-language vector`() {
        val mac = StreamAuth.compute(WireProfile.OMNIBRIDGE, challenge(0x01), fp(0x02), fp(0x03), id(0x04))
        assertEquals(
            "503aaf7d8c15b38971f4fbcc3ec34742ae27263ac94f2507ecab7c3691764576",
            mac.hex(),
        )
    }

    @Test
    fun `the pliwee mac matches the independent cross-language vector`() {
        val mac = StreamAuth.compute(WireProfile.PLIWEE, challenge(0x01), fp(0x02), fp(0x03), id(0x04))
        assertEquals(
            "de3164a18f2cfb5e042b4b755d45f30f3049e41a93d0f727b33b26e17bafc3f9",
            mac.hex(),
        )
    }

    /** No hybrid state: one profile's MAC is never the other's. */
    @Test
    fun `a mac from one profile does not verify under the other`() {
        val pliwee = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val legacy = StreamAuth.compute(WireProfile.OMNIBRIDGE, challenge(1), fp(2), fp(3), id(4))
        assertFalse(StreamAuth.verify(pliwee, legacy))
        assertFalse(StreamAuth.verify(legacy, pliwee))
    }

    @Test
    fun `a correct mac verifies`() {
        val mac = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        assertTrue(StreamAuth.verify(mac, mac))
    }

    @Test
    fun `a different challenge does not verify`() {
        val expected = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val other = StreamAuth.compute(WireProfile.PLIWEE, challenge(9), fp(2), fp(3), id(4))
        assertFalse(StreamAuth.verify(expected, other))
    }

    @Test
    fun `a proof for one transfer does not authorize another`() {
        val expected = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val other = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(5))
        assertFalse(StreamAuth.verify(expected, other))
    }

    @Test
    fun `a proof is worthless against a different acceptor`() {
        val expected = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val other = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(9), fp(3), id(4))
        assertFalse(StreamAuth.verify(expected, other))
    }

    @Test
    fun `a proof cannot be replayed by a different dialer`() {
        val expected = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val other = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(9), id(4))
        assertFalse(StreamAuth.verify(expected, other))
    }

    @Test
    fun `swapping the two fingerprints changes the mac`() {
        // Length-prefixing is what guarantees this: without it, two
        // concatenated 32-byte values would be ambiguous.
        val a = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        val b = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(3), fp(2), id(4))
        assertFalse(StreamAuth.verify(a, b))
    }

    @Test
    fun `a truncated or padded mac is refused`() {
        val mac = StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), id(4))
        assertFalse(StreamAuth.verify(mac, mac.copyOf(31)))
        assertFalse(StreamAuth.verify(mac, ByteArray(0)))
        assertFalse(StreamAuth.verify(mac, mac + byteArrayOf(0)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `a short challenge is refused rather than silently keying a weak mac`() {
        StreamAuth.compute(WireProfile.PLIWEE, ByteArray(31), fp(2), fp(3), id(4))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `a transfer id of the wrong length is refused`() {
        StreamAuth.compute(WireProfile.PLIWEE, challenge(1), fp(2), fp(3), ByteArray(15))
    }
}
