package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelCriteria
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.lifecycle.Modality
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleTracker
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * RunAnywhere Model Discovery Extensions
 *
 * Clean API for discovering models by framework and modality.
 * This provides a unified way to:
 * - Get registered frameworks
 * - Get models by framework
 * - Get models by modality (text-to-text, voice-to-text, etc.)
 * - Filter downloaded vs available models
 *
 * Matches iOS patterns for model discovery and filtering.
 */

private val discoveryLogger = SDKLogger("ModelDiscovery")

// =============================================================================
// MARK: - Framework Discovery
// =============================================================================

/**
 * Get all registered frameworks that have models available.
 *
 * @return List of unique frameworks with registered models
 */
suspend fun RunAnywhereSDK.getRegisteredFrameworks(): List<LLMFramework> {
    discoveryLogger.debug("Getting registered frameworks")

    val frameworks = ServiceContainer.shared.modelRegistry.getAllModels()
        .mapNotNull { it.preferredFramework }
        .distinct()

    discoveryLogger.info("Found ${frameworks.size} registered frameworks")
    return frameworks
}

/**
 * Get detailed information about registered frameworks with model counts.
 *
 * @return Map of framework to model count
 */
suspend fun RunAnywhereSDK.getFrameworkModelCounts(): Map<LLMFramework, Int> {
    val models = ServiceContainer.shared.modelRegistry.getAllModels()

    return models
        .groupBy { it.preferredFramework }
        .filterKeys { it != null }
        .mapKeys { it.key!! }
        .mapValues { it.value.size }
}

// =============================================================================
// MARK: - Model Discovery by Modality
// =============================================================================

/**
 * Get all models for a specific modality (text-to-text, voice-to-text, etc.)
 *
 * @param modality The FrameworkModality to filter by
 * @return List of models supporting the modality
 */
suspend fun RunAnywhereSDK.getModels(modality: FrameworkModality): List<ModelInfo> {
    discoveryLogger.debug("Getting models for modality: $modality")

    val category = ModelCategory.from(modality)
    val models = ServiceContainer.shared.modelRegistry.filterModels(
        ModelCriteria(category = category)
    )

    discoveryLogger.info("Found ${models.size} models for modality $modality")
    return models
}

/**
 * Get all text-to-text (LLM/chat) models
 *
 * @return List of text-to-text models
 */
suspend fun RunAnywhereSDK.getTextToTextModels(): List<ModelInfo> {
    return getModels(FrameworkModality.TEXT_TO_TEXT)
}

/**
 * Get all voice-to-text (STT/transcription) models
 *
 * @return List of voice-to-text models
 */
suspend fun RunAnywhereSDK.getVoiceToTextModels(): List<ModelInfo> {
    return getModels(FrameworkModality.VOICE_TO_TEXT)
}

/**
 * Get all text-to-voice (TTS) models
 *
 * @return List of text-to-voice models
 */
suspend fun RunAnywhereSDK.getTextToVoiceModels(): List<ModelInfo> {
    return getModels(FrameworkModality.TEXT_TO_VOICE)
}

// =============================================================================
// MARK: - Model Discovery by Framework
// =============================================================================

/**
 * Get all models for a specific framework
 *
 * @param framework The LLMFramework to filter by
 * @return List of models for the framework
 */
suspend fun RunAnywhereSDK.getModels(framework: LLMFramework): List<ModelInfo> {
    discoveryLogger.debug("Getting models for framework: $framework")

    val models = ServiceContainer.shared.modelRegistry.filterModels(
        ModelCriteria(framework = framework)
    )

    discoveryLogger.info("Found ${models.size} models for framework $framework")
    return models
}

// =============================================================================
// MARK: - Model Discovery with Multiple Filters
// =============================================================================

/**
 * Get models matching multiple criteria.
 *
 * @param modality Optional modality filter
 * @param framework Optional framework filter
 * @param isDownloaded Optional filter for downloaded status
 * @return List of matching models
 */
suspend fun RunAnywhereSDK.getModels(
    modality: FrameworkModality? = null,
    framework: LLMFramework? = null,
    isDownloaded: Boolean? = null
): List<ModelInfo> {
    discoveryLogger.debug("Getting models with filters: modality=$modality, framework=$framework, isDownloaded=$isDownloaded")

    val category = modality?.let { ModelCategory.from(it) }
    val criteria = ModelCriteria(
        category = category,
        framework = framework,
        isDownloaded = isDownloaded
    )

    val models = ServiceContainer.shared.modelRegistry.filterModels(criteria)
    discoveryLogger.info("Found ${models.size} models matching criteria")
    return models
}

/**
 * Get downloaded models for a specific modality.
 *
 * @param modality The modality to filter by
 * @return List of downloaded models for the modality
 */
suspend fun RunAnywhereSDK.getDownloadedModels(modality: FrameworkModality): List<ModelInfo> {
    return getModels(modality = modality, isDownloaded = true)
}

/**
 * Get all downloaded models.
 *
 * @return List of all downloaded models
 */
suspend fun RunAnywhereSDK.getAllDownloadedModels(): List<ModelInfo> {
    return getModels(isDownloaded = true)
}

// =============================================================================
// MARK: - Model Discovery for Chat Screen
// =============================================================================

/**
 * Get the first available chat model (text-to-text) that is downloaded.
 * This is useful for automatically loading a model on the chat screen.
 *
 * @return The first downloaded text-to-text model, or null if none available
 */
suspend fun RunAnywhereSDK.getFirstAvailableChatModel(): ModelInfo? {
    discoveryLogger.debug("Getting first available chat model")

    val chatModels = getDownloadedModels(FrameworkModality.TEXT_TO_TEXT)
    val model = chatModels.firstOrNull()

    if (model != null) {
        discoveryLogger.info("Found available chat model: ${model.name} (${model.id})")
    } else {
        discoveryLogger.warn("No downloaded chat models available")
    }

    return model
}

/**
 * Get all available chat models (text-to-text), both downloaded and not downloaded.
 * Sorted with downloaded models first.
 *
 * @return List of chat models, downloaded first
 */
suspend fun RunAnywhereSDK.getAllChatModels(): List<ModelInfo> {
    val models = getModels(modality = FrameworkModality.TEXT_TO_TEXT)
    return models.sortedByDescending { it.localPath != null }
}

/**
 * Check if any chat model is available for use.
 *
 * @return True if at least one chat model is downloaded
 */
suspend fun RunAnywhereSDK.hasChatModelAvailable(): Boolean {
    return getFirstAvailableChatModel() != null
}

// =============================================================================
// MARK: - Smart Model Loading for Chat
// =============================================================================

/**
 * Load the appropriate model for a given modality.
 * Automatically selects the first available (downloaded) model.
 *
 * @param modality The lifecycle modality (LLM, STT, TTS)
 * @return True if a model was loaded successfully, false if no model available
 */
suspend fun RunAnywhereSDK.loadModelForModality(modality: Modality): Boolean {
    discoveryLogger.info("Loading model for modality: $modality")

    // Map lifecycle modality to framework modality
    val frameworkModality = when (modality) {
        Modality.LLM -> FrameworkModality.TEXT_TO_TEXT
        Modality.STT -> FrameworkModality.VOICE_TO_TEXT
        Modality.TTS -> FrameworkModality.TEXT_TO_VOICE
        Modality.VLM -> FrameworkModality.IMAGE_TO_TEXT
        else -> {
            discoveryLogger.warn("Unsupported modality: $modality")
            return false
        }
    }

    // Get downloaded models for this modality
    val downloadedModels = getDownloadedModels(frameworkModality)

    if (downloadedModels.isEmpty()) {
        discoveryLogger.warn("No downloaded models available for modality: $modality")
        return false
    }

    // Get the first available model
    val modelToLoad = downloadedModels.first()
    discoveryLogger.info("Selected model to load: ${modelToLoad.name} (${modelToLoad.id})")

    // Load the model based on modality
    return try {
        when (modality) {
            Modality.LLM, Modality.VLM -> loadModel(modelToLoad.id)
            Modality.STT -> {
                loadSTTModel(modelToLoad.id)
                true
            }

            Modality.TTS -> {
                loadTTSModel(modelToLoad.id)
                true
            }

            else -> false
        }
    } catch (e: Exception) {
        discoveryLogger.error("Failed to load model: ${e.message}", e)
        false
    }
}

/**
 * Load a chat model automatically.
 * Finds the first downloaded text-to-text model and loads it.
 *
 * @return True if a chat model was loaded successfully
 */
suspend fun RunAnywhereSDK.loadChatModelAutomatically(): Boolean {
    discoveryLogger.info("Auto-loading chat model...")

    // Check if LLM is already loaded
    if (ModelLifecycleTracker.isModelLoaded(Modality.LLM)) {
        val loadedModel = ModelLifecycleTracker.loadedModel(Modality.LLM)
        discoveryLogger.info("Chat model already loaded: ${loadedModel?.modelName}")
        return true
    }

    return loadModelForModality(Modality.LLM)
}

// =============================================================================
// MARK: - Model Summary
// =============================================================================

/**
 * Data class representing a summary of available models.
 */
data class ModelSummary(
    val totalModels: Int,
    val downloadedModels: Int,
    val byModality: Map<FrameworkModality, ModalityModelInfo>,
    val byFramework: Map<LLMFramework, Int>
)

/**
 * Data class for modality-specific model information.
 */
data class ModalityModelInfo(
    val total: Int,
    val downloaded: Int,
    val models: List<ModelInfo>
)

/**
 * Get a comprehensive summary of all models.
 *
 * @return ModelSummary with counts and details
 */
suspend fun RunAnywhereSDK.getModelSummary(): ModelSummary {
    val allModels = availableModels()

    val byModality = FrameworkModality.entries.associateWith { modality ->
        val modelsForModality = allModels.filter {
            it.category.frameworkModality == modality
        }
        ModalityModelInfo(
            total = modelsForModality.size,
            downloaded = modelsForModality.count { it.localPath != null },
            models = modelsForModality
        )
    }.filter { it.value.total > 0 }

    val byFramework = allModels
        .groupBy { it.preferredFramework }
        .filterKeys { it != null }
        .mapKeys { it.key!! }
        .mapValues { it.value.size }

    return ModelSummary(
        totalModels = allModels.size,
        downloadedModels = allModels.count { it.localPath != null },
        byModality = byModality,
        byFramework = byFramework
    )
}
