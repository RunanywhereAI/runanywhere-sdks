import Foundation
import AVFoundation

// MARK: - TTS Options

/// Options for text-to-speech synthesis
public struct TTSOptions: Sendable {
    /// Voice to use for synthesis
    public let voice: String?

    /// Language for synthesis
    public let language: String

    /// Speech rate (0.0 to 2.0, 1.0 is normal)
    public let rate: Float

    /// Speech pitch (0.0 to 2.0, 1.0 is normal)
    public let pitch: Float

    /// Speech volume (0.0 to 1.0)
    public let volume: Float

    /// Audio format for output
    public let audioFormat: AudioFormat

    /// Sample rate for output audio
    public let sampleRate: Int

    /// Whether to use SSML markup
    public let useSSML: Bool

    public init(
        voice: String? = nil,
        language: String = "en-US",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: AudioFormat = .pcm,
        sampleRate: Int = 16000,
        useSSML: Bool = false
    ) {
        self.voice = voice
        self.language = language
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.useSSML = useSSML
    }
}

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services
public protocol TTSService: AnyObject {
    /// Initialize the TTS service
    func initialize() async throws

    /// Synthesize text to audio
    func synthesize(text: String, options: TTSOptions) async throws -> Data

    /// Stream synthesis for long text
    func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws

    /// Stop current synthesis
    func stop()

    /// Check if currently synthesizing
    var isSynthesizing: Bool { get }

    /// Get available voices
    var availableVoices: [String] { get }

    /// Cleanup resources
    func cleanup() async
}

// MARK: - TTS Configuration

/// Configuration for TTS component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct TTSConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .tts }

    /// Model ID (not typically used for TTS)
    public let modelId: String? = nil

    // TTS-specific parameters
    public let voice: String
    public let language: String
    public let speakingRate: Float // 0.5 to 2.0
    public let pitch: Float // 0.5 to 2.0
    public let volume: Float // 0.0 to 1.0
    public let audioFormat: AudioFormat
    public let useNeuralVoice: Bool
    public let enableSSML: Bool

    public init(
        voice: String = "com.apple.ttsbundle.siri_female_en-US_compact",
        language: String = "en-US",
        speakingRate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: AudioFormat = .pcm,
        useNeuralVoice: Bool = true,
        enableSSML: Bool = false
    ) {
        self.voice = voice
        self.language = language
        self.speakingRate = speakingRate
        self.pitch = pitch
        self.volume = volume
        self.audioFormat = audioFormat
        self.useNeuralVoice = useNeuralVoice
        self.enableSSML = enableSSML
    }

    public func validate() throws {
        guard speakingRate >= 0.5 && speakingRate <= 2.0 else {
            throw SDKError.validationFailed("Speaking rate must be between 0.5 and 2.0")
        }
        guard pitch >= 0.5 && pitch <= 2.0 else {
            throw SDKError.validationFailed("Pitch must be between 0.5 and 2.0")
        }
        guard volume >= 0.0 && volume <= 1.0 else {
            throw SDKError.validationFailed("Volume must be between 0.0 and 1.0")
        }
    }
}

// MARK: - TTS Input/Output Models

/// Input for Text-to-Speech (conforms to ComponentInput protocol)
public struct TTSInput: ComponentInput {
    /// Text to synthesize
    public let text: String

    /// Optional SSML markup (overrides text if provided)
    public let ssml: String?

    /// Voice ID override
    public let voiceId: String?

    /// Language override
    public let language: String?

    /// Custom options override
    public let options: TTSOptions?

    public init(
        text: String,
        ssml: String? = nil,
        voiceId: String? = nil,
        language: String? = nil,
        options: TTSOptions? = nil
    ) {
        self.text = text
        self.ssml = ssml
        self.voiceId = voiceId
        self.language = language
        self.options = options
    }

    public func validate() throws {
        if text.isEmpty && ssml == nil {
            throw SDKError.validationFailed("TTSInput must contain either text or SSML")
        }
    }
}

/// Output from Text-to-Speech (conforms to ComponentOutput protocol)
public struct TTSOutput: ComponentOutput {
    /// Synthesized audio data
    public let audioData: Data

    /// Audio format of the output
    public let format: AudioFormat

    /// Duration of the audio in seconds
    public let duration: TimeInterval

    /// Phoneme timestamps if available
    public let phonemeTimestamps: [PhonemeTimestamp]?

    /// Processing metadata
    public let metadata: SynthesisMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        audioData: Data,
        format: AudioFormat,
        duration: TimeInterval,
        phonemeTimestamps: [PhonemeTimestamp]? = nil,
        metadata: SynthesisMetadata,
        timestamp: Date = Date()
    ) {
        self.audioData = audioData
        self.format = format
        self.duration = duration
        self.phonemeTimestamps = phonemeTimestamps
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Synthesis metadata
public struct SynthesisMetadata: Sendable {
    public let voice: String
    public let language: String
    public let processingTime: TimeInterval
    public let characterCount: Int
    public let charactersPerSecond: Double

    public init(
        voice: String,
        language: String,
        processingTime: TimeInterval,
        characterCount: Int
    ) {
        self.voice = voice
        self.language = language
        self.processingTime = processingTime
        self.characterCount = characterCount
        self.charactersPerSecond = processingTime > 0 ? Double(characterCount) / processingTime : 0
    }
}

/// Phoneme timestamp information
public struct PhonemeTimestamp: Sendable {
    public let phoneme: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(phoneme: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.phoneme = phoneme
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - TTS Framework Adapter Protocol

/// Protocol for TTS framework adapters
public protocol TTSFrameworkAdapter: ComponentAdapter where ServiceType: TTSService {
    /// Create a TTS service for the given configuration
    func createTTSService(configuration: TTSConfiguration) async throws -> ServiceType
}

// MARK: - System TTS Service

/// System TTS Service implementation using AVSpeechSynthesizer
public final class SystemTTSService: NSObject, TTSService, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = SDKLogger(category: "SystemTTS")
    private var speechContinuation: CheckedContinuation<Data, Error>?
    private var _isSynthesizing = false
    private let speechQueue = DispatchQueue(label: "com.runanywhere.tts.speech")

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService Protocol

    public func initialize() async throws {
        // Don't configure audio session here - it's already configured by AudioCapture
        // Trying to change categories causes the '!pri' error
        logger.info("System TTS initialized - using existing audio session configuration")
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // Use proper async handling without forced sync
        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation for delegate callback using async operation
            self.speechQueue.async { [weak self] in
                self?.speechContinuation = continuation
            }

            // Create and configure utterance
            let utterance = AVSpeechUtterance(string: text)

            // Configure voice
            if options.voice == "system" {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            } else if let speechVoice = AVSpeechSynthesisVoice(language: options.voice ?? options.language) {
                utterance.voice = speechVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: options.language)
            }

            // Configure speech parameters
            utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = options.pitch
            utterance.volume = options.volume
            utterance.preUtteranceDelay = 0.0
            utterance.postUtteranceDelay = 0.0

            logger.info("Speaking text: '\(text.prefix(50))...' with voice: \(options.voice ?? options.language)")

            // Speak on main queue (required by AVSpeechSynthesizer)
            DispatchQueue.main.async { [weak self] in
                self?._isSynthesizing = true
                self?.synthesizer.speak(utterance)
            }
        }
    }

    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // System TTS doesn't support true streaming
        // Just synthesize the complete text
        _ = try await synthesize(text: text, options: options)
        onChunk(Data()) // Signal completion with empty data
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(returning: Data())
            self?.speechContinuation = nil
        }
    }

    public var isSynthesizing: Bool {
        synthesizer.isSpeaking
    }

    public var availableVoices: [String] {
        AVSpeechSynthesisVoice.speechVoices().map { $0.language }
    }

    public func cleanup() async {
        stop()
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
        #endif
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.info("TTS playback completed")
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(returning: Data())
            self?.speechContinuation = nil
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        logger.info("TTS playback cancelled")
        _isSynthesizing = false
        speechQueue.async { [weak self] in
            self?.speechContinuation?.resume(throwing: CancellationError())
            self?.speechContinuation = nil
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.info("TTS playback started")
        _isSynthesizing = true
    }
}

// MARK: - Default TTS Adapter

/// Default TTS adapter using system TTS
public final class DefaultTTSAdapter: ComponentAdapter {
    public typealias ServiceType = SystemTTSService

    public init() {}

    public func createService(configuration: any ComponentConfiguration) async throws -> SystemTTSService {
        guard let ttsConfig = configuration as? TTSConfiguration else {
            throw SDKError.validationFailed("Expected TTSConfiguration")
        }
        return try await createTTSService(configuration: ttsConfig)
    }

    public func createTTSService(configuration: TTSConfiguration) async throws -> SystemTTSService {
        let service = SystemTTSService()
        try await service.initialize()
        return service
    }
}

// MARK: - TTS Service Wrapper

/// Wrapper class to allow protocol-based TTS service to work with BaseComponent
public final class TTSServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any TTSService
    public var wrappedService: (any TTSService)?

    public init(_ service: (any TTSService)? = nil) {
        self.wrappedService = service
    }
}

// MARK: - TTS Component

/// Text-to-Speech component following the clean architecture
@MainActor
public final class TTSComponent: BaseComponent<TTSServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .tts }

    private let logger = SDKLogger(category: "TTSComponent")
    private let ttsConfiguration: TTSConfiguration
    private var currentVoice: String?

    // MARK: - Initialization

    public init(configuration: TTSConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.ttsConfiguration = configuration
        self.currentVoice = configuration.voice
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> TTSServiceWrapper {
        let modelId = ttsConfiguration.voice
        let modelName = modelId

        logger.info("Creating TTS service for modelId: \(modelId)")

        // Try to get a registered TTS provider from central registry
        // Need to access ModuleRegistry on MainActor since it's @MainActor isolated
        let provider = await MainActor.run {
            let p = ModuleRegistry.shared.ttsProvider(for: modelId)
            if let p = p {
                logger.info("Found TTS provider: \(p.name) for modelId: \(modelId)")
            } else {
                logger.info("No TTS provider found for modelId: \(modelId), will use system TTS fallback")
                // Log all registered TTS providers for debugging
                let allProviders = ModuleRegistry.shared.allTTSProviders()
                logger.info("Registered TTS providers count: \(allProviders.count)")
                for provider in allProviders {
                    logger.info("  - \(provider.name), canHandle(\(modelId)): \(provider.canHandle(modelId: modelId))")
                }
            }
            return p
        }

        // Determine framework based on provider availability
        // If a provider handles it, it's likely ONNX; otherwise it's system TTS
        let framework: LLMFramework = provider != nil ? .onnx : .systemTTS
        logger.info("Determined framework: \(framework.displayName)")

        // Notify lifecycle manager
        await MainActor.run {
            ModelLifecycleTracker.shared.modelWillLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .tts
            )
        }

        // Emit checking event
        eventBus.publish(ComponentInitializationEvent.componentChecking(
            component: Self.componentType,
            modelId: modelId
        ))

        do {
            let ttsService: any TTSService

            if let provider = provider {
                // Use registered provider (e.g., ONNXTTSServiceProvider)
                logger.info("Creating TTS service via provider: \(provider.name)")
                ttsService = try await provider.createTTSService(configuration: ttsConfiguration)
                logger.info("TTS service created successfully via provider")
            } else {
                // Fallback to default adapter (system TTS)
                logger.info("Creating TTS service via DefaultTTSAdapter (system TTS)")
                let defaultAdapter = DefaultTTSAdapter()
                ttsService = try await defaultAdapter.createTTSService(configuration: ttsConfiguration)
                logger.info("TTS service created successfully via DefaultTTSAdapter")
            }

            // Wrap the service
            let wrapper = TTSServiceWrapper(ttsService)

            // Notify lifecycle manager of successful load
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .tts,
                    memoryUsage: nil
                )
            }

            logger.info("TTS component service creation completed successfully")
            return wrapper
        } catch {
            logger.error("TTS service creation failed: \(error)")
            logger.error("Error type: \(type(of: error))")
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .tts,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    public override func initializeService() async throws {
        guard let wrappedService = service?.wrappedService else { return }

        // Track initialization
        // Track voice loading
        eventBus.publish(ComponentInitializationEvent.componentInitializing(
            component: Self.componentType,
            modelId: nil
        ))

        try await wrappedService.initialize()
    }

    // MARK: - Public API

    /// Synthesize speech from text
    public func synthesize(_ text: String, voice: String? = nil, language: String? = nil) async throws -> TTSOutput {
        try ensureReady()

        let input = TTSInput(
            text: text,
            voiceId: voice,
            language: language
        )
        return try await process(input)
    }

    /// Synthesize with SSML markup
    public func synthesizeSSML(_ ssml: String, voice: String? = nil, language: String? = nil) async throws -> TTSOutput {
        try ensureReady()

        let input = TTSInput(
            text: "",
            ssml: ssml,
            voiceId: voice,
            language: language
        )
        return try await process(input)
    }

    /// Process TTS input
    public func process(_ input: TTSInput) async throws -> TTSOutput {
        try ensureReady()

        guard let ttsService = service?.wrappedService else {
            throw SDKError.componentNotReady("TTS service not available")
        }

        // Validate input
        try input.validate()

        // Get text to synthesize
        let textToSynthesize = input.ssml ?? input.text

        // Create options from input or use defaults
        let options = input.options ?? TTSOptions(
            voice: input.voiceId ?? ttsConfiguration.voice,
            language: input.language ?? ttsConfiguration.language,
            rate: ttsConfiguration.speakingRate,
            pitch: ttsConfiguration.pitch,
            volume: ttsConfiguration.volume,
            audioFormat: ttsConfiguration.audioFormat,
            sampleRate: ttsConfiguration.audioFormat == .pcm ? 16000 : 44100,
            useSSML: input.ssml != nil
        )

        // Track processing time
        let startTime = Date()

        // Perform synthesis
        let audioData = try await ttsService.synthesize(text: textToSynthesize, options: options)

        let processingTime = Date().timeIntervalSince(startTime)

        // Calculate audio duration (mock - real implementation would calculate from audio data)
        let duration = estimateAudioDuration(dataSize: audioData.count, format: ttsConfiguration.audioFormat)

        let metadata = SynthesisMetadata(
            voice: options.voice ?? ttsConfiguration.voice,
            language: options.language,
            processingTime: processingTime,
            characterCount: textToSynthesize.count
        )

        return TTSOutput(
            audioData: audioData,
            format: ttsConfiguration.audioFormat,
            duration: duration,
            phonemeTimestamps: nil, // Would be extracted from service if available
            metadata: metadata
        )
    }

    /// Stream synthesis for long text
    public func streamSynthesize(
        _ text: String,
        voice: String? = nil,
        language: String? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureReady()

                    guard let ttsService = service?.wrappedService else {
                        continuation.finish(throwing: SDKError.componentNotReady("TTS service not available"))
                        return
                    }

                    let options = TTSOptions(
                        voice: voice ?? ttsConfiguration.voice,
                        language: language ?? ttsConfiguration.language,
                        rate: ttsConfiguration.speakingRate,
                        pitch: ttsConfiguration.pitch,
                        volume: ttsConfiguration.volume,
                        audioFormat: ttsConfiguration.audioFormat,
                        sampleRate: 16000,
                        useSSML: false
                    )

                    try await ttsService.synthesizeStream(
                        text: text,
                        options: options
                    ) { chunk in
                        continuation.yield(chunk)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get available voices
    public func getAvailableVoices() -> [String] {
        return service?.wrappedService?.availableVoices ?? []
    }

    /// Stop current synthesis
    public func stopSynthesis() {
        service?.wrappedService?.stop()
    }

    /// Check if currently synthesizing
    public var isSynthesizing: Bool {
        return service?.wrappedService?.isSynthesizing ?? false
    }

    /// Get service for compatibility
    public func getService() -> (any TTSService)? {
        return service?.wrappedService
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        service?.wrappedService?.stop()
        await service?.wrappedService?.cleanup()
        currentVoice = nil
    }

    // MARK: - Private Helpers

    private func estimateAudioDuration(dataSize: Int, format: AudioFormat) -> TimeInterval {
        // Rough estimation based on format and typical bitrates
        let bytesPerSecond: Int
        switch format {
        case .pcm, .wav:
            bytesPerSecond = 32000 // 16-bit PCM at 16kHz
        case .mp3:
            bytesPerSecond = 16000 // 128kbps MP3
        default:
            bytesPerSecond = 32000
        }

        return TimeInterval(dataSize) / TimeInterval(bytesPerSecond)
    }
}

// MARK: - Compatibility Typealias
