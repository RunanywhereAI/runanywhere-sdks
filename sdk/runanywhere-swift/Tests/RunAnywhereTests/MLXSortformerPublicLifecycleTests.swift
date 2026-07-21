import Foundation
import MLXRuntime
@testable import RunAnywhere
import XCTest

final class MLXSortformerPublicLifecycleTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testExactBundleThroughPublicOfflineAndPersistentStreamLifecycle() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["RUNANYWHERE_SORTFORMER_MODEL_DIR"],
              let fixturePath = environment["RUNANYWHERE_SORTFORMER_AUDIO_FIXTURE"] else {
            throw XCTSkip("Set the Sortformer model and audio fixture paths for the public lifecycle test")
        }

        await RunAnywhere.reset()
        let didRegister = await MainActor.run {
            MLX.register(priority: 100)
        }
        XCTAssertTrue(didRegister)
        try RunAnywhere.initialize()

        let modelID = "mlx-sortformer-4spk-v2.1-fp16-e23e6404"
        var model = RAModelInfo()
        model.id = modelID
        model.name = "NVIDIA Streaming Sortformer 4-Speaker v2.1 FP16"
        model.category = .speakerDiarization
        model.format = .safetensors
        model.framework = .mlx
        model.localPath = modelPath
        model.downloadURL = "https://huggingface.co/mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16/tree/e23e6404bd9859e93edbf94a740eb1c7fc58f12e"
        model.downloadSizeBytes = 236_109_834
        model.memoryRequiredBytes = 236_109_834
        model.isDownloaded = true

        var importRequest = RAModelImportRequest()
        importRequest.model = model
        importRequest.sourcePath = modelPath
        importRequest.overwriteExisting = true
        importRequest.validateBeforeRegister = true
        let imported = try await RunAnywhere.importModel(importRequest)
        XCTAssertTrue(imported.success, imported.errorMessage)
        XCTAssertTrue(imported.registered)
        XCTAssertEqual(imported.localPath, modelPath)

        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = modelID
        loadRequest.category = .speakerDiarization
        loadRequest.framework = .mlx
        loadRequest.validateAvailability = true
        let loaded = await RunAnywhere.loadModel(loadRequest)
        XCTAssertTrue(loaded.success, loaded.errorMessage)
        XCTAssertEqual(loaded.modelID, modelID)
        XCTAssertEqual(loaded.resolvedPath, modelPath)

        var currentRequest = RACurrentModelRequest()
        currentRequest.category = .speakerDiarization
        currentRequest.includeModelMetadata = true
        let current = RunAnywhere.currentModel(currentRequest)
        XCTAssertTrue(current.found)
        XCTAssertEqual(current.modelID, modelID)
        XCTAssertEqual(current.framework, .mlx)
        XCTAssertEqual(current.resolvedPath, modelPath)

        let pcm = try publicLifecyclePCM16Payload(URL(fileURLWithPath: fixturePath))
        XCTAssertEqual(pcm.count, 960_000)
        var options = RADiarizationOptions()
        options.sampleRateHz = 16_000
        options.channelCount = 1
        options.encoding = .pcmS16Le
        options.threshold = 0.5

        let offline = try await RunAnywhere.diarize(audioData: pcm, options: options)
        XCTAssertGreaterThanOrEqual(offline.speakerCount, 2)
        XCTAssertEqual(offline.audioDurationMs, 30_000)
        XCTAssertFalse(offline.segments.isEmpty)

        let chunkByteCount = 5 * 16_000 * MemoryLayout<Int16>.stride
        let audio = AsyncStream<Data> { continuation in
            for offset in stride(from: 0, to: pcm.count, by: chunkByteCount) {
                let end = min(offset + chunkByteCount, pcm.count)
                continuation.yield(pcm.subdata(in: offset..<end))
            }
            continuation.finish()
        }
        let stream = try await RunAnywhere.diarizeStream(audio: audio, options: options)
        var events: [RADiarizationStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.first?.kind, .started)
        XCTAssertEqual(events.last?.kind, .final)
        XCTAssertTrue(zip(events, events.dropFirst()).allSatisfy { $0.seq < $1.seq })
        let final = try XCTUnwrap(events.last?.result)
        XCTAssertGreaterThanOrEqual(final.speakerCount, 2)
        XCTAssertEqual(final.audioDurationMs, 30_000)
        XCTAssertFalse(final.segments.isEmpty)

        var unloadRequest = RAModelUnloadRequest()
        unloadRequest.modelID = modelID
        unloadRequest.category = .speakerDiarization
        let unloaded = await RunAnywhere.unloadModel(unloadRequest)
        XCTAssertTrue(unloaded.success, unloaded.errorMessage)
        XCTAssertTrue(unloaded.unloadedModelIds.contains(modelID))
        XCTAssertFalse(RunAnywhere.currentModel(currentRequest).found)

        await RunAnywhere.reset()
        await MainActor.run {
            MLX.unregister()
        }
    }
}

private func publicLifecyclePCM16Payload(_ url: URL) throws -> Data {
    let data = try Data(contentsOf: url)
    guard data.count >= 12,
          String(data: data[0..<4], encoding: .ascii) == "RIFF",
          String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
        throw CocoaError(.fileReadCorruptFile)
    }

    var offset = 12
    while offset + 8 <= data.count {
        let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii)
        let size = Int(publicLifecycleLittleEndianUInt32(data, at: offset + 4))
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + size
        guard payloadEnd <= data.count else { throw CocoaError(.fileReadCorruptFile) }
        if chunkID == "data" {
            return data.subdata(in: payloadStart..<payloadEnd)
        }
        offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
    }
    throw CocoaError(.fileReadCorruptFile)
}

private func publicLifecycleLittleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
}
