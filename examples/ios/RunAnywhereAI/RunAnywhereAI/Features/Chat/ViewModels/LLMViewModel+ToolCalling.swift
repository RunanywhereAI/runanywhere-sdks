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
        // Mirror the Android example: run the loop through generateWithTools with
        // an explicit RAToolCallingOptions whose autoExecute=true actually runs
        // the registered tools (the v3 llm.generate path leaves autoExecute
        // false, so it only leaks the raw tool call), with the final-response cap
        // kept separate from the tool decision.
        let loop = try await RunAnywhere.generateWithTools(
            prompt: prompt,
            options: ToolCallingExecutionPolicy.generationOptions(from: options),
            toolOptions: ToolCallingExecutionPolicy.toolOptions()
        )
        if loop.hasErrorMessage {
            throw LLMError.custom(loop.errorMessage)
        }
        // A capable model returns a final answer here; guard against a blank
        // bubble if a weak model finishes the loop without any prose.
        let displayText = loop.text.isEmpty
            ? "The model finished tool calling without a text answer."
            : loop.text
        let toolCallInfo = ToolCallInfo(from: loop)

        // Drop the write if this generation was superseded while awaiting.
        guard isCurrentGeneration(generationID) else { return }

        // Update the message with the result
        await updateMessageWithToolResult(
            at: messageIndex,
            text: displayText,
            thinkingContent: loop.thinkingContent.isEmpty ? nil : loop.thinkingContent,
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
