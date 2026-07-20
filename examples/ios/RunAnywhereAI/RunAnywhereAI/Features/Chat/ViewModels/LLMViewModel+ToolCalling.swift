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
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        // The SDK derives the tool-calling format from the loaded model and
        // orchestrates the tool call → execute → respond loop internally.
        // parallelToolCalls: true lets one turn request multiple tools (e.g.
        // weather + time) and get them all executed before one follow-up
        // reply, instead of one round-trip per tool.
        let result = try await RunAnywhere.generateWithTools(
            prompt: prompt,
            options: options,
            parallelToolCalls: true
        )
        let toolCallInfo = ToolCallInfo(from: result)

        // Drop the write if this generation was superseded while awaiting.
        guard isCurrentGeneration(generationID) else { return }

        // Update the message with the result
        await updateMessageWithToolResult(
            at: messageIndex,
            text: result.text,
            thinkingContent: result.hasThinkingContent ? result.thinkingContent : nil,
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
            // Drop the final write + persist if the user navigated away mid tool call.
            guard self.isActiveGenerationTarget else { return }
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
                toolCallInfo: toolCallInfo,
                attachment: currentMessage.attachment
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
