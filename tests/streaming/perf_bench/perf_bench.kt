/*
 * perf_bench.kt — Kotlin consumer for the GAP 09 #8 perf bench.
 *
 * v2.1 quick-wins Item 3 scaffold. Reads /tmp/perf_input.bin (produced
 * by tests/streaming/perf_bench/perf_producer.cpp), decodes each
 * VoiceEvent via Wire, computes the consumer-side latency delta, and
 * writes per-event delta_ns to /tmp/perf_bench.kt.log.
 *
 * Status: SCAFFOLD. Per-SDK runner integration (JUnit5 in commonTest)
 * is the v2.1-2 follow-up.
 */

package com.runanywhere.sdk.tests.perf_bench

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
// import com.runanywhere.v1.VoiceEvent  // Wire-generated

object PerfBench {
    const val INPUT_PATH  = "/tmp/perf_input.bin"
    const val OUTPUT_PATH = "/tmp/perf_bench.kt.log"
    const val MAGIC: UInt = 0x42504152u  // 'RAPB'

    @JvmStatic
    fun run() {
        val raf = RandomAccessFile(INPUT_PATH, "r")
        val channel = raf.channel
        val buf = channel.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, channel.size())
        buf.order(ByteOrder.LITTLE_ENDIAN)

        require(buf.remaining() >= 8) { "Input too short" }
        val magic = buf.int.toUInt()
        require(magic == MAGIC) { "Bad magic: ${magic.toString(16)}" }
        val count = buf.int

        val deltas = LongArray(count)
        for (i in 0 until count) {
            require(buf.remaining() >= 4) { "Truncated at event $i header" }
            val len = buf.int
            require(buf.remaining() >= len) { "Truncated at event $i body" }
            val frame = ByteArray(len)
            buf.get(frame)

            // Mark consumer-receive timestamp BEFORE decode to include
            // proto-decode cost in latency.
            val recvNs = monotonicNs()

            // SCAFFOLD: replace with actual Wire decode.
            // val event = VoiceEvent.ADAPTER.decode(frame)
            // val producerNs = event.metrics?.tokens_generated?.toLong() ?: recvNs
            val producerNs = recvNs  // scaffold no-op

            deltas[i] = recvNs - producerNs
        }
        raf.close()

        File(OUTPUT_PATH).writeText(deltas.joinToString("\n") + "\n")
        println("perf_bench.kt: wrote ${deltas.size} deltas to $OUTPUT_PATH")
    }

    @JvmStatic
    fun monotonicNs(): Long = System.nanoTime()
}

// JUnit5 entry point (commented until v2.1-2 integrates):
// import org.junit.jupiter.api.Test
// class PerfBenchTest {
//     @Test fun `p50 under 1ms`() {
//         PerfBench.run()
//         // Aggregator asserts the p50 threshold.
//     }
// }
