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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

private const val TAG = "TTSViewModel"

/**
 * Collection of funny sample texts for TTS demo
 * Matches iOS funnyTTSSampleTexts in TextToSpeechView.swift
 */
val funnyTTSSampleTexts = listOf(
    "I'm not saying I'm Batman, but have you ever seen me and Batman in the same room?",
    "According to my calculations, I should have been a millionaire by now. My calculations were wrong.",
    "I told my computer I needed a break, and now it won't stop sending me vacation ads.",
    "Why do programmers prefer dark mode? Because light attracts bugs!",
    "I speak fluent sarcasm. Unfortunately, my phone's voice assistant doesn't.",
    "I'm on a seafood diet. I see food and I eat it. Then I feel regret.",
    "My brain has too many tabs open and I can't find the one playing music.",
    "I put my phone on airplane mode but it didn't fly. Worst paper airplane ever.",
    "I'm not lazy, I'm just on energy-saving mode. Like a responsible gadget.",
    "If Monday had a face, I would politely ask it to reconsider its life choices.",
    "I tried to be normal once. Worst two minutes of my life.",
    "My favorite exercise is a cross between a lunge and a crunch. I call it lunch.",
    "I don't need anger management. I need people to stop irritating me.",
    "I'm not arguing, I'm just explaining why I'm right. There's a difference.",
    "Coffee: because adulting is hard and mornings are a cruel joke.",
    "I finally found my spirit animal. It's a sloth having a bad hair day.",
    "My wallet is like an onion. When I open it, I cry.",
    "I'm not short, I'm concentrated awesome in a compact package.",
    "Life update: currently holding it all together with one bobby pin.",
    "I would lose weight, but I hate losing.",
    "Behind every great person is a cat judging them silently.",
    "I'm on the whiskey diet. I've lost three days already.",
    "My houseplants are thriving! Just kidding, they're plastic.",
    "I don't sweat, I sparkle. Aggressively. With visible discomfort.",
    "Plot twist: the hokey pokey really IS what it's all about.",
    // RunAnywhere SDK promotional texts
    "RunAnywhere: because your AI should work even when your WiFi doesn't.",
    "We're a Y Combinator company now. Our moms are finally proud of us.",
    "On-device AI means your voice data stays on your phone. Unlike your ex, we respect privacy.",
    "RunAnywhere: Making cloud APIs jealous since 2024.",
    "Our SDK is so fast, it finished processing before you finished reading this sentence.",
    "Why pay per API call when you can run AI locally? Your wallet called, it says thank you.",
    "RunAnywhere: We put the 'smart' in smartphone, and the 'savings' in your bank account.",
    "Backed by Y Combinator. Powered by caffeine. Fueled by the dream of affordable AI.",
    "Our on-device models are like introverts. They do great work without needing the cloud.",
    "RunAnywhere SDK: Because latency is just a fancy word for 'too slow'.",
    "Voice AI that runs offline? That's not magic, that's just good engineering. Okay, maybe a little magic.",
    "We optimized our models so hard, they now run faster than your excuses for not exercising.",
    "RunAnywhere: Where 'it works offline' isn't a bug, it's the whole feature.",
    "Y Combinator believed in us. Your device believes in us. Now it's your turn.",
    "On-device AI: All the intelligence, none of the monthly subscription fees.",
    "Our SDK is like a good friend: fast, reliable, and doesn't share your secrets with big tech.",
    "RunAnywhere makes voice AI accessible. Like, actually accessible. Not 'enterprise pricing' accessible."
)

private fun getRandomSampleText(): String = funnyTTSSampleTexts.random()

// Initial random text for default state
private val initialSampleText = getRandomSampleText()

/**
 * TTS UI State
 * iOS Reference: TTSViewModel published properties in TextToSpeechView.swift
 */
data class TTSUiState(
    val inputText: String = initialSampleText,
    val characterCount: Int = initialSampleText.length,
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
    private var currentComponentModelId: String? = null  // Track which model the component is configured for
    private val restorationMutex = Mutex()  // Synchronize component restoration to prevent race conditions

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
                val wasLoaded = _uiState.value.isModelLoaded

                _uiState.update {
                    it.copy(
                        isModelLoaded = isNowLoaded,
                        selectedModelName = if (isNowLoaded) ttsState?.modelName else it.selectedModelName,
                        selectedModelId = if (isNowLoaded) ttsState?.modelId else it.selectedModelId,
                        selectedFramework = if (isNowLoaded) ttsState?.framework?.displayName else it.selectedFramework,
                        isSystemTTS = ttsState?.framework == LLMFramework.SYSTEM_TTS
                    )
                }

                // Shuffle sample text when model is first loaded
                // iOS Reference: .onChange(of: viewModel.selectedModelName) in TextToSpeechView
                if (isNowLoaded && !wasLoaded) {
                    shuffleSampleText()
                }

                // Restore component if model is loaded (handles both initial load and model switching)
                // The restoreTTSComponent method will handle checking if we need to create a new component
                if (isNowLoaded && ttsState != null) {
                    restoreTTSComponent(ttsState.modelId)
                }

                Log.d(TAG, "📊 TTS lifecycle state updated: loaded=$isNowLoaded, model=${ttsState?.modelName}")
            }
        }
    }

    /**
     * Restore TTSComponent from a previously loaded model
     * iOS Reference: restoreComponentIfNeeded() in TTSViewModel
     *
     * IMPORTANT: This now properly handles model switching by cleaning up
     * the old component when a different model is selected.
     */
    private fun restoreTTSComponent(modelId: String) {
        viewModelScope.launch {
            restorationMutex.withLock {
                // Check if we already have a component for this exact model
                if (ttsComponent != null && currentComponentModelId == modelId) {
                    Log.d(TAG, "TTS component already configured for model: $modelId")
                    return@withLock
                }

                // Clean up existing component if switching to a different model
                if (ttsComponent != null && currentComponentModelId != modelId) {
                    Log.i(TAG, "Switching TTS model from $currentComponentModelId to $modelId - cleaning up old component")
                    try {
                        ttsComponent?.cleanup()
                    } catch (e: Exception) {
                        Log.w(TAG, "Error cleaning up old TTS component: ${e.message}")
                    }
                    ttsComponent = null
                    currentComponentModelId = null
                }

                Log.i(TAG, "Restoring TTS component for model: $modelId")
                try {
                    // Get the model info to find the local path
                    val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
                    val effectiveModelId = modelInfo?.localPath ?: modelId

                    Log.i(TAG, "Using effective model path: $effectiveModelId")

                    // Create TTS configuration (matches iOS TTSConfiguration)
                    val config = TTSConfiguration(
                        modelId = effectiveModelId,
                        speakingRate = _uiState.value.speed,
                        pitch = _uiState.value.pitch,
                        volume = 1.0f,
                        audioFormat = SDKAudioFormat.WAV
                    )

                    val component = TTSComponent(config)
                    component.initialize()
                    ttsComponent = component
                    currentComponentModelId = modelId  // Track which model this component is for

                    Log.i(TAG, "✅ TTS component restored successfully for model: $modelId")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to restore TTS component: ${e.message}", e)
                }
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
     * Shuffle to a random sample text
     * iOS Reference: "Surprise me!" button in TextToSpeechView
     */
    fun shuffleSampleText() {
        val newText = getRandomSampleText()
        _uiState.update {
            it.copy(
                inputText = newText,
                characterCount = newText.length
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
                            sampleRate = null,  // SynthesisMetadata doesn't include sampleRate
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

                // Track playback progress (matches iOS timer pattern)
                val duration = _uiState.value.audioDuration ?: (pcmData.size.toDouble() / (sampleRate * 2))
                var currentTime = 0.0

                while (_uiState.value.isPlaying && audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    delay(100)
                    currentTime += 0.1

                    // Check if we've reached the end of audio
                    if (currentTime >= duration) {
                        break
                    }

                    withContext(Dispatchers.Main) {
                        _uiState.update {
                            it.copy(
                                currentTime = currentTime,
                                playbackProgress = (currentTime / duration).coerceIn(0.0, 1.0)
                            )
                        }
                    }
                }

                // Playback finished - stop and reset state
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
        // Update state first to signal the playback loop to stop
        _uiState.update {
            it.copy(
                isPlaying = false,
                currentTime = 0.0,
                playbackProgress = 0.0
            )
        }

        // Cancel the playback job
        playbackJob?.cancel()
        playbackJob = null

        // Stop and release AudioTrack
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null

        Log.d(TAG, "Playback stopped")
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
        currentComponentModelId = null
        generatedAudioData = null
    }
}
