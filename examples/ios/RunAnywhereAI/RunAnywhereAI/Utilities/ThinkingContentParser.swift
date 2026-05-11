//
//  ThinkingContentParser.swift
//  RunAnywhereAI
//
//  Pure Swift helper for parsing `<think>...</think>` blocks from raw model
//  output text. Used by callers that work on raw strings rather than the
//  proto-backed `RALLMGenerationResult` (which already exposes
//  `thinkingContent` / `text` separately):
//
//    - Streaming token accumulation: tokens are appended to a buffer for live
//      UI preview; the SDK's terminal `RALLMGenerationResult` is consumed for
//      the final analytics-aware update.
//    - Tool calling: `RAToolCallingResult.text` carries raw text with
//      `<think>` tags inline; the proto has no thinking_content field.
//    - RAG: `RARAGResult.answer` likewise carries raw text with `<think>` tags
//      embedded; the proto has no thinking_content field.
//
//  Mirrors the byte-for-byte behavior of the deleted commons C ABI
//  (rac_llm_extract_thinking / rac_llm_strip_thinking).
//

import Foundation

enum ThinkingContentParser {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    /// Extract the FIRST `<think>...</think>` block. Returns the trimmed
    /// remainder + the inside-block content (or nil if absent).
    static func extract(from text: String) -> (text: String, thinking: String?) {
        guard let openRange = text.range(of: openTag),
              let closeRange = text.range(of: closeTag),
              openRange.upperBound <= closeRange.lowerBound else {
            return (text: text, thinking: nil)
        }

        let thinking = String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = String(text[..<openRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(text[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var response = ""
        if !before.isEmpty { response = before }
        if !after.isEmpty {
            if !response.isEmpty { response += "\n" }
            response += after
        }

        return (text: response, thinking: thinking.isEmpty ? nil : thinking)
    }

    /// Strip ALL `<think>...</think>` blocks (including multiple blocks +
    /// trailing unclosed `<think>` from streaming output).
    static func strip(from text: String) -> String {
        var buffer = text

        // Remove all complete <think>...</think> blocks.
        while let openRange = buffer.range(of: openTag) {
            guard let closeRange = buffer.range(of: closeTag,
                                                range: openRange.upperBound..<buffer.endIndex) else {
                break
            }
            buffer.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }

        // Drop trailing unclosed <think>... (still streaming).
        if let trailingOpen = buffer.range(of: openTag, options: .backwards) {
            if buffer.range(of: closeTag,
                            range: trailingOpen.upperBound..<buffer.endIndex) == nil {
                buffer.removeSubrange(trailingOpen.lowerBound..<buffer.endIndex)
            }
        }

        return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
