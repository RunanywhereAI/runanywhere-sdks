//
//  SpeakerDiarization.swift
//  RunAnywhere SDK
//
//  Public entry point for the Speaker Diarization capability
//

import Foundation

/// Public entry point for the Speaker Diarization capability
/// Provides simplified access to speaker identification and tracking operations
public final class SpeakerDiarization {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = SpeakerDiarization()

    // MARK: - Properties

    private var service: SpeakerDiarizationService
    private let logger = SDKLogger(category: "SpeakerDiarization")

    // MARK: - Initialization

    /// Initialize with default service
    public convenience init() {
        let service = DefaultSpeakerDiarizationService()
        self.init(service: service)
    }

    /// Initialize with custom service (for testing or customization)
    /// - Parameter service: The service to use
    internal init(service: SpeakerDiarizationService) {
        self.service = service
        logger.debug("SpeakerDiarization initialized")
    }

    // MARK: - Public API

    /// Access the underlying service
    /// Provides low-level operations if needed
    public var underlyingService: SpeakerDiarizationService {
        return service
    }

    /// Whether the service is ready for processing
    public var isReady: Bool {
        return service.isReady
    }

    // MARK: - Configuration

    /// Configure with a custom service (allows provider-based configuration)
    /// - Parameter service: The speaker diarization service to use
    public func configure(with service: SpeakerDiarizationService) async throws {
        logger.info("Configuring SpeakerDiarization with custom service")
        try await service.initialize()
        self.service = service
        logger.info("SpeakerDiarization configured successfully")
    }

    /// Configure with a specific configuration
    /// - Parameter configuration: The speaker diarization configuration to use
    public func configure(with configuration: SpeakerDiarizationConfiguration) async throws {
        logger.info("Configuring SpeakerDiarization")

        // Find provider
        let provider = await ModuleRegistry.shared.speakerDiarizationProvider()
        guard let provider = provider else {
            logger.warning("No speaker diarization provider found, using default service")
            let defaultService = DefaultSpeakerDiarizationService()
            try await defaultService.initialize()
            self.service = defaultService
            return
        }

        // Create service from provider
        let newService = try await provider.createSpeakerDiarizationService(configuration: configuration)
        try await newService.initialize()
        self.service = newService

        logger.info("SpeakerDiarization configured successfully")
    }

    // MARK: - Core Operations

    /// Process audio and identify speaker
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    public func processAudio(_ samples: [Float]) -> SpeakerDiarizationSpeakerInfo {
        logger.debug("Processing audio for speaker identification")
        return service.processAudio(samples)
    }

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    public func getAllSpeakers() -> [SpeakerDiarizationSpeakerInfo] {
        return service.getAllSpeakers()
    }

    /// Update speaker name
    /// - Parameters:
    ///   - speakerId: The speaker ID to update
    ///   - name: The new name for the speaker
    public func updateSpeakerName(speakerId: String, name: String) {
        logger.info("Updating speaker name: \(speakerId) -> \(name)")
        service.updateSpeakerName(speakerId: speakerId, name: name)
    }

    /// Reset the diarization state
    /// Clears all speaker profiles and resets tracking
    public func reset() {
        logger.info("Resetting speaker diarization state")
        service.reset()
    }

    // MARK: - Cleanup

    /// Cleanup resources
    public func cleanup() async {
        logger.info("Cleaning up SpeakerDiarization")
        await service.cleanup()
    }
}
