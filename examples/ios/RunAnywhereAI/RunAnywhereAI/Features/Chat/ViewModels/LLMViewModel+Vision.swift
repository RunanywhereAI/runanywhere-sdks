//
//  LLMViewModel+Vision.swift
//  RunAnywhereAI
//
//  Chat-first image questions backed by the SDK VLM component.
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    func sendImageQuestion(attachment: ChatImageAttachment, prompt rawPrompt: String) async {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        currentInput = ""
        setIsGenerating(true)
        setError(nil)

        if currentConversation == nil {
            setCurrentConversation(conversationStore.createConversation())
        }

        // Pin this generation to its conversation + give it an identity so late
        // tokens / finalization are dropped if the user switches away.
        setGeneratingConversationId(currentConversation?.id)
        let generationID = UUID()
        setActiveGenerationID(generationID)

        let savedAttachment = persistImageAttachment(attachment)
        let userMessage = Message(role: .user, content: prompt, attachment: savedAttachment)
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

            let stream = try await RunAnywhere.processImageStream(attachment.image, options: options)
            let response = try await consumeVisionStream(
                stream, messageIndex: messageIndex, generationID: generationID
            )
            if isCurrentGeneration(generationID) {
                updateVisionMessage(at: messageIndex, response: response)
            }
        } catch {
            if isCurrentGeneration(generationID) {
                await handleGenerationError(error, at: messageIndex)
            }
        }

        await finalizeGeneration(at: messageIndex, generationID: generationID)
    }

    private func persistImageAttachment(_ attachment: ChatImageAttachment) -> MessageAttachment {
        let detail = ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file)
        guard let conversationID = currentConversation?.id else {
            return MessageAttachment(kind: .image, filename: attachment.filename, detail: detail)
        }

        do {
            return try conversationStore.saveAttachment(
                data: attachment.data,
                filename: attachment.filename,
                kind: .image,
                conversationID: conversationID,
                detail: detail
            )
        } catch {
            return MessageAttachment(kind: .image, filename: attachment.filename, detail: detail)
        }
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
        messageIndex: Int,
        generationID: UUID?
    ) async throws -> String {
        var fullResponse = ""

        for await event in stream {
            switch event.kind {
            case .token:
                guard !event.token.isEmpty else { continue }
                fullResponse += event.token
                // Drop live tokens once superseded (the SDK VLM stream isn't
                // cancelled on navigate-away, so keep draining but stop writing).
                if isCurrentGeneration(generationID) {
                    updateMessageContent(at: messageIndex, content: fullResponse)
                }
            case .completed:
                if fullResponse.isEmpty, !event.result.text.isEmpty {
                    fullResponse = event.result.text
                    if isCurrentGeneration(generationID) {
                        updateMessageContent(at: messageIndex, content: fullResponse)
                    }
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
            modelInfo: currentVisionModelInfo(),
            attachment: currentMessage.attachment
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
