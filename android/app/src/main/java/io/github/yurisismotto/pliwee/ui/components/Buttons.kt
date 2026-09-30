package io.github.yurisismotto.pliwee.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.github.yurisismotto.pliwee.ui.theme.PliweeBorder
import io.github.yurisismotto.pliwee.ui.theme.PliweeGradient
import io.github.yurisismotto.pliwee.ui.theme.PliweeIconSize
import io.github.yurisismotto.pliwee.ui.theme.PliweeRadius
import io.github.yurisismotto.pliwee.ui.theme.PliweeSpacing
import io.github.yurisismotto.pliwee.ui.theme.PliweeTheme
import io.github.yurisismotto.pliwee.ui.theme.PliweeType
import io.github.yurisismotto.pliwee.ui.theme.MinTouchTarget

/**
 * The branded primary action.
 *
 * Wears the CTA gradient — the one whose teal start is deepened until white
 * clears AA at every point along the sweep. It is *not* the decorative brand
 * gradient: white on that one's teal end is 2.49:1, and this button always
 * has a label on it. See [PliweeGradient].
 *
 * Disabled state is a flat neutral rather than a faded gradient, because a
 * translucent gradient reads as "still tappable, just pretty".
 */
@Composable
fun PliweePrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: Int? = null,
) {
    val colors = PliweeTheme.colors
    val shape = RoundedCornerShape(PliweeRadius.full)
    val background: Brush = if (enabled) {
        PliweeGradient.cta()
    } else {
        Brush.linearGradient(listOf(colors.surfaceSunken, colors.surfaceSunken))
    }
    val content = if (enabled) Color.White else colors.disabled

    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget)
            .clip(shape)
            .background(background)
            .then(
                if (enabled) {
                    Modifier.clickable(role = Role.Button, onClick = onClick)
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Icon(
                    painter = painterResource(icon),
                    contentDescription = null,
                    tint = content,
                    modifier = Modifier.size(PliweeIconSize.medium),
                )
                Spacer(Modifier.width(PliweeSpacing.xs))
            }
            Text(text, style = PliweeType.body.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = content)
        }
    }
}

/** The quieter action beside a primary one. */
@Composable
fun PliweeSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: Int? = null,
) {
    val colors = PliweeTheme.colors
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = MinTouchTarget),
        shape = RoundedCornerShape(PliweeRadius.full),
        border = BorderStroke(PliweeBorder.hairline, colors.borderStrong),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = colors.textPrimary,
            disabledContentColor = colors.disabled,
        ),
    ) {
        if (icon != null) {
            Icon(
                painter = painterResource(icon),
                contentDescription = null,
                modifier = Modifier.size(PliweeIconSize.medium),
            )
            Spacer(Modifier.width(PliweeSpacing.xs))
        }
        Text(text, style = PliweeType.body)
    }
}

/**
 * An action that takes something away — forgetting a device, revoking trust.
 *
 * Kept visually apart from everything else: red, outlined rather than filled,
 * and never placed adjacent to a confirming button. Filling it red would make
 * it the loudest thing on a screen whose main job is usually something else,
 * and sitting it next to "Send" is how a mis-tap becomes a lost pairing.
 */
@Composable
fun PliweeDestructiveButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: Int? = null,
) {
    val colors = PliweeTheme.colors
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget),
        shape = RoundedCornerShape(PliweeRadius.full),
        border = BorderStroke(PliweeBorder.hairline, colors.accentRed.copy(alpha = 0.5f)),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = colors.accentRed,
            disabledContentColor = colors.disabled,
        ),
    ) {
        if (icon != null) {
            Icon(
                painter = painterResource(icon),
                contentDescription = null,
                modifier = Modifier.size(PliweeIconSize.medium),
            )
            Spacer(Modifier.width(PliweeSpacing.xs))
        }
        Text(text, style = PliweeType.body)
    }
}

/** A low-emphasis inline action: "Cancel", "Dismiss", "View all". */
@Composable
fun PliweeTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = MinTouchTarget),
    ) {
        Text(
            text,
            style = PliweeType.body,
            color = if (enabled) PliweeTheme.colors.accentBlue else PliweeTheme.colors.disabled,
        )
    }
}

/**
 * One tile in the "Quick actions" row: icon over a short label.
 *
 * [enabled] is false when the action genuinely cannot run right now — nothing
 * is paired, nothing is connected. It stays visible and greys out rather than
 * disappearing, so the row does not reflow every time a device drops.
 */
@Composable
fun PliweeQuickAction(
    label: String,
    icon: Int,
    accent: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val colors = PliweeTheme.colors
    Column(
        modifier = modifier
            .defaultMinSize(minWidth = 76.dp)
            .clip(RoundedCornerShape(PliweeRadius.large))
            .background(colors.surface)
            .then(
                if (enabled) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier,
            )
            .padding(vertical = PliweeSpacing.sm, horizontal = PliweeSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(PliweeSpacing.xs),
    ) {
        Icon(
            painter = painterResource(icon),
            contentDescription = null,
            tint = if (enabled) accent else colors.disabled,
            modifier = Modifier.size(PliweeIconSize.large),
        )
        Text(
            label,
            style = PliweeType.caption,
            color = if (enabled) colors.textSecondary else colors.disabled,
            textAlign = TextAlign.Center,
        )
    }
}
