/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public model descriptor used in router.<capability>.addPair(...).
 * Mirrors HybridModelDescriptor in idl/hybrid_router.proto.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.HybridModelType

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
 *
 * Aliased to the generated [HybridModelType] (the wire schema's
 * `HybridModelType` in idl/hybrid_router.proto) so the wire numbering is
 * maintained in one place. [ROUTER.OFFLINE] / [ROUTER.ONLINE] keep the
 * ergonomic short names; `RACModel.modelType` carries the proto enum directly,
 * so descriptor marshalling needs no Kotlin→proto translation.
 */
typealias ModelType = HybridModelType

/**
 * Convenience accessor for the two model types:
 *
 *     RACModel(id = "sherpa-onnx-whisper-tiny.en", modelType = ROUTER.OFFLINE)
 *     RACModel(id = "saaras", modelType = ROUTER.ONLINE)
 */
object ROUTER {
    /** Shortcut for the offline (on-device) model type. */
    val OFFLINE: ModelType = HybridModelType.HYBRID_MODEL_TYPE_OFFLINE

    /** Shortcut for the online (cloud) model type. */
    val ONLINE: ModelType = HybridModelType.HYBRID_MODEL_TYPE_ONLINE
}
