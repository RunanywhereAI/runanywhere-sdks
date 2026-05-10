/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generated-model helpers for resolving declared artifact file paths.
 */

package com.runanywhere.sdk.public.extensions.Models

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadResult
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
