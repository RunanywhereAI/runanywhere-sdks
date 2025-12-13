//
//  ModelLifecycleService.swift
//  RunAnywhere SDK
//
//  Core protocol defining model lifecycle operations
//

import Combine
import Foundation

/// Protocol defining the core model lifecycle operations
/// Handles loading, unloading, and tracking models across all modalities
public protocol ModelLifecycleService: AnyObject, Sendable {

    // MARK: - Loading Operations

    /// Load a model by identifier
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model
    /// - Returns: The loaded model with its service
    /// - Throws: ModelLifecycleError if loading fails
    func loadModel(_ modelId: String, modality: Modality) async throws -> LoadedModel

    /// Load a model with progress tracking
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model
    ///   - onProgress: Callback for progress updates (0.0 to 1.0)
    /// - Returns: The loaded model with its service
    func loadModel(
        _ modelId: String,
        modality: Modality,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> LoadedModel

    // MARK: - Unloading Operations

    /// Unload a model by identifier
    /// - Parameter modelId: The model identifier
    func unloadModel(_ modelId: String) async throws

    /// Unload all models for a specific modality
    /// - Parameter modality: The modality to unload
    func unloadModels(for modality: Modality) async throws

    /// Unload all loaded models
    func unloadAllModels() async throws

    // MARK: - Query Operations

    /// Get a loaded model by identifier
    /// - Parameter modelId: The model identifier
    /// - Returns: The loaded model if available
    func getLoadedModel(_ modelId: String) async -> LoadedModel?

    /// Get the loaded model for a specific modality
    /// - Parameter modality: The modality to query
    /// - Returns: The loaded model state if available
    func getLoadedModel(for modality: Modality) async -> LoadedModelState?

    /// Check if a model is loaded
    /// - Parameter modelId: The model identifier
    /// - Returns: True if the model is loaded
    func isModelLoaded(_ modelId: String) async -> Bool

    /// Check if a model is loaded for a specific modality
    /// - Parameter modality: The modality to check
    /// - Returns: True if a model is loaded for this modality
    func isModelLoaded(for modality: Modality) async -> Bool

    /// Get all currently loaded models
    /// - Returns: Array of all loaded model states
    func getAllLoadedModels() async -> [LoadedModelState]

    // MARK: - Service Access

    /// Get the LLM service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The LLM service if available
    func getLLMService(for modelId: String) async -> (any LLMService)?

    /// Get the STT service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The STT service if available
    func getSTTService(for modelId: String) async -> (any STTService)?

    /// Get the TTS service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The TTS service if available
    func getTTSService(for modelId: String) async -> (any TTSService)?

    // MARK: - Lifecycle Events

    /// Publisher for lifecycle events
    var lifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> { get }

    // MARK: - Memory Management

    /// Estimate memory usage for a model
    /// - Parameter modelId: The model identifier
    /// - Returns: Estimated memory usage in bytes
    func estimateMemoryUsage(for modelId: String) async -> Int64

    /// Get current total memory usage by all loaded models
    /// - Returns: Total memory usage in bytes
    func getTotalMemoryUsage() async -> Int64

    /// Handle memory pressure by unloading least recently used models
    func handleMemoryPressure() async

    // MARK: - Cleanup

    /// Clean up all resources
    func cleanup() async
}

// MARK: - Default Implementations

public extension ModelLifecycleService {

    /// Load a model without progress tracking
    func loadModel(_ modelId: String, modality: Modality) async throws -> LoadedModel {
        try await loadModel(modelId, modality: modality, onProgress: { _ in })
    }

    /// Default memory pressure handling
    func handleMemoryPressure() async {
        // Default: no-op, implementations can override
    }
}
