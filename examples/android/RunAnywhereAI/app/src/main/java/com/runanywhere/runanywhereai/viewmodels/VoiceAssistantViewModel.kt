package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.SDKInitState
import com.runanywhere.runanywhereai.models.VoiceAgentState
import com.runanywhere.runanywhereai.models.VoiceEvent
import com.runanywhere.runanywhereai.models.VoiceModelLoadState
import com.runanywhere.runanywhereai.models.VoiceSelectedModel
import com.runanywhere.runanywhereai.models.VoiceUiState
import com.runanywhere.runanywhereai.services.AudioCaptureService
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.events.SDKEvent
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VoiceAgent.ComponentLoadState
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.extensions.startVoiceSession
import com.runanywhere.sdk.public.extensions.stopVoiceSession
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.extensions.voiceAgentComponentStates
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

class VoiceAssistantViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication

    // Audio capture service for microphone input
    private var audioCaptureService: AudioCaptureService? = null

    // Audio buffer (guarded by lock)
    private val audioBuffer = ByteArrayOutputStream()
    private val audioBufferLock = Any()

    // Voice session flow
    private var voiceSessionFlow: Flow<VoiceSessionEvent>? = null

    // Coroutine jobs
    private var pipelineJob: Job? = null
    private var eventSubscriptionJob: Job? = null
    private var audioRecordingJob: Job? = null
    private var silenceDetectionJob: Job? = null
    private var audioPlaybackJob: Job? = null
    private var processingJob: Job? = null

    // Speech state tracking
    @Volatile private var isSpeechActive = false
    private var lastSpeechTime: Long = 0L
    @Volatile private var isProcessingTurn = false

    // Audio playback
    private var audioTrack: AudioTrack? = null
    @Volatile private var isPlayingAudio = false

    // Voice session configuration
    private val speechThreshold = 0.1f
    private val silenceDurationMs = 1500L
    private val minAudioBytes = 16000
    private val ttsSampleRate = 22050

    private val _uiState = MutableStateFlow<VoiceUiState>(VoiceUiState.Ready())
    val uiState: StateFlow<VoiceUiState> = _uiState.asStateFlow()

    private val _events = Channel<VoiceEvent>(Channel.BUFFERED)
    val events: Flow<VoiceEvent> = _events.receiveAsFlow()

    init {
        subscribeToSDKEvents()
        observeSDKState()
    }

    private fun observeSDKState() {
        viewModelScope.launch {
            app.sdkState.collect { sdkState ->
                when (sdkState) {
                    is SDKInitState.Loading -> { /* stay in current state */ }
                    is SDKInitState.Ready -> {
                        viewModelScope.launch { syncModelStates() }
                    }
                    is SDKInitState.Error -> {
                        _uiState.value = VoiceUiState.Error(sdkState.message)
                    }
                }
            }
        }
    }

    fun initialize(context: Context) {
        if (audioCaptureService == null) {
            audioCaptureService = AudioCaptureService(context)
            Log.i(TAG, "AudioCaptureService initialized")
        }
    }

    fun refreshComponentStatesFromSDK() {
        viewModelScope.launch { syncModelStates() }
    }

    // -- Model selection --

    fun setSTTModel(framework: String, name: String, modelId: String) {
        updateReady {
            copy(sttModel = VoiceSelectedModel(framework, name, modelId))
        }
        Log.i(TAG, "STT model selected: $name ($modelId)")
        viewModelScope.launch { syncModelStates() }
    }

    fun setLLMModel(framework: String, name: String, modelId: String) {
        updateReady {
            copy(llmModel = VoiceSelectedModel(framework, name, modelId))
        }
        Log.i(TAG, "LLM model selected: $name ($modelId)")
        viewModelScope.launch { syncModelStates() }
    }

    fun setTTSModel(framework: String, name: String, modelId: String) {
        updateReady {
            copy(ttsModel = VoiceSelectedModel(framework, name, modelId))
        }
        Log.i(TAG, "TTS model selected: $name ($modelId)")
        viewModelScope.launch { syncModelStates() }
    }

    // -- Session control --

    fun startSession() {
        viewModelScope.launch {
            try {
                Log.i(TAG, "Starting conversation...")

                updateReady {
                    copy(
                        agentState = VoiceAgentState.LISTENING,
                        error = null,
                        currentTranscript = "",
                        assistantResponse = "",
                        streamingResponse = "",
                    )
                }

                val ready = (_uiState.value as? VoiceUiState.Ready)
                if (ready?.allModelsLoaded != true) {
                    Log.w(TAG, "Cannot start: Not all models loaded")
                    updateReady {
                        copy(
                            agentState = VoiceAgentState.IDLE,
                            error = "Please load all required models (STT, LLM, TTS) before starting",
                        )
                    }
                    return@launch
                }

                val audioCapture = audioCaptureService
                if (audioCapture == null) {
                    updateReady {
                        copy(
                            agentState = VoiceAgentState.IDLE,
                            error = "Audio capture not initialized. Please grant microphone permission.",
                        )
                    }
                    return@launch
                }

                if (!audioCapture.hasRecordPermission()) {
                    updateReady {
                        copy(
                            agentState = VoiceAgentState.IDLE,
                            error = "Microphone permission required",
                        )
                    }
                    return@launch
                }

                // Start voice session (for SDK state tracking)
                val sessionFlow = RunAnywhere.startVoiceSession(VoiceSessionConfig.DEFAULT)
                voiceSessionFlow = sessionFlow

                // Consume voice session events in background
                pipelineJob = viewModelScope.launch {
                    try {
                        sessionFlow.collect { event -> handleVoiceSessionEvent(event) }
                    } catch (e: Exception) {
                        Log.e(TAG, "Session event error", e)
                    }
                }

                // Reset audio buffer
                synchronized(audioBufferLock) { audioBuffer.reset() }

                // Update state to listening
                updateReady {
                    copy(
                        agentState = VoiceAgentState.LISTENING,
                        isListening = true,
                        audioLevel = 0f,
                    )
                }

                // Reset speech state tracking
                isSpeechActive = false
                lastSpeechTime = 0L
                isProcessingTurn = false

                // Start audio capture
                audioRecordingJob = viewModelScope.launch {
                    try {
                        audioCapture.startCapture().collect { audioData ->
                            if (isProcessingTurn) return@collect

                            withContext(Dispatchers.IO) {
                                synchronized(audioBufferLock) {
                                    audioBuffer.write(audioData)
                                }
                            }

                            val rms = audioCapture.calculateRMS(audioData)
                            val normalizedLevel = normalizeAudioLevel(rms)
                            updateReady { copy(audioLevel = normalizedLevel) }

                            checkSpeechState(normalizedLevel)
                        }
                    } catch (_: kotlinx.coroutines.CancellationException) {
                        Log.d(TAG, "Audio recording cancelled")
                    } catch (e: Exception) {
                        Log.e(TAG, "Audio capture error", e)
                        updateReady { copy(error = "Audio capture error: ${e.message}") }
                    }
                }

                // Start silence detection monitoring
                silenceDetectionJob = viewModelScope.launch {
                    val currentReady = _uiState.value as? VoiceUiState.Ready
                    while (currentReady?.isListening == true && !isProcessingTurn) {
                        checkSilenceAndTriggerProcessing()
                        delay(50)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start session", e)
                updateReady {
                    copy(
                        agentState = VoiceAgentState.IDLE,
                        error = "Failed to start: ${e.message}",
                        isListening = false,
                    )
                }
            }
        }
    }

    fun stopSession() {
        viewModelScope.launch {
            Log.i(TAG, "Stopping conversation...")

            isProcessingTurn = false
            isSpeechActive = false
            lastSpeechTime = 0L

            stopAudioPlayback()

            audioRecordingJob?.cancel()
            audioRecordingJob = null
            silenceDetectionJob?.cancel()
            silenceDetectionJob = null
            pipelineJob?.cancel()
            pipelineJob = null
            processingJob?.cancel()
            processingJob = null

            audioCaptureService?.stopCapture()

            val audioData: ByteArray
            val audioSize: Int
            synchronized(audioBufferLock) {
                audioData = audioBuffer.toByteArray()
                audioSize = audioData.size
                audioBuffer.reset()
            }

            if (audioSize >= minAudioBytes) {
                updateReady {
                    copy(
                        agentState = VoiceAgentState.THINKING,
                        isListening = false,
                        isSpeechDetected = false,
                        audioLevel = 0f,
                    )
                }

                processAudioWithStreamingPipeline(audioData)
            } else {
                updateReady {
                    copy(
                        agentState = VoiceAgentState.IDLE,
                        isListening = false,
                        isSpeechDetected = false,
                        audioLevel = 0f,
                        error = if (audioSize > 0) "Recording too short" else null,
                    )
                }
            }

            RunAnywhere.stopVoiceSession()
            voiceSessionFlow = null
        }
    }

    fun clearError() {
        updateReady { copy(error = null) }
    }

    fun clearConversation() {
        updateReady {
            copy(
                currentTranscript = "",
                assistantResponse = "",
                streamingResponse = "",
            )
        }
    }

    // -- Streaming pipeline: STT -> streaming LLM -> sentence-buffered TTS --

    /**
     * Processes audio through a streaming pipeline:
     * 1. Transcribe audio (STT)
     * 2. Stream LLM response token-by-token (displayed with markdown)
     * 3. Buffer sentences and synthesize each via TTS
     */
    private fun processAudioWithStreamingPipeline(audioData: ByteArray) {
        processingJob = viewModelScope.launch {
            try {
                // Step 1: Transcribe
                Log.i(TAG, "Streaming pipeline: transcribing ${audioData.size} bytes...")
                val transcription = withContext(Dispatchers.Default) {
                    RunAnywhere.transcribe(audioData)
                }

                if (transcription.isBlank()) {
                    Log.w(TAG, "No speech detected in transcription")
                    updateReady {
                        copy(
                            agentState = VoiceAgentState.IDLE,
                            error = "No speech detected",
                        )
                    }
                    return@launch
                }

                Log.i(TAG, "Streaming pipeline: transcribed -> \"$transcription\"")

                updateReady {
                    copy(
                        currentTranscript = transcription,
                        streamingResponse = "",
                        assistantResponse = "",
                        agentState = VoiceAgentState.THINKING,
                    )
                }

                // Step 2: Stream LLM response with limited tokens for voice
                Log.i(TAG, "Streaming pipeline: generating response...")
                val voiceOptions = LLMGenerationOptions(maxTokens = VOICE_MAX_TOKENS)
                val fullResponse = StringBuilder()
                val sentenceBuffer = StringBuilder()
                val ttsQueue = Channel<String>(Channel.UNLIMITED)

                // Launch TTS consumer that processes sentences from the queue
                val ttsJob = launch {
                    var firstSentence = true
                    for (sentence in ttsQueue) {
                        val cleanText = stripMarkdownForTTS(sentence)
                        if (cleanText.isBlank()) continue

                        Log.d(TAG, "TTS synthesizing: \"$cleanText\"")

                        if (firstSentence) {
                            updateReady { copy(agentState = VoiceAgentState.SPEAKING) }
                            firstSentence = false
                        }

                        try {
                            val ttsOutput = withContext(Dispatchers.Default) {
                                RunAnywhere.synthesize(cleanText)
                            }
                            if (ttsOutput.audioData.isNotEmpty()) {
                                playAudioBlocking(ttsOutput.audioData)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "TTS synthesis error for sentence", e)
                        }
                    }
                }

                // Collect streaming tokens
                try {
                    RunAnywhere.generateStream(transcription, voiceOptions).collect { token ->
                        fullResponse.append(token)
                        sentenceBuffer.append(token)

                        // Update streaming display (shown with markdown)
                        updateReady { copy(streamingResponse = fullResponse.toString()) }

                        // Check if we have a complete sentence to send to TTS
                        val buffered = sentenceBuffer.toString()
                        val sentenceEnd = findSentenceEnd(buffered)
                        if (sentenceEnd >= 0) {
                            val sentence = buffered.substring(0, sentenceEnd + 1).trim()
                            sentenceBuffer.delete(0, sentenceEnd + 1)
                            if (sentence.isNotBlank()) {
                                ttsQueue.send(sentence)
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "LLM stream error", e)
                }

                // Flush remaining text in sentence buffer
                val remaining = sentenceBuffer.toString().trim()
                if (remaining.isNotBlank()) {
                    ttsQueue.send(remaining)
                }
                ttsQueue.close()

                // Wait for TTS to finish speaking all sentences
                ttsJob.join()

                val responseText = fullResponse.toString()
                Log.i(TAG, "Streaming pipeline: complete. Response length=${responseText.length}")

                updateReady {
                    copy(
                        assistantResponse = responseText,
                        streamingResponse = "",
                        agentState = VoiceAgentState.IDLE,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Streaming pipeline error", e)
                updateReady {
                    copy(
                        agentState = VoiceAgentState.IDLE,
                        error = "Processing error: ${e.message}",
                    )
                }
            }
        }
    }

    /** Find the index of a sentence-ending character (. ! ? followed by space or end). */
    private fun findSentenceEnd(text: String): Int {
        val sentenceEnders = charArrayOf('.', '!', '?')
        for (i in text.indices) {
            if (text[i] in sentenceEnders) {
                // Make sure it's a real sentence end (followed by space, newline, or end of text)
                val nextIdx = i + 1
                if (nextIdx >= text.length || text[nextIdx] == ' ' || text[nextIdx] == '\n') {
                    return i
                }
            }
        }
        return -1
    }

    /**
     * Strip markdown formatting for TTS, keeping only plain text with
     * punctuation (,.!?) and digits (0-9).
     */
    private fun stripMarkdownForTTS(text: String): String {
        var result = text
        // Remove code blocks
        result = result.replace(Regex("```[\\s\\S]*?```"), " ")
        result = result.replace(Regex("`[^`]+`"), " ")
        // Remove headers
        result = result.replace(Regex("^#{1,6}\\s+", RegexOption.MULTILINE), "")
        // Remove bold/italic markers
        result = result.replace(Regex("\\*{1,3}"), "")
        result = result.replace(Regex("_{1,3}"), "")
        // Remove links [text](url) -> text
        result = result.replace(Regex("\\[([^]]+)]\\([^)]+\\)"), "$1")
        // Remove images
        result = result.replace(Regex("!\\[([^]]*)]\\([^)]+\\)"), "$1")
        // Remove bullet points
        result = result.replace(Regex("^[\\-*+]\\s+", RegexOption.MULTILINE), "")
        // Remove numbered list markers
        result = result.replace(Regex("^\\d+\\.\\s+", RegexOption.MULTILINE), "")
        // Remove blockquote markers
        result = result.replace(Regex("^>\\s+", RegexOption.MULTILINE), "")
        // Remove horizontal rules
        result = result.replace(Regex("^[\\-*_]{3,}$", RegexOption.MULTILINE), "")
        // Remove emojis and other symbols outside basic Latin + punctuation
        result = result.replace(Regex("[\\x{1F000}-\\x{1FFFF}\\x{2600}-\\x{27BF}\\x{FE00}-\\x{FEFF}\\x{200D}\\x{20E3}\\x{E0020}-\\x{E007F}]"), "")
        // Collapse multiple spaces/newlines
        result = result.replace(Regex("\\s+"), " ")
        return result.trim()
    }

    // -- Private helpers --

    private fun normalizeAudioLevel(rms: Float): Float =
        (rms * 3.0f).coerceIn(0f, 1f)

    private fun checkSpeechState(level: Float) {
        if (level > speechThreshold) {
            if (!isSpeechActive) {
                isSpeechActive = true
                updateReady { copy(isSpeechDetected = true) }
            }
            lastSpeechTime = System.currentTimeMillis()
        }
    }

    private fun checkSilenceAndTriggerProcessing() {
        if (!isSpeechActive || isProcessingTurn) return

        val currentLevel = (_uiState.value as? VoiceUiState.Ready)?.audioLevel ?: 0f
        if (currentLevel <= speechThreshold && lastSpeechTime > 0) {
            val silenceTime = System.currentTimeMillis() - lastSpeechTime
            if (silenceTime > silenceDurationMs) {
                isSpeechActive = false
                updateReady { copy(isSpeechDetected = false) }

                val audioSize = synchronized(audioBufferLock) { audioBuffer.size() }
                if (audioSize >= minAudioBytes) {
                    processCurrentAudio()
                } else {
                    synchronized(audioBufferLock) { audioBuffer.reset() }
                }
            }
        }
    }

    private fun processCurrentAudio() {
        if (isProcessingTurn) return
        isProcessingTurn = true

        val audioData: ByteArray
        synchronized(audioBufferLock) {
            audioData = audioBuffer.toByteArray()
            audioBuffer.reset()
        }

        viewModelScope.launch {
            updateReady {
                copy(
                    agentState = VoiceAgentState.THINKING,
                    isListening = false,
                    isSpeechDetected = false,
                    audioLevel = 0f,
                )
            }

            audioRecordingJob?.cancel()
            silenceDetectionJob?.cancel()
            audioCaptureService?.stopCapture()

            processAudioWithStreamingPipeline(audioData)
        }
    }

    /**
     * Play audio synchronously (blocks the coroutine until playback finishes).
     * Used by the TTS queue consumer so sentences play in order.
     */
    private suspend fun playAudioBlocking(audioData: ByteArray) {
        if (audioData.isEmpty()) return

        isPlayingAudio = true

        withContext(Dispatchers.IO) {
            try {
                val channelConfig = AudioFormat.CHANNEL_OUT_MONO
                val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                // Scan for WAV "data" chunk to find PCM offset
                val isWav = audioData.size > 44 &&
                    audioData[0] == 'R'.code.toByte() &&
                    audioData[1] == 'I'.code.toByte() &&
                    audioData[2] == 'F'.code.toByte() &&
                    audioData[3] == 'F'.code.toByte()

                val headerSize = if (isWav) {
                    var offset = 12
                    var dataStart = -1
                    while (offset + 8 <= audioData.size) {
                        val chunkId = String(audioData, offset, 4, Charsets.US_ASCII)
                        val chunkSize = (audioData[offset + 4].toInt() and 0xFF) or
                            ((audioData[offset + 5].toInt() and 0xFF) shl 8) or
                            ((audioData[offset + 6].toInt() and 0xFF) shl 16) or
                            ((audioData[offset + 7].toInt() and 0xFF) shl 24)
                        if (chunkId == "data") {
                            dataStart = offset + 8
                            break
                        }
                        offset += 8 + chunkSize
                    }
                    if (dataStart > 0) dataStart else 44
                } else {
                    0
                }

                val pcmData = audioData.copyOfRange(headerSize, audioData.size)
                val bufferSize = AudioTrack.getMinBufferSize(ttsSampleRate, channelConfig, audioFormat)

                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(audioFormat)
                            .setSampleRate(ttsSampleRate)
                            .setChannelMask(channelConfig)
                            .build(),
                    )
                    .setBufferSizeInBytes(bufferSize.coerceAtLeast(pcmData.size))
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                track.write(pcmData, 0, pcmData.size)
                track.play()

                val durationMs = (pcmData.size.toDouble() / (ttsSampleRate * 2) * 1000).toLong()
                var elapsed = 0L
                while (isPlayingAudio && elapsed < durationMs && track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    delay(100)
                    elapsed += 100
                }

                try {
                    track.stop()
                    track.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping AudioTrack: ${e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Audio playback error", e)
            }
        }
    }

    private fun stopAudioPlayback() {
        isPlayingAudio = false
        audioPlaybackJob?.cancel()
        audioPlaybackJob = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping AudioTrack: ${e.message}")
        }
        audioTrack = null
    }

    // -- SDK event handling --

    private fun subscribeToSDKEvents() {
        eventSubscriptionJob?.cancel()
        eventSubscriptionJob = viewModelScope.launch {
            EventBus.events.collect { event -> handleSDKEvent(event) }
        }
    }

    private fun handleSDKEvent(event: SDKEvent) {
        when (event) {
            is ModelEvent -> {
                when (event.eventType) {
                    ModelEvent.ModelEventType.LOADED -> {
                        when (event.category) {
                            EventCategory.LLM -> updateReady {
                                copy(
                                    llmLoadState = VoiceModelLoadState.LOADED,
                                    llmModel = llmModel ?: VoiceSelectedModel("llamacpp", event.modelId, event.modelId),
                                )
                            }
                            EventCategory.STT -> updateReady {
                                copy(
                                    sttLoadState = VoiceModelLoadState.LOADED,
                                    sttModel = sttModel ?: VoiceSelectedModel("whisper", event.modelId, event.modelId),
                                )
                            }
                            EventCategory.TTS -> updateReady {
                                copy(
                                    ttsLoadState = VoiceModelLoadState.LOADED,
                                    ttsModel = ttsModel ?: VoiceSelectedModel("tts", event.modelId, event.modelId),
                                )
                            }
                            else -> { /* ignore */ }
                        }
                    }
                    ModelEvent.ModelEventType.UNLOADED -> {
                        when (event.category) {
                            EventCategory.LLM -> updateReady {
                                copy(llmLoadState = VoiceModelLoadState.NOT_LOADED, llmModel = null)
                            }
                            EventCategory.STT -> updateReady {
                                copy(sttLoadState = VoiceModelLoadState.NOT_LOADED, sttModel = null)
                            }
                            EventCategory.TTS -> updateReady {
                                copy(ttsLoadState = VoiceModelLoadState.NOT_LOADED, ttsModel = null)
                            }
                            else -> { /* ignore */ }
                        }
                    }
                    else -> { /* ignore */ }
                }
            }
            else -> { /* ignore */ }
        }
    }

    private fun handleVoiceSessionEvent(event: VoiceSessionEvent) {
        when (event) {
            is VoiceSessionEvent.Started -> {
                updateReady { copy(agentState = VoiceAgentState.LISTENING, isListening = true) }
            }
            is VoiceSessionEvent.Listening -> {
                updateReady { copy(audioLevel = event.audioLevel) }
            }
            is VoiceSessionEvent.SpeechStarted -> {
                updateReady { copy(isSpeechDetected = true) }
            }
            is VoiceSessionEvent.Processing -> {
                updateReady { copy(agentState = VoiceAgentState.THINKING, isSpeechDetected = false) }
            }
            is VoiceSessionEvent.Transcribed -> {
                updateReady { copy(currentTranscript = event.text) }
            }
            is VoiceSessionEvent.Responded -> {
                updateReady { copy(assistantResponse = event.text) }
            }
            is VoiceSessionEvent.Speaking -> {
                updateReady { copy(agentState = VoiceAgentState.SPEAKING) }
            }
            is VoiceSessionEvent.TurnCompleted -> {
                updateReady {
                    copy(
                        currentTranscript = event.transcript,
                        assistantResponse = event.response,
                        agentState = VoiceAgentState.LISTENING,
                        isListening = true,
                    )
                }
            }
            is VoiceSessionEvent.Stopped -> {
                updateReady { copy(agentState = VoiceAgentState.IDLE, isListening = false) }
            }
            is VoiceSessionEvent.Error -> {
                updateReady { copy(error = event.message) }
            }
        }
    }

    private suspend fun syncModelStates() {
        try {
            val states = RunAnywhere.voiceAgentComponentStates()

            val sttModelId = (states.stt as? ComponentLoadState.Loaded)?.loadedModelId
            val llmModelId = (states.llm as? ComponentLoadState.Loaded)?.loadedModelId
            val ttsModelId = (states.tts as? ComponentLoadState.Loaded)?.loadedModelId

            updateReady {
                copy(
                    sttLoadState = mapLoadState(states.stt),
                    llmLoadState = mapLoadState(states.llm),
                    ttsLoadState = mapLoadState(states.tts),
                    sttModel = sttModel ?: sttModelId?.let { id ->
                        VoiceSelectedModel("ONNX Runtime", id, id)
                    },
                    llmModel = llmModel ?: llmModelId?.let { id ->
                        VoiceSelectedModel("llamacpp", id, id)
                    },
                    ttsModel = ttsModel ?: ttsModelId?.let { id ->
                        VoiceSelectedModel("ONNX Runtime", id, id)
                    },
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not sync model states: ${e.message}")
        }
    }

    private fun mapLoadState(state: ComponentLoadState): VoiceModelLoadState =
        when (state) {
            is ComponentLoadState.NotLoaded -> VoiceModelLoadState.NOT_LOADED
            is ComponentLoadState.Loading -> VoiceModelLoadState.LOADING
            is ComponentLoadState.Loaded -> VoiceModelLoadState.LOADED
            is ComponentLoadState.Error -> VoiceModelLoadState.ERROR
        }

    /** Atomically update the [VoiceUiState.Ready] state. No-op if state is not Ready. */
    private inline fun updateReady(crossinline transform: VoiceUiState.Ready.() -> VoiceUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is VoiceUiState.Ready -> current.transform()
                else -> current
            }
        }
    }

    override fun onCleared() {
        eventSubscriptionJob?.cancel()
        pipelineJob?.cancel()
        audioRecordingJob?.cancel()
        silenceDetectionJob?.cancel()
        processingJob?.cancel()
        stopAudioPlayback()
        audioCaptureService?.release()
        audioCaptureService = null
        @Suppress("OPT_IN_USAGE")
        kotlinx.coroutines.GlobalScope.launch(Dispatchers.IO) {
            try {
                RunAnywhere.stopVoiceSession()
            } catch (_: Exception) { /* best-effort cleanup */ }
        }
        super.onCleared()
    }

    companion object {
        private const val TAG = "VoiceAssistantVM"
        /** Keep voice responses concise — short enough to speak naturally. */
        private const val VOICE_MAX_TOKENS = 256
    }
}
