//
//  LLMProtocol.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

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
