package com.runanywhere.runanywhereai.ui.screens.stt

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.log10
import kotlin.math.sqrt

class AudioRecorder {

    @Volatile
    private var recording = false
    private var record: AudioRecord? = null
    private var worker: Thread? = null

    @SuppressLint("MissingPermission")
    fun start(onChunk: (ByteArray, Float) -> Unit) {
        if (recording) return
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL,
            ENCODING,
            maxOf(minBuffer, CHUNK_BYTES * 2),
        )
        record = rec
        recording = true
        rec.startRecording()
        worker = Thread {
            val buffer = ByteArray(CHUNK_BYTES)
            while (recording) {
                val read = rec.read(buffer, 0, buffer.size)
                if (read > 0) onChunk(buffer.copyOf(read), level(buffer, read))
            }
        }.also { it.start() }
    }

    fun stop() {
        if (!recording) return
        recording = false
        worker?.join(250)
        worker = null
        record?.run {
            runCatching { stop() }
            release()
        }
        record = null
    }

    private fun level(bytes: ByteArray, length: Int): Float {
        val samples = length / 2
        if (samples == 0) return 0f
        var sum = 0.0
        for (i in 0 until samples) {
            val lo = bytes[2 * i].toInt() and 0xff
            val hi = bytes[2 * i + 1].toInt()
            val sample = (hi shl 8) or lo
            sum += sample.toDouble() * sample
        }
        val rms = sqrt(sum / samples)
        val db = 20 * log10((rms / 32768.0).coerceAtLeast(1e-6))
        return (((db + 60) / 60).coerceIn(0.0, 1.0)).toFloat()
    }

    companion object {
        const val SAMPLE_RATE = 16000
        private const val CHUNK_BYTES = 3200
        private val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }
}
