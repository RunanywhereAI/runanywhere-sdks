//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Minimal stub implementation - uses SDK for actual functionality
//

import Foundation
import RunAnywhereSDK

@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isLoading = false
    @Published var error: Error?

    private let sdk = RunAnywhereSDK.shared

    private init() {}

    // MARK: - Model Operations

    func loadModel(_ modelInfo: ModelInfo) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Use SDK's model loading
            try await sdk.loadModel(modelInfo.id)
        } catch {
            self.error = error
            throw error
        }
    }

    func unloadCurrentModel() async {
        isLoading = true
        defer { isLoading = false }

        // Use SDK's model unloading if available
        // await sdk.unloadModel()
    }

    func getAvailableModels() async -> [ModelInfo] {
        do {
            // Use SDK's model registry
            return await sdk.modelRegistry.listAvailableModels()
        } catch {
            self.error = error
            return []
        }
    }

    func getCurrentModel() -> ModelInfo? {
        return sdk.currentModel
    }

    func isModelLoaded(_ modelId: String) -> Bool {
        return sdk.currentModel?.id == modelId
    }

    func isModelDownloaded(_ modelName: String, framework: LLMFramework) -> Bool {
        // Check if model exists locally
        // For now, return false unless it's Foundation Models which are built-in
        return framework == .foundationModels
    }
}

// MARK: - ModelInfo Extension

extension ModelInfo {
    var isLocal: Bool {
        return localPath != nil
    }

    var downloadProgress: Double {
        // Stub implementation - return 0 or 1
        return isLocal ? 1.0 : 0.0
    }
}
