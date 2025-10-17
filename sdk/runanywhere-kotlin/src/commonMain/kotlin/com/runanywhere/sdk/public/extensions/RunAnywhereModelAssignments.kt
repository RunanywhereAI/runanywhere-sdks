package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.events.SDKFrameworkEvent
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Model Assignments extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+ModelAssignments.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/ModelAssignments/RunAnywhere+ModelAssignments.swift
 *
 * Note: Phase 2 implementation - provides backend-driven model assignment capabilities
 */

private val assignmentsLogger = SDKLogger("ModelAssignmentsAPI")

/**
 * Model assignment from backend
 * Matches iOS ModelAssignment struct
 */
data class ModelAssignment(
    val modelId: String,
    val category: ModelCategory,
    val framework: LLMFramework,
    val priority: Int = 0,
    val isRecommended: Boolean = false,
    val metadata: Map<String, String> = emptyMap()
)

/**
 * Fetch model assignments from backend
 * Matches iOS fetchModelAssignments() method
 *
 * @return List of model assignments from backend
 */
suspend fun RunAnywhereSDK.fetchModelAssignments(): List<ModelAssignment> {
    assignmentsLogger.debug("Fetching model assignments from backend")

    // Publish event
    events.publish(SDKModelEvent.ListRequested)

    val assignments = try {
        // TODO: Fetch from backend API when available
        // For now, return default assignments based on available models
        assignmentsLogger.warning("Model assignments fetch is placeholder - backend API not implemented")

        val defaultAssignments = listOf(
            ModelAssignment(
                modelId = "llama-2-7b-chat",
                category = ModelCategory.LANGUAGE,
                framework = LLMFramework.LLAMA_CPP,
                priority = 1,
                isRecommended = true,
                metadata = mapOf("size" to "7B", "type" to "chat")
            ),
            ModelAssignment(
                modelId = "whisper-base",
                category = ModelCategory.SPEECH_RECOGNITION,
                framework = LLMFramework.WHISPER_CPP,
                priority = 1,
                isRecommended = true,
                metadata = mapOf("language" to "multilingual")
            )
        )

        // Publish completion event
        val modelInfos = defaultAssignments.map { assignment ->
            ModelInfo(
                id = assignment.modelId,
                name = assignment.modelId,
                category = assignment.category,
                format = com.runanywhere.sdk.models.enums.ModelFormat.GGUF,
                downloadURL = null,
                localPath = null,
                downloadSize = 0L, // Placeholder
                compatibleFrameworks = listOf(assignment.framework),
                preferredFramework = assignment.framework
            )
        }
        events.publish(SDKModelEvent.ListCompleted(modelInfos))

        defaultAssignments
    } catch (e: Exception) {
        assignmentsLogger.error("Failed to fetch model assignments: ${e.message}")
        events.publish(SDKModelEvent.ListFailed(e))
        throw e
    }

    assignmentsLogger.info("Fetched ${assignments.size} model assignments")
    return assignments
}

/**
 * Get models for a specific framework
 * Matches iOS getModelsForFramework(_:) method
 *
 * @param framework The LLM framework
 * @return List of model IDs for the framework
 */
suspend fun RunAnywhereSDK.getModelsForFramework(framework: LLMFramework): List<String> {
    assignmentsLogger.debug("Getting models for framework: $framework")

    // Publish event
    events.publish(SDKFrameworkEvent.ModelsForFrameworkRequested(framework.name))

    val models = try {
        // Fetch assignments and filter by framework
        val assignments = fetchModelAssignments()
        assignments.filter { it.framework == framework }
            .sortedByDescending { it.priority }
            .map { it.modelId }
    } catch (e: Exception) {
        assignmentsLogger.error("Failed to get models for framework: ${e.message}")
        emptyList()
    }

    // Publish completion event
    events.publish(SDKFrameworkEvent.ModelsForFrameworkRetrieved(framework.name, models))

    assignmentsLogger.debug("Found ${models.size} models for framework $framework")
    return models
}

/**
 * Get models for a specific category
 * Matches iOS getModelsForCategory(_:) method
 *
 * @param category The model category
 * @return List of model IDs for the category
 */
suspend fun RunAnywhereSDK.getModelsForCategory(category: ModelCategory): List<String> {
    assignmentsLogger.debug("Getting models for category: $category")

    val models = try {
        // Fetch assignments and filter by category
        val assignments = fetchModelAssignments()
        assignments.filter { it.category == category }
            .sortedByDescending { it.priority }
            .map { it.modelId }
    } catch (e: Exception) {
        assignmentsLogger.error("Failed to get models for category: ${e.message}")
        emptyList()
    }

    assignmentsLogger.debug("Found ${models.size} models for category $category")
    return models
}

/**
 * Clear cached model assignments
 * Matches iOS clearModelAssignmentsCache() method
 */
suspend fun RunAnywhereSDK.clearModelAssignmentsCache() {
    assignmentsLogger.debug("Clearing model assignments cache")

    try {
        // TODO: Clear cache when caching is implemented
        assignmentsLogger.warning("Model assignments cache clear is placeholder - no cache implemented yet")

        assignmentsLogger.info("Model assignments cache cleared (no-op)")
    } catch (e: Exception) {
        assignmentsLogger.error("Failed to clear model assignments cache: ${e.message}")
        throw e
    }
}
