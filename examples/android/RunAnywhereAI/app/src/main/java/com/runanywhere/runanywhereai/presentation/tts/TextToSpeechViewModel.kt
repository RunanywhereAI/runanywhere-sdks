package com.runanywhere.runanywhereai.presentation.tts

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_TTS
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.SDKComponent
import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.extensions.componentLifecycleSnapshot
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.stopSpeaking
import com.runanywhere.sdk.public.extensions.stopSynthesis
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RATTSOptions
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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
 * - Audio playback via RunAnywhere.speak()
 * - Voice settings (speed, pitch)
 *
 * Architecture matches iOS:
 * - Uses RunAnywhere SDK extension functions directly
 * - Model loading via RunAnywhere.loadModel(RAModelLoadRequest)
 * - Event subscription via RunAnywhere.events.events
 */
class TextToSpeechViewModel(
    application: Application,
) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(TTSUiState())
    val uiState: StateFlow<TTSUiState> = _uiState.asStateFlow()

    // Playback driver — `RunAnywhere.speak()` owns synthesis + audio output,
    // so we only need to track the in-flight job for cancellation. The SDK
    // handles raw-audio decoding, sample-rate conversion, output device
    // lifecycle, and playback progress (mirrors iOS TTSViewModel).
    private var playbackJob: Job? = null

    // System TTS playback (Android-only — no cross-platform SDK affordance).
    private var systemTts: TextToSpeech? = null
    private var systemTtsInit: CompletableDeferred<Boolean>? = null

    init {
        Timber.i("Initializing TTS ViewModel...")

        // Subscribe to SDK events for TTS model state
        viewModelScope.launch {
            EventBus.events.collect { event ->
                // Handle model events with TTS category
                if (event.category == EVENT_CATEGORY_TTS) {
                    event.model?.let { handleModelEvent(it) }
                }
            }
        }

        // Check initial TTS state
        viewModelScope.launch { updateTTSState() }
    }

    /**
     * Handle model events for TTS
     */
    private fun handleModelEvent(event: ModelEvent) {
        when (event.kind) {
            ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED -> {
                Timber.i("✅ TTS model loaded: ${event.model_id}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = true,
                        selectedModelId = event.model_id,
                        selectedModelName = event.model_id,
                    )
                }
                // Shuffle sample text when model is first loaded
                shuffleSampleText()
            }
            ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED -> {
                Timber.d("TTS model unloaded: ${event.model_id}")
                _uiState.update {
                    it.copy(
                        isModelLoaded = false,
                        selectedModelId = null,
                        selectedModelName = null,
                    )
                }
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_STARTED -> {
                Timber.d("TTS model download started: ${event.model_id}")
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED -> {
                Timber.d("TTS model download completed: ${event.model_id}")
            }
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED -> {
                Timber.e("TTS model download failed: ${event.model_id} - ${event.error}")
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
     * Update TTS state from SDK via the canonical lifecycle / current-model API.
     */
    private suspend fun updateTTSState() {
        val snapshot = RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_TTS)
        val isLoaded =
            snapshot?.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                snapshot.model_id.isNotEmpty()
        val voiceId =
            RunAnywhere
                .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS))
                .model_id
                .takeIf { it.isNotEmpty() }

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
                Timber.i("Loading TTS voice: $voiceId")
                RunAnywhere.loadModel(
                    RAModelLoadRequest(
                        model_id = voiceId,
                        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                    ),
                )
                updateTTSState()
            } catch (e: Exception) {
                Timber.e(e, "Failed to load TTS voice: ${e.message}")
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
        Timber.i("Model loaded notification: $modelName (id: $modelId, framework: ${framework?.displayName})")

        val isSystem = modelId == SYSTEM_TTS_MODEL_ID || framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

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
        Timber.i("Initializing TTS ViewModel...")
        viewModelScope.launch { updateTTSState() }
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
            val ttsSnapshot = RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_TTS)
            val isTtsLoaded =
                ttsSnapshot?.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    ttsSnapshot.model_id.isNotEmpty()
            if (!isSystem && !isTtsLoaded) {
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
                Timber.i("Generating speech for text: ${text.take(50)}...")

                val startTime = System.currentTimeMillis()

                // Create TTS options with current settings (proto-canonical)
                val options =
                    RATTSOptions(
                        voice = _uiState.value.selectedModelId ?: "",
                        language_code = "en-US",
                        speaking_rate = _uiState.value.speed,
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
                    // Synthesise via the SDK to capture metrics (duration / size /
                    // sample rate) for the Audio Info panel. Playback is a
                    // separate action driven by `RunAnywhere.speak()` (see
                    // startPlayback) so we do not retain the raw audio bytes
                    // here.
                    val result =
                        withContext(Dispatchers.IO) {
                            RunAnywhere.synthesize(text, options)
                        }

                    val processingTime = System.currentTimeMillis() - startTime
                    val audioBytes = result.audio_data.toByteArray()
                    val protoSampleRate =
                        result.sample_rate.takeIf { it > 0 }
                            ?: options.sample_rate.takeIf { it > 0 }
                            ?: 22050
                    Timber.i(
                        "✅ Speech generation complete: ${audioBytes.size} bytes, " +
                            "sample_rate=$protoSampleRate Hz, duration=${(result.duration_ms / 1000.0)}s",
                    )

                    _uiState.update {
                        it.copy(
                            isGenerating = false,
                            isSpeaking = false,
                            hasGeneratedAudio = audioBytes.isNotEmpty(),
                            audioDuration = (result.duration_ms / 1000.0),
                            audioSize = audioBytes.size.takeIf { it > 0 },
                            sampleRate = protoSampleRate.takeIf { audioBytes.isNotEmpty() },
                            processingTimeMs = processingTime,
                        )
                    }
                }
            } catch (e: Exception) {
                Timber.e(e, "Speech generation failed: ${e.message}")
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
     * Toggle audio playback. Delegates to `RunAnywhere.speak()` for the
     * synthesise + play pipeline; iOS routes the same way through
     * `RunAnywhere.speak()` in TTSViewModel.
     */
    fun togglePlayback() {
        if (_uiState.value.isPlaying) {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /**
     * Start audio playback via the SDK. `RunAnywhere.speak()` owns
     * synthesis, encoded-PCM conversion, audio-output wiring, and
     * lifecycle teardown — the example just kicks the call off and
     * surfaces errors.
     */
    private fun startPlayback() {
        val text = _uiState.value.inputText
        if (text.isEmpty()) {
            Timber.w("No text to play")
            return
        }

        Timber.i("Starting SDK playback for ${text.length}-char text")
        _uiState.update { it.copy(isPlaying = true, errorMessage = null) }

        playbackJob =
            viewModelScope.launch {
                try {
                    val options =
                        RATTSOptions(
                            voice = _uiState.value.selectedModelId ?: "",
                            language_code = "en-US",
                            speaking_rate = _uiState.value.speed,
                            pitch = _uiState.value.pitch,
                            volume = 1.0f,
                        )
                    val result =
                        withContext(Dispatchers.IO) {
                            RunAnywhere.speak(text, options)
                        }
                    Timber.i("Speech playback complete: duration=${result.duration_ms}ms")
                } catch (e: Exception) {
                    Timber.e(e, "Playback failed: ${e.message}")
                    _uiState.update {
                        it.copy(errorMessage = "Playback failed: ${e.message}")
                    }
                } finally {
                    _uiState.update { it.copy(isPlaying = false) }
                    playbackJob = null
                }
            }
    }

    /**
     * Stop audio playback. Routes through the SDK so the same path that
     * started playback also tears it down.
     */
    private fun stopPlayback() {
        playbackJob?.cancel()
        playbackJob = null
        viewModelScope.launch { RunAnywhere.stopSpeaking() }
        _uiState.update {
            it.copy(
                isPlaying = false,
                currentTime = 0.0,
                playbackProgress = 0.0,
            )
        }
        Timber.d("Playback stopped")
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
        Timber.i("ViewModel cleared, cleaning up resources")
        stopPlayback()
        systemTts?.shutdown()
        systemTts = null
        systemTtsInit = null
    }

    private suspend fun speakSystemTts(
        text: String,
        options: RATTSOptions,
    ) {
        val ready = ensureSystemTtsReady()
        if (!ready) {
            throw IllegalStateException("System TTS not available")
        }

        withContext(Dispatchers.Main) {
            val tts = systemTts ?: throw IllegalStateException("System TTS not initialized")
            val locale = Locale.forLanguageTag(options.language_code.ifBlank { "en-US" })
            tts.language = locale
            tts.setSpeechRate(options.speaking_rate)
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
                        Timber.d("System TTS started")
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

                    override fun onStop(
                        utteranceId: String?,
                        interrupted: Boolean,
                    ) {
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
