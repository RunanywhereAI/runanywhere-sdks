package com.runanywhere.runanywhereai.ui.screens.tts

import ai.runanywhere.proto.v1.InferenceFramework
import android.app.Application
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
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
                val result = RunAnywhere.speak(content, options())
                val elapsed = System.currentTimeMillis() - start
                metrics = TtsMetrics(
                    durationSec = result.duration_ms.takeIf { it > 0 }?.let { it / 1000.0 }
                        ?: (elapsed / 1000.0),
                    processingMs = elapsed,
                    charsPerSec = if (elapsed > 0) content.length * 1000.0 / elapsed else null,
                    sizeBytes = result.audio_size_bytes.takeIf { it > 0 },
                    sampleRate = result.sample_rate.takeIf { it > 0 },
                )
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
        viewModelScope.launch { runCatching { RunAnywhere.stopSpeaking() } }
        isSpeaking = false
        isGenerating = false
    }

    private fun options() = RATTSOptions(language_code = "en-US", speaking_rate = speed, volume = 1f)

    private fun isSystem(voice: RAModelInfo): Boolean =
        voice.id == "system-tts" || voice.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

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
