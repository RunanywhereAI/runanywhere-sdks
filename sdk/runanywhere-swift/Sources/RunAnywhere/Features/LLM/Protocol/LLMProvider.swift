//
//  LLMProvider.swift
//  RunAnywhere SDK
//
//  Protocol for registering external LLM implementations
//

import Foundation

/// Protocol for LLM service providers (plugins)
/// External implementations like llama.cpp should conform to this protocol
public protocol LLMServiceProvider {

    // MARK: - Provider Identification

    /// Provider name for identification and logging
    var name: String { get }

    /// Provider priority (higher = preferred when multiple providers can handle a model)
    var priority: Int { get }

    /// Supported LLM frameworks
    var supportedFrameworks: [LLMFramework] { get }

    // MARK: - Model Handling

    /// Check if this provider can handle the given model
    /// - Parameter modelId: The model identifier to check
    /// - Returns: True if this provider can handle the model
    func canHandle(modelId: String?) -> Bool

    // MARK: - Service Creation

    /// Create an LLM service for the given configuration
    /// - Parameter configuration: The LLM configuration
    /// - Returns: An initialized LLM service
    func createLLMService(configuration: LLMConfiguration) async throws -> LLMService
}

// MARK: - Default Implementation

extension LLMServiceProvider {

    /// Default priority (can be overridden by providers)
    public var priority: Int { 0 }

    /// Default supported frameworks (empty - provider handles all or specifies own)
    public var supportedFrameworks: [LLMFramework] { [] }

    /// Default: can handle any model
    public func canHandle(modelId: String?) -> Bool {
        return true
    }
}
