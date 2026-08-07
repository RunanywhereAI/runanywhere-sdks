//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Deprecated flat STT verbs. The v3 surface is `RunAnywhere.stt`; these
//  forwarders keep the proto-typed shapes they always returned.
//

import Foundation

public extension RunAnywhere {

    /// Transcribe audio data through the generated-proto C++ STT ABI.
    @available(*, deprecated, renamed: "stt.transcribe(_:options:)")
    static func transcribe(
        audio audioData: Data,
        options: RASTTOptions = .defaults()
    ) async throws -> RASTTOutput {
        try await transcribeProto(
            audio: .float32(audioData, sampleRate: Int(RADefaults.AudioCapture.micSampleRateHz)),
            options: options
        )
    }

    /// Current STT service state from the commons lifecycle.
    @available(*, deprecated, renamed: "stt.state()")
    static func sttState() async throws -> RASTTServiceState {
        try await sttStateProto()
    }

    /// Stream-in / stream-out transcription over raw PCM chunks.
    @available(*, deprecated, renamed: "stt.transcribeStream(_:options:)")
    static func transcribeStream(
        audio: AsyncStream<Data>,
        options: RASTTOptions = .defaults()
    ) -> AsyncStream<RASTTPartialResult> {
        AsyncStream { continuation in
            let task = Task {
                guard let snapshot = try? requireSTTModel() else {
                    continuation.finish()
                    return
                }
                do {
                    try await ensureServicesReady()
                } catch {
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
                        if partial.isFinal { sawFinal = true }
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
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
