package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveArtifact
import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.ExpectedModelFiles
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.MultiFileArtifact
import ai.runanywhere.proto.v1.SingleFileArtifact
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.registerModel

internal sealed interface CatalogModel {
    val id: String
    fun toModelInfo(): ModelInfo
    suspend fun register()
}

internal data class ModelFile(val url: String, val filename: String)

internal data class SingleFileModel(
    override val id: String,
    val name: String,
    val url: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val supportsLora: Boolean = false,
    val supportsThinking: Boolean = false,
) : CatalogModel {
    override suspend fun register() {
        RunAnywhere.registerModel(
            id = id,
            name = name,
            url = url,
            framework = framework,
            modality = category,
            artifactType = null,
            memoryRequirement = memoryBytes,
            supportsThinking = supportsThinking,
            supportsLora = supportsLora,
        )
    }

    override fun toModelInfo() = ModelInfo(
        id = id,
        name = name,
        download_url = url,
        framework = framework,
        category = category,
        memory_required_bytes = memoryBytes,
        download_size_bytes = memoryBytes,
        supports_lora = supportsLora,
        supports_thinking = supportsThinking,
        single_file = SingleFileArtifact(),
    )
}

internal data class ArchiveModel(
    override val id: String,
    val name: String,
    val url: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val archiveType: ArchiveType,
    val structure: ArchiveStructure,
) : CatalogModel {
    override suspend fun register() {
        RunAnywhere.registerModel(
            archiveUrl = url,
            structure = structure,
            id = id,
            name = name,
            framework = framework,
            modality = category,
            archiveType = archiveType,
            memoryRequirement = memoryBytes,
            supportsThinking = false,
            supportsLora = false,
        )
    }

    override fun toModelInfo() = ModelInfo(
        id = id,
        name = name,
        download_url = url,
        framework = framework,
        category = category,
        memory_required_bytes = memoryBytes,
        download_size_bytes = memoryBytes,
        artifact_type = when (archiveType) {
            ArchiveType.ARCHIVE_TYPE_TAR_GZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
            ArchiveType.ARCHIVE_TYPE_ZIP -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
            ArchiveType.ARCHIVE_TYPE_TAR_BZ2 -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE
            ArchiveType.ARCHIVE_TYPE_TAR_XZ -> ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE
            else -> ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE
        },
        archive = ArchiveArtifact(type = archiveType, structure = structure),
    )
}

internal data class MultiFileModel(
    override val id: String,
    val name: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val files: List<ModelFile>,
) : CatalogModel {
    override suspend fun register() {
        RunAnywhere.registerModel(
            multiFile = descriptors(),
            id = id,
            name = name,
            framework = framework,
            modality = category,
            memoryRequirement = memoryBytes,
            contextLength = null,
            supportsThinking = false,
            source = ModelSource.MODEL_SOURCE_REMOTE,
        )
    }

    override fun toModelInfo(): ModelInfo {
        val descriptors = descriptors()
        // expected_files must mirror multi_file or the download falls back to the single-URL branch.
        return ModelInfo(
            id = id,
            name = name,
            framework = framework,
            category = category,
            memory_required_bytes = memoryBytes,
            download_size_bytes = memoryBytes,
            multi_file = MultiFileArtifact(files = descriptors),
            expected_files = ExpectedModelFiles(files = descriptors),
        )
    }

    private fun descriptors(): List<ModelFileDescriptor> =
        files.mapIndexed { idx, file ->
            ModelFileDescriptor(
                url = file.url,
                filename = file.filename,
                is_required = true,
                role = if (idx == 0) {
                    ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                } else {
                    ModelFileRole.MODEL_FILE_ROLE_COMPANION
                },
            )
        }
}