/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for storage operations.
 *
 * Mirrors Swift `RunAnywhere+Storage.swift` exactly:
 *   - `registerModel(...)` URL / archive / multi-file overloads (Swift parity)
 *   - `importModel(request)` local-import entry point
 *   - `getStorageInfo(request)` (replaces the legacy `storageInfo()` accessor)
 *   - `deleteStorage(request)` executing or dry-running deletion
 *   - `clearCache()` / `cleanTempFiles()` forwarding to the FileManager bridge
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ArchiveArtifact
import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import ai.runanywhere.proto.v1.RegisterMultiFileModelRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.archiveArtifact
import com.runanywhere.sdk.public.extensions.Models.setArchiveArtifact
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - Model Registration

// MARK: - Model Import

// MARK: - Storage Information

// MARK: - Storage Deletion

// MARK: - Cache and Temp

private fun requireStorageInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

// MARK: - Model Registration

suspend fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): RAModelInfo {
    requireStorageInitialized(this)

    // Canonical commons factory: rac_register_model_from_url_proto derives
    // id/name/format/artifact, resolves hf.co/org/repo[:quant] refs (quant
    // selection, mmproj pairing, sharded GGUF sets, checksums), and preserves
    // prior download state when a catalog re-seeds on launch.
    val request =
        RegisterModelFromUrlRequest(
            url = url,
            name = name,
            framework = framework,
            category = modality,
            source = ModelSource.MODEL_SOURCE_REMOTE,
            id = id,
            memory_required_bytes = memoryRequirement,
            // Mirror Swift `RunAnywhere+Storage.swift`: a caller-supplied size is
            // both the memory estimate and the download size. Without
            // download_size_bytes the download planner can't verify free storage
            // and fails when the server (e.g. an HF redirect) omits Content-Length.
            download_size_bytes = memoryRequirement,
            supports_thinking = if (supportsThinking) true else null,
            supports_lora = if (supportsLora) true else null,
            artifact_type = artifactType,
        )

    val saved =
        CppBridgeModelRegistry.registerModelFromUrl(request)
            ?: throw SDKException.storage(
                "Native registry proto ABI unavailable for registerModelFromUrl",
            )
    return saved
}

suspend fun RunAnywhere.registerModel(
    archiveUrl: String,
    structure: ArchiveStructure,
    id: String? = null,
    name: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    archiveType: ArchiveType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): RAModelInfo {
    val resolvedArtifactType: ModelArtifactType? =
        archiveType?.let { type ->
            when (type) {
                ArchiveType.ARCHIVE_TYPE_ZIP -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
                ArchiveType.ARCHIVE_TYPE_TAR_GZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
                ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE
                ArchiveType.ARCHIVE_TYPE_TAR_XZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE
                ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE
            }
        }

    var model =
        registerModel(
            id = id,
            name = name,
            url = archiveUrl,
            framework = framework,
            modality = modality,
            artifactType = resolvedArtifactType,
            memoryRequirement = memoryRequirement,
            supportsThinking = supportsThinking,
            supportsLora = supportsLora,
        )

    // Preserve the structure on the archive artifact. The URL-form inferred
    // artifact only captures the archive type, not the nested/directory
    // layout, so patch it here and re-persist through the registry's proto
    // save path (mirroring Swift's archive overload). When the URL suffix
    // doesn't reveal an archive (query strings, presigned CDN URLs), the
    // URL-form registration produced a single_file artifact; Swift still
    // persists an archive artifact carrying the caller's type and structure,
    // so build one here instead of dropping the caller's intent.
    val archive =
        model.archiveArtifact
            ?: ArchiveArtifact(type = archiveType ?: ArchiveType.ARCHIVE_TYPE_UNSPECIFIED)
    model =
        model
            .setArchiveArtifact(archive.copy(structure = structure))
            .copy(updated_at_unix_ms = getCurrentTimeMillis())
    CppBridgeModelRegistry.save(model)
    return model
}

suspend fun RunAnywhere.registerModel(
    multiFile: List<ModelFileDescriptor>,
    id: String,
    name: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement: Long? = null,
    contextLength: Int? = null,
    supportsThinking: Boolean = false,
    source: ModelSource = ModelSource.MODEL_SOURCE_REMOTE,
): RAModelInfo {
    requireStorageInitialized(this)

    // Canonical commons factory: rac_register_multi_file_model_proto builds
    // the MultiFileArtifact ModelInfo (descriptors carry url/filename/
    // size/checksum/role) and persists it with merge-on-reseed semantics.
    val request =
        RegisterMultiFileModelRequest(
            id = id,
            name = name,
            framework = framework,
            category = modality,
            memory_required_bytes = memoryRequirement,
            // Swift parity: curated catalogs use this value as the exact
            // aggregate download size. Commons can then keep the storage gate
            // deterministic even if a legacy per-file descriptor lacks a size
            // and the remote HEAD response omits Content-Length.
            download_size_bytes = memoryRequirement,
            context_length = contextLength,
            supports_thinking = if (supportsThinking) true else null,
            source = source,
            files = multiFile,
        )

    val saved =
        CppBridgeModelRegistry.registerMultiFileModel(request)
            ?: throw SDKException.storage(
                "Native registry proto ABI unavailable for registerMultiFileModel",
            )
    return saved
}

// MARK: - Model Import

suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult {
    requireStorageInitialized(this)
    ensureServicesReady()
    return CppBridgeModelRegistry.importModel(request)
}

// MARK: - Storage Information

suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest = StorageInfoRequest()): StorageInfoResult {
    requireStorageInitialized(this)
    ensureServicesReady()
    return CppBridgeStorage.info(request)
        ?: throw SDKException.storage("Native storage info proto API unavailable")
}

suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult {
    requireStorageInitialized(this)
    ensureServicesReady()
    return CppBridgeStorage.delete(request)
        ?: throw SDKException.storage("Native storage delete proto API unavailable")
}

/**
 * Delete one downloaded model end-to-end: unload it if loaded, remove its
 * files through the platform adapter, and clear its registry path so the
 * entry returns to registered-not-downloaded (re-downloadable). Convenience
 * over [deleteStorage] with the canonical flag set — mirrors Swift
 * `RunAnywhere.deleteModel(_:)`.
 */
suspend fun RunAnywhere.deleteModel(modelId: String): StorageDeleteResult =
    deleteStorage(
        StorageDeleteRequest(
            model_ids = listOf(modelId),
            delete_files = true,
            clear_registry_paths = true,
            unload_if_loaded = true,
            allow_platform_delete = true,
        ),
    )

suspend fun RunAnywhere.clearCache() {
    requireStorageInitialized(this)
    ensureServicesReady()
    if (!CppBridgeFileManager.clearCache()) {
        throw SDKException.storage("Failed to clear cache")
    }
}

suspend fun RunAnywhere.cleanTempFiles() {
    requireStorageInitialized(this)
    ensureServicesReady()
    if (!CppBridgeFileManager.clearTemp()) {
        throw SDKException.storage("Failed to clean temp files")
    }
}

// MARK: - Helpers
