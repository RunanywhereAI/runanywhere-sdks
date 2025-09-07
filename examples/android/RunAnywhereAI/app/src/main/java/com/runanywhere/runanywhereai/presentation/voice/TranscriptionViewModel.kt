package com.runanywhere.runanywhereai.presentation.voice

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// @HiltViewModel
class TranscriptionViewModel(application: Application) : AndroidViewModel(application) {

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _transcriptionText = MutableStateFlow("")
    val transcriptionText: StateFlow<String> = _transcriptionText.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    private val _partialTranscript = MutableStateFlow("")
    val partialTranscript: StateFlow<String> = _partialTranscript.asStateFlow()

    init {
        initializeSDK()
        observeSDKEvents()
    }

    private fun initializeSDK() {
        viewModelScope.launch {
            try {
                // Initialize SDK without context parameter (not needed in new SDK)
                RunAnywhere.initialize(
                    apiKey = "demo-api-key",
                    baseURL = "https://api.runanywhere.ai",
                    environment = com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT
                )

                _isInitialized.value = true

            } catch (e: Exception) {
                _error.value = "Failed to initialize SDK: ${e.message}"
            }
        }
    }

    private fun observeSDKEvents() {
        viewModelScope.launch {
            // Observe voice events from EventBus
            EventBus.voiceEvents.collect { event ->
                when (event) {
                    is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionStarted -> {
                        _isRecording.value = true
                        _partialTranscript.value = ""
                    }

                    is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionFinal -> {
                        val currentText = _transcriptionText.value
                        _transcriptionText.value = if (currentText.isEmpty()) {
                            event.text
                        } else {
                            "$currentText\n${event.text}"
                        }
                        _partialTranscript.value = ""
                        _isRecording.value = false
                    }

                    is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionPartial -> {
                        _partialTranscript.value = event.text
                    }

                    is com.runanywhere.sdk.events.SDKVoiceEvent.PipelineError -> {
                        _error.value = event.error.message ?: "Unknown error"
                        _isRecording.value = false
                    }

                    else -> {
                        // Handle other events
                    }
                }
            }
        }
    }

    fun startRecording() {
        viewModelScope.launch {
            try {
                if (!_isInitialized.value) {
                    _error.value = "SDK not initialized yet. Please wait..."
                    return@launch
                }

                // For now, just simulate starting transcription
                // In a real implementation, we would:
                // 1. Create STT and VAD components with configurations
                // 2. Start audio capture
                // 3. Process audio through the pipeline

                val sttConfig = STTConfiguration(
                    modelId = "whisper-base",
                    language = "en-US"
                )

                val vadConfig = VADConfiguration(
                    aggressiveness = 2
                )

                // Simulate starting recording
                _isRecording.value = true

                // TODO: Implement actual audio capture and processing
                // This would involve using the audio capture service from the implementation plan

            } catch (e: Exception) {
                _error.value = "Failed to start recording: ${e.message}"
            }
        }
    }

    fun stopRecording() {
        viewModelScope.launch {
            try {
                // Stop recording
                _isRecording.value = false
                _partialTranscript.value = ""

                // TODO: Stop actual audio capture and processing

            } catch (e: Exception) {
                _error.value = "Failed to stop recording: ${e.message}"
            }
        }
    }

    fun clearTranscription() {
        _transcriptionText.value = ""
        _partialTranscript.value = ""
        _error.value = null
    }

    fun clearError() {
        _error.value = null
    }
}
