//
//  ModelListViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK registry directly
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine

@MainActor
class ModelListViewModel: ObservableObject {
    static let shared = ModelListViewModel()

    @Published var availableModels: [ModelInfo] = []
    @Published var currentModel: ModelInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        Task {
            await loadModelsFromRegistry()
        }
    }

    // MARK: - Methods

    /// Load models from SDK registry (no more hard-coded models)
    func loadModelsFromRegistry() async {
        isLoading = true
        errorMessage = nil

        print("🔄 ModelListViewModel: Starting to load models from registry...")

        do {
            // Get all models from SDK registry
            // This now includes:
            // 1. Models from remote configuration (if available)
            // 2. Models from framework adapters (like WhisperKit)
            // 3. Models from local storage
            // 4. User-added models
            print("📡 ModelListViewModel: Calling RunAnywhere.availableModels()...")
            let allModels = try await RunAnywhere.availableModels()
            print("✅ ModelListViewModel: Received \(allModels.count) models from SDK")

            // Filter based on iOS version if needed
            var filteredModels = allModels

            // Filter out Foundation Models for older iOS versions
            if #unavailable(iOS 26.0) {
                filteredModels = allModels.filter { $0.preferredFramework != .foundationModels }
                print("iOS < 18 - Foundation Models not available")
            }

            availableModels = filteredModels
            print("Loaded \(availableModels.count) models from registry")

            for model in availableModels {
                print("  - \(model.name) (\(model.preferredFramework?.displayName ?? "Unknown"))")
            }
        } catch {
            print("Failed to load models from SDK: \(error)")
            errorMessage = "Failed to load models: \(error.localizedDescription)"
            availableModels = []
        }

        // Don't clear currentModel if it's still valid
        if let current = currentModel {
            // Check if current model is still in the available models list
            if !availableModels.contains(where: { $0.id == current.id }) {
                currentModel = nil
            }
        }
        isLoading = false
    }

    func setCurrentModel(_ model: ModelInfo?) {
        currentModel = model
    }

    /// Alias for loadModelsFromRegistry to match view calls
    func loadModels() async {
        await loadModelsFromRegistry()
    }

    /// Select and load a model
    func selectModel(_ model: ModelInfo) async {
        do {
            try await loadModel(model)
            // currentModel is already set in loadModel, no need to set again
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    func downloadModel(_ model: ModelInfo, progressHandler: @escaping (Double) -> Void) async throws {
        try await RunAnywhere.downloadModel(model.id)
    }

    func deleteModel(_ model: ModelInfo) async throws {
        try await RunAnywhere.deleteModel(model.id)
        // Reload models after deletion
        await loadModelsFromRegistry()
    }

    func loadModel(_ model: ModelInfo) async throws {
        let loadedModel = try await RunAnywhere.loadModelWithInfo(model.id)
        currentModel = loadedModel
    }

    /// Add a custom model from URL
    func addModelFromURL(name: String, url: URL, framework: LLMFramework, estimatedSize: Int64?) async throws {
        // Use SDK's addModelFromURL method
        let model = await RunAnywhere.addModelFromURL(
            url,
            name: name,
            type: "gguf"
        )

        // Reload models to include the new one
        await loadModelsFromRegistry()
    }

    /// Add an imported model to the list
    func addImportedModel(_ model: ModelInfo) async {
        // Just reload the models - the SDK registry will pick up the new model
        await loadModelsFromRegistry()
    }
}
