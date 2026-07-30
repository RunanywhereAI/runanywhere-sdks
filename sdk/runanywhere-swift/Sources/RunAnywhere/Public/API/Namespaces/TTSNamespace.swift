//
//  TTSNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.tts` — synthesis and device playback, plus the internal
//  proto-level helpers the deprecated flat verbs share.
//

import CRACommons
import Foundation

public extension RunAnywhere {

    /// Text-to-speech.
    static var tts: TTS { TTS() }

    /// Synthesize speech and play it through the device.
    struct TTS: Sendable {

        /// Synthesize text into one audio buffer.
        ///
        /// ```swift
        /// let audio = try await RunAnywhere.tts.synthesize("Hello there")
        /// print(audio.durationMs)
        /// ```
        ///
        /// - Throws: `SDKException` when no voice is loaded or synthesis fails.
        public func synthesize(
            _ text: String,
            options: TtsOptions? = nil
        ) async throws -> Audio {
            let proto = try await RunAnywhere.synthesizeProto(
                text: text,
                options: (options ?? TtsOptions()).toProto()
            )
            return Audio(proto: proto)
        }

        /// Synthesize text, yielding audio as it is produced.
        ///
        /// - Throws: `SDKException` from this call when no voice is loaded, and
        ///   into the returned stream when synthesis fails mid-flight.
        public func synthesizeStream(
            _ text: String,
            options: TtsOptions? = nil
        ) async throws -> AsyncThrowingStream<AudioChunk, Error> {
            let snapshot = try RunAnywhere.requireTTSVoice()
            try await RunAnywhere.ensureServicesReady()

            var request = RATTSSynthesisRequest()
            request.text = text
            request.options = (options ?? TtsOptions()).toProto()

            let outputs = try await CppBridge.TTS.shared.synthesizeSessionStream(
                request,
                loadedModel: snapshot
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    for await output in outputs {
                        if Task.isCancelled { break }
                        if output.errorCode != 0 {
                            continuation.finish(throwing: SDKException(
                                code: .processingFailed,
                                message: output.hasErrorMessage ? output.errorMessage : "TTS stream failed",
                                category: .component
                            ))
                            return
                        }
                        continuation.yield(AudioChunk(proto: output))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }

        /// Synthesize text and play it through the device speakers.
        ///
        /// - Throws: `SDKException` when no voice is loaded, synthesis fails, or
        ///   playback cannot start.
        public func speak(_ text: String, options: TtsOptions? = nil) async throws {
            _ = try await RunAnywhere.speakProto(
                text: text,
                options: (options ?? TtsOptions()).toProto()
            )
        }

        /// Stop playback and any synthesis still in flight.
        public func stop() async {
            await RunAnywhere.stopSpeech()
        }

        /// List the voices the loaded engine can speak with.
        ///
        /// - Throws: `SDKException` when the SDK has not been initialized.
        public func voices() async throws -> [Voice] {
            try await RunAnywhere.ttsStateProto().voices
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    /// Playback manager shared by `tts.speak` and the deprecated `speak`.
    private static let speechPlayback = AudioPlaybackManager()

    internal static func requireTTSVoice() throws -> RACurrentModelResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        // The lifecycle is the source of truth: the CppBridge.TTS actor keeps a
        // separate handle that RunAnywhere-level loads never populate.
        let snapshot = loadedModelSnapshot(category: .speechSynthesis)
        guard snapshot.found else {
            throw SDKException(code: .modelNotLoaded, message: "TTS voice not loaded", category: .component)
        }
        return snapshot
    }

    internal static func synthesizeProto(
        text: String,
        options: RATTSOptions
    ) async throws -> RATTSOutput {
        _ = try requireTTSVoice()
        try await ensureServicesReady()

        var request = RATTSSynthesisRequest()
        request.text = text
        request.options = options
        return try await CppBridge.TTS.shared.synthesize(request)
    }

    internal static func speakProto(
        text: String,
        options: RATTSOptions
    ) async throws -> RATTSSpeakResult {
        let output = try await synthesizeProto(text: text, options: options)

        let sampleRate = output.sampleRate > 0 ? output.sampleRate : options.sampleRate
        let wavSampleRate = sampleRate > 0 ? sampleRate : Int32(RADefaults.AudioCapture.ttsSampleRateHz)
        let wavData = try convertPCMToWAV(pcmData: output.audioData, sampleRate: wavSampleRate)

        if !wavData.isEmpty {
            try await speechPlayback.play(wavData)
        }
        return RATTSSpeakResult(output: output)
    }

    internal static func stopSpeech() async {
        speechPlayback.stop()
        await CppBridge.TTS.shared.stop()
    }

    internal static func ttsStateProto() async throws -> RATTSServiceState {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.TTS.shared.stateProto()
    }

    /// Wrap Float32 PCM in a WAV container using the commons audio utility.
    private static func convertPCMToWAV(pcmData: Data, sampleRate: Int32) throws -> Data {
        guard !pcmData.isEmpty else { return Data() }

        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize = 0

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
            throw SDKException(
                code: .processingFailed,
                message: "Failed to convert PCM to WAV: \(result)",
                category: .component
            )
        }

        let wavData = Data(bytes: ptr, count: wavSize)
        rac_free(ptr)
        return wavData
    }
}
