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
import ai.runanywhere.proto.v1.VoiceAgentAudioFrame
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.features.STT.Services.AudioCaptureManager
import com.runanywhere.sdk.features.TTS.Services.AudioPlaybackException
import com.runanywhere.sdk.features.TTS.Services.AudioPlaybackManager
import com.runanywhere.sdk.generated.RADefaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.api.AgentState
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import okio.ByteString.Companion.toByteString
import kotlin.coroutines.cancellation.CancellationException

/**
 * Captures mic audio and feeds raw frames to the in-core voice agent bound to
 * [handle]. [run] suspends until the calling coroutine is cancelled; cancel it
 * to stop the session (capture teardown is handled in a finally block).
 *
 * Segmentation/endpointing lives in the C core, which re-runs its own VAD over
 * each utterance.
 *
 * ## Why this loop is half-duplex, and what it would take to change
 *
 * The agent takes turns: while a reply is playing out, captured frames are
 * dropped instead of fed. Interruption is therefore an explicit control
 * ([stopPlayback]) and never something the user can do by simply talking over
 * the agent — which is why every UI mounted on this driver has to say so rather
 * than imply the mic is still listening. Swift `VoiceAgentMicDriver` is the
 * same shape for the same reasons, so the two platforms make the same promise.
 *
 * Two things are missing for hands-free barge-in, and neither can be supplied
 * from here:
 *
 *  1. **A speech signal during playout.** `rac_voice_agent_feed_audio_proto`
 *     answers a frame with a *completed turn* or with nothing; it reports
 *     nothing at the moment it first hears a voice. Feeding through the playout
 *     would therefore let the core capture the barge-in, but this layer would
 *     not learn of it until the whole replacement turn (STT -> LLM -> TTS,
 *     seconds) had run — far too late to cut the sentence the user talked over.
 *     Cutting it promptly needs the core to emit speech-start from its
 *     segmenter; synthesizing it here would be an SDK-side VAD, duplicating the
 *     core's segmenter on one platform only.
 *  2. **Echo cancellation on the capture path.** Feeding while the speaker is
 *     live re-feeds the device's own reply, which the core segments as a user
 *     utterance and answers — the agent talks to itself. Suppressing that is
 *     `AcousticEchoCanceler` on a `VOICE_COMMUNICATION` capture, which not
 *     every device (nor the emulator's audio HAL) provides.
 *
 * Until both exist, dropping the frames is the honest behaviour: the bounded
 * channel bounds memory and keeps the device's own TTS out of the next turn.
 */
internal class VoiceAgentMicDriver(
    private val handle: Long,
    /**
     * Reports [AgentState.SPEAKING] when a reply becomes audible and
     * [AgentState.LISTENING] when it stops. The core emits `PLAYING_TTS` *before*
     * synthesis and hands the WAV back for this driver to play, so its pipeline
     * states describe intent, not sound. Only this layer knows when audio is
     * actually leaving the speaker, so only this layer can say "speaking"
     * truthfully — and the interrupt affordance a UI mounts on that state is
     * then reachable exactly while there is something to interrupt.
     * Mirrors Swift `VoiceAgentMicDriver.onPlaybackPhase`.
     */
    private val onPlaybackPhase: (AgentState) -> Unit = {},
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
                        VoiceAgentAudioFrame.ADAPTER.encode(
                            VoiceAgentAudioFrame(
                                audio_data = chunk.toByteString(),
                                sample_rate_hz = SAMPLE_RATE_HZ,
                                channels = 1,
                                encoding = AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
                                is_final = false,
                            ),
                        ),
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
                // stale audio is not folded into the next turn. See the
                // half-duplex note on the class: without echo cancellation these
                // frames are mostly the device's own reply, and feeding them
                // back would have the agent answer itself.
                while (chunks.tryReceive().isSuccess) Unit
            }
        }
    }

    /**
     * Silence the reply playing out right now, if any.
     *
     * This driver plays agent replies through its *own* [AudioPlaybackManager], so the TTS
     * namespace's stop — which only reaches the module-level playback singleton — cannot
     * touch it. Barge-in therefore has to come through here, or the agent talks over the
     * user to the end of its buffer. Safe to call from any thread and when nothing is
     * playing: [AudioPlaybackManager.stop] is a no-op without a live track.
     */
    fun stopPlayback() {
        playback.stop()
    }

    private suspend fun playReply(wav: ByteArray) {
        if (wav.isEmpty()) return
        // The listening report is in `finally` so an interrupted or failed playout
        // still ends the speaking state — a panel that latches on "Speaking" over a
        // silent speaker is the exact contradiction this signal exists to prevent.
        onPlaybackPhase(AgentState.SPEAKING)
        try {
            playback.play(wav)
        } catch (e: CancellationException) {
            playback.stop()
            throw e
        } catch (e: AudioPlaybackException.PlaybackInterrupted) {
            // Barge-in, not a fault: the user took the turn back mid-utterance. Logged as
            // the ordinary outcome it is so the log does not read as a playback failure.
            logger.info("Agent reply interrupted")
        } catch (e: Exception) {
            logger.warning("Agent reply playback failed: ${e.message}")
        } finally {
            onPlaybackPhase(AgentState.LISTENING)
        }
    }

    private companion object {
        const val SAMPLE_RATE_HZ = RADefaults.AudioCapture.MIC_SAMPLE_RATE_HZ

        /**
         * Bounded mic ingress buffer. The capture callback trySends while the
         * consumer pauses for the duration of each turn, so an unbounded channel
         * could grow without limit on long turns. DROP_OLDEST bounds memory;
         * frames captured mid-turn are discarded anyway (the class note explains
         * what hands-free barge-in would need first).
         */
        const val MIC_CHANNEL_CAPACITY = RADefaults.AudioCapture.MIC_CHANNEL_CAPACITY
    }
}
