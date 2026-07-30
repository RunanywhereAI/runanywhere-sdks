/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.vad`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Voice-activity detection over raw audio.
 *
 * ```kotlin
 * val verdict = RunAnywhere.vad.detect(AudioInput.pcm16(frame))
 * if (verdict.isSpeech) startTurn()
 * ```
 */
public class VadNamespace internal constructor() {
    /**
     * Decide whether [audio] contains speech.
     *
     * @throws SDKException when the buffer is empty or the SDK is not initialized.
     */
    public suspend fun detect(audio: AudioInput, options: VadOptions? = null): VadResult =
        legacyDetectVoiceActivity(audio.normalizedBytes(), options.orDefault().toProto()).toVadResult()

    /**
     * Track speech across a live [audio] stream, emitting a transition when it starts or ends.
     *
     * @throws SDKException when the SDK is not initialized.
     */
    public fun detectStream(
        audio: Flow<AudioInput>,
        options: VadOptions? = null,
    ): Flow<VadEvent> =
        flow {
            val opts = options.orDefault().toProto()
            var speaking = false
            audio.collect { frame ->
                val verdict =
                    legacyDetectVoiceActivity(frame.normalizedBytes(), opts).toVadResult()
                when {
                    verdict.isSpeech && !speaking -> {
                        speaking = true
                        emit(VadEvent.SpeechStarted(verdict))
                    }
                    !verdict.isSpeech && speaking -> {
                        speaking = false
                        emit(VadEvent.SpeechEnded(verdict))
                    }
                    else -> emit(VadEvent.Frame(verdict))
                }
            }
        }
}
