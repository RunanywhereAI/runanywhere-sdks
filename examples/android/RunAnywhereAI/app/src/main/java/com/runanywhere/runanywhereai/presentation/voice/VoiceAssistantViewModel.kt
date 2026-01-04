package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.SessionState
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
import com.runanywhere.sdk.public.extensions.startVoiceSession
import com.runanywhere.sdk.public.extensions.stopVoiceSession
import com.runanywhere.sdk.public.extensions.voiceAgentComponentStates
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
    // Voice session flow
    private var voiceSessionFlow: Flow<VoiceSessionEvent>? = null

    // Jobs for coroutine management
    private var pipelineJob: Job? = null
    private var eventSubscriptionJob: Job? = null

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
     */
    private suspend fun syncModelStates() {
        try {
            val states = RunAnywhere.voiceAgentComponentStates()

            // Extract model IDs with explicit casting to avoid smart cast issues
            val sttModelId = (states.stt as? ComponentLoadState.Loaded)?.loadedModelId
            val llmModelId = (states.llm as? ComponentLoadState.Loaded)?.loadedModelId
            val ttsModelId = (states.tts as? ComponentLoadState.Loaded)?.loadedModelId

            _uiState.update {
                it.copy(
                    sttLoadState = ModelLoadState.fromSDK(states.stt),
                    llmLoadState = ModelLoadState.fromSDK(states.llm),
                    ttsLoadState = ModelLoadState.fromSDK(states.tts),
                    sttModel =
                        sttModelId?.let { id ->
                            SelectedModel("whisper", id, id)
                        },
                    llmModel =
                        llmModelId?.let { id ->
                            SelectedModel("llamacpp", id, id)
                        },
                    ttsModel =
                        ttsModelId?.let { id ->
                            SelectedModel("tts", id, id)
                        },
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
     * Uses the new VoiceSession API which handles:
     * - Audio capture internally
     * - Real-time speech detection (VAD)
     * - Automatic STT → LLM → TTS pipeline when speech ends
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

                // Start voice session with default config
                // VoiceSession handles audio capture, VAD, and pipeline internally
                val sessionFlow = RunAnywhere.startVoiceSession(VoiceSessionConfig.DEFAULT)
                voiceSessionFlow = sessionFlow

                Log.i(TAG, "Voice session started, listening...")

                // Consume voice session events
                pipelineJob =
                    viewModelScope.launch {
                        try {
                            sessionFlow.collect { event ->
                                handleVoiceSessionEvent(event)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Session error", e)
                            _uiState.update {
                                it.copy(
                                    sessionState = SessionState.ERROR,
                                    errorMessage = "Session error: ${e.message}",
                                    isListening = false,
                                )
                            }
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
     * Stop conversation
     * iOS Reference: stopConversation() in VoiceAgentViewModel.swift
     */
    fun stopSession() {
        viewModelScope.launch {
            Log.i(TAG, "Stopping conversation...")

            // Cancel pipeline job
            pipelineJob?.cancel()
            pipelineJob = null

            // Stop voice session (handles audio capture cleanup internally)
            RunAnywhere.stopVoiceSession()
            voiceSessionFlow = null

            // Reset UI state
            _uiState.update {
                it.copy(
                    sessionState = SessionState.DISCONNECTED,
                    isListening = false,
                    isSpeechDetected = false,
                    audioLevel = 0f,
                )
            }

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
     */
    fun setSTTModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                sttModel = SelectedModel(framework, name, modelId),
                sttLoadState = ModelLoadState.NOT_LOADED,
            )
        }
        Log.i(TAG, "STT model selected: $name ($modelId)")
    }

    /**
     * Set the LLM model for the voice pipeline
     */
    fun setLLMModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                llmModel = SelectedModel(framework, name, modelId),
                llmLoadState = ModelLoadState.NOT_LOADED,
            )
        }
        Log.i(TAG, "LLM model selected: $name ($modelId)")
    }

    /**
     * Set the TTS model for the voice pipeline
     */
    fun setTTSModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                ttsModel = SelectedModel(framework, name, modelId),
                ttsLoadState = ModelLoadState.NOT_LOADED,
                ttsVoice = modelId,
            )
        }
        Log.i(TAG, "TTS model selected: $name ($modelId)")
    }

    override fun onCleared() {
        super.onCleared()
        eventSubscriptionJob?.cancel()
        pipelineJob?.cancel()
        viewModelScope.launch {
            RunAnywhere.stopVoiceSession()
        }
    }
}
