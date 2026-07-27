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
            chunks.close()
            logger.info("Voice-agent mic capture stopped")
        }
    }

    private suspend fun feedLoop(chunks: Channel<ByteArray>) {
        while (currentCoroutineContext().isActive) {
            val chunk = chunks.receive()

            // Half-duplex: while a streaming reply is playing out the speaker
            // (plus a short acoustic-decay tail), drop captured frames instead
            // of feeding them to the core. Playback is now async + app-side
            // (StreamingAudioPlayer), so without this the mic re-records the
            // device's own TTS and the agent transcribes + answers itself in an
            // endless loop. No barge-in by design, so dropping here is correct.
            if (VoiceTtsPlaybackGate.micSuppressed()) continue

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
            // turn this call. Audio is played INCREMENTALLY by StreamingAudioPlayer
            // as AudioFrameEvents arrive on the streamVoiceAgent flow. The whole
            // reply WAV is already synthesized by the time this blocking call
            // returns, so we know exactly how long it will play — mute the mic for
            // that duration + a tail RIGHT NOW, before receiving another frame.
            // This is the deterministic echo guard: without it the device speaker's
            // own reply is re-captured, transcribed, and answered in an endless
            // loop (worse on the phone speaker than a distant one). Also drain any
            // frames captured while the turn ran.
            val reply = result.synthesized_audio
            if (reply != null && reply.size > 0) {
                while (chunks.tryReceive().isSuccess) Unit
                val playbackMs = wavPlaybackMs(reply.toByteArray())
                if (playbackMs > 0) {
                    VoiceTtsPlaybackGate.suppressForMs(playbackMs + REPLY_TAIL_MS)
                    logger.info("turn reply ~${playbackMs}ms; muting mic through playback")
                }
            }
        }
    }

    /**
     * Duration in ms of a canonical little-endian WAV (as written by the core's
     * float32→WAV helper): byteRate is a uint32 at byte offset 28, the data-chunk
     * size a uint32 at offset 40. Falls back to (total − 44-byte header) if the
     * stored data size looks wrong. Returns 0 for anything too short to be a WAV.
     */
    private fun wavPlaybackMs(wav: ByteArray): Long {
        if (wav.size < WAV_HEADER_BYTES) return 0
        val byteRate = le32(wav, 28)
        if (byteRate <= 0) return 0
        val stored = le32(wav, 40)
        val dataSize = if (stored in 1..(wav.size - WAV_HEADER_BYTES).toLong()) stored else (wav.size - WAV_HEADER_BYTES).toLong()
        return dataSize * 1000 / byteRate
    }

    private fun le32(b: ByteArray, off: Int): Long =
        (b[off].toLong() and 0xFF) or
            ((b[off + 1].toLong() and 0xFF) shl 8) or
            ((b[off + 2].toLong() and 0xFF) shl 16) or
            ((b[off + 3].toLong() and 0xFF) shl 24)

    private companion object {
        const val SAMPLE_RATE_HZ = 16_000

        /**
         * Bounded mic ingress buffer. The capture callback trySends while the
         * consumer pauses for the duration of each turn, so an unbounded channel
         * could grow without limit on long turns. DROP_OLDEST bounds memory;
         * frames captured mid-turn are discarded anyway (no barge-in).
         */
        const val MIC_CHANNEL_CAPACITY = 128

        /** Canonical PCM/float WAV header size (RIFF + fmt + data headers). */
        const val WAV_HEADER_BYTES = 44

        /**
         * Extra mute past the reply's raw duration: absorbs AudioTrack start-up
         * latency, inter-chunk pacing, and the speaker→mic acoustic decay so the
         * reply's final syllable is never re-transcribed.
         */
        const val REPLY_TAIL_MS = 1_200L
    }
}
