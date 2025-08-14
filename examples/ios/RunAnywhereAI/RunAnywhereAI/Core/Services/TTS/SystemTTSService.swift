import AVFoundation
import Foundation

@MainActor
public class SystemTTSService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(text: String, voice: String? = "en-US") async {
        await withCheckedContinuation { continuation in
            completionHandler = {
                continuation.resume()
            }

            let utterance = AVSpeechUtterance(string: text)

            if let voiceLanguage = voice,
               let speechVoice = AVSpeechSynthesisVoice(language: voiceLanguage) {
                utterance.voice = speechVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }

            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0

            synthesizer.speak(utterance)
        }
    }

    public func speak(
        text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        voice: String? = "en-US"
    ) async {
        await withCheckedContinuation { continuation in
            completionHandler = {
                continuation.resume()
            }

            let utterance = AVSpeechUtterance(string: text)

            if let voiceLanguage = voice,
               let speechVoice = AVSpeechSynthesisVoice(language: voiceLanguage) {
                utterance.voice = speechVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }

            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.volume = volume

            synthesizer.speak(utterance)
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

    public func continueSpeaking() {
        synthesizer.continueSpeaking()
    }

    public var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    public var isPaused: Bool {
        synthesizer.isPaused
    }

    public func getAvailableVoices() -> [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.language }
    }

    public func getVoiceForLanguage(_ language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: @preconcurrency AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            completionHandler?()
            completionHandler = nil
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            completionHandler?()
            completionHandler = nil
        }
    }
}

// MARK: - TTS Configuration

public struct TTSConfiguration {
    public var voice: String
    public var rate: Float
    public var pitch: Float
    public var volume: Float

    public init(
        voice: String = "en-US",
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0
    ) {
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }

    public static let `default` = TTSConfiguration()

    public static let fast = TTSConfiguration(rate: AVSpeechUtteranceMaximumSpeechRate * 0.6)

    public static let slow = TTSConfiguration(rate: AVSpeechUtteranceMinimumSpeechRate * 2.0)
}

// MARK: - TTS Error

public enum TTSError: LocalizedError {
    case synthesisInProgress
    case voiceNotAvailable(String)
    case textTooLong

    public var errorDescription: String? {
        switch self {
        case .synthesisInProgress:
            return "Speech synthesis is already in progress"
        case .voiceNotAvailable(let voice):
            return "Voice not available: \(voice)"
        case .textTooLong:
            return "Text is too long for synthesis"
        }
    }
}
