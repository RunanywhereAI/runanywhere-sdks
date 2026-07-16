//
//  LLMViewModel+Documents.swift
//  RunAnywhereAI
//
//  Chat-first document questions backed by the SDK RAG pipeline.
//

import Foundation
import RunAnywhere

extension LLMViewModel {
    func sendDocumentQuestion(
        document: ChatDocumentAttachment,
        embeddingModel: RAModelInfo,
        answerModel: RAModelInfo,
        prompt rawPrompt: String
    ) async {
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

        let savedAttachment = persistDocumentAttachment(document)
        let userMessage = Message(role: .user, content: prompt, attachment: savedAttachment)
        let assistantMessage = Message(role: .assistant, content: "")
        setMessages(messagesValue + [userMessage, assistantMessage])

        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let messageIndex = messagesValue.count - 1

        // Track the turn so Stop / conversation-switch cancels it and unlocks the
        // composer (mirrors the text path). ragQuery is a single await with no SDK
        // cancel entry point, so cancellation is observed once it returns.
        let task = Task {
            do {
                try await prepareDocumentRAGPipelineIfNeeded(
                    document: document,
                    embeddingModel: embeddingModel,
                    answerModel: answerModel
                )

                var options = RARAGQueryOptions.defaults(question: prompt)
                let settings = SettingsViewModel.shared
                options.disableThinking =
                    answerModel.supportsThinking && !settings.thinkingModeEnabled

                let result = try await RunAnywhere.ragQuery(options)
                if isCurrentGeneration(generationID) {
                    updateDocumentMessage(
                        at: messageIndex,
                        answer: result.answer,
                        thinkingContent: result.hasThinkingContent ? result.thinkingContent : nil,
                        answerModel: answerModel
                    )
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

    private func persistDocumentAttachment(_ document: ChatDocumentAttachment) -> MessageAttachment {
        let detail = "\(document.characterCount) characters"
        let previewText = String(document.text.prefix(4_000))
        guard let conversationID = currentConversation?.id,
              let data = document.text.data(using: .utf8) else {
            return MessageAttachment(
                kind: .document,
                filename: document.filename,
                detail: detail,
                previewText: previewText
            )
        }

        do {
            return try conversationStore.saveAttachment(
                data: data,
                filename: document.filename,
                kind: .document,
                conversationID: conversationID,
                detail: detail,
                previewText: previewText
            )
        } catch {
            return MessageAttachment(
                kind: .document,
                filename: document.filename,
                detail: detail,
                previewText: previewText
            )
        }
    }

    private func prepareDocumentRAGPipelineIfNeeded(
        document: ChatDocumentAttachment,
        embeddingModel: RAModelInfo,
        answerModel: RAModelInfo
    ) async throws {
        let key = ChatDocumentRAGPipelineKey(
            documentID: document.id,
            embeddingModelID: embeddingModel.id,
            answerModelID: answerModel.id
        )
        guard preparedDocumentRAGPipelineKey != key else { return }

        preparedDocumentRAGPipelineKey = nil
        await RunAnywhere.ragDestroyPipeline()
        try await RunAnywhere.ragCreatePipeline(
            embeddingModel: embeddingModel,
            llmModel: answerModel
        )
        var ragDocument = RARAGDocument()
        ragDocument.text = document.text
        ragDocument.metadata = [
            "source": document.filename,
            "filename": document.filename
        ]
        try await RunAnywhere.ragIngest(ragDocument)
        preparedDocumentRAGPipelineKey = key
    }

    private func updateDocumentMessage(
        at index: Int,
        answer: String,
        thinkingContent: String?,
        answerModel: RAModelInfo
    ) {
        guard index < messagesValue.count else { return }

        let currentMessage = messagesValue[index]
        let updatedMessage = Message(
            id: currentMessage.id,
            role: currentMessage.role,
            content: answer,
            thinkingContent: thinkingContent,
            timestamp: currentMessage.timestamp,
            analytics: nil,
            modelInfo: MessageModelInfo(from: answerModel),
            attachment: currentMessage.attachment
        )
        updateMessage(at: index, with: updatedMessage)
    }
}
