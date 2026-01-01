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

/// System TTS Service implementation using AVSpeechSynthesizer
///
/// This is the default TTS service that uses Apple's built-in speech synthesis.
/// It supports all iOS/macOS system voices and provides real-time speech playback.
///
/// **Note:** System TTS plays audio directly through speakers. The returned `Data`
/// is a placeholder - use ONNX Piper TTS if you need actual audio data for custom playback.
///
/// **Concurrency:** This service uses `Task.detached` to completely isolate AVFoundation
/// operations from Swift's async runtime, avoiding "unsafeForcedSync" warnings.
@MainActor
public final class SystemTTSService: NSObject, TTSService {

    // MARK: - Framework Identification

    public nonisolated let inferenceFramework: InferenceFramework = .systemTTS

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")

    /// Completion handler for current speech operation
    private var speechCompletion: ((Result<Data, Error>) -> Void)?

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService Protocol

    public nonisolated func initialize() async throws {
        await MainActor.run {
            logger.info("System TTS initialized (direct playback mode)")
        }
    }

    public nonisolated func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // Use Task.detached to completely break out of any async context
        // This prevents AVFoundation's internal sync operations from conflicting with Swift concurrency
        return try await Task.detached { @MainActor [self] in
            logger.info("Speaking: '\(text.prefix(50))...'")

            let utterance = createUtterance(text: text, options: options)

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                // We're already on MainActor, so this is safe
                speechCompletion = { result in
                    switch result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                synthesizer.speak(utterance)
            }
        }.value
    }

    public nonisolated func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // System TTS doesn't support streaming - synthesize and signal completion
        _ = try await synthesize(text: text, options: options)
        onChunk(Data())
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speechCompletion?(.success(Data()))
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
            speechCompletion?(.success(Data()))
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
