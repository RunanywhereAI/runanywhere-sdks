package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.features.llm.LLMServiceProvider
import com.runanywhere.sdk.features.llm.ModelCompatibilityResult
import com.runanywhere.sdk.features.llm.HardwareConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * LlamaCpp provider for Language Model services via RunAnywhere Core.
 *
 * This provider wraps runanywhere-core's LlamaCPP backend which includes
 * proper chat template support for all models (Qwen, LFM2, Llama, etc.)
 *
 * Usage:
 * ```kotlin
 * import com.runanywhere.sdk.llm.llamacpp.LlamaCppServiceProvider
 *
 * // In your Application.onCreate():
 * LlamaCppServiceProvider.register()
 * ```
 */
object LlamaCppServiceProvider : LLMServiceProvider {
    private val logger = SDKLogger("LlamaCppServiceProvider")

    /**
     * Simple registration - just call this in your app
     */
    fun register() {
        ModuleRegistry.shared.registerLLM(this)
        logger.info("LlamaCppServiceProvider registered (RunAnywhere Core backend)")
    }

    // MARK: - LLMServiceProvider Protocol

    override val name: String = "LlamaCpp (RunAnywhere Core)"

    override val framework: InferenceFramework = InferenceFramework.LLAMA_CPP

    override val supportedFeatures: Set<String> = setOf(
        "text-generation",
        "streaming",
        "quantization",
        "gguf-format",
        "chat-templates"
    )

    override fun canHandle(modelId: String?): Boolean {
        // Null model ID is not handled - require explicit model
        if (modelId == null) return false

        val lowercased = modelId.lowercase()

        // Check if model format is GGUF/GGML by file extension
        if (lowercased.endsWith(".gguf") || lowercased.contains(".gguf")) {
            return true
        }
        if (lowercased.endsWith(".ggml") || lowercased.contains(".ggml")) {
            return true
        }

        // Check for explicit gguf/ggml references in model name
        if (lowercased.contains("gguf") || lowercased.contains("ggml")) {
            return true
        }

        // Check for llamacpp framework references
        if (lowercased.contains("llamacpp") ||
            lowercased.contains("llama-cpp") ||
            lowercased.contains("llama_cpp")) {
            return true
        }

        // Check for GGUF quantization patterns (q2_k, q4_0, q5_1, q8_0, etc.)
        // Pattern: q followed by 2-8, optionally followed by _k or _K, optionally followed by _m/_M/_s/_S/_0
        val quantizationPattern = Regex("""q[2-8]([_-][kK])?([_-][mMsS0])?""")
        if (quantizationPattern.containsMatchIn(lowercased)) {
            return true
        }

        // Explicit format checks for common LLM model patterns
        val llmPatterns = listOf(
            "llama", "mistral", "mixtral", "phi", "qwen", "lfm",
            "deepseek", "hermes", "gemma", "yi-", "tinyllama"
        )
        if (llmPatterns.any { lowercased.contains(it) }) {
            // These are likely LLM models - check if they don't have other framework markers
            if (!lowercased.contains("onnx") &&
                !lowercased.contains("coreml") &&
                !lowercased.contains("mlmodel") &&
                !lowercased.contains("tflite")) {
                return true
            }
        }

        return false
    }

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        logger.info("Creating LlamaCpp service (RunAnywhere Core backend)")

        // Create the service - model loading happens when initialize(modelPath) is called
        // by the caller (LLMComponent) with the correct path
        val service = LlamaCppService(configuration)

        logger.info("LlamaCpp service created - waiting for initialize() with model path")
        return service
    }

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        // Check if model format is supported
        val modelFormat = model.format
        if (modelFormat != ModelFormat.GGUF &&
            modelFormat != ModelFormat.GGML
        ) {
            return ModelCompatibilityResult(
                isCompatible = false,
                details = "Llama.cpp only supports GGUF and GGML formats",
                memoryRequired = 0L,
                warnings = listOf("Unsupported model format: $modelFormat")
            )
        }

        // Check memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available ($memoryRequired bytes required, $availableMemory bytes available)")
        }

        return ModelCompatibilityResult(
            isCompatible = true,
            details = "Model is compatible with Llama.cpp (RunAnywhere Core)",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo {
        throw UnsupportedOperationException("Use RunAnywhere.downloadModel() instead")
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        return model.memoryRequired ?: model.downloadSize ?: 1_000_000_000L
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        return HardwareConfiguration(
            preferGPU = false, // CPU-only for now
            minMemoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt(),
            recommendedThreads = Runtime.getRuntime().availableProcessors()
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId,
            category = ModelCategory.LANGUAGE,
            format = ModelFormat.GGUF,
            downloadURL = null,
            localPath = null,
            downloadSize = null,
            memoryRequired = null,
            compatibleFrameworks = listOf(InferenceFramework.LLAMA_CPP),
            preferredFramework = InferenceFramework.LLAMA_CPP,
            contextLength = 4096,
            supportsThinking = false,
            metadata = null
        )
    }

    private fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }
}
