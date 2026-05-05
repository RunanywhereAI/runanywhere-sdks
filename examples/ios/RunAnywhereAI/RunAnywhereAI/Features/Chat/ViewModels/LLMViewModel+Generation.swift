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
        options: RALLMGenerationOptions,
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

        let request = Self.makeRequest(prompt: prompt, options: options)
        let eventStream = try await RunAnywhere.generateStream(request)
        for await event in eventStream {
            if !event.token.isEmpty {
                if firstTokenTime == nil { firstTokenTime = Date() }
                fullResponse += event.token
                tokenCount += 1
                let displayText = Self.stripThinkTags(from: fullResponse)
                updateMessageContent(at: messageIndex, content: displayText)
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
        var result = RALLMGenerationResult()
        result.text = Self.stripThinkTags(from: fullResponse)
        result.inputTokens = Int32(max(1, prompt.count / 4))
        result.tokensGenerated = Int32(tokenCount)
        result.modelUsed = modelId
        result.generationTimeMs = totalLatency
        result.framework = "llamacpp"
        result.tokensPerSecond = totalLatency > 0 ? Double(tokenCount) / (totalLatency / 1000) : 0
        if let ttft {
            result.ttftMs = ttft
        }
        result.responseTokens = Int32(tokenCount)

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
        options: RALLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        let request = Self.makeRequest(prompt: prompt, options: options)
        let result = try await RunAnywhere.generate(request)
        await updateMessageWithResult(
            at: messageIndex,
            result: result,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    /// Compose a canonical `RALLMGenerateRequest` from a prompt and options.
    /// Example-local convenience for bridging the app's options-based API into
    /// the SDK's canonical request-based entry points.
    static func makeRequest(prompt: String, options: RALLMGenerationOptions) -> RALLMGenerateRequest {
        var request = RALLMGenerateRequest()
        request.prompt = prompt
        request.maxTokens = options.maxTokens
        request.temperature = options.temperature
        request.topP = options.topP
        request.topK = options.topK
        request.systemPrompt = options.systemPrompt
        request.stopSequences = options.stopSequences
        request.streamingEnabled = options.streamingEnabled
        return request
    }

    // MARK: - Message Updates

    func updateMessageContent(at index: Int, content: String) {
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

    func updateMessageWithResult(
        at index: Int,
        result: RALLMGenerationResult,
        prompt: String,
        options: RALLMGenerationOptions,
        wasInterrupted: Bool
    ) async {
        // LLMViewModel is @MainActor (class-level); this extension inherits that
        // isolation so a MainActor.run wrapper here is a no-op that only adds an
        // artificial suspension point on the streaming hot path.
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
            thinkingContent: result.hasThinkingContent ? result.thinkingContent : nil,
            timestamp: currentMessage.timestamp,
            analytics: analytics,
            modelInfo: modelInfo
        )
        self.updateMessage(at: index, with: updatedMessage)
        self.updateConversationAnalytics()
    }

    // MARK: - Error Handling

    func handleGenerationError(_ error: Error, at index: Int) async {
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

    // MARK: - Finalization

    func finalizeGeneration(at index: Int) async {
        self.setIsGenerating(false)

        guard index < self.messagesValue.count else { return }

        let assistantMessage = self.messagesValue[index]

        // Use the CURRENT conversation from store (not the stale local copy).
        guard let conversationId = self.currentConversation?.id,
              let conversation = self.conversationStore.conversations.first(where: { $0.id == conversationId }) else {
            return
        }

        self.conversationStore.addMessage(assistantMessage, to: conversation)

        if var updatedConversation = self.conversationStore.currentConversation {
            updatedConversation.messages = self.messagesValue
            updatedConversation.modelName = self.loadedModelName
            self.conversationStore.updateConversation(updatedConversation)
            self.setCurrentConversation(updatedConversation)
        }

        if self.messagesValue.count >= 2 {
            await self.conversationStore.generateSmartTitleForConversation(conversationId)
        }
    }
}
