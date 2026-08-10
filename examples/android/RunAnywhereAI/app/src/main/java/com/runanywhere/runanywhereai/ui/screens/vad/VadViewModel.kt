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

    /**
     * The microphone has been handing back a flat, unvarying signal since this
     * session started listening.
     *
     * A detector that reports nothing is indistinguishable from a room that
     * said nothing and from an input that is not connected — and only the last
     * of those is a fault the listener can act on. Acoustic audio always jitters
     * chunk to chunk, so a level that has not moved at all is a dead input,
     * whether it sits at the floor (muted, disconnected) or pinned at the
     * ceiling (a stuck or synthetic source). The level is already measured per
     * chunk, so the screen can name that instead of sitting on "Listening for
     * speech…" forever. Mirrors `SttViewModel.micInputUnusable`.
     */
    var micInputUnusable by mutableStateOf(false)
        private set

    // Level range seen since the last chunk that actually moved; see
    // [micInputUnusable].
    private var steadySinceMs = 0L
    private var steadyPeakLevel = 0f
    private var steadyFloorLevel = 1f

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
        micInputUnusable = false
        resetSteadyWindow()
        startDetectionStream()
        isListening = true
        try {
            recorder.start(
                onChunk = { chunk, level ->
                    // The SDK normalises the samples; framing is handled natively.
                    audio?.trySend(AudioInput.pcm16(chunk, AudioRecorder.SAMPLE_RATE))
                    audioLevel = level
                    // Any real movement in the level restarts the window, so a
                    // quiet stretch mid-session never reads as a dead input.
                    if (level > steadyPeakLevel) steadyPeakLevel = level
                    if (level < steadyFloorLevel) steadyFloorLevel = level
                    if (steadyPeakLevel - steadyFloorLevel >= UNUSABLE_LEVEL_RANGE) {
                        resetSteadyWindow()
                        micInputUnusable = false
                    } else {
                        micInputUnusable =
                            System.currentTimeMillis() - steadySinceMs >= UNUSABLE_REPORT_MS
                    }
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
        micInputUnusable = false
    }

    private fun resetSteadyWindow() {
        steadySinceMs = System.currentTimeMillis()
        steadyPeakLevel = 0f
        steadyFloorLevel = 1f
    }

    // The SDK reports speech-state transitions directly; a failed chunk throws
    // into the collector, so a still-listening session is shut down below.
    private fun startDetectionStream() {
        // Bounded so a wedged detector can never queue the microphone without
        // limit — but bounded by MEMORY, not by a fraction of a second. The
        // detector is not ready when the mic opens: `detectStream` resolves and
        // loads the VAD model only once it starts collecting this flow, and a
        // cold load is seconds. At the old 8-chunk (800 ms) bound every chunk
        // captured during that load was dropped, so the speech that opened the
        // session was gone before anything could judge it. See the same note in
        // `SttViewModel.startLive`.
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
                        is VadEvent.Activity -> isSpeechDetected = event.isSpeech
                        else -> Unit
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

        // Mic ingress held for the detection session, as seconds of chunks —
        // sized to outlast a cold model load. See [startDetectionStream].
        const val AUDIO_INGRESS_SECONDS = 30
        const val AUDIO_CHANNEL_CAPACITY = AUDIO_INGRESS_SECONDS * 1000 / AudioRecorder.CHUNK_MS

        // How still the level has to stay, and for how long, before the screen
        // calls the input dead. Same scale and threshold as
        // `SttViewModel.UNUSABLE_LEVEL_RANGE`; the window is longer here because
        // this session runs open-ended rather than ending at a stop button.
        const val UNUSABLE_LEVEL_RANGE = 0.02f
        const val UNUSABLE_REPORT_MS = 3000L
    }
}
