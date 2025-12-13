import Foundation

/// Repository protocol for model information persistence
public protocol ModelInfoRepository: Repository where Entity == ModelInfo {
    // Model-specific queries
    func fetchByFramework(_ framework: InferenceFramework) async throws -> [ModelInfo]
    func fetchByCategory(_ category: ModelCategory) async throws -> [ModelInfo]
    func fetchDownloaded() async throws -> [ModelInfo]

    // Update operations
    func updateDownloadStatus(_ modelId: String, localPath: URL?) async throws
    func updateLastUsed(for modelId: String) async throws
}
