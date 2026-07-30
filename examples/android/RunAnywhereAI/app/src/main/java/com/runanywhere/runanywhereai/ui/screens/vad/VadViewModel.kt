package com.runanywhere.runanywhereai.ui.screens.vad

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.ui.screens.stt.AudioRecorder
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.AudioInput
import com.runanywhere.sdk.public.api.VadEvent
import com.runanywhere.sdk.public.api.vad
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
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
    private var audio: Channel<AudioInput>? = null
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
        try {
            recorder.start(
                onChunk = { chunk, level ->
                    // The SDK normalises the samples; framing is handled natively.
                    audio?.trySend(AudioInput.pcm16(chunk, AudioRecorder.SAMPLE_RATE))
                    audioLevel = level
                },
                onError = { e ->
                    // A2: a mid-capture mic fault (e.g. OS revoke) — clear the UI on the main thread.
                    viewModelScope.launch {
                        if (isListening) {
                            RACLog.e("microphone error", e)
                            error = e.message ?: "Microphone error"
                            stop()
                        }
                    }
                },
            )
        } catch (e: Exception) {
            RACLog.e("microphone start failed", e)
            error = e.message ?: "Could not start the microphone"
            stop()
        }
    }

    fun stop() {
        isListening = false
        recorder.stop()
        stopDetectionStream()
        isSpeechDetected = false
        audioLevel = 0f
    }

    // The SDK reports speech-state transitions directly; a failed chunk throws
    // into the collector, so a still-listening session is shut down below.
    private fun startDetectionStream() {
        val channel = Channel<AudioInput>(
            capacity = AUDIO_CHANNEL_CAPACITY,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
        audio = channel
        detectionJob = viewModelScope.launch {
            try {
                RuntimeModelSelection.requireCurrent(ModelSelectionContext.VAD)
                RunAnywhere.vad.detectStream(channel.receiveAsFlow()).collect { event ->
                    when (event) {
                        is VadEvent.SpeechStarted -> {
                            isSpeechDetected = true
                            addLogEntry(VadActivity.SPEECH_STARTED)
                        }
                        is VadEvent.SpeechEnded -> {
                            isSpeechDetected = false
                            addLogEntry(VadActivity.SPEECH_ENDED)
                        }
                        is VadEvent.Frame -> isSpeechDetected = event.result.isSpeech
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("vad stream failed", e)
                error = e.message ?: "Voice activity detection failed"
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
        const val AUDIO_CHANNEL_CAPACITY = 8
    }
}
