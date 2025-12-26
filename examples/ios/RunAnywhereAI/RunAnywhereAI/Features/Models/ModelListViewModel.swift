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
        // Subscribe to SDK events for model lifecycle updates
        subscribeToModelEvents()

        Task {
            await loadModelsFromRegistry()
        }
    }

    /// Subscribe to SDK events for real-time model state updates
    private func subscribeToModelEvents() {
        // Subscribe to LLM events via EventBus
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                self.handleSDKEvent(event)
            }
            .store(in: &cancellables)
    }

    /// Handle SDK events to update model state
    private func handleSDKEvent(_ event: any SDKEvent) {
        // Check for LLM model load/unload events
        if let llmEvent = event as? LLMEvent {
            switch llmEvent {
            case .modelLoadCompleted(let modelId, _, _, _):
                // Find the matching model and set as current
                if let matchingModel = availableModels.first(where: { $0.id == modelId }) {
                    currentModel = matchingModel
                    print("✅ ModelListViewModel: Model loaded: \(matchingModel.name)")
                }
            case .modelUnloaded(let modelId):
                if currentModel?.id == modelId {
                    currentModel = nil
                    print("ℹ️ ModelListViewModel: Model unloaded: \(modelId)")
                }
            default:
                break
            }
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
            // 2. Models from framework adapters
            // 3. Models from local storage
            // 4. User-added models
            let allModels = try await RunAnywhere.availableModels()

            // Filter based on iOS version if needed
            var filteredModels = allModels

            // Filter out Foundation Models for older iOS versions
            if #unavailable(iOS 26.0) {
                filteredModels = allModels.filter { $0.framework != .foundationModels }
                print("iOS < 26 - Foundation Models not available")
            }

            availableModels = filteredModels
            print("Loaded \(availableModels.count) models from registry")

            for model in availableModels {
                print("  - \(model.name) (\(model.framework.displayName))")
            }

            // Sync currentModel with SDK's current model state
            await syncCurrentModelWithSDK()
        } catch {
            print("Failed to load models from SDK: \(error)")
            errorMessage = "Failed to load models: \(error.localizedDescription)"
            availableModels = []
        }

        isLoading = false
    }

    /// Sync current model state with SDK
    private func syncCurrentModelWithSDK() async {
        if let currentModelId = await RunAnywhere.getCurrentModelId(),
           let matchingModel = availableModels.first(where: { $0.id == currentModelId }) {
            currentModel = matchingModel
            print("✅ ModelListViewModel: Restored currentModel from SDK: \(matchingModel.name)")
        }
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

    func downloadModel(_ model: ModelInfo) async throws {
        // Get the model info and use the Download service
        let allModels = try await RunAnywhere.availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == model.id }) else {
            throw RunAnywhereError.modelNotFound(model.id)
        }

        // Use the SDK's download mechanism via the Download class
        let task = try await Download.shared.downloadModel(modelInfo)

        // Wait for completion
        for await progress in task.progress {
            print("Download progress: \(Int(progress.overallProgress * 100))%")
            if progress.stage == .completed {
                break
            }
        }

        // Reload models after download
        await loadModelsFromRegistry()
    }

    func deleteModel(_ model: ModelInfo) async throws {
        try await RunAnywhere.deleteStoredModel(model.id, framework: model.framework)
        // Reload models after deletion
        await loadModelsFromRegistry()
    }

    func loadModel(_ model: ModelInfo) async throws {
        try await RunAnywhere.loadModel(model.id)
        currentModel = model
    }

    /// Add a custom model from URL
    func addModelFromURL(name: String, url: URL, framework: InferenceFramework, estimatedSize: Int64?) async {
        // Use SDK's registerModel method
        RunAnywhere.registerModel(
            name: name,
            url: url,
            framework: framework,
            memoryRequirement: estimatedSize
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
