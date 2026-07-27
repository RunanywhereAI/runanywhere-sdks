package com.runanywhere.runanywhereai.ui.screens.diffusion

import ai.runanywhere.proto.v1.DiffusionMode
import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generateImage
import com.runanywhere.sdk.public.types.RADiffusionGenerationOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

/**
 * Text-to-image generation. Model download/load is owned by the shared
 * [com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet] /
 * [RuntimeModelSelection] path (same as STT / Vision). This VM only runs
 * [RunAnywhere.generateImage].
 */
class DiffusionViewModel(application: Application) : AndroidViewModel(application) {

    var prompt by mutableStateOf("a red apple")
        private set
    var isGenerating by mutableStateOf(false)
        private set
    var image by mutableStateOf<Bitmap?>(null)
        private set
    var lastLatencyMs by mutableStateOf<Long?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null

    fun onPromptChange(value: String) {
        prompt = value
    }

    fun generate() {
        if (isGenerating || prompt.isBlank()) return
        val text = prompt.trim()
        error = null
        isGenerating = true
        job = viewModelScope.launch {
            val start = System.currentTimeMillis()
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.IMAGE_GENERATION)
                val result = RunAnywhere.generateImage(
                    RADiffusionGenerationOptions(
                        prompt = text,
                        width = 256,
                        height = 256,
                        mode = DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
                    ),
                )
                val bmp = withContext(Dispatchers.Default) {
                    toBitmap(result.image_data.toByteArray(), result.width, result.height)
                }
                image = bmp
                lastLatencyMs = result.total_time_ms.takeIf { it > 0 }
                    ?: (System.currentTimeMillis() - start)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("diffusion generate failed", e)
                error = e.message ?: "Generation failed"
            } finally {
                isGenerating = false
            }
        }
    }

    /** Raw RGBA (row-major, R,G,B,A per pixel) -> ARGB_8888 Bitmap. */
    private fun toBitmap(rgba: ByteArray, width: Int, height: Int): Bitmap? {
        if (width <= 0 || height <= 0 || rgba.size < width * height * 4) return null
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val o = i * 4
            val r = rgba[o].toInt() and 0xFF
            val g = rgba[o + 1].toInt() and 0xFF
            val b = rgba[o + 2].toInt() and 0xFF
            val a = rgba[o + 3].toInt() and 0xFF
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
