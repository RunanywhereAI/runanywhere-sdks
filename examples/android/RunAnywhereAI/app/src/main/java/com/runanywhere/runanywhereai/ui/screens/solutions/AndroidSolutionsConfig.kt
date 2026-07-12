package com.runanywhere.runanywhereai.ui.screens.solutions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.types.RAModelInfo

/** A solution YAML plus the concrete Android catalog models it references. */
internal data class ResolvedAndroidSolution(
    val yaml: String?,
    val requiredModelIds: List<String>,
    val missingModels: List<String>,
) {
    val isReady: Boolean get() = yaml != null && missingModels.isEmpty()
}

internal data class ResolvedAndroidSolutions(
    val voice: ResolvedAndroidSolution,
    val rag: ResolvedAndroidSolution,
)

/**
 * Adapts the cross-platform example YAMLs to Android's device-filtered QHexRT catalog.
 *
 * The canonical YAML remains shared by every platform. Android resolves each accelerated
 * role from the models native registration exposed for this device, preferring the app's
 * current recommendations and then any already-downloaded QHexRT model for that role.
 */
internal object AndroidSolutionsConfig {
    internal const val PREFERRED_LLM_ID = "qwen3_5_0_8b"
    internal const val PREFERRED_STT_ID = "whisper_base"
    internal const val PREFERRED_TTS_ID = "kokoro_en"
    internal const val PREFERRED_EMBEDDING_ID = "embeddinggemma_300m"
    internal const val VAD_ID = "silero-vad"

    private val qhexrt = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT

    fun resolve(models: List<RAModelInfo>): ResolvedAndroidSolutions {
        val llm = selectQHexRT(
            models = models,
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            preferredId = PREFERRED_LLM_ID,
        )
        val stt = selectQHexRT(
            models = models,
            category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            preferredId = PREFERRED_STT_ID,
        )
        val tts = selectQHexRT(
            models = models,
            category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            preferredId = PREFERRED_TTS_ID,
        )
        val embedding = selectQHexRT(
            models = models,
            category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
            preferredId = PREFERRED_EMBEDDING_ID,
        )
        val vad = models.firstOrNull {
            it.id == VAD_ID &&
                it.category == ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        }

        return ResolvedAndroidSolutions(
            voice = buildSolution(
                template = SolutionsYaml.VOICE_AGENT,
                fields = listOf(
                    ModelField("llm_model_id", "QHexRT language model", llm),
                    ModelField("stt_model_id", "QHexRT speech recognition model", stt),
                    ModelField("tts_model_id", "QHexRT speech synthesis model", tts),
                    ModelField("vad_model_id", VAD_ID, vad),
                ),
            ),
            rag = buildSolution(
                template = SolutionsYaml.RAG,
                fields = listOf(
                    ModelField("embed_model_id", "QHexRT embedding model", embedding),
                    ModelField("llm_model_id", "QHexRT language model", llm),
                ),
            ),
        )
    }

    private fun selectQHexRT(
        models: List<RAModelInfo>,
        category: ModelCategory,
        preferredId: String,
    ): RAModelInfo? {
        val candidates = models.filter { it.framework == qhexrt && it.category == category }
        return candidates.firstOrNull { it.id == preferredId && it.isDownloadedOnDisk }
            ?: candidates.firstOrNull { it.isDownloadedOnDisk }
            ?: candidates.firstOrNull { it.id == preferredId }
            ?: candidates.firstOrNull()
    }

    private fun buildSolution(
        template: String,
        fields: List<ModelField>,
    ): ResolvedAndroidSolution {
        val selected = fields.mapNotNull { it.model }
        val missing = fields.mapNotNull { field ->
            when {
                field.model == null -> "${field.missingLabel} (not available on this device)"
                !field.model.isDownloadedOnDisk -> field.model.id
                else -> null
            }
        }
        val yaml = if (selected.size == fields.size) {
            fields.fold(template) { current, field ->
                replaceYamlValue(current, field.yamlKey, requireNotNull(field.model).id)
            }
        } else {
            null
        }
        return ResolvedAndroidSolution(
            yaml = yaml,
            requiredModelIds = selected.map { it.id },
            missingModels = missing,
        )
    }

    private fun replaceYamlValue(yaml: String, key: String, modelId: String): String {
        require(modelId.matches(Regex("[A-Za-z0-9._-]+"))) { "Unsafe model ID: $modelId" }
        val field = Regex(
            pattern = "(?m)^(\\s*${Regex.escape(key)}\\s*:\\s*)" +
                "(?:\"[^\"]*\"|'[^']*'|[^\\s#]+)(\\s*(?:#.*)?)$",
        )
        require(field.findAll(yaml).count() == 1) { "Expected exactly one '$key' field" }
        return field.replace(yaml) { match ->
            "${match.groupValues[1]}\"$modelId\"${match.groupValues[2]}"
        }
    }

    private data class ModelField(
        val yamlKey: String,
        val missingLabel: String,
        val model: RAModelInfo?,
    )
}
