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
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeBrandMark
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeCard
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeFingerprint
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeSecondaryButton
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeSectionLabel
import io.github.yurisismotto.omnibridge.ui.components.OmniBridgeSecurityNotice
import io.github.yurisismotto.omnibridge.ui.components.omniBridgeContentColumn
import io.github.yurisismotto.omnibridge.ui.theme.OmniBridgeSpacing
import io.github.yurisismotto.omnibridge.ui.theme.OmniBridgeTheme
import io.github.yurisismotto.omnibridge.ui.theme.OmniBridgeType

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
    val colors = OmniBridgeTheme.colors
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .omniBridgeContentColumn()
            .padding(horizontal = OmniBridgeSpacing.md),
        verticalArrangement = Arrangement.spacedBy(OmniBridgeSpacing.sm),
    ) {
        OmniBridgeSectionLabel("This device")
        OmniBridgeCard {
            Text(state.ownDeviceName, style = OmniBridgeType.subtitle, color = colors.textPrimary)
            Spacer(Modifier.height(OmniBridgeSpacing.xxs))
            Text("Fingerprint", style = OmniBridgeType.label, color = colors.textSecondary)
            OmniBridgeFingerprint(state.ownFingerprint)
            Spacer(Modifier.height(OmniBridgeSpacing.xxs))
            Text(
                state.keyBackingDescription,
                style = OmniBridgeType.caption,
                color = colors.textSecondary,
            )
        }

        OmniBridgeSectionLabel("Paired computers")
        OmniBridgeCard {
            if (state.peers.isEmpty()) {
                Text(
                    "None yet.",
                    style = OmniBridgeType.body,
                    color = colors.textSecondary,
                )
            } else {
                state.peers.forEach { peer ->
                    Text(peer.deviceName, style = OmniBridgeType.body, color = colors.textPrimary)
                    OmniBridgeFingerprint(
                        peer.fingerprint.toDisplayShort(),
                        color = colors.textSecondary,
                    )
                    Spacer(Modifier.height(OmniBridgeSpacing.xs))
                }
            }
        }

        OmniBridgeSectionLabel("Privacy")
        OmniBridgeSecurityNotice(
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
        OmniBridgeSecondaryButton(
            text = "Privacy policy",
            icon = R.drawable.ic_shield,
            onClick = actions.onOpenPrivacyPolicy,
        )

        Spacer(Modifier.height(OmniBridgeSpacing.lg))
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(OmniBridgeSpacing.xs),
        ) {
            OmniBridgeBrandMark(contentDescription = "Pliwee")
            Text("Pliwee", style = OmniBridgeType.subtitle, color = colors.textPrimary)
            Text(
                "One flow. Any device.",
                style = OmniBridgeType.caption,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(OmniBridgeSpacing.xxl))
    }
}
