//
//  STTServiceProvider.swift
//  RunAnywhere SDK
//
//  Protocol for registering external STT implementations
//

import Foundation

// MARK: - STT Service Provider Protocol

/// Protocol for registering external STT implementations
public protocol STTServiceProvider {
    /// Create an STT service for the given configuration
    func createSTTService(configuration: STTConfiguration) async throws -> STTService

    /// Check if this provider can handle the given model
    func canHandle(modelId: String?) -> Bool

    /// Provider name for identification
    var name: String { get }
}
