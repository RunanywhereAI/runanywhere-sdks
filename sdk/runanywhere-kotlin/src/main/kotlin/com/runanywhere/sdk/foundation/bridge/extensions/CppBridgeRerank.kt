/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeRerank.kt
 *
 * Cross-encoder reranking component bridge — wraps the proto-canonical
 * `rac_rerank_component_*` C ABI.
 *
 * Unlike diarization / segmentation (which each publish a handle-free
 * `*_lifecycle_proto` verb whose commons resolver reads the global loaded
 * store), the revived rerank primitive ships ONLY the handle-scoped verb
 * `rac_rerank_component_rerank_proto`, whose `rac_lifecycle_acquire_service`
 * is owner-scoped. This bridge therefore owns a component handle and loads the
 * lifecycle-resolved model into it before scoring — mirroring the handle-prep
 * half of Swift `CppBridge.Diarization.prepareStreamingHandle`.
 *
 * All generic scaffolding (handle creation, isLoaded, loadModel, unload,
 * destroy) lives in [ComponentActor]; this object only adds the rerank-specific
 * surface (`rerank`). Mirrors Swift `CppBridge.Rerank`.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.RerankRequest
import ai.runanywhere.proto.v1.RerankResult
import com.runanywhere.sdk.foundation.bridge.ComponentActor
import com.runanywhere.sdk.foundation.bridge.ComponentVTable
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RARerankRequest
import com.runanywhere.sdk.public.types.RARerankResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Mirrors Swift `CppBridge.Rerank`. Wraps `rac_rerank_component_*` C ABI. Handle
 * lifecycle lives in [inner]; scoring loads the lifecycle-resolved model into
 * the component handle, then dispatches the handle-scoped proto verb.
 */
object CppBridgeRerank {
    /** Generic scaffold (handle / isLoaded / loadModel / unload / destroy). */
    private val inner = ComponentActor(ComponentVTable.rerank)

    private val logger = SDKLogger("CppBridge.Rerank")

    // MARK: - Handle Management

    /** Get or create the rerank component handle. */
    suspend fun getHandle(): Long = inner.getHandle()

    /** Currently-loaded model id, or null. */
    val currentModelId: String?
        get() = inner.currentAssetId

    // MARK: - Model Lifecycle

    /** Unload the current model. */
    suspend fun unload() {
        inner.unload()
    }

    /** Destroy the component. */
    suspend fun destroy() {
        inner.destroy()
    }

    // MARK: - Offline rerank

    /**
     * Score every candidate against the query with the currently-loaded
     * cross-encoder model, returning them ordered by descending relevance.
     *
     * Mirrors iOS Swift's `CppBridge.Rerank.rerank(_:loadedModel:)`: the
     * lifecycle-resolved model is loaded into the component handle (owner-scoped
     * acquire), then the serialized `RerankRequest` is scored through
     * `rac_rerank_component_rerank_proto`.
     */
    suspend fun rerank(
        request: RARerankRequest,
        loadedModel: ComponentLifecycleSnapshot,
    ): RARerankResult {
        prepareHandle(loadedModel)
        val handle = getHandle()

        val payload =
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhereBridge.racRerankComponentRerankProto(
                        handle,
                        RerankRequest.ADAPTER.encode(request),
                    )
                }
            } catch (error: SDKException) {
                throw error
            } catch (error: Throwable) {
                throw SDKException.operation(
                    "Rerank failed: ${error.message ?: error::class.java.simpleName}",
                    error,
                )
            } ?: throw SDKException.operation(
                "racRerankComponentRerankProto returned null",
            )

        return try {
            RerankResult.ADAPTER.decode(payload)
        } catch (error: Exception) {
            throw SDKException.operation(
                "Failed to decode racRerankComponentRerankProto result: ${error.message}",
                error,
            )
        }
    }

    /**
     * Load the lifecycle-resolved rerank model into the component handle. The
     * snapshot is produced by [componentLifecycleSnapshot] keyed by
     * `SDK_COMPONENT_RERANK` (there is no `MODEL_CATEGORY_RERANK`).
     */
    private suspend fun prepareHandle(snapshot: ComponentLifecycleSnapshot) {
        val model = snapshot.model
        val modelId = snapshot.model_id.ifEmpty { model?.id.orEmpty() }
        val modelName = model?.name?.ifEmpty { modelId } ?: modelId
        val modelPath = snapshot.resolved_path.ifEmpty { model?.local_path.orEmpty() }
        if (modelId.isEmpty() || modelPath.isEmpty()) {
            throw SDKException.modelLoadFailed(
                modelId = modelId,
                reason = "Loaded rerank model is missing a resolved path",
            )
        }

        if (currentModelId == modelId) {
            return
        }

        inner.loadModel(path = modelPath, id = modelId, name = modelName)
        logger.info("Rerank model loaded: $modelId")
    }
}
