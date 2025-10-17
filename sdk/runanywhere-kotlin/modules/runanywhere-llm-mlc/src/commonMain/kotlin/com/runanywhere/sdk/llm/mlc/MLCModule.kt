package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.core.AutoRegisteringModule
import com.runanywhere.sdk.core.ModuleRegistry

/**
 * MLC-LLM Module - auto-registers with ModuleRegistry
 *
 * Provides on-device LLM inference using MLC-compiled models with GPU acceleration.
 * This module implements the AutoRegisteringModule interface to enable automatic
 * registration when the module is on the classpath.
 *
 * ## Features
 * - GPU acceleration via OpenCL
 * - Token-by-token streaming generation
 * - Multi-modal support (text and image inputs)
 * - Compiled model execution for optimized performance
 *
 * ## Usage
 * ```kotlin
 * // Auto-registration happens automatically when module is on classpath
 * // Or manually register:
 * MLCModule.register()
 *
 * // Check availability
 * if (MLCModule.isAvailable) {
 *     // Use via ModuleRegistry
 *     val provider = ModuleRegistry.llmProvider("phi-3-mini-mlc")
 * }
 * ```
 */
object MLCModule : AutoRegisteringModule {

    private var provider: MLCProvider? = null

    /**
     * Register this module with the ModuleRegistry
     *
     * Checks for native library availability before registering the provider.
     * If native libraries are not available, registration is skipped silently.
     */
    override fun register() {
        if (checkNativeLibraryAvailable()) {
            provider = MLCProvider()
            ModuleRegistry.shared.registerLLM(provider!!)
        }
    }

    /**
     * Check if MLC-LLM native library is available
     *
     * @return true if the native TVM runtime library can be loaded
     */
    val isAvailable: Boolean
        get() = checkNativeLibraryAvailable()

    /**
     * Module name for identification
     */
    val name: String = "MLC-LLM"

    /**
     * Module version
     */
    val version: String = "0.1.0"

    /**
     * MLC-LLM framework version
     */
    val mlcLLMVersion: String = "0.1.0"

    /**
     * TVM runtime version (bundled with MLC)
     */
    val tvmVersion: String = "0.13.0"

    /**
     * Module description
     */
    val description: String =
        "On-device LLM inference using MLC-LLM framework with GPU acceleration via OpenCL"

    /**
     * Cleanup module resources
     *
     * Clears the provider reference to allow garbage collection.
     * Does not unregister from ModuleRegistry - use ModuleRegistry.clear() if needed.
     */
    fun cleanup() {
        provider = null
    }
}

/**
 * Platform-specific check for native library availability
 *
 * This is implemented using expect/actual pattern to provide platform-specific
 * implementations. On Android, it attempts to load the TVM runtime library.
 *
 * @return true if native library is available and can be loaded
 */
expect fun checkNativeLibraryAvailable(): Boolean
