package com.runanywhere.runanywhereai.data.benchmark

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import kotlin.math.PI
import kotlin.math.sin

// Deterministic, reproducible inputs for benchmarking STT and VLM so runs are
// comparable across devices and sessions.
object SyntheticInput {

    private const val SAMPLE_RATE = 16000

    fun availableMemoryBytes(context: Context): Long = memoryInfo(context).availMem

    fun memoryInfo(context: Context): ActivityManager.MemoryInfo {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
    }

    // PCM 16-bit mono @ 16 kHz, all zeros.
    fun silentPcm(durationSeconds: Double): ByteArray = ByteArray((SAMPLE_RATE * durationSeconds).toInt() * 2)

    // PCM 16-bit mono @ 16 kHz, 440 Hz sine.
    fun sinePcm(durationSeconds: Double, frequency: Double = 440.0): ByteArray {
        val samples = (SAMPLE_RATE * durationSeconds).toInt()
        val out = ByteArray(samples * 2)
        for (i in 0 until samples) {
            val v = (sin(2.0 * PI * frequency * i / SAMPLE_RATE) * Short.MAX_VALUE * 0.6).toInt().toShort()
            out[i * 2] = (v.toInt() and 0xFF).toByte()
            out[i * 2 + 1] = ((v.toInt() shr 8) and 0xFF).toByte()
        }
        return out
    }

    fun solidImage(size: Int = 224): Bitmap =
        Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }

    fun gradientImage(size: Int = 224): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (y in 0 until size) {
            for (x in 0 until size) {
                val b = (255 * (size - x) / size)
                val g = (255 * y / size)
                bmp.setPixel(x, y, Color.rgb(0, g, b))
            }
        }
        return bmp
    }
}
