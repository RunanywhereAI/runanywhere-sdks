package com.runanywhere.sdk.core

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.infrastructure.download.DownloadStrategy
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelArtifactType
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * Types of capabilities that modules can provide
 * Matches iOS CapabilityType exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift
 */
enum class CapabilityType(
    val value: String,
) {
    STT("STT"),
    TTS("TTS"),
    LLM("LLM"),
    VAD("VAD"),
    SPEAKER_DIARIZATION("SpeakerDiarization"),
    ;

    companion object {
        fun fromValue(value: String): CapabilityType? {
            return entries.find { it.value == value }
        }
    }
}

/**
 * Protocol for RunAnywhere modules that provide AI services.
 *
 * External modules (ONNX, LlamaCPP, WhisperKit, etc.) implement this interface
 * to register their services with the SDK in a standardized way.
 *
 * Matches iOS RunAnywhereModule protocol exactly.
 *
 * ## Implementing a Module
 *
 * ```kotlin
 * object MyModule : RunAnywhereModule {
 *     override val moduleId = "my-module"
 *     override val moduleName = "My Custom Module"
 *     override val inferenceFramework = InferenceFramework.ONNX
 *     override val capabilities = setOf(CapabilityType.STT, CapabilityType.TTS)
 *
 *     override fun register(priority: Int) { ... }
 * }
 * ```
 *
 * ## Registration with Models
 *
 * ```kotlin
 * LlamaCPP.register()
 * LlamaCPP.addModel(name = "Llama 2 7B", url = "...", memoryRequirement = 4_000_000_000)
 * ```
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift
 */
interface RunAnywhereModule {
    /**
     * Unique identifier for this module (e.g., "onnx", "llamacpp", "whisperkit")
     */
    val moduleId: String

    /**
     * Human-readable display name (e.g., "ONNX Runtime", "LlamaCPP")
     */
    val moduleName: String

    /**
     * The inference framework this module provides (required)
     */
    val inferenceFramework: InferenceFramework

    /**
     * Set of capabilities this module provides
     */
    val capabilities: Set<CapabilityType>

    /**
     * Default priority for service registration (higher = preferred)
     * Default is 100
     */
    val defaultPriority: Int
        get() = 100

    /**
     * Optional storage strategy for detecting downloaded models
     * Modules with directory-based models (like ONNX) should provide this
     */
    val storageStrategy: ModelStorageStrategy?
        get() = null

    /**
     * Optional download strategy for custom download handling
     * Modules with special download requirements (like WhisperKit) should provide this
     */
    val downloadStrategy: DownloadStrategy?
        get() = null

    /**
     * Register all services provided by this module with the ServiceRegistry.
     * This is called by ModuleRegistry.register(module) - modules should NOT call
     * ModuleRegistry from this method to avoid infinite recursion.
     *
     * @param priority Registration priority (higher values are preferred)
     */
    fun registerServices(priority: Int)
}

/**
 * Extension functions for RunAnywhereModule
 * Matches iOS extension methods
 */

/**
 * Add a model to this module (uses the module's inferenceFramework automatically)
 *
 * @param id Explicit model ID. If null, a stable ID is generated from the URL filename.
 * @param name Display name for the model
 * @param url Download URL string for the model
 * @param modality Model category (inferred from module capabilities if not specified)
 * @param artifactType How the model is packaged (inferred from URL if not specified)
 * @param memoryRequirement Estimated memory usage in bytes
 * @param supportsThinking Whether the model supports reasoning/thinking
 * @return The created ModelInfo, or null if URL is invalid
 */
fun RunAnywhereModule.addModel(
    id: String? = null,
    name: String,
    url: String,
    modality: ModelCategory? = null,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
): ModelInfo? {
    val logger = SDKLogger("Module.${this.moduleId}")

    // Validate URL
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
        logger.error("Invalid URL for model '$name': $url")
        return null
    }

    // Determine modality from parameter or infer from module capabilities
    val category = modality ?: inferModalityFromCapabilities()

    // Generate ID from URL filename if not provided
    val modelId = id ?: url.substringAfterLast('/').substringBeforeLast('.')

    // Register the model with this module's framework
    val modelInfo =
        ServiceContainer.shared.modelRegistry.addModelFromURL(
            id = modelId,
            name = name,
            url = url,
            framework = inferenceFramework,
            category = category,
            artifactType = artifactType,
            estimatedSize = memoryRequirement,
            supportsThinking = supportsThinking,
        )

    return modelInfo
}

/**
 * Infer the primary modality from module capabilities
 */
private fun RunAnywhereModule.inferModalityFromCapabilities(): ModelCategory {
    return when {
        capabilities.contains(CapabilityType.LLM) -> ModelCategory.LANGUAGE
        capabilities.contains(CapabilityType.STT) -> ModelCategory.SPEECH_RECOGNITION
        capabilities.contains(CapabilityType.TTS) -> ModelCategory.SPEECH_SYNTHESIS
        capabilities.contains(CapabilityType.VAD) ||
            capabilities.contains(CapabilityType.SPEAKER_DIARIZATION) -> ModelCategory.AUDIO
        else -> ModelCategory.LANGUAGE // Default
    }
}

/**
 * Metadata about a registered module
 * Matches iOS ModuleMetadata exactly
 */
data class ModuleMetadata(
    /**
     * Module identifier
     */
    val moduleId: String,
    /**
     * Display name
     */
    val moduleName: String,
    /**
     * Capabilities provided
     */
    val capabilities: Set<CapabilityType>,
    /**
     * Registration priority used
     */
    val priority: Int,
    /**
     * When the module was registered (timestamp in milliseconds)
     */
    val registeredAt: Long = currentTimeMillis(),
)

/**
 * Thread-safe storage for module auto-discovery.
 *
 * This is a separate helper to allow modules to register themselves
 * for discovery during static initialization.
 *
 * Matches iOS ModuleDiscovery exactly.
 *
 * ## Usage
 *
 * ```kotlin
 * // In your module's companion object:
 * companion object {
 *     init {
 *         ModuleDiscovery.register(MyModule)
 *     }
 * }
 *
 * // At app startup:
 * ModuleDiscovery.registerDiscoveredModules()
 * ```
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Module/ModuleRegistry.swift
 */
object ModuleDiscovery {
    private val lock = Any()
    private val _discoveredModules = mutableListOf<RunAnywhereModule>()
    private val logger = SDKLogger("ModuleDiscovery")

    /**
     * Get all discovered modules (thread-safe)
     */
    val discoveredModules: List<RunAnywhereModule>
        get() = synchronized(lock) { _discoveredModules.toList() }

    /**
     * Register a module for auto-discovery.
     *
     * Call this from your module's static initialization to enable auto-registration.
     *
     * ```kotlin
     * object MyModule : RunAnywhereModule {
     *     init {
     *         ModuleDiscovery.register(this)
     *     }
     *     // ...
     * }
     * ```
     *
     * @param module The module to register for discovery
     */
    fun register(module: RunAnywhereModule) {
        synchronized(lock) {
            // Only add if not already registered
            if (!_discoveredModules.any { it.moduleId == module.moduleId }) {
                _discoveredModules.add(module)
                logger.debug("Module discovered: ${module.moduleName} [${module.moduleId}]")
            }
        }
    }

    /**
     * Register all discovered modules with the ModuleRegistry.
     * This should be called at app startup after all module imports.
     *
     * Matches iOS ModuleRegistry.shared.registerDiscoveredModules()
     */
    fun registerDiscoveredModules() {
        val discovered = discoveredModules
        logger.info("Registering ${discovered.size} discovered modules")

        for (module in discovered) {
            if (!ModuleRegistry.shared.isRegistered(module.moduleId)) {
                ModuleRegistry.shared.register(module)
                logger.info("Auto-registered module: ${module.moduleName}")
            }
        }
    }

    /**
     * Clear all discovered modules (for testing)
     */
    fun reset() {
        synchronized(lock) {
            _discoveredModules.clear()
        }
    }
}
