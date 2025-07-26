//
//  LLMProtocol.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

enum LLMError: LocalizedError {
    case notInitialized
    case modelNotFound
    case insufficientMemory
    case generationFailed(String)
    case noServiceSelected
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "LLM service is not initialized"
        case .modelNotFound:
            return "Model file not found"
        case .insufficientMemory:
            return "Insufficient memory to load model"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .noServiceSelected:
            return "No LLM service selected"
        }
    }
}

protocol LLMService: AnyObject {
    var name: String { get }
    var isInitialized: Bool { get }
    var supportedModels: [ModelInfo] { get }
    
    func initialize(modelPath: String) async throws
    func generate(prompt: String, options: GenerationOptions) async throws -> String
    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws
    func getModelInfo() -> ModelInfo?
    func cleanup()
}