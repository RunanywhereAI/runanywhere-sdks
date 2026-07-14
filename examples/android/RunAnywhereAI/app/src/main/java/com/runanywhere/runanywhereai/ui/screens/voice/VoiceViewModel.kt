package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.TokenKind
import ai.runanywhere.proto.v1.VoiceEvent
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
import com.runanywhere.sdk.public.extensions.cleanupVoiceAgent
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.initializeVoiceAgentWithLoadedModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.stopSpeaking
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RATTSOptions
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
    // Cut sentences on . ! ? followed by whitespace (so "3.14"/"U.S." don't split mid-number).
    private val sentenceSplit = Regex("(?<=[.!?])\\s+")
    // Hard cap per TTS chunk. MeloTTS v79 rejects >512 phonemes (~a couple hundred chars) with the
    // -130 "Text/audio generation failed"; keep each spoken chunk comfortably under that.
    private val maxTtsChars = 160

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
                // A previous Talk collector may still be returning from a
                // blocking native turn. Never reinitialize its handle until
                // capture has stopped and cleanup has completed.
                pendingCleanup?.join()
                state = VoiceState.STARTING
                // The voice agent binds all component handles at initialization.
                // Query each process-wide lifecycle immediately beforehand.
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.STT)
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.LLM)
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.TTS)
                RuntimeModelSelection.queryCurrent(ModelSelectionContext.VAD)
                RunAnywhere.initializeVoiceAgentWithLoadedModels()
                state = VoiceState.LISTENING
                RunAnywhere.streamVoiceAgent().collect(::handleEvent)
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
                withContext(Dispatchers.IO) { RunAnywhere.loadModel(RAModelLoadRequest(model_id = stt.id)) }
                val transcript = RunAnywhere.transcribe(audio).text.trim()
                if (transcript.isBlank()) { state = VoiceState.IDLE; return@launch }
                turns += VoiceTurn(transcript, isUser = true)
                assistantTurnIndex = null
                // 2. Load the chat LLM (evicts Whisper) and produce the reply.
                state = VoiceState.THINKING
                withContext(Dispatchers.IO) { RunAnywhere.loadModel(RAModelLoadRequest(model_id = llm.id)) }
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
        RunAnywhere.generateStream(prompt, voiceGenOptions()).collect { ev ->
            ev.token?.let { tok ->
                if (tok.isEmpty()) return@let
                appendAssistantToken(tok)
                buf.append(tok)
                emit(drainSentences(buf, flush = false))
            }
        }
        emit(drainSentences(buf, flush = true))
        chunks.close()
        speaker.join()
    }

    // NPU TTS (or no TTS): the LLM must fully finish before the TTS can take the slot. Accumulate the
    // whole reply, then (loading the NPU TTS if needed) speak it sentence-by-sentence.
    private suspend fun bufferedTurn(prompt: String, tts: RAModelInfo?) {
        val sb = StringBuilder()
        RunAnywhere.generateStream(prompt, voiceGenOptions()).collect { ev ->
            ev.token?.let { if (it.isNotEmpty()) { sb.append(it); appendAssistantToken(it) } }
        }
        val buf = StringBuilder(sb)
        val sentences = drainSentences(buf, flush = true)
        if (sentences.isEmpty() || tts == null) return
        state = VoiceState.SPEAKING
        if (isNpu(tts)) withContext(Dispatchers.IO) { RunAnywhere.loadModel(RAModelLoadRequest(model_id = tts.id)) }
        for (chunk in sentences) speakChunk(chunk)
    }

    private fun voiceGenOptions() =
        RALLMGenerationOptions(
            max_tokens = 200,
            temperature = 0.7f,
            top_p = 0.95f,
            // Same persona as chat so the small on-device models use conversation context instead of
            // defaulting to a defensive "I don't have personal information" refusal.
            system_prompt = SettingsRepository.settings.systemPrompt.ifBlank { null },
        )

    private fun ttsOptions() =
        RATTSOptions(language_code = "en-US", speaking_rate = 1f, volume = 1f)

    // Speak one chunk, hard-splitting anything longer than the engine can take and skipping
    // blank/symbol-only text (an empty phoneme sequence also fails synthesis). A single failed chunk
    // is logged and skipped, never aborting the turn.
    private suspend fun speakChunk(text: String) {
        for (piece in capForTts(text)) {
            if (piece.isBlank()) continue
            try {
                RunAnywhere.speak(piece, ttsOptions())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.w("tts chunk failed: ${e.message}")
            }
        }
    }

    // Pull complete, speakable sentences out of [buf] (mutating it), dropping <think> reasoning so it
    // is never read aloud. With [flush] the trailing partial is returned too and the buffer drained.
    private fun drainSentences(buf: StringBuilder, flush: Boolean): List<String> {
        val stripped = buf.toString().replace(Regex("(?s)<think>.*?</think>"), "")
        val open = stripped.indexOf("<think>")                 // an unclosed reasoning block, if any
        val held = if (open >= 0) stripped.substring(open) else ""
        val speakable = if (open >= 0) stripped.substring(0, open) else stripped
        val parts = sentenceSplit.split(speakable)
        val complete = if (flush) parts.size else parts.size - 1
        val out = ArrayList<String>(maxOf(complete, 0))
        for (i in 0 until complete) {
            val clean = sanitizeForTts(parts[i])
            if (clean.isNotEmpty()) out.add(clean)
        }
        buf.setLength(0)
        if (!flush) buf.append(parts.lastOrNull() ?: "").append(held)
        return out
    }

    // Strip markdown formatting and collapse whitespace so the TTS g2p sees clean prose.
    private fun sanitizeForTts(text: String): String =
        text.replace(Regex("[*_`#>~|]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

    private fun capForTts(text: String): List<String> {
        if (text.length <= maxTtsChars) return listOf(text)
        val out = ArrayList<String>()
        val cur = StringBuilder()
        for (w in text.split(" ")) {
            if (cur.isNotEmpty() && cur.length + 1 + w.length > maxTtsChars) { out.add(cur.toString()); cur.setLength(0) }
            if (cur.isNotEmpty()) cur.append(' ')
            cur.append(w)
        }
        if (cur.isNotEmpty()) out.add(cur.toString())
        return out
    }

    fun stop() {
        if (useNpuSwap) {
            recorder.stop()
            job?.cancel(); job = null
            assistantTurnIndex = null
            viewModelScope.launch { runCatching { RunAnywhere.stopSpeaking() } }
            state = VoiceState.IDLE
            return
        }
        val session = job
        session?.cancel()
        job = null
        assistantTurnIndex = null
        state = VoiceState.IDLE
        val previousCleanup = cleanupJob
        cleanupJob = viewModelScope.launch(Dispatchers.IO) {
            // streamVoiceAgent completes only after its mic driver has
            // cancelAndJoined, so cleanup cannot race an active feed call.
            session?.join()
            previousCleanup?.join()
            runCatching { RunAnywhere.cleanupVoiceAgent() }
                .onFailure { RACLog.w("voice agent cleanup failed: ${it.message}") }
        }
    }

    fun clear() {
        stop()
        turns.clear()
        error = null
    }

    private fun handleEvent(event: VoiceEvent) {
        event.state?.current?.let(::handlePipelineState)
        event.vad?.let {
            state = if (it.is_speech) VoiceState.LISTENING else VoiceState.TRANSCRIBING
        }
        event.user_said?.let { userSaid ->
            val text = userSaid.text.trim()
            if (userSaid.is_final && text.isNotBlank()) {
                turns += VoiceTurn(text, isUser = true)
                assistantTurnIndex = null
            }
        }
        event.agent_response_started?.let {
            state = VoiceState.THINKING
            ensureAssistantTurn()
        }
        event.assistant_token?.let { token ->
            if (token.text.isNotEmpty() && token.kind.isDisplayableVoiceAnswer()) {
                state = VoiceState.THINKING
                appendAssistantToken(token.text)
            }
        }
        if (event.audio != null || event.agent_response_completed != null) {
            state = VoiceState.SPEAKING
        }
        event.session_stopped?.let { state = VoiceState.IDLE }
        val message = event.session_error?.message?.takeIf { it.isNotBlank() }
            ?: event.error?.message?.takeIf { it.isNotBlank() }
        if (message != null) {
            error = message
            state = VoiceState.IDLE
        }
    }

    private fun handlePipelineState(pipelineState: PipelineState) {
        state = when (pipelineState) {
            PipelineState.PIPELINE_STATE_IDLE,
            PipelineState.PIPELINE_STATE_STOPPED,
            -> VoiceState.IDLE
            PipelineState.PIPELINE_STATE_LISTENING,
            PipelineState.PIPELINE_STATE_WAITING_WAKEWORD,
            -> VoiceState.LISTENING
            PipelineState.PIPELINE_STATE_PROCESSING_SPEECH -> VoiceState.TRANSCRIBING
            PipelineState.PIPELINE_STATE_THINKING,
            PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
            -> VoiceState.THINKING
            PipelineState.PIPELINE_STATE_SPEAKING,
            PipelineState.PIPELINE_STATE_PLAYING_TTS,
            -> VoiceState.SPEAKING
            PipelineState.PIPELINE_STATE_ERROR -> VoiceState.IDLE
            PipelineState.PIPELINE_STATE_COOLDOWN,
            PipelineState.PIPELINE_STATE_UNSPECIFIED,
            -> state
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

internal fun TokenKind.isDisplayableVoiceAnswer(): Boolean =
    this == TokenKind.TOKEN_KIND_ANSWER || this == TokenKind.TOKEN_KIND_UNSPECIFIED
