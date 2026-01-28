//
//  LLMViewModel+ToolCalling.swift
//  RunAnywhereAI
//
//  Tool calling generation functionality for LLMViewModel
//

import Foundation
import RunAnywhere

extension LLMViewModel {

    // MARK: - Tool Calling Format Detection

    /// Determines the optimal tool calling format based on the model name/ID.
    /// Different models are trained on different tool calling formats.
    private func detectToolCallFormat(for modelName: String?) -> ToolCallFormat {
        guard let name = modelName?.lowercased() else {
            return .default
        }

        // LFM2-Tool models use Pythonic format: <|tool_call_start|>[func(args)]<|tool_call_end|>
        if name.contains("lfm2") && name.contains("tool") {
            return .lfm2
        }

        // FunctionGemma models use custom format: <start_function_call>call:func{args}<end_function_call>
        if name.contains("functiongemma") || name.contains("function-gemma") {
            return .gemma
        }

        // Default JSON format for general-purpose models
        return .default
    }

    // MARK: - Tool Calling Generation

    func generateWithToolCalling(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        // Auto-detect the tool calling format based on the loaded model
        let format = detectToolCallFormat(for: loadedModelName)

        // Get tool calling options with the appropriate format
        let toolOptions = ToolCallingOptions(
            maxToolCalls: 3,
            autoExecute: true,
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            format: format
        )

        // Log the format being used for debugging
        print("Using tool calling with format: \(format.name) for model: \(loadedModelName ?? "unknown")")

        // Generate with tools
        let result = try await RunAnywhere.generateWithTools(prompt, options: toolOptions)

        // Extract tool call info if any tools were called
        let toolCallInfo: ToolCallInfo?
        if let lastCall = result.toolCalls.last,
           let lastResult = result.toolResults.last {
            toolCallInfo = ToolCallInfo(
                toolName: lastCall.toolName,
                arguments: lastCall.arguments,
                result: lastResult.result,
                success: lastResult.success,
                error: lastResult.error
            )
        } else {
            toolCallInfo = nil
        }

        // Update the message with the result
        await updateMessageWithToolResult(
            at: messageIndex,
            text: result.text,
            toolCallInfo: toolCallInfo
        )
    }

    // MARK: - Message Updates

    func updateMessageWithToolResult(
        at index: Int,
        text: String,
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
                thinkingContent: nil,
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
