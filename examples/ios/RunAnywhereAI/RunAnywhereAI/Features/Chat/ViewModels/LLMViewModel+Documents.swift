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

        let userMessage = Message(role: .user, content: "Document attached: \(document.filename)\n\(prompt)")
        let assistantMessage = Message(role: .assistant, content: "")
        setMessages(messagesValue + [userMessage, assistantMessage])

        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let messageIndex = messagesValue.count - 1

        do {
            try await RunAnywhere.ragCreatePipeline(
                embeddingModel: embeddingModel,
                llmModel: answerModel
            )
            try await RunAnywhere.ragIngest(
                text: document.text,
                metadataJSON: document.metadataJSON
            )

            var options = RARAGQueryOptions.defaults(question: prompt)
            let settings = SettingsViewModel.shared
            options.disableThinking =
                settings.loadedModelSupportsThinking && !settings.thinkingModeEnabled

            let result = try await RunAnywhere.ragQuery(options)
            updateDocumentMessage(
                at: messageIndex,
                answer: result.answer,
                thinkingContent: result.hasThinkingContent ? result.thinkingContent : nil,
                answerModel: answerModel
            )
        } catch {
            await handleGenerationError(error, at: messageIndex)
        }

        await finalizeGeneration(at: messageIndex)
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
            modelInfo: MessageModelInfo(from: answerModel)
        )
        updateMessage(at: index, with: updatedMessage)
    }
}
