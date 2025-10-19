package com.runanywhere.sdk.voice

import com.runanywhere.sdk.audio.VoiceAudioChunk
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.llm.LLMComponent
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationComponent
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationConfiguration
import com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationInput
import com.runanywhere.sdk.components.stt.AudioFormat
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.events.ModularPipelineEvent
import com.runanywhere.sdk.events.SpeakerInfo
import com.runanywhere.sdk.public.ModularPipelineConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Modular voice pipeline that orchestrates individual components
 * Matches iOS ModularVoicePipeline exactly
 */
class ModularVoicePipeline(
    private val config: ModularPipelineConfig
) {
    private var vadComponent: VADComponent? = null
    private var sttComponent: STTComponent? = null
    private var llmComponent: LLMComponent? = null
    private var speakerDiarizationComponent: SpeakerDiarizationComponent? = null

    // Diarization state
    private var enableDiarization = false
    private var enableContinuousMode = false

    // TTS handler (to be set by platform-specific code)
    private var ttsHandler: TTSHandler? = null

    /**
     * Enable or disable speaker diarization
     */
    fun enableSpeakerDiarization(enabled: Boolean) {
        enableDiarization = enabled
    }

    /**
     * Enable or disable continuous mode
     */
    fun enableContinuousMode(enabled: Boolean) {
        enableContinuousMode = enabled
    }

    /**
     * Set TTS handler (platform-specific)
     */
    fun setTTSHandler(handler: TTSHandler) {
        this.ttsHandler = handler
    }

    /**
     * Initialize all components
     * Returns a flow of initialization events
     */
    fun initializeComponents(): Flow<ModularPipelineEvent> = flow {
        try {
            // Initialize VAD
            if (config.components.contains(SDKComponent.VAD) && config.vadConfig != null) {
                emit(ModularPipelineEvent.componentInitializing("VAD"))
                vadComponent = VADComponent(config.vadConfig)
                vadComponent?.initialize()
                emit(ModularPipelineEvent.componentInitialized("VAD"))
            }

            // Initialize STT
            if (config.components.contains(SDKComponent.STT) && config.sttConfig != null) {
                emit(ModularPipelineEvent.componentInitializing("STT"))
                sttComponent = STTComponent(config.sttConfig)
                sttComponent?.initialize()
                emit(ModularPipelineEvent.componentInitialized("STT"))
            }

            // Initialize LLM
            if (config.components.contains(SDKComponent.LLM) && config.llmConfig != null) {
                emit(ModularPipelineEvent.componentInitializing("LLM"))
                llmComponent = LLMComponent(config.llmConfig)
                llmComponent?.initialize()
                emit(ModularPipelineEvent.componentInitialized("LLM"))
            }

            // Initialize TTS (delegated to platform-specific handler)
            if (config.components.contains(SDKComponent.TTS) && config.ttsConfig != null) {
                emit(ModularPipelineEvent.componentInitializing("TTS"))
                ttsHandler?.initialize()
                emit(ModularPipelineEvent.componentInitialized("TTS"))
            }

            // Initialize Speaker Diarization if needed
            if (config.components.contains(SDKComponent.SPEAKER_DIARIZATION)) {
                emit(ModularPipelineEvent.componentInitializing("SpeakerDiarization"))
                val diarizationConfig = SpeakerDiarizationConfiguration()
                speakerDiarizationComponent = SpeakerDiarizationComponent(diarizationConfig)
                speakerDiarizationComponent?.initialize()
                emit(ModularPipelineEvent.componentInitialized("SpeakerDiarization"))
            }

            emit(ModularPipelineEvent.allComponentsInitialized)

        } catch (error: Exception) {
            emit(ModularPipelineEvent.pipelineError(error))
            throw error
        }
    }

    /**
     * Process audio stream through the pipeline
     * Matches iOS implementation logic
     */
    fun process(audioStream: Flow<VoiceAudioChunk>): Flow<ModularPipelineEvent> = flow {
        try {
            var currentSpeaker: SpeakerInfo? = null
            val audioBuffer = mutableListOf<Float>()
            var isSpeaking = false

            emit(ModularPipelineEvent.pipelineStarted)

            audioStream.collect { voiceChunk ->
                val floatSamples = voiceChunk.samples
                val timestamp = voiceChunk.timestamp

                // Process through VAD if available
                var speechDetected = false
                vadComponent?.let { vad ->
                    val vadResult = vad.detectSpeech(floatSamples)
                    speechDetected = vadResult.isSpeechDetected

                    if (speechDetected && !isSpeaking) {
                        // Speech just started
                        emit(ModularPipelineEvent.vadSpeechStart)
                        isSpeaking = true
                        audioBuffer.clear()
                    } else if (!speechDetected && isSpeaking) {
                        // Speech just ended
                        emit(ModularPipelineEvent.vadSpeechEnd)
                        isSpeaking = false

                        // Process accumulated audio through STT
                        if (audioBuffer.isNotEmpty()) {
                            processSTT(audioBuffer.toFloatArray())?.let { transcript ->
                                // Emit transcript with or without speaker info
                                if (enableDiarization && currentSpeaker != null) {
                                    emit(
                                        ModularPipelineEvent.sttFinalTranscriptWithSpeaker(
                                            transcript,
                                            currentSpeaker!!
                                        )
                                    )
                                } else {
                                    emit(ModularPipelineEvent.sttFinalTranscript(transcript))
                                }

                                // Process through LLM if available
                                llmComponent?.let { llm ->
                                    emit(ModularPipelineEvent.llmThinking)

                                    // Generate response
                                    val response = llm.generate(transcript).text
                                    emit(ModularPipelineEvent.llmFinalResponse(response))

                                    // Process through TTS if available
                                    ttsHandler?.let { tts ->
                                        emit(ModularPipelineEvent.ttsStarted)
                                        tts.synthesize(response)
                                        emit(ModularPipelineEvent.ttsCompleted)
                                    }
                                }
                            }
                        }

                        audioBuffer.clear()
                    }
                }

                // Accumulate audio if speaking
                if (isSpeaking || vadComponent == null) {
                    audioBuffer.addAll(floatSamples.toList())
                }

                // TODO: Implement speaker diarization processing
                // Speaker diarization would be processed here when fully implemented
            }

            emit(ModularPipelineEvent.pipelineCompleted)

        } catch (error: Exception) {
            emit(ModularPipelineEvent.pipelineError(error))
            throw error
        }
    }

    /**
     * Process audio through STT
     * Returns the transcribed text or null if failed
     */
    private suspend fun processSTT(audioSamples: FloatArray): String? {
        return try {
            sttComponent?.let { stt ->
                // Convert float samples to PCM bytes
                val audioBytes = floatSamplesToBytes(audioSamples)

                // Transcribe with configured language
                val language = config.sttConfig?.language ?: "en-US"
                val result = stt.transcribe(
                    audioData = audioBytes,
                    format = AudioFormat.PCM,
                    language = language
                )

                result.text.takeIf { it.isNotBlank() }
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Convert float samples [-1.0, 1.0] to PCM 16-bit bytes
     */
    private fun floatSamplesToBytes(samples: FloatArray): ByteArray {
        val bytes = ByteArray(samples.size * 2)
        for (i in samples.indices) {
            val sample16 = (samples[i] * 32767f).toInt().coerceIn(-32768, 32767)
            bytes[i * 2] = (sample16 and 0xFF).toByte()
            bytes[i * 2 + 1] = ((sample16 shr 8) and 0xFF).toByte()
        }
        return bytes
    }

    /**
     * Cleanup all components
     */
    suspend fun cleanup() {
        try {
            vadComponent?.cleanup()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }

        try {
            sttComponent?.cleanup()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }

        try {
            llmComponent?.cleanup()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }

        try {
            ttsHandler?.cleanup()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }

        try {
            speakerDiarizationComponent?.cleanup()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }
    }
}

/**
 * Platform-specific TTS handler interface
 * Implementations will handle platform-specific TTS details
 */
interface TTSHandler {
    suspend fun initialize()
    suspend fun synthesize(text: String)
    suspend fun cleanup()
}
