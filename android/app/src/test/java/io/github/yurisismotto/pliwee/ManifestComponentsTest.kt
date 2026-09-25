package io.github.yurisismotto.pliwee

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * The app's package and its manifest components, pinned as a snapshot.
 *
 * ## Why components are frozen
 *
 * Android persists state against a `ComponentName` — package **plus class
 * name** — not against the app alone (ADR-0020 §"Android component
 * identity"): the notification-access grant is keyed by the listener's, the
 * Quick Settings slot by the tile's, pinned icons and shortcuts by the
 * launcher activity's, direct-share ranking by the share target's. The D1
 * transition to `io.github.yurisismotto.pliwee` preserved none of that (a new
 * app), so the names below were chosen freely in Wave 6. **From this build on
 * they are frozen.** Renaming a class here must keep the old `ComponentName`
 * — a stable subclass or an `activity-alias` — or it is a breaking change,
 * and this snapshot is where that shows up.
 *
 * The same facts are read back from the *built* APK with `aapt2` in the Wave 6
 * report; this test holds the source of them.
 */
class ManifestComponentsTest {

    private val manifest: Element by lazy {
        val file = File("src/main/AndroidManifest.xml")
        assertTrue("expected the manifest at ${file.absolutePath}", file.isFile)
        DocumentBuilderFactory.newInstance()
            .apply { isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(file)
            .documentElement
    }

    private fun Element.android(name: String): String? =
        getAttributeNS(ANDROID, name).takeIf { hasAttributeNS(ANDROID, name) }

    private fun Element.children(tag: String): List<Element> {
        val nodes = getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }.filter { it.parentNode == this }
    }

    private val application: Element by lazy {
        manifest.children("application").single()
    }

    /** Every component this app declares itself (a relative name). */
    private val ownComponents: List<Element> by lazy {
        COMPONENT_TAGS.flatMap { application.children(it) }
            .filter { it.android("name")!!.startsWith(".") }
    }

    private fun gradleString(file: String, key: String): String {
        val text = File(file).readText()
        val matches = Regex("""(?m)^\s*$key\s*=\s*"([^"]*)"""").findAll(text).map { it.groupValues[1] }.toList()
        assertEquals("$file declares $key exactly once: $matches", 1, matches.size)
        return matches.single()
    }

    @Test
    fun `applicationId and namespace are io github yurisismotto pliwee`() {
        assertEquals(PACKAGE, gradleString("build.gradle.kts", "applicationId"))
        assertEquals(PACKAGE, gradleString("build.gradle.kts", "namespace"))
        // The manifest must not carry a package of its own that could
        // disagree with Gradle's.
        assertEquals("", manifest.getAttribute("package"))
    }

    @Test
    fun `the notification fixture is io github yurisismotto pliwee fixture`() {
        assertEquals("$PACKAGE.fixture", gradleString("../fixture/build.gradle.kts", "applicationId"))
        assertEquals("$PACKAGE.fixture", gradleString("../fixture/build.gradle.kts", "namespace"))
    }

    /** The snapshot. Exact: a component added, removed or renamed fails it. */
    @Test
    fun `the component snapshot is exactly the frozen set`() {
        val actual = ownComponents.map { c ->
            listOf(
                c.tagName,
                c.android("name"),
                "exported=${c.android("exported")}",
                "permission=${c.android("permission")}",
            ).joinToString(" ")
        }
        assertEquals(FROZEN, actual)
        assertEquals(".PliweeApp", application.android("name"))
    }

    /** Each frozen name resolves, under the namespace, to a class that exists. */
    @Test
    fun `every component resolves to a compiled class in the pliwee package`() {
        assertTrue("no components were read at all", ownComponents.isNotEmpty())
        for (name in ownComponents.map { it.android("name")!! } + application.android("name")!!) {
            val qualified = PACKAGE + name
            val loaded = runCatching { Class.forName(qualified, false, javaClass.classLoader) }
            assertTrue("$qualified does not exist: ${loaded.exceptionOrNull()}", loaded.isSuccess)
        }
    }

    /**
     * What Android keys by each frozen component is still wired to it: the
     * launcher entry, the share target, the listener's binding permission and
     * the tile's action. A rename that kept the name but lost the role would
     * pass the snapshot and fail here.
     */
    @Test
    fun `the persisted roles are attached to the frozen components`() {
        fun component(name: String) = ownComponents.single { it.android("name") == name }
        fun actions(c: Element) = c.children("intent-filter")
            .flatMap { it.children("action") }.map { it.android("name") }

        assertTrue(
            actions(component(".ui.MainActivity")).contains("android.intent.action.MAIN"),
        )
        assertTrue(
            component(".ui.MainActivity").children("intent-filter")
                .flatMap { it.children("category") }
                .any { it.android("name") == "android.intent.category.LAUNCHER" },
        )
        assertEquals(
            listOf("android.intent.action.SEND", "android.intent.action.SEND", "android.intent.action.SEND_MULTIPLE"),
            actions(component(".ui.SendActivity")),
        )
        assertEquals(
            listOf("android.service.notification.NotificationListenerService"),
            actions(component(".notifications.PliweeNotificationListener")),
        )
        assertEquals(
            listOf("android.service.quicksettings.action.QS_TILE"),
            actions(component(".ui.ClipboardTileService")),
        )
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
        const val PACKAGE = "io.github.yurisismotto.pliwee"
        val COMPONENT_TAGS = listOf("activity", "activity-alias", "service", "receiver", "provider")

        /**
         * Frozen at Pliwee Wave 6 (ADR-0020). Order: as the manifest
         * declares them, grouped by tag.
         */
        val FROZEN = listOf(
            "activity .ui.MainActivity exported=true permission=null",
            "activity .ui.PairingCaptureActivity exported=false permission=null",
            "activity .ui.SendActivity exported=true permission=null",
            "service .service.ConnectionService exported=false permission=null",
            "service .notifications.PliweeNotificationListener exported=false " +
                "permission=android.permission.BIND_NOTIFICATION_LISTENER_SERVICE",
            "service .ui.ClipboardTileService exported=true " +
                "permission=android.permission.BIND_QUICK_SETTINGS_TILE",
        )
    }
}
