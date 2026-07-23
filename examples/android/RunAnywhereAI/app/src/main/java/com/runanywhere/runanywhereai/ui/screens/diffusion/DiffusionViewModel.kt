package com.runanywhere.runanywhereai.ui.screens.diffusion

import ai.runanywhere.proto.v1.DiffusionMode
import ai.runanywhere.proto.v1.ModelListRequest
import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.models.requiresHfAuth
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.extensions.generateImage
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RADiffusionGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

/** Where the cosmos3_edge_diffusion model is in its lifecycle for this screen. */
enum class DiffusionModelStage { UNKNOWN, NEEDS_TOKEN, NOT_DOWNLOADED, DOWNLOADING, LOADING, READY }

class DiffusionViewModel(application: Application) : AndroidViewModel(application) {

    var stage by mutableStateOf(DiffusionModelStage.UNKNOWN)
        private set
    var downloadPercent by mutableStateOf<Int?>(null)
        private set
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

    init {
        refresh()
    }

    fun onPromptChange(value: String) {
        prompt = value
    }

    /** Locate the diffusion model and update [stage] from download / token state. */
    fun refresh() {
        viewModelScope.launch {
            val model = findModel()
            if (stage == DiffusionModelStage.READY) return@launch   // keep a loaded model
            stage = when {
                model == null -> DiffusionModelStage.UNKNOWN
                needsToken(model) -> DiffusionModelStage.NEEDS_TOKEN
                else -> DiffusionModelStage.NOT_DOWNLOADED           // includes on-disk-but-not-loaded (button loads it)
            }
        }
    }

    /** Download (if needed) then load the model so generation can run. */
    fun prepare() {
        if (job?.isActive == true) return
        error = null
        job = viewModelScope.launch {
            try {
                val model = findModel() ?: run {
                    error = "Cosmos3-Edge Diffusion is not in the catalog for this device."
                    return@launch
                }
                if (needsToken(model)) {
                    stage = DiffusionModelStage.NEEDS_TOKEN
                    error = "Add a Hugging Face token in Settings to download this private model."
                    return@launch
                }
                if (!model.isDownloadedOnDisk) {
                    stage = DiffusionModelStage.DOWNLOADING
                    downloadPercent = 0
                    RunAnywhere.downloadModelStream(model).collect { p ->
                        downloadPercent = if (p.total_bytes > 0) {
                            (p.bytes_downloaded * 100 / p.total_bytes).toInt()
                        } else {
                            (p.stage_progress.coerceIn(0f, 1f) * 100).toInt()
                        }
                    }
                    downloadPercent = null
                }
                stage = DiffusionModelStage.LOADING
                val fresh = findModel() ?: model
                val result = RunAnywhere.loadModel(fresh)
                stage = if (result.success) DiffusionModelStage.READY else DiffusionModelStage.NOT_DOWNLOADED
                if (!result.success) error = "Failed to load the model."
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("diffusion prepare failed", e)
                error = e.message ?: "Model preparation failed"
                downloadPercent = null
                stage = DiffusionModelStage.NOT_DOWNLOADED
            }
        }
    }

    /** Generate an image for [prompt] via the on-NPU text-to-image path. */
    fun generate() {
        if (isGenerating || stage != DiffusionModelStage.READY || prompt.isBlank()) return
        val text = prompt.trim()
        error = null
        isGenerating = true
        job = viewModelScope.launch {
            val start = System.currentTimeMillis()
            try {
                val result = RunAnywhere.generateImage(
                    RADiffusionGenerationOptions(
                        prompt = text,
                        width = 256,
                        height = 256,
                        mode = DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
                    ),
                )
                val bmp = withContext(Dispatchers.Default) { toBitmap(result.image_data.toByteArray(), result.width, result.height) }
                image = bmp
                lastLatencyMs = result.total_time_ms.takeIf { it > 0 } ?: (System.currentTimeMillis() - start)
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

    private suspend fun findModel(): RAModelInfo? =
        runCatching {
            RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
                .firstOrNull { it.id == MODEL_ID }
        }.getOrNull()

    private fun needsToken(model: RAModelInfo): Boolean =
        model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank() &&
            com.runanywhere.runanywhereai.BuildConfig.HF_TOKEN.isBlank()

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

    private companion object {
        const val MODEL_ID = "cosmos3_edge_diffusion"
    }
}
