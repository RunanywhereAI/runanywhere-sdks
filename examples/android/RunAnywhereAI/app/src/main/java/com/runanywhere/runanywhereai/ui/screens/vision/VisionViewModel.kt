package com.runanywhere.runanywhereai.ui.screens.vision

import ai.runanywhere.proto.v1.VLMImageFormat
import ai.runanywhere.proto.v1.VLMStreamEventKind
import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
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
    var prompt by mutableStateOf("Describe this image in detail.")
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

    fun onImagePicked(bitmap: Bitmap?) {
        if (bitmap == null) return
        image = bitmap
        description = ""
        error = null
    }

    fun onPromptChange(value: String) {
        prompt = value
    }

    fun describe() {
        val bitmap = image ?: return
        if (isGenerating || prompt.isBlank()) return
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
                val options = RAVLMGenerationOptions(prompt = prompt.trim(), max_tokens = 300, temperature = 0.7f)
                // Typed VLM stream: TOKEN events carry text; the terminal
                // COMPLETED event carries the engine-measured VLMResult, so
                // metrics come from the SDK instead of wall-clock math.
                RunAnywhere.processImageStream(vlmImage, options).collect { event ->
                    when (event.kind) {
                        VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN ->
                            if (event.token.isNotEmpty()) description += event.token
                        VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                            val result = event.result ?: return@collect
                            if (result.text.isNotBlank()) description = result.text
                            metrics = VlmMetrics(
                                tokens = result.completion_tokens,
                                tokensPerSecond = result.tokens_per_second.toDouble(),
                                processingMs = result.processing_time_ms,
                                imageEncodeMs = result.image_encode_time_ms,
                                ttftMs = result.time_to_first_token_ms,
                            )
                        }
                        else -> {}
                    }
                }
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
        isGenerating = false
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
