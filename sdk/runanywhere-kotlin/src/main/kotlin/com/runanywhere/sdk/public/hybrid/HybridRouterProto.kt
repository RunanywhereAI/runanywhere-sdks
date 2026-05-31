/* 
   * Copyright 2026 RunAnywhere SDK
   * SPDX-License-Identifier: Apache-2.0
   *
   * Protobuf marshalling for the hybrid router JNI ABI. Replaces the
   * earlier JSON marshalling (HybridRouterJson.kt, deleted in #25).
   *
   * Pairs with rac_hybrid_router_jni.cpp which decodes/encodes the same
   * runanywhere.v1.* messages on the C++ side using the protobuf-generated
   * types under sdk/runanywhere-commons/src/generated/proto/hybrid_router.pb.h.
   *
   * All four functions are pure — no state, no I/O. Custom filter callbacks
   * are extracted into PackedPolicy.customFilters for host-side evaluation
   * since function pointers can't cross JNI.
   */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.BatteryFilter
import ai.runanywhere.proto.v1.ConfidenceCascade
import ai.runanywhere.proto.v1.CustomFilter
import ai.runanywhere.proto.v1.HybridBackendKind
import ai.runanywhere.proto.v1.HybridCascade
import ai.runanywhere.proto.v1.HybridFilter
import ai.runanywhere.proto.v1.HybridLlmGenerateOptions
import ai.runanywhere.proto.v1.HybridLlmGenerateRequest
import ai.runanywhere.proto.v1.HybridLlmGenerateResponse
import ai.runanywhere.proto.v1.HybridModelDescriptor
import ai.runanywhere.proto.v1.HybridModelType
import ai.runanywhere.proto.v1.HybridRank
import ai.runanywhere.proto.v1.HybridRoutingContext
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

    /**
     * Build a HybridLlmGenerateRequest carrying the prompt, the per-request
     * routing context, and the generation options.
     *
     * Device-state fields (is_online, battery_percent, thermal_throttled)
     * live behind the cross-SDK `rac_hybrid_device_state` C ABI vtable
     * (task #22). HybridRoutingContext currently carries no fields; it
     * remains in the wire shape so future per-call hints can be added
     * without changing every caller.
     */
    fun request(prompt: String): ByteArray {
        val context = HybridRoutingContext()
        val options = HybridLlmGenerateOptions(
            max_tokens = 256,
            temperature = 0.7f,
            top_p = 1.0f,
            streaming_enabled = false,
            system_prompt = "",
        )
        val msg = HybridLlmGenerateRequest(
            prompt = prompt,
            context = context,
            options = options,
        )
        return HybridLlmGenerateRequest.ADAPTER.encode(msg)
    }

    /**
     * Decode a HybridLlmGenerateResponse returned by the JNI generate
     * thunk into the public [GenerateResult] shape.
     */
    fun parseResponse(bytes: ByteArray): GenerateResult {
        val msg = HybridLlmGenerateResponse.ADAPTER.decode(bytes)
        val routing = msg.routing
        return GenerateResult(
            text = msg.text,
            routing = RoutedMetadata(
                chosenModelId = routing?.chosen_model_id.orEmpty(),
                wasFallback = routing?.was_fallback ?: false,
                attemptCount = routing?.attempt_count ?: 0,
                primaryErrorCode = routing?.primary_error_code ?: 0,
                primaryErrorMessage = routing?.primary_error_message.orEmpty(),
            ),
        )
    }

    // ----------------------------------------------------------------------
    // Internal mappers
    // ----------------------------------------------------------------------

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
        1 -> HybridBackendKind.HYBRID_BACKEND_LLAMACPP
        2 -> HybridBackendKind.HYBRID_BACKEND_OPENROUTER
        else -> HybridBackendKind.HYBRID_BACKEND_UNSPECIFIED
    }
}
