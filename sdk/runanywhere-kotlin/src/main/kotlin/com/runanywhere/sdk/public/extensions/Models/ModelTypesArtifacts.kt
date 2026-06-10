/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Artifact / archive / expected-files helpers for the proto-generated model
 * contract types. Mirrors the Swift counterpart at
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes+Artifacts.swift`.
 *
 * The `RA*` typealiases are pending; for now these helpers operate
 * on the Wire-generated proto types directly.
 *
 * NOTE: filesystem-aware checks (`isDownloadedOnDisk`) defer to the proto's
 * `is_downloaded` flag because commonMain does not have access to platform
 * file APIs. The platform actuals (jvmAndroidMain) populate that flag.
 */

package com.runanywhere.sdk.public.extensions.Models

import ai.runanywhere.proto.v1.ArchiveArtifact
import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ExpectedModelFiles
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.MultiFileArtifact
import ai.runanywhere.proto.v1.SingleFileArtifact
import ai.runanywhere.proto.v1.ThinkingTagPattern
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadResult
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - ExpectedModelFiles

/** An [ExpectedModelFiles] manifest with no files declared. */
val ExpectedModelFiles.Companion.none: ExpectedModelFiles
    get() = ExpectedModelFiles()

/**
 * True when the manifest carries no information at all (no files, no root,
 * no patterns, no description). Mirrors Swift `isEmptyManifest`.
 */
val ExpectedModelFiles.isEmptyManifest: Boolean
    get() =
        files.isEmpty() &&
            root_directory.isNullOrEmpty() &&
            required_patterns.isEmpty() &&
            optional_patterns.isEmpty() &&
            description.isNullOrEmpty()

// MARK: - ModelFileDescriptor

/**
 * Build a [ModelFileDescriptor]. Mirrors Swift's
 * `RAModelFileDescriptor(url:filename:isRequired:)` initializer — the
 * `relativePath` defaults to the URL's last path component and the
 * `destinationPath` to the filename.
 */
fun ModelFileDescriptor.Companion.create(
    url: String,
    filename: String,
    isRequired: Boolean = true,
): ModelFileDescriptor =
    ModelFileDescriptor(
        url = url,
        filename = filename,
        is_required = isRequired,
        relative_path = url.substringAfterLast('/').takeIf { it.isNotEmpty() } ?: filename,
        destination_path = filename,
    )

/**
 * Infer the canonical [ModelFileRole] for a single sidecar filename in a
 * multi-file model. Mirrors Swift's
 * `RunAnywhere.inferModelFileRole(filename:modality:)` and delegates to the
 * shared commons classifier `rac_infer_model_file_role`, so the SDK and the
 * C++ model-paths resolver always agree on which file is the primary model,
 * the vision projector (`mmproj`), tokenizer, vocabulary, etc.
 *
 * @param filename The sidecar's filename (case-insensitive; directory
 *   components are ignored).
 * @param modality The model's [ModelCategory]; only
 *   [ModelCategory.MODEL_CATEGORY_MULTIMODAL] enables the `mmproj` match path.
 * @return The matching [ModelFileRole], or
 *   [ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL] when nothing matches.
 */
fun RunAnywhere.inferModelFileRole(filename: String, modality: ModelCategory): ModelFileRole {
    val roleValue = RunAnywhereBridge.racInferModelFileRole(filename, modality.value)
    return ModelFileRole.fromValue(roleValue) ?: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
}

/** Returns the descriptor's URL field, or null if it is empty. */
val ModelFileDescriptor.urlValue: String?
    get() = url.takeIf { it.isNotEmpty() }

/**
 * The on-disk filename to write this descriptor to. Falls back through
 * `destination_path` → `filename` → `relative_path` to match Swift.
 */
val ModelFileDescriptor.destinationFilename: String
    get() =
        destination_path?.takeIf { it.isNotEmpty() }
            ?: filename.takeIf { it.isNotEmpty() }
            ?: relative_path.orEmpty()

/** Resolved local file system path, or null if the proto field is empty. */
val ModelFileDescriptor.resolvedLocalPath: String?
    get() = local_path?.takeIf { it.isNotEmpty() }

// MARK: - Collection<ModelFileDescriptor>

fun Collection<ModelFileDescriptor>.resolvedModelFilePath(role: ModelFileRole): String? =
    firstOrNull { it.role == role }?.resolvedLocalPath

val Collection<ModelFileDescriptor>.resolvedPrimaryModelPath: String?
    get() = resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL)

val Collection<ModelFileDescriptor>.resolvedVisionProjectorPath: String?
    get() = resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR)

val Collection<ModelFileDescriptor>.resolvedTokenizerPath: String?
    get() = resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_TOKENIZER)

val Collection<ModelFileDescriptor>.resolvedConfigPath: String?
    get() = resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_CONFIG)

val Collection<ModelFileDescriptor>.resolvedVocabularyPath: String?
    get() = resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_VOCABULARY)

// MARK: - ModelLoadResult resolved-artifact accessors
//
// NOTE: `resolvedPrimaryModelPath()` and `resolvedVisionProjectorPath()`
// also exist later in this file (different signature — those fall back
// through the model registry). The accessors below mirror the Swift API
// surface that just walks `resolved_artifacts` directly.

fun RAModelLoadResult.resolvedTokenizerPath(): String? =
    resolved_artifacts.resolvedTokenizerPath

fun RAModelLoadResult.resolvedConfigPath(): String? =
    resolved_artifacts.resolvedConfigPath

fun RAModelLoadResult.resolvedVocabularyPath(): String? =
    resolved_artifacts.resolvedVocabularyPath

/** Primary artifact path for the lifecycle, or `resolved_path` as a fallback. */
val RAModelLoadResult.lifecyclePrimaryArtifactPath: String?
    get() = resolvedPrimaryModelPath() ?: resolved_path.takeIf { it.isNotEmpty() }

// MARK: - CurrentModelResult resolved-artifact accessors

fun CurrentModelResult.resolvedTokenizerPath(): String? =
    resolved_artifacts.resolvedTokenizerPath

fun CurrentModelResult.resolvedConfigPath(): String? =
    resolved_artifacts.resolvedConfigPath

fun CurrentModelResult.resolvedVocabularyPath(): String? =
    resolved_artifacts.resolvedVocabularyPath

/** Primary artifact path for the lifecycle, or `resolved_path` as a fallback. */
val CurrentModelResult.lifecyclePrimaryArtifactPath: String?
    get() = resolvedPrimaryModelPath() ?: resolved_path.takeIf { it.isNotEmpty() }

// MARK: - ModelArtifactType

/**
 * True when the artifact type denotes an archive that has to be unpacked
 * before its contents are usable.
 */
val ModelArtifactType.requiresExtraction: Boolean
    get() =
        when (this) {
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE,
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE,
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE,
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE,
            -> true
            else -> false
        }

/**
 * True when this artifact type requires a network download. Built-in
 * models (system Foundation Models, system TTS) are the only artifact
 * type that never needs to be fetched.
 */
val ModelArtifactType.requiresDownload: Boolean
    get() = this != ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN

// `ModelArtifactType.displayName` already exists in ModelTypes.kt — do not
// redeclare it here.

// MARK: - ModelInfo artifact helpers

/** True when the entry's artifact requires extraction (archive). */
val RAModelInfo.requiresExtraction: Boolean
    get() {
        if (archive != null) return true
        return artifactTypeOrUnspecified.requiresExtraction
    }

/** True when the entry needs to be downloaded before it can be used. */
val RAModelInfo.requiresDownload: Boolean
    get() {
        if (isBuiltIn) return false
        return artifactTypeOrUnspecified.requiresDownload
    }

/** Underlying [ArchiveArtifact] or null if the entry isn't an archive. */
val RAModelInfo.archiveArtifact: ArchiveArtifact?
    get() {
        archive?.let { return it }
        return when (artifact_type) {
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE,
            ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE,
            ->
                makeArchiveArtifact(ArchiveType.ARCHIVE_TYPE_ZIP)
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE ->
                makeArchiveArtifact(ArchiveType.ARCHIVE_TYPE_TAR_GZ)
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE ->
                makeArchiveArtifact(ArchiveType.ARCHIVE_TYPE_TAR_BZ2)
            ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE ->
                makeArchiveArtifact(ArchiveType.ARCHIVE_TYPE_TAR_XZ)
            else -> null
        }
    }

/** Multi-file descriptors declared on the entry, or empty. */
val RAModelInfo.multiFileDescriptors: List<ModelFileDescriptor>
    get() = multi_file?.files ?: emptyList()

/**
 * Resolve the [ExpectedModelFiles] manifest the SDK should hand to the
 * downloader. Mirrors Swift's `expectedArtifactFiles`: a top-level manifest
 * short-circuits; otherwise the canonical fall-through (artifact-attached
 * manifest → pattern shorthand → multi-file descriptor seed) is computed by
 * commons via `rac_artifact_expected_files_proto` so the Kotlin,
 * Swift, and download-planner views can never drift.
 */
val RAModelInfo.expectedArtifactFiles: ExpectedModelFiles
    get() {
        expected_files?.let { if (!it.isEmptyManifest) return it }
        val decoded =
            RunAnywhereBridge
                .racArtifactExpectedFilesProto(ModelInfo.ADAPTER.encode(this))
                ?.let { ExpectedModelFiles.ADAPTER.decode(it) }
        return decoded ?: ExpectedModelFiles.none
    }

/**
 * Built-in detection — covers the explicit `built_in` oneof flag, the
 * `built_in` artifact type, the `builtin:` localpath prefix, and the two
 * platform-built-in frameworks (Foundation Models, System TTS).
 */
val RAModelInfo.isBuiltIn: Boolean
    get() {
        if (built_in == true) return true
        if (artifact_type == ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN) return true
        if (local_path.startsWith("builtin:")) return true
        return framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
            framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
    }

/**
 * Whether the model is downloaded on disk. CommonMain has no filesystem
 * access, so this falls back to the proto's `is_downloaded` flag (which
 * the platform actuals populate via `FileOperationsUtilities` /
 * `existsWithType` on the JVM/Android side).
 */
val RAModelInfo.isDownloadedOnDisk: Boolean
    get() {
        if (isBuiltIn) return true
        return is_downloaded == true || local_path.isNotEmpty()
    }

/** Whether the model is ready to load (built-in OR on-disk OR proto-marked). */
val RAModelInfo.isAvailableForUse: Boolean
    get() = isBuiltIn || isDownloadedOnDisk || (is_available == true)

/** Returns the download URL string or null if empty. */
val RAModelInfo.downloadURLValue: String?
    get() = download_url.takeIf { it.isNotEmpty() }

/**
 * Returns the local-path string or null if empty. CommonMain doesn't have
 * a URL type, so this is just the canonical path string the platform
 * actuals already use (`/abs/path` or `file:///` or `builtin:...`).
 */
val RAModelInfo.localPathURL: String?
    get() = local_path.takeIf { it.isNotEmpty() }

/** Hint of the download size in bytes, alias for `download_size_bytes`. */
val RAModelInfo.downloadSizeHint: Long
    get() = download_size_bytes

private val RAModelInfo.artifactTypeOrUnspecified: ModelArtifactType
    get() = artifact_type ?: ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED

// MARK: - Fluent helpers (return a new copy with the requested mutation)

/** Returns a copy of [ModelInfo] with `download_url` updated. */
fun RAModelInfo.setDownloadURL(url: String?): RAModelInfo =
    copy(download_url = url.orEmpty())

/**
 * Returns a copy of [ModelInfo] with `local_path` updated and the derived
 * `is_downloaded` / `is_available` flags re-stamped to match.
 */
fun RAModelInfo.setLocalPath(path: String?): RAModelInfo {
    val updated = copy(local_path = path.orEmpty())
    return updated.copy(
        is_downloaded = updated.isDownloadedOnDisk,
        is_available = updated.isAvailableForUse,
    )
}

/**
 * Returns a copy of [ModelInfo] with the artifact oneof set to a single-
 * file artifact. Also updates the canonical `artifact_type` and stamps
 * the artifact's `expected_files` onto the entry when non-empty.
 */
fun RAModelInfo.setSingleFileArtifact(artifact: SingleFileArtifact): RAModelInfo {
    val derived = artifact.expected_files?.takeIf { !it.isEmptyManifest }
    return copy(
        single_file = artifact,
        archive = null,
        multi_file = null,
        custom_strategy_id = null,
        built_in = null,
        artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
        expected_files = derived ?: expected_files,
    )
}

/**
 * Returns a copy of [ModelInfo] with the artifact oneof set to an archive.
 * Also updates `artifact_type` and stamps the manifest when present.
 */
fun RAModelInfo.setArchiveArtifact(artifact: ArchiveArtifact): RAModelInfo {
    val derived = artifact.expected_files?.takeIf { !it.isEmptyManifest }
    return copy(
        single_file = null,
        archive = artifact,
        multi_file = null,
        custom_strategy_id = null,
        built_in = null,
        artifact_type = artifact.type.toModelArtifactType(),
        expected_files = derived ?: expected_files,
    )
}

/**
 * Returns a copy of [ModelInfo] with the artifact oneof set to a multi-
 * file artifact. Also updates `artifact_type`.
 */
fun RAModelInfo.setMultiFileArtifact(artifact: MultiFileArtifact): RAModelInfo =
    copy(
        single_file = null,
        archive = null,
        multi_file = artifact,
        custom_strategy_id = null,
        built_in = null,
        artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
    )

/**
 * Returns a copy of [ModelInfo] with the artifact oneof set to a custom
 * strategy id. Also updates `artifact_type`.
 */
fun RAModelInfo.setCustomStrategyArtifact(strategyId: String): RAModelInfo =
    copy(
        single_file = null,
        archive = null,
        multi_file = null,
        custom_strategy_id = strategyId,
        built_in = null,
        artifact_type = ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM,
    )

/**
 * Returns a copy of [ModelInfo] flagged as built-in. Also updates
 * `artifact_type`.
 */
fun RAModelInfo.setBuiltInArtifact(enabled: Boolean = true): RAModelInfo =
    copy(
        single_file = null,
        archive = null,
        multi_file = null,
        custom_strategy_id = null,
        built_in = enabled,
        artifact_type =
            if (enabled) {
                ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN
            } else {
                ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED
            },
    )

// MARK: - Factory

/**
 * Build a [ModelInfo] populated with the canonical defaults the iOS SDK
 * uses (created/updated timestamps, inferred artifact, derived
 * downloaded/available flags).
 *
 * @param archiveType If known, forces the archive variant of the inferred
 *   artifact. Pass `null` to let the helper infer from the URL.
 */
fun ModelInfo.Companion.make(
    id: String,
    name: String,
    category: ModelCategory,
    format: ModelFormat,
    framework: InferenceFramework,
    downloadURL: String? = null,
    localPath: String? = null,
    downloadSizeBytes: Long? = null,
    contextLength: Int? = null,
    supportsThinking: Boolean = false,
    thinkingPattern: ThinkingTagPattern? = null,
    description: String? = null,
    source: ModelSource = ModelSource.MODEL_SOURCE_REMOTE,
    createdAtUnixMs: Long = getCurrentTimeMillis(),
    updatedAtUnixMs: Long = getCurrentTimeMillis(),
    archiveType: ArchiveType? = null,
): RAModelInfo {
    val resolvedContext =
        contextLength
            ?: if (category.requiresContextLength) 2048 else 0
    val resolvedSupportsThinking = category.supportsThinking && supportsThinking
    val base =
        RAModelInfo(
            id = id,
            name = name,
            category = category,
            format = format,
            framework = framework,
            download_url = downloadURL.orEmpty(),
            local_path = localPath.orEmpty(),
            download_size_bytes = downloadSizeBytes ?: 0L,
            context_length = resolvedContext,
            supports_thinking = resolvedSupportsThinking,
            description = description.orEmpty(),
            source = source,
            created_at_unix_ms = createdAtUnixMs,
            updated_at_unix_ms = updatedAtUnixMs,
            thinking_pattern = if (resolvedSupportsThinking) thinkingPattern else null,
        )

    val withArtifact = base.applyInferredArtifact(downloadURL, archiveType)
    return withArtifact.copy(
        is_downloaded = withArtifact.isDownloadedOnDisk,
        is_available = withArtifact.isAvailableForUse,
    )
}

private fun RAModelInfo.applyInferredArtifact(
    url: String?,
    explicitArchiveType: ArchiveType?,
): RAModelInfo {
    val archiveType = explicitArchiveType ?: archiveTypeFromPath(url.orEmpty())
    return if (archiveType != null) {
        setArchiveArtifact(
            ArchiveArtifact(
                type = archiveType,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
            ),
        )
    } else {
        setSingleFileArtifact(SingleFileArtifact())
    }
}

private fun makeArchiveArtifact(type: ArchiveType): ArchiveArtifact =
    ArchiveArtifact(
        type = type,
        structure = ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
    )

private fun ArchiveType.toModelArtifactType(): ModelArtifactType =
    when (this) {
        ArchiveType.ARCHIVE_TYPE_ZIP -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_GZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_TAR_XZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE
        ArchiveType.ARCHIVE_TYPE_UNSPECIFIED -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE
    }

// MARK: - Generated-model helpers for resolving declared artifact file paths

fun RAModelInfo.resolvedPrimaryModelPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL)

fun RAModelInfo.resolvedVocabularyPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_VOCABULARY)

fun RAModelLoadResult.resolvedPrimaryModelPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL)

fun RAModelLoadResult.resolvedVisionProjectorPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR)

fun RAModelLoadResult.resolvedModelFilePath(role: ModelFileRole): String? =
    resolved_artifacts.resolvedArtifactLocalPath(role)

fun CurrentModelResult.resolvedPrimaryModelPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL)

fun CurrentModelResult.resolvedVisionProjectorPath(): String? =
    resolvedModelFilePath(ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR)

fun CurrentModelResult.resolvedModelFilePath(role: ModelFileRole): String? =
    resolved_artifacts.resolvedArtifactLocalPath(role)

fun RAModelInfo.resolvedModelFilePath(role: ModelFileRole): String? {
    val descriptors = declaredModelFileDescriptors
    if (descriptors.isEmpty()) {
        return local_path.takeIf { role == ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL && it.isNotBlank() }
    }

    val descriptor =
        descriptors.firstOrNull { it.role == role }
            ?: if (role == ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL) {
                descriptors.firstOrNull { it.is_required } ?: descriptors.firstOrNull()
            } else {
                null
            }
            ?: return null

    descriptor.local_path.takeIfNotBlank()?.let { return it }

    val pathFragment = descriptor.pathFragment() ?: return null
    return resolveDescriptorPath(descriptorRootPath(descriptors), pathFragment)
}

private val RAModelInfo.declaredModelFileDescriptors: List<ModelFileDescriptor>
    get() =
        expected_files?.files?.takeIf { it.isNotEmpty() }
            ?: multi_file?.files?.takeIf { it.isNotEmpty() }
            ?: archive?.expected_files?.files?.takeIf { it.isNotEmpty() }
            ?: single_file?.expected_files?.files?.takeIf { it.isNotEmpty() }
            ?: emptyList()

private fun List<ModelFileDescriptor>.resolvedArtifactLocalPath(role: ModelFileRole): String? =
    firstOrNull { it.role == role }?.local_path.takeIfNotBlank()

private fun RAModelInfo.descriptorRootPath(descriptors: List<ModelFileDescriptor>): String {
    val modelPath = local_path.takeIfNotBlank().orEmpty()
    val primaryDescriptor =
        descriptors.firstOrNull { it.role == ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL }
            ?: descriptors.firstOrNull()
            ?: return modelPath

    primaryDescriptor.local_path.takeIfNotBlank()?.let { primaryPath ->
        return parentPath(primaryPath) ?: modelPath
    }

    val primaryFragment = primaryDescriptor.pathFragment()
    return if (modelPath.isNotBlank() && primaryFragment != null && modelPath.endsWithPathFragment(primaryFragment)) {
        parentPath(modelPath) ?: modelPath
    } else {
        modelPath
    }
}

private fun ModelFileDescriptor.pathFragment(): String? =
    destination_path.takeIfNotBlank()
        ?: relative_path.takeIfNotBlank()
        ?: filename.takeIfNotBlank()

private fun resolveDescriptorPath(
    rootPath: String,
    pathFragment: String,
): String? {
    if (pathFragment.isAbsolutePath()) return pathFragment
    if (rootPath.isBlank()) return null

    val root = rootPath.trimEnd('/', '\\')
    val child = pathFragment.trimStart('/', '\\')
    if (root.endsWithPathFragment(child)) return root

    return "$root/$child"
}

private fun String.endsWithPathFragment(pathFragment: String): Boolean {
    val root = trimEnd('/', '\\')
    val child = pathFragment.trimStart('/', '\\')
    return root == child || root.endsWith("/$child") || root.endsWith("\\$child")
}

private fun String.isAbsolutePath(): Boolean =
    startsWith("/") ||
        startsWith("\\") ||
        contains("://") ||
        (length > 2 && this[1] == ':' && (this[2] == '/' || this[2] == '\\'))

private fun parentPath(path: String): String? {
    val trimmed = path.trimEnd('/', '\\')
    val separatorIndex = maxOf(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
    return when {
        separatorIndex > 0 -> trimmed.substring(0, separatorIndex)
        separatorIndex == 0 -> trimmed.substring(0, 1)
        else -> null
    }
}

private fun String?.takeIfNotBlank(): String? = this?.takeIf { it.isNotBlank() }
