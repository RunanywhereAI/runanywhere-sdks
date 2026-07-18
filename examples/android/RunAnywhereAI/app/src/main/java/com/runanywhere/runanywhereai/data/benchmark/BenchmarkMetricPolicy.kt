package com.runanywhere.runanywhereai.data.benchmark

import com.runanywhere.sdk.public.types.RALLMGenerationResult

/**
 * Converts the canonical one-shot LLM result into benchmark metrics.
 *
 * Streaming callbacks intentionally cannot carry every backend's terminal
 * statistics (notably QHexRT's `qhx_output`). The one-shot result does, so its
 * generated-token count is authoritative and is never replaced with a chunk
 * count or text-length estimate.
 */
internal fun llmBenchmarkMetrics(
    result: RALLMGenerationResult,
    loadTimeMs: Double,
    warmupTimeMs: Double,
    measuredEndToEndMs: Double,
    memoryDeltaBytes: Long,
): BenchmarkMetrics {
    require(result.error_message.isNullOrBlank()) {
        result.error_message ?: "LLM benchmark generation failed"
    }
    val outputTokens = result.tokens_generated
    require(outputTokens > 0) { "LLM benchmark produced zero output tokens" }

    val endToEndMs = result.generation_time_ms.takeIf { it > 0 } ?: measuredEndToEndMs
    val explicitDecodeMs = result.decode_time_ms.toDouble().takeIf { it > 0 }
    val tokensPerSecond = result.tokens_per_second.takeIf { it > 0 }
        ?: explicitDecodeMs?.let { outputTokens * 1000.0 / it }
        ?: (outputTokens * 1000.0 / endToEndMs).takeIf { endToEndMs > 0 }
    require(tokensPerSecond != null && tokensPerSecond.isFinite() && tokensPerSecond > 0) {
        "LLM benchmark did not report usable decode throughput"
    }
    // QHexRT exposes decode throughput and TTFT on the one-shot result but its
    // generic result envelope has no dedicated QHex timing fields. These two
    // identities recover the same native durations without text/token guesses.
    val decodeMs = explicitDecodeMs ?: outputTokens * 1000.0 / tokensPerSecond
    val promptEvalMs = result.prompt_eval_time_ms.toDouble().takeIf { it > 0 }
        ?: result.ttft_ms?.takeIf { it > 0 }

    return BenchmarkMetrics(
        loadTimeMs = loadTimeMs,
        warmupTimeMs = warmupTimeMs,
        endToEndLatencyMs = endToEndMs,
        tokensPerSecond = tokensPerSecond,
        ttftMs = result.ttft_ms?.takeIf { it > 0 },
        inputTokens = result.input_tokens.takeIf { it > 0 },
        outputTokens = outputTokens,
        promptEvalMs = promptEvalMs,
        decodeMs = decodeMs,
        memoryDeltaBytes = memoryDeltaBytes,
    )
}

/**
 * Median + variance reduction of repeated benchmark trials.
 *
 * A single measured pass is noisy: thermal throttling, background work, or a cold
 * cache can skew any one run. Running the same (model × scenario) several times and
 * reporting the per-metric **median** (robust to a single outlier) with the observed
 * [MetricRange] gives a number that is both representative and honest about spread.
 */
internal data class AggregatedBenchmark(
    val metrics: BenchmarkMetrics,
    val variance: BenchmarkVariance?,
)

/** Lower-interpolated median of a non-empty, finite numeric sample. */
private fun List<Double>.median(): Double {
    val sorted = sorted()
    val mid = sorted.size / 2
    return if (sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2.0
}

/** Reduce per-trial metrics to a median representative plus a headline variance summary. */
internal fun aggregateTrials(trials: List<BenchmarkMetrics>): AggregatedBenchmark {
    require(trials.isNotEmpty()) { "aggregateTrials requires at least one trial" }
    if (trials.size == 1) return AggregatedBenchmark(trials.first(), null)

    // Median over the finite, present values of a Double-valued field.
    fun med(select: (BenchmarkMetrics) -> Double?): Double? =
        trials.mapNotNull(select).filter { it.isFinite() }.takeIf { it.isNotEmpty() }?.median()

    // Median over the present values of an Int-valued field (rounded).
    fun medInt(select: (BenchmarkMetrics) -> Int?): Int? =
        trials.mapNotNull(select).map { it.toDouble() }.takeIf { it.isNotEmpty() }?.median()?.let(Math::round)?.toInt()

    // [min, max] over the finite, present values — only meaningful with >1 sample.
    fun range(select: (BenchmarkMetrics) -> Double?): MetricRange? =
        trials.mapNotNull(select).filter { it.isFinite() }
            .takeIf { it.size > 1 }
            ?.let { MetricRange(it.min(), it.max()) }

    val median = BenchmarkMetrics(
        loadTimeMs = med { it.loadTimeMs } ?: 0.0,
        warmupTimeMs = med { it.warmupTimeMs } ?: 0.0,
        endToEndLatencyMs = med { it.endToEndLatencyMs } ?: 0.0,
        tokensPerSecond = med { it.tokensPerSecond },
        ttftMs = med { it.ttftMs },
        inputTokens = medInt { it.inputTokens },
        outputTokens = medInt { it.outputTokens },
        promptEvalMs = med { it.promptEvalMs },
        decodeMs = med { it.decodeMs },
        realTimeFactor = med { it.realTimeFactor },
        audioLengthSeconds = med { it.audioLengthSeconds },
        audioDurationSeconds = med { it.audioDurationSeconds },
        charactersProcessed = medInt { it.charactersProcessed },
        memoryDeltaBytes = med { it.memoryDeltaBytes.toDouble() }?.let(Math::round) ?: 0L,
    )
    val variance = BenchmarkVariance(
        trials = trials.size,
        tokensPerSecond = range { it.tokensPerSecond },
        ttftMs = range { it.ttftMs },
        endToEndLatencyMs = range { it.endToEndLatencyMs },
    )
    return AggregatedBenchmark(median, variance)
}

/** Reject modality runs that returned success codes but no usable output. */
internal fun BenchmarkMetrics.requireSuccessfulOutput(category: BenchmarkCategory): BenchmarkMetrics {
    if (category == BenchmarkCategory.LLM || category == BenchmarkCategory.VLM) {
        require((outputTokens ?: 0) > 0) {
            "${category.label} benchmark produced zero output tokens"
        }
    }
    if (category == BenchmarkCategory.LLM) {
        require(tokensPerSecond != null && tokensPerSecond.isFinite() && tokensPerSecond > 0) {
            "LLM benchmark did not report usable decode throughput"
        }
    }
    return this
}
