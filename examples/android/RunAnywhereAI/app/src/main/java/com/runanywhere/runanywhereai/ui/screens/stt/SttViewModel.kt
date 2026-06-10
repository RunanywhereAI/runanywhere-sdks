package com.runanywhere.runanywhereai.ui.screens.stt

import ai.runanywhere.proto.v1.STTLanguage
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    // router. Defaults to the built-in Sarvam entry; can be pointed at any
    // developer-registered provider (see CloudProviderRepository).
    var onlineProviderId by mutableStateOf(ONLINE_MODEL_ID)
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
    private var committed = ""
    private var offlineModelId: String? = null

    private var router: HybridSTTRouter? = null
    private var routerOfflineId: String? = null

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
        if (current != null) viewModelScope.launch(Dispatchers.IO) { runCatching { current.close() } }
    }

    fun toggle(modelId: String?) {
        if (isRecording) stop() else start(modelId)
    }

    private fun start(modelId: String?) {
        transcript = ""
        committed = ""
        metrics = null
        routing = null
        error = null
        offlineModelId = modelId
        synchronized(buffer) { buffer.reset() }
        audioLevel = 0f
        isRecording = true
        if (mode == SttMode.LIVE) startLive()
        recorder.start { chunk, level ->
            // Batch/hybrid buffer locally; live feeds the SDK streaming session.
            if (mode == SttMode.LIVE) {
                liveAudio?.trySend(chunk)
            } else {
                synchronized(buffer) { buffer.write(chunk) }
            }
            audioLevel = level
        }
    }

    private fun startLive() {
        val channel = Channel<ByteArray>(Channel.UNLIMITED)
        liveAudio = channel
        liveJob = viewModelScope.launch {
            RunAnywhere.transcribeStream(
                channel.receiveAsFlow(),
                RASTTOptions(language = STTLanguage.STT_LANGUAGE_EN, enable_punctuation = true),
            ).collect { partial -> onLivePartial(partial) }
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
            return
        }
        val audio = synchronized(buffer) { val bytes = buffer.toByteArray(); buffer.reset(); bytes }
        when {
            audio.size < MIN_BYTES ->
                error = "Recording too short — hold a little longer."
            mode == SttMode.HYBRID -> {
                isTranscribing = true
                viewModelScope.launch {
                    runHybrid(audio)
                    isTranscribing = false
                }
            }
            else -> {
                isTranscribing = true
                viewModelScope.launch {
                    runTranscription(audio)?.let { transcript = it }
                    isTranscribing = false
                }
            }
        }
    }

    private suspend fun runHybrid(audio: ByteArray) {
        val offlineId = offlineModelId
        if (offlineId.isNullOrBlank()) {
            error = "Select a model first."
            return
        }
        try {
            val wav = pcmToWav(audio, AudioRecorder.SAMPLE_RATE)
            val started = System.currentTimeMillis()
            val result = withContext(Dispatchers.IO) {
                ensureRouter(offlineId).transcribe(
                    wav,
                    HybridTranscribeOptions(sample_rate = AudioRecorder.SAMPLE_RATE, audio_format = WAV_FORMAT),
                )
            }
            val elapsed = System.currentTimeMillis() - started
            val r = result.routing
            RACLog.i(
                "hybrid result: text='${result.text}' lang=${result.detectedLanguage} " +
                    "chosen=${r.chosen_model_id} fallback=${r.was_fallback} conf=${r.confidence} " +
                    "primaryConf=${r.primary_confidence} attempts=${r.attempt_count} " +
                    "primaryErr=${r.primary_error_code}/${r.primary_error_message}",
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
            error = e.message ?: "Hybrid transcription failed"
        }
    }

    private fun ensureRouter(offlineId: String): HybridSTTRouter {
        router?.let { if (routerOfflineId == offlineId) return it else it.close() }
        val created = HybridSTTRouter()
        val filters = buildList {
            if (requireNetwork) add(HybridFilter.Network)
            add(HybridFilter.Battery(minPercent = minBattery.toInt()))
        }
        try {
            created.setPair(
                offline = HybridModel.offlineSherpa(offlineId),
                online = HybridModel.onlineCloud(onlineProviderId),
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
        return created
    }

    private suspend fun runTranscription(audio: ByteArray): String? = try {
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

    override fun onCleared() {
        liveAudio?.close()
        liveAudio = null
        liveJob?.cancel()
        recorder.stop()
        router?.close()
        router = null
    }

    private companion object {
        const val MIN_BYTES = 16000
        const val WAV_FORMAT = 1
        const val ONLINE_MODEL_ID = "saaras"
    }
}

private fun pcmToWav(pcm: ByteArray, sampleRate: Int): ByteArray {
    val channels = 1
    val bitsPerSample = 16
    val byteRate = sampleRate * channels * bitsPerSample / 8
    val header = ByteArray(44)
    fun putInt(offset: Int, value: Int) {
        header[offset] = value.toByte()
        header[offset + 1] = (value shr 8).toByte()
        header[offset + 2] = (value shr 16).toByte()
        header[offset + 3] = (value shr 24).toByte()
    }
    fun putShort(offset: Int, value: Int) {
        header[offset] = value.toByte()
        header[offset + 1] = (value shr 8).toByte()
    }
    "RIFF".toByteArray().copyInto(header, 0)
    putInt(4, 36 + pcm.size)
    "WAVE".toByteArray().copyInto(header, 8)
    "fmt ".toByteArray().copyInto(header, 12)
    putInt(16, 16)
    putShort(20, 1)
    putShort(22, channels)
    putInt(24, sampleRate)
    putInt(28, byteRate)
    putShort(32, channels * bitsPerSample / 8)
    putShort(34, bitsPerSample)
    "data".toByteArray().copyInto(header, 36)
    putInt(40, pcm.size)
    return header + pcm
}
