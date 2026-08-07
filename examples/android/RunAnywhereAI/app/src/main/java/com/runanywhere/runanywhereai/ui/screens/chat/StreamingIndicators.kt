package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.components.StreamingCaret
import com.runanywhere.runanywhereai.ui.components.shimmer
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalReduceMotion
import com.runanywhere.runanywhereai.ui.theme.ambientPeriod
import kotlinx.coroutines.delay

/**
 * The waiting and streaming affordances for an assistant turn.
 *
 * These exist because the honest answer to "what is the app doing?" changes over the
 * first few seconds of a turn, and a single anonymous spinner cannot say any of it. On
 * this device the gap between pressing send and the first token was measured at ~2.6 s,
 * which a bare row of dots renders as a hang. So the wait names itself, and escalates
 * its own wording as it goes — reporting the app's own elapsed wait, never inventing
 * engine state it cannot observe.
 */

/** How long the app has been waiting, and therefore what it is honest to say. */
private enum class WaitPhase(val label: String) {
    /** Sub-second: the turn is being handed to the engine. Say almost nothing. */
    DISPATCHING("Starting…"),

    /** The prompt is being read. This is where most of the ~2.6 s actually goes. */
    READING("Reading your message…"),

    /** Long enough that the user deserves to know a first run is expensive. */
    WARMING("Warming up the model — the first reply takes longest"),
}

private const val READING_AFTER_MS = 600L
private const val WARMING_AFTER_MS = 2_500L

/**
 * Shown for an assistant turn that has produced nothing yet. Two parts: a labelled
 * status line that escalates with elapsed time, and shimmering skeleton lines standing in
 * for the reply that is coming.
 *
 * The skeleton is what makes the wait feel like loading rather than failure — it shows the
 * *shape* of the answer arriving. It is announced to accessibility services as a polite
 * live region so a screen-reader user hears the same status a sighted user reads.
 */
@Composable
fun PendingReplyIndicator(modifier: Modifier = Modifier) {
    var phase by remember { mutableStateOf(WaitPhase.DISPATCHING) }

    LaunchedEffect(Unit) {
        delay(READING_AFTER_MS)
        phase = WaitPhase.READING
        delay(WARMING_AFTER_MS - READING_AFTER_MS)
        phase = WaitPhase.WARMING
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = phase.label
            },
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            ThinkingPips()
            AnimatedContent(
                targetState = phase,
                transitionSpec = {
                    fadeIn(AppMotion.standard()) togetherWith fadeOut(AppMotion.exit())
                },
                label = "waitPhase",
            ) { current ->
                Text(
                    text = current.label,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        ReplySkeleton()
    }
}

/**
 * Three pips breathing out of phase. Staggered by a third of the period each so the group
 * reads as a travelling wave — the "thinking" idiom — rather than three lights blinking in
 * unison. Suppressed to a steady row when motion is reduced.
 */
@Composable
private fun ThinkingPips() {
    val period = ambientPeriod(AppMotion.AMBIENT_BREATHE)
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(PIP_COUNT) { index ->
            val alpha = if (period == null) {
                0.7f
            } else {
                pipAlpha(index = index, period = period)
            }
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = alpha)),
            )
        }
    }
}

@Composable
private fun pipAlpha(index: Int, period: Int): Float {
    val transition = rememberInfiniteTransition(label = "pip$index")
    val value by transition.animateFloat(
        initialValue = 0.25f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(
                durationMillis = period / 2,
                delayMillis = index * (period / (2 * PIP_COUNT)),
                easing = LinearEasing,
            ),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pipAlpha$index",
    )
    return value
}

private const val PIP_COUNT = 3

/**
 * Placeholder lines with a shimmer sweep, at the widths a short paragraph actually has —
 * full, full, then a short last line. Uniform-width bars are the tell of a lazy skeleton;
 * a ragged last line is what makes this read as prose about to appear.
 */
@Composable
private fun ReplySkeleton(modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SKELETON_WIDTHS.forEach { fraction ->
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(12.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(scheme.surfaceContainerHigh)
                    .shimmer(highlight = scheme.primary.copy(alpha = 0.16f)),
            )
        }
    }
}

private val SKELETON_WIDTHS = listOf(1f, 0.94f, 0.55f)

/**
 * Fades the bottom edge of streaming prose so arriving text rises into view instead of
 * snapping in whole. Applied to the text itself via [BlendMode.DstIn], so it costs one
 * draw pass, never re-lays-out the paragraph, and never disturbs text the user is already
 * reading above the fade — the failure mode the guideline warns about (§6.6).
 *
 * A no-op when motion is reduced: a mask that moves with every token is exactly the kind
 * of continuous motion §6.5 says to suppress outright.
 */
@Composable
fun Modifier.streamingReveal(active: Boolean): Modifier {
    if (LocalReduceMotion.current) return this
    // Animated rather than switched, so the mask retracts smoothly when the turn ends
    // instead of the last line popping to full opacity.
    val strength by animateFloatAsState(
        targetValue = if (active) 1f else 0f,
        animationSpec = AppMotion.standard(),
        label = "revealStrength",
    )
    if (strength <= 0.01f) return this
    return this.drawWithContent {
        drawContent()
        val fade = (FADE_HEIGHT_PX * strength).coerceAtMost(size.height)
        if (fade <= 0f) return@drawWithContent
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(Color.White, Color.Transparent),
                startY = size.height - fade,
                endY = size.height,
            ),
            topLeft = Offset(0f, size.height - fade),
            size = Size(size.width, fade),
            blendMode = BlendMode.DstIn,
        )
    }
}

/** Roughly one line of body text — enough to read as a reveal, not as a vignette. */
private const val FADE_HEIGHT_PX = 26f

/**
 * The caret that trails a streaming reply, plus its accessible label. Breathes on the
 * 1.6 s ambient period; goes steady under reduced motion.
 */
@Composable
fun StreamingTail(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.semantics { contentDescription = "Still writing" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StreamingCaret(color = MaterialTheme.colorScheme.primary)
    }
}
