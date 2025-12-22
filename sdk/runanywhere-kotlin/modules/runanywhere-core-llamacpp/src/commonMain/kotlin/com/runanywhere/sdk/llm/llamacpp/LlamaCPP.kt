package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.CapabilityType
import com.runanywhere.sdk.core.ModuleDiscovery
import com.runanywhere.sdk.core.ModuleRegistryMetadata
import com.runanywhere.sdk.core.RunAnywhereModule
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework

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
     * Register LlamaCPP LLM service with the SDK
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

        // Register the underlying service provider
        LlamaCppServiceProvider.register()

        // Register module metadata for tracking
        ModuleRegistryMetadata.registerModule(this, priority)

        logger.info("LlamaCPP module registered with priority $priority")
    }

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
