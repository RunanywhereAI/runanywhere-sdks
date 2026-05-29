package com.runanywhere.runanywhereai.presentation.vad

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_VAD
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.SDKComponent
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
import com.runanywhere.sdk.public.extensions.componentLifecycleSnapshot
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.detectVoiceActivity
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.ByteArrayOutputStream

/**
 * A single entry in the speech activity log.
 *
 * iOS Reference: SpeechActivityLogEntry struct in VADViewModel.swift
 */
data class SpeechActivityLogEntry(
    val id: Long,
    val type: ActivityType,
    val timestampMs: Long,
) {
    enum class ActivityType {
        SPEECH_STARTED,
        SPEECH_ENDED,
    }
}

/**
 * VAD UI State
 *
 * iOS Reference: VADViewModel published properties in VADViewModel.swift
 */
data class VADUiState(
    val selectedFramework: InferenceFramework? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val isModelLoaded: Boolean = false,
    val isListening: Boolean = false,
    val isProcessing: Boolean = false,
    val isSpeechDetected: Boolean = false,
    val audioLevel: Float = 0f,
    val errorMessage: String? = null,
    val activityLog: List<SpeechActivityLogEntry> = emptyList(),
)

/**
 * Voice Activity Detection ViewModel
 *
 * iOS Reference: VADViewModel in VADViewModel.swift
 *
 * This ViewModel manages:
 * - Microphone capture via AudioCaptureService
 * - Audio buffering: 1024 bytes = 512 Int16 samples = 32ms @ 16kHz
 * - Detection loop polling every 30ms, calls RunAnywhere.detectVoiceActivity()
 * - Activity log of speech start/end events (capped at 50 entries)
 */
class VADViewModel : ViewModel() {
    companion object {
        // 512 Int16 samples = 1024 bytes = 32ms @ 16kHz, matching iOS VADViewModel.startDetectionLoop
        private const val VAD_FRAME_BYTES = 1024
        private const val DETECTION_INTERVAL_MS = 30L
        private const val MAX_LOG_ENTRIES = 50
    }

    private val _uiState = MutableStateFlow(VADUiState())
    val uiState: StateFlow<VADUiState> = _uiState.asStateFlow()

    // Audio capture service
    private var audioCaptureService: AudioCaptureService? = null

    // Capture and detection coroutines
    private var captureJob: Job? = null
    private var detectionJob: Job? = null
    private var eventSubscriptionJob: Job? = null

    // Audio ring buffer fed by capture, drained by detection loop.
    private val audioBuffer = ByteArrayOutputStream()
    private val bufferMutex = Mutex()

    // Tracks the next sequential entry id for the activity log.
    private var nextLogEntryId = 0L

    // Initialization guards (idempotency)
    private var isInitialized = false
    private var hasSubscribedToEvents = false

    init {
        Timber.d("VADViewModel initialized")
    }

    /**
     * Initialize the ViewModel with context for audio capture
     * iOS equivalent: initialize() in VADViewModel.swift
     */
    fun initialize(context: Context) {
        if (isInitialized) {
            Timber.d("VAD view model already initialized, skipping")
            return
        }
        isInitialized = true

        viewModelScope.launch {
            Timber.i("Initializing VAD view model...")

            audioCaptureService = AudioCaptureService(context)

            val hasPermission =
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                Timber.w("Microphone permission not granted")
                _uiState.update { it.copy(errorMessage = "Microphone permission required") }
            }

            subscribeToSDKEvents()
            checkInitialModelState()
        }
    }

    /**
     * Subscribe to SDK events for VAD model state updates.
     * iOS Reference: subscribeToSDKEvents() in VADViewModel.swift
     */
    private fun subscribeToSDKEvents() {
        if (hasSubscribedToEvents) {
            Timber.d("Already subscribed to VAD SDK events, skipping")
            return
        }
        hasSubscribedToEvents = true

        eventSubscriptionJob =
            viewModelScope.launch {
                EventBus.events.collect { event ->
                    if (event.category == EVENT_CATEGORY_VAD) {
                        event.model?.let { handleModelEvent(it) }
                    }
                }
            }
    }

    /**
     * Handle model events for VAD.
     * iOS Reference: handleSDKEvent() in VADViewModel.swift
     */
    private fun handleModelEvent(event: ModelEvent) {
        when (event.kind) {
            ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED -> {
                Timber.i("VAD model loaded: ${event.model_id}")
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
                Timber.i("VAD model unloaded: ${event.model_id}")
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
                _uiState.update { it.copy(isProcessing = true) }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED -> {
                _uiState.update { it.copy(isProcessing = false) }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED -> {
                Timber.e("VAD model download failed: ${event.model_id} - ${event.error}")
                _uiState.update {
                    it.copy(
                        errorMessage = "Download failed: ${event.error}",
                        isProcessing = false,
                    )
                }
            }
            else -> { /* Other events not relevant for VAD state */ }
        }
    }

    /**
     * Check whether a VAD model is already loaded in the SDK.
     * iOS Reference: checkInitialModelState() in VADViewModel.swift
     */
    private suspend fun checkInitialModelState() {
        val snapshot = RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_VAD)
        val isLoaded =
            snapshot?.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                snapshot.model_id.isNotEmpty()
        if (isLoaded) {
            val current =
                RunAnywhere.currentModel(
                    CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION),
                )
            val modelId = current.model_id.takeIf { it.isNotEmpty() }
            val displayName = current.model?.name ?: modelId
            _uiState.update {
                it.copy(
                    isModelLoaded = true,
                    selectedModelId = modelId,
                    selectedModelName = displayName,
                )
            }
            Timber.i("VAD model already loaded: $displayName")
        }
    }

    /**
     * Called when a VAD model has been loaded (e.g., by ModelSelectionViewModel)
     */
    fun onModelLoaded(
        modelName: String,
        modelId: String,
        framework: InferenceFramework?,
    ) {
        Timber.i("VAD model loaded notification: $modelName (id: $modelId)")
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
     * Load a VAD model via SDK.
     * iOS Reference: loadModelFromSelection() in VADViewModel.swift
     */
    fun loadModel(
        modelName: String,
        modelId: String,
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, errorMessage = null) }

            try {
                Timber.i("Loading VAD model: $modelName (id: $modelId)")
                RunAnywhere.loadModel(
                    RAModelLoadRequest(
                        model_id = modelId,
                        category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
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
                Timber.i("VAD model loaded successfully: $modelName")
            } catch (e: Exception) {
                Timber.e(e, "Failed to load VAD model: ${e.message}")
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
     * Toggle listening state (start/stop).
     * iOS Reference: toggleListening() in VADViewModel.swift
     */
    fun toggleListening() {
        viewModelScope.launch {
            if (_uiState.value.isListening) {
                stopListening()
            } else {
                startListening()
            }
        }
    }

    /**
     * Clear the activity log.
     * iOS Reference: clearLog() in VADViewModel.swift
     */
    fun clearLog() {
        _uiState.update { it.copy(activityLog = emptyList()) }
    }

    /**
     * Start audio capture and VAD detection.
     * iOS Reference: startListening() in VADViewModel.swift
     */
    private suspend fun startListening() {
        Timber.i("Starting VAD listening")

        if (!_uiState.value.isModelLoaded) {
            _uiState.update { it.copy(errorMessage = "No VAD model loaded") }
            return
        }

        val audioCapture =
            audioCaptureService ?: run {
                _uiState.update { it.copy(errorMessage = "Audio capture not initialized") }
                return
            }

        bufferMutex.withLock { audioBuffer.reset() }
        _uiState.update {
            it.copy(
                isListening = true,
                isSpeechDetected = false,
                errorMessage = null,
                audioLevel = 0f,
            )
        }

        captureJob =
            viewModelScope.launch {
                try {
                    audioCapture.startCapture().collect { audioData ->
                        bufferMutex.withLock { audioBuffer.write(audioData) }

                        val rms = audioCapture.calculateRMS(audioData)
                        _uiState.update { it.copy(audioLevel = rms) }
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    Timber.d("VAD capture cancelled (expected when stopping)")
                } catch (e: Exception) {
                    Timber.e(e, "VAD capture error: ${e.message}")
                    _uiState.update {
                        it.copy(
                            errorMessage = "Recording error: ${e.message}",
                            isListening = false,
                            audioLevel = 0f,
                        )
                    }
                }
            }

        startDetectionLoop()
        Timber.i("VAD listening started")
    }

    /**
     * Stop audio capture and detection loop.
     * iOS Reference: stopListening() in VADViewModel.swift
     */
    private suspend fun stopListening() {
        Timber.i("Stopping VAD listening")

        detectionJob?.cancel()
        detectionJob = null

        audioCaptureService?.stopCapture()
        captureJob?.cancel()
        captureJob = null

        bufferMutex.withLock { audioBuffer.reset() }

        _uiState.update {
            it.copy(
                isListening = false,
                isSpeechDetected = false,
                audioLevel = 0f,
            )
        }
    }

    /**
     * Continuously poll the audio buffer every 30ms, running VAD on each
     * 1024-byte (512 Int16 samples / 32ms @ 16kHz) frame as it becomes
     * available.
     *
     * iOS Reference: startDetectionLoop() in VADViewModel.swift
     */
    private fun startDetectionLoop() {
        detectionJob =
            viewModelScope.launch(Dispatchers.Default) {
                var wasSpeechActive = false
                while (_uiState.value.isListening) {
                    val frame: ByteArray? =
                        bufferMutex.withLock {
                            if (audioBuffer.size() >= VAD_FRAME_BYTES) {
                                val all = audioBuffer.toByteArray()
                                val take = all.copyOfRange(0, VAD_FRAME_BYTES)
                                val rest = all.copyOfRange(VAD_FRAME_BYTES, all.size)
                                audioBuffer.reset()
                                audioBuffer.write(rest)
                                take
                            } else {
                                null
                            }
                        }

                    if (frame != null) {
                        try {
                            val result =
                                withContext(Dispatchers.IO) {
                                    RunAnywhere.detectVoiceActivity(frame)
                                }
                            val speechDetected = result.is_speech

                            _uiState.update { it.copy(isSpeechDetected = speechDetected) }

                            if (speechDetected && !wasSpeechActive) {
                                addLogEntry(SpeechActivityLogEntry.ActivityType.SPEECH_STARTED)
                                wasSpeechActive = true
                            } else if (!speechDetected && wasSpeechActive) {
                                addLogEntry(SpeechActivityLogEntry.ActivityType.SPEECH_ENDED)
                                wasSpeechActive = false
                            }
                        } catch (e: Exception) {
                            Timber.e(e, "VAD processing error: ${e.message}")
                        }
                    }

                    delay(DETECTION_INTERVAL_MS)
                }
            }
    }

    /**
     * Insert a new log entry at the top, capped at MAX_LOG_ENTRIES.
     * iOS Reference: addLogEntry() in VADViewModel.swift
     */
    private fun addLogEntry(type: SpeechActivityLogEntry.ActivityType) {
        val entry =
            SpeechActivityLogEntry(
                id = nextLogEntryId++,
                type = type,
                timestampMs = System.currentTimeMillis(),
            )
        _uiState.update { state ->
            val updated = (listOf(entry) + state.activityLog).take(MAX_LOG_ENTRIES)
            state.copy(activityLog = updated)
        }
    }

    /**
     * Clean up resources.
     * iOS Reference: cleanup() in VADViewModel.swift
     */
    fun cleanup() {
        detectionJob?.cancel()
        captureJob?.cancel()
        eventSubscriptionJob?.cancel()
        audioCaptureService?.release()
        isInitialized = false
        hasSubscribedToEvents = false
    }

    override fun onCleared() {
        super.onCleared()
        cleanup()
    }
}
