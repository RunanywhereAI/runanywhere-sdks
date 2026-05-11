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
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        // Query ModelLifecycle instead of the CppBridge.STT actor's own
        // handle — those handles are separate, and the one loaded by
        // RunAnywhere.loadModel() is the lifecycle's, not the actor's.
        var currentRequest = RACurrentModelRequest()
        currentRequest.category = .speechRecognition
        let current = RunAnywhere.currentModel(currentRequest)
        guard current.found else {
            throw SDKException(code: .notInitialized, message: "STT model not loaded", category: .component)
        }

        var request = RASTTTranscriptionRequest()
        var audioSource = RASTTAudioSource()
        audioSource.audioData = audioData
        request.audio = audioSource
        request.options = options
        return try await CppBridge.STT.shared.transcribe(request)
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
                var currentRequest = RACurrentModelRequest()
                currentRequest.category = .speechRecognition
                let current = RunAnywhere.currentModel(currentRequest)
                guard current.found else {
                    continuation.finish()
                    return
                }
                for await chunk in audio {
                    if Task.isCancelled { break }
                    var request = RASTTTranscriptionRequest()
                    var audioSource = RASTTAudioSource()
                    audioSource.audioData = chunk
                    request.audio = audioSource
                    request.options = options
                    guard let partials = try? await CppBridge.STT.shared.transcribeStream(request) else {
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
