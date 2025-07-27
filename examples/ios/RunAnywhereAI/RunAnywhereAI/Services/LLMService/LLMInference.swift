//
//  LLMInference.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Generation request with all parameters
struct GenerationRequest {
    let prompt: String
    let systemPrompt: String?
    let messages: [ChatMessage]?
    let options: GenerationOptions
    let images: [Data]?
    let stopSequences: [String]
    let seed: Int?
    
    init(
        prompt: String,
        systemPrompt: String? = nil,
        messages: [ChatMessage]? = nil,
        options: GenerationOptions = .default,
        images: [Data]? = nil,
        stopSequences: [String] = [],
        seed: Int? = nil
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.options = options
        self.images = images
        self.stopSequences = stopSequences
        self.seed = seed
    }
}

/// Generation response with metadata
struct GenerationResponse {
    let text: String
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval
    let totalTime: TimeInterval
    let tokensPerSecond: Double
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let finishReason: FinishReason
    let metadata: [String: Any]
    
    var formattedSpeed: String {
        String(format: "%.1f tokens/s", tokensPerSecond)
    }
    
    var formattedTime: String {
        String(format: "%.2fs", totalTime)
    }
}

/// Reason for generation completion
enum FinishReason: String {
    case completed = "completed"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case error = "error"
    case cancelled = "cancelled"
}

/// Protocol for inference capabilities
protocol LLMInference {
    /// Generate text synchronously
    func generate(_ request: GenerationRequest) async throws -> GenerationResponse
    
    /// Stream generation with token callback
    func streamGenerate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error>
    
    /// Cancel ongoing generation
    func cancelGeneration() async
    
    /// Check if model is ready for inference
    var isReadyForInference: Bool { get }
    
    /// Get current generation state
    var generationState: GenerationState { get }
}

/// Generation state
enum GenerationState {
    case idle
    case generating(progress: GenerationProgress)
    case completed(response: GenerationResponse)
    case failed(error: Error)
    case cancelled
}

/// Generation progress information
struct GenerationProgress {
    let tokensGenerated: Int
    let estimatedTotal: Int?
    let currentSpeed: Double
    let elapsedTime: TimeInterval
}