/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * `EmbeddingsConfiguration` is deleted outright (idl/embeddings_options.proto)
 * -- `EmbeddingsOptions` is the sole embeddings knob surface now, with no
 * default embedding dimension (it is derived from the loaded model, not a
 * caller-supplied default). `RAGConfiguration.similarity_threshold` was
 * renamed `score_threshold`, and `embedding_dimension` remains `optional`
 * with no default (unset until the embedding model resolves it).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.STTConfiguration
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.VADConfiguration
import com.runanywhere.sdk.generated.convenience.defaults
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GeneratedConfigurationDefaultsTest {
    @Test
    fun ragDefaultsUseAcceptAllSimilarityThreshold() {
        val configuration = RAGConfiguration.defaults()

        assertNull(configuration.embedding_dimension)
        assertEquals(5, configuration.top_k)
        assertEquals(0.0f, configuration.score_threshold)
        assertEquals(512, configuration.chunk_size)
        assertEquals(64, configuration.chunk_overlap)
    }

    @Test
    fun modalityDefaultsComeFromCanonicalIdlAnnotations() {
        val embeddings = EmbeddingsOptions.defaults()
        assertEquals(true, embeddings.normalize)
        assertNull(embeddings.dimensions)

        // VADConfiguration.threshold (energy-detector-specific, default 0.015)
        // was renamed activation_threshold: a normalized [0,1] sensitivity
        // (industry default 0.5, matching OpenAI/Silero/LiveKit), which each
        // backend maps onto its own units (idl/vad_options.proto).
        val vad = VADConfiguration.defaults()
        assertEquals(16_000, vad.sample_rate)
        assertEquals(0.5f, vad.activation_threshold)

        val sttConfiguration = STTConfiguration.defaults()
        assertEquals(16_000, sttConfiguration.sample_rate)
        assertEquals(true, sttConfiguration.enable_punctuation)
        assertEquals(true, sttConfiguration.enable_word_timestamps)

        val sttOptions = STTOptions.defaults()
        assertEquals(true, sttOptions.enable_punctuation)
        assertEquals(true, sttOptions.enable_word_timestamps)

        // TTS synthesis knobs left TTSConfiguration in the v2 contract; TTSOptions owns them.
        // sample_rate now defaults to 0 (idl/tts_options.proto): render at
        // the voice's native rate rather than forcing a resample to a fixed
        // 22050 Hz, which cost quality.
        assertEquals(0, TTSOptions.defaults().sample_rate)
    }
}
