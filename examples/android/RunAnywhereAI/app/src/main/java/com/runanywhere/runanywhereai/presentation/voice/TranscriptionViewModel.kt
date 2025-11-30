package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Transcript segment with speaker diarization support
 * Matches iOS TranscriptSegment
 */
@Serializable
data class TranscriptSegment(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val isFinal: Boolean,
    val speakerId: String? = null,
    val speakerName: String? = null
)

/**
 * Speaker information for diarization
 * Matches iOS SpeakerInfo
 */
@Serializable
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val color: Int? = null
)

// Note: ModelLoadState is defined in VoiceAssistantViewModel.kt

/**
 * TranscriptionViewModel - Voice transcription with speaker diarization
 * Matches iOS TranscriptionViewModel.swift structure
 */
class TranscriptionViewModel(application: Application) : AndroidViewModel(application) {

    // MARK: - Published Properties (matching iOS)

    private val _transcriptionText = MutableStateFlow("")
    val transcriptionText: StateFlow<String> = _transcriptionText.asStateFlow()

    private val _isTranscribing = MutableStateFlow(false)
    val isTranscribing: StateFlow<Boolean> = _isTranscribing.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    private val _currentStatus = MutableStateFlow("Initializing...")
    val currentStatus: StateFlow<String> = _currentStatus.asStateFlow()

    private val _whisperModel = MutableStateFlow("Whisper Base")
    val whisperModel: StateFlow<String> = _whisperModel.asStateFlow()

    private val _partialTranscript = MutableStateFlow("")
    val partialTranscript: StateFlow<String> = _partialTranscript.asStateFlow()

    private val _finalTranscripts = MutableStateFlow<List<TranscriptSegment>>(emptyList())
    val finalTranscripts: StateFlow<List<TranscriptSegment>> = _finalTranscripts.asStateFlow()

    private val _detectedSpeakers = MutableStateFlow<List<SpeakerInfo>>(emptyList())
    val detectedSpeakers: StateFlow<List<SpeakerInfo>> = _detectedSpeakers.asStateFlow()

    private val _currentSpeaker = MutableStateFlow<SpeakerInfo?>(null)
    val currentSpeaker: StateFlow<SpeakerInfo?> = _currentSpeaker.asStateFlow()

    private val _enableSpeakerDiarization = MutableStateFlow(true)
    val enableSpeakerDiarization: StateFlow<Boolean> = _enableSpeakerDiarization.asStateFlow()

    // MARK: - Model Loading State (from SDK lifecycle tracker)

    private val _sttModelState = MutableStateFlow(ModelLoadState.NOT_LOADED)
    val sttModelState: StateFlow<ModelLoadState> = _sttModelState.asStateFlow()

    val isModelLoaded: Boolean get() = _sttModelState.value.isLoaded

    // MARK: - Private Properties

    private val whisperModelName: String = "whisper-base"

    // MARK: - Initialization

    init {
        initialize()
    }

    private fun initialize() {
        viewModelScope.launch {
            try {
                // TODO: Request microphone permission
                // Matches iOS: await AudioCapture.requestMicrophonePermission()

                // Initialize SDK
                RunAnywhere.initialize(
                    apiKey = "demo-api-key",
                    baseURL = "https://api.runanywhere.ai",
                    environment = com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT
                )

                // Subscribe to model lifecycle changes
                subscribeToModelLifecycle()

                // Update whisper model display name
                updateWhisperModelName()

                // Start observing SDK events
                observeSDKEvents()

                _currentStatus.value = "Ready (FluidAudio)"
                _isInitialized.value = true

            } catch (e: Exception) {
                _errorMessage.value = "Failed to initialize: ${e.message}"
                _currentStatus.value = "Error"
            }
        }
    }

    /**
     * Subscribe to SDK's model lifecycle tracker for STT model state updates
     * Matches iOS subscribeToModelLifecycle()
     */
    private fun subscribeToModelLifecycle() {
        viewModelScope.launch {
            // TODO: Observe changes to STT model via the SDK's lifecycle tracker
            // Matches iOS: ModelLifecycleTracker.shared.$modelsByModality
            //     .receive(on: DispatchQueue.main)
            //     .sink { modelsByModality in ... }

            // For now, simulate initial state
            _sttModelState.value = ModelLoadState.NOT_LOADED
        }
    }

    private fun updateWhisperModelName() {
        _whisperModel.value = when (whisperModelName) {
            "whisper-base" -> "Whisper Base"
            "whisper-small" -> "Whisper Small"
            "whisper-medium" -> "Whisper Medium"
            "whisper-large" -> "Whisper Large"
            "whisper-large-v3" -> "Whisper Large v3"
            else -> whisperModelName.replace("-", " ")
                .replaceFirstChar { it.uppercase() }
        }
    }

    // MARK: - Transcription Control

    /**
     * Start real-time transcription
     * Matches iOS startTranscription()
     */
    fun startTranscription() {
        if (_isTranscribing.value) {
            return
        }

        viewModelScope.launch {
            try {
                // TODO: Create modular pipeline config matching iOS
                // val config = ModularPipelineConfig.transcriptionWithVAD(
                //     sttModel = whisperModelName,
                //     vadThreshold = 0.01f
                // )

                // TODO: Create pipeline with optional diarization
                // if (_enableSpeakerDiarization.value) {
                //     voicePipeline = FluidAudioIntegration.createVoicePipelineWithDiarization(config)
                // } else {
                //     voicePipeline = RunAnywhere.createVoicePipeline(config)
                // }

                // TODO: Initialize components
                // for (event in pipeline.initializeComponents()) { ... }

                // TODO: Start audio capture and process through pipeline
                // val audioStream = audioCapture.startContinuousCapture()
                // pipelineTask = launch { pipeline.process(audioStream) }

                _isTranscribing.value = true
                _currentStatus.value = "Listening..."
                _errorMessage.value = null
                _partialTranscript.value = ""

            } catch (e: Exception) {
                _errorMessage.value = "Failed to start transcription: ${e.message}"
                _currentStatus.value = "Error"
            }
        }
    }

    /**
     * Stop transcription
     * Matches iOS stopTranscription()
     */
    fun stopTranscription() {
        if (!_isTranscribing.value) {
            return
        }

        viewModelScope.launch {
            try {
                // TODO: Cancel pipeline task
                // pipelineTask?.cancel()

                // TODO: Stop audio capture
                // audioCapture.stopContinuousCapture()

                _isTranscribing.value = false
                _currentStatus.value = "Ready to transcribe"

                // Add final partial transcript if exists
                if (_partialTranscript.value.isNotEmpty()) {
                    val segment = TranscriptSegment(
                        text = _partialTranscript.value,
                        isFinal = true,
                        speakerId = _currentSpeaker.value?.id,
                        speakerName = _currentSpeaker.value?.name
                    )
                    _finalTranscripts.value = _finalTranscripts.value + segment
                    _partialTranscript.value = ""
                }

            } catch (e: Exception) {
                _errorMessage.value = "Failed to stop transcription: ${e.message}"
            }
        }
    }

    /**
     * Clear all transcripts
     * Matches iOS clearTranscripts()
     */
    fun clearTranscripts() {
        _finalTranscripts.value = emptyList()
        _partialTranscript.value = ""
        _transcriptionText.value = ""
    }

    /**
     * Export transcripts as text
     * Matches iOS exportTranscripts()
     */
    fun exportTranscripts(): String {
        val dateFormatter = SimpleDateFormat("MM/dd/yy h:mm:ss a", Locale.getDefault())
        val now = Date()

        val builder = StringBuilder()
        builder.appendLine("Transcription Export")
        builder.appendLine("Date: ${dateFormatter.format(now)}")
        builder.appendLine("Model: ${_whisperModel.value}")
        builder.appendLine("---")
        builder.appendLine()

        for (segment in _finalTranscripts.value) {
            val timestamp = Date(segment.timestamp)
            builder.appendLine("[${dateFormatter.format(timestamp)}]")
            if (segment.speakerName != null) {
                builder.appendLine("Speaker: ${segment.speakerName}")
            }
            builder.appendLine(segment.text)
            builder.appendLine()
        }

        if (_partialTranscript.value.isNotEmpty()) {
            builder.appendLine("[Current]")
            builder.appendLine(_partialTranscript.value)
        }

        return builder.toString()
    }

    /**
     * Copy all transcripts to clipboard
     * Matches iOS copyToClipboard()
     */
    fun copyToClipboard() {
        val fullText = _finalTranscripts.value.joinToString(" ") { it.text }
        val textToCopy = if (fullText.isEmpty()) _partialTranscript.value else fullText

        val clipboard = getApplication<Application>()
            .getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Transcription", textToCopy)
        clipboard.setPrimaryClip(clip)
    }

    /**
     * Toggle speaker diarization
     */
    fun toggleSpeakerDiarization() {
        _enableSpeakerDiarization.value = !_enableSpeakerDiarization.value
    }

    /**
     * Clear error message
     */
    fun clearError() {
        _errorMessage.value = null
    }

    // MARK: - SDK Event Observation

    private fun observeSDKEvents() {
        viewModelScope.launch {
            // Observe voice events from EventBus
            EventBus.voiceEvents.collect { event ->
                handleVoiceEvent(event)
            }
        }
    }

    private fun handleVoiceEvent(event: com.runanywhere.sdk.events.SDKVoiceEvent) {
        when (event) {
            is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionStarted -> {
                _isTranscribing.value = true
                _currentStatus.value = "Listening..."
                _partialTranscript.value = ""
            }

            is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionPartial -> {
                _partialTranscript.value = event.text
            }

            is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionFinal -> {
                if (event.text.isNotBlank()) {
                    val segment = TranscriptSegment(
                        text = event.text,
                        isFinal = true,
                        speakerId = _currentSpeaker.value?.id,
                        speakerName = _currentSpeaker.value?.name
                    )
                    _finalTranscripts.value = _finalTranscripts.value + segment
                    _partialTranscript.value = ""
                    _transcriptionText.value = _finalTranscripts.value.joinToString(" ") { it.text }
                }
            }

            is com.runanywhere.sdk.events.SDKVoiceEvent.PipelineError -> {
                _errorMessage.value = event.error.message ?: "Unknown error"
                _currentStatus.value = "Error"
                _isTranscribing.value = false
            }

            else -> {
                // Handle other events as needed
            }
        }
    }
}
