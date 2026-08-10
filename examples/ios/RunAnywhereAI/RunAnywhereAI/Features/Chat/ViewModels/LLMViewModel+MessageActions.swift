//
//  LLMViewModel+MessageActions.swift
//  RunAnywhereAI
//
//  Per-message actions: regenerate a reply, edit a question, delete an exchange.
//
//  Every one of these ends at the same two primitives the typed path uses —
//  `beginGeneration()` + `executeGeneration(prompt:messageIndex:generationID:)`
//  — so a regenerated turn gets identical tool routing, supersede guards, error
//  handling, and finalization. A second generation entry point would be a second
//  place for the `activeGenerationID` bookkeeping to drift out of sync, and that
//  bookkeeping is the only thing keeping a stale stream from writing into the
//  wrong conversation.
//

import Foundation

extension LLMViewModel {
    // MARK: - Regenerate

    /// Replace an assistant reply by re-asking the question above it.
    ///
    /// The reply and everything after it are dropped first: the model must see a
    /// history that ends at the question, exactly as a fresh turn does. Leaving
    /// the old answer in place would condition the retry on the answer it is
    /// supposed to be replacing.
    func regenerateReply(messageID: UUID) {
        guard !isGenerating,
              let replyIndex = messagesValue.firstIndex(where: { $0.id == messageID }),
              messagesValue[replyIndex].role == .assistant,
              let questionIndex = messagesValue[0..<replyIndex].lastIndex(where: { $0.role == .user })
        else { return }

        let prompt = messagesValue[questionIndex].content
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Persist the trimmed transcript before regenerating, so a crash or a
        // force-quit mid-retry reopens the chat at the question rather than
        // showing an answer the user already rejected.
        setMessages(Array(messagesValue[0...questionIndex]))
        persistVisibleMessages()

        beginGeneration()

        var pending = messagesValue
        pending.append(Message(role: .assistant, content: ""))
        setMessages(pending)

        let messageIndex = pending.count - 1
        let generationID = activeGenerationID
        setGenerationTask(
            Task { [weak self] in
                await self?.executeGeneration(
                    prompt: prompt,
                    messageIndex: messageIndex,
                    generationID: generationID
                )
            }
        )
    }

    // MARK: - Edit

    /// Put a question back in the composer and rewind the transcript to just
    /// before it, so sending again continues from that point.
    ///
    /// Deliberately does not auto-send: the whole reason to edit is to change the
    /// wording, and an edit that fires immediately gives the user nowhere to do
    /// that.
    func editQuestion(messageID: UUID) {
        guard !isGenerating,
              let index = messagesValue.firstIndex(where: { $0.id == messageID }),
              messagesValue[index].role == .user
        else { return }

        currentInput = messagesValue[index].content
        setMessages(Array(messagesValue[0..<index]))
        persistVisibleMessages()
    }

    // MARK: - Delete

    /// Delete a message. Deleting a question also deletes the reply it produced.
    ///
    /// A question and its answer are one exchange: keeping the answer would leave
    /// a reply with nothing to reply to, and `makeChatMessages` would then feed
    /// the model an unanchored assistant turn. Deleting an answer on its own is
    /// fine — the question stands, and Regenerate is right there.
    func deleteMessage(id: UUID) {
        guard !isGenerating,
              let index = messagesValue.firstIndex(where: { $0.id == id })
        else { return }

        var upperBound = index
        if messagesValue[index].role == .user,
           index + 1 < messagesValue.count,
           messagesValue[index + 1].role == .assistant {
            upperBound = index + 1
        }

        var remaining = messagesValue
        remaining.removeSubrange(index...upperBound)
        setMessages(remaining)
        persistVisibleMessages()
    }

    // MARK: - Persistence

    /// Write the visible transcript over the stored one.
    ///
    /// `ConversationStore.addMessage` only appends, so it cannot express a
    /// deletion or a rewind; `updateConversation` replacing the whole array is
    /// the only mutator that can. Reads the stored conversation rather than the
    /// local copy so a title generated in the background isn't clobbered.
    func persistVisibleMessages() {
        guard let id = currentConversation?.id,
              var stored = conversationStore.conversations.first(where: { $0.id == id })
        else { return }

        stored.messages = messagesValue
        conversationStore.updateConversation(stored)

        // `updateConversation` stamps `updatedAt`, so read the stored value back
        // rather than keeping a copy that claims an older timestamp.
        if let refreshed = conversationStore.conversations.first(where: { $0.id == id }) {
            setCurrentConversation(refreshed)
        }
    }
}
