//
//  ChatMessage.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinkingContent: String?  // Stores the model's thinking/reasoning
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, thinkingContent: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
    }
}

// Type alias for consistency
typealias Message = ChatMessage
