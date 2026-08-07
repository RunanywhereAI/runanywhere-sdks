package com.runanywhere.runanywhereai.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.ambientPeriod

/**
 * The app's ambient (repeating) motion primitives, all linear and all at the canonical
 * periods from `examples/DESIGN_GUIDELINE.md` §6.4. Each one resolves its period through
 * [ambientPeriod], so when the user has reduced motion the loop is not shortened — it is
 * not started at all, and the composable renders its resting frame instead (§6.5).
 */

/**
 * A single value breathing between [min] and [max] on the 1.6 s pulse period. Returns
 * [max] as a constant when motion is reduced, so the caller draws a steady shape rather
 * than a frozen mid-animation frame.
 */
@Composable
fun rememberBreath(min: Float = 0.35f, max: Float = 1f, label: String = "breathe"): Float {
    val period = ambientPeriod(AppMotion.AMBIENT_BREATHE) ?: return max
    val transition = rememberInfiniteTransition(label = label)
    val value by transition.animateFloat(
        initialValue = max,
        targetValue = min,
        animationSpec = infiniteRepeatable(
            // Half the period per leg, so a full out-and-back is one 1.6 s cycle.
            animation = tween(period / 2, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = label,
    )
    return value
}

/**
 * The caret that trails streaming text. Reads as "still writing" the way a text-editor
 * cursor does, which is why it breathes rather than spins — a spinner would claim the app
 * is waiting when in fact tokens are arriving.
 */
@Composable
fun StreamingCaret(color: Color, size: Dp = 9.dp, modifier: Modifier = Modifier) {
    val alpha = rememberBreath(min = 0.25f)
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(color.copy(alpha = alpha)),
    )
}

/**
 * A shimmer sweep for skeleton placeholders, on the 1.2 s period. Drawn as a lit band
 * moving across whatever it decorates, using [BlendMode.SrcAtop] so it stays inside the
 * placeholder's own shape without a second clip layer.
 *
 * When motion is reduced this contributes nothing, leaving a plain static placeholder —
 * which is the correct reduced-motion rendering of "content is loading".
 */
@Composable
fun Modifier.shimmer(highlight: Color): Modifier {
    val period = ambientPeriod(AppMotion.AMBIENT_SHIMMER) ?: return this
    val transition = rememberInfiniteTransition(label = "shimmer")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(period, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmerSweep",
    )
    return this.drawWithContent {
        drawContent()
        // Sweep from one full band off the left edge to one full band off the right, so
        // the highlight enters and exits cleanly instead of popping at the boundary.
        val band = size.width * 0.5f
        val start = -band + progress * (size.width + 2 * band)
        drawRect(
            brush = Brush.linearGradient(
                colors = listOf(Color.Transparent, highlight, Color.Transparent),
                start = Offset(start, 0f),
                end = Offset(start + band, size.height),
            ),
            blendMode = BlendMode.SrcAtop,
        )
    }
}
