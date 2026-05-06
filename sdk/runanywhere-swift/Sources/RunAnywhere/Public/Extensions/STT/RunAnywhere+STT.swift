//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations.
//  All transcription flows through C++ via CppBridge.STT / rac_stt_component,
//  which provides automatic telemetry for every registered STT backend.
//

import CRACommons
import Foundation

// MARK: - STT Operations

public extension RunAnywhere {

    /// Transcribe audio data through the generated-proto C++ STT ABI.
    static func transcribe(
        audio audioData: Data,
        options: RASTTOptions = .defaults()
    ) async throws -> RASTTOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKException.stt(.notInitialized, "STT model not loaded")
        }

        return try await CppBridge.STT.shared.transcribe(audioData: audioData, options: options)
    }

    /// Canonical stream-in / stream-out transcription.
    ///
    /// Consumes an `AsyncStream<Data>` of PCM audio chunks and yields
    /// `RASTTPartialResult` events. Each partial result carries an
    /// incremental transcript and an `isFinal` flag; the stream closes after
    /// the final event or on error.
    static func transcribeStream(
        audio: AsyncStream<Data>,
        options: RASTTOptions = .defaults()
    ) -> AsyncStream<RASTTPartialResult> {
        AsyncStream { continuation in
            Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }
                guard await CppBridge.STT.shared.isLoaded else {
                    continuation.finish()
                    return
                }
                for await chunk in audio {
                    if Task.isCancelled { break }
                    guard let partials = try? await CppBridge.STT.shared.transcribeStream(
                        audioData: chunk,
                        options: options
                    ) else {
                        continue
                    }
                    for await partial in partials {
                        continuation.yield(partial)
                    }
                }
                var finalPartial = RASTTPartialResult()
                finalPartial.isFinal = true
                continuation.yield(finalPartial)
                continuation.finish()
            }
        }
    }
}
