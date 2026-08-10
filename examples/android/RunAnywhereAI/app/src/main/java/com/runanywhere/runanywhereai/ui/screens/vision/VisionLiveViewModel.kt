package com.runanywhere.runanywhereai.ui.screens.vision

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.GenerationEvent
import com.runanywhere.sdk.public.api.GenerationResult
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.vlm
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException

/** Whether the live view keeps captioning on its own, or waits to be asked. */
enum class LiveCaptureMode { CONTINUOUS, MANUAL }

/** What the camera itself is doing, which is independent of what the model is doing. */
sealed interface LiveCameraState {
    /** Permission is held and CameraX is being asked for a provider. */
    data object Starting : LiveCameraState

    /** Preview and analyzer are bound; frames are arriving. */
    data object Ready : LiveCameraState

    /**
     * No usable camera. [message] is user-facing.
     *
     * This state exists because the bind failure used to be swallowed: the preview stayed a
     * black rectangle with a LIVE badge on it and a caption reading "Point the camera at a
     * scene…", which is the app claiming to see something it cannot.
     */
    data class Unavailable(val message: String) : LiveCameraState
}

/**
 * The handoff between the CameraX analyzer thread and the caption loop.
 *
 * The analyzer used to convert *every* frame — an `ImageProxy.toBitmap()` plus a rotation copy,
 * thirty times a second — so that one of them, every two and a half seconds, could be captioned.
 * The other seventy-four were allocated and dropped. [arm] is a one-shot latch, so a bitmap is
 * materialised only when the loop is about to ask for one.
 */
class LiveFrameSink {
    private val wanted = AtomicBoolean(false)
    private val frame = AtomicReference<Bitmap?>(null)

    /** Ask for one frame; the next analyzed frame after this call fills the slot. */
    fun arm() {
        frame.set(null)
        wanted.set(true)
    }

    /** Analyzer thread: materialise a frame only if one was asked for. */
    fun offer(convert: () -> Bitmap?) {
        if (!wanted.compareAndSet(true, false)) return
        val converted = convert()
        // A dropped conversion re-arms rather than resolving as "no frame": one bad frame in a
        // live stream is normal and the next one is milliseconds away.
        if (converted == null) wanted.set(true) else frame.set(converted)
    }

    /** Take the armed frame, or null when none has arrived yet. */
    fun take(): Bitmap? = frame.getAndSet(null)

    fun reset() {
        wanted.set(false)
        frame.set(null)
    }
}

/**
 * The live-camera half of the Vision screen.
 *
 * The caption loop used to live inside the composable as a `LaunchedEffect` that spooled cache
 * files and called the VLM directly, which put inference, cancellation and error handling in the
 * one place none of them survive a recomposition. It is here so that stopping mid-stream,
 * switching between continuous and single-shot, and a camera that never binds are all states
 * with owners.
 */
class VisionLiveViewModel(application: Application) : AndroidViewModel(application) {

    /** Written by the CameraX analyzer, read by the caption loop. */
    val frames = LiveFrameSink()

    var captureMode by mutableStateOf(LiveCaptureMode.CONTINUOUS)
        private set

    var cameraState by mutableStateOf<LiveCameraState>(LiveCameraState.Starting)
        private set

    var caption by mutableStateOf("")
        private set

    var status by mutableStateOf<VisionRunStatus>(VisionRunStatus.Idle)
        private set

    /** Counters from the most recent finished caption, kept so the rate survives the next run. */
    var lastMetrics by mutableStateOf<VlmMetrics?>(null)
        private set

    private var runner: Job? = null
    private var modelId: String? = null

    fun onCameraReady() {
        cameraState = LiveCameraState.Ready
        if (captureMode == LiveCaptureMode.CONTINUOUS) startRunner()
    }

    fun onCameraUnavailable(message: String) {
        cameraState = LiveCameraState.Unavailable(message)
        frames.reset()
        runner?.cancel()
        runner = null
        status = VisionRunStatus.Idle
    }

    /** The screen reports which vision model is resident; null means none. */
    fun onModelChanged(id: String?) {
        if (modelId == id) return
        modelId = id
        caption = ""
        lastMetrics = null
        status = VisionRunStatus.Idle
        if (id != null && captureMode == LiveCaptureMode.CONTINUOUS) startRunner()
    }

    /** Turn continuous captioning on or off. Off leaves single-shot capture available. */
    fun setAutoCapture(enabled: Boolean) {
        val mode = if (enabled) LiveCaptureMode.CONTINUOUS else LiveCaptureMode.MANUAL
        if (captureMode == mode) return
        captureMode = mode
        // Switching to single-shot lets the caption already in flight finish — the loop checks
        // the mode between passes — so the toggle never throws away work the user watched start.
        if (enabled) startRunner()
    }

    /** Caption one frame now. The only way to run in single-shot mode. */
    fun captureOnce() {
        startRunner()
    }

    fun stop() {
        // A Stop that lets a continuous loop restart itself two seconds later is not a stop, so
        // this drops to single-shot first and hands the decision of when to resume to the user.
        // It runs even when nothing is mid-inference, because in continuous mode the button is
        // just as often pressed during the pause between two captions.
        captureMode = LiveCaptureMode.MANUAL
        val active = runner ?: return
        if (!active.isActive) return
        if (status.isRunning) status = VisionRunStatus.Stopping
        active.cancel()
    }

    /**
     * Live mode left the screen.
     *
     * The view model outlives the composable (it is scoped to the nav entry so a Photo/Live
     * round-trip keeps its caption), which means nothing else would ever stop the loop: leaving
     * Live used to release the camera and leave the caption loop grinding against a sink that
     * would never be filled again.
     */
    fun onLeaveLiveMode() {
        runner?.cancel()
        runner = null
        frames.reset()
        cameraState = LiveCameraState.Starting
        if (status.isBusy) status = VisionRunStatus.Cancelled
    }

    override fun onCleared() {
        runner?.cancel()
        frames.reset()
        liveFrameFile().delete()
    }

    private fun startRunner() {
        if (runner?.isActive == true) return
        if (modelId == null || cameraState !is LiveCameraState.Ready) return
        runner = viewModelScope.launch {
            do {
                captionOneFrame()
                if (captureMode != LiveCaptureMode.CONTINUOUS) break
                delay(LIVE_INTERVAL_MS)
            } while (captureMode == LiveCaptureMode.CONTINUOUS)
        }
    }

    private suspend fun captionOneFrame() {
        if (modelId == null || cameraState !is LiveCameraState.Ready) return
        status = VisionRunStatus.Running
        val startedAt = System.currentTimeMillis()
        try {
            val frame = awaitFrame()
            if (frame == null) {
                status = VisionRunStatus.Failed("The camera did not deliver a frame.")
                return
            }
            val path = withContext(Dispatchers.IO) { writeFrame(frame) }
            val settings = SettingsRepository.settings
            val activeModel = RuntimeModelSelection.requireCurrent(ModelSelectionContext.VLM)
            val options = VisionGenerationPolicy.options(
                model = activeModel.model,
                mode = VisionAnswerMode.LIVE_CAPTION,
                userLimit = settings.maxTokens,
                // Honour the app-wide system prompt for persona, but the tight LIVE_CAPTION
                // token cap keeps each frame quick.
                systemPrompt = settings.systemPrompt,
            )
            var completed: GenerationResult? = null
            var streamed = ""
            RunAnywhere.vlm.generateStream(ImageInput.file(path), LIVE_PROMPT, options)
                .collect { event ->
                    when (event) {
                        is GenerationEvent.TextDelta -> {
                            streamed += event.text
                            caption = streamed
                        }
                        is GenerationEvent.Completed -> completed = event.result
                        is GenerationEvent.Failed -> throw event.error
                        else -> Unit
                    }
                }
            val result = completed
            if (result == null) {
                status = VisionRunStatus.Failed("The caption stream ended early.")
                return
            }
            if (result.text.isNotBlank()) caption = result.text
            val metrics = result.toUiMetrics(System.currentTimeMillis() - startedAt)
            lastMetrics = metrics
            status = VisionRunStatus.Done(
                metrics = metrics,
                truncated = VisionGenerationPolicy.wasTruncated(
                    options,
                    result.finishReason,
                    result.outputTokens,
                ),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("live caption failed", e)
            status = VisionRunStatus.Failed(e.userFacingVisionMessage())
        } finally {
            if (status is VisionRunStatus.Stopping) status = VisionRunStatus.Cancelled
        }
    }

    /**
     * Arm the sink and wait for the analyzer to fill it.
     *
     * Polling rather than a suspending handoff because the producer is a CameraX executor
     * callback, and a frame is at most one display refresh away — a channel here would be more
     * machinery for the same wait.
     */
    private suspend fun awaitFrame(): Bitmap? {
        frames.arm()
        var waited = 0L
        while (waited < FRAME_WAIT_TIMEOUT_MS) {
            frames.take()?.let { return it }
            delay(FRAME_POLL_MS)
            waited += FRAME_POLL_MS
        }
        return frames.take()
    }

    private fun writeFrame(frame: Bitmap): String {
        val file = liveFrameFile()
        FileOutputStream(file).use { frame.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }
        return file.absolutePath
    }

    /** One reused path: the VLM ABI takes images by file, and live mode overwrites per frame. */
    private fun liveFrameFile(): File = File(getApplication<Application>().cacheDir, "vlm_live.jpg")

    private companion object {
        /** Pause between captions so the cadence stays responsive without pinning the CPU. */
        const val LIVE_INTERVAL_MS = 2_500L
        const val FRAME_WAIT_TIMEOUT_MS = 3_000L
        const val FRAME_POLL_MS = 50L
        const val JPEG_QUALITY = 90
        const val LIVE_PROMPT = "Describe what you see in one sentence."
    }
}
