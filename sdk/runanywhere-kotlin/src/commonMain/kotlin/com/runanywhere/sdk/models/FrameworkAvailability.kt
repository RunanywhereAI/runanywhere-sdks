package com.runanywhere.sdk.models

import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.models.enums.supportedModalities
import kotlinx.serialization.Serializable

/**
 * Provides detailed availability information for a framework
 * Matches iOS FrameworkAvailability struct
 */
@Serializable
data class FrameworkAvailability(
    val framework: InferenceFramework,
    val isAvailable: Boolean,
    val unavailabilityReason: String? = null,
    val recommendedFor: List<String> = emptyList(),
    val supportedFormats: List<ModelFormat> = emptyList(),
    val supportedModalities: Set<FrameworkModality> = emptySet(),
) {
    companion object {
        /**
         * Creates FrameworkAvailability for a given framework with default values
         */
        fun forFramework(
            framework: InferenceFramework,
            isAvailable: Boolean,
            unavailabilityReason: String? = null,
        ): FrameworkAvailability =
            FrameworkAvailability(
                framework = framework,
                isAvailable = isAvailable,
                unavailabilityReason = unavailabilityReason,
                recommendedFor = getRecommendedFor(framework),
                supportedFormats = getSupportedFormats(framework),
                supportedModalities = framework.supportedModalities,
            )

        private fun getRecommendedFor(framework: InferenceFramework): List<String> =
            when (framework) {
                InferenceFramework.LLAMA_CPP, InferenceFramework.LLAMACPP -> listOf("GGUF models", "Text generation", "Chat")
                InferenceFramework.WHISPER_KIT, InferenceFramework.WHISPER_CPP, InferenceFramework.OPEN_AI_WHISPER ->
                    listOf(
                        "Speech recognition",
                        "Transcription",
                    )
                InferenceFramework.TENSOR_FLOW_LITE -> listOf("TFLite models", "Edge inference")
                InferenceFramework.ONNX -> listOf("ONNX models", "Cross-platform inference")
                InferenceFramework.CORE_ML -> listOf("Apple Neural Engine", "iOS/macOS optimization")
                InferenceFramework.FOUNDATION_MODELS -> listOf("Apple Intelligence", "On-device LLM")
                InferenceFramework.MEDIA_PIPE -> listOf("MediaPipe models", "Multi-task AI")
                InferenceFramework.SYSTEM_TTS -> listOf("Text-to-speech", "Voice synthesis")
                InferenceFramework.MLX -> listOf("MLX models", "Apple Silicon optimization")
                InferenceFramework.MLC -> listOf("MLC models", "Optimized inference")
                InferenceFramework.EXECU_TORCH -> listOf("ExecuTorch models", "Mobile optimization")
                InferenceFramework.PICO_LLM -> listOf("PicoLLM models", "Embedded inference")
                InferenceFramework.SWIFT_TRANSFORMERS -> listOf("Transformers models", "HuggingFace integration")
                InferenceFramework.FLUID_AUDIO -> listOf("Speaker diarization", "Audio segmentation")
                InferenceFramework.BUILT_IN -> listOf("Built-in algorithms", "Energy-based VAD")
                InferenceFramework.NONE, InferenceFramework.UNKNOWN -> emptyList()
            }

        private fun getSupportedFormats(framework: InferenceFramework): List<ModelFormat> =
            when (framework) {
                InferenceFramework.LLAMA_CPP, InferenceFramework.LLAMACPP -> listOf(ModelFormat.GGUF, ModelFormat.GGML)
                InferenceFramework.WHISPER_KIT -> listOf(ModelFormat.MLMODEL, ModelFormat.MLPACKAGE)
                InferenceFramework.WHISPER_CPP -> listOf(ModelFormat.GGML, ModelFormat.BIN)
                InferenceFramework.OPEN_AI_WHISPER -> listOf(ModelFormat.BIN, ModelFormat.SAFETENSORS)
                InferenceFramework.TENSOR_FLOW_LITE -> listOf(ModelFormat.TFLITE)
                InferenceFramework.ONNX -> listOf(ModelFormat.ONNX)
                InferenceFramework.CORE_ML -> listOf(ModelFormat.MLMODEL, ModelFormat.MLPACKAGE)
                InferenceFramework.FOUNDATION_MODELS -> emptyList() // Built-in models
                InferenceFramework.MEDIA_PIPE -> listOf(ModelFormat.TFLITE)
                InferenceFramework.SYSTEM_TTS -> emptyList() // Built-in voices
                InferenceFramework.FLUID_AUDIO -> emptyList() // Uses embedded models
                InferenceFramework.MLX -> listOf(ModelFormat.SAFETENSORS)
                InferenceFramework.MLC -> listOf(ModelFormat.SAFETENSORS)
                InferenceFramework.EXECU_TORCH -> listOf(ModelFormat.PTE)
                InferenceFramework.PICO_LLM -> listOf(ModelFormat.BIN)
                InferenceFramework.SWIFT_TRANSFORMERS -> listOf(ModelFormat.SAFETENSORS, ModelFormat.BIN)
                InferenceFramework.BUILT_IN -> emptyList() // Built-in algorithms, no model files
                InferenceFramework.NONE, InferenceFramework.UNKNOWN -> emptyList()
            }
    }
}
