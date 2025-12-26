//
//  TTSInput.swift
//  RunAnywhere SDK
//
//  Input model for Text-to-Speech operations
//

import Foundation

/// Input for Text-to-Speech synthesis
///
/// Conforms to ComponentInput protocol for integration with the SDK's component system.
public struct TTSInput: ComponentInput, Sendable {

    // MARK: - Properties

    /// Text to synthesize
    public let text: String

    /// Optional SSML markup (overrides text if provided)
    public let ssml: String?

    /// Voice ID override
    public let voiceId: String?

    /// Language override
    public let language: String?

    /// Custom options override
    public let options: TTSOptions?

    // MARK: - Initialization

    public init(
        text: String,
        ssml: String? = nil,
        voiceId: String? = nil,
        language: String? = nil,
        options: TTSOptions? = nil
    ) {
        self.text = text
        self.ssml = ssml
        self.voiceId = voiceId
        self.language = language
        self.options = options
    }

    // MARK: - ComponentInput

    public func validate() throws {
        if text.isEmpty && ssml == nil {
            throw SDKError.tts(.emptyInput, "Text cannot be empty")
        }
    }

    // MARK: - Factory Methods

    /// Create input from plain text
    public static func text(_ text: String) -> TTSInput {
        TTSInput(text: text)
    }

    /// Create input from SSML markup
    public static func ssml(_ ssml: String) -> TTSInput {
        TTSInput(text: "", ssml: ssml)
    }

    /// Create input with voice override
    public static func text(_ text: String, voice: String) -> TTSInput {
        TTSInput(text: text, voiceId: voice)
    }

    /// Create input with language override
    public static func text(_ text: String, language: String) -> TTSInput {
        TTSInput(text: text, language: language)
    }
}
