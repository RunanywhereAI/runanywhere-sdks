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

        /// Open a live transcription stream. The format is established once;
        /// every frame pushed afterward carries raw PCM in that format.
        ///
        /// ```swift
        /// let stream = try await RunAnywhere.stt.openStream(format: .init(encoding: .pcmS16Le, sampleRate: 16000))
        /// for try await event in stream.events { print(event) }
        /// ```
        ///
        /// - Throws: `SDKException` when no STT model is loaded or the native
        ///   streaming session cannot start.
        public func openStream(
            format: AudioFormatSpec,
            options: SttOptions? = nil
        ) async throws -> SttStream {
            guard format.encoding != .container else {
                throw SDKException(
                    code: .invalidInput,
                    message: "STT live streams need raw PCM (pcmS16Le/pcmF32Le), not a container format",
                    category: .validation
                )
            }
            let snapshot = try RunAnywhere.requireSTTModel()
            try await RunAnywhere.ensureServicesReady()

            let (audioStream, audioContinuation) = AsyncStream<Data>.makeStream()
            let partials = try await CppBridge.STT.shared.transcribeSessionStream(
                audio: audioStream,
                options: (options ?? SttOptions()).toProto(),
                loadedModel: snapshot
            )

            let requestId = UUID().uuidString
            let events = AsyncThrowingStream<TranscriptionEvent, Error> { continuation in
                let task = Task {
                    continuation.yield(.started(requestId: requestId))
                    var sawTerminal = false
                    var sequence: Int64 = 0
                    func nextSequence() -> Int64 {
                        sequence += 1
                        return sequence
                    }

                    // A FINAL ends an UTTERANCE, not the session. commons closes
                    // a window on ~800 ms of trailing silence and publishes one
                    // FINAL for it (rac_stt_stream.cpp), then keeps the session
                    // open for the next phrase. This loop used to `break` on the
                    // first one and report `.completed`, so a live session went
                    // deaf the moment the speaker drew breath: measured on the
                    // simulator, a 16 s recording of four spaced sentences
                    // transcribed the first and silently discarded the other
                    // three while the panel still said RECORDING. Every final is
                    // forwarded now; the session ends when the audio source does.
                    for await partial in partials {
                        if Task.isCancelled { break }
                        if partial.isFinal {
                            continuation.yield(.transcriptFinal(
                                requestId: requestId,
                                sequence: nextSequence(),
                                transcription: RunAnywhere.transcription(from: partial)
                            ))
                            sawTerminal = true
                            continue
                        }
                        continuation.yield(.partial(
                            requestId: requestId,
                            sequence: nextSequence(),
                            segmentId: requestId,
                            revision: Int(sequence),
                            alternatives: [partial.text]
                        ))
                    }

                    // The grammar ends in `completed`/`failed`/`cancelled` —
                    // never a fabricated `transcriptFinal`/`completed` when the
                    // producer never reported one.
                    if Task.isCancelled {
                        continuation.yield(.cancelled(requestId: requestId))
                    } else if sawTerminal {
                        continuation.yield(.completed(requestId: requestId))
                    } else {
                        continuation.yield(.failed(
                            requestId: requestId,
                            error: SDKException(
                                code: .streamCancelled,
                                message: "Transcription stream ended before a final result",
                                category: .component
                            )
                        ))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }

            return SttStream(
                events: events,
                pushHandler: { frame in audioContinuation.yield(frame.samples) },
                flushHandler: { /* frames are fed to the native session as they arrive */ },
                finishHandler: { audioContinuation.finish() },
                closeHandler: { audioContinuation.finish() }
            )
        }

        /// Transcribe a live stream of audio chunks.
        ///
        /// Forwards into `openStream` when every chunk shares one
        /// `AudioFormatSpec`; a chunk with a different format ends the stream
        /// with a thrown error.
        ///
        /// - Throws: `SDKException` from this call when no STT model is loaded,
        ///   and into the returned stream when the input produced no chunks,
        ///   chunks disagree on format, or the session fails mid-flight.
        @available(*, deprecated, message: "Use openStream(format:options:) and push AudioFrame values")
        public func transcribeStream(
            _ audio: AsyncStream<AudioInput>,
            options: SttOptions? = nil
        ) async throws -> AsyncThrowingStream<TranscriptionEvent, Error> {
            // Preflight only what can be answered without touching the caller's
            // stream, so "no model loaded" still fails from this call.
            _ = try RunAnywhere.requireSTTModel()
            let iterator = AudioInputIteratorBox(audio)

            return AsyncThrowingStream { continuation in
                // The first chunk is read *inside* the returned stream, never
                // before it is handed back. Every microphone-fed caller starts
                // capture only once this factory returns, so peeking here would
                // park the consumer on a producer that cannot start yet — that
                // circular wait is what froze STT Live on iOS and macOS.
                let driver = Task {
                    var live: SttStream?
                    do {
                        guard let first = await iterator.next() else {
                            throw SDKException(
                                code: .invalidInput,
                                message: "Audio stream produced no chunks",
                                category: .validation
                            )
                        }
                        let format = try first.liveFormatSpec()
                        let stream = try await openStream(format: format, options: options)
                        live = stream

                        // Drain concurrently with the pump so partials reach the
                        // caller while the microphone is still open.
                        let drainTask = Task {
                            for try await event in stream.events {
                                continuation.yield(event)
                            }
                        }

                        var mismatch: SDKException?
                        stream.pushFrame(first.toLiveFrame())
                        while let chunk = await iterator.next() {
                            if Task.isCancelled { break }
                            guard chunk.matchesLiveFormat(format) else {
                                mismatch = SDKException.validationFailed(
                                    "stt.transcribeStream chunks must share one AudioFormatSpec"
                                )
                                break
                            }
                            stream.pushFrame(chunk.toLiveFrame())
                        }
                        stream.finish()
                        _ = try? await drainTask.value
                        if let mismatch {
                            continuation.finish(throwing: mismatch)
                        } else {
                            continuation.finish()
                        }
                    } catch {
                        continuation.finish(throwing: SDKException.from(error))
                    }
                    await live?.close()
                }
                continuation.onTermination = { @Sendable _ in driver.cancel() }
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

    /// Build a terminal `RASTTOutput` from a partial. `RASTTPartialResult`
    /// collapsed to `text`/`isFinal`/`language` (idl/stt_options.proto):
    /// `finalOutput`/`confidence`/`audioStartMs`/`audioEndMs` no longer
    /// exist on it, so this now only carries `text`/`language` forward.
    internal static func transcription(from partial: RASTTPartialResult) -> Transcription {
        var synthesized = RASTTOutput()
        synthesized.text = partial.text
        if partial.hasLanguage { synthesized.language = partial.language }
        return Transcription(proto: synthesized)
    }
}
