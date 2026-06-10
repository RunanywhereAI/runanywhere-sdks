//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Public API for Voice Activity Detection operations.
//  Calls C++ directly via CppBridge.VAD for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import Foundation

// MARK: - VAD Operations

public extension RunAnywhere {

    /// Detect voice activity in a raw PCM audio buffer.
    ///
    /// Routes through the commons VAD lifecycle service (handle-less) so the
    /// Silero model loaded via `RunAnywhere.loadModel(...)` is actually used
    /// instead of falling through to the energy-based fallback. Fixes SWIFT-VAD-001.
    static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions? = nil) async throws -> RAVADResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        guard audioData.count >= MemoryLayout<Float>.size else {
            throw SDKException(code: .emptyAudioBuffer, message: "Audio data is empty", category: .component)
        }

        var request = RAVADProcessRequest()
        var audioSource = RAVADAudioSource()
        audioSource.audioData = audioData
        request.audio = audioSource
        if let options {
            request.options = options
        }
        return try await CppBridge.VAD.shared.processLifecycle(request: request)
    }

    /// Stream VAD results over a sequence of raw PCM audio chunks.
    ///
    /// Each element in `audio` must be `Data` holding IEEE-754 single-precision
    /// PCM samples at 16 kHz mono. The returned `AsyncStream` yields one
    /// `RAVADResult` per input chunk.
    ///
    /// When the underlying detector throws, the failure is surfaced as an
    /// error-marked `RAVADResult` (non-empty `errorMessage`, non-zero
    /// `errorCode`) and the stream finishes so callers do not silently keep
    /// pumping audio into a dead detector.
    static func streamVAD(audio: AsyncStream<Data>, options: RAVADOptions? = nil) -> AsyncStream<RAVADResult> {
        AsyncStream<RAVADResult> { continuation in
            let task = Task {
                for await chunk in audio {
                    guard !Task.isCancelled else { break }
                    do {
                        let vadResult = try await detectVoiceActivity(chunk, options: options)
                        continuation.yield(vadResult)
                    } catch {
                        let sdkError = SDKException.from(error, category: .component)
                        var failure = RAVADResult()
                        failure.errorMessage = "VAD stream failed: \(sdkError.message)"
                        failure.errorCode = Int32(sdkError.code.rawValue)
                        continuation.yield(failure)
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Reset VAD internal state.
    static func resetVAD() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await CppBridge.VAD.shared.reset()
    }
}
