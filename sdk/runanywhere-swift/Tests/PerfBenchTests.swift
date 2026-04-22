//
// PerfBenchTests.swift — XCTest runner for GAP 09 #8 p50 benchmark.
//
// v3.1: asserts p50 < 1ms for the Swift SDK's event-decode path over
// 10,000 events produced by tests/streaming/perf_bench/perf_producer.
//
// Pre-condition: /tmp/perf_input.bin must exist. Produce it with:
//   cmake --build build/macos-release --target perf_producer && \
//   ./build/macos-release/tests/streaming/perf_bench/perf_producer
//

import XCTest
@testable import RunAnywhere

// PerfBench lives in the shared tests/streaming/perf_bench/ directory
// and is symlinked into this test target via Package.swift exclude +
// resource rules. For now, we inline the consumer runner here to keep
// the Package.swift layout minimal.

final class PerfBenchTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.fileExists(atPath: "/tmp/perf_input.bin") else {
            throw XCTSkip(
                "perf_bench input missing at /tmp/perf_input.bin. " +
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
            1_000_000,  // 1 ms
            "p50 latency \(p50) ns exceeds 1ms threshold (GAP 09 #8)"
        )
    }
}
