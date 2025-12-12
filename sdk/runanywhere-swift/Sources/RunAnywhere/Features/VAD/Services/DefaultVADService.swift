//
//  DefaultVADService.swift
//  RunAnywhere SDK
//
//  Default implementation of VAD service that delegates to underlying provider
//

@preconcurrency import AVFoundation
import Foundation

/// Default implementation of VAD service that delegates to underlying provider
internal final class DefaultVADService: VADService {

    // MARK: - Properties

    private let configuration: VADConfiguration
    private let logger = SDKLogger(category: "DefaultVADService")
    private var underlyingService: VADService?

    private(set) var isReady: Bool = false

    // MARK: - VADService Protocol Properties

    public var energyThreshold: Float {
        get { underlyingService?.energyThreshold ?? configuration.energyThreshold }
        set { underlyingService?.energyThreshold = newValue }
    }

    public var sampleRate: Int {
        underlyingService?.sampleRate ?? configuration.sampleRate
    }

    public var frameLength: Float {
        underlyingService?.frameLength ?? configuration.frameLength
    }

    public var isSpeechActive: Bool {
        underlyingService?.isSpeechActive ?? false
    }

    public var onSpeechActivity: ((SpeechActivityEvent) -> Void)? {
        get { underlyingService?.onSpeechActivity }
        set { underlyingService?.onSpeechActivity = newValue }
    }

    public var onAudioBuffer: ((Data) -> Void)? {
        get { underlyingService?.onAudioBuffer }
        set { underlyingService?.onAudioBuffer = newValue }
    }

    // MARK: - Initialization

    init(configuration: VADConfiguration) {
        self.configuration = configuration
    }

    // MARK: - VADService Protocol Implementation

    func initialize() async throws {
        logger.info("Initializing VAD service")

        // Validate configuration
        try configuration.validate()

        // Create the underlying service (SimpleEnergyVADService is the default)
        let service = SimpleEnergyVADService(
            sampleRate: configuration.sampleRate,
            frameLength: configuration.frameLength,
            energyThreshold: configuration.energyThreshold
        )

        try await service.initialize()

        self.underlyingService = service
        self.isReady = true

        logger.info("VAD service initialized successfully")
    }

    func start() {
        underlyingService?.start()
    }

    func stop() {
        underlyingService?.stop()
    }

    func reset() {
        underlyingService?.reset()
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        underlyingService?.processAudioBuffer(buffer)
    }

    @discardableResult
    func processAudioData(_ audioData: [Float]) -> Bool {
        underlyingService?.processAudioData(audioData) ?? false
    }

    func pause() {
        underlyingService?.pause()
    }

    func resume() {
        underlyingService?.resume()
    }

    // MARK: - Cleanup

    func cleanup() async {
        logger.info("Cleaning up VAD service")
        underlyingService?.stop()
        underlyingService = nil
        isReady = false
    }
}
