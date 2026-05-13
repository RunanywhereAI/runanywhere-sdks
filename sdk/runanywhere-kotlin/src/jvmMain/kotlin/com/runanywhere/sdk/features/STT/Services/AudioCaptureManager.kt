/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM `actual` implementation of [AudioCaptureManager] backed by
 * `javax.sound.sampled.TargetDataLine`. Captures PCM 16-bit mono samples at
 * 16 kHz — the canonical Whisper / Sherpa-ONNX input format.
 *
 * iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 *
 * Permission: desktop hosts grant microphone access at the OS level; this
 * implementation always reports permission as granted and surfaces an
 * SDKException from `startRecording` if the line cannot actually be opened.
 *
 * Audio session: there is no concept of audio focus on the JVM, so
 * `activateAudioSession` / `deactivateAudioSession` are no-ops.
 */

package com.runanywhere.sdk.features.STT.Services

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.DataLine
import javax.sound.sampled.LineUnavailableException
import javax.sound.sampled.TargetDataLine
import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

actual class AudioCaptureManager actual constructor() {
    private val logger = SDKLogger("AudioCapture")

    private val recordingFlag = AtomicBoolean(false)

    @Volatile
    private var targetLine: TargetDataLine? = null

    @Volatile
    private var captureScope: CoroutineScope? = null

    @Volatile
    private var captureJob: Job? = null

    @Volatile
    private var currentAudioLevel: Float = 0f

    actual val isRecording: Boolean
        get() = recordingFlag.get()

    actual val audioLevel: Float
        get() = currentAudioLevel

    init {
        logger.info("AudioCaptureManager initialized (JVM)")
    }

    actual suspend fun requestPermission(): Boolean = true

    actual suspend fun startRecording(onAudioData: (ByteArray) -> Unit) {
        if (recordingFlag.get()) {
            logger.warning("Already recording")
            return
        }

        val sampleRate = AudioCaptureConstants.TARGET_SAMPLE_RATE.toFloat()
        val sampleSizeBits = AudioCaptureConstants.BYTES_PER_SAMPLE * 8
        val channels = AudioCaptureConstants.CHANNEL_COUNT

        // signed = true, bigEndian = false → standard 16-bit PCM little-endian.
        val format =
            AudioFormat(
                // sampleRate    =
                sampleRate,
                // sampleSizeInBits =
                sampleSizeBits,
                // channels      =
                channels,
                // signed        =
                true,
                // bigEndian     =
                false,
            )

        val info = DataLine.Info(TargetDataLine::class.java, format)
        if (!AudioSystem.isLineSupported(info)) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message =
                    AudioCaptureError.NoInputDevice.description +
                        " (PCM 16 kHz mono 16-bit not supported by AudioSystem)",
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
            )
        }

        val line =
            try {
                AudioSystem.getLine(info) as TargetDataLine
            } catch (e: LineUnavailableException) {
                throw SDKException.make(
                    code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                    message = AudioCaptureError.NoInputDevice.description + ": ${e.message}",
                    category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                    cause = e,
                )
            } catch (t: Throwable) {
                throw SDKException.make(
                    code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                    message = AudioCaptureError.EngineStartFailed(t.message).description,
                    category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                    cause = t,
                )
            }

        // ~100 ms buffer: 16000 * 2 bytes * 0.1 s = 3200 bytes.
        val chunkBytes =
            (
                AudioCaptureConstants.TARGET_SAMPLE_RATE *
                    AudioCaptureConstants.BYTES_PER_SAMPLE *
                    AudioCaptureConstants.CHUNK_DURATION_MS
            ) / 1000
        // Open with a buffer of ~2x the chunk so the producer never blocks the consumer.
        val openBufferBytes = chunkBytes * 4

        try {
            line.open(format, openBufferBytes)
            line.start()
        } catch (e: LineUnavailableException) {
            try {
                line.close()
            } catch (_: Throwable) {
                // ignored
            }
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message = AudioCaptureError.EngineStartFailed(e.message).description,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                cause = e,
            )
        } catch (t: Throwable) {
            try {
                line.close()
            } catch (_: Throwable) {
                // ignored
            }
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message = AudioCaptureError.EngineStartFailed(t.message).description,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                cause = t,
            )
        }

        targetLine = line
        recordingFlag.set(true)

        val scope = CoroutineScope(Dispatchers.IO)
        captureScope = scope
        captureJob =
            scope.launch {
                val buffer = ByteArray(chunkBytes)
                try {
                    while (isActive && recordingFlag.get()) {
                        val bytesRead =
                            try {
                                line.read(buffer, 0, chunkBytes)
                            } catch (t: Throwable) {
                                logger.error("TargetDataLine.read threw: ${t.message}", throwable = t)
                                break
                            }
                        if (bytesRead > 0) {
                            val chunk = buffer.copyOf(bytesRead)
                            currentAudioLevel = computeNormalizedLevel(chunk)
                            try {
                                onAudioData(chunk)
                            } catch (t: Throwable) {
                                logger.error("onAudioData callback threw: ${t.message}", throwable = t)
                            }
                        } else if (bytesRead < 0) {
                            logger.warning("TargetDataLine.read returned $bytesRead — stopping capture")
                            break
                        }
                    }
                } finally {
                    currentAudioLevel = 0f
                }
            }

        logger.info("Recording started (sampleRate=${sampleRate.toInt()}, chunkBytes=$chunkBytes)")
    }

    actual fun stopRecording() {
        if (!recordingFlag.compareAndSet(true, false)) {
            // Already stopped (or never started).
            return
        }

        val job = captureJob
        captureJob = null
        val scope = captureScope
        captureScope = null
        val line = targetLine
        targetLine = null

        job?.cancel()

        try {
            line?.stop()
        } catch (t: Throwable) {
            logger.warning("TargetDataLine.stop threw: ${t.message}")
        }
        try {
            line?.flush()
        } catch (t: Throwable) {
            logger.warning("TargetDataLine.flush threw: ${t.message}")
        }
        try {
            line?.close()
        } catch (t: Throwable) {
            logger.warning("TargetDataLine.close threw: ${t.message}")
        }

        scope?.cancel()

        currentAudioLevel = 0f
        logger.info("Recording stopped")
    }

    actual suspend fun activateAudioSession() {
        // No-op on JVM — desktop has no audio focus concept.
    }

    actual suspend fun deactivateAudioSession() {
        // No-op on JVM.
    }

    // ============================================================================
    // Private helpers
    // ============================================================================

    /**
     * Compute a normalized audio level (0.0–1.0) for the given PCM 16-bit
     * little-endian chunk. Matches the Android actual so consumers see the
     * same `audioLevel` semantics across platforms.
     */
    private fun computeNormalizedLevel(pcm16le: ByteArray): Float {
        if (pcm16le.size < 2) return 0f
        val shorts = ByteBuffer.wrap(pcm16le).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val sampleCount = shorts.remaining()
        if (sampleCount == 0) return 0f
        var sumSquares = 0.0
        while (shorts.hasRemaining()) {
            val s = shorts.get().toDouble() / Short.MAX_VALUE.toDouble()
            sumSquares += s * s
        }
        val rms = kotlin.math.sqrt(sumSquares / sampleCount).toFloat()
        if (rms <= 0f) return 0f
        val db = 20f * kotlin.math.log10(rms.toDouble()).toFloat()
        return ((db + 60f) / 60f).coerceIn(0f, 1f)
    }
}
