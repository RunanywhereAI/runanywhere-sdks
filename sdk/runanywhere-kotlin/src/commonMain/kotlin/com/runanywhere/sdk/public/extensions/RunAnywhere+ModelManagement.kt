/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for model management operations.
 * Calls C++ directly via CppBridge.ModelRegistry for all operations.
 *
 * Mirrors Swift RunAnywhere+ModelManagement.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ArchiveStructure
import com.runanywhere.sdk.public.extensions.Models.ArchiveType
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import com.runanywhere.sdk.public.extensions.Models.ModelArtifactType
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSource
import kotlinx.coroutines.flow.Flow

// MARK: - Model Registration

/**
 * Register a model from a download URL.
 * Use this to add models for development or offline use.
 *
 * Mirrors Swift RunAnywhere.registerModel() exactly.
 *
 * @param id Explicit model ID. If null, a stable ID is generated from the URL filename.
 * @param name Display name for the model
 * @param url Download URL for the model (e.g., HuggingFace)
 * @param framework Target inference framework
 * @param modality Model category (default: LANGUAGE for LLMs)
 * @param artifactType How the model is packaged (archive, single file, etc.). If null, inferred from URL.
 * @param memoryRequirement Estimated memory usage in bytes
 * @param supportsThinking Whether the model supports reasoning/thinking
 * @return The created ModelInfo
 */
fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.LANGUAGE,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): ModelInfo {
    val logger = SDKLogger.models

    // Generate model ID from URL filename if not provided
    val modelId = id ?: generateModelIdFromUrl(url)
    logger.debug("Registering model: $modelId (name: $name)")

    // Detect format from URL extension
    val format = detectFormatFromUrl(url)
    logger.debug("Detected format: ${format.value} for model: $modelId")

    // Infer artifact type if not provided
    val effectiveArtifactType = artifactType ?: inferArtifactType(url)
    logger.debug("Artifact type: ${effectiveArtifactType.displayName} for model: $modelId")

    // Create ModelInfo
    val modelInfo =
        ModelInfo(
            id = modelId,
            name = name,
            category = modality,
            format = format,
            downloadURL = url,
            localPath = null,
            artifactType = effectiveArtifactType,
            downloadSize = memoryRequirement,
            framework = framework,
            contextLength = if (modality.requiresContextLength) 2048 else null,
            supportsThinking = supportsThinking,
            supportsLora = supportsLora,
            description = "User-added model",
            source = com.runanywhere.sdk.public.extensions.Models.ModelSource.LOCAL,
        )

    // Save to registry (fire-and-forget)
    registerModelInternal(modelInfo)

    logger.info("Registered model: $modelId (category: ${modality.value}, framework: ${framework.rawValue})")
    return modelInfo
}

/**
 * Register a multi-file model (e.g., VLM with separate main model + mmproj files).
 * Files are downloaded separately and stored in the same model folder.
 *
 * Mirrors Swift RunAnywhere.registerMultiFileModel() exactly.
 *
 * @param id Model ID (required for multi-file models)
 * @param name Display name for the model
 * @param files Array of file descriptors specifying URL and filename for each file
 * @param framework Target inference framework
 * @param modality Model category (default: MULTIMODAL)
 * @param memoryRequirement Estimated memory usage in bytes
 * @return The created ModelInfo
 */
fun RunAnywhere.registerMultiFileModel(
    id: String,
    name: String,
    files: List<ModelFileDescriptor>,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MULTIMODAL,
    memoryRequirement: Long? = null,
): ModelInfo {
    val logger = SDKLogger.models
    require(files.isNotEmpty()) { "Multi-file model must have at least one file descriptor" }

    logger.debug("Registering multi-file model: $id (name: $name, files: ${files.size})")

    // Cache the file descriptors (C++ registry doesn't preserve them)
    cacheMultiFileDescriptors(id, files)

    // Create ModelInfo with multiFile artifact type
    val modelInfo =
        ModelInfo(
            id = id,
            name = name,
            category = modality,
            format = ModelFormat.GGUF, // Assume GGUF for VLM models (matches iOS)
            downloadURL = files.firstOrNull()?.url, // Use first file URL as primary (for display)
            localPath = null,
            artifactType = ModelArtifactType.MultiFile(files),
            downloadSize = memoryRequirement,
            framework = framework,
            contextLength = if (modality.requiresContextLength) 2048 else null,
            supportsThinking = false,
            description = "Multi-file model (${files.size} files)",
            source = ModelSource.LOCAL,
        )

    // Save to registry (fire-and-forget)
    registerModelInternal(modelInfo)

    logger.info("Registered multi-file model: $id (${files.size} files, framework: ${framework.rawValue})")
    return modelInfo
}

/**
 * Cache multi-file descriptors for later retrieval during download.
 * The C++ registry doesn't preserve the file descriptor array.
 * Implemented via expect/actual for platform-specific thread safety.
 */
internal expect fun cacheMultiFileDescriptors(modelId: String, files: List<ModelFileDescriptor>)

/**
 * Get cached file descriptors for a multi-file model.
 * Returns null if no cached descriptors exist for the given model ID.
 */
expect fun getMultiFileDescriptors(modelId: String): List<ModelFileDescriptor>?

/**
 * Internal implementation to save model to registry.
 * Implemented via expect/actual for platform-specific behavior.
 */
internal expect fun registerModelInternal(modelInfo: ModelInfo)

/**
 * Describes a companion file to download alongside the primary model file.
 * Mirrors iOS ModelFileDescriptor (url + filename variant) for multi-file models.
 */
data class ModelCompanionFile(
    val url: String,
    val filename: String,
)

/**
 * Register a multi-file model where multiple files must be downloaded together
 * into the same directory (e.g., model.onnx + vocab.txt for embedding models).
 *
 * Mirrors iOS RunAnywhere.registerMultiFileModel() exactly.
 *
 * @param id Explicit model ID
 * @param name Display name for the model
 * @param primaryUrl Download URL for the primary model file
 * @param companionFiles Additional files to download alongside the primary file
 * @param framework Target inference framework
 * @param modality Model category
 * @param memoryRequirement Estimated memory usage in bytes
 * @return The created ModelInfo
 */
fun RunAnywhere.registerMultiFileModel(
    id: String,
    name: String,
    primaryUrl: String,
    companionFiles: List<ModelCompanionFile>,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.LANGUAGE,
    memoryRequirement: Long? = null,
): ModelInfo {
    val modelInfo = registerModel(
        id = id,
        name = name,
        url = primaryUrl,
        framework = framework,
        modality = modality,
        memoryRequirement = memoryRequirement,
    )
    registerCompanionFilesInternal(id, companionFiles.map { it.url to it.filename })
    return modelInfo
}

/**
 * Internal implementation to store companion file URLs for a multi-file model.
 * Implemented via expect/actual for platform-specific behavior.
 */
internal expect fun registerCompanionFilesInternal(modelId: String, companionFiles: List<Pair<String, String>>)

// MARK: - Helper Functions

private fun generateModelIdFromUrl(url: String): String {
    var filename = url.substringAfterLast('/')
    val knownExtensions = listOf("gz", "bz2", "tar", "zip", "gguf", "onnx", "ort", "bin")
    while (true) {
        val ext = filename.substringAfterLast('.', "")
        if (ext.isNotEmpty() && knownExtensions.contains(ext.lowercase())) {
            filename = filename.dropLast(ext.length + 1)
        } else {
            break
        }
    }
    return filename
}

private fun detectFormatFromUrl(url: String): com.runanywhere.sdk.public.extensions.Models.ModelFormat {
    val ext = url.substringAfterLast('.').lowercase()
    return when (ext) {
        "onnx" -> com.runanywhere.sdk.public.extensions.Models.ModelFormat.ONNX
        "ort" -> com.runanywhere.sdk.public.extensions.Models.ModelFormat.ORT
        "gguf" -> com.runanywhere.sdk.public.extensions.Models.ModelFormat.GGUF
        "bin" -> com.runanywhere.sdk.public.extensions.Models.ModelFormat.BIN
        else -> com.runanywhere.sdk.public.extensions.Models.ModelFormat.UNKNOWN
    }
}

private fun inferArtifactType(url: String): ModelArtifactType {
    val lowercased = url.lowercase()
    return when {
        lowercased.endsWith(".tar.gz") || lowercased.endsWith(".tgz") ->
            ModelArtifactType.Archive(ArchiveType.TAR_GZ, ArchiveStructure.NESTED_DIRECTORY)
        lowercased.endsWith(".tar.bz2") || lowercased.endsWith(".tbz2") ->
            ModelArtifactType.Archive(ArchiveType.TAR_BZ2, ArchiveStructure.NESTED_DIRECTORY)
        lowercased.endsWith(".tar.xz") || lowercased.endsWith(".txz") ->
            ModelArtifactType.Archive(ArchiveType.TAR_XZ, ArchiveStructure.NESTED_DIRECTORY)
        lowercased.endsWith(".zip") ->
            ModelArtifactType.Archive(ArchiveType.ZIP, ArchiveStructure.NESTED_DIRECTORY)
        else -> ModelArtifactType.SingleFile()
    }
}

// MARK: - Model Discovery

/**
 * Get all available models (both downloaded and remote).
 *
 * @return List of all model info
 */
expect suspend fun RunAnywhere.availableModels(): List<ModelInfo>

/**
 * Get models by category.
 *
 * @param category Model category to filter by
 * @return List of models in the specified category
 */
expect suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

/**
 * Get downloaded models.
 *
 * @return List of downloaded model info
 */
expect suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>

/**
 * Get model info by ID.
 *
 * @param modelId Model identifier
 * @return Model info or null if not found
 */
expect suspend fun RunAnywhere.model(modelId: String): ModelInfo?

// MARK: - Model Downloads

/**
 * Download a model.
 *
 * @param modelId Model identifier to download
 * @return Flow of download progress
 */
expect fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress>

/**
 * Cancel a model download.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.cancelDownload(modelId: String)

/**
 * Check if a model is downloaded.
 *
 * @param modelId Model identifier
 * @return True if the model is downloaded
 */
expect suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean

// MARK: - Model Management

/**
 * Delete a downloaded model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.deleteModel(modelId: String)

/**
 * Delete all downloaded models.
 */
expect suspend fun RunAnywhere.deleteAllModels()

/**
 * Refresh the model registry from remote.
 */
expect suspend fun RunAnywhere.refreshModelRegistry()

// MARK: - Model Loading

/**
 * Load an LLM model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.loadLLMModel(modelId: String)

/**
 * Unload the currently loaded LLM model.
 */
expect suspend fun RunAnywhere.unloadLLMModel()

/**
 * Check if an LLM model is loaded.
 *
 * @return True if a model is loaded
 */
expect suspend fun RunAnywhere.isLLMModelLoaded(): Boolean

/**
 * Get the currently loaded LLM model ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded model,
 * or null if no model is loaded. Mirrors iOS RunAnywhere.getCurrentModelId().
 */
expect val RunAnywhere.currentLLMModelId: String?

/**
 * Get the currently loaded LLM model info.
 *
 * This is a convenience property that combines currentLLMModelId with
 * a lookup in the available models registry.
 *
 * @return The currently loaded ModelInfo, or null if no model is loaded
 */
expect suspend fun RunAnywhere.currentLLMModel(): ModelInfo?

/**
 * Get the currently loaded STT model info.
 *
 * @return The currently loaded STT ModelInfo, or null if no model is loaded
 */
expect suspend fun RunAnywhere.currentSTTModel(): ModelInfo?

/**
 * Load an STT model.
 *
 * @param modelId Model identifier
 */
expect suspend fun RunAnywhere.loadSTTModel(modelId: String)

// MARK: - Model Assignments

/**
 * Fetch model assignments for the current device from the backend.
 *
 * This method fetches models assigned to this device based on device type and platform.
 * Results are cached and saved to the model registry automatically.
 *
 * Note: Model assignments are automatically fetched during SDK initialization
 * when services are initialized (Phase 2). This method allows manual refresh.
 *
 * @param forceRefresh If true, bypass cache and fetch fresh data from backend
 * @return List of ModelInfo objects assigned to this device
 */
expect suspend fun RunAnywhere.fetchModelAssignments(forceRefresh: Boolean = false): List<ModelInfo>
