package com.runanywhere.runanywhereai.presentation.tts

import android.app.Application
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.events.TTSEvent
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.currentTTSVoiceId
import com.runanywhere.sdk.public.extensions.isTTSVoiceLoadedSync
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.stopSynthesis
import com.runanywhere.sdk.public.extensions.synthesize
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val TAG = "TTSViewModel"
private const val SYSTEM_TTS_MODEL_ID = "system-tts"

/**
 * Collection of funny sample texts for TTS demo
 * Matches iOS funnyTTSSampleTexts in TextToSpeechView.swift
 */
val funnyTTSSampleTexts =
    listOf(
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
        "RunAnywhere: Making cloud APIs jealous since 2026.",
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
        "RunAnywhere makes voice AI accessible. Like, actually accessible. Not 'enterprise pricing' accessible.",
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
    val selectedFramework: InferenceFramework? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val isGenerating: Boolean = false,
    val isPlaying: Boolean = false,
    val isSpeaking: Boolean = false,
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
    val processingTimeMs: Long? = null,
)

/**
 * Text to Speech ViewModel
 *
 * iOS Reference: TTSViewModel in TextToSpeechView.swift
 *
 * This ViewModel manages:
 * - Voice/model selection and loading via RunAnywhere SDK
 * - Speech generation from text via RunAnywhere.synthesize()
 * - Audio playback controls with AudioTrack
 * - Voice settings (speed, pitch)
 *
 * Architecture matches iOS:
 * - Uses RunAnywhere SDK extension functions directly
 * - Model loading via RunAnywhere.loadTTSVoice()
 * - Event subscription via RunAnywhere.events.events
 */
class TextToSpeechViewModel(
    application: Application,
) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(TTSUiState())
    val uiState: StateFlow<TTSUiState> = _uiState.asStateFlow()

    // Audio playback
    private var audioTrack: AudioTrack? = null
    private var generatedAudioData: ByteArray? = null
    private var playbackJob: Job? = null

    // System TTS playback
    private var systemTts: TextToSpeech? = null
    private var systemTtsInit: CompletableDeferred<Boolean>? = null

    init {
        Log.i(TAG, "Initializing TTS ViewModel...")

        // Subscribe to SDK events for TTS model state
        viewModelScope.launch {
            EventBus.events.collect { event ->
                // Handle TTS-specific events
                if (event is TTSEvent) {
                    handleTTSEvent(event)
                }
                // Handle model events with TTS category
                if (event is ModelEvent && event.category == EventCategory.TTS) {
                    handleModelEvent(event)
                }
            }
        }

        // Check initial TTS state
        updateTTSState()
    }

    /**
     * Handle TTS events from SDK EventBus
     * iOS Reference: Event subscription in TTSViewModel
     */
    private fun handleTTSEvent(event: TTSEvent) {
        when (event.eventType) {
            TTSEvent.TTSEventType.SYNTHESIS_STARTED -> {
                Log.d(TAG, "Synthesis started")
            }
            TTSEvent.TTSEventType.SYNTHESIS_COMPLETED -> {
                Log.i(TAG, "Synthesis completed: ${event.durationMs}ms")
            }
            TTSEvent.TTSEventType.SYNTHESIS_FAILED -> {
                Log.e(TAG, "Synthesis failed: ${event.error}")
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        errorMessage = "Synthesis failed: ${event.error}",
                    )
                }
            }
            TTSEvent.TTSEventType.PLAYBACK_STARTED -> {
                Log.d(TAG, "Playback started")
            }
            TTSEvent.TTSEventType.PLAYBACK_COMPLETED -> {
                Log.d(TAG, "Playback completed")
            }
        }
    }

    /**
     * Handle model events for TTS
     */
    private fun handleModelEvent(event: ModelEvent) {
        when (event.eventType) {
            ModelEvent.ModelEventType.LOADED -> {
                Log.i(TAG, "✅ TTS model loaded: ${event.modelId}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelId = event.modelId,
                        selectedModelName = event.modelId,
                    )
                }
                // Shuffle sample text when model is first loaded
                shuffleSampleText()
            }
            ModelEvent.ModelEventType.UNLOADED -> {
                Log.d(TAG, "TTS model unloaded: ${event.modelId}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = false,
                        selectedModelId = null,
                        selectedModelName = null,
                    )
                }
            }
            ModelEvent.ModelEventType.DOWNLOAD_STARTED -> {
                Log.d(TAG, "TTS model download started: ${event.modelId}")
            }
            ModelEvent.ModelEventType.DOWNLOAD_COMPLETED -> {
                Log.d(TAG, "TTS model download completed: ${event.modelId}")
            }
            ModelEvent.ModelEventType.DOWNLOAD_FAILED -> {
                Log.e(TAG, "TTS model download failed: ${event.modelId} - ${event.error}")
                _uiState.update {
                    it.copy(
                        errorMessage = "Download failed: ${event.error}",
                    )
                }
            }
            else -> { /* Other events not relevant for TTS state */ }
        }
    }

    /**
     * Update TTS state from SDK
     */
    private fun updateTTSState() {
        val isLoaded = RunAnywhere.isTTSVoiceLoadedSync
        val voiceId = RunAnywhere.currentTTSVoiceId

        _uiState.update {
            it.copy(
                isModelLoaded = isLoaded,
                selectedModelId = voiceId,
                selectedModelName = voiceId,
            )
        }
    }

    /**
     * Load a TTS voice
     * iOS Reference: loadVoice() in TTSViewModel
     */
    fun loadVoice(voiceId: String) {
        viewModelScope.launch {
            try {
                Log.i(TAG, "Loading TTS voice: $voiceId")
                RunAnywhere.loadTTSVoice(voiceId)
                updateTTSState()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load TTS voice: ${e.message}", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to load voice: ${e.message}")
                }
            }
        }
    }

    /**
     * Called when a model is loaded from the ModelSelectionBottomSheet
     * This explicitly updates the ViewModel state when a model is selected and loaded
     */
    fun onModelLoaded(
        modelName: String,
        modelId: String,
        framework: InferenceFramework?,
    ) {
        Log.i(TAG, "Model loaded notification: $modelName (id: $modelId, framework: ${framework?.displayName})")

        val isSystem = modelId == SYSTEM_TTS_MODEL_ID || framework == InferenceFramework.SYSTEM_TTS

        _uiState.update {
            it.copy(
                isModelLoaded = true,
                selectedModelName = modelName,
                selectedModelId = modelId,
                selectedFramework = framework,
                isSystemTTS = isSystem,
                errorMessage = null,
            )
        }

        // Shuffle sample text when model is loaded
        shuffleSampleText()
    }

    /**
     * Initialize the TTS ViewModel
     * iOS Reference: initialize() in TTSViewModel
     */
    fun initialize() {
        Log.i(TAG, "Initializing TTS ViewModel...")
        updateTTSState()
    }

    /**
     * Update the input text for TTS
     */
    fun updateInputText(text: String) {
        _uiState.update {
            it.copy(
                inputText = text,
                characterCount = text.length,
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
                characterCount = newText.length,
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
     * Generate speech from text via RunAnywhere SDK
     * iOS Reference: generateSpeech(text:) in TTSViewModel
     */
    fun generateSpeech() {
        viewModelScope.launch {
            val text = _uiState.value.inputText
            if (text.isEmpty()) return@launch

            val isSystem = _uiState.value.isSystemTTS
            if (!isSystem && !RunAnywhere.isTTSVoiceLoadedSync) {
                _uiState.update {
                    it.copy(errorMessage = "No TTS model loaded. Please select a voice first.")
                }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isGenerating = !isSystem,
                    isSpeaking = isSystem,
                    hasGeneratedAudio = false,
                    errorMessage = null,
                )
            }

            try {
                Log.i(TAG, "Generating speech for text: ${text.take(50)}...")

                val startTime = System.currentTimeMillis()

                // Create TTS options with current settings
                val options =
                    TTSOptions(
                        voice = _uiState.value.selectedModelId,
                        language = "en-US",
                        rate = _uiState.value.speed,
                        pitch = _uiState.value.pitch,
                        volume = 1.0f,
                    )

                if (isSystem) {
                    speakSystemTts(text, options)
                    val processingTime = System.currentTimeMillis() - startTime
                    _uiState.update {
                        it.copy(
                            isGenerating = false,
                            isSpeaking = false,
                            audioDuration = null,
                            audioSize = null,
                            sampleRate = null,
                            processingTimeMs = processingTime,
                        )
                    }
                } else {
                    // Use RunAnywhere.synthesize() via SDK extension function
                    val result =
                        withContext(Dispatchers.IO) {
                            RunAnywhere.synthesize(text, options)
                        }

                    val processingTime = System.currentTimeMillis() - startTime

                    if (result.audioData.isEmpty()) {
                        Log.i(TAG, "TTS synthesis returned empty audio")
                        _uiState.update {
                            it.copy(
                                isGenerating = false,
                                isSpeaking = false,
                                audioDuration = result.duration,
                                audioSize = null,
                                sampleRate = null,
                                processingTimeMs = processingTime,
                            )
                        }
                    } else {
                        // ONNX/Piper TTS returns audio data for playback
                        Log.i(TAG, "✅ Speech generation complete: ${result.audioData.size} bytes, duration: ${result.duration}s")

                        generatedAudioData = result.audioData

                        _uiState.update {
                            it.copy(
                                isGenerating = false,
                                isSpeaking = false,
                                hasGeneratedAudio = true,
                                audioDuration = result.duration,
                                audioSize = result.audioData.size,
                                sampleRate = null,
                                processingTimeMs = processingTime,
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Speech generation failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        isSpeaking = false,
                        errorMessage = "Speech generation failed: ${e.message}",
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

        playbackJob =
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    // Parse WAV header to get audio parameters
                    val sampleRate = _uiState.value.sampleRate ?: 22050
                    val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                    val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                    // Skip WAV header (44 bytes) if present
                    val headerSize =
                        if (audioData.size > 44 &&
                            audioData[0] == 'R'.code.toByte() &&
                            audioData[1] == 'I'.code.toByte() &&
                            audioData[2] == 'F'.code.toByte() &&
                            audioData[3] == 'F'.code.toByte()
                        ) {
                            44
                        } else {
                            0
                        }

                    val pcmData = audioData.copyOfRange(headerSize, audioData.size)

                    val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)

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
                                    .setSampleRate(sampleRate)
                                    .setChannelMask(channelConfig)
                                    .build(),
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
                                    playbackProgress = (currentTime / duration).coerceIn(0.0, 1.0),
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
                                errorMessage = "Playback failed: ${e.message}",
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
                playbackProgress = 0.0,
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

    /**
     * Stop current synthesis
     */
    fun stopSynthesis() {
        viewModelScope.launch {
            RunAnywhere.stopSynthesis()
        }
        systemTts?.stop()
        _uiState.update { it.copy(isGenerating = false, isSpeaking = false) }
    }

    override fun onCleared() {
        super.onCleared()
        Log.i(TAG, "ViewModel cleared, cleaning up resources")
        stopPlayback()
        generatedAudioData = null
        systemTts?.shutdown()
        systemTts = null
        systemTtsInit = null
    }

    private suspend fun speakSystemTts(
        text: String,
        options: TTSOptions,
    ) {
        val ready = ensureSystemTtsReady()
        if (!ready) {
            throw IllegalStateException("System TTS not available")
        }

        withContext(Dispatchers.Main) {
            val tts = systemTts ?: throw IllegalStateException("System TTS not initialized")
            val locale = Locale.forLanguageTag(options.language.ifBlank { "en-US" })
            tts.language = locale
            tts.setSpeechRate(options.rate)
            tts.setPitch(options.pitch)
        }

        suspendCancellableCoroutine { continuation ->
            val tts = systemTts
            if (tts == null) {
                continuation.resumeWithException(IllegalStateException("System TTS not initialized"))
                return@suspendCancellableCoroutine
            }

            val utteranceId = "system-tts-${System.currentTimeMillis()}"
            tts.setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        Log.d(TAG, "System TTS started")
                    }

                    override fun onDone(utteranceId: String?) {
                        if (continuation.isActive) {
                            continuation.resume(Unit)
                        }
                    }

                    override fun onError(utteranceId: String?) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(IllegalStateException("System TTS error"))
                        }
                    }

                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        if (continuation.isActive) {
                            if (interrupted) {
                                continuation.resume(Unit)
                            } else {
                                continuation.resumeWithException(IllegalStateException("System TTS stopped"))
                            }
                        }
                    }
                },
            )

            val result =
                tts.speak(
                    text,
                    TextToSpeech.QUEUE_FLUSH,
                    null,
                    utteranceId,
                )
            if (result != TextToSpeech.SUCCESS) {
                continuation.resumeWithException(IllegalStateException("System TTS speak failed"))
            }
        }
    }

    private suspend fun ensureSystemTtsReady(): Boolean {
        val deferred =
            systemTtsInit
                ?: CompletableDeferred<Boolean>().also { init ->
                    systemTtsInit = init
                    withContext(Dispatchers.Main) {
                        systemTts =
                            TextToSpeech(getApplication()) { status ->
                                val ready = status == TextToSpeech.SUCCESS
                                if (ready) {
                                    init.complete(true)
                                } else {
                                    systemTts?.shutdown()
                                    systemTts = null
                                    systemTtsInit = null
                                    init.complete(false)
                                }
                            }
                    }
                }

        return deferred.await()
    }
}
