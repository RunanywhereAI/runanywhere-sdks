package com.runanywhere.runanywhereai.ui.screens.vad

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.stt.AudioRecorder
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.pcm16ToFloat32
import com.runanywhere.sdk.public.extensions.resetVAD
import com.runanywhere.sdk.public.extensions.streamVAD
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch

enum class VadActivity { SPEECH_STARTED, SPEECH_ENDED }

data class VadLogEntry(val type: VadActivity, val timestampMs: Long)

class VadViewModel : ViewModel() {

    var isListening by mutableStateOf(false)
        private set
    var isSpeechDetected by mutableStateOf(false)
        private set
    var audioLevel by mutableFloatStateOf(0f)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    // Most recent first, capped at MAX_LOG_ENTRIES. Mirrors iOS VADViewModel.
    val activityLog = mutableStateListOf<VadLogEntry>()

    private val recorder = AudioRecorder()

    // Mic chunks are fed straight into the SDK's streamVAD session; the SDK
    // owns model framing — no app-side buffer math. Mirrors iOS VADViewModel.
    private var audio: Channel<ByteArray>? = null
    private var detectionJob: Job? = null

    fun toggle() {
        if (isListening) stop() else start()
    }

    fun clearLog() {
        activityLog.clear()
    }

    private fun start() {
        error = null
        isSpeechDetected = false
        audioLevel = 0f
        startDetectionStream()
        isListening = true
        recorder.start { chunk, level ->
            // SDK expects Float32 PCM; framing is handled natively.
            audio?.trySend(RunAnywhere.pcm16ToFloat32(chunk))
            audioLevel = level
        }
    }

    private fun stop() {
        isListening = false
        recorder.stop()
        stopDetectionStream()
        isSpeechDetected = false
        audioLevel = 0f
        viewModelScope.launch {
            runCatching { RunAnywhere.resetVAD() }
                .onFailure { RACLog.w("vad reset failed: ${it.message}") }
        }
    }

    // One RAVADResult per mic chunk; speech-state transitions feed the log.
    // Per-chunk failures never throw — they arrive as an error-marked result
    // and the flow completes, so a still-listening session is shut down here.
    private fun startDetectionStream() {
        val channel = Channel<ByteArray>(Channel.UNLIMITED)
        audio = channel
        detectionJob = viewModelScope.launch {
            var wasSpeechActive = false
            RunAnywhere.streamVAD(channel.receiveAsFlow()).collect { result ->
                val message = result.error_message
                if (!message.isNullOrEmpty()) {
                    RACLog.e("vad stream error: $message")
                    error = message
                    return@collect
                }
                isSpeechDetected = result.is_speech
                if (result.is_speech && !wasSpeechActive) {
                    addLogEntry(VadActivity.SPEECH_STARTED)
                    wasSpeechActive = true
                } else if (!result.is_speech && wasSpeechActive) {
                    addLogEntry(VadActivity.SPEECH_ENDED)
                    wasSpeechActive = false
                }
            }
            if (isListening) stop()
        }
    }

    private fun stopDetectionStream() {
        audio?.close()
        audio = null
        detectionJob?.cancel()
        detectionJob = null
    }

    private fun addLogEntry(type: VadActivity) {
        activityLog.add(0, VadLogEntry(type, System.currentTimeMillis()))
        if (activityLog.size > MAX_LOG_ENTRIES) activityLog.removeAt(activityLog.lastIndex)
    }

    override fun onCleared() {
        recorder.stop()
        audio?.close()
        detectionJob?.cancel()
    }

    private companion object {
        const val MAX_LOG_ENTRIES = 50
    }
}
