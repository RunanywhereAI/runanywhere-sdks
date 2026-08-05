package com.runanywhere.runanywhereai.ui.screens.voice

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.ui.screens.stt.AudioRecorder
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.AgentState
import com.runanywhere.sdk.public.api.AudioInput
import com.runanywhere.sdk.public.api.GenerationEvent
import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.ModelRef
import com.runanywhere.sdk.public.api.TokenKind
import com.runanywhere.sdk.public.api.TtsOptions
import com.runanywhere.sdk.public.api.VoiceEvent
import com.runanywhere.sdk.public.api.VoiceSession
import com.runanywhere.sdk.public.api.llm
import com.runanywhere.sdk.public.api.models
import com.runanywhere.sdk.public.api.stt
import com.runanywhere.sdk.public.api.tts
import com.runanywhere.sdk.public.api.voice
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.coroutines.cancellation.CancellationException

enum class VoiceState { IDLE, STARTING, LISTENING, TRANSCRIBING, THINKING, SPEAKING }

data class VoiceTurn(val text: String, val isUser: Boolean)

class VoiceViewModel : ViewModel() {

    var state by mutableStateOf(VoiceState.IDLE)
        private set
    val turns = mutableStateListOf<VoiceTurn>()
    var error by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null
    private var cleanupJob: Job? = null
    private var assistantTurnIndex: Int? = null
    private var session: VoiceSession? = null

    // NPU per-turn-swap path: a single-slot Hexagon NPU cannot hold the STT and the chat LLM at once, so
    // the shared voice-agent (which requires all components co-resident) can't run there. When both the
    // recognizer and the chat model are QHexRT we drive the turn manually — record -> transcribe (loads
    // Whisper) -> generate (loads the LLM) -> speak (system TTS, memory-independent) — swapping the one NPU
    // slot per phase. Push-to-talk: tap to record, tap to send. Non-NPU pipelines keep the co-resident
    // streaming agent untouched (this branch is engine-scoped, no commons change).
    private val recorder = AudioRecorder()
    private val pcm = ByteArrayOutputStream()
    private var sttModel: RAModelInfo? = null
    private var llmModel: RAModelInfo? = null
    private var ttsModel: RAModelInfo? = null
    private var useNpuSwap = false

    /** Called by VoiceScreen with the currently-selected components so the mic can swap them per turn. */
    fun setPipeline(stt: RAModelInfo?, llm: RAModelInfo?, tts: RAModelInfo?) {
        sttModel = stt
        llmModel = llm
        ttsModel = tts
        useNpuSwap = stt?.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT &&
            llm?.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
    }

    private fun isNpu(m: RAModelInfo?) = m?.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT

    fun toggle() {
        if (useNpuSwap) {
            when (state) {
                VoiceState.IDLE -> startRecordingNpu()
                VoiceState.LISTENING -> stopAndProcessNpu()
                else -> Unit // busy transcribing/thinking/speaking — ignore taps
            }
            return
        }
        when (state) {
            VoiceState.IDLE -> startConversation()
            else -> stop()
        }
    }

    private fun startConversation() {
        job?.cancel()
        error = null
        val pendingCleanup = cleanupJob
        job = viewModelScope.launch {
            try {
                // A previous session may still be returning from a blocking
                // native turn. Never open a new one until it has closed.
                pendingCleanup?.join()
                state = VoiceState.STARTING
                val stt = sttModel ?: error("Choose a speech-recognition model first.")
                val llm = llmModel ?: error("Choose a chat model first.")
                val tts = ttsModel ?: error("Choose a voice first.")
                // The session downloads and loads its own models and ensures a VAD.
                val opened = RunAnywhere.voice.createSession(
                    stt = ModelRef(stt.id),
                    llm = ModelRef(llm.id),
                    tts = ModelRef(tts.id),
                    generation = voiceGenOptions(),
                )
                session = opened
                state = VoiceState.LISTENING
                opened.start()
                opened.events.collect(::handleEvent)
            } catch (e: CancellationException) {
                // User-driven stop cancels the collector; leave the UI in the stopped state.
            } catch (e: Exception) {
                RACLog.e("voice agent failed", e)
                error = e.message ?: "Something went wrong"
                state = VoiceState.IDLE
            }
        }
    }

    private fun startRecordingNpu() {
        error = null
        pcm.reset()
        try {
            recorder.start(
                onChunk = { chunk, _ -> synchronized(pcm) { pcm.write(chunk) } },
                onError = { e -> viewModelScope.launch { error = e.message ?: "Microphone failed"; state = VoiceState.IDLE } },
            )
            state = VoiceState.LISTENING
        } catch (e: Exception) {
            error = e.message ?: "Microphone failed"
            state = VoiceState.IDLE
        }
    }

    private fun stopAndProcessNpu() {
        recorder.stop()
        val audio = synchronized(pcm) { pcm.toByteArray() }
        processNpuTurn(audio)
    }

    private fun processNpuTurn(audio: ByteArray) {
        val stt = sttModel
        val llm = llmModel
        if (stt == null || llm == null) { error = "Voice models not selected"; state = VoiceState.IDLE; return }
        // Ignore <~0.5s of 16-bit PCM @16k (a stray tap with no speech).
        if (audio.size < AudioRecorder.SAMPLE_RATE) { state = VoiceState.IDLE; return }
        job?.cancel()
        job = viewModelScope.launch {
            try {
                // 1. Load Whisper (evicts the LLM on the single NPU slot) and transcribe the recording.
                state = VoiceState.TRANSCRIBING
                RunAnywhere.models.load(stt.id)
                val transcript = RunAnywhere.stt
                    .transcribe(AudioInput.pcm16(audio, AudioRecorder.SAMPLE_RATE))
                    .text
                    .trim()
                if (transcript.isBlank()) { state = VoiceState.IDLE; return@launch }
                turns += VoiceTurn(transcript, isUser = true)
                assistantTurnIndex = null
                // 2. Load the chat LLM (evicts Whisper) and produce the reply.
                state = VoiceState.THINKING
                RunAnywhere.models.load(llm.id)
                // 3. Speak. Two regimes, forced by the single Hexagon slot:
                //    - A system/platform TTS runs on the CPU, so it plays WHILE the NPU LLM keeps
                //      generating -> true streaming: each sentence is spoken the moment it lands.
                //    - An NPU TTS (e.g. MeloTTS) shares the one slot with the LLM, so it can only load
                //      AFTER generation finishes; we then speak the reply sentence-by-sentence (short
                //      chunks stay under MeloTTS's 512-phoneme cap that was throwing the -130).
                val tts = ttsModel
                if (tts != null && !isNpu(tts)) streamingTurn(transcript)
                else bufferedTurn(transcript, tts)
                state = VoiceState.IDLE
            } catch (e: CancellationException) {
                // user-driven stop
            } catch (e: Exception) {
                RACLog.e("npu voice turn failed", e)
                error = e.message ?: "Something went wrong"
                state = VoiceState.IDLE
            }
        }
    }

    // Non-NPU TTS (system/platform): the LLM stays resident while a CPU TTS plays, so speak each
    // sentence as it streams out of the model. A single consumer coroutine pulls finished sentences
    // off an unbounded channel and speaks them in order (each speak() blocks until its own audio
    // finishes, so back-to-back calls never clip one another).
    private suspend fun streamingTurn(prompt: String) = coroutineScope {
        val chunks = Channel<String>(Channel.UNLIMITED)
        val speaker = launch(Dispatchers.IO) {
            for (chunk in chunks) speakChunk(chunk)
        }
        val buf = StringBuilder()
        var speaking = false
        suspend fun emit(sentences: List<String>) {
            for (s in sentences) {
                if (!speaking) { speaking = true; state = VoiceState.SPEAKING }
                chunks.send(s)
            }
        }
        RunAnywhere.llm.generateStream(prompt, voiceGenOptions()).collect { ev ->
            if (ev is GenerationEvent.TextDelta && ev.text.isNotEmpty()) {
                appendAssistantToken(ev.text)
                buf.append(ev.text)
                emit(VoiceTtsChunkPolicy.drainSentences(buf, flush = false))
            }
        }
        emit(VoiceTtsChunkPolicy.drainSentences(buf, flush = true))
        chunks.close()
        speaker.join()
    }

    // NPU TTS (or no TTS): the LLM must fully finish before the TTS can take the slot. Accumulate the
    // whole reply, then (loading the NPU TTS if needed) speak it sentence-by-sentence.
    private suspend fun bufferedTurn(prompt: String, tts: RAModelInfo?) {
        val sb = StringBuilder()
        RunAnywhere.llm.generateStream(prompt, voiceGenOptions()).collect { ev ->
            if (ev is GenerationEvent.TextDelta && ev.text.isNotEmpty()) {
                sb.append(ev.text)
                appendAssistantToken(ev.text)
            }
        }
        val buf = StringBuilder(sb)
        val sentences = VoiceTtsChunkPolicy.drainSentences(buf, flush = true)
        if (sentences.isEmpty() || tts == null) return
        state = VoiceState.SPEAKING
        if (isNpu(tts)) RunAnywhere.models.load(tts.id)
        for (chunk in sentences) speakChunk(chunk)
    }

    private fun voiceGenOptions() =
        LlmOptions(
            maxOutputTokens = 200,
            temperature = 0.7f,
            topP = 0.95f,
            // Same persona as chat so the small on-device models use conversation context instead of
            // defaulting to a defensive "I don't have personal information" refusal.
            systemPrompt = SettingsRepository.settings.systemPrompt.ifBlank { null },
        )

    private fun ttsOptions() = TtsOptions(language = "en-US", speed = 1f)

    // Speak one chunk, hard-splitting anything longer than the engine can take and skipping
    // blank/symbol-only text (an empty phoneme sequence also fails synthesis). A single failed chunk
    // is logged and skipped, never aborting the turn.
    private suspend fun speakChunk(text: String) {
        for (piece in VoiceTtsChunkPolicy.capForTts(text)) {
            if (piece.isBlank()) continue
            try {
                RunAnywhere.tts.speak(piece, ttsOptions())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.w("tts chunk failed: ${e.message}")
            }
        }
    }

    fun stop() {
        if (useNpuSwap) {
            recorder.stop()
            job?.cancel(); job = null
            assistantTurnIndex = null
            viewModelScope.launch { runCatching { RunAnywhere.tts.stop() } }
            state = VoiceState.IDLE
            return
        }
        val sessionJob = job
        sessionJob?.cancel()
        job = null
        assistantTurnIndex = null
        state = VoiceState.IDLE
        val previousCleanup = cleanupJob
        val openSession = session
        session = null
        cleanupJob = viewModelScope.launch(Dispatchers.IO) {
            // close() joins the session's mic driver, so cleanup cannot race an
            // active feed call.
            sessionJob?.join()
            previousCleanup?.join()
            runCatching { openSession?.close() }
                .onFailure { RACLog.w("voice session close failed: ${it.message}") }
        }
    }

    fun clear() {
        stop()
        turns.clear()
        error = null
    }

    private fun handleEvent(event: VoiceEvent) {
        when (event) {
            is VoiceEvent.UserTranscribed -> {
                val text = event.text.trim()
                if (event.isFinal && text.isNotBlank()) {
                    turns += VoiceTurn(text, isUser = true)
                    assistantTurnIndex = null
                }
            }
            is VoiceEvent.AgentStateChanged ->
                state = when (event.state) {
                    AgentState.LISTENING -> VoiceState.LISTENING
                    AgentState.THINKING -> VoiceState.THINKING
                    AgentState.SPEAKING -> VoiceState.SPEAKING
                }
            is VoiceEvent.AgentResponse -> {
                state = VoiceState.THINKING
                appendAssistantToken(event.text)
            }
            is VoiceEvent.SpeechStarted -> state = VoiceState.LISTENING
            is VoiceEvent.SpeechEnded -> state = VoiceState.TRANSCRIBING
            is VoiceEvent.Error -> {
                error = event.message
                if (!event.recoverable) state = VoiceState.IDLE
            }
        }
    }

    private fun appendAssistantToken(token: String) {
        val index = ensureAssistantTurn()
        turns[index] = turns[index].copy(text = turns[index].text + token)
    }

    private fun ensureAssistantTurn(): Int {
        assistantTurnIndex?.let { if (it in turns.indices) return it }
        turns += VoiceTurn("", isUser = false)
        return turns.lastIndex.also { assistantTurnIndex = it }
    }

    override fun onCleared() {
        stop()
    }
}
