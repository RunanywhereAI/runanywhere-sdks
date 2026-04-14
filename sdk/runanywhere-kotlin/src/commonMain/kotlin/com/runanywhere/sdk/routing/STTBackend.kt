/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Interface for STT-capable backends.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput

/**
 * Implemented by any backend capable of transcribing audio.
 *
 * The router selects a backend via RoutableBackend.descriptors(), then calls
 * transcribe() on the selected STTBackend. If it throws, the router tries
 * the next candidate.
 */
interface STTBackend : RoutableBackend {
    /**
     * Transcribe [audioData] to text using the given [options].
     * Throw on failure — the router will advance to the next candidate.
     */
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput
}
