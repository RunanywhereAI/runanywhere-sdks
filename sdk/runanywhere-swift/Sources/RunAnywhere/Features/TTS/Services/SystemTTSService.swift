//
//  SystemTTSService.swift
//  RunAnywhere SDK
//
//  System TTS Service implementation using AVSpeechSynthesizer
//

import AVFoundation
import Foundation

/// System TTS Service implementation using AVSpeechSynthesizer
///
/// This is the default TTS service that uses Apple's built-in speech synthesis.
/// It supports all iOS/macOS system voices and provides real-time speech playback.
///
/// **Note:** System TTS plays audio directly through speakers. The returned `Data`
/// is a placeholder - use ONNX Piper TTS if you need actual audio data for custom playback.
public final class SystemTTSService: NSObject, TTSService, @unchecked Sendable {

    // MARK: - Framework Identification

    /// System TTS uses Apple's built-in speech synthesis (AVSpeechSynthesizer)
    public let inferenceFramework: InferenceFrameworkType = .builtIn

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")
    private var speechContinuation: CheckedContinuation<Data, Error>?
    private var _isSynthesizing = false
    private let lock = NSLock()

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService Protocol

    public func initialize() async throws {
        logger.info("System TTS initialized (direct playback mode)")
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        logger.info("Speaking: '\(text.prefix(50))...'")

        // Create and configure utterance
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        if let voiceId = options.voice, voiceId != "system" && voiceId != "system-tts" {
            if let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                utterance.voice = voice
            } else if let voice = AVSpeechSynthesisVoice(language: voiceId) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            }
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: options.language)
        }

        // Configure speech parameters
        utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        // Use speak() for direct playback - waits for completion via delegate
        return try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            self.speechContinuation = continuation
            self._isSynthesizing = true
            self.lock.unlock()

            // Speak on main thread (required by AVSpeechSynthesizer)
            DispatchQueue.main.async {
                self.synthesizer.speak(utterance)
            }
        }
    }

    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // System TTS doesn't support streaming - just synthesize and signal completion
        _ = try await synthesize(text: text, options: options)
        onChunk(Data()) // Signal completion
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lock.lock()
        _isSynthesizing = false
        // Resume with empty data if waiting
        speechContinuation?.resume(returning: Data())
        speechContinuation = nil
        lock.unlock()
    }

    public var isSynthesizing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSynthesizing || synthesizer.isSpeaking
    }

    public var availableVoices: [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.identifier }
    }

    public func cleanup() async {
        stop()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.info("Speech playback completed")
        lock.lock()
        _isSynthesizing = false
        // Return empty data - audio was played directly through speakers
        speechContinuation?.resume(returning: Data())
        speechContinuation = nil
        lock.unlock()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        logger.info("Speech playback cancelled")
        lock.lock()
        _isSynthesizing = false
        speechContinuation?.resume(throwing: CancellationError())
        speechContinuation = nil
        lock.unlock()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.info("Speech playback started")
    }
}
