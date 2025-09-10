package com.runanywhere.runanywhereai.domain.services

import android.content.Context
import com.runanywhere.runanywhereai.domain.models.*
import com.runanywhere.sdk.RunAnywhere
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTInput
import com.runanywhere.sdk.components.stt.AudioFormat
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADInput
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Orchestrates the complete voice pipeline matching iOS VoiceAssistantService
 * VAD -> STT -> LLM -> TTS
 */
class VoicePipelineService(
    private val context: Context,
    private val ttsService: AndroidTTSService = AndroidTTSService(context)
) {

    private val audioCapture = AudioCaptureService(context)
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Pipeline components from KMP SDK
    private var vadComponent: VADComponent? = null
    private var sttComponent: STTComponent? = null

    // Event flow for pipeline events
    private val _pipelineEvents = MutableSharedFlow<VoicePipelineEvent>()
    val pipelineEvents: SharedFlow<VoicePipelineEvent> = _pipelineEvents.asSharedFlow()

    // Audio level for visualization
    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    // Pipeline state
    private val _isActive = MutableStateFlow(false)
    val isActive: StateFlow<Boolean> = _isActive.asStateFlow()

    private var captureJob: Job? = null
    private var processingJob: Job? = null

    // Audio buffer for STT
    private val audioBuffer = ByteArrayOutputStream()
    private var isSpeaking = false
    private var lastSpeechTime = 0L

    /**
     * Initialize the pipeline with configuration
     */
    suspend fun initialize(config: ModularPipelineConfig) {
        try {
            // Initialize VAD component
            if (config.components.contains(PipelineComponent.VAD)) {
                val vadConfig = VADConfiguration(
                    energyThreshold = config.vadConfig.sensitivity, // Map sensitivity to energy threshold
                    sampleRate = 16000,
                    frameLength = config.vadConfig.minSpeechDuration / 1000f // Convert ms to seconds
                )
                vadComponent = VADComponent(vadConfig).apply {
                    initialize()
                }
            }

            // Initialize STT component
            if (config.components.contains(PipelineComponent.STT)) {
                val sttConfig = STTConfiguration(
                    modelId = config.sttConfig.modelId,
                    language = config.sttConfig.language,
                    enablePunctuation = true,
                    enableTimestamps = true
                )
                sttComponent = STTComponent(sttConfig).apply {
                    initialize()
                }
            }

            // Initialize TTS
            if (config.components.contains(PipelineComponent.TTS)) {
                ttsService.initialize(config.ttsConfig.voice)
            }

        } catch (e: Exception) {
            _pipelineEvents.emit(VoicePipelineEvent.Error("Failed to initialize pipeline: ${e.message}"))
            throw e
        }
    }

    /**
     * Start the voice pipeline
     */
    suspend fun startPipeline() {
        if (_isActive.value) return

        _isActive.value = true
        audioBuffer.reset()

        // Start audio capture
        captureJob = scope.launch {
            audioCapture.startCapture()
                .catch { e ->
                    _pipelineEvents.emit(VoicePipelineEvent.Error("Audio capture error: ${e.message}"))
                }
                .collect { audioData ->
                    processAudioChunk(audioData)
                }
        }
    }

    /**
     * Convert ByteArray to FloatArray for VAD processing
     */
    private fun bytesToFloats(bytes: ByteArray): FloatArray {
        val shorts = ShortArray(bytes.size / 2)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        return FloatArray(shorts.size) { i ->
            shorts[i].toFloat() / Short.MAX_VALUE.toFloat()
        }
    }

    /**
     * Process audio chunk through VAD and accumulate for STT
     */
    private suspend fun processAudioChunk(audioData: ByteArray) {
        // Update audio level for visualization
        val rms = audioCapture.calculateRMS(audioData)
        _audioLevel.value = rms

        // Convert bytes to floats for VAD
        val audioFloats = bytesToFloats(audioData)

        // Process through VAD if available
        val vadResult = vadComponent?.processAudioChunk(VADInput(audioFloats))

        when {
            vadResult?.isSpeechDetected == true -> {
                if (!isSpeaking) {
                    isSpeaking = true
                    _pipelineEvents.emit(VoicePipelineEvent.VADSpeechStart)
                    audioBuffer.reset()
                }
                // Accumulate audio for STT
                audioBuffer.write(audioData)
                lastSpeechTime = System.currentTimeMillis()
            }
            vadResult?.isSpeechDetected == false -> {
                if (isSpeaking && System.currentTimeMillis() - lastSpeechTime > 500) {
                    isSpeaking = false
                    _pipelineEvents.emit(VoicePipelineEvent.VADSpeechEnd)

                    // Process accumulated audio through STT
                    val audioForSTT = audioBuffer.toByteArray()
                    if (audioForSTT.isNotEmpty()) {
                        processSTT(audioForSTT)
                    }
                }
            }
            else -> {
                // No VAD, accumulate all audio
                audioBuffer.write(audioData)
            }
        }
    }

    /**
     * Process audio through STT
     */
    private suspend fun processSTT(audioData: ByteArray) {
        try {
            val sttInput = STTInput(
                audioData = audioData,
                format = AudioFormat.PCM,
                language = "en-US"
            )

            val transcriptionResult = sttComponent?.transcribe(sttInput)

            if (transcriptionResult != null && transcriptionResult.text.isNotBlank()) {
                _pipelineEvents.emit(
                    VoicePipelineEvent.STTFinalTranscript(
                        text = transcriptionResult.text,
                        confidence = transcriptionResult.confidence
                    )
                )

                // Process through LLM
                processLLM(transcriptionResult.text)
            }
        } catch (e: Exception) {
            _pipelineEvents.emit(VoicePipelineEvent.Error("STT error: ${e.message}"))
        }
    }

    /**
     * Process text through LLM
     */
    private suspend fun processLLM(userInput: String) {
        try {
            val options = RunAnywhereGenerationOptions(
                modelId = "llama3.2-3b",
                maxTokens = 150,
                temperature = 0.7,
                stream = false
            )

            val response = RunAnywhere.generate(userInput, options)

            _pipelineEvents.emit(
                VoicePipelineEvent.LLMResponse(
                    text = response.text,
                    thinking = response.thinking
                )
            )

            // Process through TTS
            if (response.text.isNotBlank()) {
                processTTS(response.text)
            }
        } catch (e: Exception) {
            _pipelineEvents.emit(VoicePipelineEvent.Error("LLM error: ${e.message}"))
        }
    }

    /**
     * Process text through TTS
     */
    private suspend fun processTTS(text: String) {
        try {
            _pipelineEvents.emit(VoicePipelineEvent.TTSStart(text))

            ttsService.speak(text) {
                scope.launch {
                    _pipelineEvents.emit(VoicePipelineEvent.TTSComplete)
                }
            }
        } catch (e: Exception) {
            _pipelineEvents.emit(VoicePipelineEvent.Error("TTS error: ${e.message}"))
        }
    }

    /**
     * Stop the voice pipeline
     */
    fun stopPipeline() {
        _isActive.value = false
        captureJob?.cancel()
        processingJob?.cancel()
        audioCapture.stopCapture()
        ttsService.stop()
        audioBuffer.reset()
        isSpeaking = false
    }

    /**
     * Manual push-to-talk mode
     */
    suspend fun startListening() {
        if (!_isActive.value) {
            startPipeline()
        }
    }

    suspend fun stopListening() {
        if (audioBuffer.size() > 0) {
            val audioData = audioBuffer.toByteArray()
            audioBuffer.reset()
            processSTT(audioData)
        }
        stopPipeline()
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopPipeline()
        scope.cancel()
        audioCapture.release()
        ttsService.shutdown()

        // Clean up components in coroutine scope
        scope.launch {
            vadComponent?.cleanup()
            sttComponent?.cleanup()
        }
    }
}
