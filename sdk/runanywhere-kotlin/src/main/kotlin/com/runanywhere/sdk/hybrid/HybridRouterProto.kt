/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Shared protobuf marshalling for the hybrid router — the descriptor and
 * routing-policy encoders are capability-agnostic and reused by the STT
 * router (see HybridSttRouterProto for the STT request/response shapes).
 *
 * Both functions are pure — no state, no I/O. Custom filter definitions are
 * extracted into PackedPolicy.customFilters so the router can register each
 * one's predicate by name with the commons callback table (the policy proto
 * carries only the filter's name/description; commons invokes the predicate
 * during filtering).
 */

package com.runanywhere.sdk.hybrid

import ai.runanywhere.proto.v1.BatteryFilter
import ai.runanywhere.proto.v1.ConfidenceCascade
import ai.runanywhere.proto.v1.CustomFilter
import ai.runanywhere.proto.v1.HybridInferenceMode
import ai.runanywhere.proto.v1.HybridModelDescriptor
import ai.runanywhere.proto.v1.HybridCascade as HybridCascadeProto
import ai.runanywhere.proto.v1.HybridFilter as HybridFilterProto
import ai.runanywhere.proto.v1.HybridRoutingPolicy as HybridRoutingPolicyProto

/**
 * Output of [HybridRouterProto.policy]. Carries the serialised policy bytes
 * for the native side plus any [HybridFilter.Custom] filters extracted so the
 * router can register each predicate by name with the commons custom-filter
 * callback table.
 */
internal class PackedPolicy(
    val bytes: ByteArray,
    val customFilters: List<HybridFilter.Custom>,
)

internal object HybridRouterProto {
    /**
     * Serialise a [HybridModel] as a HybridModelDescriptor. Native side
     * decodes via runanywhere::v1::HybridModelDescriptor::ParseFromArray.
     *
     * `HybridModelDescriptor.backend`/`.provider` are deleted outright
     * (idl/hybrid_router.proto), replaced by a single `engine: string` field
     * so a new backend name is not a proto change; `is_local` was renamed
     * `is_on_device`. Mirrors Swift's `HybridModel.descriptorBytes()`.
     */
    fun descriptor(model: HybridModel): ByteArray {
        val msg =
            HybridModelDescriptor(
                model_id = model.id,
                is_on_device = model.isLocal,
                engine = model.backend,
            )
        return HybridModelDescriptor.ADAPTER.encode(msg)
    }

    /**
     * Marshal a [HybridRoutingPolicy] into HybridRoutingPolicy bytes plus the
     * list of [HybridFilter.Custom] filters the router must register with the
     * commons callback table.
     *
     * `prefer_local` is deleted outright (idl/hybrid_router.proto), replaced
     * by `mode: HybridInferenceMode`. commons
     * (rac_stt_hybrid_router_proto.cpp) has not wired up a `models` list
     * consumer yet -- it still drives routing off the two separately
     * registered offline/online service descriptors and reads only `mode`
     * from this policy to decide rank direction. Anything other than
     * PREFER_IN_CLOUD/ONLY_IN_CLOUD is treated as local-first, so
     * `preferLocal = true` maps to PREFER_ON_DEVICE and `false` to
     * PREFER_IN_CLOUD to preserve the exact old behavior. Mirrors Swift's
     * `HybridRoutingPolicy.serializedBytes()`.
     */
    fun policy(policy: HybridRoutingPolicy): PackedPolicy {
        val msg =
            HybridRoutingPolicyProto(
                cascade = policy.cascade?.let(::cascadeToProto),
                mode =
                    if (policy.preferLocal) {
                        HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE
                    } else {
                        HybridInferenceMode.HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD
                    },
                hard_filters = policy.hardFilters.map(::filterToProto),
            )
        return PackedPolicy(
            bytes = HybridRoutingPolicyProto.ADAPTER.encode(msg),
            customFilters = policy.hardFilters.filterIsInstance<HybridFilter.Custom>(),
        )
    }

    // Internal mappers

    private fun filterToProto(filter: HybridFilter): HybridFilterProto =
        when (filter) {
            is HybridFilter.Network ->
                HybridFilterProto(network = true)
            // HybridFilter's oneof only has network/battery/custom arms
            // (idl/hybrid_router.proto) -- there has never been a wire slot
            // for a quality tier. Matches this case's own doc comment: "v1
            // descriptors carry no quality tier, so commons treats this as
            // a no-op today." Nothing to encode.
            is HybridFilter.Quality -> HybridFilterProto()
            is HybridFilter.Battery ->
                HybridFilterProto(battery = BatteryFilter(min_battery_percent = filter.minPercent))
            is HybridFilter.Custom ->
                HybridFilterProto(custom = CustomFilter(name = filter.name, description = filter.description))
        }

    private fun cascadeToProto(cascade: HybridCascade): HybridCascadeProto =
        when (cascade) {
            is HybridCascade.Confidence ->
                HybridCascadeProto(confidence = ConfidenceCascade(threshold = cascade.threshold))
        }
}
