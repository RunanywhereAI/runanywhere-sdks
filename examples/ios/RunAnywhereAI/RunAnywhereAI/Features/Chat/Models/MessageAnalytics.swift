//
//  MessageAnalytics.swift
//  RunAnywhereAI
//
//  Analytics models for message tracking
//

import Foundation

// MARK: - Message Analytics

public struct MessageAnalytics: Codable, Sendable {
    // Identifiers
    let messageId: String
    let conversationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let timestamp: Date

    // Timing Metrics
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let thinkingTime: TimeInterval?
    let responseTime: TimeInterval?

    // Token Metrics
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let responseTokens: Int
    let averageTokensPerSecond: Double

    // Quality Metrics
    let messageLength: Int
    let wasThinkingMode: Bool
    let wasInterrupted: Bool
    let retryCount: Int
    let completionStatus: CompletionStatus

    // Performance Indicators
    let tokensPerSecondHistory: [Double]
    let generationMode: GenerationMode

    // Context Information
    let contextWindowUsage: Double
    let generationParameters: GenerationParameters

    public enum CompletionStatus: String, Codable, Sendable {
        case complete
        case interrupted
        case failed
        case timeout
    }

    public enum GenerationMode: String, Codable, Sendable {
        case streaming
        case nonStreaming
    }

    public struct GenerationParameters: Codable, Sendable {
        let temperature: Double
        let maxTokens: Int
        let topP: Double?
        let topK: Int?

        init(temperature: Double = 0.7, maxTokens: Int = 500, topP: Double? = nil, topK: Int? = nil) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.topP = topP
            self.topK = topK
        }
    }
}

// MARK: - Conversation Analytics

public struct ConversationAnalytics: Codable, Sendable {
    let conversationId: String
    let startTime: Date
    let endTime: Date?
    let messageCount: Int

    // Aggregate Metrics
    let averageTTFT: TimeInterval
    let averageGenerationSpeed: Double
    let totalTokensUsed: Int
    let modelsUsed: Set<String>

    // Efficiency Metrics
    let thinkingModeUsage: Double
    let completionRate: Double
    let averageMessageLength: Int

    // Real-time Metrics
    let currentModel: String?
    let ongoingMetrics: MessageAnalytics?
}
