import Foundation

/// Represents a model that has been loaded and is ready for use
public struct LoadedModel {
    /// The model information
    public let model: ModelInfo

    /// The service that can execute this model
    public let service: LLMService

    public init(model: ModelInfo, service: LLMService) {
        self.model = model
        self.service = service
    }
}
