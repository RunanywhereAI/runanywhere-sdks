package com.runanywhere.sdk.components.voiceagent

import com.runanywhere.sdk.components.base.ComponentConfiguration
import com.runanywhere.sdk.components.base.ComponentOutput
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.TTSConfiguration
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

// MARK: - VoiceAgent Configuration

/**
 * Configuration for the VoiceAgent component - aggregates all sub-component configurations
 * Matches iOS VoiceAgentConfiguration exactly
 * Note: Not serializable because sub-component configurations are not serializable
 */
data class VoiceAgentConfiguration(
    // Sub-component configurations matching iOS structure
    val vadConfig: VADConfiguration = VADConfiguration(),
    val sttConfig: STTConfiguration = STTConfiguration(),
    val llmConfig: LLMConfiguration = LLMConfiguration(),
    val ttsConfig: TTSConfiguration = TTSConfiguration()
) : ComponentConfiguration {

    /** The component type for this configuration */
    val componentType: SDKComponent
        get() = SDKComponent.VOICE_AGENT

    /** VoiceAgent doesn't have its own model - it orchestrates sub-components */
    val modelId: String?
        get() = null

    override fun validate() {
        // Validate all sub-component configurations
        vadConfig.validate()
        sttConfig.validate()
        llmConfig.validate()
        ttsConfig.validate()
    }
}

// MARK: - VoiceAgent Result

/**
 * Result from processing audio through the VoiceAgent pipeline
 * Matches iOS VoiceAgentResult structure exactly
 */
@Serializable
data class VoiceAgentResult(
    /** Whether speech was detected by VAD */
    val speechDetected: Boolean = false,

    /** Transcription from STT (null if no speech or STT not run) */
    val transcription: String? = null,

    /** LLM response text (null if transcription empty or LLM not run) */
    val response: String? = null,

    /** Synthesized audio from TTS (null if no response or TTS not run) */
    val synthesizedAudio: ByteArray? = null,

    /** Processing timestamp */
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput {

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as VoiceAgentResult

        if (speechDetected != other.speechDetected) return false
        if (transcription != other.transcription) return false
        if (response != other.response) return false
        if (synthesizedAudio != null) {
            if (other.synthesizedAudio == null) return false
            if (!synthesizedAudio.contentEquals(other.synthesizedAudio)) return false
        } else if (other.synthesizedAudio != null) return false
        if (timestamp != other.timestamp) return false

        return true
    }

    override fun hashCode(): Int {
        var result = speechDetected.hashCode()
        result = 31 * result + (transcription?.hashCode() ?: 0)
        result = 31 * result + (response?.hashCode() ?: 0)
        result = 31 * result + (synthesizedAudio?.contentHashCode() ?: 0)
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

// MARK: - VoiceAgent Events (for streaming)

/**
 * Events emitted during streaming VoiceAgent processing
 * Matches iOS VoiceAgentEvent enum exactly
 */
sealed class VoiceAgentEvent {
    /** Full pipeline result */
    data class Processed(val result: VoiceAgentResult) : VoiceAgentEvent()

    /** VAD detection result */
    data class VadTriggered(val speechDetected: Boolean) : VoiceAgentEvent()

    /** STT transcription available */
    data class TranscriptionAvailable(val text: String) : VoiceAgentEvent()

    /** LLM response generated */
    data class ResponseGenerated(val text: String) : VoiceAgentEvent()

    /** TTS audio synthesized */
    data class AudioSynthesized(val data: ByteArray) : VoiceAgentEvent() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is AudioSynthesized) return false
            return data.contentEquals(other.data)
        }

        override fun hashCode(): Int = data.contentHashCode()
    }

    /** Pipeline error */
    data class Error(val error: Throwable) : VoiceAgentEvent()
}

// MARK: - VoiceAgent Service

/**
 * Simple service wrapper for VoiceAgent
 * VoiceAgent doesn't need an external service - it orchestrates other components
 * Matches iOS VoiceAgentService
 */
class VoiceAgentService {
    // No-op service - VoiceAgent orchestrates other component services
}

// MARK: - VoiceAgent Errors

/**
 * Errors specific to VoiceAgent processing
 */
sealed class VoiceAgentError : Exception() {
    /** Pipeline not initialized */
    object PipelineNotInitialized : VoiceAgentError() {
        override val message: String = "VoiceAgent pipeline is not initialized"
    }

    /** VAD component failed */
    data class VADFailed(override val cause: Throwable) : VoiceAgentError() {
        override val message: String = "VAD processing failed: ${cause.message}"
    }

    /** STT component failed */
    data class STTFailed(override val cause: Throwable) : VoiceAgentError() {
        override val message: String = "STT transcription failed: ${cause.message}"
    }

    /** LLM component failed */
    data class LLMFailed(override val cause: Throwable) : VoiceAgentError() {
        override val message: String = "LLM generation failed: ${cause.message}"
    }

    /** TTS component failed */
    data class TTSFailed(override val cause: Throwable) : VoiceAgentError() {
        override val message: String = "TTS synthesis failed: ${cause.message}"
    }

    /** Sub-component initialization failed */
    data class ComponentInitializationFailed(
        val componentName: String,
        override val cause: Throwable
    ) : VoiceAgentError() {
        override val message: String = "Failed to initialize $componentName: ${cause.message}"
    }
}

// MARK: - Pipeline State

/**
 * Tracks the current state of the VoiceAgent pipeline
 */
enum class VoiceAgentPipelineState {
    IDLE,
    VAD_PROCESSING,
    STT_PROCESSING,
    LLM_PROCESSING,
    TTS_PROCESSING,
    COMPLETED,
    ERROR
}
