/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Convenience helper that pairs a Flow<String> token stream with a Deferred
 * proto-canonical VLMResult containing the final metrics. This is the Kotlin
 * idiom for Swift's `VLMStreamingResult` — proto doesn't model it because
 * `Flow` / `Deferred` are runtime-only types.
 *
 * Wave 2 KOTLIN: replaces the legacy hand-rolled `VLMStreamingResult` from
 * `public/extensions/VLM/VLMTypes.kt` (deleted).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMResult
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow

/**
 * Container for streaming VLM generation with metrics.
 *
 * @property stream Flow of tokens as they are generated.
 * @property result Deferred proto-canonical VLMResult that completes with
 *                  the final metrics once generation is done.
 */
data class VLMStreamingResult(
    val stream: Flow<String>,
    val result: Deferred<VLMResult>,
)
