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
// KOT-15: `ModelSelectionContext` lived here as a UI filter helper but had
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

val InferenceFramework.rawValue: String
    get() =
        when (this) {
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX"
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "LlamaCpp"
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "FoundationModels"
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "SystemTTS"
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "FluidAudio"
            InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "CoreML"
            InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "MLX"
            InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT_COREML -> "WhisperKitCoreML"
            InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> "MetalRT"
            InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> "Genie"
            InferenceFramework.INFERENCE_FRAMEWORK_TFLITE -> "TFLite"
            InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH -> "ExecuTorch"
            InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE -> "MediaPipe"
            InferenceFramework.INFERENCE_FRAMEWORK_MLC -> "MLC"
            InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM -> "PicoLLM"
            InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> "PiperTTS"
            InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT -> "WhisperKit"
            InferenceFramework.INFERENCE_FRAMEWORK_OPENAI_WHISPER -> "OpenAIWhisper"
            InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS -> "SwiftTransformers"
            InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> "BuiltIn"
            InferenceFramework.INFERENCE_FRAMEWORK_NONE -> "None"
            InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> "Unknown"
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa"
            InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED -> "Unspecified"
        }

val InferenceFramework.displayName: String
    get() =
        when (this) {
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX Runtime"
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "llama.cpp"
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Foundation Models"
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "System TTS"
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "FluidAudio"
            InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> "Qualcomm Genie"
            InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> "Built-in"
            InferenceFramework.INFERENCE_FRAMEWORK_NONE -> "None"
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa-ONNX"
            InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED -> "Unspecified"
            else -> rawValue
        }

val InferenceFramework.analyticsKey: String
    get() =
        rawValue
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

fun archiveTypeFromPath(path: String): ArchiveType? {
    val lowercased = path.lowercase()
    return when {
        lowercased.endsWith(".tar.bz2") || lowercased.endsWith(".tbz2") -> ArchiveType.ARCHIVE_TYPE_TAR_BZ2
        lowercased.endsWith(".tar.gz") || lowercased.endsWith(".tgz") -> ArchiveType.ARCHIVE_TYPE_TAR_GZ
        lowercased.endsWith(".tar.xz") || lowercased.endsWith(".txz") -> ArchiveType.ARCHIVE_TYPE_TAR_XZ
        lowercased.endsWith(".zip") -> ArchiveType.ARCHIVE_TYPE_ZIP
        else -> null
    }
}
