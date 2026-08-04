/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.models`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.StorageInfoRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.atomic.AtomicBoolean

private val modelsLogger = SDKLogger("Models")
private val loadKnobsWarned = AtomicBoolean(false)

/**
 * [LoadOptions] fields the commons load ABI has no wire path for yet.
 *
 * `ModelLoadRequest` only carries a framework pin; `contextLength`, `threads`,
 * and `useGpu` are accepted here for cross-SDK API parity but are silently
 * dropped below commons until the native load ABI grows placement fields
 * (tracked as a follow-up — see PR #605 review follow-up issue 8).
 */
internal fun LoadOptions?.ignoredKnobs(): List<String> =
    listOfNotNull(
        "contextLength".takeIf { this?.contextLength != null },
        "threads".takeIf { this?.threads != null },
        "useGpu".takeIf { this?.useGpu != null },
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

/**
 * The model catalog and its residency.
 *
 * ```kotlin
 * RunAnywhere.models.download("qwen3-0.6b").collect { event -> report(event) }
 * RunAnywhere.models.load("qwen3-0.6b")
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
     * Fetch [id]'s bytes, reporting progress until the model is on disk.
     *
     * Cancelling the flow stops the transfer and preserves resume bytes.
     *
     * @throws SDKException when the model is unknown or the transfer fails.
     */
    public fun download(id: String): Flow<DownloadEvent> =
        flow {
            val model = get(id) ?: throw SDKException.modelNotFound(id)
            var extractingEmitted = false
            legacyDownloadModel(model) { progress ->
                if (progress.stage == DownloadStage.DOWNLOAD_STAGE_EXTRACTING) {
                    if (!extractingEmitted) {
                        extractingEmitted = true
                        emit(DownloadEvent.Extracting)
                    }
                } else {
                    emit(
                        DownloadEvent.Progress(
                            bytesDone = progress.bytes_downloaded,
                            bytesTotal = progress.total_bytes,
                            percent = progress.overall_progress,
                        ),
                    )
                }
            }
            emit(DownloadEvent.Completed(get(id) ?: model))
        }

    /**
     * Remove [id]'s files and return it to registered-not-downloaded.
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
     * `contextLength`, `threads`, and `useGpu` on [options] are not carried by
     * the commons load ABI yet and are ignored; only `framework` reaches
     * commons today.
     *
     * @throws SDKException when the model cannot be loaded.
     */
    public suspend fun load(id: String, options: LoadOptions? = null) {
        val registered = get(id)
        val category =
            registered?.category?.takeIf { it != ModelCategory.MODEL_CATEGORY_UNSPECIFIED }
                ?: ModelCategory.MODEL_CATEGORY_LANGUAGE
        val ignored = options.ignoredKnobs()
        if (ignored.isNotEmpty() && loadKnobsWarned.compareAndSet(false, true)) {
            modelsLogger.warn(
                "LoadOptions ${ignored.joinToString(", ")} ignored: " +
                    "the commons load ABI does not carry them",
            )
        }
        if (registered != null && registered.local_path.isEmpty()) {
            legacyDownloadModel(registered)
        }
        val result =
            legacyLoadModel(
                ModelLoadRequest(
                    model_id = id,
                    category = category,
                    framework = options?.framework ?: registered?.framework?.takeIf { it.value != 0 },
                    validate_availability = true,
                ),
            )
        result.error?.let { throw SDKException(it) }
    }

    /**
     * Release the model resident under [category], or every model when null.
     *
     * @throws SDKException when the unload fails.
     */
    public suspend fun unload(category: ModelCategory? = null) {
        val request =
            if (category == null) {
                ModelUnloadRequest(unload_all = true)
            } else {
                ModelUnloadRequest(category = category)
            }
        val result = legacyUnloadModel(request)
        result.error?.let { throw SDKException(it) }
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
