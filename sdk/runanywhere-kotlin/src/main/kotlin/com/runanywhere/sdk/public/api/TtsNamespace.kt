/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.tts`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Text-to-speech synthesis and playback.
 *
 * ```kotlin
 * RunAnywhere.tts.speak("Deployment finished", TtsOptions(speed = 1.1f))
 * ```
 */
public class TtsNamespace internal constructor() {
    /**
     * Synthesize [text] into one audio buffer.
     *
     * @throws SDKException when no voice is loaded.
     */
    public suspend fun synthesize(text: String, options: TtsOptions? = null): Audio {
        val opts = options.orDefault()
        return legacySynthesize(text, opts.toProto()).toAudio(opts.sampleRate)
    }

    /**
     * Synthesize [text] incrementally so playback can start before the tail is ready.
     *
     * @throws SDKException when no voice is loaded.
     */
    public fun synthesizeStream(text: String, options: TtsOptions? = null): Flow<AudioChunk> =
        legacySynthesizeStream(text, options.orDefault().toProto()).map { it.toAudioChunk() }

    /**
     * Synthesize [text] and play it through the device.
     *
     * @throws SDKException when no voice is loaded or playback fails.
     */
    public suspend fun speak(text: String, options: TtsOptions? = null) {
        legacySpeak(text, options.orDefault().toProto())
    }

    /** Stop playback and any synthesis still in flight. */
    public suspend fun stop() {
        legacyStopSpeaking()
    }

    /** Voices the loaded speech-synthesis model can render. */
    public suspend fun voices(): List<Voice> = legacyVoices()
}
