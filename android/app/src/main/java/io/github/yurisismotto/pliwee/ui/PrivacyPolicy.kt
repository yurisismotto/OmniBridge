package io.github.yurisismotto.pliwee.ui

/**
 * Where OmniBridge's privacy policy is published.
 *
 * Google Play requires the policy to be reachable both from the store listing
 * and from inside the app (Play v1 audit F4). It lives in the public source
 * repository beside the code it describes, rendered by GitHub and readable
 * without an account. `PrivacyPolicyTest` pins this address to the file in
 * the repository, so moving the document breaks the build instead of the link.
 */
object PrivacyPolicy {
    /** Repository-relative path of the policy. */
    const val PATH = "docs/policy/PRIVACY-POLICY.md"

    const val URL = "https://github.com/yurisismotto/OmniBridge/blob/main/$PATH"
}
