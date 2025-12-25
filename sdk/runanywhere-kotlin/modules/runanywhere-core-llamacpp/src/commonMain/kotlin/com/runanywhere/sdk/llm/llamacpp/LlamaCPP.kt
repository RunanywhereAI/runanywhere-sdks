package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.CapabilityType
import com.runanywhere.sdk.core.ModuleDiscovery
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.ModuleRegistryMetadata
import com.runanywhere.sdk.core.RunAnywhereModule
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory

/**
 * LlamaCPP module for LLM text generation.
 *
 * Provides large language model capabilities using llama.cpp
 * with GGUF/GGML models and Metal/GPU acceleration.
 *
 * Matches iOS LlamaCPP enum exactly.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
 *
 * // Option 1: Direct registration
 * LlamaCPP.register()
 *
 * // Option 2: Via ModuleDiscovery (auto-discovery)
 * ModuleDiscovery.registerDiscoveredModules()
 * ```
 *
 * ## Adding Models
 *
 * ```kotlin
 * LlamaCPP.register()
 *
 * // Add models using the module's addModel extension
 * LlamaCPP.addModel(
 *     name = "Llama 2 7B Chat",
 *     url = "https://example.com/llama-2-7b-chat.Q4_K_M.gguf",
 *     memoryRequirement = 4_000_000_000L
 * )
 * ```
 *
 * ## Usage
 *
 * ```kotlin
 * // After registration and model download
 * RunAnywhere.loadModel("my-model-id")
 * val result = RunAnywhere.generate("Hello!")
 * ```
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPPServiceProvider.swift
 */
object LlamaCPP : RunAnywhereModule {
    private val logger = SDKLogger("LlamaCPP")

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "llamacpp"

    override val moduleName: String = "LlamaCPP"

    override val capabilities: Set<CapabilityType> = setOf(CapabilityType.LLM)

    override val defaultPriority: Int = 100

    /**
     * LlamaCPP uses the llama.cpp inference framework
     */
    override val inferenceFramework: InferenceFramework = InferenceFramework.LLAMA_CPP

    /**
     * Register LlamaCPP LLM service with the SDK.
     * Matches iOS: @MainActor public static func register(priority: Int)
     *
     * @param priority Registration priority (higher values are preferred)
     */
    override fun register(priority: Int) {
        // Check for duplicate registration
        if (ModuleRegistryMetadata.isRegistered(moduleId)) {
            logger.warning("LlamaCPP module already registered, skipping")
            return
        }

        // Register LLM service using factory closure (matching iOS exactly)
        ModuleRegistry.shared.registerLLMFactory(
            name = moduleName,
            priority = priority,
            canHandle = { modelId -> canHandleModel(modelId) },
            factory = { config -> createLLMService(config) },
        )

        // Register module metadata for tracking
        ModuleRegistryMetadata.registerModule(this, priority)

        logger.info("LlamaCPP LLM registered with priority $priority")
    }

    // MARK: - Private Helpers

    /**
     * Check if this module can handle the given model
     * Matches iOS canHandleModel(_:) implementation
     */
    private fun canHandleModel(modelId: String?): Boolean {
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
            lowercased.contains("llama_cpp")
        ) {
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
            "deepseek", "hermes", "gemma", "yi-", "tinyllama",
        )
        if (llmPatterns.any { lowercased.contains(it) }) {
            // These are likely LLM models - check if they don't have other framework markers
            if (!lowercased.contains("onnx") &&
                !lowercased.contains("coreml") &&
                !lowercased.contains("mlmodel") &&
                !lowercased.contains("tflite")
            ) {
                return true
            }
        }

        return false
    }

    /**
     * Create an LLM service with the given configuration
     * Matches iOS createService(config:) implementation
     */
    private suspend fun createLLMService(config: LLMConfiguration): LLMService {
        logger.info("Creating LlamaCpp service for model: ${config.modelId}")

        // Get the actual model file path from the model registry
        val modelId = config.modelId
        val modelInfo = modelId?.let { ServiceContainer.shared.modelRegistry.getModel(it) }
        val modelPath = modelInfo?.localPath

        if (modelPath != null) {
            logger.info("Found local model path: $modelPath")
        } else if (modelId != null) {
            logger.warning("Model '$modelId' is not downloaded - service will need path at initialize()")
        }

        // Create the service - model loading happens when initialize(modelPath) is called
        val service = createLlamaCppService(config)

        logger.info("LlamaCpp service created - waiting for initialize() with model path")
        return service
    }

    // MARK: - Auto-Discovery Registration

    /**
     * Enable auto-discovery for this module.
     * Access this property to trigger registration.
     * Matches iOS: public static let autoRegister: Void
     */
    val autoRegister: Unit by lazy {
        ModuleDiscovery.register(this)
    }

    // Force initialization of auto-register when the object is accessed
    init {
        ModuleDiscovery.register(this)
    }
}

/**
 * Platform-specific LlamaCpp service creation
 * Defined in jvmAndroidMain source set
 */
internal expect suspend fun createLlamaCppService(config: LLMConfiguration): LLMService
