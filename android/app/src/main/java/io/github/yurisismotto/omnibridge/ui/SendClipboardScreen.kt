package io.github.yurisismotto.omnibridge.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import io.github.yurisismotto.omnibridge.R
import io.github.yurisismotto.omnibridge.ui.components.ExchangeHero
import io.github.yurisismotto.omnibridge.ui.components.ExchangePayloadCard
import io.github.yurisismotto.omnibridge.ui.components.ExchangePayloadEmpty
import io.github.yurisismotto.omnibridge.ui.components.ExchangePeerStatus
import io.github.yurisismotto.omnibridge.ui.components.ExchangeSecurityFooter
import io.github.yurisismotto.omnibridge.ui.components.NoticeTone
import io.github.yurisismotto.omnibridge.ui.components.PliweePrimaryButton
import io.github.yurisismotto.omnibridge.ui.components.PliweeSecurityNotice
import io.github.yurisismotto.omnibridge.ui.components.PliweeTextButton
import io.github.yurisismotto.omnibridge.ui.components.deviceKindIcon
import io.github.yurisismotto.omnibridge.ui.components.pliweeContentColumn
import io.github.yurisismotto.omnibridge.ui.theme.PliweeRadius
import io.github.yurisismotto.omnibridge.ui.theme.PliweeSpacing
import io.github.yurisismotto.omnibridge.ui.theme.PliweeTheme
import io.github.yurisismotto.omnibridge.ui.theme.PliweeType

/**
 * The deliberate act of sending the clipboard to one computer.
 *
 * ## The shape of the screen
 *
 * Hero, destination, payload, action, cancel, security — in that order,
 * because that is the order the questions occur in: *what am I doing*,
 * *where is it going*, *what exactly is going*, *do it*, *actually, no*, *is
 * this safe*. It is the exchange-flow composition, shared with the
 * Sharesheet's file send so the two cannot drift; see
 * [io.github.yurisismotto.omnibridge.ui.components.ExchangeHero].
 *
 * ## About the preview
 *
 * Ordinary text is shown, because seeing it is how a person notices they are
 * about to send the wrong thing. Text the source app marked sensitive is
 * **not** shown — `EXTRA_IS_SENSITIVE` exists precisely so that surfaces like
 * this one do not render a password into a shoulder-surfable box, and the
 * size and destination are enough to decide with.
 *
 * Neither case is logged or persisted. The preview lives in composition and
 * dies with the screen. See [ClipboardPreview].
 */
@Composable
fun SendClipboardScreen(
    state: MainUiState,
    actions: MainActions,
    fingerprintHex: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PliweeTheme.colors
    val peer = state.peerByHex(fingerprintHex)
    if (peer == null) {
        Column(modifier.fillMaxSize().padding(PliweeSpacing.md)) {
            Text(
                "This device is no longer paired.",
                style = PliweeType.body,
                color = colors.textSecondary,
            )
        }
        return
    }

    // Read once, when the screen opens. The Activity has focus here, which is
    // the only state in which Android permits a clipboard read at all.
    val preview = remember(fingerprintHex) { actions.readClipboardPreview() }
    val connected = state.isConnected(peer)
    // Every decision this screen makes, in one value and testable on the JVM.
    val ui = UiMapping.sendClipboardUi(state.clipboardSendGate(peer), preview)

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .pliweeContentColumn()
            .padding(horizontal = PliweeSpacing.md),
    ) {
        // --- what is moving, and where to ---------------------------
        ExchangeHero(
            sourceIcon = R.drawable.ic_clipboard,
            // The peer's own glyph while its session is up, and a neutral
            // device otherwise. Never a monitor by default: this screen is
            // reachable from a phone peer too.
            destinationIcon = deviceKindIcon(
                UiMapping.peerDeviceKind(peer, state.liveSession),
            ),
        )

        // --- where it is going -------------------------------------
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            ExchangePeerStatus(
                status = state.statusFor(peer),
                label = if (connected) "Connected to ${peer.deviceName}" else peer.deviceName,
                // The peer's real platform while the session is up, and its
                // pinned fingerprint otherwise. It used to print a literal
                // "Desktop · Linux" at every peer regardless.
                // See UiMapping.peerIdentityLine.
                identity = UiMapping.peerIdentityLine(peer, state.liveSession),
            )
        }

        Spacer(Modifier.height(PliweeSpacing.lg))

        // --- what is going -----------------------------------------
        if (preview == null) ClipboardEmpty() else ClipboardContent(preview)

        Spacer(Modifier.height(PliweeSpacing.lg))

        // --- do it --------------------------------------------------
        PliweePrimaryButton(
            text = "Send to ${peer.deviceName}",
            icon = R.drawable.ic_send,
            // The same gate as every other Send clipboard affordance. This
            // screen used to ask only whether a link was up, which made it the
            // most permissive of the three and the one a Quick Settings press
            // is most likely to land on.
            enabled = ui.enabled,
            onClick = {
                actions.onSendClipboard(peer.fingerprint)
                onBack()
            },
        )
        // Why the button is off, whichever reason applies. A disabled
        // button with no explanation is a dead control.
        ui.blockedReason?.let { reason ->
            Spacer(Modifier.height(PliweeSpacing.xxs))
            Text(
                reason,
                style = PliweeType.caption,
                color = colors.textMuted,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(Modifier.height(PliweeSpacing.xs))
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            PliweeTextButton("Cancel", onBack)
        }

        Spacer(Modifier.height(PliweeSpacing.lg))
        ExchangeSecurityFooter()
        Spacer(Modifier.height(PliweeSpacing.xxl))
    }
}

/**
 * Nothing on the clipboard.
 *
 * Says what is true and what to do about it, and nothing else. In
 * particular it does not suggest that OmniBridge could fetch the clipboard
 * if it tried harder: Android only lets an app read the clipboard while it
 * has focus, and this screen has already had its one chance.
 *
 * The glyph is a clipboard, which is the payload this card is about. It used
 * to be the connection ribbon — an abstract flourish that said nothing about
 * *which* empty state a person was looking at.
 */
@Composable
private fun ClipboardEmpty() {
    ExchangePayloadCard(title = "Clipboard") {
        ExchangePayloadEmpty(
            icon = R.drawable.ic_clipboard,
            title = UiMapping.EMPTY_CLIPBOARD_REASON,
            subtitle = "Copy some text, then come back.",
            accent = PliweeTheme.colors.accentCyan,
        )
    }
}

/** The clip that is about to leave, shown as restrainedly as it can be. */
@Composable
private fun ClipboardContent(preview: ClipboardPreview) {
    val colors = PliweeTheme.colors
    ExchangePayloadCard(title = "Clipboard", trailing = "${preview.bytes} bytes") {
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(PliweeRadius.medium))
                .background(colors.surfaceSunken)
                .padding(PliweeSpacing.md),
        ) {
            Text(
                text = preview.text ?: "•".repeat(12),
                style = PliweeType.mono,
                color = if (preview.text != null) colors.textPrimary else colors.textMuted,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
                // A hidden clip is a row of bullets, which a screen reader
                // would otherwise read out one bullet at a time.
                modifier = if (preview.text == null) {
                    Modifier.semantics {
                        contentDescription = "Hidden because this clipboard is marked sensitive"
                    }
                } else {
                    Modifier
                },
            )
        }
    }

    if (preview.sensitive) {
        Spacer(Modifier.height(PliweeSpacing.sm))
        PliweeSecurityNotice(
            title = "This clipboard is marked sensitive",
            body = "The app you copied from marked this text as sensitive — " +
                "a password, a recovery code, or similar. It is hidden here " +
                "on purpose. Send it only if you meant to.",
            tone = NoticeTone.Caution,
            icon = R.drawable.ic_warning,
        )
    }
}
