package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.frameworks.UnifiedFrameworkAdapter
import com.runanywhere.sdk.events.SDKFrameworkEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.FrameworkAvailability
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.primaryModality
import com.runanywhere.sdk.models.enums.supportedModalities
import com.runanywhere.sdk.public.RunAnywhereSDK
import com.runanywhere.sdk.public.models.ModelRegistration

/**
 * Framework Management extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+Framework.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Framework/RunAnywhere+Framework.swift
 */

private val frameworkLogger = SDKLogger("FrameworkAPI")

/**
 * Framework adapter interface
 * Matches iOS UnifiedFrameworkAdapter protocol
 */
interface FrameworkAdapter {
    val name: String
    val framework: LLMFramework
    val supportedModalities: Set<FrameworkModality>
    suspend fun isAvailable(): Boolean
}

/**
 * Register a framework adapter with name
 * Matches iOS registerFrameworkAdapter(name:adapter:) method
 *
 * @param name Name identifier for the adapter
 * @param adapter The framework adapter to register
 */
fun RunAnywhereSDK.registerFrameworkAdapter(name: String, adapter: FrameworkAdapter) {
    frameworkLogger.debug("Registering framework adapter: $name for framework ${adapter.framework}")

    // Publish event
    events.publish(SDKFrameworkEvent.AdapterRegistered(
        framework = adapter.framework.name,
        name = name
    ))

    // Register with ModuleRegistry
    // TODO: Extend ModuleRegistry to support generic framework adapters
    frameworkLogger.warning("Framework adapter registration is placeholder - ModuleRegistry extension needed")

    frameworkLogger.info("Framework adapter registered: $name")
}

/**
 * Register a framework adapter
 * Matches iOS registerFrameworkAdapter(_:) method
 *
 * @param adapter The framework adapter to register
 */
fun RunAnywhereSDK.registerFrameworkAdapter(adapter: FrameworkAdapter) {
    registerFrameworkAdapter(adapter.name, adapter)
}

/**
 * Register a framework with optional models.
 * This is the primary registration API matching iOS RunAnywhere.registerFramework(_:models:) exactly.
 *
 * Registration flow:
 * 1. Register adapter with ModuleRegistry (via registerFrameworkAdapter)
 * 2. Adapter's onRegistration() is called to register service providers
 * 3. Each ModelRegistration is converted to ModelInfo and registered
 *
 * All parameters are strongly typed - uses LLMFramework and FrameworkModality enums.
 *
 * @param adapter The UnifiedFrameworkAdapter to register
 * @param models List of ModelRegistration objects to register with this framework
 */
suspend fun RunAnywhereSDK.registerFramework(
    adapter: UnifiedFrameworkAdapter,
    models: List<ModelRegistration> = emptyList()
) {
    frameworkLogger.info("Registering framework ${adapter.framework} with ${models.size} models")

    // 1. Register the adapter with ModuleRegistry
    ModuleRegistry.shared.registerFrameworkAdapter(adapter)
    frameworkLogger.debug("Adapter registered with ModuleRegistry")

    // 2. onRegistration() is called by ModuleRegistry.registerFrameworkAdapter()
    // which registers the adapter's service providers (STT, TTS, LLM, etc.)

    // 3. Publish adapter registration event
    events.publish(SDKFrameworkEvent.AdapterRegistered(
        framework = adapter.framework.name,
        name = adapter.framework.displayName
    ))

    // 4. Register each model
    for (modelReg in models) {
        val modelInfo = modelReg.toModelInfo()

        // Register in model registry
        ServiceContainer.shared.modelRegistry.registerModel(modelInfo)

        // Also persist to database
        try {
            ServiceContainer.shared.modelInfoService.saveModel(modelInfo)
            frameworkLogger.debug("Model registered and persisted: ${modelInfo.id}")
        } catch (e: Exception) {
            frameworkLogger.warn("Model registered but not persisted: ${modelInfo.id} - ${e.message}")
            // Continue anyway - model is still in registry for this session
        }
    }

    frameworkLogger.info("Framework ${adapter.framework} registered with ${models.size} models")
}

/**
 * Get all registered framework adapters
 * Matches iOS getRegisteredAdapters() method
 *
 * @return List of registered adapter names
 */
suspend fun RunAnywhereSDK.getRegisteredAdapters(): List<String> {
    frameworkLogger.debug("Getting registered adapters")

    // Publish event
    events.publish(SDKFrameworkEvent.AdaptersRequested)

    val adapters = try {
        // Get from ModuleRegistry
        val llmProviders = ModuleRegistry.allLLMProviders.map { it.name }
        val sttProviders = ModuleRegistry.allSTTProviders.map { it.name }
        val ttsProviders = ModuleRegistry.allTTSProviders.map { it.name }

        (llmProviders + sttProviders + ttsProviders).distinct()
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get registered adapters: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.AdaptersRetrieved(adapters.size))

    frameworkLogger.debug("Found ${adapters.size} registered adapters")
    return adapters
}

/**
 * Get available frameworks
 * Matches iOS getAvailableFrameworks() method
 *
 * @return List of available LLMFramework values
 */
suspend fun RunAnywhereSDK.getAvailableFrameworks(): List<LLMFramework> {
    frameworkLogger.debug("Getting available frameworks")

    // Publish event
    events.publish(SDKFrameworkEvent.FrameworksRequested)

    val frameworks = try {
        // Return frameworks that have registered providers
        val availableFrameworks = mutableSetOf<LLMFramework>()

        // Check LLM providers
        ModuleRegistry.allLLMProviders.forEach { provider ->
            // Map provider name to framework
            val framework = frameworkFromProviderName(provider.name)
            if (framework != null) {
                availableFrameworks.add(framework)
            }
        }

        // Check STT providers
        ModuleRegistry.allSTTProviders.forEach { provider ->
            val framework = frameworkFromProviderName(provider.name)
            if (framework != null) {
                availableFrameworks.add(framework)
            }
        }

        // Check TTS providers
        ModuleRegistry.allTTSProviders.forEach { provider ->
            val framework = frameworkFromProviderName(provider.name)
            if (framework != null) {
                availableFrameworks.add(framework)
            }
        }

        availableFrameworks.toList()
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get available frameworks: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.FrameworksRetrieved(frameworks.map { it.name }))

    frameworkLogger.debug("Found ${frameworks.size} available frameworks")
    return frameworks
}

/**
 * Get detailed framework availability information
 * Matches iOS getFrameworkAvailability() method
 *
 * @return List of FrameworkAvailability with detailed info
 */
suspend fun RunAnywhereSDK.getFrameworkAvailability(): List<FrameworkAvailability> {
    frameworkLogger.debug("Getting framework availability")

    // Publish event
    events.publish(SDKFrameworkEvent.AvailabilityRequested)

    val availability = try {
        val availableFrameworks = getAvailableFrameworks().toSet()

        LLMFramework.entries.map { framework ->
            val isAvailable = availableFrameworks.contains(framework)
            val reason = if (!isAvailable) getUnavailabilityReason(framework) else null

            FrameworkAvailability.forFramework(
                framework = framework,
                isAvailable = isAvailable,
                unavailabilityReason = reason
            )
        }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get framework availability: ${e.message}")
        emptyList()
    }

    // Publish completion event
    val availableList = availability.filter { it.isAvailable }.map { it.framework.name }
    events.publish(SDKFrameworkEvent.AvailabilityRetrieved(availableList))

    frameworkLogger.debug("Framework availability: ${availability.size} frameworks checked")
    return availability
}

/**
 * Get available frameworks for a specific modality
 * Matches iOS getFrameworks(for modality:) method
 *
 * @param modality The FrameworkModality to filter by
 * @return List of LLMFramework values supporting the modality
 */
suspend fun RunAnywhereSDK.getFrameworks(modality: FrameworkModality): List<LLMFramework> {
    frameworkLogger.debug("Getting frameworks for modality: $modality")

    // Publish event
    events.publish(SDKFrameworkEvent.FrameworksForModalityRequested(modality.name))

    val frameworks = try {
        // Filter all frameworks by modality support
        LLMFramework.entries.filter { framework ->
            framework.supportedModalities.contains(modality)
        }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get frameworks for modality $modality: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.FrameworksForModalityRetrieved(modality.name, frameworks.map { it.name }))

    frameworkLogger.debug("Found ${frameworks.size} frameworks for modality $modality")
    return frameworks
}

/**
 * Get available frameworks for a specific model category
 * Convenience method matching iOS patterns
 *
 * @param category The ModelCategory to filter by
 * @return List of LLMFramework values supporting the category
 */
suspend fun RunAnywhereSDK.getFrameworks(category: ModelCategory): List<LLMFramework> {
    return getFrameworks(category.frameworkModality)
}

/**
 * Get primary modality for a framework
 * Matches iOS getPrimaryModality(for:) method
 *
 * @param framework The LLMFramework
 * @return Primary FrameworkModality the framework supports
 */
fun RunAnywhereSDK.getPrimaryModality(framework: LLMFramework): FrameworkModality {
    frameworkLogger.debug("Getting primary modality for framework: $framework")
    return framework.primaryModality
}

/**
 * Check if framework supports a specific modality
 * Matches iOS frameworkSupports(_:modality:) method
 *
 * @param framework The LLMFramework
 * @param modality The FrameworkModality to check
 * @return True if framework supports the modality
 */
fun RunAnywhereSDK.frameworkSupports(framework: LLMFramework, modality: FrameworkModality): Boolean {
    frameworkLogger.debug("Checking if $framework supports $modality")
    return framework.supportedModalities.contains(modality)
}

// NOTE: getModelsForFramework is defined in RunAnywhereModelAssignments.kt

// MARK: - Legacy String-based API (for backward compatibility)

/**
 * Get available frameworks as string names
 * @deprecated Use getAvailableFrameworks() returning List<LLMFramework> instead
 */
@Deprecated("Use getAvailableFrameworks() returning List<LLMFramework>", ReplaceWith("getAvailableFrameworks()"))
suspend fun RunAnywhereSDK.getAvailableFrameworkNames(): List<String> {
    return getAvailableFrameworks().map { it.displayName }
}

/**
 * Get framework availability as Map
 * @deprecated Use getFrameworkAvailability() returning List<FrameworkAvailability> instead
 */
@Deprecated("Use getFrameworkAvailability() returning List<FrameworkAvailability>", ReplaceWith("getFrameworkAvailability()"))
suspend fun RunAnywhereSDK.getFrameworkAvailabilityMap(): Map<String, Boolean> {
    return getFrameworkAvailability().associate { it.framework.name to it.isAvailable }
}

// MARK: - Helper Functions

/**
 * Map provider name to LLMFramework
 */
private fun frameworkFromProviderName(name: String): LLMFramework? {
    val normalizedName = name.lowercase()
    return when {
        normalizedName.contains("llama") -> LLMFramework.LLAMA_CPP
        normalizedName.contains("whisper") && normalizedName.contains("kit") -> LLMFramework.WHISPER_KIT
        normalizedName.contains("whisper") && normalizedName.contains("cpp") -> LLMFramework.WHISPER_CPP
        normalizedName.contains("whisper") -> LLMFramework.OPEN_AI_WHISPER
        normalizedName.contains("onnx") -> LLMFramework.ONNX
        normalizedName.contains("tflite") || normalizedName.contains("tensorflow") -> LLMFramework.TENSOR_FLOW_LITE
        normalizedName.contains("coreml") -> LLMFramework.CORE_ML
        normalizedName.contains("foundation") -> LLMFramework.FOUNDATION_MODELS
        normalizedName.contains("mediapipe") -> LLMFramework.MEDIA_PIPE
        normalizedName.contains("mlx") -> LLMFramework.MLX
        normalizedName.contains("mlc") -> LLMFramework.MLC
        normalizedName.contains("execu") || normalizedName.contains("torch") -> LLMFramework.EXECU_TORCH
        normalizedName.contains("pico") -> LLMFramework.PICO_LLM
        normalizedName.contains("swift") && normalizedName.contains("transformer") -> LLMFramework.SWIFT_TRANSFORMERS
        normalizedName.contains("system") && normalizedName.contains("tts") -> LLMFramework.SYSTEM_TTS
        normalizedName.contains("tts") -> LLMFramework.SYSTEM_TTS
        else -> null
    }
}

/**
 * Get unavailability reason for a framework
 */
private fun getUnavailabilityReason(framework: LLMFramework): String {
    return when (framework) {
        LLMFramework.FOUNDATION_MODELS -> "Requires iOS 18+ / macOS 15+"
        LLMFramework.CORE_ML -> "No CoreML provider registered"
        LLMFramework.MLX -> "Requires Apple Silicon Mac"
        LLMFramework.SWIFT_TRANSFORMERS -> "No Swift Transformers provider registered"
        LLMFramework.WHISPER_KIT -> "No WhisperKit provider registered"
        LLMFramework.SYSTEM_TTS -> "No System TTS provider registered"
        else -> "No provider registered for ${framework.displayName}"
    }
}
