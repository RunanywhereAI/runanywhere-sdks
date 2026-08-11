package com.runanywhere.runanywhereai.ui.screens.tts

import ai.runanywhere.proto.v1.InferenceFramework
import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.SpeechHandle
import com.runanywhere.sdk.public.api.TtsOptions
import com.runanywhere.sdk.public.api.tts
import com.runanywhere.sdk.public.types.RAModelInfo
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

    /** The utterance currently playing out, held so [stop] can interrupt that exact one. */
    private var speech: SpeechHandle? = null

    fun onTextChange(value: String) {
        text = value
    }

    fun surpriseMe() {
        text = SAMPLES.filter { it != text }.randomOrNull() ?: SAMPLES.first()
    }

    fun onSpeedChange(value: Float) {
        speed = value
    }

    fun generate() {
        if (text.isBlank() || isGenerating || isSpeaking) return
        val content = text.trim()
        error = null
        metrics = null
        isGenerating = true
        job = viewModelScope.launch {
            val start = System.currentTimeMillis()
            try {
                val voice = RuntimeModelSelection.requireCurrent(ModelSelectionContext.TTS).model
                check(!isSystem(voice)) { "Choose a downloadable voice to generate audio." }
                val audio = RunAnywhere.tts.synthesize(content, options())
                val elapsed = System.currentTimeMillis() - start
                metrics = TtsMetrics(
                    durationSec = audio.durationMs.takeIf { it > 0 }?.let { it / 1000.0 },
                    // Wall wait for this call. TTSSynthesisMetadata.processing_time_ms
                    // is not mapped onto public Audio yet — do not invent chars/s.
                    processingMs = elapsed,
                    charsPerSec = null,
                    sizeBytes = audio.data.size.toLong().takeIf { it > 0 },
                    sampleRate = audio.sampleRate.takeIf { it > 0 },
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

    fun speak() {
        if (text.isBlank() || isSpeaking || isGenerating) return
        val content = text.trim()
        error = null
        isSpeaking = true
        job = viewModelScope.launch {
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.TTS)
                // `speak` hands back a handle and returns at once — it does not await the
                // utterance. Awaiting the handle is what keeps [isSpeaking] true for the
                // length of the audio, so the button can offer Stop and a second tap cannot
                // start a second utterance over the first. Without it the flag flipped back
                // within ~2 ms and two taps played two replies simultaneously.
                val handle = RunAnywhere.tts.speak(content, options())
                speech = handle
                handle.waitForPlayout()
                handle.error?.let { throw it }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("tts speak failed", e)
                error = e.message ?: "Speech failed"
            } finally {
                speech = null
                isSpeaking = false
            }
        }
    }

    fun stop() {
        // Interrupt through the handle: it is the only thing that reaches the playback of
        // *this* utterance. Deliberately no metrics are published for a stopped utterance —
        // nothing measured about a run the user cut short would be true of the audio.
        val handle = speech
        speech = null
        job?.cancel()
        viewModelScope.launch { runCatching { handle?.interrupt() ?: RunAnywhere.tts.stop() } }
        isSpeaking = false
        isGenerating = false
    }

    private fun options() = TtsOptions(language = "en-US", speed = speed)

    private fun isSystem(voice: RAModelInfo): Boolean =
        voice.id == "system-tts" || voice.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

    private companion object {
        val SAMPLES = listOf(
            "AI inference runs locally, and prompts stay on this device by default.",
            "The quick brown fox jumps over the lazy dog.",
            "In a hole in the ground there lived a hobbit.",
            "The future is already here — it's just not evenly distributed.",
            "Hello! This voice is running locally, right here on your device.",
            "She sells seashells by the seashore.",
        )
    }
}
