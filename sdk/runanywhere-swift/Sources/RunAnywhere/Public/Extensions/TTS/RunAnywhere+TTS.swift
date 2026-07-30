//
//  RunAnywhere+TTS.swift
//  RunAnywhere SDK
//
//  Deprecated flat TTS verbs. The v3 surface is `RunAnywhere.tts`; these
//  forwarders keep the proto-typed shapes they always returned.
//

import Foundation

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
        AsyncStream { continuation in
            let task = Task {
                guard let snapshot = try? requireTTSVoice() else {
                    continuation.finish()
                    return
                }
                do {
                    try await ensureServicesReady()
                } catch {
                    continuation.finish()
                    return
                }
                var request = RATTSSynthesisRequest()
                request.text = text
                request.options = options
                do {
                    let stream = try await CppBridge.TTS.shared.synthesizeSessionStream(
                        request,
                        loadedModel: snapshot
                    )
                    for await output in stream {
                        if Task.isCancelled { break }
                        continuation.yield(output)
                    }
                } catch {
                    var failure = RATTSOutput()
                    failure.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                    failure.isFinal = true
                    failure.errorMessage = "TTS stream failed: \(error)"
                    continuation.yield(failure)
                }
                continuation.finish()
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
