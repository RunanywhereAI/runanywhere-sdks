/**
 * HybridAudioCapture.kt
 *
 * In-SDK microphone capture for STT features (Android).
 * Port of the Kotlin SDK:
 * sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/features/STT/Services/AudioCaptureManager.kt
 * (AudioRecord 16kHz CHANNEL_IN_MONO PCM16, background read loop).
 * iOS source of truth:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 *
 * Permission handling: `requestPermission()` reports whether RECORD_AUDIO is
 * already granted. The runtime permission prompt is issued from TypeScript via
 * `PermissionsAndroid` because it requires an Activity.
 */

package com.margelo.nitro.runanywhere

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
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.ArrayBuffer
import com.margelo.nitro.core.Promise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.sqrt

class HybridAudioCapture : HybridAudioCaptureSpec() {

    companion object {
        /** Canonical Whisper/Sherpa input format: 16 kHz mono 16-bit PCM. */
        private const val TARGET_SAMPLE_RATE: Int = 16000
        private const val BYTES_PER_SAMPLE: Int = 2
        private const val CHUNK_DURATION_MS: Int = 100
    }

    private val logger = SDKLogger("AudioCapture")

    private val recordingFlag = AtomicBoolean(false)

    @Volatile
    private var audioRecord: AudioRecord? = null

    @Volatile
    private var captureScope: CoroutineScope? = null

    @Volatile
    private var captureJob: Job? = null

    @Volatile
    private var currentAudioLevel: Double = 0.0

    @Volatile
    private var focusRequest: AudioFocusRequest? = null

    @Volatile
    @Suppress("DEPRECATION")
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null

    override val isRecording: Boolean
        get() = recordingFlag.get()

    override val audioLevel: Double
        get() = currentAudioLevel

    /**
     * Permission CHECK only — the actual runtime prompt happens in TS via
     * PermissionsAndroid (it requires an Activity, which this SDK service
     * object does not have).
     */
    override fun requestPermission(): Promise<Boolean> = Promise.async {
        val ctx = NitroModules.applicationContext ?: run {
            logger.warning("Application context not available — cannot check RECORD_AUDIO permission")
            return@async false
        }
        val granted = ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            logger.warning(
                "RECORD_AUDIO permission not granted. Request it from JS via " +
                    "PermissionsAndroid before calling startRecording()."
            )
        }
        granted
    }

    override fun startRecording(onAudioData: (chunk: ArrayBuffer) -> Unit): Promise<Unit> = Promise.async {
        if (recordingFlag.get()) {
            logger.warning("Already recording")
            return@async
        }

        val ctx = NitroModules.applicationContext
            ?: throw IllegalStateException("Application context not available — cannot start audio capture")

        val granted = ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            throw SecurityException("Microphone permission denied")
        }

        // Request audio focus before opening the mic so other media is ducked
        // (Kotlin SDK parity).
        requestAudioFocus(ctx)

        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioEncoding = AudioFormat.ENCODING_PCM_16BIT

        val minBufferBytes =
            AudioRecord.getMinBufferSize(TARGET_SAMPLE_RATE, channelConfig, audioEncoding)
        if (minBufferBytes == AudioRecord.ERROR || minBufferBytes == AudioRecord.ERROR_BAD_VALUE) {
            abandonAudioFocus(ctx)
            throw IllegalStateException(
                "Failed to convert audio format (AudioRecord.getMinBufferSize returned $minBufferBytes)"
            )
        }

        // 100 ms chunk size = 16000 * 2 bytes/sample * 0.1 s = 3200 bytes.
        val chunkBytes = (TARGET_SAMPLE_RATE * BYTES_PER_SAMPLE * CHUNK_DURATION_MS) / 1000
        val recordBufferBytes = maxOf(minBufferBytes, chunkBytes * 2)

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                TARGET_SAMPLE_RATE,
                channelConfig,
                audioEncoding,
                recordBufferBytes
            )
        } catch (t: Throwable) {
            abandonAudioFocus(ctx)
            throw IllegalStateException("Failed to start audio engine: ${t.message}", t)
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            releaseQuietly(record)
            abandonAudioFocus(ctx)
            throw IllegalStateException(
                "No audio input device available (AudioRecord state=${record.state})"
            )
        }

        try {
            record.startRecording()
        } catch (t: Throwable) {
            releaseQuietly(record)
            abandonAudioFocus(ctx)
            throw IllegalStateException("Failed to start audio engine: ${t.message}", t)
        }

        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            stopQuietly(record)
            releaseQuietly(record)
            abandonAudioFocus(ctx)
            throw IllegalStateException(
                "Failed to start audio engine (recordingState=${record.recordingState})"
            )
        }

        audioRecord = record
        recordingFlag.set(true)

        val scope = CoroutineScope(Dispatchers.IO)
        captureScope = scope
        captureJob = scope.launch {
            val buffer = ByteArray(chunkBytes)
            try {
                while (isActive && recordingFlag.get()) {
                    val bytesRead = record.read(buffer, 0, chunkBytes)
                    if (bytesRead > 0) {
                        val chunk = buffer.copyOf(bytesRead)
                        currentAudioLevel = computeNormalizedLevel(chunk)
                        try {
                            onAudioData(ArrayBuffer.copy(chunk))
                        } catch (t: Throwable) {
                            logger.error("onAudioData callback threw: ${t.message}")
                        }
                    } else if (bytesRead < 0) {
                        logger.warning("AudioRecord.read error: $bytesRead — stopping capture")
                        break
                    }
                }
            } finally {
                currentAudioLevel = 0.0
            }
        }

        logger.info("Recording started (sampleRate=$TARGET_SAMPLE_RATE, chunkBytes=$chunkBytes)")
    }

    override fun stopRecording(deactivateSession: Boolean) {
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

        record?.let {
            stopQuietly(it)
            releaseQuietly(it)
        }

        scope?.cancel()

        // Keep audio focus alive between listening segments when the caller
        // asks for it (mirrors iOS deactivateSession semantics).
        if (deactivateSession) {
            NitroModules.applicationContext?.let { abandonAudioFocus(it) }
        }

        currentAudioLevel = 0.0
        logger.info("Recording stopped (deactivateSession=$deactivateSession)")
    }

    /** iOS-only audio-session keepalive — no-op on Android. */
    override fun activateAudioSession(): Promise<Unit> = Promise.async {
        // Audio focus is requested in startRecording().
    }

    /** iOS-only audio-session teardown — no-op on Android. */
    override fun deactivateAudioSession() {
        // Audio focus is abandoned in stopRecording().
    }

    // MARK: - Private helpers

    /**
     * Compute a normalized audio level (0.0–1.0) for the given PCM 16-bit
     * little-endian chunk. RMS->dB mapping identical to commons'
     * `rac_audio_compute_level_db`, normalized -60 dB..0 dB → 0..1
     * (Swift/Kotlin SDK parity).
     */
    private fun computeNormalizedLevel(pcm16le: ByteArray): Double {
        if (pcm16le.size < 2) return 0.0
        val shorts = ByteBuffer.wrap(pcm16le).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val sampleCount = shorts.remaining()
        if (sampleCount == 0) return 0.0
        var sumSquares = 0.0
        while (shorts.hasRemaining()) {
            val s = shorts.get().toDouble() / Short.MAX_VALUE.toDouble()
            sumSquares += s * s
        }
        val rms = sqrt(sumSquares / sampleCount)
        if (rms <= 0.0) return 0.0
        val db = 20.0 * log10(rms)
        // Normalize -60 dB .. 0 dB → 0 .. 1.
        return ((db + 60.0) / 60.0).coerceIn(0.0, 1.0)
    }

    private fun stopQuietly(record: AudioRecord) {
        try {
            record.stop()
        } catch (t: Throwable) {
            logger.warning("AudioRecord.stop threw: ${t.message}")
        }
    }

    private fun releaseQuietly(record: AudioRecord) {
        try {
            record.release()
        } catch (t: Throwable) {
            logger.warning("AudioRecord.release threw: ${t.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun requestAudioFocus(ctx: Context) {
        val manager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) return
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
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
            val result = manager.requestAudioFocus(
                listener,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN
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
