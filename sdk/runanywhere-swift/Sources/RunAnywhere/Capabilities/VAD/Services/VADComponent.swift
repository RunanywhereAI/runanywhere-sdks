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
public final class VADComponent: BaseComponent<SimpleEnergyVADService>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .vad }

    private let vadConfiguration: VADConfiguration
    private var isPaused: Bool = false

    // MARK: - Initialization

    public init(configuration: VADConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.vadConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> SimpleEnergyVADService {
        let vad = SimpleEnergyVADService(
            sampleRate: vadConfiguration.sampleRate,
            frameLength: vadConfiguration.frameLength,
            energyThreshold: vadConfiguration.energyThreshold
        )
        try await vad.initialize()
        return vad
    }

    // MARK: - Pause and Resume

    /// Pause VAD processing
    public func pause() {
        isPaused = true
        service?.pause()
    }

    /// Resume VAD processing
    public func resume() {
        isPaused = false
        service?.resume()
    }

    // MARK: - Public API

    /// Detect speech in audio buffer
    public func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput {
        try ensureReady()

        guard let vadService = service else {
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

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )
    }

    /// Detect speech in audio samples
    public func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        try ensureReady()

        guard let vadService = service else {
            throw VADError.serviceNotAvailable
        }

        // Process samples and get result
        let isSpeechDetected = vadService.processAudioData(samples)

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold
        )
    }

    /// Process VAD input (supports both buffer and samples)
    public func process(_ input: VADInput) async throws -> VADOutput {
        // Apply threshold override if provided
        if let threshold = input.energyThresholdOverride,
           let vadService = service {
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
        service?.reset()
    }

    /// Set speech activity callback
    public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        service?.onSpeechActivity = callback
    }

    /// Start VAD processing
    public func start() {
        service?.start()
    }

    /// Stop VAD processing
    public func stop() {
        service?.stop()
    }

    /// Get the underlying VAD service
    public func getService() -> VADService? {
        return service
    }

    /// Start calibration of the VAD
    public func startCalibration() async throws {
        try ensureReady()

        guard let vadService = service else {
            throw VADError.serviceNotAvailable
        }

        await vadService.startCalibration()
    }

    /// Get current VAD statistics for debugging
    public func getStatistics() -> VADStatistics? {
        return service?.getStatistics()
    }

    /// Set calibration parameters
    public func setCalibrationParameters(multiplier: Float) {
        service?.setCalibrationParameters(multiplier: multiplier)
    }
}
