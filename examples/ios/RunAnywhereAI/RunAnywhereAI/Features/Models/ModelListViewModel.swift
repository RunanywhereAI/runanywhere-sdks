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
    private var attemptedDefaultChatModelLoad = false

    // MARK: - Initialization

    init() {
        // Subscribe to SDK events for model lifecycle updates
        subscribeToModelEvents()

        Task {
            await loadModelsFromRegistry()
        }
    }

    /// Subscribe to the SDK's typed lifecycle stream for real-time model state
    private func subscribeToModelEvents() {
        RunAnywhere.events.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self else { return }
                self.handleModelLifecycle(change)
            }
            .store(in: &cancellables)
    }

    /// Apply a typed load/unload change to the current-model state
    private func handleModelLifecycle(_ change: RAModelLifecycleChange) {
        guard change.component == .llm || change.event.category == .llm else { return }

        switch change.kind {
        case .loaded:
            // Find the matching model and set as current
            if let matchingModel = availableModels.first(where: { $0.id == change.modelID }) {
                currentModel = matchingModel
                print("ModelListViewModel: Model loaded: \(matchingModel.name)")
            }
        case .unloaded:
            if currentModel?.id == change.modelID {
                currentModel = nil
                print("ModelListViewModel: Model unloaded: \(change.modelID)")
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

            // QHexRT (Qualcomm Hexagon NPU) models can never run on Apple
            // hardware — keep them out of every picker on this platform.
            filteredModels = filteredModels.filter { $0.framework != .qhexrt }
            availableModels = filteredModels
            print("Loaded \(availableModels.count) models from registry")

            for model in availableModels {
                print("  - \(model.name) (\(model.framework.displayName))")
            }

            // Sync currentModel with SDK's current model state
            await syncCurrentModelWithSDK()
            await loadDefaultChatModelIfAvailable()
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

    func loadDefaultChatModelIfAvailable() async {
        guard !isLoadingModel, currentModel == nil, !attemptedDefaultChatModelLoad else { return }
        guard isAppleFoundationDefaultAvailable else { return }
        guard let defaultModel = availableModels.first(where: {
            $0.isAppleFoundationModel && $0.category == .language
        }) else {
            return
        }

        attemptedDefaultChatModelLoad = true
        isLoadingModel = true
        defer { isLoadingModel = false }

        do {
            try await loadModel(defaultModel)
            currentModel = defaultModel
            print("ModelListViewModel: Loaded default Apple Foundation model")
        } catch {
            print("ModelListViewModel: Failed to load default Apple Foundation model: \(error.localizedDescription)")
        }
    }

    private var isAppleFoundationDefaultAvailable: Bool {
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemFoundationModels.isAvailable
        }
        #endif
        return false
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
        let result = await RunAnywhere.deleteModel(model.id)
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
        if currentModel?.id == model.id {
            currentModel = nil
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
