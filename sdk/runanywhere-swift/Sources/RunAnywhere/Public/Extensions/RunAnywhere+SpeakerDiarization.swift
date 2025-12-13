//
//  RunAnywhere+SpeakerDiarization.swift
//  RunAnywhere SDK
//
//  Public API for Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Operations

public extension RunAnywhere {

    // MARK: - Initialization

    /// Initialize speaker diarization with default configuration
    static func initializeSpeakerDiarization() async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.speakerDiarizationCapability.initialize()
    }

    /// Initialize speaker diarization with configuration
    /// - Parameter config: Speaker diarization configuration
    static func initializeSpeakerDiarization(_ config: SpeakerDiarizationConfiguration) async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.speakerDiarizationCapability.initialize(config)
    }

    /// Check if speaker diarization is ready
    static var isSpeakerDiarizationReady: Bool {
        get async {
            await serviceContainer.speakerDiarizationCapability.isReady
        }
    }

    // MARK: - Speaker Identification

    /// Process audio and identify speaker
    /// - Parameter samples: Audio samples to analyze
    /// - Returns: Information about the detected speaker
    static func identifySpeaker(_ samples: [Float]) async throws -> SpeakerDiarizationSpeakerInfo {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        return try await serviceContainer.speakerDiarizationCapability.processAudio(samples)
    }

    /// Get all identified speakers
    /// - Returns: Array of all speakers detected so far
    static func getAllSpeakers() async throws -> [SpeakerDiarizationSpeakerInfo] {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        return try await serviceContainer.speakerDiarizationCapability.getAllSpeakers()
    }

    /// Update speaker name
    /// - Parameters:
    ///   - speakerId: The speaker ID to update
    ///   - name: The new name for the speaker
    static func updateSpeakerName(speakerId: String, name: String) async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.speakerDiarizationCapability.updateSpeakerName(speakerId: speakerId, name: name)
    }

    /// Reset speaker diarization state
    static func resetSpeakerDiarization() async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.speakerDiarizationCapability.reset()
    }

    // MARK: - Cleanup

    /// Cleanup speaker diarization resources
    static func cleanupSpeakerDiarization() async {
        await serviceContainer.speakerDiarizationCapability.cleanup()
    }
}
