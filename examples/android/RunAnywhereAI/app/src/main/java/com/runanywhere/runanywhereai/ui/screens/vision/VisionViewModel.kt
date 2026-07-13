package com.runanywhere.runanywhereai.ui.screens.vision

import ai.runanywhere.proto.v1.VLMImageFormat
import ai.runanywhere.proto.v1.VLMResult
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
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.cancellation.CancellationException

data class VlmMetrics(
    val tokens: Int,
    val tokensPerSecond: Double,
    val processingMs: Long,
    val imageEncodeMs: Long,
    val ttftMs: Long,
)

class VisionViewModel(application: Application) : AndroidViewModel(application) {

    var image by mutableStateOf<Bitmap?>(null)
        private set
    var prompt by mutableStateOf(DEFAULT_VISION_PROMPT)
        private set
    var description by mutableStateOf("")
        private set
    var isGenerating by mutableStateOf(false)
        private set
    var metrics by mutableStateOf<VlmMetrics?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null
    private var watchdog: Job? = null

    fun onImagePicked(bitmap: Bitmap?) {
        if (bitmap == null) return
        if (isGenerating) stop()
        image = bitmap
        description = ""
        metrics = null
        error = null
    }

    fun onPromptChange(value: String) {
        prompt = value
    }

    fun describe() {
        val bitmap = image ?: return
        val requestPrompt = prompt.trim()
        // Derive the answer mode from the current prompt at generate time rather
        // than latching it on edit: the default describe prompt gets the larger
        // detailed-description budget, any custom prompt is a focused question.
        val requestMode = if (requestPrompt == DEFAULT_VISION_PROMPT) {
            VisionAnswerMode.DETAILED_DESCRIPTION
        } else {
            VisionAnswerMode.FOCUSED_QUESTION
        }
        if (isGenerating || requestPrompt.isBlank()) return
        description = ""
        metrics = null
        error = null
        isGenerating = true
        startWatchdog()
        job = viewModelScope.launch {
            var file: File? = null
            try {
                file = withContext(Dispatchers.IO) { writeJpegToCache(bitmap) }
                val vlmImage = RAVLMImage(
                    file_path = file.absolutePath,
                    format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
                )
                val result = withContext(Dispatchers.Default) {
                    val activeModel = RuntimeModelSelection.requireCurrent(ModelSelectionContext.VLM)
                    val options = VisionGenerationPolicy.options(
                        prompt = requestPrompt,
                        model = activeModel.model,
                        mode = requestMode,
                        userLimit = SettingsRepository.settings.maxTokens,
                    )
                    // This screen presents one complete analysis card, so use the
                    // canonical result path. It returns the final caption and native
                    // metrics uniformly even when a backend's stream granularity is
                    // whole-response rather than token-by-token.
                    RunAnywhere.processImage(vlmImage, options)
                }
                description = result.toDisplayText()
                metrics = result.toUiMetrics()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("vlm describe failed", e)
                error = e.message ?: "Vision failed"
            } finally {
                // Native call unwound: clear the busy guard and stand down the
                // watchdog so it never fires against a completed request.
                watchdog?.cancel()
                isGenerating = false
                file?.delete()
            }
        }
    }

    fun stop() {
        job?.cancel()
        viewModelScope.launch { runCatching { RunAnywhere.cancelVLMGeneration() } }
        // Keep the busy guard raised until the native call actually unwinds in
        // the job's finally block. Clearing it here lets a second request race
        // the still-running lifecycle component and fail with INVALID_STATE.
        // The watchdog started in describe() is the backstop: if a hung native
        // VLM call never unwinds, it force-clears the guard so image-pick,
        // model-switch and Live mode cannot stay permanently wedged.
    }

    /**
     * Force-clears the busy guard if a request never unwinds. A non-cancellable
     * processImage JNI call can outlive its coroutine's cancellation, leaving the
     * job's finally block unreached and isGenerating stuck true forever. This
     * timeout is a UI backstop (not a native cancel) that surfaces a timed-out
     * error and re-enables the screen; it runs independently of [job].
     */
    private fun startWatchdog() {
        watchdog?.cancel()
        watchdog = viewModelScope.launch {
            delay(GENERATION_TIMEOUT_MS)
            if (isGenerating) {
                job?.cancel()
                runCatching { RunAnywhere.cancelVLMGeneration() }
                isGenerating = false
                error = "Vision timed out"
            }
        }
    }

    override fun onCleared() {
        watchdog?.cancel()
        job?.cancel()
    }

    private fun writeJpegToCache(bitmap: Bitmap): File {
        val file = File.createTempFile("vlm_", ".jpg", getApplication<Application>().cacheDir)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return file
    }

    private companion object {
        // Generous ceiling: a full detailed description on the slowest supported
        // VLM stays well under this, so only a genuinely hung native call trips it.
        const val GENERATION_TIMEOUT_MS = 120_000L
    }
}

internal fun VLMResult.toUiMetrics(): VlmMetrics =
    VlmMetrics(
        tokens = completion_tokens,
        tokensPerSecond = tokens_per_second.toDouble(),
        processingMs = processing_time_ms,
        imageEncodeMs = image_encode_time_ms,
        ttftMs = time_to_first_token_ms,
    )

internal fun VLMResult.toDisplayText(): String = text.ifBlank { "I could not read that image." }
