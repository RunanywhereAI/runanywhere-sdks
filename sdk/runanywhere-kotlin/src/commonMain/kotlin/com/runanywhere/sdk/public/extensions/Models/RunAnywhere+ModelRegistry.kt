/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for proto-backed model registry, discovery, and downloads.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+ModelRegistry.swift.
 */

package com.runanywhere.sdk.public.extensions

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
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import ai.runanywhere.proto.v1.ModelRegistryRefreshResult
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.MultiFileArtifact
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
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
    val format = formatFromUrl(url)
    val now = getCurrentTimeMillis()

    logger.debug("Registering model: $modelId (name: $name)")
    logger.debug("Detected format: ${format.catalogKey} for model: $modelId")

    val baseInfo =
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
            artifact_type = artifactType ?: ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED,
        )

    val modelInfo = applyInferredArtifact(baseInfo, url)
    val artifactTypeLabel = modelInfo.artifact_type?.displayName ?: "unspecified"
    logger.debug("Artifact type: $artifactTypeLabel for model: $modelId")

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

/**
 * Platform-backed URL → ModelFormat inference. Delegates to the commons
 * proto ABI (`rac_model_format_from_url_proto`) on JVM/Android; returns
 * `MODEL_FORMAT_UNKNOWN` when the native ABI is unavailable.
 */
internal expect fun formatFromUrl(url: String): ModelFormat

/**
 * Platform-backed URL → ModelArtifactType inference. Populates the
 * artifact-classification fields on [modelInfo] by delegating to the
 * commons proto ABI (`rac_artifact_infer_from_url_proto`). Returns
 * [modelInfo] unchanged when the native ABI is unavailable.
 */
internal expect fun applyInferredArtifact(modelInfo: ModelInfo, url: String): ModelInfo

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

// MARK: - Model Discovery

expect suspend fun RunAnywhere.availableModels(): List<ModelInfo>

expect suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

expect suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>

expect suspend fun RunAnywhere.model(modelId: String): ModelInfo?

expect suspend fun RunAnywhere.queryModels(query: ModelQuery = ModelQuery()): ModelInfoList

expect suspend fun RunAnywhere.downloadedModelsProto(): ModelInfoList

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

// MARK: - Model Import

/**
 * Import a stable, platform-normalized local model path into the generated
 * registry. Mirrors Swift `importModel(_ request: RAModelImportRequest)`.
 *
 * Adapters should first copy/link/authorize transient OS file picker handles
 * and provide a stable path visible to the C++ workflow. The request's
 * `source_path` must be a stable, normalized path under platform control.
 *
 * NOTE: The dedicated commons proto thunk `rac_model_registry_import_proto`
 * is not yet exposed via the Kotlin JNI bridge (`RunAnywhereBridge` has no
 * `racModelRegistryImportProto`). Until that thunk is wired, this entry
 * point falls back to the existing `registerModel` flow on
 * [CppBridgeModelRegistry] (`save`/`update`), which performs a registry
 * merge with the supplied [ModelImportRequest.model] payload.
 */
expect suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult
