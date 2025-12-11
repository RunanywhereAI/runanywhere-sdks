import Foundation

/// Handles local storage of model registry information
class RegistryStorage {
    private let storageURL: URL

    init() {
        guard let documentsURL = try? FileOperationsUtilities.getDocumentsDirectory() else {
            fatalError("Unable to access documents directory")
        }
        storageURL = documentsURL.appendingPathComponent("ModelRegistry.plist")
    }

    func saveModel(_ model: ModelInfo) async {
        var models = await loadAllModels()
        models[model.id] = model
        await saveAllModels(models)
    }

    func removeModel(_ modelId: String) async {
        var models = await loadAllModels()
        models.removeValue(forKey: modelId)
        await saveAllModels(models)
    }

    func loadAllModels() async -> [String: ModelInfo] {
        // This would need proper encoding/decoding implementation
        // For now, return empty dictionary
        [:]
    }

    func saveAllModels(_ models: [String: ModelInfo]) async {
        // This would need proper encoding/decoding implementation
    }

    func getModel(_ modelId: String) async -> ModelInfo? {
        let models = await loadAllModels()
        return models[modelId]
    }

    func getAllModelIds() async -> [String] {
        let models = await loadAllModels()
        return Array(models.keys)
    }

    func clearStorage() async {
        await saveAllModels([:])
    }

    func getStorageSize() -> Int64 {
        return FileOperationsUtilities.fileSize(at: storageURL) ?? 0
    }
}
