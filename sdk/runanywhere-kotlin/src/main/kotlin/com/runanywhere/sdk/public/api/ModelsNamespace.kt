/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: `RunAnywhere.models`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.StorageInfoRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * [LoadOptions] fields the commons load ABI has no wire path for yet.
 *
 * `ModelLoadRequest` only carries a framework pin; `contextLength`, `threads`,
 * and `accelerator` are accepted here for cross-SDK API parity but cannot be
 * honored until the native load ABI grows placement fields (tracked as a
 * follow-up — see PR #605 review follow-up issue 8). Per the v4 contract,
 * "every accepted field is implemented end to end or fails preflight" —
 * silently dropping them is forbidden, so [ModelsNamespace.load] throws
 * instead of warning.
 */
internal fun LoadOptions?.unsupportedLoadKnobs(): List<String> =
    listOfNotNull(
        "contextLength".takeIf { this?.contextLength != null },
        "threads".takeIf { this?.threads != null },
        "accelerator".takeIf { this?.resolvedAccelerator != null },
        "backendPreferences (only the first preference reaches commons; ordered fallback is not carried)"
            .takeIf { (this?.resolvedBackendPreferences?.size ?: 0) > 1 },
    )

private val LOADABLE_CATEGORIES =
    listOf(
        ModelCategory.MODEL_CATEGORY_LANGUAGE,
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        ModelCategory.MODEL_CATEGORY_EMBEDDING,
        ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
        ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
        ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
    )

/** True when [id] is resident under any tracked category right now. */
private suspend fun isModelResident(id: String): Boolean =
    LOADABLE_CATEGORIES.any { category ->
        val current = legacyCurrentModel(CurrentModelRequest(category = category))
        current.found && current.model_id == id
    }

/**
 * The model catalog and everything that governs residency.
 *
 * ```kotlin
 * RunAnywhere.models.download("qwen3-0.6b").collect { event -> report(event) }
 * val loaded = RunAnywhere.models.load("qwen3-0.6b")
 * ```
 */
public class ModelsNamespace internal constructor() {
    /**
     * Every registered model, narrowed by [filter].
     *
     * @throws SDKException when the registry cannot be read.
     */
    public suspend fun list(filter: ModelFilter? = null): List<ModelInfo> {
        val result = legacyListModels(ModelListRequest(query = filter.toProto()))
        result.error?.let { throw SDKException(it) }
        return result.models?.models.orEmpty()
    }

    /** The registry record for [id], or null when it is not registered. */
    public suspend fun get(id: String): ModelInfo? {
        val result = legacyGetModel(ModelGetRequest(model_id = id))
        return if (result.found) result.model else null
    }

    /**
     * Add [model] to the registry without fetching its bytes.
     *
     * @throws SDKException when the registry rejects the artifact.
     */
    public suspend fun register(model: ModelRegistration): ModelInfo =
        when (model.kind) {
            ModelRegistration.Kind.URL -> legacyRegisterFromUrl(model)
            ModelRegistration.Kind.ARCHIVE -> legacyRegisterArchive(model)
            ModelRegistration.Kind.MULTI_FILE -> legacyRegisterMultiFile(model)
        }

    /**
     * Remove [id] from the registry. Registration metadata only — [id] must
     * already be unloaded and have no local artifacts.
     *
     * @throws SDKException when [id] is unknown, still loaded, or still has
     *   local artifacts; call [unload]/[delete] first.
     */
    public suspend fun unregister(id: String) {
        val model = get(id) ?: throw SDKException.modelNotFound(id)
        if (isModelResident(id)) {
            throw SDKException.invalidState(
                "Model '$id' is currently loaded. Call models.unload('$id') before unregister.",
            )
        }
        if (model.local_path.isNotEmpty()) {
            throw SDKException.invalidState(
                "Model '$id' still has local artifacts. Call models.delete('$id') before unregister.",
            )
        }
        legacyUnregisterModel(id)
    }

    /**
     * Fetch [id]'s bytes, reporting progress until the model is on disk.
     *
     * Cancelling the flow stops the transfer and preserves resume bytes. The
     * stream ends in [DownloadEvent.Completed]/[DownloadEvent.Failed] — never
     * a fabricated success.
     *
     * @throws SDKException when the model is unknown.
     */
    public fun download(id: String): Flow<DownloadEvent> =
        flow {
            val operationId = id
            var sequence = 0L
            val model = get(id) ?: throw SDKException.modelNotFound(id)
            emit(DownloadEvent.Started(operationId, sequence++))
            try {
                legacyDownloadModel(model) { progress ->
                    // DownloadStage was folded into DownloadState
                    // (idl/download_service.proto) -- switch on `.state`
                    // directly.
                    when (progress.state) {
                        DownloadState.DOWNLOAD_STATE_VALIDATING ->
                            emit(DownloadEvent.Verifying(operationId, sequence++))
                        DownloadState.DOWNLOAD_STATE_EXTRACTING ->
                            emit(
                                DownloadEvent.Extracting(
                                    operationId = operationId,
                                    sequence = sequence++,
                                    percent = progress.stage_progress * 100,
                                ),
                            )
                        else ->
                            emit(
                                DownloadEvent.Progress(
                                    operationId = operationId,
                                    sequence = sequence++,
                                    bytesDone = progress.bytes_downloaded,
                                    bytesTotal = progress.total_bytes,
                                    file = progress.current_file_name.takeIf { it.isNotEmpty() },
                                    // C++ reports 0 for "not measured yet" and the proto leaves eta
                                    // absent for "unknown". Both are normalised to null here so a
                                    // UI can tell missing from genuinely zero and show nothing
                                    // rather than "0 B/s" while the transfer spins up.
                                    bytesPerSecond = progress.bytes_per_second.takeIf { it > 0f },
                                    etaSeconds = progress.eta_seconds,
                                    retryAttempt = progress.retry_attempt,
                                    overallProgress = progress.overall_progress.takeIf { it > 0f },
                                    currentFileIndex = progress.current_file_index,
                                    totalFiles = progress.total_files.coerceAtLeast(1),
                                ),
                            )
                    }
                }
            } catch (error: SDKException) {
                emit(DownloadEvent.Failed(operationId, sequence++, error))
                return@flow
            }
            emit(DownloadEvent.Completed(operationId, sequence++, get(id) ?: model))
        }

    /**
     * Remove [id]'s files and return it to registered-not-downloaded.
     * Registration metadata is retained, so the same id can be downloaded again.
     *
     * @throws SDKException when deletion fails.
     */
    public suspend fun delete(id: String) {
        val result = legacyDeleteModel(id)
        result.error?.let { throw SDKException(it) }
    }

    /**
     * Make [id] resident now, downloading it first when its bytes are absent.
     *
     * Only [LoadOptions.backendPreferences]'s first entry (equivalently the
     * deprecated `framework`) reaches commons today. `contextLength`,
     * `threads`, and a real `accelerator` choice are not yet carried by the
     * native load ABI, so passing them throws rather than being silently dropped.
     *
     * @throws SDKException when the model cannot be loaded, or when [options]
     *   sets a placement knob the load ABI cannot honor yet.
     */
    public suspend fun load(id: String, options: LoadOptions? = null): LoadedModel {
        val unsupported = options.unsupportedLoadKnobs()
        if (unsupported.isNotEmpty()) {
            throw SDKException.invalidConfiguration(
                "LoadOptions.${unsupported.joinToString(", ")} cannot be carried by the native load ABI yet",
            )
        }
        val registered = get(id) ?: throw SDKException.modelNotFound(id)
        val category =
            registered.category.takeIf { it != ModelCategory.MODEL_CATEGORY_UNSPECIFIED }
                ?: ModelCategory.MODEL_CATEGORY_LANGUAGE
        if (registered.local_path.isEmpty()) {
            legacyDownloadModel(registered)
        }
        val requestedBackend = options?.resolvedBackendPreferences?.firstOrNull()
        val result =
            legacyLoadModel(
                ModelLoadRequest(
                    model_id = id,
                    category = category,
                    framework = requestedBackend?.backend ?: registered.framework.takeIf { it.value != 0 },
                    force_reload = options?.forceReload ?: false,
                    validate_availability = true,
                ),
            )
        result.error?.let { throw SDKException(it) }
        val refreshed = get(id)
        return LoadedModel(
            id = id,
            category = category,
            requestedBackend = requestedBackend,
            actualBackend = requestedBackend?.backend ?: refreshed?.framework ?: registered.framework,
            closeHandler = { modelId -> unload(modelId) },
        )
    }

    /**
     * Release one resident model by [id]. Idempotent — a no-op when [id] is not loaded.
     *
     * @throws SDKException when the unload is rejected.
     */
    public suspend fun unload(id: String) {
        val model = get(id)
        val result =
            legacyUnloadModel(
                ModelUnloadRequest(model_id = id, category = model?.category, unload_all = false),
            )
        result.error?.let { throw SDKException(it) }
    }

    /**
     * Release the model resident under [category], or every resident model
     * when [category] is null. This is the only category/global unload;
     * [unload] releases exactly one model by id.
     *
     * @throws SDKException when the unload fails.
     */
    public suspend fun unloadAll(category: ModelCategory? = null) {
        val request =
            if (category == null) {
                ModelUnloadRequest(unload_all = true)
            } else {
                ModelUnloadRequest(category = category)
            }
        val result = legacyUnloadModel(request)
        result.error?.let { throw SDKException(it) }
    }

    /**
     * @deprecated Use [unloadAll]. Release the model resident under [category],
     *   or every model when null.
     */
    @Deprecated("Use unloadAll(category).", ReplaceWith("unloadAll(category)"))
    public suspend fun unload(category: ModelCategory? = null) {
        unloadAll(category)
    }

    /** What is resident right now, and how much storage is used and free. */
    public suspend fun state(): ModelsState {
        val loaded = mutableMapOf<ModelCategory, ModelInfo>()
        for (category in LOADABLE_CATEGORIES) {
            val current =
                legacyCurrentModel(
                    CurrentModelRequest(category = category, include_model_metadata = true),
                )
            if (current.found) {
                current.model?.let { loaded[category] = it }
            }
        }
        val storage =
            legacyStorageInfo(
                StorageInfoRequest(include_device = true, include_app = true, include_models = true),
            ).info
        return ModelsState(
            loaded = loaded,
            storageUsedBytes = storage?.total_models_bytes ?: 0L,
            storageFreeBytes = storage?.device?.free_bytes ?: 0L,
        )
    }
}
