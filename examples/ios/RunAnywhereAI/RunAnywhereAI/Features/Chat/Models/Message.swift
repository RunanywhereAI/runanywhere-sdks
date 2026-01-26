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
    public let toolCallInfo: ToolCallInfo?

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
        modelInfo: MessageModelInfo? = nil,
        toolCallInfo: ToolCallInfo? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.analytics = analytics
        self.modelInfo = modelInfo
        self.toolCallInfo = toolCallInfo
    }
}

// MARK: - Tool Call Info

public struct ToolCallInfo: Codable, Sendable {
    public let toolName: String
    public let arguments: String  // JSON string for display
    public let result: String?    // JSON string for display
    public let success: Bool
    public let error: String?

    public init(
        toolName: String,
        arguments: [String: ToolValue],
        result: [String: ToolValue]? = nil,
        success: Bool,
        error: String? = nil
    ) {
        self.toolName = toolName
        self.success = success
        self.error = error

        // Convert arguments to JSON string using ToolValue
        self.arguments = ToolValue.object(arguments).toJSONString(pretty: true) ?? "{}"

        // Convert result to JSON string using ToolValue
        if let result = result {
            self.result = ToolValue.object(result).toJSONString(pretty: true)
        } else {
            self.result = nil
        }
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
