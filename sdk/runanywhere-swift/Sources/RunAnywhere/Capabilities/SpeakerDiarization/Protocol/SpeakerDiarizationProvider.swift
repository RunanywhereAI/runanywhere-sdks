//
//  SpeakerDiarizationProvider.swift
//  RunAnywhere SDK
//
//  Provider protocol for Speaker Diarization services
//

import Foundation

// MARK: - Speaker Diarization Service Provider

/// Protocol for speaker diarization service providers (plugins)
/// Allows external modules like FluidAudioDiarization to provide diarization implementations
public protocol SpeakerDiarizationServiceProvider {

    /// Provider name for logging and identification
    var name: String { get }

    /// Check if this provider can handle the given model
    /// - Parameter modelId: Optional model ID to check
    /// - Returns: true if the provider can handle this model
    func canHandle(modelId: String?) -> Bool

    /// Create a speaker diarization service instance
    /// - Parameter configuration: Configuration for the service
    /// - Returns: Configured speaker diarization service
    func createSpeakerDiarizationService(
        configuration: SpeakerDiarizationConfiguration
    ) async throws -> SpeakerDiarizationService
}

// MARK: - Default Implementation

extension SpeakerDiarizationServiceProvider {
    /// Default implementation - provider can handle any model
    public func canHandle(modelId: String?) -> Bool {
        return true
    }
}
