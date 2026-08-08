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

        let savedAttachment = persistDocumentAttachment(document)
        let userMessage = Message(role: .user, content: prompt, attachment: savedAttachment)
        let assistantMessage = Message(role: .assistant, content: "")
        setMessages(messagesValue + [userMessage, assistantMessage])

        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let messageIndex = messagesValue.count - 1

        // Track the turn so Stop / conversation-switch cancels it and unlocks the
        // composer (mirrors the text path). The RAG query is a single await, so
        // cancellation is observed once it returns.
        let task = Task {
            do {
                let session = try await prepareDocumentRAGSessionIfNeeded(
                    document: document,
                    embeddingModel: embeddingModel,
                    answerModel: answerModel
                )

                let settings = SettingsViewModel.shared
                var reasoning = ReasoningOptions()
                if answerModel.supportsThinking && !settings.thinkingModeEnabled {
                    reasoning.mode = .off
                }
                reasoning.includeInOutput = settings.thinkingModeEnabled
                var generation = LlmOptions()
                generation.reasoning = reasoning

                // Stream the answer: the one-shot query resolves with an empty
                // answer under the v4 RAG pipeline, so accumulate tokens live and
                // fall back to the completed result.
                var answer = ""
                let events = try await session.queryStream(
                    question: prompt,
                    options: RagQueryOptions(generation: generation)
                )
                for try await event in events {
                    guard isCurrentGeneration(generationID) else { break }
                    switch event {
                    case .token(let text, _):
                        answer += text
                        updateDocumentMessage(
                            at: messageIndex,
                            answer: answer,
                            thinkingContent: nil,
                            answerModel: answerModel
                        )
                    case .completed(let result):
                        let finalAnswer = result.answer.isEmpty ? answer : result.answer
                        updateDocumentMessage(
                            at: messageIndex,
                            answer: finalAnswer,
                            thinkingContent: nil,
                            answerModel: answerModel
                        )
                    case .retrieved:
                        break
                    }
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

    /// Reuse the open session while the document and both models are unchanged;
    /// otherwise close it and open a fresh corpus.
    private func prepareDocumentRAGSessionIfNeeded(
        document: ChatDocumentAttachment,
        embeddingModel: RAModelInfo,
        answerModel: RAModelInfo
    ) async throws -> RagSession {
        let key = ChatDocumentRAGPipelineKey(
            documentID: document.id,
            embeddingModelID: embeddingModel.id,
            answerModelID: answerModel.id
        )
        if preparedDocumentRAGPipelineKey == key, let session = documentRAGSession {
            return session
        }

        preparedDocumentRAGPipelineKey = nil
        await documentRAGSession?.close()
        documentRAGSession = nil

        // Indexing is the part that can fail, so the chip tracks it rather than
        // claiming readiness from the model choice alone.
        setDocumentIndexState(.indexing)
        do {
            let session = try await RunAnywhere.rag.open(
                embeddingModel: ModelRef(id: embeddingModel.id),
                llmModel: ModelRef(id: answerModel.id)
            )
            try await session.ingest(document: RagDocument(
                text: document.text,
                metadata: [
                    "source": document.filename,
                    "filename": document.filename
                ]
            ))

            documentRAGSession = session
            preparedDocumentRAGPipelineKey = key
            setDocumentIndexState(.indexed)
            return session
        } catch {
            // Commons now names the cause (e.g. "The embedding model produced no
            // vector …"); carry it verbatim rather than replacing it with a
            // second, vaguer sentence of our own.
            setDocumentIndexState(.failed(error.localizedDescription))
            throw error
        }
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
