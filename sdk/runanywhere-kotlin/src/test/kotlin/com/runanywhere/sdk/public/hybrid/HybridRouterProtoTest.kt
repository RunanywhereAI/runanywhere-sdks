/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Desktop JVM unit tests for HybridRouterProto. Pure Kotlin — no JNI,
 * no native library required. Runs under `./gradlew :testDebugUnitTest`.
 *
 * Replaces the earlier HybridRouterJsonTest. Verifies that the proto
 * encode/decode round-trip preserves descriptor / policy / response
 * semantics.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.HybridBackendKind
import ai.runanywhere.proto.v1.HybridCascade
import ai.runanywhere.proto.v1.HybridFilter
import ai.runanywhere.proto.v1.HybridLlmGenerateRequest
import ai.runanywhere.proto.v1.HybridLlmGenerateResponse
import ai.runanywhere.proto.v1.HybridModelDescriptor
import ai.runanywhere.proto.v1.HybridModelType
import ai.runanywhere.proto.v1.HybridRank
import ai.runanywhere.proto.v1.HybridRoutedMetadata
import ai.runanywhere.proto.v1.HybridRoutingPolicy
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HybridRouterProtoTest {

    @Test
    fun descriptorEncodesIdTypeAndBackend() {
        val bytes = HybridRouterProto.descriptor(
            model = RACModel(id = "llama-1.2b", modelType = ROUTER.OFFLINE),
            backendKind = BACKEND.LLAMACPP.TEXTGEN.kind,
        )
        val msg = HybridModelDescriptor.ADAPTER.decode(bytes)

        assertEquals("llama-1.2b", msg.model_id)
        assertEquals(HybridModelType.HYBRID_MODEL_TYPE_OFFLINE, msg.model_type)
        assertEquals(HybridBackendKind.HYBRID_BACKEND_LLAMACPP, msg.backend)
    }

    @Test
    fun simplePolicyWrapsOneFilterAndDefaultsRankToPreferLocalFirst() {
        val packed = HybridRouterProto.policy(
            RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK()),
        )
        val policy = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)

        assertEquals(1, policy.hard_filters.size)
        val filter = policy.hard_filters[0]
        assertEquals(HybridFilter.KindCase.NETWORK, filter.kind_case)
        assertTrue(filter.network == true)
        assertEquals(HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST, policy.rank)
        assertTrue(packed.customFilters.isEmpty())
    }

    @Test
    fun advancePolicyCarriesFiltersCascadeAndRank() {
        val policy = RACRouter.AdvanceRouterPolicy {
            hardFilters = arrayOf(
                RACRouter.RoutingPolicy.NETWORK(),
                RACRouter.RoutingPolicy.Battery(minPercent = 25),
            )
            cascadeConditions = RACRouter.RoutingPolicy.Confidence(0.6f)
            rankSort = RACRouter.RoutingPolicy.PreferLocalFirst
        }
        val packed = HybridRouterProto.policy(policy)
        val msg = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)

        assertEquals(2, msg.hard_filters.size)
        assertEquals(HybridFilter.KindCase.NETWORK, msg.hard_filters[0].kind_case)
        assertEquals(HybridFilter.KindCase.BATTERY, msg.hard_filters[1].kind_case)
        assertEquals(25, msg.hard_filters[1].battery!!.min_battery_percent)

        val cascade = msg.cascade
        assertNotNull(cascade)
        assertEquals(HybridCascade.KindCase.CONFIDENCE, cascade!!.kind_case)
        assertEquals(0.6f, cascade.confidence!!.threshold, 1e-6f)

        assertEquals(HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST, msg.rank)
    }

    @Test
    fun customDefineFilterIsExtractedForHostSideEvaluation() {
        var checked = false
        val customFilter = RACRouter.RoutingPolicy.CustomDefine(
            name = "battery-saver",
            description = "Block cloud when laptop battery is plugged in",
            check = { _ ->
                checked = true
                true
            },
        )
        val packed = HybridRouterProto.policy(RACRouter.SimpleRouterPolicy(customFilter))

        assertEquals(1, packed.customFilters.size)
        assertEquals("battery-saver", packed.customFilters[0].name)
        assertFalse("policy() must not invoke the callback during serialisation", checked)

        val policy = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)
        assertEquals(1, policy.hard_filters.size)
        val custom = policy.hard_filters[0].custom
        assertNotNull(custom)
        assertEquals("battery-saver", custom!!.name)
        assertEquals("Block cloud when laptop battery is plugged in", custom.description)
    }

    @Test
    fun batteryFilterCarriesMinPercent() {
        val packed = HybridRouterProto.policy(
            RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.Battery(minPercent = 35)),
        )
        val msg = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)
        val battery = msg.hard_filters[0].battery
        assertNotNull(battery)
        assertEquals(35, battery!!.min_battery_percent)
    }

    @Test
    fun preferOnlineFirstRankRoundTrips() {
        val packed = HybridRouterProto.policy(
            RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferOnlineFirst),
        )
        val msg = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)
        assertEquals(HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST, msg.rank)
    }

    @Test
    fun requestPacksPromptContextAndOptions() {
        val bytes = HybridRouterProto.request("Hello world")
        val msg = HybridLlmGenerateRequest.ADAPTER.decode(bytes)

        assertEquals("Hello world", msg.prompt)
        // HybridRoutingContext has no caller-supplied fields today; device
        // state lives behind rac_hybrid_device_state on the native side.
        assertNotNull(msg.context)

        assertNotNull(msg.options)
        assertEquals(256, msg.options!!.max_tokens)
        assertEquals(0.7f, msg.options!!.temperature, 1e-6f)
        assertEquals(1.0f, msg.options!!.top_p, 1e-6f)
        assertFalse(msg.options!!.streaming_enabled)
    }

    @Test
    fun parseResponseExtractsTextAndRoutingMetadata() {
        val bytes = HybridLlmGenerateResponse(
            rc = 0,
            text = "hello from cloud",
            routing = HybridRoutedMetadata(
                chosen_model_id = "openai/gpt-4o-mini",
                was_fallback = true,
                attempt_count = 2,
            ),
            error_msg = "",
        ).let { HybridLlmGenerateResponse.ADAPTER.encode(it) }

        val result = HybridRouterProto.parseResponse(bytes)
        assertEquals("hello from cloud", result.text)
        assertEquals("openai/gpt-4o-mini", result.routing.chosenModelId)
        assertTrue(result.routing.wasFallback)
        assertEquals(2, result.routing.attemptCount)
    }

    @Test
    fun parseResponseHandlesMissingRoutingBlock() {
        val bytes = HybridLlmGenerateResponse(rc = -100, text = "boom", routing = null).let {
            HybridLlmGenerateResponse.ADAPTER.encode(it)
        }
        val result = HybridRouterProto.parseResponse(bytes)
        assertEquals("boom", result.text)
        assertEquals("", result.routing.chosenModelId)
        assertFalse(result.routing.wasFallback)
        assertEquals(0, result.routing.attemptCount)
    }

    @Test
    fun emptyDescriptorBytesProduceEmptyMessageDefaults() {
        // Sanity: encoding a default RACModel should still decode back to
        // a HybridModelDescriptor with empty model_id (not crash).
        val bytes = HybridRouterProto.descriptor(
            model = RACModel(id = "", modelType = ROUTER.ONLINE),
            backendKind = BACKEND.OPENROUTER.TEXTGEN.kind,
        )
        val msg = HybridModelDescriptor.ADAPTER.decode(bytes)
        assertEquals("", msg.model_id)
        assertEquals(HybridModelType.HYBRID_MODEL_TYPE_ONLINE, msg.model_type)
        assertEquals(HybridBackendKind.HYBRID_BACKEND_OPENROUTER, msg.backend)
    }

    @Test
    fun descriptorBytesAreDeterministic() {
        val m = RACModel(id = "lfm2-350m", modelType = ROUTER.OFFLINE)
        val a = HybridRouterProto.descriptor(m, BACKEND.LLAMACPP.TEXTGEN.kind)
        val b = HybridRouterProto.descriptor(m, BACKEND.LLAMACPP.TEXTGEN.kind)
        assertArrayEquals(a, b)

        // Mismatched constructions are distinct.
        val c = HybridRouterProto.descriptor(m, BACKEND.OPENROUTER.TEXTGEN.kind)
        assertFalse(a.contentEquals(c))
    }

    @Test
    fun simplePolicyFromRankOnlyEmitsNoFiltersAndNoCascade() {
        val packed = HybridRouterProto.policy(
            RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferOnlineFirst),
        )
        val msg = HybridRoutingPolicy.ADAPTER.decode(packed.bytes)
        assertTrue(msg.hard_filters.isEmpty())
        assertNull(msg.cascade)
        assertEquals(HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST, msg.rank)
    }
}
