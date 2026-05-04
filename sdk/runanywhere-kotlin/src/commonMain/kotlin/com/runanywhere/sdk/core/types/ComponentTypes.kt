package com.runanywhere.sdk.core.types

// Re-export the proto-generated AudioFormat so callers that previously imported
// com.runanywhere.sdk.core.types.AudioFormat continue to resolve. The hand-rolled
// enum class has been deleted per Iron Rule 2 / §15 of CANONICAL_API.md.
typealias AudioFormat = ai.runanywhere.proto.v1.AudioFormat

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
    RAG("RAG"),
    VLM("VLM"),
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
                RAG -> "Retrieval-Augmented Generation"
                VLM -> "Vision Language Model"
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
 * GAP 01 Phase 3: this Kotlin enum is a subset of the IDL
 * `runanywhere.v1.InferenceFramework`; Apple-only frameworks (`CoreML`, `MLX`,
 * `WhisperKitCoreML`, `MetalRT`) and secondary runtimes (`TFLite`,
 * `ExecuTorch`, etc.) are present in the proto but intentionally omitted here
 * until the Kotlin SDK ships support. Adding a case here requires a
 * corresponding IDL update; the `toProto()` bijection forces the mapping to
 * stay in sync.
 */
enum class InferenceFramework(
    val rawValue: String,
) {
    // Model-based frameworks
    ONNX("ONNX"),
    SHERPA("Sherpa"), // Sherpa-ONNX speech engine (STT/TTS/VAD/wakeword)
    LLAMA_CPP("LlamaCpp"),
    FOUNDATION_MODELS("FoundationModels"),
    SYSTEM_TTS("SystemTTS"),
    FLUID_AUDIO("FluidAudio"),
    GENIE("Genie"),

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
                SHERPA -> "Sherpa-ONNX"
                LLAMA_CPP -> "llama.cpp"
                FOUNDATION_MODELS -> "Foundation Models"
                SYSTEM_TTS -> "System TTS"
                FLUID_AUDIO -> "FluidAudio"
                GENIE -> "Qualcomm Genie"
                BUILT_IN -> "Built-in"
                NONE -> "None"
                UNKNOWN -> "Unknown"
            }

    /** Snake_case key for analytics/telemetry */
    val analyticsKey: String
        get() =
            when (this) {
                ONNX -> "onnx"
                SHERPA -> "sherpa"
                LLAMA_CPP -> "llama_cpp"
                FOUNDATION_MODELS -> "foundation_models"
                SYSTEM_TTS -> "system_tts"
                FLUID_AUDIO -> "fluid_audio"
                GENIE -> "genie"
                BUILT_IN -> "built_in"
                NONE -> "none"
                UNKNOWN -> "unknown"
            }

    /** Convert to the IDL-generated Wire enum. */
    fun toProto(): ai.runanywhere.proto.v1.InferenceFramework =
        when (this) {
            ONNX -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_ONNX
            SHERPA -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA
            LLAMA_CPP -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
            FOUNDATION_MODELS -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS
            SYSTEM_TTS -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
            FLUID_AUDIO -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO
            GENIE -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_GENIE
            BUILT_IN -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN
            NONE -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_NONE
            UNKNOWN -> ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
        }

    companion object {
        /** Create from raw string value, matching case-insensitively */
        fun fromRawValue(value: String): InferenceFramework {
            val lowercased = value.lowercase()
            entries.find { it.rawValue.equals(value, ignoreCase = true) }?.let { return it }
            entries.find { it.analyticsKey == lowercased }?.let { return it }
            return UNKNOWN
        }

        /** Decode from the IDL-generated Wire enum; unsupported → UNKNOWN. */
        fun fromProto(proto: ai.runanywhere.proto.v1.InferenceFramework): InferenceFramework =
            when (proto) {
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> ONNX
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> SHERPA
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> LLAMA_CPP
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> FOUNDATION_MODELS
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> SYSTEM_TTS
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> FLUID_AUDIO
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> GENIE
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> BUILT_IN
                ai.runanywhere.proto.v1.InferenceFramework.INFERENCE_FRAMEWORK_NONE -> NONE
                else -> UNKNOWN
            }
    }
}
