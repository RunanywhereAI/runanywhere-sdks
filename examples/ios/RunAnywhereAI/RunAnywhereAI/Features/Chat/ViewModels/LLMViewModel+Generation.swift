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
        // The SDK's `aggregateStream(prompt:events:onToken:)` consumes the
        // RALLMStreamEvent sequence, populates the canonical
        // RALLMGenerationResult (including `framework` resolved from the
        // currently-loaded LLM model), and invokes `onToken` for live UI
        // updates. Avoids the synthetic result construction the example used
        // to do alongside a hardcoded `framework = "llamacpp"` literal.
        let request = Self.makeRequest(prompt: prompt, options: options)
        let eventStream = try await RunAnywhere.generateStream(request)
        let result = await RunAnywhere.aggregateStream(
            prompt: prompt,
            events: eventStream
        ) { fullResponse in
            await MainActor.run {
                // `@Observable` publishes the message mutation; the chat view
                // auto-scrolls via `.onChange(of: messages.last?.content)`.
                self.updateMessageContent(at: messageIndex, content: fullResponse)
            }
        }

        if !result.errorMessage.isEmpty {
            throw NSError(domain: "RunAnywhereAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: result.errorMessage
            ])
        }

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
        // Canonical embedded options (request field 26): commons prefers these
        // over the deprecated inline scalars and they carry the knobs the
        // inline fields lack (disable_thinking, thinking_pattern, …).
        request.options = options
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
