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
        from result: RALLMGenerationResult,
        messageId: String,
        conversationId: String,
        wasInterrupted: Bool,
        options: RALLMGenerationOptions
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
        result: RALLMGenerationResult,
        messageId: String,
        conversationId: String,
        modelName: String,
        currentModel: RAModelInfo,
        wasInterrupted: Bool,
        options: RALLMGenerationOptions
    ) -> MessageAnalytics {
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete
        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature),
            maxTokens: Int(options.maxTokens),
            topP: nil,
            topK: nil
        )
        // Prefer the TTFT carried on the result (streaming sets it); fall back
        // to the value recorded from the SDK's first-token event. Mirrors
        // Android ChatViewModel.buildStats.
        let ttftMs = result.timeToFirstTokenMs ?? activeGenerationTTFTMs

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: result.framework.isEmpty ? currentModel.framework.wireString : result.framework,
            timestamp: Date(),
            timeToFirstToken: ttftMs.map { $0 / 1000.0 },
            totalGenerationTime: result.latencyMs / 1000.0,
            thinkingTime: nil,
            responseTime: nil,
            inputTokens: Int(result.inputTokens),
            outputTokens: result.tokensUsed,
            thinkingTokens: result.thinkingTokens > 0 ? Int(result.thinkingTokens) : nil,
            responseTokens: result.responseTokens > 0 ? Int(result.responseTokens) : result.tokensUsed,
            averageTokensPerSecond: result.tokensPerSecond,
            messageLength: result.text.count,
            wasThinkingMode: result.hasThinkingContent,
            wasInterrupted: wasInterrupted,
            retryCount: 0,
            completionStatus: completionStatus,
            generationMode: options.streamingEnabled ? .streaming : .nonStreaming,
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
        // Persist the live transcript, not `currentConversation`'s stale snapshot
        // (which lags a full turn and is empty on a brand-new conversation). Without
        // this, an analytics write during a turn whose assistant reply finalizes
        // empty — where `finalizeGeneration` early-returns before its own repair —
        // overwrites the on-disk conversation with a truncated message list and
        // drops the user's just-sent message. Mirrors the tool-calling path.
        updatedConversation.messages = messages
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
