//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Public API for Voice Activity Detection operations.
//  Calls C++ directly via CppBridge.VAD for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import CRACommons
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
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard audioData.count >= MemoryLayout<Float>.size else {
            throw SDKException.vad(.emptyAudioBuffer, "Audio data is empty")
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
    static func streamVAD(audio: AsyncStream<Data>) -> AsyncStream<RAVADResult> {
        AsyncStream<RAVADResult> { continuation in
            let task = Task {
                for await chunk in audio {
                    guard !Task.isCancelled else { break }
                    if let vadResult = try? await detectVoiceActivity(chunk) {
                        continuation.yield(vadResult)
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
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.VAD.shared.reset()
    }
}
