package com.runanywhere.sdk.cloud.sarvam

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.RouterRegistration

/**
 * Sarvam AI cloud backend for STT.
 *
 * Provides speech-to-text via Sarvam AI's Saarika model (cloud API).
 * Requires an API key and internet connection.
 *
 * ## Registration
 *
 * ```kotlin
 * Sarvam.register(apiKey = "sk_...")
 * ```
 *
 * ## Usage
 *
 * Once registered, Sarvam is available through the standard STT API
 * when the selected model's framework is SARVAM:
 *
 * ```kotlin
 * val text = RunAnywhere.transcribe(audioData)
 * ```
 */
object Sarvam {
    private val logger = SDKLogger("Sarvam")

    const val version = "1.0.0"

    val moduleId: String = "sarvam"
    val moduleName: String = "Sarvam AI"
    val capabilities: Set<SDKComponent> = setOf(SDKComponent.STT)
    val defaultPriority: Int = 10
    val inferenceFramework: InferenceFramework = InferenceFramework.SARVAM

    @Volatile
    private var isRegistered = false

    /**
     * Register Sarvam backend with the C++ service registry.
     *
     * @param apiKey Sarvam AI API key (required)
     * @param priority Registration priority (lower = fallback, default 10)
     */
    @JvmStatic
    @JvmOverloads
    fun register(apiKey: String, priority: Int = defaultPriority) {
        if (isRegistered) {
            logger.debug("Sarvam already registered")
            return
        }

        // Load native library
        try {
            SarvamBridge.ensureLoaded()
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Sarvam native library not available: ${e.message}")
            return
        }

        // Set API key first
        val keyResult = SarvamBridge.nativeSetApiKey(apiKey)
        if (keyResult != 0) {
            logger.error("Failed to set Sarvam API key: $keyResult")
            return
        }

        // Register backend
        val result = SarvamBridge.nativeRegister()
        if (result != 0 && result != -20) { // -20 = RAC_ERROR_MODULE_ALREADY_REGISTERED
            logger.error("Sarvam registration failed: $result")
            return
        }

        isRegistered = true
        logger.info("Sarvam backend registered (STT, cloud)")

        // Now that the C service registry knows how to create a Sarvam STT
        // service, spin up a dedicated component for it and add it to the
        // hybrid router as a long-lived candidate.
        RouterRegistration.registerSarvam()
    }

    /**
     * Unregister the Sarvam backend.
     */
    fun unregister() {
        if (!isRegistered) return
        RouterRegistration.unregisterSarvam()
        SarvamBridge.nativeUnregister()
        isRegistered = false
        logger.info("Sarvam backend unregistered")
    }

    /**
     * Update the Sarvam API key without re-running the full register flow.
     * Useful when the app pre-registered Sarvam at startup with a stale key
     * and a fresh key needs to take effect immediately.
     */
    @JvmStatic
    fun updateApiKey(apiKey: String): Boolean {
        try {
            SarvamBridge.ensureLoaded()
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Sarvam native library not available: ${e.message}")
            return false
        }
        val rc = SarvamBridge.nativeSetApiKey(apiKey)
        if (rc != 0) {
            logger.error("Failed to update Sarvam API key: $rc")
            return false
        }
        logger.info("Sarvam API key updated")
        return true
    }

    /**
     * Check if Sarvam can handle a model.
     */
    fun canHandleSTT(modelId: String?): Boolean {
        if (modelId == null) return false
        return modelId.lowercase().contains("sarvam") || modelId.lowercase().contains("saarika")
    }

    /**
     * Check if an API key is configured.
     */
    fun hasApiKey(): Boolean = SarvamBridge.nativeHasApiKey()
}
