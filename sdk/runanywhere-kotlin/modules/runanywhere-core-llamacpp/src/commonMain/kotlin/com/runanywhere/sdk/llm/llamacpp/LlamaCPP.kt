package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.CapabilityType
import com.runanywhere.sdk.core.ModuleDiscovery
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.ModuleRegistry.shared
import com.runanywhere.sdk.core.RunAnywhereModule
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.infrastructure.download.DownloadStrategy
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.storage.ModelStorageStrategy

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
     * Download strategy for GGUF models - handles direct file downloads
     */
    override val downloadStrategy: DownloadStrategy = LlamaCppDownloadStrategy.shared

    /**
     * Storage strategy for detecting GGUF models on disk
     */
    override val storageStrategy: ModelStorageStrategy = LlamaCppDownloadStrategy.shared

    /**
     * Register LlamaCPP LLM service with the SDK.
     * Matches iOS: @MainActor public static func register(priority: Int)
     *
     * @param priority Registration priority (higher values are preferred)
     */
    override fun register(priority: Int) {
        ModuleRegistry.shared.registerLLM(moduleName) { config -> createLLMService(config) }
        logger.info("LlamaCPP LLM registered")
    }

    // MARK: - Private Helpers

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
