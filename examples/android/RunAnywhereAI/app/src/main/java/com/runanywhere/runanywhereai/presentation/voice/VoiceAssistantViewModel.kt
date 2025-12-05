package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.SessionState
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.audio.AudioCaptureOptions
import com.runanywhere.sdk.audio.VoiceAudioChunk
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.events.ModularPipelineEvent
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleTracker
import com.runanywhere.sdk.models.lifecycle.Modality
import com.runanywhere.sdk.public.ModularPipelineConfig
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.VoiceLLMConfig
import com.runanywhere.sdk.public.VoiceSTTConfig
import com.runanywhere.sdk.public.VoiceTTSConfig
import com.runanywhere.sdk.public.createVoicePipeline
import com.runanywhere.sdk.voice.ModularVoicePipeline
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

private const val TAG = "VoiceAssistantVM"

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
 * Uses RunAnywhere SDK ModularVoicePipeline for STT → LLM → TTS flow
 */
class VoiceAssistantViewModel(
    application: Application
) : AndroidViewModel(application) {

    private val context: Context = application.applicationContext

    // Pipeline state
    private var voicePipeline: ModularVoicePipeline? = null
    private var pipelineJob: Job? = null
    private var lifecycleJob: Job? = null

    // Audio capture
    private val audioCapture: AudioCaptureService by lazy {
        AudioCaptureService(context, AudioCaptureOptions.SPEECH_RECOGNITION)
    }

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
        // Subscribe to SDK's ModelLifecycleTracker for real-time model state updates
        // iOS equivalent: subscribeToModelLifecycle() in VoiceAssistantViewModel
        subscribeToModelLifecycle()
    }

    /**
     * Subscribe to SDK's model lifecycle tracker for real-time model state updates
     * iOS equivalent: subscribeToModelLifecycle() in VoiceAssistantViewModel.swift
     */
    private fun subscribeToModelLifecycle() {
        lifecycleJob?.cancel()
        lifecycleJob = viewModelScope.launch {
            // Observe changes to loaded models via the SDK's lifecycle tracker
            ModelLifecycleTracker.modelsByModality.collect { modelsByModality ->
                Log.d(TAG, "Model lifecycle update: ${modelsByModality.keys}")

                // Update STT model state
                val sttState = modelsByModality[Modality.STT]
                if (sttState != null) {
                    val loadState = when {
                        sttState.state.isLoaded -> ModelLoadState.LOADED
                        sttState.state.isLoading -> ModelLoadState.LOADING
                        sttState.state.isError -> ModelLoadState.ERROR
                        else -> ModelLoadState.NOT_LOADED
                    }
                    _uiState.update {
                        it.copy(
                            sttLoadState = loadState,
                            sttModel = if (sttState.state.isLoaded) {
                                SelectedModel(sttState.framework.name, sttState.modelName, sttState.modelId)
                            } else it.sttModel,
                            whisperModel = if (sttState.state.isLoaded) sttState.modelName else it.whisperModel
                        )
                    }
                    if (sttState.state.isLoaded) {
                        Log.i(TAG, "✅ STT model loaded: ${sttState.modelName}")
                    }
                } else {
                    _uiState.update { it.copy(sttLoadState = ModelLoadState.NOT_LOADED) }
                }

                // Update LLM model state
                val llmState = modelsByModality[Modality.LLM]
                if (llmState != null) {
                    val loadState = when {
                        llmState.state.isLoaded -> ModelLoadState.LOADED
                        llmState.state.isLoading -> ModelLoadState.LOADING
                        llmState.state.isError -> ModelLoadState.ERROR
                        else -> ModelLoadState.NOT_LOADED
                    }
                    _uiState.update {
                        it.copy(
                            llmLoadState = loadState,
                            llmModel = if (llmState.state.isLoaded) {
                                SelectedModel(llmState.framework.name, llmState.modelName, llmState.modelId)
                            } else it.llmModel,
                            currentLLMModel = if (llmState.state.isLoaded) llmState.modelName else it.currentLLMModel
                        )
                    }
                    if (llmState.state.isLoaded) {
                        Log.i(TAG, "✅ LLM model loaded: ${llmState.modelName}")
                    }
                } else {
                    _uiState.update { it.copy(llmLoadState = ModelLoadState.NOT_LOADED) }
                }

                // Update TTS model state
                val ttsState = modelsByModality[Modality.TTS]
                if (ttsState != null) {
                    val loadState = when {
                        ttsState.state.isLoaded -> ModelLoadState.LOADED
                        ttsState.state.isLoading -> ModelLoadState.LOADING
                        ttsState.state.isError -> ModelLoadState.ERROR
                        else -> ModelLoadState.NOT_LOADED
                    }
                    _uiState.update {
                        it.copy(
                            ttsLoadState = loadState,
                            ttsModel = if (ttsState.state.isLoaded) {
                                SelectedModel(ttsState.framework.name, ttsState.modelName, ttsState.modelId)
                            } else it.ttsModel,
                            ttsVoice = if (ttsState.state.isLoaded) ttsState.modelName else it.ttsVoice
                        )
                    }
                    if (ttsState.state.isLoaded) {
                        Log.i(TAG, "✅ TTS model loaded: ${ttsState.modelName}")
                    }
                } else {
                    _uiState.update { it.copy(ttsLoadState = ModelLoadState.NOT_LOADED) }
                }

                // Log overall state
                val uiStateValue = _uiState.value
                Log.i(TAG, "📊 Voice pipeline state - STT: ${uiStateValue.sttLoadState.isLoaded}, LLM: ${uiStateValue.llmLoadState.isLoaded}, TTS: ${uiStateValue.ttsLoadState.isLoaded}")
            }
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
     * iOS equivalent: startConversation() in VoiceAssistantViewModel.swift
     */
    fun startSession() {
        viewModelScope.launch {
            try {
                Log.i(TAG, "Starting conversation with modular pipeline...")

                _uiState.update {
                    it.copy(
                        sessionState = SessionState.CONNECTING,
                        errorMessage = null,
                        currentTranscript = "",
                        assistantResponse = ""
                    )
                }

                // Check if all models are loaded
                val uiStateValue = _uiState.value
                if (!uiStateValue.allModelsLoaded) {
                    Log.w(TAG, "Cannot start: Not all models loaded")
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Please load all required models (STT, LLM, TTS) before starting"
                        )
                    }
                    return@launch
                }

                // Check microphone permission
                if (!audioCapture.hasRecordPermission()) {
                    Log.e(TAG, "Microphone permission not granted")
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Microphone permission required"
                        )
                    }
                    return@launch
                }

                // Get model IDs from lifecycle tracker
                val sttModelId = ModelLifecycleTracker.loadedModel(Modality.STT)?.modelId
                val llmModelId = ModelLifecycleTracker.loadedModel(Modality.LLM)?.modelId
                val ttsModelId = ModelLifecycleTracker.loadedModel(Modality.TTS)?.modelId ?: "system"

                if (sttModelId == null) {
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "No STT model loaded"
                        )
                    }
                    return@launch
                }

                if (llmModelId == null) {
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "No LLM model loaded"
                        )
                    }
                    return@launch
                }

                Log.i(TAG, "Starting voice pipeline with STT: $sttModelId, LLM: $llmModelId, TTS: $ttsModelId")

                // Create pipeline configuration
                val config = ModularPipelineConfig.create(
                    components = listOf(
                        com.runanywhere.sdk.public.PipelineComponent.STT,
                        com.runanywhere.sdk.public.PipelineComponent.LLM,
                        com.runanywhere.sdk.public.PipelineComponent.TTS
                    ),
                    stt = VoiceSTTConfig(modelId = sttModelId, language = "en"),
                    llm = VoiceLLMConfig(
                        modelId = llmModelId,
                        systemPrompt = "You are a helpful voice assistant. Keep responses concise and conversational.",
                        maxTokens = 100
                    ),
                    tts = VoiceTTSConfig(voice = ttsModelId)
                )

                // Create the voice pipeline
                voicePipeline = RunAnywhere.createVoicePipeline(config)
                val pipeline = voicePipeline ?: run {
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.ERROR,
                            errorMessage = "Failed to create voice pipeline"
                        )
                    }
                    return@launch
                }

                // Initialize components
                pipeline.initializeComponents().collect { event ->
                    handleInitializationEvent(event)
                }

                // Start audio capture and get audio stream as Flow<VoiceAudioChunk>
                // Note: We need a Flow<VoiceAudioChunk> for the pipeline
                val audioFlow = audioCapture.startCaptureChunks()

                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isListening = true
                    )
                }

                Log.i(TAG, "Conversation pipeline started, listening...")

                // Process audio through pipeline
                pipelineJob = viewModelScope.launch {
                    try {
                        pipeline.process(audioFlow).collect { event ->
                            handlePipelineEvent(event)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Pipeline error", e)
                        _uiState.update {
                            it.copy(
                                sessionState = SessionState.ERROR,
                                errorMessage = "Pipeline error: ${e.message}",
                                isListening = false
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
                        isListening = false
                    )
                }
            }
        }
    }

    /**
     * Handle initialization events from the pipeline
     * iOS equivalent: handleInitializationEvent() in VoiceAssistantViewModel.swift
     */
    private fun handleInitializationEvent(event: ModularPipelineEvent) {
        when (event) {
            is ModularPipelineEvent.componentInitializing -> {
                Log.i(TAG, "Initializing component: ${event.componentName}")
                _uiState.update { it.copy(errorMessage = "Initializing ${event.componentName}...") }
            }
            is ModularPipelineEvent.componentInitialized -> {
                Log.i(TAG, "Component initialized: ${event.componentName}")
            }
            is ModularPipelineEvent.componentInitializationFailed -> {
                Log.e(TAG, "Component initialization failed: ${event.componentName} - ${event.error}")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.ERROR,
                        errorMessage = "Failed to initialize ${event.componentName}: ${event.error.message}"
                    )
                }
            }
            ModularPipelineEvent.allComponentsInitialized -> {
                Log.i(TAG, "All components initialized")
                _uiState.update { it.copy(errorMessage = null) }
            }
            else -> {}
        }
    }

    /**
     * Handle events from the voice pipeline
     * iOS equivalent: handlePipelineEvent() in VoiceAssistantViewModel.swift
     */
    private fun handlePipelineEvent(event: ModularPipelineEvent) {
        when (event) {
            // VAD Audio Level - iOS Reference: case .vadAudioLevel(let level):
            is ModularPipelineEvent.vadAudioLevel -> {
                Log.d(TAG, "Audio level: ${event.level}")
                _uiState.update { it.copy(audioLevel = event.level) }
            }
            ModularPipelineEvent.vadSpeechStart -> {
                Log.i(TAG, "Speech started")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isSpeechDetected = true,
                        isListening = true
                    )
                }
            }
            ModularPipelineEvent.vadSpeechEnd -> {
                Log.i(TAG, "Speech ended")
                _uiState.update { it.copy(isSpeechDetected = false) }
            }
            // TODO: Audio Control Events - not yet implemented in Kotlin SDK
            // iOS Reference: case .audioControlPauseRecording / .audioControlResumeRecording
            // When SDK adds these events, add handlers to pause/resume microphone during TTS
            is ModularPipelineEvent.sttPartialTranscript -> {
                Log.d(TAG, "Partial transcript: ${event.partial}")
                _uiState.update { it.copy(currentTranscript = event.partial) }
            }
            is ModularPipelineEvent.sttFinalTranscript -> {
                Log.i(TAG, "Final transcript: ${event.transcript}")
                _uiState.update {
                    it.copy(
                        currentTranscript = event.transcript,
                        sessionState = SessionState.PROCESSING
                    )
                }
            }
            ModularPipelineEvent.llmThinking -> {
                Log.d(TAG, "LLM thinking...")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.PROCESSING,
                        assistantResponse = ""
                    )
                }
            }
            is ModularPipelineEvent.llmPartialResponse -> {
                _uiState.update { it.copy(assistantResponse = event.text) }
            }
            is ModularPipelineEvent.llmFinalResponse -> {
                Log.i(TAG, "LLM response: ${event.text.take(50)}...")
                _uiState.update { it.copy(assistantResponse = event.text) }
            }
            ModularPipelineEvent.ttsStarted -> {
                Log.d(TAG, "TTS started")
                // Pause listening while speaking to avoid feedback
                _uiState.update {
                    it.copy(
                        isListening = false,
                        audioLevel = 0f
                    )
                }
            }
            ModularPipelineEvent.ttsCompleted -> {
                Log.d(TAG, "TTS completed")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        isListening = true,
                        currentTranscript = "" // Clear for next interaction
                    )
                }
            }
            is ModularPipelineEvent.pipelineError -> {
                Log.e(TAG, "Pipeline error: ${event.error}")
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.ERROR,
                        errorMessage = event.error.message,
                        isListening = false
                    )
                }
            }
            ModularPipelineEvent.pipelineStarted -> {
                Log.i(TAG, "Pipeline started")
            }
            ModularPipelineEvent.pipelineCompleted -> {
                Log.i(TAG, "Pipeline completed")
            }
            else -> {}
        }
    }

    /**
     * Stop conversation
     * iOS equivalent: stopConversation() in VoiceAssistantViewModel.swift
     */
    fun stopSession() {
        viewModelScope.launch {
            Log.i(TAG, "Stopping conversation...")

            // Cancel pipeline task
            pipelineJob?.cancel()
            pipelineJob = null

            // Stop audio capture
            audioCapture.stopCapture()

            // Clean up pipeline
            try {
                voicePipeline?.cleanup()
            } catch (e: Exception) {
                Log.e(TAG, "Error during pipeline cleanup", e)
            }
            voicePipeline = null

            // Reset UI state
            _uiState.update {
                it.copy(
                    sessionState = SessionState.DISCONNECTED,
                    isListening = false,
                    isSpeechDetected = false,
                    audioLevel = 0f
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
                assistantResponse = ""
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        lifecycleJob?.cancel()
        pipelineJob?.cancel()
        voicePipeline = null
        audioCapture.release()
    }
}
