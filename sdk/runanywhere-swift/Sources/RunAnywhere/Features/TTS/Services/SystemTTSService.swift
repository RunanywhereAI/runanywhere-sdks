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
public final class SystemTTSService: NSObject, TTSService, @unchecked Sendable {

    // MARK: - Framework Identification

    /// System TTS uses Apple's built-in speech synthesis (AVSpeechSynthesizer)
    public let inferenceFramework: InferenceFrameworkType = .builtIn

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")
    private var speechContinuation: CheckedContinuation<Data, Error>?
    private var _isSynthesizing = false
    private let speechQueue = DispatchQueue(label: "com.runanywhere.tts.speech")

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService Protocol

    public func initialize() async throws {
        // Don't configure audio session here - it's already configured by AudioCapture
        // Trying to change categories causes the '!pri' error
        logger.info("System TTS initialized - using existing audio session configuration")
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // Use proper async handling without forced sync
        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation for delegate callback using async operation
            self.speechQueue.async { [weak self] in
                self?.speechContinuation = continuation
            }

            // Create and configure utterance
            let utterance = AVSpeechUtterance(string: text)

            // Configure voice
            if options.voice == "system" {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            } else if let speechVoice = AVSpeechSynthesisVoice(language: options.voice ?? options.language) {
                utterance.voice = speechVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            }

            // Configure speech parameters
            utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = options.pitch
            utterance.volume = options.volume
            utterance.preUtteranceDelay = 0.0
            utterance.postUtteranceDelay = 0.0

            logger.info("Speaking text: '\(text.prefix(50))...' with voice: \(options.voice ?? options.language)")

            // Speak on main queue (required by AVSpeechSynthesizer)
            DispatchQueue.main.async { [weak self] in
                self?._isSynthesizing = true
                self?.synthesizer.speak(utterance)
            }
        }
    }

    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // System TTS doesn't support true streaming
        // Just synthesize the complete text
        _ = try await synthesize(text: text, options: options)
        onChunk(Data()) // Signal completion with empty data
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(returning: Data())
            self?.speechContinuation = nil
        }
    }

    public var isSynthesizing: Bool {
        synthesizer.isSpeaking
    }

    public var availableVoices: [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.language }
    }

    public func cleanup() async {
        stop()
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
        #endif
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.info("TTS playback completed")
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(returning: Data())
            self?.speechContinuation = nil
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        logger.info("TTS playback cancelled")
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(throwing: CancellationError())
            self?.speechContinuation = nil
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.info("TTS playback started")
        _isSynthesizing = true
    }
}
