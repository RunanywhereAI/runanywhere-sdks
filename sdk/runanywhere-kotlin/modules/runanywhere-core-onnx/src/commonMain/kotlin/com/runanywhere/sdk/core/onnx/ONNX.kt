package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.core.module.RunAnywhereModule
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * ONNX Runtime module for STT, TTS, and VAD services.
 *
 * Provides speech-to-text, text-to-speech, and voice activity detection
 * capabilities using ONNX Runtime with models like Whisper, Piper, and Silero.
 *
 * This is a thin wrapper that calls C++ backend registration.
 * All business logic is handled by the C++ commons layer.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.core.onnx.ONNX
 *
 * // Register the backend (done automatically if auto-registration is enabled)
 * ONNX.register()
 * ```
 *
 * ## Usage
 *
 * Services are accessed through the main SDK APIs - the C++ backend handles
 * service creation and lifecycle internally:
 *
 * ```kotlin
 * // STT via public API
 * val text = RunAnywhere.transcribe(audioData)
 *
 * // TTS via public API
 * RunAnywhere.speak("Hello")
 * ```
 *
 * Matches iOS ONNX.swift exactly.
 */
object ONNX : RunAnywhereModule {
    private val logger = SDKLogger("ONNX")

    // MARK: - Module Info

    /** Current version of the ONNX Runtime module */
    const val version = "2.0.0"

    /** ONNX Runtime library version (underlying C library) */
    const val onnxRuntimeVersion = "1.23.2"

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "onnx"

    override val moduleName: String = "ONNX Runtime"

    override val capabilities: Set<SDKComponent> = setOf(
        SDKComponent.STT,
        SDKComponent.TTS,
        SDKComponent.VAD
    )

    override val defaultPriority: Int = 100

    /** ONNX uses the ONNX Runtime inference framework */
    override val inferenceFramework: InferenceFramework = InferenceFramework.ONNX

    // MARK: - Registration State

    @Volatile
    private var isRegistered = false

    // MARK: - Registration

    /**
     * Register ONNX backend with the C++ service registry.
     *
     * This calls `rac_backend_onnx_register()` to register all ONNX
     * service providers (STT, TTS, VAD) with the C++ commons layer.
     *
     * Safe to call multiple times - subsequent calls are no-ops.
     *
     * @param priority Ignored (C++ uses its own priority system)
     */
    @JvmStatic
    @JvmOverloads
    fun register(priority: Int = defaultPriority) {
        if (isRegistered) {
            logger.debug("ONNX already registered, returning")
            return
        }

        logger.info("Registering ONNX backend with C++ registry...")

        val result = registerNative()

        // Success or already registered is OK
        if (result != 0 && result != -4) { // RAC_ERROR_MODULE_ALREADY_REGISTERED = -4
            logger.error("ONNX registration failed with code: $result")
            // Don't throw - registration failure shouldn't crash the app
            return
        }

        isRegistered = true
        logger.info("ONNX backend registered successfully (STT + TTS + VAD)")
    }

    /**
     * Unregister the ONNX backend from C++ registry.
     */
    fun unregister() {
        if (!isRegistered) return

        unregisterNative()
        isRegistered = false
        logger.info("ONNX backend unregistered")
    }

    // MARK: - Model Handling

    /**
     * Check if ONNX can handle a given model for STT.
     * Uses model name pattern matching - actual framework info is in C++ registry.
     */
    fun canHandleSTT(modelId: String?): Boolean {
        if (modelId == null) return false
        val lowercased = modelId.lowercase()
        return lowercased.contains("whisper") ||
                lowercased.contains("zipformer") ||
                lowercased.contains("paraformer")
    }

    /**
     * Check if ONNX can handle a given model for TTS.
     * Uses model name pattern matching - actual framework info is in C++ registry.
     */
    fun canHandleTTS(modelId: String?): Boolean {
        if (modelId == null) return false
        val lowercased = modelId.lowercase()
        return lowercased.contains("piper") || lowercased.contains("vits")
    }

    /**
     * Check if ONNX can handle VAD (always true for Silero VAD).
     */
    fun canHandleVAD(modelId: String?): Boolean {
        return true // ONNX Silero VAD is the default
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
 * Calls rac_backend_onnx_register() via JNI.
 */
internal expect fun ONNX.registerNative(): Int

/**
 * Platform-specific native unregistration.
 * Calls rac_backend_onnx_unregister() via JNI.
 */
internal expect fun ONNX.unregisterNative(): Int
