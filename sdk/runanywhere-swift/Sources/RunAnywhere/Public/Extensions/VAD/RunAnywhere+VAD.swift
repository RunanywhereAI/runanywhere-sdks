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
    static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions? = nil) async throws -> RAVADResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let sampleCount = audioData.count / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            throw SDKException.vad(.emptyAudioBuffer, "Audio data is empty")
        }

        let samples: [Float] = audioData.withUnsafeBytes { rawBuf in
            Array(rawBuf.bindMemory(to: Float.self).prefix(sampleCount))
        }
        return try await CppBridge.VAD.shared.process(
            samples: samples,
            options: options ?? RAVADOptions()
        )
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
