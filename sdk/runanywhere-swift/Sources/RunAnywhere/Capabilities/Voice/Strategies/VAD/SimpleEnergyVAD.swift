import Foundation
import AVFoundation
import Accelerate
import os

/// Simple energy-based Voice Activity Detection
/// Based on WhisperKit's EnergyVAD implementation but simplified for real-time audio processing
public class SimpleEnergyVAD: NSObject, VADService {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "SimpleEnergyVAD")

    /// Energy threshold for voice activity detection (0.0 to 1.0)
    /// Values above this threshold indicate voice activity
    public var energyThreshold: Float = 0.022

    /// Sample rate of the audio (typically 16000 Hz)
    public let sampleRate: Int

    /// Length of each analysis frame in samples
    public let frameLengthSamples: Int

    /// Speech activity callback
    public var onSpeechActivity: ((SpeechActivityEvent) -> Void)?

    /// Optional callback for processed audio buffers
    public var onAudioBuffer: ((Data) -> Void)?

    // State tracking
    private var isActive = false
    private var isCurrentlySpeaking = false
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0

    // Hysteresis parameters to prevent rapid on/off switching
    private let voiceStartThreshold = 2  // frames of voice to start
    private let voiceEndThreshold = 10   // frames of silence to end

    // MARK: - Initialization

    /// Initialize the VAD with specified parameters
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (default: 16000)
    ///   - frameLength: Frame length in seconds (default: 0.1 = 100ms)
    ///   - energyThreshold: Energy threshold for voice detection (default: 0.022)
    public init(
        sampleRate: Int = 16000,
        frameLength: Float = 0.1,
        energyThreshold: Float = 0.022
    ) {
        self.sampleRate = sampleRate
        self.frameLengthSamples = Int(frameLength * Float(sampleRate))
        self.energyThreshold = energyThreshold
        super.init()

        logger.info("SimpleEnergyVAD initialized - sampleRate: \(sampleRate), frameLength: \(self.frameLengthSamples) samples, threshold: \(energyThreshold)")
    }

    // MARK: - VADService Protocol Implementation

    /// Initialize the VAD service
    public func initialize() async throws {
        start()
    }

    /// Current speech activity state
    public var isSpeechActive: Bool {
        return isCurrentlySpeaking
    }

    /// Frame length in seconds
    public var frameLength: Float {
        return Float(frameLengthSamples) / Float(sampleRate)
    }

    /// Reset the VAD state
    public func reset() {
        stop()
        isCurrentlySpeaking = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
    }

    // MARK: - Public Methods

    /// Start voice activity detection
    public func start() {
        guard !isActive else { return }

        isActive = true
        isCurrentlySpeaking = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0

        logger.info("SimpleEnergyVAD started")
    }

    /// Stop voice activity detection
    public func stop() {
        guard isActive else { return }

        // If currently speaking, send end event
        if isCurrentlySpeaking {
            isCurrentlySpeaking = false
            logger.info("🎙️ VAD: SPEECH ENDED (stopped)")
            onSpeechActivity?(.ended)
        }

        isActive = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0

        logger.info("SimpleEnergyVAD stopped")
    }

    /// Process an audio buffer for voice activity detection
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isActive else { return }

        // Convert buffer to float array
        let audioData = convertBufferToFloatArray(buffer)
        guard !audioData.isEmpty else { return }

        // Calculate energy of the entire buffer
        let energy = calculateAverageEnergy(of: audioData)
        let hasVoice = energy > energyThreshold

        logger.debug("Audio buffer: \(audioData.count) samples, energy: \(String(format: "%.6f", energy)), threshold: \(self.energyThreshold), hasVoice: \(hasVoice)")

        // Update state based on voice detection
        updateVoiceActivityState(hasVoice: hasVoice)

        // Call audio buffer callback if provided
        if let audioData = bufferToData(buffer) {
            onAudioBuffer?(audioData)
        }
    }

    /// Process a raw audio array for voice activity detection
    /// - Parameter audioData: Array of Float audio samples
    /// - Returns: Whether speech is detected in current frame
    @discardableResult
    public func processAudioData(_ audioData: [Float]) -> Bool {
        guard isActive else { return false }
        guard !audioData.isEmpty else { return false }

        // Calculate energy
        let energy = calculateAverageEnergy(of: audioData)
        let hasVoice = energy > energyThreshold

        // Log with threshold comparison for debugging
        logger.debug("VAD: \(audioData.count) samples, energy: \(String(format: "%.6f", energy)) \(hasVoice ? ">" : "≤") threshold: \(String(format: "%.6f", self.energyThreshold)), voice: \(hasVoice ? "YES" : "no")")

        // Update state
        updateVoiceActivityState(hasVoice: hasVoice)

        return hasVoice
    }

    // MARK: - Private Methods

    /// Calculate the RMS (Root Mean Square) energy of an audio signal
    /// - Parameter signal: Array of audio samples
    /// - Returns: RMS energy value
    private func calculateAverageEnergy(of signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0.0 }

        var rmsEnergy: Float = 0.0
        vDSP_rmsqv(signal, 1, &rmsEnergy, vDSP_Length(signal.count))
        return rmsEnergy
    }

    /// Update voice activity state with hysteresis to prevent rapid switching
    /// - Parameter hasVoice: Whether voice was detected in current frame
    private func updateVoiceActivityState(hasVoice: Bool) {
        if hasVoice {
            consecutiveVoiceFrames += 1
            consecutiveSilentFrames = 0

            // Start speaking if we have enough consecutive voice frames
            if !isCurrentlySpeaking && consecutiveVoiceFrames >= voiceStartThreshold {
                isCurrentlySpeaking = true
                logger.info("🎙️ VAD: SPEECH STARTED (energy above threshold for \(self.consecutiveVoiceFrames) frames)")
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechActivity?(.started)
                }
            }
        } else {
            consecutiveSilentFrames += 1
            consecutiveVoiceFrames = 0

            // Stop speaking if we have enough consecutive silent frames
            if isCurrentlySpeaking && consecutiveSilentFrames >= voiceEndThreshold {
                isCurrentlySpeaking = false
                logger.info("🎙️ VAD: SPEECH ENDED (silence for \(self.consecutiveSilentFrames) frames)")
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechActivity?(.ended)
                }
            }
        }
    }

    /// Convert AVAudioPCMBuffer to Float array
    /// - Parameter buffer: Audio buffer to convert
    /// - Returns: Array of Float audio samples
    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let samples = channelData.pointee

        return Array(UnsafeBufferPointer(start: samples, count: frameLength))
    }

    /// Convert audio buffer to Data for callback
    /// - Parameter buffer: Audio buffer to convert
    /// - Returns: Data representation of audio samples
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer<Float>(
            start: channelDataValue,
            count: channelDataCount
        ))

        return samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }
}
