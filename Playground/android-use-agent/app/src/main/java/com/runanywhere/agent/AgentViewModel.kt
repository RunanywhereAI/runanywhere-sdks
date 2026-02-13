package com.runanywhere.agent

import android.app.Application
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.provider.Settings
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.agent.accessibility.AgentAccessibilityService
import com.runanywhere.agent.kernel.AgentKernel
import com.runanywhere.agent.tts.TTSManager
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.transcribe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

class AgentViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "AgentViewModel"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    enum class Status {
        IDLE, RUNNING, DONE, ERROR
    }

    data class UiState(
        val goal: String = "",
        val status: Status = Status.IDLE,
        val logs: List<String> = emptyList(),
        val isServiceEnabled: Boolean = false,
        val selectedModelIndex: Int = 1, // Default to Qwen (best)
        val availableModels: List<ModelInfo> = AgentApplication.AVAILABLE_MODELS,
        val isRecording: Boolean = false,
        val isTranscribing: Boolean = false,
        val isSTTModelLoaded: Boolean = false,
        val isSTTModelLoading: Boolean = false,
        val sttDownloadProgress: Float = 0f,
        val isVoiceMode: Boolean = false,
        val isSpeaking: Boolean = false
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val agentKernel = AgentKernel(
        context = application,
        onLog = { log -> addLog(log) }
    )

    private val ttsManager = TTSManager(application)

    // Agent job
    private var agentJob: Job? = null

    // Audio recording state
    private var audioRecord: AudioRecord? = null
    @Volatile
    private var isCapturing = false
    private val audioData = ByteArrayOutputStream()

    init {
        checkServiceStatus()
    }

    fun checkServiceStatus() {
        val isEnabled = AgentAccessibilityService.isEnabled(getApplication())
        _uiState.value = _uiState.value.copy(isServiceEnabled = isEnabled)
    }

    fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        getApplication<Application>().startActivity(intent)
    }

    fun setGoal(goal: String) {
        _uiState.value = _uiState.value.copy(goal = goal)
    }

    fun setModel(index: Int) {
        if (index in AgentApplication.AVAILABLE_MODELS.indices) {
            _uiState.value = _uiState.value.copy(selectedModelIndex = index)
            agentKernel.setModel(AgentApplication.AVAILABLE_MODELS[index].id)
        }
    }

    fun toggleVoiceMode() {
        _uiState.value = _uiState.value.copy(isVoiceMode = !_uiState.value.isVoiceMode)
    }

    fun startAgent() {
        val goal = _uiState.value.goal.trim()
        if (goal.isEmpty()) {
            addLog("Please enter a goal")
            return
        }

        if (!_uiState.value.isServiceEnabled) {
            addLog("Accessibility service not enabled")
            return
        }

        _uiState.value = _uiState.value.copy(
            status = Status.RUNNING,
            logs = listOf("Starting: $goal")
        )

        agentJob = viewModelScope.launch {
            agentKernel.run(goal).collect { event ->
                when (event) {
                    is AgentKernel.AgentEvent.Log -> addLog(event.message)
                    is AgentKernel.AgentEvent.Step -> addLog("${event.action}: ${event.result}")
                    is AgentKernel.AgentEvent.Done -> {
                        addLog(event.message)
                        _uiState.value = _uiState.value.copy(status = Status.DONE)
                    }
                    is AgentKernel.AgentEvent.Error -> {
                        addLog("ERROR: ${event.message}")
                        _uiState.value = _uiState.value.copy(status = Status.ERROR)
                    }
                    is AgentKernel.AgentEvent.Speak -> {
                        if (_uiState.value.isVoiceMode) {
                            ttsManager.speak(event.text)
                        }
                    }
                }
            }
        }
    }

    fun stopAgent() {
        agentKernel.stop()
        agentJob?.cancel()
        agentJob = null
        ttsManager.stop()
        addLog("Agent stopped")
        _uiState.value = _uiState.value.copy(status = Status.IDLE)
    }

    fun clearLogs() {
        _uiState.value = _uiState.value.copy(logs = emptyList())
    }

    // ========== STT Methods ==========

    fun loadSTTModelIfNeeded() {
        if (_uiState.value.isSTTModelLoaded || _uiState.value.isSTTModelLoading) return

        _uiState.value = _uiState.value.copy(isSTTModelLoading = true, sttDownloadProgress = 0f)

        viewModelScope.launch {
            try {
                // Download model if needed
                var downloadFailed = false
                RunAnywhere.downloadModel(AgentApplication.STT_MODEL_ID)
                    .catch { e ->
                        Log.e(TAG, "STT download failed: ${e.message}")
                        addLog("STT download failed: ${e.message}")
                        downloadFailed = true
                    }
                    .collect { progress ->
                        _uiState.value = _uiState.value.copy(sttDownloadProgress = progress.progress)
                    }

                if (downloadFailed) {
                    _uiState.value = _uiState.value.copy(isSTTModelLoading = false)
                    return@launch
                }

                // Load model
                RunAnywhere.loadSTTModel(AgentApplication.STT_MODEL_ID)
                _uiState.value = _uiState.value.copy(
                    isSTTModelLoaded = true,
                    isSTTModelLoading = false
                )
                Log.i(TAG, "STT model loaded")
            } catch (e: Exception) {
                Log.e(TAG, "STT model load failed: ${e.message}", e)
                addLog("STT model load failed: ${e.message}")
                _uiState.value = _uiState.value.copy(isSTTModelLoading = false)
            }
        }
    }

    @Suppress("MissingPermission")
    fun startRecording() {
        if (_uiState.value.isRecording) return

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
            addLog("Audio recording not supported")
            return
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize * 2
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                addLog("Failed to initialize audio recorder")
                return
            }

            audioData.reset()
            audioRecord?.startRecording()
            isCapturing = true
            _uiState.value = _uiState.value.copy(isRecording = true)

            // Capture audio in background thread
            viewModelScope.launch(Dispatchers.IO) {
                val buffer = ByteArray(bufferSize)
                while (isCapturing) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        synchronized(audioData) {
                            audioData.write(buffer, 0, read)
                        }
                    }
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Microphone permission denied: ${e.message}")
            addLog("Microphone permission required")
            audioRecord?.release()
            audioRecord = null
        }
    }

    fun stopRecordingAndTranscribe() {
        if (!_uiState.value.isRecording) return

        // Stop capturing
        isCapturing = false
        audioRecord?.let { record ->
            if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                record.stop()
            }
            record.release()
        }
        audioRecord = null

        val capturedAudio: ByteArray
        synchronized(audioData) {
            capturedAudio = audioData.toByteArray()
        }

        _uiState.value = _uiState.value.copy(isRecording = false, isTranscribing = true)

        if (capturedAudio.isEmpty()) {
            addLog("No audio recorded")
            _uiState.value = _uiState.value.copy(isTranscribing = false)
            return
        }

        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    RunAnywhere.transcribe(capturedAudio)
                }

                if (result.isNotBlank()) {
                    _uiState.value = _uiState.value.copy(
                        goal = result.trim(),
                        isTranscribing = false
                    )
                    // Auto-start agent in voice mode
                    if (_uiState.value.isVoiceMode) {
                        startAgent()
                    }
                } else {
                    if (_uiState.value.isVoiceMode) {
                        ttsManager.speak("I didn't catch that.")
                    }
                    addLog("No speech detected")
                    _uiState.value = _uiState.value.copy(isTranscribing = false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Transcription failed: ${e.message}", e)
                addLog("Transcription failed: ${e.message}")
                _uiState.value = _uiState.value.copy(isTranscribing = false)
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Clean up TTS
        ttsManager.shutdown()
        // Clean up audio resources
        isCapturing = false
        audioRecord?.let { record ->
            try {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    record.stop()
                }
                record.release()
            } catch (_: Exception) {}
        }
        audioRecord = null
    }

    private fun addLog(message: String) {
        val current = _uiState.value.logs.toMutableList()
        current.add(message)
        // Keep last 50 logs
        if (current.size > 50) {
            current.removeAt(0)
        }
        _uiState.value = _uiState.value.copy(logs = current)
    }
}
