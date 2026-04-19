package com.runanywhere.sdk.core

/**
 * Audio conversion utilities shared across all modules.
 *
 * Provides common audio format conversions needed for STT and TTS operations:
 * - PCM byte arrays ↔ Float sample arrays
 * - Float samples → WAV format
 *
 * These utilities are format-agnostic and can be used by any backend
 * (ONNX, LlamaCpp, WhisperKit, etc.)
 */
object AudioUtils {
    // =========================================================================
    // MARK: - PCM ↔ Float Conversion
    // =========================================================================

    /**
     * Convert raw 16-bit PCM audio bytes to normalized float samples.
     *
     * Input format: Little-endian 16-bit signed PCM (standard Android/iOS format)
     * Output range: -1.0f to 1.0f
     *
     * @param audioData Raw PCM byte array (2 bytes per sample)
     * @return Float array with normalized samples
     */
    fun pcmBytesToFloatSamples(audioData: ByteArray): FloatArray {
        val samples = FloatArray(audioData.size / 2)
        for (i in samples.indices) {
            val low = audioData[i * 2].toInt() and 0xFF
            val high = audioData[i * 2 + 1].toInt()
            val sample = (high shl 8) or low
            samples[i] = sample / 32768.0f
        }
        return samples
    }

    /**
     * Convert normalized float samples to 16-bit PCM bytes.
     *
     * Input range: -1.0f to 1.0f
     * Output format: Little-endian 16-bit signed PCM
     *
     * @param samples Float array with normalized samples
     * @return Raw PCM byte array
     */
    fun floatSamplesToPcmBytes(samples: FloatArray): ByteArray {
        val buffer = ByteArray(samples.size * 2)
        for (i in samples.indices) {
            val intSample = (samples[i] * 32767).toInt().coerceIn(-32768, 32767)
            buffer[i * 2] = (intSample and 0xFF).toByte()
            buffer[i * 2 + 1] = ((intSample shr 8) and 0xFF).toByte()
        }
        return buffer
    }

    // =========================================================================
    // MARK: - WAV Format Conversion
    // =========================================================================

    /**
     * Convert float samples to WAV format with standard header.
     *
     * Creates a complete WAV file with:
     * - RIFF header
     * - fmt chunk (PCM format, mono, 16-bit)
     * - data chunk with samples
     *
     * @param samples Float array with normalized samples (-1.0 to 1.0)
     * @param sampleRate Sample rate in Hz (e.g., 16000, 22050, 44100)
     * @return Complete WAV file as byte array
     */
    fun floatSamplesToWav(
        samples: FloatArray,
        sampleRate: Int,
    ): ByteArray {
        val numSamples = samples.size
        val bitsPerSample = 16
        val numChannels = 1
        val byteRate = sampleRate * numChannels * bitsPerSample / 8
        val blockAlign = numChannels * bitsPerSample / 8
        val dataSize = numSamples * blockAlign
        val fileSize = 36 + dataSize

        val buffer = ByteArray(44 + dataSize)
        var offset = 0

        // RIFF header
        writeString(buffer, offset, "RIFF")
        offset += 4
        writeInt32LE(buffer, offset, fileSize)
        offset += 4
        writeString(buffer, offset, "WAVE")
        offset += 4

        // fmt chunk
        writeString(buffer, offset, "fmt ")
        offset += 4
        writeInt32LE(buffer, offset, 16) // Subchunk1Size (16 for PCM)
        offset += 4
        writeInt16LE(buffer, offset, 1) // AudioFormat (1 = PCM)
        offset += 2
        writeInt16LE(buffer, offset, numChannels)
        offset += 2
        writeInt32LE(buffer, offset, sampleRate)
        offset += 4
        writeInt32LE(buffer, offset, byteRate)
        offset += 4
        writeInt16LE(buffer, offset, blockAlign)
        offset += 2
        writeInt16LE(buffer, offset, bitsPerSample)
        offset += 2

        // data chunk
        writeString(buffer, offset, "data")
        offset += 4
        writeInt32LE(buffer, offset, dataSize)
        offset += 4

        // Write samples
        for (sample in samples) {
            val intSample = (sample * 32767).toInt().coerceIn(-32768, 32767)
            writeInt16LE(buffer, offset, intSample)
            offset += 2
        }

        return buffer
    }

    /**
     * Extract float samples from a WAV byte array.
     *
     * Parses the WAV header and extracts PCM samples.
     * Supports 16-bit mono PCM WAV files.
     *
     * @param wavData Complete WAV file as byte array
     * @return Pair of (samples, sampleRate) or null if invalid
     */
    fun wavToFloatSamples(wavData: ByteArray): Pair<FloatArray, Int>? {
        if (wavData.size < 44) return null

        // Verify RIFF header
        val riff = String(wavData.sliceArray(0..3))
        if (riff != "RIFF") return null

        val wave = String(wavData.sliceArray(8..11))
        if (wave != "WAVE") return null

        // Read sample rate from fmt chunk (offset 24)
        val sampleRate = readInt32LE(wavData, 24)

        // Find data chunk
        var dataOffset = 12
        while (dataOffset < wavData.size - 8) {
            val chunkId = String(wavData.sliceArray(dataOffset until dataOffset + 4))
            val chunkSize = readInt32LE(wavData, dataOffset + 4)

            if (chunkId == "data") {
                dataOffset += 8
                val numSamples = chunkSize / 2
                val samples = FloatArray(numSamples)

                for (i in 0 until numSamples) {
                    val byteOffset = dataOffset + i * 2
                    if (byteOffset + 1 < wavData.size) {
                        val low = wavData[byteOffset].toInt() and 0xFF
                        val high = wavData[byteOffset + 1].toInt()
                        val sample = (high shl 8) or low
                        samples[i] = sample / 32768.0f
                    }
                }

                return Pair(samples, sampleRate)
            }

            dataOffset += 8 + chunkSize
        }

        return null
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================

    private fun writeString(
        buffer: ByteArray,
        offset: Int,
        value: String,
    ) {
        value.toByteArray().copyInto(buffer, offset)
    }

    private fun writeInt16LE(
        buffer: ByteArray,
        offset: Int,
        value: Int,
    ) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
    }

    private fun writeInt32LE(
        buffer: ByteArray,
        offset: Int,
        value: Int,
    ) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
        buffer[offset + 2] = ((value shr 16) and 0xFF).toByte()
        buffer[offset + 3] = ((value shr 24) and 0xFF).toByte()
    }

    private fun readInt32LE(
        buffer: ByteArray,
        offset: Int,
    ): Int {
        return (buffer[offset].toInt() and 0xFF) or
            ((buffer[offset + 1].toInt() and 0xFF) shl 8) or
            ((buffer[offset + 2].toInt() and 0xFF) shl 16) or
            ((buffer[offset + 3].toInt() and 0xFF) shl 24)
    }
}
