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

import ai.runanywhere.proto.v1.ExpectedModelFiles
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAApplyRequest
import ai.runanywhere.proto.v1.LoRAApplyResult
import ai.runanywhere.proto.v1.LoRARemoveRequest
import ai.runanywhere.proto.v1.LoRAState
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogGetResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedResult
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoMetadata
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.SingleFileArtifact
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.utils.getCurrentTimeMillis

/**
 * Capability namespace for LoRA adapter management.
 *
 * This surface intentionally follows the generated LoRA service messages:
 * runtime apply/remove/list/state, catalog list/query/get, and download
 * completion all use request/result/state types generated from
 * `lora_options.proto`. Legacy `load`/`clear` compatibility helpers were
 * removed with the corresponding C ABI symbols.
 */
expect class LoRA internal constructor() {
    /** Apply one or more LoRA adapters to the current LLM session. */
    suspend fun apply(request: LoRAApplyRequest): LoRAApplyResult

    /** Remove adapters by generated request semantics, including `clear_all`. */
    suspend fun remove(request: LoRARemoveRequest): LoRAState

    /** Return the current loaded-adapter snapshot from native state. */
    suspend fun list(request: LoRAState): LoRAState

    /** Return the logical LoRA service state from native state. */
    suspend fun state(request: LoRAState): LoRAState

    /** Pre-flight compatibility check for an adapter config and current base model. */
    suspend fun checkCompatibility(config: LoRAAdapterConfig): LoraCompatibilityResult

    /** Register an adapter catalog entry. */
    suspend fun register(entry: LoraAdapterCatalogEntry): LoraAdapterCatalogEntry

    /** List catalog entries using the generated catalog request/result ABI. */
    suspend fun listCatalog(
        request: LoraAdapterCatalogListRequest = LoraAdapterCatalogListRequest(),
    ): LoraAdapterCatalogListResult

    /** Query catalog entries using generated filter semantics owned by commons. */
    suspend fun queryCatalog(query: LoraAdapterCatalogQuery): LoraAdapterCatalogListResult

    /** Fetch one catalog entry by generated request semantics. */
    suspend fun getCatalogEntry(request: LoraAdapterCatalogGetRequest): LoraAdapterCatalogGetResult

    /** Persist native-reported completion state after Android has fetched bytes. */
    suspend fun markDownloadCompleted(
        request: LoraAdapterDownloadCompletedRequest,
    ): LoraAdapterDownloadCompletedResult
}

/** Public capability accessor: `RunAnywhere.lora.apply(request)`. */
expect val RunAnywhere.lora: LoRA

private const val LORA_ARTIFACT_MODEL_ID_PREFIX = "lora-adapter:"
private const val LORA_ARTIFACT_TAG = "lora-adapter"

/**
 * Stable model-registry id used for a LoRA adapter artifact.
 *
 * The adapter remains a LoRA catalog entry for apply/remove semantics, while
 * its bytes are represented as a generated model artifact so download/storage
 * policy stays on the generated registry/download path.
 */
val LoraAdapterCatalogEntry.loraArtifactModelId: String
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
): ModelInfo {
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

    return ModelInfo(
        id = loraArtifactModelId,
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
 * Register both the generated LoRA catalog entry and its generated download
 * artifact record. This does not fetch bytes.
 */
suspend fun RunAnywhere.registerLoraArtifact(entry: LoraAdapterCatalogEntry): ModelInfo {
    val registeredEntry = lora.register(entry)
    val artifact = registeredEntry.toLoraArtifactModelInfo()
    registerModelInternal(artifact)
    return artifact
}
