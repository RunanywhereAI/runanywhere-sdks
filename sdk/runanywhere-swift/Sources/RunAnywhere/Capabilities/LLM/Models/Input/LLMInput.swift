//
//  LLMInput.swift
//  RunAnywhere SDK
//
//  Input model for LLM generation
//

import Foundation

/// Input for Language Model generation
public struct LLMInput: ComponentInput, Sendable {

    /// Messages in the conversation
    public let messages: [Message]

    /// Optional system prompt override
    public let systemPrompt: String?

    /// Optional context for conversation
    public let context: Context?

    /// Optional generation options override
    public let options: LLMGenerationOptions?

    public init(
        messages: [Message],
        systemPrompt: String? = nil,
        context: Context? = nil,
        options: LLMGenerationOptions? = nil
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.context = context
        self.options = options
    }

    /// Convenience initializer for single prompt
    public init(prompt: String, systemPrompt: String? = nil) {
        self.messages = [Message(role: .user, content: prompt)]
        self.systemPrompt = systemPrompt
        self.context = nil
        self.options = nil
    }

    public func validate() throws {
        guard !messages.isEmpty else {
            throw RunAnywhereError.validationFailed("LLMInput must contain at least one message")
        }
    }
}
