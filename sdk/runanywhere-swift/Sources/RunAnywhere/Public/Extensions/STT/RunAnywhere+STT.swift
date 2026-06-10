//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations.
//  All transcription flows through C++ via CppBridge.STT / rac_stt_component,
//  which provides automatic telemetry for every registered STT backend.
//

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
        guard loadedModelSnapshot(category: .speechRecognition).found else {
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
    ///
    /// Chunks are fed into a lifecycle-derived native session as they arrive.
    /// Bridge errors are surfaced as a terminal partial with `isFinal = true`.
    static func transcribeStream(
        audio: AsyncStream<Data>,
        options: RASTTOptions = .defaults()
    ) -> AsyncStream<RASTTPartialResult> {
        AsyncStream { continuation in
            let task = Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }
                do {
                    try await ensureServicesReady()
                } catch {
                    continuation.finish()
                    return
                }
                let snapshot = loadedModelSnapshot(category: .speechRecognition)
                guard snapshot.found else {
                    continuation.finish()
                    return
                }

                do {
                    let partials = try await CppBridge.STT.shared.transcribeSessionStream(
                        audio: audio,
                        options: options,
                        loadedModel: snapshot
                    )
                    var sawFinal = false
                    for await partial in partials {
                        if Task.isCancelled { break }
                        if partial.isFinal {
                            sawFinal = true
                        }
                        continuation.yield(partial)
                    }
                    if !Task.isCancelled, !sawFinal {
                        var finalPartial = RASTTPartialResult()
                        finalPartial.isFinal = true
                        continuation.yield(finalPartial)
                    }
                } catch {
                    var failure = RASTTPartialResult()
                    failure.isFinal = true
                    failure.text = "STT stream failed: \(error)"
                    continuation.yield(failure)
                    continuation.finish()
                    return
                }

                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
