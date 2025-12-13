//
//  SpeakerDiarizationCapability.swift
//  RunAnywhere SDK
//
//  Simplified actor-based Speaker Diarization capability
//

import Foundation

/// Actor-based Speaker Diarization capability for identifying and tracking speakers
public actor SpeakerDiarizationCapability: ServiceBasedCapability {
    public typealias Configuration = SpeakerDiarizationConfiguration
    public typealias Service = SpeakerDiarizationService

    // MARK: - State

    /// Currently active service
    private var service: SpeakerDiarizationService?

    /// Current configuration
    private var config: SpeakerDiarizationConfiguration?

    /// Whether diarization is initialized
    private var isConfigured = false

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "SpeakerDiarizationCapability")
    private let analyticsService: SpeakerDiarizationAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: SpeakerDiarizationAnalyticsService = SpeakerDiarizationAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: SpeakerDiarizationConfiguration) {
        self.config = config
    }

    // MARK: - Service Lifecycle (ServiceBasedCapability Protocol)

    public var isReady: Bool {
        isConfigured && service?.isReady == true
    }

    public func initialize() async throws {
        try await initialize(SpeakerDiarizationConfiguration())
    }

    public func initialize(_ config: SpeakerDiarizationConfiguration) async throws {
        logger.info("Initializing Speaker Diarization")

        self.config = config

        // Create service through ServiceRegistry
        let diarizationService = try await MainActor.run {
            Task {
                try await ServiceRegistry.shared.createSpeakerDiarization(config: config)
            }
        }.value

        self.service = diarizationService
        self.isConfigured = true

        // Track session start via analytics service
        _ = await analyticsService.startDiarizationSession(maxSpeakers: config.maxSpeakers)

        logger.info("Speaker Diarization initialized successfully")
    }

    public func cleanup() async {
        logger.info("Cleaning up Speaker Diarization")

        // Track session completed before cleanup
        let speakers = (try? getAllSpeakers()) ?? []
        await analyticsService.completeDiarizationSession(
            speakerCount: speakers.count,
            segmentCount: 0,
            averageConfidence: 0.0
        )

        await service?.cleanup()
        service = nil
        isConfigured = false
    }

    // MARK: - Core Operations

    /// Process audio and identify speaker
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    public func processAudio(_ samples: [Float]) async throws -> SpeakerDiarizationSpeakerInfo {
        guard let service = service else {
            throw CapabilityError.notInitialized("Speaker Diarization")
        }

        logger.debug("Processing audio for speaker identification")
        return service.processAudio(samples)
    }

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    public func getAllSpeakers() throws -> [SpeakerDiarizationSpeakerInfo] {
        guard let service = service else {
            throw CapabilityError.notInitialized("Speaker Diarization")
        }

        return service.getAllSpeakers()
    }

    /// Update speaker name
    /// - Parameters:
    ///   - speakerId: The speaker ID to update
    ///   - name: The new name for the speaker
    public func updateSpeakerName(speakerId: String, name: String) async throws {
        guard let service = service else {
            throw CapabilityError.notInitialized("Speaker Diarization")
        }

        logger.info("Updating speaker name: \(speakerId) -> \(name)")
        service.updateSpeakerName(speakerId: speakerId, name: name)
    }

    /// Reset the diarization state
    /// Clears all speaker profiles and resets tracking
    public func reset() async throws {
        guard let service = service else {
            throw CapabilityError.notInitialized("Speaker Diarization")
        }

        logger.info("Resetting speaker diarization state")
        service.reset()

        // Start new analytics session
        _ = await analyticsService.startDiarizationSession(maxSpeakers: config?.maxSpeakers ?? 10)
    }

    // MARK: - Analytics

    /// Get current analytics metrics
    public func getAnalyticsMetrics() async -> SpeakerDiarizationMetrics {
        await analyticsService.getMetrics()
    }
}
