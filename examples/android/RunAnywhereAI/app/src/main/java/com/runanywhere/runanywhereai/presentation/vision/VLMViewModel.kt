package com.runanywhere.runanywhereai.presentation.vision

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import com.runanywhere.sdk.public.extensions.processImageStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * UI state for VLM screen.
 * Mirrors iOS VLMViewModel published properties.
 */
data class VLMUiState(
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val isProcessing: Boolean = false,
    val currentDescription: String = "",
    val error: String? = null,
    val selectedImageUri: Uri? = null,
    val showModelSelection: Boolean = false,
    val isCameraAuthorized: Boolean = false,
    val isAutoStreamingEnabled: Boolean = false,
)

/**
 * VLM ViewModel matching iOS VLMViewModel functionality.
 *
 * Manages:
 * - VLM model status
 * - Camera preview via CameraX LifecycleCameraController
 * - Frame capture via ImageAnalysis
 * - Image selection (from gallery)
 * - Image processing with streaming output
 * - Auto-streaming mode (live, every 2.5s)
 * - Generation cancellation
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../Features/Vision/VLMViewModel.swift
 */
class VLMViewModel(application: Application) : AndroidViewModel(application) {
    companion object {
        private const val TAG = "VLMViewModel"
        private const val AUTO_STREAM_INTERVAL_MS = 2500L
    }

    private val _uiState = MutableStateFlow(VLMUiState())
    val uiState: StateFlow<VLMUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null
    private var autoStreamJob: Job? = null

    // Camera — uses LifecycleCameraController for simplicity
    private var cameraController: LifecycleCameraController? = null
    private var currentFrameRgb: ByteArray? = null
    private var currentFrameWidth: Int = 0
    private var currentFrameHeight: Int = 0
    private val frameLock = Any()

    // Background executor for frame analysis (avoid blocking main thread)
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    init {
        viewModelScope.launch {
            checkModelStatus()
            checkCameraPermission()
        }
    }

    // ========================================================================
    // MODEL
    // ========================================================================

    fun checkModelStatus() {
        try {
            val isLoaded = RunAnywhere.isVLMModelLoaded
            _uiState.update { it.copy(isModelLoaded = isLoaded) }
            Log.d(TAG, "VLM model loaded: $isLoaded")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check VLM model status: ${e.message}", e)
            _uiState.update { it.copy(isModelLoaded = false) }
        }
    }

    fun onModelLoaded(modelName: String) {
        _uiState.update {
            it.copy(
                isModelLoaded = true,
                loadedModelName = modelName,
                showModelSelection = false,
            )
        }
    }

    fun setShowModelSelection(show: Boolean) {
        _uiState.update { it.copy(showModelSelection = show) }
    }

    // ========================================================================
    // CAMERA - Mirrors iOS setupCamera / startCamera / stopCamera
    // Uses LifecycleCameraController (CameraX recommended API)
    // ========================================================================

    fun checkCameraPermission() {
        val context = getApplication<Application>()
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
        _uiState.update { it.copy(isCameraAuthorized = granted) }
    }

    fun onCameraPermissionResult(granted: Boolean) {
        _uiState.update { it.copy(isCameraAuthorized = granted) }
    }

    /**
     * Bind camera preview + image analysis to the given PreviewView.
     * Mirrors iOS setupCamera() + startCamera().
     *
     * Uses LifecycleCameraController which automatically manages Preview + ImageAnalysis.
     */
    fun bindCamera(previewView: PreviewView, lifecycleOwner: LifecycleOwner) {
        if (cameraController != null) return

        val context = getApplication<Application>()

        val controller = LifecycleCameraController(context).apply {
            cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
            setEnabledUseCases(CameraController.IMAGE_ANALYSIS)
            imageAnalysisBackpressureStrategy = ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
            imageAnalysisOutputImageFormat = ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888

            setImageAnalysisAnalyzer(analysisExecutor) { imageProxy ->
                captureFrame(imageProxy)
            }
        }

        controller.bindToLifecycle(lifecycleOwner)
        previewView.controller = controller
        cameraController = controller
    }

    fun unbindCamera() {
        cameraController?.unbind()
        cameraController = null
    }

    /**
     * Capture the latest camera frame as RGB bytes.
     * Mirrors iOS captureOutput delegate that stores currentFrame (CVPixelBuffer).
     *
     * CameraX delivers RGBA_8888 format; we strip alpha to get RGB.
     */
    private fun captureFrame(imageProxy: ImageProxy) {
        try {
            val plane = imageProxy.planes[0]
            val buffer = plane.buffer
            val width = imageProxy.width
            val height = imageProxy.height
            val rowStride = plane.rowStride
            val pixelStride = plane.pixelStride

            // RGBA_8888 -> RGB (strip alpha), handle row stride padding
            val rgbSize = width * height * 3
            val rgb = ByteArray(rgbSize)
            var rgbIdx = 0
            for (row in 0 until height) {
                for (col in 0 until width) {
                    val srcIdx = row * rowStride + col * pixelStride
                    rgb[rgbIdx++] = buffer[srcIdx]       // R
                    rgb[rgbIdx++] = buffer[srcIdx + 1]   // G
                    rgb[rgbIdx++] = buffer[srcIdx + 2]   // B
                }
            }

            synchronized(frameLock) {
                currentFrameRgb = rgb
                currentFrameWidth = width
                currentFrameHeight = height
            }
        } catch (e: Exception) {
            Log.e(TAG, "Frame capture failed: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    // ========================================================================
    // DESCRIBE - Mirrors iOS describeCurrentFrame / describeImage
    // ========================================================================

    /**
     * Describe the current camera frame. Mirrors iOS describeCurrentFrame().
     */
    fun describeCurrentFrame() {
        val frameData: ByteArray
        val w: Int
        val h: Int

        synchronized(frameLock) {
            frameData = currentFrameRgb ?: run {
                _uiState.update { it.copy(error = "No camera frame available") }
                return
            }
            w = currentFrameWidth
            h = currentFrameHeight
        }

        if (_uiState.value.isProcessing) return

        generationJob?.cancel()
        _uiState.update {
            it.copy(isProcessing = true, currentDescription = "", error = null)
        }

        generationJob = viewModelScope.launch {
            try {
                val image = VLMImage.fromRGBPixels(frameData, w, h)
                val options = VLMGenerationOptions(maxTokens = 200, temperature = 0.7f)

                Log.i(TAG, "Describing current camera frame (${w}x${h})")

                RunAnywhere.processImageStream(
                    image,
                    "Describe what you see briefly.",
                    options,
                ).collect { token ->
                    _uiState.update { it.copy(currentDescription = it.currentDescription + token) }
                }

                Log.i(TAG, "Frame description completed")
            } catch (e: Exception) {
                Log.e(TAG, "Frame description failed: ${e.message}", e)
                _uiState.update { it.copy(error = "Processing failed: ${e.message}") }
            } finally {
                _uiState.update { it.copy(isProcessing = false) }
            }
        }
    }

    /**
     * Process a gallery image. Mirrors iOS describeImage(uiImage:).
     */
    fun processSelectedImage(prompt: String = "Describe this image in detail.") {
        val uri = _uiState.value.selectedImageUri ?: return

        if (!_uiState.value.isModelLoaded) {
            _uiState.update { it.copy(error = "No VLM model loaded. Please select a model first.") }
            return
        }

        generationJob?.cancel()
        cancelGeneration()

        _uiState.update {
            it.copy(isProcessing = true, currentDescription = "", error = null)
        }

        generationJob = viewModelScope.launch {
            try {
                val tempFile = copyUriToTempFile(uri) ?: throw Exception("Failed to read image")
                val image = VLMImage.fromFilePath(tempFile.absolutePath)
                val options = VLMGenerationOptions(maxTokens = 300, temperature = 0.7f)

                Log.i(TAG, "Starting VLM streaming for image: ${tempFile.name}")

                RunAnywhere.processImageStream(image, prompt, options)
                    .collect { token ->
                        _uiState.update { it.copy(currentDescription = it.currentDescription + token) }
                    }

                Log.i(TAG, "VLM streaming completed")
                tempFile.delete()
            } catch (e: Exception) {
                Log.e(TAG, "VLM processing failed: ${e.message}", e)
                _uiState.update { it.copy(error = "Processing failed: ${e.message}") }
            } finally {
                _uiState.update { it.copy(isProcessing = false) }
            }
        }
    }

    // ========================================================================
    // AUTO-STREAMING - Mirrors iOS toggleAutoStreaming / startAutoStreaming
    // ========================================================================

    fun toggleAutoStreaming() {
        if (_uiState.value.isAutoStreamingEnabled) {
            stopAutoStreaming()
        } else {
            startAutoStreaming()
        }
    }

    private fun startAutoStreaming() {
        if (autoStreamJob != null) return
        _uiState.update { it.copy(isAutoStreamingEnabled = true) }

        autoStreamJob = viewModelScope.launch {
            while (_uiState.value.isAutoStreamingEnabled) {
                // Wait for any current processing to finish
                while (_uiState.value.isProcessing) {
                    delay(100)
                    if (!_uiState.value.isAutoStreamingEnabled) return@launch
                }

                describeCurrentFrameForAutoStream()

                delay(AUTO_STREAM_INTERVAL_MS)
            }
        }
    }

    fun stopAutoStreaming() {
        autoStreamJob?.cancel()
        autoStreamJob = null
        _uiState.update { it.copy(isAutoStreamingEnabled = false) }
    }

    /**
     * Auto-stream variant — smoother transition, shorter prompt, errors logged only.
     * Mirrors iOS describeCurrentFrameForAutoStream().
     */
    private suspend fun describeCurrentFrameForAutoStream() {
        val frameData: ByteArray
        val w: Int
        val h: Int

        synchronized(frameLock) {
            frameData = currentFrameRgb ?: return
            w = currentFrameWidth
            h = currentFrameHeight
        }

        if (_uiState.value.isProcessing) return

        _uiState.update { it.copy(isProcessing = true, error = null) }

        var newDescription = ""
        try {
            val image = VLMImage.fromRGBPixels(frameData, w, h)
            val options = VLMGenerationOptions(maxTokens = 100, temperature = 0.7f)

            RunAnywhere.processImageStream(
                image,
                "Describe what you see in one sentence.",
                options,
            ).collect { token ->
                newDescription += token
                _uiState.update { it.copy(currentDescription = newDescription) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Auto-stream VLM error: ${e.message}")
        } finally {
            _uiState.update { it.copy(isProcessing = false) }
        }
    }

    // ========================================================================
    // CANCEL
    // ========================================================================

    fun cancelGeneration() {
        try {
            RunAnywhere.cancelVLMGeneration()
            generationJob?.cancel()
            _uiState.update { it.copy(isProcessing = false) }
            Log.d(TAG, "VLM generation cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel VLM generation: ${e.message}", e)
        }
    }

    // ========================================================================
    // IMAGE SELECTION
    // ========================================================================

    fun setSelectedImage(uri: Uri?) {
        _uiState.update {
            it.copy(selectedImageUri = uri, currentDescription = "", error = null)
        }
    }

    // ========================================================================
    // HELPERS
    // ========================================================================

    private suspend fun copyUriToTempFile(uri: Uri): File? = withContext(Dispatchers.IO) {
        try {
            val context = getApplication<Application>()
            val inputStream = context.contentResolver.openInputStream(uri) ?: return@withContext null
            val tempFile = File.createTempFile("vlm_image_", ".jpg", context.cacheDir)
            FileOutputStream(tempFile).use { output -> inputStream.copyTo(output) }
            inputStream.close()
            tempFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy URI to temp file: ${e.message}", e)
            null
        }
    }

    override fun onCleared() {
        super.onCleared()
        generationJob?.cancel()
        autoStreamJob?.cancel()
        unbindCamera()
        analysisExecutor.shutdown()
    }
}
