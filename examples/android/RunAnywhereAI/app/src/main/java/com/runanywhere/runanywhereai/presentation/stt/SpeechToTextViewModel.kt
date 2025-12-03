package com.runanywhere.runanywhereai.presentation.stt

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.audio.AudioCaptureOptions
import com.runanywhere.sdk.components.stt.AudioFormat
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTStreamEvent
import com.runanywhere.sdk.models.lifecycle.Modality
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleTracker
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * STT Recording Mode
 * iOS Reference: STTMode enum in SpeechToTextView.swift
 */
enum class STTMode {
    BATCH,  // Record full audio then transcribe
    LIVE    // Real-time streaming transcription
}

/**
 * Recording State
 * iOS Reference: RecordingState in SpeechToTextView.swift
 */
enum class RecordingState {
    IDLE,
    RECORDING,
    PROCESSING
}

/**
 * Transcription metrics for display
 */
data class TranscriptionMetrics(
    val confidence: Float = 0f,
    val audioDurationMs: Double = 0.0,
    val inferenceTimeMs: Double = 0.0,
    val detectedLanguage: String = "",
    val wordCount: Int = 0
) {
    val realTimeFactor: Double
        get() = if (audioDurationMs > 0) inferenceTimeMs / audioDurationMs else 0.0
}

/**
 * STT UI State
 * iOS Reference: STTViewModel state properties in SpeechToTextView.swift
 */
data class STTUiState(
    val mode: STTMode = STTMode.BATCH,
    val recordingState: RecordingState = RecordingState.IDLE,
    val transcription: String = "",
    val isModelLoaded: Boolean = false,
    val selectedFramework: String? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val audioLevel: Float = 0f,
    val language: String = "en",
    val errorMessage: String? = null,
    val supportsLiveMode: Boolean = false,
    val isTranscribing: Boolean = false,
    val metrics: TranscriptionMetrics? = null
)

/**
 * Speech to Text ViewModel
 *
 * iOS Reference: STTViewModel in SpeechToTextView.swift
 *
 * This ViewModel manages:
 * - Model loading and selection via STTComponent
 * - Recording state management with AudioCaptureService
 * - Transcription processing via RunAnywhere SDK
 * - Audio level monitoring for UI visualization
 */
class SpeechToTextViewModel : ViewModel() {
    companion object {
        private const val TAG = "STTViewModel"
        private const val SAMPLE_RATE = 16000 // 16kHz for Whisper/ONNX STT models
    }

    private val _uiState = MutableStateFlow(STTUiState())
    val uiState: StateFlow<STTUiState> = _uiState.asStateFlow()

    // SDK Components - matches iOS STTComponent pattern
    private var sttComponent: STTComponent? = null
    private var audioCaptureService: AudioCaptureService? = null

    // Audio recording state
    private var recordingJob: Job? = null
    private val audioBuffer = ByteArrayOutputStream()
    private var recordedSampleRate: Int = SAMPLE_RATE

    init {
        // Subscribe to model lifecycle tracker for STT modality
        // iOS Reference: subscribeToModelLifecycle() in STTViewModel
        viewModelScope.launch {
            ModelLifecycleTracker.modelsByModality.collect { modelsByModality ->
                val sttState = modelsByModality[Modality.STT]
                val isNowLoaded = sttState?.state?.isLoaded == true

                _uiState.update {
                    it.copy(
                        isModelLoaded = isNowLoaded,
                        selectedModelName = if (isNowLoaded) sttState?.modelName else it.selectedModelName,
                        selectedModelId = if (isNowLoaded) sttState?.modelId else it.selectedModelId,
                        selectedFramework = if (isNowLoaded) sttState?.framework?.displayName else it.selectedFramework
                    )
                }

                // If model is loaded, restore STT component
                if (isNowLoaded && sttState != null && sttComponent == null) {
                    restoreSTTComponent(sttState.modelId)
                }

                Log.d(TAG, "📊 STT lifecycle state updated: loaded=$isNowLoaded, model=${sttState?.modelName}")
            }
        }
    }

    /**
     * Initialize the STT ViewModel with context for audio capture
     * iOS equivalent: viewModel.initialize() in onAppear
     */
    fun initialize(context: Context) {
        viewModelScope.launch {
            Log.i(TAG, "Initializing STT ViewModel...")

            // Initialize audio capture service
            audioCaptureService = AudioCaptureService(
                context = context,
                options = AudioCaptureOptions.SPEECH_RECOGNITION
            )

            // Check for microphone permission
            val hasPermission = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                Log.w(TAG, "Microphone permission not granted")
                _uiState.update { it.copy(errorMessage = "Microphone permission required") }
            }
        }
    }

    /**
     * Restore STT component from existing model state
     * iOS Reference: restoreComponentIfNeeded() in STTViewModel
     */
    private fun restoreSTTComponent(modelId: String) {
        viewModelScope.launch {
            if (sttComponent != null) return@launch

            Log.i(TAG, "Restoring STT component for model: $modelId")
            try {
                // Get the model's local path from the model registry
                val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
                val modelPath = modelInfo?.localPath

                if (modelPath.isNullOrEmpty()) {
                    Log.w(TAG, "Model $modelId has no local path - may not be downloaded")
                } else {
                    Log.i(TAG, "Found model path: $modelPath")
                }

                // Use the actual file path as modelId so the ONNX service can load it
                val effectiveModelId = modelPath ?: modelId
                Log.i(TAG, "Using effective model ID: $effectiveModelId")

                val config = STTConfiguration(
                    modelId = effectiveModelId,
                    language = "en",
                    enablePunctuation = true,
                    enableDiarization = false,
                    sampleRate = SAMPLE_RATE
                )

                val component = STTComponent(config)
                component.initialize()
                sttComponent = component

                // Update live mode support based on service capabilities
                _uiState.update {
                    it.copy(supportsLiveMode = component.supportsStreaming)
                }

                Log.i(TAG, "✅ STT component restored successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restore STT component: ${e.message}", e)
            }
        }
    }

    /**
     * Set the STT mode (Batch or Live)
     */
    fun setMode(mode: STTMode) {
        _uiState.update { it.copy(mode = mode) }
    }

    /**
     * Load a STT model via STTComponent
     * iOS Reference: loadModelFromSelection() in STTViewModel
     *
     * @param modelName Display name of the model
     * @param modelId Model identifier for SDK
     */
    fun loadModel(modelName: String, modelId: String) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    recordingState = RecordingState.PROCESSING,
                    errorMessage = null
                )
            }

            try {
                Log.i(TAG, "Loading STT model: $modelName (id: $modelId)")

                // Create STT configuration (matches iOS STTConfiguration)
                val config = STTConfiguration(
                    modelId = modelId,
                    language = "en",
                    enablePunctuation = true,
                    enableDiarization = false,
                    sampleRate = SAMPLE_RATE
                )

                // Create and initialize STT component
                val component = STTComponent(config)
                component.initialize()

                sttComponent = component

                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedFramework = "ONNX Runtime", // Will be updated by lifecycle tracker
                        selectedModelName = modelName,
                        selectedModelId = modelId,
                        recordingState = RecordingState.IDLE,
                        supportsLiveMode = component.supportsStreaming
                    )
                }

                Log.i(TAG, "✅ STT model loaded successfully: $modelName")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load STT model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        errorMessage = "Failed to load model: ${e.message}",
                        recordingState = RecordingState.IDLE
                    )
                }
            }
        }
    }

    /**
     * Toggle recording state
     * iOS Reference: toggleRecording() in STTViewModel
     */
    fun toggleRecording() {
        viewModelScope.launch {
            when (_uiState.value.recordingState) {
                RecordingState.IDLE -> startRecording()
                RecordingState.RECORDING -> stopRecording()
                RecordingState.PROCESSING -> { /* Cannot toggle while processing */ }
            }
        }
    }

    /**
     * Start audio recording
     * iOS Reference: startRecording() in STTViewModel
     */
    private suspend fun startRecording() {
        Log.i(TAG, "Starting recording in ${_uiState.value.mode} mode")

        // Clear previous state
        _uiState.update {
            it.copy(
                recordingState = RecordingState.RECORDING,
                transcription = "",
                errorMessage = null,
                audioLevel = 0f
            )
        }
        audioBuffer.reset()

        val audioCapture = audioCaptureService ?: run {
            _uiState.update { it.copy(errorMessage = "Audio capture not initialized") }
            return
        }

        if (!audioCapture.hasRecordPermission()) {
            _uiState.update { it.copy(errorMessage = "Microphone permission required") }
            return
        }

        when (_uiState.value.mode) {
            STTMode.BATCH -> startBatchRecording(audioCapture)
            STTMode.LIVE -> startLiveRecording(audioCapture)
        }
    }

    /**
     * Start batch recording - collect all audio then transcribe
     * iOS Reference: Batch mode in startRecording()
     */
    private fun startBatchRecording(audioCapture: AudioCaptureService) {
        // Note: Don't use Dispatchers.IO here - the flow handles IO internally via callbackFlow
        recordingJob = viewModelScope.launch {
            try {
                audioCapture.startCapture().collect { audioData ->
                    // Append to buffer (thread-safe ByteArrayOutputStream)
                    withContext(Dispatchers.IO) {
                        audioBuffer.write(audioData)
                    }

                    // Calculate and update audio level on Main thread
                    val rms = audioCapture.calculateRMS(audioData)
                    val normalizedLevel = normalizeAudioLevel(rms)
                    _uiState.update { it.copy(audioLevel = normalizedLevel) }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                // Expected when stopping recording - not an error
                Log.d(TAG, "Batch recording cancelled (expected when stopping)")
            } catch (e: Exception) {
                Log.e(TAG, "Error during batch recording: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        errorMessage = "Recording error: ${e.message}",
                        recordingState = RecordingState.IDLE,
                        audioLevel = 0f
                    )
                }
            }
        }
    }

    /**
     * Start live streaming recording - transcribe in real-time
     * iOS Reference: Live mode in startRecording() with liveTranscribe
     */
    private fun startLiveRecording(audioCapture: AudioCaptureService) {
        val component = sttComponent ?: run {
            _uiState.update { it.copy(errorMessage = "No STT model loaded") }
            return
        }

        // Note: Don't use Dispatchers.IO - flow handles IO internally via callbackFlow
        recordingJob = viewModelScope.launch {
            try {
                // Use onEach to update audio level without creating a nested flow
                val audioFlow = audioCapture.startCapture().onEach { audioData ->
                    // Update audio level on Main thread
                    val rms = audioCapture.calculateRMS(audioData)
                    val normalizedLevel = normalizeAudioLevel(rms)
                    _uiState.update { it.copy(audioLevel = normalizedLevel) }
                }

                // Use SDK's streaming transcription
                component.streamTranscribe(
                    audioStream = audioFlow,
                    language = _uiState.value.language
                ).collect { event ->
                    handleSTTStreamEvent(event)
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                // Expected when stopping recording - not an error
                Log.d(TAG, "Live recording cancelled (expected when stopping)")
            } catch (e: Exception) {
                Log.e(TAG, "Error during live recording: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        errorMessage = "Live transcription error: ${e.message}",
                        recordingState = RecordingState.IDLE,
                        audioLevel = 0f
                    )
                }
            }
        }
    }

    /**
     * Handle STT stream events during live transcription
     * iOS Reference: Event handling in streaming task
     */
    private fun handleSTTStreamEvent(event: STTStreamEvent) {
        when (event) {
            is STTStreamEvent.PartialTranscription -> {
                // Filter out placeholder "..." - only update UI with actual transcription text
                // This matches iOS behavior where partials are only emitted with real text
                if (event.text.isNotBlank() && event.text != "...") {
                    val wordCount = event.text.trim().split("\\s+".toRegex()).size
                    _uiState.update {
                        it.copy(
                            transcription = event.text,
                            metrics = TranscriptionMetrics(
                                confidence = event.confidence,
                                wordCount = wordCount
                            )
                        )
                    }
                    Log.d(TAG, "Partial transcription: ${event.text}")
                }
            }
            is STTStreamEvent.FinalTranscription -> {
                val result = event.result
                val wordCount = result.transcript.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
                _uiState.update {
                    it.copy(
                        transcription = result.transcript,
                        metrics = TranscriptionMetrics(
                            confidence = result.confidence ?: 0f,
                            audioDurationMs = 0.0, // Not available in stream result
                            inferenceTimeMs = 0.0,
                            detectedLanguage = result.language ?: "",
                            wordCount = wordCount
                        )
                    )
                }
                Log.i(TAG, "Final: ${result.transcript}")
            }
            is STTStreamEvent.AudioLevelChanged -> {
                _uiState.update { it.copy(audioLevel = event.level) }
            }
            is STTStreamEvent.Error -> {
                _uiState.update { it.copy(errorMessage = event.error.message) }
                Log.e(TAG, "STT Error: ${event.error}")
            }
            else -> { /* Ignore other events */ }
        }
    }

    /**
     * Stop audio recording and process transcription (for batch mode)
     * iOS Reference: stopRecording() in STTViewModel
     */
    private suspend fun stopRecording() {
        Log.i(TAG, "Stopping recording in ${_uiState.value.mode} mode")

        // Stop audio capture FIRST - this will cause the callbackFlow to close gracefully
        audioCaptureService?.stopCapture()

        // Wait a moment for the flow to complete and buffer to be filled
        kotlinx.coroutines.delay(100)

        // Now cancel the recording job (it should already be completing)
        recordingJob?.cancel()
        recordingJob = null

        // Reset audio level
        _uiState.update {
            it.copy(
                recordingState = if (_uiState.value.mode == STTMode.BATCH) {
                    RecordingState.PROCESSING
                } else {
                    RecordingState.IDLE
                },
                audioLevel = 0f,
                isTranscribing = _uiState.value.mode == STTMode.BATCH
            )
        }

        // For batch mode, transcribe the collected audio
        if (_uiState.value.mode == STTMode.BATCH) {
            performBatchTranscription()
        }
    }

    /**
     * Perform batch transcription on collected audio
     * iOS Reference: performBatchTranscription() in STTViewModel
     */
    private suspend fun performBatchTranscription() {
        val component = sttComponent ?: run {
            _uiState.update {
                it.copy(
                    errorMessage = "No STT model loaded",
                    recordingState = RecordingState.IDLE,
                    isTranscribing = false
                )
            }
            return
        }

        val audioBytes = audioBuffer.toByteArray()
        if (audioBytes.isEmpty()) {
            _uiState.update {
                it.copy(
                    errorMessage = "No audio recorded",
                    recordingState = RecordingState.IDLE,
                    isTranscribing = false
                )
            }
            return
        }

        Log.i(TAG, "Starting batch transcription of ${audioBytes.size} bytes")

        try {
            withContext(Dispatchers.IO) {
                val startTime = System.currentTimeMillis()

                // Convert PCM bytes to float samples for SDK
                val samples = bytesToFloats(audioBytes)

                // Calculate audio duration: bytes / (sample_rate * 2 bytes per sample) * 1000 ms
                val audioDurationMs = (audioBytes.size.toDouble() / (SAMPLE_RATE * 2)) * 1000

                // Transcribe using SDK's STTComponent
                // iOS Reference: component.transcribe(audioBuffer, options: options)
                val result = component.transcribe(
                    audioBuffer = samples,
                    language = _uiState.value.language
                )

                val inferenceTimeMs = System.currentTimeMillis() - startTime
                val wordCount = result.text.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size

                withContext(Dispatchers.Main) {
                    _uiState.update {
                        it.copy(
                            transcription = result.text,
                            recordingState = RecordingState.IDLE,
                            isTranscribing = false,
                            metrics = TranscriptionMetrics(
                                confidence = result.confidence,
                                audioDurationMs = audioDurationMs,
                                inferenceTimeMs = inferenceTimeMs.toDouble(),
                                detectedLanguage = result.detectedLanguage ?: _uiState.value.language,
                                wordCount = wordCount
                            )
                        )
                    }
                }

                Log.i(TAG, "✅ Batch transcription complete: ${result.text} (${inferenceTimeMs}ms, ${wordCount} words)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Batch transcription failed: ${e.message}", e)
            _uiState.update {
                it.copy(
                    errorMessage = "Transcription failed: ${e.message}",
                    recordingState = RecordingState.IDLE,
                    isTranscribing = false,
                    metrics = null
                )
            }
        }
    }

    /**
     * Set the transcription language
     *
     * @param language Language code (e.g., "en", "es", "fr")
     */
    fun setLanguage(language: String) {
        _uiState.update { it.copy(language = language) }
    }

    /**
     * Clear the current transcription
     */
    fun clearTranscription() {
        _uiState.update { it.copy(transcription = "") }
    }

    /**
     * Unload the current model
     * iOS Reference: cleanup() in STTComponent
     */
    fun unloadModel() {
        viewModelScope.launch {
            try {
                sttComponent?.cleanup()
            } catch (e: Exception) {
                Log.e(TAG, "Error cleaning up STT component: ${e.message}", e)
            }

            sttComponent = null

            _uiState.update {
                it.copy(
                    isModelLoaded = false,
                    selectedFramework = null,
                    selectedModelName = null,
                    selectedModelId = null,
                    transcription = "",
                    supportsLiveMode = false
                )
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        recordingJob?.cancel()
        audioCaptureService?.release()
        // Cleanup synchronously
        try {
            kotlinx.coroutines.runBlocking {
                sttComponent?.cleanup()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up STT component on cleared: ${e.message}", e)
        }
    }

    // ============================================================================
    // Private Helper Methods
    // ============================================================================

    /**
     * Normalize audio level to 0-1 range for UI visualization
     * iOS Reference: updateAudioLevel() in STTViewModel
     */
    private fun normalizeAudioLevel(rms: Float): Float {
        // Convert RMS to dB scale and normalize
        val dbLevel = 20 * log10(rms + 0.0001f)
        // Normalize to 0-1 range (assuming -60dB to 0dB range)
        return max(0f, min(1f, (dbLevel + 60) / 60))
    }

    /**
     * Convert PCM 16-bit bytes to float samples
     */
    private fun bytesToFloats(pcmBytes: ByteArray): FloatArray {
        val shorts = ShortArray(pcmBytes.size / 2)
        ByteBuffer.wrap(pcmBytes)
            .order(ByteOrder.LITTLE_ENDIAN)
            .asShortBuffer()
            .get(shorts)

        return FloatArray(shorts.size) { i ->
            shorts[i].toFloat() / Short.MAX_VALUE.toFloat()
        }
    }
}
