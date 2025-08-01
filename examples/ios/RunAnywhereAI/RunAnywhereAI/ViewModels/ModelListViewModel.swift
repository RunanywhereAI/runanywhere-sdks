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

    @Published var availableModels: [RunAnywhereSDK.ModelInfo] = []
    @Published var currentModel: RunAnywhereSDK.ModelInfo?
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

        do {
            // Direct SDK usage
            availableModels = await sdk.modelRegistry.listAvailableModels()
            currentModel = sdk.currentModel
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func selectModel(_ model: RunAnywhereSDK.ModelInfo) async {
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
}
