//
//  RunAnywhere+VAD.swift
//  RunAnywhere SDK
//
//  Deprecated flat VAD verbs. The v3 surface is `RunAnywhere.vad`.
//

import Foundation

public extension RunAnywhere {

    /// Detect voice activity in a raw Float32 PCM buffer.
    @available(*, deprecated, renamed: "vad.detect(_:options:)")
    static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions? = nil) async throws -> RAVADResult {
        try await detectVoiceActivityProto(
            audio: .float32(audioData, sampleRate: Int(RADefaults.AudioCapture.micSampleRateHz)),
            options: options
        )
    }

    /// Stream VAD results over a sequence of raw Float32 PCM chunks.
    @available(*, deprecated, renamed: "vad.detectStream(_:options:)")
    static func streamVAD(audio: AsyncStream<Data>, options: RAVADOptions? = nil) -> AsyncStream<RAVADResult> {
        AsyncStream<RAVADResult> { continuation in
            let task = Task {
                for await chunk in audio {
                    guard !Task.isCancelled else { break }
                    do {
                        let vadResult = try await detectVoiceActivityProto(
                            audio: .float32(chunk, sampleRate: Int(RADefaults.AudioCapture.micSampleRateHz)),
                            options: options
                        )
                        continuation.yield(vadResult)
                    } catch {
                        let sdkError = SDKException.from(error, category: .component)
                        var failure = RAVADResult()
                        var failureError = sdkError.proto
                        failureError.message = "VAD stream failed: \(sdkError.message)"
                        failure.error = failureError
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
    @available(*, deprecated, renamed: "vad.reset()")
    static func resetVAD() async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await CppBridge.VAD.shared.reset()
    }
}
