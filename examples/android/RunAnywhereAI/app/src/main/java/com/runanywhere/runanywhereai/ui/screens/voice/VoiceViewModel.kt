package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.ThinkingTagPattern
import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.stt.AudioRecorder
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.runanywhereai.util.ThinkingParser
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RATTSOptions
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException

enum class VoiceState { IDLE, LISTENING, TRANSCRIBING, THINKING, SPEAKING }

data class VoiceTurn(val text: String, val isUser: Boolean)

class VoiceViewModel(application: Application) : AndroidViewModel(application) {

    var state by mutableStateOf(VoiceState.IDLE)
        private set
    val turns = mutableStateListOf<VoiceTurn>()
    var error by mutableStateOf<String?>(null)
        private set

    private val recorder = AudioRecorder()
    private val buffer = ByteArrayOutputStream()
    private var job: Job? = null
    private var systemTts: TextToSpeech? = null
    private var ttsVoice: RAModelInfo? = null

    fun toggle(ttsVoice: RAModelInfo?) {
        this.ttsVoice = ttsVoice
        when (state) {
            VoiceState.IDLE -> startListening()
            VoiceState.LISTENING -> stopAndRun()
            else -> stop()
        }
    }

    private fun startListening() {
        error = null
        synchronized(buffer) { buffer.reset() }
        state = VoiceState.LISTENING
        recorder.start { chunk, _ -> synchronized(buffer) { buffer.write(chunk) } }
    }

    private fun stopAndRun() {
        recorder.stop()
        val audio = synchronized(buffer) { val bytes = buffer.toByteArray(); buffer.reset(); bytes }
        if (audio.size < MIN_BYTES) {
            state = VoiceState.IDLE
            return
        }
        job = viewModelScope.launch {
            try {
                state = VoiceState.TRANSCRIBING
                val userText = RunAnywhere.transcribe(
                    audio,
                    RASTTOptions(language = STTLanguage.STT_LANGUAGE_EN, enable_punctuation = true),
                ).text.trim()
                if (userText.isBlank()) {
                    state = VoiceState.IDLE
                    return@launch
                }
                turns += VoiceTurn(userText, isUser = true)

                state = VoiceState.THINKING
                val replyIndex = turns.size
                turns += VoiceTurn("", isUser = false)
                val raw = StringBuilder()
                val options = RALLMGenerationOptions(
                    max_tokens = 400,
                    temperature = 0.7f,
                    system_prompt = VOICE_SYSTEM_PROMPT,
                    thinking_pattern = ThinkingTagPattern(open_tag = "<think>", close_tag = "</think>"),
                )
                RunAnywhere.generateStream(userText, options).collect { event ->
                    if (event.is_final) return@collect
                    if (event.token.isNotEmpty()) {
                        raw.append(event.token)
                        turns[replyIndex] = turns[replyIndex].copy(text = ThinkingParser.parse(raw.toString()).text)
                    }
                }
                val reply = ThinkingParser.parse(raw.toString()).text.trim()
                turns[replyIndex] = turns[replyIndex].copy(text = reply)

                if (reply.isNotBlank()) {
                    state = VoiceState.SPEAKING
                    runSpeak(reply)
                }
                state = VoiceState.IDLE
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("voice pipeline failed", e)
                error = e.message ?: "Something went wrong"
                state = VoiceState.IDLE
            }
        }
    }

    fun stop() {
        job?.cancel()
        recorder.stop()
        systemTts?.stop()
        RunAnywhere.cancelGeneration()
        state = VoiceState.IDLE
    }

    fun clear() {
        stop()
        turns.clear()
        error = null
    }

    private suspend fun runSpeak(text: String) {
        val voice = ttsVoice
        val useSystem = voice == null ||
            voice.id == "system-tts" ||
            voice.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
        if (useSystem) {
            speakSystem(text)
        } else {
            runCatching {
                RunAnywhere.speak(text, RATTSOptions(language_code = "en-US", speaking_rate = 1f, volume = 1f))
            }.onFailure {
                RACLog.w("voice tts failed, using system: ${it.message}")
                speakSystem(text)
            }
        }
    }

    private suspend fun speakSystem(text: String) {
        val tts = ensureSystemTts()
        withContext(Dispatchers.Main) {
            tts.language = Locale.getDefault()
        }
        suspendCancellableCoroutine { cont ->
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) {
                    if (cont.isActive) cont.resumeWith(Result.success(Unit))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    if (cont.isActive) cont.resumeWith(Result.success(Unit))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    if (cont.isActive) cont.resumeWith(Result.success(Unit))
                }
            })
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "rac-voice")
            cont.invokeOnCancellation { tts.stop() }
        }
    }

    private suspend fun ensureSystemTts(): TextToSpeech {
        systemTts?.let { return it }
        val ready = CompletableDeferred<Boolean>()
        val tts = TextToSpeech(getApplication()) { status -> ready.complete(status == TextToSpeech.SUCCESS) }
        if (!ready.await()) {
            tts.shutdown()
            throw IllegalStateException("System TTS unavailable")
        }
        systemTts = tts
        return tts
    }

    override fun onCleared() {
        job?.cancel()
        recorder.stop()
        systemTts?.shutdown()
    }

    private companion object {
        const val MIN_BYTES = 16000
        const val VOICE_SYSTEM_PROMPT =
            "You are a friendly voice assistant. Answer in one or two short, conversational sentences."
    }
}
