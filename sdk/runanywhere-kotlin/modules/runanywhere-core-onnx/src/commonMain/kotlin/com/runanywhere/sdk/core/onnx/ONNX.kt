package com.runanywhere.sdk.core.onnx

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.core.module.RunAnywhereModule
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
    private val logger = SDKLogger.onnx

    // MARK: - Module Info

    /** Current version of the ONNX Runtime module */
    const val version = "2.0.0"

    /** ONNX Runtime library version (underlying C library) */
    const val onnxRuntimeVersion = "1.23.2"

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "onnx"

    override val moduleName: String = "ONNX Runtime"

    override val capabilities: Set<SDKComponent> =
        setOf(
            SDKComponent.SDK_COMPONENT_STT,
            SDKComponent.SDK_COMPONENT_TTS,
            SDKComponent.SDK_COMPONENT_VAD,
        )

    override val defaultPriority: Int = 100

    /** ONNX uses the ONNX Runtime inference framework */
    override val inferenceFramework: InferenceFramework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX

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
    @Suppress("UNUSED_PARAMETER")
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

    // `canHandleSTT` / `canHandleTTS` / `canHandleVAD` deleted per
    // gaps/kotlin.md — mirrors SWIFT-DUP-CANHANDLE. The C++ plugin router
    // (`rac_router_*` / `rac_plugin_route`) is the only routing authority;
    // Kotlin-side substring matching was never called from the dispatch path.

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
