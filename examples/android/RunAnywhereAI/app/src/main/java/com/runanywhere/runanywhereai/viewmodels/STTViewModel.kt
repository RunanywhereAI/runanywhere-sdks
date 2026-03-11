package com.runanywhere.runanywhereai.viewmodels

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.models.RecordingState
import com.runanywhere.runanywhereai.models.STTEvent
import com.runanywhere.runanywhereai.models.STTMode
import com.runanywhere.runanywhereai.models.STTUiState
import com.runanywhere.runanywhereai.models.TranscriptionMetrics
import com.runanywhere.runanywhereai.services.AudioCaptureService
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.currentSTTModel
import com.runanywhere.sdk.public.extensions.currentSTTModelId
import com.runanywhere.sdk.public.extensions.isSTTModelLoadedSync
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.transcribeStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

class STTViewModel : ViewModel() {

    companion object {
        private const val TAG = "STTViewModel"
        private const val SAMPLE_RATE = 16000
    }

    // Start in Ready immediately — no loading spinner
    private val _uiState = MutableStateFlow<STTUiState>(STTUiState.Ready())
    val uiState: StateFlow<STTUiState> = _uiState.asStateFlow()

    private val _events = Channel<STTEvent>(Channel.BUFFERED)
    val events: Flow<STTEvent> = _events.receiveAsFlow()

    private var audioCaptureService: AudioCaptureService? = null
    private var recordingJob: Job? = null
    private val audioBuffer = ByteArrayOutputStream()
    private var eventSubscriptionJob: Job? = null
    private var isInitialized = false
    private var hasSubscribedToEvents = false

    /** Initialize with context for audio capture. */
    fun initialize(context: Context) {
        if (isInitialized) return
        isInitialized = true

        viewModelScope.launch {
            audioCaptureService = AudioCaptureService(context)

            val hasPermission = ContextCompat.checkSelfPermission(
                context, Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                updateReady { copy(error = "Microphone permission required") }
            }

            subscribeToSDKEvents()
            checkInitialModelState()
        }
    }

    private fun subscribeToSDKEvents() {
        if (hasSubscribedToEvents) return
        hasSubscribedToEvents = true

        eventSubscriptionJob = viewModelScope.launch {
            EventBus.events.collect { event ->
                if (event is ModelEvent && event.category == EventCategory.STT) {
                    handleModelEvent(event)
                }
            }
        }
    }

    private fun handleModelEvent(event: ModelEvent) {
        when (event.eventType) {
            ModelEvent.ModelEventType.LOADED -> {
                Log.i(TAG, "STT model loaded: ${event.modelId}")
                updateReady {
                    copy(isModelLoaded = true, selectedModelId = event.modelId, selectedModelName = selectedModelName ?: event.modelId)
                }
            }
            ModelEvent.ModelEventType.UNLOADED -> {
                updateReady { copy(isModelLoaded = false, selectedModelId = null, selectedModelName = null, selectedFramework = null) }
            }
            ModelEvent.ModelEventType.DOWNLOAD_FAILED -> {
                updateReady { copy(error = "Download failed: ${event.error}") }
            }
            else -> { /* ignore */ }
        }
    }

    private suspend fun checkInitialModelState() {
        if (RunAnywhere.isSTTModelLoadedSync) {
            val currentModel = RunAnywhere.currentSTTModel()
            val modelId = RunAnywhere.currentSTTModelId
            val displayName = currentModel?.name ?: modelId
            updateReady { copy(isModelLoaded = true, selectedModelId = modelId, selectedModelName = displayName) }
            Log.i(TAG, "STT model already loaded: $displayName")
        }
    }

    fun setMode(mode: STTMode) {
        updateReady { copy(mode = mode) }
    }

    /** Called when model is loaded from ModelSelectionBottomSheet. */
    fun onModelLoaded(modelName: String, modelId: String, framework: InferenceFramework?) {
        Log.i(TAG, "Model loaded: $modelName (id=$modelId)")
        updateReady {
            copy(
                isModelLoaded = true,
                selectedModelName = modelName,
                selectedModelId = modelId,
                selectedFramework = framework,
                error = null,
            )
        }
    }

    fun toggleRecording() {
        viewModelScope.launch {
            val state = (_uiState.value as? STTUiState.Ready) ?: return@launch
            when (state.recordingState) {
                RecordingState.IDLE -> startRecording()
                RecordingState.RECORDING -> stopRecording()
                RecordingState.PROCESSING -> { /* cannot toggle while processing */ }
            }
        }
    }

    private suspend fun startRecording() {
        val state = (_uiState.value as? STTUiState.Ready) ?: return
        if (!state.isModelLoaded) {
            updateReady { copy(error = "No STT model loaded") }
            return
        }

        updateReady { copy(recordingState = RecordingState.RECORDING, transcription = "", error = null, audioLevel = 0f) }
        audioBuffer.reset()

        val audioCapture = audioCaptureService ?: run {
            updateReady { copy(error = "Audio capture not initialized") }
            return
        }

        when (state.mode) {
            STTMode.BATCH -> startBatchRecording(audioCapture)
            STTMode.LIVE -> startLiveRecording(audioCapture)
        }
    }

    private fun startBatchRecording(audioCapture: AudioCaptureService) {
        recordingJob = viewModelScope.launch {
            try {
                audioCapture.startCapture().collect { audioData ->
                    withContext(Dispatchers.IO) { audioBuffer.write(audioData) }
                    val rms = audioCapture.calculateRMS(audioData)
                    updateReady { copy(audioLevel = normalizeAudioLevel(rms)) }
                }
            } catch (_: kotlinx.coroutines.CancellationException) {
                Log.d(TAG, "Batch recording cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Batch recording error", e)
                updateReady { copy(error = "Recording error: ${e.message}", recordingState = RecordingState.IDLE, audioLevel = 0f) }
            }
        }
    }

    private fun startLiveRecording(audioCapture: AudioCaptureService) {
        recordingJob = viewModelScope.launch {
            try {
                val chunkBuffer = ByteArrayOutputStream()
                var lastTranscription = ""

                audioCapture.startCapture().collect { audioData ->
                    val rms = audioCapture.calculateRMS(audioData)
                    updateReady { copy(audioLevel = normalizeAudioLevel(rms)) }
                    chunkBuffer.write(audioData)

                    // Transcribe every ~1 second of audio
                    if (chunkBuffer.size() >= 32000) {
                        val chunkData = chunkBuffer.toByteArray()
                        chunkBuffer.reset()

                        withContext(Dispatchers.IO) {
                            try {
                                val options = STTOptions(language = (_uiState.value as? STTUiState.Ready)?.language ?: "en")
                                val result = RunAnywhere.transcribeStream(
                                    audioData = chunkData,
                                    options = options,
                                ) { partial ->
                                    if (partial.transcript.isNotBlank()) {
                                        val newText = "$lastTranscription ${partial.transcript}".trim()
                                        viewModelScope.launch(Dispatchers.Main) { handleStreamText(newText) }
                                    }
                                }
                                lastTranscription = "$lastTranscription ${result.text}".trim()
                                withContext(Dispatchers.Main) { handleStreamText(lastTranscription) }
                            } catch (e: Exception) {
                                Log.w(TAG, "Chunk transcription error: ${e.message}")
                            }
                        }
                    }
                }
            } catch (_: kotlinx.coroutines.CancellationException) {
                Log.d(TAG, "Live recording cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Live recording error", e)
                updateReady { copy(error = "Live transcription error: ${e.message}", recordingState = RecordingState.IDLE, audioLevel = 0f) }
            }
        }
    }

    private fun handleStreamText(text: String) {
        if (text.isNotBlank() && text != "...") {
            val wordCount = text.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
            updateReady { copy(transcription = text, metrics = TranscriptionMetrics(wordCount = wordCount)) }
        }
    }

    private suspend fun stopRecording() {
        val state = (_uiState.value as? STTUiState.Ready) ?: return
        audioCaptureService?.stopCapture()
        delay(100)
        recordingJob?.cancel()
        recordingJob = null

        updateReady {
            copy(
                recordingState = if (state.mode == STTMode.BATCH) RecordingState.PROCESSING else RecordingState.IDLE,
                audioLevel = 0f,
                isTranscribing = state.mode == STTMode.BATCH,
            )
        }

        if (state.mode == STTMode.BATCH) {
            performBatchTranscription()
        }
    }

    private suspend fun performBatchTranscription() {
        val audioBytes = audioBuffer.toByteArray()
        if (audioBytes.isEmpty()) {
            updateReady { copy(error = "No audio recorded", recordingState = RecordingState.IDLE, isTranscribing = false) }
            return
        }

        Log.i(TAG, "Batch transcribing ${audioBytes.size} bytes")

        try {
            withContext(Dispatchers.IO) {
                val startTime = System.currentTimeMillis()
                val audioDurationMs = (audioBytes.size.toDouble() / (SAMPLE_RATE * 2)) * 1000
                val result = RunAnywhere.transcribe(audioBytes)
                val inferenceTimeMs = System.currentTimeMillis() - startTime
                val wordCount = result.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }.size

                withContext(Dispatchers.Main) {
                    updateReady {
                        copy(
                            transcription = result,
                            recordingState = RecordingState.IDLE,
                            isTranscribing = false,
                            metrics = TranscriptionMetrics(
                                audioDurationMs = audioDurationMs,
                                inferenceTimeMs = inferenceTimeMs.toDouble(),
                                detectedLanguage = language,
                                wordCount = wordCount,
                            ),
                        )
                    }
                }
                Log.i(TAG, "Batch transcription complete: $result (${inferenceTimeMs}ms)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Batch transcription failed", e)
            updateReady {
                copy(error = "Transcription failed: ${e.message}", recordingState = RecordingState.IDLE, isTranscribing = false, metrics = null)
            }
        }
    }

    fun clearTranscription() {
        updateReady { copy(transcription = "", metrics = null) }
    }

    override fun onCleared() {
        super.onCleared()
        recordingJob?.cancel()
        eventSubscriptionJob?.cancel()
        audioCaptureService?.release()
    }

    // -- Helpers ------------------------------------------------------------------

    private fun normalizeAudioLevel(rms: Float): Float {
        val dbLevel = 20 * log10(rms + 0.0001f)
        return max(0f, min(1f, (dbLevel + 60) / 60))
    }

    private inline fun updateReady(crossinline transform: STTUiState.Ready.() -> STTUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is STTUiState.Ready -> current.transform()
                else -> current
            }
        }
    }
}
