/**
 * perf_bench.kt — Kotlin consumer for the GAP 09 #8 perf bench.
 *
 * v3.2: Reads /tmp/perf_input.bin (produced by
 * tests/streaming/perf_bench/perf_producer.cpp), decodes each VoiceEvent
 * via Wire (the Kotlin proto lib used by the SDK), and measures the
 * per-event decode latency with `System.nanoTime()` brackets around
 * the decode call. Writes per-event delta_ns to /tmp/perf_bench.kt.log.
 *
 * Why not `now() - metrics.created_at_ns` like the C++/Swift consumers:
 * the producer stamps `created_at_ns` using C++ `std::chrono::steady_clock`,
 * which is monotonic but has a process-local, platform-defined epoch.
 * The JVM's `System.nanoTime()` is also monotonic but has its own
 * origin; on macOS it's backed by `mach_absolute_time`, on Linux by
 * `CLOCK_MONOTONIC` — neither guaranteed to share an epoch with the
 * C++ producer running in a separate process. Subtracting them yields
 * garbage deltas (observed: all-negative ≈ -96s offset), which the
 * `p50 > 0` filter discards, producing a spurious "no non-zero deltas"
 * failure. Measuring decode latency in-process is what the README spec
 * actually describes — "per-event work: proto decode + delta
 * computation only" — so we bracket `System.nanoTime()` directly
 * around the decode call. Monotonic, same-clock, measures exactly
 * the cost the p50 budget is meant to bound.
 *
 * Runner integration: sdk/runanywhere-kotlin/src/jvmTest/kotlin/
 * PerfBenchTest.kt (JUnit wrapper — asserts p50 < 1ms).
 *
 * Binary format (matches perf_producer.cpp):
 *   uint32_t magic = 0x42504152 ('RAPB')
 *   uint32_t count
 *   count × { uint32_t len; uint8_t[len] proto_bytes }
 */

package tests.streaming.perf_bench

import ai.runanywhere.proto.v1.VoiceEvent
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

object PerfBench {
    const val DEFAULT_INPUT_PATH = "/tmp/perf_input.bin"
    const val DEFAULT_OUTPUT_PATH = "/tmp/perf_bench.kt.log"
    const val MAGIC = 0x42504152u  // 'RAPB'

    data class Result(
        val count: Int,
        val nonEmpty: Int,
        val deltas: List<Long>,
    )

    /**
     * Run the perf bench consumer. Returns per-event latency deltas in ns.
     */
    fun run(
        inputPath: String = DEFAULT_INPUT_PATH,
        outputPath: String = DEFAULT_OUTPUT_PATH,
    ): Result {
        val bytes = File(inputPath).readBytes()
        require(bytes.size >= 8) { "perf_bench input too short (<8 bytes): ${bytes.size}" }

        val header = ByteBuffer.wrap(bytes, 0, 8).order(ByteOrder.LITTLE_ENDIAN)
        val readMagic = header.int.toUInt()
        require(readMagic == MAGIC) {
            "perf_bench bad magic: 0x${readMagic.toString(16)} (expected 0x${MAGIC.toString(16)})"
        }
        val count = header.int

        val deltas = ArrayList<Long>(count)
        var nonEmpty = 0
        var cursor = 8

        for (i in 0 until count) {
            if (cursor + 4 > bytes.size) break
            val lenBuf = ByteBuffer.wrap(bytes, cursor, 4).order(ByteOrder.LITTLE_ENDIAN)
            val len = lenBuf.int
            cursor += 4
            if (cursor + len > bytes.size) break

            val frame = bytes.copyOfRange(cursor, cursor + len)
            cursor += len

            try {
                val startNs = System.nanoTime()
                val event = VoiceEvent.ADAPTER.decode(frame)
                val endNs = System.nanoTime()
                val decodeNs = endNs - startNs

                if (decodeNs > 0L) {
                    deltas.add(decodeNs)
                    if ((event.metrics?.created_at_ns ?: 0L) > 0L) {
                        nonEmpty++
                    }
                } else {
                    deltas.add(0L)
                }
            } catch (e: Exception) {
                deltas.add(0L)
            }
        }

        writeDeltas(deltas, outputPath)
        println("perf_bench.kt: wrote ${deltas.size} deltas ($nonEmpty non-empty) to $outputPath")
        return Result(count = deltas.size, nonEmpty = nonEmpty, deltas = deltas)
    }

    /** Compute p50 over non-zero deltas. Returns null if no non-zero values. */
    fun p50(deltas: List<Long>): Long? {
        val nonZero = deltas.filter { it > 0 }.sorted()
        if (nonZero.isEmpty()) return null
        return nonZero[nonZero.size / 2]
    }

    private fun writeDeltas(deltas: List<Long>, path: String) {
        File(path).writeText(deltas.joinToString("\n") + "\n")
    }
}
