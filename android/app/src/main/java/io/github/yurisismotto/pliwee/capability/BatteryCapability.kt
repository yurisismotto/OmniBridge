package io.github.yurisismotto.pliwee.capability

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import com.google.protobuf.ByteString
import io.github.yurisismotto.pliwee.identity.Fingerprint
import io.github.yurisismotto.pliwee.proto.capabilities.BatteryState
import io.github.yurisismotto.pliwee.proto.capabilities.ChargingState
import java.util.concurrent.atomic.AtomicReference

/**
 * `battery.v1` — reports this phone's battery to the paired computer, and
 * keeps the computer's most recent reading in memory.
 *
 * Nothing is persisted. A battery history is a usage-and-movement log of the
 * person holding the phone, and there is no reason to keep one.
 */
class BatteryCapability internal constructor(
    /**
     * Whether this phone's battery may be sent to [peer] — the `battery.v1`
     * grant, re-read from the trust store at the moment of sending.
     *
     * Negotiation says what both sides *support*; only this says what the
     * person *allowed*. Before this existed the Battery switch on the device
     * card changed the trust record and nothing read it, so the reading left
     * the phone on every connect whatever the switch said (Play v1 audit F1).
     */
    private val isSharingAllowed: (Fingerprint) -> Boolean,
    private val localReading: () -> Reading?,
) : Capability {

    constructor(appContext: Context, isSharingAllowed: (Fingerprint) -> Boolean) :
        this(isSharingAllowed, { readLocal(appContext) })

    override val id: String = ID

    /** The desktop's latest reading, or null. In memory only. */
    private val remote = AtomicReference<Reading?>(null)

    data class Reading(
        val percentage: Int,
        val chargingState: ChargingState,
        val peerTimestampUnixMs: Long,
    )

    fun remoteReading(): Reading? = remote.get()

    override suspend fun onPeerConnected(context: CapabilityContext) {
        // Send once on connect so the desktop shows something immediately
        // rather than waiting for the next battery broadcast — and only to a
        // computer the person has allowed to see it.
        if (!isSharingAllowed(context.peer)) {
            Log.d(TAG, "battery not shared with ${context.peer.toDisplayShort()}: no battery.v1 grant")
            return
        }
        localReading()?.let { context.send(ID, encode(it)) }
    }

    override suspend fun onMessage(context: CapabilityContext, payload: ByteString) {
        val reading = decode(payload)
        Log.d(TAG, "battery update from ${context.peer.toDisplayShort()}: ${reading.percentage}%")
        remote.set(reading)
    }

    override suspend fun onPeerDisconnected(peer: Fingerprint) {
        remote.set(null)
    }

    companion object {
        const val ID = "battery.v1"
        private const val TAG = "BatteryCapability"

        /** Reads the current battery level from the platform. */
        fun readLocal(appContext: Context): Reading? {
            val intent: Intent = appContext.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            ) ?: return null

            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level < 0 || scale <= 0) return null

            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            return Reading(
                percentage = (level * 100 / scale).coerceIn(0, 100),
                chargingState = when (status) {
                    BatteryManager.BATTERY_STATUS_CHARGING -> ChargingState.CHARGING_STATE_CHARGING
                    BatteryManager.BATTERY_STATUS_DISCHARGING ->
                        ChargingState.CHARGING_STATE_DISCHARGING
                    BatteryManager.BATTERY_STATUS_FULL -> ChargingState.CHARGING_STATE_FULL
                    BatteryManager.BATTERY_STATUS_NOT_CHARGING ->
                        ChargingState.CHARGING_STATE_NOT_CHARGING
                    else -> ChargingState.CHARGING_STATE_UNSPECIFIED
                },
                peerTimestampUnixMs = System.currentTimeMillis(),
            )
        }

        fun encode(reading: Reading): ByteString =
            BatteryState.newBuilder()
                .setPercentage(reading.percentage)
                .setChargingState(reading.chargingState)
                .setTimestampUnixMs(reading.peerTimestampUnixMs)
                .build()
                .toByteString()

        /**
         * Decodes and validates.
         *
         * The range check lives here, at the capability boundary, so a hostile
         * peer cannot push a nonsense value into a progress bar or a
         * formatter further downstream.
         */
        fun decode(payload: ByteString): Reading {
            val message = BatteryState.parseFrom(payload)
            require(message.percentage in 0..100) {
                "battery percentage out of range"
            }
            return Reading(
                percentage = message.percentage,
                chargingState = message.chargingState,
                peerTimestampUnixMs = message.timestampUnixMs,
            )
        }
    }
}
