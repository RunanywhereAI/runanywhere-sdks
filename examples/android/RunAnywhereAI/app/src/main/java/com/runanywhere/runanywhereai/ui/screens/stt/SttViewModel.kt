package com.runanywhere.runanywhereai.ui.screens.stt

import ai.runanywhere.proto.v1.STTLanguage
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
import com.runanywhere.sdk.hybrid.HybridRank
import com.runanywhere.sdk.hybrid.HybridRoutedMetadata
import com.runanywhere.sdk.hybrid.HybridRoutingPolicy
import com.runanywhere.sdk.hybrid.HybridSTTRouter
import com.runanywhere.sdk.hybrid.HybridTranscribeOptions
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.RASTTPartialResult
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.transcribeStream
import com.runanywhere.sdk.public.types.RASTTOptions
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
    // transcription (RunAnywhere.transcribeStream), which owns endpointing/
    // segmentation natively. No app-side silence detection. Mirrors iOS
    // STTViewModel.
    private var liveAudio: Channel<ByteArray>? = null
    private var liveJob: Job? = null
    private var operationJob: Job? = null
    private var operationEpoch = 0
    private var committed = ""
    private var router: HybridSTTRouter? = null
    private var routerOfflineId: String? = null
    private var routerOnlineId: String? = null

    fun selectMode(value: SttMode) {
        if (!isRecording && !isTranscribing) mode = value
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
        synchronized(buffer) { buffer.reset() }
        audioLevel = 0f
        isRecording = true
        if (mode == SttMode.LIVE) startLive()
        try {
            recorder.start(
                onChunk = { chunk, level ->
                    // Batch/hybrid buffer locally; live feeds the SDK streaming session.
                    if (mode == SttMode.LIVE) {
                        liveAudio?.trySend(chunk)
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
        // A native fallback recognizer can spend seconds finalizing an
        // utterance. Bound mic ingress so navigation/stop never leaves minutes
        // of 100 ms chunks queued behind one blocking JNI call.
        val channel = Channel<ByteArray>(
            capacity = LIVE_CHANNEL_CAPACITY,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
        liveAudio = channel
        liveJob = viewModelScope.launch {
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.STT)
                RunAnywhere.transcribeStream(
                    channel.receiveAsFlow(),
                    RASTTOptions(language = STTLanguage.STT_LANGUAGE_EN, enable_punctuation = true),
                ).collect { partial -> onLivePartial(partial) }
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

    // Fold one streaming partial into the displayed transcript: non-final
    // partials preview the current utterance, finals commit it as a line.
    private fun onLivePartial(partial: RASTTPartialResult) {
        val text = partial.text.trim()
        if (partial.is_final) {
            // Stream errors surface as a terminal partial carrying the
            // failure text (see RunAnywhere.transcribeStream).
            if (text.startsWith("STT stream failed")) {
                error = text
                return
            }
            if (text.isNotEmpty()) committed = join(committed, text)
            transcript = committed
        } else if (text.isNotEmpty()) {
            transcript = join(committed, text)
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
                try {
                    // The native flush can wedge; bound the wait so the record
                    // button can't stay disabled forever. On timeout the job is
                    // left to finish on its own — we just stop blocking the UI.
                    withTimeoutOrNull(LIVE_FLUSH_TIMEOUT_MS) { active?.join() }
                } finally {
                    if (liveJob === active) liveJob = null
                    isTranscribing = false
                }
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
                    rank = if (preferLocalFirst) {
                        HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST
                    } else {
                        HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST
                    },
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
        val output = RunAnywhere.transcribe(
            audio,
            RASTTOptions(language = STTLanguage.STT_LANGUAGE_EN, enable_punctuation = true),
        )
        val elapsed = System.currentTimeMillis() - started
        val text = output.text.trim()
        val audioMs = output.duration_ms.takeIf { it > 0 }
            ?: output.metadata?.audio_length_ms?.takeIf { it > 0 }
            ?: (audio.size.toLong() / (AudioRecorder.SAMPLE_RATE * 2L / 1000L))
        val processingMs = output.metadata?.processing_time_ms?.takeIf { it > 0 } ?: elapsed
        metrics = SttMetrics(
            audioSec = audioMs / 1000.0,
            processingMs = processingMs,
            realTimeFactor = if (audioMs > 0) processingMs.toDouble() / audioMs else null,
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
        const val LIVE_CHANNEL_CAPACITY = 8
        const val LIVE_FLUSH_TIMEOUT_MS = 5000L
    }
}
