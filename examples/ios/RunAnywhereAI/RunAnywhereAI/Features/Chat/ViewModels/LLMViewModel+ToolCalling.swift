//
//  LLMViewModel+ToolCalling.swift
//  RunAnywhereAI
//
//  Tool calling generation functionality for LLMViewModel
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    // MARK: - Tool Calling Generation

    func generateWithToolCalling(
        prompt: String,
        options: RALLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        // The SDK derives the tool-calling format from the loaded model and
        // orchestrates the tool call → execute → respond loop internally.
        let result = try await RunAnywhere.generateWithTools(prompt: prompt, options: options)

        // Tool call metadata is embedded in the result text (the SDK orchestrates
        // tool call → execute → respond internally). No separate toolCalls/toolResults
        // fields exist on RALLMGenerationResult; ToolCallInfo is unavailable here.
        let toolCallInfo: ToolCallInfo? = nil

        // Split `<think>...</think>` content from the response so the UI can render
        // the thinking block separately and avoid silently dropping SDK-provided
        // thinking content on the tool-calling path.
        let (displayText, thinkingContent) = ThinkingContentParser.extract(from: result.text)

        // Update the message with the result
        await updateMessageWithToolResult(
            at: messageIndex,
            text: displayText,
            thinkingContent: thinkingContent,
            toolCallInfo: toolCallInfo
        )
    }

    // MARK: - Message Updates

    func updateMessageWithToolResult(
        at index: Int,
        text: String,
        thinkingContent: String?,
        toolCallInfo: ToolCallInfo?
    ) async {
        await MainActor.run {
            guard index < self.messagesValue.count else { return }

            let currentMessage = self.messagesValue[index]

            let modelInfo: MessageModelInfo?
            if let currentModel = ModelListViewModel.shared.currentModel {
                modelInfo = MessageModelInfo(from: currentModel)
            } else {
                modelInfo = nil
            }

            let updatedMessage = Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: text,
                thinkingContent: thinkingContent,
                timestamp: currentMessage.timestamp,
                analytics: nil, // Tool calling doesn't use standard analytics
                modelInfo: modelInfo,
                toolCallInfo: toolCallInfo
            )

            self.updateMessage(at: index, with: updatedMessage)

            // Save conversation
            if let conversation = self.currentConversation {
                var updatedConversation = conversation
                updatedConversation.messages = self.messagesValue
                updatedConversation.modelName = self.loadedModelName
                self.conversationStore.updateConversation(updatedConversation)
            }
        }
    }
}
