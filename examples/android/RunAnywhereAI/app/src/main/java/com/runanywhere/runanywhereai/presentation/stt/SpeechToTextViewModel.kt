package com.runanywhere.runanywhereai.presentation.stt

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_STT
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.STTOptions
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.extensions.componentLifecycleSnapshot
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.defaults
import com.runanywhere.sdk.public.extensions.fromBcp47
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RASTTOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
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
 * - Model loading via RunAnywhere.loadModel(RAModelLoadRequest)
 * - Recording state management with AudioCaptureService
 * - Transcription via RunAnywhere.transcribe()
 * - Audio level monitoring for UI visualization
 */
class SpeechToTextViewModel : ViewModel() {
    companion object {
        private const val SAMPLE_RATE = 16000 // 16kHz for Whisper/ONNX STT models

        // VAD-gated live transcription (mirrors iOS STTViewModel.swift)
        // iOS uses speechThreshold=0.02 (normalized dB level) and silenceDuration=1.5s.
        private const val SPEECH_THRESHOLD = 0.02f
        private const val SILENCE_DURATION_MS = 1500L
        private const val VAD_POLL_INTERVAL_MS = 50L

        // Minimum audio bytes before transcribing (~0.5s at 16kHz mono 16-bit).
        // Mirrors iOS: `if audioBuffer.count > 16000`.
        private const val MIN_TRANSCRIBE_BYTES = 16000
    }

    private val _uiState = MutableStateFlow(STTUiState())
    val uiState: StateFlow<STTUiState> = _uiState.asStateFlow()

    // Audio capture service
    private var audioCaptureService: AudioCaptureService? = null

    // Audio recording state
    private var recordingJob: Job? = null
    private val audioBuffer = ByteArrayOutputStream()

    // VAD state for live mode (iOS parity: STTViewModel.swift)
    private var vadJob: Job? = null
    private var isSpeechActive = false
    private var lastSpeechTimeMs: Long = 0L

    // SDK event subscription
    private var eventSubscriptionJob: Job? = null

    // Initialization state (for idempotency)
    private var isInitialized = false
    private var hasSubscribedToEvents = false

    init {
        Timber.d("STTViewModel initialized")
    }

    /**
     * Initialize the STT ViewModel with context for audio capture
     * iOS equivalent: initialize() in STTViewModel.swift
     */
    fun initialize(context: Context) {
        if (isInitialized) {
            Timber.d("STT view model already initialized, skipping")
            return
        }
        isInitialized = true

        viewModelScope.launch {
            Timber.i("Initializing STT view model...")

            // Initialize audio capture service
            audioCaptureService = AudioCaptureService(context)

            // Check for microphone permission
            val hasPermission =
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                Timber.w("Microphone permission not granted")
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
            Timber.d("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToEvents = true

        eventSubscriptionJob =
            viewModelScope.launch {
                // Listen for model events with STT category
                EventBus.events.collect { event ->
                    // Filter for model events with STT category
                    if (event.category == EVENT_CATEGORY_STT) {
                        event.model?.let { handleModelEvent(it) }
                    }
                }
            }
    }

    /**
     * Handle model events for STT
     * iOS Reference: handleSDKEvent() in STTViewModel.swift
     */
    private fun handleModelEvent(event: ModelEvent) {
        when (event.kind) {
            ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED -> {
                Timber.i("STT model loaded: ${event.model_id}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelId = event.model_id,
                        selectedModelName = it.selectedModelName ?: event.model_id,
                        isProcessing = false,
                    )
                }
            }
            ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED -> {
                Timber.i("STT model unloaded: ${event.model_id}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = false,
                        selectedModelId = null,
                        selectedModelName = null,
                        selectedFramework = null,
                    )
                }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_STARTED -> {
                Timber.i("STT model download started: ${event.model_id}")
                _uiState.update { it.copy(isProcessing = true) }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED -> {
                Timber.i("STT model download completed: ${event.model_id}")
                _uiState.update { it.copy(isProcessing = false) }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED -> {
                Timber.e("STT model download failed: ${event.model_id} - ${event.error}")
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
     * Uses currentSTTModel() for display name so app bar shows correct model icon.
     */
    private suspend fun checkInitialModelState() {
        val sttSnapshot = RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_STT)
        val isLoaded =
            sttSnapshot.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                sttSnapshot.model_id.isNotEmpty()
        if (isLoaded) {
            val currentSTT =
                RunAnywhere.currentModel(
                    CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
                )
            val modelId = currentSTT.model_id.takeIf { it.isNotEmpty() }
            val displayName = currentSTT.model?.name ?: modelId
            _uiState.update {
                it.copy(
                    isModelLoaded = true,
                    selectedModelId = modelId,
                    selectedModelName = displayName,
                )
            }
            Timber.i("STT model already loaded: $displayName")
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
        Timber.i("Model loaded notification: $modelName (id: $modelId, framework: ${framework?.displayName})")
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
                Timber.i("Loading STT model: $modelName (id: $modelId)")

                // Use SDK's canonical proto-backed loadModel API
                RunAnywhere.loadModel(
                    RAModelLoadRequest(
                        model_id = modelId,
                        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                    ),
                )

                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelName = modelName,
                        selectedModelId = modelId,
                        isProcessing = false,
                    )
                }

                Timber.i("✅ STT model loaded successfully: $modelName")
            } catch (e: Exception) {
                Timber.e(e, "Failed to load STT model: ${e.message}")
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
        Timber.i("Starting recording in ${_uiState.value.mode} mode")

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
        // Reset VAD state (iOS parity: STTViewModel.swift startRecording())
        isSpeechActive = false
        lastSpeechTimeMs = 0L

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
                    Timber.d("Batch recording cancelled (expected when stopping)")
                } catch (e: Exception) {
                    Timber.e(e, "Error during batch recording: ${e.message}")
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
     * Start live streaming recording — VAD-gated batch transcription.
     *
     * iOS Reference: STTViewModel.swift `startVADMonitoring()` + `checkSpeechState()` +
     * `performLiveTranscription()`.
     *
     * Behaviour parity:
     *  - Continuously captures audio into `audioBuffer`.
     *  - A separate VAD polling task (50ms interval) watches the normalized audio level.
     *  - When level > 0.02 (≈ -58.8dB normalized) we mark speech as active.
     *  - Once 1.5s of silence elapses after speech, the accumulated buffer is sent to
     *    `RunAnywhere.transcribe` (batch), the buffer is cleared, and recording continues
     *    for the next utterance.
     *  - If the accumulated buffer is below 16000 bytes (~0.5s) at the point of silence
     *    we discard it rather than transcribing — this prevents Whisper from
     *    hallucinating "[BLANK_AUDIO]" / "[SIDE CONVERSATION]" tokens on near-empty
     *    buffers.
     *
     * This replaces the previous fixed-interval (~1s) chunk transcription that fed
     * Whisper noisy ambient audio regardless of whether speech was present, which
     * matched the user-reported symptom of Android STT being "too sensitive".
     */
    private fun startLiveRecording(audioCapture: AudioCaptureService) {
        // Audio capture coroutine: accumulate every chunk into audioBuffer and
        // mirror iOS's `audioBuffer.append(audioData)` callback.
        recordingJob =
            viewModelScope.launch {
                try {
                    audioCapture.startCapture().collect { audioData ->
                        withContext(Dispatchers.IO) {
                            audioBuffer.write(audioData)
                        }
                        val rms = audioCapture.calculateRMS(audioData)
                        val normalizedLevel = normalizeAudioLevel(rms)
                        _uiState.update { it.copy(audioLevel = normalizedLevel) }
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    Timber.d("Live recording cancelled (expected when stopping)")
                } catch (e: Exception) {
                    Timber.e(e, "Error during live recording: ${e.message}")
                    _uiState.update {
                        it.copy(
                            errorMessage = "Live transcription error: ${e.message}",
                            recordingState = RecordingState.IDLE,
                            audioLevel = 0f,
                        )
                    }
                }
            }

        // VAD monitor coroutine: poll audio level every 50ms and trigger an
        // accumulated-buffer transcription when 1.5s of silence follows speech.
        // Mirrors iOS `startVADMonitoring()` + `checkSpeechState()`.
        vadJob =
            viewModelScope.launch {
                Timber.i("Starting VAD monitoring for live transcription")
                while (isActive && _uiState.value.recordingState == RecordingState.RECORDING) {
                    val level = _uiState.value.audioLevel
                    checkSpeechState(level)
                    delay(VAD_POLL_INTERVAL_MS)
                }
            }
    }

    /**
     * VAD state machine: tracks speech onset/offset and auto-transcribes on silence.
     * iOS reference: STTViewModel.swift `checkSpeechState(level:)`.
     */
    private suspend fun checkSpeechState(level: Float) {
        if (_uiState.value.recordingState != RecordingState.RECORDING ||
            _uiState.value.mode != STTMode.LIVE
        ) {
            return
        }

        val nowMs = System.currentTimeMillis()
        if (level > SPEECH_THRESHOLD) {
            if (!isSpeechActive) {
                Timber.d("Speech started")
                isSpeechActive = true
            }
            lastSpeechTimeMs = nowMs
        } else if (isSpeechActive) {
            val silenceElapsed = nowMs - lastSpeechTimeMs
            if (silenceElapsed > SILENCE_DURATION_MS) {
                Timber.d("Silence detected — auto-transcribing")
                isSpeechActive = false

                val bufferedBytes =
                    withContext(Dispatchers.IO) {
                        audioBuffer.size()
                    }
                if (bufferedBytes > MIN_TRANSCRIBE_BYTES) {
                    performLiveTranscription()
                } else {
                    // Discard short / noise-only buffers to avoid Whisper hallucinations
                    withContext(Dispatchers.IO) {
                        audioBuffer.reset()
                    }
                }
            }
        }
    }

    /**
     * Transcribe the accumulated buffer for a single utterance and append to the
     * running transcript. Mirrors iOS `performLiveTranscription()`.
     */
    private suspend fun performLiveTranscription() {
        val audioBytes =
            withContext(Dispatchers.IO) {
                val bytes = audioBuffer.toByteArray()
                audioBuffer.reset()
                bytes
            }
        if (audioBytes.isEmpty()) return

        Timber.i("Live transcription of ${audioBytes.size} bytes")
        _uiState.update { it.copy(isTranscribing = true) }
        try {
            withContext(Dispatchers.IO) {
                val output = RunAnywhere.transcribe(audioBytes, defaultSttOptions())
                withContext(Dispatchers.Main) {
                    val existing = _uiState.value.transcription
                    val appended =
                        if (existing.isBlank()) {
                            output.text
                        } else {
                            existing + "\n" + output.text
                        }
                    _uiState.update {
                        it.copy(
                            transcription = appended,
                            isTranscribing = false,
                        )
                    }
                }
                Timber.i("Live transcription result: ${output.text}")
            }
        } catch (e: Exception) {
            Timber.e(e, "Live transcription failed: ${e.message}")
            _uiState.update {
                it.copy(
                    errorMessage = "Transcription failed: ${e.message}",
                    isTranscribing = false,
                )
            }
        }
    }

    /**
     * Stop audio recording and process transcription (for batch mode)
     * iOS Reference: stopRecording() in STTViewModel.swift
     */
    private suspend fun stopRecording() {
        Timber.i("Stopping recording in ${_uiState.value.mode} mode")

        // Stop VAD monitor first so it doesn't trigger a final transcription
        // mid-stop. Mirrors iOS `silenceCheckTask?.cancel()`.
        vadJob?.cancel()
        vadJob = null
        isSpeechActive = false
        lastSpeechTimeMs = 0L

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

        Timber.i("Starting batch transcription of ${audioBytes.size} bytes")

        try {
            withContext(Dispatchers.IO) {
                val startTime = System.currentTimeMillis()

                // Calculate audio duration: bytes / (sample_rate * 2 bytes per sample) * 1000 ms
                val audioDurationMs = (audioBytes.size.toDouble() / (SAMPLE_RATE * 2)) * 1000

                // Use SDK's transcribe extension function with iOS-default options
                // (language=EN, punctuation+word-timestamps enabled) — mirrors
                // Swift `RASTTOptions.defaults()`. Default `RASTTOptions()`
                // would send STT_LANGUAGE_UNSPECIFIED which Whisper can
                // misinterpret as auto-detect.
                val transcriptionOutput = RunAnywhere.transcribe(audioBytes, defaultSttOptions())
                val result = transcriptionOutput.text

                val inferenceTimeMs = System.currentTimeMillis() - startTime
                val wordCount =
                    result
                        .trim()
                        .split("\\s+".toRegex())
                        .filter { it.isNotEmpty() }
                        .size

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

                Timber.i("✅ Batch transcription complete: $result (${inferenceTimeMs}ms, $wordCount words)")
            }
        } catch (e: Exception) {
            Timber.e(e, "Batch transcription failed: ${e.message}")
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
        vadJob?.cancel()
        vadJob = null
        isSpeechActive = false
        lastSpeechTimeMs = 0L
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

    /**
     * Default `RASTTOptions` honouring the user-selected language from UI
     * state. Delegates BCP-47 parsing and option defaults to the SDK
     * (`STTLanguage.fromBcp47` + `STTOptions.defaults(language:)`) so the
     * example app does not duplicate the cross-platform mapping table.
     */
    private fun defaultSttOptions(): RASTTOptions {
        val parsed = STTLanguage.fromBcp47(_uiState.value.language)
        val lang =
            if (parsed == STTLanguage.STT_LANGUAGE_UNSPECIFIED) {
                STTLanguage.STT_LANGUAGE_EN
            } else {
                parsed
            }
        return STTOptions.defaults(language = lang)
    }
}
