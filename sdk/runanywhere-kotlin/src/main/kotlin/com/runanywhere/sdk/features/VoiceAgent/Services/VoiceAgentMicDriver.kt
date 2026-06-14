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
import ai.runanywhere.proto.v1.VoiceEvent
import com.runanywhere.sdk.features.STT.Services.AudioCaptureManager
import com.runanywhere.sdk.features.TTS.Services.AudioPlaybackManager
import com.runanywhere.sdk.foundation.errors.SDKException
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
    private val playback = AudioPlaybackManager()

    suspend fun run() {
        val chunks = Channel<ByteArray>(Channel.UNLIMITED)
        capture.startRecording { chunk -> chunks.trySend(chunk) }
        logger.info("Voice-agent mic capture started")
        try {
            segmentLoop(chunks)
        } finally {
            capture.stopRecording()
            playback.stop()
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
        var noiseFloor = SPEECH_RMS_THRESHOLD

        while (currentCoroutineContext().isActive) {
            val chunk = chunks.receive()
            val chunkMs = chunk.size * 1000 / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE)
            // Adaptive endpointing. A fixed RMS threshold misses the end-of-
            // utterance pause on devices whose mic noise floor sits above the
            // constant: silence is never seen, so an utterance only ends at the
            // MAX_UTTERANCE_MS cap (a ~1s turn then waits ~15s). Track the ambient
            // floor — drop instantly to any quieter level, and creep up only while
            // not in speech so loud speech can't inflate it — and require a chunk
            // to rise clearly above that floor to count as speech.
            val level = rms(chunk)
            val speechThreshold = maxOf(SPEECH_RMS_THRESHOLD, noiseFloor * SPEECH_FLOOR_MULTIPLIER)
            val speech = level >= speechThreshold
            noiseFloor = when {
                level < noiseFloor -> level
                !speech -> noiseFloor + (level - noiseFloor) * NOISE_FLOOR_RISE
                else -> noiseFloor
            }

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

    private suspend fun processTurn(audio: ByteArray) {
        val request =
            VoiceAgentTurnRequest(
                request_id = UUID.randomUUID().toString(),
                audio_data = audio.toByteString(),
                sample_rate_hz = SAMPLE_RATE_HZ,
                channels = 1,
                encoding = AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            )
        logger.info("Submitting voice turn (${audio.size} bytes)")

        // Accumulate synthesized TTS frames from the turn's event stream;
        // played after the native call returns. Events also reach
        // streamVoiceAgent() collectors via the handle callback fan-out.
        val ttsPcm = ByteArrayOutputStream()
        var ttsSampleRate = 0
        var ttsEncoding = AudioEncoding.AUDIO_ENCODING_UNSPECIFIED
        var rc = RunAnywhereBridge.RAC_SUCCESS
        try {
            rc =
                RunAnywhereBridge.racVoiceAgentProcessTurnProto(
                    handle,
                    VoiceAgentTurnRequest.ADAPTER.encode(request),
                ) { bytes ->
                    try {
                        val frame = VoiceEvent.ADAPTER.decode(bytes).audio
                        if (frame != null && frame.pcm.size > 0) {
                            ttsPcm.write(frame.pcm.toByteArray())
                            if (frame.sample_rate_hz > 0) ttsSampleRate = frame.sample_rate_hz
                            if (frame.encoding != AudioEncoding.AUDIO_ENCODING_UNSPECIFIED) {
                                ttsEncoding = frame.encoding
                            }
                        }
                    } catch (_: Exception) {
                        // Non-VoiceEvent or undecodable payload — ignore.
                    }
                    true
                }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            logger.error("Voice turn threw: ${e.message}")
        }

        if (rc == RunAnywhereBridge.RAC_ERROR_NOT_INITIALIZED) {
            // The agent was torn down (session cleaned up) while this driver was
            // still capturing. Stop instead of re-submitting every utterance to a
            // dead agent, which spams "voice agent is not initialized" failures.
            throw SDKException.voiceAgent("Voice agent is no longer initialized")
        }
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            logger.warning("Voice turn failed: rc=$rc")
        }

        playTtsAudio(ttsPcm.toByteArray(), ttsSampleRate, ttsEncoding)
    }

    // Play the turn's synthesized reply through the shared TTS sink. Runs
    // before segmentLoop drains stale mic chunks, so the microphone stays
    // gated while the device speaks (no self-transcription).
    private suspend fun playTtsAudio(pcm: ByteArray, sampleRateHz: Int, encoding: AudioEncoding) {
        if (pcm.isEmpty()) return
        val sampleRate = if (sampleRateHz > 0) sampleRateHz else DEFAULT_TTS_SAMPLE_RATE_HZ
        val wav =
            when (encoding) {
                AudioEncoding.AUDIO_ENCODING_PCM_S16_LE -> pcmS16ToWav(pcm, sampleRate)
                // TTS backends emit f32 LE (AudioFrameEvent contract default).
                else -> RunAnywhereBridge.racAudioFloat32ToWav(pcm, sampleRate)
            }
        if (wav == null || wav.isEmpty()) {
            logger.warning("TTS audio conversion failed (${pcm.size} bytes, ${sampleRate}Hz, $encoding)")
            return
        }
        logger.info("Playing agent reply (${pcm.size} PCM bytes @ ${sampleRate}Hz)")
        try {
            playback.play(wav)
        } catch (e: CancellationException) {
            playback.stop()
            throw e
        } catch (e: Exception) {
            logger.warning("Agent reply playback failed: ${e.message}")
        }
    }

    private fun pcmS16ToWav(pcm: ByteArray, sampleRate: Int): ByteArray {
        val channels = 1
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val header = ByteArray(44)
        fun putInt(offset: Int, value: Int) {
            header[offset] = value.toByte()
            header[offset + 1] = (value shr 8).toByte()
            header[offset + 2] = (value shr 16).toByte()
            header[offset + 3] = (value shr 24).toByte()
        }
        fun putShort(offset: Int, value: Int) {
            header[offset] = value.toByte()
            header[offset + 1] = (value shr 8).toByte()
        }
        "RIFF".toByteArray().copyInto(header, 0)
        putInt(4, 36 + pcm.size)
        "WAVE".toByteArray().copyInto(header, 8)
        "fmt ".toByteArray().copyInto(header, 12)
        putInt(16, 16)
        putShort(20, 1)
        putShort(22, channels)
        putInt(24, sampleRate)
        putInt(28, byteRate)
        putShort(32, channels * bitsPerSample / 8)
        putShort(34, bitsPerSample)
        "data".toByteArray().copyInto(header, 36)
        putInt(40, pcm.size)
        return header + pcm
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

        /** Absolute floor for the adaptive speech threshold (normalized RMS). */
        const val SPEECH_RMS_THRESHOLD = 0.015

        /** Speech must exceed this multiple of the tracked ambient noise floor. */
        const val SPEECH_FLOOR_MULTIPLIER = 2.2

        /** Per-chunk rate at which the ambient floor creeps up toward louder ambient. */
        const val NOISE_FLOOR_RISE = 0.05

        /** Trailing silence that closes an utterance. */
        const val END_OF_UTTERANCE_SILENCE_MS = 800

        /** Utterances with less accumulated speech than this are noise. */
        const val MIN_SPEECH_MS = 300

        /** Hard cap so a noisy room cannot grow an unbounded buffer. */
        const val MAX_UTTERANCE_MS = 15_000

        /** Leading chunks kept so the utterance onset is not clipped. */
        const val PRE_ROLL_CHUNKS = 3

        /** Piper's native rate; used when the audio frame omits sample_rate_hz. */
        const val DEFAULT_TTS_SAMPLE_RATE_HZ = 22_050
    }
}
