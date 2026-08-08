package com.runanywhere.runanywhereai.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import kotlin.math.max

/**
 * A live microphone waveform, drawn.
 *
 * Replaces the three hand-rolled `LevelBars` copies (STT, VAD, diarization), each of which
 * lit a fixed staircase of 12 bars from the *current* level only. That renders a VU meter,
 * not a signal: it says how loud the room is right now and forgets everything else, so a
 * pause between words looked identical to a dead microphone.
 *
 * This keeps a short rolling history and scrolls it right-to-left, so the shape of what the
 * user just said stays visible — which is the thing that tells them capture is working. The
 * newest sample is at the right edge under the brand gradient; older samples fade back.
 *
 * Motion here is *data*, not decoration: bars move because audio arrived, so reduced motion
 * does not suppress it (§6.5 governs ambient loops). Each new level shifts the history one
 * slot, so a quiet stretch walks in as hairlines and the shape of the last phrase drains off
 * the left edge; an unchanging level parks the trace rather than animating a signal that is
 * not there.
 */
@Composable
fun AudioWaveform(
    level: Float,
    modifier: Modifier = Modifier,
    /** Speech-gated tint: VAD turns this off so "hearing you" and "hearing the room" differ. */
    active: Boolean = true,
    height: Dp = WAVEFORM_HEIGHT,
) {
    val scheme = MaterialTheme.colorScheme
    val dimens = LocalDimens.current
    // One immutable snapshot per arriving chunk. 64 floats is cheaper to copy than it is to
    // make individually observable, and it keeps the Canvas a pure function of its input.
    var history by remember { mutableStateOf(FloatArray(SAMPLE_COUNT)) }

    // `level` is a plain Float parameter, so it has to be lifted into snapshot state before
    // snapshotFlow can observe it: reading the parameter directly inside a LaunchedEffect(Unit)
    // captures the value from the composition that started the effect and never sees another,
    // which left the waveform frozen at its first sample for the whole recording — a level
    // meter that in practice drew a flat hairline through several seconds of loud speech.
    val latestLevel by rememberUpdatedState(level)

    // Driven off the level rather than a frame clock, so nothing redraws while the mic is idle.
    LaunchedEffect(Unit) {
        snapshotFlow { latestLevel }.collect { next ->
            history = FloatArray(SAMPLE_COUNT).also { out ->
                history.copyInto(out, destinationOffset = 0, startIndex = 1)
                out[SAMPLE_COUNT - 1] = next.coerceIn(0f, 1f)
            }
        }
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .semantics {
                contentDescription = if (active) "Microphone input level" else "Microphone idle"
            },
    ) {
        val samples = history
        val barWidth = BAR_WIDTH.toPx()
        val gap = dimens.spacingXs.toPx() / 2f
        val slot = barWidth + gap
        // Right-aligned, so the newest sample sits at the right edge whatever width we get.
        val visible = ((size.width + gap) / slot).toInt().coerceIn(1, SAMPLE_COUNT)
        val firstIndex = SAMPLE_COUNT - visible
        val midY = size.height / 2f
        val maxHalf = midY - barWidth / 2f
        val brush = Brush.horizontalGradient(
            colors = if (active) {
                listOf(scheme.primary.copy(alpha = 0.30f), scheme.primary, scheme.tertiary)
            } else {
                listOf(
                    scheme.onSurfaceVariant.copy(alpha = 0.22f),
                    scheme.onSurfaceVariant.copy(alpha = 0.50f),
                )
            },
            startX = size.width - visible * slot,
            endX = size.width,
        )

        repeat(visible) { slotIndex ->
            val sample = samples[firstIndex + slotIndex]
            // A floor, so silence is a hairline rather than a gap: an empty stretch would
            // read as the waveform having ended.
            val half = max(barWidth / 2f, sample * maxHalf)
            val x = size.width - (visible - slotIndex) * slot + barWidth / 2f
            drawLine(
                brush = brush,
                start = Offset(x, midY - half),
                end = Offset(x, midY + half),
                strokeWidth = barWidth,
                cap = StrokeCap.Round,
            )
        }
    }
}

/** Tall enough to show a syllable's shape without stealing the card. */
private val WAVEFORM_HEIGHT = 44.dp

private val BAR_WIDTH = 3.dp

/** ~2 s of history at the recorder's chunk rate — one phrase, not a whole take. */
private const val SAMPLE_COUNT = 64
