//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Service for managing model loading and lifecycle
//

import Foundation
import RunAnywhere

@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isLoading = false
    @Published var error: Error?

    private init() {}

    // MARK: - Model Operations

    func loadModel(_ modelInfo: RAModelInfo) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Use SDK's model loading with new API
            try await RunAnywhere.loadModel(modelInfo.id)
        } catch {
            self.error = error
            throw error
        }
    }

    func unloadCurrentModel() async {
        isLoading = true
        defer { isLoading = false }

        // Use SDK's model unloading with new API
        do {
            try await RunAnywhere.unloadModel()
        } catch {
            self.error = error
            print("Failed to unload model: \(error)")
        }
    }

    func getAvailableModels() async -> [RAModelInfo] {
        let result = await RunAnywhere.listModels()
        guard result.success else {
            print("Failed to get available models: \(result.errorMessage)")
            return []
        }
        return result.models.models
    }

    func getCurrentModel() async -> RAModelInfo? {
        // Get current model ID from SDK and look up the model info
        guard let modelId = await RunAnywhere.getCurrentModelId() else {
            return nil
        }
        let models = await getAvailableModels()
        return models.first { $0.id == modelId }
    }
}
