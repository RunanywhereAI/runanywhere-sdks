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
        // Llama-3.2 1B Q6_K
        ModelInfo(
            id: "llama-3.2-1b-instruct-q6-k",
            name: "Llama 3.2 1B Instruct Q6_K",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf"),
            estimatedMemory: 1_200_000_000, // 1.2GB
            contextLength: 131072,
            downloadSize: 1_100_000_000, // ~1.1GB
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
            downloadSize: 1_700_000_000, // ~1.7GB
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
            downloadSize: 650_000_000, // ~650MB
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
            downloadSize: 385_000_000, // ~385MB
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
            downloadSize: 1_400_000_000, // ~1.4GB
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
            downloadSize: 656_000_000, // ~656MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: true
        ),

        // MARK: - Voice Models (WhisperKit)
        // Note: URLs provide the base path for the custom download strategy to extract model info

        // Whisper Tiny
        ModelInfo(
            id: "whisper-tiny",
            name: "Whisper Tiny",
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en"), // Base URL for strategy
            estimatedMemory: 39_000_000, // 39MB
            contextLength: 0, // Not applicable for voice models
            downloadSize: 39_000_000, // ~39MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            supportsThinking: false
        ),

        // Whisper Base
        ModelInfo(
            id: "whisper-base",
            name: "Whisper Base",
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base"), // Base URL for strategy
            estimatedMemory: 74_000_000, // 74MB
            contextLength: 0, // Not applicable for voice models
            downloadSize: 74_000_000, // ~74MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            supportsThinking: false
        ),

        // Whisper Small
        ModelInfo(
            id: "whisper-small",
            name: "Whisper Small",
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small"), // Base URL for strategy
            estimatedMemory: 244_000_000, // 244MB
            contextLength: 0, // Not applicable for voice models
            downloadSize: 244_000_000, // ~244MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            supportsThinking: false
        ),

        // MARK: - LiquidAI Models

        // LiquidAI LFM2 350M Q4_K_M (Smallest, fastest)
        ModelInfo(
            id: "lfm2-350m-q4-k-m",
            name: "LiquidAI LFM2 350M Q4_K_M",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf"),
            estimatedMemory: 250_000_000, // 250MB
            contextLength: 32768,
            downloadSize: 218_690_000, // ~219MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: false
        ),

        // LiquidAI LFM2 350M Q6_K (Best balance)
        ModelInfo(
            id: "lfm2-350m-q6-k",
            name: "LiquidAI LFM2 350M Q6_K",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q6_K.gguf"),
            estimatedMemory: 350_000_000, // 350MB
            contextLength: 32768,
            downloadSize: 279_790_000, // ~280MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: false
        ),

        // LiquidAI LFM2 350M Q8_0 (Highest quality)
        ModelInfo(
            id: "lfm2-350m-q8-0",
            name: "LiquidAI LFM2 350M Q8_0",
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf"),
            estimatedMemory: 400_000_000, // 400MB
            contextLength: 32768,
            downloadSize: 361_650_000, // ~362MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            supportsThinking: false
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

        // Use SDK models as the source of truth
        do {
            // Get all models from SDK (includes registered predefined models)
            let sdkModels = try await sdk.listAvailableModels()
            availableModels = sdkModels
        } catch {
            print("Failed to load models from SDK: \(error)")
            // Fall back to predefined models if SDK fails
            availableModels = predefinedModels
        }

        currentModel = nil
        isLoading = false
    }

    private func registerPredefinedModels() async {
        for model in predefinedModels {
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
            // Get the model info
            guard let model = availableModels.first(where: { $0.id == modelId }) else {
                throw SDKError.modelNotFound(modelId)
            }

            // Use the SDK's downloadModel with strategy support
            // The SDK will automatically use the registered WhisperKit strategy for whisper models
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
