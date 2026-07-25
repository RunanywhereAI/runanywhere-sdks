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
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.net.URI
// `ModelSelectionContext` lived here as a UI filter helper but had
// zero consumers inside the SDK. It was moved to the Android example app at
// `examples/android/RunAnywhereAI/.../models/ModelSelectionContext.kt`.

val ModelCategory.requiresContextLength: Boolean
    get() =
        runCatching { RunAnywhereBridge.racModelCategoryRequiresContextLength(value) }
            .getOrElse { requiresContextLengthFallback() }

val ModelCategory.supportsThinking: Boolean
    get() =
        runCatching { RunAnywhereBridge.racModelCategorySupportsThinking(value) }
            .getOrElse { requiresContextLengthFallback() }

/**
 * Framework the SDK falls back to when a category has no explicit model
 * framework resolved (e.g. a pending UI selection that has not yet matched a
 * catalogued model). Mirrors commons' `rac_model_category_default_framework`
 * and Swift's `RAModelCategory.defaultFramework`.
 */
val ModelCategory.defaultFramework: InferenceFramework
    get() =
        runCatching {
            InferenceFramework.fromValue(RunAnywhereBridge.racModelCategoryDefaultFramework(value))
                ?: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
        }.getOrElse { defaultFrameworkFallback() }

private fun ModelCategory.requiresContextLengthFallback(): Boolean =
    this == ModelCategory.MODEL_CATEGORY_LANGUAGE ||
        this == ModelCategory.MODEL_CATEGORY_MULTIMODAL

private fun ModelCategory.defaultFrameworkFallback(): InferenceFramework =
    when (this) {
        ModelCategory.MODEL_CATEGORY_LANGUAGE,
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        -> InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        ModelCategory.MODEL_CATEGORY_EMBEDDING,
        ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
        -> InferenceFramework.INFERENCE_FRAMEWORK_ONNX
        else -> InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
    }

/**
 * Canonical wire string for a framework (e.g. "LlamaCpp", "ONNX"). Routes
 * through commons' `rac_framework_raw_value` so the Kotlin, Swift, and C++
 * tables can never drift. Mirrors Swift's `RAInferenceFramework.wireString`
 * surface. Falls back to the proto enum name when the native lib is
 * unavailable (e.g. non-inference unit-test contexts).
 */
val InferenceFramework.wireString: String
    get() = RunAnywhereBridge.racFrameworkRawValue(value) ?: name

/**
 * Human-readable display name from commons'
 * `rac_inference_framework_display_name` (e.g. "llama.cpp",
 * "Foundation Models"). Mirrors Swift's `RAInferenceFramework.displayName`.
 * Falls back to [wireString] when the native lib is unavailable.
 */
val InferenceFramework.displayName: String
    get() = RunAnywhereBridge.racInferenceFrameworkDisplayName(value) ?: wireString

/**
 * Snake_case analytics key from commons'
 * `rac_inference_framework_analytics_key` (e.g. "llama_cpp",
 * "foundation_models"). Mirrors Swift's `RAInferenceFramework.analyticsKey`.
 * Falls back to a local normalization of [wireString] when the native lib is
 * unavailable.
 */
val InferenceFramework.analyticsKey: String
    get() =
        RunAnywhereBridge.racInferenceFrameworkAnalyticsKey(value)
            ?: wireString
                .replace(Regex("([a-z])([A-Z])"), "$1_$2")
                .replace('-', '_')
                .lowercase()

val InferenceFramework.Companion.knownCases: List<InferenceFramework>
    get() =
        listOf(
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS,
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO,
            InferenceFramework.INFERENCE_FRAMEWORK_COREML,
            InferenceFramework.INFERENCE_FRAMEWORK_MLX,
            InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
            InferenceFramework.INFERENCE_FRAMEWORK_TFLITE,
            InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH,
            InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE,
            InferenceFramework.INFERENCE_FRAMEWORK_MLC,
            InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM,
            InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS,
            InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS,
            InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN,
            InferenceFramework.INFERENCE_FRAMEWORK_NONE,
            InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
        )

fun InferenceFramework.Companion.fromCaseInsensitive(value: String): InferenceFramework? {
    val normalized = value.trim().lowercase()
    if (normalized.isEmpty()) return null
    return knownCases.firstOrNull { framework ->
        framework.name.lowercase() == normalized ||
            framework.wireString.lowercase() == normalized ||
            framework.displayName.lowercase() == normalized ||
            framework.analyticsKey.lowercase() == normalized
    }
}

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

fun ArchiveType.Companion.from(url: URI): ArchiveType? =
    archiveTypeFromPath(url.path.orEmpty())

/**
 * Detect the archive type for a URL/file-path. Routes through commons'
 * `rac_archive_type_from_path` (the same detector Swift's `ArchiveType.from(url:)`
 * wraps) so archive sniffing can never drift between SDKs. Returns null when
 * the path is not a recognized archive.
 */
internal fun archiveTypeFromPath(path: String): ArchiveType? {
    val protoValue = RunAnywhereBridge.racArchiveTypeFromPath(path)
    return if (protoValue < 0) null else ArchiveType.fromValue(protoValue)
}
