/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public model descriptor used in router.<capability>.addPair(...).
 * Mirrors HybridModelDescriptor in idl/hybrid_router.proto.
 */

package com.runanywhere.sdk.public.hybrid

/**
 * Identifies one of the two models a hybrid router dispatches between.
 *
 * `id` is the lookup key the SDK uses to resolve the concrete backend
 * resource:
 *   - For [ModelType.OFFLINE]: forwarded to the C model registry
 *     (`rac_get_model`) so the underlying engine (e.g. llama.cpp) can
 *     load the corresponding gguf.
 *   - For [ModelType.ONLINE]: looked up in `BACKEND.OPENROUTER` to fetch
 *     the OpenRouter model string + credentials.
 *
 * Construct via the [offline] / [online] convenience properties on
 * `ROUTER` to keep [modelType] correct by construction.
 *
 * @property id        Registry identifier shared with the SDK.
 * @property modelType Whether this side of the pair runs on-device or in the cloud.
 */
class RACModel(
    val id: String,
    val modelType: ModelType,
)

/**
 * Whether a registered model is served on-device or via a cloud backend.
 * Wire values match `HybridModelType` in idl/hybrid_router.proto.
 */
enum class ModelType(val value: Int) {
    /** On-device backend (e.g. llama.cpp). */
    OFFLINE(1),

    /** Cloud backend (e.g. OpenRouter). */
    ONLINE(2),
}

/**
 * Convenience accessor mirroring the file.txt sketch:
 *
 *     RACModel(id = "llama-1.2b", modelType = ROUTER.OFFLINE)
 *     RACModel(id = "claude-haiku", modelType = ROUTER.ONLINE)
 */
object ROUTER {
    /** Shortcut for [ModelType.OFFLINE]. */
    val OFFLINE: ModelType = ModelType.OFFLINE

    /** Shortcut for [ModelType.ONLINE]. */
    val ONLINE: ModelType = ModelType.ONLINE
}
