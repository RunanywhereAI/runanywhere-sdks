/**
 * PerfBenchTest.kt — JUnit runner for GAP 09 #8 p50 benchmark.
 *
 * v3.1: asserts p50 < 1ms for the Kotlin SDK's event-decode path over
 * 10,000 events produced by tests/streaming/perf_bench/perf_producer.
 *
 * Pre-condition: /tmp/perf_input.bin must exist.
 *
 * To run:
 *   cmake --build build/macos-release --target perf_producer && \
 *   ./build/macos-release/tests/streaming/perf_bench/perf_producer && \
 *   cd sdk/runanywhere-kotlin && ./gradlew jvmTest --tests *PerfBenchTest*
 */

package com.runanywhere.sdk.perf

import org.junit.Assume
import org.junit.Test
import tests.streaming.perfbench.PerfBench
import java.io.File
import kotlin.test.assertTrue

class PerfBenchTest {
    @Test
    fun `perf bench decodes and emits deltas`() {
        Assume.assumeTrue(
            "perf_bench input missing at /tmp/perf_input.bin (run perf_producer first)",
            File(PerfBench.DEFAULT_INPUT_PATH).exists(),
        )

        val result = PerfBench.run()
        assertTrue(result.count > 0, "expected >0 events decoded")
        assertTrue(result.nonEmpty > 0, "expected >0 non-empty deltas")
    }

    @Test
    fun `perf bench p50 under 1ms`() {
        Assume.assumeTrue(
            "perf_bench input missing at /tmp/perf_input.bin",
            File(PerfBench.DEFAULT_INPUT_PATH).exists(),
        )

        val result = PerfBench.run()
        val p50 = PerfBench.p50(result.deltas)
        requireNotNull(p50) {
            "no non-zero deltas — producer likely not emitting metrics arm"
        }
        assertTrue(
            p50 < 1_000_000L, // 1 ms
            "p50 latency $p50 ns exceeds 1ms threshold (GAP 09 #8)",
        )
    }
}
