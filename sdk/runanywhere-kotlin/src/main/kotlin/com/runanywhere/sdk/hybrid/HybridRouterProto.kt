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
     * The descriptor's `provider` field carries [HybridModel.provider] for a
     * `HYBRID_BACKEND_CLOUD` backend (e.g. "sarvam"); empty for non-cloud
     * backends, where the field is ignored.
     */
    fun descriptor(model: HybridModel): ByteArray {
        val msg =
            HybridModelDescriptor(
                model_id = model.id,
                model_type = model.modelType,
                backend = model.backend,
                provider = model.provider,
            )
        return HybridModelDescriptor.ADAPTER.encode(msg)
    }

    /**
     * Marshal a [HybridRoutingPolicy] into HybridRoutingPolicy bytes plus the
     * list of [HybridFilter.Custom] filters the router must register with the
     * commons callback table.
     */
    fun policy(policy: HybridRoutingPolicy): PackedPolicy {
        val msg =
            HybridRoutingPolicyProto(
                cascade = policy.cascade?.let(::cascadeToProto),
                rank = policy.rank,
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
            is HybridFilter.Quality ->
                HybridFilterProto(quality_tier = filter.tier)
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
