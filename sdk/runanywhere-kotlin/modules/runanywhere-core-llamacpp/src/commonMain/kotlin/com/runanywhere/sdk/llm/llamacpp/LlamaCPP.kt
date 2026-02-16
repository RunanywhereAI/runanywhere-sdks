package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.module.RunAnywhereModule
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * LlamaCPP module for LLM text generation.
 *
 * Provides large language model capabilities using llama.cpp
 * with GGUF models and Metal/GPU acceleration.
 *
 * This is a thin wrapper that calls C++ backend registration.
 * All business logic is handled by the C++ commons layer.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
 *
 * // Register the backend (done automatically if auto-registration is enabled)
 * LlamaCPP.register()
 * ```
 *
 * ## Usage
 *
 * LLM services are accessed through the main SDK APIs - the C++ backend handles
 * service creation and lifecycle internally:
 *
 * ```kotlin
 * // Generate text via public API
 * val response = RunAnywhere.chat("Hello!")
 *
 * // Stream text via public API
 * RunAnywhere.streamChat("Tell me a story").collect { token ->
 *     print(token)
 * }
 * ```
 *
 * Matches iOS LlamaCPP.swift exactly.
 */
object LlamaCPP : RunAnywhereModule {
    private val logger = SDKLogger.llamacpp

    // MARK: - Module Info

    /** Current version of the LlamaCPP Runtime module */
    const val version = "2.0.0"

    /** LlamaCPP library version (underlying C++ library) */
    const val llamaCppVersion = "b7199"

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "llamacpp"

    override val moduleName: String = "LlamaCPP"

    override val capabilities: Set<SDKComponent> = setOf(SDKComponent.LLM)

    override val defaultPriority: Int = 100

    /** LlamaCPP uses the llama.cpp inference framework */
    override val inferenceFramework: InferenceFramework = InferenceFramework.LLAMA_CPP

    // MARK: - Registration State

    @Volatile
    private var isRegistered = false

    @Volatile
    private var isVlmRegistered = false

    // MARK: - Registration

    /**
     * Register LlamaCPP backend with the C++ service registry.
     *
     * This calls `rac_backend_llamacpp_register()` to register the
     * LlamaCPP service provider with the C++ commons layer, then
     * also registers the VLM (Vision Language Model) backend.
     *
     * Safe to call multiple times - subsequent calls are no-ops.
     *
     * Matches iOS LlamaCPP.register() which registers both LLM and VLM.
     *
     * @param priority Ignored (C++ uses its own priority system)
     */
    @Suppress("UNUSED_PARAMETER")
    @JvmStatic
    @JvmOverloads
    fun register(priority: Int = defaultPriority) {
        if (isRegistered) {
            logger.debug("LlamaCPP already registered, returning")
            return
        }

        logger.info("Registering LlamaCPP backend with C++ registry...")

        val result = registerNative()

        // Success or already registered is OK
        if (result != 0 && result != -4) { // RAC_ERROR_MODULE_ALREADY_REGISTERED = -4
            logger.error("LlamaCPP registration failed with code: $result")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("LlamaCPP LLM backend registered successfully")

        // Register VLM backend (Vision Language Model) — matches iOS pattern
        registerVLM()
    }

    /**
     * Register VLM (Vision Language Model) backend.
     * Matches iOS LlamaCPP.registerVLM() exactly.
     */
    private fun registerVLM() {
        if (isVlmRegistered) return

        logger.info("Registering LlamaCPP VLM backend...")

        val vlmResult = registerVlmNative()

        if (vlmResult != 0 && vlmResult != -4) { // RAC_ERROR_MODULE_ALREADY_REGISTERED = -4
            logger.warning("LlamaCPP VLM registration failed with code: $vlmResult (VLM features may not be available)")
            return
        }

        isVlmRegistered = true
        logger.info("LlamaCPP VLM backend registered successfully")
    }

    /**
     * Unregister the LlamaCPP backend from C++ registry.
     */
    fun unregister() {
        if (!isRegistered) return

        unregisterNative()
        isRegistered = false
        isVlmRegistered = false
        logger.info("LlamaCPP backend unregistered")
    }

    // MARK: - Model Handling

    /**
     * Check if LlamaCPP can handle a given model.
     * Uses file extension pattern matching - actual framework info is in C++ registry.
     */
    fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false
        return modelId.lowercase().endsWith(".gguf")
    }

    // MARK: - Auto-Registration

    /**
     * Enable auto-registration for this module.
     * Access this property to trigger C++ backend registration.
     */
    val autoRegister: Unit by lazy {
        register()
    }
}

/**
 * Platform-specific native registration.
 * Calls rac_backend_llamacpp_register() via JNI.
 */
internal expect fun LlamaCPP.registerNative(): Int

/**
 * Platform-specific native unregistration.
 * Calls rac_backend_llamacpp_unregister() via JNI.
 */
internal expect fun LlamaCPP.unregisterNative(): Int

/**
 * Platform-specific VLM native registration.
 * Calls rac_backend_llamacpp_vlm_register() via JNI.
 */
internal expect fun LlamaCPP.registerVlmNative(): Int
