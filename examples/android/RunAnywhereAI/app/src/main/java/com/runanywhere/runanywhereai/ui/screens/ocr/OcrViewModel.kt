package com.runanywhere.runanywhereai.ui.screens.ocr

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
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.vlm
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
                val result = RunAnywhere.vlm.generate(
                    ImageInput.file(file.absolutePath),
                    OcrGenerationPolicy.PROMPT,
                    options,
                )
                extractedText = result.text.trim()
                latencyMs = System.currentTimeMillis() - start
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
    }

    fun reportError(message: String) {
        error = message
    }

    override fun onCleared() {
        // Cancelling the job reaches the native VLM cancel through the SDK.
        job?.cancel()
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
    /**
     * Suites use an empty prompt, but an empty string is omitted on the wire and
     * commons then rejects the request as missing a prompt. A single space is a
     * no-op for the OCR detector+recognizer path.
     */
    const val PROMPT: String = " "

    fun options(modelId: String): LlmOptions {
        val parse = modelId.contains("parse", ignoreCase = true)
        return LlmOptions(
            // OCR returns the full document in one shot (suite max_new=1).
            // Parse is a longer structured decode — give it room for multi-page text.
            maxOutputTokens = if (parse) 512 else 1,
            temperature = 0f,
            topP = 0f,
            topK = 0,
        )
    }
}
