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
        var fullResponse = ""

        let streamingResult = try await RunAnywhere.generateStream(prompt, options: options)
        let stream = streamingResult.stream
        let metricsTask = streamingResult.result

        for try await token in stream {
            fullResponse += token
            await updateMessageContent(at: messageIndex, content: fullResponse)
            NotificationCenter.default.post(
                name: Notification.Name("MessageContentUpdated"),
                object: nil
            )
        }

        let sdkResult = try await metricsTask.value
        await updateMessageWithResult(
            at: messageIndex,
            result: sdkResult,
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

            if index < self.messagesValue.count,
               let conversation = self.currentConversation {
                var updatedConversation = conversation
                updatedConversation.messages = self.messagesValue
                updatedConversation.modelName = self.loadedModelName
                self.conversationStore.updateConversation(updatedConversation)
            }
        }
    }
}
