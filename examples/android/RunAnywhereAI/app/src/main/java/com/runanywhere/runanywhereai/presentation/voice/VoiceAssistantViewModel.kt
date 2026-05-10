package com.runanywhere.runanywhereai.presentation.voice

import ai.runanywhere.proto.v1.AudioEncoding
import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_LLM
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_STT
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_TTS
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.VoiceAgentResult
import ai.runanywhere.proto.v1.VoiceEvent
import ai.runanywhere.proto.v1.VoiceSessionError
import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
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
import com.runanywhere.sdk.public.extensions.processVoiceTurn
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import com.runanywhere.sdk.public.extensions.toVoiceAgentTurnRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.ByteArrayOutputStream

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

    // Audio buffer for accumulating audio data (guarded by audioBufferLock)
    private val audioBuffer = ByteArrayOutputStream()
    private val audioBufferLock = Any()

    // Jobs for coroutine management
    private var pipelineJob: Job? = null
    private var eventSubscriptionJob: Job? = null
    private var audioRecordingJob: Job? = null

    @Volatile
    private var isProcessingTurn = false

    // Audio playback (matching iOS AudioPlaybackManager)
    private var audioTrack: AudioTrack? = null
    private var audioPlaybackJob: Job? = null
    private var processingJob: Job? = null

    @Volatile
    private var isPlayingAudio = false

    private val minAudioBytes = 16000 // ~0.5s at 16kHz, 16-bit
    private val defaultTtsSampleRate = 22050 // TTS output sample rate (Piper default)

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
     * Play synthesized TTS audio
     * iOS Reference: AudioPlaybackManager.play() in VoiceSessionHandle
     *
     * Plays WAV audio data through AudioTrack
     */
    private fun playAudio(
        audioData: ByteArray,
        sampleRateHz: Int = defaultTtsSampleRate,
    ) {
        if (audioData.isEmpty()) {
            Timber.w("No audio data to play")
            _uiState.update { it.copy(pipelineState = PipelineState.PIPELINE_STATE_STOPPED) }
            return
        }

        Timber.i("🔊 Starting TTS playback (${audioData.size} bytes)")
        isPlayingAudio = true

        _uiState.update {
            it.copy(pipelineState = PipelineState.PIPELINE_STATE_SPEAKING)
        }

        audioPlaybackJob =
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                    val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                    // Scan for WAV "data" chunk to find PCM offset
                    val isWav =
                        audioData.size > 44 &&
                            audioData[0] == 'R'.code.toByte() &&
                            audioData[1] == 'I'.code.toByte() &&
                            audioData[2] == 'F'.code.toByte() &&
                            audioData[3] == 'F'.code.toByte()

                    val headerSize =
                        if (isWav) {
                            var offset = 12 // skip RIFF header (12 bytes)
                            var dataStart = -1
                            while (offset + 8 <= audioData.size) {
                                val chunkId = String(audioData, offset, 4, Charsets.US_ASCII)
                                val chunkSize =
                                    (audioData[offset + 4].toInt() and 0xFF) or
                                        ((audioData[offset + 5].toInt() and 0xFF) shl 8) or
                                        ((audioData[offset + 6].toInt() and 0xFF) shl 16) or
                                        ((audioData[offset + 7].toInt() and 0xFF) shl 24)
                                if (chunkId == "data") {
                                    dataStart = offset + 8
                                    break
                                }
                                offset += 8 + chunkSize
                            }
                            if (dataStart > 0) dataStart else 44 // fallback for malformed files
                        } else {
                            0
                        }

                    val pcmData = audioData.copyOfRange(headerSize, audioData.size)
                    Timber.d("PCM data size: ${pcmData.size} bytes (skipped $headerSize byte header)")

                    val bufferSize = AudioTrack.getMinBufferSize(sampleRateHz, channelConfig, audioFormat)

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
                                    .setSampleRate(sampleRateHz)
                                    .setChannelMask(channelConfig)
                                    .build(),
                            )
                            .setBufferSizeInBytes(bufferSize.coerceAtLeast(pcmData.size))
                            .setTransferMode(AudioTrack.MODE_STATIC)
                            .build()

                    audioTrack?.write(pcmData, 0, pcmData.size)
                    audioTrack?.play()

                    Timber.i("🔊 TTS playback started")

                    // Calculate duration and wait for playback to complete
                    val durationMs = (pcmData.size.toDouble() / (sampleRateHz * 2) * 1000).toLong()
                    Timber.d("Expected playback duration: ${durationMs}ms")

                    // Wait for playback to complete
                    var elapsed = 0L
                    while (isPlayingAudio && elapsed < durationMs && audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        delay(100)
                        elapsed += 100
                    }

                    Timber.i("🔊 TTS playback completed")

                    withContext(Dispatchers.Main) {
                        stopAudioPlayback()
                        _uiState.update {
                            it.copy(
                                pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                                audioLevel = 0f,
                            )
                        }
                    }
                } catch (e: Exception) {
                    Timber.e(e, "Audio playback error: ${e.message}")
                    withContext(Dispatchers.Main) {
                        stopAudioPlayback()
                        _uiState.update {
                            it.copy(
                                pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                                audioLevel = 0f,
                                errorMessage = "Audio playback error: ${e.message}",
                            )
                        }
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

                synchronized(audioBufferLock) { audioBuffer.reset() }
                isProcessingTurn = false

                _uiState.update {
                    it.copy(
                        pipelineState = PipelineState.PIPELINE_STATE_LISTENING,
                        audioLevel = 0f,
                    )
                }

                Timber.i("Voice turn recording started")

                audioRecordingJob =
                    viewModelScope.launch {
                        try {
                            audioCapture.startCapture().collect { audioData ->
                                if (isProcessingTurn) {
                                    // KOT-VOICE-001: trace why audio is being dropped during turn handoff.
                                    Timber.d("Skipping audio chunk while processing turn (size=${audioData.size})")
                                    return@collect
                                }

                                synchronized(audioBufferLock) {
                                    audioBuffer.write(audioData)
                                }

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
        handleProtoEvent(VoiceEvent(session_error = error))
    }

    private fun handleProtoEvent(event: VoiceEvent) {
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
     * Stop conversation completely
     * iOS Reference: stop() in VoiceSessionHandle
     *
     * Stops audio recording and voice session without processing remaining audio.
     * Use this for manual stop (user pressed stop button).
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

            val audioData: ByteArray
            val audioSize: Int
            synchronized(audioBufferLock) {
                audioData = audioBuffer.toByteArray()
                audioSize = audioData.size
                audioBuffer.reset()
            }

            Timber.i("Captured audio: $audioSize bytes")

            if (audioSize >= minAudioBytes) {
                isProcessingTurn = true
                _uiState.update {
                    it.copy(
                        pipelineState = PipelineState.PIPELINE_STATE_PROCESSING_SPEECH,
                        audioLevel = 0f,
                    )
                }

                try {
                    Timber.i("Processing audio through voice pipeline...")

                    val result =
                        withContext(Dispatchers.Default) {
                            processVoiceTurn(audioData)
                        }

                    Timber.i(
                        "Voice pipeline result - speechDetected: ${result.speech_detected}, " +
                            "transcription: ${result.transcription?.take(50)}, " +
                            "response: ${result.assistant_response?.take(50)}",
                    )

                    applyVoiceTurnResult(result)
                } catch (e: Exception) {
                    Timber.e(e, "Error processing voice: ${e.message}")
                    showSessionError(
                        VoiceSessionError(
                            code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                            message = "Processing error: ${e.message}",
                            failed_component = "voice_agent",
                            recoverable = true,
                        ),
                    )
                } finally {
                    isProcessingTurn = false
                }
            } else {
                Timber.i("Audio too short to process ($audioSize bytes)")
                _uiState.update {
                    it.copy(
                        pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                        audioLevel = 0f,
                        errorMessage = if (audioSize > 0) "Recording too short" else null,
                    )
                }
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
                // Don't reset ttsLoadState - model may already be loaded by ModelSelectionBottomSheet
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

    private suspend fun processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
        val request =
            audioData.toVoiceAgentTurnRequest(
                sampleRateHz = AudioCaptureService.SAMPLE_RATE,
                channels = 1,
                encoding = AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            )
        return RunAnywhere.processVoiceTurn(request)
    }

    private fun applyVoiceTurnResult(result: VoiceAgentResult) {
        val errorMessage = result.error_message
        if (!errorMessage.isNullOrBlank()) {
            showSessionError(
                VoiceSessionError(
                    code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                    message = errorMessage,
                    failed_component = "voice_agent",
                    recoverable = true,
                ),
            )
            return
        }

        val transcription = result.transcription
        val response = result.assistant_response.orEmpty()
        if (result.speech_detected && !transcription.isNullOrBlank()) {
            _uiState.update {
                it.copy(
                    currentTranscript = transcription,
                    assistantResponse = response,
                    pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                    errorMessage = null,
                )
            }

            val synthesizedAudio = result.synthesized_audio?.toByteArray()
            if (synthesizedAudio != null && synthesizedAudio.isNotEmpty()) {
                Timber.i("🔊 Playing TTS response (${synthesizedAudio.size} bytes)")
                val sampleRate =
                    result.synthesized_audio_sample_rate_hz
                        .takeIf { it > 0 }
                        ?: defaultTtsSampleRate
                playAudio(synthesizedAudio, sampleRate)
            }
        } else {
            Timber.i("No speech detected in audio")
            _uiState.update {
                it.copy(
                    pipelineState = PipelineState.PIPELINE_STATE_STOPPED,
                    errorMessage = "No speech detected",
                )
            }
        }
    }
}
