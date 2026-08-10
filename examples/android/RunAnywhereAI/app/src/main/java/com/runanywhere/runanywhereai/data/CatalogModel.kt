package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.ModelRegistration
import com.runanywhere.sdk.public.api.models

internal sealed interface CatalogModel {
    val id: String
    suspend fun register(): ModelInfo?
}

internal data class ModelFile(
    val url: String,
    val filename: String,
    val sizeBytes: Long? = null,
    val checksumSha256: String? = null,
)

internal data class SingleFileModel(
    override val id: String,
    val name: String,
    val url: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val downloadBytes: Long = memoryBytes,
    val contextLength: Int? = null,
    val supportsLora: Boolean = false,
    val supportsThinking: Boolean = false,
) : CatalogModel {
    override suspend fun register(): ModelInfo =
        RunAnywhere.models.register(
            ModelRegistration.url(
                id = id,
                name = name,
                url = url,
                framework = framework,
                category = category,
                memoryBytes = memoryBytes,
                downloadBytes = downloadBytes,
                supportsThinking = supportsThinking,
                supportsLora = supportsLora,
            ),
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
    override suspend fun register(): ModelInfo =
        RunAnywhere.models.register(
            ModelRegistration.archive(
                id = id,
                name = name,
                url = url,
                framework = framework,
                structure = structure,
                archiveType = archiveType,
                category = category,
                memoryBytes = memoryBytes,
            ),
        )
}

internal data class MultiFileModel(
    override val id: String,
    val name: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val downloadBytes: Long = memoryBytes,
    val files: List<ModelFile>,
    /** Computer-Use-Agent profile id (e.g. `"fara"`) for CUA-capable rows. */
    val cuaProfile: String? = null,
) : CatalogModel {
    override suspend fun register(): ModelInfo =
        RunAnywhere.models.register(
            ModelRegistration.multiFile(
                id = id,
                name = name,
                framework = framework,
                files = descriptors(),
                category = category,
                memoryBytes = memoryBytes,
                downloadBytes = downloadBytes,
                cuaProfile = cuaProfile,
            ),
        )

    internal fun descriptors(): List<ModelFileDescriptor> =
        files.mapIndexed { idx, file ->
            ModelFileDescriptor(
                url = file.url,
                filename = file.filename,
                // Wire polarity: is_required -> is_optional (inverted). All
                // catalog files here are required, so is_optional = false.
                is_optional = false,
                size_bytes = file.sizeBytes,
                checksum_sha256 = file.checksumSha256,
                role = if (idx == 0) {
                    ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                } else {
                    ModelFileRole.MODEL_FILE_ROLE_COMPANION
                },
            )
        }
}
