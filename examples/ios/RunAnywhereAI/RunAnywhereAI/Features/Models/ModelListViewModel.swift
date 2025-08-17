//
//  ModelListViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK directly
//

import Foundation
import SwiftUI
import RunAnywhereSDK

@MainActor
class ModelListViewModel: ObservableObject {
    static let shared = ModelListViewModel()

    @Published var availableModels: [ModelInfo] = []
    @Published var currentModel: ModelInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sdk = RunAnywhereSDK.shared

    // MARK: - Predefined Models
    private let predefinedModels: [ModelInfo] = [
        // Apple Foundation Models (iOS 26+)
        ModelInfo(
            id: "foundation-models-default",
            name: "Apple Foundation Model",
            format: .mlmodel,
            downloadURL: nil, // Built-in, no download needed
            estimatedMemory: 500_000_000, // 500MB
            contextLength: 8192,
            downloadSize: 0, // Built-in
            compatibleFrameworks: [.foundationModels],
            preferredFramework: .foundationModels,
            supportsThinking: false
        ),
        
        // Llama-3.2 1B Q6_K
        ModelInfo(
            id: "llama-3.2-1b-instruct-q6-k",
            name: "Llama 3.2 1B Instruct Q6_K",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf"),
            estimatedMemory: 1_200_000_000, // 1.2GB
            contextLength: 131072,
            downloadSize: 750_000_000, // ~750MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        ),

        // SmolLM2 1.7B Instruct Q6_K_L
        ModelInfo(
            id: "smollm2-1.7b-instruct-q6-k-l",
            name: "SmolLM2 1.7B Instruct Q6_K_L",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf"),
            estimatedMemory: 1_800_000_000, // 1.8GB
            contextLength: 8192,
            downloadSize: 1_300_000_000, // ~1.3GB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        ),

        // Qwen-2.5 0.5B Q6_K
        ModelInfo(
            id: "qwen-2.5-0.5b-instruct-q6-k",
            name: "Qwen 2.5 0.5B Instruct Q6_K",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf"),
            estimatedMemory: 600_000_000, // 600MB
            contextLength: 32768,
            downloadSize: 400_000_000, // ~400MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        ),

        // SmolLM2 360M Q8_0
        ModelInfo(
            id: "smollm2-360m-q8-0",
            name: "SmolLM2 360M Q8_0",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"),
            estimatedMemory: 500_000_000, // 500MB
            contextLength: 8192,
            downloadSize: 380_000_000, // ~380MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: false
        ),

        // Qwen-2.5 1.5B Q6_K
        ModelInfo(
            id: "qwen-2.5-1.5b-instruct-q6-k",
            name: "Qwen 2.5 1.5B Instruct Q6_K",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf"),
            estimatedMemory: 1_600_000_000, // 1.6GB
            contextLength: 32768,
            downloadSize: 1_100_000_000, // ~1.1GB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        ),

        // Qwen3 600M Q8_0
        ModelInfo(
            id: "qwen3-600m-instruct-q8-0",
            name: "Qwen3 600M Instruct Q8_0",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"),
            estimatedMemory: 800_000_000, // 800MB
            contextLength: 32768,
            downloadSize: 650_000_000, // ~650MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        )
    ]

    init() {
        Task {
            await loadModels()
        }
    }

    func loadModels() async {
        isLoading = true
        errorMessage = nil

        // First, register predefined models with SDK if they have download URLs
        await registerPredefinedModels()

        // Start with predefined models - filter based on iOS version
        var allModels: [ModelInfo] = []
        
        // Add Foundation Model only if iOS 26+ is available
        if #available(iOS 26.0, *) {
            allModels = predefinedModels
            print("iOS 26+ detected - Foundation Models available")
        } else {
            // Filter out Foundation Models for older iOS versions
            allModels = predefinedModels.filter { $0.preferredFramework != .foundationModels }
            print("iOS < 18 - Foundation Models not available")
        }

        do {
            // Add any existing SDK models
            let sdkModels = try await sdk.listAvailableModels()

            // Avoid duplicates by checking if model already exists in predefined list
            for sdkModel in sdkModels {
                if !allModels.contains(where: { $0.id == sdkModel.id }) {
                    allModels.append(sdkModel)
                }
            }
        } catch {
            print("Failed to load models from SDK: \(error)")
            // Still proceed with predefined models even if SDK fails
        }

        availableModels = allModels
        currentModel = nil
        isLoading = false
        
        print("Available models count: \(availableModels.count)")
        for model in availableModels {
            print("  - \(model.name) (\(model.preferredFramework?.displayName ?? "Unknown"))")
        }
    }

    private func registerPredefinedModels() async {
        for model in predefinedModels {
            // Handle Foundation Models separately (no download URL needed)
            if model.preferredFramework == .foundationModels {
                do {
                    // Check if model is already registered
                    let existingModels = try await sdk.listAvailableModels()
                    let alreadyRegistered = existingModels.contains { $0.id == model.id }
                    
                    if !alreadyRegistered {
                        // Register Foundation Model directly with the SDK's registry
                        print("Registering Foundation Model: \(model.name)")
                        
                        // Create a model info with a "built-in" path indicator
                        var foundationModel = model
                        foundationModel.localPath = URL(string: "builtin://foundation-models")
                        
                        // Register using the SDK's public API
                        sdk.registerBuiltInModel(foundationModel)
                        print("Successfully registered Foundation Model: \(model.name)")
                    } else {
                        print("Foundation Model already registered")
                    }
                } catch {
                    print("Failed to check Foundation Model: \(error)")
                }
                continue
            }
            
            // For models that need downloading
            guard let downloadURL = model.downloadURL else { continue }

            do {
                // Check if model is already registered by trying to get it
                let existingModels = try await sdk.listAvailableModels()
                let alreadyRegistered = existingModels.contains { $0.id == model.id }

                if !alreadyRegistered {
                    // Register the model with SDK
                    let _ = sdk.addModelFromURL(
                        name: model.name,
                        url: downloadURL,
                        framework: model.preferredFramework ?? .llamaCpp,
                        estimatedSize: model.downloadSize,
                        supportsThinking: model.supportsThinking
                    )
                    print("Registered predefined model: \(model.name)")
                } else {
                    print("Model \(model.name) already registered, skipping")
                }
            } catch {
                print("Failed to register predefined model \(model.name): \(error)")
                // Continue with other models even if one fails
            }
        }
    }

    func selectModel(_ model: ModelInfo) async {
        isLoading = true
        errorMessage = nil

        do {
            // Direct SDK usage
            try await sdk.loadModel(model.id)
            currentModel = model

            // Post notification that model was loaded
            await MainActor.run {
                NotificationCenter.default.post(name: Notification.Name("ModelLoaded"), object: model)
            }
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refreshModels() async {
        await loadModels()
    }

    func addImportedModel(_ model: ModelInfo) async {
        availableModels.append(model)
    }

    func setCurrentModel(_ model: ModelInfo) async {
        currentModel = model
    }

    func downloadModel(_ modelId: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await sdk.downloadModel(modelId)
            // Wait a moment for filesystem to settle
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            // Refresh models to update download status
            await loadModels()
            return true
        } catch {
            errorMessage = "Failed to download model: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    func deleteModel(_ modelId: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            try await sdk.deleteModel(modelId)
            // Refresh models to update list
            await loadModels()
            return true
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
}
