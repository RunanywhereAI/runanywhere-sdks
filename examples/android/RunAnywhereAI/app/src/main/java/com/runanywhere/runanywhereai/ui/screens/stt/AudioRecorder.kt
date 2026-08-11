package com.runanywhere.runanywhereai.ui.screens.stt

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import com.runanywhere.sdk.features.STT.Services.AudioCaptureManager

class AudioRecorder {

    @Volatile
    private var recording = false

    // record is cleared by the worker (after release()) as well as by start/stop,
    // so it is volatile for cross-thread visibility.
    @Volatile
    private var record: AudioRecord? = null
    private var worker: Thread? = null

    @SuppressLint("MissingPermission")
    fun start(onChunk: (ByteArray, Float) -> Unit, onError: (Throwable) -> Unit = {}) {
        if (recording) return
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL,
            ENCODING,
            maxOf(minBuffer, CHUNK_BYTES * 2),
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("Microphone failed to initialize")
        }
        try {
            rec.startRecording()
        } catch (t: Throwable) {
            rec.release()
            throw t
        }
        record = rec
        recording = true
        val thread = Thread {
            val buffer = ByteArray(CHUNK_BYTES)
            var failure: Throwable? = null
            while (recording) {
                val read = rec.read(buffer, 0, buffer.size)
                if (read > 0) {
                    // Level comes from the SDK helper (same formula as capture
                    // manager / commons rac_audio_compute_level_normalized).
                    onChunk(
                        buffer.copyOf(read),
                        AudioCaptureManager.normalizedLevelFromPcm16Le(buffer, read),
                    )
                } else {
                    // Any non-positive read is terminal: a graceful stop() (which
                    // flips recording=false and calls rec.stop() to unblock this
                    // read) leaves recording already false, but ERROR_DEAD_OBJECT
                    // (-6) / ERROR_INVALID_OPERATION (-3) while still recording
                    // would otherwise hot-spin forever. Break out and, if it was
                    // an unexpected fault, surface it so callers clear state.
                    if (recording) failure = IllegalStateException("Microphone read failed ($read)")
                    break
                }
            }
            // The worker owns release() so it never runs while read() could still
            // be in-flight. stop() unblocks read() and joins before it would touch
            // rec. Drop our own handles first (unless a restart already replaced
            // them) so a reentrant stop() from onError finds nothing to double-free.
            rec.release()
            if (record === rec) record = null
            failure?.let { onError(it) }
        }
        worker = thread
        thread.start()
    }

    fun stop() {
        recording = false
        // Stop AudioRecord first so a blocking read wakes before we join the
        // worker. Joining before stop could leave the retained screen's mic
        // thread alive while another speech surface opened the device.
        record?.let { runCatching { it.stop() } }
        // Join (bounded) so we never let cleanup race the worker's own release()
        // — freeing the AudioRecord while a blocking read() could still touch it
        // is a native use-after-free. release() lives in the worker, so a join
        // timeout simply leaves the mic thread to finish and free itself: we skip
        // cleanup and leak rather than crash. Never join our own thread (a
        // worker-thread onError may call stop()); it will unwind on its own.
        val w = worker
        if (w != null && w !== Thread.currentThread()) {
            w.join(JOIN_TIMEOUT_MS)
            if (!w.isAlive) worker = null
        }
    }

    companion object {
        const val SAMPLE_RATE = 16000
        private const val CHUNK_BYTES = 3200

        /**
         * Milliseconds of audio in one `onChunk` callback, derived from
         * [CHUNK_BYTES] so callers sizing a buffer in seconds cannot drift from
         * the size this recorder actually emits.
         */
        const val CHUNK_MS = CHUNK_BYTES * 1000 / (SAMPLE_RATE * 2)

        private const val JOIN_TIMEOUT_MS = 5000L
        private val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }
}
