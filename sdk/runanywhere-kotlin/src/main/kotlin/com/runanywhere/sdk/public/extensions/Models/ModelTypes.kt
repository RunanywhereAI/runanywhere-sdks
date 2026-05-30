/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kotlin helpers around proto-generated model contracts.
 */

package com.runanywhere.sdk.public.extensions.Models

import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFormat
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
// `ModelSelectionContext` lived here as a UI filter helper but had
// zero consumers inside the SDK. It was moved to the Android example app at
// `examples/android/RunAnywhereAI/.../models/ModelSelectionContext.kt`.

val ModelCategory.requiresContextLength: Boolean
    get() =
        this == ModelCategory.MODEL_CATEGORY_LANGUAGE ||
            this == ModelCategory.MODEL_CATEGORY_MULTIMODAL

val ModelCategory.supportsThinking: Boolean
    get() = requiresContextLength

/**
 * Framework the SDK falls back to when a category has no explicit model
 * framework resolved (e.g. a pending UI selection that has not yet matched a
 * catalogued model). Mirrors commons' `rac_model_category_default_framework`
 * and Swift's `RAModelCategory.defaultFramework`.
 */
val ModelCategory.defaultFramework: InferenceFramework
    get() =
        when (this) {
            ModelCategory.MODEL_CATEGORY_LANGUAGE,
            ModelCategory.MODEL_CATEGORY_MULTIMODAL,
            -> InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            ModelCategory.MODEL_CATEGORY_EMBEDDING,
            ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
            -> InferenceFramework.INFERENCE_FRAMEWORK_ONNX
            else -> InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
        }

val ModelCategory.catalogKey: String
    get() =
        when (this) {
            ModelCategory.MODEL_CATEGORY_LANGUAGE -> "language"
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> "speech-recognition"
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> "speech-synthesis"
            ModelCategory.MODEL_CATEGORY_VISION -> "vision"
            ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION -> "image-generation"
            ModelCategory.MODEL_CATEGORY_MULTIMODAL -> "multimodal"
            ModelCategory.MODEL_CATEGORY_AUDIO -> "audio"
            ModelCategory.MODEL_CATEGORY_EMBEDDING -> "embedding"
            ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> "voice-activity-detection"
            ModelCategory.MODEL_CATEGORY_UNSPECIFIED -> "unspecified"
        }

val ModelFormat.catalogKey: String
    get() =
        when (this) {
            ModelFormat.MODEL_FORMAT_GGUF -> "gguf"
            ModelFormat.MODEL_FORMAT_GGML -> "ggml"
            ModelFormat.MODEL_FORMAT_ONNX -> "onnx"
            ModelFormat.MODEL_FORMAT_ORT -> "ort"
            ModelFormat.MODEL_FORMAT_BIN -> "bin"
            ModelFormat.MODEL_FORMAT_COREML -> "coreml"
            ModelFormat.MODEL_FORMAT_MLMODEL -> "mlmodel"
            ModelFormat.MODEL_FORMAT_MLPACKAGE -> "mlpackage"
            ModelFormat.MODEL_FORMAT_TFLITE -> "tflite"
            ModelFormat.MODEL_FORMAT_SAFETENSORS -> "safetensors"
            ModelFormat.MODEL_FORMAT_QNN_CONTEXT -> "qnn_context"
            ModelFormat.MODEL_FORMAT_ZIP -> "zip"
            ModelFormat.MODEL_FORMAT_FOLDER -> "folder"
            ModelFormat.MODEL_FORMAT_PROPRIETARY -> "proprietary"
            ModelFormat.MODEL_FORMAT_UNKNOWN -> "unknown"
            ModelFormat.MODEL_FORMAT_UNSPECIFIED -> "unspecified"
        }

/**
 * Canonical wire string for a framework (e.g. "LlamaCpp", "ONNX"). Routes
 * through commons' `rac_framework_raw_value` so the Kotlin, Swift, and C++
 * tables can never drift. Mirrors Swift's `RAInferenceFramework.rawValue`
 * surface. Falls back to the proto enum name when the native lib is
 * unavailable (e.g. non-inference unit-test contexts).
 */
val InferenceFramework.rawValue: String
    get() = RunAnywhereBridge.racFrameworkRawValue(value) ?: name

/**
 * Human-readable display name from commons'
 * `rac_inference_framework_display_name` (e.g. "llama.cpp",
 * "Foundation Models"). Mirrors Swift's `RAInferenceFramework.displayName`.
 * Falls back to [rawValue] when the native lib is unavailable.
 */
val InferenceFramework.displayName: String
    get() = RunAnywhereBridge.racInferenceFrameworkDisplayName(value) ?: rawValue

/**
 * Snake_case analytics key from commons'
 * `rac_inference_framework_analytics_key` (e.g. "llama_cpp",
 * "foundation_models"). Mirrors Swift's `RAInferenceFramework.analyticsKey`.
 * Falls back to a local normalization of [rawValue] when the native lib is
 * unavailable.
 */
val InferenceFramework.analyticsKey: String
    get() =
        RunAnywhereBridge.racInferenceFrameworkAnalyticsKey(value)
            ?: rawValue
                .replace(Regex("([a-z])([A-Z])"), "$1_$2")
                .replace('-', '_')
                .lowercase()

val ArchiveType.fileExtension: String
    get() =
        when (this) {
            ArchiveType.ARCHIVE_TYPE_ZIP -> "zip"
            ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> "tar.bz2"
            ArchiveType.ARCHIVE_TYPE_TAR_GZ -> "tar.gz"
            ArchiveType.ARCHIVE_TYPE_TAR_XZ -> "tar.xz"
            ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> ""
        }

val ModelArtifactType.displayName: String
    get() =
        when (this) {
            ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE -> "Single File"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE -> "TAR.GZ Archive"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY -> "Directory"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE -> "ZIP Archive"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM -> "Custom"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE -> "Archive"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE -> "Multi-File"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN -> "Built-in"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE -> "TAR.BZ2 Archive"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE -> "TAR.XZ Archive"
            ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED -> "Unspecified"
        }

/**
 * Detect the archive type for a URL/file-path. Routes through commons'
 * `rac_archive_type_from_path` (the same detector Swift's `ArchiveType.from(url:)`
 * wraps) so archive sniffing can never drift between SDKs. Returns null when
 * the path is not a recognized archive.
 */
fun archiveTypeFromPath(path: String): ArchiveType? {
    val protoValue = RunAnywhereBridge.racArchiveTypeFromPath(path)
    return if (protoValue < 0) null else ArchiveType.fromValue(protoValue)
}
