//
//  VADComponent.swift
//  RunAnywhere SDK
//
//  Component wrapper for VAD to integrate with the component lifecycle system
//

@preconcurrency import AVFoundation
import Foundation

/// Voice Activity Detection component following the clean architecture
/// Extends BaseComponent to integrate with the SDK's component lifecycle system
@MainActor
public final class VADComponent: BaseComponent<VADServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .vad }

    private let vadConfiguration: VADConfiguration
    private var isPaused: Bool = false
    private let logger = SDKLogger(category: "VADComponent")
    private let analyticsService = VADAnalyticsService()

    // MARK: - Initialization

    public init(configuration: VADConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.vadConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> VADServiceWrapper {
        // Create default SimpleEnergyVADService
        // Note: VAD currently uses SimpleEnergyVADService directly
        // Future enhancement: Support VAD provider pattern via ModuleRegistry like STT/TTS
        logger.info("Creating SimpleEnergyVADService")
        let vadService = SimpleEnergyVADService(
            sampleRate: vadConfiguration.sampleRate,
            frameLength: vadConfiguration.frameLength,
            energyThreshold: vadConfiguration.energyThreshold
        )
        try await vadService.initialize()

        // Wrap the service
        let wrapper = VADServiceWrapper(vadService)
        return wrapper
    }

    public override func performCleanup() async throws {
        // No specific cleanup needed for VAD
    }

    // MARK: - Helper Methods

    private var vadService: (any VADService)? {
        return service?.wrappedService
    }

    // MARK: - Pause and Resume

    /// Pause VAD processing
    public func pause() {
        isPaused = true
        vadService?.pause()
    }

    /// Resume VAD processing
    public func resume() {
        isPaused = false
        vadService?.resume()
    }

    // MARK: - Public API

    /// Detect speech in audio buffer
    public func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        try ensureReady()

        guard let vadService = vadService else {
            throw VADError.serviceNotAvailable
        }

        // Apply threshold if configured
        if vadConfiguration.energyThreshold != vadService.energyThreshold {
            vadService.energyThreshold = vadConfiguration.energyThreshold
        }

        // Process buffer
        vadService.processAudioBuffer(buffer)

        // Get current state
        let isSpeechDetected = vadService.isSpeechActive

        // Track detection
        await analyticsService.trackDetection(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )
    }

    /// Detect speech in audio samples
    public func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        try ensureReady()

        guard let vadService = vadService else {
            throw VADError.serviceNotAvailable
        }

        // Process samples and get result
        let isSpeechDetected = vadService.processAudioData(samples)

        // Track detection
        await analyticsService.trackDetection(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )
    }

    /// Process VAD input (supports both buffer and samples)
    public func process(_ input: VADInput) async throws -> VADOutput {
        // Apply threshold override if provided
        if let threshold = input.energyThresholdOverride,
           let vadService = vadService {
            vadService.energyThreshold = threshold
        }

        // Process based on input type
        if let buffer = input.buffer {
            return try await detectSpeech(in: buffer)
        } else if let samples = input.audioSamples {
            return try await detectSpeech(in: samples)
        } else {
            throw VADError.invalidInput(reason: "VADInput must contain either buffer or audioSamples")
        }
    }

    /// Process audio stream
    public func processAudioStream<S: AsyncSequence>(_ stream: S) -> AsyncThrowingStream<VADOutput, Error>
    where S.Element == AVAudioPCMBuffer {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await buffer in stream {
                        let output = try await detectSpeech(in: buffer)
                        continuation.yield(output)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset VAD state
    public func reset() {
        vadService?.reset()
    }

    /// Set speech activity callback
    public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        vadService?.onSpeechActivity = { [weak self] event in
            callback(event)

            // Track speech activity events
            Task { [weak self] in
                guard let self = self else { return }
                switch event {
                case .started:
                    await self.analyticsService.trackSpeechActivityStarted()
                case .ended:
                    // We don't have duration info from the event, pass 0
                    await self.analyticsService.trackSpeechActivityEnded(duration: 0)
                }
            }
        }
    }

    /// Start VAD processing
    public func start() {
        vadService?.start()
    }

    /// Stop VAD processing
    public func stop() {
        vadService?.stop()
    }

    /// Get the underlying VAD service
    public func getService() -> VADService? {
        return vadService
    }

    /// Start calibration of the VAD
    public func startCalibration() async throws {
        try ensureReady()

        guard let vadService = vadService else {
            throw VADError.serviceNotAvailable
        }

        // These methods are specific to SimpleEnergyVADService
        guard let energyVAD = vadService as? SimpleEnergyVADService else {
            logger.warning("Calibration is only supported for SimpleEnergyVADService")
            return
        }

        let startTime = Date()
        let thresholdBefore = vadService.energyThreshold

        // Track calibration started
        await analyticsService.trackCalibrationStarted(currentThreshold: thresholdBefore)

        await energyVAD.startCalibration()

        let duration = Date().timeIntervalSince(startTime)
        let thresholdAfter = vadService.energyThreshold

        // Track calibration completed
        await analyticsService.trackCalibrationCompleted(
            thresholdBefore: thresholdBefore,
            thresholdAfter: thresholdAfter,
            samplesCollected: 20, // Based on SimpleEnergyVADService default
            duration: duration * 1000 // Convert to ms
        )
    }

    /// Get current VAD statistics for debugging
    public func getStatistics() -> VADStatistics? {
        guard let energyVAD = vadService as? SimpleEnergyVADService else {
            return nil
        }
        return energyVAD.getStatistics()
    }

    /// Set calibration parameters
    public func setCalibrationParameters(multiplier: Float) {
        guard let energyVAD = vadService as? SimpleEnergyVADService else {
            logger.warning("setCalibrationParameters is only supported for SimpleEnergyVADService")
            return
        }
        energyVAD.setCalibrationParameters(multiplier: multiplier)
    }

    /// Get analytics service for advanced tracking
    public func getAnalyticsService() -> VADAnalyticsService {
        return analyticsService
    }
}
