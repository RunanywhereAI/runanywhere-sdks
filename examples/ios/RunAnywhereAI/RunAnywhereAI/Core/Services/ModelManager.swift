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

    func loadModel(_ modelInfo: ModelInfo) async throws {
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

    func getAvailableModels() async -> [ModelInfo] {
        do {
            return try await RunAnywhere.listAvailableModels()
        } catch {
            print("Failed to get available models: \(error)")
            return []
        }
    }

    func getCurrentModel() -> ModelInfo? {
        // Use the SDK's public method to get the current model
        return RunAnywhere.currentModel
    }
}
