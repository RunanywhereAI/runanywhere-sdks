package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.registerModel

private val QHEXRT = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
private const val HNPU_DESCRIPTION = "Qualcomm Hexagon NPU model bundle."
internal sealed interface CatalogModel {
    val id: String
    suspend fun register(): ModelInfo?
}

internal data class ModelFile(val url: String, val filename: String)

internal data class SingleFileModel(
    override val id: String,
    val name: String,
    val url: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val contextLength: Int? = null,
    val supportsLora: Boolean = false,
    val supportsThinking: Boolean = false,
) : CatalogModel {
    internal fun toQHexRTRegistrationRequest(): RegisterModelFromUrlRequest {
        require(framework == QHEXRT) { "Only QHexRT catalog rows use device-aware registration" }
        return RegisterModelFromUrlRequest(
            id = id,
            name = name,
            url = url,
            framework = framework,
            category = category,
            source = ModelSource.MODEL_SOURCE_REMOTE,
            memory_required_bytes = memoryBytes,
            download_size_bytes = memoryBytes,
            context_length = contextLength,
            supports_thinking = supportsThinking,
            supports_lora = supportsLora,
            description = HNPU_DESCRIPTION,
        )
    }

    override suspend fun register(): ModelInfo? {
        if (framework == QHEXRT) {
            return QHexRT.registerModelForDevice(toQHexRTRegistrationRequest())
        }
        return RunAnywhere.registerModel(
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

internal data class MultiFileModel(
    override val id: String,
    val name: String,
    val framework: InferenceFramework,
    val category: ModelCategory,
    val memoryBytes: Long,
    val files: List<ModelFile>,
) : CatalogModel {
    override suspend fun register(): ModelInfo =
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
