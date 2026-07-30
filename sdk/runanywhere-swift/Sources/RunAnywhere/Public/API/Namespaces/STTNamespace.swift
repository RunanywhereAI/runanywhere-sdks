//
//  STTNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.stt` — transcription. Holds the internal proto-level helpers
//  that both this namespace and the deprecated flat verbs call.
//

import Foundation

public extension RunAnywhere {

    /// Speech-to-text.
    static var stt: STT { STT() }

    /// Transcribe recorded audio or a live audio stream.
    struct STT: Sendable {

        /// Transcribe one audio input.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.stt.transcribe(.wav(bytes))
        /// print(result.text)
        /// ```
        ///
        /// - Throws: `SDKException` when no STT model is loaded or the backend fails.
        public func transcribe(
            _ audio: AudioInput,
            options: SttOptions? = nil
        ) async throws -> Transcription {
            let proto = try await RunAnywhere.transcribeProto(
                audio: audio,
                options: (options ?? SttOptions()).toProto()
            )
            return Transcription(proto: proto)
        }

        /// Transcribe a live stream of audio chunks.
        ///
        /// - Throws: `SDKException` from this call when no STT model is loaded,
        ///   and into the returned stream when the session fails mid-flight.
        public func transcribeStream(
            _ audio: AsyncStream<AudioInput>,
            options: SttOptions? = nil
        ) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
            let snapshot = try RunAnywhere.requireSTTModel()
            try await RunAnywhere.ensureServicesReady()

            let chunks = AsyncStream<Data> { continuation in
                let pump = Task {
                    for await input in audio {
                        continuation.yield(input.data)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in pump.cancel() }
            }

            let partials = try await CppBridge.STT.shared.transcribeSessionStream(
                audio: chunks,
                options: (options ?? SttOptions()).toProto(),
                loadedModel: snapshot
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.started)
                    var sawFinal = false
                    var last: RASTTPartialResult?
                    for await partial in partials {
                        if Task.isCancelled { break }
                        last = partial
                        // The bridge reports stream failures on the terminal
                        // partial's `finalOutput`; surface them as a thrown
                        // error instead of leaking them through `text`.
                        if partial.hasFinalOutput, partial.finalOutput.errorCode != 0 {
                            let message = partial.finalOutput.errorMessage
                            continuation.finish(throwing: SDKException(
                                code: .processingFailed,
                                message: message.isEmpty ? "STT stream failed" : message,
                                category: .component
                            ))
                            return
                        }
                        if partial.isFinal {
                            sawFinal = true
                            continuation.yield(.final(RunAnywhere.transcription(from: partial)))
                        } else {
                            continuation.yield(.partial(text: partial.text))
                        }
                    }
                    if !sawFinal, !Task.isCancelled {
                        continuation.yield(.final(RunAnywhere.transcription(from: last ?? RASTTPartialResult())))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }

        /// Report whether transcription is usable and which languages it covers.
        ///
        /// - Throws: `SDKException` when the SDK has not been initialized.
        public func state() async throws -> SttState {
            SttState(proto: try await RunAnywhere.sttStateProto())
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func requireSTTModel() throws -> RACurrentModelResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        let snapshot = loadedModelSnapshot(category: .speechRecognition)
        guard snapshot.found else {
            throw SDKException(code: .modelNotLoaded, message: "STT model not loaded", category: .component)
        }
        return snapshot
    }

    internal static func transcribeProto(
        audio: AudioInput,
        options: RASTTOptions
    ) async throws -> RASTTOutput {
        _ = try requireSTTModel()
        try await ensureServicesReady()

        var request = RASTTTranscriptionRequest()
        request.audio = audio.toSTTAudioSource()
        request.options = options
        return try await CppBridge.STT.shared.transcribe(request)
    }

    internal static func sttStateProto() async throws -> RASTTServiceState {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.STT.shared.stateProto()
    }

    /// Prefer the backend's terminal `RASTTOutput`; fall back to the partial's
    /// own transcript when the session ended without one.
    internal static func transcription(from partial: RASTTPartialResult) -> Transcription {
        if partial.hasFinalOutput {
            return Transcription(proto: partial.finalOutput)
        }
        var synthesized = RASTTOutput()
        synthesized.text = partial.text
        synthesized.confidence = partial.confidence
        if partial.hasLanguage { synthesized.language = partial.language }
        synthesized.durationMs = max(0, partial.audioEndMs - partial.audioStartMs)
        return Transcription(proto: synthesized)
    }
}
