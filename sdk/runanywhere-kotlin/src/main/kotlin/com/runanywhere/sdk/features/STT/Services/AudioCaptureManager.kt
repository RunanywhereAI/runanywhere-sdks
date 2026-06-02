/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android `actual` implementation of [AudioCaptureManager] backed by
 * `android.media.AudioRecord`. Captures PCM 16-bit mono samples at 16 kHz —
 * the canonical Whisper / Sherpa-ONNX input format.
 *
 * iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 *
 * Permission handling:
 *   `requestPermission()` reports whether `RECORD_AUDIO` is already granted.
 *   The consumer app is responsible for showing the runtime permission prompt
 *   (the prompt requires an Activity which is out of scope for this SDK
 *   service object).
 *
 * Audio focus:
 *   `activateAudioSession()` requests AUDIOFOCUS_GAIN with USAGE_VOICE_COMMUNICATION
 *   so this capture cooperates with media playback.
 */

package com.runanywhere.sdk.features.STT.Services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

class AudioCaptureManager {
    private val logger = SDKLogger("AudioCapture")

    private val recordingFlag = AtomicBoolean(false)

    @Volatile
    private var audioRecord: AudioRecord? = null

    @Volatile
    private var captureScope: CoroutineScope? = null

    @Volatile
    private var captureJob: Job? = null

    @Volatile
    private var currentAudioLevel: Float = 0f

    @Volatile
    private var focusRequest: AudioFocusRequest? = null

    @Volatile
    @Suppress("DEPRECATION")
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null

    val isRecording: Boolean
        get() = recordingFlag.get()

    val audioLevel: Float
        get() = currentAudioLevel

    init {
        logger.debug("AudioCaptureManager initialized")
    }

    suspend fun requestPermission(): Boolean {
        val ctx =
            appContextOrNull() ?: run {
                logger.warning("AndroidPlatformContext not initialized — cannot check RECORD_AUDIO permission")
                return false
            }
        val granted =
            ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            logger.warning(
                "RECORD_AUDIO permission not granted. Host app must call " +
                    "ActivityCompat.requestPermissions(...) from an Activity.",
            )
        }
        return granted
    }

    suspend fun startRecording(onAudioData: (ByteArray) -> Unit) {
        if (recordingFlag.get()) {
            logger.warning("Already recording")
            return
        }

        val ctx =
            appContextOrNull()
                ?: throw SDKException.make(
                    code = ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
                    message = "AndroidPlatformContext not initialized — cannot start audio capture",
                    category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                )

        val granted =
            ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_MICROPHONE_PERMISSION_DENIED,
                message = AudioCaptureError.PermissionDenied.description,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
            )
        }

        // Request audio focus before opening the mic so other media is ducked.
        requestAudioFocus(ctx)

        val sampleRate = AudioCaptureConstants.TARGET_SAMPLE_RATE
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioEncoding = AudioFormat.ENCODING_PCM_16BIT

        val minBufferBytes = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioEncoding)
        if (minBufferBytes == AudioRecord.ERROR || minBufferBytes == AudioRecord.ERROR_BAD_VALUE) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
                message =
                    AudioCaptureError.FormatConversionFailed.description +
                        " (AudioRecord.getMinBufferSize returned $minBufferBytes)",
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
            )
        }

        // 100 ms chunk size = 16000 * 2 bytes/sample * 0.1 s = 3200 bytes.
        val chunkBytes =
            (sampleRate * AudioCaptureConstants.BYTES_PER_SAMPLE * AudioCaptureConstants.CHUNK_DURATION_MS) / 1000
        val recordBufferBytes = maxOf(minBufferBytes, chunkBytes * 2)

        val record =
            try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioEncoding,
                    recordBufferBytes,
                )
            } catch (t: Throwable) {
                abandonAudioFocus(ctx)
                throw SDKException.make(
                    code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                    message = AudioCaptureError.EngineStartFailed(t.message).description,
                    category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                    cause = t,
                )
            }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            try {
                record.release()
            } catch (_: Throwable) {
                // ignored
            }
            abandonAudioFocus(ctx)
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message =
                    AudioCaptureError.NoInputDevice.description +
                        " (AudioRecord state=${record.state})",
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
            )
        }

        try {
            record.startRecording()
        } catch (t: Throwable) {
            try {
                record.release()
            } catch (_: Throwable) {
                // ignored
            }
            abandonAudioFocus(ctx)
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message = AudioCaptureError.EngineStartFailed(t.message).description,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                cause = t,
            )
        }

        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            try {
                record.stop()
            } catch (_: Throwable) {
                // ignored
            }
            try {
                record.release()
            } catch (_: Throwable) {
                // ignored
            }
            abandonAudioFocus(ctx)
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                message = AudioCaptureError.EngineStartFailed("recordingState=${record.recordingState}").description,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
            )
        }

        audioRecord = record
        recordingFlag.set(true)

        val scope = CoroutineScope(Dispatchers.IO)
        captureScope = scope
        captureJob =
            scope.launch {
                val buffer = ByteArray(chunkBytes)
                try {
                    while (isActive && recordingFlag.get()) {
                        val bytesRead = record.read(buffer, 0, chunkBytes)
                        if (bytesRead > 0) {
                            val chunk = buffer.copyOf(bytesRead)
                            currentAudioLevel = computeNormalizedLevel(chunk)
                            try {
                                onAudioData(chunk)
                            } catch (t: Throwable) {
                                logger.error("onAudioData callback threw: ${t.message}", throwable = t)
                            }
                        } else if (bytesRead < 0) {
                            logger.warning("AudioRecord.read error: $bytesRead — stopping capture")
                            break
                        }
                    }
                } finally {
                    currentAudioLevel = 0f
                }
            }

        logger.info("Recording started (sampleRate=$sampleRate, chunkBytes=$chunkBytes)")
    }

    fun stopRecording() {
        if (!recordingFlag.compareAndSet(true, false)) {
            // Already stopped (or never started).
            return
        }

        val job = captureJob
        captureJob = null
        val scope = captureScope
        captureScope = null
        val record = audioRecord
        audioRecord = null

        job?.cancel()

        try {
            record?.stop()
        } catch (t: Throwable) {
            logger.warning("AudioRecord.stop threw: ${t.message}")
        }
        try {
            record?.release()
        } catch (t: Throwable) {
            logger.warning("AudioRecord.release threw: ${t.message}")
        }

        scope?.cancel()

        appContextOrNull()?.let { abandonAudioFocus(it) }

        currentAudioLevel = 0f
        logger.info("Recording stopped")
    }

    suspend fun activateAudioSession() {
        val ctx = appContextOrNull() ?: return
        withContext(Dispatchers.IO) {
            requestAudioFocus(ctx)
        }
        logger.debug("Audio session activated (audio focus requested)")
    }

    suspend fun deactivateAudioSession() {
        val ctx = appContextOrNull() ?: return
        withContext(Dispatchers.IO) {
            abandonAudioFocus(ctx)
        }
        logger.debug("Audio session deactivated")
    }

    // Private helpers

    /**
     * Compute a normalized audio level (0.0–1.0) for the given PCM 16-bit
     * little-endian chunk. Uses RMS->dB mapping similar to Swift's
     * `rac_audio_compute_level_db` but in pure Kotlin so this works on hosts
     * without the native commons library.
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
        // Normalize -60 dB .. 0 dB → 0 .. 1.
        return ((db + 60f) / 60f).coerceIn(0f, 1f)
    }

    private fun appContextOrNull(): Context? =
        try {
            AndroidPlatformContext.applicationContext
        } catch (_: IllegalStateException) {
            null
        }

    @Suppress("DEPRECATION")
    private fun requestAudioFocus(ctx: Context) {
        val manager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) return
            val attributes =
                AudioAttributes
                    .Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            val request =
                AudioFocusRequest
                    .Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attributes)
                    .setOnAudioFocusChangeListener { /* no-op */ }
                    .build()
            val result = manager.requestAudioFocus(request)
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                focusRequest = request
            } else {
                logger.warning("requestAudioFocus returned $result")
            }
        } else {
            if (legacyFocusListener != null) return
            val listener = AudioManager.OnAudioFocusChangeListener { /* no-op */ }
            val result =
                manager.requestAudioFocus(
                    listener,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                legacyFocusListener = listener
            } else {
                logger.warning("requestAudioFocus(legacy) returned $result")
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun abandonAudioFocus(ctx: Context) {
        val manager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            legacyFocusListener?.let { manager.abandonAudioFocus(it) }
            legacyFocusListener = null
        }
    }
}

/**
 * Errors raised by [AudioCaptureManager]. Mirrors Swift's `AudioCaptureError`
 * enum. Wrapped in `SDKException` before being thrown.
 */
sealed class AudioCaptureError(
    val description: String,
) {
    data object PermissionDenied : AudioCaptureError("Microphone permission denied")

    data object FormatConversionFailed : AudioCaptureError("Failed to convert audio format")

    data class EngineStartFailed(
        val reason: String? = null,
    ) : AudioCaptureError(
            if (reason != null) "Failed to start audio engine: $reason" else "Failed to start audio engine",
        )

    data object NoInputDevice : AudioCaptureError("No audio input device available")
}

/**
 * Default audio capture parameters: 16 kHz mono 16-bit PCM.
 */
internal object AudioCaptureConstants {
    const val TARGET_SAMPLE_RATE: Int = 16000
    const val CHANNEL_COUNT: Int = 1
    const val BYTES_PER_SAMPLE: Int = 2
    const val CHUNK_DURATION_MS: Int = 100
}
