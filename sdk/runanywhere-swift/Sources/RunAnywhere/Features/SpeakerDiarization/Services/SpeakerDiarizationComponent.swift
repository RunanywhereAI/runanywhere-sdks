// swiftlint:disable file_length
//
//  SpeakerDiarizationComponent.swift
//  RunAnywhere SDK
//
//  Speaker Diarization component following the clean architecture
//

import Foundation

// MARK: - SpeakerDiarization Component

/// Speaker Diarization component following the clean architecture
public final class SpeakerDiarizationComponent: BaseComponent<any SpeakerDiarizationService>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .speakerDiarization }

    private let diarizationConfiguration: SpeakerDiarizationConfiguration
    private var providerName: String = "Unknown"  // Store the provider name for telemetry
    private let logger = SDKLogger(category: "SpeakerDiarizationComponent")
    private let analytics: SpeakerDiarizationAnalyticsService

    // MARK: - Initialization

    public init(configuration: SpeakerDiarizationConfiguration) {
        self.diarizationConfiguration = configuration
        self.analytics = SpeakerDiarizationAnalyticsService()
        super.init(configuration: configuration)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> any SpeakerDiarizationService {
        let modelId = diarizationConfiguration.modelId ?? "default"

        // Try to get a registered SpeakerDiarization provider from central registry
        let provider = await MainActor.run {
            ModuleRegistry.shared.speakerDiarizationProvider()
        }

        guard let provider = provider else {
            // Fall back to default service if no provider is registered
            logger.warning("No SpeakerDiarization service provider registered, using default service")
            let defaultService = DefaultSpeakerDiarizationService()
            try await defaultService.initialize()
            self.providerName = "Default"
            return defaultService
        }

        do {
            // Create service through provider
            let diarizationService = try await provider.createSpeakerDiarizationService(
                configuration: diarizationConfiguration
            )

            // Store provider name for telemetry
            self.providerName = provider.name

            // Initialize the service
            try await diarizationService.initialize()

            logger.info("SpeakerDiarization service created with provider: \(provider.name)")

            return diarizationService
        } catch {
            logger.error("Failed to create SpeakerDiarization service: \(error)")
            throw error
        }
    }

    public override func performCleanup() async throws {
        await service?.cleanup()
    }

    // MARK: - Core Operations

    /// Process audio and identify speaker
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    public func processAudio(_ samples: [Float]) async throws -> SpeakerDiarizationSpeakerInfo {
        try ensureReady()

        guard let diarizationService = service else {
            throw RunAnywhereError.componentNotReady("SpeakerDiarization service not available")
        }

        let startTime = Date()

        // Process audio
        let speakerInfo = diarizationService.processAudio(samples)

        let processingTime = Date().timeIntervalSince(startTime)

        // Track analytics
        await analytics.trackAudioProcessed(
            sampleCount: samples.count,
            duration: processingTime,
            speakerId: speakerInfo.id,
            confidence: speakerInfo.confidence ?? 0.0
        )

        // Submit telemetry in background
        let modelId = diarizationConfiguration.modelId
        let frameworkName = self.providerName
        Task.detached(priority: .background) {
            let deviceInfo = TelemetryDeviceInfo.current
            let eventData = SpeakerDiarizationTelemetryData(
                modelId: modelId,
                modelName: modelId,
                framework: frameworkName,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: processingTime * 1000,
                success: true,
                errorMessage: nil,
                audioDurationMs: nil,  // Not applicable for single audio chunk
                speakerCount: 1,
                segmentCount: 1,
                averageConfidence: Double(speakerInfo.confidence ?? 0.0),
                maxSpeakers: self.diarizationConfiguration.maxSpeakers
            )
            let event = SpeakerDiarizationEvent(
                type: .audioProcessed,
                eventData: eventData
            )
            await AnalyticsQueueManager.shared.enqueue(event)
        }

        return speakerInfo
    }

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    public func getAllSpeakers() throws -> [SpeakerDiarizationSpeakerInfo] {
        try ensureReady()

        guard let diarizationService = service else {
            throw RunAnywhereError.componentNotReady("SpeakerDiarization service not available")
        }

        return diarizationService.getAllSpeakers()
    }

    /// Update speaker name
    /// - Parameters:
    ///   - speakerId: The speaker ID to update
    ///   - name: The new name for the speaker
    public func updateSpeakerName(speakerId: String, name: String) async throws {
        try ensureReady()

        guard let diarizationService = service else {
            throw RunAnywhereError.componentNotReady("SpeakerDiarization service not available")
        }

        // Get old name for analytics
        let oldName = diarizationService.getAllSpeakers()
            .first { $0.id == speakerId }?
            .name

        diarizationService.updateSpeakerName(speakerId: speakerId, name: name)

        // Track analytics
        await analytics.trackSpeakerNameUpdate(
            speakerId: speakerId,
            oldName: oldName,
            newName: name
        )
    }

    /// Reset the diarization state
    /// Clears all speaker profiles and resets tracking
    public func reset() throws {
        try ensureReady()

        guard let diarizationService = service else {
            throw RunAnywhereError.componentNotReady("SpeakerDiarization service not available")
        }

        diarizationService.reset()
        logger.info("SpeakerDiarization state reset")
    }

    /// Get service for compatibility
    public func getService() -> (any SpeakerDiarizationService)? {
        return service
    }

    // MARK: - Analytics Access

    /// Get the analytics service for advanced tracking
    public func getAnalytics() -> SpeakerDiarizationAnalyticsService {
        return analytics
    }
}
