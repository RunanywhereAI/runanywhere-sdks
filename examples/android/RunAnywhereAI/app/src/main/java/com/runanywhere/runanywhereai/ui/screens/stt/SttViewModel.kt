package com.runanywhere.runanywhereai.ui.screens.stt

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.ui.HybridBetaCopy
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.hybrid.HybridCascade
import com.runanywhere.sdk.hybrid.HybridFilter
import com.runanywhere.sdk.hybrid.HybridModel
import com.runanywhere.sdk.hybrid.HybridRoutedMetadata
import com.runanywhere.sdk.hybrid.HybridRoutingPolicy
import com.runanywhere.sdk.hybrid.HybridSTTRouter
import com.runanywhere.sdk.hybrid.HybridTranscribeOptions
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.AudioInput
import com.runanywhere.sdk.public.api.SttOptions
import com.runanywhere.sdk.public.api.TranscriptionEvent
import com.runanywhere.sdk.public.api.stt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import kotlin.coroutines.cancellation.CancellationException

enum class SttMode { BATCH, LIVE, HYBRID }

data class SttMetrics(
    val audioSec: Double,
    val processingMs: Long,
    val realTimeFactor: Double?,
    val words: Int,
)

class SttViewModel : ViewModel() {

    var mode by mutableStateOf(SttMode.BATCH)
        private set
    var transcript by mutableStateOf("")
        private set
    var isRecording by mutableStateOf(false)
        private set
    var isTranscribing by mutableStateOf(false)
        private set
    var audioLevel by mutableFloatStateOf(0f)
        private set
    var metrics by mutableStateOf<SttMetrics?>(null)
        private set
    var routing by mutableStateOf<HybridRoutedMetadata?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    /**
     * A recording finished and the engine recognised nothing in it.
     *
     * Distinct from "nothing recorded yet". Commons now publishes an engine's own
     * no-speech marker ("(wind)", "[Music]") as empty text, so an honestly silent
     * recording is an empty transcript and the screen has to say which of the two
     * it is. Previously only the batch path could show that, because it inferred
     * the state from `metrics`, which live mode never sets. Mirrors iOS
     * `STTViewModel.noSpeechDetected`.
     */
    var noSpeechDetected by mutableStateOf(false)
        private set

    /**
     * The recording that produced [noSpeechDetected] carried no usable signal —
     * the input never varied, so there was nothing in it to recognise.
     *
     * "No speech detected" is the right answer to a room that stayed quiet and
     * the wrong answer to a microphone that was muted, held by another app, or
     * wired to nothing. Both of those are indistinguishable from silence to the
     * recognizer, and telling them apart by hand costs hours — so the screen
     * says which one it was, from evidence already in hand: [AudioRecorder]
     * reports a normalised level per chunk, and *acoustic* audio always jitters
     * frame to frame. A capture whose level never moved across
     * [UNUSABLE_MIN_FRAMES] is not a quiet room; it is a dead input — whether it
     * sat at the floor (muted, disconnected) or pinned at the ceiling (a stuck
     * or synthetic source). Judging the range rather than the level alone is
     * what catches both.
     */
    var micInputUnusable by mutableStateOf(false)
        private set

    // Level range observed across the capture in progress, and how many chunks
    // it spans. See [micInputUnusable].
    private var micPeakLevel = 0f
    private var micFloorLevel = 1f
    private var micFrames = 0

    var requireNetwork by mutableStateOf(true)
        private set
    var minBattery by mutableFloatStateOf(20f)
        private set
    var confidenceThreshold by mutableFloatStateOf(0.5f)
        private set
    var preferLocalFirst by mutableStateOf(true)
        private set

    // Registry id of the cloud backend used for the online side of the hybrid
    // router. Providers are configured by the user in Cloud Providers.
    var onlineProviderId by mutableStateOf(CloudProviderRepository.defaultProviderId)
        private set

    fun selectOnlineProvider(id: String) {
        if (id == onlineProviderId || id.isBlank()) return
        onlineProviderId = id
        invalidateRouter()
    }

    private val recorder = AudioRecorder()
    private val buffer = ByteArrayOutputStream()

    // Live mode: mic chunks are fed straight into the SDK's streaming
    // transcription (RunAnywhere.stt.transcribeStream), which owns endpointing/
    // segmentation natively. No app-side silence detection. Mirrors iOS
    // STTViewModel.
    private var liveAudio: Channel<AudioInput>? = null
    private var liveJob: Job? = null
    private var operationJob: Job? = null
    private var operationEpoch = 0
    private var committed = ""
    private var router: HybridSTTRouter? = null
    private var routerOfflineId: String? = null
    private var routerOnlineId: String? = null

    /**
     * Switch mode, clearing the previous mode's output.
     *
     * Leaving a Batch transcript (and its stats) on screen under the Live mode's
     * description attributes one mode's result to another — the reader has no way
     * to tell which mode produced what. Same reset [start] already performs.
     */
    fun selectMode(value: SttMode) {
        if (isRecording || isTranscribing || value == mode) return
        mode = value
        transcript = ""
        committed = ""
        metrics = null
        routing = null
        error = null
        noSpeechDetected = false
        micInputUnusable = false
    }

    fun onNetworkChange(value: Boolean) {
        requireNetwork = value
        invalidateRouter()
    }

    fun onBatteryChange(value: Float) {
        minBattery = value
        invalidateRouter()
    }

    fun onConfidenceChange(value: Float) {
        confidenceThreshold = value
        invalidateRouter()
    }

    fun onRankChange(localFirst: Boolean) {
        preferLocalFirst = localFirst
        invalidateRouter()
    }

    private fun invalidateRouter() {
        val current = router
        router = null
        routerOfflineId = null
        routerOnlineId = null
        if (current != null) viewModelScope.launch(Dispatchers.IO) { runCatching { current.close() } }
    }

    fun toggle() {
        if (isRecording) stop() else start()
    }

    private fun start() {
        transcript = ""
        committed = ""
        metrics = null
        routing = null
        error = null
        noSpeechDetected = false
        micInputUnusable = false
        synchronized(buffer) { buffer.reset() }
        audioLevel = 0f
        isRecording = true
        micPeakLevel = 0f
        micFloorLevel = 1f
        micFrames = 0
        if (mode == SttMode.LIVE) startLive()
        try {
            recorder.start(
                onChunk = { chunk, level ->
                    // Level range across the capture, so an empty result can say
                    // whether the input carried anything at all. See
                    // [micInputUnusable].
                    if (level > micPeakLevel) micPeakLevel = level
                    if (level < micFloorLevel) micFloorLevel = level
                    micFrames += 1
                    // Batch/hybrid buffer locally; live feeds the SDK streaming session.
                    if (mode == SttMode.LIVE) {
                        liveAudio?.trySend(AudioInput.pcm16(chunk, AudioRecorder.SAMPLE_RATE))
                    } else {
                        synchronized(buffer) { buffer.write(chunk) }
                    }
                    audioLevel = level
                },
                onError = { t ->
                    // A mid-capture mic fault (e.g. ERROR_DEAD_OBJECT) fires on the
                    // recorder's worker thread; hop to main to surface it and clear
                    // recording state so the button re-enables instead of hanging.
                    RACLog.e("microphone read failed", t)
                    viewModelScope.launch {
                        if (isRecording) {
                            error = t.message ?: "Microphone stopped unexpectedly"
                            cancel()
                        }
                    }
                },
            )
        } catch (e: Exception) {
            RACLog.e("microphone start failed", e)
            error = e.message ?: "Could not start the microphone"
            cancel()
        }
    }

    private fun startLive() {
        // Bound mic ingress so navigation/stop never leaves minutes of 100 ms
        // chunks queued behind one blocking JNI call — but bound it by MEMORY,
        // not by one flush. The session's native side is not ready when the mic
        // opens: `transcribeStream` only resolves the model and loads the
        // recognizer once it starts collecting this flow, and a cold load is
        // seconds. Measured on the emulator, the first Live run of a session
        // logged "STT model loaded" ~20 s after the record button — with the
        // old 8-chunk (800 ms) bound, every chunk in between was dropped and
        // the user's whole first sentence was gone before the recognizer
        // existed to hear it. LIVE_CHANNEL_CAPACITY now holds
        // LIVE_INGRESS_SECONDS of audio (~1 MB), which covers a cold start and
        // still refuses to grow without limit.
        val channel = Channel<AudioInput>(
            capacity = LIVE_CHANNEL_CAPACITY,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
        liveAudio = channel
        liveJob = viewModelScope.launch {
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.STT)
                RunAnywhere.stt.transcribeStream(
                    channel.receiveAsFlow(),
                    SttOptions(language = "en", punctuation = true),
                ).collect(::onLiveEvent)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("live stt failed", e)
                error = e.message ?: "Live transcription failed"
                isRecording = false
                recorder.stop()
            }
        }
    }

    // Fold one streaming event into the displayed transcript: partials preview
    // the current utterance, the final result commits it as a line.
    private fun onLiveEvent(event: TranscriptionEvent) {
        when (event) {
            is TranscriptionEvent.Partial -> {
                val text = event.alternatives.firstOrNull()?.text?.trim().orEmpty()
                if (text.isNotEmpty()) transcript = join(committed, text)
            }
            is TranscriptionEvent.TranscriptFinal -> {
                val text = event.segment.text.trim()
                if (text.isNotEmpty()) committed = join(committed, text)
                transcript = committed
            }
            else -> Unit
        }
    }

    private fun stop() {
        isRecording = false
        recorder.stop()
        audioLevel = 0f
        if (mode == SttMode.LIVE) {
            // Closing the audio stream lets the native session flush and emit
            // its final result; the collect job ends with the stream.
            liveAudio?.close()
            liveAudio = null
            isTranscribing = true
            val active = liveJob
            viewModelScope.launch {
                // The native flush can wedge; bound the wait so the record
                // button can't stay disabled forever. On timeout the job is
                // left to finish on its own — we just stop blocking the UI.
                val finished = withTimeoutOrNull(LIVE_FLUSH_TIMEOUT_MS) { active?.join() } != null
                if (liveJob === active) liveJob = null
                isTranscribing = false
                // Only a flush we actually saw finish can testify that nothing
                // was recognised. Measured: a final arrived 5.4 s after stop —
                // past this timeout — so asserting "no speech" on the timeout
                // told the user their recording was empty while its transcript
                // was still on its way.
                if (finished) reportSilenceIfEmpty()
            }
            return
        }
        val audio = synchronized(buffer) { val bytes = buffer.toByteArray(); buffer.reset(); bytes }
        when {
            audio.size < MIN_BYTES ->
                error = "Recording too short — hold a little longer."
            mode == SttMode.HYBRID -> {
                isTranscribing = true
                val epoch = ++operationEpoch
                operationJob = viewModelScope.launch {
                    try {
                        runHybrid(audio)
                    } finally {
                        if (operationEpoch == epoch) {
                            isTranscribing = false
                            operationJob = null
                            reportSilenceIfEmpty()
                        }
                    }
                }
            }
            else -> {
                isTranscribing = true
                val epoch = ++operationEpoch
                operationJob = viewModelScope.launch {
                    try {
                        runTranscription(audio)?.let { transcript = it }
                    } finally {
                        if (operationEpoch == epoch) {
                            isTranscribing = false
                            operationJob = null
                            reportSilenceIfEmpty()
                        }
                    }
                }
            }
        }
    }

    private suspend fun runHybrid(audio: ByteArray) {
        val onlineId = resolveOnlineProviderId()
        if (onlineId.isNullOrBlank()) {
            error = HybridBetaCopy.CLOUD_PROVIDER_REQUIRED
            return
        }
        try {
            val offlineId = RuntimeModelSelection.requireCurrent(ModelSelectionContext.STT).id
            val started = System.currentTimeMillis()
            val result = withContext(Dispatchers.IO) {
                ensureRouter(offlineId, onlineId).transcribe(
                    audio,
                    HybridTranscribeOptions(sample_rate = AudioRecorder.SAMPLE_RATE),
                )
            }
            val elapsed = System.currentTimeMillis() - started
            val r = result.routing
            RACLog.i(
                "hybrid result: chars=${result.text.length} lang=${result.detectedLanguage} " +
                    "chosen=${r.chosen_model_id} fallback=${r.was_fallback} conf=${r.confidence} " +
                    "primaryConf=${r.primary_confidence} attempts=${r.attempt_count} " +
                    "primaryErrorCode=${r.primary_error_code}",
            )
            transcript = result.text.trim()
            routing = result.routing
            val audioMs = audio.size.toLong() / (AudioRecorder.SAMPLE_RATE * 2L / 1000L)
            metrics = SttMetrics(
                audioSec = audioMs / 1000.0,
                processingMs = elapsed,
                realTimeFactor = if (audioMs > 0) elapsed.toDouble() / audioMs else null,
                words = result.text.trim().split(Regex("\\s+")).count { it.isNotBlank() },
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("hybrid transcribe failed", e)
            error = HybridBetaCopy.TRANSCRIPTION_FAILED
        }
    }

    private fun resolveOnlineProviderId(): String? {
        val selected = onlineProviderId?.takeIf { id -> CloudProviderRepository.providers.any { it.id == id } }
        val resolved = selected ?: CloudProviderRepository.defaultProviderId
        if (resolved != onlineProviderId) {
            onlineProviderId = resolved
            invalidateRouter()
        }
        return resolved
    }

    private fun ensureRouter(offlineId: String, onlineId: String): HybridSTTRouter {
        router?.let { if (routerOfflineId == offlineId && routerOnlineId == onlineId) return it else it.close() }
        val created = HybridSTTRouter()
        val filters = buildList {
            if (requireNetwork) add(HybridFilter.Network)
            add(HybridFilter.Battery(minPercent = minBattery.toInt()))
        }
        try {
            created.setPair(
                offline = HybridModel.offlineSherpa(offlineId),
                online = HybridModel.onlineCloud(onlineId),
                policy = HybridRoutingPolicy(
                    hardFilters = filters,
                    cascade = HybridCascade.Confidence(confidenceThreshold),
                    preferLocal = preferLocalFirst,
                ),
            )
        } catch (t: Throwable) {
            created.close()
            throw t
        }
        router = created
        routerOfflineId = offlineId
        routerOnlineId = onlineId
        return created
    }

    private suspend fun runTranscription(audio: ByteArray): String? = try {
        RuntimeModelSelection.requireCurrent(ModelSelectionContext.STT)
        val started = System.currentTimeMillis()
        val output = RunAnywhere.stt.transcribe(
            AudioInput.pcm16(audio, AudioRecorder.SAMPLE_RATE),
            SttOptions(language = "en", punctuation = true),
        )
        val elapsed = System.currentTimeMillis() - started
        val text = output.text.trim()
        // STTOutput.duration_ms is populated for every non-empty buffer; never
        // re-derive length from PCM bytes when the commons field is absent.
        val audioMs = output.durationMs.takeIf { it > 0 }
        metrics = SttMetrics(
            audioSec = (audioMs ?: 0L) / 1000.0,
            processingMs = elapsed,
            realTimeFactor = audioMs?.let { elapsed.toDouble() / it },
            words = text.split(Regex("\\s+")).count { it.isNotBlank() },
        )
        text
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        RACLog.e("stt transcribe failed", e)
        error = e.message ?: "Transcription failed"
        null
    }

    /**
     * Publish the empty-result state once an operation has genuinely finished,
     * naming whichever of the two empty cases actually happened. See
     * [micInputUnusable].
     */
    private fun reportSilenceIfEmpty() {
        val empty = transcript.isBlank() && error == null
        noSpeechDetected = empty
        micInputUnusable = empty &&
            micFrames >= UNUSABLE_MIN_FRAMES &&
            micPeakLevel - micFloorLevel < UNUSABLE_LEVEL_RANGE
    }

    // Committed utterances stack as lines, mirroring iOS STTViewModel.
    private fun join(a: String, b: String): String =
        listOf(a.trim(), b.trim()).filter { it.isNotEmpty() }.joinToString("\n")

    /** Cancel capture and discard an unfinished live utterance on navigation. */
    fun cancel() {
        isRecording = false
        isTranscribing = false
        recorder.stop()
        audioLevel = 0f
        liveAudio?.cancel()
        liveAudio = null
        val active = liveJob
        liveJob = null
        active?.cancel()
        operationEpoch += 1
        operationJob?.cancel()
        operationJob = null
        if (active != null) {
            // Await native stream cancellation off-main. The native per-session
            // operation lock prevents another screen from entering the same
            // Whisper/QHexRT session until this in-flight feed has returned.
            viewModelScope.launch(Dispatchers.IO) { active.cancelAndJoin() }
        }
    }

    override fun onCleared() {
        cancel()
        router?.close()
        router = null
    }

    private companion object {
        const val MIN_BYTES = 16000

        // Mic ingress held for the live session, as seconds of 100 ms chunks.
        // Sized to outlast a cold recognizer load rather than one flush — see
        // the note in [startLive]. 30 s is ~1 MB of PCM.
        const val LIVE_INGRESS_SECONDS = 30
        const val LIVE_CHANNEL_CAPACITY = LIVE_INGRESS_SECONDS * 1000 / AudioRecorder.CHUNK_MS

        const val LIVE_FLUSH_TIMEOUT_MS = 5000L

        // How still a capture's level has to be, on AudioRecorder's normalised
        // 0..1 dB scale, before it reads as a dead input rather than a quiet
        // room — and how many chunks that has to hold for. Measured on this
        // emulator: a silent room still swung 0.36..0.48 chunk to chunk, while
        // a disconnected input sat at a flat 0.950 for 126 consecutive chunks.
        // 0.02 over 2 s sits far below the former and far above the latter.
        // See [micInputUnusable].
        const val UNUSABLE_LEVEL_RANGE = 0.02f
        const val UNUSABLE_MIN_FRAMES = 2000 / AudioRecorder.CHUNK_MS
    }
}
