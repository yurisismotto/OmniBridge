package io.github.yurisismotto.pliwee

import io.github.yurisismotto.pliwee.ui.PrivacyPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The in-app privacy link must point at a document that exists (Play v1
 * audit F4). Unit tests run with the `:app` module as the working directory,
 * so the repository root is two levels up.
 */
class PrivacyPolicyTest {

    private val repositoryRoot = File("../..").canonicalFile

    @Test
    fun `the linked policy exists in the repository`() {
        val policy = File(repositoryRoot, PrivacyPolicy.PATH)
        assertTrue("missing ${policy.path}", policy.isFile)
        assertTrue("the policy is empty", policy.length() > 0)
    }

    @Test
    fun `the link is the public GitHub rendering of that file on main`() {
        assertEquals(
            "https://github.com/yurisismotto/OmniBridge/blob/main/" + PrivacyPolicy.PATH,
            PrivacyPolicy.URL,
        )
        assertTrue(PrivacyPolicy.URL.startsWith("https://"))
    }
}
