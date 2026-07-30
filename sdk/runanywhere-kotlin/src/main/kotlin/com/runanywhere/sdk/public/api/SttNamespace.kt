/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.stt`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map

/**
 * Speech-to-text transcription.
 *
 * ```kotlin
 * val text = RunAnywhere.stt.transcribe(AudioInput.wav(recording)).text
 * println(text)
 * ```
 */
public class SttNamespace internal constructor() {
    /**
     * Transcribe a complete [audio] buffer.
     *
     * @throws SDKException when no speech-recognition model is loaded.
     */
    public suspend fun transcribe(audio: AudioInput, options: SttOptions? = null): Transcription =
        legacyTranscribe(audio.normalizedBytes(), options.orDefault().toProto()).toTranscription()

    /**
     * Transcribe a live [audio] stream, emitting partials until each utterance closes.
     *
     * @throws SDKException when no speech-recognition model is loaded.
     */
    public fun transcribeStream(
        audio: Flow<AudioInput>,
        options: SttOptions? = null,
    ): Flow<TranscriptionEvent> =
        flow {
            emit(TranscriptionEvent.Started)
            val chunks = audio.map { it.normalizedBytes() }
            legacyTranscribeStream(chunks, options.orDefault().toProto()).collect { partial ->
                if (partial.is_final) {
                    val output = partial.final_output
                    emit(
                        TranscriptionEvent.Final(
                            output?.toTranscription() ?: Transcription(
                                text = partial.text,
                                language = partial.language?.takeIf { it.isNotEmpty() },
                                confidence = partial.confidence,
                            ),
                        ),
                    )
                } else if (partial.text.isNotEmpty()) {
                    emit(TranscriptionEvent.Partial(partial.text))
                }
            }
        }

    /** Readiness, model, and language coverage of the speech-recognition component. */
    public suspend fun state(): SttState = legacySttState().toSttState()
}
