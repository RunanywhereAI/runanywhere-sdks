import Foundation

// MARK: - Model Registry Protocol

/// Model registry protocol
public protocol ModelRegistry {
    /// Discover available models
    /// - Returns: Array of discovered models
    func discoverModels() async -> [ModelInfo]

    /// Register a model
    /// - Parameter model: Model to register
    func registerModel(_ model: ModelInfo)

    /// Get model by ID
    /// - Parameter id: Model identifier
    /// - Returns: Model information if found
    func getModel(by id: String) -> ModelInfo?

    /// Get all registered models
    /// - Returns: All models in registry
    func getAllModels() -> [ModelInfo]

    /// Update model information
    /// - Parameter model: Updated model information
    func updateModel(_ model: ModelInfo)

    /// Remove a model
    /// - Parameter id: Model identifier
    func removeModel(_ id: String)

    /// Add a custom model from URL
    /// - Parameters:
    ///   - id: Explicit model ID. If nil, a stable ID is generated from the URL filename.
    ///   - name: Display name for the model
    ///   - url: Download URL for the model
    ///   - framework: Target framework for the model
    ///   - category: Model category (e.g., .language, .speechRecognition). If nil, inferred from framework.
    ///   - artifactType: How the model is packaged (archive, single file, etc.). If nil, inferred from URL.
    ///   - estimatedSize: Estimated memory usage (optional)
    ///   - supportsThinking: Whether the model supports thinking/reasoning
    /// - Returns: The created model info
    func addModelFromURL(
        id: String?,
        name: String,
        url: URL,
        framework: InferenceFramework,
        category: ModelCategory?,
        artifactType: ModelArtifactType?,
        estimatedSize: Int64?,
        supportsThinking: Bool
    ) -> ModelInfo
}
