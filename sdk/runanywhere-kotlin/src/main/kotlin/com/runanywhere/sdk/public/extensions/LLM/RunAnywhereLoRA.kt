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
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraApplyResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfoMetadata
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALoRAAdapterConfig
import com.runanywhere.sdk.public.types.RALoRAApplyRequest
import com.runanywhere.sdk.public.types.RALoRARemoveRequest
import com.runanywhere.sdk.public.types.RALoRAState
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Stateless capability namespace for LoRA adapter management.
 *
 * Mirrors Swift's `RunAnywhere.lora` (`RunAnywhere+LoRA.swift` +
 * `RunAnywhere+LoRADownload.swift`) surface 1:1. Runtime operations
 * (apply / remove / list / state / checkCompatibility) and catalog
 * operations (register / listCatalog / queryCatalog / getCatalogEntry) flow
 * through generated request / result types from `lora_options.proto`.
 *
 * `LoraAdapterDownloadCompletedRequest`/`Result` and
 * `LoraAdapterImportRequest`/`Result` were deleted outright from
 * idl/lora_options.proto (the "lora-delete-download-import-bookkeeping"
 * API-simplification edit): adapter files are now acquired exclusively
 * through the models domain's download/import verbs; this LoRA domain
 * carries no download/import state of its own -- a non-empty
 * `LoraAdapterCatalogEntry.local_path` is the only "downloaded" signal
 * that survives. `markDownloadCompleted`/`markImportCompleted` are gone
 * with no replacement.
 */
interface LoRA {
    /** Apply one or more LoRA adapters to the currently loaded model. */
    suspend fun apply(request: RALoRAApplyRequest): LoraApplyResult

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
    ): LoraApplyResult {
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
                            adapter_id = entry.id,
                            scale = scale ?: entry.default_scale?.takeIf { it > 0f } ?: 1f,
                        ),
                    ),
                // Wire polarity was inverted (LoraApplyRequest.replace_existing ->
                // keep_existing): the public replaceExisting parameter name/default
                // are unchanged, only the proto-building code inverts.
                keep_existing = !replaceExisting,
            ),
        )
    }

    /**
     * Named alias for [apply] on a catalog entry, mirroring Swift
     * `applyCatalogAdapter(_:localPath:scale:replaceExisting:)`.
     */
    suspend fun applyCatalogAdapter(
        entry: LoraAdapterCatalogEntry,
        localPath: String? = null,
        scale: Float? = null,
        replaceExisting: Boolean = false,
    ): LoraApplyResult = apply(entry, localPath, scale, replaceExisting)

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
     * Register both the LoRA catalog entry and its caller-supplied
     * downloadable artifact record. Does not fetch bytes.
     *
     * `LoraAdapterCatalogEntry` no longer carries url/filename/size/checksum
     * metadata (idl/lora_options.proto: "everything generic about the
     * artifact ... lives on the ModelInfo record for this adapter"), so the
     * artifact can no longer be derived from the entry alone -- callers
     * supply the [artifact] `ModelInfo` describing where/how to fetch the
     * adapter bytes (e.g. built via `ModelInfo.Companion.make(...)`).
     */
    suspend fun registerArtifact(entry: LoraAdapterCatalogEntry, artifact: RAModelInfo): RAModelInfo

    /**
     * Download a LoRA adapter through the canonical model-download pipeline.
     *
     * One call registers the catalog entry + artifact, downloads with
     * resume/checksum/progress through commons, and returns the stable
     * local adapter path. There is nothing left to "mark completed" in the
     * LoRA domain: the model-registry artifact record (keyed by
     * [artifact]'s id) is the sole source of truth for the downloaded path.
     */
    suspend fun download(
        entry: LoraAdapterCatalogEntry,
        artifact: RAModelInfo,
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

    /**
     * Import a user-picked local adapter file into SDK-owned storage.
     *
     * The LoRA-domain import verb (deterministic catalog matching, canonical
     * `{Models}/{framework}/lora-adapter:{id}/` placement, catalog
     * `imported=true` completion) has no replacement. Adapter files are now
     * acquired exclusively through the models domain's generic import verb
     * (`RunAnywhere.importModel`), so this imports [sourcePath] as a plain
     * model artifact tagged `lora-adapter`. Unlike the retired ABI, this
     * does NOT automatically match the import against an existing LoRA
     * catalog entry -- callers that need the catalog association call
     * [register]/[registerArtifact] with the matching entry themselves once
     * they know which adapter this file corresponds to.
     */
    suspend fun importAdapter(sourcePath: String): ModelImportResult

    /**
     * Get all LoRA adapters compatible with a specific model
     * (CANONICAL_API §3, mirrors Swift `adaptersForModel`).
     */
    suspend fun adaptersForModel(modelId: String): List<LoraAdapterCatalogEntry> {
        val result = queryCatalog(LoraAdapterCatalogQuery(model_id = modelId))
        if (result.error != null) {
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                message = result.error!!.message.ifBlank { "LoRA catalog query failed" },
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
        if (result.error != null) {
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_PROCESSING_FAILED,
                message = result.error!!.message.ifBlank { "LoRA catalog list failed" },
                category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
                shouldLog = false,
            )
        }
        return result.entries
    }
}

private const val LORA_ARTIFACT_TAG = "lora-adapter"

private suspend fun ensureLoraReady() {
    if (!RunAnywhere.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    RunAnywhere.ensureServicesReady()
}

/**
 * JVM/Android backing object for [LoRA]. Stateless; all calls
 * delegate to [CppBridgeLoraRegistry] on `Dispatchers.IO`.
 */
internal object AndroidLoRA : LoRA {
    override suspend fun apply(request: RALoRAApplyRequest): LoraApplyResult {
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
                error =
                    ai.runanywhere.proto.v1.SDKError(
                        code = ErrorCode.ERROR_CODE_UNKNOWN,
                        category = ErrorCategory.ERROR_CATEGORY_COMPONENT,
                        message = e.message.orEmpty(),
                    ),
            )
        }

    override suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry {
        ensureLoraReady()
        return withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.register(entry)
        }
    }

    override suspend fun registerArtifact(
        entry: LoraAdapterCatalogEntry,
        artifact: RAModelInfo,
    ): RAModelInfo {
        register(entry)
        val tagged =
            artifact.copy(
                metadata =
                    (artifact.metadata ?: ModelInfoMetadata()).copy(
                        tags = (artifact.metadata?.tags.orEmpty() + LORA_ARTIFACT_TAG).distinct(),
                    ),
            )
        registerModelInternal(tagged)
        return tagged
    }

    override suspend fun download(
        entry: LoraAdapterCatalogEntry,
        artifact: RAModelInfo,
        onProgress: (suspend (DownloadProgress) -> Unit)?,
    ): String {
        ensureLoraReady()
        val registered = registerArtifact(entry, artifact)
        val finalProgress = RunAnywhere.downloadModel(registered, onProgress = onProgress)

        var localPath = finalProgress.local_path
        if (localPath.isBlank()) {
            val lookup =
                RunAnywhere.getModel(
                    ai.runanywhere.proto.v1
                        .ModelGetRequest(model_id = registered.id),
                )
            if (lookup.found) {
                localPath = lookup.model?.local_path.orEmpty()
            }
        }
        if (localPath.isBlank()) {
            throw SDKException.operation(
                "LoRA adapter '${entry.id}' downloaded but no local path was recorded",
            )
        }
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

    override suspend fun importAdapter(sourcePath: String): ModelImportResult {
        ensureLoraReady()
        val model =
            RAModelInfo(
                metadata = ModelInfoMetadata(tags = listOf(LORA_ARTIFACT_TAG)),
            )
        return RunAnywhere.importModel(
            ModelImportRequest(
                model = model,
                source_path = sourcePath,
                copy_into_managed_storage = true,
                validate_before_register = true,
            ),
        )
    }
}

/**
 * LoRA catalog surface kept for one release.
 *
 * The v3 namespace `RunAnywhere.lora` covers apply, remove, and list; commons
 * keeps its catalog behind a separate ABI, so registration and import still
 * come from here.
 */
@Deprecated("Use RunAnywhere.lora for apply/remove/list; catalog verbs remain here for one release.")
val RunAnywhere.loraCatalog: LoRA
    get() = AndroidLoRA
