package io.github.yurisismotto.omnibridge.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Finds desktop daemons on the local network via DNS-SD.
 *
 * ## Two service types, one device
 *
 * A Pliwee daemon advertises one instance under both `_pliwee._tcp` and the
 * legacy `_omnibridge._tcp`; an OmniBridge 1.0.0 daemon only under the
 * latter (ADR-0020 §D4). This browses **both**, tags every result with the
 * [WireProfile] of the type it was found under, and [merge] folds the two
 * records of one daemon into one device, preferring the canonical record.
 * A daemon seen only under the legacy type is dialled with the legacy
 * profile; anything else with the canonical one.
 *
 * ## Discovery is not trust
 *
 * Everything here is attacker-controlled: anyone on the link can publish a
 * record claiming any name, id or address. This class answers only "what is
 * worth dialling". The identity check happens in the TLS handshake against
 * the pinned key, and a spoofed record produces nothing but a failed
 * connection.
 */
class Discovery(context: Context) {

    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifi = context.applicationContext
        .getSystemService(Context.WIFI_SERVICE) as WifiManager

    data class Found(
        val deviceId: String?,
        val deviceName: String?,
        val address: InetSocketAddress,
        /** The profile of the service type this record was found under. */
        val profile: WireProfile,
    )

    /**
     * One device, however many records announced it: every address any of
     * them resolved to, and the profile to dial it with.
     */
    data class Device(
        val deviceId: String,
        val addresses: List<InetSocketAddress>,
        val profile: WireProfile,
    )

    /**
     * Browses for services until the flow is cancelled.
     *
     * A multicast lock is held for the duration: without it, Wi-Fi hardware
     * filters multicast packets while the screen is off and discovery
     * silently stops finding anything.
     *
     * ## This flow completes; it does not fail
     *
     * `NsdManager` refuses to start discovery for reasons that are entirely
     * routine — most often `FAILURE_MAX_LIMIT` or `FAILURE_ALREADY_ACTIVE`
     * when requests have been made faster than the platform tears the old
     * ones down, which is exactly what a retry loop does. This used to close
     * the flow with an exception, which propagated out of the collector, out
     * of the reconnect loop, and ended the connection job for good: the
     * process stayed alive with no scheduled retry and no error anywhere.
     *
     * A responder that will not start is a discovery result of "nothing
     * found", not a failure of the caller. So the flow completes normally and
     * the reason is logged. Callers must still be able to survive an
     * exception from here — nothing in a coroutine is exception-proof by
     * construction — but they will not routinely be handed one.
     */
    fun browse(): Flow<Found> = callbackFlow {
        val lock = wifi.createMulticastLock("omnibridge-discovery").apply {
            setReferenceCounted(true)
            acquire()
        }

        // `NsdManager.resolveService` throws IllegalArgumentException if the
        // same listener object is handed to it while an earlier resolve is
        // still outstanding — from a platform callback thread, where nothing
        // catches it and the process dies. A listener per service, retired
        // when it answers, is the documented way to avoid that.
        val resolving = ConcurrentHashMap<String, Boolean>()

        fun resolveListenerFor(key: String, profile: WireProfile) = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo?, errorCode: Int) {
                resolving.remove(key)
                Log.d(TAG, "resolve failed: $errorCode")
            }

            override fun onServiceResolved(info: NsdServiceInfo) {
                resolving.remove(key)
                val attributes = info.attributes ?: emptyMap()
                val deviceId = attributes["id"]?.toString(Charsets.UTF_8)
                    ?.takeIf { it.length <= 64 && it.all { c -> c.isHex() } }
                val deviceName = attributes["dn"]?.toString(Charsets.UTF_8)
                    ?.let { name -> name.filter { !it.isISOControl() }.take(64) }

                // Emit every resolved address, not just one: a daemon on a
                // dual-stack link publishes both, and picking a single one
                // arbitrarily can pick the unreachable one.
                for (host in info.resolvedAddresses()) {
                    trySend(Found(deviceId, deviceName, InetSocketAddress(host, info.port), profile))
                }
            }
        }

        // One browse per service type. Each listener knows its own profile,
        // so a record is tagged by the browse that found it rather than by
        // parsing a type string the platform formats inconsistently.
        val running = java.util.concurrent.atomic.AtomicInteger(WireProfile.entries.size)
        val listeners = WireProfile.entries.map { profile ->
            object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String?) = Unit
                override fun onDiscoveryStopped(serviceType: String?) = Unit
                override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                    // Completes the flow rather than failing it, once no
                    // browse is left. See the class note above: failing here
                    // is what used to kill the caller's reconnect loop
                    // permanently. One type failing still leaves the other.
                    Log.w(TAG, "could not start ${profile.id} discovery: error $errorCode")
                    if (running.decrementAndGet() == 0) close()
                }
                override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) = Unit
                override fun onServiceLost(info: NsdServiceInfo?) = Unit

                override fun onServiceFound(info: NsdServiceInfo) {
                    val short = profile.serviceType.substringBefore('.')
                    if (info.serviceType?.contains(short) != true) return
                    val key = "${info.serviceName}.${info.serviceType}"
                    if (resolving.putIfAbsent(key, true) != null) return
                    @Suppress("DEPRECATION")
                    runCatching { nsd.resolveService(info, resolveListenerFor(key, profile)) }
                        .onFailure {
                            resolving.remove(key)
                            Log.d(TAG, "resolve rejected: ${it.javaClass.simpleName}")
                        }
                }
            } to profile
        }

        // Starting discovery can itself throw on some platform versions.
        // Same rule as a start failure: no services found, not a broken
        // caller.
        val started = listeners.filter { (listener, profile) ->
            val result = runCatching {
                nsd.discoverServices(profile.serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
            }
            if (result.isFailure) {
                Log.w(
                    TAG,
                    "${profile.id} discovery could not start: " +
                        "${result.exceptionOrNull()?.javaClass?.simpleName}",
                )
                running.decrementAndGet()
            }
            result.isSuccess
        }
        if (started.isEmpty()) {
            runCatching { if (lock.isHeld) lock.release() }
            close()
            return@callbackFlow
        }

        awaitClose {
            for ((listener, _) in started) {
                runCatching { nsd.stopServiceDiscovery(listener) }
            }
            runCatching { if (lock.isHeld) lock.release() }
        }
    }

    private fun Char.isHex() = this in '0'..'9' || this in 'a'..'f'

    /**
     * Every address the service resolved to.
     *
     * `getHost()` was deprecated in API 34 in favour of `getHostAddresses()`,
     * and it only ever returned one address. Below API 34 one address is all
     * the platform offers.
     */
    private fun NsdServiceInfo.resolvedAddresses(): List<InetAddress> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            hostAddresses
        } else {
            @Suppress("DEPRECATION")
            listOfNotNull(host)
        }

    companion object {
        private const val TAG = "Discovery"

        /** Canonical NSD service type. */
        const val SERVICE_TYPE = "_pliwee._tcp."

        /** Legacy NSD service type, browsed alongside the canonical one. */
        const val LEGACY_SERVICE_TYPE = "_omnibridge._tcp."

        /**
         * Folds records into devices, one per TXT `id`.
         *
         * A Pliwee daemon announces itself twice — once per service type —
         * with the same `id`, so without this it would appear twice. The
         * merged device keeps every address either record resolved to, in
         * first-seen order, and is dialled with the canonical profile if any
         * record came from the canonical type: only a device seen on the
         * legacy type alone is an OmniBridge 1.0.0 daemon.
         *
         * Records with no usable `id` are dropped, because nothing ties them
         * to a paired device. The id is only a filter; identity is decided by
         * the pinned key during the TLS handshake, and that key — the peer's
         * pinned fingerprint — is what the caller keys the result under.
         */
        fun merge(found: List<Found>): List<Device> =
            found.filter { it.deviceId != null }
                .groupBy { it.deviceId!! }
                .map { (id, records) ->
                    Device(
                        deviceId = id,
                        addresses = records.map { it.address }.distinct(),
                        profile = if (records.any { it.profile == WireProfile.CANONICAL }) {
                            WireProfile.CANONICAL
                        } else {
                            WireProfile.OMNIBRIDGE
                        },
                    )
                }

        /**
         * The one device [deviceId] names among [found], if any record does.
         *
         * A record that carried no usable `id` is kept as a candidate for the
         * device being looked for, as it always was: its addresses are only
         * hints, and the pinned key decides who answers. It counts towards the
         * profile verdict like any other record.
         */
        fun mergeFor(deviceId: String, found: List<Found>): Device? =
            merge(
                found.filter { it.deviceId == null || it.deviceId == deviceId }
                    .map { if (it.deviceId == null) it.copy(deviceId = deviceId) else it },
            ).firstOrNull()
    }
}
