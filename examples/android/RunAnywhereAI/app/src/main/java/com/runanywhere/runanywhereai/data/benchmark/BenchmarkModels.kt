package com.runanywhere.runanywhereai.data.benchmark

import kotlinx.serialization.Serializable

@Serializable
enum class BenchmarkCategory(val label: String) {
    LLM("LLM"),
    STT("Speech to Text"),
    TTS("Text to Speech"),
    VLM("Vision"),
}

@Serializable
enum class BenchmarkStatus { RUNNING, COMPLETED, CANCELLED, FAILED }

// One measured run of a scenario against a model. Nullable metrics are per-category;
// only the fields relevant to the scenario's category are populated.
@Serializable
data class BenchmarkMetrics(
    val loadTimeMs: Double = 0.0,
    val warmupTimeMs: Double = 0.0,
    val endToEndLatencyMs: Double = 0.0,
    val tokensPerSecond: Double? = null,
    val ttftMs: Double? = null,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val promptEvalMs: Double? = null,
    val decodeMs: Double? = null,
    val realTimeFactor: Double? = null,
    val audioLengthSeconds: Double? = null,
    val audioDurationSeconds: Double? = null,
    val charactersProcessed: Int? = null,
    val memoryDeltaBytes: Long = 0L,
)

@Serializable
data class BenchmarkResult(
    val category: BenchmarkCategory,
    val scenario: String,
    val modelId: String,
    val modelName: String,
    val framework: String,
    val success: Boolean,
    val errorMessage: String? = null,
    val metrics: BenchmarkMetrics = BenchmarkMetrics(),
)

@Serializable
data class BenchDeviceInfo(
    val device: String,
    val manufacturer: String,
    val androidSdk: Int,
    val totalRamBytes: Long,
    val availableRamBytes: Long,
)

@Serializable
data class BenchmarkRun(
    val id: String,
    val startedAt: Long,
    val completedAt: Long?,
    val status: BenchmarkStatus,
    val device: BenchDeviceInfo,
    val results: List<BenchmarkResult>,
) {
    val passed: Int get() = results.count { it.success }
    val failed: Int get() = results.count { !it.success }
    val durationMs: Long get() = (completedAt ?: startedAt) - startedAt
}

// Live progress emitted while a run executes.
data class BenchmarkProgress(
    val current: Int,
    val total: Int,
    val category: BenchmarkCategory,
    val scenario: String,
    val model: String,
)
