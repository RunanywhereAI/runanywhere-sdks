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
    public let attachment: MessageAttachment?

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
        toolCallInfo: ToolCallInfo? = nil,
        attachment: MessageAttachment? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.analytics = analytics
        self.modelInfo = modelInfo
        self.toolCallInfo = toolCallInfo
        self.attachment = attachment
    }
}

// MARK: - Message Attachment

public struct MessageAttachment: Identifiable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image
        case document
    }

    public let id: UUID
    public let kind: Kind
    public let filename: String
    public let detail: String?
    public let relativePath: String?
    public let previewText: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        filename: String,
        detail: String? = nil,
        relativePath: String? = nil,
        previewText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.detail = detail
        self.relativePath = relativePath
        self.previewText = previewText
    }

    public var fileURL: URL? {
        guard let relativePath, !relativePath.isEmpty,
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent(relativePath)
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
        arguments: [String: RAToolValue],
        result: [String: RAToolValue]? = nil,
        success: Bool,
        error: String? = nil
    ) {
        self.toolName = toolName
        self.success = success
        self.error = error

        // Convert arguments to JSON string using RAToolValue.
        self.arguments = RAToolValue.object(arguments).toJSONString(pretty: true) ?? "{}"

        // Convert result to JSON string using RAToolValue.
        if let result = result {
            self.result = RAToolValue.object(result).toJSONString(pretty: true)
        } else {
            self.result = nil
        }
    }

    public init(
        toolName: String,
        argumentsJSON: String,
        resultJSON: String? = nil,
        success: Bool,
        error: String? = nil
    ) {
        self.toolName = toolName
        self.arguments = ToolCallInfo.prettyJSONString(argumentsJSON, fallback: "{}")
        self.result = resultJSON.map { ToolCallInfo.prettyJSONString($0, fallback: $0) }
        self.success = success
        self.error = error
    }

    public init?(from toolCallingResult: RAToolCallingResult) {
        guard !toolCallingResult.toolCalls.isEmpty || !toolCallingResult.toolResults.isEmpty else {
            return nil
        }

        if toolCallingResult.toolCalls.count == 1,
           let toolCall = toolCallingResult.toolCalls.first {
            let toolResult = ToolCallInfo.matchingResult(
                for: toolCall,
                in: toolCallingResult.toolResults
            )
            self.init(
                toolName: toolCall.name,
                argumentsJSON: toolCall.argumentsJson,
                resultJSON: toolResult?.resultJson,
                success: toolResult?.success ?? (toolCallingResult.errorCode == 0),
                error: ToolCallInfo.errorMessage(from: toolResult, fallback: toolCallingResult)
            )
            return
        }

        self.init(
            toolName: "\(toolCallingResult.toolCalls.count) tool calls",
            argumentsJSON: ToolCallInfo.callsJSON(toolCallingResult.toolCalls),
            resultJSON: ToolCallInfo.resultsJSON(toolCallingResult.toolResults),
            success: toolCallingResult.errorCode == 0
                && !toolCallingResult.toolResults.contains { !$0.success || $0.hasError },
            error: toolCallingResult.hasErrorMessage ? toolCallingResult.errorMessage : nil
        )
    }

    private static func matchingResult(
        for toolCall: RAToolCall,
        in results: [RAToolResult]
    ) -> RAToolResult? {
        let callID = toolCall.id
        if !callID.isEmpty {
            return results.first { $0.toolCallID == callID }
        }
        return results.first { $0.name == toolCall.name }
    }

    private static func errorMessage(
        from result: RAToolResult?,
        fallback toolCallingResult: RAToolCallingResult
    ) -> String? {
        if let result, result.hasError, !result.error.isEmpty {
            return result.error
        }
        if toolCallingResult.hasErrorMessage, !toolCallingResult.errorMessage.isEmpty {
            return toolCallingResult.errorMessage
        }
        return nil
    }

    private static func callsJSON(_ calls: [RAToolCall]) -> String {
        let payload = calls.map { call in
            [
                "id": call.id,
                "name": call.name,
                "arguments": jsonObject(from: call.argumentsJson) ?? call.argumentsJson
            ] as [String: Any]
        }
        return prettyJSONString(payload, fallback: "[]")
    }

    private static func resultsJSON(_ results: [RAToolResult]) -> String {
        let payload = results.map { result in
            [
                "id": result.toolCallID,
                "name": result.name,
                "success": result.success,
                "result": jsonObject(from: result.resultJson) ?? result.resultJson,
                "error": result.hasError ? result.error : ""
            ] as [String: Any]
        }
        return prettyJSONString(payload, fallback: "[]")
    }

    private static func prettyJSONString(_ rawJSON: String, fallback: String) -> String {
        guard let object = jsonObject(from: rawJSON) else {
            return rawJSON.isEmpty ? fallback : rawJSON
        }
        return prettyJSONString(object, fallback: rawJSON)
    }

    private static func prettyJSONString(_ object: Any, fallback: String) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return string
    }

    private static func jsonObject(from rawJSON: String) -> Any? {
        guard !rawJSON.isEmpty,
              let data = rawJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

// MARK: - Message Model Info

public struct MessageModelInfo: Codable, Sendable {
    public let modelId: String
    public let modelName: String
    public let framework: String

    public init(from modelInfo: RAModelInfo) {
        self.modelId = modelInfo.id
        self.modelName = modelInfo.name
        self.framework = modelInfo.framework.wireString
    }
}
