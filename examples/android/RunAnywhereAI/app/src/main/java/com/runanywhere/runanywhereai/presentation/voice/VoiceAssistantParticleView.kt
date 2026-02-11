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
 * Ported from iOS VoiceAssistantParticleView.swift (Metal-based)
 * This is a Canvas-based Compose implementation that mimics the visual effect.
 *
 * Features:
 * - 2000 particles distributed on a Fibonacci sphere
 * - Morphs between sphere (idle) and ring (active) states
 * - Responds to audio amplitude
 * - Touch scatter effect
 * - Smooth breathing animation
 */
@Composable
fun VoiceAssistantParticleView(
    amplitude: Float,
    morphProgress: Float,
    scatterAmount: Float,
    touchPoint: Offset,
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
                morphProgress = morphProgress,
                amplitude = amplitude,
                scatterAmount = scatterAmount,
                touchPoint = touchPoint,
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
    val radiusOffset: Float, // random offset for ring variation
    val seed: Float // random seed for animation variation
)

private const val PARTICLE_COUNT = 800 // Reduced from iOS 2000 for performance

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
    morphProgress: Float,
    amplitude: Float,
    scatterAmount: Float,
    touchPoint: Offset,
    centerX: Float,
    centerY: Float,
    scale: Float,
    baseColor: Color,
    activeColor: Color,
    isDarkMode: Boolean
) {
    val (sphereX, sphereY, sphereZ) = particle.position
    val seed = particle.seed

    // === SPHERE STATE ===
    // Rotate sphere slowly
    val sphereAngle = -time * 0.2f
    val cosA = cos(sphereAngle)
    val sinA = sin(sphereAngle)

    var rotatedX = sphereX * cosA - sphereZ * sinA
    var rotatedY = sphereY
    var rotatedZ = sphereX * sinA + sphereZ * cosA

    // Breathing effect
    val breath = 1f + sin(time) * 0.025f
    rotatedX *= breath
    rotatedY *= breath
    rotatedZ *= breath

    // === RING STATE ===
    val ringAngle = particle.index * PI.toFloat() * 2f + time * 0.25f
    val baseRingRadius = 1.3f
    val audioPulse = amplitude * 0.4f
    val ringRadius = baseRingRadius + audioPulse + sin(time * 1.5f) * 0.03f + particle.radiusOffset * 0.18f

    val ringX = cos(ringAngle) * ringRadius
    val ringY = sin(ringAngle) * ringRadius
    val ringZ = 0f

    // === MORPH ===
    val personalSpeed = 0.6f + seed * 0.8f
    val personalMorph = (morphProgress * personalSpeed + (seed - 0.5f) * 0.3f).coerceIn(0f, 1f)
    // Double smoothstep for extra smooth transition
    var smoothMorph = personalMorph * personalMorph * (3f - 2f * personalMorph)
    smoothMorph = smoothMorph * smoothMorph * (3f - 2f * smoothMorph)

    // Wandering during transition
    val wanderPhase = morphProgress * (1f - morphProgress) * 4f
    val wanderX = (noise(seed * 100f, time * 0.3f) - 0.5f) * wanderPhase * 0.6f
    val wanderY = (noise(seed * 100f + 50f, time * 0.3f) - 0.5f) * wanderPhase * 0.6f
    val wanderZ = (noise(seed * 100f + 100f, time * 0.3f) - 0.5f) * wanderPhase * 0.6f

    // Spiral during transition
    val spiralAngle = seed * 6.28f + time * 0.5f
    val spiralRadius = wanderPhase * 0.25f
    val spiralX = cos(spiralAngle) * spiralRadius
    val spiralY = sin(spiralAngle) * spiralRadius

    // Interpolate between sphere and ring
    var finalX = lerp(rotatedX, ringX, smoothMorph) + wanderX + spiralX
    var finalY = lerp(rotatedY, ringY, smoothMorph) + wanderY + spiralY
    val finalZ = lerp(rotatedZ, ringZ, smoothMorph) + wanderZ

    // === TOUCH SCATTER ===
    if (scatterAmount > 0.001f) {
        // Calculate screen position
        val projScale = 0.85f
        val tempZ = finalZ + 2.5f
        val screenX = (finalX / tempZ) * projScale
        val screenY = (finalY / tempZ) * projScale

        // Distance from touch
        val dx = screenX - touchPoint.x
        val dy = screenY - touchPoint.y
        val touchDist = sqrt(dx * dx + dy * dy)

        // Affect particles near touch
        val touchRadius = 0.35f
        val touchInfluence = ((1f - (touchDist / touchRadius)).coerceIn(0f, 1f)) * scatterAmount

        if (touchInfluence > 0.001f) {
            // Push outward from touch
            val pushLen = sqrt(dx * dx + dy * dy) + 0.001f
            val pushX = dx / pushLen
            val pushY = dy / pushLen
            val pushAmount = touchInfluence * 0.15f

            finalX += pushX * pushAmount
            finalY += pushY * pushAmount
        }
    }

    // === PROJECTION ===
    val z = finalZ + 2.5f
    val projScale = 0.85f
    val projX = centerX + (finalX / z) * projScale * scale
    val projY = centerY - (finalY / z) * projScale * scale // Flip Y

    // === SIZE ===
    val baseSize = 3f
    val transitionGlow = 1f + wanderPhase * 0.4f
    val particleSize = (baseSize * (2.8f / z) * transitionGlow * scale / 100f).coerceIn(2f, 8f)

    // === COLOR ===
    val energy = smoothMorph * (0.5f + amplitude * 0.5f)
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
    val alpha = lerp(depthShade * 0.8f, 1f, smoothMorph).coerceIn(0.3f, 1f)

    // Draw particle with glow effect
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                finalColor.copy(alpha = alpha),
                finalColor.copy(alpha = alpha * 0.5f),
                finalColor.copy(alpha = 0f)
            ),
            center = Offset(projX, projY),
            radius = particleSize * 2f
        ),
        radius = particleSize * 2f,
        center = Offset(projX, projY)
    )

    // Core
    drawCircle(
        color = finalColor.copy(alpha = alpha),
        radius = particleSize,
        center = Offset(projX, projY)
    )
}

// Simple pseudo-random noise function
private fun noise(x: Float, y: Float): Float {
    val n = sin(x * 12.9898f + y * 78.233f) * 43758.5453f
    return n - floor(n)
}

private fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = lerp(a.red, b.red, t),
    green = lerp(a.green, b.green, t),
    blue = lerp(a.blue, b.blue, t),
    alpha = lerp(a.alpha, b.alpha, t)
)
