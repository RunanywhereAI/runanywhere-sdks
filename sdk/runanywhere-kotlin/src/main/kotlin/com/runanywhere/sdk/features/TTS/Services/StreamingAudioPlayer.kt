/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * StreamingAudioPlayer.kt
 *
 * Incremental PCM playback for the streaming voice agent. Unlike
 * AudioPlaybackManager (MODE_STATIC, one-shot WAV blob), this plays a sequence
 * of float32 PCM chunks as they arrive — so a spoken reply starts playing after
 * its FIRST sentence/clause while the rest is still being generated + synthesized
 * on the NPU/CPU. Fed by AudioFrameEvent payloads off `RunAnywhere.streamVoiceAgent()`
 * (the voice-agent AudioFrameEvent is float32 little-endian, mono).
 *
 * Threading: enqueue() runs on the flow collector and only appends to an
 * unbounded queue (never blocks the collector); a dedicated writer thread drains
 * the queue and does blocking AudioTrack writes, which pace playback naturally.
 */

package com.runanywhere.sdk.features.TTS.Services

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.runanywhere.sdk.features.VoiceAgent.Services.VoiceTtsPlaybackGate
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue

internal class StreamingAudioPlayer {
    private val logger = SDKLogger("StreamingAudio")

    // Unbounded so the flow collector never blocks handing off a chunk; the writer
    // thread paces real playback via blocking AudioTrack writes.
    private val queue = LinkedBlockingQueue<FloatArray>()
    private var track: AudioTrack? = null
    private var writer: Thread? = null
    private var sampleRate = 0

    // Total mono frames handed to (and accepted by) AudioTrack.write across the
    // whole reply. WRITE_BLOCKING only blocks until samples are COPIED into the
    // track buffer, not until they are rendered, so at end-of-stream up to a
    // buffer's worth is still unplayed; the drain below waits for the hardware
    // playback head to reach this count before releasing (else the tail clips).
    @Volatile private var framesWritten = 0L

    @Volatile private var stopped = false

    /** Sentinel: the reply's audio is complete — drain then release the track. */
    private val endOfStream = FloatArray(0)

    /**
     * Append one non-final AudioFrameEvent PCM chunk. [pcmLeFloat32] is float32
     * little-endian mono samples; [sampleRateHz] is the chunk's rate (all chunks
     * of a reply share it — piper is 22050). Lazily starts the track on the first
     * chunk. No-op after [markFinal]/[stop].
     */
    fun enqueue(pcmLeFloat32: ByteArray, sampleRateHz: Int) {
        if (stopped || pcmLeFloat32.isEmpty()) return
        ensureStarted(if (sampleRateHz > 0) sampleRateHz else DEFAULT_RATE)
        queue.put(toFloats(pcmLeFloat32))
    }

    /** The terminal AudioFrameEvent (is_final): let queued audio finish, then release. */
    fun markFinal() {
        if (stopped) return
        // Only meaningful if playback ever started; otherwise nothing to drain.
        if (track != null) queue.put(endOfStream)
    }

    /** Hard stop (session teardown / barge-in): abort playback immediately. */
    fun stop() {
        if (stopped) return
        stopped = true
        writer?.interrupt()
        releaseTrack()
    }

    @Synchronized
    private fun ensureStarted(rate: Int) {
        if (track != null || stopped) return
        sampleRate = rate
        val minBuf =
            AudioTrack.getMinBufferSize(
                rate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
            )
        if (minBuf <= 0) {
            logger.error("Invalid AudioTrack min buffer ($minBuf) for rate=$rate; audio disabled")
            stopped = true
            return
        }
        // ~0.5 s of headroom so short inter-chunk synthesis gaps don't underrun.
        val bufBytes = maxOf(minBuf, rate * BYTES_PER_SAMPLE / 2)
        val t =
            AudioTrack
                .Builder()
                .setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                ).setAudioFormat(
                    AudioFormat
                        .Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                ).setBufferSizeInBytes(bufBytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        t.play()
        track = t
        // Half-duplex: tell the mic driver to stop feeding the core while this
        // reply plays, so the device does not transcribe its own TTS (echo loop).
        VoiceTtsPlaybackGate.onPlaybackStart()
        writer = Thread({ writeLoop() }, "StreamingAudioPlayer").also { it.start() }
        logger.info("Streaming audio started (rate=$rate, buf=$bufBytes)")
    }

    private fun writeLoop() {
        val t = track ?: return
        try {
            while (!stopped) {
                val buf = queue.take()
                if (buf === endOfStream) {
                    // Blocking writes above copied all queued audio into the track
                    // buffer, but a buffer's worth is still unplayed. Wait for the
                    // hardware to render it out before releasing, or the last
                    // ~0.5 s of the reply is clipped.
                    drainAndRelease()
                    return
                }
                var off = 0
                while (off < buf.size && !stopped) {
                    val n = t.write(buf, off, buf.size - off, AudioTrack.WRITE_BLOCKING)
                    if (n < 0) {
                        logger.warning("AudioTrack.write returned $n; stopping stream")
                        return
                    }
                    off += n
                    framesWritten += n // mono float32: 1 float == 1 frame
                }
            }
        } catch (_: InterruptedException) {
            // stop() interrupted us — normal teardown.
        } catch (e: Exception) {
            logger.warning("Streaming audio writer failed: ${e.message}")
        }
    }

    /**
     * Natural end-of-stream: let the hardware play out everything already
     * written before releasing, so the reply's tail is not clipped. Polls the
     * playback head toward [framesWritten] with a stall + hard-cap guard so a
     * misbehaving track can never hang the writer thread. A concurrent hard
     * [stop] flips `stopped` and breaks the wait immediately (barge-in wins).
     */
    private fun drainAndRelease() {
        val t = track
        if (t != null) {
            try {
                t.stop() // MODE_STREAM: renders the last written buffer, then halts
                val target = framesWritten
                var lastHead = -1L
                var stalls = 0
                var waited = 0
                while (!stopped && waited < MAX_DRAIN_MS) {
                    val head = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
                    if (head >= target) break
                    if (head == lastHead) {
                        if (++stalls >= DRAIN_STALL_TICKS) break
                    } else {
                        stalls = 0
                        lastHead = head
                    }
                    Thread.sleep(DRAIN_TICK_MS.toLong())
                    waited += DRAIN_TICK_MS
                }
            } catch (_: InterruptedException) {
                // stop() interrupted us — teardown; fall through to release.
            } catch (_: Exception) {
            }
        }
        releaseTrack()
    }

    @Synchronized
    private fun releaseTrack() {
        val t = track ?: return
        track = null
        try {
            t.stop()
        } catch (_: Exception) {
        }
        t.release()
        // Reply finished playing (or was hard-stopped): re-open the mic after the
        // hardware buffer drain + acoustic-decay tail (handled inside the gate).
        VoiceTtsPlaybackGate.onPlaybackStop()
    }

    private fun toFloats(bytes: ByteArray): FloatArray {
        val fb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        val out = FloatArray(fb.remaining())
        fb.get(out)
        return out
    }

    private companion object {
        const val DEFAULT_RATE = 22_050
        const val BYTES_PER_SAMPLE = 4 // float32 mono

        // End-of-stream drain: poll the playback head every DRAIN_TICK_MS until it
        // reaches the written frame count. DRAIN_STALL_TICKS of no progress (head
        // frozen) or MAX_DRAIN_MS total both end the wait defensively.
        const val DRAIN_TICK_MS = 20
        const val DRAIN_STALL_TICKS = 15 // ~300 ms of a frozen head → give up
        const val MAX_DRAIN_MS = 4_000 // hard cap so the writer never hangs
    }
}
