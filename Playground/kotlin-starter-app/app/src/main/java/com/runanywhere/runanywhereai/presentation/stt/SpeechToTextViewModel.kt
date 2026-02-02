package com.runanywhere.runanywhereai.presentation.stt

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.currentSTTModelId
import com.runanywhere.sdk.public.extensions.isSTTModelLoadedSync
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.transcribeStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * STT Recording Mode
 * iOS Reference: STTMode enum in STTViewModel.swift
 */
enum class STTMode {
    BATCH, // Record full audio then transcribe
    LIVE, // Real-time streaming transcription
}

/**
 * Recording State
 * iOS Reference: Recording state in STTViewModel.swift
 */
enum class RecordingState {
    IDLE,
    RECORDING,
    PROCESSING,
}

/**
 * Transcription metrics for display
 */
data class TranscriptionMetrics(
    val confidence: Float = 0f,
    val audioDurationMs: Double = 0.0,
    val inferenceTimeMs: Double = 0.0,
    val detectedLanguage: String = "",
    val wordCount: Int = 0,
) {
    val realTimeFactor: Double
        get() = if (audioDurationMs > 0) inferenceTimeMs / audioDurationMs else 0.0
}

/**
 * STT UI State
 * iOS Reference: STTViewModel published properties in STTViewModel.swift
 */
data class STTUiState(
    val mode: STTMode = STTMode.BATCH,
    val recordingState: RecordingState = RecordingState.IDLE,
    val transcription: String = "",
    val isModelLoaded: Boolean = false,
    val selectedFramework: InferenceFramework? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val audioLevel: Float = 0f,
    val language: String = "en",
    val errorMessage: String? = null,
    val isTranscribing: Boolean = false,
    val metrics: TranscriptionMetrics? = null,
    val isProcessing: Boolean = false,
    /** Whether selected model supports live streaming */
    val supportsLiveMode: Boolean = true,
)

/**
 * Speech to Text ViewModel
 *
 * iOS Reference: STTViewModel in STTViewModel.swift
 *
 * This ViewModel manages:
 * - Model loading via RunAnywhere.loadSTTModel()
 * - Recording state management with AudioCaptureService
 * - Transcription via RunAnywhere.transcribe()
 * - Audio level monitoring for UI visualization
 */
class SpeechToTextViewModel : ViewModel() {
    companion object {
        private const val TAG = "STTViewModel"
        private const val SAMPLE_RATE = 16000 // 16kHz for Whisper/ONNX STT models
    }

    private val _uiState = MutableStateFlow(STTUiState())
    val uiState: StateFlow<STTUiState> = _uiState.asStateFlow()

    // Audio capture service
    private var audioCaptureService: AudioCaptureService? = null

    // Audio recording state
    private var recordingJob: Job? = null
    private val audioBuffer = ByteArrayOutputStream()

    // SDK event subscription
    private var eventSubscriptionJob: Job? = null

    // Initialization state (for idempotency)
    private var isInitialized = false
    private var hasSubscribedToEvents = false

    init {
        Log.d(TAG, "STTViewModel initialized")
    }

    /**
     * Initialize the STT ViewModel with context for audio capture
     * iOS equivalent: initialize() in STTViewModel.swift
     */
    fun initialize(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "STT view model already initialized, skipping")
            return
        }
        isInitialized = true

        viewModelScope.launch {
            Log.i(TAG, "Initializing STT view model...")

            // Initialize audio capture service
            audioCaptureService = AudioCaptureService(context)

            // Check for microphone permission
            val hasPermission =
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                Log.w(TAG, "Microphone permission not granted")
                _uiState.update { it.copy(errorMessage = "Microphone permission required") }
            }

            // Subscribe to SDK events for STT model state
            subscribeToSDKEvents()

            // Check initial STT model state
            checkInitialModelState()
        }
    }

    /**
     * Subscribe to SDK events for STT model state updates
     * iOS Reference: subscribeToSDKEvents() in STTViewModel.swift
     */
    private fun subscribeToSDKEvents() {
        if (hasSubscribedToEvents) {
            Log.d(TAG, "Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToEvents = true

        eventSubscriptionJob =
            viewModelScope.launch {
                // Listen for model events with STT category
                EventBus.events.collect { event ->
                    // Filter for model events with STT category
                    if (event is ModelEvent && event.category == EventCategory.STT) {
                        handleModelEvent(event)
                    }
                }
            }
    }

    /**
     * Handle model events for STT
     * iOS Reference: handleSDKEvent() in STTViewModel.swift
     */
    private fun handleModelEvent(event: ModelEvent) {
        when (event.eventType) {
            ModelEvent.ModelEventType.LOADED -> {
                Log.i(TAG, "STT model loaded: ${event.modelId}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelId = event.modelId,
                        selectedModelName = it.selectedModelName ?: event.modelId,
                        isProcessing = false,
                    )
                }
            }
            ModelEvent.ModelEventType.UNLOADED -> {
                Log.i(TAG, "STT model unloaded: ${event.modelId}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = false,
                        selectedModelId = null,
                        selectedModelName = null,
                        selectedFramework = null,
                    )
                }
            }
            ModelEvent.ModelEventType.DOWNLOAD_STARTED -> {
                Log.i(TAG, "STT model download started: ${event.modelId}")
                _uiState.update { it.copy(isProcessing = true) }
            }
            ModelEvent.ModelEventType.DOWNLOAD_COMPLETED -> {
                Log.i(TAG, "STT model download completed: ${event.modelId}")
                _uiState.update { it.copy(isProcessing = false) }
            }
            ModelEvent.ModelEventType.DOWNLOAD_FAILED -> {
                Log.e(TAG, "STT model download failed: ${event.modelId} - ${event.error}")
                _uiState.update {
                    it.copy(
                        errorMessage = "Download failed: ${event.error}",
                        isProcessing = false,
                    )
                }
            }
            else -> { /* Other events not relevant for STT state */ }
        }
    }

    /**
     * Check initial STT model state
     * iOS Reference: checkInitialModelState() in STTViewModel.swift
     */
    private fun checkInitialModelState() {
        if (RunAnywhere.isSTTModelLoadedSync) {
            val modelId = RunAnywhere.currentSTTModelId
            _uiState.update {
                it.copy(
                    isModelLoaded = true,
                    selectedModelId = modelId,
                    selectedModelName = modelId,
                )
            }
            Log.i(TAG, "STT model already loaded: $modelId")
        }
    }

    /**
     * Set the STT mode (Batch or Live)
     */
    fun setMode(mode: STTMode) {
        _uiState.update { it.copy(mode = mode) }
    }

    /**
     * Set the selected model name (for display purposes)
     * Called when model is selected from UI before SDK events arrive
     */
    fun setSelectedModelName(name: String) {
        _uiState.update { it.copy(selectedModelName = name) }
    }

    /**
     * Called when a model has been loaded (e.g., by ModelSelectionViewModel)
     * This updates the UI state to reflect the loaded model
     */
    fun onModelLoaded(
        modelName: String,
        modelId: String,
        framework: InferenceFramework?,
    ) {
        Log.i(TAG, "Model loaded notification: $modelName (id: $modelId, framework: ${framework?.displayName})")
        _uiState.update {
            it.copy(
                isModelLoaded = true,
                selectedModelName = modelName,
                selectedModelId = modelId,
                selectedFramework = framework,
                isProcessing = false,
                errorMessage = null,
            )
        }
    }

    /**
     * Load a STT model via SDK
     * iOS Reference: loadModelFromSelection() in STTViewModel.swift
     *
     * @param modelName Display name of the model
     * @param modelId Model identifier for SDK
     */
    fun loadModel(
        modelName: String,
        modelId: String,
    ) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isProcessing = true,
                    errorMessage = null,
                )
            }

            try {
                Log.i(TAG, "Loading STT model: $modelName (id: $modelId)")

                // Use SDK's loadSTTModel extension function
                RunAnywhere.loadSTTModel(modelId)

                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelName = modelName,
                        selectedModelId = modelId,
                        isProcessing = false,
                    )
                }

                Log.i(TAG, "✅ STT model loaded successfully: $modelName")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load STT model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        errorMessage = "Failed to load model: ${e.message}",
                        isProcessing = false,
                    )
                }
            }
        }
    }

    /**
     * Toggle recording state
     * iOS Reference: toggleRecording() in STTViewModel.swift
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
     * iOS Reference: startRecording() in STTViewModel.swift
     */
    private suspend fun startRecording() {
        Log.i(TAG, "Starting recording in ${_uiState.value.mode} mode")

        if (!_uiState.value.isModelLoaded) {
            _uiState.update { it.copy(errorMessage = "No STT model loaded") }
            return
        }

        // Clear previous state
        _uiState.update {
            it.copy(
                recordingState = RecordingState.RECORDING,
                transcription = "",
                errorMessage = null,
                audioLevel = 0f,
            )
        }
        audioBuffer.reset()

        val audioCapture =
            audioCaptureService ?: run {
                _uiState.update { it.copy(errorMessage = "Audio capture not initialized") }
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
        recordingJob =
            viewModelScope.launch {
                try {
                    audioCapture.startCapture().collect { audioData ->
                        // Append to buffer
                        withContext(Dispatchers.IO) {
                            audioBuffer.write(audioData)
                        }

                        // Calculate and update audio level
                        val rms = audioCapture.calculateRMS(audioData)
                        val normalizedLevel = normalizeAudioLevel(rms)
                        _uiState.update { it.copy(audioLevel = normalizedLevel) }
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    Log.d(TAG, "Batch recording cancelled (expected when stopping)")
                } catch (e: Exception) {
                    Log.e(TAG, "Error during batch recording: ${e.message}", e)
                    _uiState.update {
                        it.copy(
                            errorMessage = "Recording error: ${e.message}",
                            recordingState = RecordingState.IDLE,
                            audioLevel = 0f,
                        )
                    }
                }
            }
    }

    /**
     * Start live streaming recording - transcribe in chunks
     * iOS Reference: Live mode in startRecording() with liveTranscribe
     *
     * Note: The SDK's transcribeStream API takes a ByteArray, not a Flow.
     * For live mode, we collect audio chunks and transcribe them incrementally.
     */
    private fun startLiveRecording(audioCapture: AudioCaptureService) {
        recordingJob =
            viewModelScope.launch {
                try {
                    val chunkBuffer = ByteArrayOutputStream()
                    var lastTranscription = ""

                    audioCapture.startCapture().collect { audioData ->
                        // Update audio level
                        val rms = audioCapture.calculateRMS(audioData)
                        val normalizedLevel = normalizeAudioLevel(rms)
                        _uiState.update { it.copy(audioLevel = normalizedLevel) }

                        // Append to chunk buffer
                        chunkBuffer.write(audioData)

                        // Transcribe every ~1 second of audio (16000 samples * 2 bytes = 32000 bytes)
                        if (chunkBuffer.size() >= 32000) {
                            val chunkData = chunkBuffer.toByteArray()
                            chunkBuffer.reset()

                            // Transcribe in background
                            withContext(Dispatchers.IO) {
                                try {
                                    val options = STTOptions(language = _uiState.value.language)
                                    val result =
                                        RunAnywhere.transcribeStream(
                                            audioData = chunkData,
                                            options = options,
                                        ) { partial ->
                                            // Update UI with partial result (non-suspend callback)
                                            if (partial.transcript.isNotBlank()) {
                                                val newText = lastTranscription + " " + partial.transcript
                                                // Use launch since we're in a non-suspend callback
                                                viewModelScope.launch(Dispatchers.Main) {
                                                    handleSTTStreamText(newText.trim())
                                                }
                                            }
                                        }
                                    // Update with final result
                                    lastTranscription = (lastTranscription + " " + result.text).trim()
                                    withContext(Dispatchers.Main) {
                                        handleSTTStreamText(lastTranscription)
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "Chunk transcription error: ${e.message}")
                                }
                            }
                        }
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    Log.d(TAG, "Live recording cancelled (expected when stopping)")
                } catch (e: Exception) {
                    Log.e(TAG, "Error during live recording: ${e.message}", e)
                    _uiState.update {
                        it.copy(
                            errorMessage = "Live transcription error: ${e.message}",
                            recordingState = RecordingState.IDLE,
                            audioLevel = 0f,
                        )
                    }
                }
            }
    }

    /**
     * Handle STT stream text during live transcription
     */
    private fun handleSTTStreamText(text: String) {
        if (text.isNotBlank() && text != "...") {
            val wordCount = text.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
            _uiState.update {
                it.copy(
                    transcription = text,
                    metrics =
                        TranscriptionMetrics(
                            confidence = 0f,
                            wordCount = wordCount,
                        ),
                )
            }
            Log.d(TAG, "Stream transcription: $text")
        }
    }

    /**
     * Stop audio recording and process transcription (for batch mode)
     * iOS Reference: stopRecording() in STTViewModel.swift
     */
    private suspend fun stopRecording() {
        Log.i(TAG, "Stopping recording in ${_uiState.value.mode} mode")

        // Stop audio capture
        audioCaptureService?.stopCapture()

        // Wait a moment for the flow to complete
        kotlinx.coroutines.delay(100)

        // Cancel the recording job
        recordingJob?.cancel()
        recordingJob = null

        // Reset audio level
        _uiState.update {
            it.copy(
                recordingState =
                    if (_uiState.value.mode == STTMode.BATCH) {
                        RecordingState.PROCESSING
                    } else {
                        RecordingState.IDLE
                    },
                audioLevel = 0f,
                isTranscribing = _uiState.value.mode == STTMode.BATCH,
            )
        }

        // For batch mode, transcribe the collected audio
        if (_uiState.value.mode == STTMode.BATCH) {
            performBatchTranscription()
        }
    }

    /**
     * Perform batch transcription on collected audio
     * iOS Reference: performBatchTranscription() in STTViewModel.swift
     */
    private suspend fun performBatchTranscription() {
        val audioBytes = audioBuffer.toByteArray()
        if (audioBytes.isEmpty()) {
            _uiState.update {
                it.copy(
                    errorMessage = "No audio recorded",
                    recordingState = RecordingState.IDLE,
                    isTranscribing = false,
                )
            }
            return
        }

        Log.i(TAG, "Starting batch transcription of ${audioBytes.size} bytes")

        try {
            withContext(Dispatchers.IO) {
                val startTime = System.currentTimeMillis()

                // Calculate audio duration: bytes / (sample_rate * 2 bytes per sample) * 1000 ms
                val audioDurationMs = (audioBytes.size.toDouble() / (SAMPLE_RATE * 2)) * 1000

                // Use SDK's transcribe extension function
                val result = RunAnywhere.transcribe(audioBytes)

                val inferenceTimeMs = System.currentTimeMillis() - startTime
                val wordCount = result.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size

                withContext(Dispatchers.Main) {
                    _uiState.update {
                        it.copy(
                            transcription = result,
                            recordingState = RecordingState.IDLE,
                            isTranscribing = false,
                            metrics =
                                TranscriptionMetrics(
                                    confidence = 0f,
                                    audioDurationMs = audioDurationMs,
                                    inferenceTimeMs = inferenceTimeMs.toDouble(),
                                    detectedLanguage = _uiState.value.language,
                                    wordCount = wordCount,
                                ),
                        )
                    }
                }

                Log.i(TAG, "✅ Batch transcription complete: $result (${inferenceTimeMs}ms, $wordCount words)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Batch transcription failed: ${e.message}", e)
            _uiState.update {
                it.copy(
                    errorMessage = "Transcription failed: ${e.message}",
                    recordingState = RecordingState.IDLE,
                    isTranscribing = false,
                    metrics = null,
                )
            }
        }
    }

    /**
     * Set the transcription language
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
     * Clean up resources
     * iOS Reference: cleanup() in STTViewModel.swift
     */
    fun cleanup() {
        recordingJob?.cancel()
        eventSubscriptionJob?.cancel()
        audioCaptureService?.release()

        // Reset initialization flags
        isInitialized = false
        hasSubscribedToEvents = false
    }

    override fun onCleared() {
        super.onCleared()
        cleanup()
    }

    // ============================================================================
    // Private Helper Methods
    // ============================================================================

    /**
     * Normalize audio level to 0-1 range for UI visualization
     */
    private fun normalizeAudioLevel(rms: Float): Float {
        val dbLevel = 20 * log10(rms + 0.0001f)
        return max(0f, min(1f, (dbLevel + 60) / 60))
    }
}
