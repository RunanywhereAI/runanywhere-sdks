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
                    for try await partial in partials {
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
                    // Deliberately not yielded as a partial. This used to emit
                    // `isFinal = true` with the error message as `text`, which a
                    // consumer reads as recognized speech — the failure arrived
                    // looking like the user had said "STT stream failed: …".
                    //
                    // `AsyncStream<RASTTPartialResult>` has no error channel and
                    // widening this deprecated signature would be source-breaking,
                    // so the honest option left is to log and end the stream
                    // without a transcript. Callers that need the failure itself
                    // should use `RunAnywhere.stt.openStream`, whose event grammar
                    // carries `.failed`.
                    SDKLogger.stt.error("transcribeStream failed: \(error.localizedDescription)")
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
