import Foundation

/// Handles local storage of model registry information
class RegistryStorage {
    private let storageURL: URL

    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: storageURL.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }
}
