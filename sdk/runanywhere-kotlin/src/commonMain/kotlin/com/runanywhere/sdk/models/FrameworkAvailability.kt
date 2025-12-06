package com.runanywhere.sdk.models

import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.models.enums.supportedModalities
import kotlinx.serialization.Serializable

/**
 * Provides detailed availability information for a framework
 * Matches iOS FrameworkAvailability struct
 */
@Serializable
data class FrameworkAvailability(
    val framework: LLMFramework,
    val isAvailable: Boolean,
    val unavailabilityReason: String? = null,
    val recommendedFor: List<String> = emptyList(),
    val supportedFormats: List<ModelFormat> = emptyList(),
    val supportedModalities: Set<FrameworkModality> = emptySet()
) {
    companion object {
        /**
         * Creates FrameworkAvailability for a given framework with default values
         */
        fun forFramework(
            framework: LLMFramework,
            isAvailable: Boolean,
            unavailabilityReason: String? = null
        ): FrameworkAvailability {
            return FrameworkAvailability(
                framework = framework,
                isAvailable = isAvailable,
                unavailabilityReason = unavailabilityReason,
                recommendedFor = getRecommendedFor(framework),
                supportedFormats = getSupportedFormats(framework),
                supportedModalities = framework.supportedModalities
            )
        }

        private fun getRecommendedFor(framework: LLMFramework): List<String> {
            return when (framework) {
                LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP -> listOf("GGUF models", "Text generation", "Chat")
                LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP, LLMFramework.OPEN_AI_WHISPER -> listOf("Speech recognition", "Transcription")
                LLMFramework.TENSOR_FLOW_LITE -> listOf("TFLite models", "Edge inference")
                LLMFramework.ONNX -> listOf("ONNX models", "Cross-platform inference")
                LLMFramework.CORE_ML -> listOf("Apple Neural Engine", "iOS/macOS optimization")
                LLMFramework.FOUNDATION_MODELS -> listOf("Apple Intelligence", "On-device LLM")
                LLMFramework.MEDIA_PIPE -> listOf("MediaPipe models", "Multi-task AI")
                LLMFramework.SYSTEM_TTS -> listOf("Text-to-speech", "Voice synthesis")
                LLMFramework.MLX -> listOf("MLX models", "Apple Silicon optimization")
                LLMFramework.MLC -> listOf("MLC models", "Optimized inference")
                LLMFramework.EXECU_TORCH -> listOf("ExecuTorch models", "Mobile optimization")
                LLMFramework.PICO_LLM -> listOf("PicoLLM models", "Embedded inference")
                LLMFramework.SWIFT_TRANSFORMERS -> listOf("Transformers models", "HuggingFace integration")
            }
        }

        private fun getSupportedFormats(framework: LLMFramework): List<ModelFormat> {
            return when (framework) {
                LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP -> listOf(ModelFormat.GGUF, ModelFormat.GGML)
                LLMFramework.WHISPER_KIT -> listOf(ModelFormat.MLMODEL, ModelFormat.MLPACKAGE)
                LLMFramework.WHISPER_CPP -> listOf(ModelFormat.GGML, ModelFormat.BIN)
                LLMFramework.OPEN_AI_WHISPER -> listOf(ModelFormat.BIN, ModelFormat.SAFETENSORS)
                LLMFramework.TENSOR_FLOW_LITE -> listOf(ModelFormat.TFLITE)
                LLMFramework.ONNX -> listOf(ModelFormat.ONNX)
                LLMFramework.CORE_ML -> listOf(ModelFormat.MLMODEL, ModelFormat.MLPACKAGE)
                LLMFramework.FOUNDATION_MODELS -> emptyList() // Built-in models
                LLMFramework.MEDIA_PIPE -> listOf(ModelFormat.TFLITE)
                LLMFramework.SYSTEM_TTS -> emptyList() // Built-in voices
                LLMFramework.MLX -> listOf(ModelFormat.SAFETENSORS)
                LLMFramework.MLC -> listOf(ModelFormat.SAFETENSORS)
                LLMFramework.EXECU_TORCH -> listOf(ModelFormat.PTE)
                LLMFramework.PICO_LLM -> listOf(ModelFormat.BIN)
                LLMFramework.SWIFT_TRANSFORMERS -> listOf(ModelFormat.SAFETENSORS, ModelFormat.BIN)
            }
        }
    }
}
