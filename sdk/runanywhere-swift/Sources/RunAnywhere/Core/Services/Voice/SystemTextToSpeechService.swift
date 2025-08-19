import Foundation
import AVFoundation
import os

/// System TTS Service implementation for SDK
public final class SystemTextToSpeechService: NSObject, TextToSpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "SystemTTS")
    private var completionHandler: (() -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TextToSpeechService Protocol

    public func initialize() async throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Configure audio session for playback on iOS/tvOS/watchOS
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        logger.info("System TTS initialized with playback configuration")
        #else
        // On macOS, no audio session configuration needed
        logger.info("System TTS initialized")
        #endif
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // For system TTS, we can't easily get raw audio data
        // Instead, we'll play it directly and return empty data
        try await speak(text: text, options: options)
        return Data()
    }

    public func speak(text: String, options: TTSOptions) async throws {
        await withCheckedContinuation { continuation in
            completionHandler = {
                continuation.resume()
            }

            let utterance = AVSpeechUtterance(string: text)

            // Configure voice
            let voiceLanguage = options.voice ?? options.language
            if let speechVoice = AVSpeechSynthesisVoice(language: voiceLanguage) {
                utterance.voice = speechVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            }

            // Configure speech parameters
            utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = options.pitch
            utterance.volume = options.volume

            logger.info("Speaking text: '\(text.prefix(50))...' with voice: \(options.voice ?? options.language)")
            synthesizer.speak(utterance)
        }
    }

    public func synthesizeStream(text: String, options: TTSOptions) -> AsyncThrowingStream<VoiceAudioChunk, Error> {
        // System TTS doesn't support true streaming
        // Use default implementation that returns complete audio at once
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For system TTS, we can't get raw audio, so we'll just signal completion
                    try await speak(text: text, options: options)

                    // Return empty chunk to signal completion
                    let chunk = VoiceAudioChunk(
                        samples: [],
                        timestamp: Date().timeIntervalSince1970,
                        sampleRate: options.sampleRate,
                        channels: 1,
                        sequenceNumber: 0,
                        isFinal: true
                    )
                    continuation.yield(chunk)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler?()
        completionHandler = nil
    }

    public func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    public func resume() {
        synthesizer.continueSpeaking()
    }

    public var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    public var isPaused: Bool {
        synthesizer.isPaused
    }

    public var availableVoices: [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            VoiceInfo(
                id: voice.language,
                name: voice.name,
                language: voice.language,
                gender: determineGender(from: voice),
                ageGroup: .adult,
                quality: voice.quality == .enhanced ? .high : .standard,
                isNeural: voice.quality == .enhanced
            )
        }
    }

    public var currentVoice: VoiceInfo? {
        get { nil }
        set { /* System TTS doesn't maintain current voice state */ }
    }

    public var supportsStreaming: Bool { false }

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

    // MARK: - Private Methods

    private func determineGender(from voice: AVSpeechSynthesisVoice) -> VoiceGender {
        let name = voice.name.lowercased()
        if name.contains("female") || name.contains("woman") || name.contains("girl") {
            return .female
        } else if name.contains("male") || name.contains("man") || name.contains("boy") {
            return .male
        }
        return .neutral
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTextToSpeechService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.info("TTS playback completed")
        completionHandler?()
        completionHandler = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        logger.info("TTS playback cancelled")
        completionHandler?()
        completionHandler = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.info("TTS playback started")
    }
}
