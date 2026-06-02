/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Shared protobuf marshalling for the hybrid router — the descriptor and
 * routing-policy encoders are capability-agnostic and reused by the STT
 * router (see HybridSttRouterProto for the STT request/response shapes).
 *
 * Both functions are pure — no state, no I/O. Custom filter callbacks are
 * extracted into PackedPolicy.customFilters for host-side evaluation since
 * function pointers can't cross JNI.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.BatteryFilter
import ai.runanywhere.proto.v1.ConfidenceCascade
import ai.runanywhere.proto.v1.CustomFilter
import ai.runanywhere.proto.v1.HybridBackendKind
import ai.runanywhere.proto.v1.HybridCascade
import ai.runanywhere.proto.v1.HybridFilter
import ai.runanywhere.proto.v1.HybridModelDescriptor
import ai.runanywhere.proto.v1.HybridModelType
import ai.runanywhere.proto.v1.HybridRank
import ai.runanywhere.proto.v1.HybridRoutingPolicy


/**
 * Output of [HybridRouterProto.policy]. Carries the serialised policy
 * bytes for the native side plus any [RACRouter.RoutingPolicy.CustomDefine]
 * filters extracted for host-side evaluation (callbacks can't cross JNI).
 */
internal data class PackedPolicy(
    val bytes: ByteArray,
    val customFilters: List<RACRouter.RoutingPolicy.CustomDefine>,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as PackedPolicy

        if (!bytes.contentEquals(other.bytes)) return false
        if (customFilters != other.customFilters) return false

        return true
    }

    override fun hashCode(): Int {
        var result = bytes.contentHashCode()
        result = 31 * result + customFilters.hashCode()
        return result
    }
}

internal object HybridRouterProto {

    /**
     * Serialise a [RACModel] + backend wire kind as a HybridModelDescriptor.
     * Native side decodes via runanywhere::v1::HybridModelDescriptor::ParseFromArray.
     */
    fun descriptor(model: RACModel, backendKind: Int): ByteArray {
        val msg = HybridModelDescriptor(
            model_id = model.id,
            model_type = model.modelType.toProto(),
            backend = backendKindFromInt(backendKind),
        )
        return HybridModelDescriptor.ADAPTER.encode(msg)
    }

    /**
     * Marshal a [RACRouter.SimpleRouterPolicy] or [RACRouter.AdvanceRouterPolicy]
     * into HybridRoutingPolicy bytes plus the host-side CustomDefine list.
     */
    fun policy(policy: RACRouter.RouterPolicyBase): PackedPolicy {
        val filters = mutableListOf<HybridFilter>()
        val customs = mutableListOf<RACRouter.RoutingPolicy.CustomDefine>()
        var cascade: HybridCascade? = null
        var rank: HybridRank = HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST

        when (policy) {
            is RACRouter.SimpleRouterPolicy -> {
                policy.filter?.let { filters.add(filterToProto(it, customs)) }
                policy.cascade?.let { cascade = cascadeToProto(it) }
                policy.rank?.let { rank = it.toProto() }
            }
            is RACRouter.AdvanceRouterPolicy -> {
                for (f in policy.hardFilters) {
                    filters.add(filterToProto(f, customs))
                }
                policy.cascadeConditions?.let { cascade = cascadeToProto(it) }
                policy.rankSort?.let { rank = it.toProto() }
            }
        }

        val msg = HybridRoutingPolicy(
            cascade = cascade,
            rank = rank,
            hard_filters = filters,
        )
        return PackedPolicy(
            bytes = HybridRoutingPolicy.ADAPTER.encode(msg),
            customFilters = customs,
        )
    }

    // Internal mappers

    private fun filterToProto(
        filter: RACRouter.Filter,
        customs: MutableList<RACRouter.RoutingPolicy.CustomDefine>,
    ): HybridFilter = when (filter) {
        is RACRouter.RoutingPolicy.NETWORK ->
            HybridFilter(network = true)
        is RACRouter.RoutingPolicy.Quality ->
            HybridFilter(quality_tier = filter.tier)
        is RACRouter.RoutingPolicy.Battery ->
            HybridFilter(battery = BatteryFilter(min_battery_percent = filter.minPercent))
        is RACRouter.RoutingPolicy.CustomDefine -> {
            customs.add(filter)
            HybridFilter(custom = CustomFilter(name = filter.name, description = filter.description))
        }
        else -> HybridFilter()
    }

    private fun cascadeToProto(cascade: RACRouter.Cascade): HybridCascade = when (cascade) {
        is RACRouter.RoutingPolicy.Confidence ->
            HybridCascade(confidence = ConfidenceCascade(threshold = cascade.threshold))
        else -> HybridCascade()
    }

    private fun ModelType.toProto(): HybridModelType = when (this) {
        ModelType.OFFLINE -> HybridModelType.HYBRID_MODEL_TYPE_OFFLINE
        ModelType.ONLINE -> HybridModelType.HYBRID_MODEL_TYPE_ONLINE
    }

    private fun RACRouter.Rank.toProto(): HybridRank = when (this) {
        RACRouter.Rank.PreferLocalFirst -> HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST
        RACRouter.Rank.PreferOnlineFirst -> HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST
    }

    private fun backendKindFromInt(kind: Int): HybridBackendKind = when (kind) {
        3 -> HybridBackendKind.HYBRID_BACKEND_SHERPA
        4 -> HybridBackendKind.HYBRID_BACKEND_SARVAM
        else -> HybridBackendKind.HYBRID_BACKEND_UNSPECIFIED
    }
}
