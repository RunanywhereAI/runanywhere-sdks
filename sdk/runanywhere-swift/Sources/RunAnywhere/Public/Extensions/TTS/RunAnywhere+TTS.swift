//
//  RunAnywhere+TTS.swift
//  RunAnywhere SDK
//
//  Public API for Text-to-Speech operations.
//  Calls C++ directly via CppBridge.TTS for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import CRACommons
import Foundation

// MARK: - TTS Operations

public extension RunAnywhere {

    // MARK: - Synthesis

    /// Synthesize text to speech.
    ///
    /// A TTS voice must be loaded via `RAModelLoadRequest` (lifecycle) before calling this.
    static func synthesize(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) async throws -> RATTSOutput {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        // Use ModelLifecycle.currentModel to check if a TTS voice is loaded in
        // the lifecycle — CppBridge.TTS.shared.isLoaded queries the Swift
        // actor's own handle which is separate from the lifecycle's handle,
        // and would return false even after a successful RunAnywhere.loadModel().
        guard loadedModelSnapshot(category: .speechSynthesis).found else {
            throw SDKException(code: .notInitialized, message: "TTS voice not loaded", category: .component)
        }

        var request = RATTSSynthesisRequest()
        request.text = text
        request.options = options
        return try await CppBridge.TTS.shared.synthesize(request)
    }

    /// Stream synthesis through a lifecycle-derived native TTS session.
    static func synthesizeStream(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) -> AsyncStream<RATTSOutput> {
        AsyncStream { continuation in
            let task = Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }
                do {
                    try await ensureServicesReady()
                } catch {
                    continuation.finish()
                    return
                }
                // Mirror synthesize(): query ModelLifecycle (the canonical
                // source of truth) instead of the CppBridge.TTS actor's own
                // handle, which is separate from the lifecycle's handle.
                let snapshot = loadedModelSnapshot(category: .speechSynthesis)
                guard snapshot.found else {
                    continuation.finish()
                    return
                }
                var request = RATTSSynthesisRequest()
                request.text = text
                request.options = options
                let stream: AsyncStream<RATTSOutput>
                do {
                    stream = try await CppBridge.TTS.shared.synthesizeSessionStream(
                        request,
                        loadedModel: snapshot
                    )
                } catch {
                    var failure = RATTSOutput()
                    failure.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                    failure.isFinal = true
                    failure.errorMessage = "TTS stream failed: \(error)"
                    failure.errorCode = Int32(RAC_ERROR_PROCESSING_FAILED)
                    continuation.yield(failure)
                    continuation.finish()
                    return
                }
                for await output in stream {
                    if Task.isCancelled { break }
                    continuation.yield(output)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Stop current TTS synthesis
    static func stopSynthesis() async {
        await CppBridge.TTS.shared.stop()
    }

    // MARK: - Speak (Simple API)

    /// Speak text aloud through the device speakers.
    ///
    /// Synthesizes via the C++ TTS ABI then plays the resulting PCM through the
    /// platform `AudioPlaybackManager`.
    static func speak(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) async throws -> RATTSSpeakResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let output = try await synthesize(text, options: options)

        // Convert Float32 PCM to WAV format using C++ utility
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : options.sampleRate
        let wavData = try convertPCMToWAV(pcmData: output.audioData, sampleRate: sampleRate > 0 ? sampleRate : 22_050)

        // Play the audio using platform audio manager
        if !wavData.isEmpty {
            try await ttsAudioPlayback.play(wavData)
        }

        return RATTSSpeakResult(output: output)
    }

    /// Stop current speech playback
    static func stopSpeaking() async {
        ttsAudioPlayback.stop()
        await stopSynthesis()
    }

    // MARK: - Private Audio Playback

    /// Audio playback manager for TTS speak functionality
    private static let ttsAudioPlayback = AudioPlaybackManager()

    /// Convert Float32 PCM to WAV using C++ audio utilities
    private static func convertPCMToWAV(pcmData: Data, sampleRate: Int32) throws -> Data {
        guard !pcmData.isEmpty else { return Data() }

        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize: Int = 0

        let result = pcmData.withUnsafeBytes { pcmPtr in
            rac_audio_float32_to_wav(
                pcmPtr.baseAddress,
                pcmData.count,
                sampleRate,
                &wavDataPtr,
                &wavSize
            )
        }

        guard result == RAC_SUCCESS, let ptr = wavDataPtr, wavSize > 0 else {
            throw SDKException(code: .processingFailed, message: "Failed to convert PCM to WAV: \(result)", category: .component)
        }

        let wavData = Data(bytes: ptr, count: wavSize)
        rac_free(ptr)

        return wavData
    }
}
