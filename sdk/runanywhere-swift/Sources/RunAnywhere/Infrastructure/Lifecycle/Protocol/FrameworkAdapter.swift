//
//  FrameworkAdapter.swift
//  RunAnywhere SDK
//
//  Protocol for framework adapters that can load models
//

import Foundation

/// Unified protocol for all framework adapters (LLM, Voice, Image, etc.)
/// Framework adapters are responsible for loading models using their respective frameworks
public protocol FrameworkAdapter {
    /// The framework this adapter handles
    var framework: LLMFramework { get }

    /// The modalities this adapter supports
    var supportedModalities: Set<FrameworkModality> { get }

    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }

    /// Check if this adapter can handle a specific model
    /// - Parameter model: The model information
    /// - Returns: Whether this adapter can handle the model
    func canHandle(model: ModelInfo) -> Bool

    /// Create a service instance based on the modality
    /// - Parameter modality: The modality to create a service for
    /// - Returns: A service instance (LLMService, STTService, TTSService, etc.)
    func createService(for modality: FrameworkModality) -> Any?

    /// Load a model using this adapter
    /// - Parameters:
    ///   - model: The model to load
    ///   - modality: The modality to use
    /// - Returns: A service instance with the loaded model
    func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any

    /// Estimate memory usage for a model
    /// - Parameter model: The model to estimate
    /// - Returns: Estimated memory in bytes
    func estimateMemoryUsage(for model: ModelInfo) -> Int64

    /// Called when the adapter is registered with the SDK
    /// Adapters should register their service providers with ModuleRegistry here
    @MainActor
    func onRegistration()

    /// Get models provided by this adapter (built-in models)
    /// - Returns: Array of models this adapter provides
    func getProvidedModels() -> [ModelInfo]

    /// Get download strategy provided by this adapter (if any)
    /// - Returns: Download strategy or nil if none
    func getDownloadStrategy() -> DownloadStrategy?

    /// Initialize adapter with component parameters
    /// - Parameters:
    ///   - parameters: Component initialization parameters
    ///   - modality: The modality to initialize for
    /// - Returns: Initialized service ready for use
    func initializeComponent(
        with parameters: any ComponentInitParameters,
        for modality: FrameworkModality
    ) async throws -> Any?
}

// MARK: - Default Implementations

public extension FrameworkAdapter {
    /// Default implementation that returns the framework's supported modalities
    var supportedModalities: Set<FrameworkModality> {
        return framework.supportedModalities
    }

    /// Default implementation - does nothing
    @MainActor
    func onRegistration() {
        // Default: no-op - adapters should override to register their service providers
    }

    /// Default implementation - returns empty array
    func getProvidedModels() -> [ModelInfo] {
        return []
    }

    /// Default implementation - returns nil
    func getDownloadStrategy() -> DownloadStrategy? {
        return nil
    }

    /// Default implementation - creates service and initializes with parameters
    func initializeComponent(
        with parameters: any ComponentInitParameters,
        for modality: FrameworkModality
    ) async throws -> Any? {
        // Default implementation: create service and initialize if model is specified
        guard let service = createService(for: modality) else {
            return nil
        }

        // If there's a model ID, try to load it
        if let modelId = parameters.modelId,
           let modelRegistry = ServiceContainer.shared.modelRegistry.getModel(by: modelId) {
            return try await loadModel(modelRegistry, for: modality)
        }

        return service
    }
}
