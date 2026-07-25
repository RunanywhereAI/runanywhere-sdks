//
//  RunAnywhere+Diarization.swift
//  RunAnywhere SDK
//

import Foundation

public extension RunAnywhere {
    /// Run standalone speaker diarization through the currently-loaded
    /// `.speakerDiarization` model. `audioData` must match `options.encoding`.
    static func diarize(
        audioData: Data,
        options: RADiarizationOptions = RADiarizationOptions()
    ) async throws -> RADiarizationResult {
        var request = RADiarizationRequest()
        request.audioData = audioData
        request.options = options
        return try await diarize(request)
    }

    /// Canonical request-based standalone speaker-diarization entry point.
    static func diarize(_ request: RADiarizationRequest) async throws -> RADiarizationResult {
        guard isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        try await ensureServicesReady()
        guard loadedModelSnapshot(category: .speakerDiarization).found else {
            throw SDKException(
                code: .notInitialized,
                message: "Speaker-diarization model not loaded",
                category: .component
            )
        }
        return try await CppBridge.Diarization.shared.diarize(request)
    }

    /// Feed a persistent stream of raw PCM chunks into the currently-loaded
    /// speaker-diarization model. UPDATE and FINAL events contain complete
    /// session snapshots; the final event terminates the stream.
    static func diarizeStream(
        audio: AsyncStream<Data>,
        options: RADiarizationOptions = RADiarizationOptions()
    ) async throws -> AsyncThrowingStream<RADiarizationStreamEvent, Error> {
        guard isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        try await ensureServicesReady()
        let snapshot = loadedModelSnapshot(category: .speakerDiarization)
        guard snapshot.found else {
            throw SDKException(
                code: .notInitialized,
                message: "Speaker-diarization model not loaded",
                category: .component
            )
        }
        return try await CppBridge.Diarization.shared.stream(
            audio: audio,
            options: options,
            loadedModel: snapshot
        )
    }
}
