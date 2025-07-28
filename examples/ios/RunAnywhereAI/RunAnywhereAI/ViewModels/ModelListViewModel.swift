//
//  ModelListViewModel.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation
import SwiftUI

@MainActor
class ModelListViewModel: ObservableObject {
    static let shared = ModelListViewModel()

    @Published var availableServices: [LLMService] = []
    @Published var currentService: LLMService?
    @Published var downloadedModels: [ModelInfo] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let llmService = UnifiedLLMService.shared

    init() {
        loadServices()
        loadDownloadedModels()
    }

    func loadServices() {
        availableServices = llmService.availableServices
        currentService = llmService.currentService
    }

    func refreshServices() async {
        // In a real app, this might check for new services or download models
        loadServices()
    }

    func selectService(_ service: LLMService) {
        currentService = service
        llmService.selectService(named: service.name)
    }

    func loadModel(_ model: ModelInfo) async {
        isLoading = true
        showError = false

        do {
            // In a real implementation, this would download/load the model
            // For now, we'll simulate initialization
            if let service = currentService {
                try await service.initialize(modelPath: model.path ?? "")
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func loadDownloadedModels() {
        Task {
            let modelManager = ModelManager.shared
            let modelFiles = await modelManager.listDownloadedModels()

            // Convert file names to ModelInfo
            var models: [ModelInfo] = []
            for fileName in modelFiles {
                let path = await modelManager.modelPath(for: fileName)
                let size = await modelManager.getModelSize(fileName) ?? 0

                let model = ModelInfo(
                    id: fileName,
                    name: fileName.replacingOccurrences(of: ".gguf", with: "")
                        .replacingOccurrences(of: ".mlpackage", with: "")
                        .replacingOccurrences(of: ".onnxRuntime", with: ""),
                    path: path.path,
                    format: detectFormat(from: fileName),
                    size: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                    framework: frameworkForFormat(detectFormat(from: fileName))
                )
                models.append(model)
            }
            downloadedModels = models
        }
    }

    func addDownloadedModel(_ model: ModelInfo) {
        downloadedModels.append(model)
    }

    func addImportedModel(_ model: ModelInfo) {
        downloadedModels.append(model)
    }

    private func detectFormat(from fileName: String) -> ModelFormat {
        if fileName.hasSuffix(".gguf") {
            return .gguf
        } else if fileName.hasSuffix(".mlpackage") || fileName.hasSuffix(".mlmodel") {
            return .coreML
        } else if fileName.hasSuffix(".onnxRuntime") {
            return .onnxRuntime
        } else {
            return .other
        }
    }

    private func frameworkForFormat(_ format: ModelFormat) -> LLMFramework {
        switch format {
        case .gguf:
            return .llamaCpp
        case .coreML:
            return .coreML
        case .onnxRuntime:
            return .onnxRuntime
        case .mlx:
            return .mlx
        default:
            return .coreML  // Default to Core ML instead of mock
        }
    }
}
