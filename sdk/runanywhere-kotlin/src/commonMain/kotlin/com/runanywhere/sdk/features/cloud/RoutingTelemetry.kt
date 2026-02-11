/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry events for routing decisions and cloud usage.
 * Mirrors Swift RoutingTelemetry.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.EventDestination
import com.runanywhere.sdk.public.events.SDKEvent
import com.runanywhere.sdk.public.extensions.Cloud.ExecutionTarget
import com.runanywhere.sdk.public.extensions.Cloud.HandoffReason
import com.runanywhere.sdk.public.extensions.Cloud.RoutingMode
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Event emitted when a routing decision is made.
 */
@OptIn(ExperimentalUuidApi::class)
data class RoutingEvent(
    val routingMode: RoutingMode,
    val executionTarget: ExecutionTarget,
    val confidence: Float,
    val cloudHandoffTriggered: Boolean,
    val handoffReason: HandoffReason,
    val cloudProviderId: String? = null,
    val cloudModel: String? = null,
    val latencyMs: Double,
    val estimatedCostUSD: Double? = null,
) : SDKEvent {
    override val id: String = Uuid.random().toString()
    override val type: String = "routing.decision"
    override val category: EventCategory = EventCategory.LLM
    override val timestamp: Long = System.currentTimeMillis()
    override val sessionId: String? = null
    override val destination: EventDestination = EventDestination.ALL
    override val properties: Map<String, String>
        get() = buildMap {
            put("routing_mode", routingMode.value)
            put("execution_target", executionTarget.value)
            put("confidence", "%.4f".format(confidence))
            put("cloud_handoff", cloudHandoffTriggered.toString())
            put("handoff_reason", handoffReason.code.toString())
            put("latency_ms", "%.1f".format(latencyMs))
            cloudProviderId?.let { put("cloud_provider_id", it) }
            cloudModel?.let { put("cloud_model", it) }
            estimatedCostUSD?.let { put("estimated_cost_usd", "%.6f".format(it)) }
        }
}

/**
 * Event emitted when a cloud request incurs cost.
 */
@OptIn(ExperimentalUuidApi::class)
data class CloudCostEvent(
    val providerId: String,
    val inputTokens: Int,
    val outputTokens: Int,
    val costUSD: Double,
    val cumulativeTotalUSD: Double,
) : SDKEvent {
    override val id: String = Uuid.random().toString()
    override val type: String = "cloud.cost"
    override val category: EventCategory = EventCategory.LLM
    override val timestamp: Long = System.currentTimeMillis()
    override val sessionId: String? = null
    override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    override val properties: Map<String, String>
        get() = mapOf(
            "provider_id" to providerId,
            "input_tokens" to inputTokens.toString(),
            "output_tokens" to outputTokens.toString(),
            "cost_usd" to "%.6f".format(costUSD),
            "cumulative_total_usd" to "%.6f".format(cumulativeTotalUSD),
        )
}

/**
 * Event emitted when a provider failover occurs.
 */
@OptIn(ExperimentalUuidApi::class)
data class ProviderFailoverEvent(
    val failedProviderId: String,
    val fallbackProviderId: String? = null,
    val failureReason: String,
) : SDKEvent {
    override val id: String = Uuid.random().toString()
    override val type: String = "cloud.provider_failover"
    override val category: EventCategory = EventCategory.LLM
    override val timestamp: Long = System.currentTimeMillis()
    override val sessionId: String? = null
    override val destination: EventDestination = EventDestination.ALL
    override val properties: Map<String, String>
        get() = buildMap {
            put("failed_provider_id", failedProviderId)
            put("failure_reason", failureReason)
            fallbackProviderId?.let { put("fallback_provider_id", it) }
        }
}

/**
 * Event emitted when a latency timeout triggers cloud fallback.
 */
@OptIn(ExperimentalUuidApi::class)
data class LatencyTimeoutEvent(
    val maxLatencyMs: Long,
    val actualLatencyMs: Double,
) : SDKEvent {
    override val id: String = Uuid.random().toString()
    override val type: String = "routing.latency_timeout"
    override val category: EventCategory = EventCategory.LLM
    override val timestamp: Long = System.currentTimeMillis()
    override val sessionId: String? = null
    override val destination: EventDestination = EventDestination.ALL
    override val properties: Map<String, String>
        get() = mapOf(
            "max_latency_ms" to maxLatencyMs.toString(),
            "actual_latency_ms" to "%.1f".format(actualLatencyMs),
        )
}
