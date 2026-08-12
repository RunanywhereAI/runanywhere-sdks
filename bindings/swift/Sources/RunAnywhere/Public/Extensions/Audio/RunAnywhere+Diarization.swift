//
//  RunAnywhere+Diarization.swift
//  RunAnywhere SDK
//
//  Deprecated flat diarization verbs. The v3 surface is
//  `RunAnywhere.diarization`.
//

import Foundation

public extension RunAnywhere {

    /// Run standalone speaker diarization over raw PCM.
    @available(*, deprecated, renamed: "diarization.diarize(_:options:)")
    static func diarize(
        audioData: Data,
        options: RADiarizationOptions = RADiarizationOptions()
    ) async throws -> RADiarizationResult {
        var request = RADiarizationRequest()
        request.audioData = audioData
        request.options = options
        return try await diarizeProto(request)
    }

    /// Canonical request-based standalone speaker-diarization entry point.
    @available(*, deprecated, renamed: "diarization.diarize(_:options:)")
    static func diarize(_ request: RADiarizationRequest) async throws -> RADiarizationResult {
        try await diarizeProto(request)
    }

    /// Feed a persistent stream of raw PCM chunks into the loaded model.
    @available(*, deprecated, renamed: "diarization.diarizeStream(_:options:sampleRate:channels:encoding:)")
    static func diarizeStream(
        audio: AsyncStream<Data>,
        options: RADiarizationOptions = RADiarizationOptions()
    ) async throws -> AsyncThrowingStream<RADiarizationStreamEvent, Error> {
        let snapshot = try requireDiarizationModel()
        try await ensureServicesReady()
        return try await CppBridge.Diarization.shared.stream(
            audio: audio,
            options: options,
            loadedModel: snapshot
        )
    }
}
