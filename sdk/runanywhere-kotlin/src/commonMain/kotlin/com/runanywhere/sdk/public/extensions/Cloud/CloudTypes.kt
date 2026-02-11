/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Types for cloud provider infrastructure and routing.
 * Mirrors Swift CloudTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Cloud

import kotlinx.serialization.Serializable

// MARK: - Routing Mode

/**
 * Routing mode for inference requests.
 * Mirrors Swift RoutingMode exactly.
 */
@Serializable
enum class RoutingMode(val value: String) {
    /** Never use cloud - all inference on-device only */
    ALWAYS_LOCAL("always_local"),

    /** Always use cloud - skip on-device inference */
    ALWAYS_CLOUD("always_cloud"),

    /** On-device first, auto-fallback to cloud on low confidence */
    HYBRID_AUTO("hybrid_auto"),

    /** On-device first, return handoff signal for app to decide */
    HYBRID_MANUAL("hybrid_manual"),
}

// MARK: - Execution Target

/**
 * Where inference was actually executed.
 * Mirrors Swift ExecutionTarget exactly.
 */
@Serializable
enum class ExecutionTarget(val value: String) {
    ON_DEVICE("on_device"),
    CLOUD("cloud"),
    HYBRID_FALLBACK("hybrid_fallback"),
}

// MARK: - Handoff Reason

/**
 * Reason why the on-device engine recommended cloud handoff.
 * Mirrors Swift HandoffReason exactly.
 */
@Serializable
enum class HandoffReason(val code: Int) {
    /** No handoff needed */
    NONE(0),

    /** First token had low confidence */
    FIRST_TOKEN_LOW_CONFIDENCE(1),

    /** Rolling window showed degrading confidence */
    ROLLING_WINDOW_DEGRADATION(2),
    ;

    companion object {
        fun fromCode(code: Int): HandoffReason = entries.find { it.code == code } ?: NONE
    }
}

// MARK: - Routing Policy

/**
 * Policy controlling how requests are routed between on-device and cloud.
 * Mirrors Swift RoutingPolicy exactly.
 */
data class RoutingPolicy(
    /** Routing mode */
    val mode: RoutingMode = RoutingMode.HYBRID_MANUAL,
    /** Confidence threshold for cloud handoff (0.0 - 1.0). Only relevant for hybrid modes. */
    val confidenceThreshold: Float = 0.7f,
    /** Max on-device time-to-first-token before cloud fallback (ms). 0 = no limit. */
    val maxLocalLatencyMs: Long = 0,
    /** Max cloud cost per request in USD. 0.0 = no cap. */
    val costCapUSD: Float = 0.0f,
    /** Whether to prefer streaming for cloud calls */
    val preferStreaming: Boolean = true,
) {
    companion object {
        /** Always run on-device, never use cloud */
        val LOCAL_ONLY = RoutingPolicy(mode = RoutingMode.ALWAYS_LOCAL, confidenceThreshold = 0.0f)

        /** Always use cloud provider */
        val CLOUD_ONLY = RoutingPolicy(mode = RoutingMode.ALWAYS_CLOUD, confidenceThreshold = 0.0f)

        /** Hybrid mode with automatic cloud fallback */
        fun hybridAuto(confidenceThreshold: Float = 0.7f) =
            RoutingPolicy(mode = RoutingMode.HYBRID_AUTO, confidenceThreshold = confidenceThreshold)

        /** Hybrid mode returning handoff signal (app decides) */
        fun hybridManual(confidenceThreshold: Float = 0.7f) =
            RoutingPolicy(mode = RoutingMode.HYBRID_MANUAL, confidenceThreshold = confidenceThreshold)
    }
}

// MARK: - Routing Decision

/**
 * Metadata about how a generation request was routed.
 * Mirrors Swift RoutingDecision exactly.
 */
data class RoutingDecision(
    /** Where inference was executed */
    val executionTarget: ExecutionTarget,
    /** The routing policy that was applied */
    val policy: RoutingPolicy,
    /** On-device confidence score (0.0 - 1.0) */
    val onDeviceConfidence: Float = 1.0f,
    /** Whether cloud handoff was triggered */
    val cloudHandoffTriggered: Boolean = false,
    /** Reason for cloud handoff */
    val handoffReason: HandoffReason = HandoffReason.NONE,
    /** Cloud provider ID used (null if on-device only) */
    val cloudProviderId: String? = null,
    /** Cloud model used (null if on-device only) */
    val cloudModel: String? = null,
)

// MARK: - Cloud Generation Options

/**
 * Options specific to cloud-based generation.
 * Mirrors Swift CloudGenerationOptions exactly.
 */
data class CloudGenerationOptions(
    /** Cloud model identifier (e.g., "gpt-4o-mini") */
    val model: String,
    /** Maximum tokens to generate */
    val maxTokens: Int = 1024,
    /** Temperature for sampling */
    val temperature: Float = 0.7f,
    /** System prompt */
    val systemPrompt: String? = null,
    /** Messages in chat format (role, content pairs) */
    val messages: List<ChatMessage>? = null,
)

/**
 * A single chat message with role and content.
 * Replaces Swift's tuple (role: String, content: String).
 */
@Serializable
data class ChatMessage(
    val role: String,
    val content: String,
)

// MARK: - Cloud Generation Result

/**
 * Result from cloud-based generation.
 * Mirrors Swift CloudGenerationResult exactly.
 */
data class CloudGenerationResult(
    /** Generated text */
    val text: String,
    /** Tokens used (input) */
    val inputTokens: Int = 0,
    /** Tokens used (output) */
    val outputTokens: Int = 0,
    /** Total latency in milliseconds */
    val latencyMs: Double = 0.0,
    /** Provider that handled the request */
    val providerId: String,
    /** Model used */
    val model: String,
    /** Estimated cost in USD (null if unknown) */
    val estimatedCostUSD: Double? = null,
)

// MARK: - Routed Results

/**
 * Generation result enriched with routing metadata.
 * Mirrors Swift RoutedGenerationResult exactly.
 */
data class RoutedGenerationResult(
    /** The generation result */
    val generationResult: com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult,
    /** How the request was routed */
    val routingDecision: RoutingDecision,
)

/**
 * Streaming result enriched with routing metadata.
 * Mirrors Swift RoutedStreamingResult exactly.
 */
data class RoutedStreamingResult(
    /** The streaming result */
    val streamingResult: com.runanywhere.sdk.public.extensions.LLM.LLMStreamingResult,
    /** How the request was routed */
    val routingDecision: RoutingDecision,
)
