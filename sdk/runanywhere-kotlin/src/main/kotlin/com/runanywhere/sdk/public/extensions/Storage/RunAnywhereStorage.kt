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
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.MultiFileArtifact
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import ai.runanywhere.proto.v1.ThinkingTagPattern
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.archiveArtifact
import com.runanywhere.sdk.public.extensions.Models.create
import com.runanywhere.sdk.public.extensions.Models.setArchiveArtifact
import com.runanywhere.sdk.public.extensions.Models.setMultiFileArtifact
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAStorageInfo
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

    // Delegate the full build-and-save flow to commons via the canonical
    // `rac_register_model_from_url_proto` ABI (P2-T6) — mirrors Swift's
    // `RunAnywhere+Storage.swift:19-72`. The native helper translates a
    // RegisterModelFromUrlRequest → ModelInfoMakeRequest (framework-aware
    // defaulting + artifact inference + id/name derivation) and persists
    // through the registry's proto save path. If the JNI thunk has not yet
    // been wired in commons we fall back to the legacy local build path so
    // current behaviour is preserved.
    val request =
        RegisterModelFromUrlRequest(
            url = url,
            name = name,
            framework = framework,
            category = modality,
            source = ModelSource.MODEL_SOURCE_REMOTE,
        )

    var model =
        CppBridgeModelRegistry.registerModelFromUrl(request)
            ?: buildModelFromUrlLocally(
                id = id,
                name = name,
                url = url,
                framework = framework,
                modality = modality,
                memoryRequirement = memoryRequirement,
                supportsThinking = supportsThinking,
            )

    // Patch fields the proto request does not yet model (id override, memory
    // hint, thinking flag, LoRA flag, explicit artifact type) and re-persist
    // through the registry's proto save path. Mirrors Swift's needsResave
    // pattern.
    var needsResave = false
    if (id != null && id != model.id) {
        model = model.copy(id = id)
        needsResave = true
    }
    if (memoryRequirement != null) {
        model =
            model.copy(
                download_size_bytes = memoryRequirement,
                memory_required_bytes = memoryRequirement,
            )
        needsResave = true
    }
    if (supportsThinking && model.thinking_pattern == null) {
        model =
            model.copy(
                supports_thinking = true,
                thinking_pattern = ThinkingTagPattern(),
            )
        needsResave = true
    }
    if (supportsLora) {
        model = model.copy(supports_lora = true)
        needsResave = true
    }
    if (artifactType != null && artifactType != model.artifact_type) {
        model = model.copy(artifact_type = artifactType)
        needsResave = true
    }

    if (needsResave) {
        model = model.copy(updated_at_unix_ms = getCurrentTimeMillis())
        CppBridgeModelRegistry.save(model)
    }

    return model
}

/**
 * JVM-only fallback that mirrors the legacy local build-and-save path used
 * before commons exposed `rac_register_model_from_url_proto`. Kept so
 * registerModel(URL) still works when the JNI thunk is not yet bound (e.g.
 * older `librunanywhere_jni.so` builds).
 */
private fun buildModelFromUrlLocally(
    id: String?,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory,
    memoryRequirement: Long?,
    supportsThinking: Boolean,
): RAModelInfo {
    val model =
        ModelInfo.create(
            id = id ?: deriveModelIdFromUrl(url, name),
            name = name,
            category = modality,
            format = ModelFormat.MODEL_FORMAT_UNSPECIFIED,
            framework = framework,
            downloadURL = url,
            downloadSizeBytes = memoryRequirement,
            supportsThinking = supportsThinking,
            source = ModelSource.MODEL_SOURCE_REMOTE,
        )
    CppBridgeModelRegistry.save(model)
    return model
}

suspend fun RunAnywhere.registerModel(
    archiveUrl: String,
    structure: ArchiveStructure,
    id: String?,
    name: String,
    framework: InferenceFramework,
    modality: ModelCategory,
    archiveType: ArchiveType?,
    memoryRequirement: Long?,
    supportsThinking: Boolean,
    supportsLora: Boolean,
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
    modality: ModelCategory,
    memoryRequirement: Long?,
    contextLength: Int?,
    supportsThinking: Boolean,
    source: ModelSource,
): RAModelInfo {
    requireStorageInitialized(this)

    val artifact = MultiFileArtifact(files = multiFile)
    var model =
        ModelInfo
            .create(
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

    if (memoryRequirement != null) {
        model = model.copy(memory_required_bytes = memoryRequirement)
    }

    CppBridgeModelRegistry.save(model)
    return model
}

// MARK: - Model Import

suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult {
    requireStorageInitialized(this)
    return CppBridgeModelRegistry.importModel(request)
}

// MARK: - Storage Information

suspend fun RunAnywhere.getStorageInfo(): RAStorageInfo {
    requireStorageInitialized(this)
    return getStorageInfo(
        StorageInfoRequest(
            include_device = true,
            include_app = true,
            include_models = true,
        ),
    ).info ?: throw SDKException.storage("Storage info result did not include info")
}

suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest): StorageInfoResult {
    requireStorageInitialized(this)
    return CppBridgeStorage.info(request)
        ?: throw SDKException.storage("Native storage info proto API unavailable")
}

suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult {
    requireStorageInitialized(this)
    return CppBridgeStorage.delete(request)
        ?: throw SDKException.storage("Native storage delete proto API unavailable")
}

suspend fun RunAnywhere.clearCache() {
    requireStorageInitialized(this)
    if (!CppBridgeFileManager.clearCache()) {
        throw SDKException.storage("Failed to clear cache")
    }
}

suspend fun RunAnywhere.cleanTempFiles() {
    requireStorageInitialized(this)
    if (!CppBridgeFileManager.clearTemp()) {
        throw SDKException.storage("Failed to clean temp files")
    }
}

// MARK: - Device Registration

/**
 * Clear the persisted device-registration flag so the next services
 * initialization re-runs the device-registration handshake against the
 * configured backend. Persists the cleared state through the secure-storage
 * adapter the SDK already uses for the `runanywhere_device_registered`
 * key — callers must NOT reach into app-private SharedPreferences to wipe
 * `runanywhere_sdk`/`com.runanywhere.sdk.deviceRegistered`, which never
 * shadowed the real flag.
 */
fun RunAnywhere.resetDeviceRegistration() {
    requireStorageInitialized(this)
    CppBridgeDevice.setRegisteredCallback(false)
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
