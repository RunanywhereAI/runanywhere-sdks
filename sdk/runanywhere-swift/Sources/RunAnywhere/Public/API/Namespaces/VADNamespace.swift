//
//  VADNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.vad` — voice-activity detection over buffers and streams.
//

import Foundation

public extension RunAnywhere {

    /// Voice-activity detection.
    static var vad: VAD { VAD() }

    /// Decide whether audio contains speech.
    struct VAD: Sendable {

        /// Detect speech in one audio buffer.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.vad.detect(.float32(samples: frame))
        /// print(result.isSpeech)
        /// ```
        ///
        /// - Throws: `SDKException` when the buffer is empty or the detector fails.
        public func detect(
            _ audio: AudioInput,
            options: VadOptions? = nil
        ) async throws -> VadResult {
            let proto = try await RunAnywhere.detectVoiceActivityProto(
                audio: audio,
                options: options?.toProto()
            )
            return VadResult(proto: proto)
        }

        /// Open a live VAD stream. The format is established once; every frame
        /// pushed afterward carries raw PCM in that format.
        ///
        /// Preflight failures (SDK not initialized, unsupported encoding)
        /// surface as `.failed` on `events` rather than a thrown error, since
        /// this factory does not `throw`.
        ///
        /// ```swift
        /// let stream = RunAnywhere.vad.openStream(format: .init(encoding: .pcmS16Le, sampleRate: 16000))
        /// for try await event in stream.events { print(event) }
        /// ```
        public func openStream(format: AudioFormatSpec, options: VadOptions? = nil) -> VadStream {
            let protoOptions = options?.toProto()
            let (frameStream, frameContinuation) = AsyncStream<AudioFrame>.makeStream()

            let events = AsyncThrowingStream<VadEvent, Error> { continuation in
                let task = Task {
                    guard RunAnywhere.isReady else {
                        continuation.yield(.failed(SDKException(
                            code: .notInitialized,
                            message: "SDK not initialized",
                            category: .internal
                        )))
                        continuation.finish()
                        return
                    }
                    try? await RunAnywhere.ensureServicesReady()

                    var wasSpeech = false
                    for await frame in frameStream {
                        if Task.isCancelled { break }
                        do {
                            let source = try RunAnywhere.vadAudioSource(frame: frame, format: format)
                            let result = VadResult(proto: try await RunAnywhere.detectVoiceActivityProto(
                                source: source,
                                options: protoOptions
                            ))
                            if result.isSpeech != wasSpeech {
                                wasSpeech = result.isSpeech
                                continuation.yield(result.isSpeech
                                    ? .speechStarted(timestampMs: frame.timestampMs)
                                    : .speechEnded(timestampMs: frame.timestampMs))
                            }
                            continuation.yield(.activity(
                                isSpeech: result.isSpeech,
                                probability: result.probability,
                                timestampMs: frame.timestampMs
                            ))
                        } catch {
                            continuation.yield(.failed(SDKException.from(error)))
                            continuation.finish()
                            return
                        }
                    }
                    if !Task.isCancelled {
                        continuation.yield(.completed)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }

            return VadStream(
                events: events,
                pushHandler: { frame in frameContinuation.yield(frame) },
                flushHandler: { /* frames are processed as they arrive */ },
                finishHandler: { frameContinuation.finish() },
                closeHandler: { frameContinuation.finish() }
            )
        }

        /// Detect speech across a live stream of audio chunks.
        ///
        /// Forwards into `openStream` when every chunk shares one
        /// `AudioFormatSpec`; a chunk with a different format ends the stream
        /// with a thrown error.
        ///
        /// - Throws: `SDKException` into the returned stream when the input
        ///   produced no chunks, chunks disagree on format, or detection fails.
        @available(*, deprecated, message: "Use openStream(format:options:) and push AudioFrame values")
        public func detectStream(
            _ audio: AsyncStream<AudioInput>,
            options: VadOptions? = nil
        ) async throws -> AsyncThrowingStream<VadEvent, Error> {
            let iterator = AudioInputIteratorBox(audio)

            return AsyncThrowingStream { continuation in
                // The first chunk is read *inside* the returned stream, never
                // before it is handed back. Every microphone-fed caller starts
                // capture only once this factory returns, so peeking here would
                // park the consumer on a producer that cannot start yet — that
                // circular wait is what froze the VAD screen on iOS and macOS.
                let driver = Task {
                    var live: VadStream?
                    do {
                        guard let first = await iterator.next() else {
                            throw SDKException(
                                code: .invalidInput,
                                message: "Audio stream produced no chunks",
                                category: .validation
                            )
                        }
                        let format = try first.liveFormatSpec()
                        let stream = openStream(format: format, options: options)
                        live = stream

                        // Drain concurrently with the pump so speech-started /
                        // speech-ended reach the caller while the mic is open.
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
                                    "vad.detectStream chunks must share one AudioFormatSpec"
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

        /// Clear the detector's rolling state between unrelated recordings.
        ///
        /// - Throws: `SDKException` when the SDK has not been initialized.
        public func reset() async throws {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await CppBridge.VAD.shared.reset()
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func detectVoiceActivityProto(
        audio: AudioInput,
        options: RAVADOptions?
    ) async throws -> RAVADResult {
        guard audio.data.count >= MemoryLayout<Float>.size else {
            throw SDKException(code: .emptyAudioBuffer, message: "Audio data is empty", category: .component)
        }
        return try await detectVoiceActivityProto(source: try audio.toVADAudioSource(), options: options)
    }

    internal static func detectVoiceActivityProto(
        source: RAVADAudioSource,
        options: RAVADOptions?
    ) async throws -> RAVADResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var request = RAVADProcessRequest()
        request.audio = source
        if let options {
            request.options = options
        }
        return try await CppBridge.VAD.shared.processLifecycle(request: request)
    }

    /// Build a raw-PCM `RAVADAudioSource` from one pushed `AudioFrame`, using
    /// the format established once by `vad.openStream`.
    internal static func vadAudioSource(frame: AudioFrame, format: AudioFormatSpec) throws -> RAVADAudioSource {
        var source = RAVADAudioSource()
        source.channels = Int32(max(1, format.channels))
        if format.sampleRate > 0 { source.sampleRate = Int32(format.sampleRate) }
        switch format.encoding {
        case .pcmS16Le:
            source.audioData = frame.samples
            source.encoding = .pcmS16Le
        case .pcmF32Le:
            source.audioData = frame.samples
            source.encoding = .pcmF32Le
        default:
            throw SDKException(
                code: .invalidInput,
                message: "VAD live streams need raw PCM (pcmS16Le/pcmF32Le), not a container format",
                category: .validation
            )
        }
        return source
    }
}
