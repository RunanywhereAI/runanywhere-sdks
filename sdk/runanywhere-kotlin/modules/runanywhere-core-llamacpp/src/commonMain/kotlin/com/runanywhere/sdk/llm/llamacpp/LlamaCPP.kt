package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhereModule

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
 * // Register the backend (suspend, called once during SDK bootstrap)
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
 * val response = RunAnywhere.generate("Hello!")
 *
 * // Stream text via public API
 * RunAnywhere.generateStream("Tell me a story").collect { event ->
 *     if (!event.is_final) print(event.token_)
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

    /** Default priority used when callers do not specify one. */
    const val defaultPriority: Int = 100

    // MARK: - RunAnywhereModule Conformance

    override val moduleName: String = "LlamaCPP"

    // MARK: - Registration State

    @Volatile
    private var isRegistered = false

    @Volatile
    private var isVlmRegistered = false

    // MARK: - Registration

    /**
     * Register LlamaCPP backend with the C++ service registry (RunAnywhereModule override).
     *
     * Mirrors iOS `LlamaCPP.register()` which registers both LLM and VLM.
     * Suspend so that callers can await module bootstrap from a coroutine scope.
     */
    override suspend fun register() {
        registerInternal()
    }

    /**
     * Unregister the LlamaCPP backend from C++ registry (RunAnywhereModule override).
     */
    override suspend fun unregister() {
        if (!isRegistered) return

        // Unregister VLM backend first (matches iOS unregister order)
        if (isVlmRegistered) {
            try {
                unregisterVlmNative()
                isVlmRegistered = false
                logger.info("LlamaCPP VLM backend unregistered")
            } catch (e: UnsatisfiedLinkError) {
                isVlmRegistered = false
                logger.warning("LlamaCPP VLM unregister skipped — native symbols not available")
            }
        }

        unregisterNative()
        isRegistered = false
        logger.info("LlamaCPP backend unregistered")
    }

    /**
     * Backwards-compatible non-suspend registration entry point.
     *
     * Apps that bootstrap on the main thread (e.g. `Application.onCreate`)
     * call `LlamaCPP.register(priority = 100)`. The `priority` argument is
     * ignored — the C++ plugin registry assigns priority internally.
     *
     * No default value is set here so that the no-arg suspend [register]
     * override remains unambiguous on the call site.
     *
     * @param priority Ignored (C++ uses its own priority system).
     */
    @Suppress("UNUSED_PARAMETER")
    @JvmStatic
    fun register(priority: Int) {
        registerInternal()
    }

    private fun registerInternal() {
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
     *
     * Wrapped in UnsatisfiedLinkError handling because the VLM JNI symbols
     * may not be present in older native library builds. In that case, LLM
     * features continue to work normally — only VLM is unavailable.
     */
    private fun registerVLM() {
        if (isVlmRegistered) return

        logger.info("Registering LlamaCPP VLM backend...")

        try {
            val vlmResult = registerVlmNative()

            if (vlmResult != 0 && vlmResult != -4) { // RAC_ERROR_MODULE_ALREADY_REGISTERED = -4
                logger.warning("LlamaCPP VLM registration failed with code: $vlmResult (VLM features may not be available)")
                return
            }

            isVlmRegistered = true
            logger.info("LlamaCPP VLM backend registered successfully")
        } catch (e: UnsatisfiedLinkError) {
            logger.warning(
                "LlamaCPP VLM native symbols not found — native library does not include VLM support. " +
                    "LLM features work normally. VLM will be available when native libs are rebuilt with VLM support.",
            )
        }
    }

    // `canHandle(modelId)` deleted per gaps/kotlin.md — mirrors
    // SWIFT-DUP-CANHANDLE. The C++ plugin router (`rac_router_*`) is the
    // only routing authority; Kotlin-side file-extension matching was never
    // called from the dispatch path and could drift from C++ format tables.

    // MARK: - Auto-Registration

    /**
     * Enable auto-registration for this module.
     * Access this property to trigger C++ backend registration.
     */
    val autoRegister: Unit by lazy {
        registerInternal()
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

/**
 * Platform-specific VLM native unregistration.
 * Calls rac_backend_llamacpp_vlm_unregister() via JNI.
 */
internal expect fun LlamaCPP.unregisterVlmNative(): Int
