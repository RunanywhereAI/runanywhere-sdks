//
//  ModelListViewModel.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation
import SwiftUI

@MainActor
class ModelListViewModel: ObservableObject {
    @Published var availableServices: [LLMService] = []
    @Published var currentService: LLMService?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let llmService = UnifiedLLMService.shared
    
    init() {
        loadServices()
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
                try await service.initialize(modelPath: model.name)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
}