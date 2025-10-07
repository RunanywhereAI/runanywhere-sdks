package com.runanywhere.sdk.models

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable

/**
 * Comprehensive cost tracking system - exact match with iOS cost tracking capabilities
 * Provides real-time cost monitoring and savings calculations
 */

/**
 * Cost information for a specific model and provider
 */
@Serializable
data class ModelCostInfo(
    /** Model identifier */
    val modelId: String,

    /** Provider name */
    val provider: String,

    /** Cost per 1000 prompt tokens */
    val promptTokenCostPer1K: Double,

    /** Cost per 1000 completion tokens */
    val completionTokenCostPer1K: Double,

    /** Currency code (USD, EUR, etc.) */
    val currency: String = "USD",

    /** Pricing tier (e.g., free, pro, enterprise) */
    val pricingTier: String? = null,

    /** Last updated timestamp */
    val lastUpdated: Long = getCurrentTimeMillis()
) {
    /**
     * Calculate cost for token usage
     */
    fun calculateCost(tokenUsage: TokenUsage): Double {
        val promptCost = (tokenUsage.promptTokens / 1000.0) * promptTokenCostPer1K
        val completionCost = (tokenUsage.completionTokens / 1000.0) * completionTokenCostPer1K
        return promptCost + completionCost
    }

    /**
     * Calculate cost for specific token counts
     */
    fun calculateCost(promptTokens: Int, completionTokens: Int): Double {
        val promptCost = (promptTokens / 1000.0) * promptTokenCostPer1K
        val completionCost = (completionTokens / 1000.0) * completionTokenCostPer1K
        return promptCost + completionCost
    }
}

/**
 * Real-time cost tracking metrics
 */
@Serializable
data class CostMetrics(
    /** Total cost for current session */
    val sessionCost: Double = 0.0,

    /** Total cost savings compared to cloud execution */
    val totalSavings: Double = 0.0,

    /** Number of on-device executions */
    val onDeviceExecutions: Int = 0,

    /** Number of cloud executions */
    val cloudExecutions: Int = 0,

    /** Total tokens processed on-device */
    val onDeviceTokens: Long = 0L,

    /** Total tokens processed in cloud */
    val cloudTokens: Long = 0L,

    /** Average cost per generation */
    val averageCostPerGeneration: Double = 0.0,

    /** Cost efficiency ratio (savings / total potential cost) */
    val costEfficiencyRatio: Double = 0.0,

    /** Session start time */
    val sessionStartTime: Long = getCurrentTimeMillis(),

    /** Last updated timestamp */
    val lastUpdated: Long = getCurrentTimeMillis()
) {
    /**
     * Calculate total executions
     */
    val totalExecutions: Int
        get() = onDeviceExecutions + cloudExecutions

    /**
     * Calculate total tokens processed
     */
    val totalTokens: Long
        get() = onDeviceTokens + cloudTokens

    /**
     * Calculate on-device execution percentage
     */
    val onDevicePercentage: Double
        get() = if (totalExecutions > 0) {
            (onDeviceExecutions.toDouble() / totalExecutions) * 100.0
        } else 0.0

    /**
     * Calculate cost per token
     */
    val costPerToken: Double
        get() = if (totalTokens > 0) {
            sessionCost / totalTokens
        } else 0.0

    /**
     * Calculate session duration in minutes
     */
    val sessionDurationMinutes: Long
        get() = (lastUpdated - sessionStartTime) / 60_000L
}

/**
 * Cost calculation result for a generation request
 */
@Serializable
data class CostCalculationResult(
    /** Execution target used */
    val executionTarget: ExecutionTarget,

    /** Actual cost incurred */
    val actualCost: Double,

    /** Cost that would have been incurred on cloud */
    val cloudCost: Double,

    /** Savings amount (cloudCost - actualCost) */
    val savings: Double,

    /** Token usage for this generation */
    val tokenUsage: TokenUsage,

    /** Model cost info used for calculation */
    val modelCostInfo: ModelCostInfo,

    /** Timestamp when calculation was performed */
    val timestamp: Long = getCurrentTimeMillis()
) {
    /**
     * Validate the cost calculation
     */
    fun validate() {
        require(actualCost >= 0.0) { "Actual cost must be non-negative" }
        require(cloudCost >= 0.0) { "Cloud cost must be non-negative" }
        require(savings >= 0.0) { "Savings must be non-negative" }
        require(timestamp > 0) { "Timestamp must be positive" }
        tokenUsage.validate()
    }

    /**
     * Calculate savings percentage
     */
    val savingsPercentage: Double
        get() = if (cloudCost > 0.0) {
            (savings / cloudCost) * 100.0
        } else 0.0
}

/**
 * Cost tracking service interface
 */
interface CostTrackingService {
    /** Track a generation execution */
    suspend fun trackExecution(
        executionTarget: ExecutionTarget,
        tokenUsage: TokenUsage,
        modelId: String,
        provider: String = "default"
    ): CostCalculationResult

    /** Get current cost metrics */
    suspend fun getCurrentMetrics(): CostMetrics

    /** Get model cost information */
    suspend fun getModelCostInfo(modelId: String, provider: String = "default"): ModelCostInfo?

    /** Update model cost information */
    suspend fun updateModelCostInfo(costInfo: ModelCostInfo)

    /** Reset session metrics */
    suspend fun resetSession()

    /** Get cost breakdown by model */
    suspend fun getCostBreakdownByModel(): Map<String, Double>

    /** Get cost history */
    suspend fun getCostHistory(
        startTime: Long? = null,
        endTime: Long? = null,
        limit: Int = 100
    ): List<CostCalculationResult>
}

/**
 * Default implementation of cost tracking service
 */
class DefaultCostTrackingService : CostTrackingService {
    private var currentMetrics = CostMetrics()
    private val costHistory = mutableListOf<CostCalculationResult>()
    private val modelCostInfoMap = mutableMapOf<String, ModelCostInfo>()

    init {
        // Initialize with common model pricing
        initializeCommonModelPricing()
    }

    private fun initializeCommonModelPricing() {
        // OpenAI GPT-4 pricing (example)
        modelCostInfoMap["gpt-4"] = ModelCostInfo(
            modelId = "gpt-4",
            provider = "openai",
            promptTokenCostPer1K = 0.03,
            completionTokenCostPer1K = 0.06,
            currency = "USD",
            pricingTier = "standard"
        )

        // OpenAI GPT-3.5-turbo pricing (example)
        modelCostInfoMap["gpt-3.5-turbo"] = ModelCostInfo(
            modelId = "gpt-3.5-turbo",
            provider = "openai",
            promptTokenCostPer1K = 0.001,
            completionTokenCostPer1K = 0.002,
            currency = "USD",
            pricingTier = "standard"
        )

        // Claude pricing (example)
        modelCostInfoMap["claude-3-sonnet"] = ModelCostInfo(
            modelId = "claude-3-sonnet",
            provider = "anthropic",
            promptTokenCostPer1K = 0.003,
            completionTokenCostPer1K = 0.015,
            currency = "USD",
            pricingTier = "standard"
        )

        // On-device models (free)
        modelCostInfoMap["llama-7b"] = ModelCostInfo(
            modelId = "llama-7b",
            provider = "on-device",
            promptTokenCostPer1K = 0.0,
            completionTokenCostPer1K = 0.0,
            currency = "USD",
            pricingTier = "free"
        )

        modelCostInfoMap["mistral-7b"] = ModelCostInfo(
            modelId = "mistral-7b",
            provider = "on-device",
            promptTokenCostPer1K = 0.0,
            completionTokenCostPer1K = 0.0,
            currency = "USD",
            pricingTier = "free"
        )
    }

    override suspend fun trackExecution(
        executionTarget: ExecutionTarget,
        tokenUsage: TokenUsage,
        modelId: String,
        provider: String
    ): CostCalculationResult {
        val modelCostInfo = getModelCostInfo(modelId, provider)
            ?: ModelCostInfo(
                modelId = modelId,
                provider = provider,
                promptTokenCostPer1K = 0.01, // Default pricing
                completionTokenCostPer1K = 0.02,
                currency = "USD"
            )

        val actualCost = when (executionTarget) {
            ExecutionTarget.ON_DEVICE -> 0.0 // On-device execution is free
            ExecutionTarget.CLOUD, ExecutionTarget.HYBRID -> modelCostInfo.calculateCost(tokenUsage)
        }

        // Calculate what the cost would have been if run in cloud
        val cloudCostInfo = getCloudCostInfo(modelId) ?: modelCostInfo
        val cloudCost = cloudCostInfo.calculateCost(tokenUsage)

        val savings = cloudCost - actualCost

        val result = CostCalculationResult(
            executionTarget = executionTarget,
            actualCost = actualCost,
            cloudCost = cloudCost,
            savings = savings,
            tokenUsage = tokenUsage,
            modelCostInfo = modelCostInfo
        )

        // Update metrics
        updateMetrics(result)

        // Add to history
        costHistory.add(result)
        if (costHistory.size > 1000) { // Keep last 1000 entries
            costHistory.removeAt(0)
        }

        return result
    }

    private suspend fun getCloudCostInfo(modelId: String): ModelCostInfo? {
        // Try to find a cloud equivalent for cost comparison
        return when {
            modelId.contains("llama", ignoreCase = true) -> modelCostInfoMap["gpt-3.5-turbo"]
            modelId.contains("mistral", ignoreCase = true) -> modelCostInfoMap["claude-3-sonnet"]
            else -> modelCostInfoMap.values.firstOrNull { it.provider != "on-device" }
        }
    }

    private fun updateMetrics(result: CostCalculationResult) {
        val newMetrics = currentMetrics.copy(
            sessionCost = currentMetrics.sessionCost + result.actualCost,
            totalSavings = currentMetrics.totalSavings + result.savings,
            onDeviceExecutions = if (result.executionTarget == ExecutionTarget.ON_DEVICE) {
                currentMetrics.onDeviceExecutions + 1
            } else currentMetrics.onDeviceExecutions,
            cloudExecutions = if (result.executionTarget != ExecutionTarget.ON_DEVICE) {
                currentMetrics.cloudExecutions + 1
            } else currentMetrics.cloudExecutions,
            onDeviceTokens = if (result.executionTarget == ExecutionTarget.ON_DEVICE) {
                currentMetrics.onDeviceTokens + result.tokenUsage.totalTokens
            } else currentMetrics.onDeviceTokens,
            cloudTokens = if (result.executionTarget != ExecutionTarget.ON_DEVICE) {
                currentMetrics.cloudTokens + result.tokenUsage.totalTokens
            } else currentMetrics.cloudTokens,
            lastUpdated = getCurrentTimeMillis()
        )

        // Calculate derived metrics
        val totalExecutions = newMetrics.onDeviceExecutions + newMetrics.cloudExecutions
        val averageCost = if (totalExecutions > 0) {
            newMetrics.sessionCost / totalExecutions
        } else 0.0

        val totalPotentialCost = newMetrics.sessionCost + newMetrics.totalSavings
        val efficiencyRatio = if (totalPotentialCost > 0) {
            newMetrics.totalSavings / totalPotentialCost
        } else 0.0

        currentMetrics = newMetrics.copy(
            averageCostPerGeneration = averageCost,
            costEfficiencyRatio = efficiencyRatio
        )
    }

    override suspend fun getCurrentMetrics(): CostMetrics {
        return currentMetrics
    }

    override suspend fun getModelCostInfo(modelId: String, provider: String): ModelCostInfo? {
        val key = if (provider == "default") modelId else "${provider}:${modelId}"
        return modelCostInfoMap[key] ?: modelCostInfoMap[modelId]
    }

    override suspend fun updateModelCostInfo(costInfo: ModelCostInfo) {
        val key = "${costInfo.provider}:${costInfo.modelId}"
        modelCostInfoMap[key] = costInfo
    }

    override suspend fun resetSession() {
        currentMetrics = CostMetrics()
        costHistory.clear()
    }

    override suspend fun getCostBreakdownByModel(): Map<String, Double> {
        val breakdown = mutableMapOf<String, Double>()

        for (result in costHistory) {
            val modelId = result.modelCostInfo.modelId
            breakdown[modelId] = (breakdown[modelId] ?: 0.0) + result.actualCost
        }

        return breakdown
    }

    override suspend fun getCostHistory(
        startTime: Long?,
        endTime: Long?,
        limit: Int
    ): List<CostCalculationResult> {
        var filtered = costHistory.asSequence()

        startTime?.let { start ->
            filtered = filtered.filter { it.timestamp >= start }
        }

        endTime?.let { end ->
            filtered = filtered.filter { it.timestamp <= end }
        }

        return filtered.sortedByDescending { it.timestamp }
            .take(limit)
            .toList()
    }
}

/**
 * Cost tracking helper functions
 */
object CostTrackingUtils {
    /**
     * Format cost amount for display
     */
    fun formatCost(amount: Double, currency: String = "USD"): String {
        return when (currency.uppercase()) {
            "USD" -> "$%.4f".format(amount)
            "EUR" -> "€%.4f".format(amount)
            "GBP" -> "£%.4f".format(amount)
            else -> "%.4f $currency".format(amount)
        }
    }

    /**
     * Format savings percentage
     */
    fun formatSavingsPercentage(percentage: Double): String {
        return "%.1f%%".format(percentage)
    }

    /**
     * Calculate cost per million tokens
     */
    fun calculateCostPerMillion(costPer1K: Double): Double {
        return costPer1K * 1000
    }

    /**
     * Estimate monthly cost based on daily usage
     */
    fun estimateMonthlyCost(dailyCost: Double): Double {
        return dailyCost * 30
    }

    /**
     * Calculate ROI of on-device deployment
     */
    fun calculateOnDeviceROI(
        onDeviceSetupCost: Double,
        monthlySavings: Double,
        months: Int = 12
    ): Double {
        val totalSavings = monthlySavings * months
        return if (onDeviceSetupCost > 0) {
            ((totalSavings - onDeviceSetupCost) / onDeviceSetupCost) * 100
        } else 100.0
    }
}
