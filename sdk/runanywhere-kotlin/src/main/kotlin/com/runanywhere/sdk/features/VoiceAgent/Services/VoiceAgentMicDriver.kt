/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VoiceAgentMicDriver.kt
 *
 * Audio ingress for the voice agent. The C ABI owns NO microphone access
 * (rac_voice_agent.h "Audio-Ingress Contract"): the platform SDK captures raw
 * mic frames and pushes them continuously into the C core via
 * `rac_voice_agent_feed_audio_proto`. The core performs energy-based utterance
 * segmentation and runs the STT -> LLM -> TTS turn pipeline itself, returning
 * the synthesized reply inline for playback. This driver is therefore a thin
 * capture -> feed -> play loop with NO SDK-side VAD; turn VoiceEvents fan out
 * to the handle callback, so `RunAnywhere.streamVoiceAgent()` collectors
 * observe them without extra wiring.
 */

package com.runanywhere.sdk.features.VoiceAgent.Services

import ai.runanywhere.proto.v1.AudioEncoding
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.features.STT.Services.AudioCaptureManager
import com.runanywhere.sdk.features.TTS.Services.AudioPlaybackManager
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlin.coroutines.cancellation.CancellationException

/**
 * Captures mic audio and feeds raw frames to the in-core voice agent bound to
 * [handle]. [run] suspends until the calling coroutine is cancelled; cancel it
 * to stop the session (capture teardown is handled in a finally block).
 *
 * Segmentation/endpointing lives in the C core, which re-runs its own VAD over
 * each utterance and is strictly turn-taking (no barge-in). Mic frames that
 * arrive while a turn is processing are dropped by the bounded channel, which
 * also avoids transcribing the device's own TTS output.
 */
internal class VoiceAgentMicDriver(
    private val handle: Long,
) {
    private val logger = SDKLogger("VoiceAgentMic")
    private val capture = AudioCaptureManager()
    private val playback = AudioPlaybackManager()

    suspend fun run() {
        val chunks =
            Channel<ByteArray>(
                capacity = MIC_CHANNEL_CAPACITY,
                onBufferOverflow = BufferOverflow.DROP_OLDEST,
            )
        capture.startRecording { chunk -> chunks.trySend(chunk) }
        logger.info("Voice-agent mic capture started")
        try {
            feedLoop(chunks)
        } finally {
            capture.stopRecording()
            playback.stop()
            chunks.close()
            logger.info("Voice-agent mic capture stopped")
        }
    }

    private suspend fun feedLoop(chunks: Channel<ByteArray>) {
        while (currentCoroutineContext().isActive) {
            val chunk = chunks.receive()

            val resultBytes =
                try {
                    RunAnywhereBridge.racVoiceAgentFeedAudioProto(
                        handle,
                        chunk,
                        SAMPLE_RATE_HZ,
                        1,
                        AudioEncoding.AUDIO_ENCODING_PCM_S16_LE.value,
                        false,
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    // Never swallow JVM Errors (OOM, …). A recoverable failure
                    // means this utterance's turn failed (e.g. empty STT) or the
                    // agent was torn down; the session cancels this coroutine on
                    // teardown, so log and keep feeding rather than killing the
                    // loop on a single bad turn.
                    if (e is Error) throw e
                    logger.warning("Voice feed failed: ${e.message}")
                    null
                } ?: continue

            val result =
                try {
                    VoiceAgentResult.ADAPTER.decode(resultBytes)
                } catch (_: Exception) {
                    null
                } ?: continue

            // A non-empty reply means the core closed an utterance and ran a full
            // turn this call. synthesized_audio is self-describing WAV.
            val reply = result.synthesized_audio
            if (reply != null && reply.size > 0) {
                logger.info("Playing agent reply (${reply.size} WAV bytes)")
                playReply(reply.toByteArray())
                // Drop frames captured while the turn ran / the device spoke so
                // stale audio is not folded into the next turn.
                while (chunks.tryReceive().isSuccess) Unit
            }
        }
    }

    private suspend fun playReply(wav: ByteArray) {
        if (wav.isEmpty()) return
        try {
            playback.play(wav)
        } catch (e: CancellationException) {
            playback.stop()
            throw e
        } catch (e: Exception) {
            logger.warning("Agent reply playback failed: ${e.message}")
        }
    }

    private companion object {
        const val SAMPLE_RATE_HZ = 16_000

        /**
         * Bounded mic ingress buffer. The capture callback trySends while the
         * consumer pauses for the duration of each turn, so an unbounded channel
         * could grow without limit on long turns. DROP_OLDEST bounds memory;
         * frames captured mid-turn are discarded anyway (no barge-in).
         */
        const val MIC_CHANNEL_CAPACITY = 128
    }
}
