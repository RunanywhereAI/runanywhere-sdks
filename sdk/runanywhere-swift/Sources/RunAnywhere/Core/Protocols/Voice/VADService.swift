import Foundation

// MARK: - VAD Initialization Parameters

/// Initialization parameters specific to VAD component
public struct VADInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.vad
    public let modelId: String? = nil // VAD typically doesn't use models

    // VAD-specific parameters
    public let energyThreshold: Float
    public let sampleRate: Int
    public let frameLength: Int // in samples
    public let bufferSize: Int // number of frames to buffer
    public let silenceThreshold: Int // frames of silence before speech end

    public init(
        energyThreshold: Float = 0.01,
        sampleRate: Int = 16000,
        frameLength: Int = 320,
        bufferSize: Int = 10,
        silenceThreshold: Int = 10
    ) {
        self.energyThreshold = energyThreshold
        self.sampleRate = sampleRate
        self.frameLength = frameLength
        self.bufferSize = bufferSize
        self.silenceThreshold = silenceThreshold
    }

    public func validate() throws {
        guard energyThreshold >= 0 && energyThreshold <= 1.0 else {
            throw SDKError.validationFailed("Energy threshold must be between 0 and 1.0")
        }
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard frameLength > 0 && frameLength <= sampleRate else {
            throw SDKError.validationFailed("Frame length must be between 1 and sample rate")
        }
    }
}

// MARK: - VAD Service Protocol

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
