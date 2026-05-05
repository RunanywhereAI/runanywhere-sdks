/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for model management operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ArchiveArtifact
import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.DownloadCancelRequest
import ai.runanywhere.proto.v1.DownloadCancelResult
import ai.runanywhere.proto.v1.DownloadPlanRequest
import ai.runanywhere.proto.v1.DownloadPlanResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadResumeRequest
import ai.runanywhere.proto.v1.DownloadResumeResult
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadStartResult
import ai.runanywhere.proto.v1.DownloadSubscribeRequest
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import ai.runanywhere.proto.v1.ModelRegistryRefreshResult
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.MultiFileArtifact
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.SingleFileArtifact
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.archiveTypeFromPath
import com.runanywhere.sdk.public.extensions.Models.catalogKey
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.extensions.Models.rawValue
import com.runanywhere.sdk.public.extensions.Models.requiresContextLength
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow

// MARK: - Model Registration

fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): ModelInfo {
    val logger = SDKLogger.models
    val modelId = id ?: generateModelIdFromUrl(url)
    val format = detectFormatFromUrl(url)
    val artifact = inferArtifactFields(url, artifactType)
    val now = getCurrentTimeMillis()

    logger.debug("Registering model: $modelId (name: $name)")
    logger.debug("Detected format: ${format.catalogKey} for model: $modelId")
    logger.debug("Artifact type: ${artifact.artifactType.displayName} for model: $modelId")

    val modelInfo =
        ModelInfo(
            id = modelId,
            name = name,
            category = modality,
            format = format,
            framework = framework,
            download_url = url,
            download_size_bytes = memoryRequirement ?: 0L,
            memory_required_bytes = memoryRequirement,
            context_length = if (modality.requiresContextLength) 2048 else 0,
            supports_thinking = supportsThinking,
            supports_lora = supportsLora,
            description = "User-added model",
            source = ModelSource.MODEL_SOURCE_LOCAL,
            created_at_unix_ms = now,
            updated_at_unix_ms = now,
            single_file = artifact.singleFile,
            archive = artifact.archive,
            multi_file = artifact.multiFile,
            custom_strategy_id = artifact.customStrategyId,
            built_in = artifact.builtIn,
            artifact_type = artifact.artifactType,
        )

    registerModelInternal(modelInfo)

    logger.info("Registered model: $modelId (category: ${modality.catalogKey}, framework: ${framework.rawValue})")
    return modelInfo
}

fun RunAnywhere.registerMultiFileModel(
    id: String,
    name: String,
    files: List<ModelFileDescriptor>,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    memoryRequirement: Long? = null,
): ModelInfo {
    val logger = SDKLogger.models
    require(files.isNotEmpty()) { "Multi-file model must have at least one file descriptor" }

    logger.debug("Registering multi-file model: $id (name: $name, files: ${files.size})")

    val now = getCurrentTimeMillis()
    val modelInfo =
        ModelInfo(
            id = id,
            name = name,
            category = modality,
            format = ModelFormat.MODEL_FORMAT_GGUF,
            framework = framework,
            download_url = files.firstOrNull()?.url.orEmpty(),
            download_size_bytes = memoryRequirement ?: 0L,
            memory_required_bytes = memoryRequirement,
            context_length = if (modality.requiresContextLength) 2048 else 0,
            description = "Multi-file model (${files.size} files)",
            source = ModelSource.MODEL_SOURCE_LOCAL,
            created_at_unix_ms = now,
            updated_at_unix_ms = now,
            multi_file = MultiFileArtifact(files = files),
            artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
        )

    registerModelInternal(modelInfo)

    logger.info("Registered multi-file model: $id (${files.size} files, framework: ${framework.rawValue})")
    return modelInfo
}

internal expect fun registerModelInternal(modelInfo: ModelInfo)

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

private fun detectFormatFromUrl(url: String): ModelFormat {
    val ext = url.substringAfterLast('.').lowercase()
    return when (ext) {
        "onnx" -> ModelFormat.MODEL_FORMAT_ONNX
        "ort" -> ModelFormat.MODEL_FORMAT_ORT
        "gguf" -> ModelFormat.MODEL_FORMAT_GGUF
        "bin" -> ModelFormat.MODEL_FORMAT_BIN
        else -> ModelFormat.MODEL_FORMAT_UNKNOWN
    }
}

private data class ModelArtifactFields(
    val singleFile: SingleFileArtifact? = null,
    val archive: ArchiveArtifact? = null,
    val multiFile: MultiFileArtifact? = null,
    val customStrategyId: String? = null,
    val builtIn: Boolean? = null,
    val artifactType: ModelArtifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
)

private fun inferArtifactFields(url: String, requestedType: ModelArtifactType?): ModelArtifactFields {
    val archiveType = archiveTypeFromPath(url)
    if (archiveType != null) {
        return ModelArtifactFields(
            archive =
                ArchiveArtifact(
                    type = archiveType,
                    structure = ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
                ),
            artifactType = requestedType ?: archiveType.toArtifactType(),
        )
    }

    return ModelArtifactFields(
        singleFile = SingleFileArtifact(),
        artifactType = requestedType ?: ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
    )
}

private fun ArchiveType.toArtifactType(): ModelArtifactType =
    when (this) {
        ArchiveType.ARCHIVE_TYPE_ZIP -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_GZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_XZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE
    }

// MARK: - Model Discovery

expect suspend fun RunAnywhere.availableModels(): List<ModelInfo>

expect suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

expect suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>

expect suspend fun RunAnywhere.model(modelId: String): ModelInfo?

expect suspend fun RunAnywhere.queryModels(query: ModelQuery = ModelQuery()): ModelInfoList

expect suspend fun RunAnywhere.downloadedModelsProto(): ModelInfoList

expect suspend fun RunAnywhere.loadModel(request: ModelLoadRequest): ModelLoadResult

expect suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult

expect suspend fun RunAnywhere.currentModel(request: CurrentModelRequest = CurrentModelRequest()): CurrentModelResult

expect suspend fun RunAnywhere.componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot

// MARK: - Model Downloads

expect fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress>

expect suspend fun RunAnywhere.planDownload(request: DownloadPlanRequest): DownloadPlanResult

expect fun RunAnywhere.startDownload(request: DownloadStartRequest): Flow<DownloadProgress>

expect suspend fun RunAnywhere.startDownloadProto(request: DownloadStartRequest): DownloadStartResult

expect suspend fun RunAnywhere.cancelDownload(request: DownloadCancelRequest): DownloadCancelResult

expect suspend fun RunAnywhere.resumeDownload(request: DownloadResumeRequest): DownloadResumeResult

expect suspend fun RunAnywhere.downloadProgress(request: DownloadSubscribeRequest): DownloadProgress?

expect suspend fun RunAnywhere.cancelDownload(modelId: String)

expect suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean

// MARK: - Model Management

expect suspend fun RunAnywhere.deleteModel(modelId: String)

expect suspend fun RunAnywhere.deleteAllModels()

expect suspend fun RunAnywhere.refreshModelRegistry(
    includeRemoteCatalog: Boolean = true,
    rescanLocal: Boolean = true,
    pruneOrphans: Boolean = false,
): ModelRegistryRefreshResult

expect suspend fun RunAnywhere.refreshModelRegistry(
    request: ModelRegistryRefreshRequest,
): ModelRegistryRefreshResult

// MARK: - Model Loading

expect suspend fun RunAnywhere.loadModel(modelId: String)

expect suspend fun RunAnywhere.loadLLMModel(modelId: String)

expect suspend fun RunAnywhere.unloadLLMModel()

expect val RunAnywhere.isLLMModelLoaded: Boolean

expect val RunAnywhere.currentLLMModel: ModelInfo?

expect suspend fun RunAnywhere.currentSTTModel(): ModelInfo?

expect suspend fun RunAnywhere.loadSTTModel(modelId: String)

// MARK: - Model Assignments
// `fetchModelAssignments` was deleted in the dead-code wave (KOT-DEAD).
// The legacy path was a JSON adapter over `racModelAssignmentFetch`.
// Use `refreshModelRegistry(includeRemoteCatalog = true)` followed by
// `availableModels()` to drive the proto-backed catalog refresh instead.
