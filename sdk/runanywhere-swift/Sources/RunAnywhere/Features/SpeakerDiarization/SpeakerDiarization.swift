//
//  SpeakerDiarization.swift
//  RunAnywhere SDK
//
//  Public entry point for the Speaker Diarization capability
//

import Foundation

/// Public entry point for the Speaker Diarization capability
/// Provides simplified access to speaker identification and tracking operations
@MainActor
public final class SpeakerDiarization {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = SpeakerDiarization()

    // MARK: - Properties

    private var component: SpeakerDiarizationComponent?
    private let logger = SDKLogger(category: "SpeakerDiarization")

    // MARK: - Initialization

    /// Initialize with default configuration
    public init() {
        logger.debug("SpeakerDiarization initialized")
    }

    // MARK: - Public API

    /// Access the underlying component
    /// Provides access to the component for advanced usage
    public var underlyingComponent: SpeakerDiarizationComponent? {
        return component
    }

    /// Whether the component is ready for processing
    public var isReady: Bool {
        return component?.isReady ?? false
    }

    // MARK: - Configuration

    /// Configure with a specific configuration
    /// - Parameter configuration: The speaker diarization configuration to use
    public func configure(with configuration: SpeakerDiarizationConfiguration) async throws {
        logger.info("Configuring SpeakerDiarization with configuration")

        // Create component
        let newComponent = SpeakerDiarizationComponent(configuration: configuration)
        try await newComponent.initialize()
        self.component = newComponent

        logger.info("SpeakerDiarization configured successfully")
    }

    // MARK: - Core Operations

    /// Process audio and identify speaker
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    public func processAudio(_ samples: [Float]) async throws -> SpeakerDiarizationSpeakerInfo {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("SpeakerDiarization not configured. Call configure() first.")
        }
        logger.debug("Processing audio for speaker identification")
        return try await component.processAudio(samples)
    }

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    public func getAllSpeakers() throws -> [SpeakerDiarizationSpeakerInfo] {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("SpeakerDiarization not configured. Call configure() first.")
        }
        return try component.getAllSpeakers()
    }

    /// Update speaker name
    /// - Parameters:
    ///   - speakerId: The speaker ID to update
    ///   - name: The new name for the speaker
    public func updateSpeakerName(speakerId: String, name: String) async throws {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("SpeakerDiarization not configured. Call configure() first.")
        }
        logger.info("Updating speaker name: \(speakerId) -> \(name)")
        try await component.updateSpeakerName(speakerId: speakerId, name: name)
    }

    /// Reset the diarization state
    /// Clears all speaker profiles and resets tracking
    public func reset() throws {
        guard let component = component else {
            throw RunAnywhereError.componentNotInitialized("SpeakerDiarization not configured. Call configure() first.")
        }
        logger.info("Resetting speaker diarization state")
        try component.reset()
    }

    // MARK: - Cleanup

    /// Cleanup resources
    public func cleanup() async throws {
        guard let component = component else {
            logger.warning("SpeakerDiarization cleanup called but not configured")
            return
        }
        logger.info("Cleaning up SpeakerDiarization")
        try await component.cleanup()
        self.component = nil
    }
}
