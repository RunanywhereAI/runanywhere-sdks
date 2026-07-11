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
    private var answerMode = VisionAnswerMode.DETAILED_DESCRIPTION

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
        answerMode = VisionAnswerMode.FOCUSED_QUESTION
    }

    fun describe() {
        val bitmap = image ?: return
        val requestPrompt = prompt.trim()
        val requestMode = answerMode
        if (isGenerating || requestPrompt.isBlank()) return
        description = ""
        metrics = null
        error = null
        isGenerating = true
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
                description = result.text
                metrics = result.toUiMetrics()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("vlm describe failed", e)
                error = e.message ?: "Vision failed"
            } finally {
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
    }

    override fun onCleared() {
        job?.cancel()
    }

    private fun writeJpegToCache(bitmap: Bitmap): File {
        val file = File.createTempFile("vlm_", ".jpg", getApplication<Application>().cacheDir)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return file
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
