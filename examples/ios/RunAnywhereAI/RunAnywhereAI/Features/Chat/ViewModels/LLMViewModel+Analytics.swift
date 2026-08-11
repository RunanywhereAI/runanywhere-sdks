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
        from result: GenerationResult,
        messageId: String,
        conversationId: String,
        wasInterrupted: Bool,
        options: LlmOptions
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
        result: GenerationResult,
        messageId: String,
        conversationId: String,
        modelName: String,
        currentModel: RAModelInfo,
        wasInterrupted: Bool,
        options: LlmOptions
    ) -> MessageAnalytics {
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete
        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature),
            maxTokens: options.maxOutputTokens,
            topP: nil,
            topK: nil
        )
        // Prefer the TTFT carried on the result (streaming sets it). Do not
        // fall back to a separately stamped event-bus value — chat footer and
        // analytics must show the same commons field as benchmarks.
        let ttftMs: Double? = result.timeToFirstTokenMs > 0
            ? Double(result.timeToFirstTokenMs)
            : nil

        // Prefer the turn's own wall clock for total wait time (UI duration).
        // Throughput and token counts come from commons — never reconstruct
        // duration from tokens÷rate, and never second-guess counts with chars/4.
        let generationSeconds = generationStartedAt.map { Date().timeIntervalSince($0) } ?? 0

        let countedTokens = result.outputTokens
        let throughput = countedTokens > 0 ? Double(result.tokensPerSecond) : 0

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: currentModel.framework.wireString,
            timestamp: Date(),
            timeToFirstToken: ttftMs.map { $0 / 1000.0 },
            totalGenerationTime: generationSeconds,
            thinkingTime: nil,
            responseTime: nil,
            inputTokens: result.inputTokens,
            outputTokens: countedTokens,
            thinkingTokens: nil,
            responseTokens: countedTokens,
            averageTokensPerSecond: throughput,
            messageLength: result.text.count,
            wasThinkingMode: result.thinkingText?.isEmpty == false,
            wasInterrupted: wasInterrupted,
            retryCount: 0,
            completionStatus: completionStatus,
            generationMode: useStreaming ? .streaming : .nonStreaming,
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
