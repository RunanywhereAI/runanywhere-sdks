/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * STT-side result types for the hybrid router. Mirrors GenerateResult.kt
 * structurally — same RoutedMetadata reused unchanged.
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
