/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for LoRA adapter management.
 * Delegates to the generated LoRA proto-byte ABI in C++.
 *
 * LoRA (Low-Rank Adaptation) adapters allow fine-tuning behavior
 * of a loaded base model without replacing it.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.ExpectedModelFiles
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoRAApplyResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import ai.runanywhere.proto.v1.LoraAdapterImportRequest
import ai.runanywhere.proto.v1.LoraAdapterImportResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelInfoMetadata
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.SingleFileArtifact
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALoRAAdapterConfig
import com.runanywhere.sdk.public.types.RALoRAApplyRequest
import com.runanywhere.sdk.public.types.RALoRARemoveRequest
import com.runanywhere.sdk.public.types.RALoRAState
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Stateless capability namespace for LoRA adapter management.
 *
 * Mirrors Swift's `RunAnywhere.lora` (`RunAnywhere+LoRA.swift`) surface 1:1.
 * Runtime operations (apply / remove / list / state / checkCompatibility) and
 * catalog operations (register / listCatalog / queryCatalog / getCatalogEntry /
 * markDownloadCompleted / markImportCompleted) all flow through generated
 * request / result types from `lora_options.proto`.
 */
interface LoRA {
    /** Apply one or more LoRA adapters to the currently loaded model. */
    suspend fun apply(request: RALoRAApplyRequest): LoRAApplyResult

    /**
     * Apply one registered catalog adapter to the currently loaded model.
     *
     * Preserves `entry.id` in the generated config so commons can validate
     * registered catalog adapters against the loaded base model.
     */
    suspend fun apply(
        entry: LoraAdapterCatalogEntry,
        localPath: String? = null,
        scale: Float? = null,
        replaceExisting: Boolean = false,
    ): LoRAApplyResult {
        val adapterPath = localPath ?: entry.local_path?.takeIf { it.isNotBlank() }
        if (adapterPath.isNullOrBlank()) {
            throw SDKException.invalidArgument("LoRA catalog adapter '${entry.id}' has no local path")
        }
        return apply(
            RALoRAApplyRequest(
                adapters =
                    listOf(
                        RALoRAAdapterConfig(
                            adapter_path = adapterPath,
                            adapter_id = entry.id.takeIf { it.isNotBlank() },
                            scale = scale ?: entry.default_scale.takeIf { it > 0f } ?: 1f,
                        ),
                    ),
                replace_existing = replaceExisting,
            ),
        )
    }

    /** Remove adapters by generated request semantics, including `clear_all`. */
    suspend fun remove(request: RALoRARemoveRequest): RALoRAState

    /** Get info about all currently loaded LoRA adapters. */
    suspend fun list(): RALoRAState

    /** Get the LoRA service state reported by commons. */
    suspend fun state(): RALoRAState

    /**
     * Check whether a LoRA adapter is compatible with the current base model.
     * Mirrors Swift: returns an incompatible result instead of throwing.
     */
    suspend fun checkCompatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult

    /** Register a LoRA adapter from a full catalog entry. */
    suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry

    /**
     * Register both the generated LoRA catalog entry and its generated download
     * artifact record. This does not fetch bytes.
     */
    suspend fun registerArtifact(entry: LoraAdapterCatalogEntry): RAModelInfo

    /**
     * Download a LoRA adapter through the canonical model-download pipeline.
     *
     * One call registers the catalog entry + artifact, downloads with
     * resume/checksum/progress through commons, records completion in the LoRA
     * catalog, and returns the stable local adapter path.
     */
    suspend fun download(
        entry: LoraAdapterCatalogEntry,
        onProgress: (suspend (DownloadProgress) -> Unit)? = null,
    ): String

    /** List catalog entries using the generated catalog request/result ABI. */
    suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest = LoraAdapterCatalogListRequest(),
    ): LoraAdapterCatalogListResult

    /** Query catalog entries using generated filter semantics owned by commons. */
    suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult

    /** Fetch one catalog entry by generated request semantics. */
    suspend fun getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult

    /** Persist native-reported completion state after the platform has fetched bytes. */
    suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult

    /**
     * Import a user-picked local adapter file into SDK-owned storage.
     *
     * Kotlin only resolves platform access (e.g. content URI to a readable
     * path) before calling; commons owns everything past the source path:
     * deterministic catalog matching, canonical placement, artifact registry
     * record + manifest persistence, and catalog completion for matched
     * entries. Apps apply the returned `local_path`; they never construct
     * on-disk paths themselves.
     */
    suspend fun importAdapter(sourcePath: String): LoraAdapterImportResult

    /**
     * Persist native-reported import completion state. Sets `imported = true`
     * and a default status message when not already populated, matching the
     * IDL contract for platform file-picker / import completion.
     */
    suspend fun markImportCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult {
        val patched =
            request.copy(
                imported = true,
                status_message =
                    request.status_message.ifBlank { "import completed" },
            )
        return markDownloadCompleted(patched)
    }

    /**
     * Get all LoRA adapters compatible with a specific model
     * (CANONICAL_API §3, mirrors Swift `adaptersForModel`).
     */
    suspend fun adaptersForModel(modelId: String): List<LoraAdapterCatalogEntry> {
        val result = queryCatalog(LoraAdapterCatalogQuery(model_id = modelId))
        if (!result.success) {
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                message = result.error_message.ifBlank { "LoRA catalog query failed" },
                category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
                shouldLog = false,
            )
        }
        return result.entries
    }

    /**
     * Get all registered LoRA adapters
     * (CANONICAL_API §3, mirrors Swift `allRegistered`).
     */
    suspend fun allRegistered(): List<LoraAdapterCatalogEntry> {
        val result = listCatalog()
        if (!result.success) {
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                message = result.error_message.ifBlank { "LoRA catalog list failed" },
                category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
                shouldLog = false,
            )
        }
        return result.entries
    }
}

private const val LORA_ARTIFACT_MODEL_ID_PREFIX = "lora-adapter:"
private const val LORA_ARTIFACT_TAG = "lora-adapter"

private suspend fun ensureLoraReady() {
    if (!RunAnywhere.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    RunAnywhere.ensureServicesReady()
}

/**
 * Stable model-registry id used for a LoRA adapter artifact.
 *
 * The adapter remains a LoRA catalog entry for apply/remove semantics, while
 * its bytes are represented as a generated model artifact so download/storage
 * policy stays on the generated registry/download path.
 */
val LoraAdapterCatalogEntry.loraArtifactModelID: String
    get() =
        if (id.startsWith(LORA_ARTIFACT_MODEL_ID_PREFIX)) {
            id
        } else {
            "$LORA_ARTIFACT_MODEL_ID_PREFIX$id"
        }

/**
 * Convert a generated LoRA catalog entry into generated model-registry
 * metadata used by the generic generated download path. Catalog filtering and
 * completion state remain owned by the generated LoRA catalog ABI.
 */
fun LoraAdapterCatalogEntry.toLoraArtifactModelInfo(
    timestampUnixMs: Long = getCurrentTimeMillis(),
): RAModelInfo {
    val artifactFilename = filename.ifBlank { url.substringAfterLast('/').substringBefore('?') }
    val descriptor =
        ModelFileDescriptor(
            url = url,
            filename = artifactFilename,
            is_required = true,
            size_bytes = size_bytes.takeIf { it > 0 },
            role = ModelFileRole.MODEL_FILE_ROLE_COMPANION,
            checksum_sha256 = checksum_sha256,
        )
    val expectedFiles =
        ExpectedModelFiles(
            files = listOf(descriptor),
            required_patterns = listOf(artifactFilename),
            description = "LoRA adapter artifact",
        )
    val metadataTags =
        buildList {
            add(LORA_ARTIFACT_TAG)
            compatible_models.forEach { add("base-model:$it") }
            addAll(tags)
        }.distinct()

    return RAModelInfo(
        id = loraArtifactModelID,
        name = name,
        category = ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
        format = ModelFormat.MODEL_FORMAT_GGUF,
        framework = InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED,
        download_url = url,
        download_size_bytes = size_bytes,
        supports_lora = false,
        description = description,
        source = ModelSource.MODEL_SOURCE_REMOTE,
        created_at_unix_ms = timestampUnixMs,
        updated_at_unix_ms = timestampUnixMs,
        checksum_sha256 = checksum_sha256,
        metadata =
            ModelInfoMetadata(
                description = description,
                author = author.orEmpty(),
                license = license.orEmpty(),
                tags = metadataTags,
            ),
        single_file =
            SingleFileArtifact(
                required_patterns = listOf(artifactFilename),
                expected_files = expectedFiles,
            ),
        artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
        expected_files = expectedFiles,
        is_available = true,
    )
}

/**
 * JVM/Android backing object for [LoRA]. Stateless; all calls
 * delegate to [CppBridgeLoraRegistry] on `Dispatchers.IO`.
 */
internal object AndroidLoRA : LoRA {
    override suspend fun apply(request: RALoRAApplyRequest): LoRAApplyResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.apply(request)
        }
    }

    override suspend fun remove(request: RALoRARemoveRequest): RALoRAState {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.remove(request)
        }
    }

    override suspend fun list(): RALoRAState {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.list(RALoRAState())
        }
    }

    override suspend fun state(): RALoRAState {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.state(RALoRAState())
        }
    }

    override suspend fun checkCompatibility(config: RALoRAAdapterConfig): LoraCompatibilityResult =
        try {
            ensureLoraReady()
            withContext(Dispatchers.IO) {
                CppBridgeLoraRegistry.compatibility(config)
            }
        } catch (e: Exception) {
            LoraCompatibilityResult(
                is_compatible = false,
                error_message = e.message.orEmpty(),
            )
        }

    override suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.register(entry)
        }
    }

    override suspend fun registerArtifact(entry: LoraAdapterCatalogEntry): RAModelInfo {
        val registeredEntry = register(entry)
        val artifact = registeredEntry.toLoraArtifactModelInfo()
        registerModelInternal(artifact)
        return artifact
    }

    override suspend fun download(
        entry: LoraAdapterCatalogEntry,
        onProgress: (suspend (DownloadProgress) -> Unit)?,
    ): String {
        ensureLoraReady()
        val artifact = registerArtifact(entry)
        val finalProgress = RunAnywhere.downloadModel(artifact, onProgress = onProgress)

        var localPath = finalProgress.local_path
        if (localPath.isBlank()) {
            val lookup = RunAnywhere.getModel(ModelGetRequest(model_id = artifact.id))
            if (lookup.found) {
                localPath = lookup.model?.local_path.orEmpty()
            }
        }
        if (localPath.isBlank()) {
            throw SDKException.operation(
                "LoRA adapter '${entry.id}' downloaded but no local path was recorded",
            )
        }

        markDownloadCompleted(
            LoraAdapterDownloadCompletedRequest(
                adapter_id = entry.id,
                local_path = localPath,
            ),
        )
        return localPath
    }

    override suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest,
    ): LoraAdapterCatalogListResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.listCatalog(request)
        }
    }

    override suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.queryCatalog(query)
        }
    }

    override suspend fun getCatalogEntry(
        request: LoraAdapterCatalogGetRequest,
    ): LoraAdapterCatalogGetResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.getCatalogEntry(request)
        }
    }

    override suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.markDownloadCompleted(request)
        }
    }

    override suspend fun importAdapter(sourcePath: String): LoraAdapterImportResult {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.importAdapter(LoraAdapterImportRequest(source_path = sourcePath))
        }
    }
}

val RunAnywhere.lora: LoRA
    get() = AndroidLoRA
