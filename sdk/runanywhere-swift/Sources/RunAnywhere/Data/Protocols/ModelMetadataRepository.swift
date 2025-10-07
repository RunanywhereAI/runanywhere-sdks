import Foundation

/// Repository protocol for model metadata persistence
public protocol ModelMetadataRepository: Repository where Entity == ModelMetadataData {
    // Model-specific queries
    func fetchByModelId(_ modelId: String) async throws -> ModelMetadataData?
    func fetchByFramework(_ framework: LLMFramework) async throws -> [ModelMetadataData]
    func fetchDownloaded() async throws -> [ModelMetadataData]
    func updateDownloadStatus(_ modelId: String, isDownloaded: Bool) async throws

    // Additional methods
    func updateThinkingSupport(
        for modelId: String,
        supportsThinking: Bool,
        thinkingTagPattern: ThinkingTagPattern?
    ) async throws

    func loadStoredModels() async throws -> [ModelInfo]
    func saveModelMetadata(_ model: ModelInfo) async throws
    func updateLastUsed(for modelId: String) async throws
}
