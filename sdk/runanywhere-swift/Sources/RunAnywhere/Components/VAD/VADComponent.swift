import Foundation
@preconcurrency import AVFoundation

// MARK: - VAD Service Protocol

/// Base protocol for VAD services
public protocol VADService: AnyObject {
    /// Energy threshold for voice detection
    var energyThreshold: Float { get set }

    /// Sample rate of the audio
    var sampleRate: Int { get }

    /// Frame length in seconds
    var frameLength: Float { get }

    /// Whether speech is currently active
    var isSpeechActive: Bool { get }

    /// Speech activity callback
    var onSpeechActivity: ((SpeechActivityEvent) -> Void)? { get set }

    /// Audio buffer callback
    var onAudioBuffer: ((Data) -> Void)? { get set }

    /// Initialize the service
    func initialize() async throws

    /// Start processing
    func start()

    /// Stop processing
    func stop()

    /// Reset state
    func reset()

    /// Process audio buffer
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)

    /// Process audio samples
    @discardableResult
    func processAudioData(_ audioData: [Float]) -> Bool

    /// Pause VAD processing (optional, not all implementations may support)
    func pause()

    /// Resume VAD processing (optional, not all implementations may support)
    func resume()
}

/// Extension with default implementations for optional methods
public extension VADService {
    /// Default implementation does nothing
    func pause() {}

    /// Default implementation does nothing
    func resume() {}
}

/// Speech activity events
public enum SpeechActivityEvent: String, Sendable {
    case started = "started"
    case ended = "ended"
}

// MARK: - VAD Initialization Parameters

/// Initialization parameters for VAD component (alias for VADConfiguration)

// MARK: - VAD Configuration

/// Configuration for VAD component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct VADConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .vad }

    /// Model ID (not used for VAD)
    public var modelId: String? { nil }

    /// Energy threshold for voice detection (0.0 to 1.0)
    public let energyThreshold: Float

    /// Sample rate in Hz
    public let sampleRate: Int

    /// Frame length in seconds
    public let frameLength: Float

    /// Enable automatic calibration
    public let enableAutoCalibration: Bool

    /// Calibration multiplier (threshold = ambient noise * multiplier)
    public let calibrationMultiplier: Float

    public init(
        energyThreshold: Float = 0.015,  // Changed default to more reasonable value
        sampleRate: Int = 16000,
        frameLength: Float = 0.1,
        enableAutoCalibration: Bool = false,
        calibrationMultiplier: Float = 2.0
    ) {
        self.energyThreshold = energyThreshold
        self.sampleRate = sampleRate
        self.frameLength = frameLength
        self.enableAutoCalibration = enableAutoCalibration
        self.calibrationMultiplier = calibrationMultiplier
    }

    public func validate() throws {
        // Validate threshold range with better guidance
        guard energyThreshold >= 0 && energyThreshold <= 1.0 else {
            throw SDKError.validationFailed("Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05")
        }

        // Warn if threshold is too low or too high
        if energyThreshold < 0.002 {
            // This is just validation, can't log here, but the value is suspicious
            throw SDKError.validationFailed("Energy threshold \(energyThreshold) is very low and may cause false positives. Recommended minimum: 0.002")
        }
        if energyThreshold > 0.1 {
            // This might be intentional for very noisy environments
            throw SDKError.validationFailed("Energy threshold \(energyThreshold) is very high and may miss speech. Recommended maximum: 0.1")
        }

        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard frameLength > 0 && frameLength <= 1.0 else {
            throw SDKError.validationFailed("Frame length must be between 0 and 1 second")
        }

        // Validate calibration multiplier
        guard calibrationMultiplier >= 1.5 && calibrationMultiplier <= 5.0 else {
            throw SDKError.validationFailed("Calibration multiplier must be between 1.5 and 5.0")
        }
    }
}

// MARK: - VAD Input/Output Models

/// Input for Voice Activity Detection (conforms to ComponentInput protocol)
public struct VADInput: ComponentInput {
    /// Audio buffer to process
    public let buffer: AVAudioPCMBuffer?

    /// Audio samples (alternative to buffer)
    public let audioSamples: [Float]?

    /// Optional override for energy threshold
    public let energyThresholdOverride: Float?

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
        self.audioSamples = nil
        self.energyThresholdOverride = nil
    }

    public init(audioSamples: [Float], energyThresholdOverride: Float? = nil) {
        self.buffer = nil
        self.audioSamples = audioSamples
        self.energyThresholdOverride = energyThresholdOverride
    }

    /// Validate the input
    public func validate() throws {
        if buffer == nil && audioSamples == nil {
            throw SDKError.validationFailed("VADInput must contain either buffer or audioSamples")
        }
        if let threshold = energyThresholdOverride {
            guard threshold >= 0 && threshold <= 1.0 else {
                throw SDKError.validationFailed("Energy threshold override must be between 0 and 1.0")
            }
        }
    }
}

/// Output from Voice Activity Detection (conforms to ComponentOutput protocol)
public struct VADOutput: ComponentOutput {
    /// Whether speech is detected
    public let isSpeechDetected: Bool

    /// Audio energy level
    public let energyLevel: Float

    /// Timestamp of this detection (required by ComponentOutput)
    public let timestamp: Date

    public init(
        isSpeechDetected: Bool,
        energyLevel: Float,
        timestamp: Date = Date()
    ) {
        self.isSpeechDetected = isSpeechDetected
        self.energyLevel = energyLevel
        self.timestamp = timestamp
    }
}

// MARK: - VAD Service Adapter Protocol

/// Protocol for VAD framework adapters (conforms to ComponentAdapter protocol)
public protocol VADFrameworkAdapter: ComponentAdapter where ServiceType: VADService {
    /// Create a VAD service for the given configuration
    func createVADService(configuration: VADConfiguration) async throws -> ServiceType
}

// MARK: - Default VAD Adapter

/// Default VAD adapter using SimpleEnergyVAD (conforms to ComponentAdapter)
public final class DefaultVADAdapter: ComponentAdapter {
    public typealias ServiceType = SimpleEnergyVAD

    public init() {}

    /// Create service (required by ComponentAdapter)
    public func createService(configuration: any ComponentConfiguration) async throws -> SimpleEnergyVAD {
        guard let vadConfig = configuration as? VADConfiguration else {
            throw SDKError.validationFailed("Expected VADConfiguration")
        }
        return try await createVADService(configuration: vadConfig)
    }

    /// Create VAD service specifically
    public func createVADService(configuration: VADConfiguration) async throws -> SimpleEnergyVAD {
        let vad = SimpleEnergyVAD(
            sampleRate: configuration.sampleRate,
            frameLength: configuration.frameLength,
            energyThreshold: configuration.energyThreshold
        )
        try await vad.initialize()
        return vad
    }
}

// MARK: - VAD Component

/// Voice Activity Detection component following the clean architecture
@MainActor
public final class VADComponent: BaseComponent<SimpleEnergyVAD>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .vad }

    private let vadConfiguration: VADConfiguration
    private var lastSpeechState: Bool = false
    private var isPaused: Bool = false

    // MARK: - Initialization

    public init(configuration: VADConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.vadConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> SimpleEnergyVAD {
        // For now, always use the default adapter
        // In future, we can get adapter from registry when it's available

        // Fallback to default adapter (SimpleEnergyVAD)
        let defaultAdapter = DefaultVADAdapter()
        return try await defaultAdapter.createVADService(configuration: vadConfiguration)
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
            throw SDKError.componentNotReady("VAD service not available")
        }

        // No need to change state during processing

        // Apply threshold override if configured
        if vadConfiguration.energyThreshold != vadService.energyThreshold {
            vadService.energyThreshold = vadConfiguration.energyThreshold
        }

        // Process buffer
        vadService.processAudioBuffer(buffer)

        // Get current state
        let isSpeechDetected = vadService.isSpeechActive

        // Track state changes
        if isSpeechDetected != lastSpeechState {
            lastSpeechState = isSpeechDetected
        }

        return VADOutput(
            isSpeechDetected: isSpeechDetected,
            energyLevel: vadService.energyThreshold // Note: actual energy would be better
        )
    }

    /// Detect speech in audio samples
    public func detectSpeech(in samples: [Float]) async throws -> VADOutput {
        try ensureReady()

        guard let vadService = service else {
            throw SDKError.componentNotReady("VAD service not available")
        }

        // No need to change state during processing

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
            throw SDKError.validationFailed("VADInput must contain either buffer or audioSamples")
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
        lastSpeechState = false
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

        guard let vadService = service as? SimpleEnergyVAD else {
            throw SDKError.componentNotReady("VAD service does not support calibration")
        }

        // Start calibration
        await vadService.startCalibration()
    }

    /// Get current VAD statistics for debugging
    public func getStatistics() -> (current: Float, threshold: Float, ambient: Float, recentAvg: Float, recentMax: Float)? {
        guard let vadService = service as? SimpleEnergyVAD else {
            return nil
        }

        return vadService.getStatistics()
    }

    /// Set calibration parameters
    public func setCalibrationParameters(multiplier: Float) {
        guard let vadService = service as? SimpleEnergyVAD else {
            return
        }

        vadService.setCalibrationParameters(multiplier: multiplier)
    }
}
