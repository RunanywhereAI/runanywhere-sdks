package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.SessionState
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.LLMEvent
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.events.SDKEvent
import com.runanywhere.sdk.public.events.STTEvent
import com.runanywhere.sdk.public.events.TTSEvent
import com.runanywhere.sdk.public.extensions.VoiceAgent.ComponentLoadState
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import com.runanywhere.sdk.public.extensions.processVoice
import com.runanywhere.sdk.public.extensions.startVoiceSession
import com.runanywhere.sdk.public.extensions.stopVoiceSession
import com.runanywhere.sdk.public.extensions.voiceAgentComponentStates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

private const val TAG = "VoiceAssistantVM"

/**
 * Model Load State matching iOS ModelLoadState
 */
enum class ModelLoadState {
    NOT_LOADED,
    LOADING,
    LOADED,
    ERROR,
    ;

    val isLoaded: Boolean get() = this == LOADED
    val isLoading: Boolean get() = this == LOADING

    companion object {
        fun fromSDK(state: ComponentLoadState): ModelLoadState =
            when (state) {
                is ComponentLoadState.NotLoaded -> NOT_LOADED
                is ComponentLoadState.Loading -> LOADING
                is ComponentLoadState.Loaded -> LOADED
                is ComponentLoadState.Error -> ERROR
            }
    }
}

/**
 * Selected Model Info matching iOS pattern
 */
data class SelectedModel(
    val framework: String,
    val name: String,
    val modelId: String,
)

/**
 * Voice Assistant UI State matching iOS VoiceAgentViewModel
 */
data class VoiceUiState(
    val sessionState: SessionState = SessionState.DISCONNECTED,
    val isListening: Boolean = false,
    val isSpeechDetected: Boolean = false,
    val currentTranscript: String = "",
    val assistantResponse: String = "",
    val errorMessage: String? = null,
    val audioLevel: Float = 0f,
    val currentLLMModel: String = "No model loaded",
    val whisperModel: String = "Whisper Base",
    val ttsVoice: String = "System",
    // Model Selection State matching iOS
    val sttModel: SelectedModel? = null,
    val llmModel: SelectedModel? = null,
    val ttsModel: SelectedModel? = null,
    // Model Loading States matching iOS
    val sttLoadState: ModelLoadState = ModelLoadState.NOT_LOADED,
    val llmLoadState: ModelLoadState = ModelLoadState.NOT_LOADED,
    val ttsLoadState: ModelLoadState = ModelLoadState.NOT_LOADED,
) {
    /**
     * Check if all models are actually loaded in memory
     * iOS Reference: allModelsLoaded computed property
     */
    val allModelsLoaded: Boolean
        get() = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded
}

/**
 * ViewModel for Voice Assistant screen
 *
 * iOS Reference: VoiceAgentViewModel
 *
 * This ViewModel manages:
 * - Model selection for 3-model voice pipeline (STT, LLM, TTS)
 * - Model loading states from SDK events
 * - Voice conversation flow with audio capture
 * - Pipeline event handling
 *
 * Uses RunAnywhere SDK VoiceAgent capability for STT → LLM → TTS flow
 */
class VoiceAssistantViewModel(
    application: Application,
) : AndroidViewModel(application) {
    // Audio capture service for microphone input
    private var audioCaptureService: AudioCaptureService? = null

    // Audio buffer for accumulating audio data
    private val audioBuffer = ByteArrayOutputStream()

    // Voice session flow
    private var voiceSessionFlow: Flow<VoiceSessionEvent>? = null

    // Jobs for coroutine management
    private var pipelineJob: Job? = null
    private var eventSubscriptionJob: Job? = null
    private var audioRecordingJob: Job? = null
    private var silenceDetectionJob: Job? = null

    // Speech state tracking (matching iOS VoiceSessionHandle)
    @Volatile
    private var isSpeechActive = false
    private var lastSpeechTime: Long = 0L

    @Volatile
    private var isProcessingTurn = false

    // Audio playback (matching iOS AudioPlaybackManager)
    private var audioTrack: AudioTrack? = null
    private var audioPlaybackJob: Job? = null

    @Volatile
    private var isPlayingAudio = false

    // Voice session configuration (matching iOS VoiceSessionConfig)
    private val speechThreshold = 0.1f // Minimum audio level to detect speech (0.0 - 1.0)
    private val silenceDurationMs = 1500L // 1.5 seconds of silence before processing
    private val minAudioBytes = 16000 // ~0.5s at 16kHz, 16-bit
    private val ttsSampleRate = 22050 // TTS output sample rate (Piper default)

    private val _uiState = MutableStateFlow(VoiceUiState())
    val uiState: StateFlow<VoiceUiState> = _uiState.asStateFlow()

    // Convenience accessors for backward compatibility
    val sessionState: StateFlow<SessionState> =
        _uiState.map { it.sessionState }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            SessionState.DISCONNECTED,
        )
    val isListening: StateFlow<Boolean> =
        _uiState.map { it.isListening }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            false,
        )
    val error: StateFlow<String?> =
        _uiState.map { it.errorMessage }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            null,
        )
    val currentTranscript: StateFlow<String> =
        _uiState.map { it.currentTranscript }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            "",
        )
    val assistantResponse: StateFlow<String> =
        _uiState.map { it.assistantResponse }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            "",
        )
    val audioLevel: StateFlow<Float> =
        _uiState.map { it.audioLevel }.stateIn(
            viewModelScope,
            SharingStarted.Eagerly,
            0f,
        )

    /**
     * Initialize audio capture service
     * Must be called before starting a voice session
     */
    fun initialize(context: Context) {
        if (audioCaptureService == null) {
            audioCaptureService = AudioCaptureService(context)
            Log.i(TAG, "AudioCaptureService initialized")
        }
    }

    /**
     * Normalize audio level for visualization (0.0 to 1.0)
     * Matches STT implementation
     */
    private fun normalizeAudioLevel(rms: Float): Float {
        // RMS values typically range from 0 to ~0.3 for normal speech
        // Scale up for better visualization
        return (rms * 3.0f).coerceIn(0f, 1f)
    }

    /**
     * Check speech state based on audio level
     * iOS Reference: checkSpeechState(level: Float) in VoiceSessionHandle
     *
     * Detects when speech starts and updates lastSpeechTime
     */
    private fun checkSpeechState(level: Float) {
        if (level > speechThreshold) {
            // Speech detected
            if (!isSpeechActive) {
                Log.d(TAG, "🎙️ Speech started (level: $level)")
                isSpeechActive = true
                _uiState.update { it.copy(isSpeechDetected = true) }
            }
            // Update last speech time (keep tracking while speaking)
            lastSpeechTime = System.currentTimeMillis()
        }
        // Note: We don't reset isSpeechActive here - that's done in checkSilenceAndTriggerProcessing
    }

    /**
     * Check if silence duration has been exceeded and trigger processing
     * iOS Reference: Part of checkSpeechState in VoiceSessionHandle
     *
     * When silence exceeds silenceDuration after speech was active, process the audio
     */
    private fun checkSilenceAndTriggerProcessing() {
        if (!isSpeechActive || isProcessingTurn) return

        val currentLevel = _uiState.value.audioLevel
        if (currentLevel <= speechThreshold && lastSpeechTime > 0) {
            val silenceTime = System.currentTimeMillis() - lastSpeechTime
            if (silenceTime > silenceDurationMs) {
                Log.d(TAG, "🔇 Speech ended after ${silenceTime}ms of silence")
                isSpeechActive = false
                _uiState.update { it.copy(isSpeechDetected = false) }

                // Check if we have enough audio to process
                val audioSize = audioBuffer.size()
                if (audioSize >= minAudioBytes) {
                    Log.i(TAG, "🚀 Auto-triggering voice pipeline (audio: $audioSize bytes)")
                    processCurrentAudio()
                } else {
                    Log.d(TAG, "Audio too short to process ($audioSize bytes), resetting buffer")
                    audioBuffer.reset()
                }
            }
        }
    }

    /**
     * Process the current audio buffer through the STT → LLM → TTS pipeline
     * iOS Reference: processCurrentAudio() in VoiceSessionHandle
     *
     * IMPORTANT: The heavy processing (STT, LLM, TTS) runs on Dispatchers.Default
     * to avoid blocking the main thread and causing ANR.
     */
    private fun processCurrentAudio() {
        if (isProcessingTurn) {
            Log.d(TAG, "Already processing a turn, skipping")
            return
        }

        isProcessingTurn = true

        // Get the buffered audio and reset
        val audioData = audioBuffer.toByteArray()
        audioBuffer.reset()

        viewModelScope.launch {
            try {
                // Update state to processing (on main thread for UI)
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.PROCESSING,
                        isListening = false,
                        isSpeechDetected = false,
                        audioLevel = 0f,
                    )
                }

                // Stop audio capture during processing (matching iOS)
                audioRecordingJob?.cancel()
                silenceDetectionJob?.cancel()
                audioCaptureService?.stopCapture()

                Log.i(TAG, "🔄 Processing ${audioData.size} bytes through voice pipeline...")

                // Process audio through STT → LLM → TTS pipeline
                // Run on Default dispatcher to avoid blocking main thread (fixes ANR)
                val result =
                    withContext(Dispatchers.Default) {
                        RunAnywhere.processVoice(audioData)
                    }

                val transcription = result.transcription
                val response = result.response

                Log.i(
                    TAG,
                    "✅ Voice pipeline result - speechDetected: ${result.speechDetected}, " +
                        "transcription: ${transcription?.take(50)}, " +
                        "response: ${response?.take(50)}",
                )

                if (result.speechDetected && transcription != null) {
                    _uiState.update {
                        it.copy(
                            currentTranscript = transcription,
                            assistantResponse = response ?: "",
                        )
                    }

                    // Play synthesized audio if available (matching iOS autoPlayTTS)
                    val synthesizedAudio = result.synthesizedAudio
                    if (synthesizedAudio != null && synthesizedAudio.isNotEmpty()) {
                        Log.i(TAG, "🔊 Playing TTS response (${synthesizedAudio.size} bytes)")
                        playAudio(synthesizedAudio)
                        // Note: resumeListening() is called after playback completes
                    } else {
                        Log.d(TAG, "No synthesized audio, resuming listening immediately")
                        resumeListening()
                    }
                } else {
                    Log.i(TAG, "No speech detected in audio")
                    _uiState.update {
                        it.copy(
                            errorMessage = if (!result.speechDetected) "No speech detected" else null,
                        )
                    }
                    resumeListening()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing voice: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.ERROR,
                        errorMessage = "Processing error: ${e.message}",
                    )
                }
                isProcessingTurn = false
                // Resume listening even on error
                resumeListening()
            }
        }
    }

    /**
     * Resume listening after processing a turn
     * iOS Reference: Continuous mode resume in processCurrentAudio
     */
    private fun resumeListening() {
        val audioCapture = audioCaptureService ?: return

        // Reset state for next turn
        isProcessingTurn = false
        isSpeechActive = false
        lastSpeechTime = 0L
        audioBuffer.reset()

        _uiState.update {
            it.copy(
                sessionState = SessionState.LISTENING,
                isListening = true,
                audioLevel = 0f,
            )
        }

        Log.i(TAG, "🎙️ Resuming listening for next turn...")

        // Restart audio capture
        audioRecordingJob =
            viewModelScope.launch {
                try {
                    audioCapture.startCapture().collect { audioData ->
                        if (isProcessingTurn) return@collect

                        withContext(Dispatchers.IO) {
                            audioBuffer.write(audioData)
                        }

                        val rms = audioCapture.calculateRMS(audioData)
                        val normalizedLevel = normalizeAudioLevel(rms)
                        _uiState.update { it.copy(audioLevel = normalizedLevel) }

                        checkSpeechState(normalizedLevel)
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    Log.d(TAG, "Audio recording cancelled")
                } catch (e: Exception) {
                    Log.e(TAG, "Audio capture error on resume", e)
                }
            }

        // Restart silence detection
        silenceDetectionJob =
            viewModelScope.launch {
                while (_uiState.value.isListening && !isProcessingTurn) {
                    checkSilenceAndTriggerProcessing()
                    delay(50)
                }
            }
    }

    /**
     * Play synthesized TTS audio
     * iOS Reference: AudioPlaybackManager.play() in VoiceSessionHandle
     *
     * Plays WAV audio data through AudioTrack
     */
    private fun playAudio(audioData: ByteArray) {
        if (audioData.isEmpty()) {
            Log.w(TAG, "No audio data to play")
            resumeListening()
            return
        }

        Log.i(TAG, "🔊 Starting TTS playback (${audioData.size} bytes)")
        isPlayingAudio = true

        _uiState.update {
            it.copy(sessionState = SessionState.PROCESSING) // Show as "speaking"
        }

        audioPlaybackJob =
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                    val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                    // Skip WAV header (44 bytes) if present
                    val headerSize =
                        if (audioData.size > 44 &&
                            audioData[0] == 'R'.code.toByte() &&
                            audioData[1] == 'I'.code.toByte() &&
                            audioData[2] == 'F'.code.toByte() &&
                            audioData[3] == 'F'.code.toByte()
                        ) {
                            44
                        } else {
                            0
                        }

                    val pcmData = audioData.copyOfRange(headerSize, audioData.size)
                    Log.d(TAG, "PCM data size: ${pcmData.size} bytes (skipped $headerSize byte header)")

                    val bufferSize = AudioTrack.getMinBufferSize(ttsSampleRate, channelConfig, audioFormat)

                    audioTrack =
                        AudioTrack.Builder()
                            .setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_MEDIA)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build(),
                            )
                            .setAudioFormat(
                                AudioFormat.Builder()
                                    .setEncoding(audioFormat)
                                    .setSampleRate(ttsSampleRate)
                                    .setChannelMask(channelConfig)
                                    .build(),
                            )
                            .setBufferSizeInBytes(bufferSize.coerceAtLeast(pcmData.size))
                            .setTransferMode(AudioTrack.MODE_STATIC)
                            .build()

                    audioTrack?.write(pcmData, 0, pcmData.size)
                    audioTrack?.play()

                    Log.i(TAG, "🔊 TTS playback started")

                    // Calculate duration and wait for playback to complete
                    val durationMs = (pcmData.size.toDouble() / (ttsSampleRate * 2) * 1000).toLong()
                    Log.d(TAG, "Expected playback duration: ${durationMs}ms")

                    // Wait for playback to complete
                    var elapsed = 0L
                    while (isPlayingAudio && elapsed < durationMs && audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        delay(100)
                        elapsed += 100
                    }

                    Log.i(TAG, "🔊 TTS playback completed")

                    withContext(Dispatchers.Main) {
                        stopAudioPlayback()
                        resumeListening()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Audio playback error: ${e.message}", e)
                    withContext(Dispatchers.Main) {
                        stopAudioPlayback()
                        resumeListening()
                    }
                }
            }
    }

    /**
     * Stop audio playback
     * iOS Reference: AudioPlaybackManager.stop()
     */
    private fun stopAudioPlayback() {
        isPlayingAudio = false
        audioPlaybackJob?.cancel()
        audioPlaybackJob = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping AudioTrack: ${e.message}")
        }
        audioTrack = null

        Log.d(TAG, "Audio playback stopped")
    }

    init {
        // Subscribe to SDK events for model state tracking
        // iOS equivalent: subscribeToSDKEvents() in VoiceAgentViewModel
        subscribeToSDKEvents()
        // Sync initial model states
        viewModelScope.launch {
            syncModelStates()
        }
    }

    /**
     * Subscribe to SDK events for model state tracking
     * iOS Reference: subscribeToSDKEvents() in VoiceAgentViewModel.swift
     */
    private fun subscribeToSDKEvents() {
        eventSubscriptionJob?.cancel()
        eventSubscriptionJob =
            viewModelScope.launch {
                EventBus.events.collect { event ->
                    handleSDKEvent(event)
                }
            }
    }

    /**
     * Handle SDK events for model state updates
     * iOS Reference: handleSDKEvent(_:) in VoiceAgentViewModel.swift
     */
    private fun handleSDKEvent(event: SDKEvent) {
        when (event) {
            // Handle model events for LLM, STT, TTS
            is ModelEvent -> {
                when (event.eventType) {
                    ModelEvent.ModelEventType.LOADED -> {
                        when (event.category) {
                            EventCategory.LLM -> {
                                _uiState.update {
                                    it.copy(
                                        llmLoadState = ModelLoadState.LOADED,
                                        llmModel = SelectedModel("llamacpp", event.modelId, event.modelId),
                                        currentLLMModel = event.modelId,
                                    )
                                }
                                Log.i(TAG, "✅ LLM model loaded: ${event.modelId}")
                            }
                            EventCategory.STT -> {
                                _uiState.update {
                                    it.copy(
                                        sttLoadState = ModelLoadState.LOADED,
                                        sttModel = SelectedModel("whisper", event.modelId, event.modelId),
                                        whisperModel = event.modelId,
                                    )
                                }
                                Log.i(TAG, "✅ STT model loaded: ${event.modelId}")
                            }
                            EventCategory.TTS -> {
                                _uiState.update {
                                    it.copy(
                                        ttsLoadState = ModelLoadState.LOADED,
                                        ttsModel = SelectedModel("tts", event.modelId, event.modelId),
                                        ttsVoice = event.modelId,
                                    )
                                }
                                Log.i(TAG, "✅ TTS model loaded: ${event.modelId}")
                            }
                            else -> { /* Ignore other categories */ }
                        }
                    }
                    ModelEvent.ModelEventType.UNLOADED -> {
                        when (event.category) {
                            EventCategory.LLM -> {
                                _uiState.update {
                                    it.copy(
                                        llmLoadState = ModelLoadState.NOT_LOADED,
                                        llmModel = null,
                                    )
                                }
                            }
                            EventCategory.STT -> {
                                _uiState.update {
                                    it.copy(
                                        sttLoadState = ModelLoadState.NOT_LOADED,
                                        sttModel = null,
                                    )
                                }
                            }
                            EventCategory.TTS -> {
                                _uiState.update {
                                    it.copy(
                                        ttsLoadState = ModelLoadState.NOT_LOADED,
                                        ttsModel = null,
                                    )
                                }
                            }
                            else -> { /* Ignore other categories */ }
                        }
                    }
                    else -> { /* Ignore other model events */ }
                }
            }
            is LLMEvent -> {
                // LLM generation events (handled separately from model loading)
            }
            is STTEvent -> {
                // STT transcription events (handled separately from model loading)
            }
            is TTSEvent -> {
                // TTS synthesis events (handled separately from model loading)
            }
            else -> { /* Ignore other events */ }
        }
    }

    /**
     * Sync model states from SDK
     * iOS Reference: syncModelStates() in VoiceAgentViewModel.swift
     *
     * This method queries the SDK for actual component load states and updates the UI.
     * It preserves existing model selection info if present, only updating load states
     * and filling in model info from SDK if not already set.
     */
    private suspend fun syncModelStates() {
        try {
            val states = RunAnywhere.voiceAgentComponentStates()

            // Extract model IDs with explicit casting to avoid smart cast issues
            val sttModelId = (states.stt as? ComponentLoadState.Loaded)?.loadedModelId
            val llmModelId = (states.llm as? ComponentLoadState.Loaded)?.loadedModelId
            val ttsModelId = (states.tts as? ComponentLoadState.Loaded)?.loadedModelId

            _uiState.update { currentState ->
                currentState.copy(
                    // Always update load states from SDK - this is the source of truth
                    sttLoadState = ModelLoadState.fromSDK(states.stt),
                    llmLoadState = ModelLoadState.fromSDK(states.llm),
                    ttsLoadState = ModelLoadState.fromSDK(states.tts),
                    // Preserve existing model selection info if present,
                    // only fill in from SDK if no selection exists but model is loaded
                    sttModel =
                        currentState.sttModel ?: sttModelId?.let { id ->
                            SelectedModel("ONNX Runtime", id, id)
                        },
                    llmModel =
                        currentState.llmModel ?: llmModelId?.let { id ->
                            SelectedModel("llamacpp", id, id)
                        },
                    ttsModel =
                        currentState.ttsModel ?: ttsModelId?.let { id ->
                            SelectedModel("ONNX Runtime", id, id)
                        },
                    // Also update convenience fields for backward compatibility
                    whisperModel = sttModelId ?: currentState.whisperModel,
                    currentLLMModel = llmModelId ?: currentState.currentLLMModel,
                    ttsVoice = ttsModelId ?: currentState.ttsVoice,
                )
            }

            Log.i(TAG, "📊 Model states synced - STT: ${states.stt.isLoaded}, LLM: ${states.llm.isLoaded}, TTS: ${states.tts.isLoaded}")
        } catch (e: Exception) {
            Log.w(TAG, "Could not sync model states: ${e.message}")
        }
    }

    /**
     * Refresh component states from SDK
     * iOS Reference: refreshComponentStatesFromSDK() in VoiceAgentViewModel.swift
     */
    fun refreshComponentStatesFromSDK() {
        viewModelScope.launch {
            syncModelStates()
        }
    }

    /**
     * Start voice conversation session
     * iOS Reference: startConversation() in VoiceAgentViewModel.swift
     *
     * Now uses AudioCaptureService directly (like STT screen) for audio input.
     * Audio levels are updated in real-time for visualization.
     */
    fun startSession() {
        viewModelScope.launch {
            try {
                Log.i(TAG, "Starting conversation...")

                _uiState.update {
                    it.copy(
                        sessionState = SessionState.CONNECTING,
                        errorMessage = null,
                        currentTranscript = "",
                        assistantResponse = "",
                    )
                }

                // Check if all models are loaded
                val uiStateValue = _uiState.value
                if (!uiStateValue.allModelsLoaded) {
                    Log.w(TAG, "Cannot start: Not all models loaded")
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Please load all required models (STT, LLM, TTS) before starting",
                        )
                    }
                    return@launch
                }

                // Initialize audio capture if not already done
                val audioCapture = audioCaptureService
                if (audioCapture == null) {
                    Log.e(TAG, "AudioCaptureService not initialized")
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Audio capture not initialized. Please grant microphone permission.",
                        )
                    }
                    return@launch
                }

                // Check microphone permission
                if (!audioCapture.hasRecordPermission()) {
                    Log.e(TAG, "No microphone permission")
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Microphone permission required",
                        )
                    }
                    return@launch
                }

                // Start voice session (for SDK state tracking)
                val sessionFlow = RunAnywhere.startVoiceSession(VoiceSessionConfig.DEFAULT)
                voiceSessionFlow = sessionFlow

                // Consume voice session events in background
                pipelineJob =
                    viewModelScope.launch {
                        try {
                            sessionFlow.collect { event ->
                                handleVoiceSessionEvent(event)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Session event error", e)
                        }
                    }

                // Reset audio buffer
                audioBuffer.reset()

                // Update state to listening
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isListening = true,
                        audioLevel = 0f,
                    )
                }

                Log.i(TAG, "Voice session started, starting audio capture...")

                // Reset speech state tracking
                isSpeechActive = false
                lastSpeechTime = 0L
                isProcessingTurn = false

                // Start audio capture directly (like STT does)
                audioRecordingJob =
                    viewModelScope.launch {
                        try {
                            audioCapture.startCapture().collect { audioData ->
                                // Skip processing if we're currently processing a turn
                                if (isProcessingTurn) return@collect

                                // Append to buffer
                                withContext(Dispatchers.IO) {
                                    audioBuffer.write(audioData)
                                }

                                // Calculate and update audio level for visualization
                                val rms = audioCapture.calculateRMS(audioData)
                                val normalizedLevel = normalizeAudioLevel(rms)
                                _uiState.update { it.copy(audioLevel = normalizedLevel) }

                                // Speech state detection (matching iOS checkSpeechState)
                                checkSpeechState(normalizedLevel)
                            }
                        } catch (e: kotlinx.coroutines.CancellationException) {
                            Log.d(TAG, "Audio recording cancelled (expected when stopping)")
                        } catch (e: Exception) {
                            Log.e(TAG, "Audio capture error", e)
                            _uiState.update {
                                it.copy(
                                    errorMessage = "Audio capture error: ${e.message}",
                                )
                            }
                        }
                    }

                // Start silence detection monitoring (matching iOS startAudioLevelMonitoring)
                silenceDetectionJob =
                    viewModelScope.launch {
                        while (_uiState.value.isListening && !isProcessingTurn) {
                            checkSilenceAndTriggerProcessing()
                            delay(50) // Check every 50ms like iOS
                        }
                    }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start session", e)
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.ERROR,
                        errorMessage = "Failed to start: ${e.message}",
                        isListening = false,
                    )
                }
            }
        }
    }

    /**
     * Handle VoiceSession events (new API matching iOS)
     */
    private fun handleVoiceSessionEvent(event: VoiceSessionEvent) {
        when (event) {
            is VoiceSessionEvent.Started -> {
                Log.i(TAG, "Voice session started")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isListening = true,
                    )
                }
            }

            is VoiceSessionEvent.Listening -> {
                _uiState.update { it.copy(audioLevel = event.audioLevel) }
            }

            is VoiceSessionEvent.SpeechStarted -> {
                Log.d(TAG, "Speech detected")
                _uiState.update { it.copy(isSpeechDetected = true) }
            }

            is VoiceSessionEvent.Processing -> {
                Log.i(TAG, "Processing speech...")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.PROCESSING,
                        isSpeechDetected = false,
                    )
                }
            }

            is VoiceSessionEvent.Transcribed -> {
                Log.i(TAG, "Transcription: ${event.text}")
                _uiState.update { it.copy(currentTranscript = event.text) }
            }

            is VoiceSessionEvent.Responded -> {
                Log.i(TAG, "Response: ${event.text.take(50)}...")
                _uiState.update { it.copy(assistantResponse = event.text) }
            }

            is VoiceSessionEvent.Speaking -> {
                Log.d(TAG, "Playing TTS audio")
                _uiState.update { it.copy(sessionState = SessionState.PROCESSING) }
            }

            is VoiceSessionEvent.TurnCompleted -> {
                Log.i(TAG, "Turn completed")
                _uiState.update {
                    it.copy(
                        currentTranscript = event.transcript,
                        assistantResponse = event.response,
                        sessionState = SessionState.LISTENING,
                        isListening = true,
                    )
                }
            }

            is VoiceSessionEvent.Stopped -> {
                Log.i(TAG, "Voice session stopped")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.DISCONNECTED,
                        isListening = false,
                    )
                }
            }

            is VoiceSessionEvent.Error -> {
                Log.e(TAG, "Voice session error: ${event.message}")
                _uiState.update {
                    it.copy(
                        errorMessage = event.message,
                        // Don't change state to error - session can continue
                    )
                }
            }
        }
    }

    /**
     * Stop conversation completely
     * iOS Reference: stop() in VoiceSessionHandle
     *
     * Stops audio recording and voice session without processing remaining audio.
     * Use this for manual stop (user pressed stop button).
     */
    fun stopSession() {
        viewModelScope.launch {
            Log.i(TAG, "Stopping conversation...")

            // Reset speech state
            isProcessingTurn = false
            isSpeechActive = false
            lastSpeechTime = 0L

            // Stop audio playback if playing
            stopAudioPlayback()

            // Cancel all jobs
            audioRecordingJob?.cancel()
            audioRecordingJob = null
            silenceDetectionJob?.cancel()
            silenceDetectionJob = null
            pipelineJob?.cancel()
            pipelineJob = null

            // Stop audio capture service
            audioCaptureService?.stopCapture()

            // Get the buffered audio before resetting
            val audioData = audioBuffer.toByteArray()
            val audioSize = audioData.size
            audioBuffer.reset()

            Log.i(TAG, "Captured audio: $audioSize bytes")

            // Only process if we have meaningful audio data (at least 0.5 seconds at 16kHz, 16-bit)
            // 16000 samples/sec * 2 bytes/sample * 0.5 sec = 16000 bytes
            if (audioSize >= minAudioBytes) {
                // Update state to processing
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.PROCESSING,
                        isListening = false,
                        isSpeechDetected = false,
                        audioLevel = 0f,
                    )
                }

                try {
                    Log.i(TAG, "Processing audio through voice pipeline...")

                    // Process audio through STT → LLM → TTS pipeline
                    // Run on Default dispatcher to avoid blocking main thread (fixes ANR)
                    val result =
                        withContext(Dispatchers.Default) {
                            RunAnywhere.processVoice(audioData)
                        }

                    val transcription = result.transcription
                    val response = result.response

                    Log.i(
                        TAG,
                        "Voice pipeline result - speechDetected: ${result.speechDetected}, " +
                            "transcription: ${transcription?.take(50)}, " +
                            "response: ${response?.take(50)}",
                    )

                    if (result.speechDetected && transcription != null) {
                        _uiState.update {
                            it.copy(
                                currentTranscript = transcription,
                                assistantResponse = response ?: "",
                                sessionState = SessionState.DISCONNECTED,
                            )
                        }

                        // Play synthesized audio on manual stop as well
                        val synthesizedAudio = result.synthesizedAudio
                        if (synthesizedAudio != null && synthesizedAudio.isNotEmpty()) {
                            Log.i(TAG, "🔊 Playing TTS response (${synthesizedAudio.size} bytes)")
                            playAudio(synthesizedAudio)
                        }
                    } else {
                        Log.i(TAG, "No speech detected in audio")
                        _uiState.update {
                            it.copy(
                                sessionState = SessionState.DISCONNECTED,
                                errorMessage = if (!result.speechDetected) "No speech detected" else null,
                            )
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing voice: ${e.message}", e)
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Processing error: ${e.message}",
                        )
                    }
                }
            } else {
                Log.i(TAG, "Audio too short to process ($audioSize bytes)")
                // Reset UI state without processing
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.DISCONNECTED,
                        isListening = false,
                        isSpeechDetected = false,
                        audioLevel = 0f,
                        errorMessage = if (audioSize > 0) "Recording too short" else null,
                    )
                }
            }

            // Stop voice session
            RunAnywhere.stopVoiceSession()
            voiceSessionFlow = null

            Log.i(TAG, "Conversation stopped")
        }
    }

    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun clearConversation() {
        _uiState.update {
            it.copy(
                currentTranscript = "",
                assistantResponse = "",
            )
        }
    }

    /**
     * Set the STT model for the voice pipeline
     * iOS Reference: After selection, sync with SDK to get actual load state
     *
     * Note: The model is already loaded by ModelSelectionBottomSheet before this callback.
     * We sync with SDK to get the actual load state instead of resetting to NOT_LOADED.
     */
    fun setSTTModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                sttModel = SelectedModel(framework, name, modelId),
                whisperModel = modelId,
                // Don't reset sttLoadState - model may already be loaded by ModelSelectionBottomSheet
            )
        }
        Log.i(TAG, "STT model selected: $name ($modelId)")
        // Sync with SDK to get actual load state (model may already be loaded)
        viewModelScope.launch {
            syncModelStates()
        }
    }

    /**
     * Set the LLM model for the voice pipeline
     * iOS Reference: After selection, sync with SDK to get actual load state
     *
     * Note: The model is already loaded by ModelSelectionBottomSheet before this callback.
     * We sync with SDK to get the actual load state instead of resetting to NOT_LOADED.
     */
    fun setLLMModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                llmModel = SelectedModel(framework, name, modelId),
                currentLLMModel = modelId,
                // Don't reset llmLoadState - model may already be loaded by ModelSelectionBottomSheet
            )
        }
        Log.i(TAG, "LLM model selected: $name ($modelId)")
        // Sync with SDK to get actual load state (model may already be loaded)
        viewModelScope.launch {
            syncModelStates()
        }
    }

    /**
     * Set the TTS model for the voice pipeline
     * iOS Reference: After selection, sync with SDK to get actual load state
     *
     * Note: The model is already loaded by ModelSelectionBottomSheet before this callback.
     * We sync with SDK to get the actual load state instead of resetting to NOT_LOADED.
     */
    fun setTTSModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                ttsModel = SelectedModel(framework, name, modelId),
                ttsVoice = modelId,
                // Don't reset ttsLoadState - model may already be loaded by ModelSelectionBottomSheet
            )
        }
        Log.i(TAG, "TTS model selected: $name ($modelId)")
        // Sync with SDK to get actual load state (model may already be loaded)
        viewModelScope.launch {
            syncModelStates()
        }
    }

    override fun onCleared() {
        super.onCleared()
        eventSubscriptionJob?.cancel()
        pipelineJob?.cancel()
        audioRecordingJob?.cancel()
        silenceDetectionJob?.cancel()
        stopAudioPlayback()
        audioCaptureService?.release()
        audioCaptureService = null
        viewModelScope.launch {
            RunAnywhere.stopVoiceSession()
        }
    }
}
