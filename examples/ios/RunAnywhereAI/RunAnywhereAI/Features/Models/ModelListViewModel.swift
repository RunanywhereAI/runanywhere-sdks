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
        // Subscribe to model lifecycle changes from SDK
        subscribeToModelLifecycle()

        Task {
            await loadModelsFromRegistry()
        }
    }

    /// Subscribe to SDK's model lifecycle tracker for real-time model state updates
    private func subscribeToModelLifecycle() {
        // Observe changes to loaded models via the SDK's lifecycle tracker
        ModelLifecycleTracker.shared.$modelsByModality
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modelsByModality in
                guard let self = self else { return }

                // Check if LLM is loaded and sync currentModel
                if let llmState = modelsByModality[.llm], llmState.state.isLoaded {
                    // Find the matching model in availableModels
                    if let matchingModel = self.availableModels.first(where: { $0.id == llmState.modelId }) {
                        if self.currentModel?.id != matchingModel.id {
                            self.currentModel = matchingModel
                            print("✅ ModelListViewModel: Synced currentModel from SDK lifecycle: \(matchingModel.name)")
                        }
                    } else {
                        // Model not in list yet, create a placeholder
                        print("⚠️ ModelListViewModel: LLM loaded but not in availableModels: \(llmState.modelName)")
                    }
                } else if modelsByModality[.llm] == nil && self.currentModel != nil {
                    // LLM was unloaded
                    print("ℹ️ ModelListViewModel: LLM unloaded, clearing currentModel")
                    self.currentModel = nil
                }
            }
            .store(in: &cancellables)

        // Check initial state
        if let llmState = ModelLifecycleTracker.shared.modelsByModality[.llm], llmState.state.isLoaded {
            // We'll sync after availableModels is loaded
            print("📊 ModelListViewModel: Initial LLM state found: \(llmState.modelName)")
        }
    }

    // MARK: - Methods

    /// Load models from SDK registry (no more hard-coded models)
    func loadModelsFromRegistry() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get all models from SDK registry
            // This now includes:
            // 1. Models from remote configuration (if available)
            // 2. Models from framework adapters (like WhisperKit)
            // 3. Models from local storage
            // 4. User-added models
            let allModels = try await RunAnywhere.availableModels()

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

            // After loading models, sync currentModel with SDK's lifecycle tracker
            // Don't clear currentModel - let the lifecycle subscription handle it
            if let llmState = ModelLifecycleTracker.shared.modelsByModality[.llm], llmState.state.isLoaded {
                if let matchingModel = availableModels.first(where: { $0.id == llmState.modelId }) {
                    currentModel = matchingModel
                    print("✅ ModelListViewModel: Restored currentModel after reload: \(matchingModel.name)")
                }
            }
        } catch {
            print("Failed to load models from SDK: \(error)")
            errorMessage = "Failed to load models: \(error.localizedDescription)"
            availableModels = []
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

    /// Get all adapters capable of handling a specific model (NEW - Multi-Adapter Support)
    func availableAdapters(for model: ModelInfo) async -> [LLMFramework] {
        return await RunAnywhere.availableAdapters(for: model.id)
    }

    /// Select and load a model
    func selectModel(_ model: ModelInfo) async {
        do {
            try await loadModel(model)
            setCurrentModel(model)

            // Post notification that model was loaded successfully
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ModelLoaded"),
                    object: model
                )
            }
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            // Don't set currentModel if loading failed
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
        try await RunAnywhere.loadModel(model.id)
        currentModel = model
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
