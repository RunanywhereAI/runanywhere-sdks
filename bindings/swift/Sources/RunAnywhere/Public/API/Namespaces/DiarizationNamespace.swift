//
//  DiarizationNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.diarization` — who spoke when.
//

import Foundation

public extension RunAnywhere {

    /// Speaker diarization.
    static var diarization: Diarization { Diarization() }

    /// Attribute audio spans to speakers.
    struct Diarization: Sendable {

        /// Split `audio` into speaker turns.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.diarization.diarize(.float32(samples: pcm))
        /// print(result.speakerCount)
        /// ```
        ///
        /// - Throws: `SDKException` when no diarization model is loaded or the run fails.
        public func diarize(
            _ audio: AudioInput,
            options: DiarizationOptions? = nil
        ) async throws -> DiarizationResult {
            var request = RADiarizationRequest()
            request.audioData = try audio.diarizationBytes()
            request.options = (options ?? DiarizationOptions()).toProto(audio: audio)
            return DiarizationResult(proto: try await RunAnywhere.diarizeProto(request))
        }

        /// Diarize a live stream, emitting a full session snapshot per update.
        ///
        /// - Throws: `SDKException` from this call when no diarization model is
        ///   loaded, and into the returned stream when the session fails.
        /// - Parameter encoding: Sample layout of the streamed chunks.
        public func diarizeStream(
            _ audio: AsyncStream<AudioInput>,
            options: DiarizationOptions? = nil,
            sampleRate: Int = 16000,
            channels: Int = 1,
            encoding: RAAudioEncoding = .pcmF32Le
        ) async throws -> AsyncThrowingStream<DiarizationResult, Error> {
            let snapshot = try RunAnywhere.requireDiarizationModel()
            try await RunAnywhere.ensureServicesReady()

            let protoOptions = (options ?? DiarizationOptions()).toProto(
                sampleRate: sampleRate,
                channels: channels,
                encoding: encoding
            )

            let chunks = AsyncStream<Data> { continuation in
                let pump = Task {
                    for await input in audio {
                        continuation.yield(input.data)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in pump.cancel() }
            }

            let events = try await CppBridge.Diarization.shared.stream(
                audio: chunks,
                options: protoOptions,
                loadedModel: snapshot
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in events {
                            if Task.isCancelled { break }
                            if event.kind == .error {
                                throw SDKException(
                                    code: .processingFailed,
                                    message: event.hasError ? event.error.message : "Diarization stream failed",
                                    category: .component
                                )
                            }
                            if event.hasResult {
                                continuation.yield(DiarizationResult(proto: event.result))
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func requireDiarizationModel() throws -> RACurrentModelResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        let snapshot = loadedModelSnapshot(category: .speakerDiarization)
        guard snapshot.found else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Speaker-diarization model not loaded",
                category: .component
            )
        }
        return snapshot
    }

    internal static func diarizeProto(_ request: RADiarizationRequest) async throws -> RADiarizationResult {
        _ = try requireDiarizationModel()
        try await ensureServicesReady()
        return try await CppBridge.Diarization.shared.diarize(request)
    }
}
