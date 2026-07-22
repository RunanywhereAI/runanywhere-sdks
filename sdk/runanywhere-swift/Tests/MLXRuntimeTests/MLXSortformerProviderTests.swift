import Foundation
@testable import MLXRuntime
import os
import XCTest

final class MLXSortformerProviderTests: XCTestCase {
    func testPinnedBundleMetadata() {
        XCTAssertEqual(
            MLXSortformerCatalog.repository,
            "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
        )
        XCTAssertEqual(
            MLXSortformerCatalog.revision,
            "e23e6404bd9859e93edbf94a740eb1c7fc58f12e"
        )
        XCTAssertEqual(MLXSortformerCatalog.maximumSpeakerCount, 4)
        XCTAssertEqual(MLXSortformerCatalog.supportedSampleRate, 16_000)
        XCTAssertEqual(MLXSortformerCatalog.downloadSizeBytes, 236_109_834)
        XCTAssertEqual(
            MLXSortformerCatalog.files.map(\.filename),
            ["config.json", "model.safetensors"]
        )
        XCTAssertEqual(
            MLXSortformerCatalog.files.map(\.sha256),
            [
                "17c9f943bed07b0593f2b8dca01e0be6a418053becc6148b01ecabdff9cbd84d",
                "3b60b8df29e59a8abaf8061ceeeae6e9284a68fbcd2e762c68f5e058bfceebfa"
            ]
        )
        XCTAssertTrue(
            MLXSortformerCatalog.files.allSatisfy {
                $0.url.absoluteString.contains(MLXSortformerCatalog.revision)
            }
        )
    }

    func testBundleValidationReportsBothRequiredFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try MLXSortformerCatalog.validateModelDirectory(directory)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .missingBundleFiles(["config.json", "model.safetensors"])
            )
        }
    }

    func testOptionsRejectUnsupportedSampleRate() {
        var options = MLXSortformerOptions()
        options.sampleRate = 48_000

        XCTAssertThrowsError(try options.validate(sampleCount: 16_000)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .unsupportedSampleRate(48_000)
            )
        }
    }

    func testOptionsRejectInvalidStreamingCache() {
        var options = MLXSortformerOptions()
        options.speakerCacheFrames = 0

        XCTAssertThrowsError(try options.validate(sampleCount: 16_000)) { error in
            XCTAssertEqual(
                error as? MLXSortformerProviderError,
                .invalidStreamingCacheSize
            )
        }
    }

    func testSessionCancellationGateRejectsBeforeOperation() async {
        await XCTAssertThrowsErrorAsync(
            try await MLXSessionCancellationGate.run(
                isCancelled: { true },
                operation: {
                    XCTFail("A pre-cancelled MLX operation must not start")
                    return 1
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testSessionCancellationGateRejectsResultAfterCancellation() async {
        let cancellation = OSAllocatedUnfairLock(initialState: false)

        await XCTAssertThrowsErrorAsync(
            try await MLXSessionCancellationGate.run(
                isCancelled: { cancellation.withLock { $0 } },
                operation: {
                    cancellation.withLock { $0 = true }
                    return 1
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testSessionCancellationGateReturnsCompletedResult() async throws {
        let result = try await MLXSessionCancellationGate.run(
            isCancelled: { false },
            operation: { 42 }
        )

        XCTAssertEqual(result, 42)
    }

    func testRealOfflineAndPersistentStreamWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["RUNANYWHERE_SORTFORMER_MODEL_DIR"],
              let fixturePath = environment["RUNANYWHERE_SORTFORMER_AUDIO_FIXTURE"] else {
            throw XCTSkip("Set the Sortformer model and audio fixture paths for the Metal integration test")
        }

        let provider = try MLXSortformerProvider(
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        let samples = try readMonoPCM16WAV(URL(fileURLWithPath: fixturePath))
        XCTAssertEqual(samples.count, 480_000)

        let offline = try await provider.diarize(samples: samples)
        XCTAssertFalse(offline.segments.isEmpty)
        XCTAssertGreaterThanOrEqual(offline.activeSpeakerCount, 2)
        XCTAssertEqual(offline.audioDurationMilliseconds, 30_000)

        let stream = try provider.makePersistentStream()
        await XCTAssertThrowsErrorAsync(try await provider.diarize(samples: samples)) { error in
            XCTAssertEqual(error as? MLXSortformerProviderError, .providerBusy)
        }

        var snapshot: MLXSortformerResult?
        let chunkSize = 5 * MLXSortformerCatalog.supportedSampleRate
        for offset in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(offset + chunkSize, samples.count)
            snapshot = try await stream.feed(samples: Array(samples[offset..<end]))
        }
        let final = try XCTUnwrap(snapshot)
        XCTAssertFalse(final.segments.isEmpty)
        XCTAssertGreaterThanOrEqual(final.activeSpeakerCount, 2)
        XCTAssertEqual(final.audioDurationMilliseconds, 30_000)
        XCTAssertEqual(try stream.flush(), final)
        stream.close()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        errorHandler(error)
    }
}

private func readMonoPCM16WAV(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard data.count >= 12,
          String(data: data[0..<4], encoding: .ascii) == "RIFF",
          String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
        throw CocoaError(.fileReadCorruptFile)
    }

    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii)
        let size = Int(littleEndianUInt32(data, at: offset + 4))
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + size
        guard payloadEnd <= data.count else { throw CocoaError(.fileReadCorruptFile) }
        if chunkID == "data" {
            guard size.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
            return stride(from: payloadStart, to: payloadEnd, by: 2).map { index in
                let bits = UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
                return Float(Int16(bitPattern: bits)) / Float(Int16.max)
            }
        }
        offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
    }
    throw CocoaError(.fileReadCorruptFile)
}

private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
}
