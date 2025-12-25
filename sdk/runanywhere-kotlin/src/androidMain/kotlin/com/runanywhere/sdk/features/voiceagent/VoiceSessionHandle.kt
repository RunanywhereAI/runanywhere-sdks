package com.runanywhere.sdk.features.voiceagent

import com.runanywhere.sdk.core.AudioUtils
import com.runanywhere.sdk.features.stt.AudioChunk
import com.runanywhere.sdk.features.stt.AndroidAudioCaptureManager
import com.runanywhere.sdk.features.tts.AudioPlaybackManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.initializeVoiceAgentWithLoadedModels
import com.runanywhere.sdk.public.extensions.isVoiceAgentReady
import com.runanywhere.sdk.public.extensions.processVoiceTurn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.sqrt

/**
 * Handle to control an active voice session.
 * Matches iOS VoiceSessionHandle exactly.
 *
 * This class manages the complete voice conversation loop:
 * 1. Audio capture
 * 2. Real-time speech detection (energy-based VAD)
 * 3. Audio buffering during speech
 * 4. Processing when speech ends (STT → LLM → TTS)
 * 5. Audio playback of response
 *
 * Usage:
 * ```kotlin
 * val session = RunAnywhere.startVoiceSession()
 * session.events.collect { event ->
 *     when (event) {
 *         is VoiceSessionEvent.Listening -> updateAudioMeter(event.audioLevel)
 *         is VoiceSessionEvent.SpeechStarted -> showSpeechIndicator()
 *         is VoiceSessionEvent.Processing -> showProcessingIndicator()
 *         is VoiceSessionEvent.TurnCompleted -> updateUI(event.transcript, event.response)
 *         else -> {}
 *     }
 * }
 * ```
 */
actual class VoiceSessionHandle actual constructor(
    private val config: VoiceSessionConfig,
) {
    private val logger = SDKLogger("VoiceSession")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Audio capture and playback
    private var audioCapture: AndroidAudioCaptureManager? = null
    private val audioPlayback = AudioPlaybackManager()

    // State
    private var isRunning = false
    private var audioBuffer = mutableListOf<ByteArray>()
    private var lastSpeechTime: Long = 0
    private var isSpeechActive = false

    // Jobs
    private var captureJob: Job? = null
    private var monitorJob: Job? = null

    // Event flow
    private val _events = MutableSharedFlow<VoiceSessionEvent>(replay = 1)

    /** Stream of session events */
    actual val events: Flow<VoiceSessionEvent> = _events.asSharedFlow()

    // Audio level tracking
    private var currentAudioLevel: Float = 0f

    /**
     * Start the voice session
     */
    actual suspend fun start() {
        if (isRunning) {
            throw VoiceSessionError.AlreadyRunning
        }

        logger.info("Starting voice session (speechThreshold: ${config.speechThreshold}, silenceDuration: ${config.silenceDuration}s)")

        // Verify voice agent is ready, or try to initialize
        if (!RunAnywhere.isVoiceAgentReady) {
            try {
                RunAnywhere.initializeVoiceAgentWithLoadedModels()
            } catch (e: Exception) {
                emit(VoiceSessionEvent.Error("Voice agent not ready: ${e.message}"))
                throw e
            }
        }

        // Initialize audio capture
        audioCapture = AndroidAudioCaptureManager()

        // Check permission
        if (!audioCapture!!.hasPermission()) {
            emit(VoiceSessionEvent.Error("Microphone permission denied"))
            throw VoiceSessionError.MicrophonePermissionDenied
        }

        isRunning = true
        emit(VoiceSessionEvent.Started)

        // Start listening
        startListening()
    }

    /**
     * Stop the voice session
     */
    actual fun stop() {
        if (!isRunning) return

        logger.info("Stopping voice session")

        isRunning = false

        // Cancel jobs
        captureJob?.cancel()
        monitorJob?.cancel()
        captureJob = null
        monitorJob = null

        // Stop audio capture and playback
        audioCapture?.stopRecording()
        audioCapture = null
        audioPlayback.stop()

        // Clear state
        audioBuffer.clear()
        isSpeechActive = false
        lastSpeechTime = 0
        currentAudioLevel = 0f

        emit(VoiceSessionEvent.Stopped)
    }

    /**
     * Force process current audio (push-to-talk)
     */
    actual suspend fun sendNow() {
        if (!isRunning) return
        isSpeechActive = false

        // Copy buffer and process
        val audioToProcess = audioBuffer.toList()
        audioBuffer.clear()

        if (audioToProcess.isNotEmpty()) {
            processCurrentAudio(audioToProcess)
        }
    }

    // MARK: - Private

    private fun emit(event: VoiceSessionEvent) {
        scope.launch {
            _events.emit(event)
        }
    }

    private fun startListening() {
        audioBuffer.clear()
        lastSpeechTime = 0
        isSpeechActive = false

        logger.debug("Starting audio capture and speech detection")

        // Start audio capture
        captureJob =
            scope.launch {
                try {
                    audioCapture?.startRecording()?.collect { chunk: AudioChunk ->
                        if (isRunning) {
                            handleAudioData(chunk.data)
                        }
                    }
                } catch (e: Exception) {
                    if (isRunning) {
                        logger.error("Audio capture error: ${e.message}")
                        emit(VoiceSessionEvent.Error("Audio capture failed: ${e.message}"))
                    }
                }
            }

        // Start speech detection monitoring
        monitorJob =
            scope.launch {
                while (isActive && isRunning) {
                    checkSpeechState()
                    delay(50) // 50ms check interval
                }
            }
    }

    private fun handleAudioData(data: ByteArray) {
        if (!isRunning) return

        // Calculate audio level (RMS energy)
        val samples = AudioUtils.pcmBytesToFloatSamples(data)
        currentAudioLevel = calculateRmsEnergy(samples)

        // Always buffer audio when speech is active
        if (isSpeechActive) {
            audioBuffer.add(data)
        }
    }

    private suspend fun checkSpeechState() {
        if (!isRunning) return

        val level = currentAudioLevel

        // Emit audio level for UI visualization
        emit(VoiceSessionEvent.Listening(level))

        if (level > config.speechThreshold) {
            // Speech detected
            if (!isSpeechActive) {
                logger.info("🎤 Speech started (level: ${String.format("%.4f", level)}, threshold: ${config.speechThreshold})")
                isSpeechActive = true
                audioBuffer.clear() // Start fresh buffer
                emit(VoiceSessionEvent.SpeechStarted)
            }
            lastSpeechTime = System.currentTimeMillis()
        } else if (isSpeechActive) {
            // Check if silence duration exceeded
            val silenceMs = System.currentTimeMillis() - lastSpeechTime
            val silenceThresholdMs = (config.silenceDuration * 1000).toLong()

            if (silenceMs > silenceThresholdMs) {
                logger.info("🔇 Speech ended after ${silenceMs}ms silence")
                isSpeechActive = false

                // Only process if we have enough audio (~0.5s at 16kHz, 2 bytes per sample)
                val totalBytes = audioBuffer.sumOf { it.size }
                if (totalBytes > 16000) {
                    // Copy buffer and clear for next capture
                    val audioToProcess = audioBuffer.toList()
                    audioBuffer.clear()

                    // Launch processing in a separate coroutine to avoid canceling ourselves
                    scope.launch {
                        processCurrentAudio(audioToProcess)
                    }
                } else {
                    logger.debug("Not enough audio to process ($totalBytes bytes), minimum is 16000")
                    audioBuffer.clear()
                }
            }
        }
    }

    private suspend fun processCurrentAudio(audioChunks: List<ByteArray>) {
        // Combine audio buffer
        val totalSize = audioChunks.sumOf { it.size }
        val combinedAudio = ByteArray(totalSize)
        var offset = 0
        audioChunks.forEach { chunk ->
            chunk.copyInto(combinedAudio, offset)
            offset += chunk.size
        }

        if (combinedAudio.isEmpty() || !isRunning) return

        logger.info("Processing ${combinedAudio.size} bytes of audio (~${combinedAudio.size / 32000.0}s)")

        // Stop audio capture properly before processing
        audioCapture?.stopRecording()

        // Wait for capture job to finish naturally
        captureJob?.join()
        captureJob = null

        // Cancel the monitor job (we'll restart it after processing)
        monitorJob?.cancel()
        monitorJob = null

        emit(VoiceSessionEvent.Processing)

        try {
            val result = RunAnywhere.processVoiceTurn(combinedAudio)

            if (!result.speechDetected) {
                logger.info("No speech detected in audio")
                if (config.continuousMode && isRunning) {
                    startListening()
                }
                return
            }

            // Emit intermediate results
            result.transcription?.let { transcript ->
                logger.info("📝 Transcription: $transcript")
                emit(VoiceSessionEvent.Transcribed(transcript))
            }

            result.response?.let { response ->
                logger.info("🤖 Response: ${response.take(100)}...")
                emit(VoiceSessionEvent.Responded(response))
            }

            // Play TTS if enabled
            if (config.autoPlayTTS && result.synthesizedAudio != null && result.synthesizedAudio.isNotEmpty()) {
                emit(VoiceSessionEvent.Speaking)
                try {
                    logger.info("🔊 Playing TTS audio: ${result.synthesizedAudio.size} bytes")
                    audioPlayback.play(result.synthesizedAudio)
                    logger.info("🔊 TTS playback completed")
                } catch (e: Exception) {
                    logger.error("TTS playback failed: ${e.message}")
                    // Continue even if playback fails
                }
            }

            // Emit complete result
            emit(
                VoiceSessionEvent.TurnCompleted(
                    transcript = result.transcription ?: "",
                    response = result.response ?: "",
                    audio = result.synthesizedAudio,
                ),
            )
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) {
                logger.debug("Processing was cancelled")
                throw e
            }
            logger.error("Processing failed: ${e.message}")
            emit(VoiceSessionEvent.Error(e.message ?: "Processing failed"))
        }

        // Resume listening if continuous mode
        if (config.continuousMode && isRunning) {
            startListening()
        }
    }

    private fun calculateRmsEnergy(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0f
        var sum = 0f
        for (sample in samples) {
            sum += sample * sample
        }
        return sqrt(sum / samples.size)
    }
}
