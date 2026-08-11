//
//  RunAnywhere+TTS.swift
//  RunAnywhere SDK
//
//  Deprecated flat TTS verbs. The v3 surface is `RunAnywhere.tts`; these
//  forwarders keep the proto-typed shapes they always returned.
//

public extension RunAnywhere {

    /// Synthesize text to speech.
    @available(*, deprecated, renamed: "tts.synthesize(_:options:)")
    static func synthesize(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) async throws -> RATTSOutput {
        try await synthesizeProto(text: text, options: options)
    }

    /// Stream synthesis through a lifecycle-derived native TTS session.
    @available(*, deprecated, renamed: "tts.synthesizeStream(_:options:)")
    static func synthesizeStream(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) -> AsyncStream<RATTSOutput> {
        // Keep the legacy RATTSOptions / AsyncStream<RATTSOutput> surface.
        // `tts.synthesizeStream` is the v3 API (`TtsOptions` →
        // `AsyncThrowingStream<AudioChunk, Error>`); do not forward into it.
        AsyncStream { continuation in
            let task = Task {
                do {
                    let snapshot = try requireTTSVoice()
                    try await ensureServicesReady()
                    var request = RATTSSynthesisRequest()
                    request.text = text
                    request.options = options
                    let outputs = try await CppBridge.TTS.shared.synthesizeSessionStream(
                        request,
                        loadedModel: snapshot
                    )
                    for await output in outputs {
                        if Task.isCancelled { break }
                        continuation.yield(output)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Stop current TTS synthesis.
    @available(*, deprecated, renamed: "tts.stop()")
    static func stopSynthesis() async {
        await CppBridge.TTS.shared.stop()
    }

    /// Current TTS service state from the commons lifecycle.
    @available(*, deprecated, renamed: "tts.voices()")
    static func ttsState() async throws -> RATTSServiceState {
        try await ttsStateProto()
    }

    /// Speak text aloud through the device speakers.
    @available(*, deprecated, renamed: "tts.speak(_:options:)")
    static func speak(
        _ text: String,
        options: RATTSOptions = .defaults()
    ) async throws -> RATTSSpeakResult {
        try await speakProto(text: text, options: options)
    }

    /// Stop current speech playback.
    @available(*, deprecated, renamed: "tts.stop()")
    static func stopSpeaking() async {
        await stopSpeech()
    }
}
