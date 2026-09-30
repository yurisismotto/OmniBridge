package io.github.yurisismotto.pliwee

import io.github.yurisismotto.pliwee.clipboard.ClipboardNotifications
import io.github.yurisismotto.pliwee.net.Discovery
import io.github.yurisismotto.pliwee.net.PeerProfiles
import io.github.yurisismotto.pliwee.net.TlsFactory
import io.github.yurisismotto.pliwee.net.WireProfile
import io.github.yurisismotto.pliwee.notifications.NotificationSecret
import io.github.yurisismotto.pliwee.pairing.QrPayload
import io.github.yurisismotto.pliwee.proto.Envelope
import io.github.yurisismotto.pliwee.proto.capabilities.BatteryState
import io.github.yurisismotto.pliwee.service.ConnectionService
import io.github.yurisismotto.pliwee.ui.MainActivity
import java.net.InetSocketAddress
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The wire identities, pinned as literals.
 *
 * The mirror image of `desktop/core/tests/wire_identity.rs`, which spells out
 * the same strings from the Rust side. Every value here is a contract with
 * the desktop daemon: a peer that disagrees about any one of them does not
 * fail gracefully. A wrong ALPN fails the TLS handshake, a wrong service type
 * makes the daemon invisible to discovery, and a wrong QR prefix rejects a
 * valid pairing code — all of which look like "the network is broken" rather
 * than "somebody renamed a constant".
 *
 * Asserting `SERVICE_TYPE == SERVICE_TYPE` would prove nothing, so the
 * expected strings are written out. Changing an identity means changing both
 * files in the same commit.
 *
 * **Two profiles** (ADR-0020 §D4): the canonical Pliwee values and the legacy
 * OmniBridge values are both pinned, side by side, so neither can drift.
 * Removing the legacy profile is a breaking change with its own ADR. The
 * OmniBridge values were recorded in ADR-0018, the Pliwee values in ADR-0020.
 */
class WireIdentityTest {

    // -- canonical profile --------------------------------------------------

    @Test
    fun `control ALPN is pliwee 1`() {
        assertEquals("pliwee/1", TlsFactory.ALPN_PROTOCOL)
        assertEquals("pliwee/1", WireProfile.PLIWEE.controlAlpn)
    }

    @Test
    fun `data ALPN is pliwee-data 1`() {
        assertEquals("pliwee-data/1", TlsFactory.ALPN_DATA_PROTOCOL)
        assertEquals("pliwee-data/1", WireProfile.PLIWEE.dataAlpn)
    }

    /**
     * Android's NSD wants the service type without the `.local.` suffix the
     * desktop's `mdns-sd` uses, so the two constants are not string-equal.
     * What has to agree is the label, which is what this asserts.
     */
    @Test
    fun `mDNS service type is the pliwee tcp service`() {
        assertEquals("_pliwee._tcp.", Discovery.SERVICE_TYPE)
        assertEquals(Discovery.SERVICE_TYPE, WireProfile.PLIWEE.serviceType)
        assertTrue(
            "the desktop advertises _pliwee._tcp.local.",
            "_pliwee._tcp.local.".startsWith(Discovery.SERVICE_TYPE),
        )
    }

    @Test
    fun `QR scheme is pliwee1`() {
        assertEquals("pliwee1", QrPayload.SCHEME)
        assertEquals("pliwee1", WireProfile.PLIWEE.qrScheme)
    }

    @Test
    fun `pliwee domains`() {
        assertEquals("pliwee/pairing-proof/v1", WireProfile.PLIWEE.pairingProofDomain)
        assertEquals("pliwee/pairing-confirm/v1", WireProfile.PLIWEE.pairingConfirmDomain)
        assertEquals("pliwee/files.v1/data-stream/v1", WireProfile.PLIWEE.filesDataStreamDomain)
    }

    // -- legacy profile -----------------------------------------------------

    @Test
    fun `legacy control ALPN is omnibridge 1`() {
        assertEquals("omnibridge/1", TlsFactory.LEGACY_ALPN_PROTOCOL)
        assertEquals("omnibridge/1", WireProfile.OMNIBRIDGE.controlAlpn)
    }

    @Test
    fun `legacy data ALPN is omnibridge-data 1`() {
        assertEquals("omnibridge-data/1", TlsFactory.LEGACY_ALPN_DATA_PROTOCOL)
        assertEquals("omnibridge-data/1", WireProfile.OMNIBRIDGE.dataAlpn)
    }

    @Test
    fun `legacy mDNS service type is the omnibridge tcp service`() {
        assertEquals("_omnibridge._tcp.", Discovery.LEGACY_SERVICE_TYPE)
        assertEquals(Discovery.LEGACY_SERVICE_TYPE, WireProfile.OMNIBRIDGE.serviceType)
        assertTrue("_omnibridge._tcp.local.".startsWith(Discovery.LEGACY_SERVICE_TYPE))
    }

    @Test
    fun `legacy QR scheme is omnibridge1`() {
        assertEquals("omnibridge1", QrPayload.LEGACY_SCHEME)
        assertEquals("omnibridge1", WireProfile.OMNIBRIDGE.qrScheme)
    }

    @Test
    fun `legacy domains`() {
        assertEquals("omnibridge/pairing-proof/v1", WireProfile.OMNIBRIDGE.pairingProofDomain)
        assertEquals("omnibridge/pairing-confirm/v1", WireProfile.OMNIBRIDGE.pairingConfirmDomain)
        assertEquals(
            "omnibridge/files.v1/data-stream/v1",
            WireProfile.OMNIBRIDGE.filesDataStreamDomain,
        )
    }

    // -- the rules between them ---------------------------------------------

    @Test
    fun `exactly two profiles, canonical first and canonical by default`() {
        assertEquals(listOf(WireProfile.PLIWEE, WireProfile.OMNIBRIDGE), WireProfile.entries.toList())
        assertEquals(WireProfile.PLIWEE, WireProfile.CANONICAL)
        assertEquals("pliwee", WireProfile.PLIWEE.id)
        assertEquals("omnibridge", WireProfile.OMNIBRIDGE.id)
    }

    @Test
    fun `the four ALPN identifiers are distinct`() {
        val all = WireProfile.entries.flatMap { listOf(it.controlAlpn, it.dataAlpn) }
        assertEquals(4, all.toSet().size)
    }

    /** The profile selection table: each ALPN maps to exactly one profile. */
    @Test
    fun `each ALPN selects exactly one profile`() {
        assertEquals(WireProfile.PLIWEE, WireProfile.ofControlAlpn("pliwee/1"))
        assertEquals(WireProfile.OMNIBRIDGE, WireProfile.ofControlAlpn("omnibridge/1"))
        assertEquals(WireProfile.PLIWEE, WireProfile.ofDataAlpn("pliwee-data/1"))
        assertEquals(WireProfile.OMNIBRIDGE, WireProfile.ofDataAlpn("omnibridge-data/1"))
        // A data ALPN is not a control ALPN, and nothing unknown maps.
        assertNull(WireProfile.ofControlAlpn("pliwee-data/1"))
        assertNull(WireProfile.ofDataAlpn("pliwee/1"))
        for (unknown in listOf(null, "", "anyflow/1", "pliwee/2", "omnibridge/2", "h2")) {
            assertNull(WireProfile.ofControlAlpn(unknown))
            assertNull(WireProfile.ofDataAlpn(unknown))
        }
    }

    /**
     * X4: a client offers exactly one ALPN — its profile's — and never both.
     * Checked on a real `SSLSocket` hardened by the production code.
     */
    @Test
    fun `a hardened client socket offers exactly one ALPN`() {
        for (profile in WireProfile.entries) {
            for (alpn in listOf(profile.controlAlpn, profile.dataAlpn)) {
                val socket = SSLContext.getDefault().socketFactory.createSocket() as SSLSocket
                socket.use {
                    TlsFactory.harden(it, alpn)
                    assertArrayEquals(arrayOf(alpn), it.sslParameters.applicationProtocols)
                    assertArrayEquals(arrayOf("TLSv1.3"), it.enabledProtocols)
                }
            }
        }
    }

    @Test
    fun `no pre-rename identity survives`() {
        // A clean pre-v1 rename means a grep for a dead name is unambiguously
        // a bug (ADR-0011 "Consequences", carried into ADR-0018 and ADR-0020).
        // Neither live profile may carry one.
        for (dead in listOf("anyflow", "fedroid")) {
            for (profile in WireProfile.entries) {
                for (value in listOf(
                    profile.controlAlpn, profile.dataAlpn, profile.serviceType, profile.qrScheme,
                    profile.pairingProofDomain, profile.pairingConfirmDomain,
                    profile.filesDataStreamDomain,
                )) {
                    assertFalse(value, value.contains(dead))
                }
            }
        }
    }

    // -- discovery: one device, however many records (plan §4 X5) ----------

    private fun found(id: String?, host: String, profile: WireProfile) =
        Discovery.Found(id, "Desk", InetSocketAddress.createUnresolved(host, 55432), profile)

    @Test
    fun `a daemon advertised under both types is one device, dialled canonically`() {
        val devices = Discovery.merge(
            listOf(
                found("ab12", "10.0.0.2", WireProfile.OMNIBRIDGE),
                found("ab12", "10.0.0.2", WireProfile.PLIWEE),
                found("ab12", "fe80::2", WireProfile.PLIWEE),
            ),
        )
        assertEquals(1, devices.size)
        assertEquals("ab12", devices[0].deviceId)
        assertEquals(WireProfile.PLIWEE, devices[0].profile)
        assertEquals(2, devices[0].addresses.size)
    }

    @Test
    fun `a daemon seen only on the legacy type is dialled with the legacy profile`() {
        val devices = Discovery.merge(
            listOf(
                found("cd34", "10.0.0.3", WireProfile.OMNIBRIDGE),
                found("ab12", "10.0.0.2", WireProfile.PLIWEE),
            ),
        )
        assertEquals(2, devices.size)
        assertEquals(WireProfile.OMNIBRIDGE, devices.single { it.deviceId == "cd34" }.profile)
        assertEquals(WireProfile.PLIWEE, devices.single { it.deviceId == "ab12" }.profile)
    }

    @Test
    fun `merging for one device keeps id-less hints and ignores other devices`() {
        val device = Discovery.mergeFor(
            "ab12",
            listOf(
                found(null, "10.0.0.9", WireProfile.OMNIBRIDGE),
                found("ab12", "10.0.0.2", WireProfile.OMNIBRIDGE),
                found("ff00", "10.0.0.7", WireProfile.PLIWEE),
            ),
        )
        assertNotNull(device)
        assertEquals(WireProfile.OMNIBRIDGE, device!!.profile)
        assertEquals(listOf("10.0.0.9", "10.0.0.2"), device.addresses.map { it.hostString })
        assertNull(Discovery.mergeFor("0000", listOf(found("ab12", "10.0.0.2", WireProfile.PLIWEE))))
    }

    // -- which profile a paired computer is dialled with --------------------

    @Test
    fun `a computer is dialled canonically unless known only as legacy`() {
        val profiles = PeerProfiles()
        assertEquals(WireProfile.PLIWEE, profiles.forDialing("aa"))

        // Paired from an omnibridge1: code.
        profiles.learnedFromPairing("aa", WireProfile.OMNIBRIDGE)
        assertEquals(WireProfile.OMNIBRIDGE, profiles.forDialing("aa"))

        // Later seen on the canonical type: it was upgraded.
        profiles.learnedFromDiscovery("aa", WireProfile.PLIWEE)
        assertEquals(WireProfile.PLIWEE, profiles.forDialing("aa"))

        // Other computers are unaffected.
        assertEquals(WireProfile.PLIWEE, profiles.forDialing("bb"))
    }

    /**
     * The protobuf namespace, observed from generated code rather than from
     * the `.proto` text: `package pliwee.v1` plus
     * `java_package = "io.github.yurisismotto.pliwee.proto"` is what puts
     * [Envelope] here. A namespace rename that missed either option would
     * land the class somewhere else and this would not compile.
     */
    @Test
    fun `generated protobuf types live in the pliwee namespace`() {
        assertEquals(
            "io.github.yurisismotto.pliwee.proto.Envelope",
            Envelope::class.java.name,
        )
        assertEquals(
            "io.github.yurisismotto.pliwee.proto.capabilities.BatteryState",
            BatteryState::class.java.name,
        )
    }

    // -- the Android package identity (ADR-0020 §D1, §D2) --------------------
    //
    // Not wire values, but the same kind of contract: the OS persists state
    // against them. `applicationId` and the manifest components are pinned by
    // ManifestComponentsTest; these are the ones that live in Kotlin.

    /**
     * `R` is generated into the Gradle `namespace`, and the Kotlin root
     * package is where every class lives. Observed from compiled classes, so
     * a namespace or package change that missed either would move them.
     */
    @Test
    fun `the Kotlin package and the namespace are io github yurisismotto pliwee`() {
        assertEquals("io.github.yurisismotto.pliwee.R", R::class.java.name)
        assertEquals("io.github.yurisismotto.pliwee.PliweeApp", PliweeApp::class.java.name)
        assertEquals("io.github.yurisismotto.pliwee.net", WireProfile::class.java.`package`!!.name)
    }

    @Test
    fun `intent actions and extras are under the pliwee root`() {
        assertEquals("io.github.yurisismotto.pliwee.STOP", ConnectionService.ACTION_STOP)
        assertEquals(
            "io.github.yurisismotto.pliwee.TARGET_FINGERPRINT",
            ConnectionService.EXTRA_TARGET_FINGERPRINT,
        )
        assertEquals("io.github.yurisismotto.pliwee.APPLY_CLIP", ClipboardNotifications.ACTION_APPLY_CLIP)
        assertEquals("io.github.yurisismotto.pliwee.SEND_CLIPBOARD", MainActivity.ACTION_SEND_CLIPBOARD)
        assertEquals(
            "io.github.yurisismotto.pliwee.CLIPBOARD_REQUEST_ID",
            MainActivity.EXTRA_REQUEST_ID,
        )
    }

    /**
     * The Keystore aliases restart at v1 under the new applicationId. The
     * identity alias is private to `DeviceIdentity` and is pinned on a device
     * by the instrumented `PliweeIdentityTest`; this one is public.
     */
    @Test
    fun `the notification secret alias is pliwee-notification-secret-v1`() {
        assertEquals("pliwee-notification-secret-v1", NotificationSecret.KEY_ALIAS)
    }

    @Test
    fun `no retired name survives in the package identity`() {
        val values = listOf(
            R::class.java.name,
            ConnectionService.ACTION_STOP,
            ConnectionService.EXTRA_TARGET_FINGERPRINT,
            ClipboardNotifications.ACTION_APPLY_CLIP,
            MainActivity.ACTION_SEND_CLIPBOARD,
            MainActivity.EXTRA_REQUEST_ID,
            NotificationSecret.KEY_ALIAS,
        )
        for (dead in listOf("omnibridge", "anyflow", "fedroid")) {
            for (value in values) {
                assertFalse("$value carries $dead", value.lowercase().contains(dead))
            }
        }
    }
}
