//
//  LLMViewModel+Generation.swift
//  RunAnywhereAI
//
//  Message generation functionality for LLMViewModel
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    // MARK: - Streaming Response Generation

    func generateStreamingResponse(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        // v2 close-out Phase G-2: generateStream now returns
        // AsyncStream<RALLMStreamEvent>. Compute metrics locally from the
        // event sequence (no separate metrics Task — the terminal event
        // carries finish_reason and we derive the rest).
        var fullResponse = ""
        var tokenCount = 0
        var firstTokenTime: Date?
        let startTime = Date()
        var finishReason = ""
        var terminalError = ""

        let eventStream = try await RunAnywhere.generateStream(prompt, options: options)
        for await event in eventStream {
            if !event.token.isEmpty {
                if firstTokenTime == nil { firstTokenTime = Date() }
                fullResponse += event.token
                tokenCount += 1
                let displayText = Self.stripThinkTags(from: fullResponse)
                await updateMessageContent(at: messageIndex, content: displayText)
                NotificationCenter.default.post(
                    name: Notification.Name("MessageContentUpdated"),
                    object: nil
                )
            }
            if event.isFinal {
                finishReason = event.finishReason
                terminalError = event.errorMessage
                break
            }
        }

        if !terminalError.isEmpty {
            throw NSError(domain: "RunAnywhereAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: terminalError,
            ])
        }

        _ = finishReason
        let totalLatency = Date().timeIntervalSince(startTime) * 1000
        let ttft = firstTokenTime.map { $0.timeIntervalSince(startTime) * 1000 }

        let modelId = ModelListViewModel.shared.currentModel?.id ?? "unknown"
        let result = LLMGenerationResult(
            text: Self.stripThinkTags(from: fullResponse),
            thinkingContent: nil,
            inputTokens: max(1, prompt.count / 4),
            tokensUsed: tokenCount,
            modelUsed: modelId,
            latencyMs: totalLatency,
            framework: "llamacpp",
            tokensPerSecond: totalLatency > 0 ? Double(tokenCount) / (totalLatency / 1000) : 0,
            timeToFirstTokenMs: ttft,
            thinkingTokens: nil,
            responseTokens: tokenCount
        )

        await updateMessageWithResult(
            at: messageIndex,
            result: result,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    // MARK: - Non-Streaming Response Generation

    func generateNonStreamingResponse(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        let result = try await RunAnywhere.generate(prompt, options: options)
        await updateMessageWithResult(
            at: messageIndex,
            result: result,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    // MARK: - Message Updates

    func updateMessageContent(at index: Int, content: String) async {
        await MainActor.run {
            guard index < self.messagesValue.count else { return }
            let currentMessage = self.messagesValue[index]
            let updatedMessage = Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: content,
                thinkingContent: currentMessage.thinkingContent,
                timestamp: currentMessage.timestamp
            )
            self.updateMessage(at: index, with: updatedMessage)
        }
    }

    func updateMessageWithResult(
        at index: Int,
        result: LLMGenerationResult,
        prompt: String,
        options: LLMGenerationOptions,
        wasInterrupted: Bool
    ) async {
        await MainActor.run {
            guard index < self.messagesValue.count,
                  let conversationId = self.currentConversation?.id else { return }

            let currentMessage = self.messagesValue[index]
            let analytics = self.createAnalytics(
                from: result,
                messageId: currentMessage.id.uuidString,
                conversationId: conversationId,
                wasInterrupted: wasInterrupted,
                options: options
            )

            let modelInfo: MessageModelInfo?
            if let currentModel = ModelListViewModel.shared.currentModel {
                modelInfo = MessageModelInfo(from: currentModel)
            } else {
                modelInfo = nil
            }

            let updatedMessage = Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: result.text,
                thinkingContent: result.thinkingContent,
                timestamp: currentMessage.timestamp,
                analytics: analytics,
                modelInfo: modelInfo
            )
            self.updateMessage(at: index, with: updatedMessage)
            self.updateConversationAnalytics()
        }
    }

    // MARK: - Error Handling

    func handleGenerationError(_ error: Error, at index: Int) async {
        await MainActor.run {
            self.setError(error)

            if index < self.messagesValue.count {
                let errorMessage: String
                if error is LLMError {
                    errorMessage = error.localizedDescription
                } else {
                    errorMessage = "Generation failed: \(error.localizedDescription)"
                }

                let currentMessage = self.messagesValue[index]
                let updatedMessage = Message(
                    id: currentMessage.id,
                    role: currentMessage.role,
                    content: errorMessage,
                    timestamp: currentMessage.timestamp
                )
                self.updateMessage(at: index, with: updatedMessage)
            }
        }
    }

    // MARK: - Finalization

    func finalizeGeneration(at index: Int) async {
        await MainActor.run {
            self.setIsGenerating(false)
        }
        
        guard index < self.messagesValue.count else { return }
        
        // Get the assistant message that was just generated
        let assistantMessage = self.messagesValue[index]
        
        // Get the CURRENT conversation from store (not the stale local copy)
        guard let conversationId = self.currentConversation?.id,
              let conversation = self.conversationStore.conversations.first(where: { $0.id == conversationId }) else {
            return
        }
        
        // Add assistant message to conversation store
        await MainActor.run {
            self.conversationStore.addMessage(assistantMessage, to: conversation)
        }
        
        // Update conversation with all messages and model info
        await MainActor.run {
            if var updatedConversation = self.conversationStore.currentConversation {
                updatedConversation.messages = self.messagesValue
                updatedConversation.modelName = self.loadedModelName
                self.conversationStore.updateConversation(updatedConversation)
                self.setCurrentConversation(updatedConversation)
            }
        }
        
        // Generate smart title immediately after first AI response
        if self.messagesValue.count >= 2 {
            await self.conversationStore.generateSmartTitleForConversation(conversationId)
        }
    }
}
