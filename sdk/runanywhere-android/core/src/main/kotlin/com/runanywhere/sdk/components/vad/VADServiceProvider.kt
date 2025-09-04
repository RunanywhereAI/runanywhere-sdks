package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.ModuleRegistry
import com.runanywhere.sdk.components.base.VADServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * WebRTC VAD Service Provider
 */
class WebRTCVADServiceProvider : VADServiceProvider {
    private val logger = SDKLogger("WebRTCVADServiceProvider")

    override val name: String = "WebRTCVAD"

    override suspend fun createVADService(configuration: VADConfiguration): VADService {
        logger.info("Creating WebRTC VAD Service")
        val service = WebRTCVADService()
        service.initialize(configuration)
        return service
    }

    override fun canHandle(modelId: String?): Boolean {
        // WebRTC VAD doesn't use models, so it can handle any request
        return true
    }

    companion object {
        /**
         * Register this provider with the module registry
         */
        fun register() {
            ModuleRegistry.registerVADProvider(WebRTCVADServiceProvider())
        }
    }
}
