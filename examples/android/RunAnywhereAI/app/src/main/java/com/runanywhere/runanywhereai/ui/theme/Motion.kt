package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween

// iOS-inspired motion constants for smooth, fluid animations.
object AppMotion {

    // Durations (ms)
    const val DURATION_SHORT = 200
    const val DURATION_MEDIUM = 300
    const val DURATION_LONG = 450
    const val DURATION_EXTRA_LONG = 550

    // Easing curves
    val EaseInOut = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1.0f)
    val EaseOut = CubicBezierEasing(0.0f, 0.0f, 0.2f, 1.0f)
    val EaseIn = CubicBezierEasing(0.4f, 0.0f, 1.0f, 1.0f)
    val Snappy = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f)

    // Springs
    fun <T> springDefault() = spring<T>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = Spring.StiffnessMediumLow,
    )

    fun <T> springSnappy() = spring<T>(
        dampingRatio = 0.85f,
        stiffness = Spring.StiffnessMedium,
    )

    fun <T> springGentle() = spring<T>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = Spring.StiffnessLow,
    )

    fun <T> springBouncy() = spring<T>(
        dampingRatio = Spring.DampingRatioLowBouncy,
        stiffness = Spring.StiffnessMedium,
    )

    // Tweens
    fun <T> tweenShort() = tween<T>(
        durationMillis = DURATION_SHORT,
        easing = EaseOut,
    )

    fun <T> tweenMedium() = tween<T>(
        durationMillis = DURATION_MEDIUM,
        easing = EaseInOut,
    )

    fun <T> tweenLong() = tween<T>(
        durationMillis = DURATION_LONG,
        easing = EaseInOut,
    )

    fun <T> tweenExit() = tween<T>(
        durationMillis = DURATION_SHORT,
        easing = EaseIn,
    )
}
