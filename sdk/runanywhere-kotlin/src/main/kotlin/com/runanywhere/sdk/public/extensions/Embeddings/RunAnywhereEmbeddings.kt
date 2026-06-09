/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`.
 *
 * Mirrors Swift `RunAnywhere+Embeddings.swift` exactly. Lifecycle
 * (load / current / unload) delegates to the commons model lifecycle service
 * via `RunAnywhere.loadModel` / `RunAnywhere.unloadModel`. Embed calls
 * dispatch through the lifecycle-aware ABI
 * `rac_embeddings_embed_batch_lifecycle_proto` (via
 * `CppBridgeEmbeddings.embedBatchLifecycle`) so they share the same
 * model-load/registry state as LLM/STT/TTS.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsRequest
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEmbeddings
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAEmbeddingsResult

/**
 * Stateless namespace exposing the canonical Embeddings surface. Backed by the
 * commons C ABI through [CppBridgeEmbeddings] and the model lifecycle.
 */
object Embeddings {
    // MARK: - Lifecycle introspection

    /** True when commons lifecycle has a ready embeddings model. */
    suspend fun isLoaded(): Boolean {
        val snapshot =
            RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS)
                ?: return false
        return snapshot.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
            snapshot.model_id.isNotEmpty()
    }

    /** Currently-loaded embeddings model id, or null. */
    suspend fun currentModelID(): String? {
        val snapshot =
            RunAnywhere.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS)
                ?: return null
        if (snapshot.state != ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
            snapshot.model_id.isEmpty()
        ) {
            return null
        }
        return snapshot.model_id
    }

    // MARK: - Embed

    /**
     * Generate an embedding vector for a single text. Loads the requested
     * embedding model into the commons lifecycle if it is not already loaded,
     * then issues a single-text embed call through the lifecycle-aware ABI.
     */
    suspend fun embed(
        text: String,
        modelId: String,
        options: EmbeddingsOptions? = null,
    ): RAEmbeddingsResult =
        embedBatch(
            EmbeddingsRequest(texts = listOf(text), options = options),
            modelId = modelId,
        )

    /**
     * Generate embeddings for a batch of texts. The request's `model_id` is
     * honoured when set; otherwise the supplied [modelId] argument is used.
     */
    suspend fun embedBatch(
        request: EmbeddingsRequest,
        modelId: String,
    ): RAEmbeddingsResult {
        if (!RunAnywhere.isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }
        ensureLoaded(modelId)

        val requestModelId = request.model_id
        if (!requestModelId.isNullOrEmpty() && requestModelId != modelId) {
            throw SDKException.invalidArgument(
                "EmbeddingsRequest.model_id does not match requested modelId",
            )
        }

        return CppBridgeEmbeddings.embedBatchLifecycle(request.copy(model_id = modelId))
    }

    // MARK: - Unload

    /** Unload the currently-loaded embeddings model. No-op if none. */
    suspend fun unload() {
        if (!RunAnywhere.isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        val modelId =
            currentModelID()
                ?: RunAnywhere
                    .currentModel(
                        CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_EMBEDDING),
                    ).model_id
        if (modelId.isEmpty()) return

        val result =
            RunAnywhere.unloadModel(
                ModelUnloadRequest(
                    model_id = modelId,
                    category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
                ),
            )
        if (!result.success) {
            val message =
                result.error_message.ifEmpty { "Embeddings lifecycle unload failed" }
            throw SDKException.operation(message)
        }
    }

    // MARK: - Private

    private suspend fun ensureLoaded(modelId: String) {
        if (currentModelID() == modelId) return

        val current =
            RunAnywhere.currentModel(
                CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_EMBEDDING),
            )
        if (current.found && current.model_id == modelId) return

        val result =
            RunAnywhere.loadModel(
                ModelLoadRequest(
                    model_id = modelId,
                    category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
                    force_reload = true,
                    validate_availability = true,
                ),
            )
        if (!result.success) {
            val reason =
                result.error_message.ifEmpty { "Embeddings lifecycle load failed" }
            throw SDKException.modelLoadFailed(modelId, reason)
        }
    }
}

/** Capability accessor for Embeddings, mirroring Swift `RunAnywhere.embeddings`. */
val RunAnywhere.embeddings: Embeddings
    get() = Embeddings
