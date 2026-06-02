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
 *     (`rac_get_model`) so the underlying engine (e.g. sherpa) can load
 *     the corresponding model files.
 *   - For [ModelType.ONLINE]: looked up in the cloud backend registry
 *     (`BACKEND.CLOUD`) to fetch the model string + credentials + provider.
 *
 * Construct via the [ROUTER.OFFLINE] / [ROUTER.ONLINE] convenience
 * properties to keep [modelType] correct by construction.
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
    /** On-device backend (e.g. sherpa). */
    OFFLINE(1),

    /** Cloud backend (e.g. the Sarvam provider). */
    ONLINE(2),
}

/**
 * Convenience accessor for the two model types:
 *
 *     RACModel(id = "sherpa-onnx-whisper-tiny.en", modelType = ROUTER.OFFLINE)
 *     RACModel(id = "saaras", modelType = ROUTER.ONLINE)
 */
object ROUTER {
    /** Shortcut for [ModelType.OFFLINE]. */
    val OFFLINE: ModelType = ModelType.OFFLINE

    /** Shortcut for [ModelType.ONLINE]. */
    val ONLINE: ModelType = ModelType.ONLINE
}
