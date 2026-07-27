package com.runanywhere.runanywhereai.ui.screens.ocr

import ai.runanywhere.proto.v1.VLMImageFormat
import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.ui.screens.models.isDocumentOcrModel
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.processImage
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.coroutines.cancellation.CancellationException

/**
 * Document OCR / Parse through the existing VLM lifecycle (`processImage`).
 * Nemotron OCR suites use an empty prompt and a tiny decode budget — the
 * detector+recognizer pipeline returns the full document text in one shot.
 */
class OcrViewModel(application: Application) : AndroidViewModel(application) {

    var image by mutableStateOf<Bitmap?>(null)
        private set
    var extractedText by mutableStateOf("")
        private set
    var isExtracting by mutableStateOf(false)
        private set
    var latencyMs by mutableStateOf<Long?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var status by mutableStateOf("")
        private set

    private var job: Job? = null

    fun onImagePicked(bitmap: Bitmap?) {
        if (bitmap == null) return
        if (isExtracting) stop()
        image = bitmap
        extractedText = ""
        latencyMs = null
        error = null
        status = "Document ready (${bitmap.width}×${bitmap.height})."
    }

    fun extract() {
        val bitmap = image ?: run {
            error = "Pick a document photo first."
            return
        }
        if (isExtracting) return
        extractedText = ""
        latencyMs = null
        error = null
        isExtracting = true
        status = "Extracting text…"
        job = viewModelScope.launch {
            var file: File? = null
            val start = System.currentTimeMillis()
            try {
                val active = RuntimeModelSelection.requireCurrent(ModelSelectionContext.OCR)
                check(active.model.isDocumentOcrModel()) {
                    "${active.id} is not a document OCR model."
                }
                file = withContext(Dispatchers.IO) { writeJpegToCache(bitmap) }
                val options = OcrGenerationPolicy.options(active.model.id)
                val result = withContext(Dispatchers.Default) {
                    RunAnywhere.processImage(
                        RAVLMImage(
                            file_path = file.absolutePath,
                            format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
                        ),
                        options,
                    )
                }
                extractedText = result.text.trim()
                latencyMs = result.processing_time_ms.takeIf { it > 0 }
                    ?: (System.currentTimeMillis() - start)
                status = if (extractedText.isBlank()) {
                    "No text detected in this image."
                } else {
                    "Extracted ${extractedText.length} characters."
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("$TAG: OCR failed", e)
                error = e.message ?: "OCR failed"
                status = ""
            } finally {
                isExtracting = false
                file?.delete()
            }
        }
    }

    fun stop() {
        job?.cancel()
        viewModelScope.launch { runCatching { RunAnywhere.cancelVLMGeneration() } }
    }

    fun reportError(message: String) {
        error = message
    }

    override fun onCleared() {
        job?.cancel()
        // viewModelScope is already cancelling; use an independent scope so the
        // one-shot native cancel actually runs during teardown.
        CoroutineScope(Dispatchers.Default).launch {
            runCatching { RunAnywhere.cancelVLMGeneration() }
        }
    }

    private fun writeJpegToCache(bitmap: Bitmap): File {
        val file = File.createTempFile("ocr_", ".jpg", getApplication<Application>().cacheDir)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        return file
    }

    private companion object {
        const val TAG = "OcrVM"
    }
}

/** Suite-aligned generation options for Nemotron OCR / Parse. */
internal object OcrGenerationPolicy {
    fun options(modelId: String): RAVLMGenerationOptions {
        val parse = modelId.contains("parse", ignoreCase = true)
        return RAVLMGenerationOptions(
            // Suites use an empty prompt, but Wire omits "" so commons never sees
            // has_prompt and returns -259 INVALID_ARGUMENT ("prompt is required").
            // A single space is a no-op for the OCR detector+recognizer path.
            prompt = " ",
            // OCR returns the full document in one shot (suite max_new=1).
            // Parse is a longer structured decode — give it room for multi-page text.
            max_tokens = if (parse) 512 else 1,
            temperature = 0f,
            top_p = 0f,
            top_k = 0,
        )
    }
}
