package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** A lifecycle-confirmed model snapshot captured immediately before inference. */
data class RuntimeModelSnapshot(
    val id: String,
    val model: RAModelInfo,
    val category: ModelCategory,
    val framework: InferenceFramework,
)

/**
 * Process-wide model state shared by every model picker.
 *
 * Picker ViewModels are screen-scoped, while the native model lifecycle is
 * process-scoped. Keeping currentModelId in each ViewModel therefore allowed
 * one screen to keep showing (and recording) model A after another screen had
 * loaded model B. This store mirrors lifecycle-confirmed snapshots to every
 * picker, while [queryCurrent] still queries native state immediately before
 * inference so the mirror is never trusted as the execution authority.
 */
object RuntimeModelSelection {
    private val store = RuntimeModelSelectionStore()

    fun observe(context: ModelSelectionContext): Flow<RuntimeModelSnapshot?> = store.observe(context)

    fun cached(context: ModelSelectionContext): RuntimeModelSnapshot? = store.snapshot(context)

    /** Record a RAG model chosen by reference rather than loaded in a lifecycle component. */
    fun selectReference(context: ModelSelectionContext, model: RAModelInfo) {
        require(!context.loadsModel) { "${context.name} is a runtime-loaded model" }
        publishKnown(context, model)
    }

    private fun publishKnown(context: ModelSelectionContext, model: RAModelInfo) {
        publish(
            context,
            RuntimeModelSnapshot(
                id = model.id,
                model = model,
                category = model.category,
                framework = model.framework,
            ),
        )
    }

    fun clear(context: ModelSelectionContext, expectedModelId: String? = null) {
        val current = store.snapshot(context)
        if (expectedModelId == null || current?.id == expectedModelId) publish(context, null)
    }

    fun clearModelEverywhere(modelId: String) {
        ModelSelectionContext.values().forEach { context ->
            if (store.snapshot(context)?.id == modelId) publish(context, null)
        }
    }

    /**
     * Query the C++ lifecycle for the model that would execute for [context].
     * This is intentionally a suspend query rather than a read from [cached].
     */
    suspend fun queryCurrent(
        context: ModelSelectionContext,
        candidates: Iterable<RAModelInfo> = emptyList(),
    ): RuntimeModelSnapshot? {
        require(context.loadsModel) { "${context.name} is selected by RAG pipeline reference" }
        val byId = candidates.associateBy { it.id }
        for (category in context.lifecycleCategories) {
            val result = RunAnywhere.currentModel(
                CurrentModelRequest(category = category, include_model_metadata = true),
            )
            if (!result.found || result.model_id.isBlank()) continue

            val id = result.model_id
            val model = result.model?.takeIf { it.id == id }
                ?: byId[id]
                ?: store.snapshot(context)?.takeIf { it.id == id }?.model
                ?: ModelInfo(
                    id = id,
                    name = id,
                    category = result.category.takeUnless {
                        it == ModelCategory.MODEL_CATEGORY_UNSPECIFIED
                    } ?: category,
                    framework = result.framework,
                )
            val snapshot = RuntimeModelSnapshot(
                id = id,
                model = model,
                category = result.category.takeUnless {
                    it == ModelCategory.MODEL_CATEGORY_UNSPECIFIED
                } ?: category,
                framework = result.framework.takeUnless {
                    it == InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED ||
                        it == InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
                } ?: model.framework,
            )
            publish(context, snapshot)
            return snapshot
        }

        publish(context, null)
        return null
    }

    suspend fun requireCurrent(
        context: ModelSelectionContext,
        candidates: Iterable<RAModelInfo> = emptyList(),
    ): RuntimeModelSnapshot = queryCurrent(context, candidates)
        ?: error("No ${context.title.removePrefix("Choose ").lowercase()} is loaded.")

    private fun publish(context: ModelSelectionContext, snapshot: RuntimeModelSnapshot?) {
        store.publish(context, snapshot)
        if (context == ModelSelectionContext.LLM) {
            GlobalState.model.set(snapshot?.model)
            if (snapshot == null) GlobalState.lora.set(null)
        }
    }
}

/** Small independently testable store behind [RuntimeModelSelection]. */
internal class RuntimeModelSelectionStore {
    private val snapshots = MutableStateFlow<Map<ModelSelectionContext, RuntimeModelSnapshot>>(emptyMap())

    fun observe(context: ModelSelectionContext): Flow<RuntimeModelSnapshot?> =
        snapshots.map { it[context] }.distinctUntilChanged()

    fun snapshot(context: ModelSelectionContext): RuntimeModelSnapshot? = snapshots.value[context]

    fun publish(context: ModelSelectionContext, snapshot: RuntimeModelSnapshot?) {
        synchronized(this) {
            snapshots.value = if (snapshot == null) {
                snapshots.value - context
            } else {
                snapshots.value + (context to snapshot)
            }
        }
    }
}
