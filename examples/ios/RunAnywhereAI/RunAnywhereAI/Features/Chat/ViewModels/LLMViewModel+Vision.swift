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

        // Same reason as the text path (`beginGeneration`): the previous turn's
        // title request must release the LLM component before this turn claims it.
        conversationStore.cancelPendingTitleGeneration()

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

        // Track the turn so Stop / conversation-switch can cancel it (mirrors the
        // text path). Cancelling this task terminates the SDK stream, which
        // forwards the cancellation to the native layer.
        let task = Task {
            do {
                try await ensureVisionModelLoaded()

                let stream = try await RunAnywhere.vlm.generateStream(
                    image: attachment.image,
                    prompt: prompt,
                    options: LlmOptions(maxOutputTokens: 500)
                )
                let response = try await consumeVisionStream(
                    stream, messageIndex: messageIndex, generationID: generationID
                )
                if isCurrentGeneration(generationID) {
                    await updateVisionMessage(at: messageIndex, response: response)
                }
            } catch {
                if isCurrentGeneration(generationID) {
                    await handleGenerationError(error, at: messageIndex)
                }
            }

            await finalizeGeneration(at: messageIndex, generationID: generationID)
        }
        setGenerationTask(task)
        await task.value
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

    private func ensureVisionModelLoaded() async throws {
        guard await RunAnywhere.models.state().loaded[.multimodal] != nil else {
            throw LLMError.custom("Choose or download a vision model before asking about an image.")
        }
    }

    private func consumeVisionStream(
        _ stream: AsyncThrowingStream<GenerationEvent, Error>,
        messageIndex: Int,
        generationID: UUID?
    ) async throws -> String {
        var fullResponse = ""

        for try await event in stream {
            switch event {
            case .textDelta(_, _, _, _, let text):
                guard !text.isEmpty else { continue }
                fullResponse += text
                // Drop live tokens once superseded (user navigated away).
                if isCurrentGeneration(generationID) {
                    updateMessageContent(at: messageIndex, content: fullResponse)
                }
            case .completed(_, let result):
                if fullResponse.isEmpty, !result.text.isEmpty {
                    fullResponse = result.text
                    if isCurrentGeneration(generationID) {
                        updateMessageContent(at: messageIndex, content: fullResponse)
                    }
                }
            default:
                break
            }
        }

        return fullResponse.isEmpty ? "I couldn't produce a response for that image." : fullResponse
    }

    private func updateVisionMessage(at index: Int, response: String) async {
        guard index < messagesValue.count else { return }

        let currentMessage = messagesValue[index]
        let updatedMessage = Message(
            id: currentMessage.id,
            role: currentMessage.role,
            content: response,
            thinkingContent: currentMessage.thinkingContent,
            timestamp: currentMessage.timestamp,
            analytics: nil,
            modelInfo: await currentVisionModelInfo(),
            attachment: currentMessage.attachment
        )
        updateMessage(at: index, with: updatedMessage)
    }

    private func currentVisionModelInfo() async -> MessageModelInfo? {
        guard let loadedId = await RunAnywhere.models.state().loaded[.multimodal]?.id else { return nil }

        guard let model = ModelListViewModel.shared.availableModels.first(where: {
            $0.id == loadedId
        }) else {
            return nil
        }

        return MessageModelInfo(from: model)
    }
}
