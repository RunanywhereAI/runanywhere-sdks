// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Android PCM playback queue. Uses AudioTrack in streaming mode with
// MODE_STREAM so successive play() calls enqueue naturally.
//
// Equivalent to sdk/swift/Sources/RunAnywhere/Platform/AudioPlaybackManager.swift.

package com.runanywhere.sdk.platform

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import java.util.concurrent.atomic.AtomicBoolean

class AudioPlaybackManager {

    private val playing = AtomicBoolean(false)
    private var track: AudioTrack? = null
    private var currentSampleRate = 0

    val isPlaying: Boolean get() = playing.get()

    /// Enqueue PCM samples for playback. Sample rate can vary between
    /// calls — the track is rebuilt when it changes.
    fun play(pcm: FloatArray, sampleRateHz: Int) {
        ensureTrack(sampleRateHz)
        val t = track ?: return
        t.play()
        t.write(pcm, 0, pcm.size, AudioTrack.WRITE_BLOCKING)
        playing.set(true)
    }

    /// Stop playback and release the AudioTrack.
    fun stop() {
        if (!playing.getAndSet(false)) return
        track?.apply { stop(); release() }
        track = null
        currentSampleRate = 0
    }

    /// Immediately mute and stop after `durationMs`.
    fun fadeOutAndStop(durationMs: Long = 200) {
        track?.setVolume(0f)
        Thread.sleep(durationMs)
        stop()
    }

    // MARK: - Internals

    private fun ensureTrack(sampleRateHz: Int) {
        if (track != null && currentSampleRate == sampleRateHz) return
        track?.apply { stop(); release() }

        val bufSize = AudioTrack.getMinBufferSize(
            sampleRateHz,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_FLOAT
        ).coerceAtLeast(4096)

        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(sampleRateHz)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        currentSampleRate = sampleRateHz
    }
}
