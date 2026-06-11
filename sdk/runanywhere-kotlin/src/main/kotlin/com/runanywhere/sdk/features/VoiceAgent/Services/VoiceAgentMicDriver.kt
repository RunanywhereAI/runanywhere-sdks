/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VoiceAgentMicDriver.kt
 *
 * Audio ingress for the voice agent. The C ABI owns NO microphone access
 * (rac_voice_agent.h "Audio-Ingress Contract"): the platform SDK must
 * capture mic audio and push complete utterances into the C core, or the
 * session is dead-air. This driver implements ingress mode 1 (per-utterance
 * turns): capture 16 kHz mono PCM16 via [AudioCaptureManager], segment
 * utterances with energy-based endpointing, and feed each utterance through
 * `rac_voice_agent_process_turn_proto`. Turn VoiceEvents fan out to the
 * handle callback, so `RunAnywhere.streamVoiceAgent()` collectors observe
 * them without extra wiring.
 */

package com.runanywhere.sdk.features.VoiceAgent.Services

import ai.runanywhere.proto.v1.AudioEncoding
import ai.runanywhere.proto.v1.VoiceAgentTurnRequest
import com.runanywhere.sdk.features.STT.Services.AudioCaptureManager
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.ByteArrayOutputStream
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.sqrt
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import okio.ByteString.Companion.toByteString

/**
 * Captures mic audio and drives per-utterance voice-agent turns against
 * [handle]. [run] suspends until the calling coroutine is cancelled; cancel
 * it to stop the session (capture teardown is handled in a finally block).
 *
 * Endpointing is energy-based and intentionally simple: the C++ pipeline
 * re-runs its own VAD over each submitted buffer, so the only job here is
 * deciding where one utterance ends. Mic chunks that arrive while a turn is
 * processing are discarded — the pipeline is strictly turn-taking (no
 * barge-in), which also avoids transcribing the device's own TTS output.
 */
internal class VoiceAgentMicDriver(private val handle: Long) {

    private val logger = SDKLogger("VoiceAgentMic")
    private val capture = AudioCaptureManager()

    suspend fun run() {
        val chunks = Channel<ByteArray>(Channel.UNLIMITED)
        capture.startRecording { chunk -> chunks.trySend(chunk) }
        logger.info("Voice-agent mic capture started")
        try {
            segmentLoop(chunks)
        } finally {
            capture.stopRecording()
            chunks.close()
            logger.info("Voice-agent mic capture stopped")
        }
    }

    private suspend fun segmentLoop(chunks: Channel<ByteArray>) {
        val preRoll = ArrayDeque<ByteArray>()
        val utterance = ByteArrayOutputStream()
        var inSpeech = false
        var speechMs = 0
        var silenceMs = 0

        while (currentCoroutineContext().isActive) {
            val chunk = chunks.receive()
            val chunkMs = chunk.size * 1000 / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE)
            val speech = rms(chunk) >= SPEECH_RMS_THRESHOLD

            if (!inSpeech) {
                preRoll.addLast(chunk)
                while (preRoll.size > PRE_ROLL_CHUNKS) preRoll.removeFirst()
                if (speech) {
                    inSpeech = true
                    speechMs = chunkMs
                    silenceMs = 0
                    utterance.reset()
                    preRoll.forEach(utterance::write)
                    preRoll.clear()
                }
                continue
            }

            utterance.write(chunk)
            if (speech) {
                speechMs += chunkMs
                silenceMs = 0
            } else {
                silenceMs += chunkMs
            }

            val utteranceMs = utterance.size() * 1000 / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE)
            if (silenceMs >= END_OF_UTTERANCE_SILENCE_MS || utteranceMs >= MAX_UTTERANCE_MS) {
                val audio = utterance.toByteArray()
                inSpeech = false
                utterance.reset()
                if (speechMs >= MIN_SPEECH_MS) {
                    processTurn(audio)
                    // Drop chunks captured while the turn ran (agent thinking /
                    // speaking) so stale audio is not folded into the next turn.
                    while (chunks.tryReceive().isSuccess) Unit
                } else {
                    logger.debug("Utterance discarded (${speechMs}ms speech < ${MIN_SPEECH_MS}ms)")
                }
                speechMs = 0
                silenceMs = 0
            }
        }
    }

    private fun processTurn(audio: ByteArray) {
        val request =
            VoiceAgentTurnRequest(
                request_id = UUID.randomUUID().toString(),
                audio_data = audio.toByteString(),
                sample_rate_hz = SAMPLE_RATE_HZ,
                channels = 1,
                encoding = AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            )
        logger.info("Submitting voice turn (${audio.size} bytes)")
        try {
            // Events reach streamVoiceAgent() collectors via the handle
            // callback fan-out; this listener only keeps the native stream
            // alive.
            val rc =
                RunAnywhereBridge.racVoiceAgentProcessTurnProto(
                    handle,
                    VoiceAgentTurnRequest.ADAPTER.encode(request),
                ) { true }
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                logger.warning("Voice turn failed: rc=$rc")
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            logger.error("Voice turn threw: ${e.message}")
        }
    }

    private fun rms(chunk: ByteArray): Double {
        val samples = chunk.size / BYTES_PER_SAMPLE
        if (samples == 0) return 0.0
        var sum = 0.0
        for (i in 0 until samples) {
            val lo = chunk[2 * i].toInt() and 0xff
            val hi = chunk[2 * i + 1].toInt()
            val sample = ((hi shl 8) or lo).toDouble()
            sum += sample * sample
        }
        return sqrt(sum / samples) / Short.MAX_VALUE
    }

    private companion object {
        const val SAMPLE_RATE_HZ = 16_000
        const val BYTES_PER_SAMPLE = 2

        /** Normalized RMS above which a chunk counts as speech. */
        const val SPEECH_RMS_THRESHOLD = 0.015

        /** Trailing silence that closes an utterance. */
        const val END_OF_UTTERANCE_SILENCE_MS = 800

        /** Utterances with less accumulated speech than this are noise. */
        const val MIN_SPEECH_MS = 300

        /** Hard cap so a noisy room cannot grow an unbounded buffer. */
        const val MAX_UTTERANCE_MS = 15_000

        /** Leading chunks kept so the utterance onset is not clipped. */
        const val PRE_ROLL_CHUNKS = 3
    }
}
