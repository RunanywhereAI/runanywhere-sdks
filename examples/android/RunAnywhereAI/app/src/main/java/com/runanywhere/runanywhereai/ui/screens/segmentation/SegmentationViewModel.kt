package com.runanywhere.runanywhereai.ui.screens.segmentation

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
import com.runanywhere.sdk.public.api.ClassInfo
import com.runanywhere.sdk.public.api.ImageInput
import com.runanywhere.sdk.public.api.SegmentationOptions
import com.runanywhere.sdk.public.api.segmentation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import java.nio.ByteBuffer
import kotlin.coroutines.cancellation.CancellationException

/**
 * Drives semantic image segmentation through `RunAnywhere.segment`. Model
 * download/load is owned by [ModelSelectionSheet] + [RuntimeModelSelection]
 * (same pattern as STT / Vision / iOS SegmentationView).
 */
class SegmentationViewModel(application: Application) : AndroidViewModel(application) {

    var sourceBitmap by mutableStateOf<Bitmap?>(null)
        private set
    var maskBitmap by mutableStateOf<Bitmap?>(null)
        private set

    var classSummaries by mutableStateOf<List<ClassInfo>>(emptyList())
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
        val pixels = sourcePixels
        if (pixels == null) {
            error = "Pick an image first."
            return
        }

        viewModelScope.launch {
            isSegmenting = true
            error = null
            maskBitmap = null
            classSummaries = emptyList()
            status = "Running segmentation…"
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.SEGMENTATION)
                val startedAt = System.currentTimeMillis()
                val result = RunAnywhere.segmentation.segment(
                    ImageInput.rawRgba(pixels.rgba, pixels.width, pixels.height),
                    SegmentationOptions(includeDiagnosticImage = true),
                )
                val elapsed = System.currentTimeMillis() - startedAt
                classSummaries = result.classes.sortedByDescending { it.pixelCount }
                processingTimeMs = elapsed
                val diagnostic = result.diagnosticImage
                if (diagnostic != null && diagnostic.size == result.width * result.height * 4) {
                    maskBitmap = bitmapFromRgba(diagnostic, result.width, result.height)
                }
                status = "Done — ${result.classes.size} classes in ${elapsed}ms."
            } catch (e: CancellationException) {
                throw e
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
        const val MAX_DIMENSION = 1024
    }
}
