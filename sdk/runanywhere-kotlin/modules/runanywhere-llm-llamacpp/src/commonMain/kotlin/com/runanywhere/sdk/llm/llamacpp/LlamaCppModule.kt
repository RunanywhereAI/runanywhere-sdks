package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.core.AutoRegisteringModule
import com.runanywhere.sdk.core.ModuleRegistry

/**
 * Auto-registering module for llama.cpp LLM provider
 * This module is automatically discovered and registered by the SDK
 */
object LlamaCppModule : AutoRegisteringModule {

    private var provider: LlamaCppProvider? = null

    override fun register() {
        if (isAvailable) {
            provider = LlamaCppProvider()
            ModuleRegistry.shared.registerLLM(provider!!)
        }
    }

    override val isAvailable: Boolean
        get() = checkNativeLibraryAvailable()

    override val name: String = "llama.cpp"

    override val version: String = "0.1.0"

    override val description: String = "On-device LLM inference using llama.cpp"

    override fun cleanup() {
        provider?.cleanup()
        provider = null
    }
}

/**
 * Check if native library is available - platform specific implementation
 */
expect fun checkNativeLibraryAvailable(): Boolean
