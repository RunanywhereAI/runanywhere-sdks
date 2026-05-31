package com.runanywhere.runanywhereai.presentation.voice

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_LLM
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_STT
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_TTS
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.VoiceSessionError
import android.app.Application
import android.content.Context
import android.media.AudioTrack
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.SDKEvent
import com.runanywhere.sdk.public.extensions.VoiceAgent.errorMessageOrNull
import com.runanywhere.sdk.public.extensions.VoiceAgent.pipelineStateOrNull
import com.runanywhere.sdk.public.extensions.cleanupVoiceAgent
import com.runanywhere.sdk.public.extensions.getVoiceAgentComponentStates
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import com.runanywhere.sdk.public.types.RAVoiceEvent
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * Selected Model Info matching iOS pattern
 */
data class SelectedModel(
    val framework: String,
    val name: String,
    val modelId: String,
)

val ComponentLifecycleState.isLoaded: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY

val ComponentLifecycleState.isLoading: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_LOADING

/**
 * Voice Assistant UI State matching iOS VoiceAgentViewModel
 */
data class VoiceUiState(
    val pipelineState: PipelineState = PipelineState.PIPELINE_STATE_STOPPED,
    val currentTranscript: String = "",
    val assistantResponse: String = "",
    val errorMessage: String? = null,
    val audioLevel: Float = 0f,
    // Model Selection State matching iOS
    val sttModel: SelectedModel? = null,
    val llmModel: SelectedModel? = null,
    val ttsModel: SelectedModel? = null,
    // Model Loading States matching iOS
    val sttLoadState: ComponentLifecycleState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED,
    val llmLoadState: ComponentLifecycleState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED,
    val ttsLoadState: ComponentLifecycleState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED,
) {
    /**
     * Check if all models are actually loaded in memory
     * iOS Reference: allModelsLoaded computed property
     */
    val allModelsLoaded: Boolean
        get() = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded

    val isPipelineListening: Boolean
        get() = pipelineState == PipelineState.PIPELINE_STATE_LISTENING

    val isPipelineSpeaking: Boolean
        get() =
            pipelineState == PipelineState.PIPELINE_STATE_SPEAKING ||
                pipelineState == PipelineState.PIPELINE_STATE_PLAYING_TTS

    val isPipelineProcessing: Boolean
        get() =
            pipelineState == PipelineState.PIPELINE_STATE_THINKING ||
                pipelineState == PipelineState.PIPELINE_STATE_PROCESSING_SPEECH ||
                pipelineState == PipelineState.PIPELINE_STATE_GENERATING_RESPONSE

    val isInputActive: Boolean
        get() = isPipelineListening && audioLevel > 0.05f
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

    // Jobs for coroutine management
    private var pipelineJob: Job? = null
    private var eventSubscriptionJob: Job? = null
    private var audioRecordingJob: Job? = null

    // Audio playback (matching iOS AudioPlaybackManager)
    private var audioTrack: AudioTrack? = null
    private var audioPlaybackJob: Job? = null
    private var processingJob: Job? = null

    @Volatile
    private var isPlayingAudio = false

    private val _uiState = MutableStateFlow(VoiceUiState())
    val uiState: StateFlow<VoiceUiState> = _uiState.asStateFlow()

    /**
     * Initialize audio capture service
     * Must be called before starting a voice session
     */
    fun initialize(context: Context) {
        if (audioCaptureService == null) {
            audioCaptureService = AudioCaptureService(context)
            Timber.i("AudioCaptureService initialized")
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
     * Stop audio playback.
     * iOS Reference: AudioPlaybackManager.stop()
     *
     * TTS playback is owned by the C++ voice agent now (via `streamVoiceAgent`
     * `RAVoiceEvent.audio` frames). The local `AudioTrack` plumbing is kept as
     * a safety net for any in-flight audio session the C++ layer may have
     * delegated to the JVM in the future; today it is a no-op.
     */
    private fun stopAudioPlayback() {
        isPlayingAudio = false
        audioPlaybackJob?.cancel()
        audioPlaybackJob = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Timber.w("Error stopping AudioTrack: ${e.message}")
        }
        audioTrack = null

        Timber.d("Audio playback stopped")
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
        event.voice_pipeline?.let(::handleProtoEvent)

        val modelEvent = event.model ?: return
        when (modelEvent.kind) {
            ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED -> {
                when (event.category) {
                    EVENT_CATEGORY_LLM -> {
                        _uiState.update {
                            it.copy(
                                llmLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY,
                                llmModel = SelectedModel("llamacpp", modelEvent.model_id, modelEvent.model_id),
                            )
                        }
                        Timber.i("✅ LLM model loaded: ${modelEvent.model_id}")
                    }
                    EVENT_CATEGORY_STT -> {
                        _uiState.update {
                            it.copy(
                                sttLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY,
                                sttModel = SelectedModel("whisper", modelEvent.model_id, modelEvent.model_id),
                            )
                        }
                        Timber.i("✅ STT model loaded: ${modelEvent.model_id}")
                    }
                    EVENT_CATEGORY_TTS -> {
                        _uiState.update {
                            it.copy(
                                ttsLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY,
                                ttsModel = SelectedModel("tts", modelEvent.model_id, modelEvent.model_id),
                            )
                        }
                        Timber.i("✅ TTS model loaded: ${modelEvent.model_id}")
                    }
                    else -> { /* Ignore other categories */ }
                }
            }
            ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED -> {
                when (event.category) {
                    EVENT_CATEGORY_LLM -> {
                        _uiState.update {
                            it.copy(
                                llmLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                llmModel = null,
                            )
                        }
                    }
                    EVENT_CATEGORY_STT -> {
                        _uiState.update {
                            it.copy(
                                sttLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                sttModel = null,
                            )
                        }
                    }
                    EVENT_CATEGORY_TTS -> {
                        _uiState.update {
                            it.copy(
                                ttsLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
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
            val protoStates = RunAnywhere.getVoiceAgentComponentStates()

            // getVoiceAgentComponentStates() now returns VoiceAgentComponentStates (proto message).
            val sttState = protoStates.stt_state
            val llmState = protoStates.llm_state
            val ttsState = protoStates.tts_state

            val sttModelId = "stt".takeIf { sttState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY }
            val llmModelId = "llm".takeIf { llmState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY }
            val ttsModelId = "tts".takeIf { ttsState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY }

            _uiState.update { currentState ->
                currentState.copy(
                    sttLoadState = sttState,
                    llmLoadState = llmState,
                    ttsLoadState = ttsState,
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
                )
            }

            Timber.i(
                "Model states synced - STT: ${sttState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY}, " +
                    "LLM: ${llmState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY}, " +
                    "TTS: ${ttsState == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY}",
            )
        } catch (e: Exception) {
            Timber.w("Could not sync model states: ${e.message}")
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

    fun startSession() {
        viewModelScope.launch {
            try {
                Timber.i("Starting one-shot voice turn recording...")

                _uiState.update {
                    it.copy(
                        pipelineState = PipelineState.PIPELINE_STATE_IDLE,
                        errorMessage = null,
                        currentTranscript = "",
                        assistantResponse = "",
                    )
                }

                // Check if all models are loaded
                val uiStateValue = _uiState.value
                if (!uiStateValue.allModelsLoaded) {
                    Timber.w("Cannot start: Not all models loaded")
                    showSessionError(
                        VoiceSessionError(
                            code = ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
                            message = "Please load all required models (STT, LLM, TTS) before starting",
                            recoverable = true,
                        ),
                    )
                    return@launch
                }

                val audioCapture = audioCaptureService
                if (audioCapture == null) {
                    Timber.e("AudioCaptureService not initialized")
                    showSessionError(
                        VoiceSessionError(
                            code = ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
                            message = "Audio capture not initialized. Please grant microphone permission.",
                            recoverable = true,
                        ),
                    )
                    return@launch
                }

                if (!audioCapture.hasRecordPermission()) {
                    Timber.e("No microphone permission")
                    showSessionError(
                        VoiceSessionError(
                            code = ErrorCode.ERROR_CODE_MICROPHONE_PERMISSION_DENIED,
                            message = "Microphone permission required",
                            recoverable = true,
                        ),
                    )
                    return@launch
                }

                val agentFlow =
                    try {
                        RunAnywhere.streamVoiceAgent()
                    } catch (e: Exception) {
                        showSessionError(
                            VoiceSessionError(
                                code = ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
                                message = "Native voice-agent event stream unavailable: ${e.message}",
                                recoverable = false,
                            ),
                        )
                        return@launch
                    }
                pipelineJob =
                    viewModelScope.launch {
                        try {
                            agentFlow.collect(::handleProtoEvent)
                        } catch (e: Exception) {
                            Timber.e(e, "Voice agent event error")
                            showSessionError(
                                VoiceSessionError(
                                    code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                                    message = "Voice agent event stream error: ${e.message}",
                                    failed_component = "voice_agent",
                                    recoverable = false,
                                ),
                            )
                        }
                    }

                _uiState.update {
                    it.copy(
                        pipelineState = PipelineState.PIPELINE_STATE_LISTENING,
                        audioLevel = 0f,
                    )
                }

                Timber.i("Voice session started — events flow from streamVoiceAgent()")

                // Audio capture drives the UI-level visualization only. The
                // voice-agent C++ pipeline owns its own audio capture and
                // emits events via streamVoiceAgent() — mirroring the iOS
                // VoiceAgentViewModel that does not feed audio bytes back
                // into the SDK either.
                audioRecordingJob =
                    viewModelScope.launch {
                        try {
                            audioCapture.startCapture().collect { audioData ->
                                val rms = audioCapture.calculateRMS(audioData)
                                val normalizedLevel = normalizeAudioLevel(rms)
                                _uiState.update {
                                    it.copy(
                                        audioLevel = normalizedLevel,
                                    )
                                }
                            }
                        } catch (e: kotlinx.coroutines.CancellationException) {
                            Timber.d("Audio recording cancelled (expected when stopping)")
                        } catch (e: Exception) {
                            Timber.e(e, "Audio capture error")
                            _uiState.update {
                                it.copy(
                                    errorMessage = "Audio capture error: ${e.message}",
                                )
                            }
                        }
                    }
            } catch (e: Exception) {
                Timber.e(e, "Failed to start session")
                showSessionError(
                    VoiceSessionError(
                        code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                        message = "Failed to start: ${e.message}",
                        failed_component = "voice_agent",
                        recoverable = true,
                    ),
                )
            }
        }
    }

    private fun showSessionError(error: VoiceSessionError) {
        handleProtoEvent(RAVoiceEvent(session_error = error))
    }

    private fun handleProtoEvent(event: RAVoiceEvent) {
        val nextPipelineState = event.pipelineStateOrNull()
        val errorMessage = event.errorMessageOrNull()
        val assistantToken = event.assistant_token?.text

        _uiState.update { current ->
            current.copy(
                pipelineState = nextPipelineState ?: current.pipelineState,
                errorMessage = errorMessage ?: current.errorMessage,
                currentTranscript = event.user_said?.text ?: current.currentTranscript,
                assistantResponse =
                    when {
                        event.agent_response_started != null -> ""
                        assistantToken != null -> current.assistantResponse + assistantToken
                        else -> current.assistantResponse
                    },
                audioLevel = event.audio_level?.rms ?: current.audioLevel,
            )
        }

        if (errorMessage != null) {
            Timber.e("Voice agent error: $errorMessage")
        }
    }

    /**
     * Stop conversation completely.
     * iOS Reference: stopConversation() in VoiceAgentViewModel
     *
     * Cancels the streaming jobs and releases the voice agent. The C++
     * voice agent owns its audio pipeline, so there is no buffered audio
     * to flush — mirroring iOS, which also drops the buffer on stop.
     */
    fun stopSession() {
        viewModelScope.launch {
            Timber.i("Stopping conversation...")

            stopAudioPlayback()

            audioRecordingJob?.cancel()
            audioRecordingJob = null
            pipelineJob?.cancel()
            pipelineJob = null
            processingJob?.cancel()
            processingJob = null

            audioCaptureService?.stopCapture()

            _uiState.update {
                it.copy(
                    pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                    audioLevel = 0f,
                )
            }

            RunAnywhere.cleanupVoiceAgent()

            Timber.i("Conversation stopped")
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
                // Don't reset sttLoadState - model may already be loaded by ModelSelectionBottomSheet
            )
        }
        Timber.i("STT model selected: $name ($modelId)")
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
                // Don't reset llmLoadState - model may already be loaded by ModelSelectionBottomSheet
            )
        }
        Timber.i("LLM model selected: $name ($modelId)")
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
     * Mirrors iOS `VoiceAgentViewModel.setTTSModel` (`ttsModelState = .loaded`):
     * we optimistically mark the TTS load state as READY before syncing with the
     * SDK so the "Start Voice Assistant" button enables immediately when System
     * TTS is selected (System TTS has no model artifact, so `syncModelStates`
     * cannot derive READY from a `tts` slot).
     */
    fun setTTSModel(
        framework: String,
        name: String,
        modelId: String,
    ) {
        _uiState.update {
            it.copy(
                ttsModel = SelectedModel(framework, name, modelId),
                // iOS parity: optimistically mark TTS as READY so callers don't
                // need to wait on `syncModelStates` to enable Start.
                ttsLoadState = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY,
            )
        }
        Timber.i("TTS model selected: $name ($modelId)")
        // Sync with SDK to get actual load state (model may already be loaded)
        viewModelScope.launch {
            syncModelStates()
        }
    }

    override fun onCleared() {
        // Cancel all jobs BEFORE super.onCleared() cancels viewModelScope
        eventSubscriptionJob?.cancel()
        pipelineJob?.cancel()
        audioRecordingJob?.cancel()
        processingJob?.cancel()
        stopAudioPlayback()
        audioCaptureService?.release()
        audioCaptureService = null
        // Round 1 KOTLIN (G-E4): best-effort teardown via public SDK.
        try {
            // cleanupVoiceAgent is a suspend fn; fire-and-forget on viewModelScope.
            viewModelScope.launch { RunAnywhere.cleanupVoiceAgent() }
        } catch (_: Exception) {
            // best-effort cleanup
        }
        super.onCleared()
    }
}
