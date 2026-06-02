/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelFormat/Artifact inference bridge for CppBridge.
 *
 * Wraps the commons-owned URL-heuristic proto ABI
 * (`rac_model_format_from_url_proto` + `rac_artifact_infer_from_url_proto`)
 * so every SDK shares one implementation of the trailing-suffix parsing
 * that used to live as hand-rolled Dart/Kotlin helpers.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ArchiveArtifact
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.ArtifactInferFromUrlRequest
import ai.runanywhere.proto.v1.ArtifactInferFromUrlResult
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelFormatFromUrlRequest
import ai.runanywhere.proto.v1.ModelFormatFromUrlResult
import ai.runanywhere.proto.v1.SingleFileArtifact
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * Bridge wrapper over the two commons URL-inference proto APIs.
 *
 * Returns conservative defaults (`MODEL_FORMAT_UNKNOWN` / unchanged
 * `ModelInfo`) whenever the native proto ABI is unavailable or the
 * decode fails — this keeps pre-init / unit-test flows working without
 * the JNI loaded.
 */
internal object ModelTypesCppBridge {
    private const val TAG = "CppBridge/ModelTypesCppBridge"

    /**
     * Infer the primary model format from a portable URL or file-path.
     *
     * Falls back to `MODEL_FORMAT_UNKNOWN` when commons returns the
     * proto `UNSPECIFIED` sentinel, so the Kotlin API contract (which
     * predates proto3 zero-defaults) stays stable for existing callers.
     */
    fun formatFromUrl(url: String): ModelFormat {
        val result = formatFromUrlProto(url) ?: return ModelFormat.MODEL_FORMAT_UNKNOWN
        return when (result.format) {
            ModelFormat.MODEL_FORMAT_UNSPECIFIED -> ModelFormat.MODEL_FORMAT_UNKNOWN
            else -> result.format
        }
    }

    /**
     * Update the artifact-classification fields on [modelInfo] based on
     * a URL/file-path. Preserves any caller-supplied `artifact_type` on
     * the existing info when the caller has explicitly set it; otherwise
     * uses the inferred artifact type.
     *
     * For archive URLs, sets `archive = ArchiveArtifact(...)` and clears
     * `single_file`; for single-file URLs, sets `single_file =
     * SingleFileArtifact()` and clears `archive`. `multi_file` and
     * related fields are left untouched — those are populated by
     * `registerMultiFileModel` or server-side metadata.
     */
    fun applyInferredArtifact(modelInfo: RAModelInfo, url: String): RAModelInfo {
        val result = artifactInferFromUrlProto(url, modelInfo.id)
        val existingType = modelInfo.artifact_type ?: ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED
        if (result == null) {
            // Native ABI unavailable — preserve existing info, fall back to
            // a single-file artifact when nothing is set so the
            // registerModel path still produces a valid ModelInfo.
            if (existingType == ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED &&
                modelInfo.single_file == null &&
                modelInfo.archive == null &&
                modelInfo.multi_file == null
            ) {
                return modelInfo.copy(
                    single_file = SingleFileArtifact(),
                    artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
                )
            }
            return modelInfo
        }

        val inferredType = result.artifact_type
        val effectiveType =
            if (existingType != ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED) {
                existingType
            } else {
                inferredType
            }

        return if (result.archive_type != ArchiveType.ARCHIVE_TYPE_UNSPECIFIED) {
            modelInfo.copy(
                single_file = null,
                archive =
                    ArchiveArtifact(
                        type = result.archive_type,
                        structure = result.archive_structure,
                    ),
                artifact_type = effectiveType,
            )
        } else {
            modelInfo.copy(
                single_file = SingleFileArtifact(),
                archive = null,
                artifact_type =
                    if (effectiveType == ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED) {
                        ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE
                    } else {
                        effectiveType
                    },
            )
        }
    }

    // Proto ABI

    private fun formatFromUrlProto(url: String): ModelFormatFromUrlResult? {
        val request = ModelFormatFromUrlRequest(url = url)
        val bytes =
            callProtoBytes("racModelFormatFromUrlProto") {
                RunAnywhereBridge.racModelFormatFromUrlProto(
                    ModelFormatFromUrlRequest.ADAPTER.encode(request),
                )
            } ?: return null

        return try {
            ModelFormatFromUrlResult.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelFormatFromUrlResult proto: ${e.message}")
            null
        }
    }

    private fun artifactInferFromUrlProto(url: String, modelId: String): ArtifactInferFromUrlResult? {
        val request = ArtifactInferFromUrlRequest(url = url, model_id = modelId)
        val bytes =
            callProtoBytes("racArtifactInferFromUrlProto") {
                RunAnywhereBridge.racArtifactInferFromUrlProto(
                    ArtifactInferFromUrlRequest.ADAPTER.encode(request),
                )
            } ?: return null

        return try {
            ArtifactInferFromUrlResult.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ArtifactInferFromUrlResult proto: ${e.message}")
            null
        }
    }

    private fun callProtoBytes(operation: String, block: () -> ByteArray?): ByteArray? =
        try {
            block()
        } catch (e: UnsatisfiedLinkError) {
            log(LogLevel.DEBUG, "Native format/artifact proto ABI unavailable for $operation: ${e.message}")
            null
        }

    // Logging

    private enum class LogLevel { DEBUG, INFO, WARN, ERROR }

    private fun log(level: LogLevel, message: String) {
        val adapterLevel =
            when (level) {
                LogLevel.DEBUG -> CppBridgePlatformAdapter.LogLevel.DEBUG
                LogLevel.INFO -> CppBridgePlatformAdapter.LogLevel.INFO
                LogLevel.WARN -> CppBridgePlatformAdapter.LogLevel.WARN
                LogLevel.ERROR -> CppBridgePlatformAdapter.LogLevel.ERROR
            }
        CppBridgePlatformAdapter.logCallback(adapterLevel, TAG, message)
    }
}
