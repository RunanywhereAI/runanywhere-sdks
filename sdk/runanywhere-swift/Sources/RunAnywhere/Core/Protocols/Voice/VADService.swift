import Foundation

/// Protocol for Voice Activity Detection services
public protocol VADService: AnyObject {
    /// Initialize the VAD service
    func initialize() async throws

    /// Process audio data for voice activity detection
    /// - Parameter audioData: Array of audio samples (Float)
    /// - Returns: Whether speech is detected
    func processAudioData(_ audioData: [Float]) -> Bool

    /// Reset the VAD state
    func reset()

    /// Set callback for speech activity events
    var onSpeechActivity: ((SpeechActivityEvent) -> Void)? { get set }

    /// Current speech activity state
    var isSpeechActive: Bool { get }

    /// Configuration parameters
    var energyThreshold: Float { get set }
    var sampleRate: Int { get }
    var frameLength: Float { get }
}

/// Speech activity events
public enum SpeechActivityEvent {
    case started
    case ended
}
