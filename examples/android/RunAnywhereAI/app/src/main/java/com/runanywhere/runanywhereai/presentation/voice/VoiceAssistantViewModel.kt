package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.SessionState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * Model Load State
 * iOS Reference: ModelLoadState enum in ModelStatusComponents.swift
 */
enum class ModelLoadState {
    NOT_LOADED,
    LOADING,
    LOADED,
    ERROR;

    val isLoaded: Boolean get() = this == LOADED
    val isLoading: Boolean get() = this == LOADING
}

/**
 * Selected Model Info
 * iOS Reference: (framework: LLMFramework, name: String) tuple in VoiceAssistantViewModel.swift
 */
data class SelectedModel(
    val framework: String,
    val name: String,
    val modelId: String
)

/**
 * Voice Assistant UI State
 * iOS Reference: VoiceAssistantViewModel in VoiceAssistantView.swift
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

    // Model Selection State (for Voice Pipeline Setup)
    // iOS Reference: sttModel, llmModel, ttsModel in VoiceAssistantViewModel.swift
    val sttModel: SelectedModel? = null,
    val llmModel: SelectedModel? = null,
    val ttsModel: SelectedModel? = null,

    // Model Loading States (from SDK lifecycle tracker)
    // iOS Reference: sttModelState, llmModelState, ttsModelState
    val sttLoadState: ModelLoadState = ModelLoadState.NOT_LOADED,
    val llmLoadState: ModelLoadState = ModelLoadState.NOT_LOADED,
    val ttsLoadState: ModelLoadState = ModelLoadState.NOT_LOADED
) {
    /**
     * Check if all required models are selected for the voice pipeline
     * iOS Reference: allModelsReady computed property
     */
    val allModelsReady: Boolean
        get() = sttModel != null && llmModel != null && ttsModel != null

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
 * iOS Reference: VoiceAssistantViewModel in VoiceAssistantView.swift
 *
 * This ViewModel manages:
 * - Model selection for 3-model voice pipeline (STT, LLM, TTS)
 * - Model loading states from SDK lifecycle tracker
 * - Voice conversation flow with audio capture
 * - Pipeline event handling
 *
 * TODO: Integrate with RunAnywhere SDK ModularVoicePipeline when available
 * iOS equivalent: ModularVoicePipeline with VAD, STT, LLM, TTS components
 */
class VoiceAssistantViewModel(
    application: Application
) : AndroidViewModel(application) {

    private val context: Context = application.applicationContext
    private var pipelineJob: Job? = null

    private val _uiState = MutableStateFlow(VoiceUiState())
    val uiState: StateFlow<VoiceUiState> = _uiState.asStateFlow()

    // Convenience accessors for backward compatibility
    val sessionState: StateFlow<SessionState> = _uiState.map { it.sessionState }.stateIn(
        viewModelScope, SharingStarted.Eagerly, SessionState.DISCONNECTED
    )
    val isListening: StateFlow<Boolean> = _uiState.map { it.isListening }.stateIn(
        viewModelScope, SharingStarted.Eagerly, false
    )
    val error: StateFlow<String?> = _uiState.map { it.errorMessage }.stateIn(
        viewModelScope, SharingStarted.Eagerly, null
    )
    val currentTranscript: StateFlow<String> = _uiState.map { it.currentTranscript }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val assistantResponse: StateFlow<String> = _uiState.map { it.assistantResponse }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val audioLevel: StateFlow<Float> = _uiState.map { it.audioLevel }.stateIn(
        viewModelScope, SharingStarted.Eagerly, 0f
    )

    init {
        // TODO: Subscribe to SDK's ModelLifecycleTracker for real-time model state updates
        // iOS equivalent: subscribeToModelLifecycle() in VoiceAssistantViewModel
        subscribeToModelLifecycle()
    }

    /**
     * Subscribe to SDK's model lifecycle tracker for real-time model state updates
     *
     * TODO: Integrate with actual SDK ModelLifecycleTracker
     * iOS equivalent: subscribeToModelLifecycle() in VoiceAssistantViewModel.swift
     */
    private fun subscribeToModelLifecycle() {
        viewModelScope.launch {
            // TODO: Observe changes to loaded models via the SDK's lifecycle tracker
            // iOS equivalent:
            // ModelLifecycleTracker.shared.$modelsByModality
            //     .receive(on: DispatchQueue.main)
            //     .sink { modelsByModality in ... }
        }
    }

    /**
     * Set the STT model for voice pipeline
     *
     * TODO: Integrate with SDK model loading
     * iOS equivalent: setSTTModel(_ model: ModelInfo)
     */
    fun setSTTModel(framework: String, name: String, modelId: String) {
        viewModelScope.launch {
            val model = SelectedModel(framework, name, modelId)
            _uiState.update {
                it.copy(
                    sttModel = model,
                    whisperModel = name,
                    sttLoadState = ModelLoadState.LOADING
                )
            }

            // TODO: Load the model using SDK
            // iOS equivalent:
            // sttModel = (framework: model.preferredFramework ?? .whisperKit, name: model.name)
            // whisperModel = model.name

            // Mock loading for now
            delay(1500)

            _uiState.update { it.copy(sttLoadState = ModelLoadState.LOADED) }
        }
    }

    /**
     * Set the LLM model for voice pipeline
     *
     * TODO: Integrate with SDK model loading
     * iOS equivalent: setLLMModel(_ model: ModelInfo)
     */
    fun setLLMModel(framework: String, name: String, modelId: String) {
        viewModelScope.launch {
            val model = SelectedModel(framework, name, modelId)
            _uiState.update {
                it.copy(
                    llmModel = model,
                    currentLLMModel = name,
                    llmLoadState = ModelLoadState.LOADING
                )
            }

            // TODO: Load the model using SDK
            // iOS equivalent:
            // llmModel = (framework: model.preferredFramework ?? .llamaCpp, name: model.name)
            // currentLLMModel = model.name

            // Mock loading for now
            delay(2000)

            _uiState.update { it.copy(llmLoadState = ModelLoadState.LOADED) }
        }
    }

    /**
     * Set the TTS model for voice pipeline
     *
     * TODO: Integrate with SDK model loading
     * iOS equivalent: setTTSModel(_ model: ModelInfo)
     */
    fun setTTSModel(framework: String, name: String, modelId: String) {
        viewModelScope.launch {
            val model = SelectedModel(framework, name, modelId)
            _uiState.update {
                it.copy(
                    ttsModel = model,
                    ttsVoice = name,
                    ttsLoadState = ModelLoadState.LOADING
                )
            }

            // TODO: Load the model using SDK
            // iOS equivalent:
            // ttsModel = (framework: model.preferredFramework ?? .onnx, name: model.name)

            // Mock loading for now
            delay(1000)

            _uiState.update { it.copy(ttsLoadState = ModelLoadState.LOADED) }
        }
    }

    /**
     * Start real-time conversation using modular pipeline
     *
     * TODO: Integrate with RunAnywhere SDK ModularVoicePipeline
     * iOS equivalent: startConversation() in VoiceAssistantViewModel.swift
     */
    fun startSession() {
        viewModelScope.launch {
            try {
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.CONNECTING,
                        errorMessage = null,
                        currentTranscript = "",
                        assistantResponse = ""
                    )
                }

                // TODO: Create pipeline configuration
                // iOS equivalent:
                // let config = ModularPipelineConfig(
                //     components: [.vad, .stt, .llm, .tts],
                //     vad: VADConfig(energyThreshold: 0.005),
                //     stt: VoiceSTTConfig(modelId: whisperModelName),
                //     llm: VoiceLLMConfig(modelId: "default", ...),
                //     tts: VoiceTTSConfig(voice: "system")
                // )

                // TODO: Create the voice pipeline using SDK
                // iOS equivalent: voicePipeline = try await RunAnywhere.createVoicePipeline(config: config)

                // TODO: Initialize components
                // iOS equivalent:
                // for try await event in pipeline.initializeComponents() {
                //     handleInitializationEvent(event)
                // }

                // Mock initialization delay
                delay(1000)

                // TODO: Start audio capture
                // iOS equivalent: let audioStream = audioCapture.startContinuousCapture()

                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isListening = true
                    )
                }

                // TODO: Process audio through pipeline
                // iOS equivalent:
                // pipelineTask = Task {
                //     for try await event in voicePipeline!.process(audioStream: audioStream) {
                //         await handlePipelineEvent(event)
                //     }
                // }

                // Mock listening loop
                pipelineJob = viewModelScope.launch {
                    while (true) {
                        delay(100)
                        // Simulate audio level changes
                        val randomLevel = (Math.random() * 0.5f).toFloat()
                        _uiState.update { it.copy(audioLevel = randomLevel) }
                    }
                }

            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.ERROR,
                        errorMessage = "Failed to start: ${e.message}",
                        isListening = false
                    )
                }
            }
        }
    }

    /**
     * Stop conversation
     *
     * TODO: Integrate with SDK pipeline cleanup
     * iOS equivalent: stopConversation() in VoiceAssistantViewModel.swift
     */
    fun stopSession() {
        viewModelScope.launch {
            // TODO: Cancel pipeline task
            // iOS equivalent:
            // pipelineTask?.cancel()
            // pipelineTask = nil

            pipelineJob?.cancel()
            pipelineJob = null

            // TODO: Stop audio capture
            // iOS equivalent: audioCapture.stopContinuousCapture()

            // TODO: Clean up pipeline
            // iOS equivalent: voicePipeline = nil

            _uiState.update {
                it.copy(
                    sessionState = SessionState.DISCONNECTED,
                    isListening = false,
                    isSpeechDetected = false,
                    audioLevel = 0f
                )
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun clearConversation() {
        _uiState.update {
            it.copy(
                currentTranscript = "",
                assistantResponse = ""
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch {
            stopSession()
        }
    }
}
