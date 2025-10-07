package com.runanywhere.sdk.routing

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Decision engine for intelligent routing
 * Makes routing decisions based on multiple factors
 */
class RoutingDecisionEngine {

    private val logger = SDKLogger("RoutingDecisionEngine")

    /**
     * Make a routing decision based on request analysis and configuration
     */
    fun decide(
        request: RoutingRequest,
        analysis: RequestAnalysis,
        config: RoutingConfiguration
    ): RoutingDecision {

        // Check for forced routing (testing/debugging)
        config.forceTarget?.let { target ->
            return RoutingDecision(
                target = target,
                reason = "Forced routing to $target",
                confidence = 1.0f
            )
        }

        // Calculate scores for each target
        val onDeviceScore = calculateOnDeviceScore(analysis, config)
        val cloudScore = calculateCloudScore(analysis, config)

        // Privacy override - always use on-device for PII
        if (config.alwaysOnDeviceForPII && request.containsPII) {
            return RoutingDecision(
                target = RoutingTarget.ON_DEVICE,
                reason = "PII detected - privacy policy requires on-device processing",
                confidence = 1.0f
            )
        }

        // Privacy threshold check
        if (analysis.privacyScore > config.privacyThreshold) {
            return RoutingDecision(
                target = RoutingTarget.ON_DEVICE,
                reason = "Privacy score (${analysis.privacyScore}) exceeds threshold",
                confidence = 0.9f
            )
        }

        // Latency requirement check
        if (analysis.latencyRequirement == LatencyRequirement.REAL_TIME) {
            return RoutingDecision(
                target = RoutingTarget.ON_DEVICE,
                reason = "Real-time latency requirement",
                confidence = 0.95f,
                estimatedLatencyMs = 50L
            )
        }

        // Cost optimization
        if (config.enableCostOptimization && analysis.costSensitivity == CostSensitivity.HIGH) {
            return RoutingDecision(
                target = RoutingTarget.ON_DEVICE,
                reason = "Cost optimization - high sensitivity",
                confidence = 0.85f,
                estimatedCost = 0f
            )
        }

        // Quality requirement check
        if (analysis.qualityRequirement == QualityRequirement.HIGH && cloudScore > onDeviceScore * 1.5) {
            if (config.allowCloudFallback) {
                val estimatedCost = estimateCost(analysis.estimatedTokens)
                if (estimatedCost <= config.maxCloudCostPerRequest) {
                    return RoutingDecision(
                        target = RoutingTarget.CLOUD,
                        reason = "High quality requirement - cloud offers better quality",
                        confidence = 0.8f,
                        estimatedCost = estimatedCost,
                        estimatedLatencyMs = 500L
                    )
                }
            }
        }

        // Default decision based on scores
        val target = if (onDeviceScore >= cloudScore) {
            RoutingTarget.ON_DEVICE
        } else if (config.allowCloudFallback) {
            RoutingTarget.CLOUD
        } else {
            RoutingTarget.ON_DEVICE // Fallback to on-device if cloud not allowed
        }

        val confidence = kotlin.math.abs(onDeviceScore - cloudScore) /
                        (onDeviceScore + cloudScore).coerceAtLeast(0.01f)

        return RoutingDecision(
            target = target,
            reason = "Score-based decision (on-device: %.2f, cloud: %.2f)".format(onDeviceScore, cloudScore),
            confidence = confidence,
            estimatedCost = if (target == RoutingTarget.CLOUD) estimateCost(analysis.estimatedTokens) else 0f,
            estimatedLatencyMs = if (target == RoutingTarget.CLOUD) 500L else 100L
        )
    }

    /**
     * Calculate score for on-device execution
     */
    private fun calculateOnDeviceScore(
        analysis: RequestAnalysis,
        config: RoutingConfiguration
    ): Float {
        var score = 0f

        // Privacy bonus
        score += analysis.privacyScore * 30f

        // Latency bonus
        score += when (analysis.latencyRequirement) {
            LatencyRequirement.REAL_TIME -> 40f
            LatencyRequirement.LOW -> 30f
            LatencyRequirement.MEDIUM -> 20f
            LatencyRequirement.FLEXIBLE -> 10f
        }

        // Cost bonus
        score += when (analysis.costSensitivity) {
            CostSensitivity.HIGH -> 30f
            CostSensitivity.MEDIUM -> 20f
            CostSensitivity.LOW -> 10f
        }

        // Configuration preference
        if (config.preferOnDevice) {
            score += 20f
        }

        // Token size penalty (large requests may be slow on device)
        if (analysis.estimatedTokens > 1000) {
            score -= 10f
        }

        return score.coerceAtLeast(0f)
    }

    /**
     * Calculate score for cloud execution
     */
    private fun calculateCloudScore(
        analysis: RequestAnalysis,
        config: RoutingConfiguration
    ): Float {
        var score = 0f

        // Quality bonus
        score += when (analysis.qualityRequirement) {
            QualityRequirement.HIGH -> 40f
            QualityRequirement.MEDIUM -> 25f
            QualityRequirement.STANDARD -> 15f
        }

        // Large request bonus (cloud handles better)
        if (analysis.estimatedTokens > 1000) {
            score += 20f
        }

        // Flexibility bonus
        if (analysis.latencyRequirement == LatencyRequirement.FLEXIBLE) {
            score += 15f
        }

        // Configuration preference
        if (!config.preferOnDevice) {
            score += 20f
        }

        // Privacy penalty
        score -= analysis.privacyScore * 25f

        // Cost penalty
        if (analysis.costSensitivity == CostSensitivity.HIGH) {
            score -= 20f
        }

        // Availability check
        if (!config.allowCloudFallback) {
            score = 0f
        }

        return score.coerceAtLeast(0f)
    }

    /**
     * Estimate cost for cloud execution
     */
    private fun estimateCost(tokens: Int): Float {
        // Simple cost model: $0.002 per 1K tokens
        return (tokens / 1000f) * 0.002f
    }
}

/**
 * Routing metrics collector
 */
class RoutingMetrics {
    private var totalRequests = 0L
    private var onDeviceRequests = 0L
    private var cloudRequests = 0L
    private var hybridRequests = 0L
    private var totalCost = 0.0
    private var totalLatency = 0L

    fun recordDecision(decision: RoutingDecision) {
        totalRequests++
        when (decision.target) {
            RoutingTarget.ON_DEVICE -> onDeviceRequests++
            RoutingTarget.CLOUD -> {
                cloudRequests++
                totalCost += decision.estimatedCost
            }
            RoutingTarget.HYBRID -> hybridRequests++
        }
        totalLatency += decision.estimatedLatencyMs
    }

    fun getStatistics(): RoutingStatistics {
        val avgLatency = if (totalRequests > 0) totalLatency / totalRequests else 0L
        val onDevicePercentage = if (totalRequests > 0) {
            (onDeviceRequests * 100f) / totalRequests
        } else 0f

        return RoutingStatistics(
            totalRequests = totalRequests,
            onDeviceRequests = onDeviceRequests,
            cloudRequests = cloudRequests,
            hybridRequests = hybridRequests,
            totalCost = totalCost,
            averageLatencyMs = avgLatency,
            onDevicePercentage = onDevicePercentage
        )
    }
}

/**
 * Routing statistics
 */
data class RoutingStatistics(
    val totalRequests: Long,
    val onDeviceRequests: Long,
    val cloudRequests: Long,
    val hybridRequests: Long,
    val totalCost: Double,
    val averageLatencyMs: Long,
    val onDevicePercentage: Float
)
