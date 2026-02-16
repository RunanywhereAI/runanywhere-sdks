package com.runanywhere.sdk.diffusion.sdcpp

import com.runanywhere.sdk.core.module.RunAnywhereModule
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * stable-diffusion.cpp module for image generation.
 *
 * Provides diffusion model capabilities using stable-diffusion.cpp (ggml)
 * with support for SD 1.5, SD 2.1, SDXL, SD3, FLUX models.
 *
 * Cross-platform: Uses Metal on iOS/macOS, CPU/Vulkan on Android.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.diffusion.sdcpp.SdcppDiffusion
 * SdcppDiffusion.register()
 * ```
 *
 * ## Usage
 *
 * Diffusion services are accessed through the main SDK APIs:
 *
 * ```kotlin
 * RunAnywhere.loadDiffusionModel(modelPath, modelId)
 * val result = RunAnywhere.generateImage("A sunset over mountains")
 * ```
 *
 * Matches the iOS architecture pattern exactly.
 */
object SdcppDiffusion : RunAnywhereModule {
    private val logger = SDKLogger("SdcppDiffusion")

    const val version = "1.0.0"

    override val moduleId: String = "sdcpp"
    override val moduleName: String = "stable-diffusion.cpp"
    override val capabilities: Set<SDKComponent> = setOf(SDKComponent.DIFFUSION)
    override val defaultPriority: Int = 90
    override val inferenceFramework: InferenceFramework = InferenceFramework.SDCPP

    @Volatile
    private var isRegistered = false

    @JvmStatic
    @JvmOverloads
    fun register(@Suppress("UNUSED_PARAMETER") priority: Int = defaultPriority) {
        if (isRegistered) {
            logger.debug("sd.cpp already registered, returning")
            return
        }

        logger.info("Registering sd.cpp diffusion backend with C++ registry...")

        val result = registerNative()

        if (result != 0 && result != -4) {
            logger.error("sd.cpp registration failed with code: $result")
            return
        }

        isRegistered = true
        logger.info("sd.cpp diffusion backend registered successfully")
    }

    fun unregister() {
        if (!isRegistered) return
        isRegistered = false
        logger.info("sd.cpp diffusion backend unregistered")
    }

    fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false
        val lower = modelId.lowercase()
        return lower.endsWith(".safetensors") || lower.endsWith(".gguf") || lower.endsWith(".ckpt")
    }

    val autoRegister: Unit by lazy {
        register()
    }
}

internal expect fun SdcppDiffusion.registerNative(): Int
