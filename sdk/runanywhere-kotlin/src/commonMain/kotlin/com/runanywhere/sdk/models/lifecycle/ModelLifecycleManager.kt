package com.runanywhere.sdk.models.lifecycle

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.Serializable

// =============================================================================
// DEPRECATION NOTICE
// =============================================================================
// This file contains legacy lifecycle management code that is NOT aligned with iOS.
//
// For iOS-aligned lifecycle management, use:
//   - com.runanywhere.sdk.core.capabilities.ModelLifecycleManager<ServiceType>
//   - com.runanywhere.sdk.core.capabilities.ManagedLifecycle<ServiceType>
//   - com.runanywhere.sdk.core.capabilities.CapabilityLoadingState
//
// This file will be removed in a future version.
// =============================================================================

// MARK: - Model Load State

/**
 * Represents the current state of a model
 * Matches iOS ModelLoadState enum
 *
 * @deprecated Use [com.runanywhere.sdk.core.capabilities.CapabilityLoadingState] instead
 * for iOS-aligned lifecycle state tracking.
 */
@Deprecated(
    message = "Use CapabilityLoadingState from core.capabilities package instead",
    replaceWith = ReplaceWith("CapabilityLoadingState", "com.runanywhere.sdk.core.capabilities.CapabilityLoadingState"),
)
@Serializable
sealed class ModelLoadState {
    @Serializable
    data object NotLoaded : ModelLoadState()

    @Serializable
    data class Loading(
        val progress: Double = 0.0,
    ) : ModelLoadState()

    @Serializable
    data object Loaded : ModelLoadState()

    @Serializable
    data object Unloading : ModelLoadState()

    @Serializable
    data class Error(
        val message: String,
    ) : ModelLoadState()

    val isLoaded: Boolean
        get() = this is Loaded

    val isLoading: Boolean
        get() = this is Loading

    val isError: Boolean
        get() = this is Error
}

// MARK: - Modality

/**
 * Supported modalities for model lifecycle tracking
 * Matches iOS Modality enum
 */
@Serializable
enum class Modality(
    val value: String,
    val displayName: String,
) {
    LLM("llm", "Language Model"),
    STT("stt", "Speech Recognition"),
    TTS("tts", "Text to Speech"),
    VLM("vlm", "Vision Model"),
    SPEAKER_DIARIZATION("speaker_diarization", "Speaker Diarization"),
    WAKE_WORD("wake_word", "Wake Word"),
    ;

    companion object {
        fun fromValue(value: String): Modality? = entries.find { it.value == value }
    }
}

// MARK: - Loaded Model State

/**
 * Information about a currently loaded model
 * Matches iOS LoadedModelState struct
 */
@Serializable
data class LoadedModelState(
    val modelId: String,
    val modelName: String,
    val framework: InferenceFramework,
    val modality: Modality,
    val state: ModelLoadState,
    val loadedAt: Long? = null, // Epoch milliseconds
    val memoryUsage: Long? = null, // Bytes
) {
    /**
     * Create a copy with updated state
     */
    fun withState(newState: ModelLoadState): LoadedModelState = copy(state = newState)

    /**
     * Create a copy marked as loaded with timestamp
     */
    fun asLoaded(memoryUsage: Long? = null): LoadedModelState =
        copy(
            state = ModelLoadState.Loaded,
            loadedAt = currentTimeMillis(),
            memoryUsage = memoryUsage,
        )
}

// MARK: - Model Lifecycle Events

/**
 * Events published when model lifecycle changes
 * Matches iOS ModelLifecycleEvent enum
 *
 * @deprecated Use LLMEvent, STTEvent, TTSEvent, VADEvent from features package instead.
 * These provide iOS-aligned event tracking with EventPublisher integration.
 */
@Deprecated(
    message = "Use capability-specific events (LLMEvent, STTEvent, etc.) from features package instead",
)
sealed class ModelLifecycleEvent {
    data class WillLoad(
        val modelId: String,
        val modality: Modality,
    ) : ModelLifecycleEvent()

    data class LoadProgress(
        val modelId: String,
        val modality: Modality,
        val progress: Double,
    ) : ModelLifecycleEvent()

    data class DidLoad(
        val modelId: String,
        val modality: Modality,
        val framework: InferenceFramework,
    ) : ModelLifecycleEvent()

    data class WillUnload(
        val modelId: String,
        val modality: Modality,
    ) : ModelLifecycleEvent()

    data class DidUnload(
        val modelId: String,
        val modality: Modality,
    ) : ModelLifecycleEvent()

    data class LoadFailed(
        val modelId: String,
        val modality: Modality,
        val error: String,
    ) : ModelLifecycleEvent()
}

// MARK: - Model Lifecycle Tracker

/**
 * Centralized tracker for model lifecycle across all modalities
 * Thread-safe singleton with StateFlow-based reactive updates
 *
 * Matches iOS ModelLifecycleTracker
 *
 * @deprecated Use [com.runanywhere.sdk.core.capabilities.ManagedLifecycle] instead.
 * ManagedLifecycle provides per-service lifecycle management with integrated
 * event tracking via EventPublisher, matching iOS architecture.
 */
@Deprecated(
    message = "Use ManagedLifecycle from core.capabilities package instead",
    replaceWith = ReplaceWith("ManagedLifecycle", "com.runanywhere.sdk.core.capabilities.ManagedLifecycle"),
)
object ModelLifecycleTracker {
    private val logger = SDKLogger("ModelLifecycleTracker")

    // Current state of all models, keyed by modality
    private val _modelsByModality = MutableStateFlow<Map<Modality, LoadedModelState>>(emptyMap())
    val modelsByModality: StateFlow<Map<Modality, LoadedModelState>> = _modelsByModality.asStateFlow()

    // Event stream for lifecycle changes
    private val _lifecycleEvents = MutableSharedFlow<ModelLifecycleEvent>(extraBufferCapacity = 64)
    val lifecycleEvents: SharedFlow<ModelLifecycleEvent> = _lifecycleEvents.asSharedFlow()

    // MARK: - Query API

    /**
     * Get currently loaded model for a specific modality
     */
    fun loadedModel(modality: Modality): LoadedModelState? = _modelsByModality.value[modality]

    /**
     * Check if a model is loaded for a specific modality
     */
    fun isModelLoaded(modality: Modality): Boolean = _modelsByModality.value[modality]?.state?.isLoaded == true

    /**
     * Get all currently loaded models
     */
    fun allLoadedModels(): List<LoadedModelState> = _modelsByModality.value.values.filter { it.state.isLoaded }

    /**
     * Check if a specific model is loaded (by ID)
     */
    fun isModelLoaded(modelId: String): Boolean = _modelsByModality.value.values.any { it.modelId == modelId && it.state.isLoaded }

    /**
     * Get the current state for a modality
     */
    fun getState(modality: Modality): ModelLoadState = _modelsByModality.value[modality]?.state ?: ModelLoadState.NotLoaded

    // MARK: - State Management

    /**
     * Called when a model starts loading
     */
    fun modelWillLoad(
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        modality: Modality,
    ) {
        logger.info("Model will load: $modelName [$modality]")

        val state =
            LoadedModelState(
                modelId = modelId,
                modelName = modelName,
                framework = framework,
                modality = modality,
                state = ModelLoadState.Loading(0.0),
            )

        _modelsByModality.update { current ->
            current + (modality to state)
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.WillLoad(modelId, modality))
    }

    /**
     * Update loading progress
     */
    fun updateLoadProgress(
        modelId: String,
        modality: Modality,
        progress: Double,
    ) {
        val current = _modelsByModality.value[modality] ?: return
        if (current.modelId != modelId) return

        _modelsByModality.update { map ->
            map + (modality to current.withState(ModelLoadState.Loading(progress)))
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.LoadProgress(modelId, modality, progress))
    }

    /**
     * Called when a model finishes loading successfully
     */
    fun modelDidLoad(
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        modality: Modality,
        memoryUsage: Long? = null,
    ) {
        logger.info("Model loaded: $modelName [$modality] with ${framework.displayName}")

        val state =
            LoadedModelState(
                modelId = modelId,
                modelName = modelName,
                framework = framework,
                modality = modality,
                state = ModelLoadState.Loaded,
                loadedAt = currentTimeMillis(),
                memoryUsage = memoryUsage,
            )

        _modelsByModality.update { current ->
            current + (modality to state)
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.DidLoad(modelId, modality, framework))
    }

    /**
     * Called when a model fails to load
     */
    fun modelLoadFailed(
        modelId: String,
        modality: Modality,
        error: String,
    ) {
        logger.error("Model load failed: $modelId [$modality] - $error")

        val current = _modelsByModality.value[modality]
        if (current != null) {
            _modelsByModality.update { map ->
                map + (modality to current.withState(ModelLoadState.Error(error)))
            }
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.LoadFailed(modelId, modality, error))
    }

    /**
     * Called when a model starts unloading
     */
    fun modelWillUnload(
        modelId: String,
        modality: Modality,
    ) {
        logger.info("Model will unload: $modelId [$modality]")

        val current = _modelsByModality.value[modality]
        if (current != null && current.modelId == modelId) {
            _modelsByModality.update { map ->
                map + (modality to current.withState(ModelLoadState.Unloading))
            }
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.WillUnload(modelId, modality))
    }

    /**
     * Called when a model finishes unloading
     */
    fun modelDidUnload(
        modelId: String,
        modality: Modality,
    ) {
        logger.info("Model unloaded: $modelId [$modality]")

        _modelsByModality.update { current ->
            current - modality
        }

        _lifecycleEvents.tryEmit(ModelLifecycleEvent.DidUnload(modelId, modality))
    }

    /**
     * Clear all loaded models (for cleanup)
     */
    fun clearAll() {
        logger.info("Clearing all loaded models")
        _modelsByModality.value = emptyMap()
    }
}
