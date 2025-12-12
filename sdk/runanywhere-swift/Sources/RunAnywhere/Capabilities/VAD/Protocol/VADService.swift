//
//  VADService.swift
//  RunAnywhere SDK
//
//  Protocol defining Voice Activity Detection service capabilities
//

@preconcurrency import AVFoundation
import Foundation

/// Protocol defining Voice Activity Detection service capabilities
public protocol VADService: AnyObject { // swiftlint:disable:this avoid_any_object
    /// Energy threshold for voice detection (0.0 to 1.0)
    var energyThreshold: Float { get set }

    /// Sample rate of the audio in Hz
    var sampleRate: Int { get }

    /// Frame length in seconds
    var frameLength: Float { get }

    /// Whether speech is currently active
    var isSpeechActive: Bool { get }

    /// Speech activity callback
    var onSpeechActivity: ((SpeechActivityEvent) -> Void)? { get set }

    /// Audio buffer callback for processed audio
    var onAudioBuffer: ((Data) -> Void)? { get set }

    // MARK: - Lifecycle

    /// Initialize the VAD service
    func initialize() async throws

    /// Start VAD processing
    func start()

    /// Stop VAD processing
    func stop()

    /// Reset VAD state
    func reset()

    // MARK: - Processing

    /// Process audio buffer for voice activity detection
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)

    /// Process audio samples for voice activity detection
    /// - Parameter audioData: Array of Float audio samples
    /// - Returns: Whether speech is detected in current frame
    @discardableResult
    func processAudioData(_ audioData: [Float]) -> Bool

    // MARK: - Pause/Resume

    /// Pause VAD processing (optional, not all implementations may support)
    func pause()

    /// Resume VAD processing (optional, not all implementations may support)
    func resume()
}

// MARK: - Default Implementations

/// Extension with default implementations for optional methods
public extension VADService {
    /// Default implementation does nothing
    func pause() {}

    /// Default implementation does nothing
    func resume() {}
}
