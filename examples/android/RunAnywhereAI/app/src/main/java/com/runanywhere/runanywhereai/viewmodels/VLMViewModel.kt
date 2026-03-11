package com.runanywhere.runanywhereai.viewmodels

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
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.SDKInitState
import com.runanywhere.runanywhereai.models.VLMEvent
import com.runanywhere.runanywhereai.models.VLMUiState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import com.runanywhere.sdk.public.extensions.processImageStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class VLMViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication

    private val _uiState = MutableStateFlow<VLMUiState>(VLMUiState.Loading)
    val uiState: StateFlow<VLMUiState> = _uiState.asStateFlow()

    private val _events = Channel<VLMEvent>(Channel.BUFFERED)
    val events: Flow<VLMEvent> = _events.receiveAsFlow()

    private var generationJob: Job? = null
    private var autoStreamJob: Job? = null

    // Camera — LifecycleCameraController for simplicity
    private var cameraController: LifecycleCameraController? = null
    private var currentFrameRgb: ByteArray? = null
    private var currentFrameWidth: Int = 0
    private var currentFrameHeight: Int = 0
    private val frameLock = Any()

    private val analysisExecutor = Executors.newSingleThreadExecutor()

    init {
        observeSDKState()
    }

    // -- SDK State --

    private fun observeSDKState() {
        viewModelScope.launch {
            app.sdkState.collect { sdkState ->
                when (sdkState) {
                    is SDKInitState.Loading -> { /* stay in Loading */ }
                    is SDKInitState.Ready -> checkModelStatus()
                    is SDKInitState.Error -> {
                        _uiState.value = VLMUiState.Error(sdkState.message)
                    }
                }
            }
        }
    }

    private fun checkModelStatus() {
        viewModelScope.launch {
            try {
                val isLoaded = withContext(Dispatchers.IO) { RunAnywhere.isVLMModelLoaded }
                val cameraAuthorized = checkCameraPermissionInternal()
                _uiState.value = VLMUiState.Ready(
                    isModelLoaded = isLoaded,
                    isCameraAuthorized = cameraAuthorized,
                )
                Log.d(TAG, "VLM model loaded: $isLoaded")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check VLM model status", e)
                _uiState.value = VLMUiState.Ready()
            }
        }
    }

    // -- Model --

    fun refreshModelStatus() {
        viewModelScope.launch {
            try {
                val isLoaded = withContext(Dispatchers.IO) { RunAnywhere.isVLMModelLoaded }
                updateReady { copy(isModelLoaded = isLoaded) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh VLM model status", e)
            }
        }
    }

    fun onModelLoaded(modelName: String) {
        updateReady {
            copy(
                isModelLoaded = true,
                loadedModelName = modelName,
                showModelSelection = false,
            )
        }
    }

    fun setShowModelSelection(show: Boolean) {
        updateReady { copy(showModelSelection = show) }
    }

    // -- Camera --

    private fun checkCameraPermissionInternal(): Boolean {
        val context = getApplication<Application>()
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.CAMERA,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun onCameraPermissionResult(granted: Boolean) {
        updateReady { copy(isCameraAuthorized = granted) }
    }

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
                    if (srcIdx + 2 < buffer.limit()) {
                        rgb[rgbIdx++] = buffer[srcIdx]       // R
                        rgb[rgbIdx++] = buffer[srcIdx + 1]   // G
                        rgb[rgbIdx++] = buffer[srcIdx + 2]   // B
                    } else {
                        rgbIdx += 3
                    }
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

    // -- Describe --

    fun describeCurrentFrame() {
        val state = (_uiState.value as? VLMUiState.Ready) ?: return
        if (!state.isModelLoaded) {
            updateReady { copy(error = "Please load a model first") }
            return
        }

        val frameData: ByteArray
        val w: Int
        val h: Int

        synchronized(frameLock) {
            frameData = currentFrameRgb ?: run {
                updateReady { copy(error = "No camera frame available") }
                return
            }
            w = currentFrameWidth
            h = currentFrameHeight
        }

        if (state.isProcessing) return

        generationJob?.cancel()
        updateReady {
            copy(
                isProcessing = true,
                currentDescription = "",
                error = null,
                showingResult = true,
            )
        }

        generationJob = viewModelScope.launch {
            try {
                val image = VLMImage.fromRGBPixels(frameData, w, h)
                val options = VLMGenerationOptions(maxTokens = 200, temperature = 0.7f)

                Log.i(TAG, "Describing current camera frame (${w}x${h})")

                RunAnywhere.processImageStream(image, "Describe what you see briefly.", options)
                    .collect { token ->
                        updateReady { copy(currentDescription = currentDescription + token) }
                    }

                updateReady { copy(currentDescription = currentDescription.trim()) }
                Log.i(TAG, "Frame description completed")
            } catch (e: Exception) {
                Log.e(TAG, "Frame description failed: ${e.message}", e)
                updateReady { copy(error = "Processing failed: ${e.message}") }
            } finally {
                updateReady { copy(isProcessing = false) }
            }
        }
    }

    fun processSelectedImage(prompt: String = "Describe this image in detail.") {
        val state = (_uiState.value as? VLMUiState.Ready) ?: return
        val uri = state.selectedImageUri ?: return

        if (!state.isModelLoaded) {
            updateReady { copy(error = "No VLM model loaded. Please select a model first.") }
            return
        }

        generationJob?.cancel()
        cancelGeneration()

        updateReady {
            copy(
                isProcessing = true,
                currentDescription = "",
                error = null,
                showingResult = true,
            )
        }

        generationJob = viewModelScope.launch {
            var tempFile: File? = null
            try {
                tempFile = copyUriToTempFile(uri) ?: throw Exception("Failed to read image")
                val image = VLMImage.fromFilePath(tempFile.absolutePath)
                val options = VLMGenerationOptions(maxTokens = 300, temperature = 0.7f)

                Log.i(TAG, "Starting VLM streaming for image: ${tempFile.name}")

                RunAnywhere.processImageStream(image, prompt, options)
                    .collect { token ->
                        updateReady { copy(currentDescription = currentDescription + token) }
                    }

                updateReady { copy(currentDescription = currentDescription.trim()) }
                Log.i(TAG, "VLM streaming completed")
            } catch (e: Exception) {
                Log.e(TAG, "VLM processing failed: ${e.message}", e)
                updateReady { copy(error = "Processing failed: ${e.message}") }
            } finally {
                tempFile?.delete()
                updateReady { copy(isProcessing = false) }
            }
        }
    }

    // -- Auto-streaming --

    fun toggleAutoStreaming() {
        val state = (_uiState.value as? VLMUiState.Ready) ?: return
        if (state.isAutoStreamingEnabled) {
            stopAutoStreaming()
        } else {
            startAutoStreaming()
        }
    }

    private fun startAutoStreaming() {
        if (autoStreamJob != null) return
        updateReady { copy(isAutoStreamingEnabled = true) }

        autoStreamJob = viewModelScope.launch {
            while ((_uiState.value as? VLMUiState.Ready)?.isAutoStreamingEnabled == true) {
                while ((_uiState.value as? VLMUiState.Ready)?.isProcessing == true) {
                    delay(100)
                    if ((_uiState.value as? VLMUiState.Ready)?.isAutoStreamingEnabled != true) return@launch
                }

                describeCurrentFrameForAutoStream()
                delay(AUTO_STREAM_INTERVAL_MS)
            }
        }
    }

    fun stopAutoStreaming() {
        autoStreamJob?.cancel()
        autoStreamJob = null
        updateReady { copy(isAutoStreamingEnabled = false) }
    }

    private suspend fun describeCurrentFrameForAutoStream() {
        val frameData: ByteArray
        val w: Int
        val h: Int

        synchronized(frameLock) {
            frameData = currentFrameRgb ?: return
            w = currentFrameWidth
            h = currentFrameHeight
        }

        if ((_uiState.value as? VLMUiState.Ready)?.isProcessing == true) return

        updateReady { copy(isProcessing = true, error = null) }

        var newDescription = ""
        try {
            val image = VLMImage.fromRGBPixels(frameData, w, h)
            val options = VLMGenerationOptions(maxTokens = 100, temperature = 0.7f)

            RunAnywhere.processImageStream(image, "Describe what you see in one sentence.", options)
                .collect { token ->
                    newDescription += token
                    updateReady { copy(currentDescription = newDescription) }
                }
            updateReady { copy(currentDescription = newDescription.trim()) }
        } catch (e: Exception) {
            Log.e(TAG, "Auto-stream VLM error: ${e.message}")
        } finally {
            updateReady { copy(isProcessing = false) }
        }
    }

    // -- Cancel --

    fun cancelGeneration() {
        try {
            RunAnywhere.cancelVLMGeneration()
            generationJob?.cancel()
            updateReady { copy(isProcessing = false) }
            Log.d(TAG, "VLM generation cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel VLM generation: ${e.message}", e)
        }
    }

    // -- Result dismissal --

    fun dismissResult() {
        updateReady {
            copy(
                showingResult = false,
                currentDescription = "",
                error = null,
                selectedImageUri = null,
            )
        }
    }

    // -- Image selection --

    fun setSelectedImage(uri: Uri?) {
        updateReady { copy(selectedImageUri = uri, currentDescription = "", error = null) }
    }

    // -- Helpers --

    private suspend fun copyUriToTempFile(uri: Uri): File? = withContext(Dispatchers.IO) {
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
            Log.e(TAG, "Failed to copy URI to temp file: ${e.message}", e)
            null
        }
    }

    /** Atomically update the [VLMUiState.Ready] state. No-op if state is not Ready. */
    private inline fun updateReady(crossinline transform: VLMUiState.Ready.() -> VLMUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is VLMUiState.Ready -> current.transform()
                else -> current
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        generationJob?.cancel()
        autoStreamJob?.cancel()
        unbindCamera()
        analysisExecutor.shutdown()
    }

    companion object {
        private const val TAG = "VLMViewModel"
        private const val AUTO_STREAM_INTERVAL_MS = 2500L
    }
}
