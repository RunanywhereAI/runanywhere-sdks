//
//  CapabilityProtocols.swift
//  RunAnywhere SDK
//
//  Base protocols and types for capability abstraction
//

import Foundation

// MARK: - Capability State

/// Represents the loading state of a capability
public enum CapabilityLoadingState: Sendable, Equatable {
    case idle
    case loading(resourceId: String)
    case loaded(resourceId: String)
    case failed(Error)

    public static func == (lhs: CapabilityLoadingState, rhs: CapabilityLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let lId), .loading(let rId)):
            return lId == rId
        case (.loaded(let lId), .loaded(let rId)):
            return lId == rId
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

/// Result of a capability operation with timing metadata
public struct CapabilityOperationResult<T: Sendable>: Sendable {
    public let value: T
    public let processingTimeMs: Double
    public let resourceId: String?

    public init(value: T, processingTimeMs: Double, resourceId: String? = nil) {
        self.value = value
        self.processingTimeMs = processingTimeMs
        self.resourceId = resourceId
    }
}

// MARK: - Base Capability Protocol

/// Base protocol for all capabilities
/// Defines the common interface that all capabilities must implement
public protocol Capability: Actor {
    /// The type of configuration used by this capability
    associatedtype Configuration: Sendable

    /// Configure the capability
    func configure(_ config: Configuration)

    /// Cleanup resources
    func cleanup() async
}

// MARK: - Model Loadable Capability

/// Protocol for capabilities that load models/resources
/// Provides a standardized interface for model lifecycle management
public protocol ModelLoadableCapability: Capability {
    /// Whether a model is currently loaded
    var isModelLoaded: Bool { get async }

    /// The currently loaded model/resource ID
    var currentModelId: String? { get async }

    /// Load a model by ID
    /// - Parameter modelId: The model identifier
    func loadModel(_ modelId: String) async throws

    /// Unload the currently loaded model
    func unload() async throws
}

// MARK: - Service Based Capability

/// Protocol for capabilities that initialize a service without model loading
/// (e.g., VAD, Speaker Diarization)
public protocol ServiceBasedCapability: Capability {
    /// Whether the capability is ready to use
    var isReady: Bool { get }

    /// Initialize the capability with default configuration
    func initialize() async throws

    /// Initialize the capability with configuration
    func initialize(_ config: Configuration) async throws
}

// MARK: - Composite Capability

/// Protocol for capabilities that compose multiple other capabilities
/// (e.g., VoiceAgent which uses STT, LLM, TTS, VAD)
public protocol CompositeCapability: Actor {
    /// Whether the composite capability is fully initialized
    var isReady: Bool { get }

    /// Clean up all composed resources
    func cleanup() async
}

// MARK: - Capability Metrics Helper

/// Helper for tracking capability operation metrics
public struct CapabilityMetrics: Sendable {
    public let startTime: Date
    public let resourceId: String

    public init(resourceId: String) {
        self.startTime = Date()
        self.resourceId = resourceId
    }

    /// Get elapsed time in milliseconds
    public var elapsedMs: Double {
        Date().timeIntervalSince(startTime) * 1000
    }

    /// Create a result with the current metrics
    public func result<T: Sendable>(_ value: T) -> CapabilityOperationResult<T> {
        CapabilityOperationResult(
            value: value,
            processingTimeMs: elapsedMs,
            resourceId: resourceId
        )
    }
}
