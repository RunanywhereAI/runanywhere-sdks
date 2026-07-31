//
//  WAVFileWriter.swift
//  RunAnywhereAI
//
//  Streams 16-bit PCM into a WAV file as it arrives.
//
//  A note can run for hours, so the samples cannot be buffered in memory and
//  written once at the end: the header is written up front with zeroed sizes
//  and patched with the real lengths when the file is closed.
//

import Foundation

/// Appends PCM16 samples to a growing WAV file.
///
/// Not thread-safe by itself; `AmbientMemoryStore` owns the only instance and
/// serializes access to it.
final class WAVFileWriter {

    private let handle: FileHandle
    private var dataBytes: UInt32 = 0
    private var isClosed = false

    private static let headerSize = 44
    private static let bitsPerSample: UInt16 = 16
    private static let channelCount: UInt16 = 1

    init(url: URL, sampleRate: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Until-first-unlock stays writable after the screen locks — required
        // for Voice Memos-style background capture. Complete protection
        // refuses every append the moment the phone locks.
        try Self.header(sampleRate: sampleRate, dataBytes: 0)
            .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(_ pcm16: Data) throws {
        guard !isClosed, !pcm16.isEmpty else { return }
        try handle.write(contentsOf: pcm16)
        dataBytes += UInt32(pcm16.count)
    }

    /// Patch the RIFF and data chunk sizes, then close. A file that is never
    /// closed (a crash mid-note) still plays in most players, just with a
    /// zero-length header, which is why the samples are on disk regardless.
    func close() throws {
        guard !isClosed else { return }
        isClosed = true
        defer { try? handle.close() }

        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: Self.littleEndian(UInt32(Self.headerSize - 8) + dataBytes))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Self.littleEndian(dataBytes))
    }

    // MARK: - Header

    private static func header(sampleRate: Int, dataBytes: UInt32) -> Data {
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)

        var data = Data(capacity: headerSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian(UInt32(headerSize - 8) + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(littleEndian(UInt32(16)))
        data.append(littleEndian(UInt16(1)))
        data.append(littleEndian(channelCount))
        data.append(littleEndian(UInt32(sampleRate)))
        data.append(littleEndian(byteRate))
        data.append(littleEndian(blockAlign))
        data.append(littleEndian(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian(dataBytes))
        return data
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
