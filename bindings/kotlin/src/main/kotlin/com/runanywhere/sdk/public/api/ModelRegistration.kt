/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: the one builder every model artifact registers through.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.ModelSource

/**
 * A model artifact to register: a single URL, an archive, or a file set.
 *
 * Build one with [url], [archive], or [multiFile].
 */
public class ModelRegistration private constructor(
    internal val kind: Kind,
    internal val id: String?,
    internal val name: String,
    internal val url: String,
    internal val framework: InferenceFramework,
    internal val category: ModelCategory,
    internal val memoryBytes: Long?,
    internal val downloadBytes: Long?,
    internal val contextLength: Int?,
    internal val source: ModelSource,
    internal val description: String?,
    internal val supportsThinking: Boolean,
    internal val supportsLora: Boolean,
    internal val archiveType: ArchiveType?,
    internal val archiveStructure: ArchiveStructure?,
    internal val files: List<ModelFileDescriptor>,
    internal val cuaProfile: String?,
) {
    internal enum class Kind {
        URL,
        ARCHIVE,
        MULTI_FILE,
    }

    public companion object {
        /** Register one downloadable file, letting commons infer format and artifact type. */
        public fun url(
            name: String,
            url: String,
            framework: InferenceFramework,
            category: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            id: String? = null,
            memoryBytes: Long? = null,
            downloadBytes: Long? = null,
            contextLength: Int? = null,
            source: ModelSource = ModelSource.MODEL_SOURCE_REMOTE,
            description: String? = null,
            supportsThinking: Boolean = false,
            supportsLora: Boolean = false,
            cuaProfile: String? = null,
        ): ModelRegistration =
            ModelRegistration(
                kind = Kind.URL,
                id = id,
                name = name,
                url = url,
                framework = framework,
                category = category,
                memoryBytes = memoryBytes,
                downloadBytes = downloadBytes,
                contextLength = contextLength,
                source = source,
                description = description,
                supportsThinking = supportsThinking,
                supportsLora = supportsLora,
                archiveType = null,
                archiveStructure = null,
                files = emptyList(),
                cuaProfile = cuaProfile,
            )

        /** Register an archive whose inner layout is described by [structure]. */
        public fun archive(
            name: String,
            url: String,
            framework: InferenceFramework,
            structure: ArchiveStructure,
            archiveType: ArchiveType? = null,
            category: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            id: String? = null,
            memoryBytes: Long? = null,
            supportsThinking: Boolean = false,
            supportsLora: Boolean = false,
            cuaProfile: String? = null,
        ): ModelRegistration =
            ModelRegistration(
                kind = Kind.ARCHIVE,
                id = id,
                name = name,
                url = url,
                framework = framework,
                category = category,
                memoryBytes = memoryBytes,
                downloadBytes = null,
                contextLength = null,
                source = ModelSource.MODEL_SOURCE_REMOTE,
                description = null,
                supportsThinking = supportsThinking,
                supportsLora = supportsLora,
                archiveType = archiveType,
                archiveStructure = structure,
                files = emptyList(),
                cuaProfile = cuaProfile,
            )

        /** Register a model whose weights span several files. */
        public fun multiFile(
            id: String,
            name: String,
            framework: InferenceFramework,
            files: List<ModelFileDescriptor>,
            category: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            memoryBytes: Long? = null,
            downloadBytes: Long? = null,
            contextLength: Int? = null,
            supportsThinking: Boolean = false,
            cuaProfile: String? = null,
        ): ModelRegistration =
            ModelRegistration(
                kind = Kind.MULTI_FILE,
                id = id,
                name = name,
                url = "",
                framework = framework,
                category = category,
                memoryBytes = memoryBytes,
                downloadBytes = downloadBytes,
                contextLength = contextLength,
                source = ModelSource.MODEL_SOURCE_REMOTE,
                description = null,
                supportsThinking = supportsThinking,
                supportsLora = false,
                archiveType = null,
                archiveStructure = null,
                files = files,
                cuaProfile = cuaProfile,
            )
    }
}
