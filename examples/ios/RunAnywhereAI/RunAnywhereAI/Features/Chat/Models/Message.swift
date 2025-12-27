//
//  Message.swift
//  RunAnywhereAI
//
//  Message models for chat functionality
//

import Foundation
import RunAnywhere

// MARK: - Message Model

public struct Message: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let thinkingContent: String?
    public let timestamp: Date
    public let analytics: MessageAnalytics?
    public let modelInfo: MessageModelInfo?

    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        thinkingContent: String? = nil,
        timestamp: Date = Date(),
        analytics: MessageAnalytics? = nil,
        modelInfo: MessageModelInfo? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.analytics = analytics
        self.modelInfo = modelInfo
    }
}

// MARK: - Message Model Info

public struct MessageModelInfo: Codable, Sendable {
    public let modelId: String
    public let modelName: String
    public let framework: String

    public init(from modelInfo: ModelInfo) {
        self.modelId = modelInfo.id
        self.modelName = modelInfo.name
        self.framework = modelInfo.framework.rawValue
    }
}
