package com.runanywhere.runanywhereai.ui.screens.stt

import ai.runanywhere.proto.v1.STTLanguage
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.hybrid.BACKEND
import com.runanywhere.sdk.public.hybrid.RACModel
import com.runanywhere.sdk.public.hybrid.RACRouter
import com.runanywhere.sdk.public.hybrid.ROUTER
import com.runanywhere.sdk.public.hybrid.RoutedMetadata
import com.runanywhere.sdk.public.types.RASTTOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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
    var routing by mutableStateOf<RoutedMetadata?>(null)
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
    private var liveJob: Job? = null
    private var committed = ""
    private var offlineModelId: String? = null

    private var router: RACRouter? = null
    private var routerOfflineId: String? = null

    @Volatile
    private var lastVoiceMs = 0L

    @Volatile
    private var voiceSeen = false

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
        voiceSeen = false
        offlineModelId = modelId
        synchronized(buffer) { buffer.reset() }
        audioLevel = 0f
        isRecording = true
        recorder.start { chunk, level ->
            synchronized(buffer) { buffer.write(chunk) }
            audioLevel = level
            if (level > SPEECH_THRESHOLD) {
                voiceSeen = true
                lastVoiceMs = System.currentTimeMillis()
            }
        }
        if (mode == SttMode.LIVE) startLive()
    }

    private fun startLive() {
        liveJob = viewModelScope.launch {
            while (true) {
                delay(LIVE_INTERVAL_MS)
                val snapshot = synchronized(buffer) { buffer.toByteArray() }
                if (snapshot.size < MIN_BYTES || !voiceSeen) continue
                val text = runTranscription(snapshot) ?: continue
                transcript = join(committed, text)
                if (System.currentTimeMillis() - lastVoiceMs > SILENCE_MS && text.isNotBlank()) {
                    committed = transcript
                    synchronized(buffer) { buffer.reset() }
                    voiceSeen = false
                }
            }
        }
    }

    private fun stop() {
        isRecording = false
        liveJob?.cancel()
        liveJob = null
        recorder.stop()
        audioLevel = 0f
        val audio = synchronized(buffer) { val bytes = buffer.toByteArray(); buffer.reset(); bytes }
        when {
            audio.size < MIN_BYTES && mode != SttMode.LIVE ->
                error = "Recording too short — hold a little longer."
            mode == SttMode.HYBRID -> {
                isTranscribing = true
                viewModelScope.launch {
                    runHybrid(audio)
                    isTranscribing = false
                }
            }
            mode == SttMode.BATCH -> {
                isTranscribing = true
                viewModelScope.launch {
                    runTranscription(audio)?.let { transcript = it }
                    isTranscribing = false
                }
            }
            voiceSeen && audio.size >= MIN_BYTES -> {
                isTranscribing = true
                viewModelScope.launch {
                    runTranscription(audio)?.let { transcript = join(committed, it) }
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
                ensureRouter(offlineId).stt.transcribe(audioBytes = wav, audioFormat = WAV_FORMAT, sampleRate = AudioRecorder.SAMPLE_RATE)
            }
            val elapsed = System.currentTimeMillis() - started
            val r = result.routing
            RACLog.i(
                "hybrid result: text='${result.text}' lang=${result.detectedLanguage} " +
                    "chosen=${r.chosenModelId} fallback=${r.wasFallback} conf=${r.confidence} " +
                    "primaryConf=${r.primaryConfidence} attempts=${r.attemptCount} " +
                    "primaryErr=${r.primaryErrorCode}/${r.primaryErrorMessage}",
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

    private fun ensureRouter(offlineId: String): RACRouter {
        router?.let { if (routerOfflineId == offlineId) return it else it.close() }
        val created = RACRouter.stt.init(backendOffline = BACKEND.SHERPA.STT, backendOnline = BACKEND.CLOUD.STT)
        val filters = buildList {
            if (requireNetwork) add(RACRouter.RoutingPolicy.NETWORK())
            add(RACRouter.RoutingPolicy.Battery(minPercent = minBattery.toInt()))
        }
        created.stt.addPair(
            model1 = RACModel(id = offlineId, modelType = ROUTER.OFFLINE),
            model2 = RACModel(id = onlineProviderId, modelType = ROUTER.ONLINE),
            routerPolicy = RACRouter.AdvanceRouterPolicy {
                hardFilters = filters.toTypedArray()
                cascadeConditions = RACRouter.RoutingPolicy.Confidence(confidenceThreshold)
                rankSort = if (preferLocalFirst) {
                    RACRouter.RoutingPolicy.PreferLocalFirst
                } else {
                    RACRouter.RoutingPolicy.PreferOnlineFirst
                }
            },
        )
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

    private fun join(a: String, b: String): String =
        listOf(a.trim(), b.trim()).filter { it.isNotEmpty() }.joinToString(" ")

    override fun onCleared() {
        liveJob?.cancel()
        recorder.stop()
        router?.close()
        router = null
    }

    private companion object {
        const val MIN_BYTES = 16000
        const val LIVE_INTERVAL_MS = 900L
        const val SILENCE_MS = 1000L
        const val SPEECH_THRESHOLD = 0.35f
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
