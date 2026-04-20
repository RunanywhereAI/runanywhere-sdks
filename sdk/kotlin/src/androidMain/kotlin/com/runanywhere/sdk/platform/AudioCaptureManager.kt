// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Android mic capture. Uses AudioRecord to produce Float[] chunks at
// 16 kHz mono, matching Whisper's expected input. Runs the recording
// loop on a dedicated thread and dispatches callbacks to the caller.
//
// Equivalent to sdk/swift/Sources/RunAnywhere/Platform/AudioCaptureManager.swift.

package com.runanywhere.sdk.platform

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class AudioCaptureManager(
    private val sampleRateHz: Int = 16_000,
    private val bufferSizeBytes: Int =
        AudioRecord.getMinBufferSize(
            16_000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT
        ).coerceAtLeast(4096)
) {

    private val recording = AtomicBoolean(false)
    private var recorder: AudioRecord? = null
    private var captureThread: Thread? = null

    val isRecording: Boolean get() = recording.get()

    /// Start recording. `onAudio` fires on the background capture thread
    /// for every buffer; keep the callback non-blocking.
    /// Caller must have RECORD_AUDIO permission granted.
    fun startRecording(onAudio: (FloatArray) -> Unit) {
        if (recording.getAndSet(true)) return
        val rec = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRateHz,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
            bufferSizeBytes
        )
        recorder = rec
        rec.startRecording()

        captureThread = thread(name = "ra-audio-capture", start = true) {
            val buf = FloatArray(bufferSizeBytes / 4)
            while (recording.get() && rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val n = rec.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                if (n > 0) {
                    val chunk = if (n == buf.size) buf.copyOf() else buf.copyOf(n)
                    onAudio(chunk)
                } else if (n < 0) {
                    break
                }
            }
        }
    }

    fun stopRecording() {
        if (!recording.getAndSet(false)) return
        recorder?.apply { stop(); release() }
        recorder = null
        captureThread?.join(1_000)
        captureThread = null
    }
}
