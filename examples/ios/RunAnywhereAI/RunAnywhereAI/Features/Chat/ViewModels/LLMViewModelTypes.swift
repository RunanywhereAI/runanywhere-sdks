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

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model is loaded. Please select and load a model from the Models tab first."
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
