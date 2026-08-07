package com.runanywhere.runanywhereai.ui.theme

import android.provider.Settings
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode

/**
 * The single motion vocabulary for the app, pinned to `examples/DESIGN_GUIDELINE.md` §6.
 *
 * Four duration tiers and four springs, shared verbatim with the iOS and Web apps so the
 * same interaction moves at the same speed on every platform. A duration that is not one
 * of these tiers is a bug, not a preference — that is why the tiers are the only public
 * entry point and raw `tween(220)`-style literals do not appear at call sites.
 *
 * Every discrete helper here is reduce-motion aware: when the user has turned animation
 * off, discrete motion collapses to a 150 ms crossfade (perceived, not blinked past) and
 * repeating motion is *suppressed entirely* rather than shortened — a looping animation
 * that has merely been made faster still loops forever. Read
 * [LocalReduceMotion] for the flag; use [ambient] for anything that repeats.
 */
object AppMotion {

    // ---- §6.1 Duration tiers -------------------------------------------------------

    /** Tap feedback, chip/toggle selection, icon swap. Below ~100 ms reads as a jump. */
    const val MICRO = 120

    /** The default: row insert/remove, disclosure, most state changes. */
    const val STANDARD = 240

    /** Sheets, hero swaps, anything crossing a layout boundary. */
    const val EMPHASIS = 400

    /** Once-per-session brand moments only (launch, first successful load). */
    const val HERO = 700

    /** §6.5 — what a discrete animation collapses to when motion is reduced. */
    const val REDUCED = 150

    // ---- §6.4 Ambient periods (linear, exempt from the tiers) -----------------------

    /** Breathing/pulse period. */
    const val AMBIENT_BREATHE = 1600

    /** Shimmer sweep period. */
    const val AMBIENT_SHIMMER = 1200

    /** Spinner rotation period. */
    const val AMBIENT_SPIN = 1000

    // ---- §6.3 Eases ----------------------------------------------------------------

    /** Entrances and settle-to-rest. The workhorse. */
    val EaseOut: Easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)

    /** Moves where both ends matter — a value ticking, a bar filling. */
    val EaseInOut: Easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)

    /** Exits only. Starts too slow to feel responsive on an entrance. */
    val EaseIn: Easing = CubicBezierEasing(0.4f, 0f, 1f, 1f)

    /** The stand-in for [springBouncy]. Same restriction: arrival only. */
    val EaseSpring: Easing = CubicBezierEasing(0.34f, 1.4f, 0.64f, 1f)

    // ---- §6.2 Springs --------------------------------------------------------------
    // stiffness ~= (2*pi / response)^2, dampingRatio == dampingFraction.

    private const val STIFFNESS_SNAPPY = 500f
    private const val STIFFNESS_STANDARD = 225f
    private const val STIFFNESS_GENTLE = 110f
    private const val STIFFNESS_BOUNCY = 275f

    /** Direct manipulation — the thing you just touched. Barely overshoots. */
    fun <T> springSnappy(): FiniteAnimationSpec<T> =
        spring(dampingRatio = 0.86f, stiffness = STIFFNESS_SNAPPY)

    /** The default spring, for state that changes on its own. */
    fun <T> springDefault(): FiniteAnimationSpec<T> =
        spring(dampingRatio = 0.82f, stiffness = STIFFNESS_STANDARD)

    /** Large soft travel — sheets, full-screen transitions. */
    fun <T> springGentle(): FiniteAnimationSpec<T> =
        spring(dampingRatio = 0.86f, stiffness = STIFFNESS_GENTLE)

    /**
     * Deliberate overshoot for arrival and success **only**. On a progress bar or
     * spinner a bounce reads as instability (§6.2).
     */
    fun <T> springBouncy(): FiniteAnimationSpec<T> =
        spring(dampingRatio = 0.66f, stiffness = STIFFNESS_BOUNCY)

    // ---- Tweens ---------------------------------------------------------------------

    fun <T> micro(): FiniteAnimationSpec<T> = tween(MICRO, easing = EaseOut)

    fun <T> standard(): FiniteAnimationSpec<T> = tween(STANDARD, easing = EaseOut)

    fun <T> emphasis(): FiniteAnimationSpec<T> = tween(EMPHASIS, easing = EaseOut)

    fun <T> hero(): FiniteAnimationSpec<T> = tween(HERO, easing = EaseOut)

    /** Exits. Paired with [standard] on the way in. */
    fun <T> exit(): FiniteAnimationSpec<T> = tween(MICRO, easing = EaseIn)

    /** A value ticking or a bar filling, where both ends matter. */
    fun <T> value(): FiniteAnimationSpec<T> = tween(STANDARD, easing = EaseInOut)

    /** The reduce-motion substitute: perceptible, but not animation. */
    fun <T> reduced(): FiniteAnimationSpec<T> = tween(REDUCED, easing = LinearEasing)

    /**
     * §6.4 — a repeating spec at one of the canonical periods, always linear because
     * anything eased reads as a stutter when it loops.
     */
    fun <T> ambient(periodMillis: Int, mode: RepeatMode = RepeatMode.Reverse): AnimationSpec<T> =
        infiniteRepeatable(tween(periodMillis, easing = LinearEasing), mode)
}

/**
 * True when the user has turned system animation off
 * (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`), per §6.5. Provided by
 * [RunAnywhereAITheme] so no composable has to reach for a ContentResolver.
 */
val LocalReduceMotion: ProvidableCompositionLocal<Boolean> = compositionLocalOf { false }

@Composable
internal fun rememberSystemReduceMotion(): Boolean {
    val context = LocalContext.current
    val inspecting = LocalInspectionMode.current
    return remember(context, inspecting) {
        if (inspecting) {
            false
        } else {
            runCatching {
                Settings.Global.getFloat(
                    context.contentResolver,
                    Settings.Global.ANIMATOR_DURATION_SCALE,
                    1f,
                ) == 0f
            }.getOrDefault(false)
        }
    }
}

/**
 * Picks [spec] normally and a 150 ms crossfade when motion is reduced. Use this for any
 * discrete animation so the reduce-motion branch is impossible to forget.
 */
@Composable
fun <T> motionSpec(spec: () -> FiniteAnimationSpec<T>): FiniteAnimationSpec<T> =
    if (LocalReduceMotion.current) AppMotion.reduced() else spec()

/**
 * The period to use for repeating motion, or `null` when motion is reduced and the
 * animation must not run at all. Callers render the resting frame on `null`.
 */
@Composable
fun ambientPeriod(periodMillis: Int): Int? =
    if (LocalReduceMotion.current) null else periodMillis
