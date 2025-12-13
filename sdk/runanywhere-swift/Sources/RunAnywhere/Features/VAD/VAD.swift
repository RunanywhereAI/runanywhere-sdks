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

    private var component: VADComponent?
    private let logger = SDKLogger(category: "VAD")

    // MARK: - Initialization

    /// Initialize with default settings
    public init() {
        logger.debug("VAD initialized")
    }

    // MARK: - Public API

    /// Access the underlying component
    /// Provides low-level operations if needed
    public var underlyingComponent: VADComponent? {
        return component
    }

    /// Whether the VAD component is ready for detection
    public var isReady: Bool {
        return component?.isReady ?? false
    }

    /// Whether speech is currently active
    public var isSpeechActive: Bool {
        component?.getService()?.isSpeechActive ?? false
    }

    /// Current energy threshold
    public var energyThreshold: Float {
        get { component?.getService()?.energyThreshold ?? 0.0 }
        set {
            if let service = component?.getService() {
                service.energyThreshold = newValue
            }
        }
    }

    // MARK: - Configuration

    /// Configure the VAD capability with a specific configuration
    /// - Parameter configuration: The VAD configuration to use
    public func configure(with configuration: VADConfiguration) async throws {
        logger.info("Configuring VAD")
        let newComponent = VADComponent(configuration: configuration)
        try await newComponent.initialize()
        self.component = newComponent
        logger.info("VAD configured successfully")
    }

    /// Initialize the VAD service (for backward compatibility)
    /// Must be called before using VAD operations
    public func initialize() async throws {
        let configuration = VADConfiguration()
        try await configure(with: configuration)
    }

    /// Initialize with specific configuration
    /// - Parameter configuration: The VAD configuration
    public func initialize(with configuration: VADConfiguration) async throws {
        try await configure(with: configuration)
    }

    // MARK: - Convenience Methods

    /// Detect speech in audio buffer
    /// - Parameter buffer: AVAudioPCMBuffer containing audio data
    /// - Returns: VADOutput with detection result
    public func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("VAD not configured. Call configure() first.")
        }
        return try await component.detectSpeech(in: buffer)
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Array of Float audio samples
    /// - Returns: VADOutput with detection result
    public func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("VAD not configured. Call configure() first.")
        }
        return try await component.detectSpeech(in: samples)
    }

    /// Process VAD input (supports both buffer and samples)
    /// - Parameter input: The VAD input to process
    /// - Returns: VADOutput with detection result
    public func process(_ input: VADInput) async throws -> VADOutput {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("VAD not configured. Call configure() first.")
        }
        return try await component.process(input)
    }

    /// Start VAD processing
    public func start() {
        logger.info("Starting VAD")
        component?.start()
    }

    /// Stop VAD processing
    public func stop() {
        logger.info("Stopping VAD")
        component?.stop()
    }

    /// Reset VAD state
    public func reset() {
        logger.info("Resetting VAD")
        component?.reset()
    }

    /// Pause VAD processing
    public func pause() {
        logger.info("Pausing VAD")
        component?.pause()
    }

    /// Resume VAD processing
    public func resume() {
        logger.info("Resuming VAD")
        component?.resume()
    }

    /// Set speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        component?.setSpeechActivityCallback(callback)
    }

    /// Set audio buffer callback
    /// - Parameter callback: Callback invoked for processed audio buffers
    public func setAudioBufferCallback(_ callback: @escaping (Data) -> Void) {
        if let service = component?.getService() {
            service.onAudioBuffer = callback
        }
    }

    // MARK: - Calibration

    /// Start calibration to measure ambient noise
    public func startCalibration() async throws {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("VAD not configured. Call configure() first.")
        }
        try await component.startCalibration()
    }

    /// Set calibration parameters
    /// - Parameter multiplier: Threshold multiplier (1.5 to 4.0)
    public func setCalibrationParameters(multiplier: Float) {
        component?.setCalibrationParameters(multiplier: multiplier)
    }

    // MARK: - Statistics

    /// Get current VAD statistics for debugging
    /// - Returns: VADStatistics with current state
    public func getStatistics() -> VADStatistics? {
        return component?.getStatistics()
    }

    // MARK: - TTS Integration

    /// Notify VAD that TTS is about to start
    public func notifyTTSWillStart() {
        if let service = component?.getService() as? SimpleEnergyVADService {
            service.notifyTTSWillStart()
        }
    }

    /// Notify VAD that TTS has finished
    public func notifyTTSDidFinish() {
        if let service = component?.getService() as? SimpleEnergyVADService {
            service.notifyTTSDidFinish()
        }
    }

    /// Set TTS threshold multiplier
    /// - Parameter multiplier: Multiplier to apply during TTS (2.0 to 5.0)
    public func setTTSThresholdMultiplier(_ multiplier: Float) {
        if let service = component?.getService() as? SimpleEnergyVADService {
            service.setTTSThresholdMultiplier(multiplier)
        }
    }

    // MARK: - Cleanup

    /// Clean up VAD resources
    public func cleanup() async throws {
        logger.info("Cleaning up VAD")
        try await component?.cleanup()
        component = nil
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
    public static func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        try await shared.detectSpeech(in: buffer)
    }

    /// Detect speech in samples using shared instance
    /// - Parameter samples: Array of Float audio samples
    /// - Returns: VADOutput with detection result
    public static func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        try await shared.detectSpeech(in: samples)
    }
}
