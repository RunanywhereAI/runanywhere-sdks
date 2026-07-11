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
