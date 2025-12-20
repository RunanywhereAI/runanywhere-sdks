package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.VADServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Platform VAD Service Provider
 */
class PlatformVADServiceProvider : VADServiceProvider {
    private val logger = SDKLogger("PlatformVADServiceProvider")

    override val name: String = "PlatformVAD"

    override suspend fun createVADService(configuration: VADConfiguration): VADService {
        logger.info("Creating Platform VAD Service")
        return createPlatformVADService().also {
            it.initialize(configuration)
        }
    }

    override fun canHandle(modelId: String): Boolean {
        // Platform VAD doesn't use models, so it can handle any request
        return true
    }

    companion object {
        /**
         * Register this provider with the module registry
         */
        fun register() {
            ModuleRegistry.registerVAD(PlatformVADServiceProvider())
        }
    }
}

/**
 * Platform-specific VAD service creation
 */
expect fun createPlatformVADService(): VADService
