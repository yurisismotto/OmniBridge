package io.github.yurisismotto.omnibridge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import io.github.yurisismotto.omnibridge.R
import io.github.yurisismotto.omnibridge.ui.components.PliweeBrandMark
import io.github.yurisismotto.omnibridge.ui.components.PliweeCard
import io.github.yurisismotto.omnibridge.ui.components.PliweeFingerprint
import io.github.yurisismotto.omnibridge.ui.components.PliweeSecondaryButton
import io.github.yurisismotto.omnibridge.ui.components.PliweeSectionLabel
import io.github.yurisismotto.omnibridge.ui.components.PliweeSecurityNotice
import io.github.yurisismotto.omnibridge.ui.components.pliweeContentColumn
import io.github.yurisismotto.omnibridge.ui.theme.PliweeSpacing
import io.github.yurisismotto.omnibridge.ui.theme.PliweeTheme
import io.github.yurisismotto.omnibridge.ui.theme.PliweeType

/**
 * This device's own identity, and what OmniBridge is.
 *
 * The identity block is not decoration: the fingerprint here is what the
 * person reads aloud, or compares on screen, while pairing from the other
 * side.
 */
@Composable
fun SettingsScreen(
    state: MainUiState,
    actions: MainActions,
    modifier: Modifier = Modifier,
) {
    val colors = PliweeTheme.colors
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .pliweeContentColumn()
            .padding(horizontal = PliweeSpacing.md),
        verticalArrangement = Arrangement.spacedBy(PliweeSpacing.sm),
    ) {
        PliweeSectionLabel("This device")
        PliweeCard {
            Text(state.ownDeviceName, style = PliweeType.subtitle, color = colors.textPrimary)
            Spacer(Modifier.height(PliweeSpacing.xxs))
            Text("Fingerprint", style = PliweeType.label, color = colors.textSecondary)
            PliweeFingerprint(state.ownFingerprint)
            Spacer(Modifier.height(PliweeSpacing.xxs))
            Text(
                state.keyBackingDescription,
                style = PliweeType.caption,
                color = colors.textSecondary,
            )
        }

        PliweeSectionLabel("Paired computers")
        PliweeCard {
            if (state.peers.isEmpty()) {
                Text(
                    "None yet.",
                    style = PliweeType.body,
                    color = colors.textSecondary,
                )
            } else {
                state.peers.forEach { peer ->
                    Text(peer.deviceName, style = PliweeType.body, color = colors.textPrimary)
                    PliweeFingerprint(
                        peer.fingerprint.toDisplayShort(),
                        color = colors.textSecondary,
                    )
                    Spacer(Modifier.height(PliweeSpacing.xs))
                }
            }
        }

        PliweeSectionLabel("Privacy")
        PliweeSecurityNotice(
            title = "Nothing leaves your network",
            // Every clause is a property of the code, checked for the Play v1
            // privacy policy. The earlier "transfers are not logged" was not
            // true: file names went to the system log (audit F5).
            body = "Pliwee has no account, no cloud service, no ads and no analytics. " +
                "It talks only to the computers you pair. Clipboard text, notification " +
                "content and file names are never written to this device's storage or " +
                "its system log, and no transfer history is kept.",
            icon = R.drawable.ic_shield_check,
        )
        // The privacy policy, published with the source (Play v1 audit F4).
        // Google Play requires it to be reachable from inside the app.
        PliweeSecondaryButton(
            text = "Privacy policy",
            icon = R.drawable.ic_shield,
            onClick = actions.onOpenPrivacyPolicy,
        )

        Spacer(Modifier.height(PliweeSpacing.lg))
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(PliweeSpacing.xs),
        ) {
            PliweeBrandMark(contentDescription = "Pliwee")
            Text("Pliwee", style = PliweeType.subtitle, color = colors.textPrimary)
            Text(
                "One flow. Any device.",
                style = PliweeType.caption,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(PliweeSpacing.xxl))
    }
}
