//
//  VADCapability.swift
//  RunAnywhere SDK
//
//  Simplified actor-based VAD capability for voice activity detection
//

@preconcurrency import AVFoundation
import Foundation

/// Actor-based VAD capability that provides a simplified interface for voice activity detection
/// Owns the VAD service lifecycle and provides thread-safe access
public actor VADCapability: ServiceBasedCapability {
    public typealias Configuration = VADConfiguration
    public typealias Service = VADService

    // MARK: - State

    /// Currently active VAD service
    private var service: VADService?

    /// Whether VAD is initialized
    private var isConfigured = false

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "VADCapability")
    private let analyticsService: VADAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: VADAnalyticsService = VADAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: VADConfiguration) {
        // Configuration is passed during initialize
    }

    // MARK: - Service Lifecycle (ServiceBasedCapability Protocol)

    public var isReady: Bool {
        isConfigured && service != nil
    }

    /// Whether speech is currently active
    public var isSpeechActive: Bool {
        service?.isSpeechActive ?? false
    }

    /// Current energy threshold
    public var energyThreshold: Float {
        service?.energyThreshold ?? 0.0
    }

    public func initialize() async throws {
        try await initialize(VADConfiguration())
    }

    public func initialize(_ config: VADConfiguration) async throws {
        logger.info("Initializing VAD")

        // Try to get service from ServiceRegistry, fallback to built-in
        let vadService: VADService
        let hasVAD = await MainActor.run { ServiceRegistry.shared.hasVAD }

        do {
            if hasVAD {
                vadService = try await MainActor.run {
                    Task {
                        try await ServiceRegistry.shared.createVAD(config: config)
                    }
                }.value
            } else {
                // Fall back to built-in SimpleEnergyVADService
                vadService = SimpleEnergyVADService(
                    sampleRate: config.sampleRate,
                    energyThreshold: config.energyThreshold
                )
                try await vadService.initialize()
            }

            self.service = vadService
            self.isConfigured = true

            // Track initialization success
            await analyticsService.trackInitialized(framework: vadService.inferenceFramework)

            logger.info("VAD initialized successfully")
        } catch {
            // Track initialization failure
            await analyticsService.trackInitializationFailed(
                error: error.localizedDescription,
                framework: .builtIn
            )
            throw error
        }
    }

    public func cleanup() async {
        logger.info("Cleaning up VAD")

        service?.stop()
        service = nil
        isConfigured = false

        // Track cleanup
        await analyticsService.trackCleanedUp()
    }

    // MARK: - Detection

    /// Detect speech in audio buffer
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: VAD output with detection result
    public func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        guard let service = service else {
            throw CapabilityError.notInitialized("VAD")
        }

        service.processAudioBuffer(buffer)

        return VADOutput(
            isSpeechDetected: service.isSpeechActive,
            energyLevel: service.energyThreshold,
            timestamp: Date()
        )
    }

    /// Detect speech in audio samples
    /// - Parameter samples: Float array of audio samples
    /// - Returns: VAD output with detection result
    public func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        guard let service = service else {
            throw CapabilityError.notInitialized("VAD")
        }

        let isSpeech = service.processAudioData(samples)

        return VADOutput(
            isSpeechDetected: isSpeech,
            energyLevel: service.energyThreshold,
            timestamp: Date()
        )
    }

    // MARK: - Lifecycle Control

    /// Start VAD processing
    public func start() async {
        logger.info("Starting VAD")
        service?.start()
        await analyticsService.trackStarted()
    }

    /// Stop VAD processing
    public func stop() async {
        logger.info("Stopping VAD")
        service?.stop()
        await analyticsService.trackStopped()
    }

    /// Reset VAD state
    public func reset() {
        logger.info("Resetting VAD")
        service?.reset()
    }

    /// Pause VAD processing
    public func pause() async {
        logger.info("Pausing VAD")
        service?.pause()
        await analyticsService.trackPaused()
    }

    /// Resume VAD processing
    public func resume() async {
        logger.info("Resuming VAD")
        service?.resume()
        await analyticsService.trackResumed()
    }

    // MARK: - Configuration Updates

    /// Set energy threshold
    /// - Parameter threshold: New energy threshold (0.0 to 1.0)
    public func setEnergyThreshold(_ threshold: Float) {
        service?.energyThreshold = threshold
    }

    /// Set speech activity callback
    /// - Parameter callback: Callback invoked when speech state changes
    public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        service?.onSpeechActivity = callback
    }

    /// Set audio buffer callback
    /// - Parameter callback: Callback invoked for processed audio buffers
    public func setAudioBufferCallback(_ callback: @escaping (Data) -> Void) {
        service?.onAudioBuffer = callback
    }

    // MARK: - TTS Integration

    /// Notify VAD that TTS is about to start (to adjust sensitivity)
    public func notifyTTSWillStart() {
        if let simpleVAD = service as? SimpleEnergyVADService {
            simpleVAD.notifyTTSWillStart()
        }
    }

    /// Notify VAD that TTS has finished
    public func notifyTTSDidFinish() {
        if let simpleVAD = service as? SimpleEnergyVADService {
            simpleVAD.notifyTTSDidFinish()
        }
    }

    // MARK: - Analytics

    /// Get current VAD analytics metrics
    public func getAnalyticsMetrics() async -> VADMetrics {
        await analyticsService.getMetrics()
    }
}
