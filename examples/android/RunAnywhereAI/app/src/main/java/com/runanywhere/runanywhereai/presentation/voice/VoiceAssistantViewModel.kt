package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.SessionState
import com.runanywhere.sdk.audio.AndroidAudioCapture
import com.runanywhere.sdk.audio.AudioCaptureOptions
import com.runanywhere.sdk.components.tts.AndroidTTSService
import com.runanywhere.sdk.components.TTSOptions
import com.runanywhere.sdk.events.ModularPipelineEvent
import com.runanywhere.sdk.public.ModularPipelineConfig
import com.runanywhere.sdk.public.PipelineComponent
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.VADConfig
import com.runanywhere.sdk.public.VoiceSTTConfig
import com.runanywhere.sdk.public.VoiceLLMConfig
import com.runanywhere.sdk.public.VoiceTTSConfig
import com.runanywhere.sdk.public.createVoicePipeline
import com.runanywhere.sdk.voice.ModularVoicePipeline
import com.runanywhere.sdk.voice.TTSHandler
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * ViewModel for Voice Assistant screen
 * Uses SDK's ModularVoicePipeline directly (matches iOS pattern)
 */
class VoiceAssistantViewModel(
    application: Application
) : AndroidViewModel(application) {

    private val context: Context = application.applicationContext
    private var voicePipeline: ModularVoicePipeline? = null
    private var audioCapture: AndroidAudioCapture? = null
    private var pipelineJob: Job? = null
    private var ttsService: AndroidTTSService? = null

    // UI State
    data class UiState(
        val sessionState: SessionState = SessionState.DISCONNECTED,
        val isListening: Boolean = false,
        val isSpeechDetected: Boolean = false,
        val currentTranscript: String = "",
        val assistantResponse: String = "",
        val errorMessage: String? = null,
        val audioLevel: Float = 0f,
        val currentLLMModel: String = "llama3.2-3b",
        val whisperModel: String = "whisper-base",
        val ttsVoice: String = "default"
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

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

    // Additional state flows
    val currentTranscript: StateFlow<String> = _uiState.map { it.currentTranscript }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val assistantResponse: StateFlow<String> = _uiState.map { it.assistantResponse }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val audioLevel: StateFlow<Float> = _uiState.map { it.audioLevel }.stateIn(
        viewModelScope, SharingStarted.Eagerly, 0f
    )

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

                // Create pipeline configuration
                val config = ModularPipelineConfig.create(
                    components = listOf(
                        PipelineComponent.VAD,
                        PipelineComponent.STT,
                        PipelineComponent.LLM,
                        PipelineComponent.TTS
                    ),
                    vad = VADConfig(
                        energyThreshold = 0.005f // Lower threshold for better detection
                    ),
                    stt = VoiceSTTConfig(
                        modelId = _uiState.value.whisperModel,
                        language = "en-US"
                    ),
                    llm = VoiceLLMConfig(
                        modelId = _uiState.value.currentLLMModel,
                        maxTokens = 100,
                        systemPrompt = "You are a helpful voice assistant. Keep responses concise and conversational."
                    ),
                    tts = VoiceTTSConfig(
                        voice = _uiState.value.ttsVoice
                    )
                )

                // Create the voice pipeline using SDK
                voicePipeline = RunAnywhere.createVoicePipeline(config)

                // Initialize TTS service
                ttsService = AndroidTTSService(context)
                ttsService?.initialize()

                // Set TTS handler for the pipeline
                voicePipeline?.setTTSHandler(object : TTSHandler {
                    override suspend fun initialize() {
                        // Already initialized above
                    }

                    override suspend fun synthesize(text: String) {
                        ttsService?.synthesize(
                            text, TTSOptions(
                                language = "en-US",
                                rate = 1.0f,
                                pitch = 1.0f,
                                volume = 1.0f
                            )
                        )
                    }

                    override suspend fun cleanup() {
                        ttsService?.cleanup()
                    }
                })

                // Initialize components
                _uiState.update { it.copy(sessionState = SessionState.CONNECTING) }

                voicePipeline?.initializeComponents()?.collect { event ->
                    handleInitializationEvent(event)
                }

                // Start audio capture
                val audioCaptureOptions = AudioCaptureOptions()
                audioCapture = AndroidAudioCapture(context, audioCaptureOptions)
                val audioStream = audioCapture?.startContinuousCapture()

                _uiState.update {
                    it.copy(
                        sessionState = SessionState.CONNECTED,
                        isListening = true
                    )
                }

                // Process audio through pipeline
                pipelineJob = viewModelScope.launch {
                    try {
                        voicePipeline?.process(audioStream!!)?.collect { event ->
                            handlePipelineEvent(event)
                        }
                    } catch (e: Exception) {
                        _uiState.update { it.copy(
                            errorMessage = "Pipeline error: ${e.message}",
                            sessionState = SessionState.ERROR
                        )}
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

    private fun handleInitializationEvent(event: ModularPipelineEvent) {
        when (event) {
            is ModularPipelineEvent.componentInitializing -> {
                // Component is initializing
            }
            is ModularPipelineEvent.componentInitialized -> {
                // Component initialized
            }

            is ModularPipelineEvent.allComponentsInitialized -> {
                _uiState.update { it.copy(sessionState = SessionState.CONNECTED) }
            }

            else -> {}
        }
    }

    private fun handlePipelineEvent(event: ModularPipelineEvent) {
        when (event) {
            is ModularPipelineEvent.vadSpeechStart -> {
                _uiState.update { it.copy(
                    isSpeechDetected = true,
                    sessionState = SessionState.LISTENING
                )}
            }

            is ModularPipelineEvent.vadSpeechEnd -> {
                _uiState.update { it.copy(
                    isSpeechDetected = false,
                    sessionState = SessionState.PROCESSING
                )}
            }

            is ModularPipelineEvent.sttPartialTranscript -> {
                _uiState.update { it.copy(
                    currentTranscript = event.partial
                )}
            }
            is ModularPipelineEvent.sttFinalTranscript -> {
                _uiState.update {
                    it.copy(
                        currentTranscript = event.transcript,
                        sessionState = SessionState.PROCESSING
                    )
                }
            }

            is ModularPipelineEvent.llmThinking -> {
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.PROCESSING
                    )
                }
            }

            is ModularPipelineEvent.llmFinalResponse -> {
                _uiState.update {
                    it.copy(
                        assistantResponse = event.text,
                        sessionState = SessionState.SPEAKING
                    )
                }
            }

            is ModularPipelineEvent.ttsStarted -> {
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.SPEAKING
                    )
                }
            }

            is ModularPipelineEvent.ttsCompleted -> {
                _uiState.update {
                    it.copy(
                        sessionState = SessionState.LISTENING,
                        currentTranscript = "",
                        assistantResponse = ""
                    )
                }
            }

            is ModularPipelineEvent.pipelineError -> {
                _uiState.update {
                    it.copy(
                        errorMessage = event.error.message,
                        sessionState = SessionState.ERROR
                    )
                }
            }

            else -> {}
        }
    }

    fun stopSession() {
        viewModelScope.launch {
            pipelineJob?.cancel()
            pipelineJob = null
            audioCapture?.stopCapture()

            voicePipeline?.cleanup()
            voicePipeline = null

            _uiState.update { it.copy(
                sessionState = SessionState.DISCONNECTED,
                isListening = false,
                isSpeechDetected = false
            )}
        }
    }

    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun clearConversation() {
        _uiState.update { it.copy(
            currentTranscript = "",
            assistantResponse = ""
        )}
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch {
            stopSession()
        }
    }
}
