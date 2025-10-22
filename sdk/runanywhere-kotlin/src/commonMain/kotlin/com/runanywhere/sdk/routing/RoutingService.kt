package com.runanywhere.sdk.routing

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.events.EventBus
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Intelligent routing service for on-device vs cloud execution
 * Optimizes for cost, latency, and privacy based on task requirements
 */
class RoutingService(
    private val configuration: RoutingConfiguration = RoutingConfiguration(),
    private val decisionEngine: RoutingDecisionEngine = RoutingDecisionEngine()
) {

    private val logger = SDKLogger("RoutingService")
    private val mutex = Mutex()

    // Routing metrics
    private val routingMetrics = RoutingMetrics()

    /**
     * Route a request to the optimal execution target
     */
    suspend fun route(request: RoutingRequest): RoutingDecision {
        logger.debug("Routing request: ${request.taskType}")

        val decision = mutex.withLock {
            // Analyze request and make routing decision
            val analysis = analyzeRequest(request)
            decisionEngine.decide(request, analysis, configuration)
        }

        // Update metrics
        routingMetrics.recordDecision(decision)

        // Publish routing event
        publishRoutingDecision(decision)

        logger.info("Routed to ${decision.target}: ${decision.reason}")

        return decision
    }

    /**
     * Analyze a request to determine routing factors
     */
    private fun analyzeRequest(request: RoutingRequest): RequestAnalysis {
        return RequestAnalysis(
            estimatedTokens = estimateTokens(request),
            privacyScore = calculatePrivacyScore(request),
            latencyRequirement = determineLatencyRequirement(request),
            qualityRequirement = determineQualityRequirement(request),
            costSensitivity = determineCostSensitivity(request)
        )
    }

    /**
     * Update routing configuration
     */
    suspend fun updateConfiguration(config: RoutingConfiguration) {
        mutex.withLock {
            configuration.apply {
                preferOnDevice = config.preferOnDevice
                maxCloudCostPerRequest = config.maxCloudCostPerRequest
                privacyThreshold = config.privacyThreshold
                latencyThresholdMs = config.latencyThresholdMs
                qualityThreshold = config.qualityThreshold
            }
        }
        logger.info("Routing configuration updated")
    }

    /**
     * Get routing statistics
     */
    fun getStatistics(): RoutingStatistics {
        return routingMetrics.getStatistics()
    }

    /**
     * Force a specific routing target for testing
     */
    suspend fun forceRoute(target: RoutingTarget) {
        mutex.withLock {
            configuration.forceTarget = target
        }
        logger.warning("Forcing routing to: $target")
    }

    /**
     * Clear forced routing
     */
    suspend fun clearForceRoute() {
        mutex.withLock {
            configuration.forceTarget = null
        }
        logger.info("Cleared forced routing")
    }

    // Private helper methods

    private fun estimateTokens(request: RoutingRequest): Int {
        // Simple estimation based on text length
        val textLength = when (request.taskType) {
            TaskType.TEXT_GENERATION -> request.payload.length * 2 // Assume 2x output
            TaskType.TRANSCRIPTION -> request.payload.length / 10 // Audio to text ratio
            TaskType.TRANSLATION -> request.payload.length
            TaskType.SUMMARIZATION -> request.payload.length / 3
            TaskType.CODE_GENERATION -> request.payload.length * 3
            TaskType.CONVERSATION -> request.payload.length * 2
        }
        return textLength / 4 // Rough token estimate
    }

    private fun calculatePrivacyScore(request: RoutingRequest): Float {
        // Higher score means more privacy-sensitive
        return when {
            request.containsPII -> 1.0f
            request.containsSensitiveData -> 0.8f
            request.taskType == TaskType.TRANSCRIPTION -> 0.6f // Voice data
            else -> 0.3f
        }
    }

    private fun determineLatencyRequirement(request: RoutingRequest): LatencyRequirement {
        return when (request.taskType) {
            TaskType.CONVERSATION -> LatencyRequirement.REAL_TIME
            TaskType.TRANSCRIPTION -> LatencyRequirement.LOW
            TaskType.CODE_GENERATION -> LatencyRequirement.MEDIUM
            else -> LatencyRequirement.FLEXIBLE
        }
    }

    private fun determineQualityRequirement(request: RoutingRequest): QualityRequirement {
        return when (request.taskType) {
            TaskType.CODE_GENERATION -> QualityRequirement.HIGH
            TaskType.TRANSLATION -> QualityRequirement.HIGH
            TaskType.CONVERSATION -> QualityRequirement.MEDIUM
            else -> QualityRequirement.STANDARD
        }
    }

    private fun determineCostSensitivity(request: RoutingRequest): CostSensitivity {
        return when {
            request.preferLowCost -> CostSensitivity.HIGH
            request.taskType == TaskType.CONVERSATION -> CostSensitivity.MEDIUM
            else -> CostSensitivity.LOW
        }
    }

    private fun publishRoutingDecision(decision: RoutingDecision) {
        // TODO: Publish event through EventBus
        logger.debug("Published routing decision: ${decision.target}")
    }
}

/**
 * Routing request
 */
data class RoutingRequest(
    val taskType: TaskType,
    val payload: String,
    val modelPreference: String? = null,
    val containsPII: Boolean = false,
    val containsSensitiveData: Boolean = false,
    val preferLowCost: Boolean = false
)

/**
 * Task types for routing
 */
enum class TaskType {
    TEXT_GENERATION,
    TRANSCRIPTION,
    TRANSLATION,
    SUMMARIZATION,
    CODE_GENERATION,
    CONVERSATION
}

/**
 * Routing targets
 */
enum class RoutingTarget {
    ON_DEVICE,
    CLOUD,
    HYBRID // Use both for comparison or fallback
}

/**
 * Routing decision with reasoning
 */
data class RoutingDecision(
    val target: RoutingTarget,
    val model: String? = null,
    val reason: String,
    val confidence: Float,
    val estimatedCost: Float = 0f,
    val estimatedLatencyMs: Long = 0L
)

/**
 * Request analysis results
 */
data class RequestAnalysis(
    val estimatedTokens: Int,
    val privacyScore: Float,
    val latencyRequirement: LatencyRequirement,
    val qualityRequirement: QualityRequirement,
    val costSensitivity: CostSensitivity
)

/**
 * Latency requirements
 */
enum class LatencyRequirement {
    REAL_TIME,  // < 100ms
    LOW,        // < 500ms
    MEDIUM,     // < 2000ms
    FLEXIBLE    // No strict requirement
}

/**
 * Quality requirements
 */
enum class QualityRequirement {
    HIGH,
    MEDIUM,
    STANDARD
}

/**
 * Cost sensitivity levels
 */
enum class CostSensitivity {
    HIGH,   // Minimize cost
    MEDIUM, // Balance cost and quality
    LOW     // Quality over cost
}
