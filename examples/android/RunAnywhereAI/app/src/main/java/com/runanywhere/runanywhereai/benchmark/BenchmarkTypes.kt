package com.runanywhere.runanywhereai.benchmark

import kotlinx.serialization.Serializable

// MARK: - Benchmark Configuration

/**
 * Configuration for benchmark runs
 */
@Serializable
data class BenchmarkConfig(
    val warmupIterations: Int = 3,
    val testIterations: Int = 5,
    val maxTokensList: List<Int> = listOf(50, 100),
    val prompts: List<BenchmarkPrompt> = BenchmarkPrompt.standardPrompts,
) {
    companion object {
        val DEFAULT = BenchmarkConfig()
        
        val QUICK = BenchmarkConfig(
            warmupIterations = 1,
            testIterations = 3,
            maxTokensList = listOf(50),
            prompts = listOf(BenchmarkPrompt.standardPrompts.first())
        )
        
        val COMPREHENSIVE = BenchmarkConfig(
            warmupIterations = 3,
            testIterations = 10,
            maxTokensList = listOf(50, 100, 256),
            prompts = BenchmarkPrompt.standardPrompts
        )
    }
}

/**
 * A benchmark prompt with metadata
 */
@Serializable
data class BenchmarkPrompt(
    val id: String,
    val text: String,
    val category: PromptCategory,
    val expectedMinTokens: Int,
) {
    @Serializable
    enum class PromptCategory {
        SHORT,
        MEDIUM,
        LONG,
        REASONING
    }
    
    companion object {
        // Standard prompts for benchmarking different capabilities
        // See examples/benchmark-config.json for the full configurable prompt list
        val standardPrompts = listOf(
            // Short - Quick responses
            BenchmarkPrompt(
                id = "short-1",
                text = "What is 2+2?",
                category = PromptCategory.SHORT,
                expectedMinTokens = 5
            ),
            // Medium - General explanations
            BenchmarkPrompt(
                id = "medium-1",
                text = "Explain quantum computing in simple terms.",
                category = PromptCategory.MEDIUM,
                expectedMinTokens = 50
            ),
            // Reasoning - Math and logic
            BenchmarkPrompt(
                id = "reasoning-1",
                text = "If a train travels at 60 mph for 2.5 hours, how far does it travel? Show your work.",
                category = PromptCategory.REASONING,
                expectedMinTokens = 30
            ),
            // Long - Extended generation (used in comprehensive mode)
            BenchmarkPrompt(
                id = "long-1",
                text = "Write a short story about a robot learning to paint. Include a beginning, middle, and end.",
                category = PromptCategory.LONG,
                expectedMinTokens = 150
            )
        )
    }
}

// MARK: - Benchmark Results

/**
 * Result of a single inference run
 */
@Serializable
data class SingleRunResult(
    val promptId: String,
    val maxTokens: Int,
    val tokensPerSecond: Double,
    val latencyMs: Double,
    val ttftMs: Double?,
    val outputTokens: Int,
    val inputTokens: Int,
    val timestamp: Long,
)

/**
 * Aggregated benchmark result for a model
 */
@Serializable
data class BenchmarkResult(
    val id: String,
    val modelId: String,
    val modelName: String,
    val framework: String,
    
    // Device info
    val deviceId: String,
    val deviceModel: String,
    val osVersion: String,
    val sdkVersion: String,
    val gitCommit: String?,
    
    // Timing
    val timestamp: Long,
    val modelLoadTimeMs: Double,
    
    // Aggregated LLM metrics
    val avgTokensPerSecond: Double,
    val p50TokensPerSecond: Double,
    val p95TokensPerSecond: Double,
    val minTokensPerSecond: Double,
    val maxTokensPerSecond: Double,
    
    val avgTtftMs: Double,
    val p50TtftMs: Double,
    val p95TtftMs: Double,
    
    val avgLatencyMs: Double,
    val p50LatencyMs: Double,
    val p95LatencyMs: Double,
    
    val peakMemoryBytes: Long,
    val totalRuns: Int,
    
    // Per-prompt breakdown
    val promptResults: List<PromptAggregatedResult>,
    
    // Configuration used
    val config: BenchmarkConfig,
)

/**
 * Aggregated results for a specific prompt
 */
@Serializable
data class PromptAggregatedResult(
    val promptId: String,
    val promptCategory: String,
    val avgTokensPerSecond: Double,
    val avgLatencyMs: Double,
    val avgTtftMs: Double,
    val runCount: Int,
)

// MARK: - Benchmark State

/**
 * Current state of benchmark execution
 */
sealed class BenchmarkState {
    data object Idle : BenchmarkState()
    data object Preparing : BenchmarkState()
    data class WarmingUp(val model: String, val iteration: Int, val total: Int) : BenchmarkState()
    data class Running(val model: String, val prompt: String, val iteration: Int, val total: Int) : BenchmarkState()
    data object Completed : BenchmarkState()
    data class Failed(val error: String) : BenchmarkState()
    
    val isRunning: Boolean
        get() = this is Preparing || this is WarmingUp || this is Running
}

/**
 * Progress information for UI
 */
data class BenchmarkProgress(
    val state: BenchmarkState,
    val overallProgress: Float,
    val currentModelIndex: Int,
    val totalModels: Int,
    val elapsedTimeMs: Long,
    val estimatedRemainingTimeMs: Long?,
)

// MARK: - Export Format

/**
 * Container for exporting benchmark results
 */
@Serializable
data class BenchmarkExport(
    val exportVersion: String = CURRENT_VERSION,
    val exportedAt: Long = System.currentTimeMillis(),
    val results: List<BenchmarkResult>,
) {
    companion object {
        const val CURRENT_VERSION = "1.0"
    }
}
