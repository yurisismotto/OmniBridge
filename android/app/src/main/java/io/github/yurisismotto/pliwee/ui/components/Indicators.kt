package io.github.yurisismotto.pliwee.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.yurisismotto.pliwee.R
import io.github.yurisismotto.pliwee.ui.theme.PliweeGradient
import io.github.yurisismotto.pliwee.ui.theme.PliweeIconSize
import io.github.yurisismotto.pliwee.ui.theme.PliweeMotion
import io.github.yurisismotto.pliwee.ui.theme.PliweeRadius
import io.github.yurisismotto.pliwee.ui.theme.PliweeSpacing
import io.github.yurisismotto.pliwee.ui.theme.PliweeStatus
import io.github.yurisismotto.pliwee.ui.theme.PliweeTheme
import io.github.yurisismotto.pliwee.ui.theme.PliweeType
import io.github.yurisismotto.pliwee.ui.theme.LocalReducedMotion
import io.github.yurisismotto.pliwee.ui.theme.motionDuration

/**
 * A device or transfer state: dot, icon, word.
 *
 * All three, always. See [PliweeStatus] for why the word is not optional.
 * The dot and the icon are marked decorative so a screen reader announces the
 * state once, not three times.
 */
@Composable
fun PliweeStatusBadge(
    status: PliweeStatus,
    modifier: Modifier = Modifier,
    label: String = status.label,
    showIcon: Boolean = true,
) {
    val color = status.color()
    Row(
        modifier = modifier.semantics(mergeDescendants = true) { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(PliweeSpacing.xxs),
    ) {
        Box(
            Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(PliweeRadius.full))
                .background(status.dot()),
        )
        if (showIcon) {
            Icon(
                painter = painterResource(status.icon),
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(PliweeIconSize.small),
            )
        }
        Text(label, style = PliweeType.label, color = color)
    }
}

/**
 * The Pliwee mark, at whatever size the caller needs.
 *
 * Product placements: app bar, transfer motifs, empty states. [PliweeBrandMark]
 * is the same artwork at the institutional size — there is one mark now, not two.
 */
@Composable
fun PliweeGradientMark(
    modifier: Modifier = Modifier,
    size: Dp = PliweeIconSize.large,
    contentDescription: String? = null,
) {
    Icon(
        painter = painterResource(R.drawable.logo_pliwee_mark),
        contentDescription = contentDescription,
        tint = Color.Unspecified,
        modifier = modifier.size(size),
    )
}

/**
 * The Pliwee mark, institutional size: About, onboarding, the empty first run.
 *
 * The same artwork the launcher icon wears. `logo_pliwee_mark.xml` carries the
 * geometry of `docs/design/assets/pliwee-mark.svg` verbatim, and
 * `BrandingResourcesTest` asserts the equality, so the app cannot drift from
 * the master.
 */
@Composable
fun PliweeBrandMark(
    modifier: Modifier = Modifier,
    size: Dp = PliweeIconSize.hero,
    contentDescription: String? = null,
) {
    Icon(
        painter = painterResource(R.drawable.logo_pliwee_mark),
        contentDescription = contentDescription,
        tint = Color.Unspecified,
        modifier = modifier.size(size),
    )
}

/**
 * Transfer progress, in the brand gradient.
 *
 * Rolls its own track and fill rather than tinting a Material bar, because a
 * `LinearProgressIndicator` takes a solid colour and the gradient is the
 * point. The semantics are supplied by hand for the same reason — this must
 * still announce itself as a progress bar.
 */
@Composable
fun PliweeProgressBar(
    fraction: Float?,
    modifier: Modifier = Modifier,
    height: Dp = 6.dp,
) {
    val colors = PliweeTheme.colors
    val reduced = LocalReducedMotion.current

    // Indeterminate work still has to look alive; under reduced motion it
    // simply sits at a fixed width instead of sweeping.
    val infinite = rememberInfiniteTransition(label = "indeterminate")
    val sweep by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(PliweeMotion.RIBBON_PULSE_MS, easing = PliweeMotion.Flow),
            repeatMode = RepeatMode.Restart,
        ),
        label = "sweep",
    )
    val target = fraction?.coerceIn(0f, 1f)
    val animated by animateFloatAsState(
        targetValue = target ?: 0f,
        animationSpec = tween(motionDuration(PliweeMotion.NORMAL_MS), easing = PliweeMotion.Flow),
        label = "progress",
    )

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(PliweeRadius.full))
            .background(colors.surfaceSunken)
            .semantics {
                progressBarRangeInfo = if (target != null) {
                    ProgressBarRangeInfo(animated, 0f..1f)
                } else {
                    ProgressBarRangeInfo.Indeterminate
                }
            },
    ) {
        if (target != null) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(animated)
                    .clip(RoundedCornerShape(PliweeRadius.full))
                    .background(PliweeGradient.progress()),
            )
        } else {
            // Indeterminate: a short segment travelling the track. Under
            // reduced motion it parks in the middle rather than sweeping,
            // which still reads as "working" without any movement at all.
            val bias = if (reduced) 0f else (sweep * 2f - 1f)
            Box(
                Modifier
                    .align(androidx.compose.ui.BiasAlignment(bias, 0f))
                    .fillMaxHeight()
                    .fillMaxWidth(SEGMENT)
                    .clip(RoundedCornerShape(PliweeRadius.full))
                    .background(PliweeGradient.progress()),
            )
        }
    }
}

/** Width of the travelling segment shown while progress is unknown. */
private const val SEGMENT = 0.3f

/**
 * Battery, as a number with a bar beside it.
 *
 * [stale] is surfaced rather than hidden. A percentage from a session that
 * has gone quiet is history, and showing it as though it were current is the
 * exact bug the daemon's `DeviceState` type was introduced to stop.
 */
@Composable
fun PliweeBatteryPill(
    percentage: Int,
    modifier: Modifier = Modifier,
    charging: Boolean = false,
    stale: Boolean = false,
) {
    val colors = PliweeTheme.colors
    val tint = when {
        stale -> colors.textMuted
        percentage <= 15 -> colors.accentRed
        else -> colors.accentCyan
    }
    val suffix = when {
        stale -> ", last known"
        charging -> ", charging"
        else -> ""
    }
    Row(
        modifier = modifier.semantics(mergeDescendants = true) {
            contentDescription = "Battery $percentage percent$suffix"
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(PliweeSpacing.xxs),
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_battery),
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(PliweeIconSize.small),
        )
        Text("$percentage%", style = PliweeType.label, color = tint)
        if (charging && !stale) {
            Text("charging", style = PliweeType.caption, color = colors.textMuted)
        }
        if (stale) {
            Text("last known", style = PliweeType.caption, color = colors.textMuted)
        }
    }
}
