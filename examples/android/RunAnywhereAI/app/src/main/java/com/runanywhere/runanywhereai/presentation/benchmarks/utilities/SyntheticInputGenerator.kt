package com.runanywhere.runanywhereai.presentation.benchmarks.utilities

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

/**
 * Generates deterministic synthetic inputs for benchmarking.
 * Matches iOS SyntheticInputGenerator exactly.
 */
object SyntheticInputGenerator {

    // -- Audio --

    /** Generate silent PCM Int16 mono audio data. */
    fun silentAudio(durationSeconds: Double, sampleRate: Int = 16_000): ByteArray {
        val sampleCount = (durationSeconds * sampleRate).toInt()
        return ByteArray(sampleCount * Short.SIZE_BYTES)
    }

    /** Generate a sine wave PCM Int16 mono audio buffer. */
    fun sineWaveAudio(
        durationSeconds: Double,
        frequencyHz: Double = 440.0,
        sampleRate: Int = 16_000,
    ): ByteArray {
        val sampleCount = (durationSeconds * sampleRate).toInt()
        val buffer = ByteBuffer.allocate(sampleCount * Short.SIZE_BYTES)
            .order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until sampleCount) {
            val t = i.toDouble() / sampleRate
            val value = sin(2.0 * PI * frequencyHz * t) * (Short.MAX_VALUE / 2)
            buffer.putShort(value.toInt().toShort())
        }
        return buffer.array()
    }

    // -- Images (raw RGB pixel data for VLMImage.fromRGBPixels) --

    /**
     * Generate a solid-color RGB pixel buffer.
     * Returns a ByteArray of (width * height * 3) bytes in RGB format.
     */
    fun solidColorRgb(
        width: Int = 224,
        height: Int = 224,
        r: Byte = 0xFF.toByte(),
        g: Byte = 0x00,
        b: Byte = 0x00,
    ): ByteArray {
        val size = width * height * 3
        val data = ByteArray(size)
        for (i in 0 until width * height) {
            data[i * 3] = r
            data[i * 3 + 1] = g
            data[i * 3 + 2] = b
        }
        return data
    }

    /**
     * Generate a gradient RGB pixel buffer (top-left blue to bottom-right green).
     * Returns a ByteArray of (width * height * 3) bytes in RGB format.
     */
    fun gradientRgb(width: Int = 224, height: Int = 224): ByteArray {
        val data = ByteArray(width * height * 3)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val t = ((x.toFloat() / width) + (y.toFloat() / height)) / 2f
                val idx = (y * width + x) * 3
                data[idx] = 0 // R
                data[idx + 1] = (t * 255).toInt().toByte() // G (blue->green)
                data[idx + 2] = ((1f - t) * 255).toInt().toByte() // B
            }
        }
        return data
    }

    // -- Memory --

    /** Returns available memory in bytes via Runtime. */
    fun availableMemoryBytes(): Long {
        val runtime = Runtime.getRuntime()
        return runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())
    }
}
