//
//  StorageViewModel.swift
//  RunAnywhereAI
//
//  Simplified ViewModel that uses SDK storage methods
//

import Foundation
import SwiftUI
import RunAnywhereSDK

@MainActor
class StorageViewModel: ObservableObject {
    @Published var totalStorageSize: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var modelStorageSize: Int64 = 0
    @Published var storedModels: [StoredModelInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sdk = RunAnywhereSDK.shared

    func loadData() async {
        isLoading = true
        errorMessage = nil

        // Use SDK file manager directly
        let fileManager = sdk.fileManager

        // Get storage sizes from SDK
        totalStorageSize = fileManager.getTotalStorageSize()
        availableSpace = fileManager.getAvailableSpace()
        modelStorageSize = fileManager.getModelStorageSize()

        // Get stored models from SDK
        let modelData = fileManager.getAllStoredModels()
        storedModels = modelData.map { modelId, format, size in
            // Get file path from SDK
            let baseURL = fileManager.getBaseDirectoryURL()
            let modelPath = baseURL.appendingPathComponent("Models").appendingPathComponent(modelId)

            // Detect framework based on format
            let framework = detectFramework(for: format)

            // Get creation date
            let createdDate = getCreatedDate(for: modelPath)

            return StoredModelInfo(
                name: modelId,
                format: format,
                size: size,
                framework: framework,
                filePath: modelPath.path,
                createdDate: createdDate,
                lastUsed: nil
            )
        }

        isLoading = false
    }

    func refreshData() async {
        await loadData()
    }

    func clearCache() async {
        do {
            try sdk.fileManager.clearCache()
            await refreshData()
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }

    func cleanTempFiles() async {
        do {
            try sdk.fileManager.cleanTempFiles()
            await refreshData()
        } catch {
            errorMessage = "Failed to clean temporary files: \(error.localizedDescription)"
        }
    }

    func deleteModel(_ modelId: String) async {
        do {
            try sdk.fileManager.deleteModel(modelId: modelId)
            await refreshData()
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    // MARK: - Helper Methods

    private func detectFramework(for format: ModelFormat) -> LLMFramework? {
        switch format {
        case .gguf, .ggml:
            return .llamaCpp
        case .mlmodel, .mlpackage:
            return .coreML
        case .onnx:
            return .onnx
        case .tflite:
            return .tensorFlowLite
        case .mlx:
            return .mlx
        default:
            return nil
        }
    }

    private func getCreatedDate(for path: URL) -> Date {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
           let creationDate = attributes[.creationDate] as? Date {
            return creationDate
        }
        return Date()
    }
}

// MARK: - Simplified Data Models

struct StoredModelInfo {
    let name: String
    let format: ModelFormat
    let size: Int64
    let framework: LLMFramework?
    let filePath: String?
    let createdDate: Date
    let lastUsed: Date?
}
