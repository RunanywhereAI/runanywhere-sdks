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
 * Particles expand outward from center based on audio amplitude.
 * Responds to both voice input (microphone) and voice output (TTS).
 * Non-interactive (no tap/touch handling).
 *
 * Features:
 * - 400 particles distributed on a Fibonacci sphere
 * - Amplitude-driven expansion from center
 * - Smooth breathing animation with slow rotation
 * - Organic per-particle variation for fluid movement
 */
@Composable
fun VoiceAssistantParticleView(
    amplitude: Float,
    isDarkMode: Boolean = isSystemInDarkTheme(),
    modifier: Modifier = Modifier,
) {
    // Generate particles once
    val particles = remember { generateFibonacciSphereParticles(PARTICLE_COUNT) }

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
        val scale = minOf(size.width, size.height) * 0.35f

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
    val position: Triple<Float, Float, Float>, // x, y, z on unit sphere
    val index: Float, // 0-1 normalized index
    val radiusOffset: Float, // random offset for variation
    val seed: Float // random seed for animation variation
)

private const val PARTICLE_COUNT = 400

private fun generateFibonacciSphereParticles(count: Int): List<Particle> {
    val goldenRatio = (1.0 + sqrt(5.0)) / 2.0
    val angleIncrement = (PI * 2.0 * goldenRatio).toFloat()

    return (0 until count).map { i ->
        val t = i.toFloat() / (count - 1).toFloat()
        val inclination = acos(1f - 2f * t)
        val azimuth = angleIncrement * i

        val x = sin(inclination) * cos(azimuth)
        val y = sin(inclination) * sin(azimuth)
        val z = cos(inclination)

        Particle(
            position = Triple(x, y, z),
            index = i.toFloat() / count,
            radiusOffset = Random.nextFloat() * 2f - 1f,
            seed = Random.nextFloat()
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
    val (sphereX, sphereY, sphereZ) = particle.position
    val seed = particle.seed

    // === ROTATION (slow rotation for visual interest) ===
    val rotationAngle = -time * 0.2f
    val cosA = cos(rotationAngle)
    val sinA = sin(rotationAngle)
    val rotatedX = sphereX * cosA - sphereZ * sinA
    val rotatedY = sphereY
    val rotatedZ = sphereX * sinA + sphereZ * cosA

    // === BREATHING (visible pulsing at all times) ===
    val breath = 1f + sin(time * 0.8f) * 0.06f

    // === IDLE DRIFT (per-particle movement so they look alive at rest) ===
    val phaseOffset = seed * PI.toFloat() * 2f
    val driftX = sin(time * 0.6f + phaseOffset) * 0.04f
    val driftY = cos(time * 0.5f + phaseOffset * 1.3f) * 0.04f

    // === AMPLITUDE-DRIVEN EXPANSION FROM CENTER ===
    // At rest (amplitude ≈ 0): large sphere so individual particles are visible
    // With audio: particles expand further outward proportional to amplitude
    val idleRadius = 1.0f
    val maxExpansion = 0.5f

    // Per-particle wave effect for organic movement (scales with amplitude)
    val waveEffect = sin(time * 2.5f + phaseOffset) * 0.08f * amplitude

    // Per-particle seed variation (each particle expands slightly differently)
    val seedVariation = (seed - 0.5f) * 0.15f * amplitude

    val expansionRadius = (idleRadius + amplitude * maxExpansion + waveEffect + seedVariation) * breath

    val finalX = rotatedX * expansionRadius + driftX
    val finalY = rotatedY * expansionRadius + driftY
    val finalZ = rotatedZ * expansionRadius

    // === PROJECTION ===
    val z = finalZ + 2.5f
    val projScale = 0.85f
    val projX = centerX + (finalX / z) * projScale * scale
    val projY = centerY - (finalY / z) * projScale * scale // Flip Y

    // === SIZE ===
    val baseSize = 3f
    val energyGlow = 1f + amplitude * 0.4f
    val particleSize = (baseSize * (2.8f / z) * energyGlow * scale / 100f).coerceIn(2f, 8f)

    // === COLOR ===
    val energy = amplitude * 0.7f
    val particleColor = lerpColor(baseColor, activeColor, energy)

    // Brightness adjustment
    val brightMultiplier = if (isDarkMode) 1.5f + energy * 0.5f else 2.2f + energy * 0.6f
    val finalColor = particleColor.copy(
        red = (particleColor.red * brightMultiplier).coerceIn(0f, 1f),
        green = (particleColor.green * brightMultiplier).coerceIn(0f, 1f),
        blue = (particleColor.blue * brightMultiplier).coerceIn(0f, 1f)
    )

    // === ALPHA ===
    val depthShade = 0.5f + 0.5f * (1f - (z - 1.8f) / 2f)
    val alpha = (depthShade * (0.6f + amplitude * 0.4f)).coerceIn(0.3f, 1f)

    // === DRAW ===
    // Glow effect (subtle, so particles stay distinct)
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                finalColor.copy(alpha = alpha * 0.6f),
                finalColor.copy(alpha = alpha * 0.2f),
                finalColor.copy(alpha = 0f)
            ),
            center = Offset(projX, projY),
            radius = particleSize * 1.5f
        ),
        radius = particleSize * 1.5f,
        center = Offset(projX, projY)
    )

    // Core
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
