//
//  LLMViewModel+Vision.swift
//  RunAnywhereAI
//
//  Chat-first image questions backed by the SDK VLM component.
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    func sendImageQuestion(image: RAVLMImage, prompt rawPrompt: String) async {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        currentInput = ""
        setIsGenerating(true)
        setError(nil)

        if currentConversation == nil {
            setCurrentConversation(conversationStore.createConversation())
        }

        let userMessage = Message(role: .user, content: "Image attached\n\(prompt)")
        let assistantMessage = Message(role: .assistant, content: "")
        setMessages(messagesValue + [userMessage, assistantMessage])

        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let messageIndex = messagesValue.count - 1

        do {
            try ensureVisionModelLoaded()

            var options = RAVLMGenerationOptions.defaults(prompt: prompt)
            options.maxTokens = 500

            let stream = try await RunAnywhere.processImageStream(image, options: options)
            let response = try await consumeVisionStream(stream, messageIndex: messageIndex)
            updateVisionMessage(at: messageIndex, response: response)
        } catch {
            await handleGenerationError(error, at: messageIndex)
        }

        await finalizeGeneration(at: messageIndex)
    }

    private func ensureVisionModelLoaded() throws {
        var request = RACurrentModelRequest()
        request.category = .multimodal
        guard RunAnywhere.currentModel(request).found else {
            throw LLMError.custom("Choose or download a vision model before asking about an image.")
        }
    }

    private func consumeVisionStream(
        _ stream: AsyncStream<RAVLMStreamEvent>,
        messageIndex: Int
    ) async throws -> String {
        var fullResponse = ""

        for await event in stream {
            switch event.kind {
            case .token:
                guard !event.token.isEmpty else { continue }
                fullResponse += event.token
                updateMessageContent(at: messageIndex, content: fullResponse)
            case .completed:
                if fullResponse.isEmpty, !event.result.text.isEmpty {
                    fullResponse = event.result.text
                    updateMessageContent(at: messageIndex, content: fullResponse)
                }
            case .error:
                throw NSError(
                    domain: "RunAnywhereAI.VisionChat",
                    code: Int(event.errorCode),
                    userInfo: [
                        NSLocalizedDescriptionKey: event.errorMessage.isEmpty
                            ? "Image question failed"
                            : event.errorMessage
                    ]
                )
            default:
                break
            }
        }

        return fullResponse.isEmpty ? "I couldn't produce a response for that image." : fullResponse
    }

    private func updateVisionMessage(at index: Int, response: String) {
        guard index < messagesValue.count else { return }

        let currentMessage = messagesValue[index]
        let updatedMessage = Message(
            id: currentMessage.id,
            role: currentMessage.role,
            content: response,
            thinkingContent: currentMessage.thinkingContent,
            timestamp: currentMessage.timestamp,
            analytics: nil,
            modelInfo: currentVisionModelInfo()
        )
        updateMessage(at: index, with: updatedMessage)
    }

    private func currentVisionModelInfo() -> MessageModelInfo? {
        var request = RACurrentModelRequest()
        request.category = .multimodal
        let snapshot = RunAnywhere.currentModel(request)
        guard snapshot.found else { return nil }

        guard let model = ModelListViewModel.shared.availableModels.first(where: {
            $0.id == snapshot.modelID
        }) else {
            return nil
        }

        return MessageModelInfo(from: model)
    }
}
