/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for storage operations.
 *
 * Mirrors Swift `RunAnywhere+Storage.swift` exactly:
 *   - `registerModel(...)` URL / archive / multi-file overloads (Swift parity)
 *   - `importModel(request)` local-import entry point
 *   - `getStorageInfo()` (replaces the legacy `storageInfo()` accessor)
 *   - `deleteStorage(request)` executing or dry-running deletion
 *   - `clearCache()` / `cleanTempFiles()` forwarding to the FileManager bridge
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAStorageInfo

// MARK: - Model Registration

/**
 * Register a remote model with the in-memory model registry from a
 * download URL.
 *
 * Mirrors Swift `RunAnywhere.registerModel(id:name:url:framework:modality:
 * artifactType:memoryRequirement:supportsThinking:supportsLora:)`. The Swift
 * implementation delegates to the canonical `rac_register_model_from_url_proto`
 * C ABI. The Kotlin SDK does not yet expose that direct ABI, so this synthesises
 * an [RAModelInfo] via [ai.runanywhere.proto.v1.ModelInfo.Companion.create] and
 * persists through the registry's proto save path — matching the same
 * downstream behaviour.
 */
expect suspend fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): RAModelInfo

/**
 * Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
 * where the caller needs to specify the on-disk layout (`directoryBased`,
 * `nestedDirectory`, etc.) the URL-form [registerModel] cannot infer.
 *
 * Mirrors Swift `RunAnywhere.registerModel(archive:structure:...)`.
 * Composes the canonical URL-form [registerModel] and then patches the
 * resolved archive artifact `structure` before re-saving through the
 * registry.
 */
expect suspend fun RunAnywhere.registerModel(
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
): RAModelInfo

/**
 * Register a multi-file model (e.g., VLMs with a separate mmproj, MiniLM
 * embedding with vocab.txt). Builds [RAModelInfo] via the canonical
 * `ModelInfo.create(...)` factory and persists through the registry's
 * proto save path — no URL is involved at the model level because each
 * [ModelFileDescriptor] carries its own URL.
 *
 * Mirrors Swift `RunAnywhere.registerModel(multiFile:id:name:format:
 * framework:modality:contextLength:source:)`.
 */
expect suspend fun RunAnywhere.registerModel(
    multiFile: List<ModelFileDescriptor>,
    id: String,
    name: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement: Long? = null,
    contextLength: Int? = null,
    supportsThinking: Boolean = false,
    source: ModelSource = ModelSource.MODEL_SOURCE_REMOTE,
): RAModelInfo

// MARK: - Model Import

/**
 * Import a stable, platform-normalized local model path into the generated
 * registry. This is also the public local-import entry point for file
 * picker/bookmark flows after the platform has handled sandbox access.
 *
 * Mirrors Swift `RunAnywhere.importModel(_:)`. Backed by
 * `rac_model_registry_import_proto`.
 */
expect suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult

// MARK: - Storage Information

/**
 * Get complete storage information.
 *
 * Mirrors Swift `RunAnywhere.getStorageInfo()`. Equivalent to calling
 * [getStorageInfo] with the default request that includes device, app and
 * model storage details.
 */
expect suspend fun RunAnywhere.getStorageInfo(): RAStorageInfo

/**
 * Get storage information through the canonical generated proto API.
 *
 * Mirrors Swift `RunAnywhere.getStorageInfo(_:)`.
 */
expect suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest): StorageInfoResult

// MARK: - Storage Deletion

/**
 * Execute or dry-run a C++-planned storage delete.
 *
 * Mirrors Swift `RunAnywhere.deleteStorage(_:)`.
 */
expect suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult

// MARK: - Cache and Temp

/**
 * Clear the SDK's Cache directory.
 *
 * Mirrors Swift `RunAnywhere.clearCache()`. Forwards to the FileManager
 * bridge `nativeFileManagerClearCache()` thunk.
 */
expect suspend fun RunAnywhere.clearCache()

/**
 * Clear the SDK's Temp directory.
 *
 * Mirrors Swift `RunAnywhere.cleanTempFiles()`. Forwards to the FileManager
 * bridge `nativeFileManagerClearTemp()` thunk.
 */
expect suspend fun RunAnywhere.cleanTempFiles()
