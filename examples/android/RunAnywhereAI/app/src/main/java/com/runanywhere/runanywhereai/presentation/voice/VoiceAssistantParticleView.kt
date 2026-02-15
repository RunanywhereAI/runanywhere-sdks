package com.runanywhere.runanywhereai.presentation.voice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.*
import kotlin.random.Random

/**
 * VoiceAssistantParticleView - Particle animation for voice assistant
 *
 * Particles form a thick circular ring with scattered fill toward center.
 * Dense at the circumference, sparse inside -- like a particle nebula ring.
 * Responds to both voice input (microphone) and voice output (TTS).
 * Non-interactive (no tap/touch handling).
 *
 * Features:
 * - 2000 particles with edge-biased radial distribution
 * - Dense outer ring band with sparse inner scatter
 * - Amplitude-driven ring expansion from center
 * - Smooth breathing animation with slow rotation
 * - Organic per-particle drift for fluid movement
 */
@Composable
fun VoiceAssistantParticleView(
    amplitude: Float,
    isDarkMode: Boolean = isSystemInDarkTheme(),
    modifier: Modifier = Modifier,
) {
    // Generate particles once
    val particles = remember { generateRingParticles(PARTICLE_COUNT) }

    // Time for animation
    var time by remember { mutableFloatStateOf(0f) }

    // Update time continuously
    LaunchedEffect(Unit) {
        val startTime = System.currentTimeMillis()
        while (true) {
            time = (System.currentTimeMillis() - startTime) / 1000f
            kotlinx.coroutines.delay(16) // ~60 FPS
        }
    }

    // Base colors
    val baseColor = if (isDarkMode) {
        Color(1f, 0.6f, 0.1f) // Brighter golden for dark mode
    } else {
        Color(0.9f, 0.4f, 0.05f) // Richer orange for light mode
    }

    val activeColor = Color(1f, 0.55f, 0.15f) // Warm amber

    Canvas(modifier = modifier) {
        val centerX = size.width / 2
        val centerY = size.height / 2
        val scale = minOf(size.width, size.height) * 0.50f

        particles.forEach { particle ->
            drawParticle(
                particle = particle,
                time = time,
                amplitude = amplitude,
                centerX = centerX,
                centerY = centerY,
                scale = scale,
                baseColor = baseColor,
                activeColor = activeColor,
                isDarkMode = isDarkMode
            )
        }
    }
}

private data class Particle(
    val angle: Float,        // position around the ring (0 to 2π)
    val radialFactor: Float, // 0 = center, 1 = ring edge (biased toward 1)
    val seed: Float          // random seed for animation variation
)

private const val PARTICLE_COUNT = 2000

private fun generateRingParticles(count: Int): List<Particle> {
    val random = Random(42) // Fixed seed for consistent generation
    return (0 until count).map {
        val angle = random.nextFloat() * PI.toFloat() * 2f
        // Power distribution biased toward the ring edge:
        // pow(0.35) makes most values cluster near 1.0 with a tail toward 0
        val radialFactor = 0.08f + random.nextFloat().pow(0.35f) * 1.05f
        Particle(
            angle = angle,
            radialFactor = radialFactor.coerceIn(0.05f, 1.15f),
            seed = random.nextFloat()
        )
    }
}

private fun DrawScope.drawParticle(
    particle: Particle,
    time: Float,
    amplitude: Float,
    centerX: Float,
    centerY: Float,
    scale: Float,
    baseColor: Color,
    activeColor: Color,
    isDarkMode: Boolean
) {
    val seed = particle.seed

    // === ROTATION (slow rotation of the whole ring) ===
    val rotation = time * 0.3f

    // === BREATHING (visible pulsing at all times) ===
    val breath = 1f + sin(time * 0.8f) * 0.04f

    // === PER-PARTICLE DRIFT (organic movement) ===
    val phaseOffset = seed * PI.toFloat() * 2f
    val angleDrift = sin(time * 0.5f + phaseOffset) * 0.025f
    val radialDrift = sin(time * 0.6f + phaseOffset * 1.3f) * 0.01f

    // === AMPLITUDE-DRIVEN RING EXPANSION ===
    val idleRadius = 0.32f
    val maxExpansion = 0.15f

    // Per-particle wave for organic movement (scales with amplitude)
    val waveEffect = sin(time * 2.5f + phaseOffset) * 0.03f * amplitude

    // Per-particle seed variation
    val seedVariation = (seed - 0.5f) * 0.04f * amplitude

    val ringRadius = (idleRadius + amplitude * maxExpansion + waveEffect + seedVariation) * breath

    // === FINAL POSITION ===
    val angle = particle.angle + rotation + angleDrift
    val radius = ringRadius * particle.radialFactor + radialDrift

    val x = cos(angle) * radius
    val y = sin(angle) * radius

    // Screen position
    val projX = centerX + x * scale
    val projY = centerY + y * scale

    // === SIZE (smaller for crisp dots, slightly bigger near edge) ===
    val edgeFactor = particle.radialFactor.coerceIn(0f, 1f)
    val baseSize = 1.2f + edgeFactor * 0.8f // 1.2 at center, 2.0 at edge
    val energyGlow = 1f + amplitude * 0.4f
    val particleSize = (baseSize * energyGlow * scale / 250f).coerceIn(1f, 5f)

    // === COLOR ===
    val energy = amplitude * 0.7f
    val particleColor = lerpColor(baseColor, activeColor, energy)

    // Brightness -- edge particles slightly brighter
    val edgeBright = 0.85f + edgeFactor * 0.15f
    val brightMultiplier = (if (isDarkMode) 1.5f + energy * 0.5f else 2.2f + energy * 0.6f) * edgeBright
    val finalColor = particleColor.copy(
        red = (particleColor.red * brightMultiplier).coerceIn(0f, 1f),
        green = (particleColor.green * brightMultiplier).coerceIn(0f, 1f),
        blue = (particleColor.blue * brightMultiplier).coerceIn(0f, 1f)
    )

    // === ALPHA (edge particles more opaque, inner particles more transparent) ===
    val baseAlpha = 0.3f + edgeFactor * 0.5f // 0.3 at center, 0.8 at edge
    val alpha = (baseAlpha + amplitude * 0.2f).coerceIn(0.2f, 1f)

    // === DRAW ===
    // Soft glow
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                finalColor.copy(alpha = alpha * 0.5f),
                finalColor.copy(alpha = alpha * 0.15f),
                finalColor.copy(alpha = 0f)
            ),
            center = Offset(projX, projY),
            radius = particleSize * 1.4f
        ),
        radius = particleSize * 1.4f,
        center = Offset(projX, projY)
    )

    // Core dot
    drawCircle(
        color = finalColor.copy(alpha = alpha),
        radius = particleSize,
        center = Offset(projX, projY)
    )
}

private fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = lerp(a.red, b.red, t),
    green = lerp(a.green, b.green, t),
    blue = lerp(a.blue, b.blue, t),
    alpha = lerp(a.alpha, b.alpha, t)
)
