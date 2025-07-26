//
//  LLMProtocol.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

/// Main protocol composition for LLM services following SOLID principles
protocol LLMService: AnyObject, LLMCapabilities, LLMModelLoader, LLMInference, LLMMetrics {
    /// Framework information
    var frameworkInfo: FrameworkInfo { get }
    
    /// Service name (legacy support)
    var name: String { get }
    
    /// Initialization state (legacy support)
    var isInitialized: Bool { get }
    
    /// Supported models (legacy support)
    var supportedModels: [ModelInfo] { get }
    
    /// Get current model information
    func getModelInfo() -> ModelInfo?
    
    /// Clean up resources
    func cleanup()
    
    /// Service-specific configuration
    func configure(_ options: [String: Any]) throws
    
    /// Health check
    func healthCheck() async -> HealthCheckResult
}

/// Health check result
struct HealthCheckResult {
    let isHealthy: Bool
    let frameworkVersion: String
    let availableMemory: Int64
    let modelLoaded: Bool
    let lastError: Error?
    let diagnostics: [String: Any]
}

/// Extension providing default implementations for legacy methods
extension LLMService {
    /// Legacy initialize method mapped to new loadModel
    func initialize(modelPath: String) async throws {
        try await loadModel(modelPath)
    }
    
    /// Legacy generate method mapped to new inference protocol
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        let request = GenerationRequest(prompt: prompt, options: options)
        let response = try await generate(request)
        return response.text
    }
    
    /// Legacy stream generate mapped to new inference protocol
    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        let request = GenerationRequest(prompt: prompt, options: options)
        for try await token in streamGenerate(request) {
            onToken(token)
        }
    }
}
