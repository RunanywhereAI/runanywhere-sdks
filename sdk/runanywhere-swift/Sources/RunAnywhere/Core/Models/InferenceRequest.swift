import Foundation

/// Request for inference
internal struct InferenceRequest {
    let id: UUID
    let prompt: String
    let options: GenerationOptions?
    let timestamp: Date
    let estimatedTokens: Int?
    let priority: RequestPriority

    init(
        prompt: String,
        options: GenerationOptions? = nil,
        estimatedTokens: Int? = nil,
        priority: RequestPriority = .normal
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.options = options
        self.timestamp = Date()
        self.estimatedTokens = estimatedTokens
        self.priority = priority
    }
}
