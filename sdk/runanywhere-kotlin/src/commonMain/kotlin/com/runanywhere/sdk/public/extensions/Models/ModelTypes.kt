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
 */
@Serializable
enum class ModelSource(
    val value: String,
) {
    /** Model info came from remote API (backend model catalog) */
    REMOTE("remote"),

    /** Model info was provided locally via SDK input (addModel calls) */
    LOCAL("local"),
}

// MARK: - Model Format

/**
 * Model formats supported.
 * Mirrors Swift ModelFormat exactly.
 */
@Serializable
enum class ModelFormat(
    val value: String,
) {
    ONNX("onnx"),
    ORT("ort"),
    GGUF("gguf"),
    BIN("bin"),
    UNKNOWN("unknown"),
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

    /** Select an image generation model (Diffusion) */
    DIFFUSION("diffusion"),
    ;

    /** Human-readable title for the selection context */
    val title: String
        get() =
            when (this) {
                LLM -> "Select LLM Model"
                STT -> "Select STT Model"
                TTS -> "Select TTS Voice"
                VOICE -> "Select Voice Models"
                DIFFUSION -> "Select Diffusion Model"
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
            DIFFUSION -> category == ModelCategory.IMAGE_GENERATION
        }

    /** Check if a framework is relevant for this selection context */
    fun isFrameworkRelevant(framework: com.runanywhere.sdk.core.types.InferenceFramework): Boolean =
        when (this) {
            LLM ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.LLAMA_CPP ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.FOUNDATION_MODELS
            STT -> framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX
            TTS ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.SYSTEM_TTS ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.FLUID_AUDIO
            VOICE ->
                LLM.isFrameworkRelevant(framework) ||
                    STT.isFrameworkRelevant(framework) ||
                    TTS.isFrameworkRelevant(framework)
            DIFFUSION ->
                framework == com.runanywhere.sdk.core.types.InferenceFramework.ONNX ||
                    framework == com.runanywhere.sdk.core.types.InferenceFramework.COREML
        }
}

// MARK: - Model Category

/**
 * Defines the category/type of a model based on its input/output modality.
 * Mirrors Swift ModelCategory exactly.
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
    ;

    /** Whether this category typically requires context length */
    val requiresContextLength: Boolean
        get() = this == LANGUAGE || this == MULTIMODAL

    /** Whether this category typically supports thinking/reasoning */
    val supportsThinking: Boolean
        get() = this == LANGUAGE || this == MULTIMODAL
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
    val relativePath: String,
    val destinationPath: String,
    val isRequired: Boolean = true,
)

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
    val thinkingPattern: ThinkingTagPattern? = null,
    // Optional metadata
    val description: String? = null,
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

/**
 * Progress information for model downloads.
 */
@Serializable
data class DownloadProgress(
    /** Model ID being downloaded */
    val modelId: String,
    /** Progress percentage (0.0 to 1.0) */
    val progress: Float,
    /** Bytes downloaded so far */
    val bytesDownloaded: Long,
    /** Total bytes to download (null if unknown) */
    val totalBytes: Long?,
    /** Download state */
    val state: DownloadState,
    /** Error message if state is ERROR */
    val error: String? = null,
)

/**
 * State of a model download.
 */
@Serializable
enum class DownloadState {
    PENDING,
    DOWNLOADING,
    EXTRACTING,
    COMPLETED,
    ERROR,
    CANCELLED,
}
