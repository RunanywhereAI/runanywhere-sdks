/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for on-device embeddings generation (B10).
 *
 * Delegates to the `rac_embeddings_*` C ABI via JNI.
 * Mirrors Swift RunAnywhere+Embeddings.swift.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsResult
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Generate an embedding vector for a single text.
 *
 * The underlying service is keyed by `modelId`; a handle is created lazily
 * on first use per model and reused across calls.
 *
 * @param text     Input text to embed.
 * @param modelId  Embeddings model identifier (registry id or local path).
 * @param options  Optional per-call overrides (default: L2-normalized).
 * @return An [EmbeddingsResult] containing one vector (in `vectors[0]`).
 * @throws com.runanywhere.sdk.foundation.errors.SDKException on failure.
 */
expect suspend fun RunAnywhere.embed(
    text: String,
    modelId: String,
    options: EmbeddingsOptions? = null,
): EmbeddingsResult
