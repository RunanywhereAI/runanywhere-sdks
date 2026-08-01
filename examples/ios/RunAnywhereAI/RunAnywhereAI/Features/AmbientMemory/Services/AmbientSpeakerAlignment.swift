//
//  AmbientSpeakerAlignment.swift
//  RunAnywhereAI
//
//  Post-pass helpers: strip PCM from Notes WAVs and assign Sortformer turns
//  to ASR segments by recording-relative overlap.
//

import Foundation
import RunAnywhere

enum AmbientSpeakerAlignment {

    /// Minimum overlap (ms) and fraction of the ASR segment that must match a
    /// diarization turn before we accept a speaker assignment.
    static let minimumOverlapMs = 200
    static let minimumOverlapFraction = 0.30

    struct Turn {
        let startMs: Int64
        let endMs: Int64
        let label: String
    }

    /// Map diarization turns onto ASR segments. One label per segment (dominant
    /// overlap). Ambiguous / short overlaps yield no assignment.
    static func assignments(
        segments: [AmbientSegmentRecord],
        turns: [Turn]
    ) -> [String: String] {
        let intervals = recordingIntervals(for: segments)
        let sortedTurns = turns.sorted { $0.startMs < $1.startMs }
        var result: [String: String] = [:]

        for interval in intervals {
            let duration = max(0, interval.endMs - interval.startMs)
            guard duration > 0 else { continue }

            var bestLabel: String?
            var bestOverlap = 0
            for turn in sortedTurns {
                let overlap = max(
                    0,
                    min(interval.endMs, Int(turn.endMs)) - max(interval.startMs, Int(turn.startMs))
                )
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestLabel = turn.label
                }
            }

            let threshold = max(minimumOverlapMs, Int(Double(duration) * minimumOverlapFraction))
            if let bestLabel, bestOverlap >= threshold {
                result[interval.segment.id] = bestLabel
            }
        }
        return result
    }

    static func turns(from result: RADiarizationResult) -> [Turn] {
        result.segments.map { segment in
            let label: String
            if !segment.speakerID.isEmpty {
                // "speaker_0" → "Speaker 1" for a friendlier Notes UI.
                if segment.speakerID.hasPrefix("speaker_"),
                   let index = Int(segment.speakerID.dropFirst("speaker_".count)) {
                    label = "Speaker \(index + 1)"
                } else {
                    label = segment.speakerID
                }
            } else {
                label = "Speaker \(segment.speakerIndex + 1)"
            }
            return Turn(startMs: segment.startMs, endMs: segment.endMs, label: label)
        }
    }

    /// Prefer stamped offsets; fall back to cumulative `durationMs` for notes
    /// captured before the pipeline wrote recording-relative times.
    static func recordingIntervals(
        for segments: [AmbientSegmentRecord]
    ) -> [(segment: AmbientSegmentRecord, startMs: Int, endMs: Int)] {
        let ordered = segments.sorted { $0.index < $1.index }
        var cursor = 0
        var intervals: [(AmbientSegmentRecord, Int, Int)] = []
        for segment in ordered {
            let start: Int
            let end: Int
            if let stampedStart = segment.startOffsetMs,
               let stampedEnd = segment.endOffsetMs,
               stampedEnd > stampedStart {
                start = stampedStart
                end = stampedEnd
                cursor = max(cursor, end)
            } else {
                start = cursor
                end = cursor + max(0, segment.durationMs)
                cursor = end
            }
            intervals.append((segment, start, end))
        }
        return intervals.map { ($0.0, $0.1, $0.2) }
    }
}

// MARK: - WAV → PCM

enum AmbientWAVPCMReader {
    enum ReadError: LocalizedError {
        case missingFile
        case invalidHeader
        case unsupportedFormat(String)
        case truncated

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return "Recording file is missing."
            case .invalidHeader:
                return "Recording is not a valid WAV file."
            case .unsupportedFormat(let detail):
                return "Unsupported recording format: \(detail)."
            case .truncated:
                return "Recording file is truncated."
            }
        }
    }

    /// Read PCM16 LE mono from a Notes WAV written by `WAVFileWriter`.
    static func pcm16Mono(from url: URL, expectedSampleRate: Int = 16_000) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.missingFile
        }
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else { throw ReadError.invalidHeader }

        // Notes writes a fixed 44-byte PCM header (RIFF/WAVE/fmt /data).
        guard String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
            throw ReadError.invalidHeader
        }

        var offset = 12
        var sampleRate: UInt32 = 0
        var channels: UInt16 = 0
        var bitsPerSample: UInt16 = 0
        var audioFormat: UInt16 = 0
        var pcm: Data?

        while offset + 8 <= data.count {
            let chunkID = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32(data, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard payloadEnd <= data.count else { throw ReadError.truncated }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else { throw ReadError.invalidHeader }
                audioFormat = readUInt16(data, at: payloadStart)
                channels = readUInt16(data, at: payloadStart + 2)
                sampleRate = readUInt32(data, at: payloadStart + 4)
                bitsPerSample = readUInt16(data, at: payloadStart + 14)
            } else if chunkID == "data" {
                pcm = data.subdata(in: payloadStart..<payloadEnd)
            }

            offset = payloadEnd + (chunkSize % 2) // word-align
        }

        guard let pcm else { throw ReadError.invalidHeader }
        guard audioFormat == 1 else {
            throw ReadError.unsupportedFormat("audio format \(audioFormat) (need PCM)")
        }
        guard channels == 1 else {
            throw ReadError.unsupportedFormat("\(channels) channels (need mono)")
        }
        guard bitsPerSample == 16 else {
            throw ReadError.unsupportedFormat("\(bitsPerSample)-bit (need 16)")
        }
        guard Int(sampleRate) == expectedSampleRate else {
            throw ReadError.unsupportedFormat(
                "\(sampleRate) Hz (need \(expectedSampleRate))"
            )
        }
        return pcm
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}
