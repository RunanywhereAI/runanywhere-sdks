import Foundation

/// Memory-specific information about a loaded model
internal struct MemoryLoadedModelInfo {
    let model: MemoryLoadedModel
    let size: Int64
    var lastUsed: Date
    weak var service: LLMService?
    let priority: MemoryPriority

    init(
        model: MemoryLoadedModel,
        size: Int64,
        lastUsed: Date = Date(),
        service: LLMService? = nil,
        priority: MemoryPriority = .normal
    ) {
        self.model = model
        self.size = size
        self.lastUsed = lastUsed
        self.service = service
        self.priority = priority
    }
}
