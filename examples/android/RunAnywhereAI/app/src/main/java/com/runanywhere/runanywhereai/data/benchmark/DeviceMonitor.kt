package com.runanywhere.runanywhereai.data.benchmark

import android.content.Context
import android.os.Environment
import android.os.StatFs
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.RandomAccessFile

data class MemorySample(val usedBytes: Long, val totalBytes: Long) {
    val fraction: Float get() = if (totalBytes > 0) usedBytes.toFloat() / totalBytes else 0f
}

data class StorageInfo(val usedBytes: Long, val totalBytes: Long) {
    val freeBytes: Long get() = totalBytes - usedBytes
    val fraction: Float get() = if (totalBytes > 0) usedBytes.toFloat() / totalBytes else 0f
}

data class DiskSpeed(val writeMbps: Double, val readMbps: Double)

// Best-effort, no-root device telemetry. CPU is the app's own usage (system-wide
// /proc/stat is blocked since Android 8); frequency + storage come from sysfs/StatFs.
object DeviceMonitor {

    fun memory(context: Context): MemorySample {
        val mi = SyntheticInput.memoryInfo(context)
        return MemorySample(usedBytes = mi.totalMem - mi.availMem, totalBytes = mi.totalMem)
    }

    fun storage(): StorageInfo {
        val stat = StatFs(Environment.getDataDirectory().path)
        return StorageInfo(usedBytes = stat.totalBytes - stat.availableBytes, totalBytes = stat.totalBytes)
    }

    fun coreCount(): Int = Runtime.getRuntime().availableProcessors()

    // Highest current core frequency in MHz, or null when sysfs isn't readable.
    fun currentFreqMhz(): Int? = runCatching {
        (0 until coreCount()).mapNotNull { core ->
            File("/sys/devices/system/cpu/cpu$core/cpufreq/scaling_cur_freq")
                .takeIf { it.canRead() }?.readText()?.trim()?.toLongOrNull()
        }.maxOrNull()?.let { (it / 1000).toInt() }
    }.getOrNull()

    // Sequential write then read of a temp file; returns MB/s. Blocking — call off the main thread.
    fun measureDiskSpeed(context: Context, sizeMb: Int = 16): DiskSpeed {
        val total = sizeMb * 1024 * 1024
        val chunk = ByteArray(1024 * 1024) { (it and 0xFF).toByte() }
        val file = File.createTempFile("iobench_", ".bin", context.cacheDir)
        try {
            val writeNs = measureNanos {
                RandomAccessFile(file, "rw").use { raf ->
                    var written = 0
                    while (written < total) {
                        raf.write(chunk)
                        written += chunk.size
                    }
                    raf.fd.sync()
                }
            }
            val readNs = measureNanos {
                RandomAccessFile(file, "r").use { raf ->
                    val buf = ByteArray(1024 * 1024)
                    while (raf.read(buf) > 0) { /* drain */ }
                }
            }
            val mb = total / (1024.0 * 1024.0)
            return DiskSpeed(
                writeMbps = if (writeNs > 0) mb / (writeNs / 1e9) else 0.0,
                readMbps = if (readNs > 0) mb / (readNs / 1e9) else 0.0,
            )
        } finally {
            file.delete()
        }
    }

    private inline fun measureNanos(block: () -> Unit): Long {
        val start = System.nanoTime()
        block()
        return System.nanoTime() - start
    }
}

// Stateful sampler: app CPU usage as a percentage of total device CPU capacity (0..100),
// computed from /proc/self/stat deltas between calls.
class CpuSampler {
    private val clkTck = runCatching { Os.sysconf(OsConstants._SC_CLK_TCK) }.getOrDefault(100L)
    private val cores = Runtime.getRuntime().availableProcessors()
    private var lastProcTicks = 0L
    private var lastWallNs = 0L

    fun sample(): Float {
        val proc = readSelfTicks() ?: return 0f
        val nowNs = System.nanoTime()
        if (lastWallNs == 0L) {
            lastProcTicks = proc
            lastWallNs = nowNs
            return 0f
        }
        val procSec = (proc - lastProcTicks).toDouble() / clkTck
        val wallSec = (nowNs - lastWallNs) / 1e9
        lastProcTicks = proc
        lastWallNs = nowNs
        if (wallSec <= 0.0) return 0f
        return ((procSec / (wallSec * cores)) * 100.0).toFloat().coerceIn(0f, 100f)
    }

    private fun readSelfTicks(): Long? = runCatching {
        val stat = File("/proc/self/stat").readText()
        val fields = stat.substring(stat.lastIndexOf(')') + 1).trim().split(Regex("\\s+"))
        fields[11].toLong() + fields[12].toLong() // utime + stime
    }.getOrNull()
}
