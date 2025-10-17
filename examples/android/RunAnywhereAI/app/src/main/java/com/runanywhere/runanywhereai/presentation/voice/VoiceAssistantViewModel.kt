package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.models.*
import com.runanywhere.runanywhereai.domain.services.VoicePipelineService
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
// import dagger.hilt.android.lifecycle.HiltViewModel
// import javax.inject.Inject

/**
 * ViewModel for Voice Assistant screen
 * Implements complete voice pipeline matching iOS functionality
 */
// @HiltViewModel
class VoiceAssistantViewModel(
    application: Application
    // @Inject private val voicePipelineService: VoicePipelineService
) : AndroidViewModel(application) {

    private val voicePipelineService = VoicePipelineService(application.applicationContext)

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

    // Additional state flows matching iOS
    val currentTranscript: StateFlow<String> = _uiState.map { it.currentTranscript }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val assistantResponse: StateFlow<String> = _uiState.map { it.assistantResponse }.stateIn(
        viewModelScope, SharingStarted.Eagerly, ""
    )
    val audioLevel: StateFlow<Float> = voicePipelineService.audioLevel

    init {
        initializePipeline()
        observePipelineEvents()
        observeAudioLevels()
    }

    private fun initializePipeline() {
        viewModelScope.launch {
            try {
                val config = ModularPipelineConfig(
                    components = listOf(
                        PipelineComponent.VAD,
                        PipelineComponent.STT,
                        PipelineComponent.LLM,
                        PipelineComponent.TTS
                    ),
                    vadConfig = VADConfig(
                        sensitivity = 0.5f,
                        minSpeechDuration = 250,
                        minSilenceDuration = 500
                    ),
                    sttConfig = VoiceSTTConfig(
                        modelId = _uiState.value.whisperModel,
                        language = "en",
                        enableRealTime = true
                    ),
                    llmConfig = VoiceLLMConfig(
                        modelId = _uiState.value.currentLLMModel,
                        maxTokens = 150,
                        temperature = 0.7f
                    ),
                    ttsConfig = VoiceTTSConfig(
                        voice = _uiState.value.ttsVoice
                    )
                )

                voicePipelineService.initialize(config)
            } catch (e: Exception) {
                _uiState.update { it.copy(
                    errorMessage = "Failed to initialize: ${e.message}",
                    sessionState = SessionState.ERROR
                )}
            }
        }
    }

    private fun observePipelineEvents() {
        viewModelScope.launch {
            voicePipelineService.pipelineEvents.collect { event ->
                when (event) {
                    is VoicePipelineEvent.VADSpeechStart -> {
                        _uiState.update { it.copy(
                            isSpeechDetected = true,
                            sessionState = SessionState.LISTENING
                        )}
                    }
                    is VoicePipelineEvent.VADSpeechEnd -> {
                        _uiState.update { it.copy(
                            isSpeechDetected = false,
                            sessionState = SessionState.PROCESSING
                        )}
                    }
                    is VoicePipelineEvent.STTPartialTranscript -> {
                        _uiState.update { it.copy(
                            currentTranscript = event.text
                        )}
                    }
                    is VoicePipelineEvent.STTFinalTranscript -> {
                        _uiState.update { it.copy(
                            currentTranscript = event.text,
                            sessionState = SessionState.PROCESSING
                        )}
                    }
                    is VoicePipelineEvent.LLMResponse -> {
                        _uiState.update { it.copy(
                            assistantResponse = event.text,
                            sessionState = SessionState.SPEAKING
                        )}
                    }
                    is VoicePipelineEvent.TTSStart -> {
                        _uiState.update { it.copy(
                            sessionState = SessionState.SPEAKING
                        )}
                    }
                    is VoicePipelineEvent.TTSComplete -> {
                        _uiState.update { it.copy(
                            sessionState = SessionState.CONNECTED
                        )}
                    }
                    is VoicePipelineEvent.Error -> {
                        _uiState.update { it.copy(
                            errorMessage = event.message,
                            sessionState = SessionState.ERROR
                        )}
                    }
                }
            }
        }
    }

    private fun observeAudioLevels() {
        viewModelScope.launch {
            audioLevel.collect { level ->
                _uiState.update { it.copy(audioLevel = level) }
            }
        }
    }

    fun startSession() {
        viewModelScope.launch {
            try {
                _uiState.update { it.copy(
                    sessionState = SessionState.CONNECTING,
                    errorMessage = null,
                    currentTranscript = "",
                    assistantResponse = ""
                )}

                voicePipelineService.startPipeline()

                _uiState.update { it.copy(
                    sessionState = SessionState.CONNECTED,
                    isListening = true
                )}
            } catch (e: Exception) {
                _uiState.update { it.copy(
                    sessionState = SessionState.ERROR,
                    errorMessage = "Failed to start: ${e.message}",
                    isListening = false
                )}
            }
        }
    }

    fun stopSession() {
        viewModelScope.launch {
            voicePipelineService.stopPipeline()
            _uiState.update { it.copy(
                sessionState = SessionState.DISCONNECTED,
                isListening = false,
                isSpeechDetected = false
            )}
        }
    }

    // Push-to-talk functionality
    fun startListening() {
        viewModelScope.launch {
            voicePipelineService.startListening()
            _uiState.update { it.copy(
                isListening = true,
                sessionState = SessionState.LISTENING
            )}
        }
    }

    fun stopListening() {
        viewModelScope.launch {
            voicePipelineService.stopListening()
            _uiState.update { it.copy(
                isListening = false,
                sessionState = SessionState.PROCESSING
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
        voicePipelineService.cleanup()
    }
}
