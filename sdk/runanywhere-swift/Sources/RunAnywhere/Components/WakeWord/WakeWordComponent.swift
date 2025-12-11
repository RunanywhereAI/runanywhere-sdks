import Foundation

// MARK: - Wake Word Service Protocol

/// Protocol for wake word detection services
public protocol WakeWordService: AnyObject { // swiftlint:disable:this avoid_any_object
    /// Initialize the service
    func initialize() async throws

    /// Start listening for wake words
    func startListening()

    /// Stop listening for wake words
    func stopListening()

    /// Process audio buffer and check for wake words
    func processAudioBuffer(_ buffer: [Float]) -> Bool

    /// Check if currently listening
    var isListening: Bool { get }

    /// Cleanup resources
    func cleanup() async
}

// MARK: - Wake Word Configuration

/// Configuration for Wake Word Detection component
public struct WakeWordConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .wakeWord }

    /// Model ID (if using ML-based detection)
    public let modelId: String?

    /// Wake words to detect
    public let wakeWords: [String]

    /// Detection sensitivity (0.0 to 1.0)
    public let sensitivity: Float

    /// Audio buffer size
    public let bufferSize: Int

    /// Sample rate
    public let sampleRate: Int

    /// Confidence threshold for detection
    public let confidenceThreshold: Float

    /// Whether to continue listening after detection
    public let continuousListening: Bool

    public init(
        modelId: String? = nil,
        wakeWords: [String] = ["Hey Siri", "OK Google"],
        sensitivity: Float = 0.5,
        bufferSize: Int = 16000,
        sampleRate: Int = 16000,
        confidenceThreshold: Float = 0.7,
        continuousListening: Bool = true
    ) {
        self.modelId = modelId
        self.wakeWords = wakeWords
        self.sensitivity = sensitivity
        self.bufferSize = bufferSize
        self.sampleRate = sampleRate
        self.confidenceThreshold = confidenceThreshold
        self.continuousListening = continuousListening
    }

    public func validate() throws {
        guard !wakeWords.isEmpty else {
            throw RunAnywhereError.validationFailed("At least one wake word must be specified")
        }
        guard sensitivity >= 0 && sensitivity <= 1 else {
            throw RunAnywhereError.validationFailed("Sensitivity must be between 0 and 1")
        }
        guard confidenceThreshold >= 0 && confidenceThreshold <= 1 else {
            throw RunAnywhereError.validationFailed("Confidence threshold must be between 0 and 1")
        }
    }
}

// MARK: - Wake Word Input/Output Models

/// Input for Wake Word Detection
public struct WakeWordInput: ComponentInput {
    /// Audio buffer to process
    public let audioBuffer: [Float]

    /// Optional timestamp
    public let timestamp: TimeInterval?

    public init(audioBuffer: [Float], timestamp: TimeInterval? = nil) {
        self.audioBuffer = audioBuffer
        self.timestamp = timestamp
    }

    public func validate() throws {
        guard !audioBuffer.isEmpty else {
            throw RunAnywhereError.validationFailed("Audio buffer cannot be empty")
        }
    }
}

/// Output from Wake Word Detection
public struct WakeWordOutput: ComponentOutput {
    /// Whether a wake word was detected
    public let detected: Bool

    /// Detected wake word (if any)
    public let wakeWord: String?

    /// Confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Detection metadata
    public let metadata: WakeWordMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        detected: Bool,
        wakeWord: String? = nil,
        confidence: Float,
        metadata: WakeWordMetadata,
        timestamp: Date = Date()
    ) {
        self.detected = detected
        self.wakeWord = wakeWord
        self.confidence = confidence
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Wake word detection metadata
public struct WakeWordMetadata: Sendable {
    public let processingTime: TimeInterval
    public let bufferSize: Int
    public let sampleRate: Int

    public init(
        processingTime: TimeInterval,
        bufferSize: Int,
        sampleRate: Int
    ) {
        self.processingTime = processingTime
        self.bufferSize = bufferSize
        self.sampleRate = sampleRate
    }
}

// MARK: - Default Wake Word Service

/// Default implementation that always returns false (no detection)
public final class DefaultWakeWordService: WakeWordService {
    private var _isListening = false

    public func initialize() async throws {
        // No initialization needed for default implementation
    }

    public func startListening() {
        _isListening = true
    }

    public func stopListening() {
        _isListening = false
    }

    public func processAudioBuffer(_ buffer: [Float]) -> Bool {
        // Default implementation always returns false (no detection)
        return false
    }

    public var isListening: Bool { _isListening }

    public func cleanup() async {
        _isListening = false
    }
}

// MARK: - Wake Word Component

/// Wake Word Detection component following the clean architecture
@MainActor
public final class WakeWordComponent: BaseComponent<DefaultWakeWordService>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .wakeWord }

    private let wakeWordConfiguration: WakeWordConfiguration

    // MARK: - Initialization

    public init(configuration: WakeWordConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.wakeWordConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> DefaultWakeWordService {
        // Emit model checking event
        eventBus.publish(ComponentInitializationEvent.componentChecking(
            component: Self.componentType,
            modelId: wakeWordConfiguration.modelId
        ))

        // Try to get a registered wake word provider from central registry
        // For now, always return default implementation
        // Note: Add support for external wake word providers

        return DefaultWakeWordService()
    }

    public override func initializeService() async throws {
        guard let service = service else { return }

        eventBus.publish(ComponentInitializationEvent.componentInitializing(
            component: Self.componentType,
            modelId: wakeWordConfiguration.modelId
        ))

        try await service.initialize()
    }

    // MARK: - Public API

    /// Start listening for wake words
    public func startListening() async throws {
        try ensureReady()

        guard let wakeWordService = service else {
            throw RunAnywhereError.componentNotReady("Wake word service not available")
        }

        wakeWordService.startListening()
    }

    /// Stop listening for wake words
    public func stopListening() async throws {
        guard let wakeWordService = service else { return }

        wakeWordService.stopListening()
    }

    /// Process audio input for wake word detection
    public func process(_ input: WakeWordInput) async throws -> WakeWordOutput {
        try ensureReady()

        guard let wakeWordService = service else {
            throw RunAnywhereError.componentNotReady("Wake word service not available")
        }

        // Validate input
        try input.validate()

        // Track processing time
        let startTime = Date()

        // Process audio buffer
        let detected = wakeWordService.processAudioBuffer(input.audioBuffer)

        let processingTime = Date().timeIntervalSince(startTime)

        // Create output
        return WakeWordOutput(
            detected: detected,
            wakeWord: detected ? wakeWordConfiguration.wakeWords.first : nil,
            confidence: detected ? wakeWordConfiguration.confidenceThreshold : 0.0,
            metadata: WakeWordMetadata(
                processingTime: processingTime,
                bufferSize: input.audioBuffer.count,
                sampleRate: wakeWordConfiguration.sampleRate
            )
        )
    }

    /// Check if currently listening
    public var isListening: Bool {
        return service?.isListening ?? false
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        await service?.cleanup()
    }
}

// MARK: - Compatibility Typealias
