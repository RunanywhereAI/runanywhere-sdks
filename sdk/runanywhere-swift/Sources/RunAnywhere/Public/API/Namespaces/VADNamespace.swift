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

        /// Detect speech across a live stream of audio chunks.
        ///
        /// - Throws: `SDKException` from this call when the SDK is not
        ///   initialized, and into the returned stream when detection fails.
        public func detectStream(
            _ audio: AsyncStream<AudioInput>,
            options: VadOptions? = nil
        ) async throws -> AsyncThrowingStream<VadEvent, Error> {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()
            let protoOptions = options?.toProto()

            return AsyncThrowingStream { continuation in
                let task = Task {
                    var wasSpeech = false
                    do {
                        for await chunk in audio {
                            if Task.isCancelled { break }
                            let proto = try await RunAnywhere.detectVoiceActivityProto(
                                audio: chunk,
                                options: protoOptions
                            )
                            let result = VadResult(proto: proto)
                            continuation.yield(.frame(result))
                            if result.isSpeech != wasSpeech {
                                wasSpeech = result.isSpeech
                                continuation.yield(result.isSpeech ? .speechStarted : .speechEnded)
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

// MARK: - VadEvent

/// Progress of one streaming voice-activity detection.
public enum VadEvent: Sendable {
    case speechStarted
    case speechEnded
    case frame(VadResult)
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func detectVoiceActivityProto(
        audio: AudioInput,
        options: RAVADOptions?
    ) async throws -> RAVADResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        guard audio.data.count >= MemoryLayout<Float>.size else {
            throw SDKException(code: .emptyAudioBuffer, message: "Audio data is empty", category: .component)
        }

        var request = RAVADProcessRequest()
        request.audio = try audio.toVADAudioSource()
        if let options {
            request.options = options
        }
        return try await CppBridge.VAD.shared.processLifecycle(request: request)
    }
}
