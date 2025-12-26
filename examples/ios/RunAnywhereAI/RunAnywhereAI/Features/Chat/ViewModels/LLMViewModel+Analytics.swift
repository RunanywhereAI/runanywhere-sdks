//
//  LLMViewModel+Analytics.swift
//  RunAnywhereAI
//
//  Analytics-related functionality for LLMViewModel
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    // MARK: - Analytics Creation

    func createAnalytics(
        from result: LLMGenerationResult,
        messageId: String,
        conversationId: String,
        wasInterrupted: Bool,
        options: LLMGenerationOptions
    ) -> MessageAnalytics? {
        guard let modelName = loadedModelName,
              let currentModel = ModelListViewModel.shared.currentModel else {
            return nil
        }

        return buildMessageAnalytics(
            result: result,
            messageId: messageId,
            conversationId: conversationId,
            modelName: modelName,
            currentModel: currentModel,
            wasInterrupted: wasInterrupted,
            options: options
        )
    }

    // swiftlint:disable:next function_parameter_count
    func buildMessageAnalytics(
        result: LLMGenerationResult,
        messageId: String,
        conversationId: String,
        modelName: String,
        currentModel: ModelInfo,
        wasInterrupted: Bool,
        options: LLMGenerationOptions
    ) -> MessageAnalytics {
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete
        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature ?? Float(LLMViewModel.defaultTemperatureValue)),
            maxTokens: options.maxTokens ?? LLMViewModel.defaultMaxTokensValue,
            topP: nil,
            topK: nil
        )

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: result.framework ?? currentModel.framework.rawValue,
            timestamp: Date(),
            timeToFirstToken: nil,
            totalGenerationTime: result.latencyMs / 1000.0,
            thinkingTime: nil,
            responseTime: nil,
            inputTokens: result.inputTokens,
            outputTokens: result.tokensUsed,
            thinkingTokens: result.thinkingTokens,
            responseTokens: result.responseTokens,
            averageTokensPerSecond: result.tokensPerSecond,
            messageLength: result.text.count,
            wasThinkingMode: result.thinkingContent != nil,
            wasInterrupted: wasInterrupted,
            retryCount: 0,
            completionStatus: completionStatus,
            tokensPerSecondHistory: [],
            generationMode: .nonStreaming,
            contextWindowUsage: 0.0,
            generationParameters: generationParameters
        )
    }

    // MARK: - Conversation Analytics

    func updateConversationAnalytics() {
        guard let conversation = currentConversation else { return }

        let analyticsMessages = messages.compactMap { $0.analytics }

        guard !analyticsMessages.isEmpty else { return }

        let conversationAnalytics = computeConversationAnalytics(
            conversation: conversation,
            analyticsMessages: analyticsMessages
        )

        var updatedConversation = conversation
        updatedConversation.analytics = conversationAnalytics
        updatedConversation.performanceSummary = PerformanceSummary(from: messages)
        conversationStore.updateConversation(updatedConversation)
    }

    private func computeConversationAnalytics(
        conversation: Conversation,
        analyticsMessages: [MessageAnalytics]
    ) -> ConversationAnalytics {
        let count = Double(analyticsMessages.count)
        let ttftSum = analyticsMessages.compactMap { $0.timeToFirstToken }.reduce(0, +)
        let averageTTFT = ttftSum / count
        let speedSum = analyticsMessages.map { $0.averageTokensPerSecond }.reduce(0, +)
        let averageGenerationSpeed = speedSum / count
        let totalTokensUsed = analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        let modelsUsed = Set(analyticsMessages.map { $0.modelName })

        let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
        let thinkingModeUsage = Double(thinkingMessages.count) / count

        let completedMessages = analyticsMessages.filter { $0.completionStatus == .complete }
        let completionRate = Double(completedMessages.count) / count

        let averageMessageLength = analyticsMessages.reduce(0) { $0 + $1.messageLength } / analyticsMessages.count

        return ConversationAnalytics(
            conversationId: conversation.id,
            startTime: conversation.createdAt,
            endTime: Date(),
            messageCount: messages.count,
            averageTTFT: averageTTFT,
            averageGenerationSpeed: averageGenerationSpeed,
            totalTokensUsed: totalTokensUsed,
            modelsUsed: modelsUsed,
            thinkingModeUsage: thinkingModeUsage,
            completionRate: completionRate,
            averageMessageLength: averageMessageLength,
            currentModel: loadedModelName,
            ongoingMetrics: nil
        )
    }
}
