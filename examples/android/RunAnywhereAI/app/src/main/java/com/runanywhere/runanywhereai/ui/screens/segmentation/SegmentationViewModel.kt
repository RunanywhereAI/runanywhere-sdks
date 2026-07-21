package com.runanywhere.runanywhereai.ui.screens.segmentation

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.SegmentationClassSummary
import ai.runanywhere.proto.v1.SegmentationImage
import ai.runanywhere.proto.v1.SegmentationOptions
import ai.runanywhere.proto.v1.SegmentationPixelFormat
import ai.runanywhere.proto.v1.SegmentationRequest
import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import android.system.Os
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.importModel
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.segment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import java.io.File
import java.nio.ByteBuffer

/**
 * Drives semantic image segmentation (SegFormer) through the canonical
 * `RunAnywhere.segment` facade. Pure platform plumbing: pixel packing, EULA
 * signalling, SDK model lifecycle, and the segment call. All inference and
 * model routing live in the SDK / C++ commons.
 */
class SegmentationViewModel(application: Application) : AndroidViewModel(application) {

    var licenseAccepted by mutableStateOf(false)
        private set
    var isModelLoaded by mutableStateOf(false)
        private set
    var loadedModelId by mutableStateOf<String?>(null)
        private set
    var isImportingModel by mutableStateOf(false)
        private set

    var sourceBitmap by mutableStateOf<Bitmap?>(null)
        private set
    var maskBitmap by mutableStateOf<Bitmap?>(null)
        private set

    var classSummaries by mutableStateOf<List<SegmentationClassSummary>>(emptyList())
        private set
    var processingTimeMs by mutableStateOf(0L)
        private set
    var isSegmenting by mutableStateOf(false)
        private set

    var status by mutableStateOf("")
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private var sourcePixels: PackedImage? = null

    private data class PackedImage(val rgba: ByteArray, val width: Int, val height: Int)

    fun refreshModelStatus() {
        viewModelScope.launch {
            isModelLoaded = runCatching {
                RunAnywhere.currentModel(
                    CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION),
                ).found
            }.getOrDefault(false)
        }
    }

    /**
     * Accept the SegFormer noncommercial license for this process. The native
     * ONNX provider reads [LICENSE_ENV] via getenv when the model is loaded, so
     * acceptance must precede [importAndLoadModel].
     */
    fun acceptLicense() {
        runCatching { Os.setenv(LICENSE_ENV, "1", true) }
            .onFailure {
                error = "Could not accept the license: ${it.message}"
                return
            }
        licenseAccepted = true
        error = null
        status = "License accepted. Load a SegFormer model to continue."
    }

    /**
     * Stage the user-picked SegFormer bundle files into app storage, then import
     * and load them under the semantic-segmentation category.
     */
    fun importAndLoadModel(uris: List<Uri>) {
        if (!licenseAccepted) {
            error = "Accept the SegFormer license first."
            return
        }
        if (uris.isEmpty()) return
        viewModelScope.launch {
            isImportingModel = true
            error = null
            status = "Importing model…"
            try {
                val stagedDir = withContext(Dispatchers.IO) { stageFiles(uris) }
                val importResult = RunAnywhere.importModel(
                    ModelImportRequest(
                        source_path = stagedDir.absolutePath,
                        copy_into_managed_storage = true,
                        validate_before_register = false,
                    ),
                )
                if (!importResult.success) {
                    error = importResult.error_message.ifEmpty { "Model import failed." }
                    return@launch
                }
                val modelId = importResult.model?.id
                if (modelId.isNullOrEmpty()) {
                    error = "Imported model has no identifier; cannot load."
                    return@launch
                }

                status = "Loading model…"
                val loadResult = RunAnywhere.loadModel(
                    ModelLoadRequest(
                        model_id = modelId,
                        category = ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
                        framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
                    ),
                )
                if (!loadResult.success) {
                    error = loadResult.error_message.ifEmpty { "Model load failed." }
                    return@launch
                }
                loadedModelId = modelId
                isModelLoaded = true
                status = "Model loaded: $modelId."
            } catch (e: Exception) {
                RACLog.e("$TAG: Model import/load failed", e)
                error = "Model import/load failed: ${e.message}"
            } finally {
                isImportingModel = false
            }
        }
    }

    fun onImagePicked(bitmap: Bitmap?) {
        if (bitmap == null) return
        val scaled = downscale(bitmap, MAX_DIMENSION)
        sourceBitmap = scaled
        maskBitmap = null
        classSummaries = emptyList()
        error = null
        sourcePixels = packRgba(scaled)
        status = "Image ready (${scaled.width}×${scaled.height})."
    }

    fun runSegmentation() {
        if (!licenseAccepted) { error = "Accept the SegFormer license first."; return }
        if (!isModelLoaded) { error = "Load a segmentation model first."; return }
        val pixels = sourcePixels
        if (pixels == null) { error = "Pick an image first."; return }

        viewModelScope.launch {
            isSegmenting = true
            error = null
            maskBitmap = null
            classSummaries = emptyList()
            status = "Running segmentation…"
            try {
                val request = SegmentationRequest(
                    image = SegmentationImage(
                        data_ = pixels.rgba.toByteString(),
                        width = pixels.width,
                        height = pixels.height,
                        pixel_format = SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8,
                    ),
                    options = SegmentationOptions(include_diagnostic_rgba = true),
                )
                val result = withContext(Dispatchers.Default) { RunAnywhere.segment(request) }
                classSummaries = result.class_summaries.sortedByDescending { it.pixel_count }
                processingTimeMs = result.processing_time_ms
                val diagnostic = result.diagnostic_rgba
                if (diagnostic != null && diagnostic.size == result.width * result.height * 4) {
                    maskBitmap = bitmapFromRgba(diagnostic.toByteArray(), result.width, result.height)
                }
                status = "Done — ${result.class_summaries.size} classes in ${result.processing_time_ms}ms."
            } catch (e: Exception) {
                RACLog.e("$TAG: Segmentation failed", e)
                error = "Segmentation failed: ${e.message}"
            } finally {
                isSegmenting = false
            }
        }
    }

    fun reportError(message: String) {
        error = message
    }

    // --- Pixel + file helpers -------------------------------------------------

    private fun stageFiles(uris: List<Uri>): File {
        val resolver = getApplication<Application>().contentResolver
        val dir = File(getApplication<Application>().filesDir, "segmentation-import").apply {
            deleteRecursively()
            mkdirs()
        }
        uris.forEachIndexed { index, uri ->
            val name = displayName(uri) ?: "model-file-$index"
            resolver.openInputStream(uri)?.use { input ->
                File(dir, name).outputStream().use { output -> input.copyTo(output) }
            }
        }
        return dir
    }

    private fun displayName(uri: Uri): String? {
        val resolver = getApplication<Application>().contentResolver
        return resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    private fun downscale(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= maxDimension) return bitmap.copy(Bitmap.Config.ARGB_8888, false)
        val scale = maxDimension.toFloat() / longest.toFloat()
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
            .copy(Bitmap.Config.ARGB_8888, false)
    }

    private fun packRgba(bitmap: Bitmap): PackedImage {
        val argb = if (bitmap.config == Bitmap.Config.ARGB_8888) {
            bitmap
        } else {
            bitmap.copy(Bitmap.Config.ARGB_8888, false)
        }
        val buffer = ByteBuffer.allocate(argb.width * argb.height * 4)
        argb.copyPixelsToBuffer(buffer)
        return PackedImage(buffer.array(), argb.width, argb.height)
    }

    private fun bitmapFromRgba(rgba: ByteArray, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
        return bitmap
    }

    private companion object {
        const val TAG = "SegmentationVM"
        const val LICENSE_ENV = "RAC_ACCEPT_NVIDIA_SEGFORMER_NONCOMMERCIAL_LICENSE"
        const val MAX_DIMENSION = 1024
    }
}
