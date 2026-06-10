/**
 * HybridAudioPlayback.kt
 *
 * In-SDK audio playback for TTS features (Android).
 * Port of the Kotlin SDK:
 * sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/features/TTS/Services/AudioPlaybackManager.kt
 * (AudioTrack MODE_STATIC, WAV header parsing, marker-listener completion),
 * plus pause()/resume() and audio-focus handling for parity with the iOS
 * Swift source of truth:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift
 * (pause/resume :113-124, interruption pause/auto-resume :239-254).
 */

package com.margelo.nitro.runanywhere

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.ArrayBuffer
import com.margelo.nitro.core.Promise
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class HybridAudioPlayback : HybridAudioPlaybackSpec() {

    private val logger = SDKLogger("AudioPlayback")
    private val playbackIdGenerator = AtomicInteger(0)

    @Volatile
    private var audioTrack: AudioTrack? = null

    @Volatile
    private var trackSampleRate: Int = 0

    @Volatile
    private var trackTotalFrames: Int = 0

    @Volatile
    private var interruptPlayback: (() -> Unit)? = null

    @Volatile
    private var focusRequest: AudioFocusRequest? = null

    @Volatile
    @Suppress("DEPRECATION")
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null

    /**
     * Audio-focus reactions — Swift interruption-delegate parity
     * (pause on interruption begin, auto-resume on `.shouldResume`).
     */
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                logger.info("Audio focus lost — pausing playback")
                pause()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                logger.info("Audio focus regained — resuming playback")
                resume()
            }
            else -> Unit
        }
    }

    override val isPlaying: Boolean
        get() = audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING

    override val currentTime: Double
        get() {
            val track = audioTrack ?: return 0.0
            val rate = trackSampleRate
            if (rate <= 0) return 0.0
            return try {
                track.playbackHeadPosition.toDouble() / rate.toDouble()
            } catch (_: Throwable) {
                0.0
            }
        }

    override val duration: Double
        get() {
            val rate = trackSampleRate
            if (rate <= 0) return 0.0
            return trackTotalFrames.toDouble() / rate.toDouble()
        }

    // MARK: - Public API

    override fun play(wavData: ArrayBuffer): Promise<Unit> {
        // Copy synchronously — the JS-owned buffer is only valid during this call.
        val bytes = wavData.toByteArray()
        return Promise.async { playWavBytes(bytes) }
    }

    override fun playFile(path: String): Promise<Unit> = Promise.async {
        val file = File(path)
        if (!file.exists()) {
            throw AudioPlaybackException.PlaybackFailed("Audio file not found: $path")
        }
        playWavBytes(file.readBytes())
    }

    /** Stop current playback — an in-flight play() rejects with PlaybackInterrupted. */
    override fun stop() {
        logger.debug("stop() called: isPlaying=$isPlaying, hasTrack=${audioTrack != null}")
        interruptPlayback?.invoke()
    }

    /** Pause current playback (AudioTrack.pause() — Swift pause() parity). */
    override fun pause() {
        val track = audioTrack ?: return
        try {
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                track.pause()
                logger.info("Playback paused")
            }
        } catch (t: Throwable) {
            logger.warning("AudioTrack.pause threw: ${t.message}")
        }
    }

    /** Resume paused playback (AudioTrack.play() — Swift resume() parity). */
    override fun resume() {
        val track = audioTrack ?: return
        try {
            if (track.playState == AudioTrack.PLAYSTATE_PAUSED) {
                track.play()
                logger.info("Playback resumed")
            }
        } catch (t: Throwable) {
            logger.warning("AudioTrack.resume threw: ${t.message}")
        }
    }

    // MARK: - Private Implementation

    private suspend fun playWavBytes(audioData: ByteArray) {
        if (audioData.isEmpty()) {
            throw AudioPlaybackException.EmptyAudioData
        }

        val playbackId = playbackIdGenerator.incrementAndGet()
        logger.debug("[playbackId=$playbackId] play() start: totalBytes=${audioData.size}")

        try {
            val wavInfo = parseWavHeader(audioData)
            logger.info(
                "[playbackId=$playbackId] Playing audio: ${audioData.size} bytes, " +
                    "${wavInfo.sampleRate}Hz, ${wavInfo.channels}ch, ${wavInfo.bitsPerSample}bit"
            )

            val pcmData = audioData.copyOfRange(wavInfo.dataOffset, audioData.size)

            playPcmData(playbackId, pcmData, wavInfo.sampleRate, wavInfo.channels, wavInfo.bitsPerSample)

            logger.info("[playbackId=$playbackId] play() completed")
        } catch (e: Exception) {
            logger.error("[playbackId=$playbackId] play() failed: ${e.message}")
            throw if (e is AudioPlaybackException) e else AudioPlaybackException.PlaybackFailed(e.message)
        }
    }

    private suspend fun playPcmData(
        playbackId: Int,
        pcmData: ByteArray,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
    ) = suspendCancellableCoroutine { continuation ->
        val resumed = AtomicBoolean(false)

        fun cleanup(track: AudioTrack?) {
            try {
                track?.stop()
            } catch (_: Exception) {
            }
            try {
                track?.release()
            } catch (_: Exception) {
            }
            if (audioTrack === track) {
                audioTrack = null
                trackSampleRate = 0
                trackTotalFrames = 0
            }
            interruptPlayback = null
            NitroModules.applicationContext?.let { abandonAudioFocus(it) }
        }

        fun succeed(track: AudioTrack?) {
            val casWon = resumed.compareAndSet(false, true)
            logger.debug("[playbackId=$playbackId] completion path=success casWon=$casWon")
            if (casWon) {
                cleanup(track)
                continuation.resume(Unit)
            }
        }

        fun fail(track: AudioTrack?, throwable: Throwable) {
            val casWon = resumed.compareAndSet(false, true)
            logger.debug("[playbackId=$playbackId] completion path=${throwable::class.simpleName} casWon=$casWon")
            if (casWon) {
                cleanup(track)
                continuation.resumeWithException(throwable)
            }
        }

        try {
            logger.debug(
                "[playbackId=$playbackId] playPcmData() enter: pcmBytes=${pcmData.size}, " +
                    "sampleRate=$sampleRate, channels=$channels, bitsPerSample=$bitsPerSample"
            )

            // Stop any existing playback first (Swift startPlayback parity).
            interruptPlayback?.invoke()

            val channelConfig =
                if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO

            val audioFormat = when (bitsPerSample) {
                8 -> AudioFormat.ENCODING_PCM_8BIT
                16 -> AudioFormat.ENCODING_PCM_16BIT
                else -> {
                    logger.debug("[playbackId=$playbackId] completion path=unsupported_bit_depth bitsPerSample=$bitsPerSample")
                    continuation.resumeWithException(AudioPlaybackException.InvalidAudioFormat)
                    return@suspendCancellableCoroutine
                }
            }

            val minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)

            if (minBufferSize == AudioTrack.ERROR || minBufferSize == AudioTrack.ERROR_BAD_VALUE) {
                logger.warning("[playbackId=$playbackId] Invalid minBufferSize=$minBufferSize")
                continuation.resumeWithException(AudioPlaybackException.InvalidAudioFormat)
                return@suspendCancellableCoroutine
            }

            val bufferSize = maxOf(minBufferSize, pcmData.size)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(audioFormat)
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelConfig)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            interruptPlayback = { fail(track, AudioPlaybackException.PlaybackInterrupted) }
            audioTrack = track
            trackSampleRate = sampleRate

            val bytesWritten = track.write(pcmData, 0, pcmData.size)
            if (bytesWritten < 0) {
                logger.debug("[playbackId=$playbackId] completion path=write_error bytesWritten=$bytesWritten")
                fail(track, AudioPlaybackException.PlaybackFailed("Write failed: $bytesWritten"))
                return@suspendCancellableCoroutine
            }

            val bytesPerSample = bitsPerSample / 8
            val frameSize = bytesPerSample * channels
            if (frameSize <= 0 || bytesWritten % frameSize != 0) {
                logger.debug("[playbackId=$playbackId] completion path=invalid_frame frameSize=$frameSize bytesWritten=$bytesWritten")
                fail(track, AudioPlaybackException.InvalidAudioFormat)
                return@suspendCancellableCoroutine
            }

            trackTotalFrames = bytesWritten / frameSize
            track.notificationMarkerPosition = bytesWritten / frameSize
            track.setPlaybackPositionUpdateListener(
                object : AudioTrack.OnPlaybackPositionUpdateListener {
                    override fun onMarkerReached(track: AudioTrack?) {
                        succeed(track)
                    }

                    override fun onPeriodicNotification(track: AudioTrack?) {
                    }
                }
            )

            continuation.invokeOnCancellation {
                fail(track, AudioPlaybackException.PlaybackInterrupted)
            }

            // Request audio focus so other media ducks/pauses (Swift
            // .playback + .duckOthers session parity).
            NitroModules.applicationContext?.let { requestAudioFocus(it) }

            logger.debug("[playbackId=$playbackId] track.play()")
            track.play()
        } catch (e: Exception) {
            fail(audioTrack, e)
        }
    }

    private fun parseWavHeader(data: ByteArray): WavInfo {
        if (data.size < 44) throw AudioPlaybackException.InvalidAudioFormat

        val riff = String(data.copyOfRange(0, 4))
        if (riff != "RIFF") throw AudioPlaybackException.InvalidAudioFormat

        val wave = String(data.copyOfRange(8, 12))
        if (wave != "WAVE") throw AudioPlaybackException.InvalidAudioFormat

        val channels = (data[22].toInt() and 0xFF) or ((data[23].toInt() and 0xFF) shl 8)
        val sampleRate =
            (data[24].toInt() and 0xFF) or
                ((data[25].toInt() and 0xFF) shl 8) or
                ((data[26].toInt() and 0xFF) shl 16) or
                ((data[27].toInt() and 0xFF) shl 24)
        val bitsPerSample = (data[34].toInt() and 0xFF) or ((data[35].toInt() and 0xFF) shl 8)

        if (channels !in 1..2) throw AudioPlaybackException.InvalidAudioFormat
        if (sampleRate <= 0) throw AudioPlaybackException.InvalidAudioFormat
        if (bitsPerSample !in setOf(8, 16)) throw AudioPlaybackException.InvalidAudioFormat

        var dataOffset = 12
        while (dataOffset < data.size - 8) {
            val chunkId = String(data.copyOfRange(dataOffset, dataOffset + 4))
            val chunkSize =
                (data[dataOffset + 4].toInt() and 0xFF) or
                    ((data[dataOffset + 5].toInt() and 0xFF) shl 8) or
                    ((data[dataOffset + 6].toInt() and 0xFF) shl 16) or
                    ((data[dataOffset + 7].toInt() and 0xFF) shl 24)

            if (chunkId == "data") {
                dataOffset += 8
                break
            }

            if (chunkSize < 0) throw AudioPlaybackException.InvalidAudioFormat
            val paddedChunkSize = chunkSize + (chunkSize and 1)
            val nextOffset = dataOffset.toLong() + 8L + paddedChunkSize.toLong()
            if (nextOffset <= dataOffset.toLong() || nextOffset > data.size.toLong()) {
                throw AudioPlaybackException.InvalidAudioFormat
            }
            dataOffset = nextOffset.toInt()
        }

        if (dataOffset >= data.size) throw AudioPlaybackException.InvalidAudioFormat

        return WavInfo(
            sampleRate = sampleRate,
            channels = channels,
            bitsPerSample = bitsPerSample,
            dataOffset = dataOffset,
        )
    }

    private data class WavInfo(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val dataOffset: Int,
    )

    // MARK: - Audio focus

    @Suppress("DEPRECATION")
    private fun requestAudioFocus(ctx: Context) {
        val manager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) return
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()
            val result = manager.requestAudioFocus(request)
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                focusRequest = request
            } else {
                logger.warning("requestAudioFocus returned $result")
            }
        } else {
            if (legacyFocusListener != null) return
            val result = manager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                legacyFocusListener = focusChangeListener
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
 * Audio playback errors. Mirrors the Kotlin SDK's `AudioPlaybackException`
 * (itself mirroring Swift's `AudioPlaybackError`).
 */
sealed class AudioPlaybackException : Exception() {
    data object EmptyAudioData : AudioPlaybackException() {
        @Suppress("UnusedPrivateMember")
        private fun readResolve(): Any = EmptyAudioData

        override val message: String = "Audio data is empty"
    }

    data class PlaybackFailed(
        override val message: String?,
    ) : AudioPlaybackException()

    data object PlaybackInterrupted : AudioPlaybackException() {
        @Suppress("UnusedPrivateMember")
        private fun readResolve(): Any = PlaybackInterrupted

        override val message: String = "Audio playback was interrupted"
    }

    data object InvalidAudioFormat : AudioPlaybackException() {
        @Suppress("UnusedPrivateMember")
        private fun readResolve(): Any = InvalidAudioFormat

        override val message: String = "Invalid audio format"
    }
}
