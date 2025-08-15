import Foundation
import AVFoundation
import RunAnywhereSDK

/// Wrapper for SystemTTSService that conforms to TextToSpeechService protocol
public class SystemTTSServiceWrapper: TextToSpeechService {

    private var systemTTS: SystemTTSService?

    public init() {
        // Initialize will be called later
    }

    public func initialize() async throws {
        // Create SystemTTSService on MainActor
        systemTTS = await MainActor.run {
            SystemTTSService()
        }
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // System TTS doesn't return audio data directly
        // This would require using AVAudioRecorder or similar to capture the output
        // For now, return empty data as a placeholder
        return Data()
    }

    public func speak(text: String, options: TTSOptions) async throws {
        guard let tts = systemTTS else {
            throw TTSError.synthesisInProgress
        }

        await tts.speak(
            text: text,
            rate: options.rate,
            pitch: options.pitch,
            volume: options.volume,
            voice: options.language
        )
    }

    public func stop() {
        Task { @MainActor in
            systemTTS?.stop()
        }
    }

    public func pause() {
        Task { @MainActor in
            systemTTS?.pause()
        }
    }

    public func resume() {
        Task { @MainActor in
            systemTTS?.continueSpeaking()
        }
    }

    public var isSpeaking: Bool {
        // This needs to be accessed on MainActor
        // Return false as default for now
        return false
    }

    public var isPaused: Bool {
        // This needs to be accessed on MainActor
        // Return false as default for now
        return false
    }

    public var availableVoices: [VoiceInfo] {
        // Convert system voices to VoiceInfo
        return []
    }

    public var currentVoice: VoiceInfo? {
        get { nil }
        set { /* Not implemented */ }
    }

    public var supportsStreaming: Bool {
        false
    }

    public func cleanup() async {
        await MainActor.run {
            systemTTS?.stop()
            systemTTS = nil
        }
    }
}
