package com.runanywhere.runanywhereai.ui.screens.segmentation

import ai.runanywhere.proto.v1.SegmentationClassSummary
import ai.runanywhere.proto.v1.SegmentationImage
import ai.runanywhere.proto.v1.SegmentationOptions
import ai.runanywhere.proto.v1.SegmentationPixelFormat
import ai.runanywhere.proto.v1.SegmentationRequest
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
import com.runanywhere.sdk.public.extensions.segment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import java.nio.ByteBuffer

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
