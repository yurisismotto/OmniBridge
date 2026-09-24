package io.github.yurisismotto.omnibridge

import com.google.protobuf.ByteString
import io.github.yurisismotto.omnibridge.capability.BatteryCapability
import io.github.yurisismotto.omnibridge.capability.CapabilityContext
import io.github.yurisismotto.omnibridge.identity.Fingerprint
import io.github.yurisismotto.omnibridge.proto.capabilities.ChargingState
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Play v1 audit F1: the Battery switch on the device card must decide whether
 * this phone's battery leaves it.
 *
 * Before the fix `onPeerConnected` sent the reading to every computer that
 * had *negotiated* `battery.v1` — which is every OmniBridge desktop — and the
 * grant the switch writes was never read. These tests fail against that code:
 * the ungranted peer receives a frame.
 */
class BatteryGrantTest {

    private fun fingerprint(seed: Int) = Fingerprint(ByteArray(32) { (seed + it).toByte() })

    private val reading = BatteryCapability.Reading(
        percentage = 42,
        chargingState = ChargingState.CHARGING_STATE_DISCHARGING,
        peerTimestampUnixMs = 1_789_575_511_000L,
    )

    private class Recorder {
        val sent = mutableListOf<Pair<String, ByteString>>()
        fun context(peer: Fingerprint) = CapabilityContext(peer, "device-id") { id, payload ->
            sent += id to payload
            ByteString.copyFrom(ByteArray(16))
        }
    }

    @Test
    fun `a computer without the battery grant is sent nothing`() = runTest {
        val denied = fingerprint(1)
        var reads = 0
        val capability = BatteryCapability(
            isSharingAllowed = { false },
            localReading = { reads++; reading },
        )
        val recorder = Recorder()

        capability.onPeerConnected(recorder.context(denied))

        assertTrue("no frame may leave the phone", recorder.sent.isEmpty())
        assertEquals("the battery is not even read", 0, reads)
    }

    @Test
    fun `a computer holding the grant is sent the reading`() = runTest {
        val allowed = fingerprint(2)
        val capability = BatteryCapability(
            isSharingAllowed = { it == allowed },
            localReading = { reading },
        )
        val recorder = Recorder()

        capability.onPeerConnected(recorder.context(allowed))

        assertEquals(1, recorder.sent.size)
        assertEquals(BatteryCapability.ID, recorder.sent.single().first)
        assertEquals(reading, BatteryCapability.decode(recorder.sent.single().second))
    }

    @Test
    fun `the grant is asked about the peer that connected, not any peer`() = runTest {
        val allowed = fingerprint(3)
        val other = fingerprint(4)
        val asked = mutableListOf<Fingerprint>()
        val capability = BatteryCapability(
            isSharingAllowed = { asked += it; it == allowed },
            localReading = { reading },
        )
        val recorder = Recorder()

        capability.onPeerConnected(recorder.context(other))

        assertTrue(recorder.sent.isEmpty())
        assertEquals(listOf(other), asked)
    }
}
