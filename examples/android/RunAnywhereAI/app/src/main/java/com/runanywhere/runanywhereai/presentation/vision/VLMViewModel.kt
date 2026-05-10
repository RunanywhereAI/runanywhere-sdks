package com.runanywhere.runanywhereai.presentation.vision

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VLMImageFormat
import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.net.Uri
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
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.componentLifecycleSnapshot
import com.runanywhere.sdk.public.extensions.fromBitmap
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.types.RASDKEvent
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.ByteString.Companion.toByteString
import timber.log.Timber

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

    // MODEL

    suspend fun checkModelStatus() {
        try {
            val snapshot = RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_VLM)
            val isLoaded =
                snapshot.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    snapshot.model_id.isNotEmpty()
            _uiState.update { it.copy(isModelLoaded = isLoaded) }
            Timber.d("VLM model loaded: $isLoaded")
        } catch (e: Exception) {
            Timber.e(e, "Failed to check VLM model status: ${e.message}")
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

    // CAMERA - Mirrors iOS setupCamera / startCamera / stopCamera
    // Uses LifecycleCameraController (CameraX recommended API)

    fun checkCameraPermission() {
        val context = getApplication<Application>()
        val granted =
            ContextCompat.checkSelfPermission(
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
    fun bindCamera(
        previewView: PreviewView,
        lifecycleOwner: LifecycleOwner,
    ) {
        if (cameraController != null) return

        val context = getApplication<Application>()

        val controller =
            LifecycleCameraController(context).apply {
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
     * KOT-VLM-001 fix: route through `VLMImage.Companion.fromBitmap` so that
     * Android handles `rowStride` / `pixelStride` internally via
     * `Bitmap.getPixels`. The previous hand-rolled loop assumed
     * `pixelStride == 4` and ignored row padding, which produced misaligned
     * RGB / horizontal-shift artifacts on devices where the RGBA_8888 plane
     * carries trailing row bytes. We still cache the packed RGB byte buffer
     * (plus dimensions) because `describeCurrentFrame*` reuses it without
     * re-reading the camera plane.
     */
    private fun captureFrame(imageProxy: ImageProxy) {
        try {
            val bitmap = imageProxy.toBitmap()
            val image = RAVLMImage.fromBitmap(bitmap)
            val rgb = image.raw_rgb?.toByteArray() ?: return

            synchronized(frameLock) {
                currentFrameRgb = rgb
                currentFrameWidth = bitmap.width
                currentFrameHeight = bitmap.height
            }
        } catch (e: Exception) {
            Timber.e("Frame capture failed: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    // DESCRIBE - Mirrors iOS describeCurrentFrame / describeImage

    /**
     * Describe the current camera frame. Mirrors iOS describeCurrentFrame().
     */
    fun describeCurrentFrame() {
        if (!_uiState.value.isModelLoaded) {
            _uiState.update { it.copy(error = "Please load a model first") }
            return
        }

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

        generationJob =
            viewModelScope.launch {
                try {
                    val image =
                        RAVLMImage(
                            raw_rgb = frameData.toByteString(),
                            width = w,
                            height = h,
                            format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
                        )
                    val options =
                        RAVLMGenerationOptions(
                            prompt = "Describe what you see briefly.",
                            max_tokens = 200,
                            temperature = 0.7f,
                        )

                    Timber.i("Describing current camera frame (${w}x$h)")

                    RunAnywhere.processImageStream(image, options).collect { event ->
                        _uiState.update {
                            it.copy(currentDescription = applyVlmStreamEvent(it.currentDescription, event))
                        }
                    }

                    _uiState.update { it.copy(currentDescription = it.currentDescription.trim()) }
                    Timber.i("Frame description completed")
                } catch (e: Exception) {
                    Timber.e(e, "Frame description failed: ${e.message}")
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

        generationJob =
            viewModelScope.launch {
                var tempFile: File? = null
                try {
                    tempFile = copyUriToTempFile(uri) ?: throw Exception("Failed to read image")
                    val image =
                        RAVLMImage(
                            file_path = tempFile.absolutePath,
                            format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
                        )
                    val options =
                        RAVLMGenerationOptions(
                            prompt = prompt,
                            max_tokens = 300,
                            temperature = 0.7f,
                        )

                    Timber.i("Starting VLM streaming for image: ${tempFile.name}")

                    RunAnywhere.processImageStream(image, options)
                        .collect { event ->
                            _uiState.update {
                                it.copy(currentDescription = applyVlmStreamEvent(it.currentDescription, event))
                            }
                        }

                    _uiState.update { it.copy(currentDescription = it.currentDescription.trim()) }
                    Timber.i("VLM streaming completed")
                } catch (e: Exception) {
                    Timber.e(e, "VLM processing failed: ${e.message}")
                    _uiState.update { it.copy(error = "Processing failed: ${e.message}") }
                } finally {
                    tempFile?.delete()
                    _uiState.update { it.copy(isProcessing = false) }
                }
            }
    }

    // AUTO-STREAMING - Mirrors iOS toggleAutoStreaming / startAutoStreaming

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

        autoStreamJob =
            viewModelScope.launch {
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
            val image =
                RAVLMImage(
                    raw_rgb = frameData.toByteString(),
                    width = w,
                    height = h,
                    format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
                )
            val options =
                RAVLMGenerationOptions(
                    prompt = "Describe what you see in one sentence.",
                    max_tokens = 100,
                    temperature = 0.7f,
                )

            RunAnywhere.processImageStream(image, options).collect { event ->
                newDescription = applyVlmStreamEvent(newDescription, event)
                _uiState.update { it.copy(currentDescription = newDescription) }
            }
            _uiState.update { it.copy(currentDescription = newDescription.trim()) }
        } catch (e: Exception) {
            Timber.e("Auto-stream VLM error: ${e.message}")
        } finally {
            _uiState.update { it.copy(isProcessing = false) }
        }
    }

    // CANCEL

    fun cancelGeneration() {
        try {
            RunAnywhere.cancelVLMGeneration()
            generationJob?.cancel()
            _uiState.update { it.copy(isProcessing = false) }
            Timber.d("VLM generation cancelled")
        } catch (e: Exception) {
            Timber.e(e, "Failed to cancel VLM generation: ${e.message}")
        }
    }

    // IMAGE SELECTION

    fun setSelectedImage(uri: Uri?) {
        _uiState.update {
            it.copy(selectedImageUri = uri, currentDescription = "", error = null)
        }
    }

    // HELPERS

    private suspend fun copyUriToTempFile(uri: Uri): File? =
        withContext(Dispatchers.IO) {
            try {
                val context = getApplication<Application>()
                val inputStream = context.contentResolver.openInputStream(uri) ?: return@withContext null
                val tempFile = File.createTempFile("vlm_image_", ".jpg", context.cacheDir)
                inputStream.use { input ->
                    FileOutputStream(tempFile).use { output ->
                        input.copyTo(output)
                    }
                }
                tempFile
            } catch (e: Exception) {
                Timber.e(e, "Failed to copy URI to temp file: ${e.message}")
                null
            }
        }

    private fun applyVlmStreamEvent(
        currentText: String,
        event: RASDKEvent,
    ): String {
        val generation = event.generation ?: return currentText
        return when {
            generation.token.isNotBlank() -> currentText + generation.token
            generation.streaming_text.isNotBlank() -> generation.streaming_text
            generation.response.isNotBlank() -> generation.response
            else -> currentText
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
