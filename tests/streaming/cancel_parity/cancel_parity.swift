// cancel_parity.swift — Swift consumer for GAP 09 #7 (v3.1 Phase 5.1).
//
// Reads /tmp/cancel_input.bin produced by cancel_producer.cpp,
// decodes each VoiceEvent via swift-protobuf, records
// `<ordinal> <kind> <recv_ns>` trace lines to /tmp/cancel_trace.swift.log.
// On observing the `interrupted` arm, flags cancelled=true; subsequent
// events record their delta-since-cancel for the 50ms budget check.

import Foundation
import SwiftProtobuf
// RAVoiceEvent + payload oneof are vended publicly by the RunAnywhere
// module via the swift-protobuf generated voice_events.pb.swift.
import RunAnywhere

public enum CancelParity {
    public static let defaultInputPath = "/tmp/cancel_input.bin"
    public static let defaultOutputPath = "/tmp/cancel_trace.swift.log"
    public static let magic: UInt32 = 0x43504152  // 'CPAR'

    public struct Result: Sendable {
        public let total: Int
        public let interruptOrdinal: Int?
        public let postCancelCount: Int
        public let postCancelMaxDeltaNs: Int64
    }

    public static func run(
        inputPath: String = defaultInputPath,
        outputPath: String = defaultOutputPath
    ) throws -> Result {
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        guard data.count >= 8 else {
            throw NSError(domain: "CancelParity", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "input too short",
            ])
        }
        let readMagic: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: 0, as: UInt32.self)
        }
        guard readMagic == magic else {
            throw NSError(domain: "CancelParity", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "bad magic",
            ])
        }
        let count: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self)
        }

        var cursor = 8
        var lines: [String] = []
        var interruptOrdinal: Int? = nil
        var cancelNs: Int64? = nil
        var postCancelCount = 0
        var postCancelMaxDelta: Int64 = 0

        for i in 0..<Int(count) {
            guard cursor + 4 <= data.count else { break }
            let len: UInt32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: cursor, as: UInt32.self)
            }
            cursor += 4
            guard cursor + Int(len) <= data.count else { break }
            let frame = data.subdata(in: cursor..<cursor + Int(len))
            cursor += Int(len)

            let recvNs = monotonicNs()
            let kind: String
            do {
                let event = try RAVoiceEvent(serializedBytes: frame)
                kind = payloadKind(event.payload)
            } catch {
                kind = "unknown"
            }
            lines.append("\(i) \(kind) \(recvNs)")

            if kind == "interrupted" && interruptOrdinal == nil {
                interruptOrdinal = i
                cancelNs = recvNs
            } else if let c = cancelNs {
                postCancelCount += 1
                let delta = recvNs - c
                if delta > postCancelMaxDelta { postCancelMaxDelta = delta }
            }
        }

        let text = lines.joined(separator: "\n") + "\n"
        try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
        return Result(
            total: Int(count),
            interruptOrdinal: interruptOrdinal,
            postCancelCount: postCancelCount,
            postCancelMaxDeltaNs: postCancelMaxDelta
        )
    }

    private static func payloadKind(_ payload: RAVoiceEvent.OneOf_Payload?) -> String {
        guard let p = payload else { return "unknown" }
        switch p {
        case .userSaid:        return "userSaid"
        case .assistantToken:  return "assistantToken"
        case .audio:           return "audio"
        case .vad:             return "vad"
        case .state:           return "state"
        case .error:           return "error"
        case .interrupted:     return "interrupted"
        case .metrics:         return "metrics"
        }
    }

    private static func monotonicNs() -> Int64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Int64(ts.tv_sec) * 1_000_000_000 + Int64(ts.tv_nsec)
    }
}
