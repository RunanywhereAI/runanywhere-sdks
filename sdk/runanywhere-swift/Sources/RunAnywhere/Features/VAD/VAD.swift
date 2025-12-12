//
//  VAD.swift
//  RunAnywhere SDK
//
//  Public entry point for the Voice Activity Detection capability
//

@preconcurrency import AVFoundation
import Foundation

/// Public entry point for the Voice Activity Detection capability
/// Provides simplified access to VAD operations
@MainActor
public final class VAD {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = VAD()

    // MARK: - Properties

    private var vadService: VADService?
    private let logger = SDKLogger(category: "VAD")
    private var configuration: VADConfiguration

    /// Whether the VAD is currently initialized and ready
    public var isReady: Bool {
        vadService != nil
    }

    /// Whether speech is currently active
    public var isSpeechActive: Bool {
        vadService?.isSpeechActive ?? false
    }

    /// Current energy threshold
    public var energyThreshold: Float {
        get { vadService?.energyThreshold ?? configuration.energyThreshold }
        set { vadService?.energyThreshold = newValue }
    }

    // MARK: - Initialization

    /// Initialize with default configuration
    public convenience init() {
        self.init(configuration: VADConfiguration())
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The VAD configuration to use
    public init(configuration: VADConfiguration) {
        self.configuration = configuration
        logger.debug("VAD initialized with configuration")
    }

    /// Initialize with custom service (for testing or customization)
    /// - Parameter service: The VAD service to use
    internal init(service: VADService) {
        self.vadService = service
        self.configuration = VADConfiguration()
        logger.debug("VAD initialized with custom service")
    }

    // MARK: - Public API

    /// Access the underlying VAD service
    /// Provides low-level operations if needed
    public var service: VADService? {
        return vadService
    }

    /// Initialize the VAD service
    /// Must be called before using VAD operations
    public func initialize() async throws {
        logger.info("Initializing VAD")

        let service = DefaultVADService(configuration: configuration)
        try await service.initialize()

        self.vadService = service
        logger.info("VAD initialized successfully")
    }

    /// Initialize with specific configuration
    /// - Parameter configuration: The VAD configuration
    public func initialize(with configuration: VADConfiguration) async throws {
        self.configuration = configuration
        try await initialize()
    }

    // MARK: - Convenience Methods

    /// Detect speech in audio buffer
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    /// - Returns: VADOutput with detection result
    public func detectSpeech(in buffer: AVAudioPCMBuffer) throws -> VADOutput {
        guard let service = vadService else {
            throw VADError.notInitialized
        }

        service.processAudioBuffer(buffer)

        return VADOutput(
            isSpeechDetected: service.isSpeechActive,
            energyLevel: service.energyThreshold
        )
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Array of Float audio samples
    /// - Returns: VADOutput with detection result
    public func detectSpeech(in samples: [Float]) throws -> VADOutput {
        guard let service = vadService else {
            throw VADError.notInitialized
        }

        let isSpeechDetected = service.processAudioData(samples)

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: service.energyThreshold
        )
    }

    /// Process VAD input (supports both buffer and samples)
    /// - Parameter input: The VAD input to process
    /// - Returns: VADOutput with detection result
    public func process(_ input: VADInput) throws -> VADOutput {
        try input.validate()

        // Apply threshold override if provided
        if let threshold = input.energyThresholdOverride {
            vadService?.energyThreshold = threshold
        }

        // Process based on input type
        if let buffer = input.buffer {
            return try detectSpeech(in: buffer)
        } else if let samples = input.audioSamples {
            return try detectSpeech(in: samples)
        } else {
            throw VADError.invalidInput(reason: "VADInput must contain either buffer or audioSamples")
        }
    }

    /// Start VAD processing
    public func start() {
        logger.info("Starting VAD")
        vadService?.start()
    }

    /// Stop VAD processing
    public func stop() {
        logger.info("Stopping VAD")
        vadService?.stop()
    }

    /// Reset VAD state
    public func reset() {
        logger.info("Resetting VAD")
        vadService?.reset()
    }

    /// Pause VAD processing
    public func pause() {
        logger.info("Pausing VAD")
        vadService?.pause()
    }

    /// Resume VAD processing
    public func resume() {
        logger.info("Resuming VAD")
        vadService?.resume()
    }

    /// Set speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        vadService?.onSpeechActivity = callback
    }

    /// Set audio buffer callback
    /// - Parameter callback: Callback invoked for processed audio buffers
    public func setAudioBufferCallback(_ callback: @escaping (Data) -> Void) {
        vadService?.onAudioBuffer = callback
    }

    // MARK: - Calibration

    /// Start calibration to measure ambient noise
    public func startCalibration() async throws {
        guard let service = vadService as? SimpleEnergyVADService else {
            throw VADError.serviceNotAvailable
        }

        logger.info("Starting VAD calibration")
        await service.startCalibration()
    }

    /// Set calibration parameters
    /// - Parameter multiplier: Threshold multiplier (1.5 to 4.0)
    public func setCalibrationParameters(multiplier: Float) {
        guard let service = vadService as? SimpleEnergyVADService else {
            return
        }

        service.setCalibrationParameters(multiplier: multiplier)
    }

    // MARK: - Statistics

    /// Get current VAD statistics for debugging
    /// - Returns: VADStatistics with current state
    public func getStatistics() -> VADStatistics? {
        guard let service = vadService as? SimpleEnergyVADService else {
            return nil
        }

        return service.getStatistics()
    }

    // MARK: - TTS Integration

    /// Notify VAD that TTS is about to start
    public func notifyTTSWillStart() {
        guard let service = vadService as? SimpleEnergyVADService else {
            return
        }

        service.notifyTTSWillStart()
    }

    /// Notify VAD that TTS has finished
    public func notifyTTSDidFinish() {
        guard let service = vadService as? SimpleEnergyVADService else {
            return
        }

        service.notifyTTSDidFinish()
    }

    /// Set TTS threshold multiplier
    /// - Parameter multiplier: Multiplier to apply during TTS (2.0 to 5.0)
    public func setTTSThresholdMultiplier(_ multiplier: Float) {
        guard let service = vadService as? SimpleEnergyVADService else {
            return
        }

        service.setTTSThresholdMultiplier(multiplier)
    }

    // MARK: - Cleanup

    /// Clean up VAD resources
    public func cleanup() async {
        logger.info("Cleaning up VAD")

        if let service = vadService as? DefaultVADService {
            await service.cleanup()
        } else {
            vadService?.stop()
        }

        vadService = nil
    }

    // MARK: - Static Convenience Methods

    /// Initialize VAD with default configuration
    public static func initializeVAD() async throws {
        try await shared.initialize()
    }

    /// Initialize VAD with configuration
    /// - Parameter configuration: The VAD configuration
    public static func initializeVAD(with configuration: VADConfiguration) async throws {
        try await shared.initialize(with: configuration)
    }

    /// Detect speech in buffer using shared instance
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    /// - Returns: VADOutput with detection result
    public static func detectSpeech(in buffer: AVAudioPCMBuffer) throws -> VADOutput {
        try shared.detectSpeech(in: buffer)
    }

    /// Detect speech in samples using shared instance
    /// - Parameter samples: Array of Float audio samples
    /// - Returns: VADOutput with detection result
    public static func detectSpeech(in samples: [Float]) throws -> VADOutput {
        try shared.detectSpeech(in: samples)
    }
}

// MARK: - Additional Methods for Compatibility

extension VAD {
    /// Get the underlying VAD service (for compatibility with component pattern)
    public func getService() -> VADService? {
        return vadService
    }
}
