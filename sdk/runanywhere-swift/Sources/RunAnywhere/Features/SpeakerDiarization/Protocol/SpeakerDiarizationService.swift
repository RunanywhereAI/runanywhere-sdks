//
//  SpeakerDiarizationService.swift
//  RunAnywhere SDK
//
//  Protocol defining Speaker Diarization service capabilities
//

import Foundation

// MARK: - Speaker Diarization Service Protocol

/// Protocol for speaker diarization services
/// Defines the contract for identifying and tracking speakers in audio
public protocol SpeakerDiarizationService: AnyObject {

    // MARK: - Framework Identification

    /// The inference framework used by this service.
    /// Required for analytics and performance tracking.
    var inferenceFramework: InferenceFrameworkType { get }

    // MARK: - Initialization

    /// Initialize the service
    func initialize() async throws

    // MARK: - Core Operations

    /// Process audio and identify speakers
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    func processAudio(_ samples: [Float]) -> SpeakerDiarizationSpeakerInfo

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    func getAllSpeakers() -> [SpeakerDiarizationSpeakerInfo]

    /// Update the name of a speaker
    /// - Parameters:
    ///   - speakerId: The ID of the speaker to update
    ///   - name: The new name for the speaker
    func updateSpeakerName(speakerId: String, name: String)

    // MARK: - State Management

    /// Reset the diarization state
    /// Clears all speaker profiles and resets tracking
    func reset()

    // MARK: - State

    /// Check if service is ready for processing
    var isReady: Bool { get }

    // MARK: - Lifecycle

    /// Cleanup resources
    func cleanup() async
}

// MARK: - Default Implementation

extension SpeakerDiarizationService {
    /// Default implementation of initialize (does nothing)
    public func initialize() async throws {
        // Default: no initialization needed
    }

    /// Default implementation of cleanup
    public func cleanup() async {
        reset()
    }
}
