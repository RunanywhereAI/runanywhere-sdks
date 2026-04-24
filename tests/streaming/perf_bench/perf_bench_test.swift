// SPDX-License-Identifier: Apache-2.0
//
// perf_bench_test.swift — XCTest wrapper for GAP 09 #8 p50 benchmark.
//
// Asserts p50 < 1ms over the events produced by perf_producer. Wired
// into the StreamingParity test target via Package.swift. Skips when
// /tmp/perf_input.bin is missing.

import XCTest

final class PerfBenchTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.fileExists(atPath: PerfBench.defaultInputPath) else {
            throw XCTSkip(
                "perf_bench input missing at \(PerfBench.defaultInputPath). " +
                "Run: cmake --build build/macos-release --target perf_producer && " +
                "./build/macos-release/tests/streaming/perf_bench/perf_producer"
            )
        }
    }

    func testPerfBenchDecodesAndEmitsDeltas() throws {
        let result = try PerfBench.run()
        XCTAssertGreaterThan(result.count, 0, "expected >0 events decoded")
        XCTAssertGreaterThan(result.nonEmpty, 0, "expected >0 non-empty deltas")
    }

    func testPerfBenchP50UnderOneMillisecond() throws {
        let result = try PerfBench.run()
        guard let p50 = PerfBench.p50(result.deltas) else {
            XCTFail("no non-zero deltas — producer likely not emitting metrics arm")
            return
        }
        XCTAssertLessThan(
            p50,
            1_000_000,
            "p50 latency \(p50) ns exceeds 1ms threshold (GAP 09 #8)"
        )
    }
}
