//
//  ThinkingTagPattern.swift
//  RunAnywhere SDK
//
//  Pattern for extracting thinking/reasoning content from model output
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_thinking_tag_pattern_t
//  C++ Source: include/rac/features/llm/rac_llm_types.h
//

import CRACommons
import Foundation

/// Pattern for extracting thinking/reasoning content from model output
public struct ThinkingTagPattern: Codable, Sendable {

    public let openingTag: String
    public let closingTag: String

    public init(openingTag: String, closingTag: String) {
        self.openingTag = openingTag
        self.closingTag = closingTag
    }

    /// Default pattern used by models like DeepSeek and Hermes
    public static let defaultPattern = ThinkingTagPattern(
        openingTag: "<think>",
        closingTag: "</think>"
    )

    /// Alternative pattern with full "thinking" word
    public static let thinkingPattern = ThinkingTagPattern(
        openingTag: "<thinking>",
        closingTag: "</thinking>"
    )

    /// Custom pattern for models that use different tags
    public static func custom(opening: String, closing: String) -> ThinkingTagPattern {
        ThinkingTagPattern(openingTag: opening, closingTag: closing)
    }

    // MARK: - C++ Bridge (rac_thinking_tag_pattern_t)

    /// Execute a closure with the C++ equivalent pattern struct
    /// - Parameter body: Closure that receives pointer to rac_thinking_tag_pattern_t
    /// - Returns: The result of the closure
    public func withCPattern<T>(_ body: (UnsafePointer<rac_thinking_tag_pattern_t>) throws -> T) rethrows -> T {
        return try openingTag.withCString { openingPtr in
            return try closingTag.withCString { closingPtr in
                var cPattern = rac_thinking_tag_pattern_t()
                cPattern.opening_tag = openingPtr
                cPattern.closing_tag = closingPtr
                return try body(&cPattern)
            }
        }
    }

    /// Initialize from C++ rac_thinking_tag_pattern_t
    /// - Parameter cPattern: The C++ pattern struct
    public init(from cPattern: rac_thinking_tag_pattern_t) {
        self.init(
            openingTag: cPattern.opening_tag.map { String(cString: $0) } ?? "<think>",
            closingTag: cPattern.closing_tag.map { String(cString: $0) } ?? "</think>"
        )
    }
}
