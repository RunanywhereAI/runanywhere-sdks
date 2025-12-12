//
//  STTFrameworkAdapter.swift
//  RunAnywhere SDK
//
//  Protocol for STT framework adapters
//

import Foundation

// MARK: - STT Framework Adapter Protocol

/// Protocol for STT framework adapters
public protocol STTFrameworkAdapter: ComponentAdapter where ServiceType: STTService {
    /// Create an STT service for the given configuration
    func createSTTService(configuration: STTConfiguration) async throws -> ServiceType
}
