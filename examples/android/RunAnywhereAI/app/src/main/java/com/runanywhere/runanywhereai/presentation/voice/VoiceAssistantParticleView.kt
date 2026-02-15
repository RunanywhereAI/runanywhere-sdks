package com.runanywhere.runanywhereai.presentation.voice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlinx.coroutines.delay
import kotlin.math.*
import kotlin.random.Random

// ============================================================
// VoiceAssistantParticleView.kt
//
// Single-file Kotlin Compose implementation matching the iOS
// Metal shader particle animation. Features:
//   - 2000 particles distributed on a Fibonacci sphere
//   - Sphere ↔ Ring morph transition on listening state
//   - Amplitude-driven ring expansion
//   - Localized touch/drag scatter
//   - Multi-layer ambient glow background
//   - Slow rotation + breathing + per-particle wander
// ============================================================

// MARK: - Data Structures

private data class ParticleVertex(
    val position: FloatArray, // x, y, z on unit sphere
    val index: Float,         // normalized index 0..1
    val radiusOffset: Float,  // random offset for ring thickness
    val seed: Float           // random seed for animation variation
)

// MARK: - Constants

private const val PARTICLE_COUNT = 2000

// MARK: - Particle Generation (Fibonacci Sphere)

private fun generateSphereParticles(count: Int): List<ParticleVertex> {
    val goldenRatio = (1.0 + sqrt(5.0)) / 2.0
    val angleIncrement = (PI * 2.0 * goldenRatio).toFloat()

    return (0 until count).map { i ->
        val t = i.toFloat() / (count - 1).toFloat()
        val inclination = acos(1f - 2f * t)
        val azimuth = angleIncrement * i

        val x = sin(inclination) * cos(azimuth)
        val y = sin(inclination) * sin(azimuth)
        val z = cos(inclination)

        ParticleVertex(
            position = floatArrayOf(x, y, z),
            index = i.toFloat() / count.toFloat(),
            radiusOffset = Random.nextFloat() * 2f - 1f,
            seed = Random.nextFloat()
        )
    }
}

// MARK: - Noise Functions (matching Metal shader)

private fun hash(n: Float): Float {
    return (sin(n) * 43758.5453123f).let { it - floor(it) }
}

private fun noise3D(x: Float, y: Float, z: Float): Float {
    val px = floor(x); val py = floor(y); val pz = floor(z)
    var fx = x - px; var fy = y - py; var fz = z - pz
    // Smoothstep
    fx = fx * fx * (3f - 2f * fx)
    fy = fy * fy * (3f - 2f * fy)
    fz = fz * fz * (3f - 2f * fz)
    val n = px + py * 57f + 113f * pz
    return lerp(
        lerp(
            lerp(hash(n), hash(n + 1f), fx),
            lerp(hash(n + 57f), hash(n + 58f), fx), fy
        ),
        lerp(
            lerp(hash(n + 113f), hash(n + 114f), fx),
            lerp(hash(n + 170f), hash(n + 171f), fx), fy
        ), fz
    )
}

// MARK: - Utility

private fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

private fun lerpColor(a: Color, b: Color, t: Float): Color = Color(
    red = lerp(a.red, b.red, t),
    green = lerp(a.green, b.green, t),
    blue = lerp(a.blue, b.blue, t),
    alpha = lerp(a.alpha, b.alpha, t)
)

private fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}

// MARK: - Particle Canvas (Core Animation)

@Composable
fun VoiceAssistantParticleCanvas(
    amplitude: Float,
    morphProgress: Float,
    scatterAmount: Float,
    touchPoint: Offset, // normalized -1..1
    isDarkMode: Boolean = isSystemInDarkTheme(),
    modifier: Modifier = Modifier,
) {
    val particles = remember { generateSphereParticles(PARTICLE_COUNT) }
    var time by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        val startTime = System.currentTimeMillis()
        while (true) {
            time = (System.currentTimeMillis() - startTime) / 1000f
            delay(16L)
        }
    }

    val baseColor = if (isDarkMode) {
        Color(0.75f, 0.45f, 0.08f)
    } else {
        Color(0.65f, 0.3f, 0.04f)
    }
    val activeColor = Color(0.8f, 0.42f, 0.12f)

    Canvas(modifier = modifier) {
        val centerX = size.width / 2f
        val centerY = size.height / 2f
        val viewScale = minOf(size.width, size.height) * 0.5f

        particles.forEach { particle ->
            drawMorphParticle(
                particle = particle,
                time = time,
                amplitude = amplitude,
                morphProgress = morphProgress,
                scatterAmount = scatterAmount,
                touchPoint = touchPoint,
                centerX = centerX,
                centerY = centerY,
                viewScale = viewScale,
                baseColor = baseColor,
                activeColor = activeColor,
                isDarkMode = isDarkMode
            )
        }
    }
}

private fun DrawScope.drawMorphParticle(
    particle: ParticleVertex,
    time: Float,
    amplitude: Float,
    morphProgress: Float,
    scatterAmount: Float,
    touchPoint: Offset,
    centerX: Float,
    centerY: Float,
    viewScale: Float,
    baseColor: Color,
    activeColor: Color,
    isDarkMode: Boolean
) {
    val seed = particle.seed
    val sx = particle.position[0]
    val sy = particle.position[1]
    val sz = particle.position[2]

    // === SPHERE STATE ===
    val sphereAngle = -time * 0.2f
    val cosA = cos(sphereAngle)
    val sinA = sin(sphereAngle)

    var rsx = sx * cosA - sz * sinA
    var rsy = sy
    var rsz = sx * sinA + sz * cosA

    val sphereBreath = 1f + sin(time * 1.0f) * 0.025f
    rsx *= sphereBreath
    rsy *= sphereBreath
    rsz *= sphereBreath

    // === RING STATE ===
    val ringAngle = particle.index * PI.toFloat() * 2f + time * 0.25f
    val baseRingRadius = 1.3f
    val audioPulse = amplitude * 0.4f
    val ringRadius = baseRingRadius + audioPulse + sin(time * 1.5f) * 0.03f +
            particle.radiusOffset * 0.18f

    val ringX = cos(ringAngle) * ringRadius
    val ringY = sin(ringAngle) * ringRadius
    val ringZ = 0f

    // === MORPH (sphere → ring) ===
    val personalSpeed = 0.6f + seed * 0.8f
    val personalMorph = (morphProgress * personalSpeed + (seed - 0.5f) * 0.3f).coerceIn(0f, 1f)
    var smoothMorph = personalMorph * personalMorph * (3f - 2f * personalMorph)
    smoothMorph = smoothMorph * smoothMorph * (3f - 2f * smoothMorph) // double smooth

    val wanderPhase = morphProgress * (1f - morphProgress) * 4f

    // Wander noise
    val wx = (noise3D(seed * 100f, time * 0.3f, 0f) - 0.5f) * wanderPhase * 0.6f
    val wy = (noise3D(seed * 100f + 50f, time * 0.3f, 0f) - 0.5f) * wanderPhase * 0.6f
    val wz = (noise3D(seed * 100f + 100f, time * 0.3f, 0f) - 0.5f) * wanderPhase * 0.6f

    // Spiral during transition
    val spiralAngle = seed * 6.28f + time * 0.5f
    val spiralRadius = wanderPhase * 0.25f
    val spiralX = cos(spiralAngle) * spiralRadius
    val spiralY = sin(spiralAngle) * spiralRadius

    // Interpolate sphere → ring
    var finalX = lerp(rsx, ringX, smoothMorph) + wx + spiralX
    var finalY = lerp(rsy, ringY, smoothMorph) + wy + spiralY
    var finalZ = lerp(rsz, ringZ, smoothMorph) + wz

    // === PERSPECTIVE PROJECTION ===
    val projScale = 0.85f
    val zDepth = finalZ + 2.5f

    var screenX = (finalX / zDepth) * projScale
    var screenY = (finalY / zDepth) * projScale

    // === TOUCH SCATTER ===
    val touchDist = sqrt(
        (screenX - touchPoint.x) * (screenX - touchPoint.x) +
                (screenY - touchPoint.y) * (screenY - touchPoint.y)
    )
    val touchRadius = 0.35f
    val touchInfluence = (1f - smoothstep(0f, touchRadius, touchDist)) * scatterAmount

    if (touchInfluence > 0.001f) {
        val pdx = screenX - touchPoint.x + 0.001f
        val pdy = screenY - touchPoint.y + 0.001f
        val pLen = sqrt(pdx * pdx + pdy * pdy)
        val pushDirX = pdx / pLen
        val pushDirY = pdy / pLen
        val pushAmount = touchInfluence * 0.15f

        finalX += pushDirX * pushAmount
        finalY += pushDirY * pushAmount
        finalX += (noise3D(seed * 200f, time * 2f, 0f) - 0.5f) * touchInfluence * 0.08f
        finalY += (noise3D(seed * 200f + 100f, time * 2f, 0f) - 0.5f) * touchInfluence * 0.08f

        // Recalculate screen position after scatter
        screenX = (finalX / zDepth) * projScale
        screenY = (finalY / zDepth) * projScale
    }

    // === SCREEN COORDINATES ===
    val aspectRatio = size.width / size.height
    val projX = centerX + screenX * viewScale
    val projY = centerY - screenY * viewScale * aspectRatio // flip Y, apply aspect

    // === SIZE ===
    val baseSize = 6f
    val transitionGlow = 1f + wanderPhase * 0.25f
    var pointSize = baseSize * (2.8f / zDepth) * transitionGlow
    pointSize *= (1f + touchInfluence * 0.2f)
    pointSize = pointSize.coerceIn(2f, 8f)
    val particleRadius = pointSize * viewScale / 400f // scale to view

    // === COLOR ===
    val energy = smoothMorph * (0.5f + amplitude * 0.5f)
    val particleColor = lerpColor(baseColor, activeColor, energy)

    val brightMultiplier = if (isDarkMode) {
        1.0f + energy * 0.3f + touchInfluence * 0.15f
    } else {
        1.3f + energy * 0.35f + touchInfluence * 0.15f
    }

    val finalColor = Color(
        red = (particleColor.red * brightMultiplier).coerceIn(0f, 1f),
        green = (particleColor.green * brightMultiplier).coerceIn(0f, 1f),
        blue = (particleColor.blue * brightMultiplier).coerceIn(0f, 1f)
    )

    // === ALPHA ===
    val depthShade = 0.5f + 0.5f * (1f - (zDepth - 1.8f) / 2f)
    val finalAlpha = lerp(depthShade * 0.6f, 0.85f, smoothMorph).coerceIn(0.1f, 0.85f)

    // === DRAW ===
    // Glow
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                finalColor.copy(alpha = finalAlpha * 0.3f),
                finalColor.copy(alpha = finalAlpha * 0.08f),
                finalColor.copy(alpha = 0f)
            ),
            center = Offset(projX, projY),
            radius = particleRadius * 1.5f
        ),
        radius = particleRadius * 1.5f,
        center = Offset(projX, projY)
    )

    // Core
    drawCircle(
        color = finalColor.copy(alpha = finalAlpha),
        radius = particleRadius,
        center = Offset(projX, projY)
    )
}
