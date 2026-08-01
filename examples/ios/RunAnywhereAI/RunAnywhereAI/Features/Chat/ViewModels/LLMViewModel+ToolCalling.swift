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
        options: LlmOptions,
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        // Tool calling is automatic: leaving `options.tools` empty makes the SDK
        // use the `llm.tools` registry, derive the format from the loaded model,
        // and run the tool call → execute → respond loop internally.
        let result = try await RunAnywhere.llm.generate(prompt: prompt, options: options)
        let toolCallInfo = ToolCallInfo(from: result)

        // Drop the write if this generation was superseded while awaiting.
        guard isCurrentGeneration(generationID) else { return }

        // Update the message with the result
        await updateMessageWithToolResult(
            at: messageIndex,
            text: result.text,
            thinkingContent: result.thinkingText,
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
