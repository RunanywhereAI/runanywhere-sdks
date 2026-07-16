//
//  ChatNotificationNames.swift
//  RunAnywhereAI
//
//  Typed names for local chat-only NotificationCenter events.
//

import Foundation

extension Notification.Name {
    static let conversationSelected = Notification.Name("ConversationSelected")
    /// Posted (object: the deleted `Conversation.id` as `UUID`) when a conversation
    /// is deleted, so the chat ViewModel can reset if it was viewing/generating it.
    static let conversationDeleted = Notification.Name("ConversationDeleted")
}
