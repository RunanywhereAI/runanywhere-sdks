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
 *
 * Playout runs CONCURRENTLY with the feed loop. It used to be awaited inline,
 * which stopped the feed for the whole of a reply and then dropped everything
 * captured during it — so speaking over the agent could not be heard at all and
 * the only way to take the turn back was the on-screen control. Mirrors Swift
 * `VoiceAgentMicDriver`, which made the same move for the same reason.
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
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
 * ## Talking over the agent
 *
 * The frames keep flowing while a reply is audible, so the core can hear the
 * user interrupt. Two things make that safe:
 *
 *  1. **The core decides, not this layer.** `voice_agent_feed_abi.cpp` reports
 *     the segmenter's speech *onset* on the frame that opens the energy gate,
 *     and only calls it `INTERRUPT_REASON_USER_BARGE_IN` when the onset lands
 *     inside the window where the reply is still audible AND clears the echo
 *     estimate it learned from the reply's own first frames. A voice arriving
 *     on top of the loudspeaker is louder than the loudspeaker; the agent's own
 *     words are not, so they cannot cut it off. Failing that test means the
 *     reply simply finishes, which is the safe way to be wrong.
 *  2. **Echo cancellation where the device has it.** [AudioCaptureManager] is
 *     asked for an echo-cancelling capture ([AudioCaptureManager.startRecording]'s
 *     `echoCancelling`). On a device that has a canceller, that opens
 *     `VOICE_COMMUNICATION` with `AcousticEchoCanceler` attached; on one that
 *     does not — most emulators — it records from the plain `MIC` source, since
 *     the communication source's processing would cost signal without cancelling
 *     anything. It is an improvement, not a prerequisite: the margin above does
 *     the separating whenever there is no canceller.
 *
 * Only this layer can stop the speaker, so [stopPlayback] is the other half of
 * the handshake: `VoiceSession` watches the core's stream and calls it on a
 * barge-in. Swift `VoiceAgentMicDriver` has exactly this shape, so the two
 * platforms make the same promise and every UI mounted on either can, too.
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

    /**
     * The reply coming out of the speaker right now, held so it can be cut off
     * from outside the feed loop — which is the whole point of not awaiting it
     * inline any more.
     */
    private val playoutLock = Any()
    private var playoutJob: Job? = null

    /**
     * The live mic queue, published so [stopPlayback] can drop what is behind a
     * tap on the interrupt control. Null between sessions.
     */
    @Volatile
    private var chunks: Channel<ByteArray>? = null

    suspend fun run() {
        // Playout is launched into this scope, so it is a child of the caller's job: cancelling
        // the session cancels a reply in flight, and run() does not return until it has.
        coroutineScope {
            val queue =
                Channel<ByteArray>(
                    capacity = MIC_CHANNEL_CAPACITY,
                    onBufferOverflow = BufferOverflow.DROP_OLDEST,
                )
            chunks = queue
            // Ask for the echo-cancelling capture: the frames now keep flowing
            // while the agent is audible, so anything the platform can take out
            // of the mic signal is one less thing the core's echo margin has to
            // separate. Asking is not the same as getting — a device without a
            // canceller stays on the plain MIC source; see startRecording.
            capture.startRecording(echoCancelling = true) { chunk -> queue.trySend(chunk) }
            logger.info("Voice-agent mic capture started")
            try {
                feedLoop(queue, this)
            } finally {
                capture.stopRecording()
                // Cancelling the playout job is what restores the LISTENING
                // phase for a subscriber; playback.stop() alone would leave a UI
                // latched on "Speaking" over a silent speaker.
                cancelPlayout()
                queue.close()
                chunks = null
                logger.info("Voice-agent mic capture stopped")
            }
        }
    }

    private suspend fun feedLoop(chunks: Channel<ByteArray>, scope: CoroutineScope) {
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
                    // A failed feed is a failed *turn*: the core closed an
                    // utterance and spent seconds inside this one call, so the
                    // frames queued behind it are as stale as the ones behind a
                    // reply. Only the reply path used to drop them, which let one
                    // failed turn hand its own backlog to the next — a spurious
                    // utterance closing, failing, and closing again off the same
                    // audio.
                    discardBacklog(chunks)
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
                // The feed call blocked for the whole turn, so the queue now
                // holds whatever the mic heard while the reply was being
                // computed. Those frames predate playout: they are not part of
                // the turn that just closed and they are not the user talking
                // over a reply that had not started. Feeding them would seed the
                // core's echo estimate from pre-playout quiet and let the
                // reply's own onset clear the bar it set — the agent
                // interrupting itself. The core drops its own partial frame the
                // same way; this drops the driver's.
                discardBacklog(chunks)
                startPlayout(scope, reply.toByteArray())
            }
        }
    }

    /** Drop everything captured while the last turn was being computed. */
    private fun discardBacklog(chunks: Channel<ByteArray>) {
        while (chunks.tryReceive().isSuccess) Unit
    }

    /**
     * Silence the reply playing out right now, if any.
     *
     * This driver plays agent replies through its *own* [AudioPlaybackManager], so the TTS
     * namespace's stop — which only reaches the module-level playback singleton — cannot
     * touch it. Barge-in therefore has to come through here, or the agent talks over the
     * user to the end of its buffer. Safe to call from any thread and when nothing is
     * playing: [AudioPlaybackManager.stop] is a no-op without a live track.
     *
     * @param discardPendingInput `true` for the on-screen interrupt control, where the frames
     *   queued behind the tap are the tail of the agent's own playout and belong to nobody.
     *   `false` for a voice barge-in, where those same frames are the first syllables of the
     *   user's sentence — dropping them would clip the very turn that caused the interrupt.
     *   Mirrors Swift `VoiceAgentMicDriver.stopPlayback(discardPendingInput:)`.
     */
    fun stopPlayback(discardPendingInput: Boolean) {
        cancelPlayout()
        if (discardPendingInput) chunks?.let(::discardBacklog)
    }

    /**
     * Begin one reply without blocking the feed loop.
     *
     * Replies are strictly sequential (the core runs one turn per feed call), so a job still
     * live here can only be a stale one; cancel it rather than leaving two players fighting
     * over the speaker.
     */
    private fun startPlayout(scope: CoroutineScope, wav: ByteArray) {
        val job = scope.launch { playReply(wav) }
        val stale =
            synchronized(playoutLock) {
                val previous = playoutJob
                playoutJob = job
                previous
            }
        stale?.cancel()
    }

    /** Stop whatever is playing and let the playout job report LISTENING. */
    private fun cancelPlayout() {
        val job =
            synchronized(playoutLock) {
                val live = playoutJob
                playoutJob = null
                live
            }
        job?.cancel()
        // The job's cancellation resumes play() with PlaybackInterrupted, but a job that has
        // not reached play() yet has no track to interrupt; stopping directly makes the
        // silence immediate either way.
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
         * consumer is inside one blocking feed call for the whole of a turn, so
         * an unbounded channel could grow without limit on long turns.
         * DROP_OLDEST bounds memory; frames captured while the turn was being
         * computed are dropped when the reply comes back anyway. Playout no
         * longer blocks the consumer, so nothing is dropped once the reply is
         * audible — that is the window a barge-in has to be heard in.
         */
        const val MIC_CHANNEL_CAPACITY = RADefaults.AudioCapture.MIC_CHANNEL_CAPACITY
    }
}
