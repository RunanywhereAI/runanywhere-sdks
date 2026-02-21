package com.runanywhere.sdk.rag

import com.runanywhere.sdk.core.module.RunAnywhereModule
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * RAG Runtime module for Retrieval-Augmented Generation.
 *
 * Provides document chunking, embedding, vector search, and
 * LLM generation with context capabilities.
 *
 * This is a thin wrapper that calls C++ backend registration.
 * All business logic is handled by the C++ commons layer.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.rag.RAGModule
 *
 * // Register the backend (done automatically if auto-registration is enabled)
 * RAGModule.register()
 * ```
 *
 * Matches iOS RAGModule (RAG.swift) exactly.
 */
object RAGModule : RunAnywhereModule {
    private val logger = SDKLogger.rag

    // MARK: - Module Info

    /** Current version of the RAG Runtime module */
    const val version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "rag"

    override val moduleName: String = "RAG"

    /** RAG provides LLM-based generation capabilities */
    override val capabilities: Set<SDKComponent> =
        setOf(SDKComponent.LLM)

    override val defaultPriority: Int = 100

    /** RAG uses ONNX for embeddings and LlamaCPP for generation */
    override val inferenceFramework: InferenceFramework = InferenceFramework.ONNX

    // MARK: - Registration State

    @Volatile
    private var isRegistered = false

    // MARK: - Registration

    /**
     * Register RAG backend with the C++ service registry.
     *
     * This calls `rac_backend_rag_register()` to register the
     * RAG service provider with the C++ commons layer.
     *
     * Safe to call multiple times - subsequent calls are no-ops.
     *
     * @param priority Ignored (C++ uses its own priority system)
     */
    @Suppress("UNUSED_PARAMETER")
    @JvmStatic
    @JvmOverloads
    fun register(priority: Int = defaultPriority) {
        if (isRegistered) {
            logger.debug("RAG already registered, returning")
            return
        }

        logger.info("Registering RAG backend with C++ registry...")

        val result = registerNative()

        // Success or already registered is OK
        if (result != 0 && result != -4) { // RAC_ERROR_MODULE_ALREADY_REGISTERED = -4
            logger.error("RAG registration failed with code: $result")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("RAG backend registered successfully")
    }

    /**
     * Unregister the RAG backend from C++ registry.
     */
    fun unregister() {
        if (!isRegistered) return

        unregisterNative()
        isRegistered = false
        logger.info("RAG backend unregistered")
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
 * Calls rac_backend_rag_register() via JNI.
 */
internal expect fun RAGModule.registerNative(): Int

/**
 * Platform-specific native unregistration.
 * Calls rac_backend_rag_unregister() via JNI.
 */
internal expect fun RAGModule.unregisterNative(): Int
