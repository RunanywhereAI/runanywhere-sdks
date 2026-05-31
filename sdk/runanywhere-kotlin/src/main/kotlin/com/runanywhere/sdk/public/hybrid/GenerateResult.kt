/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Result returned by RACRouter's per-capability generate() call.
 * Carries the LLM output text plus the routing decision so callers know
 * which backend actually served the request.
 */

package com.runanywhere.sdk.public.hybrid

/**
 * Outcome of `router.llm.generate(prompt)`.
 *
 * The [text] field holds the generated response from whichever backend
 * was selected. [routing] explains the dispatch — which model id served
 * the request, whether it was the primary or a cascade fallback, and
 * how many backends were attempted.
 *
 * @property text    Final generated text from the chosen backend.
 * @property routing Description of the routing decision that produced [text].
 */
data class GenerateResult(
    val text: String,
    val routing: RoutedMetadata,
)

/**
 * Companion to [GenerateResult]. Always populated, including on cascade
 * scenarios where the primary candidate failed and a secondary served
 * the request.
 *
 * @property chosenModelId          The model id of the candidate that produced the text.
 * @property wasFallback            True when the secondary candidate served the request
 *                                  after the primary failed or scored below the cascade
 *                                  threshold.
 * @property attemptCount           How many backends were invoked (1 = primary only,
 *                                  2 = primary then secondary on cascade).
 * @property primaryErrorCode       Native rac_result_t from the primary candidate when
 *                                  [wasFallback] is true; otherwise 0 (RAC_SUCCESS).
 * @property primaryErrorMessage    Human-readable reason the primary failed when
 *                                  [wasFallback] is true; otherwise empty.
 */
data class RoutedMetadata(
    val chosenModelId: String,
    val wasFallback: Boolean,
    val attemptCount: Int,
    val primaryErrorCode: Int = 0,
    val primaryErrorMessage: String = "",
    /**
     * Final confidence of the chosen result. `Float.NaN` when the engine
     * does not surface a quality signal (e.g. sherpa-onnx Whisper).
     */
    val confidence: Float = Float.NaN,
    /**
     * Primary's confidence captured before a confidence-based cascade to
     * the secondary. `Float.NaN` when no cascade occurred (or when the
     * fallback fired on a primary error instead of low confidence).
     */
    val primaryConfidence: Float = Float.NaN,
)
