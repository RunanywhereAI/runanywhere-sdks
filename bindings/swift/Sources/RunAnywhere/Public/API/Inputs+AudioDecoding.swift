//
//  Inputs+AudioDecoding.swift
//  RunAnywhere SDK
//
//  Turning an audio file or container into the mono 16-bit PCM the ABI carries.
//
//  This lives with the SDK rather than in commons because reading and decoding
//  a file is platform I/O, and commons has neither a decoder nor a file reader.
//  It matters more than it looks: commons passes `audio_data` to the engine
//  without reading `encoding`, so a container handed across arrives with its
//  header treated as the first samples.
//

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

extension AudioInput {

    /// Mono 16-bit PCM plus the rate it is at.
    static func decodeToPCM16(_ input: AudioInput) throws -> (samples: Data, sampleRate: Int) {
        #if canImport(AVFoundation)
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }

        let url = try input.readableURL(temporary: &temporary)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw SDKException(
                code: .invalidInput,
                message: "could not read audio at \(url.lastPathComponent): \(error)",
                category: .validation
            )
        }

        let rate = file.processingFormat.sampleRate
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: rate,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw SDKException(
                code: .invalidInput,
                message: "unsupported audio format",
                category: .validation
            )
        }

        let samples = try Self.convert(file: file, with: converter, to: target, at: rate)
        guard !samples.isEmpty else {
            throw SDKException(
                code: .invalidInput,
                message: "audio decoded to no samples",
                category: .validation
            )
        }
        return (samples, Int(rate))
        #else
        throw SDKException(
            code: .featureNotAvailable,
            message: "Decoding audio files needs AVFoundation; supply AudioInput.pcm16 instead",
            category: .validation
        )
        #endif
    }

    #if canImport(AVFoundation)
    /// A file URL for this input, writing buffer-borne container bytes to a
    /// scratch file because `AVAudioFile` reads a file and nothing else.
    ///
    /// A scratch file is reported back through `temporary` so the caller can
    /// remove it; returning it would put the cleanup out of the caller's reach.
    private func readableURL(temporary: inout URL?) throws -> URL {
        if case .file = encoding {
            guard let path else {
                throw SDKException(
                    code: .invalidInput,
                    message: "AudioInput.file has no path",
                    category: .validation
                )
            }
            return URL(fileURLWithPath: path)
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try data.write(to: scratch)
        temporary = scratch
        return scratch
    }

    /// Reads `file` to the end, converting each chunk into `target` and
    /// appending the interleaved 16-bit samples.
    private static func convert(
        file: AVAudioFile,
        with converter: AVAudioConverter,
        to target: AVAudioFormat,
        at rate: Double
    ) throws -> Data {
        var samples = Data()
        let chunkFrames: AVAudioFrameCount = 16384

        while file.framePosition < file.length {
            guard let source = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: chunkFrames
            ) else { break }
            try file.read(into: source)
            if source.frameLength == 0 { break }

            let capacity = AVAudioFrameCount(
                (Double(source.frameLength) * rate / file.processingFormat.sampleRate).rounded(.up) + 1
            )
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
                break
            }

            var failure: NSError?
            var supplied = false
            converter.convert(to: output, error: &failure) { _, status in
                // One buffer per convert call: saying `haveData` twice would
                // hand the same chunk over again.
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return source
            }
            if let failure {
                throw SDKException(
                    code: .invalidInput,
                    message: "could not decode audio: \(failure.localizedDescription)",
                    category: .validation
                )
            }
            if let channel = output.int16ChannelData?[0], output.frameLength > 0 {
                samples.append(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
        }
        return samples
    }
    #endif
}
