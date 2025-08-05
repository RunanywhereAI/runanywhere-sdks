//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Service for managing model loading and lifecycle
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

        // Use SDK's model unloading
        do {
            try await sdk.unloadModel()
        } catch {
            self.error = error
            print("Failed to unload model: \(error)")
        }
    }

    func getAvailableModels() async -> [ModelInfo] {
        do {
            return try await sdk.listAvailableModels()
        } catch {
            print("Failed to get available models: \(error)")
            return []
        }
    }

    func getCurrentModel() -> ModelInfo? {
        // Since SDK properties are private, return nil for now
        // In a real implementation, this would use public SDK methods
        return nil
    }

    func isModelLoaded(_ modelId: String) -> Bool {
        // Since SDK properties are private, return false for now
        // In a real implementation, this would use public SDK methods
        return false
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
