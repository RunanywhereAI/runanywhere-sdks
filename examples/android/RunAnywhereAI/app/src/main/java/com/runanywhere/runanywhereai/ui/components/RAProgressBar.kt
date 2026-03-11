package com.runanywhere.runanywhereai.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

// ── Droplet: a tiny line streak ──────────────────────────────────────────────

private data class Droplet(
    var x: Float,
    var y: Float,
    val vx: Float,
    val vy: Float,
    val length: Float,    // streak length in px
    val angle: Float,     // direction angle (radians) — streak aligns to velocity
    val maxLifeMs: Long,
    var elapsedMs: Long = 0L,
) {
    val alive: Boolean get() = elapsedMs < maxLifeMs
    val alpha: Float
        get() {
            val t = elapsedMs.toFloat() / maxLifeMs
            // Fade in quickly, fade out linearly
            return if (t < 0.1f) t / 0.1f else 1f - ((t - 0.1f) / 0.9f)
        }
}

// ── Constants ────────────────────────────────────────────────────────────────

private const val DROPLET_COUNT = 7             // 6-8 droplets active at the tip
private const val SPAWN_INTERVAL_MS = 60L       // spawn a droplet every ~60ms
private const val DROPLET_MIN_LIFE_MS = 200L
private const val DROPLET_MAX_LIFE_MS = 450L
private const val DROPLET_MIN_LENGTH = 3f       // px
private const val DROPLET_MAX_LENGTH = 8f       // px
private const val DROPLET_STROKE_WIDTH = 1.5f   // px — thin micro lines
private const val SPEED_MIN = 0.08f             // px/ms
private const val SPEED_MAX = 0.18f             // px/ms

// ── Public composable ────────────────────────────────────────────────────────

/**
 * Minimal progress bar with micro line-droplets scattering from the leading edge.
 *
 * @param progress 0f..1f
 * @param modifier layout modifier
 * @param color single fill color (defaults to primary)
 * @param trackColor unfilled track color
 * @param height bar height
 */
@Composable
fun RAProgressBar(
    progress: Float,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceVariant,
    height: Dp = 6.dp,
) {
    val animatedProgress by animateFloatAsState(
        targetValue = progress.coerceIn(0f, 1f),
        animationSpec = AppMotion.tweenLong(),
        label = "progressAnim",
    )

    val droplets = remember { mutableStateListOf<Droplet>() }
    var frameTime by remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) {
        var lastSpawn = 0L
        var lastFrame = 0L
        while (true) {
            withInfiniteAnimationFrameMillis { millis ->
                val dt = if (lastFrame == 0L) 16L else millis - lastFrame
                lastFrame = millis

                // Advance existing droplets
                val iter = droplets.listIterator()
                while (iter.hasNext()) {
                    val d = iter.next()
                    d.elapsedMs += dt
                    if (!d.alive) {
                        iter.remove()
                    } else {
                        d.x += d.vx * dt
                        d.y += d.vy * dt
                    }
                }

                // Spawn new droplet — keep pool around DROPLET_COUNT
                if (millis - lastSpawn >= SPAWN_INTERVAL_MS &&
                    animatedProgress > 0.01f &&
                    droplets.size < DROPLET_COUNT
                ) {
                    lastSpawn = millis

                    // Scatter directions: up, down, and forward (roughly -60° to +60° arc centered on rightward)
                    val angle = (Random.nextFloat() - 0.5f) * Math.PI.toFloat() * 0.7f // ±63°
                    val speed = SPEED_MIN + Random.nextFloat() * (SPEED_MAX - SPEED_MIN)

                    droplets.add(
                        Droplet(
                            x = 0f,
                            y = 0f,
                            vx = cos(angle) * speed,
                            vy = sin(angle) * speed,
                            length = DROPLET_MIN_LENGTH + Random.nextFloat() * (DROPLET_MAX_LENGTH - DROPLET_MIN_LENGTH),
                            angle = angle,
                            maxLifeMs = DROPLET_MIN_LIFE_MS + Random.nextLong(DROPLET_MAX_LIFE_MS - DROPLET_MIN_LIFE_MS),
                        ),
                    )
                }

                frameTime = millis
            }
        }
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height),
    ) {
        @Suppress("UNUSED_EXPRESSION")
        frameTime // read state to trigger recomposition each frame

        val barH = size.height
        val cornerPx = barH / 2f
        val fillWidth = size.width * animatedProgress

        // Track
        drawRoundRect(
            color = trackColor,
            cornerRadius = CornerRadius(cornerPx, cornerPx),
            size = size,
        )

        // Fill — single solid color
        if (fillWidth > 0f) {
            drawRoundRect(
                color = color,
                cornerRadius = CornerRadius(cornerPx, cornerPx),
                size = androidx.compose.ui.geometry.Size(fillWidth, barH),
            )
        }

        // Droplets — thin line streaks
        if (fillWidth > 1f) {
            drawDroplets(droplets, tipX = fillWidth, tipY = barH / 2f, color = color)
        }
    }
}

// ── Draw helper ──────────────────────────────────────────────────────────────

private fun DrawScope.drawDroplets(
    droplets: List<Droplet>,
    tipX: Float,
    tipY: Float,
    color: Color,
) {
    for (d in droplets) {
        val alpha = d.alpha.coerceIn(0f, 1f)
        if (alpha <= 0f) continue

        val startX = tipX + d.x
        val startY = tipY + d.y
        val endX = startX + cos(d.angle) * d.length
        val endY = startY + sin(d.angle) * d.length

        drawLine(
            color = color.copy(alpha = alpha),
            start = Offset(startX, startY),
            end = Offset(endX, endY),
            strokeWidth = DROPLET_STROKE_WIDTH,
            cap = StrokeCap.Round,
        )
    }
}
