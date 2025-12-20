package com.runanywhere.sdk.core.frameworks

import com.runanywhere.sdk.features.llm.HardwareConfiguration
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Unified protocol for all framework adapters (LLM, Voice, Image, etc.)
 *
 * This is the Kotlin equivalent of iOS UnifiedFrameworkAdapter protocol.
 * Framework adapters implement this interface to provide a unified way to:
 * - Register service providers with ModuleRegistry
 * - Handle model loading and service creation
 * - Estimate memory usage and configure hardware
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Frameworks/UnifiedFrameworkAdapter.swift
 */
interface UnifiedFrameworkAdapter {
    /**
     * The framework this adapter handles
     */
    val framework: InferenceFramework

    /**
     * The modalities this adapter supports
     */
    val supportedModalities: Set<FrameworkModality>

    /**
     * Supported model formats
     */
    val supportedFormats: List<ModelFormat>

    /**
     * Check if this adapter can handle a specific model
     * @param model The model information
     * @return Whether this adapter can handle the model
     */
    fun canHandle(model: ModelInfo): Boolean

    /**
     * Create a service instance based on the modality
     * @param modality The modality to create a service for
     * @return A service instance (LLMService, STTService, TTSService, etc.)
     */
    fun createService(modality: FrameworkModality): Any?

    /**
     * Load a model using this adapter
     * @param model The model to load
     * @param modality The modality to use
     * @return A service instance with the loaded model
     */
    suspend fun loadModel(
        model: ModelInfo,
        modality: FrameworkModality,
    ): Any

    /**
     * Configure the adapter with hardware settings
     * @param hardware Hardware configuration
     */
    suspend fun configure(hardware: HardwareConfiguration)

    /**
     * Estimate memory usage for a model
     * @param model The model to estimate
     * @return Estimated memory in bytes
     */
    fun estimateMemoryUsage(model: ModelInfo): Long

    /**
     * Get optimal hardware configuration for a model
     * @param model The model to configure for
     * @return Optimal hardware configuration
     */
    fun optimalConfiguration(model: ModelInfo): HardwareConfiguration

    /**
     * Called when the adapter is registered with the SDK.
     * Adapters should register their service providers with ModuleRegistry here.
     */
    fun onRegistration()

    /**
     * Get models provided by this adapter
     * @return List of models this adapter provides
     */
    fun getProvidedModels(): List<ModelInfo>

    /**
     * Get download strategy provided by this adapter (if any)
     * @return Download strategy or null if none
     */
    fun getDownloadStrategy(): DownloadStrategy?

    /**
     * Get model storage strategy provided by this adapter (if any)
     * Used for detecting downloaded models on disk
     * @return Storage strategy or null if none
     */
    fun getModelStorageStrategy(): ModelStorageStrategy? = null

    /**
     * Initialize adapter with component parameters
     * @param parameters Component initialization parameters
     * @param modality The modality to initialize for
     * @return Initialized service ready for use
     */
    suspend fun initializeComponent(
        parameters: ComponentInitParameters,
        modality: FrameworkModality,
    ): Any?
}

/**
 * Interface for component initialization parameters
 * Matches iOS ComponentInitParameters protocol
 */
interface ComponentInitParameters {
    val modelId: String?
}

/**
 * Interface for download strategies
 * Matches iOS DownloadStrategy protocol
 */
interface DownloadStrategy {
    /**
     * Check if this strategy can handle the model
     */
    fun canHandle(model: ModelInfo): Boolean

    /**
     * Download the model to the destination folder
     * @param model The model to download
     * @param destinationFolder The folder to download to
     * @param progressHandler Progress callback (0.0 to 1.0)
     * @return The path to the downloaded model
     */
    suspend fun download(
        model: ModelInfo,
        destinationFolder: String,
        progressHandler: ((Double) -> Unit)?,
    ): String
}

/**
 * Interface for model storage strategies
 * Matches iOS ModelStorageStrategy protocol
 */
interface ModelStorageStrategy {
    /**
     * Find model path for a given model ID in the folder
     */
    fun findModelPath(
        modelId: String,
        modelFolder: String,
    ): String?

    /**
     * Detect model format and size in the folder
     * @return Pair of (format, size in bytes) or null if not found
     */
    fun detectModel(modelFolder: String): Pair<ModelFormat, Long>?

    /**
     * Check if the folder contains valid model storage
     */
    fun isValidModelStorage(modelFolder: String): Boolean
}
