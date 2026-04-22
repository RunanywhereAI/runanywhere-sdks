//
//  CppBridge+LLMThinking.swift
//  RunAnywhere
//
//  v2 close-out Phase 9 (P2-4). Thin Swift facade over the C ABI in
//  rac/features/llm/rac_llm_thinking.h. Replaces the in-Swift
//  `ThinkingContentParser` class that was deleted from
//  `RunAnywhere+TextGeneration.swift` in this same commit.
//
//  Behavioral parity with the deleted Swift code is locked in by the
//  10-scenario C test (test_llm_thinking) — every Swift unit test that
//  used to exercise ThinkingContentParser maps to one of those scenarios.
//

import CRACommons
import Foundation

/// Drop-in replacement for the deleted `ThinkingContentParser` enum.
///
/// Same surface (`extract`, `splitTokens`, `strip`); the implementation
/// delegates to `rac_llm_*` C symbols so all 5 SDKs render `<think>...</think>`
/// blocks identically.
public enum ThinkingContentParser {

    /// Extracts the first `<think>...</think>` block. Returns the trimmed
    /// remainder + the inside-block content (or nil if absent).
    public static func extract(from text: String) -> (text: String, thinking: String?) {
        return text.withCString { cText in
            var responsePtr: UnsafePointer<CChar>?  = nil
            var responseLen: Int                     = 0
            var thinkingPtr: UnsafePointer<CChar>?  = nil
            var thinkingLen: Int                     = 0

            let rc = rac_llm_extract_thinking(cText,
                                              &responsePtr, &responseLen,
                                              &thinkingPtr, &thinkingLen)
            guard rc == RAC_SUCCESS, let rp = responsePtr else {
                // C ABI failure (NULL inputs etc.) — fall back to original text.
                return (text: text, thinking: nil)
            }

            let response = String(cString: rp)
            let thinking: String? = {
                guard let tp = thinkingPtr, thinkingLen > 0 else { return nil }
                return String(cString: tp)
            }()
            return (text: response, thinking: thinking)
        }
    }

    /// Apportions @p totalCompletionTokens between thinking + response by
    /// the character-length ratio. If `thinkingContent` is nil/empty, all
    /// tokens belong to the response.
    public static func splitTokens(
        totalCompletionTokens: Int,
        responseText: String,
        thinkingContent: String?
    ) -> (thinkingTokens: Int, responseTokens: Int) {
        let thinkingC = thinkingContent ?? ""
        var thinkingOut: Int32 = 0
        var responseOut: Int32 = 0
        let rc = thinkingC.withCString { tPtr in
            return responseText.withCString { rPtr in
                return rac_llm_split_thinking_tokens(
                    Int32(totalCompletionTokens),
                    rPtr,
                    (thinkingContent == nil) ? nil : tPtr,
                    &thinkingOut,
                    &responseOut
                )
            }
        }
        guard rc == RAC_SUCCESS else {
            return (0, totalCompletionTokens)
        }
        return (Int(thinkingOut), Int(responseOut))
    }

    /// Strips ALL `<think>...</think>` blocks (including multiple blocks +
    /// trailing unclosed `<think>` from streaming output).
    public static func strip(from text: String) -> String {
        return text.withCString { cText in
            var outPtr: UnsafePointer<CChar>? = nil
            var outLen: Int                    = 0
            let rc = rac_llm_strip_thinking(cText, &outPtr, &outLen)
            guard rc == RAC_SUCCESS, let p = outPtr else { return text }
            return String(cString: p)
        }
    }
}
