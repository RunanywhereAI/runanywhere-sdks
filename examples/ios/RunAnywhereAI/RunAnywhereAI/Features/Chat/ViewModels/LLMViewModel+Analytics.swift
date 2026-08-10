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
        // Prefer the TTFT carried on the result (streaming sets it); fall back
        // to the value recorded from the SDK's first-token event. Mirrors
        // Android ChatViewModel.buildStats.
        let ttftMs = result.timeToFirstTokenMs > 0 ? Double(result.timeToFirstTokenMs) : activeGenerationTTFTMs

        // Prefer the turn's own wall clock. `GenerationResult` reports
        // throughput and a token count but no elapsed time, and tokens ÷
        // tokens-per-second is only a duration when the backend actually counted
        // tokens. Division stays as the fallback for a regenerated turn whose
        // start stamp was cleared.
        let generationSeconds = generationStartedAt.map { Date().timeIntervalSince($0) }
            ?? (result.tokensPerSecond > 0 ? Double(result.outputTokens) / Double(result.tokensPerSecond) : 0)

        // Some backends do not count tokens at all. The Apple Foundation Models
        // path hands commons the finished reply as a single stub token
        // (`platform_llm_vtable_generate_stream`), so a 40-word answer arrives
        // as "1 token", and the throughput derived from it read "1000 tok/s ·
        // 0.0s" under every reply on the Mac. A fabricated number is worse than
        // no number: it is the one thing on the row a reader might act on. So
        // when the count cannot be true, the count and the rate are dropped and
        // the row falls back to the time and the measured duration, both of
        // which are real.
        let countedTokens = Self.reportedTokensAreCredible(result) ? result.outputTokens : 0
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

    /// Whether the backend's token count can describe the text it came with.
    ///
    /// Four characters per token is the coarse English average; a reply that
    /// claims fewer than a quarter of the tokens its own length implies did not
    /// come from a tokenizer. Deliberately generous — the test only has to catch
    /// "the backend reported a placeholder", never to second-guess a real count.
    private static func reportedTokensAreCredible(_ result: GenerationResult) -> Bool {
        guard result.outputTokens > 0 else { return false }
        let impliedTokens = max(1, result.text.count / 4)
        return result.outputTokens * 4 >= impliedTokens
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
