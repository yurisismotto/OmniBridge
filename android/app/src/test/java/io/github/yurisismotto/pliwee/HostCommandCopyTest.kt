package io.github.yurisismotto.pliwee

import io.github.yurisismotto.pliwee.ui.FIRST_DEVICE_HINT
import io.github.yurisismotto.pliwee.ui.PairingScanner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The app tells the user which command to run on the computer. The Linux
 * packages install `/usr/bin/pliwee` and no other command name, so a screen
 * that says `omnibridge pair` sends the user to a command that does not
 * exist (G8 defect D2).
 */
class HostCommandCopyTest {

    @Test
    fun `the pairing command is the one the packages install`() {
        assertEquals("pliwee pair", PairingScanner.HOST_PAIR_COMMAND)
    }

    @Test
    fun `the scanner prompt and the empty state name pliwee pair`() {
        for (copy in listOf(PairingScanner.PROMPT, FIRST_DEVICE_HINT)) {
            assertTrue("'$copy' must name `pliwee pair`", copy.contains("`pliwee pair`"))
            assertTrue(
                "'$copy' names the retired command",
                !copy.contains("omnibridge", ignoreCase = true),
            )
        }
    }

    /**
     * No shipped source tells the user to run a retired command. Legacy wire
     * values (`omnibridge1:`, `omnibridge/1`) are not commands and do not
     * match: the pattern is the binary name followed by a CLI verb.
     */
    @Test
    fun `no shipped source names a retired desktop command`() {
        val verbs = "pair|unpair|status|devices|grant|revoke|send|clipboard|transfers|cancel|ping"
        val retired = Regex("""\bomnibridged?\s+($verbs)\b""", RegexOption.IGNORE_CASE)
        val sources = File("src/main").walkTopDown()
            .filter { it.isFile && it.extension in setOf("kt", "xml") }
            .toList()
        assertTrue("no sources found under src/main; the scan would be vacuous", sources.size > 50)
        val hits = sources.flatMap { file ->
            file.readLines().withIndex()
                .filter { (_, line) -> retired.containsMatchIn(line) }
                .map { (n, line) -> "${file.path}:${n + 1}: ${line.trim()}" }
        }
        assertTrue("retired desktop command named in shipped source:\n" + hits.joinToString("\n"), hits.isEmpty())
    }
}
