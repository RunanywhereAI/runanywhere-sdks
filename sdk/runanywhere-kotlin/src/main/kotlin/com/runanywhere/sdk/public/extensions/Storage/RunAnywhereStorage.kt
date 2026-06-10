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

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.ExpectedModelFiles
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.MultiFileArtifact
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import ai.runanywhere.proto.v1.ThinkingTagPattern
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.archiveArtifact
import com.runanywhere.sdk.public.extensions.Models.make
import com.runanywhere.sdk.public.extensions.Models.setArchiveArtifact
import com.runanywhere.sdk.public.extensions.Models.setMultiFileArtifact
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
    id: String?,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory,
    artifactType: ModelArtifactType?,
    memoryRequirement: Long?,
    supportsThinking: Boolean,
    supportsLora: Boolean,
): RAModelInfo {
    requireStorageInitialized(this)

    // Build a complete ModelInfo locally with every caller-supplied capability
    // field already set, then persist it through the registry's proto save
    // path ONCE. The plain save (rac_model_registry_register_proto) persists
    // every capability field (id, memory_required_bytes, supports_thinking +
    // thinking_pattern, supports_lora, artifact_type, download_size_bytes,
    // …), so no from-url-then-patch-then-resave round trip is needed.
    var model =
        ModelInfo.make(
            id = id ?: deriveModelIdFromUrl(url, name),
            name = name,
            category = modality,
            format = ModelFormat.MODEL_FORMAT_UNSPECIFIED,
            framework = framework,
            downloadURL = url,
            downloadSizeBytes = memoryRequirement,
            supportsThinking = supportsThinking,
            thinkingPattern = if (supportsThinking) ThinkingTagPattern() else null,
            source = ModelSource.MODEL_SOURCE_REMOTE,
        )

    if (memoryRequirement != null) {
        model = model.copy(memory_required_bytes = memoryRequirement)
    }
    if (supportsLora) {
        model = model.copy(supports_lora = true)
    }
    if (artifactType != null && artifactType != model.artifact_type) {
        model = model.copy(artifact_type = artifactType)
    }

    CppBridgeModelRegistry.save(model)
    return model
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
    // save path (mirroring Swift's archive overload).
    val archive = model.archiveArtifact ?: return model
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

    val artifact = MultiFileArtifact(files = multiFile)
    var model =
        ModelInfo
            .make(
                id = id,
                name = name,
                category = modality,
                format = ModelFormat.MODEL_FORMAT_UNSPECIFIED,
                framework = framework,
                downloadSizeBytes = memoryRequirement,
                contextLength = contextLength,
                supportsThinking = supportsThinking,
                source = source,
            ).setMultiFileArtifact(artifact)
            .copy(expected_files = ExpectedModelFiles(files = multiFile))

    if (memoryRequirement != null) {
        model = model.copy(memory_required_bytes = memoryRequirement)
    }

    CppBridgeModelRegistry.save(model)
    return model
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

/**
 * Derive a stable model id from a download URL when the caller has not
 * supplied one. Mirrors the Swift / commons fallback: take the URL's last
 * path component (sans extension), or the human-readable name slug if the
 * URL contributes nothing usable.
 */
private fun deriveModelIdFromUrl(url: String, name: String): String {
    val tail = url.substringAfterLast('/').substringBefore('?').trim()
    if (tail.isNotEmpty()) {
        val withoutExtension = tail.substringBefore('.')
        if (withoutExtension.isNotEmpty()) return withoutExtension
    }
    return name.replace(Regex("\\s+"), "-").lowercase().ifEmpty { "model-${getCurrentTimeMillis()}" }
}
