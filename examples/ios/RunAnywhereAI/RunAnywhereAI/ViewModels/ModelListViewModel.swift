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

    init() {
        Task {
            await loadModels()
        }
    }

    func loadModels() async {
        isLoading = true
        errorMessage = nil

        // Stub implementation - normally would use SDK
        // For now, create sample models since SDK properties are private
        availableModels = createSampleModels()
        currentModel = nil

        isLoading = false
    }

    func selectModel(_ model: ModelInfo) async {
        isLoading = true
        errorMessage = nil

        do {
            // Direct SDK usage
            try await sdk.loadModel(model.id)
            currentModel = model
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

    private func createSampleModels() -> [ModelInfo] {
        return [
            ModelInfo(
                id: "foundation-phi-3-mini",
                name: "Phi-3 Mini (Foundation Models)",
                format: .gguf,
                downloadURL: nil,
                localPath: nil,
                estimatedMemory: 2_000_000_000,
                contextLength: 4096,
                downloadSize: 0,
                checksum: nil,
                compatibleFrameworks: [.coreML],
                preferredFramework: .coreML,
                hardwareRequirements: [],
                tokenizerFormat: nil,
                metadata: nil,
                alternativeDownloadURLs: []
            ),
            ModelInfo(
                id: "mediapipe-gemma-2b",
                name: "Gemma 2B (MediaPipe)",
                format: .gguf,
                downloadURL: nil,
                localPath: nil,
                estimatedMemory: 2_500_000_000,
                contextLength: 2048,
                downloadSize: 0,
                checksum: nil,
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                hardwareRequirements: [],
                tokenizerFormat: nil,
                metadata: nil,
                alternativeDownloadURLs: []
            )
        ]
    }
}
