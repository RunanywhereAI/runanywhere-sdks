package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.ModuleRegistry
import com.runanywhere.sdk.components.base.VADServiceProvider

/**
 * JVM VAD Service Provider
 * Provides a simple VAD implementation for JVM platform
 */
object JvmVADServiceProvider : VADServiceProvider {

    override suspend fun createVADService(configuration: VADConfiguration): VADService {
        val service = JvmVADService()
        service.initialize(configuration)
        return service
    }

    override fun canHandle(modelId: String?): Boolean {
        // Can handle all VAD requests on JVM
        return true
    }

    override val name: String = "JVM VAD Provider"

    /**
     * Register this provider with the module registry
     */
    fun register() {
        ModuleRegistry.registerVADProvider(this)
    }
}
