//
//  TTSNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.tts` — synthesis and device playback, plus the internal
//  proto-level helpers the deprecated flat verbs share.
//

import CRACommons
import Foundation
import os

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
                        if output.hasError {
                            continuation.finish(throwing: SDKException(proto: output.error))
                            return
                        }
                        continuation.yield(AudioChunk(proto: output))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }

        /// Synthesize text and play it through the device speakers, returning a
        /// handle to the utterance immediately — playback continues in the
        /// background. Interrupt it with `handle.interrupt()`.
        ///
        /// ```swift
        /// let handle = try await RunAnywhere.tts.speak("Hello there")
        /// await handle.waitForPlayout()
        /// ```
        ///
        /// - Throws: `SDKException` when no voice is loaded or synthesis fails.
        @discardableResult
        public func speak(_ text: String, options: TtsOptions? = nil) async throws -> SpeechHandle {
            try await RunAnywhere.speakAndTrack(
                text: text,
                options: (options ?? TtsOptions()).toProto()
            )
        }

        /// Interrupt the latest active speech handle, if one exists.
        @available(*, deprecated, message: "Use the SpeechHandle returned by speak(_:options:) to interrupt one utterance")
        public func stop() async {
            if let handle = RunAnywhere.activeSpeechHandleSnapshot() {
                await handle.interrupt()
            } else {
                await RunAnywhere.stopSpeech()
            }
        }

        /// List the voices the loaded engine can speak with.
        ///
        /// `RATTSServiceState.voices` was reserved off the wire outright
        /// (idl/tts_options.proto): available voices now come from the
        /// dedicated `rac_tts_list_voices_lifecycle_proto` verb.
        ///
        /// - Throws: `SDKException` when the SDK has not been initialized.
        public func voices() async throws -> [Voice] {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()
            return try await CppBridge.TTS.shared.listVoicesProto().voices
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    /// Playback manager shared by `tts.speak` and the deprecated `speak`.
    private static let speechPlayback = AudioPlaybackManager()

    /// The most recently returned `SpeechHandle`, tracked so the deprecated
    /// `tts.stop()` and `VoiceSession.interrupt()` have something to interrupt.
    private static let activeSpeechHandleBox = OSAllocatedUnfairLock<SpeechHandle?>(initialState: nil)

    internal static func setActiveSpeechHandle(_ handle: SpeechHandle) {
        activeSpeechHandleBox.withLock { $0 = handle }
    }

    internal static func activeSpeechHandleSnapshot() -> SpeechHandle? {
        activeSpeechHandleBox.withLock { $0 }
    }

    /// Synthesize `text`, start device playback, and return a `SpeechHandle`
    /// immediately — playback continues in the background and completes the
    /// handle when it finishes, is interrupted, or fails.
    internal static func speakAndTrack(text: String, options: RATTSOptions) async throws -> SpeechHandle {
        // The handle is published BEFORE synthesis, not after it. A neural
        // voice takes seconds to synthesize, and while it did there was no
        // handle for this utterance: `tts.stop()` and `VoiceSession.interrupt()`
        // resolve their target through `activeSpeechHandleSnapshot()`, which
        // still held the *previous*, already-finished utterance. A Stop pressed
        // during synthesis therefore interrupted a dead handle, this utterance
        // went on to play in full, and the caller had already been told it was
        // over. Registering first makes the whole utterance interruptible,
        // synthesis included.
        let handle = SpeechHandle(interruptHandler: {
            await RunAnywhere.stopSpeech()
        })
        setActiveSpeechHandle(handle)

        let wavData: Data
        do {
            let output = try await synthesizeProto(text: text, options: options)
            let sampleRate = output.sampleRate > 0 ? output.sampleRate : options.sampleRate
            let wavSampleRate = sampleRate > 0 ? sampleRate : Int32(RADefaults.AudioCapture.ttsSampleRateHz)
            wavData = try convertPCMToWAV(pcmData: output.audioData, sampleRate: wavSampleRate)
        } catch {
            // The handle is already visible to interrupters and may have
            // `waitForPlayout()` waiters, so it has to be resolved before the
            // error leaves this function.
            handle.complete(error: error)
            throw error
        }

        // An interrupt that landed while the engine was synthesizing must not be
        // overtaken by the audio it was meant to cancel.
        guard !handle.interrupted, !wavData.isEmpty else {
            handle.complete()
            return handle
        }

        speechPlayback.play(wavData) { _ in
            // `false` covers both a genuine playback failure and a deliberate
            // interrupt(); `handle.interrupted` already distinguishes the two,
            // so no synthetic error is attached here.
            handle.complete()
        }
        // `play` starts the player synchronously, so an interrupt that arrived
        // between the guard above and this line would have stopped a player
        // that did not exist yet. Re-checking here closes that window; `stop()`
        // is a no-op when nothing is playing.
        if handle.interrupted {
            speechPlayback.stop()
        }
        return handle
    }

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
