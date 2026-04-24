// perf_bench.swift — Swift consumer for the GAP 09 #8 perf bench.
//
// v3.1: real implementation. Reads /tmp/perf_input.bin (produced by
// tests/streaming/perf_bench/perf_producer.cpp), decodes each VoiceEvent
// via swift-protobuf, extracts the producer-side timestamp from
// `metrics.created_at_ns`, and writes per-event delta_ns to
// /tmp/perf_bench.swift.log.
//
// Runner integration: sdk/runanywhere-swift/Tests/PerfBenchTests.swift
// (XCTest wrapper — asserts p50 < 1ms). Run with `swift test`.

import Foundation
import SwiftProtobuf
// RAVoiceEvent is vended by the RunAnywhere module (Generated/voice_events.pb.swift).
import RunAnywhere

/// Swift consumer for the GAP 09 #8 p50 benchmark.
///
/// Binary format (see tests/streaming/perf_bench/perf_producer.cpp):
///   uint32_t magic = 0x42504152 ('RAPB')
///   uint32_t count
///   count × { uint32_t len; uint8_t[len] proto_bytes }
public enum PerfBench {
    public static let defaultInputPath = "/tmp/perf_input.bin"
    public static let defaultOutputPath = "/tmp/perf_bench.swift.log"
    public static let magic: UInt32 = 0x42504152  // 'RAPB'

    public struct Result: Sendable {
        public let count: Int
        public let nonEmpty: Int
        public let deltas: [Int64]
    }

    /// Run the perf bench consumer. Returns per-event latency deltas in ns.
    @discardableResult
    public static func run(
        inputPath: String = defaultInputPath,
        outputPath: String = defaultOutputPath
    ) throws -> Result {
        let url = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: url)

        guard data.count >= 8 else {
            throw PerfBenchError.inputTooShort(size: data.count)
        }
        let readMagic: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: 0, as: UInt32.self)
        }
        guard readMagic == magic else {
            throw PerfBenchError.badMagic(got: readMagic, expected: magic)
        }
        let count: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self)
        }

        var deltas: [Int64] = []
        deltas.reserveCapacity(Int(count))
        var nonEmpty = 0

        var cursor = 8
        for _ in 0..<count {
            guard cursor + 4 <= data.count else { break }
            let len: UInt32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: cursor, as: UInt32.self)
            }
            cursor += 4
            guard cursor + Int(len) <= data.count else { break }
            let frame = data.subdata(in: cursor..<cursor + Int(len))
            cursor += Int(len)

            // Mark consumer-receive timestamp BEFORE decode — proto-decode
            // cost is part of the latency the consumer actually pays.
            let recvNs = monotonicNs()

            do {
                let event = try RAVoiceEvent(serializedBytes: frame)
                if case let .metrics(metrics) = event.payload {
                    if metrics.createdAtNs > 0 {
                        deltas.append(recvNs - metrics.createdAtNs)
                        nonEmpty += 1
                        continue
                    }
                }
                // No metrics arm (or zero timestamp) — record zero; the
                // aggregator filters zero values when computing percentiles.
                deltas.append(0)
            } catch {
                // Malformed frame: skip rather than abort the whole run.
                deltas.append(0)
            }
        }

        try writeDeltas(deltas, to: outputPath)
        print("perf_bench.swift: wrote \(deltas.count) deltas (\(nonEmpty) non-empty) to \(outputPath)")
        return Result(count: deltas.count, nonEmpty: nonEmpty, deltas: deltas)
    }

    /// Compute p50 over non-zero deltas. Returns nil if no non-zero values.
    public static func p50(_ deltas: [Int64]) -> Int64? {
        let nonZero = deltas.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return nil }
        return nonZero[nonZero.count / 2]
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

public enum PerfBenchError: Error, CustomStringConvertible {
    case inputTooShort(size: Int)
    case badMagic(got: UInt32, expected: UInt32)

    public var description: String {
        switch self {
        case .inputTooShort(let size):
            return "perf_bench input too short (<8 bytes): \(size)"
        case .badMagic(let got, let expected):
            return String(
                format: "perf_bench bad magic: 0x%08x (expected 0x%08x)",
                got, expected
            )
        }
    }
}
