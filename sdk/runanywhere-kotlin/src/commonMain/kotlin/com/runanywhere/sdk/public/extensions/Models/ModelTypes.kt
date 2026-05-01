/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for model management.
 * These are thin wrappers over C++ types in rac_model_types.h
 * Business logic (format support, capability checks) is in C++.
 *
 * Mirrors Swift ModelTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Models

import com.runanywhere.sdk.public.extensions.LLM.ThinkingTagPattern
import kotlinx.serialization.Serializable

// MARK: - Model Source

/**
 * Source of model data (where the model info came from).
 * Mirrors Swift ModelSource exactly.
 *
 * GAP 01 Phase 3: `toProto()` / `fromProto()` keep this in lock-step with
 * `runanywhere.v1.ModelSource` in `idl/model_types.proto`.
 */
@Serializable
enum class ModelSource(
    val value: String,
) {
    /** Model info came from remote API (backend model catalog) */
    REMOTE("remote"),

    /** Model info was provided locally via SDK input (addModel calls) */
    LOCAL("local"),
    ;

    fun toProto(): ai.runanywhere.proto.v1.ModelSource =
        when (this) {
            REMOTE -> ai.runanywhere.proto.v1.ModelSource.MODEL_SOURCE_REMOTE
            LOCAL -> ai.runanywhere.proto.v1.ModelSource.MODEL_SOURCE_LOCAL
        }

    companion object {
        fun fromProto(proto: ai.runanywhere.proto.v1.ModelSource): ModelSource =
            when (proto) {
                ai.runanywhere.proto.v1.ModelSource.MODEL_SOURCE_REMOTE -> REMOTE
                ai.runanywhere.proto.v1.ModelSource.MODEL_SOURCE_LOCAL -> LOCAL
                ai.runanywhere.proto.v1.ModelSource.MODEL_SOURCE_UNSPECIFIED -> LOCAL
            }
    }
}

// MARK: - Model Format

/**
 * Model formats supported.
 *
 * GAP 01 Phase 3: subset of the IDL `runanywhere.v1.ModelFormat`; the proto
 * superset additionally declares {GGML, COREML, MLMODEL, MLPACKAGE, TFLITE,
 * SAFETENSORS, ZIP, FOLDER, PROPRIETARY}. Adding any of those here requires
 * no IDL edit; dropping a case here requires the IDL to drop it first (Wire
 * codegen fails otherwise).
 */
@Serializable
enum class ModelFormat(
    val value: String,
) {
    ONNX("onnx"),
    ORT("ort"),
    GGUF("gguf"),
    BIN("bin"),
    QNN_CONTEXT("qnn_context"),
    UNKNOWN("unknown"),
    ;

    fun toProto(): ai.runanywhere.proto.v1.ModelFormat =
        when (this) {
            ONNX -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_ONNX
            ORT -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_ORT
            GGUF -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_GGUF
            BIN -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_BIN
            QNN_CONTEXT -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_QNN_CONTEXT
            UNKNOWN -> ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_UNKNOWN
        }

    companion object {
        fun fromProto(proto: ai.runanywhere.proto.v1.ModelFormat): ModelFormat =
            when (proto) {
                ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_ONNX -> ONNX
                ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_ORT -> ORT
                ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_GGUF -> GGUF
                ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_BIN -> BIN
                ai.runanywhere.proto.v1.ModelFormat.MODEL_FORMAT_QNN_CONTEXT -> QNN_CONTEXT
                else -> UNKNOWN
            }
    }
}

// MARK: - Model Selection Context

/**
 * Context for model selection UI - determines which models to show.
 * Mirrors Swift ModelSelectionContext exactly.
 */
@Serializable
enum class ModelSelectionContext(
    val value: String,
) {
    /** Select a language model (LLM) */
    LLM("llm"),

    /** Select a speech-to-text model */
    STT("stt"),

    /** Select a text-to-speech model/voice */
    TTS("tts"),

    /** Select models for voice agent (all 3 types) */
    VOICE("voice"),

    /** Select an embedding model for RAG (ONNX) */
    RAG_EMBEDDING("ragEmbedding"),

    /** Select an LLM for RAG generation (llama.cpp) */
    RAG_LLM("ragLLM"),

    /** Select a vision language model (VLM) */
    VLM("vlm"),
    ;

    /** Human-readable title for the selection context */
    val title: String
        get() =
            when (this) {
                LLM -> "Select LLM Model"
                STT -> "Select STT Model"
                TTS -> "Select TTS Voice"
                VOICE -> "Select Voice Models"
                RAG_EMBEDDING -> "Select Embedding Model"
                RAG_LLM -> "Select LLM Model"
                VLM -> "Select Vision Model"
            }

    /** Check if a category is relevant for this selection context */
    fun isCategoryRelevant(category: ModelCategory): Boolean =
        when (this) {
            LLM -> category == ModelCategory.LANGUAGE
            STT -> category == ModelCategory.SPEECH_RECOGNITION
            TTS -> category == ModelCategory.SPEECH_SYNTHESIS
            VOICE ->
                category == ModelCategory.LANGUAGE ||
                    category == ModelCategory.SPEECH_RECOGNITION ||
                    category == ModelCategory.SPEECH_SYNTHESIS
            RAG_EMBEDDING -> category == ModelCategory.EMBEDDING
            RAG_LLM -> category == ModelCategory.LANGUAGE
            VLM ->
                category == ModelCategory.MULTIMODAL ||
                    category == ModelCategory.VISION
        }

    /** Check if a framework is relevant for this selection context */
    fun isFrameworkRelevant(framework: com.runanywhere.sdk.core.types.InferenceFramework): Boolean =
        when (this) {
            LLM ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.LLAMA_CPP ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.GENIE ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.FOUNDATION_MODELS
            STT ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX
            TTS ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.SYSTEM_TTS ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.FLUID_AUDIO
            VOICE ->
                LLM.isFrameworkRelevant(framework) ||
                    STT.isFrameworkRelevant(framework) ||
                    TTS.isFrameworkRelevant(framework)
            RAG_EMBEDDING ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX
            RAG_LLM ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.LLAMA_CPP
            VLM ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.LLAMA_CPP
        }
}

// MARK: - Model Category

/**
 * Defines the category/type of a model based on its input/output modality.
 *
 * GAP 01 Phase 3: the proto superset adds `VOICE_ACTIVITY_DETECTION`; Kotlin
 * does not yet expose VAD as its own category (uses AUDIO) but the bijection
 * is kept up-to-date for future expansion without an IDL change.
 */
@Serializable
enum class ModelCategory(
    val value: String,
) {
    LANGUAGE("language"), // Text-to-text models (LLMs)
    SPEECH_RECOGNITION("speech-recognition"), // Voice-to-text models (ASR)
    SPEECH_SYNTHESIS("speech-synthesis"), // Text-to-voice models (TTS)
    VISION("vision"), // Image understanding models
    IMAGE_GENERATION("image-generation"), // Text-to-image models
    MULTIMODAL("multimodal"), // Models that handle multiple modalities
    AUDIO("audio"), // Audio processing (diarization, etc.)
    EMBEDDING("embedding"), // Embedding models (RAG, semantic search)
    ;

    /** Whether this category typically requires context length */
    val requiresContextLength: Boolean
        get() = this == LANGUAGE || this == MULTIMODAL

    /** Whether this category typically supports thinking/reasoning */
    val supportsThinking: Boolean
        get() = this == LANGUAGE || this == MULTIMODAL

    fun toProto(): ai.runanywhere.proto.v1.ModelCategory =
        when (this) {
            LANGUAGE -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_LANGUAGE
            SPEECH_RECOGNITION -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
            SPEECH_SYNTHESIS -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
            VISION -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_VISION
            IMAGE_GENERATION -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION
            MULTIMODAL -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_MULTIMODAL
            AUDIO -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_AUDIO
            EMBEDDING -> ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_EMBEDDING
        }

    companion object {
        fun fromProto(proto: ai.runanywhere.proto.v1.ModelCategory): ModelCategory =
            when (proto) {
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_LANGUAGE -> LANGUAGE
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> SPEECH_RECOGNITION
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> SPEECH_SYNTHESIS
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_VISION -> VISION
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION -> IMAGE_GENERATION
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_MULTIMODAL -> MULTIMODAL
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_AUDIO -> AUDIO
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_EMBEDDING -> EMBEDDING
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> AUDIO // collapse into AUDIO for now
                ai.runanywhere.proto.v1.ModelCategory.MODEL_CATEGORY_UNSPECIFIED -> AUDIO // defensive
            }
    }
}

// MARK: - Archive Types

/**
 * Supported archive formats for model packaging.
 * Mirrors Swift ArchiveType exactly.
 */
@Serializable
enum class ArchiveType(
    val value: String,
) {
    ZIP("zip"),
    TAR_BZ2("tar.bz2"),
    TAR_GZ("tar.gz"),
    TAR_XZ("tar.xz"),
    ;

    /** File extension for this archive type */
    val fileExtension: String get() = value

    fun toProto(): ai.runanywhere.proto.v1.ArchiveType =
        when (this) {
            ZIP -> ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_ZIP
            TAR_BZ2 -> ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_BZ2
            TAR_GZ -> ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_GZ
            TAR_XZ -> ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_XZ
        }

    companion object {
        /** Detect archive type from URL path */
        fun from(path: String): ArchiveType? {
            val lowercased = path.lowercase()
            return when {
                lowercased.endsWith(".tar.bz2") || lowercased.endsWith(".tbz2") -> TAR_BZ2
                lowercased.endsWith(".tar.gz") || lowercased.endsWith(".tgz") -> TAR_GZ
                lowercased.endsWith(".tar.xz") || lowercased.endsWith(".txz") -> TAR_XZ
                lowercased.endsWith(".zip") -> ZIP
                else -> null
            }
        }

        fun fromProto(proto: ai.runanywhere.proto.v1.ArchiveType): ArchiveType? =
            when (proto) {
                ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_ZIP -> ZIP
                ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> TAR_BZ2
                ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_GZ -> TAR_GZ
                ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_TAR_XZ -> TAR_XZ
                ai.runanywhere.proto.v1.ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> null
            }
    }
}

/**
 * Describes the internal structure of an archive after extraction.
 * Mirrors Swift ArchiveStructure exactly.
 */
@Serializable
enum class ArchiveStructure(
    val value: String,
) {
    SINGLE_FILE_NESTED("singleFileNested"),
    DIRECTORY_BASED("directoryBased"),
    NESTED_DIRECTORY("nestedDirectory"),
    UNKNOWN("unknown"),
    ;

    fun toProto(): ai.runanywhere.proto.v1.ArchiveStructure =
        when (this) {
            SINGLE_FILE_NESTED -> ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED
            DIRECTORY_BASED -> ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED
            NESTED_DIRECTORY -> ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY
            UNKNOWN -> ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN
        }

    companion object {
        fun fromProto(proto: ai.runanywhere.proto.v1.ArchiveStructure): ArchiveStructure =
            when (proto) {
                ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED -> SINGLE_FILE_NESTED
                ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED -> DIRECTORY_BASED
                ai.runanywhere.proto.v1.ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY -> NESTED_DIRECTORY
                else -> UNKNOWN
            }
    }
}

// MARK: - Expected Model Files

/**
 * Describes what files are expected after model extraction/download.
 * Mirrors Swift ExpectedModelFiles exactly.
 */
@Serializable
data class ExpectedModelFiles(
    val requiredPatterns: List<String> = emptyList(),
    val optionalPatterns: List<String> = emptyList(),
    val description: String? = null,
) {
    companion object {
        val NONE = ExpectedModelFiles()
    }
}

/**
 * Describes a file that needs to be downloaded as part of a multi-file model.
 * Mirrors Swift ModelFileDescriptor exactly.
 */
@Serializable
data class ModelFileDescriptor(
    /** Full URL to download this file from */
    val url: String,
    /** Filename to save as (e.g., "model.gguf" or "mmproj.gguf") */
    val filename: String,
    /** Whether this file is required for the model to work */
    val isRequired: Boolean = true,
    /**
     * Optional lowercase hex SHA-256 checksum of the downloaded bytes.
     * When populated, the native download runner verifies the hash
     * inline on the write path and fails with `RAC_HTTP_DL_CHECKSUM_FAILED`
     * if the bytes do not match.
     */
    val checksumSha256: String? = null,
) {
    /** Legacy compatibility */
    val relativePath: String get() = url.substringAfterLast('/').substringBefore('?')
    val destinationPath: String get() = filename
}

// MARK: - Model Artifact Type

/**
 * Describes how a model is packaged and what processing is needed after download.
 * Mirrors Swift ModelArtifactType exactly.
 */
@Serializable
sealed class ModelArtifactType {
    @Serializable
    data class SingleFile(
        val expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
    ) : ModelArtifactType()

    @Serializable
    data class Archive(
        val archiveType: ArchiveType,
        val structure: ArchiveStructure,
        val expectedFiles: ExpectedModelFiles = ExpectedModelFiles.NONE,
    ) : ModelArtifactType()

    @Serializable
    data class MultiFile(
        val files: List<ModelFileDescriptor>,
    ) : ModelArtifactType()

    @Serializable
    data class Custom(
        val strategyId: String,
    ) : ModelArtifactType()

    @Serializable
    data object BuiltIn : ModelArtifactType()

    val requiresExtraction: Boolean
        get() = this is Archive

    val requiresDownload: Boolean
        get() = this !is BuiltIn

    val expectedFilesValue: ExpectedModelFiles
        get() =
            when (this) {
                is SingleFile -> expectedFiles
                is Archive -> expectedFiles
                else -> ExpectedModelFiles.NONE
            }

    val displayName: String
        get() =
            when (this) {
                is SingleFile -> "Single File"
                is Archive -> "${archiveType.value.uppercase()} Archive"
                is MultiFile -> "Multi-File (${files.size} files)"
                is Custom -> "Custom ($strategyId)"
                is BuiltIn -> "Built-in"
            }

    companion object {
        /** Infer artifact type from download URL */
        @Suppress("UNUSED_PARAMETER")
        fun infer(url: String?, format: ModelFormat): ModelArtifactType {
            // format parameter reserved for future use when format-specific inference is needed
            if (url == null) return SingleFile()
            val archiveType = ArchiveType.from(url)
            return if (archiveType != null) {
                Archive(archiveType, ArchiveStructure.UNKNOWN)
            } else {
                SingleFile()
            }
        }
    }
}

// MARK: - Model Info

/**
 * Information about a model - in-memory entity.
 * Mirrors Swift ModelInfo exactly.
 */
@Serializable
data class ModelInfo(
    // Essential identifiers
    val id: String,
    val name: String,
    val category: ModelCategory,
    // Format and location
    val format: ModelFormat,
    val downloadURL: String? = null,
    var localPath: String? = null,
    // Artifact type
    val artifactType: ModelArtifactType = ModelArtifactType.SingleFile(),
    // Size information
    val downloadSize: Long? = null,
    // Framework
    val framework: com.runanywhere.sdk.core.types.InferenceFramework,
    // Model-specific capabilities
    val contextLength: Int? = null,
    val supportsThinking: Boolean = false,
    val supportsLora: Boolean = false,
    val thinkingPattern: ThinkingTagPattern? = null,
    // Optional metadata
    val description: String? = null,
    /**
     * Optional lowercase hex SHA-256 checksum of the downloaded artifact.
     * Populated from the provider manifest (or `ModelFileDescriptor.checksumSha256`
     * for multi-file models) and forwarded to the native download runner
     * for inline integrity verification.
     */
    val checksumSha256: String? = null,
    // Tracking fields
    val source: ModelSource = ModelSource.REMOTE,
    val createdAt: Long = System.currentTimeMillis(),
    var updatedAt: Long = System.currentTimeMillis(),
) {
    /** Whether this model is downloaded and available locally */
    val isDownloaded: Boolean
        get() {
            val path = localPath ?: return false
            if (path.startsWith("builtin://")) return true
            // Actual file check would be done in platform-specific code
            return path.isNotEmpty()
        }

    /** Whether this model is available for use */
    val isAvailable: Boolean get() = isDownloaded

    /** Whether this is a built-in platform model */
    val isBuiltIn: Boolean
        get() {
            if (artifactType is ModelArtifactType.BuiltIn) return true
            val path = localPath
            if (path != null && path.startsWith("builtin://")) return true
            return framework == com.runanywhere.sdk.core.types.InferenceFramework.FOUNDATION_MODELS ||
                framework == com.runanywhere.sdk.core.types.InferenceFramework.SYSTEM_TTS
        }
}

// MARK: - Download Progress
//
// Canonical `DownloadProgress`, `DownloadStage`, `DownloadState` are now
// proto-generated in `ai.runanywhere.proto.v1` (see
// `idl/download_service.proto`). This file previously held hand-rolled
// duplicates; import the proto types directly instead.
