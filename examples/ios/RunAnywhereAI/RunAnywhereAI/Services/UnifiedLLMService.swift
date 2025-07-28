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
        guard let service = availableServices.first(where: {
            $0.name == framework.displayName
        }) else {
            throw LLMError.serviceNotAvailable(framework.displayName)
        }

        currentService = service
        currentFramework = framework
        currentModel = model
        try await service.initialize(modelPath: model.path ?? "")
    }

    func cleanup() {
        currentService?.cleanup()
        currentService = nil
        currentFramework = nil
        currentModel = nil
    }
}
