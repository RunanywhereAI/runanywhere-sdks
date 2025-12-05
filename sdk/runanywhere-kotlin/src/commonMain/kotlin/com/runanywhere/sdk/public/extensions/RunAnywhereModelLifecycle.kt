package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.lifecycle.LoadedModelState
import com.runanywhere.sdk.models.lifecycle.Modality
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleEvent
import com.runanywhere.sdk.models.lifecycle.ModelLifecycleTracker
import com.runanywhere.sdk.models.lifecycle.ModelLoadState
import com.runanywhere.sdk.public.RunAnywhereSDK
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

private val logger = SDKLogger("ModelLifecycle")

/**
 * RunAnywhere Model Lifecycle Extensions
 *
 * Provides public API for model lifecycle management across all modalities.
 * Matches iOS RunAnywhere+ModelLifecycle.swift
 */

// MARK: - Model Lifecycle State Access

/**
 * Get the lifecycle tracker for observing model state changes
 */
val RunAnywhereSDK.modelLifecycle: ModelLifecycleTracker
    get() = ModelLifecycleTracker

/**
 * StateFlow of all models by modality for reactive UI binding
 */
val RunAnywhereSDK.modelsByModality: StateFlow<Map<Modality, LoadedModelState>>
    get() = ModelLifecycleTracker.modelsByModality

/**
 * SharedFlow of lifecycle events for reactive subscriptions
 */
val RunAnywhereSDK.modelLifecycleEvents: SharedFlow<ModelLifecycleEvent>
    get() = ModelLifecycleTracker.lifecycleEvents

// MARK: - Query API

/**
 * Get currently loaded model for a specific modality
 * @param modality The modality to check (LLM, STT, TTS, VLM)
 * @return The loaded model state, or null if no model is loaded
 */
fun RunAnywhereSDK.loadedModel(modality: Modality): LoadedModelState? {
    return ModelLifecycleTracker.loadedModel(modality)
}

/**
 * Check if a model is loaded for a specific modality
 * @param modality The modality to check
 * @return True if a model is currently loaded
 */
fun RunAnywhereSDK.isModelLoaded(modality: Modality): Boolean {
    return ModelLifecycleTracker.isModelLoaded(modality)
}

/**
 * Get all currently loaded models across all modalities
 * @return List of all loaded model states
 */
fun RunAnywhereSDK.allLoadedModels(): List<LoadedModelState> {
    return ModelLifecycleTracker.allLoadedModels()
}

/**
 * Get the current load state for a modality
 * @param modality The modality to check
 * @return Current ModelLoadState (NotLoaded, Loading, Loaded, etc.)
 */
fun RunAnywhereSDK.getModelLoadState(modality: Modality): ModelLoadState {
    return ModelLifecycleTracker.getState(modality)
}

// MARK: - Load/Unload with Lifecycle Tracking

/**
 * Load a model with full lifecycle tracking
 * This wraps the standard loadModel call with lifecycle notifications
 *
 * @param modelId The model identifier
 * @param modality The modality for this model (defaults to LLM)
 * @throws SDKError if loading fails
 */
suspend fun RunAnywhereSDK.loadModelWithTracking(modelId: String, modality: Modality = Modality.LLM) {
    // Get model info from registry
    val modelInfo = com.runanywhere.sdk.foundation.ServiceContainer.shared.modelRegistry.getModel(modelId)
    if (modelInfo == null) {
        throw IllegalArgumentException("Model not found: $modelId")
    }

    val framework = modelInfo.preferredFramework ?: LLMFramework.LLAMA_CPP

    // Notify will load
    ModelLifecycleTracker.modelWillLoad(
        modelId = modelId,
        modelName = modelInfo.name,
        framework = framework,
        modality = modality
    )

    try {
        // Load based on modality
        when (modality) {
            Modality.LLM -> loadModel(modelId)
            Modality.STT -> loadSTTModel(modelId)
            Modality.TTS -> loadTTSModel(modelId)
            Modality.VLM -> loadModel(modelId) // VLM uses same path as LLM for now
            else -> { /* Speaker diarization, wake word handled by components */ }
        }

        // Mark as loaded
        ModelLifecycleTracker.modelDidLoad(
            modelId = modelId,
            modelName = modelInfo.name,
            framework = framework,
            modality = modality,
            memoryUsage = modelInfo.memoryRequired
        )

    } catch (e: Exception) {
        ModelLifecycleTracker.modelLoadFailed(
            modelId = modelId,
            modality = modality,
            error = e.message ?: "Unknown error"
        )
        throw e
    }
}

/**
 * Unload a model for a specific modality with lifecycle tracking
 * @param modality The modality to unload
 */
suspend fun RunAnywhereSDK.unloadModelForModality(modality: Modality) {
    val state = ModelLifecycleTracker.loadedModel(modality) ?: return

    ModelLifecycleTracker.modelWillUnload(state.modelId, modality)

    try {
        // Perform unload based on modality
        when (modality) {
            Modality.LLM, Modality.VLM -> {
                com.runanywhere.sdk.foundation.ServiceContainer.shared
                    .modelLoadingService.unloadModel(state.modelId)
            }
            else -> {
                // STT, TTS, and other components handle their own cleanup
            }
        }
    } catch (e: Exception) {
        // Log but continue with lifecycle update
        logger.warning("Error during model unload for modality $modality: ${e.message}")
    }

    ModelLifecycleTracker.modelDidUnload(state.modelId, modality)
}

// MARK: - Convenience Extensions

/**
 * Check if LLM model is loaded
 */
val RunAnywhereSDK.isLLMModelLoaded: Boolean
    get() = ModelLifecycleTracker.isModelLoaded(Modality.LLM)

/**
 * Check if STT model is loaded
 */
val RunAnywhereSDK.isSTTModelLoaded: Boolean
    get() = ModelLifecycleTracker.isModelLoaded(Modality.STT)

/**
 * Check if TTS model is loaded
 */
val RunAnywhereSDK.isTTSModelLoaded: Boolean
    get() = ModelLifecycleTracker.isModelLoaded(Modality.TTS)

/**
 * Get currently loaded LLM model info
 */
val RunAnywhereSDK.loadedLLMModel: LoadedModelState?
    get() = ModelLifecycleTracker.loadedModel(Modality.LLM)

/**
 * Get currently loaded STT model info
 */
val RunAnywhereSDK.loadedSTTModel: LoadedModelState?
    get() = ModelLifecycleTracker.loadedModel(Modality.STT)

/**
 * Get currently loaded TTS model info
 */
val RunAnywhereSDK.loadedTTSModel: LoadedModelState?
    get() = ModelLifecycleTracker.loadedModel(Modality.TTS)

/**
 * Check if all voice models (STT, LLM, TTS) are loaded for voice assistant
 */
val RunAnywhereSDK.allVoiceModelsLoaded: Boolean
    get() = isSTTModelLoaded && isLLMModelLoaded && isTTSModelLoaded
