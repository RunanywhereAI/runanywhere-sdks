package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.models.TTSEvent
import com.runanywhere.runanywhereai.models.TTSUiState
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.events.TTSEvent as SDKTTSEvent
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.currentTTSVoiceId
import com.runanywhere.sdk.public.extensions.isTTSVoiceLoadedSync
import com.runanywhere.sdk.public.extensions.stopSynthesis
import com.runanywhere.sdk.public.extensions.synthesize
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val SYSTEM_TTS_MODEL_ID = "system-tts"

/** Funny sample texts for TTS demo (matches iOS). */
private val funnyTTSSampleTexts = listOf(
    "I'm not saying I'm Batman, but have you ever seen me and Batman in the same room?",
    "According to my calculations, I should have been a millionaire by now. My calculations were wrong.",
    "I told my computer I needed a break, and now it won't stop sending me vacation ads.",
    "Why do programmers prefer dark mode? Because light attracts bugs!",
    "I speak fluent sarcasm. Unfortunately, my phone's voice assistant doesn't.",
    "My brain has too many tabs open and I can't find the one playing music.",
    "I put my phone on airplane mode but it didn't fly. Worst paper airplane ever.",
    "I'm not lazy, I'm just on energy-saving mode. Like a responsible gadget.",
    "Coffee: because adulting is hard and mornings are a cruel joke.",
    "My wallet is like an onion. When I open it, I cry.",
    "Behind every great person is a cat judging them silently.",
    "RunAnywhere: because your AI should work even when your WiFi doesn't.",
    "On-device AI means your voice data stays on your phone. Unlike your ex, we respect privacy.",
    "Our SDK is so fast, it finished processing before you finished reading this sentence.",
    "Voice AI that runs offline? That's not magic, that's just good engineering. Okay, maybe a little magic.",
)

private fun getRandomSampleText(): String = funnyTTSSampleTexts.random()

class TTSViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "TTSViewModel"
    }

    // Start in Ready immediately with a random sample text — no loading spinner
    private val initialText = getRandomSampleText()

    private val _uiState = MutableStateFlow<TTSUiState>(
        TTSUiState.Ready(inputText = initialText, characterCount = initialText.length),
    )
    val uiState: StateFlow<TTSUiState> = _uiState.asStateFlow()

    private val _events = Channel<TTSEvent>(Channel.BUFFERED)
    val events: Flow<TTSEvent> = _events.receiveAsFlow()

    // Audio playback
    private var audioTrack: AudioTrack? = null
    private var generatedAudioData: ByteArray? = null
    private var playbackJob: Job? = null

    // System TTS
    private var systemTts: TextToSpeech? = null
    private var systemTtsInit: CompletableDeferred<Boolean>? = null

    init {
        subscribeToEvents()
        checkInitialTTSState()
    }

    private fun subscribeToEvents() {
        viewModelScope.launch {
            EventBus.events.collect { event ->
                when (event) {
                    is SDKTTSEvent -> handleSDKTTSEvent(event)
                    is ModelEvent -> {
                        if (event.category == EventCategory.TTS) handleModelEvent(event)
                    }
                    else -> { /* ignore */ }
                }
            }
        }
    }

    private fun handleSDKTTSEvent(event: SDKTTSEvent) {
        when (event.eventType) {
            SDKTTSEvent.TTSEventType.SYNTHESIS_FAILED -> {
                Log.e(TAG, "Synthesis failed: ${event.error}")
                updateReady { copy(isGenerating = false, error = "Synthesis failed: ${event.error}") }
            }
            else -> { /* STARTED, COMPLETED, PLAYBACK events logged only */ }
        }
    }

    private fun handleModelEvent(event: ModelEvent) {
        when (event.eventType) {
            ModelEvent.ModelEventType.LOADED -> {
                Log.i(TAG, "TTS model loaded: ${event.modelId}")
                updateReady {
                    copy(isModelLoaded = true, selectedModelId = event.modelId, selectedModelName = event.modelId)
                }
                shuffleSampleText()
            }
            ModelEvent.ModelEventType.UNLOADED -> {
                updateReady { copy(isModelLoaded = false, selectedModelId = null, selectedModelName = null) }
            }
            ModelEvent.ModelEventType.DOWNLOAD_FAILED -> {
                updateReady { copy(error = "Download failed: ${event.error}") }
            }
            else -> { /* ignore */ }
        }
    }

    private fun checkInitialTTSState() {
        val isLoaded = RunAnywhere.isTTSVoiceLoadedSync
        val voiceId = RunAnywhere.currentTTSVoiceId
        if (isLoaded) {
            updateReady { copy(isModelLoaded = true, selectedModelId = voiceId, selectedModelName = voiceId) }
        }
    }

    /** Called when a model is loaded from ModelSelectionBottomSheet. */
    fun onModelLoaded(modelName: String, modelId: String, framework: InferenceFramework?) {
        Log.i(TAG, "Model loaded: $modelName (id=$modelId, framework=${framework?.displayName})")
        val isSystem = modelId == SYSTEM_TTS_MODEL_ID || framework == InferenceFramework.SYSTEM_TTS
        updateReady {
            copy(
                isModelLoaded = true,
                selectedModelName = modelName,
                selectedModelId = modelId,
                selectedFramework = framework,
                isSystemTTS = isSystem,
                error = null,
            )
        }
        shuffleSampleText()
    }

    fun updateInputText(text: String) {
        updateReady { copy(inputText = text, characterCount = text.length) }
    }

    fun shuffleSampleText() {
        val newText = getRandomSampleText()
        updateReady { copy(inputText = newText, characterCount = newText.length) }
    }

    fun updateSpeed(speed: Float) {
        updateReady { copy(speed = speed) }
    }

    /** Generate speech from text via RunAnywhere SDK. */
    fun generateSpeech() {
        viewModelScope.launch {
            val state = (_uiState.value as? TTSUiState.Ready) ?: return@launch
            val text = state.inputText
            if (text.isEmpty()) return@launch

            val isSystem = state.isSystemTTS
            if (!isSystem && !RunAnywhere.isTTSVoiceLoadedSync) {
                updateReady { copy(error = "No TTS model loaded. Please select a voice first.") }
                return@launch
            }

            updateReady {
                copy(isGenerating = !isSystem, isSpeaking = isSystem, hasGeneratedAudio = false, error = null)
            }

            try {
                val options = TTSOptions(
                    voice = state.selectedModelId,
                    language = "en-US",
                    rate = state.speed,
                    pitch = 1.0f,
                    volume = 1.0f,
                )

                if (isSystem) {
                    speakSystemTts(text, options)
                    updateReady { copy(isGenerating = false, isSpeaking = false) }
                } else {
                    val result = withContext(Dispatchers.IO) { RunAnywhere.synthesize(text, options) }

                    if (result.audioData.isEmpty()) {
                        updateReady {
                            copy(isGenerating = false, isSpeaking = false, audioDuration = result.duration)
                        }
                    } else {
                        Log.i(TAG, "Speech generated: ${result.audioData.size} bytes, ${result.duration}s")
                        generatedAudioData = result.audioData
                        updateReady {
                            copy(
                                isGenerating = false,
                                isSpeaking = false,
                                hasGeneratedAudio = true,
                                audioDuration = result.duration,
                                audioSize = result.audioData.size,
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Speech generation failed", e)
                updateReady {
                    copy(isGenerating = false, isSpeaking = false, error = "Speech generation failed: ${e.message}")
                }
            }
        }
    }

    fun togglePlayback() {
        val state = (_uiState.value as? TTSUiState.Ready) ?: return
        if (state.isPlaying) stopPlayback() else startPlayback()
    }

    private fun startPlayback() {
        val audioData = generatedAudioData
        if (audioData == null || audioData.isEmpty()) return

        updateReady { copy(isPlaying = true) }

        playbackJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                // Parse WAV header
                val isWav = audioData.size > 44 &&
                    audioData[0] == 'R'.code.toByte() &&
                    audioData[1] == 'I'.code.toByte() &&
                    audioData[2] == 'F'.code.toByte() &&
                    audioData[3] == 'F'.code.toByte()

                val sampleRate: Int
                val pcmOffset: Int

                if (isWav) {
                    sampleRate = (audioData[24].toInt() and 0xFF) or
                        ((audioData[25].toInt() and 0xFF) shl 8) or
                        ((audioData[26].toInt() and 0xFF) shl 16) or
                        ((audioData[27].toInt() and 0xFF) shl 24)

                    var offset = 12
                    var dataStart = -1
                    while (offset + 8 <= audioData.size) {
                        val chunkId = String(audioData, offset, 4, Charsets.US_ASCII)
                        val chunkSize = (audioData[offset + 4].toInt() and 0xFF) or
                            ((audioData[offset + 5].toInt() and 0xFF) shl 8) or
                            ((audioData[offset + 6].toInt() and 0xFF) shl 16) or
                            ((audioData[offset + 7].toInt() and 0xFF) shl 24)
                        if (chunkId == "data") {
                            dataStart = offset + 8
                            break
                        }
                        offset += 8 + chunkSize
                    }
                    pcmOffset = if (dataStart > 0) dataStart else 44
                } else {
                    sampleRate = 22050
                    pcmOffset = 0
                }

                val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                val audioFormat = AudioFormat.ENCODING_PCM_16BIT
                val pcmData = audioData.copyOfRange(pcmOffset, audioData.size)
                val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)

                audioTrack = AudioTrack.Builder()
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

                val duration = (_uiState.value as? TTSUiState.Ready)?.audioDuration
                    ?: (pcmData.size.toDouble() / (sampleRate * 2))
                var currentTime = 0.0

                while ((_uiState.value as? TTSUiState.Ready)?.isPlaying == true &&
                    audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING
                ) {
                    delay(100)
                    currentTime += 0.1
                    if (currentTime >= duration) break
                    withContext(Dispatchers.Main) {
                        updateReady {
                            copy(
                                currentTime = currentTime,
                                playbackProgress = (currentTime / duration).coerceIn(0.0, 1.0),
                            )
                        }
                    }
                }

                withContext(Dispatchers.Main) { stopPlayback() }
            } catch (e: Exception) {
                Log.e(TAG, "Playback error", e)
                withContext(Dispatchers.Main) {
                    updateReady { copy(isPlaying = false, error = "Playback failed: ${e.message}") }
                }
            }
        }
    }

    private fun stopPlayback() {
        updateReady { copy(isPlaying = false, currentTime = 0.0, playbackProgress = 0.0) }
        playbackJob?.cancel()
        playbackJob = null
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }

    fun stopSynthesis() {
        viewModelScope.launch { RunAnywhere.stopSynthesis() }
        systemTts?.stop()
        updateReady { copy(isGenerating = false, isSpeaking = false) }
    }

    override fun onCleared() {
        super.onCleared()
        stopPlayback()
        generatedAudioData = null
        systemTts?.shutdown()
        systemTts = null
        systemTtsInit = null
    }

    // -- System TTS ---------------------------------------------------------------

    private suspend fun speakSystemTts(text: String, options: TTSOptions) {
        val ready = ensureSystemTtsReady()
        if (!ready) throw IllegalStateException("System TTS not available")

        withContext(Dispatchers.Main) {
            val tts = systemTts ?: throw IllegalStateException("System TTS not initialized")
            val locale = Locale.forLanguageTag(options.language.ifBlank { "en-US" })
            tts.language = locale
            tts.setSpeechRate(options.rate)
            tts.setPitch(options.pitch)
        }

        suspendCancellableCoroutine { continuation ->
            val tts = systemTts ?: run {
                continuation.resumeWithException(IllegalStateException("System TTS not initialized"))
                return@suspendCancellableCoroutine
            }
            val utteranceId = "system-tts-${System.currentTimeMillis()}"
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    if (continuation.isActive) continuation.resume(Unit)
                }
                override fun onError(utteranceId: String?) {
                    if (continuation.isActive) continuation.resumeWithException(IllegalStateException("System TTS error"))
                }
                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    if (continuation.isActive) continuation.resume(Unit)
                }
            })
            val result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            if (result != TextToSpeech.SUCCESS) {
                continuation.resumeWithException(IllegalStateException("System TTS speak failed"))
            }
        }
    }

    private suspend fun ensureSystemTtsReady(): Boolean {
        val deferred = systemTtsInit ?: CompletableDeferred<Boolean>().also { init ->
            systemTtsInit = init
            withContext(Dispatchers.Main) {
                systemTts = TextToSpeech(getApplication()) { status ->
                    val ok = status == TextToSpeech.SUCCESS
                    if (!ok) {
                        systemTts?.shutdown()
                        systemTts = null
                        systemTtsInit = null
                    }
                    init.complete(ok)
                }
            }
        }
        return deferred.await()
    }

    // -- Helpers ------------------------------------------------------------------

    private inline fun updateReady(crossinline transform: TTSUiState.Ready.() -> TTSUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is TTSUiState.Ready -> current.transform()
                else -> current
            }
        }
    }
}
