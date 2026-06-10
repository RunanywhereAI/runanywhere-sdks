package com.runanywhere.runanywhereai.ui.screens.tts

import ai.runanywhere.proto.v1.InferenceFramework
import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.stopSpeaking
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RATTSOptions
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException

data class TtsMetrics(
    val durationSec: Double? = null,
    val processingMs: Long? = null,
    val charsPerSec: Double? = null,
    val sizeBytes: Long? = null,
    val sampleRate: Int? = null,
)

class TtsViewModel(application: Application) : AndroidViewModel(application) {

    var text by mutableStateOf("")
        private set
    var speed by mutableFloatStateOf(1f)
        private set
    var isGenerating by mutableStateOf(false)
        private set
    var isSpeaking by mutableStateOf(false)
        private set
    var metrics by mutableStateOf<TtsMetrics?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null
    private var systemTts: TextToSpeech? = null

    fun onTextChange(value: String) {
        text = value
    }

    fun surpriseMe() {
        text = SAMPLES.filter { it != text }.randomOrNull() ?: SAMPLES.first()
    }

    fun onSpeedChange(value: Float) {
        speed = value
    }

    fun generate(voice: RAModelInfo?) {
        if (voice == null || text.isBlank() || isGenerating || isSpeaking || isSystem(voice)) return
        val content = text.trim()
        error = null
        metrics = null
        isGenerating = true
        job = viewModelScope.launch {
            val start = System.currentTimeMillis()
            try {
                val output = RunAnywhere.synthesize(content, options())
                val elapsed = System.currentTimeMillis() - start
                metrics = TtsMetrics(
                    durationSec = output.duration_ms.takeIf { it > 0 }?.let { it / 1000.0 },
                    processingMs = elapsed,
                    charsPerSec = if (elapsed > 0) content.length * 1000.0 / elapsed else null,
                    sizeBytes = output.audio_data.size.toLong().takeIf { it > 0 },
                    sampleRate = output.sample_rate.takeIf { it > 0 },
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("tts generate failed", e)
                error = e.message ?: "Synthesis failed"
            } finally {
                isGenerating = false
            }
        }
    }

    fun speak(voice: RAModelInfo?) {
        if (voice == null || text.isBlank() || isSpeaking || isGenerating) return
        val content = text.trim()
        error = null
        isSpeaking = true
        job = viewModelScope.launch {
            val start = System.currentTimeMillis()
            try {
                if (isSystem(voice)) {
                    speakSystem(content)
                    val elapsed = System.currentTimeMillis() - start
                    metrics = TtsMetrics(
                        durationSec = elapsed / 1000.0,
                        charsPerSec = if (elapsed > 0) content.length * 1000.0 / elapsed else null,
                    )
                } else {
                    RunAnywhere.speak(content, options())
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("tts speak failed", e)
                error = e.message ?: "Speech failed"
            } finally {
                isSpeaking = false
            }
        }
    }

    fun stop() {
        job?.cancel()
        systemTts?.stop()
        viewModelScope.launch { runCatching { RunAnywhere.stopSpeaking() } }
        isSpeaking = false
        isGenerating = false
    }

    private fun options() = RATTSOptions(language_code = "en-US", speaking_rate = speed, volume = 1f)

    private fun isSystem(voice: RAModelInfo): Boolean =
        voice.id == "system-tts" || voice.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

    private suspend fun speakSystem(value: String) {
        val tts = ensureSystemTts()
        withContext(Dispatchers.Main) {
            tts.language = Locale.getDefault()
            tts.setSpeechRate(speed)
        }
        suspendCancellableCoroutine { cont ->
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) {
                    if (cont.isActive) cont.resumeWith(Result.success(Unit))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    if (cont.isActive) cont.resumeWith(Result.failure(IllegalStateException("System TTS error $errorCode")))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    if (cont.isActive) cont.resumeWith(Result.failure(IllegalStateException("System TTS error")))
                }
            })
            tts.speak(value, TextToSpeech.QUEUE_FLUSH, null, "rac-tts")
            cont.invokeOnCancellation { tts.stop() }
        }
    }

    private suspend fun ensureSystemTts(): TextToSpeech {
        systemTts?.let { return it }
        val ready = CompletableDeferred<Boolean>()
        val tts = TextToSpeech(getApplication()) { status ->
            ready.complete(status == TextToSpeech.SUCCESS)
        }
        if (!ready.await()) {
            tts.shutdown()
            throw IllegalStateException("System TTS unavailable")
        }
        systemTts = tts
        return tts
    }

    override fun onCleared() {
        systemTts?.shutdown()
        systemTts = null
    }

    private companion object {
        val SAMPLES = listOf(
            "On-device AI means your data never leaves your phone.",
            "The quick brown fox jumps over the lazy dog.",
            "In a hole in the ground there lived a hobbit.",
            "The future is already here — it's just not evenly distributed.",
            "Hello! I'm running entirely offline, right here on your device.",
            "She sells seashells by the seashore.",
        )
    }
}
