/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Consolidated voice agent and voice session types for public API.
 * Includes: configurations, states, results, events, and errors.
 *
 * Mirrors Swift VoiceAgentTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.VoiceAgent

import kotlinx.serialization.Serializable

// MARK: - Voice Agent Result

/**
 * Result from voice agent processing.
 * Contains all outputs from the voice pipeline: transcription, LLM response, and synthesized audio.
 *
 * Mirrors Swift VoiceAgentResult exactly.
 */
@Serializable
data class VoiceAgentResult(
    /** Whether speech was detected in the input audio */
    var speechDetected: Boolean = false,

    /** Transcribed text from STT */
    var transcription: String? = null,

    /** Generated response text from LLM */
    var response: String? = null,

    /** Synthesized audio data from TTS */
    @Serializable(with = ByteArraySerializer::class)
    var synthesizedAudio: ByteArray? = null
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as VoiceAgentResult
        return speechDetected == other.speechDetected &&
                transcription == other.transcription &&
                response == other.response &&
                synthesizedAudio.contentEquals(other.synthesizedAudio)
    }

    override fun hashCode(): Int {
        var result = speechDetected.hashCode()
        result = 31 * result + (transcription?.hashCode() ?: 0)
        result = 31 * result + (response?.hashCode() ?: 0)
        result = 31 * result + (synthesizedAudio?.contentHashCode() ?: 0)
        return result
    }
}

/**
 * Custom serializer for ByteArray (null-safe).
 */
object ByteArraySerializer : kotlinx.serialization.KSerializer<ByteArray?> {
    override val descriptor = kotlinx.serialization.descriptors.PrimitiveSerialDescriptor(
        "ByteArray",
        kotlinx.serialization.descriptors.PrimitiveKind.STRING
    )

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: ByteArray?) {
        if (value != null) {
            encoder.encodeString(value.joinToString(",") { it.toString() })
        } else {
            encoder.encodeString("")
        }
    }

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): ByteArray? {
        val string = decoder.decodeString()
        if (string.isEmpty()) return null
        return string.split(",").map { it.toByte() }.toByteArray()
    }
}

// MARK: - Component Load State

/**
 * Represents the loading state of a single model/voice component.
 * Mirrors Swift ComponentLoadState exactly.
 */
sealed class ComponentLoadState {
    data object NotLoaded : ComponentLoadState()
    data object Loading : ComponentLoadState()
    data class Loaded(val loadedModelId: String) : ComponentLoadState()
    data class Error(val message: String) : ComponentLoadState()

    /** Whether the component is currently loaded and ready to use */
    val isLoaded: Boolean get() = this is Loaded

    /** Whether the component is currently loading */
    val isLoading: Boolean get() = this is Loading

    /** Get the model ID if loaded */
    val modelId: String?
        get() = (this as? Loaded)?.loadedModelId
}

// MARK: - Voice Agent Component States

/**
 * Unified state of all voice agent components.
 * Mirrors Swift VoiceAgentComponentStates exactly.
 */
data class VoiceAgentComponentStates(
    /** Speech-to-Text component state */
    val stt: ComponentLoadState = ComponentLoadState.NotLoaded,

    /** Large Language Model component state */
    val llm: ComponentLoadState = ComponentLoadState.NotLoaded,

    /** Text-to-Speech component state */
    val tts: ComponentLoadState = ComponentLoadState.NotLoaded
) {
    /** Whether all components are loaded and the voice agent is ready to use */
    val isFullyReady: Boolean
        get() = stt.isLoaded && llm.isLoaded && tts.isLoaded

    /** Whether any component is currently loading */
    val isAnyLoading: Boolean
        get() = stt.isLoading || llm.isLoading || tts.isLoading

    /** Get a summary of which components are missing */
    val missingComponents: List<String>
        get() = buildList {
            if (!stt.isLoaded) add("STT")
            if (!llm.isLoaded) add("LLM")
            if (!tts.isLoaded) add("TTS")
        }
}

// MARK: - Voice Agent Configuration

/**
 * Configuration for the voice agent.
 * Uses C++ defaults via rac_voice_agent_config_t.
 *
 * Mirrors Swift VoiceAgentConfiguration exactly.
 */
@Serializable
data class VoiceAgentConfiguration(
    /** STT model ID (optional - uses currently loaded model if null) */
    val sttModelId: String? = null,

    /** LLM model ID (optional - uses currently loaded model if null) */
    val llmModelId: String? = null,

    /** TTS voice (optional - uses currently loaded voice if null) */
    val ttsVoice: String? = null,

    /** VAD sample rate */
    val vadSampleRate: Int = 16000,

    /** VAD frame length in seconds */
    val vadFrameLength: Float = 0.1f,

    /** VAD energy threshold */
    val vadEnergyThreshold: Float = 0.005f
)

// MARK: - Voice Session Events

/**
 * Events emitted during a voice session.
 * Mirrors Swift VoiceSessionEvent exactly.
 */
sealed class VoiceSessionEvent {
    /** Session started and ready */
    data object Started : VoiceSessionEvent()

    /** Listening for speech with current audio level (0.0 - 1.0) */
    data class Listening(val audioLevel: Float) : VoiceSessionEvent()

    /** Speech detected, started accumulating audio */
    data object SpeechStarted : VoiceSessionEvent()

    /** Speech ended, processing audio */
    data object Processing : VoiceSessionEvent()

    /** Got transcription from STT */
    data class Transcribed(val text: String) : VoiceSessionEvent()

    /** Got response from LLM */
    data class Responded(val text: String) : VoiceSessionEvent()

    /** Playing TTS audio */
    data object Speaking : VoiceSessionEvent()

    /** Complete turn result */
    data class TurnCompleted(
        val transcript: String,
        val response: String,
        val audio: ByteArray?
    ) : VoiceSessionEvent() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other == null || this::class != other::class) return false
            other as TurnCompleted
            return transcript == other.transcript &&
                    response == other.response &&
                    audio.contentEquals(other.audio)
        }

        override fun hashCode(): Int {
            var result = transcript.hashCode()
            result = 31 * result + response.hashCode()
            result = 31 * result + (audio?.contentHashCode() ?: 0)
            return result
        }
    }

    /** Session stopped */
    data object Stopped : VoiceSessionEvent()

    /** Error occurred */
    data class Error(val message: String) : VoiceSessionEvent()
}

// MARK: - Voice Session Configuration

/**
 * Configuration for voice session behavior.
 * Mirrors Swift VoiceSessionConfig exactly.
 */
@Serializable
data class VoiceSessionConfig(
    /** Silence duration (seconds) before processing speech */
    var silenceDuration: Double = 1.5,

    /** Minimum audio level to detect speech (0.0 - 1.0) */
    var speechThreshold: Float = 0.1f,

    /** Whether to auto-play TTS response */
    var autoPlayTTS: Boolean = true,

    /** Whether to auto-resume listening after TTS playback */
    var continuousMode: Boolean = true
) {
    companion object {
        /** Default configuration */
        val DEFAULT = VoiceSessionConfig()
    }
}

// MARK: - Voice Session Errors

/**
 * Errors that can occur during a voice session.
 * Mirrors Swift VoiceSessionError exactly.
 */
sealed class VoiceSessionError : Exception() {
    data object MicrophonePermissionDenied : VoiceSessionError() {
        private fun readResolve(): Any = MicrophonePermissionDenied
        override val message: String = "Microphone permission denied"
    }

    data object NotReady : VoiceSessionError() {
        private fun readResolve(): Any = NotReady
        override val message: String = "Voice agent not ready. Load STT, LLM, and TTS models first."
    }

    data object AlreadyRunning : VoiceSessionError() {
        private fun readResolve(): Any = AlreadyRunning
        override val message: String = "Voice session already running"
    }
}
