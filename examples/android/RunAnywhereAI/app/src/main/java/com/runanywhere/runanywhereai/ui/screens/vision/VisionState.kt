package com.runanywhere.runanywhereai.ui.screens.vision

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap

/** Native counters for one finished vision request. */
data class VlmMetrics(
    val tokens: Int,
    val tokensPerSecond: Double,
    val processingMs: Long,
    val ttftMs: Long,
)

/**
 * What a vision request is doing, as one value rather than four booleans.
 *
 * The screen used to infer its state from `isGenerating` plus a blank-vs-non-blank description
 * plus a nullable metrics object plus a nullable error string. Sixteen combinations existed for
 * five real outcomes, and two of them — cancelled, and finished-with-no-text — rendered as
 * nothing at all: the user pressed Stop and the screen simply went quiet. A closed set of states
 * means every outcome has to be given a sentence before it can compile.
 */
sealed interface VisionRunStatus {
    /** Nothing has run for the current image yet. */
    data object Idle : VisionRunStatus

    /** In flight. Text may already be streaming into the answer pane. */
    data object Running : VisionRunStatus

    /**
     * Stop was pressed and the native call is unwinding.
     *
     * A distinct state rather than an immediate jump to [Cancelled] because the busy guard has
     * to stay raised until the decoder has actually let go: clearing it the instant the button
     * is tapped lets the next request race a still-running lifecycle component and fail with
     * INVALID_STATE, which the user reads as "Stop broke it".
     */
    data object Stopping : VisionRunStatus

    /**
     * Finished normally. [metrics] are the backend's own counters.
     *
     * [truncated] when generation stopped because it reached the output budget rather than
     * because the model had finished. The answer then ends mid-sentence — often mid-word — and a
     * screen that says nothing about it presents our own cap as the model breaking off.
     */
    data class Done(val metrics: VlmMetrics, val truncated: Boolean = false) : VisionRunStatus

    /** Stopped by the user mid-stream. Whatever arrived before the stop is kept. */
    data object Cancelled : VisionRunStatus

    /** Failed. [message] is already a sentence fit to show. */
    data class Failed(val message: String) : VisionRunStatus
}

/** The request is producing text right now — the moment Stop is the honest affordance. */
val VisionRunStatus.isRunning: Boolean get() = this is VisionRunStatus.Running

/** In flight *or* tearing down: nothing new may be submitted, nothing may be swapped underneath. */
val VisionRunStatus.isBusy: Boolean
    get() = this is VisionRunStatus.Running || this is VisionRunStatus.Stopping

/** An image the screen is holding, with the name it was picked or captured under. */
data class StagedVisionImage(
    val bitmap: Bitmap,
    /** Provider display name, or a stand-in — shown so the user can tell two photos apart. */
    val name: String,
)

/**
 * Whether this device can hand the app a camera at all.
 *
 * `android.hardware.camera.any` is declared `required="false"` in the manifest so the app
 * installs on camera-less devices, which makes checking it here mandatory rather than
 * defensive: launching the system capture intent on such a device throws
 * `ActivityNotFoundException`, so a Camera button that does not consult this crashes instead
 * of explaining itself.
 */
fun Context.hasAnyCamera(): Boolean =
    packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
