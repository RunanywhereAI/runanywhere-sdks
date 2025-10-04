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
    private let voiceEndThreshold = 5   // frames of silence to end (0.5 seconds at 100ms frames) - balanced for continuity

    // Calibration properties
    private var isCalibrating = false
    private var calibrationSamples: [Float] = []
    private var calibrationFrameCount = 0
    private let calibrationFramesNeeded = 20  // ~2 seconds at 100ms frames
    private var ambientNoiseLevel: Float = 0.0
    private var calibrationMultiplier: Float = 4.0  // Threshold = ambientNoise * multiplier - lower for better speech detection

    // Debug statistics
    private var recentEnergyValues: [Float] = []
    private let maxRecentValues = 50
    private var debugFrameCount = 0

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
        // Start automatic calibration
        await startCalibration()
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

        // Update debug statistics
        updateDebugStatistics(energy: energy)

        // Handle calibration if active
        if isCalibrating {
            handleCalibrationFrame(energy: energy)
            return  // Don't process voice activity during calibration
        }

        let hasVoice = energy > energyThreshold

        // Enhanced logging with more context
        let energyStr = String(format: "%.6f", energy)
        let thresholdStr = String(format: "%.6f", energyThreshold)
        let percentAboveThreshold = ((energy - energyThreshold) / energyThreshold) * 100

        if debugFrameCount % 10 == 0 {  // Log every 10th frame to reduce noise
            let avgRecent = recentEnergyValues.isEmpty ? 0 : recentEnergyValues.reduce(0, +) / Float(recentEnergyValues.count)
            let maxRecent = recentEnergyValues.max() ?? 0
            let minRecent = recentEnergyValues.min() ?? 0

            logger.info("📊 VAD Stats - Current: \(energyStr) | Threshold: \(thresholdStr) | Voice: \(hasVoice ? "✅" : "❌") | %Above: \(String(format: "%.1f%%", percentAboveThreshold)) | Avg: \(String(format: "%.6f", avgRecent)) | Range: [\(String(format: "%.6f", minRecent))-\(String(format: "%.6f", maxRecent))]")
        }
        debugFrameCount += 1

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

        // Update debug statistics
        updateDebugStatistics(energy: energy)

        // Handle calibration if active
        if isCalibrating {
            handleCalibrationFrame(energy: energy)
            return false  // Don't process voice activity during calibration
        }

        let hasVoice = energy > energyThreshold

        // Enhanced debug logging
        let ratio = energy / energyThreshold
        logger.debug("🎤 VAD: Energy=\(String(format: "%.6f", energy)) | Threshold=\(String(format: "%.6f", self.energyThreshold)) | Ratio=\(String(format: "%.2fx", ratio)) | Voice=\(hasVoice ? "YES✅" : "NO❌") | Ambient=\(String(format: "%.6f", self.ambientNoiseLevel))")

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

    // MARK: - Calibration Methods

    /// Start automatic calibration to determine ambient noise level
    public func startCalibration() async {
        logger.info("🎯 Starting VAD calibration - measuring ambient noise for \(Float(self.calibrationFramesNeeded) * self.frameLength) seconds...")

        isCalibrating = true
        calibrationSamples.removeAll()
        calibrationFrameCount = 0

        // Wait for calibration to complete (this is a simplified approach)
        // In production, you'd want a more sophisticated async approach
        let timeoutSeconds = Float(calibrationFramesNeeded) * frameLength + 2.0
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))

        if isCalibrating {
            // Force complete calibration if still running
            completeCalibration()
        }
    }

    /// Handle a frame during calibration
    private func handleCalibrationFrame(energy: Float) {
        guard isCalibrating else { return }

        calibrationSamples.append(energy)
        calibrationFrameCount += 1

        logger.debug("📏 Calibration frame \(self.calibrationFrameCount)/\(self.calibrationFramesNeeded): energy=\(String(format: "%.6f", energy))")

        if calibrationFrameCount >= calibrationFramesNeeded {
            completeCalibration()
        }
    }

    /// Complete the calibration process
    private func completeCalibration() {
        guard isCalibrating, !calibrationSamples.isEmpty else { return }

        // Calculate statistics from calibration samples
        let sortedSamples = calibrationSamples.sorted()
        let mean = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
        let median = sortedSamples[sortedSamples.count / 2]
        let percentile75 = sortedSamples[min(sortedSamples.count - 1, Int(Float(sortedSamples.count) * 0.75))]
        let percentile90 = sortedSamples[min(sortedSamples.count - 1, Int(Float(sortedSamples.count) * 0.90))]
        let max = sortedSamples.last ?? 0

        // Use 90th percentile as ambient noise level (robust to occasional spikes)
        ambientNoiseLevel = percentile90

        // Calculate dynamic threshold with better minimum
        let oldThreshold = energyThreshold
        // Ensure minimum threshold is high enough to avoid false positives
        // but low enough to detect actual speech
        let minimumThreshold: Float = 0.008  // Balanced for better speech detection
        let calculatedThreshold = ambientNoiseLevel * calibrationMultiplier

        // Apply threshold with sensible bounds
        energyThreshold = Swift.max(calculatedThreshold, minimumThreshold)

        // Cap at reasonable maximum
        if energyThreshold > 0.05 {
            energyThreshold = 0.05
            logger.warning("⚠️ Calibration detected high ambient noise. Capping threshold at 0.05")
        }

        logger.info("✅ VAD Calibration Complete:")
        logger.info("  📊 Statistics: Mean=\(String(format: "%.6f", mean)), Median=\(String(format: "%.6f", median))")
        logger.info("  📊 Percentiles: 75th=\(String(format: "%.6f", percentile75)), 90th=\(String(format: "%.6f", percentile90)), Max=\(String(format: "%.6f", max))")
        logger.info("  🎯 Ambient Noise Level: \(String(format: "%.6f", self.ambientNoiseLevel))")
        logger.info("  🔧 Threshold: \(String(format: "%.6f", oldThreshold)) → \(String(format: "%.6f", self.energyThreshold))")

        isCalibrating = false
        calibrationSamples.removeAll()
    }

    /// Manually set calibration parameters
    public func setCalibrationParameters(multiplier: Float = 4.0) {
        calibrationMultiplier = Swift.max(3.0, Swift.min(8.0, multiplier))  // Clamp between 3x and 8x for better speech detection
        logger.info("📝 Calibration multiplier set to \(self.calibrationMultiplier)x")
    }

    /// Get current VAD statistics for debugging
    public func getStatistics() -> (current: Float, threshold: Float, ambient: Float, recentAvg: Float, recentMax: Float) {
        let recent = recentEnergyValues.isEmpty ? 0 : recentEnergyValues.reduce(0, +) / Float(recentEnergyValues.count)
        let maxValue = recentEnergyValues.max() ?? 0
        let current = recentEnergyValues.last ?? 0

        return (current: current, threshold: energyThreshold, ambient: ambientNoiseLevel, recentAvg: recent, recentMax: maxValue)
    }

    // MARK: - Debug Helpers

    /// Update debug statistics with new energy value
    private func updateDebugStatistics(energy: Float) {
        recentEnergyValues.append(energy)
        if recentEnergyValues.count > maxRecentValues {
            recentEnergyValues.removeFirst()
        }
    }
}
