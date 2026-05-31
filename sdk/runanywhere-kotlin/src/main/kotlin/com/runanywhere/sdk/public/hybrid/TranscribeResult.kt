/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * STT-side result types for the hybrid router.
 */

package com.runanywhere.sdk.public.hybrid

/**
 * One transcribe call's outcome through the hybrid STT router.
 *
 * @property text             Transcript text from the chosen backend.
 * @property detectedLanguage BCP-47 language code reported by the backend.
 *                            Empty when the engine doesn't surface one (or
 *                            when the caller pinned [language] in the
 *                            request and the engine echoed it back).
 * @property routing          Which side ran, whether the call was a
 *                            fallback, and why the primary failed when so.
 */
data class TranscribeResult(
    val text: String,
    val detectedLanguage: String,
    val routing: RoutedMetadata,
)

/**
 * Metadata describing the routing decision behind a [TranscribeResult].
 * Always populated, including on cascade/fallback scenarios where the
 * secondary candidate served the request.
 *
 * @property chosenModelId       Model id of the candidate that produced the result.
 * @property wasFallback         True when the secondary candidate served the request
 *                               after the primary failed or scored below the cascade
 *                               threshold.
 * @property attemptCount        How many backends were invoked (1 = primary only,
 *                               2 = primary then secondary).
 * @property primaryErrorCode    Native rac_result_t from the primary when [wasFallback]
 *                               is true and the fallback fired on an error; else 0.
 * @property primaryErrorMessage Human-readable reason the primary failed; else empty.
 * @property confidence          Final confidence of the chosen result. `Float.NaN` when
 *                               the engine surfaces no quality signal.
 * @property primaryConfidence   Primary's confidence captured before a confidence-based
 *                               cascade. `Float.NaN` when no confidence cascade occurred.
 */
data class RoutedMetadata(
    val chosenModelId: String,
    val wasFallback: Boolean,
    val attemptCount: Int,
    val primaryErrorCode: Int = 0,
    val primaryErrorMessage: String = "",
    val confidence: Float = Float.NaN,
    val primaryConfidence: Float = Float.NaN,
)
