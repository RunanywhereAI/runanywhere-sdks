package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.events.SDKFrameworkEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Framework Management extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+Framework.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Framework/RunAnywhere+Framework.swift
 *
 * Note: Phase 2 implementation - provides framework adapter registration and discovery
 */

private val frameworkLogger = SDKLogger("FrameworkAPI")

/**
 * Framework adapter interface
 * Matches iOS FrameworkAdapter protocol
 */
interface FrameworkAdapter {
    val name: String
    val framework: LLMFramework
    val supportedModalities: List<ModelCategory>
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
        // TODO: Get from ModuleRegistry when framework adapter support is added
        // For now, return known providers
        val llmProviders = ModuleRegistry.allLLMProviders.map { it.name }
        val sttProviders = ModuleRegistry.allSTTProviders.map { it.name }

        llmProviders + sttProviders
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
 * @return List of available framework names
 */
suspend fun RunAnywhereSDK.getAvailableFrameworks(): List<String> {
    frameworkLogger.debug("Getting available frameworks")

    // Publish event
    events.publish(SDKFrameworkEvent.FrameworksRequested)

    val frameworks = try {
        // Return all LLM framework types that could be available
        LLMFramework.values().map { it.name }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get available frameworks: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.FrameworksRetrieved(frameworks))

    frameworkLogger.debug("Found ${frameworks.size} available frameworks")
    return frameworks
}

/**
 * Get framework availability status
 * Matches iOS getFrameworkAvailability() method
 *
 * @return Map of framework names to availability status
 */
suspend fun RunAnywhereSDK.getFrameworkAvailability(): Map<String, Boolean> {
    frameworkLogger.debug("Getting framework availability")

    // Publish event
    events.publish(SDKFrameworkEvent.AvailabilityRequested)

    val availability = try {
        // Check which frameworks have registered providers
        val llmFrameworks = ModuleRegistry.allLLMProviders.map { it.name to true }.toMap()
        val sttFrameworks = ModuleRegistry.allSTTProviders.map { it.name to true }.toMap()

        // Combine and add known frameworks as unavailable if not registered
        val allFrameworks = LLMFramework.values().associate { it.name to false }

        allFrameworks + llmFrameworks + sttFrameworks
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get framework availability: ${e.message}")
        emptyMap()
    }

    // Publish completion event
    val availableList = availability.filter { it.value }.keys.toList()
    events.publish(SDKFrameworkEvent.AvailabilityRetrieved(availableList))

    frameworkLogger.debug("Framework availability: ${availability.size} frameworks checked")
    return availability
}

/**
 * Get models supported by a specific framework
 * Matches iOS getModelsForFramework(_:) method
 *
 * @param framework The framework to query
 * @return List of model IDs supported by the framework
 */
suspend fun RunAnywhereSDK.getModelsForFramework(framework: String): List<String> {
    frameworkLogger.debug("Getting models for framework: $framework")

    // Publish event
    events.publish(SDKFrameworkEvent.ModelsForFrameworkRequested(framework))

    val models = try {
        // TODO: Query model registry for models by framework
        // For now, return placeholder based on framework type
        when (framework.uppercase()) {
            "LLAMA_CPP" -> listOf("llama-2-7b-chat", "llama-2-13b-chat")
            "ONNX" -> listOf("phi-2", "mistral-7b")
            "TENSORFLOW_LITE" -> listOf("whisper-base", "whisper-small")
            else -> emptyList()
        }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get models for framework $framework: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.ModelsForFrameworkRetrieved(framework, models))

    frameworkLogger.debug("Found ${models.size} models for framework $framework")
    return models
}

/**
 * Get available frameworks for a specific modality
 * Matches iOS getFrameworks(forModality:) method
 *
 * @param modality The model category/modality (TEXT, SPEECH, etc.)
 * @return List of framework names supporting the modality
 */
suspend fun RunAnywhereSDK.getFrameworks(modality: ModelCategory): List<String> {
    frameworkLogger.debug("Getting frameworks for modality: $modality")

    // Publish event
    events.publish(SDKFrameworkEvent.FrameworksForModalityRequested(modality.name))

    val frameworks = try {
        // Map modalities to frameworks
        when (modality) {
            ModelCategory.LANGUAGE, ModelCategory.LANGUAGE_MODEL -> listOf("LLAMA_CPP", "ONNX", "TENSORFLOW_LITE")
            ModelCategory.SPEECH_RECOGNITION -> listOf("TENSORFLOW_LITE", "ONNX", "WHISPER_CPP")
            ModelCategory.SPEECH_SYNTHESIS -> listOf("TENSORFLOW_LITE")
            ModelCategory.VISION -> listOf("CORE_ML", "TENSORFLOW_LITE")
            ModelCategory.IMAGE_GENERATION -> listOf("TENSORFLOW_LITE", "CORE_ML")
            ModelCategory.MULTIMODAL -> listOf("CORE_ML", "TENSORFLOW_LITE", "ONNX")
            ModelCategory.AUDIO -> listOf("TENSORFLOW_LITE", "ONNX")
        }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to get frameworks for modality $modality: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.FrameworksForModalityRetrieved(modality.name, frameworks))

    frameworkLogger.debug("Found ${frameworks.size} frameworks for modality $modality")
    return frameworks
}

/**
 * Get primary modality for a framework
 * Matches iOS getPrimaryModality(for:) method
 *
 * @param framework The framework name
 * @return Primary model category the framework supports
 */
fun RunAnywhereSDK.getPrimaryModality(framework: String): ModelCategory {
    frameworkLogger.debug("Getting primary modality for framework: $framework")

    val modality = when (framework.uppercase()) {
        "LLAMA_CPP", "ONNX" -> ModelCategory.LANGUAGE
        "TENSORFLOW_LITE" -> ModelCategory.MULTIMODAL
        "CORE_ML" -> ModelCategory.VISION
        "WHISPER_CPP" -> ModelCategory.SPEECH_RECOGNITION
        else -> ModelCategory.LANGUAGE
    }

    frameworkLogger.debug("Primary modality for $framework: $modality")
    return modality
}

/**
 * Check if framework supports a specific modality
 * Matches iOS frameworkSupports(_:modality:) method
 *
 * @param framework The framework name
 * @param modality The model category to check
 * @return True if framework supports the modality
 */
suspend fun RunAnywhereSDK.frameworkSupports(framework: String, modality: ModelCategory): Boolean {
    frameworkLogger.debug("Checking if $framework supports $modality")

    val supported = try {
        val supportedFrameworks = getFrameworks(modality)
        supportedFrameworks.any { it.equals(framework, ignoreCase = true) }
    } catch (e: Exception) {
        frameworkLogger.error("Failed to check framework support: ${e.message}")
        false
    }

    frameworkLogger.debug("Framework $framework supports $modality: $supported")
    return supported
}
