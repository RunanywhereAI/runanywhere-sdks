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
        options: LlmOptions,
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        let chatMessages = Self.makeChatMessages(
            from: self.messagesValue,
            currentUserIndex: messageIndex - 1,
            prompt: prompt
        )
        let stream = try await RunAnywhere.llm.generateStream(messages: chatMessages, options: options)

        var answer = ""
        var thinking = ""

        for try await event in stream {
            switch event {
            case .reasoningDelta(_, _, _, _, let text):
                thinking += text
                // Drop thoughts from a superseded generation (user navigated away).
                guard isCurrentGeneration(generationID) else { continue }
                updateMessageThinking(at: messageIndex, content: thinking)

            case .textDelta(_, _, _, _, let text):
                answer += text
                // Drop tokens from a superseded generation (user navigated away).
                guard isCurrentGeneration(generationID) else { continue }
                // `@Observable` publishes the message mutation; the chat view
                // auto-scrolls via `.onChange(of: messages.last?.content)`.
                updateMessageContent(at: messageIndex, content: answer)

            case .completed(_, let result):
                guard isCurrentGeneration(generationID) else { return }
                await updateMessageWithResult(
                    at: messageIndex,
                    result: result,
                    prompt: prompt,
                    options: options,
                    wasInterrupted: false
                )

            default:
                break
            }
        }
    }

    // MARK: - Non-Streaming Response Generation

    func generateNonStreamingResponse(
        prompt: String,
        options: LlmOptions,
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        let chatMessages = Self.makeChatMessages(
            from: self.messagesValue,
            currentUserIndex: messageIndex - 1,
            prompt: prompt
        )
        let result = try await RunAnywhere.llm.generate(messages: chatMessages, options: options)
        guard isCurrentGeneration(generationID) else { return }
        await updateMessageWithResult(
            at: messageIndex,
            result: result,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    /// Map the app's prior `Message`s plus the live user turn into the SDK's
    /// conversation shape, so commons renders the model's chat template with the
    /// earlier turns in place. Without them every turn is sent context-free and
    /// the model cannot recall earlier messages.
    ///
    /// Excludes the empty assistant slot being streamed into (it lives at
    /// `currentUserIndex + 1`) and any `system` turns — the system prompt travels
    /// separately via `options.systemPrompt`.
    static func makeChatMessages(
        from messages: [Message],
        currentUserIndex: Int,
        prompt: String
    ) -> [ChatMessage] {
        // Clamp the upper bound: `currentUserIndex` is captured before `await`s,
        // so if the user switched/cleared the conversation mid-generation the
        // buffer may now be shorter and an unclamped slice would crash (range out
        // of bounds).
        let end = min(max(currentUserIndex, 0), messages.count)
        var history: [ChatMessage] = []
        for message in messages[0..<end] {
            let role: ChatMessage.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: continue
            }
            guard !message.content.isEmpty else { continue }
            // Skip assistant error placeholders ("Generation failed…" / an
            // LLMError description): these are UI-only feedback, never real
            // model output, so they must not pollute the conversation history.
            if role == .assistant, message.isError == true { continue }
            // Collapse consecutive same-role turns (e.g. a dropped assistant turn
            // leaves two user turns back-to-back). Many chat templates require a
            // strictly alternating history and reject repeats; keep the most
            // recent turn of any same-role run.
            if history.last?.role == role { history.removeLast() }
            history.append(ChatMessage(role: role, content: message.content))
        }
        if history.last?.role == .user { history.removeLast() }
        return history + [ChatMessage(role: .user, content: prompt)]
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

    func updateMessageThinking(at index: Int, content: String) {
        guard index < self.messagesValue.count else { return }
        let currentMessage = self.messagesValue[index]
        let updatedMessage = Message(
            id: currentMessage.id,
            role: currentMessage.role,
            content: currentMessage.content,
            thinkingContent: content,
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
        result: GenerationResult,
        prompt: String,
        options: LlmOptions,
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
            thinkingContent: result.thinkingText,
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
                attachment: currentMessage.attachment,
                isError: true
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
