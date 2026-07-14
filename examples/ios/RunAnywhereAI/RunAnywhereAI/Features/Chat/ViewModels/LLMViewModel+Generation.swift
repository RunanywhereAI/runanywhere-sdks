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
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        // The SDK's `aggregateStream(prompt:events:onToken:)` consumes the
        // RALLMStreamEvent sequence, populates the canonical
        // RALLMGenerationResult (including `framework` resolved from the
        // currently-loaded LLM model), and invokes `onToken` for live UI
        // updates. Avoids the synthetic result construction the example used
        // to do alongside a hardcoded `framework = "llamacpp"` literal.
        let history = Self.makeHistory(from: self.messagesValue, currentUserIndex: messageIndex - 1)
        let request = Self.makeRequest(prompt: prompt, options: options, history: history)
        let eventStream = try await RunAnywhere.generateStream(request)
        let result = await RunAnywhere.aggregateStream(
            prompt: prompt,
            events: eventStream
        ) { fullResponse in
            await MainActor.run {
                // Drop tokens from a superseded generation (user navigated away).
                guard self.isCurrentGeneration(generationID) else { return }
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

        guard isCurrentGeneration(generationID) else { return }
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
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        let history = Self.makeHistory(from: self.messagesValue, currentUserIndex: messageIndex - 1)
        let request = Self.makeRequest(prompt: prompt, options: options, history: history)
        let result = try await RunAnywhere.generate(request)
        guard isCurrentGeneration(generationID) else { return }
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
    ///
    /// `history` carries the prior conversation turns so commons renders
    /// `{system_prompt, history, prompt}` via the model's chat template. Without
    /// it every turn is sent context-free and the model cannot recall earlier
    /// messages.
    static func makeRequest(
        prompt: String,
        options: RALLMGenerationOptions,
        history: [RAChatMessage] = []
    ) -> RALLMGenerateRequest {
        var request = RALLMGenerateRequest()
        request.prompt = prompt
        request.options = options
        request.history = history
        return request
    }

    /// Map the app's prior `Message`s into the SDK `history` field.
    ///
    /// Excludes the live user turn and the empty assistant slot being streamed
    /// into (both live at/after `currentUserIndex`), and any `system` turns —
    /// the system prompt travels separately via `options.systemPrompt`.
    static func makeHistory(from messages: [Message], currentUserIndex: Int) -> [RAChatMessage] {
        // Clamp the upper bound: `currentUserIndex` is captured before `await`s,
        // so if the user switched/cleared the conversation mid-generation the
        // buffer may now be shorter and an unclamped slice would crash (range out
        // of bounds).
        let end = min(max(currentUserIndex, 0), messages.count)
        guard end > 0 else { return [] }
        return messages[0..<end].compactMap { message in
            let role: RAMessageRole
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: return nil
            }
            guard !message.content.isEmpty else { return nil }
            var chatMessage = RAChatMessage()
            chatMessage.role = role
            chatMessage.content = message.content
            return chatMessage
        }
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
            timestamp: currentMessage.timestamp,
            analytics: currentMessage.analytics,
            modelInfo: currentMessage.modelInfo,
            toolCallInfo: currentMessage.toolCallInfo,
            attachment: currentMessage.attachment
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
        // Drop the final write + analytics persist if the user navigated away.
        guard isActiveGenerationTarget else { return }
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
            modelInfo: modelInfo,
            toolCallInfo: currentMessage.toolCallInfo,
            attachment: currentMessage.attachment
        )
        self.updateMessage(at: index, with: updatedMessage)
        self.updateConversationAnalytics()
    }

    // MARK: - Error Handling

    func handleGenerationError(_ error: Error, at index: Int) async {
        // Ignore errors from a generation the user has navigated away from, so a
        // stale failure can't raise an error banner / write into the now-active
        // conversation.
        guard isActiveGenerationTarget else { return }
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
                thinkingContent: currentMessage.thinkingContent,
                timestamp: currentMessage.timestamp,
                analytics: currentMessage.analytics,
                modelInfo: currentMessage.modelInfo,
                toolCallInfo: currentMessage.toolCallInfo,
                attachment: currentMessage.attachment
            )
            self.updateMessage(at: index, with: updatedMessage)
        }
    }

    // MARK: - Finalization

    func finalizeGeneration(at index: Int, generationID: UUID?) async {
        // Superseded? If a newer generation started, or the user navigated away
        // (cancelActiveGeneration invalidated the id), this generation is no
        // longer the owner: it must NOT touch isGenerating (the new owner manages
        // it) nor persist. Silently drop.
        guard activeGenerationID == generationID else { return }

        // This generation still owns the chat, so it is the single owner of the
        // isGenerating true->false transition (stopGeneration leaves it to us) —
        // clear it exactly once for a normal completion or a Stop.
        self.setActiveGenerationID(nil)
        self.setIsGenerating(false)

        // Guard the JSON write against a conversation swap that somehow kept the
        // id (should not normally happen once the id matches).
        guard isActiveGenerationTarget else { return }
        self.setGeneratingConversationId(nil)

        guard index < self.messagesValue.count else { return }

        let assistantMessage = self.messagesValue[index]

        // A Stop that produced no assistant text leaves an empty bubble. Drop that
        // empty slot from the visible chat and skip persistence so a cancelled turn
        // with nothing to show doesn't leave an orphan assistant bubble. A partial
        // response the user chose to keep has non-empty content and is preserved
        // and persisted normally below. isGenerating was already cleared above, so
        // the send control is restored either way.
        guard !assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.removeTrailingEmptyAssistantMessage()
            return
        }

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
