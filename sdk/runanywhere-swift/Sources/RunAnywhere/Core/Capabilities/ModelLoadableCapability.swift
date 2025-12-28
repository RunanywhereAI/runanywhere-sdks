//
//  ModelLoadableCapability.swift
//  RunAnywhere SDK
//
//  Protocol for capabilities that load and manage models.
//  This is the Swift-side protocol for actors that manage model lifecycle.
//

import Foundation

// MARK: - Base Capability Protocol

/// Base protocol for all actor-based capabilities.
///
/// Capabilities conforming to this protocol can:
/// - Be configured with a configuration type
/// - Clean up resources
///
/// ## Usage
///
/// ```swift
/// public actor VADCapability: Capability {
///     public typealias Configuration = VADConfiguration
///
///     public func configure(_ config: VADConfiguration) { /* ... */ }
///     public func cleanup() async { /* ... */ }
/// }
/// ```
public protocol Capability: Actor {
    /// The configuration type for this capability
    associatedtype Configuration: ComponentConfiguration

    /// Configure the capability with the given configuration
    /// - Parameter config: The configuration to apply
    func configure(_ config: Configuration)

    /// Cleanup all resources held by the capability
    func cleanup() async
}

// MARK: - Model Loadable Capability Protocol

/// Protocol for capabilities that manage a single model lifecycle.
///
/// Capabilities conforming to this protocol can:
/// - Load and unload models by ID
/// - Track the current model state
/// - Report whether a model is loaded
///
/// ## Usage
///
/// ```swift
/// public actor LLMCapability: ModelLoadableCapability {
///     public typealias Configuration = LLMConfiguration
///
///     public var isModelLoaded: Bool { /* ... */ }
///     public var currentModelId: String? { /* ... */ }
///
///     public func loadModel(_ modelId: String) async throws { /* ... */ }
///     public func unload() async throws { /* ... */ }
///     public func cleanup() async { /* ... */ }
/// }
/// ```
public protocol ModelLoadableCapability: Capability {
    /// Whether a model is currently loaded and ready
    var isModelLoaded: Bool { get async }

    /// The ID of the currently loaded model, if any
    var currentModelId: String? { get async }

    /// Load a model by ID
    /// - Parameter modelId: The model identifier to load
    /// - Throws: SDKError if loading fails
    func loadModel(_ modelId: String) async throws

    /// Unload the currently loaded model
    /// - Throws: SDKError if unloading fails
    func unload() async throws
}

// MARK: - Default Implementations

public extension ModelLoadableCapability {
    /// Default unload implementation (does nothing if not overridden)
    func unload() async throws {
        // Default implementation - subclasses should override
    }
}
