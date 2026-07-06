//
//  LLMViewModelTypes.swift
//  RunAnywhereAI
//
//  Supporting types for LLMViewModel
//

import Foundation

// MARK: - LLM Error

enum LLMError: LocalizedError {
    case noModelLoaded
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model is loaded. Please select and load a model from the Models tab first."
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Generation Metrics

struct GenerationMetricsFromSDK: Sendable {
    let generationId: String
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let durationMs: Double
    let tokensPerSecond: Double
    let timeToFirstTokenMs: Double?
}

// MARK: - Document RAG

struct ChatDocumentRAGPipelineKey: Equatable {
    let documentID: UUID
    let embeddingModelID: String
    let answerModelID: String
}
