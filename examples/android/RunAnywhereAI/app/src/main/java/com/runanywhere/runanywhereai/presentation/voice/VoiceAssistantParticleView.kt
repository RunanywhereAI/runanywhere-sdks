package com.runanywhere.runanywhereai.presentation.voice

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlinx.coroutines.delay
import kotlin.math.*
import kotlin.random.Random

// VoiceAssistantParticleView
//
// Optimized particle animation for voice assistant.
// Performance-focused for smooth 60fps on low-memory devices.
//
// Features:
//   - ~900 particles on a Fibonacci sphere
//   - Sphere / Ring morph transition on listening state
//   - Amplitude-driven ring expansion
//   - Localized touch/drag scatter
//   - Batched point drawing (single draw call for most particles)
//   - Pre-computed per-frame values to avoid redundant trig
//   - Cheap noise replacement using pre-baked sin LUT

// Data

/**
 * Immutable particle data generated once. All fields are primitives
 * packed into a flat structure to keep allocations minimal.
 */
private class ParticleData(
    // Fibonacci sphere position
    val sx: Float, val sy: Float, val sz: Float,
    // Normalized index 0..1
    val index: Float,
    // Random offset for ring thickness
    val radiusOffset: Float,
    // Random seed for animation variation (0..1)
    val seed: Float,
    // Pre-computed phase offsets to avoid per-frame seed*constant multiplications
    val wanderPhaseX: Float,
    val wanderPhaseY: Float,
    val wanderPhaseZ: Float,
    val spiralPhase: Float,
    val personalSpeedFactor: Float,
    val personalMorphBias: Float,
)

// Constants

private const val PARTICLE_COUNT = 900
private const val TWO_PI = (PI * 2.0).toFloat()

// Sin look-up table for cheap noise (256 entries)
private val SIN_LUT = FloatArray(256) { sin(it.toFloat() / 256f * TWO_PI).toFloat() }

// Particle Generation (Fibonacci Sphere)

private fun generateParticles(count: Int): Array<ParticleData> {
    val goldenRatio = (1.0 + sqrt(5.0)) / 2.0
    val angleIncrement = (PI * 2.0 * goldenRatio).toFloat()
    val rng = Random(42) // Fixed seed for deterministic output

    return Array(count) { i ->
        val t = i.toFloat() / (count - 1).toFloat()
        val inclination = acos(1f - 2f * t)
        val azimuth = angleIncrement * i

        val seed = rng.nextFloat()

        ParticleData(
            sx = sin(inclination) * cos(azimuth),
            sy = sin(inclination) * sin(azimuth),
            sz = cos(inclination),
            index = i.toFloat() / count.toFloat(),
            radiusOffset = rng.nextFloat() * 2f - 1f,
            seed = seed,
            wanderPhaseX = seed * 100f,
            wanderPhaseY = seed * 100f + 50f,
            wanderPhaseZ = seed * 100f + 100f,
            spiralPhase = seed * TWO_PI,
            personalSpeedFactor = 0.6f + seed * 0.8f,
            personalMorphBias = (seed - 0.5f) * 0.3f,
        )
    }
}

// Cheap Noise (LUT-based, no sin() per call)

/** Fast hash via LUT – returns 0..1. */
@Suppress("NOTHING_TO_INLINE")
private inline fun fastHash(v: Float): Float {
    val idx = ((v * 73.7f).toInt() and 0xFF)
    return (SIN_LUT[idx] * 0.5f + 0.5f) // map -1..1 → 0..1
}

/**
 * Cheap 2D noise replacement. Much faster than the full 3D noise:
 * avoids 8 sin() calls and multiple floor/lerp chains.
 */
@Suppress("NOTHING_TO_INLINE")
private inline fun cheapNoise(phase: Float, time: Float): Float {
    val a = fastHash(phase + time * 0.97f)
    val b = fastHash(phase * 1.31f + time * 1.23f)
    return (a + b) * 0.5f // 0..1
}

// Utility

@Suppress("NOTHING_TO_INLINE")
private inline fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

@Suppress("NOTHING_TO_INLINE")
private inline fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}

// Per-Frame Shared State (computed once, used by all particles)

private class FrameState(
    val time: Float,
    val amplitude: Float,
    val morphProgress: Float,
    val scatterAmount: Float,
    val touchPoint: Offset,
    val centerX: Float,
    val centerY: Float,
    val viewScale: Float,
    val aspectRatio: Float,
    // Pre-computed rotation
    val cosA: Float,
    val sinA: Float,
    // Pre-computed breathing
    val sphereBreath: Float,
    // Pre-computed ring base
    val ringTimeOffset: Float,
    val baseRingWithPulse: Float,
    val ringTimeSin: Float,
    // Wander phase
    val wanderPhase: Float,
    // Slow time for noise (avoids multiplying per particle)
    val slowTime: Float,
    // Fast time for touch scatter noise
    val fastTime: Float,
    // Color
    val baseR: Float, val baseG: Float, val baseB: Float,
    val activeR: Float, val activeG: Float, val activeB: Float,
    val brightBase: Float,
    val brightEnergyScale: Float,
    // Whether touch scatter needs processing
    val hasScatter: Boolean,
)

private fun buildFrameState(
    time: Float,
    amplitude: Float,
    morphProgress: Float,
    scatterAmount: Float,
    touchPoint: Offset,
    centerX: Float,
    centerY: Float,
    viewScale: Float,
    width: Float,
    height: Float,
    isDarkMode: Boolean,
): FrameState {
    val sphereAngle = -time * 0.2f
    val wander = morphProgress * (1f - morphProgress) * 4f

    val baseColor = if (isDarkMode) {
        Triple(0.75f, 0.45f, 0.08f)
    } else {
        Triple(0.65f, 0.3f, 0.04f)
    }

    return FrameState(
        time = time,
        amplitude = amplitude,
        morphProgress = morphProgress,
        scatterAmount = scatterAmount,
        touchPoint = touchPoint,
        centerX = centerX,
        centerY = centerY,
        viewScale = viewScale,
        aspectRatio = width / height,
        cosA = cos(sphereAngle),
        sinA = sin(sphereAngle),
        sphereBreath = 1f + sin(time) * 0.025f,
        ringTimeOffset = time * 0.25f,
        baseRingWithPulse = 1.3f + amplitude * 0.4f,
        ringTimeSin = sin(time * 1.5f) * 0.03f,
        wanderPhase = wander,
        slowTime = time * 0.3f,
        fastTime = time * 2f,
        baseR = baseColor.first,
        baseG = baseColor.second,
        baseB = baseColor.third,
        activeR = 0.8f,
        activeG = 0.42f,
        activeB = 0.12f,
        brightBase = if (isDarkMode) 1.0f else 1.3f,
        brightEnergyScale = if (isDarkMode) 0.3f else 0.35f,
        hasScatter = scatterAmount > 0.001f,
    )
}

// Particle Canvas

@Composable
fun VoiceAssistantParticleCanvas(
    amplitude: Float,
    morphProgress: Float,
    scatterAmount: Float,
    touchPoint: Offset,
    isDarkMode: Boolean = isSystemInDarkTheme(),
    modifier: Modifier = Modifier,
) {
    val particles = remember { generateParticles(PARTICLE_COUNT) }
    var time by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        val startTime = System.nanoTime()
        while (true) {
            time = (System.nanoTime() - startTime) / 1_000_000_000f
            delay(16L)
        }
    }

    Canvas(modifier = modifier) {
        val cx = size.width / 2f
        val cy = size.height / 2f
        val vs = minOf(size.width, size.height) * 0.5f

        val frame = buildFrameState(
            time = time,
            amplitude = amplitude,
            morphProgress = morphProgress,
            scatterAmount = scatterAmount,
            touchPoint = touchPoint,
            centerX = cx,
            centerY = cy,
            viewScale = vs,
            width = size.width,
            height = size.height,
            isDarkMode = isDarkMode,
        )

        drawParticlesBatched(particles, frame)
    }
}

// Batched Drawing

/**
 * Draws all particles with minimal allocations.
 * Small particles are batched into a single drawPoints call.
 * Only larger/brighter particles get individual drawCircle calls.
 */
private fun DrawScope.drawParticlesBatched(
    particles: Array<ParticleData>,
    f: FrameState,
) {
    // Reusable lists for batched point drawing (avoid re-alloc each frame via sizing)
    val batchPoints = ArrayList<Offset>(particles.size)
    val batchColors = ArrayList<Color>(particles.size)

    val projScale = 0.85f
    val invViewScale400 = f.viewScale / 400f

    for (p in particles) {
        // Sphere rotation
        var rsx = p.sx * f.cosA - p.sz * f.sinA
        val rsy = p.sy
        var rsz = p.sx * f.sinA + p.sz * f.cosA
        rsx *= f.sphereBreath
        val rsyB = rsy * f.sphereBreath
        rsz *= f.sphereBreath

        // Ring position
        val ringAngle = p.index * TWO_PI + f.ringTimeOffset
        val ringRadius = f.baseRingWithPulse + f.ringTimeSin + p.radiusOffset * 0.18f
        val ringX = cos(ringAngle) * ringRadius
        val ringY = sin(ringAngle) * ringRadius

        // Morph
        val personalMorph = (f.morphProgress * p.personalSpeedFactor + p.personalMorphBias)
            .coerceIn(0f, 1f)
        var sm = personalMorph * personalMorph * (3f - 2f * personalMorph)
        sm = sm * sm * (3f - 2f * sm)

        // Wander + spiral (only during transition)
        var wx = 0f; var wy = 0f; var wz = 0f
        var spiralX = 0f; var spiralY = 0f
        if (f.wanderPhase > 0.01f) {
            wx = (cheapNoise(p.wanderPhaseX, f.slowTime) - 0.5f) * f.wanderPhase * 0.6f
            wy = (cheapNoise(p.wanderPhaseY, f.slowTime) - 0.5f) * f.wanderPhase * 0.6f
            wz = (cheapNoise(p.wanderPhaseZ, f.slowTime) - 0.5f) * f.wanderPhase * 0.6f
            val sa = p.spiralPhase + f.time * 0.5f
            val sr = f.wanderPhase * 0.25f
            spiralX = cos(sa) * sr
            spiralY = sin(sa) * sr
        }

        // Interpolate sphere to ring
        var finalX = lerp(rsx, ringX, sm) + wx + spiralX
        var finalY = lerp(rsyB, ringY, sm) + wy + spiralY
        val finalZ = lerp(rsz, 0f, sm) + wz

        // Perspective
        val zDepth = finalZ + 2.5f
        var screenX = (finalX / zDepth) * projScale
        var screenY = (finalY / zDepth) * projScale

        // Touch scatter (skip entirely when not active)
        var touchInfluence = 0f
        if (f.hasScatter) {
            val dx = screenX - f.touchPoint.x
            val dy = screenY - f.touchPoint.y
            val touchDist = sqrt(dx * dx + dy * dy)
            touchInfluence = (1f - smoothstep(0f, 0.35f, touchDist)) * f.scatterAmount

            if (touchInfluence > 0.001f) {
                val pdx = dx + 0.001f
                val pdy = dy + 0.001f
                val invLen = 1f / sqrt(pdx * pdx + pdy * pdy)
                val push = touchInfluence * 0.15f
                finalX += pdx * invLen * push +
                        (cheapNoise(p.seed * 200f, f.fastTime) - 0.5f) * touchInfluence * 0.08f
                finalY += pdy * invLen * push +
                        (cheapNoise(p.seed * 200f + 100f, f.fastTime) - 0.5f) * touchInfluence * 0.08f
                screenX = (finalX / zDepth) * projScale
                screenY = (finalY / zDepth) * projScale
            }
        }

        // Screen position
        val projX = f.centerX + screenX * f.viewScale
        val projY = f.centerY - screenY * f.viewScale * f.aspectRatio

        // Skip off-screen particles
        if (projX < -20f || projX > size.width + 20f ||
            projY < -20f || projY > size.height + 20f) continue

        // Size
        val transGlow = 1f + f.wanderPhase * 0.25f
        var pointSize = 6f * (2.8f / zDepth) * transGlow
        pointSize *= (1f + touchInfluence * 0.2f)
        pointSize = pointSize.coerceIn(2f, 8f)
        val radius = pointSize * invViewScale400

        // Color
        val energy = sm * (0.5f + f.amplitude * 0.5f)
        val bright = f.brightBase + energy * f.brightEnergyScale + touchInfluence * 0.15f
        val r = (lerp(f.baseR, f.activeR, energy) * bright).coerceIn(0f, 1f)
        val g = (lerp(f.baseG, f.activeG, energy) * bright).coerceIn(0f, 1f)
        val b = (lerp(f.baseB, f.activeB, energy) * bright).coerceIn(0f, 1f)

        // Alpha
        val depthShade = 0.5f + 0.5f * (1f - (zDepth - 1.8f) * 0.5f)
        val alpha = lerp(depthShade * 0.6f, 0.85f, sm).coerceIn(0.1f, 0.85f)

        val color = Color(r, g, b, alpha)

        // Small particles → batch as points (single draw call)
        // Larger particles → individual circle for glow effect
        if (radius <= 3f) {
            batchPoints.add(Offset(projX, projY))
            batchColors.add(color)
        } else {
            // Glow layer (single solid circle, no gradient allocation)
            drawCircle(
                color = color.copy(alpha = alpha * 0.2f),
                radius = radius * 1.4f,
                center = Offset(projX, projY)
            )
            // Core
            drawCircle(
                color = color,
                radius = radius,
                center = Offset(projX, projY)
            )
        }
    }

    // Batch draw all small particles in one call
    if (batchPoints.isNotEmpty()) {
        // drawPoints with StrokeCap.Round renders small circles efficiently
        drawPoints(
            points = batchPoints,
            pointMode = PointMode.Points,
            color = Color.Transparent, // overridden per-point below
            strokeWidth = 4f,
            cap = StrokeCap.Round,
        )
        // Unfortunately drawPoints doesn't support per-point color,
        // so we draw in color buckets for efficiency.
        // Group by quantized color to reduce draw calls.
        drawBatchedByColor(batchPoints, batchColors)
    }
}

/**
 * Draws batched points grouped by quantized color to minimize draw calls.
 * Colors are quantized to ~16 levels per channel to group similar particles.
 */
private fun DrawScope.drawBatchedByColor(
    points: List<Offset>,
    colors: List<Color>,
) {
    // Quantize colors into buckets (5-bit per channel = ~32 shades)
    val buckets = HashMap<Long, MutableList<Offset>>(32)

    for (i in points.indices) {
        val c = colors[i]
        // Quantize to 5 bits per channel for grouping
        val rq = (c.red * 31f).toInt().toLong()
        val gq = (c.green * 31f).toInt().toLong()
        val bq = (c.blue * 31f).toInt().toLong()
        val aq = (c.alpha * 15f).toInt().toLong()
        val key = (rq shl 15) or (gq shl 10) or (bq shl 5) or aq

        buckets.getOrPut(key) { ArrayList(points.size / 8) }.add(points[i])
    }

    for ((key, pts) in buckets) {
        val aq = (key and 0x1F).toFloat() / 15f
        val bq = ((key shr 5) and 0x1F).toFloat() / 31f
        val gq = ((key shr 10) and 0x1F).toFloat() / 31f
        val rq = ((key shr 15) and 0x1F).toFloat() / 31f
        val color = Color(rq, gq, bq, aq)

        drawPoints(
            points = pts,
            pointMode = PointMode.Points,
            color = color,
            strokeWidth = 4f,
            cap = StrokeCap.Round,
        )
    }
}
