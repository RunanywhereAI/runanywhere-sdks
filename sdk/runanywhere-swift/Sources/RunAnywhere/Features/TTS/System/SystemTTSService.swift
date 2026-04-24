//
//  SystemTTSService.swift
//  RunAnywhere SDK
//
//  System TTS Service implementation using AVSpeechSynthesizer
//  Fully isolated from Swift async context to avoid AVFoundation conflicts
//

import AVFoundation
import Foundation

// MARK: - System TTS Service

/// System TTS Service implementation using AVSpeechSynthesizer.
///
/// Apple's `AVSpeechSynthesizer` synthesizes and plays directly through the
/// system audio output; it does not expose a way to obtain raw PCM for
/// arbitrary text. Because of that, this service intentionally only supports
/// playback via `speak(...)` — consumers that need raw audio samples should
/// use the ONNX Piper TTS service instead.
///
/// **Concurrency:** This service uses `Task.detached` to completely isolate
/// AVFoundation operations from Swift's async runtime, avoiding
/// "unsafeForcedSync" warnings.
@MainActor
public final class SystemTTSService: NSObject {

    // MARK: - Framework Identification

    public nonisolated let inferenceFramework: InferenceFramework = .systemTTS

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")

    /// Completion handler for current speech operation
    private var speechCompletion: ((Result<Void, Error>) -> Void)?

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTS Operations

    public nonisolated func initialize() async throws {
        await MainActor.run {
            logger.info("System TTS initialized (direct playback mode)")
        }
    }

    /// Speak `text` through the system audio output and return when playback
    /// finishes. Throws `CancellationError` if playback is cancelled via
    /// `stop()`.
    public nonisolated func speak(text: String, options: TTSOptions) async throws {
        // Use Task.detached to completely break out of any async context
        // This prevents AVFoundation's internal sync operations from conflicting with Swift concurrency
        try await Task.detached { @MainActor [self] in
            logger.info("Speaking: '\(text.prefix(50))...'")

            // The audio session may still be in .record mode from the Voice Agent's
            // audio capture phase. Switch to .playback so AVSpeechSynthesizer can
            // actually route audio to the speaker.
            #if os(iOS) || os(tvOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
            #endif

            let utterance = createUtterance(text: text, options: options)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // We're already on MainActor, so this is safe
                speechCompletion = { result in
                    continuation.resume(with: result)
                }
                synthesizer.speak(utterance)
            }
        }.value
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speechCompletion?(.success(()))
        speechCompletion = nil
    }

    public nonisolated var isSynthesizing: Bool {
        // Access synthesizer state - this is thread-safe for reading
        synthesizer.isSpeaking
    }

    public nonisolated var availableVoices: [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.identifier }
    }

    public nonisolated func cleanup() async {
        await MainActor.run {
            stop()
        }
    }

    // MARK: - Private Helpers

    private func createUtterance(text: String, options: TTSOptions) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        utterance.voice = resolveVoice(options: options)

        // Configure speech parameters
        utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        return utterance
    }

    private func resolveVoice(options: TTSOptions) -> AVSpeechSynthesisVoice? {
        guard let voiceId = options.voice,
              voiceId != "system" && voiceId != "system-tts" else {
            return AVSpeechSynthesisVoice(language: options.language)
        }

        return AVSpeechSynthesisVoice(identifier: voiceId)
            ?? AVSpeechSynthesisVoice(language: voiceId)
            ?? AVSpeechSynthesisVoice(language: options.language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            logger.info("Speech playback completed")
            speechCompletion?(.success(()))
            speechCompletion = nil
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            logger.info("Speech playback cancelled")
            speechCompletion?(.failure(CancellationError()))
            speechCompletion = nil
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            logger.debug("Speech playback started")
        }
    }
}
