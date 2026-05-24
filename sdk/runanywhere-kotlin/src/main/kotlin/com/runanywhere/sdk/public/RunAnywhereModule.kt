/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Unified module-registration protocol for backend modules
 * (LlamaCPP, ONNX, SystemTTS, etc.).
 */

package com.runanywhere.sdk.public

/**
 * Protocol for self-registering RunAnywhere SDK modules.
 *
 * Mirrors Swift's `RunAnywhereModule` protocol. Backend modules
 * (LlamaCPP, ONNX, SystemTTS) implement this for unified registration
 * with the C++ service registry and (where applicable) the Kotlin
 * model registry. Apps invoke [register] / [unregister] from a
 * coroutine scope once during SDK bootstrap.
 *
 * ## Implementing a Module
 *
 * ```kotlin
 * object MyModule : RunAnywhereModule {
 *     override val moduleName = "MyModule"
 *     override suspend fun register() {
 *         // Load native libs, call rac_backend_*_register, seed registry, etc.
 *     }
 *     override suspend fun unregister() {
 *         // Call rac_backend_*_unregister where supported.
 *     }
 * }
 * ```
 */
interface RunAnywhereModule {
    /** Human-readable module name (e.g. "LlamaCPP", "ONNX", "SystemTTS"). */
    val moduleName: String

    /** Register this module with the SDK (load native libs, register backend, seed registry). */
    suspend fun register()

    /** Unregister this module from the SDK. May be a no-op when the underlying registry does not support removal. */
    suspend fun unregister()
}
