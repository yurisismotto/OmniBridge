package io.github.yurisismotto.pliwee.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.github.yurisismotto.pliwee.R
import io.github.yurisismotto.pliwee.files.FileTransferManager
import io.github.yurisismotto.pliwee.files.TransferState
import io.github.yurisismotto.pliwee.ui.components.PliweeCard
import io.github.yurisismotto.pliwee.ui.components.PliweeIconTile
import io.github.yurisismotto.pliwee.ui.components.PliweePrimaryButton
import io.github.yurisismotto.pliwee.ui.components.PliweeSecondaryButton
import io.github.yurisismotto.pliwee.ui.components.PliweeTransferCard
import io.github.yurisismotto.pliwee.ui.theme.PliweeSpacing
import io.github.yurisismotto.pliwee.ui.theme.PliweeStatus
import io.github.yurisismotto.pliwee.ui.theme.PliweeTheme
import io.github.yurisismotto.pliwee.ui.theme.PliweeType

/**
 * File transfer, in the Pliwee visual language.
 *
 * The behaviour is unchanged from the previous release — accept or reject,
 * watch progress, see the outcome. What changed is only how it looks.
 */

/**
 * A file a computer wants to send. Nothing arrives until this is answered.
 *
 * @param peerLabel what to call the computer that is offering. Null falls
 *   back to its short fingerprint, which is always available and always
 *   unambiguous; a name is friendlier when the caller has one to hand. Either
 *   way it is display only — the offer is answered by its transfer id.
 */
@Composable
fun IncomingOfferCard(
    offer: FileTransferManager.IncomingOffer,
    onRespond: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    peerLabel: String? = null,
) {
    val colors = PliweeTheme.colors
    PliweeCard(modifier) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            PliweeIconTile(icon = R.drawable.ic_download, accent = colors.accentViolet)
            Spacer(Modifier.width(PliweeSpacing.sm))
            androidx.compose.foundation.layout.Column {
                Text("Incoming file", style = PliweeType.label, color = colors.accentViolet)
                // Already sanitized before it reaches here: a raw peer-supplied
                // name could otherwise forge the rest of this card.
                Text(offer.filename, style = PliweeType.subtitle, color = colors.textPrimary)
                Text(
                    "${humanBytes(offer.sizeBytes)} · from ${peerLabel ?: offer.peer.toDisplayShort()}",
                    style = PliweeType.caption,
                    color = colors.textSecondary,
                )
            }
        }
        Spacer(Modifier.width(PliweeSpacing.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(PliweeSpacing.xs)) {
            PliweePrimaryButton(
                text = "Accept",
                onClick = { onRespond(true) },
                icon = R.drawable.ic_check,
                modifier = Modifier.weight(1f),
            )
            PliweeSecondaryButton(
                text = "Reject",
                onClick = { onRespond(false) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** One transfer's progress and outcome. */
@Composable
fun TransferRow(
    transfer: FileTransferManager.TransferUi,
    modifier: Modifier = Modifier,
    onCancel: (() -> Unit)? = null,
) {
    val colors = PliweeTheme.colors
    val direction = if (transfer.sending) "To" else "From"
    val status = when (transfer.state) {
        TransferState.TRANSFERRING -> PliweeStatus.Transferring
        TransferState.VERIFYING -> PliweeStatus.Transferring
        TransferState.COMPLETED -> PliweeStatus.Success
        // A cancellation is not an error and is not displayed as one.
        TransferState.CANCELLED -> PliweeStatus.Disconnected
        TransferState.FAILED -> PliweeStatus.Error
        TransferState.OFFERED, TransferState.WAITING_ACCEPT -> PliweeStatus.Connecting
    }
    val detail = when (transfer.state) {
        TransferState.TRANSFERRING -> transfer.percentage?.let {
            "${humanBytes(transfer.bytesTransferred)} of ${humanBytes(transfer.sizeBytes)}"
        }
        // Named apart from "transferring": the bytes have all arrived and the
        // hash is being checked, which is a different thing to be waiting for.
        TransferState.VERIFYING -> "Checking the file…"
        TransferState.COMPLETED ->
            if (transfer.sending) "Sent" else "Saved to Downloads/Pliwee"
        TransferState.CANCELLED -> transfer.failure?.display ?: "Cancelled"
        TransferState.FAILED -> "Failed: ${transfer.failure?.display ?: "unknown reason"}"
        TransferState.OFFERED, TransferState.WAITING_ACCEPT -> "Waiting…"
    }

    PliweeTransferCard(
        modifier = modifier,
        filename = transfer.filename,
        subtitle = "$direction ${humanBytes(transfer.sizeBytes)}",
        status = status,
        fraction = transfer.percentage?.let { it / 100f },
        detail = detail,
        percentLabel = transfer.percentage
            ?.takeIf { transfer.state == TransferState.TRANSFERRING }
            ?.let { "$it%" },
        icon = if (transfer.sending) R.drawable.ic_send else R.drawable.ic_download,
        accent = if (transfer.sending) colors.accentBlue else colors.accentViolet,
        onCancel = onCancel?.takeIf { transfer.state.isActive },
    )
}

fun humanBytes(bytes: Long): String {
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unit = 0
    while (value >= 1024 && unit < units.size - 1) {
        value /= 1024
        unit++
    }
    return if (unit == 0) "$bytes B" else "%.1f %s".format(value, units[unit])
}
