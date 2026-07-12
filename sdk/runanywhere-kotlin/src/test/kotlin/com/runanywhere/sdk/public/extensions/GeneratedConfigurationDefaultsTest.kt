/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.EmbeddingsConfiguration
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.STTConfiguration
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.TTSConfiguration
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
        assertEquals(0.0f, configuration.similarity_threshold)
        assertEquals(512, configuration.chunk_size)
        assertEquals(64, configuration.chunk_overlap)
    }

    @Test
    fun modalityDefaultsComeFromCanonicalIdlAnnotations() {
        assertEquals(384, EmbeddingsConfiguration.defaults().embedding_dimension)

        val vad = VADConfiguration.defaults()
        assertEquals(16_000, vad.sample_rate)
        assertEquals(0.015f, vad.threshold)

        val sttConfiguration = STTConfiguration.defaults()
        assertEquals(16_000, sttConfiguration.sample_rate)
        assertEquals(true, sttConfiguration.enable_punctuation)
        assertEquals(true, sttConfiguration.enable_word_timestamps)

        val sttOptions = STTOptions.defaults()
        assertEquals(true, sttOptions.enable_punctuation)
        assertEquals(true, sttOptions.enable_word_timestamps)

        assertEquals(22_050, TTSConfiguration.defaults().sample_rate)
        assertEquals(22_050, TTSOptions.defaults().sample_rate)
    }
}
