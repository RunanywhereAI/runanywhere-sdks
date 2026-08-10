/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: `RunAnywhere.tts`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val ttsPlaybackScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/** The most recently created `speak()` handle, for the deprecated `stop()` adapter. */
@Volatile
private var latestSpeechHandle: SpeechHandle? = null

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
     * Synthesize [text] and play it through the device, returning immediately
     * with a handle to the in-flight utterance.
     *
     * There is no global `tts.stop()`; interrupt playback through the
     * returned handle.
     *
     * @throws SDKException never directly — synthesis/playback failure
     *   surfaces on [SpeechHandle.error].
     */
    public fun speak(text: String, options: TtsOptions? = null): SpeechHandle {
        val handle = SpeechHandle(interruptHandler = { legacyStopSpeaking() })
        latestSpeechHandle = handle
        ttsPlaybackScope.launch {
            try {
                legacySpeak(text, options.orDefault().toProto())
                handle.complete()
            } catch (error: SDKException) {
                handle.complete(error)
            } finally {
                if (latestSpeechHandle === handle) latestSpeechHandle = null
            }
        }
        return handle
    }

    /**
     * @deprecated Use the [SpeechHandle] returned by [speak]. Interrupts the
     *   most recently created handle when one is still active.
     */
    @Deprecated("Use the SpeechHandle returned by speak().")
    public suspend fun stop() {
        latestSpeechHandle?.interrupt() ?: legacyStopSpeaking()
    }

    /** Voices the loaded speech-synthesis model can render. */
    public suspend fun voices(): List<Voice> = legacyVoices()
}
