//
//  ChatNotificationNames.swift
//  RunAnywhereAI
//
//  Typed names for local chat-only NotificationCenter events.
//

import Foundation

extension Notification.Name {
    /// Posted (object: the deleted `Conversation.id`) when a conversation is
    /// deleted, so the chat ViewModel can reset if it was viewing/generating it.
    /// A broadcast because the store cannot know who is looking at the row.
    static let conversationDeleted = Notification.Name("ConversationDeleted")
}
