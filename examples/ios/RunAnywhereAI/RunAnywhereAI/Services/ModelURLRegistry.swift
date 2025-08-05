//
//  ModelURLRegistry.swift
//  RunAnywhereAI
//
//  Service for managing model download URLs
//

import Foundation
import RunAnywhereSDK

@MainActor
class ModelURLRegistry: ObservableObject {
    static let shared = ModelURLRegistry()

    @Published var isValidating = false
    @Published var validationResults: [LLMFramework: Bool] = [:]

    // Sample model URLs for demonstration
    private let modelURLs: [LLMFramework: [String: URL]] = [
        .foundationModels: [:], // Foundation Models don't have URLs - they're system provided
        .coreML: [
            "gemma-2b": URL(string: "https://huggingface.co/google/gemma-2b/resolve/main/model.mlmodel")!
        ],
        .llamaCpp: [
            // Existing model
            "phi-3-mini": URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")!,

            // Small models (< 2GB)
            "phi-2-q4": URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf")!,

            // Medium models (2-4GB)
            "llama2-7b-chat-q4": URL(string: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf")!,

            // Large models (4-8GB)
            "mistral-7b-instruct-q5": URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q5_K_M.gguf")!,

            // Code models
            "codellama-7b-q4": URL(string: "https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf")!
        ]
    ]

    private init() {}

    // MARK: - URL Management

    func getModelURLs(for framework: LLMFramework) -> [String: URL] {
        return modelURLs[framework] ?? [:]
    }

    func getURL(for modelName: String, framework: LLMFramework) -> URL? {
        return modelURLs[framework]?[modelName]
    }

    func validateURLs(for framework: LLMFramework) async {
        isValidating = true
        defer { isValidating = false }

        let urls = getModelURLs(for: framework)

        if urls.isEmpty {
            // Foundation Models and others without URLs are always "valid"
            validationResults[framework] = true
            return
        }

        // Simulate URL validation
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        var allValid = true
        for (_, url) in urls {
            // In a real implementation, this would:
            // 1. Check if URL is reachable
            // 2. Verify file exists and is the right size
            // 3. Check checksum if available

            // For now, assume all URLs are valid
            let isValid = await validateURL(url)
            if !isValid {
                allValid = false
                break
            }
        }

        validationResults[framework] = allValid
    }

    func validateAllURLs() async {
        isValidating = true
        defer { isValidating = false }

        // Validate URLs for all frameworks - use actual framework values
        let frameworks: [LLMFramework] = [.foundationModels, .coreML, .llamaCpp, .mlx]
        for framework in frameworks {
            await validateURLs(for: framework)

            // Small delay between validations
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
    }

    func isFrameworkValidated(_ framework: LLMFramework) -> Bool {
        return validationResults[framework] ?? false
    }

    func addCustomURL(_ url: URL, for modelName: String, framework: LLMFramework) {
        // In a real implementation, this would:
        // 1. Validate the URL
        // 2. Save to persistent storage
        // 3. Update the registry

        // For now, just log it
        print("Would add custom URL: \(url) for model: \(modelName) in framework: \(framework)")
    }

    func getAllModels(for framework: LLMFramework) -> [ModelInfo] {
        // Use framework directly since SDK and local frameworks are now aligned
        // Return ModelInfo objects for models that have URLs
        let urls = getModelURLs(for: framework)
        return urls.compactMap { name, url in
            // Determine format based on framework and URL
            let format: ModelFormat = {
                if framework == .coreML {
                    return .mlmodel
                } else if framework == .llamaCpp {
                    return url.pathExtension == "gguf" ? .gguf : .ggml
                }
                return .gguf // Default
            }()

            // Estimate memory based on model name
            let estimatedMemory: Int64 = {
                switch name {
                case "phi-2-q4":
                    return 1_600_000_000 // 1.6GB
                case "llama2-7b-chat-q4":
                    return 3_800_000_000 // 3.8GB
                case "mistral-7b-instruct-q5":
                    return 5_200_000_000 // 5.2GB
                case "codellama-7b-q4":
                    return 3_900_000_000 // 3.9GB
                default:
                    return 1_000_000_000 // 1GB default
                }
            }()

            // Extract quantization info from URL
            let metadata: ModelInfoMetadata = {
                if url.lastPathComponent.contains("Q4_K_M") {
                    return ModelInfoMetadata(quantizationLevel: .q4_K_M)
                } else if url.lastPathComponent.contains("Q5_K_M") {
                    return ModelInfoMetadata(quantizationLevel: .q5_K_M)
                }
                return ModelInfoMetadata()
            }()

            return ModelInfo(
                id: "\(framework.rawValue)-\(name)",
                name: name,
                format: format,
                downloadURL: url,
                estimatedMemory: estimatedMemory,
                compatibleFrameworks: [framework],
                preferredFramework: framework,
                metadata: metadata
            )
        }
    }

    // MARK: - Private Methods

    private func validateURL(_ url: URL) async -> Bool {
        // Simple URL validation - check if it's reachable
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Convenience Methods

    func getAvailableModels(for framework: LLMFramework) -> [String] {
        return Array(getModelURLs(for: framework).keys)
    }

    func getTotalModelCount() -> Int {
        return modelURLs.values.reduce(0) { total, urls in
            total + urls.count
        }
    }
}
