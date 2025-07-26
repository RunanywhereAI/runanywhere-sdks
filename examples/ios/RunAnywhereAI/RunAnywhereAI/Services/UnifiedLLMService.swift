//
//  UnifiedLLMService.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
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
    
    private init() {
        setupServices()
    }
    
    private func setupServices() {
        // Add all available services
        var services: [LLMService] = [
            MockLLMService(), // For testing
            LlamaCppService(),
        ]
        
        // Add iOS 17+ services
        if #available(iOS 17.0, *) {
            services.append(CoreMLService())
            services.append(MLXService())
        }
        
        availableServices = services
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
}