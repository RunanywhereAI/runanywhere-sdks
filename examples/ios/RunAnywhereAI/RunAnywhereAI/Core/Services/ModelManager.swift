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

        var request = RAModelLoadRequest()
        request.modelID = modelInfo.id
        if modelInfo.category != .unspecified {
            request.category = modelInfo.category
        }
        let result = await RunAnywhere.loadModel(request)
        guard result.success else {
            let err = SDKException(code: .unknown, message: result.errorMessage, category: .internal)
            self.error = err
            throw err
        }
    }

    func unloadCurrentModel() async {
        isLoading = true
        defer { isLoading = false }

        var request = RAModelUnloadRequest()
        request.unloadAll = true
        _ = await RunAnywhere.unloadModel(request)
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
        // Resolve any currently-loaded model via canonical proto snapshot API.
        let snapshot = RunAnywhere.currentModel()
        guard snapshot.found else { return nil }
        if snapshot.hasModel {
            return snapshot.model
        }
        let models = await getAvailableModels()
        return models.first { $0.id == snapshot.modelID }
    }
}
