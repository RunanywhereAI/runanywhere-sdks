package com.runanywhere.runanywhereai.presentation.tts

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.components.AudioFormat as SDKAudioFormat
import com.runanywhere.sdk.components.TTSComponent
import com.runanywhere.sdk.components.TTSConfiguration
import com.runanywhere.sdk.components.TTSVoice
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.lifecycle.Modality
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleTracker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val TAG = "TTSViewModel"

/**
 * TTS UI State
 * iOS Reference: TTSViewModel published properties in TextToSpeechView.swift
 */
data class TTSUiState(
    val inputText: String = "Hello! This is a text to speech test.",
    val characterCount: Int = "Hello! This is a text to speech test.".length,
    val maxCharacters: Int = 5000,
    val isModelLoaded: Boolean = false,
    val selectedFramework: String? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val isGenerating: Boolean = false,
    val isPlaying: Boolean = false,
    val hasGeneratedAudio: Boolean = false,
    val isSystemTTS: Boolean = false,
    val speed: Float = 1.0f,
    val pitch: Float = 1.0f,
    val audioDuration: Double? = null,
    val audioSize: Int? = null,
    val sampleRate: Int? = null,
    val playbackProgress: Double = 0.0,
    val currentTime: Double = 0.0,
    val errorMessage: String? = null,
    val processingTimeMs: Long? = null
)

/**
 * Text to Speech ViewModel
 *
 * iOS Reference: TTSViewModel in TextToSpeechView.swift
 *
 * This ViewModel manages:
 * - Voice/model selection and loading via TTSComponent
 * - Speech generation from text via RunAnywhere SDK
 * - Audio playback controls with AudioTrack
 * - Voice settings (speed, pitch)
 *
 * Architecture matches iOS:
 * - TTSComponent for framework-agnostic TTS
 * - Model loading through SDK registry
 * - Audio playback similar to iOS AVAudioPlayer
 */
class TextToSpeechViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(TTSUiState())
    val uiState: StateFlow<TTSUiState> = _uiState.asStateFlow()

    // SDK Components - matches iOS TTSComponent pattern
    private var ttsComponent: TTSComponent? = null

    // Audio playback
    private var audioTrack: AudioTrack? = null
    private var generatedAudioData: ByteArray? = null
    private var playbackJob: Job? = null

    init {
        Log.i(TAG, "Initializing TTS ViewModel...")

        // Subscribe to model lifecycle tracker for TTS modality
        viewModelScope.launch {
            ModelLifecycleTracker.modelsByModality.collect { modelsByModality ->
                val ttsState = modelsByModality[Modality.TTS]
                val isNowLoaded = ttsState?.state?.isLoaded == true

                _uiState.update {
                    it.copy(
                        isModelLoaded = isNowLoaded,
                        selectedModelName = if (isNowLoaded) ttsState?.modelName else it.selectedModelName,
                        selectedModelId = if (isNowLoaded) ttsState?.modelId else it.selectedModelId,
                        selectedFramework = if (isNowLoaded) ttsState?.framework?.displayName else it.selectedFramework,
                        isSystemTTS = ttsState?.framework == LLMFramework.SYSTEM_TTS
                    )
                }

                // Restore component if model is already loaded
                if (isNowLoaded && ttsComponent == null && ttsState != null) {
                    restoreTTSComponent(ttsState.modelId)
                }

                Log.d(TAG, "📊 TTS lifecycle state updated: loaded=$isNowLoaded, model=${ttsState?.modelName}")
            }
        }
    }

    /**
     * Restore TTSComponent from a previously loaded model
     * iOS Reference: restoreComponentIfNeeded() in TTSViewModel
     */
    private fun restoreTTSComponent(modelId: String) {
        viewModelScope.launch {
            if (ttsComponent != null) return@launch

            Log.i(TAG, "Restoring TTS component for model: $modelId")
            try {
                // Get the model info to find the local path
                val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
                val effectiveModelId = modelInfo?.localPath ?: modelId

                Log.i(TAG, "Using effective model path: $effectiveModelId")

                // Create TTS configuration (matches iOS TTSConfiguration)
                val config = TTSConfiguration(
                    modelId = effectiveModelId,
                    defaultRate = _uiState.value.speed,
                    defaultPitch = _uiState.value.pitch,
                    defaultVolume = 1.0f,
                    audioFormat = SDKAudioFormat.WAV,
                    sampleRate = 22050
                )

                val component = TTSComponent(config)
                component.initialize()
                ttsComponent = component

                Log.i(TAG, "✅ TTS component restored successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restore TTS component: ${e.message}", e)
            }
        }
    }

    /**
     * Initialize the TTS ViewModel
     * iOS Reference: initialize() in TTSViewModel
     */
    fun initialize() {
        Log.i(TAG, "Initializing TTS ViewModel...")
        // Audio session is managed by the framework - no additional setup needed
    }

    /**
     * Update the input text for TTS
     */
    fun updateInputText(text: String) {
        _uiState.update {
            it.copy(
                inputText = text,
                characterCount = text.length
            )
        }
    }

    /**
     * Update speech speed
     *
     * @param speed Speed multiplier (0.5 - 2.0)
     */
    fun updateSpeed(speed: Float) {
        _uiState.update { it.copy(speed = speed) }
    }

    /**
     * Update speech pitch
     *
     * @param pitch Pitch multiplier (0.5 - 2.0)
     */
    fun updatePitch(pitch: Float) {
        _uiState.update { it.copy(pitch = pitch) }
    }

    /**
     * Load a TTS model/voice via TTSComponent
     * iOS Reference: loadModelFromSelection() in TTSViewModel
     *
     * @param modelName Display name of the voice
     * @param modelId Voice/model identifier for SDK
     * @param isSystemTTS Whether this is the system TTS (plays directly)
     */
    fun loadModel(modelName: String, modelId: String, isSystemTTS: Boolean) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isGenerating = true,
                    errorMessage = null
                )
            }

            try {
                Log.i(TAG, "Loading TTS model: $modelName (id: $modelId, isSystem: $isSystemTTS)")

                // Get the model info to find the local path
                val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
                val effectiveModelId = modelInfo?.localPath ?: modelId

                Log.i(TAG, "Using effective model path: $effectiveModelId")

                // Create TTS configuration (matches iOS TTSConfiguration)
                val config = TTSConfiguration(
                    modelId = effectiveModelId,
                    defaultRate = _uiState.value.speed,
                    defaultPitch = _uiState.value.pitch,
                    defaultVolume = 1.0f,
                    audioFormat = SDKAudioFormat.WAV,
                    sampleRate = if (isSystemTTS) 16000 else 22050 // Piper uses 22050 Hz
                )

                val component = TTSComponent(config)
                component.initialize()

                ttsComponent = component

                val framework = if (isSystemTTS) "System TTS" else "Piper ONNX"

                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedFramework = framework,
                        selectedModelName = modelName,
                        selectedModelId = modelId,
                        isSystemTTS = isSystemTTS,
                        isGenerating = false
                    )
                }

                Log.i(TAG, "✅ TTS model loaded successfully: $modelName")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load TTS model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        errorMessage = "Failed to load voice: ${e.message}",
                        isGenerating = false
                    )
                }
            }
        }
    }

    /**
     * Generate speech from text via TTSComponent
     * iOS Reference: generateSpeech(text:) in TTSViewModel
     */
    fun generateSpeech() {
        viewModelScope.launch {
            val text = _uiState.value.inputText
            if (text.isEmpty()) return@launch

            val component = ttsComponent
            if (component == null) {
                _uiState.update {
                    it.copy(errorMessage = "No TTS model loaded. Please select a voice first.")
                }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isGenerating = true,
                    hasGeneratedAudio = false,
                    errorMessage = null
                )
            }

            try {
                Log.i(TAG, "Generating speech for text: ${text.take(50)}...")

                val startTime = System.currentTimeMillis()

                // Use TTSComponent.synthesize (matches iOS component.synthesize())
                val output = withContext(Dispatchers.IO) {
                    component.synthesize(
                        text = text,
                        voice = _uiState.value.selectedModelId,
                        language = "en-US"
                    )
                }

                val processingTime = System.currentTimeMillis() - startTime

                val isSystem = _uiState.value.isSystemTTS

                if (isSystem || output.audioData.isEmpty()) {
                    // System TTS plays directly - no audio data returned
                    // iOS equivalent: Audio already played via AVSpeechSynthesizer
                    Log.i(TAG, "System TTS playback completed (direct playback)")
                    _uiState.update {
                        it.copy(
                            isGenerating = false,
                            audioDuration = output.duration,
                            audioSize = null,
                            sampleRate = null,
                            processingTimeMs = processingTime
                            // hasGeneratedAudio stays false for system TTS
                        )
                    }
                } else {
                    // ONNX/Piper TTS returns audio data for playback
                    Log.i(TAG, "✅ Speech generation complete: ${output.audioData.size} bytes, duration: ${output.duration}s")

                    generatedAudioData = output.audioData

                    _uiState.update {
                        it.copy(
                            isGenerating = false,
                            hasGeneratedAudio = true,
                            audioDuration = output.duration,
                            audioSize = output.audioData.size,
                            sampleRate = output.metadata.sampleRate,
                            processingTimeMs = processingTime
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Speech generation failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        errorMessage = "Speech generation failed: ${e.message}"
                    )
                }
            }
        }
    }

    /**
     * Toggle audio playback
     * iOS Reference: togglePlayback() in TTSViewModel
     */
    fun togglePlayback() {
        if (_uiState.value.isPlaying) {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /**
     * Start audio playback using AudioTrack
     * iOS Reference: startPlayback() using AVAudioPlayer
     */
    private fun startPlayback() {
        val audioData = generatedAudioData
        if (audioData == null || audioData.isEmpty()) {
            Log.w(TAG, "No audio data to play")
            return
        }

        Log.i(TAG, "Starting playback of ${audioData.size} bytes")
        _uiState.update { it.copy(isPlaying = true) }

        playbackJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                // Parse WAV header to get audio parameters
                val sampleRate = _uiState.value.sampleRate ?: 22050
                val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                // Skip WAV header (44 bytes) if present
                val headerSize = if (audioData.size > 44 &&
                    audioData[0] == 'R'.code.toByte() &&
                    audioData[1] == 'I'.code.toByte() &&
                    audioData[2] == 'F'.code.toByte() &&
                    audioData[3] == 'F'.code.toByte()
                ) 44 else 0

                val pcmData = audioData.copyOfRange(headerSize, audioData.size)

                val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)

                audioTrack = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(audioFormat)
                            .setSampleRate(sampleRate)
                            .setChannelMask(channelConfig)
                            .build()
                    )
                    .setBufferSizeInBytes(bufferSize.coerceAtLeast(pcmData.size))
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                audioTrack?.write(pcmData, 0, pcmData.size)
                audioTrack?.play()

                // Track playback progress
                val duration = _uiState.value.audioDuration ?: (pcmData.size.toDouble() / (sampleRate * 2))
                var currentTime = 0.0

                while (currentTime < duration && _uiState.value.isPlaying) {
                    delay(100)
                    currentTime += 0.1
                    withContext(Dispatchers.Main) {
                        _uiState.update {
                            it.copy(
                                currentTime = currentTime,
                                playbackProgress = (currentTime / duration).coerceIn(0.0, 1.0)
                            )
                        }
                    }
                }

                // Playback finished
                withContext(Dispatchers.Main) {
                    stopPlayback()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Playback error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    _uiState.update {
                        it.copy(
                            isPlaying = false,
                            errorMessage = "Playback failed: ${e.message}"
                        )
                    }
                }
            }
        }
    }

    /**
     * Stop audio playback
     * iOS Reference: stopPlayback() using AVAudioPlayer
     */
    private fun stopPlayback() {
        playbackJob?.cancel()
        playbackJob = null

        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null

        _uiState.update {
            it.copy(
                isPlaying = false,
                currentTime = 0.0,
                playbackProgress = 0.0
            )
        }

        Log.d(TAG, "Playback stopped")
    }

    /**
     * Unload the current voice/model
     * iOS Reference: cleanup() in TTSComponent
     */
    fun unloadModel() {
        viewModelScope.launch {
            Log.i(TAG, "Unloading TTS model")
            stopPlayback()

            try {
                ttsComponent?.cleanup()
            } catch (e: Exception) {
                Log.e(TAG, "Error during TTS cleanup: ${e.message}")
            }

            ttsComponent = null
            generatedAudioData = null

            _uiState.update {
                it.copy(
                    isModelLoaded = false,
                    selectedFramework = null,
                    selectedModelName = null,
                    selectedModelId = null,
                    hasGeneratedAudio = false,
                    audioDuration = null,
                    audioSize = null,
                    sampleRate = null,
                    processingTimeMs = null
                )
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        Log.i(TAG, "ViewModel cleared, cleaning up resources")
        stopPlayback()

        viewModelScope.launch {
            try {
                ttsComponent?.cleanup()
            } catch (e: Exception) {
                Log.e(TAG, "Error during cleanup: ${e.message}")
            }
        }

        ttsComponent = null
        generatedAudioData = null
    }
}
