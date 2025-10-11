package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.components.llm.HardwareConfiguration
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.components.llm.ModelCompatibilityResult
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * LLM Service Provider for MLC-LLM framework
 *
 * Provides on-device inference using MLC-compiled models with GPU acceleration
 * via OpenCL. Supports streaming generation and multi-modal inputs.
 *
 * ## Model Detection
 * This provider handles models with:
 * - File extensions: `-mlc`, `-MLC`
 * - Keywords: `mlc-chat`, `mlc-compiled`, `mlc-ai`
 * - Architectures: `phi`, `llama`, `mistral`, `qwen`, `gemma`
 * - Vision models: `llava`, `clip`
 *
 * ## Features
 * - GPU acceleration via OpenCL
 * - Streaming token-by-token generation
 * - Multi-modal text and image inputs
 * - Compiled model optimization
 * - KV cache optimization
 * - Continuous batching
 * - Speculative decoding
 *
 * ## Usage
 * ```kotlin
 * val provider = MLCProvider()
 * val config = LLMConfiguration(
 *     modelId = "/path/to/phi-3-mini-mlc",
 *     frameworkOptions = mapOf("modelLib" to "phi_msft_q4f16_1")
 * )
 * val service = provider.createLLMService(config)
 * ```
 */
class MLCProvider : LLMServiceProvider {

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        return MLCService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val modelIdLower = modelId.lowercase()

        // MLC-specific model patterns
        return modelIdLower.endsWith("-mlc") ||
                modelIdLower.contains("mlc-chat") ||
                modelIdLower.contains("mlc-compiled") ||
                modelIdLower.contains("mlc-ai") ||
                // Common architectures that MLC supports
                modelIdLower.contains("phi") ||
                modelIdLower.contains("llama") ||
                modelIdLower.contains("mistral") ||
                modelIdLower.contains("qwen") ||
                modelIdLower.contains("gemma") ||
                // Vision models
                modelIdLower.contains("llava") ||
                modelIdLower.contains("clip")
    }

    override val name: String = "MLC-LLM"

    override val framework: LLMFramework = LLMFramework.MLC

    override val supportedFeatures: Set<String> = setOf(
        // Core features
        "streaming",
        "batch-processing",

        // GPU acceleration
        "gpu-acceleration-opencl",
        "gpu-memory-management",

        // Context windows
        "context-window-2k",
        "context-window-4k",
        "context-window-8k",
        "context-window-32k",
        "context-window-128k",

        // Advanced features
        "quantization",
        "kv-cache-optimization",
        "continuous-batching",
        "speculative-decoding",

        // Multi-modal
        "multi-modal-text-image",
        "vision-language-models",

        // Performance
        "compiled-models",
        "tvm-optimization",
        "operator-fusion",
        "memory-planning"
    )

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()
        val recommendations = mutableListOf<String>()

        // Check model format
        val isCompatible = when {
            model.format.toString().contains("MLC", ignoreCase = true) -> true
            model.format.toString().contains("TVM", ignoreCase = true) -> true
            else -> {
                warnings.add("Model format ${model.format} is not a recognized MLC-compiled format")
                warnings.add("Expected model format: MLC-compiled or TVM")
                false
            }
        }

        // Estimate memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        // Memory validation
        when {
            memoryRequired > availableMemory -> {
                warnings.add("Model requires ${memoryRequired / 1024 / 1024}MB but only ${availableMemory / 1024 / 1024}MB available")
                recommendations.add("Consider using a smaller quantized model")
            }
            memoryRequired > availableMemory * 0.8 -> {
                warnings.add("Model will use over 80% of available memory (${memoryRequired / 1024 / 1024}MB / ${availableMemory / 1024 / 1024}MB)")
                recommendations.add("Close other apps before loading this model")
            }
        }

        // GPU availability check
        if (!checkOpenCLAvailable()) {
            warnings.add("OpenCL not available - will fall back to CPU (slower)")
            recommendations.add("For best performance, use a device with OpenCL support")
        }

        // Context window check
        val contextLength = model.contextLength ?: 2048
        if (contextLength > 8192) {
            recommendations.add("Large context window ($contextLength tokens) may impact performance")
        }

        return ModelCompatibilityResult(
            isCompatible = isCompatible,
            details = "Model ${model.name} validation for MLC-LLM framework",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): ModelInfo {
        // MLC models are typically downloaded via HuggingFace
        // This is a placeholder - actual implementation would:
        // 1. Parse model URL (e.g., HF://mlc-ai/Phi-3-mini-4k-instruct-q4f16_1-MLC)
        // 2. Download model files (mlc-chat-config.json, params, etc.)
        // 3. Track progress via onProgress callback
        // 4. Return ModelInfo when complete

        TODO("Model download implementation - will integrate with ModelManager")
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        // Base model size (from download size or parameters)
        val modelSize = model.downloadSize ?: run {
            // Estimate from parameter count if available
            val params = model.metadata?.parameters ?: 1_000_000_000L // Default 1B params
            // Rough estimate: 2 bytes per param for typical quantization (q4)
            params * 2
        }

        // Context memory (KV cache)
        val contextLength = model.contextLength ?: 2048
        val kvCacheMemory = contextLength * 4L * 1024  // ~4KB per token for KV cache

        // GPU memory overhead (buffers, intermediate tensors)
        val gpuOverhead = modelSize * 0.15  // ~15% overhead for GPU

        return (modelSize + kvCacheMemory + gpuOverhead).toLong()
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val memoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt()
        val availableMemoryMB = (getAvailableSystemMemory() / 1024 / 1024).toInt()
        val contextLength = model.contextLength ?: 2048

        return HardwareConfiguration(
            // GPU acceleration is highly recommended for MLC
            preferGPU = checkOpenCLAvailable(),

            // Memory settings
            minMemoryMB = memoryMB,
            recommendedThreads = minOf(Runtime.getRuntime().availableProcessors(), 4),

            // MLC-specific optimizations
            useMmap = false,  // MLC handles memory differently
            lockMemory = false
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        // Parse model ID to extract information
        val modelName = modelId.split("/").lastOrNull() ?: modelId
        val isVisionModel = modelName.lowercase().contains("llava") ||
                modelName.lowercase().contains("clip")

        return ModelInfo(
            id = modelId,
            name = modelName,
            category = if (isVisionModel) ModelCategory.MULTI_MODAL else ModelCategory.LANGUAGE,
            format = ModelFormat.MLC_COMPILED,

            // Extract context length from model name if present
            contextLength = extractContextLength(modelName),

            // Provider info
            preferredFramework = framework,
            compatibleFrameworks = listOf(framework)
        )
    }

    // Helper methods

    protected fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }

    protected fun checkOpenCLAvailable(): Boolean {
        // This will be implemented in androidMain
        // For now, return true as most modern Android devices support OpenCL
        return true
    }

    private fun extractContextLength(modelName: String): Int? {
        // Extract context length from model name patterns like "4k", "8k", "32k"
        val contextRegex = Regex("""(\d+)k""", RegexOption.IGNORE_CASE)
        val match = contextRegex.find(modelName)
        return match?.groupValues?.get(1)?.toIntOrNull()?.times(1024)
    }
}
