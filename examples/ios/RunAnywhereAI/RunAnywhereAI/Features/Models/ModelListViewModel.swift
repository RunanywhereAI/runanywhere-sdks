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

    @Published var availableModels: [RAModelInfo] = []
    @Published var currentModel: RAModelInfo?
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
    private func handleSDKEvent(_ event: RASDKEvent) {
        guard event.category == .llm || event.component == .llm else { return }

        let modelId = event.model.modelID.isEmpty ? event.generation.modelID : event.model.modelID

        switch (event.model.kind, event.generation.kind) {
        case (.loadCompleted, _), (_, .modelLoaded):
            // Find the matching model and set as current
            if let matchingModel = availableModels.first(where: { $0.id == modelId }) {
                currentModel = matchingModel
                print("ModelListViewModel: Model loaded: \(matchingModel.name)")
            }
        case (.unloadCompleted, _), (_, .modelUnloaded):
            if currentModel?.id == modelId {
                currentModel = nil
                print("ModelListViewModel: Model unloaded: \(modelId)")
            }
        default:
            break
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
            let listResult = await RunAnywhere.listModels()
            guard listResult.success else {
                throw SDKException(
                    code: .processingFailed,
                    message: listResult.errorMessage.isEmpty ? "model registry" : listResult.errorMessage,
                    category: .internal
                )
            }
            let allModels = listResult.models.models

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
        let snapshot = RunAnywhere.currentModel()
        if snapshot.found,
           let matchingModel = availableModels.first(where: { $0.id == snapshot.modelID }) {
            currentModel = matchingModel
            print("ModelListViewModel: Restored currentModel from SDK: \(matchingModel.name)")
        }
    }

    func setCurrentModel(_ model: RAModelInfo?) {
        currentModel = model
    }

    /// Alias for loadModelsFromRegistry to match view calls
    func loadModels() async {
        await loadModelsFromRegistry()
    }

    @Published private(set) var isLoadingModel = false

    /// Select and load a model
    func selectModel(_ model: RAModelInfo) async {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        defer { isLoadingModel = false }

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

    func downloadModel(_ model: RAModelInfo) async throws {
        try await RunAnywhere.downloadModel(model) { progress in
            print("Download progress: \(Int(Double(progress.overallProgress) * 100))%")
        }

        // Reload models after download
        await loadModelsFromRegistry()
    }

    func deleteModel(_ model: RAModelInfo) async throws {
        var request = RAStorageDeleteRequest()
        request.modelIds = [model.id]
        request.deleteFiles = true
        request.clearRegistryPaths_p = true
        request.unloadIfLoaded = true
        request.allowPlatformDelete = true

        let result = await RunAnywhere.deleteStorage(request)
        guard result.success else {
            throw NSError(
                domain: "RunAnywhereAI.ModelListViewModel",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: result.errorMessage.isEmpty
                        ? "Failed to delete model"
                        : result.errorMessage
                ]
            )
        }
        // Reload models after deletion
        await loadModelsFromRegistry()
    }

    func loadModel(_ model: RAModelInfo) async throws {
        var request = RAModelLoadRequest()
        request.modelID = model.id
        if model.category != .unspecified {
            request.category = model.category
        }
        let result = await RunAnywhere.loadModel(request)
        guard result.success else {
            throw SDKException(code: .unknown, message: result.errorMessage, category: .internal)
        }
        currentModel = model
    }

    /// Add a custom model from URL via the canonical `RunAnywhere.registerModel`
    /// public API. The SDK composes the proto import request internally via
    /// `rac_register_model_from_url_proto`; example side only collects user
    /// input and reloads the registry.
    func addModelFromURL(name: String, url: URL, framework: InferenceFramework, estimatedSize: Int64?) async {
        do {
            _ = try await RunAnywhere.registerModel(
                name: name,
                url: url.absoluteString,
                framework: framework,
                memoryRequirement: estimatedSize
            )
        } catch {
            print("Failed to register model: \(error.localizedDescription)")
        }

        // Reload models to include the new one
        await loadModelsFromRegistry()
    }

}
