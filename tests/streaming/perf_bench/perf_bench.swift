// perf_bench.swift — Swift consumer for the GAP 09 #8 perf bench.
//
// v2.1 quick-wins Item 3 scaffold. Reads /tmp/perf_input.bin (produced
// by tests/streaming/perf_bench/perf_producer.cpp), decodes each
// VoiceEvent via swift-protobuf, computes the consumer-side latency
// delta, and writes per-event delta_ns to /tmp/perf_bench.swift.log.
//
// Status: SCAFFOLD. Per-SDK runner integration (XCTest) is the v2.1-2
// follow-up. To run today, you have to drop this into a test target
// manually — see tests/streaming/perf_bench/README.md "Running locally".

import Foundation
import SwiftProtobuf
// import RunAnywhere  // The codegen'd proto module name — adjust per project layout.

struct PerfBench {
    static let inputPath  = "/tmp/perf_input.bin"
    static let outputPath = "/tmp/perf_bench.swift.log"
    static let magic: UInt32 = 0x42504152  // 'RAPB'

    static func run() throws {
        let url = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: url)
        var cursor = 0

        // Header: magic (4) + count (4)
        guard data.count >= 8 else { throw NSError(domain: "PerfBench", code: 1) }
        let readMagic: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard readMagic == magic else { throw NSError(domain: "PerfBench", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Bad magic: \(String(readMagic, radix: 16))"]) }
        let count: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        cursor = 8

        var deltas: [Int64] = []
        deltas.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard cursor + 4 <= data.count else { break }
            let len: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: cursor, as: UInt32.self) }
            cursor += 4
            guard cursor + Int(len) <= data.count else { break }
            let frame = data.subdata(in: cursor..<cursor + Int(len))
            cursor += Int(len)

            // Mark the consumer-receive timestamp BEFORE decode to
            // include the proto-decode cost in the latency.
            let recvNs = monotonicNs()

            // SCAFFOLD: replace with the actual swift-protobuf type.
            // let event = try Runanywhere_V1_VoiceEvent(serializedData: frame)
            // let producerNs = Int64(event.metrics.tokensGenerated)
            //
            // For the scaffold, simulate decode work + zero delta:
            _ = frame.count
            let producerNs: Int64 = recvNs

            deltas.append(recvNs - producerNs)
        }

        try writeDeltas(deltas, to: outputPath)
        print("perf_bench.swift: wrote \(deltas.count) deltas to \(outputPath)")
    }

    static func monotonicNs() -> Int64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Int64(ts.tv_sec) * 1_000_000_000 + Int64(ts.tv_nsec)
    }

    static func writeDeltas(_ deltas: [Int64], to path: String) throws {
        let lines = deltas.map { String($0) }.joined(separator: "\n") + "\n"
        try lines.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// XCTest entry point (commented until v2.1-2 integrates):
// final class PerfBenchTests: XCTestCase {
//     func test_p50_under_1ms() throws {
//         try PerfBench.run()
//         // Aggregator (compute_percentiles.py) asserts the p50 threshold.
//     }
// }
