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
    ///
    /// Chunks are accumulated into a single buffer and forwarded to the
    /// underlying `CppBridge.STT.transcribeStream` exactly once after the
    /// input source closes. Bridge errors are surfaced as a terminal partial
    /// with `isFinal = true` and `text` carrying a non-empty `"STT stream
    /// failed: …"` payload, matching the shape `ProtoStreamContext` emits
    /// when the native producer fails.
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
                var currentRequest = RACurrentModelRequest()
                currentRequest.category = .speechRecognition
                let current = RunAnywhere.currentModel(currentRequest)
                guard current.found else {
                    continuation.finish()
                    return
                }

                var accumulated = Data()
                for await chunk in audio {
                    if Task.isCancelled { break }
                    accumulated.append(chunk)
                }

                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                var request = RASTTTranscriptionRequest()
                var audioSource = RASTTAudioSource()
                audioSource.audioData = accumulated
                request.audio = audioSource
                request.options = options

                do {
                    let partials = try await CppBridge.STT.shared.transcribeStream(request)
                    for await partial in partials {
                        if Task.isCancelled { break }
                        continuation.yield(partial)
                    }
                } catch {
                    var failure = RASTTPartialResult()
                    failure.isFinal = true
                    failure.text = "STT stream failed: \(error)"
                    continuation.yield(failure)
                    continuation.finish()
                    return
                }

                var finalPartial = RASTTPartialResult()
                finalPartial.isFinal = true
                continuation.yield(finalPartial)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
