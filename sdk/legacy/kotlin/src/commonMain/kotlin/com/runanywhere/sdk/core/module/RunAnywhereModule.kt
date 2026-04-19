package com.runanywhere.sdk.core.module

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent

/**
 * Protocol for SDK modules that provide AI capabilities.
 *
 * Modules encapsulate backend-specific functionality for the SDK.
 * Each module typically provides one or more capabilities (LLM, STT, TTS, VAD).
 *
 * Registration with the C++ service registry is handled automatically by the
 * platform backend during SDK initialization. Modules only need to provide
 * metadata and service creation methods.
 *
 * ## Implementing a Module
 *
 * ```kotlin
 * object MyModule : RunAnywhereModule {
 *     override val moduleId = "my-module"
 *     override val moduleName = "My Module"
 *     override val capabilities = setOf(SDKComponent.LLM)
 *     override val defaultPriority = 100
 *     override val inferenceFramework = InferenceFramework.ONNX
 *
 *     fun register(priority: Int = defaultPriority) {
 *         // Register with C++ backend
 *     }
 * }
 * ```
 *
 * Matches iOS RunAnywhereModule.swift exactly.
 */
interface RunAnywhereModule {
    /** Unique identifier for this module (e.g., "llamacpp", "onnx") */
    val moduleId: String

    /** Human-readable name for the module */
    val moduleName: String

    /** Set of capabilities this module provides */
    val capabilities: Set<SDKComponent>

    /** Default priority for service registration (higher = preferred) */
    val defaultPriority: Int

    /** The inference framework this module uses */
    val inferenceFramework: InferenceFramework
}
