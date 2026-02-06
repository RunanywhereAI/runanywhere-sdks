package com.runanywhere.sdk.core.types

import kotlinx.serialization.Serializable

// MARK: - Component Protocols

/**
 * Protocol for component configuration and initialization.
 *
 * All component configurations (LLM, STT, TTS, VAD, etc.) conform to this interface.
 * Provides common properties needed for model selection and framework preference.
 *
 * Mirrors Swift's ComponentConfiguration protocol.
 */
interface ComponentConfiguration {
    /** Model identifier (optional - uses default if not specified) */
    val modelId: String?

    /** Preferred inference framework for this component (optional) */
    val preferredFramework: InferenceFramework?
}

/**
 * Protocol for component output data.
 *
 * Mirrors Swift's ComponentOutput protocol.
 */
interface ComponentOutput {
    val timestamp: Long
}

// MARK: - Audio Format

/**
 * Audio format enumeration.
 * Mirrors Swift's AudioFormat enum.
 */
@Serializable
enum class AudioFormat(
    val rawValue: String,
) {
    PCM("pcm"),
    WAV("wav"),
    MP3("mp3"),
    AAC("aac"),
    OGG("ogg"),
    OPUS("opus"),
    FLAC("flac"),
    ;

    companion object {
        fun fromRawValue(value: String): AudioFormat? {
            return entries.find { it.rawValue.equals(value, ignoreCase = true) }
        }
    }
}

// MARK: - SDK Component

/**
 * SDK component types for identification.
 *
 * This enum consolidates what was previously `CapabilityType` and provides
 * a unified type for all AI capabilities in the SDK.
 *
 * ## Usage
 *
 * ```kotlin
 * // Check what capabilities a module provides
 * val capabilities = MyModule.capabilities
 * if (SDKComponent.LLM in capabilities) {
 *     // Module provides LLM services
 * }
 * ```
 *
 * Matches iOS SDKComponent exactly.
 */
enum class SDKComponent(
    val rawValue: String,
) {
    LLM("LLM"),
    STT("STT"),
    TTS("TTS"),
    VAD("VAD"),
    VOICE("VOICE"),
    EMBEDDING("EMBEDDING"),
    ;

    /** Human-readable display name */
    val displayName: String
        get() =
            when (this) {
                LLM -> "Language Model"
                STT -> "Speech to Text"
                TTS -> "Text to Speech"
                VAD -> "Voice Activity Detection"
                VOICE -> "Voice Agent"
                EMBEDDING -> "Embedding"
            }

    /** Analytics key for the component (lowercase) */
    val analyticsKey: String
        get() = rawValue.lowercase()

    companion object {
        /** Create from raw string value */
        fun fromRawValue(value: String): SDKComponent? {
            return entries.find { it.rawValue.equals(value, ignoreCase = true) }
        }
    }
}

/**
 * Supported inference frameworks/runtimes for executing models.
 *
 * Matches iOS InferenceFramework exactly.
 */
enum class InferenceFramework(
    val rawValue: String,
) {
    // Model-based frameworks
    ONNX("ONNX"),
    LLAMA_CPP("LlamaCpp"),
    FOUNDATION_MODELS("FoundationModels"),
    SYSTEM_TTS("SystemTTS"),
    FLUID_AUDIO("FluidAudio"),
    COREML("CoreML"),  // CoreML (Apple Neural Engine)
    QNN("QNN"),  // Qualcomm Neural Network for Snapdragon NPU

    // Special cases
    BUILT_IN("BuiltIn"), // For simple services (e.g., energy-based VAD)
    NONE("None"), // For services that don't use a model
    UNKNOWN("Unknown"), // For unknown/unspecified frameworks
    ;

    /** Human-readable display name for the framework */
    val displayName: String
        get() =
            when (this) {
                ONNX -> "ONNX Runtime"
                LLAMA_CPP -> "llama.cpp"
                FOUNDATION_MODELS -> "Foundation Models"
                SYSTEM_TTS -> "System TTS"
                FLUID_AUDIO -> "FluidAudio"
                COREML -> "Core ML"
                QNN -> "Qualcomm QNN"
                BUILT_IN -> "Built-in"
                NONE -> "None"
                UNKNOWN -> "Unknown"
            }

    /** Snake_case key for analytics/telemetry */
    val analyticsKey: String
        get() =
            when (this) {
                ONNX -> "onnx"
                LLAMA_CPP -> "llama_cpp"
                FOUNDATION_MODELS -> "foundation_models"
                SYSTEM_TTS -> "system_tts"
                FLUID_AUDIO -> "fluid_audio"
                COREML -> "coreml"
                QNN -> "qnn"
                BUILT_IN -> "built_in"
                NONE -> "none"
                UNKNOWN -> "unknown"
            }

    companion object {
        /** Create from raw string value, matching case-insensitively */
        fun fromRawValue(value: String): InferenceFramework {
            val lowercased = value.lowercase()

            // Try exact match
            entries.find { it.rawValue.equals(value, ignoreCase = true) }?.let { return it }

            // Try analytics key match
            entries.find { it.analyticsKey == lowercased }?.let { return it }

            return UNKNOWN
        }
    }
}
