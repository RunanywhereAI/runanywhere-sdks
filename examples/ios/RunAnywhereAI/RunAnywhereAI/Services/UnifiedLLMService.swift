//
//  UnifiedLLMService.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation
import SwiftUI

@MainActor
class UnifiedLLMService: ObservableObject {
    static let shared = UnifiedLLMService()

    @Published var currentService: LLMService?
    @Published var availableServices: [LLMService] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentFramework: LLMFramework?
    @Published var currentModel: ModelInfo?

    private let container = DependencyContainer.shared

    private init() {
        setupServices()
        observeServiceLifecycle()
    }

    private func setupServices() {
        // Get all available services from the dependency container
        availableServices = container.resolveAll(LLMService.self)
    }

    private func observeServiceLifecycle() {
        container.addObserver(ServiceLifecycleObserverImpl { [weak self] service, event in
            Task { @MainActor in
                switch event {
                case .created:
                    self?.availableServices.append(service)
                case .removed:
                    self?.availableServices.removeAll { $0 === service }
                    if self?.currentService === service {
                        self?.currentService = nil
                    }
                }
            }
        })
    }

    func selectService(named name: String) {
        currentService = availableServices.first { $0.name == name }
    }

    func generate(prompt: String, options: GenerationOptions = .default) async throws -> String {
        guard let service = currentService else {
            throw LLMError.noServiceSelected
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.generate(prompt: prompt, options: options)
            error = nil
            return result
        } catch {
            self.error = error
            throw error
        }
    }

    func streamGenerate(
        prompt: String,
        options: GenerationOptions = .default,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let service = currentService else {
            throw LLMError.noServiceSelected
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await service.streamGenerate(prompt: prompt, options: options, onToken: onToken)
            error = nil
        } catch {
            self.error = error
            throw error
        }
    }

    func loadModel(_ model: ModelInfo, framework: LLMFramework) async throws {
        NSLog("🔍 UnifiedService.loadModel called with model: %@, framework: %@", model.name, framework.displayName)
        guard let service = availableServices.first(where: {
            $0.name == framework.displayName
        }) else {
            throw LLMError.serviceNotAvailable(framework.displayName)
        }

        currentService = service
        currentFramework = framework
        currentModel = model
        
        // Determine the actual model path
        var modelPath = model.path ?? ""
        
        // If path is empty, try to find the model using ModelManager
        if modelPath.isEmpty {
            let modelManager = ModelManager.shared
            let calculatedPath = modelManager.modelPath(for: model.name, framework: framework)
            
            // Check if the model exists at the calculated path
            if FileManager.default.fileExists(atPath: calculatedPath.path) {
                modelPath = calculatedPath.path
                print("UnifiedService: Found model at calculated path: \(modelPath)")
            } else {
                // Try without framework specificity (legacy path)
                let legacyPath = modelManager.modelPath(for: model.name)
                if FileManager.default.fileExists(atPath: legacyPath.path) {
                    modelPath = legacyPath.path
                    print("UnifiedService: Found model at legacy path: \(modelPath)")
                } else {
                    print("UnifiedService: Model not found at calculated paths:")
                    print("  - Framework path: \(calculatedPath.path)")
                    print("  - Legacy path: \(legacyPath.path)")
                    
                    // List what's actually in the Models directory for debugging
                    let modelsDir = ModelManager.modelsDirectory
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: modelsDir.path)
                        print("  - Models directory contents: \(contents.joined(separator: ", "))")
                    } catch {
                        print("  - Could not read Models directory: \(error)")
                    }
                }
            }
        }
        
        print("UnifiedService: Initializing \(framework.displayName) service with model path: '\(modelPath)'")
        try await service.initialize(modelPath: modelPath)
    }

    func cleanup() {
        currentService?.cleanup()
        currentService = nil
        currentFramework = nil
        currentModel = nil
    }
}
